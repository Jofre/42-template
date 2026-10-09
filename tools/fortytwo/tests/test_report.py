"""report.py: which log 42 shows, how much of it, how cold Bazel is, and the nudge.

The logs here are invented: an exercise that does not exist, so no fixture
holds a real exercise's hint or expected output.
"""

import hashlib
import os
import tempfile
import time
import unittest

import common  # noqa: F401
import bazel
import report

LOG = """exec ${PAGER:-/usr/bin/less} "$0" || exit 1
Executing tests from //course/proj:ex07_output
-----------------------------------------------------------------------------
 CASE   | EXPECTED | GOT       | STATUS
 -------+----------+-----------+-------
 line 1 | 7$       | (no line) | FAIL <
 RESULT: FAIL  (0/1 passed, 1 failed)
 --------------------------------------------------
 HINTS:
   * What does your program print when it is given nothing at all?
 --------------------------------------------------
 (2 more hidden hints: run with --test_env=CLUE_MODE=all)


"""


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


class LogBody(unittest.TestCase):
    def test_bazels_three_lines_go_the_runners_stay_verbatim(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "test.log")
            write(p, LOG)
            lines, more = report.log_body(p)
            self.assertEqual(more, 0)
            self.assertEqual(lines[0], " CASE   | EXPECTED | GOT       | STATUS")
            self.assertEqual(lines[-1], " (2 more hidden hints: run with --test_env=CLUE_MODE=all)")

    def test_a_log_without_bazels_lines_is_kept_whole(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "test.log")
            write(p, "first\nsecond\n")
            self.assertEqual(report.log_body(p), (["first", "second"], 0))

    def test_the_cap_counts_what_it_left_out(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "test.log")
            write(p, "".join("line %d\n" % i for i in range(100)))
            lines, more = report.log_body(p)
            self.assertEqual((len(lines), more), (report.LOG_CAP, 100 - report.LOG_CAP))
            self.assertEqual(lines[-1], "line %d" % (report.LOG_CAP - 1))


class Next(unittest.TestCase):
    def run_bep(self):
        b = bazel.Bep()
        rows = (
            ("//course/proj:ex07_output", ["output", "ex07"], "FAILED", "/l/out"),
            ("//course/proj:ex07_norm", ["norm", "ex07"], "FAILED", "/l/norm"),
            ("//course/proj:ex07_files", ["files", "ex07"], "PASSED", "/l/files"),
            ("//course/proj:ex08_output", ["output", "ex08"], "FAILED", "/l/out8"),
        )
        for label, tags, status, log in rows:
            b.selected.append(label)
            b.tags[label] = tags
            b.status[label] = status
            b.logs[label] = log
        return b

    def test_a_named_label_is_the_one(self):
        self.assertEqual(report.pick_label(("work", "//course/proj", "ex07", "//x:y"), self.run_bep()), "//x:y")

    def test_ko_prefers_a_layer_a_stub_passes(self):
        nxt = ("ko", "//course/proj", "ex07", "-")
        self.assertEqual(report.pick_label(nxt, self.run_bep()), "//course/proj:ex07_norm")

    def test_otherwise_the_first_red_of_that_exercise(self):
        nxt = ("build", "//course/proj", "ex08", "-")
        self.assertEqual(report.pick_label(nxt, self.run_bep()), "//course/proj:ex08_output")
        nxt = ("build", "//course/proj", "ex09", "-")
        self.assertEqual(report.pick_label(nxt, self.run_bep()), None)

    def test_a_build_failure_shows_the_compilers_log_whatever_the_order(self):
        for order in (("forbidden", "compile_gcc", "output"), ("output", "compile_gcc", "forbidden")):
            b = bazel.Bep()
            for layer in order:
                label = "//course/proj:ex09_" + layer
                b.selected.append(label)
                b.tags[label] = [layer.split("_")[0], "ex09"]
                b.status[label] = "FAILED"
                b.logs[label] = "/l/" + layer
            nxt = ("build", "//course/proj", "ex09", "-")
            self.assertEqual(report.pick_label(nxt, b), "//course/proj:ex09_compile_gcc", order)

    def test_ex1_is_not_ex10(self):
        b = self.run_bep()
        b.selected.append("//course/proj:ex070_output")
        b.status["//course/proj:ex070_output"] = "FAILED"
        b.logs["//course/proj:ex070_output"] = "/l/x"
        nxt = ("build", "//course/proj", "ex07", "-")
        # ex070_output sorts before ex07's; the pick is ex07's, by name.
        self.assertEqual(report.pick_label(nxt, b), "//course/proj:ex07_norm")

    def test_read_next(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "next.tsv")
            write(p, "work\t//course/proj\tex07\t//course/proj:ex07_output\n")
            self.assertEqual(report.read_next(p), ("work", "//course/proj", "ex07", "//course/proj:ex07_output"))
            write(p, "")
            self.assertEqual(report.read_next(p), None)
            self.assertEqual(report.read_next(os.path.join(d, "none")), None)


class Coldness(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = os.path.join(self.tmp.name, "root")
        self.ws = os.path.join(self.tmp.name, "ws")
        os.makedirs(self.ws)

    def tearDown(self):
        self.tmp.cleanup()

    def test_the_output_base_is_bazels_md5_of_the_checkout(self):
        self.assertEqual(report.output_base(self.ws, "/r"),
                         "/r/" + hashlib.md5(os.path.realpath(self.ws).encode()).hexdigest())

    def test_machine_checkout_server_warm(self):
        self.assertEqual(report.coldness(self.ws, root=self.root), "machine")
        os.makedirs(os.path.join(self.root, "cache", "repos", "v1"))
        self.assertEqual(report.coldness(self.ws, root=self.root), "machine")
        write(os.path.join(self.root, "cache", "repos", "v1", "content_addressable", "x"), "")
        self.assertEqual(report.coldness(self.ws, root=self.root), "checkout")
        base = report.output_base(self.ws, self.root)
        os.makedirs(os.path.join(base, "server"))
        self.assertEqual(report.coldness(self.ws, root=self.root), "server")
        write(os.path.join(base, "server", "server.pid.txt"), "999999999\n")
        self.assertEqual(report.coldness(self.ws, root=self.root), "server")
        write(os.path.join(base, "server", "server.pid.txt"), "%d\n" % os.getpid())
        self.assertEqual(report.coldness(self.ws, root=self.root), None)


class Nudge(unittest.TestCase):
    def test_once_a_week(self):
        with tempfile.TemporaryDirectory() as d:
            state = os.path.join(d, "state")
            now = time.time()
            self.assertTrue(report.nudge_due(state, now))
            self.assertFalse(report.nudge_due(state, now + 3600))
            self.assertTrue(report.nudge_due(state, now + report.NUDGE_EVERY + 60))

    def test_the_nudge_is_a_sentence_about_peers(self):
        self.assertIn("peer", report.NUDGE)
        self.assertLessEqual(len(report.NUDGE) + 2, 110)


if __name__ == "__main__":
    unittest.main()
