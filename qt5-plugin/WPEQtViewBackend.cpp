/*
 * Copyright (C) 2018, 2019, 2021 Igalia S.L
 * Copyright (C) 2018, 2019 Zodiac Inflight Innovations
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 * Boston, MA 02110-1301, USA.
 */

#include "config.h"
#include "WPEQtViewBackend.h"

#include "WPEQtView.h"
#include <QGuiApplication>
#include <QMetaObject>
#include <QOpenGLFunctions>
#include <QQuickWindow>
#include <QtGlobal>

static PFNGLEGLIMAGETARGETTEXTURE2DOESPROC imageTargetTexture2DOES;

std::unique_ptr<WPEQtViewBackend> WPEQtViewBackend::create(const QSizeF& size, QPointer<QOpenGLContext> context, EGLDisplay eglDisplay, QPointer<WPEQtView> view)
{
    if (!context || !view)
        return nullptr;

    if (eglDisplay == EGL_NO_DISPLAY)
        return nullptr;

    eglInitialize(eglDisplay, nullptr, nullptr);

    if (!eglBindAPI(EGL_OPENGL_ES_API) || !wpe_fdo_initialize_for_egl_display(eglDisplay))
        return nullptr;

    static const EGLint configAttributes[13] = {
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RED_SIZE, 1,
        EGL_GREEN_SIZE, 1,
        EGL_BLUE_SIZE, 1,
        EGL_ALPHA_SIZE, 1,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_NONE
    };

    EGLint count = 0;
    if (!eglGetConfigs(eglDisplay, nullptr, 0, &count) || count < 1)
        return nullptr;

    EGLConfig eglConfig;
    EGLint matched = 0;
    EGLContext eglContext = nullptr;
    if (eglChooseConfig(eglDisplay, configAttributes, &eglConfig, 1, &matched) && !!matched) {
        static const EGLint contextAttributes[3] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
        eglContext = eglCreateContext(eglDisplay, eglConfig, nullptr, contextAttributes);
    }

    if (!eglContext)
        return nullptr;

    return std::make_unique<WPEQtViewBackend>(size, eglDisplay, eglContext, context, view);
}

WPEQtViewBackend::WPEQtViewBackend(const QSizeF& size, EGLDisplay display, EGLContext eglContext, QPointer<QOpenGLContext> context, QPointer<WPEQtView> view)
    : m_eglDisplay(display)
    , m_eglContext(eglContext)
    , m_view(view)
    , m_size(size)
{
    wpe_loader_init("libWPEBackend-fdo-1.0.so.1");

    imageTargetTexture2DOES = reinterpret_cast<PFNGLEGLIMAGETARGETTEXTURE2DOESPROC>(eglGetProcAddress("glEGLImageTargetTexture2DOES"));

    static struct wpe_view_backend_exportable_fdo_egl_client exportableClient = {
        // export_egl_image
        nullptr,
        [](void* data, struct wpe_fdo_egl_exported_image* image)
        {
            static_cast<WPEQtViewBackend*>(data)->displayImage(image);
        },
        // padding
        nullptr, nullptr, nullptr
    };

    m_exportable = wpe_view_backend_exportable_fdo_egl_create(&exportableClient, this, m_size.width(), m_size.height());

    wpe_view_backend_add_activity_state(backend(), wpe_view_activity_state_visible | wpe_view_activity_state_focused | wpe_view_activity_state_in_window);

    // Register the libwpe fullscreen handler.  Without it,
    // wpe_view_backend_platform_set_fullscreen() returns false, which makes
    // WebKit's PageClientImpl::enterFullScreen() immediately call
    // requestExitFullScreen() — DOM fullscreen enters and reverts within
    // ~100 ms (video fullscreen "exits after a second").  The handler accepts
    // the transition and forwards it to the embedding WPEQtView.
    wpe_view_backend_set_fullscreen_handler(backend(), [](void* data, bool enable) -> bool {
        return static_cast<WPEQtViewBackend*>(data)->handleFullscreenChanged(enable);
    }, this);

    m_surface.setFormat(context->format());
    m_surface.create();
}

WPEQtViewBackend::~WPEQtViewBackend()
{
    if (m_exportable && m_pendingImage)
        wpe_view_backend_exportable_fdo_egl_dispatch_release_exported_image(m_exportable, m_pendingImage);
    if (m_exportable && m_committedImage)
        wpe_view_backend_exportable_fdo_egl_dispatch_release_exported_image(m_exportable, m_committedImage);
    m_pendingImage = nullptr;
    m_committedImage = nullptr;
    wpe_view_backend_exportable_fdo_destroy(m_exportable);
    eglDestroyContext(m_eglDisplay, m_eglContext);
}

bool WPEQtViewBackend::handleFullscreenChanged(bool enable)
{
    if (!m_view)
        return false;

    // Forward to the embedding view; the browser UI switches the window state
    // (and injects the JS-side cleanup on leave).  Returning true completes
    // the libwpe handshake so WebKit keeps the DOM fullscreen state.
    m_view->notifyFullscreenRequest(enable);
    return true;
}

void WPEQtViewBackend::resize(const QSizeF& newSize)
{
    if (!newSize.isValid())
        return;

    m_size = newSize;
    wpe_view_backend_dispatch_set_size(backend(), m_size.width(), m_size.height());
}

GLuint WPEQtViewBackend::texture(QOpenGLContext* context)
{
    if ((!m_pendingImage && !m_committedImage) || !hasValidSurface())
        return 0;
    auto* image = m_pendingImage ? m_pendingImage : m_committedImage;

    context->makeCurrent(&m_surface);

    QOpenGLFunctions* glFunctions = context->functions();
    if (!m_textureId) {
        glFunctions->glGenTextures(1, &m_textureId);
        glFunctions->glBindTexture(GL_TEXTURE_2D, m_textureId);
        glFunctions->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glFunctions->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glFunctions->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glFunctions->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glFunctions->glBindTexture(GL_TEXTURE_2D, 0);
    }

    // Bind the WPE-exported frame as an EGLImage directly into m_textureId
    // (zero-copy) and hand that texture straight to Qt. updatePaintNode() wraps
    // m_textureId in a QSGSimpleTextureNode and Qt's scene graph composites the
    // EGLImage itself — so the previous per-frame glClear + full-screen textured
    // quad draw here rendered into a discarded framebuffer and was pure waste:
    // a full-screen clear + full-screen blit every frame on the single-command-
    // queue Adreno 610 (which is why the red clear was never visible). The
    // glTexImage2D(...nullptr) allocation was likewise orphaned immediately by
    // glEGLImageTargetTexture2DOES, which defines the texture's storage. Removed.
    // Producer/consumer sync is handled by the wpe-fdo export/frame-complete
    // handshake (see didRenderFrame), not by this draw.
    glFunctions->glActiveTexture(GL_TEXTURE0);
    glFunctions->glBindTexture(GL_TEXTURE_2D, m_textureId);
    imageTargetTexture2DOES(GL_TEXTURE_2D, wpe_fdo_egl_exported_image_get_egl_image(image));
    glFunctions->glBindTexture(GL_TEXTURE_2D, 0);

    m_frameUpdateRequested = m_pendingImage;

    return m_textureId;
}

void WPEQtViewBackend::didRenderFrame()
{
    if (!m_frameUpdateRequested || !m_exportable)
        return;

    m_frameUpdateRequested = false;
    wpe_view_backend_exportable_fdo_dispatch_frame_complete(m_exportable);
    if (m_committedImage)
        wpe_view_backend_exportable_fdo_egl_dispatch_release_exported_image(m_exportable, m_committedImage);
    m_committedImage = m_pendingImage;
    m_pendingImage = nullptr;
}

void WPEQtViewBackend::displayImage(struct wpe_fdo_egl_exported_image* image)
{
    if (m_pendingImage && m_exportable)
        wpe_view_backend_exportable_fdo_egl_dispatch_release_exported_image(m_exportable, m_pendingImage);

    m_pendingImage = image;
    if (m_view) {
        m_view->triggerUpdate();
        // QQuickItem::update() from triggerUpdate() is not sufficient on hybris
        // EGL: the QSGRenderThread stalls after eglSwapBuffers waiting for
        // QQuickWindow::update() before processing another frame. Without this,
        // subsequent WPE frames are silently dropped until user interaction
        // wakes the Qt render loop externally.
        if (QQuickWindow* w = m_view->window())
            QMetaObject::invokeMethod(w, "update", Qt::QueuedConnection);
        return;
    }

    if (m_exportable)
        wpe_view_backend_exportable_fdo_egl_dispatch_release_exported_image(m_exportable, m_pendingImage);
    m_pendingImage = nullptr;
}

uint32_t WPEQtViewBackend::modifiers() const
{
    uint32_t mask = m_keyboardModifiers;
    if (m_mouseModifiers)
        mask |= m_mouseModifiers;
    return mask;
}

void WPEQtViewBackend::dispatchHoverEnterEvent(QHoverEvent*)
{
    m_hovering = true;
    m_mouseModifiers = 0;
}

void WPEQtViewBackend::dispatchHoverLeaveEvent(QHoverEvent*)
{
    m_hovering = false;
}

void WPEQtViewBackend::dispatchHoverMoveEvent(QHoverEvent* event)
{
    if (!m_hovering)
        return;

    uint32_t state = !!m_mousePressedButton;
    struct wpe_input_pointer_event wpeEvent = { wpe_input_pointer_event_type_motion,
        static_cast<uint32_t>(event->timestamp()),
        event->pos().x(), event->pos().y(),
        m_mousePressedButton, state, modifiers() };
    wpe_view_backend_dispatch_pointer_event(backend(), &wpeEvent);
}

void WPEQtViewBackend::dispatchMousePressEvent(QMouseEvent* event)
{
    uint32_t button = 0;
    uint32_t modifier = 0;
    switch (event->button()) {
    case Qt::LeftButton:
        button = 1;
        modifier = wpe_input_pointer_modifier_button1;
        break;
    case Qt::RightButton:
        button = 2;
        modifier = wpe_input_pointer_modifier_button2;
        break;
    default:
        break;
    }
    m_mousePressedButton = button;
    uint32_t state = 1;
    m_mouseModifiers |= modifier;
    struct wpe_input_pointer_event wpeEvent = { wpe_input_pointer_event_type_button,
        static_cast<uint32_t>(event->timestamp()),
        event->x(), event->y(), button, state, modifiers() };
    wpe_view_backend_dispatch_pointer_event(backend(), &wpeEvent);
}

void WPEQtViewBackend::dispatchMouseReleaseEvent(QMouseEvent* event)
{
    uint32_t button = 0;
    uint32_t modifier = 0;
    switch (event->button()) {
    case Qt::LeftButton:
        button = 1;
        modifier = wpe_input_pointer_modifier_button1;
        break;
    case Qt::RightButton:
        button = 2;
        modifier = wpe_input_pointer_modifier_button2;
        break;
    default:
        break;
    }
    m_mousePressedButton = 0;
    uint32_t state = 0;
    m_mouseModifiers &= ~modifier;
    struct wpe_input_pointer_event wpeEvent = { wpe_input_pointer_event_type_button,
        static_cast<uint32_t>(event->timestamp()),
        event->x(), event->y(), button, state, modifiers() };
    wpe_view_backend_dispatch_pointer_event(backend(), &wpeEvent);
}

#if (QT_VERSION >= QT_VERSION_CHECK(5, 14, 0))
#define QWHEEL_POSITION position()
#else
#define QWHEEL_POSITION posF()
#endif

void WPEQtViewBackend::dispatchWheelEvent(QWheelEvent* event)
{
    QPoint delta = event->angleDelta();
    QPoint numDegrees = delta / 8;
    struct wpe_input_axis_2d_event wpeEvent = {};  // zero both axes + base; only one axis is set below
    if (delta.y() == event->QWHEEL_POSITION.y())
        wpeEvent.x_axis = numDegrees.x();
    else
        wpeEvent.y_axis = numDegrees.y();
    wpeEvent.base.type = static_cast<wpe_input_axis_event_type>(wpe_input_axis_event_type_mask_2d | wpe_input_axis_event_type_motion_smooth);
    wpeEvent.base.x = event->QWHEEL_POSITION.x();
    wpeEvent.base.y = event->QWHEEL_POSITION.y();
    wpe_view_backend_dispatch_axis_event(backend(), &wpeEvent.base);
}

void WPEQtViewBackend::dispatchKeyEvent(QKeyEvent* event, bool state)
{
    uint32_t keysym = event->nativeVirtualKey();
    if (!keysym)
        keysym = wpe_input_xkb_context_get_key_code(wpe_input_xkb_context_get_default(), event->key(), state);

    uint32_t modifiers = 0;
    Qt::KeyboardModifiers qtModifiers = event->modifiers();
    if (!qtModifiers)
        qtModifiers = QGuiApplication::keyboardModifiers();

    if (qtModifiers & Qt::ShiftModifier)
        modifiers |= wpe_input_keyboard_modifier_shift;

    if (qtModifiers & Qt::ControlModifier)
        modifiers |= wpe_input_keyboard_modifier_control;
    if (qtModifiers & Qt::MetaModifier)
        modifiers |= wpe_input_keyboard_modifier_meta;
    if (qtModifiers & Qt::AltModifier)
        modifiers |= wpe_input_keyboard_modifier_alt;

    struct wpe_input_keyboard_event wpeEvent = { static_cast<uint32_t>(event->timestamp()),
        keysym, event->nativeScanCode(), state, modifiers };
    wpe_view_backend_dispatch_keyboard_event(backend(), &wpeEvent);
}

void WPEQtViewBackend::dispatchTouchEvent(QTouchEvent* event)
{
    wpe_input_touch_event_type eventType;
    switch (event->type()) {
    case QEvent::TouchBegin:
        eventType = wpe_input_touch_event_type_down;
        break;
    case QEvent::TouchUpdate:
        eventType = wpe_input_touch_event_type_motion;
        break;
    case QEvent::TouchEnd:
        eventType = wpe_input_touch_event_type_up;
        break;
    default:
        eventType = wpe_input_touch_event_type_null;
        break;
    }

    // No touch points means g_new0(..., 0) returns NULL; dispatching would then
    // read rawEvents[0].id off a null pointer. Nothing to deliver, so bail out.
    if (event->touchPoints().isEmpty())
        return;

    int i = 0;
    struct wpe_input_touch_event_raw* rawEvents = g_new0(wpe_input_touch_event_raw, event->touchPoints().length());
    for (auto& point : event->touchPoints()) {
        rawEvents[i] = { eventType, static_cast<uint32_t>(event->timestamp()),
            point.id(), static_cast<int32_t>(point.pos().x()), static_cast<int32_t>(point.pos().y()) };
        i++;
    }

    struct wpe_input_touch_event wpeEvent = { rawEvents, static_cast<uint64_t>(i), eventType,
        static_cast<int32_t>(rawEvents[0].id),
        static_cast<uint32_t>(event->timestamp()), modifiers() };
    wpe_view_backend_dispatch_touch_event(backend(), &wpeEvent);
    g_free(rawEvents);
}
