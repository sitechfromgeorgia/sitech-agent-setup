#!/usr/bin/env python3
"""
sitech laptop-agent — user-space command executor (no sudo, no sshd needed).

Listens on 127.0.0.1:7681 only; reachable exclusively through the reverse SSH
tunnel (VPS 127.0.0.1:2222 -> laptop 127.0.0.1:7681).

Protocol: one newline-delimited JSON request -> one JSON response.
  request : {"token": "...", "cmd": "...", "timeout": 300}
  response: {"ok": true, "stdout": "...", "stderr": "...", "code": 0}
"""
import json
import os
import socket
import subprocess
import sys
import threading

PORT = 7681
TOKEN_FILE = os.path.expanduser("~/.sitech_agent_token")
MAX_OUT = 200_000


def load_token() -> str:
    try:
        with open(TOKEN_FILE, encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return ""


def handle(conn: socket.socket) -> None:
    try:
        conn.settimeout(600)
        fh = conn.makefile("rwb")
        line = fh.readline()
        if not line:
            return
        req = json.loads(line.decode("utf-8"))
        if req.get("token") != load_token():
            fh.write(json.dumps({"ok": False, "error": "unauthorized"}).encode() + b"\n")
            fh.flush()
            return
        cmd = str(req.get("cmd", ""))
        timeout = int(req.get("timeout", 300))
        proc = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=os.path.expanduser("~"),
        )
        fh.write(
            json.dumps(
                {
                    "ok": True,
                    "stdout": proc.stdout[-MAX_OUT:],
                    "stderr": proc.stderr[-MAX_OUT:],
                    "code": proc.returncode,
                }
            ).encode()
            + b"\n"
        )
        fh.flush()
    except subprocess.TimeoutExpired:
        try:
            conn.sendall(json.dumps({"ok": False, "error": "timeout"}).encode() + b"\n")
        except OSError:
            pass
    except Exception as exc:  # noqa: BLE001 - report any failure to the caller
        try:
            conn.sendall(json.dumps({"ok": False, "error": str(exc)}).encode() + b"\n")
        except OSError:
            pass
    finally:
        try:
            conn.close()
        except OSError:
            pass


def main() -> None:
    if not load_token():
        print(f"!! token file missing: {TOKEN_FILE}", file=sys.stderr)
        sys.exit(1)
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", PORT))
    srv.listen(8)
    print(f"sitech laptop-agent listening on 127.0.0.1:{PORT}")
    while True:
        conn, _ = srv.accept()
        threading.Thread(target=handle, args=(conn,), daemon=True).start()


if __name__ == "__main__":
    main()
