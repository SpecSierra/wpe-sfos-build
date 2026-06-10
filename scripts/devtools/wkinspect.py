#!/usr/bin/env python3
"""Drive the WPE WebKit remote inspector (Target-wrapped protocol); eval JS.

Usage: wkinspect.py "<js>" [--gesture]   (default: document.readyState)
"""
import asyncio
import json
import sys

from wkinspector import connect


async def main():
    js = sys.argv[1] if len(sys.argv) > 1 else "document.readyState"
    gesture = len(sys.argv) > 2 and sys.argv[2] == "--gesture"
    async with connect() as insp:
        tid, _ = await insp.discover_target()
        if not tid:
            print("no target announced", file=sys.stderr)
            return
        inner = await insp.evaluate(js, user_gesture=gesture, timeout=20)
        if inner is None:
            return
        r = inner.get("result", {}).get("result", inner)
        print(json.dumps(r, indent=2)[:10000])


if __name__ == "__main__":
    asyncio.run(main())
