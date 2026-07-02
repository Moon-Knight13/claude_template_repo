#!/usr/bin/env python3
"""Mock Ollama server for delegation-ladder tests (scripts/tests/test-delegation.sh).

Behavior is selected with MOCK_MODE:
  success    - healthy probe, sensible generation output
  missing    - /api/tags lists no models
  lowtps     - eval stats report ~2 tokens/sec (below LOCAL_MODEL_MIN_TPS)
  slowgen    - health probe is fast, real generation hangs 10s (forces timeout)
  empty      - generation returns whitespace only
  degenerate - generation returns one phrase repeated (junk detector food)

Other knobs: MOCK_MODEL (name in /api/tags), MOCK_CTX (context_length), MOCK_PORT.
"""
import json
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MODE = os.environ.get("MOCK_MODE", "success")
MODEL = os.environ.get("MOCK_MODEL", "qwen2.5-coder:7b")
CTX = int(os.environ.get("MOCK_CTX", "32768"))
PORT = int(os.environ.get("MOCK_PORT", "18434"))

GENERATION_TEXT = {
    "success": "def add(a, b):\n    return a + b\n",
    "empty": "   \n\t  ",
    "degenerate": "foo bar " * 120,
}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except BrokenPipeError:
            pass  # client (curl --max-time) gave up; expected in timeout tests

    def do_GET(self):
        if self.path == "/api/tags":
            models = [] if MODE == "missing" else [{"name": MODEL}]
            self._send({"models": models})
        else:
            self._send({"status": "ok"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        req = json.loads(self.rfile.read(length) or b"{}")

        if self.path == "/api/show":
            self._send({"model_info": {"qwen2.context_length": CTX}})
            return

        if self.path == "/api/generate":
            # delegate-local.sh's health probe uses num_predict=16; real work uses more.
            is_probe = req.get("options", {}).get("num_predict") == 16
            if MODE == "slowgen" and not is_probe:
                time.sleep(10)
            if MODE == "lowtps":
                stats = {"eval_count": 2, "eval_duration": 1_000_000_000}   # 2 tps
            else:
                stats = {"eval_count": 100, "eval_duration": 2_000_000_000}  # 50 tps
            text = GENERATION_TEXT.get(MODE, "ready")
            self._send({"response": text, **stats})
            return

        self._send({"error": "not found"}, 404)


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
