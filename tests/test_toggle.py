#!/usr/bin/env python3
"""Run the real bin/mihomo-toggle against a mock controller."""

import json
import os
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROCKET = "\U0001f680 \u8282\u70b9\u9009\u62e9"
GLOBAL = "GLOBAL"
TOGGLER = Path(__file__).resolve().parent.parent / "bin" / "mihomo-toggle"


class State:
    def __init__(self):
        self.lock = threading.Lock()
        self.mode = "rule"
        self.selectors = {ROCKET: "Enet-FB", GLOBAL: "hy2-154"}
        self.reject = None
        self.requests = []

    def reset(self, mode, rocket, global_node, reject=None):
        with self.lock:
            self.mode = mode
            self.selectors = {ROCKET: rocket, GLOBAL: global_node}
            self.reject = reject
            self.requests = []

    def drop_selector(self, name):
        with self.lock:
            self.selectors.pop(name, None)

    def record(self, method, path, body):
        with self.lock:
            self.requests.append((method, path, body))

    def snapshot(self):
        with self.lock:
            return {
                "mode": self.mode,
                "selectors": dict(self.selectors),
                "requests": list(self.requests),
                "reject": self.reject,
            }


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def send_json(self, status, payload=None):
        body = b"" if payload is None else json.dumps(payload).encode("utf-8")
        self.send_response(status)
        if payload is not None:
            self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def read_mutation(self, method):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        body = json.loads(raw) if raw else None
        path = unquote(urlsplit(self.path).path)
        self.server.state.record(method, path, body)
        return path, body

    def do_GET(self):
        path = urlsplit(self.path).path
        state = self.server.state
        if path == "/configs":
            self.send_json(200, {"mode": state.snapshot()["mode"]})
            return
        if path == "/proxies":
            proxies = {
                name: {"type": "Selector", "now": now}
                for name, now in state.snapshot()["selectors"].items()
            }
            self.send_json(200, {"proxies": proxies})
            return
        self.send_json(404, {"error": "not found"})

    def do_PUT(self):
        path, body = self.read_mutation("PUT")
        state = self.server.state
        snapshot = state.snapshot()
        reject = snapshot["reject"]
        if reject and reject[0] == "PUT" and reject[1] == path:
            self.send_json(reject[2], {"error": "rejected"})
            return
        group = path.removeprefix("/proxies/")
        if group not in snapshot["selectors"] or not isinstance(body, dict):
            self.send_json(404, {"error": "unknown group"})
            return
        with state.lock:
            state.selectors[group] = body.get("name", "")
        self.send_json(204)

    def do_PATCH(self):
        path, body = self.read_mutation("PATCH")
        state = self.server.state
        snapshot = state.snapshot()
        reject = snapshot["reject"]
        if reject and reject[0] == "PATCH" and reject[1] == path:
            self.send_json(reject[2], {"error": "rejected"})
            return
        if path != "/configs" or not isinstance(body, dict):
            self.send_json(404, {"error": "not found"})
            return
        mode = body.get("mode")
        if mode not in ("rule", "global", "direct"):
            self.send_json(400, {"error": "bad mode"})
            return
        with state.lock:
            state.mode = mode
        self.send_json(204)


def run_toggle(api, args):
    env = os.environ.copy()
    env["MIHOMO_API"] = api
    env.pop("MIHOMO_SECRET", None)
    return subprocess.run(
        [str(TOGGLER), *args],
        capture_output=True,
        text=True,
        timeout=10,
        env=env,
    )


def payload_of(result):
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return None


def main():
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.daemon_threads = True
    server.state = State()
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    api = "http://127.0.0.1:%d" % server.server_port
    failures = []

    def check(name, condition, detail):
        if condition:
            print("ok   " + name)
        else:
            print("FAIL " + name + ": " + detail)
            failures.append(name + ": " + detail)

    try:
        server.state.reset("global", rocket="hy2-154", global_node="hy2-154")
        result = run_toggle(api, ["node"])
        payload = payload_of(result)
        snapshot = server.state.snapshot()
        check(
            "global/node switches GLOBAL",
            result.returncode == 0
            and payload is not None
            and payload.get("ok") is True
            and payload.get("group") == GLOBAL
            and payload.get("from") == "hy2-154"
            and payload.get("to") == "Enet-FB"
            and snapshot["requests"] == [("PUT", "/proxies/GLOBAL", {"name": "Enet-FB"})]
            and snapshot["selectors"][GLOBAL] == "Enet-FB"
            and snapshot["selectors"][ROCKET] == "hy2-154",
            "rc=%r stdout=%r stderr=%r state=%r"
            % (result.returncode, result.stdout, result.stderr, snapshot),
        )

        server.state.reset("rule", rocket="Enet-FB", global_node="Enet-FB")
        result = run_toggle(api, ["node"])
        payload = payload_of(result)
        snapshot = server.state.snapshot()
        check(
            "rule/node switches rocket group",
            result.returncode == 0
            and payload is not None
            and payload.get("ok") is True
            and payload.get("group") == ROCKET
            and payload.get("from") == "Enet-FB"
            and payload.get("to") == "hy2-154"
            and snapshot["requests"] == [("PUT", "/proxies/" + ROCKET, {"name": "hy2-154"})]
            and snapshot["selectors"][ROCKET] == "hy2-154"
            and snapshot["selectors"][GLOBAL] == "Enet-FB",
            "rc=%r stdout=%r stderr=%r state=%r"
            % (result.returncode, result.stdout, result.stderr, snapshot),
        )

        server.state.reset("direct", rocket="Enet-FB", global_node="hy2-154")
        before = server.state.snapshot()
        result = run_toggle(api, ["node"])
        payload = payload_of(result)
        after = server.state.snapshot()
        check(
            "direct/node refuses without mutation",
            result.returncode == 1
            and payload is not None
            and payload.get("ok") is False
            and "direct" in payload.get("error", "")
            and before["selectors"] == after["selectors"]
            and after["requests"] == [],
            "rc=%r stdout=%r stderr=%r state=%r"
            % (result.returncode, result.stdout, result.stderr, after),
        )

        server.state.reset("rule", rocket="Enet-FB", global_node="hy2-154")
        server.state.drop_selector(ROCKET)
        result = run_toggle(api, ["node"])
        payload = payload_of(result)
        snapshot = server.state.snapshot()
        check(
            "rule/node reports missing rocket group",
            result.returncode == 1
            and payload is not None
            and payload.get("ok") is False
            and ROCKET in payload.get("error", "")
            and snapshot["requests"] == [],
            "rc=%r stdout=%r stderr=%r state=%r"
            % (result.returncode, result.stdout, result.stderr, snapshot),
        )

        server.state.reset(
            "global",
            rocket="hy2-154",
            global_node="hy2-154",
            reject=("PUT", "/proxies/GLOBAL", 400),
        )
        before = server.state.snapshot()
        result = run_toggle(api, ["node"])
        payload = payload_of(result)
        after = server.state.snapshot()
        check(
            "node API rejection is an error",
            result.returncode == 1
            and payload is not None
            and payload.get("ok") is False
            and "400" in payload.get("error", "")
            and before["selectors"] == after["selectors"]
            and after["requests"] == [("PUT", "/proxies/GLOBAL", {"name": "Enet-FB"})],
            "rc=%r stdout=%r stderr=%r state=%r"
            % (result.returncode, result.stdout, result.stderr, after),
        )

        server.state.reset("rule", rocket="Enet-FB", global_node="hy2-154")
        result = run_toggle(api, ["mode"])
        payload = payload_of(result)
        snapshot = server.state.snapshot()
        check(
            "mode/rule switches to global",
            result.returncode == 0
            and payload is not None
            and payload.get("ok") is True
            and payload.get("from") == "rule"
            and payload.get("to") == "global"
            and snapshot["requests"] == [("PATCH", "/configs", {"mode": "global"})]
            and snapshot["mode"] == "global",
            "rc=%r stdout=%r stderr=%r state=%r"
            % (result.returncode, result.stdout, result.stderr, snapshot),
        )

        server.state.reset("global", rocket="Enet-FB", global_node="hy2-154")
        result = run_toggle(api, ["mode"])
        payload = payload_of(result)
        snapshot = server.state.snapshot()
        check(
            "mode/global switches to rule",
            result.returncode == 0
            and payload is not None
            and payload.get("ok") is True
            and payload.get("from") == "global"
            and payload.get("to") == "rule"
            and snapshot["requests"] == [("PATCH", "/configs", {"mode": "rule"})]
            and snapshot["mode"] == "rule",
            "rc=%r stdout=%r stderr=%r state=%r"
            % (result.returncode, result.stdout, result.stderr, snapshot),
        )

        server.state.reset(
            "rule",
            rocket="Enet-FB",
            global_node="hy2-154",
            reject=("PATCH", "/configs", 500),
        )
        result = run_toggle(api, ["mode"])
        payload = payload_of(result)
        snapshot = server.state.snapshot()
        check(
            "mode API rejection is an error",
            result.returncode == 1
            and payload is not None
            and payload.get("ok") is False
            and "500" in payload.get("error", "")
            and snapshot["mode"] == "rule"
            and snapshot["requests"] == [("PATCH", "/configs", {"mode": "global"})],
            "rc=%r stdout=%r stderr=%r state=%r"
            % (result.returncode, result.stdout, result.stderr, snapshot),
        )
    finally:
        server.shutdown()
        server.server_close()

    if failures:
        print("FAIL")
        raise SystemExit(1)
    print("PASS: toggler used the expected group and mode mutations")


if __name__ == "__main__":
    main()
