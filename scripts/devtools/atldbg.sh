#!/usr/bin/env bash
# atldbg launcher — runs the atldbg package with the devtools dir on PYTHONPATH
# so it can import both the package and the sibling wkinspector.py client.
here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
export PYTHONPATH="$here${PYTHONPATH:+:$PYTHONPATH}"
exec python3 -m atldbg "$@"
