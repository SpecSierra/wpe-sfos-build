#!/usr/bin/env python3
"""Convert ABP/EasyList filter lists to WebKit Content Blocker JSON format.

Usage:
  python3 easylist-to-webkit.py input.txt > output.json
  python3 easylist-to-webkit.py --url https://easylist.to/easylist/easylist.txt > output.json
  python3 easylist-to-webkit.py --default > output.json  (generates built-in rules)
"""

import sys
import json
import re
import argparse

# Top ad/tracking domains to block
BLOCK_DOMAINS = [
    "doubleclick.net", "googlesyndication.com", "googleadservices.com",
    "google-analytics.com", "googletagmanager.com", "googletagservices.com",
    "adservice.google.com", "pagead2.googlesyndication.com",
    "facebook.com/tr", "connect.facebook.net/en_US/fbevents.js",
    "analytics.facebook.com",
    "ads.yahoo.com", "adtech.de", "advertising.com",
    "adnxs.com", "adsrvr.org", "adform.net", "adcolony.com",
    "amazon-adsystem.com", "aax.amazon-adsystem.com",
    "ad.doubleclick.net", "stats.g.doubleclick.net",
    "securepubads.g.doubleclick.net",
    "tpc.googlesyndication.com",
    "outbrain.com", "taboola.com", "mgid.com", "revcontent.com",
    "criteo.com", "criteo.net",
    "rubiconproject.com", "pubmatic.com", "openx.net",
    "casalemedia.com", "indexww.com", "bidswitch.net",
    "sharethrough.com", "triplelift.com", "33across.com",
    "moatads.com", "doubleverify.com", "adsafeprotected.com",
    "serving-sys.com", "sizmek.com", "flashtalking.com",
    "eyeota.net", "bluekai.com", "krxd.net", "exelator.com",
    "demdex.net", "omtrdc.net", "sc-static.net",
    "quantserve.com", "scorecardresearch.com",
    "hotjar.com", "mouseflow.com", "crazyegg.com",
    "mixpanel.com", "amplitude.com", "segment.com",
    "optimizely.com", "adobedtm.com",
    "newrelic.com", "nr-data.net",
    "chartbeat.com", "parsely.com",
    "adroll.com", "perfectaudience.com",
    "mathtag.com", "mookie1.com", "rlcdn.com",
    "turn.com", "bidgear.com",
    "popads.net", "popcash.net", "propellerads.com",
    "exoclick.com", "juicyads.com", "trafficjunky.com",
    "revenuehits.com", "hilltopads.net",
    "smartadserver.com", "yieldmo.com",
    "teads.tv", "ligatus.com", "plista.com",
    "zedo.com", "conversantmedia.com",
    "bounceexchange.com", "bouncex.net",
    "tapad.com", "liadm.com", "intentiq.com",
    "id5-sync.com", "uidapi.com",
    "ads-twitter.com", "ads.linkedin.com",
    "adsymptotic.com", "adlightning.com",
]

# URL patterns that indicate ads
BLOCK_URL_PATTERNS = [
    "/ads/", "/ad/banner", "/ad/popup",
    "/adserv", "/adserver", "/adframe",
    "/adclick", "/adview", "/advert",
    "doubleclick\\.net", "googlesyndication\\.com",
    "/pagead/", "/aclk\\?",
    "amazon-adsystem\\.com",
    "/beacon\\?", "/pixel\\?", "/track\\?",
    "/analytics\\.js", "/ga\\.js",
    "facebook\\.com/tr",
    "/prebid", "bidswitch\\.net",
    "cdn\\.taboola\\.com", "cdn\\.outbrain\\.com",
]

# CSS selectors for common ad elements  
CSS_HIDE_SELECTORS = [
    "[id^='google_ads']",
    "[id^='div-gpt-ad']",
    ".adsbygoogle",
    "[data-ad-slot]",
    "[data-ad-client]",
    "ins.adsbygoogle",
    ".ad-container",
    ".ad-wrapper",
    ".ad-banner",
    ".ad-leaderboard",
    "#ad-header",
    "#ad-footer",
    ".sponsored-content",
    ".taboola-container",
    ".outbrain-widget",
    "[id*='taboola']",
    "[class*='taboola']",
    "[id*='outbrain']",
    "[class*='outbrain']",
]


def generate_default_rules():
    """Generate a comprehensive default content blocker rule set."""
    rules = []

    # Block ad domains
    for domain in BLOCK_DOMAINS:
        escaped = domain.replace(".", "\\.")
        rules.append({
            "trigger": {"url-filter": escaped},
            "action": {"type": "block"}
        })

    # Block common ad URL patterns (third-party only)
    for pattern in BLOCK_URL_PATTERNS:
        rules.append({
            "trigger": {
                "url-filter": pattern,
                "load-type": ["third-party"]
            },
            "action": {"type": "block"}
        })

    # CSS element hiding
    for selector in CSS_HIDE_SELECTORS:
        rules.append({
            "trigger": {"url-filter": ".*"},
            "action": {"type": "css-display-none", "selector": selector}
        })

    return rules


def convert_abp_line(line):
    """Convert a single ABP filter line to WebKit content blocker rule(s)."""
    line = line.strip()
    if not line or line.startswith('!') or line.startswith('['):
        return None

    # Element hiding rules: domain##selector
    if '##' in line:
        parts = line.split('##', 1)
        selector = parts[1]
        if not selector or selector.startswith('+') or selector.startswith('?'):
            return None
        trigger = {"url-filter": ".*"}
        if parts[0]:
            domains = [d for d in parts[0].split(',') if not d.startswith('~')]
            if domains:
                trigger["if-domain"] = ["*" + d if not d.startswith('*') else d for d in domains]
        return {
            "trigger": trigger,
            "action": {"type": "css-display-none", "selector": selector}
        }

    # Exception rules (whitelist): @@
    is_exception = False
    if line.startswith('@@'):
        is_exception = True
        line = line[2:]

    # Parse options after $
    options = {}
    if '$' in line:
        parts = line.rsplit('$', 1)
        line = parts[0]
        for opt in parts[1].split(','):
            if '=' in opt:
                k, v = opt.split('=', 1)
                options[k] = v
            else:
                options[opt] = True

    # Convert filter pattern to regex
    pattern = line
    # Handle anchors
    pattern = pattern.replace('||', '^[^:]+:(//)?([^/]+\\.)?')
    pattern = pattern.replace('|', '')
    # Handle wildcards
    pattern = pattern.replace('*', '.*')
    # Handle separator
    pattern = pattern.replace('^', '[/:?&=]')
    # Escape dots (but not already escaped ones or .* )
    pattern = re.sub(r'(?<!\.)\.(?!\*)', '\\.', pattern)

    if not pattern or pattern == '.*':
        return None

    trigger = {"url-filter": pattern}

    # Map resource types
    type_map = {
        "script": "script", "image": "image", "stylesheet": "style-sheet",
        "font": "font", "xmlhttprequest": "raw", "subdocument": "document",
        "media": "media", "popup": "popup", "document": "document",
    }
    resource_types = []
    for opt, val in options.items():
        if opt in type_map:
            resource_types.append(type_map[opt])
    if resource_types:
        trigger["resource-type"] = resource_types

    if options.get("third-party"):
        trigger["load-type"] = ["third-party"]
    elif options.get("first-party") or options.get("~third-party"):
        trigger["load-type"] = ["first-party"]

    if "domain" in options:
        domains = options["domain"].split('|')
        if_domains = [("*" + d if not d.startswith('*') else d) for d in domains if not d.startswith('~')]
        unless_domains = [("*" + d[1:] if not d[1:].startswith('*') else d[1:]) for d in domains if d.startswith('~')]
        if if_domains:
            trigger["if-domain"] = if_domains
        if unless_domains:
            trigger["unless-domain"] = unless_domains

    action_type = "ignore-previous-rules" if is_exception else "block"

    return {"trigger": trigger, "action": {"type": action_type}}


def convert_abp_list(text, max_rules=50000):
    """Convert ABP filter list text to WebKit content blocker rules."""
    rules = []
    for line in text.split('\n'):
        try:
            rule = convert_abp_line(line)
            if rule:
                rules.append(rule)
                if len(rules) >= max_rules:
                    break
        except Exception:
            continue
    return rules


def main():
    parser = argparse.ArgumentParser(description='Convert ABP filters to WebKit Content Blocker JSON')
    parser.add_argument('input', nargs='?', help='Input ABP filter list file')
    parser.add_argument('--url', help='URL to download filter list from')
    parser.add_argument('--default', action='store_true', help='Generate built-in default rules')
    parser.add_argument('--max-rules', type=int, default=50000, help='Maximum number of rules')
    parser.add_argument('-o', '--output', help='Output file (default: stdout)')
    args = parser.parse_args()

    if args.default:
        rules = generate_default_rules()
    elif args.url:
        import urllib.request
        resp = urllib.request.urlopen(args.url)
        text = resp.read().decode('utf-8', errors='ignore')
        rules = convert_abp_list(text, args.max_rules)
    elif args.input:
        with open(args.input) as f:
            text = f.read()
        rules = convert_abp_list(text, args.max_rules)
    else:
        parser.print_help()
        sys.exit(1)

    output = json.dumps(rules, indent=2)
    if args.output:
        with open(args.output, 'w') as f:
            f.write(output)
        print(f"Wrote {len(rules)} rules to {args.output}", file=sys.stderr)
    else:
        print(output)
        print(f"Generated {len(rules)} rules", file=sys.stderr)


if __name__ == '__main__':
    main()
