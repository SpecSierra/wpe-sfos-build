#!/usr/bin/env python3
"""Dump buffered console messages from the WPE remote inspector."""
import asyncio
import json
import sys

from wkinspector import connect


async def main():
    async with connect() as insp:
        tid, _ = await insp.discover_target()
        if not tid:
            print("no target announced", file=sys.stderr)
            return
        await insp.send_to_target("Console.enable")
        msgs = []
        while True:
            m = await insp.recv(5)
            if m is None:
                break
            if m.get("method") == "Target.dispatchMessageFromTarget":
                inner = json.loads(m["params"]["message"])
                if inner.get("method") == "Console.messageAdded":
                    msgs.append(inner["params"]["message"])
        for msg in msgs:
            line = f"[{msg.get('level')}] {msg.get('text', '')[:300]}"
            src = msg.get('url', '')
            if src:
                line += f"  ({src.split('/')[-1][:60]}:{msg.get('line')})"
            print(line)
        print(f"--- {len(msgs)} messages", file=sys.stderr)


if __name__ == "__main__":
    asyncio.run(main())
