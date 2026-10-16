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
SESSION_MAX = 64


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


def stamp_of(t):
    if isinstance(t, bool) or not isinstance(t, (int, float)):
        t = 0
    try:
        return dt.datetime.fromtimestamp(t).strftime("%H:%M:%S.%f")[:-3]
    except (OverflowError, OSError, ValueError):
        return "--:--:--.---"


def summarize(event):
    level = str(event.get("level", "info"))
    fields = event.get("f")
    if isinstance(fields, dict):
        fields = " ".join(f"{key}={value}" for key, value in sorted(fields.items()))
    else:
        fields = ""
    return f"{COLORS.get(level, '')}{stamp_of(event.get('t'))} {level:<5} {str(event.get('cat', '?')):<6} {event.get('msg', '')} {fields}{RESET}"


def parse_line(line):
    try:
        event = json.loads(line)
    except (ValueError, RecursionError):
        event = None
    if isinstance(event, dict):
        return event
    return {"level": "warn", "cat": "logserver", "msg": "unparsable line", "f": {"line": line[:200]}}


class LogStore:
    def __init__(self, root):
        self.root = pathlib.Path(root)
        self.lock = threading.Lock()

    def append(self, events):
        day = dt.date.today().isoformat()
        with self.lock:
            for event in events:
                session = "".join(c for c in str(event.get("session", "unknown")) if c.isalnum())[:SESSION_MAX] or "unknown"
                folder = self.root / day
                try:
                    folder.mkdir(parents=True, exist_ok=True)
                    with open(folder / f"{session}.jsonl", "a", encoding="utf-8") as handle:
                        handle.write(json.dumps(event, ensure_ascii=False) + "\n")
                except OSError as error:
                    print(f"logserver: write failed: {type(error).__name__}", file=sys.stderr)


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
            # NetworkSink writes one JSON object per "\n"; str.splitlines would also break on U+2028, U+2029 and U+0085, which JSON leaves unescaped.
            events = [parse_line(line.strip()) for line in body.split("\n") if line.strip()]
            try:
                store.append(events)
            except Exception as error:
                print(f"logserver: store failed: {type(error).__name__}", file=sys.stderr)
            if not quiet:
                for event in events:
                    # The file is the record; a console that cannot show a line must not cost the reply.
                    try:
                        print(summarize(event), flush=True)
                    except (UnicodeError, OSError, ValueError):
                        pass
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
    # Windows consoles default to cp1252 when stdout is redirected, which cannot encode the Chinese UI text.
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
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
