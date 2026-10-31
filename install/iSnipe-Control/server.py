"""LAN control panel for the local iSnipe IW4x servers. Python 3.10+."""
from __future__ import annotations

import hashlib
import hmac
import ipaddress
import json
import os
import re
import secrets
import socket
import subprocess
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from http import HTTPStatus
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

PANEL = Path(__file__).resolve().parent
GAME = PANEL.parent
SETTINGS_FILE = PANEL / "panel-settings.json"
CREDENTIALS_FILE = PANEL / "panel-password.txt"
ANNOUNCEMENTS = GAME / "userraw" / "isnipe-announcements.cfg"
BAN_FILE = GAME / "userraw" / "bans.json"
STATIC = PANEL / "static"
SETTINGS = json.loads(SETTINGS_FILE.read_text(encoding="utf-8"))
SERVERS = {
    "sd": {"name": "iSnipe 2026 S&D", "mod": "isnipe-sd", "port": 28960, "mode": "sd", "cfg": "isnipe-dev.cfg"},
    "tdm": {"name": "iSnipe 2026 TDM", "mod": "isnipe-tdm", "port": 28961, "mode": "war", "cfg": "isnipe-tdm.cfg"},
    "ffa": {"name": "iSnipe 2026 FFA", "mod": "isnipe-ffa", "port": 28962, "mode": "dm", "cfg": "isnipe-ffa.cfg"},
}
SESSIONS: dict[str, tuple[float, str]] = {}
ATTEMPTS: dict[str, list[float]] = {}
SESSION_LOCK = threading.Lock()
CONFIG_LOCK = threading.Lock()
SERVER_LOCKS = {key: threading.RLock() for key in SERVERS}
LAST_RCON = {key: 0.0 for key in SERVERS}
CREATE_NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)
COMMAND_PREFIX = b"\xff\xff\xff\xff"
CONFIG_LINE = re.compile(r'^\s*set\s+([A-Za-z0-9_]+)\s+"([^"\r\n]*)"', re.I)


def atomic_write(path: Path, text: str) -> None:
    temp = path.with_name(path.name + ".panel.tmp")
    temp.write_text(text, encoding="utf-8", newline="\n")
    os.replace(temp, path)


def read_cfg(path: Path) -> dict[str, str]:
    result = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = CONFIG_LINE.match(line)
        if match:
            result[match.group(1)] = match.group(2)
    return result


def update_cfg(path: Path, values: dict[str, str]) -> None:
    lines = path.read_text(encoding="utf-8").splitlines()
    seen = set()
    output = []
    for line in lines:
        match = CONFIG_LINE.match(line)
        if match and match.group(1) in values:
            key = match.group(1)
            if key not in seen:
                output.append(f'set {key} "{values[key]}"')
                seen.add(key)
        else:
            output.append(line)
    for key, value in values.items():
        if key not in seen:
            output.append(f'set {key} "{value}"')
    atomic_write(path, "\n".join(output) + "\n")


def config_text(value, *, limit=180, allow_empty=True) -> str:
    if not isinstance(value, str) or len(value.encode("utf-8")) > limit:
        raise ValueError("Text is too long or invalid")
    if any(ch in value for ch in '"\\;\r\n\x00') or any(ord(c) < 32 for c in value):
        raise ValueError("Text cannot contain quotes, backslashes, semicolons, or control characters")
    if not allow_empty and not value.strip():
        raise ValueError("Text cannot be empty")
    return value


def integer(value, minimum: int, maximum: int) -> int:
    if isinstance(value, bool) or not re.fullmatch(r"[0-9]+", str(value)):
        raise ValueError("Expected a whole number")
    value = int(value)
    if not minimum <= value <= maximum:
        raise ValueError(f"Value must be between {minimum} and {maximum}")
    return value


def packet(port: int, text: str, timeout=1.5) -> str:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.settimeout(timeout)
        sock.sendto(COMMAND_PREFIX + text.encode("utf-8"), ("127.0.0.1", port))
        data, source = sock.recvfrom(65535)
        if source[0] != "127.0.0.1" or source[1] != port:
            raise OSError("Unexpected response source")
        return data[4:].decode("utf-8", "replace") if data.startswith(COMMAND_PREFIX) else data.decode("utf-8", "replace")


def get_info(key: str) -> dict:
    challenge = secrets.token_hex(6)
    response = packet(SERVERS[key]["port"], "getinfo " + challenge)
    lines = response.split("\n", 1)
    if len(lines) < 2 or not lines[0].lower().startswith("inforesponse"):
        raise OSError("Unexpected server response")
    fields = lines[1].strip().split("\\")
    if fields and not fields[0]:
        fields = fields[1:]
    info = dict(zip(fields[::2], fields[1::2]))
    if info.get("challenge") != challenge:
        raise OSError("Server challenge did not match")
    return info


def rcon(key: str, command: str, timeout=2.5) -> str:
    # Callers construct fixed commands from validated inputs only.
    with SERVER_LOCKS[key]:
        delay = 0.16 - (time.monotonic() - LAST_RCON[key])
        if delay > 0:
            time.sleep(delay)
        LAST_RCON[key] = time.monotonic()
        return packet(SERVERS[key]["port"], "rcon " + SETTINGS["rcon_password"] + " " + command, timeout)


def player_list(key: str) -> list[dict]:
    response = rcon(key, "isnipePanelPlayers")
    for line in response.splitlines():
        pos = line.find("ISNIPE_PLAYERS:")
        if pos >= 0:
            players = json.loads(line[pos + len("ISNIPE_PLAYERS:"):])
            if not isinstance(players, list):
                raise RuntimeError("Invalid player response")
            return players
    raise RuntimeError("Server did not return its player list; restart it with the current iSnipe build")


def processes() -> list[dict]:
    command = "Get-CimInstance Win32_Process -Filter \"Name='iw4x.exe'\" | Select-Object ProcessId,CommandLine | ConvertTo-Json -Compress"
    result = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", command],
                            capture_output=True, text=True, timeout=10, creationflags=CREATE_NO_WINDOW)
    if result.returncode:
        raise RuntimeError("Unable to inspect server processes")
    raw = result.stdout.strip().lstrip("\ufeff")
    if not raw:
        return []
    items = json.loads(raw)
    return items if isinstance(items, list) else [items]


def matching_processes(key: str, items: list[dict] | None = None) -> list[dict]:
    server = SERVERS[key]
    matches = []
    for item in processes() if items is None else items:
        cmd = item.get("CommandLine") or ""
        if re.search(r'(?i)(?:^|\s)-dedicated(?:\s|$)', cmd) and \
           re.search(r'(?i)\+set\s+fs_game\s+"?mods/' + re.escape(server["mod"]) + r'"?(?:\s|$)', cmd) and \
           re.search(r'(?i)\+set\s+net_port\s+' + str(server["port"]) + r'(?:\s|$)', cmd):
            matches.append(item)
    return matches


def start_server(key: str) -> str:
    with SERVER_LOCKS[key]:
        if matching_processes(key):
            raise ValueError("This server is already running")
        try:
            info = get_info(key)
        except OSError:
            info = None
        if info:
            raise ValueError("The port is already answering; start was cancelled")
        server = SERVERS[key]
        args = [str(GAME / "iw4x.exe"), "-dedicated", "+set", "fs_game", "mods/" + server["mod"],
                "+set", "sv_lanonly", "0", "+set", "dedicated", "2", "+set", "net_port", str(server["port"]),
                "+exec", "isnipe-public.cfg", "+exec", "isnipe-dev.cfg"]
        if key != "sd":
            args += ["+exec", server["cfg"]]
        args += ["+set", "g_gametype", server["mode"], "+map", "mp_terminal"]
        subprocess.Popen(args, cwd=GAME, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, creationflags=CREATE_NO_WINDOW)
        return "Start requested. The server may take several seconds to become ready."


def stop_server(key: str) -> str:
    with SERVER_LOCKS[key]:
        matches = matching_processes(key)
        if not matches:
            raise ValueError("This server is not running")
        if len(matches) != 1:
            raise ValueError("Multiple matching processes were found; stop them manually")
        pid = int(matches[0]["ProcessId"])
        try:
            info = get_info(key)
            if info.get("fs_game", "").lower() != ("mods/" + SERVERS[key]["mod"]).lower():
                raise ValueError("Another server is using this port")
            try:
                rcon(key, "quit", timeout=1.0)
            except OSError:
                pass  # A successful quit can close the socket before replying.
        except OSError:
            pass  # A stuck server may not answer; its process identity is checked again below.
        for _ in range(20):
            time.sleep(0.2)
            current = matching_processes(key)
            if not any(int(p["ProcessId"]) == pid for p in current):
                return "Server stopped."
        current = matching_processes(key)
        if len(current) != 1 or int(current[0]["ProcessId"]) != pid:
            raise ValueError("Server process changed; stop was cancelled")
        result = subprocess.run(["taskkill.exe", "/PID", str(pid), "/F"], capture_output=True,
                                text=True, timeout=10, creationflags=CREATE_NO_WINDOW)
        if result.returncode:
            raise RuntimeError("Could not stop the matching server process")
        return "Unresponsive server process stopped."


def server_status(key: str, proc: list[dict]) -> dict:
    result = {"id": key, "port": SERVERS[key]["port"], "name": SERVERS[key]["name"],
              "processes": len(matching_processes(key, proc)), "online": False, "players": []}
    try:
        info = get_info(key)
        result.update(online=True, name=info.get("hostname", result["name"]), mode=info.get("gametype", ""),
                      map=info.get("mapname", ""), clients=info.get("clients", "0"), bots=info.get("bots", "0"))
        if info.get("fs_game", "").lower() != ("mods/" + SERVERS[key]["mod"]).lower():
            result["error"] = "Unexpected server on this port"
        else:
            try:
                result["players"] = player_list(key)
            except (OSError, RuntimeError, json.JSONDecodeError) as exc:
                result["error"] = str(exc)
    except OSError:
        if result["processes"]:
            result["error"] = "Process is starting or not responding"
    return result


def read_bans() -> dict:
    if not BAN_FILE.exists():
        return {"id": [], "ip": []}
    data = json.loads(BAN_FILE.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or not isinstance(data.get("id"), list) or not isinstance(data.get("ip"), list):
        raise RuntimeError("IW4x ban file has an invalid format")
    return {"id": [str(x) for x in data["id"]], "ip": [str(x) for x in data["ip"]]}


def announcement_keys() -> list[str]:
    keys = ["isnipe_announcements_enabled", "isnipe_welcome_delay"]
    keys += [f"isnipe_welcome_{i}" for i in range(1, 5)]
    for i in range(1, 6):
        keys += [f"isnipe_announce_interval_{i}", f"isnipe_announce_message_{i}",
                 f"isnipe_daily_time_{i}", f"isnipe_daily_message_{i}"]
    return keys


def save_announcements(data: dict) -> list[str]:
    if set(data) != set(announcement_keys()):
        raise ValueError("Announcement settings are incomplete")
    clean = {}
    for key, value in data.items():
        if key == "isnipe_announcements_enabled":
            clean[key] = str(integer(value, 0, 1))
        elif key == "isnipe_welcome_delay":
            clean[key] = str(integer(value, 0, 120))
        elif key.startswith("isnipe_announce_interval_"):
            clean[key] = str(integer(value, 0, 604800))
        elif key.startswith("isnipe_daily_time_"):
            value = config_text(value, limit=5)
            if value and (not re.fullmatch(r"\d\d:\d\d", value) or int(value[:2]) > 23 or int(value[3:]) > 59):
                raise ValueError("Daily times must be in 24-hour HH:MM format")
            clean[key] = value
        else:
            clean[key] = config_text(value)
    with CONFIG_LOCK:
        update_cfg(ANNOUNCEMENTS, clean)
    failed = []
    for key in SERVERS:
        try:
            get_info(key)
            rcon(key, "exec isnipe-announcements.cfg")
        except (OSError, RuntimeError):
            failed.append(key)
    return failed


def read_mode_settings(key: str) -> dict:
    server = SERVERS[key]
    cfg = read_cfg(GAME / "userraw" / server["cfg"])
    mode = server["mode"]
    limit_key = "scr_sd_winlimit" if key == "sd" else f"scr_{mode}_scorelimit"
    multiplier = {"sd": 1, "tdm": 100, "ffa": 50}[key]
    return {"hostname": cfg.get("sv_hostname", server["name"]),
            "time": cfg.get(f"scr_{mode}_timelimit", ""),
            "limit": int(cfg.get(limit_key, "0")) // multiplier}


def save_mode_settings(key: str, data: dict) -> None:
    if set(data) != {"hostname", "time", "limit"}:
        raise ValueError("Server settings are incomplete")
    server = SERVERS[key]
    hostname = config_text(data["hostname"], limit=60, allow_empty=False)
    minutes = integer(data["time"], 1, 240)
    limit = integer(data["limit"], 1, 20 if key == "sd" else 1000)
    mode = server["mode"]
    limit_key = "scr_sd_winlimit" if key == "sd" else f"scr_{mode}_scorelimit"
    points = limit * {"sd": 1, "tdm": 100, "ffa": 50}[key]
    with CONFIG_LOCK:
        update_cfg(GAME / "userraw" / server["cfg"], {"sv_hostname": hostname, f"scr_{mode}_timelimit": str(minutes), limit_key: str(points)})


def verify_password(password: str) -> bool:
    if not isinstance(password, str) or len(password) > 512:
        return False
    result = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), bytes.fromhex(SETTINGS["password_salt"]), 310000).hex()
    return hmac.compare_digest(result, SETTINGS["password_hash"])


class Handler(BaseHTTPRequestHandler):
    server_version = "iSnipeControl/1.0"

    def log_message(self, fmt, *args):
        print(f"{self.client_address[0]} {fmt % args}", flush=True)

    def headers_common(self):
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; frame-ancestors 'none'; base-uri 'none'")

    def reply(self, code, payload, cookie=None):
        body = json.dumps(payload, ensure_ascii=True).encode("utf-8")
        self.send_response(code)
        self.headers_common()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        if cookie:
            self.send_header("Set-Cookie", cookie)
        self.end_headers()
        self.wfile.write(body)

    def local_peer(self):
        try:
            ip = ipaddress.ip_address(self.client_address[0])
            return ip.is_private or ip.is_loopback or ip.is_link_local
        except ValueError:
            return False

    def session(self):
        cookies = SimpleCookie()
        try:
            cookies.load(self.headers.get("Cookie", ""))
            token = cookies["isnipe_session"].value if "isnipe_session" in cookies else ""
        except Exception:
            return None
        with SESSION_LOCK:
            entry = SESSIONS.get(token)
            if not entry or entry[0] < time.time():
                SESSIONS.pop(token, None)
                return None
            return token, entry[1]

    def same_origin(self):
        origin = self.headers.get("Origin")
        if not origin:
            return True
        parsed = urlsplit(origin)
        return parsed.scheme == "http" and parsed.netloc.lower() == self.headers.get("Host", "").lower()

    def body(self):
        if not self.headers.get("Content-Type", "").lower().startswith("application/json"):
            raise ValueError("JSON content type is required")
        length = integer(self.headers.get("Content-Length", "0"), 1, 65536)
        data = json.loads(self.rfile.read(length))
        if not isinstance(data, dict):
            raise ValueError("Expected a JSON object")
        return data

    def do_GET(self):
        if not self.local_peer():
            return self.reply(403, {"error": "LAN access only"})
        path = urlsplit(self.path).path
        if path in ("/", "/index.html", "/app.js", "/style.css"):
            name = "index.html" if path in ("/", "/index.html") else path[1:]
            data = (STATIC / name).read_bytes()
            content_type = {"index.html": "text/html", "app.js": "text/javascript", "style.css": "text/css"}[name]
            self.send_response(200); self.headers_common()
            self.send_header("Content-Type", content_type + "; charset=utf-8")
            self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
            return
        session = self.session()
        if not session:
            return self.reply(401, {"error": "Sign in required"})
        try:
            if path == "/api/session":
                return self.reply(200, {"username": SETTINGS["username"], "csrf": session[1]})
            if path == "/api/servers":
                proc = processes()
                with ThreadPoolExecutor(max_workers=3) as pool:
                    servers = list(pool.map(lambda k: server_status(k, proc), SERVERS))
                return self.reply(200, {"servers": servers})
            if path == "/api/bans":
                return self.reply(200, {"bans": read_bans()})
            if path == "/api/announcements":
                cfg = read_cfg(ANNOUNCEMENTS)
                return self.reply(200, {"settings": {key: cfg.get(key, "") for key in announcement_keys()}})
            if path.startswith("/api/settings/"):
                key = path.rsplit("/", 1)[-1]
                if key not in SERVERS: raise ValueError("Unknown server")
                return self.reply(200, {"settings": read_mode_settings(key)})
            return self.reply(404, {"error": "Not found"})
        except (ValueError, OSError, RuntimeError, json.JSONDecodeError, subprocess.SubprocessError) as exc:
            return self.reply(400, {"error": str(exc)})

    def do_POST(self):
        if not self.local_peer() or not self.same_origin():
            return self.reply(403, {"error": "LAN and same-origin requests only"})
        path = urlsplit(self.path).path
        try:
            data = self.body()
            if path == "/api/login":
                ip = self.client_address[0]; now = time.time()
                with SESSION_LOCK:
                    attempts = [x for x in ATTEMPTS.get(ip, []) if now - x < 300]
                    if len(attempts) >= 10:
                        ATTEMPTS[ip] = attempts
                        return self.reply(429, {"error": "Too many attempts. Try again later."})
                if not hmac.compare_digest(str(data.get("username", "")), SETTINGS["username"]) or not verify_password(data.get("password", "")):
                    with SESSION_LOCK: ATTEMPTS[ip] = attempts + [now]
                    return self.reply(401, {"error": "Invalid username or password"})
                token, csrf = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
                with SESSION_LOCK:
                    ATTEMPTS.pop(ip, None); SESSIONS[token] = (now + 28800, csrf)
                return self.reply(200, {"csrf": csrf}, f"isnipe_session={token}; Path=/; HttpOnly; SameSite=Strict; Max-Age=28800")
            session = self.session()
            if not session:
                return self.reply(401, {"error": "Sign in required"})
            if not hmac.compare_digest(self.headers.get("X-CSRF-Token", ""), session[1]):
                return self.reply(403, {"error": "Invalid request token"})
            if path == "/api/logout":
                with SESSION_LOCK: SESSIONS.pop(session[0], None)
                return self.reply(200, {"message": "Signed out"}, "isnipe_session=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0")
            if path == "/api/password":
                if not verify_password(data.get("current", "")):
                    raise ValueError("Current password is incorrect")
                password = data.get("new", "")
                if not isinstance(password, str) or len(password) < 12 or len(password) > 128:
                    raise ValueError("New password must be 12–128 characters")
                salt = secrets.token_bytes(16)
                with CONFIG_LOCK:
                    SETTINGS["password_salt"] = salt.hex()
                    SETTINGS["password_hash"] = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, 310000).hex()
                    atomic_write(SETTINGS_FILE, json.dumps(SETTINGS, indent=2) + "\n")
                    if CREDENTIALS_FILE.exists(): CREDENTIALS_FILE.unlink()
                with SESSION_LOCK:
                    SESSIONS.clear()
                return self.reply(200, {"message": "Password changed. Sign in again."}, "isnipe_session=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0")
            if path == "/api/announcements":
                failed = save_announcements(data)
                msg = "Saved and applied to running servers." if not failed else "Saved. Restart or reload these servers: " + ", ".join(failed)
                return self.reply(200, {"message": msg})
            if path.startswith("/api/settings/"):
                key = path.rsplit("/", 1)[-1]
                if key not in SERVERS: raise ValueError("Unknown server")
                save_mode_settings(key, data)
                return self.reply(200, {"message": "Saved. Restart this server to apply."})
            if path == "/api/server/action":
                key, action = data.get("server"), data.get("action")
                if key not in SERVERS or action not in ("start", "stop", "restart"):
                    raise ValueError("Unknown server or action")
                if action == "start": message = start_server(key)
                elif action == "stop": message = stop_server(key)
                else:
                    stop_server(key)
                    message = start_server(key)
                return self.reply(200, {"message": message})
            if path == "/api/announce":
                targets = data.get("servers")
                if not isinstance(targets, list) or not targets or any(k not in SERVERS for k in targets) or len(set(targets)) != len(targets):
                    raise ValueError("Select valid servers")
                text = config_text(data.get("message"), limit=200, allow_empty=False)
                results = {}
                for key in targets:
                    try:
                        answer = rcon(key, "isnipePanelSay " + text.encode("utf-8").hex())
                        results[key] = "sent" if "ISNIPE_PANEL_OK:" in answer else "not confirmed"
                    except OSError as exc:
                        results[key] = "failed: " + str(exc)
                return self.reply(200, {"results": results})
            if path == "/api/player/action":
                key, action, player = data.get("server"), data.get("action"), data.get("player")
                if key not in SERVERS or action not in ("kick", "ban") or not isinstance(player, dict):
                    raise ValueError("Invalid player action")
                slot = integer(player.get("slot"), 0, 17)
                guid = str(player.get("guid", ""))
                if not re.fullmatch(r"[0-9A-F]{16}", guid): raise ValueError("Invalid player identity")
                session_id, challenge = str(player.get("session", "")), str(player.get("challenge", ""))
                if not re.fullmatch(r"-?\d{1,11}", session_id) or not re.fullmatch(r"-?\d{1,11}", challenge):
                    raise ValueError("Invalid connection identity")
                command = "isnipePanelKick" if action == "kick" else "isnipePanelBan"
                answer = rcon(key, f"{command} {slot} {guid} {session_id} {challenge}")
                if "ISNIPE_PANEL_OK:" not in answer:
                    reason = answer.split("ISNIPE_PANEL_ERROR:", 1)[-1].strip() if "ISNIPE_PANEL_ERROR:" in answer else "Server did not confirm the action"
                    raise ValueError(reason)
                return self.reply(200, {"message": "Player " + ("banned" if action == "ban" else "kicked") + "."})
            if path == "/api/ban/remove":
                kind, value = data.get("kind"), str(data.get("value", ""))
                if kind == "guid":
                    if not re.fullmatch(r"[0-9A-Fa-f]{1,16}", value): raise ValueError("Invalid GUID")
                elif kind == "ip":
                    value = str(ipaddress.IPv4Address(value))
                else:
                    raise ValueError("Invalid ban type")
                before = read_bans()
                selected = "id" if kind == "guid" else "ip"
                if value.upper() not in [x.upper() for x in before[selected]]:
                    raise ValueError("Ban entry is no longer present")
                running = None
                for key in SERVERS:
                    try:
                        get_info(key); running = key; break
                    except OSError:
                        continue
                if running is None: raise ValueError("Start a server before removing a ban")
                rcon(running, f"unbanClient {kind} {value}")
                after = read_bans()
                if value.upper() in [x.upper() for x in after[selected]]:
                    raise RuntimeError("The server did not remove the ban")
                return self.reply(200, {"message": "Ban entry removed."})
            return self.reply(404, {"error": "Not found"})
        except (ValueError, OSError, RuntimeError, json.JSONDecodeError, subprocess.SubprocessError) as exc:
            return self.reply(400, {"error": str(exc)})


if __name__ == "__main__":
    port = int(SETTINGS.get("listen_port", 8787))
    print(f"iSnipe control panel listening on 0.0.0.0:{port}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
