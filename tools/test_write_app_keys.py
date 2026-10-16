import contextlib
import io
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import write_app_keys  # noqa: E402


class WriteAppKeysTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.out = pathlib.Path(self.tmp.name) / "Generated" / "AppKeys.swift"

    def run_main(self, env):
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            status = write_app_keys.main(str(self.out), env)
        return status, stdout.getvalue()

    def test_writes_masked_keys(self):
        status, stdout = self.run_main({"BILI_APP_KEYS": "k1:s1"})
        self.assertEqual(status, 0)
        self.assertIn('("k1", "s1")', self.out.read_text(encoding="utf-8"))
        lines = stdout.splitlines()
        self.assertEqual([line for line in lines if line.startswith("::add-mask::")], ["::add-mask::k1", "::add-mask::s1"])
        self.assertEqual(lines[:2], ["::add-mask::k1", "::add-mask::s1"])
        self.assertIn("app keys written", stdout)

    def test_missing_secret_writes_nil(self):
        for env in ({}, {"BILI_APP_KEYS": ""}, {"BILI_APP_KEYS": "  \n"}):
            with self.subTest(env=env):
                status, stdout = self.run_main(env)
                self.assertEqual(status, 0)
                self.assertIn("= nil", self.out.read_text(encoding="utf-8"))
                self.assertIn("::notice::", stdout)
                self.assertNotIn("::add-mask::", stdout)

    def test_malformed_secret_writes_nil_and_never_echoes_it(self):
        for value in ("nocolon", ":s1", "k1:", ":", "k1:s\x001", "k1:s\n::error::x"):
            with self.subTest(value=value):
                status, stdout = self.run_main({"BILI_APP_KEYS": value})
                self.assertEqual(status, 0)
                self.assertIn("= nil", self.out.read_text(encoding="utf-8"))
                self.assertIn("::notice::", stdout)
                self.assertNotIn("nocolon", stdout)
                self.assertNotIn("::add-mask::", stdout)

    def test_escapes_quotes(self):
        status, stdout = self.run_main({"BILI_APP_KEYS": 'k"1:s\\2"'})
        self.assertEqual(status, 0)
        self.assertIn(r'("k\"1", "s\\2\"")', self.out.read_text(encoding="utf-8"))
        # The log shows compile errors with the literal as written, so the escaped form is masked too.
        self.assertIn(r'::add-mask::k\"1', stdout)

    def test_only_the_first_colon_splits(self):
        self.run_main({"BILI_APP_KEYS": "k1:s:1"})
        self.assertIn('("k1", "s:1")', self.out.read_text(encoding="utf-8"))

    def test_surrounding_whitespace_is_ignored(self):
        self.run_main({"BILI_APP_KEYS": " k1:s1 \n"})
        self.assertIn('("k1", "s1")', self.out.read_text(encoding="utf-8"))
        self.run_main({"BILI_APP_KEYS": "k1 : s1"})
        self.assertIn('("k1", "s1")', self.out.read_text(encoding="utf-8"))

    def test_a_later_run_without_the_secret_overwrites_the_keys(self):
        self.run_main({"BILI_APP_KEYS": "k1:s1"})
        self.run_main({})
        text = self.out.read_text(encoding="utf-8")
        self.assertIn("= nil", text)
        self.assertNotIn("k1", text)


if __name__ == "__main__":
    unittest.main()
