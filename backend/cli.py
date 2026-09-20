#!/usr/bin/env python3
"""
CLI interface for Android TV Remote in Omarchy.
Communicates with the background daemon via Unix domain socket.
Auto-spawns the daemon if not currently running.
"""

import os
import sys
import json
import time
import socket
import subprocess
from pathlib import Path

STATE_DIR = Path.home() / ".local" / "state" / "omarchy" / "androidtv-remote"
SOCKET_PATH = STATE_DIR / "daemon.sock"
DAEMON_SCRIPT = Path(__file__).parent / "daemon.py"
VENV_PYTHON = Path.home() / ".local" / "share" / "omarchy-androidtv" / "venv" / "bin" / "python3"

def is_daemon_running() -> bool:
    if not SOCKET_PATH.exists():
        return False
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(0.5)
            s.connect(str(SOCKET_PATH))
            s.sendall(b'{"cmd": "ping"}\n')
            res = s.recv(1024)
            data = json.loads(res.decode("utf-8"))
            return data.get("ok") is True and data.get("pong") is True
    except Exception:
        return False

def ensure_daemon():
    if is_daemon_running():
        return True

    python_bin = str(VENV_PYTHON) if VENV_PYTHON.exists() else sys.executable
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    log_file = STATE_DIR / "daemon.log"

    with open(log_file, "a") as log:
        subprocess.Popen(
            [python_bin, str(DAEMON_SCRIPT)],
            stdout=log,
            stderr=log,
            start_new_session=True,
            close_fds=True
        )

    # Wait up to 3 seconds for socket
    start = time.time()
    while time.time() - start < 3.0:
        if is_daemon_running():
            return True
        time.sleep(0.1)

    return is_daemon_running()

def send_ipc_command(payload: dict) -> dict:
    if not ensure_daemon():
        return {"ok": False, "error": "Failed to start daemon"}

    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(5.0)
            s.connect(str(SOCKET_PATH))
            msg = json.dumps(payload) + "\n"
            s.sendall(msg.encode("utf-8"))
            res = s.recv(4096)
            return json.loads(res.decode("utf-8"))
    except Exception as e:
        return {"ok": False, "error": f"Socket communication error: {e}"}

def main():
    if len(sys.argv) < 2:
        print("Usage: remote-cli <command> [args...]")
        print("Commands:")
        print("  key <KEY>           - Send key (e.g. UP, DOWN, LEFT, RIGHT, OK, BACK, HOME, POWER, VOL_UP, VOL_DOWN, MUTE, PLAY_PAUSE)")
        print("  text <TEXT>         - Send text typing to TV")
        print("  app <APP_OR_URL>    - Launch app (e.g. youtube, netflix, prime, disney, spotify, or custom uri)")
        print("  pair-start <IP>     - Start pairing with Android TV at IP")
        print("  pair-finish <CODE>  - Submit pairing PIN code shown on TV screen")
        print("  pair-cancel         - Cancel active pairing session")
        print("  connect [IP]        - Connect to IP or saved TV")
        print("  disconnect          - Disconnect from current TV")
        print("  discover            - Discover Android TVs on LAN")
        print("  status              - Get current status")
        print("  start-daemon        - Ensure daemon is running")
        print("  stop-daemon         - Stop daemon")
        sys.exit(1)

    cmd = sys.argv[1].lower()

    if cmd == "start-daemon":
        if ensure_daemon():
            print(json.dumps({"ok": True, "message": "Daemon running"}))
            sys.exit(0)
        else:
            print(json.dumps({"ok": False, "error": "Could not start daemon"}))
            sys.exit(1)

    elif cmd == "stop-daemon":
        if SOCKET_PATH.exists():
            try:
                # Send SIGTERM to process or remove socket
                res = send_ipc_command({"cmd": "disconnect"})
            except Exception:
                pass
        print(json.dumps({"ok": True}))
        sys.exit(0)

    elif cmd == "key":
        if len(sys.argv) < 3:
            print(json.dumps({"ok": False, "error": "Missing key argument"}))
            sys.exit(1)
        key = sys.argv[2]
        res = send_ipc_command({"cmd": "key", "key": key})
        print(json.dumps(res))

    elif cmd == "text":
        if len(sys.argv) < 3:
            print(json.dumps({"ok": False, "error": "Missing text argument"}))
            sys.exit(1)
        text = " ".join(sys.argv[2:])
        res = send_ipc_command({"cmd": "text", "text": text})
        print(json.dumps(res))

    elif cmd == "app":
        if len(sys.argv) < 3:
            print(json.dumps({"ok": False, "error": "Missing app argument"}))
            sys.exit(1)
        app = sys.argv[2]
        res = send_ipc_command({"cmd": "app", "app": app})
        print(json.dumps(res))

    elif cmd == "pair-start":
        if len(sys.argv) < 3:
            print(json.dumps({"ok": False, "error": "Missing IP argument"}))
            sys.exit(1)
        host = sys.argv[2]
        res = send_ipc_command({"cmd": "pair_start", "host": host})
        print(json.dumps(res))

    elif cmd == "pair-finish":
        if len(sys.argv) < 3:
            print(json.dumps({"ok": False, "error": "Missing code argument"}))
            sys.exit(1)
        code = sys.argv[2]
        res = send_ipc_command({"cmd": "pair_finish", "code": code})
        print(json.dumps(res))

    elif cmd == "pair-cancel":
        res = send_ipc_command({"cmd": "pair_cancel"})
        print(json.dumps(res))

    elif cmd == "connect":
        host = sys.argv[2] if len(sys.argv) >= 3 else ""
        payload = {"cmd": "connect"}
        if host:
            payload["host"] = host
        res = send_ipc_command(payload)
        print(json.dumps(res))

    elif cmd == "disconnect":
        res = send_ipc_command({"cmd": "disconnect"})
        print(json.dumps(res))

    elif cmd == "discover":
        res = send_ipc_command({"cmd": "discover"})
        print(json.dumps(res))

    elif cmd == "status":
        res = send_ipc_command({"cmd": "status"})
        print(json.dumps(res))

    else:
        print(json.dumps({"ok": False, "error": f"Unknown command: {cmd}"}))
        sys.exit(1)

if __name__ == "__main__":
    main()
