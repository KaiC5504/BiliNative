import io
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

    def post(self, body, port=None):
        request = urllib.request.Request(
            f"http://127.0.0.1:{port or self.port}/logs",
            data=body.encode("utf-8"),
            method="POST",
            headers={"Content-Type": "application/x-ndjson"},
        )
        with urllib.request.urlopen(request, timeout=5) as response:
            return response.status

    def serve(self, quiet):
        server = logserver.make_server(0, self.tmp.name, quiet=quiet)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        return server.server_address[1]

    def session_lines(self, name):
        files = list(pathlib.Path(self.tmp.name).rglob(f"{name}.jsonl"))
        self.assertEqual(len(files), 1)
        return [json.loads(line) for line in files[0].read_text(encoding="utf-8").split("\n") if line]

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

    def test_non_ascii_survives_a_cp1252_console(self):
        port = self.serve(quiet=False)
        event = {"t": 1, "seq": 1, "session": "zh", "level": "info", "cat": "app", "msg": "播放开始", "f": {"标题": "测试"}}
        console = io.TextIOWrapper(io.BytesIO(), encoding="cp1252", errors="strict")
        original, sys.stdout = sys.stdout, console
        try:
            self.assertEqual(self.post(json.dumps(event, ensure_ascii=False) + "\n", port), 200)
        finally:
            sys.stdout = original
        self.assertEqual([line["msg"] for line in self.session_lines("zh")], ["播放开始"])

    def test_unicode_line_separators_do_not_split_an_event(self):
        event = {"t": 1, "seq": 1, "session": "sep", "level": "info", "cat": "app", "msg": "a b c\x85d", "f": {}}
        self.assertEqual(self.post(json.dumps(event, ensure_ascii=False) + "\n"), 200)
        self.assertEqual([line["msg"] for line in self.session_lines("sep")], ["a b c\x85d"])

    def test_non_object_json_lines_do_not_lose_the_batch(self):
        good = {"t": 1, "seq": 1, "session": "batch", "level": "info", "cat": "app", "msg": "ok", "f": {}}
        body = "\n".join([json.dumps(good), "123", "[1]", "null", json.dumps(good)]) + "\n"
        self.assertEqual(self.post(body), 200)
        self.assertEqual(len(self.session_lines("batch")), 2)
        self.assertEqual(len(self.session_lines("unknown")), 3)

    def test_malformed_field_types_do_not_break_the_reply(self):
        event = {"t": "yesterday", "seq": 1, "session": "types", "level": ["x"], "cat": {"a": 1}, "msg": "m", "f": "oops"}
        port = self.serve(quiet=False)
        original, sys.stdout = sys.stdout, io.StringIO()
        try:
            self.assertEqual(self.post(json.dumps(event) + "\n", port), 200)
        finally:
            sys.stdout = original
        self.assertEqual(len(self.session_lines("types")), 1)

    def test_summarize_tolerates_bad_values(self):
        logserver.summarize({"t": 1e300, "f": "x", "level": ["y"], "cat": None})
        logserver.summarize({"t": float("nan"), "f": {"k": {"nested": 1}}})

    def test_overlong_session_id_is_capped(self):
        event = {"t": 1, "seq": 1, "session": "s" * 300, "level": "info", "cat": "app", "msg": "long", "f": {}}
        self.assertEqual(self.post(json.dumps(event) + "\n"), 200)
        self.assertEqual(len(list(pathlib.Path(self.tmp.name).rglob("s" * 64 + ".jsonl"))), 1)


if __name__ == "__main__":
    unittest.main()
