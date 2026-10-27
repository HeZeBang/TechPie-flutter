#!/usr/bin/env python3
"""Loopback-only SSE fixture. Uses synthetic data and never contacts campus APIs."""

import argparse
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote


class Fixture(BaseHTTPRequestHandler):
    releases = {}
    lock = threading.Lock()

    def log_message(self, *_):
        pass

    def respond(self, status, content_type):
        self.send_response(status)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, X-Access-Token, tenant-id")
        self.send_header("Content-Type", content_type)
        self.end_headers()

    def do_OPTIONS(self):
        self.respond(204, "text/plain")

    def do_GET(self):
        if not self.path.startswith("/release/"):
            self.respond(404, "text/plain")
            return
        group = unquote(self.path.removeprefix("/release/"))
        with self.lock:
            release = self.releases.get(group)
        if release is not None:
            release.set()
        self.respond(200, "application/json")
        self.wfile.write(b'{"ok":true}')

    def do_POST(self):
        if self.path != "/htk/chat/start/chat":
            self.respond(404, "text/plain")
            return
        if self.headers.get("X-Access-Token") != "synthetic-browser-token":
            self.respond(401, "application/json")
            return
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
        group = body["chatGroupId"]
        release = threading.Event()
        with self.lock:
            self.releases[group] = release
        try:
            self.respond(200, "text/event-stream; charset=utf-8")
            self.wfile.write(('data: ' + json.dumps({"choices": [{"index": 0, "delta": {"content": "你好"}}]}, ensure_ascii=False) + '\n\n').encode())
            self.wfile.flush()
            if release.wait(15):
                self.wfile.write(b'data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}\n\n')
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            with self.lock:
                self.releases.pop(group, None)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=18765)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Fixture)
    server.daemon_threads = True
    print(f"http://127.0.0.1:{server.server_port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
