#!/usr/bin/env python3
"""Relais entre l'app (port 11435) et Ollama (11434) : enregistre chaque requête et sa réponse."""
import http.client
import http.server
import json
import socketserver
import os
import threading
import time

UPSTREAM = ("127.0.0.1", 11434)
LOG = "/tmp/requests.jsonl"
STATE = "/tmp/proxy_state.json"
lock = threading.Lock()
state = {"seq": 0, "chat": 0, "embed": 0, "inflight": 0}


def save_state():
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f)
    os.replace(tmp, STATE)


def shorten(body):
    if not isinstance(body, dict):
        return body
    body = dict(body)
    if isinstance(body.get("messages"), list):
        messages = []
        for message in body["messages"]:
            message = dict(message)
            if message.get("images"):
                message["images"] = ["<%d caractères base64>" % len(image) for image in message["images"]]
            messages.append(message)
        body["messages"] = messages
    if "input" in body:
        inputs = body["input"] if isinstance(body["input"], list) else [body["input"]]
        body["input_count"] = len(inputs)
        body["input"] = [str(text)[:120] for text in inputs[:3]]
    return body


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def relay(self, method):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else None
        tracked = self.path.startswith("/api/chat") or self.path.startswith("/api/embed")
        with lock:
            state["seq"] += 1
            seq = state["seq"]
            if tracked:
                state["inflight"] += 1
                state["chat" if self.path.startswith("/api/chat") else "embed"] += 1
            save_state()
        record = {"seq": seq, "time": round(time.time(), 2), "method": method, "path": self.path}
        if body and tracked:
            try:
                record["body"] = shorten(json.loads(body))
            except Exception as error:  # noqa: BLE001
                record["body_error"] = repr(error)
        content, thinking, tool_calls, extra = [], [], [], {}

        def parse(line):
            try:
                item = json.loads(line)
            except Exception:  # noqa: BLE001
                return
            message = item.get("message") or {}
            if message.get("content"):
                content.append(message["content"])
            if message.get("thinking"):
                thinking.append(message["thinking"])
            if message.get("tool_calls"):
                tool_calls.extend(message["tool_calls"])
            if item.get("error"):
                extra["error"] = item["error"]
            for key in ("eval_count", "prompt_eval_count", "done_reason"):
                if key in item:
                    extra[key] = item[key]
            if "embeddings" in item:
                extra["embeddings"] = len(item["embeddings"])

        started = time.time()
        connection = None
        try:
            connection = http.client.HTTPConnection(*UPSTREAM, timeout=900)
            headers = {k: v for k, v in self.headers.items() if k.lower() not in ("host", "content-length", "connection", "accept-encoding")}
            connection.request(method, self.path, body=body, headers=headers)
            response = connection.getresponse()
            record["status"] = response.status
            self.send_response(response.status)
            for key, value in response.getheaders():
                if key.lower() not in ("transfer-encoding", "content-length", "connection"):
                    self.send_header(key, value)
            self.send_header("Transfer-Encoding", "chunked")
            self.send_header("Connection", "close")
            self.end_headers()
            pending = b""
            while True:
                chunk = response.read1(65536)
                if not chunk:
                    break
                self.wfile.write(b"%x\r\n" % len(chunk) + chunk + b"\r\n")
                self.wfile.flush()
                if tracked:
                    pending += chunk
                    while b"\n" in pending:
                        line, pending = pending.split(b"\n", 1)
                        parse(line)
            if tracked and pending.strip():
                parse(pending)
            self.wfile.write(b"0\r\n\r\n")
            self.wfile.flush()
        except Exception as error:  # noqa: BLE001
            record["relay_error"] = repr(error)
        finally:
            if connection is not None:
                connection.close()
            record["seconds"] = round(time.time() - started, 2)
            record["response"] = {
                "content": "".join(content)[:3000],
                "thinking_chars": len("".join(thinking)),
                "tool_calls": tool_calls,
                **extra,
            }
            with lock:
                if tracked:
                    state["inflight"] -= 1
                save_state()
                if tracked or record.get("status", 200) >= 400:
                    with open(LOG, "a") as f:
                        f.write(json.dumps(record, ensure_ascii=False) + "\n")
        self.close_connection = True

    def do_GET(self):
        self.relay("GET")

    def do_POST(self):
        self.relay("POST")

    def do_DELETE(self):
        self.relay("DELETE")


save_state()
class Server(http.server.ThreadingHTTPServer):
    def server_bind(self):
        # Sans socket.getfqdn() : sa recherche de nom déclenche l'alerte « réseau local » de macOS.
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = "localhost", self.server_address[1]


Server(("127.0.0.1", 11435), Handler).serve_forever()
