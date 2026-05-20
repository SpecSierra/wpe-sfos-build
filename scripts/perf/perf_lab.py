#!/usr/bin/env python3
import argparse
import json
import os
import re
import socketserver
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler
from pathlib import Path


def sanitize_fragment(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", value).strip("-")
    return cleaned or "run"


class PerfLabHandler(SimpleHTTPRequestHandler):
    server_version = "AtlanticPerfLab/1.0"

    def __init__(self, *args, directory=None, results_dir=None, **kwargs):
        self.results_dir = Path(results_dir)
        super().__init__(*args, directory=directory, **kwargs)

    def log_message(self, fmt, *args):
        timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        print(f"[{timestamp}] {self.address_string()} {fmt % args}")

    def do_POST(self):
        if self.path != "/report":
            self.send_error(HTTPStatus.NOT_FOUND, "Unknown endpoint")
            return

        length_header = self.headers.get("Content-Length")
        if not length_header:
            self.send_error(HTTPStatus.LENGTH_REQUIRED, "Missing Content-Length")
            return

        try:
            payload = self.rfile.read(int(length_header))
            report = json.loads(payload.decode("utf-8"))
        except (ValueError, json.JSONDecodeError) as error:
            self.send_error(HTTPStatus.BAD_REQUEST, f"Invalid JSON payload: {error}")
            return

        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        run_id = sanitize_fragment(str(report.get("runId", "run")))
        output_path = self.results_dir / f"{timestamp}-{run_id}.json"
        report["_serverReceivedAt"] = datetime.now(timezone.utc).isoformat()
        output_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")

        response = {
            "saved": True,
            "path": str(output_path),
            "runId": report.get("runId"),
        }
        encoded = json.dumps(response).encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


def parse_args():
    parser = argparse.ArgumentParser(description="Serve Atlantic browser performance probe pages and collect JSON reports.")
    parser.add_argument("--bind", default="0.0.0.0", help="Address to bind to. Default: 0.0.0.0")
    parser.add_argument("--port", type=int, default=8000, help="Port to listen on. Default: 8000")
    parser.add_argument(
        "--static-dir",
        default=str(Path(__file__).resolve().parent / "static"),
        help="Directory containing static probe pages.",
    )
    parser.add_argument(
        "--results-dir",
        default=str(Path(__file__).resolve().parent / "results"),
        help="Directory where JSON result reports will be stored.",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    static_dir = Path(args.static_dir).resolve()
    results_dir = Path(args.results_dir).resolve()
    results_dir.mkdir(parents=True, exist_ok=True)

    handler = lambda *handler_args, **handler_kwargs: PerfLabHandler(  # noqa: E731
        *handler_args,
        directory=str(static_dir),
        results_dir=str(results_dir),
        **handler_kwargs,
    )

    class ThreadingTCPServer(socketserver.ThreadingTCPServer):
        allow_reuse_address = True

    with ThreadingTCPServer((args.bind, args.port), handler) as httpd:
        print(f"Serving Atlantic perf lab from {static_dir}")
        print(f"Saving reports to {results_dir}")
        print(f"Listening on http://{args.bind}:{args.port}")
        httpd.serve_forever()


if __name__ == "__main__":
    main()
