#!/bin/bash
set -euo pipefail

LOCAL_PORT="${LOCAL_PORT:-8000}"
REMOTE_PORT="${REMOTE_PORT:-8000}"
PHONE_USER="${PHONE_USER:-defaultuser}"
PHONE_HOST="${PHONE_HOST:-localhost}"
PHONE_SSH_PORT="${PHONE_SSH_PORT:-2222}"
PHONE_PASSWORD="${PHONE_PASSWORD:-root}"

echo "Opening reverse tunnel so phone localhost:${REMOTE_PORT} forwards to host localhost:${LOCAL_PORT}"

exec sshpass -p "${PHONE_PASSWORD}" \
    ssh -N \
    -R "127.0.0.1:${REMOTE_PORT}:127.0.0.1:${LOCAL_PORT}" \
    -o ExitOnForwardFailure=yes \
    -o StrictHostKeyChecking=no \
    -p "${PHONE_SSH_PORT}" \
    "${PHONE_USER}@${PHONE_HOST}"
