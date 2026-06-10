#!/usr/bin/env python3
"""Probe WPE remote inspector: connect, dump initial frames, try direct + wrapped eval.

A low-level diagnostic that works with RAW frames (no JSON decode / no target
discovery), so it deliberately does not use the Inspector helper — it only
shares the connection constants.
"""
import asyncio
import json
import sys

import websockets

from wkinspector import DEFAULT_URL, MAX_SIZE


async def main():
    js = sys.argv[1] if len(sys.argv) > 1 else "document.location.href"
    async with websockets.connect(DEFAULT_URL, max_size=MAX_SIZE) as ws:
        async def recv(t=3):
            try:
                return await asyncio.wait_for(ws.recv(), t)
            except asyncio.TimeoutError:
                return None

        # 1. Drain anything the server pushes on connect
        print("--- initial frames after connect ---")
        for _ in range(10):
            m = await recv(2)
            if m is None:
                break
            print("RECV:", m[:400])

        # 2. Try DIRECT (non-wrapped) protocol
        print("--- direct Runtime.evaluate ---")
        await ws.send(json.dumps({"id": 100, "method": "Runtime.evaluate",
                                  "params": {"expression": js, "returnByValue": True}}))
        for _ in range(6):
            m = await recv(3)
            if m is None:
                print("(no reply to direct)")
                break
            print("RECV:", m[:600])

        # 3. Try Target.exists to provoke announcement
        print("--- Target.exists ---")
        await ws.send(json.dumps({"id": 200, "method": "Target.exists", "params": {}}))
        for _ in range(6):
            m = await recv(3)
            if m is None:
                print("(no reply to Target.exists)")
                break
            print("RECV:", m[:600])


if __name__ == "__main__":
    asyncio.run(main())
