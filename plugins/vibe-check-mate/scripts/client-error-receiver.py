#!/usr/bin/env python3
"""vibe-check-mate client error receiver.

Listens on localhost for POSTed browser errors from client-error-reporter.js
and appends them to .check-runtime/runtime.log so the runtime evidence
watcher and runtime-auto-fix skill can treat them identically to server
errors.

Env:
  VIBE_LOG_FILE              log file path (default: .check-runtime/runtime.log)
  VIBE_CLIENT_ERROR_PORT     listener port (default: 9876)
"""

from __future__ import annotations
import http.server
import json
import os
import sys

LOG_FILE = os.environ.get("VIBE_LOG_FILE", ".check-runtime/runtime.log")
PORT = int(os.environ.get("VIBE_CLIENT_ERROR_PORT", "9876"))


class Handler(http.server.BaseHTTPRequestHandler):
    def _cors(self) -> None:
        # sendBeacon includes credentials by default; wildcard ACAO is rejected
        # when the request is credentialed. Echo the request Origin instead.
        origin = self.headers.get("Origin", "http://localhost")
        self.send_header("Access-Control-Allow-Origin", origin)
        self.send_header("Access-Control-Allow-Credentials", "true")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Max-Age", "86400")
        self.send_header("Vary", "Origin")

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_POST(self) -> None:  # noqa: N802
        length = int(self.headers.get("Content-Length", "0"))
        data = self.rfile.read(length)
        try:
            payload = json.loads(data.decode("utf-8", errors="replace"))
            kind = payload.get("kind", "error")
            msg = (payload.get("message") or "").replace("\n", " ")
            file_ = payload.get("file") or "unknown"
            line = payload.get("line") or "?"
            col = payload.get("col") or "?"
            stack = (payload.get("stack") or "").replace("\n", " / ")
            url = payload.get("url") or ""
            network = payload.get("network") or {}

            with open(LOG_FILE, "a", encoding="utf-8") as f:
                if kind in {"network", "network-error"}:
                    method = network.get("method") or "?"
                    status = network.get("status")
                    duration = network.get("duration_ms")
                    request_url = network.get("url") or ""
                    transport = network.get("transport") or "?"
                    failed = network.get("failed") or False
                    request_body = json.dumps(
                        network.get("request_body"), ensure_ascii=False, sort_keys=True
                    )
                    request_headers = json.dumps(
                        network.get("request_headers") or {},
                        ensure_ascii=False,
                        sort_keys=True,
                    )
                    f.write(
                        f"[CLIENT_NETWORK] transport={transport} failed={failed} method={method} "
                        f"status={status} duration_ms={duration} url={request_url} page={url}\n"
                    )
                    f.write(f"[CLIENT_NETWORK_HEADERS] {request_headers}\n")
                    f.write(f"[CLIENT_NETWORK_BODY] {request_body}\n")
                    message = network.get("message")
                    if message:
                        f.write(f"[CLIENT_NETWORK_MESSAGE] {message}\n")
                else:
                    f.write(
                        f"[CLIENT_ERROR] kind={kind} msg={msg} at {file_}:{line}:{col} url={url}\n"
                    )
                    if stack:
                        f.write(f"[CLIENT_STACK] {stack}\n")
        except Exception:
            pass

        self.send_response(204)
        self._cors()
        self.end_headers()

    def log_message(self, *_args) -> None:
        return


def main() -> int:
    try:
        server = http.server.HTTPServer(("127.0.0.1", PORT), Handler)
    except OSError:
        return 0
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
