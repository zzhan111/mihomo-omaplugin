#!/usr/bin/env python3
"""Run bin/mihomo-watch against a mock controller and check node derivation."""

import json
import os
import queue
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

PHASES = [
    ("rule", "Enet-FB", "Enet-FB"),
    ("rule", "hy2-154", "Enet-FB"),
    ("global", "hy2-154", "DIRECT"),
    ("global", "Enet-FB", "hy2-154"),
    ("direct", "hy2-154", "Enet-FB"),
]
EXPECTED_NODES = ["Enet-FB", "hy2-154", "DIRECT", "hy2-154", "DIRECT"]
REQUIRED_KEYS = {
    "ok",
    "mode",
    "node",
    "up",
    "down",
    "upTotal",
    "downTotal",
    "conns",
    "ts",
}


class State:
    def __init__(self):
        self.lock = threading.Lock()
        self.next_index = 0
        self.phase = PHASES[0]

    def begin_sample(self):
        with self.lock:
            index = self.next_index
            self.phase = PHASES[min(index, len(PHASES) - 1)]
            self.next_index = min(index + 1, len(PHASES) + 1)
            return index

    def current(self):
        with self.lock:
            return self.phase


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        path = urlsplit(self.path).path
        state = self.server.state
        if path == "/connections":
            index = state.begin_sample()
            payload = {
                "uploadTotal": 1000 + index * 1000,
                "downloadTotal": 2000 + index * 2000,
                "connections": None if index == 0 else [],
            }
            if index == len(PHASES):
                del payload["connections"]
            elif index > len(PHASES):
                payload["connections"] = False
        elif path == "/configs":
            payload = {"mode": state.current()[0]}
        elif path == "/proxies":
            _, rocket, global_node = state.current()
            payload = {
                "proxies": {
                    "\U0001f680 \u8282\u70b9\u9009\u62e9": {
                        "type": "Selector",
                        "now": rocket,
                    },
                    "GLOBAL": {"type": "Selector", "now": global_node},
                }
            }
        else:
            self.send_error(404)
            return

        body = json.dumps(payload).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def read_samples(proc, count, timeout):
    lines = queue.Queue()

    def pump():
        for line in proc.stdout:
            lines.put(line)

    reader = threading.Thread(target=pump, daemon=True)
    reader.start()
    samples = []
    deadline = time.monotonic() + timeout
    while len(samples) < count:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        try:
            line = lines.get(timeout=remaining)
        except queue.Empty:
            break
        if line == "":
            break
        try:
            samples.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return samples


def main():
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.daemon_threads = True
    server.state = State()
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    env = os.environ.copy()
    env["MIHOMO_API"] = "http://127.0.0.1:%d" % server.server_port
    env.pop("MIHOMO_SECRET", None)
    watcher = Path(__file__).resolve().parent.parent / "bin" / "mihomo-watch"
    proc = subprocess.Popen(
        [str(watcher), "--interval", "1"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )

    try:
        samples = read_samples(proc, len(EXPECTED_NODES) + 2, timeout=20)
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        errors = proc.stderr.read()
        server.shutdown()
        server.server_close()

    failures = []
    if len(samples) != len(EXPECTED_NODES) + 2:
        failures.append(
            "expected %d samples, got %d; stderr=%r"
            % (len(EXPECTED_NODES) + 2, len(samples), errors[-2000:])
        )
    for index, sample in enumerate(samples):
        if index >= len(EXPECTED_NODES):
            print("sample %d: invalid connections => %r" % (index + 1, sample))
            if sample.get("ok") is not False or sample.get("error") != "connections response missing or invalid fields":
                failures.append("sample %d should reject invalid connections" % (index + 1))
            continue
        mode = PHASES[index][0]
        expected = EXPECTED_NODES[index]
        actual = sample.get("node")
        line = "sample %d: mode=%r node=%r expected node=%r" % (
            index + 1,
            sample.get("mode"),
            actual,
            expected,
        )
        print(line)
        if sample.get("ok") is not True:
            failures.append("sample %d is not ok: %r" % (index + 1, sample))
        if sample.get("conns") != 0:
            failures.append("sample %d expected 0 connections" % (index + 1))
        missing = REQUIRED_KEYS - set(sample)
        if missing:
            failures.append("sample %d missing keys: %s" % (index + 1, sorted(missing)))
        if sample.get("mode") != mode:
            failures.append("sample %d mode expected %r" % (index + 1, mode))
        if actual != expected:
            failures.append("sample %d node expected %r, got %r" % (index + 1, expected, actual))

    if failures:
        print("FAIL")
        for failure in failures:
            print("- " + failure)
        raise SystemExit(1)

    print("PASS: null and empty arrays accepted; missing and invalid connections rejected")


if __name__ == "__main__":
    main()
