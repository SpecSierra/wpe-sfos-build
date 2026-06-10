#!/usr/bin/env python3
"""Enable Runtime on the page target, evaluate, and dump ALL frames for a few seconds.

Usage: wkdump.py "<js>"   (default: document.location.href)
"""
import asyncio
import json
import sys

from wkinspector import connect


async def main():
    js = sys.argv[1] if len(sys.argv) > 1 else "document.location.href"
    async with connect() as insp:
        tid, targets = await insp.discover_target()
        print("targets:", targets, "-> using", tid, file=sys.stderr)
        if not tid:
            return
        # resume in case the target is paused-on-start
        await insp.send("Target.resume", {"targetId": tid})
        print("SENT Target.resume", file=sys.stderr)
        await insp.send_to_target("Runtime.enable")
        await insp.send_to_target("Runtime.evaluate",
                                  {"expression": js, "returnByValue": True})
        for _ in range(30):
            m = await insp.recv(3)
            if m is None:
                break
            if m.get("method") == "Target.dispatchMessageFromTarget":
                print("DISPATCH:", m["params"]["message"][:500])
            else:
                print("FRAME:", json.dumps(m)[:500])


if __name__ == "__main__":
    asyncio.run(main())
