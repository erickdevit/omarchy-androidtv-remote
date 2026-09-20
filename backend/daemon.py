#!/usr/bin/env python3
"""
Android TV Remote Daemon for Omarchy.
Maintains persistent connection to Android TV using Android TV Remote protocol v2,
discovers devices on LAN via Zeroconf, and serves commands over a Unix domain socket.
"""

import os
import sys
import json
import asyncio
import logging
import signal
from pathlib import Path
from typing import Optional, Dict, Any, List

# Ensure running in venv if not already
try:
    from androidtvremote2 import AndroidTVRemote, CannotConnect, ConnectionClosed, InvalidAuth
    from zeroconf import Zeroconf, ServiceStateChange
    from zeroconf.asyncio import AsyncZeroconf, AsyncServiceBrowser, AsyncServiceInfo
except ImportError:
    from bootstrap import ensure_venv
    ensure_venv()
    from androidtvremote2 import AndroidTVRemote, CannotConnect, ConnectionClosed, InvalidAuth
    from zeroconf import Zeroconf, ServiceStateChange
    from zeroconf.asyncio import AsyncZeroconf, AsyncServiceBrowser, AsyncServiceInfo

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger("androidtv-daemon")

STATE_DIR = Path.home() / ".local" / "state" / "omarchy" / "androidtv-remote"
SOCKET_PATH = STATE_DIR / "daemon.sock"
CONFIG_PATH = STATE_DIR / "config.json"
STATE_PATH = STATE_DIR / "state.json"
CERT_PATH = STATE_DIR / "cert.pem"
KEY_PATH = STATE_DIR / "key.pem"

KEY_MAP = {
    "UP": "DPAD_UP",
    "DOWN": "DPAD_DOWN",
    "LEFT": "DPAD_LEFT",
    "RIGHT": "DPAD_RIGHT",
    "CENTER": "DPAD_CENTER",
    "OK": "DPAD_CENTER",
    "ENTER": "DPAD_CENTER",
    "BACK": "BACK",
    "HOME": "HOME",
    "POWER": "POWER",
    "MUTE": "VOLUME_MUTE",
    "VOL_UP": "VOLUME_UP",
    "VOLUME_UP": "VOLUME_UP",
    "VOL_DOWN": "VOLUME_DOWN",
    "VOLUME_DOWN": "VOLUME_DOWN",
    "PLAY_PAUSE": "MEDIA_PLAY_PAUSE",
    "PLAY": "MEDIA_PLAY",
    "PAUSE": "MEDIA_PAUSE",
    "PREV": "MEDIA_PREVIOUS",
    "PREVIOUS": "MEDIA_PREVIOUS",
    "NEXT": "MEDIA_NEXT",
    "REWIND": "MEDIA_REWIND",
    "FAST_FORWARD": "MEDIA_FAST_FORWARD",
    "SETTINGS": "SETTINGS",
    "MENU": "MENU",
    "INPUT": "TV_INPUT",
    "TV_INPUT": "TV_INPUT",
    "ALL_APPS": "ALL_APPS",
}

APP_SHORTCUTS = {
    "youtube": "https://www.youtube.com",
    "netflix": "netflix://",
    "prime": "https://app.primevideo.com",
    "primevideo": "https://app.primevideo.com",
    "disney": "https://www.disneyplus.com",
    "disneyplus": "https://www.disneyplus.com",
    "spotify": "spotify:",
    "twitch": "twitch://",
    "kodi": "org.xbmc.kodi",
    "plex": "plex://",
    "crunchyroll": "https://www.crunchyroll.com",
    "hbo": "https://play.max.com",
    "max": "https://play.max.com",
}


class AndroidTVDaemon:
    def __init__(self):
        self.loop: Optional[asyncio.AbstractEventLoop] = None
        self.server: Optional[asyncio.Server] = None
        self.remote: Optional[AndroidTVRemote] = None
        self.pairing_remote: Optional[AndroidTVRemote] = None
        self.aiozc: Optional[AsyncZeroconf] = None
        self.browser: Optional[AsyncServiceBrowser] = None

        self.config: Dict[str, Any] = {}
        self.discovered_devices: Dict[str, Dict[str, Any]] = {}
        
        # Runtime states
        self.current_host: str = ""
        self.connected: bool = False
        self.is_on: bool = False
        self.current_app: str = ""
        self.volume_info: Dict[str, Any] = {"level": 0, "max": 100, "muted": False}
        self.pairing_active: bool = False
        self.pairing_host: str = ""
        self.last_error: str = ""
        self.shutting_down: bool = False

    def load_config(self):
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        if CONFIG_PATH.exists():
            try:
                with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                    self.config = json.load(f)
            except Exception as e:
                logger.error(f"Error reading config: {e}")
                self.config = {}
        if "devices" not in self.config:
            self.config["devices"] = {}
        if "current_device" not in self.config:
            self.config["current_device"] = ""
        self.current_host = self.config.get("current_device", "")

    def save_config(self):
        try:
            with open(CONFIG_PATH, "w", encoding="utf-8") as f:
                json.dump(self.config, f, indent=2)
        except Exception as e:
            logger.error(f"Error saving config: {e}")

    def write_state(self):
        device_name = ""
        if self.current_host and self.current_host in self.config.get("devices", {}):
            device_name = self.config["devices"][self.current_host].get("name", self.current_host)
        elif self.current_host:
            device_name = self.current_host

        state = {
            "daemon_running": True,
            "connected": self.connected,
            "is_on": self.is_on,
            "current_app": self.current_app,
            "current_device": self.current_host,
            "device_name": device_name,
            "volume": self.volume_info,
            "pairing_active": self.pairing_active,
            "pairing_host": self.pairing_host,
            "discovered_devices": list(self.discovered_devices.values()),
            "known_devices": [
                {"host": host, "name": info.get("name", host), "paired": info.get("paired", False)}
                for host, info in self.config.get("devices", {}).items()
            ],
            "last_error": self.last_error,
        }
        try:
            temp_path = STATE_PATH.with_suffix(".tmp")
            with open(temp_path, "w", encoding="utf-8") as f:
                json.dump(state, f, indent=2)
            temp_path.replace(STATE_PATH)
        except Exception as e:
            logger.error(f"Error writing state: {e}")

    # --- Callbacks from AndroidTVRemote ---
    def _on_is_on_updated(self, is_on: bool):
        logger.info(f"Power state updated: {is_on}")
        self.is_on = is_on
        self.write_state()

    def _on_current_app_updated(self, current_app: str):
        logger.info(f"Current app updated: {current_app}")
        self.current_app = current_app
        self.write_state()

    def _on_volume_info_updated(self, vol_info):
        logger.info(f"Volume updated: {vol_info}")
        self.volume_info = {
            "level": getattr(vol_info, "level", 0),
            "max": getattr(vol_info, "max", 100),
            "muted": getattr(vol_info, "muted", False),
        }
        self.write_state()

    def _on_is_available_updated(self, is_available: bool):
        logger.info(f"Availability updated: {is_available}")
        self.connected = is_available
        if not is_available:
            self.is_on = False
        self.write_state()

    # --- Zeroconf Discovery ---
    def _on_service_state_change(self, zeroconf: Zeroconf, service_type: str, name: str, state_change: ServiceStateChange):
        self.loop.create_task(self._async_handle_service_change(zeroconf, service_type, name, state_change))

    async def _async_handle_service_change(self, zeroconf: Zeroconf, service_type: str, name: str, state_change: ServiceStateChange):
        if state_change == ServiceStateChange.Removed:
            if name in self.discovered_devices:
                del self.discovered_devices[name]
                self.write_state()
            return

        info = AsyncServiceInfo(service_type, name)
        await info.async_request(zeroconf, 3000)
        if info and info.parsed_addresses():
            host = info.parsed_addresses()[0]
            clean_name = name.split(".")[0]
            # Check model or friendly name from properties
            props = {}
            if info.properties:
                props = {k.decode("utf-8", "ignore"): v.decode("utf-8", "ignore") if isinstance(v, bytes) else str(v)
                         for k, v in info.properties.items()}
            friendly_name = props.get("fn", clean_name)
            model = props.get("md", "")

            self.discovered_devices[name] = {
                "id": name,
                "name": friendly_name,
                "host": host,
                "port": info.port,
                "model": model,
            }
            logger.info(f"Discovered device: {friendly_name} at {host}:{info.port}")
            self.write_state()

    async def probe_ip(self, ip: str):
        is_awake = False
        dev_name = None
        model = "Smart TV / Android TV"

        # 1. Check if Android TV remote port (6467/6466) is open (TV is awake)
        try:
            _, writer = await asyncio.wait_for(asyncio.open_connection(ip, 6467), timeout=0.3)
            writer.close()
            await writer.wait_closed()
            is_awake = True
        except Exception:
            try:
                _, writer = await asyncio.wait_for(asyncio.open_connection(ip, 6466), timeout=0.3)
                writer.close()
                await writer.wait_closed()
                is_awake = True
            except Exception:
                is_awake = False

        # 2. Try port 8008 (Google Cast / eureka_info) for friendly name & model
        try:
            reader, writer = await asyncio.wait_for(asyncio.open_connection(ip, 8008), timeout=0.6)
            req = f"GET /setup/eureka_info HTTP/1.1\r\nHost: {ip}\r\nConnection: close\r\n\r\n"
            writer.write(req.encode())
            await writer.drain()
            data = await asyncio.wait_for(reader.read(4096), timeout=0.8)
            writer.close()
            await writer.wait_closed()
            body = data.decode("utf-8", "ignore").split("\r\n\r\n", 1)[-1]
            info = json.loads(body)
            dev_name = info.get("name", ip)
            model = info.get("model", "Smart TV / Android TV")
        except Exception:
            pass

        if is_awake or dev_name:
            self.discovered_devices[f"tv_{ip}"] = {
                "id": ip,
                "name": dev_name or f"Android TV ({ip})",
                "host": ip,
                "port": 6467,
                "model": model,
                "is_awake": is_awake,
            }
            self.write_state()

    async def scan_network(self):
        logger.info("Scanning network for Android TVs / Smart TVs...")
        try:
            import socket
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            local_ip = s.getsockname()[0]
            s.close()
            prefix = ".".join(local_ip.split(".")[:3])
        except Exception:
            prefix = "192.168.1"

        try:
            import subprocess
            p = subprocess.run(["ip", "neigh"], capture_output=True, text=True, timeout=1)
            for line in p.stdout.splitlines():
                parts = line.split()
                if parts and parts[0].startswith(prefix):
                    asyncio.create_task(self.probe_ip(parts[0]))
        except Exception:
            pass

        tasks = [self.probe_ip(f"{prefix}.{i}") for i in range(1, 255)]
        await asyncio.gather(*tasks, return_exceptions=True)
        self.write_state()
        logger.info(f"Discovery complete. Found {len(self.discovered_devices)} devices.")

    async def start_discovery(self):
        try:
            self.aiozc = AsyncZeroconf()
            services = ["_androidtvremote2._tcp.local.", "_googlecast._tcp.local."]
            self.browser = AsyncServiceBrowser(
                self.aiozc.zeroconf, services, handlers=[self._on_service_state_change]
            )
        except Exception as e:
            logger.error(f"Error starting Zeroconf discovery: {e}")

        self.loop.create_task(self.scan_network())

    # --- Connection & Control ---
    async def connect_to_host(self, host: str):
        if not host:
            return
        if self.remote:
            self.remote.disconnect()
            self.remote = None

        self.current_host = host
        self.config["current_device"] = host
        self.save_config()

        logger.info(f"Connecting to Android TV at {host}...")
        self.last_error = ""
        self.write_state()

        try:
            self.remote = AndroidTVRemote(
                client_name="Omarchy Remote",
                certfile=str(CERT_PATH),
                keyfile=str(KEY_PATH),
                host=host,
                api_port=6466,
                pair_port=6467,
                loop=self.loop,
                enable_ime=True
            )
            await self.remote.async_generate_cert_if_missing()
            self.remote.add_is_on_updated_callback(self._on_is_on_updated)
            self.remote.add_current_app_updated_callback(self._on_current_app_updated)
            self.remote.add_volume_info_updated_callback(self._on_volume_info_updated)
            self.remote.add_is_available_updated_callback(self._on_is_available_updated)

            await self.remote.async_connect()
            self.connected = True
            self.remote.keep_reconnecting()
            logger.info(f"Connected to {host}")
        except InvalidAuth:
            logger.warning(f"Device {host} requires pairing!")
            self.connected = False
            self.last_error = "Device requires pairing"
        except Exception as e:
            logger.error(f"Connection error to {host}: {e}")
            self.connected = False
            self.last_error = str(e)
            if self.remote:
                self.remote.keep_reconnecting()
        finally:
            self.write_state()

    async def pair_start(self, host: str) -> Dict[str, Any]:
        logger.info(f"Starting pairing with {host}...")
        self.last_error = ""
        if self.remote:
            self.remote.disconnect()
            self.remote = None

        self.pairing_host = host
        self.pairing_active = False
        self.write_state()

        try:
            self.pairing_remote = AndroidTVRemote(
                client_name="Omarchy Remote",
                certfile=str(CERT_PATH),
                keyfile=str(KEY_PATH),
                host=host,
                api_port=6466,
                pair_port=6467,
                loop=self.loop,
            )
            await self.pairing_remote.async_generate_cert_if_missing()
            self.pairing_active = True
            self.write_state()
            await self.pairing_remote.async_start_pairing()
            logger.info(f"Pairing challenge displayed on {host}")
            return {"ok": True, "status": "code_prompt", "host": host}
        except Exception as e:
            err_msg = str(e)
            if not err_msg or err_msg.strip() == "":
                err_msg = type(e).__name__
            if "CannotConnect" in type(e).__name__ or "111" in str(e) or "refused" in str(e).lower():
                err_msg = f"Conexão recusada na porta 6467 da TV ({host}). Verifique se a TV está ligada na tela inicial e se o 'Android TV Remote Service' está ativo/atualizado na TV."
            logger.error(f"Failed to start pairing with {host}: {err_msg}")
            self.pairing_active = False
            self.last_error = err_msg
            self.write_state()
            return {"ok": False, "error": err_msg}

    async def pair_finish(self, code: str) -> Dict[str, Any]:
        if not self.pairing_remote or not self.pairing_active:
            return {"ok": False, "error": "No pairing session active"}

        code = code.strip().upper()
        logger.info(f"Finishing pairing with code {code}...")
        try:
            await self.pairing_remote.async_finish_pairing(code)
            host = self.pairing_host
            self.pairing_active = False
            self.pairing_remote = None

            # Retrieve device name if possible
            dev_name = host
            for d in self.discovered_devices.values():
                if d.get("host") == host:
                    dev_name = d.get("name", host)
                    break

            if "devices" not in self.config:
                self.config["devices"] = {}
            self.config["devices"][host] = {
                "name": dev_name,
                "paired": True,
            }
            self.config["current_device"] = host
            self.save_config()

            logger.info(f"Pairing successfully completed for {host}!")
            # Connect immediately
            await self.connect_to_host(host)
            return {"ok": True, "status": "paired", "host": host, "name": dev_name}
        except InvalidAuth:
            logger.error("Invalid pairing code entered")
            self.last_error = "Invalid pairing code"
            self.write_state()
            return {"ok": False, "error": "Invalid pairing code"}
        except Exception as e:
            logger.error(f"Pairing error: {e}")
            self.last_error = str(e)
            self.write_state()
            return {"ok": False, "error": str(e)}

    def pair_cancel(self):
        if self.pairing_remote:
            self.pairing_remote.disconnect()
            self.pairing_remote = None
        self.pairing_active = False
        self.last_error = ""
        self.write_state()
        return {"ok": True}

    def send_key(self, key_name: str) -> Dict[str, Any]:
        if not self.remote or not self.connected:
            return {"ok": False, "error": "Not connected to Android TV"}

        mapped_key = KEY_MAP.get(key_name.upper(), key_name.upper())
        logger.info(f"Sending key: {mapped_key} (from {key_name})")
        try:
            self.remote.send_key_command(mapped_key)
            return {"ok": True, "key": mapped_key}
        except Exception as e:
            logger.error(f"Error sending key {mapped_key}: {e}")
            return {"ok": False, "error": str(e)}

    def send_text(self, text: str) -> Dict[str, Any]:
        if not self.remote or not self.connected:
            return {"ok": False, "error": "Not connected to Android TV"}

        logger.info(f"Sending text: {text}")
        try:
            self.remote.send_text(text)
            return {"ok": True}
        except Exception as e:
            logger.error(f"Error sending text: {e}")
            return {"ok": False, "error": str(e)}

    def launch_app(self, app_id_or_shortcut: str) -> Dict[str, Any]:
        if not self.remote or not self.connected:
            return {"ok": False, "error": "Not connected to Android TV"}

        target = APP_SHORTCUTS.get(app_id_or_shortcut.lower(), app_id_or_shortcut)
        logger.info(f"Launching app: {target} (from {app_id_or_shortcut})")
        try:
            self.remote.send_launch_app_command(target)
            return {"ok": True, "target": target}
        except Exception as e:
            logger.error(f"Error launching app {target}: {e}")
            return {"ok": False, "error": str(e)}

    # --- Unix Socket Server ---
    async def handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        try:
            data = await reader.readline()
            if not data:
                return
            message = json.loads(data.decode("utf-8").strip())
            cmd = message.get("cmd")
            response: Dict[str, Any] = {"ok": False, "error": "Unknown command"}

            if cmd == "ping":
                response = {"ok": True, "pong": True}
            elif cmd == "status":
                response = {
                    "ok": True,
                    "connected": self.connected,
                    "is_on": self.is_on,
                    "current_app": self.current_app,
                    "current_device": self.current_host,
                    "volume": self.volume_info,
                    "pairing_active": self.pairing_active,
                    "discovered_devices": list(self.discovered_devices.values()),
                }
            elif cmd == "key":
                key = message.get("key", "")
                response = self.send_key(key)
            elif cmd == "text":
                text = message.get("text", "")
                response = self.send_text(text)
            elif cmd == "app":
                app = message.get("app", "")
                response = self.launch_app(app)
            elif cmd == "connect":
                host = message.get("host", self.current_host)
                self.loop.create_task(self.connect_to_host(host))
                response = {"ok": True, "status": "connecting", "host": host}
            elif cmd == "disconnect":
                if self.remote:
                    self.remote.disconnect()
                    self.remote = None
                self.connected = False
                self.write_state()
                response = {"ok": True}
            elif cmd == "pair_start":
                host = message.get("host", "")
                response = await self.pair_start(host)
            elif cmd == "pair_finish":
                code = message.get("code", "")
                response = await self.pair_finish(code)
            elif cmd == "pair_cancel":
                response = self.pair_cancel()
            elif cmd == "discover":
                await self.scan_network()
                response = {"ok": True, "devices": list(self.discovered_devices.values())}

            writer.write((json.dumps(response) + "\n").encode("utf-8"))
            await writer.drain()
        except Exception as e:
            logger.error(f"Error handling IPC request: {e}")
            try:
                writer.write((json.dumps({"ok": False, "error": str(e)}) + "\n").encode("utf-8"))
                await writer.drain()
            except Exception:
                pass
        finally:
            writer.close()
            await writer.wait_closed()

    async def run(self):
        self.loop = asyncio.get_running_loop()
        self.load_config()
        self.write_state()

        if SOCKET_PATH.exists():
            SOCKET_PATH.unlink()

        self.server = await asyncio.start_unix_server(self.handle_client, path=str(SOCKET_PATH))
        SOCKET_PATH.chmod(0o700)
        logger.info(f"Android TV daemon listening on {SOCKET_PATH}")

        # Start discovery
        await self.start_discovery()

        # Connect to saved device if any
        if self.current_host:
            self.loop.create_task(self.connect_to_host(self.current_host))

        # Handle termination signals
        for sig in (signal.SIGTERM, signal.SIGINT):
            self.loop.add_signal_handler(sig, lambda: asyncio.create_task(self.shutdown()))

        async with self.server:
            await self.server.serve_forever()

    async def shutdown(self):
        if self.shutting_down:
            return
        self.shutting_down = True
        logger.info("Shutting down daemon...")

        if self.browser:
            await self.browser.async_cancel()
        if self.aiozc:
            await self.aiozc.async_close()
        if self.remote:
            self.remote.disconnect()
        if self.pairing_remote:
            self.pairing_remote.disconnect()
        if self.server:
            self.server.close()
            await self.server.wait_closed()
        if SOCKET_PATH.exists():
            SOCKET_PATH.unlink()

        # Update state to reflect daemon is down
        self.connected = False
        self.write_state()
        state = {
            "daemon_running": False,
            "connected": False,
            "is_on": False,
            "current_app": "",
            "current_device": self.current_host,
            "device_name": "",
            "volume": {"level": 0, "max": 100, "muted": False},
            "pairing_active": False,
            "pairing_host": "",
            "discovered_devices": [],
            "known_devices": [],
            "last_error": "",
        }
        with open(STATE_PATH, "w", encoding="utf-8") as f:
            json.dump(state, f, indent=2)

        self.loop.stop()


def main():
    daemon = AndroidTVDaemon()
    try:
        asyncio.run(daemon.run())
    except (KeyboardInterrupt, SystemExit):
        pass


if __name__ == "__main__":
    main()
