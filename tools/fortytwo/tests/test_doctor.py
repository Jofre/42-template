"""doctor.py: what blocks, what it says on a cold checkout, and what it reads.

Bazel is a stand-in that writes down any call (test_main.Env): on a cold root
42 doctor must not start it, and --dry-run never does.
"""

import os
import re
import tempfile
import unittest
from unittest import mock

from common import WS, run42
import doctor
import report
from test_main import Env


class Run(unittest.TestCase):
    def setUp(self):
        self.env = Env()
        self.root = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.root.cleanup()
        self.env.close()

    def doctor(self, argv, environ=None, cold=True):
        # The servers this machine runs are not the test's: Proc covers the scan.
        patches = [mock.patch.object(report, "state_root", lambda ws, env=None: self.root.name),
                   mock.patch.object(doctor, "servers", lambda proc="/proc": [])]
        if not cold:
            patches.append(mock.patch.object(report, "coldness", lambda ws, env=None, root=None: None))
        for p in patches:
            p.start()
        try:
            return run42(["doctor"] + argv, WS, environ or self.env.environ)
        finally:
            for p in patches:
                p.stop()

    def test_no_bazel_is_the_one_blocker(self):
        rc, out, err = self.doctor(["--dry-run"], dict(self.env.environ, PATH="/usr/bin:/bin"))
        self.assertEqual(rc, 1, out + err)
        self.assertIn("BLOCK no `bazel` on PATH", out)
        self.assertIn("Not ready: 1 blocker(s) above.", out)
        self.assertNotIn("env_drift", out)

    def test_a_cold_root_is_not_compared_and_says_why(self):
        rc, out, err = self.doctor([])
        self.assertEqual(rc, 0, out + err)
        self.assertIn("has not run on this machine yet", out)
        self.assertIn("about 700 MB", out)
        self.assertIn("42 doctor --drift", out)
        self.assertEqual(self.env.called(), "", "a cold root started Bazel")

    def test_a_warm_root_is_compared(self):
        rc, out, _ = self.doctor(["--dry-run"], cold=False)
        self.assertIn("$ bazel run //tools:env_drift", out)
        self.assertNotIn("--drift", out)

    def test_drift_on_a_cold_root_and_the_report(self):
        rc, out, _ = self.doctor(["--drift", "--report", "--dry-run"])
        self.assertIn("$ bazel run //tools:env_drift", out)
        self.assertIn("$ sh tools/env-audit.sh", out)
        self.assertEqual(self.env.called(), "")

    def test_the_prose_fits_80_columns(self):
        # A path cannot be wrapped, so it is measured as one character.
        _, out, _ = self.doctor([])
        for line in out.splitlines():
            self.assertLessEqual(len(re.sub(r"/\S+", "/", line)), 80, line)


class Shim(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.TemporaryDirectory()
        self.c = doctor.Check()

    def tearDown(self):
        self.d.cleanup()

    def put(self, text):
        p = os.path.join(self.d.name, "42")
        with open(p, "w") as f:
            f.write(text)
        os.chmod(p, 0o755)

    def test_install_writes_the_mark_doctor_reads(self):
        with open(os.path.join(WS, "tools", "fortytwo", "install.sh"), encoding="utf-8") as f:
            self.assertIn("MARK='%s'" % doctor.MARK, f.read())

    def test_the_shim_and_where_it_falls_back(self):
        self.put("%s\nFALLBACK='/some/other/checkout'\n" % doctor.MARK)
        doctor.check_shim(self.c, WS, {"PATH": self.d.name})
        mark, text = self.c.rows[0]
        self.assertEqual(mark, "ok")
        self.assertIn("outside one, /some/other/checkout", text)

    def test_another_42(self):
        self.put("#!/bin/sh\necho hello\n")
        doctor.check_shim(self.c, WS, {"PATH": self.d.name})
        self.assertEqual(self.c.rows[0][0], "warn")
        self.assertIn("is not 42's shim", self.c.rows[0][1])

    def test_none(self):
        doctor.check_shim(self.c, WS, {"PATH": self.d.name})
        self.assertIn("no `42` on your PATH", self.c.rows[0][1])


class Proc(unittest.TestCase):
    """servers() and the memory row, on a /proc of fixture files."""

    def setUp(self):
        self.d = tempfile.TemporaryDirectory()
        p = self.d.name
        self.proc(100, b"/usr/lib/jvm/bin/java\0-jar\0/r/install/A-server.jar\0"
                       b"--output_base=/r/abc\0--workspace_directory=/ws/a\0", 1048576)
        # A shell whose command line names the jar is no server.
        self.proc(200, b"sh\0-c\0case $c in *A-server.jar*) echo;; esac\0", 2048)
        os.makedirs(os.path.join(p, "self"))
        with open(os.path.join(p, "meminfo"), "w") as f:
            f.write("MemTotal: 8388608 kB\nMemAvailable: 2097152 kB\n")

    def tearDown(self):
        self.d.cleanup()

    def proc(self, pid, cmdline, rss_kb):
        d = os.path.join(self.d.name, str(pid))
        os.makedirs(d)
        with open(os.path.join(d, "cmdline"), "wb") as f:
            f.write(cmdline)
        with open(os.path.join(d, "status"), "w") as f:
            f.write("Name:\tx\nVmRSS:\t %d kB\n" % rss_kb)

    def test_servers(self):
        self.assertEqual(doctor.servers(self.d.name), [(100, 2 ** 30, "/ws/a")])

    def test_this_checkout_and_another(self):
        c = doctor.Check()
        doctor.check_memory(c, "/ws/a", self.d.name)
        self.assertIn("2.0 GB available", c.rows[0][1])
        self.assertIn("pid 100, holds 1.0 GB (this checkout)", c.rows[0][1])
        self.assertNotIn("42 stop", c.rows[0][1])
        c = doctor.Check()
        doctor.check_memory(c, "/ws/b", self.d.name)
        self.assertIn("(/ws/a)", c.rows[0][1])
        self.assertIn("`42 stop` in a checkout", c.rows[0][1])


if __name__ == "__main__":
    unittest.main()
