import json
import pathlib
import sys
import tempfile
import threading
import unittest
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import logserver  # noqa: E402


class LogServerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.server = logserver.make_server(0, self.tmp.name, quiet=True)
        self.port = self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.tmp.cleanup()

    def post(self, body):
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.port}/logs",
            data=body.encode("utf-8"),
            method="POST",
            headers={"Content-Type": "application/x-ndjson"},
        )
        with urllib.request.urlopen(request, timeout=5) as response:
            return response.status

    def test_events_land_in_their_session_file(self):
        events = [
            {"t": 1760000000.5, "seq": 1, "session": "abc123", "level": "info", "cat": "engine", "msg": "piece", "f": {"bytes": 65536}},
            {"t": 1760000001, "seq": 2, "session": "abc123", "level": "warn", "cat": "api", "msg": "slow", "f": {}},
        ]
        self.assertEqual(self.post("\n".join(json.dumps(e) for e in events) + "\n"), 200)
        files = list(pathlib.Path(self.tmp.name).rglob("abc123.jsonl"))
        self.assertEqual(len(files), 1)
        lines = files[0].read_text(encoding="utf-8").splitlines()
        self.assertEqual([json.loads(line)["seq"] for line in lines], [1, 2])

    def test_unparsable_line_is_kept(self):
        self.assertEqual(self.post("not json\n"), 200)
        self.assertEqual(len(list(pathlib.Path(self.tmp.name).rglob("unknown.jsonl"))), 1)

    def test_health(self):
        with urllib.request.urlopen(f"http://127.0.0.1:{self.port}/health", timeout=5) as response:
            self.assertEqual(response.read(), b"ok")


if __name__ == "__main__":
    unittest.main()
