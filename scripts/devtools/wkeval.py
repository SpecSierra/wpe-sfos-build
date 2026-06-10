#!/usr/bin/env python3
"""Eval JS against the WPE inspector page target and print the result.

Usage: wkeval.py "<js>"   (default: document.location.href)
"""
import asyncio
import json
import sys

from wkinspector import connect


async def main():
    js = sys.argv[1] if len(sys.argv) > 1 else "document.location.href"
    async with connect() as insp:
        tid, targets = await insp.discover_target()
        if not tid:
            print("no page target; targets=", targets, file=sys.stderr)
            return
        print(f"[target {tid}] targets={targets}", file=sys.stderr)
        inner = await insp.evaluate(js)
        if inner is None:
            print("(timeout waiting for eval reply)", file=sys.stderr)
            return
        print(json.dumps(inner.get("result", inner), indent=2)[:8000])


if __name__ == "__main__":
    asyncio.run(main())
