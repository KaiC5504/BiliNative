# /// script
# requires-python = ">=3.12"
# dependencies = ["zeroconf"]
# ///
"""Receives BiliNative's dev logs over Wi-Fi and writes them to logs/<date>/<session>.jsonl."""
import argparse
import datetime as dt
import json
import pathlib
import socket
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = pathlib.Path(__file__).resolve().parent.parent
SERVICE_TYPE = "_bilinative-log._tcp.local."
COLORS = {"debug": "\033[90m", "info": "\033[0m", "warn": "\033[33m", "error": "\033[31m"}
RESET = "\033[0m"


def lan_addresses():
    addresses = set()
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            # connect() on UDP sends nothing; it only picks the outbound interface.
            probe.connect(("192.0.2.1", 9))
            addresses.add(probe.getsockname()[0])
    except OSError:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            addresses.add(info[4][0])
    except OSError:
        pass
    return sorted(a for a in addresses if not a.startswith("127."))


def summarize(event):
    stamp = dt.datetime.fromtimestamp(event.get("t", 0)).strftime("%H:%M:%S.%f")[:-3]
    level = event.get("level", "info")
    fields = " ".join(f"{key}={value}" for key, value in sorted(event.get("f", {}).items()))
    return f"{COLORS.get(level, '')}{stamp} {level:<5} {event.get('cat', '?'):<6} {event.get('msg', '')} {fields}{RESET}"


class LogStore:
    def __init__(self, root):
        self.root = pathlib.Path(root)
        self.lock = threading.Lock()

    def append(self, events):
        day = dt.date.today().isoformat()
        with self.lock:
            for event in events:
                session = "".join(c for c in str(event.get("session", "unknown")) if c.isalnum()) or "unknown"
                folder = self.root / day
                folder.mkdir(parents=True, exist_ok=True)
                with open(folder / f"{session}.jsonl", "a", encoding="utf-8") as handle:
                    handle.write(json.dumps(event, ensure_ascii=False) + "\n")


def make_handler(store, quiet):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == "/health":
                self._reply(200, b"ok")
            else:
                self._reply(404, b"not found")

        def do_POST(self):
            if self.path != "/logs":
                self._reply(404, b"not found")
                return
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length).decode("utf-8", errors="replace")
            events = []
            for line in body.splitlines():
                line = line.strip()
                if not line:
                    continue
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    events.append({"level": "warn", "cat": "logserver", "msg": "unparsable line", "f": {"line": line[:200]}})
            store.append(events)
            if not quiet:
                for event in events:
                    print(summarize(event), flush=True)
            self._reply(200, b"ok")

        def _reply(self, status, body):
            self.send_response(status)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    return Handler


def make_server(port, root, quiet=False):
    return ThreadingHTTPServer(("0.0.0.0", port), make_handler(LogStore(root), quiet))


def advertise(port):
    from zeroconf import ServiceInfo, Zeroconf

    zeroconf = Zeroconf()
    addresses = [socket.inet_aton(address) for address in lan_addresses()]
    name = f"BiliNative log on {socket.gethostname()}.{SERVICE_TYPE}"
    info = ServiceInfo(SERVICE_TYPE, name, addresses=addresses, port=port, properties={"path": "/logs"})
    zeroconf.register_service(info)
    return zeroconf, info


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=47321)
    parser.add_argument("--no-bonjour", action="store_true")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()
    server = make_server(args.port, ROOT / "logs", args.quiet)
    print(f"Writing to {ROOT / 'logs'}")
    for address in lan_addresses():
        print(f"Phone: enter {address}:{args.port}")
    zeroconf = None
    if not args.no_bonjour:
        zeroconf, info = advertise(args.port)
        print("Advertised over Bonjour as", info.name)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        if zeroconf:
            zeroconf.unregister_all_services()
            zeroconf.close()
        server.server_close()


if __name__ == "__main__":
    sys.exit(main())
