"""report.py: which log 42 shows, how much of it, how cold Bazel is, and the nudge.

The logs here are invented: an exercise that does not exist, so no fixture
holds a real exercise's hint or expected output.
"""

import hashlib
import os
import subprocess
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

    def test_a_function_of_a_library_is_its_own_prefix(self):
        b = self.run_bep()
        # first_red names a label of its own for one function's red (a
        # function can be a prefix of another, ft_one of ft_one_more, which
        # no prefix tells apart); this is the reading where it names none.
        for label, layer in (("//course/lib:ex00_ft_one_valgrind", "valgrind"),
                             ("//course/lib:ex00_ft_two_output", "output"),
                             ("//course/lib:ex00_norm", "norm")):
            b.selected.append(label)
            b.tags[label] = [layer, "ex00"]
            b.status[label] = "FAILED"
            b.logs[label] = "/l/" + layer
        nxt = ("rigour", "//course/lib", "ex00 ft_one", "-")
        self.assertEqual(report.pick_label(nxt, b), "//course/lib:ex00_ft_one_valgrind")
        nxt = ("ko", "//course/lib", "ex00", "-")
        self.assertEqual(report.pick_label(nxt, b), "//course/lib:ex00_norm")

    def test_a_library_own_red_shows_its_own_log(self):
        # A red of the library as a whole (no function) in the rigour bucket,
        # beside a function's: every function test's name begins ex00_ too,
        # and sorts first, so with no label from first_red the log shown under
        # the library's line was the function's. first_red.sh itself, over a
        # toy library, names the label 42 picks.
        lib = "//course/lib"
        reds = ((lib + ":ex00_ft_one_diff", "diff"), (lib + ":ex00_symbols", "symbols"))
        with tempfile.TemporaryDirectory() as d:
            write(os.path.join(d, "course", "lib", "BUILD.bazel"),
                  'subject(\n    grader = "both",\n    group = False,\n    exercises = {\n'
                  '        "00": exercise(page = 1, dir = None, files = ["Makefile"], allowed = [],\n'
                  '            functions = {\n                "ft_one": [],\n            }),\n'
                  '    },\n)\n')
            summary = os.path.join(d, "summary.log")
            write(summary, "".join("%s  FAILED in 0.1s\n" % l for l, _ in reds))
            nxt_path = os.path.join(d, "next.tsv")
            with open(summary, "rb") as f:
                subprocess.run(["sh", os.path.join(common.WS, "tools", "first_red.sh"), "--next", nxt_path],
                               cwd=d, stdin=f, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            nxt = report.read_next(nxt_path)
        self.assertEqual(nxt[:3], ("rigour", lib, "ex00"))
        b = bazel.Bep()
        for label, layer in reds:
            b.selected.append(label)
            b.tags[label] = [layer, "ex00"]
            b.status[label] = "FAILED"
            b.logs[label] = "/l/" + layer
        self.assertEqual(report.pick_label(nxt, b), lib + ":ex00_symbols")

    def test_a_library_that_does_not_build_shows_the_stand_in_log(self):
        # first_red names no label for the build bucket, and a library's
        # exercise prefix (ex00_) matches every red of it: with no compile or
        # files test red -- a link failure on one function, which the compile
        # layers never see -- 42 showed whatever red sorted first, another
        # function's wrong-output table or the Makefile's rules, under one
        # function's DOES NOT BUILD line (V233). The stand-in's own log is
        # what that line quotes. first_red.sh itself, over a toy library,
        # files the bucket; the marks are read from tools/standin.sh.
        lib = "//course/lib"
        marks = subprocess.run(
            ["sh", "-c", '. "$1"; printf "%s\\n%s" "$STANDIN_MARK" "$NOTURNIN_MARK"', "sh",
             os.path.join(common.WS, "tools", "standin.sh")],
            stdout=subprocess.PIPE, check=True, universal_newlines=True).stdout.split("\n")
        standin = "%s\nYOUR CODE DID NOT BUILD\ncourse/lib/deliverable/ft_zeta.c:3:1: error: toy\n" % marks[0]
        noturnin = "%sthe toy library has no ft_zeta.c\n" % marks[1]
        wrong = " CASE | EXPECTED | GOT | STATUS\n x    | 1        | 2   | FAIL <\n"
        rules = "ex00_build_rules: the toy Makefile has no clean rule\n"
        member = (lib + ":ex00_ft_zeta_output", "output")

        def pick(reds, body):
            with tempfile.TemporaryDirectory() as d:
                write(os.path.join(d, "course", "lib", "BUILD.bazel"),
                      'subject(\n    grader = "both",\n    group = False,\n    exercises = {\n'
                      '        "00": exercise(page = 1, dir = None, files = ["Makefile"], allowed = [],\n'
                      '            functions = {\n                "ft_alpha": [],\n                "ft_zeta": [],\n'
                      '            }),\n    },\n)\n')
                b = bazel.Bep()
                summary = ""
                for label, layer, text in reds + [member + (body,)]:
                    path = os.path.join(d, "logs", label.split(":")[1], "test.log")
                    write(path, text)
                    summary += "%s  FAILED in 0.1s\n  %s\n" % (label, path)
                    b.selected.append(label)
                    b.tags[label] = [layer, "ex00"]
                    b.status[label] = "FAILED"
                    b.logs[label] = path
                write(os.path.join(d, "summary.log"), summary)
                nxt_path = os.path.join(d, "next.tsv")
                with open(os.path.join(d, "summary.log"), "rb") as f:
                    subprocess.run(["sh", os.path.join(common.WS, "tools", "first_red.sh"), "--next", nxt_path],
                                   cwd=d, stdin=f, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
                nxt = report.read_next(nxt_path)
                self.assertEqual(nxt, ("build", lib, "ex00", "-"))
                return report.pick_label(nxt, b)
        # Another function's wrong answer, which sorts first by name.
        self.assertEqual(pick([(lib + ":ex00_ft_alpha_output", "output", wrong)], standin), member[0])
        # A test of the whole library that sorts first.
        self.assertEqual(pick([(lib + ":ex00_build_rules", "output", rules)], standin), member[0])
        # A file not turned in is the same news.
        self.assertEqual(pick([(lib + ":ex00_build_rules", "output", rules)], noturnin), member[0])
        # A red compile test still quotes the compiler most fully, and wins.
        self.assertEqual(pick([(lib + ":ex00_ft_alpha_output", "output", wrong),
                               (lib + ":ex00_compile_gcc", "compile", "toy compiler words\n")], standin),
                         lib + ":ex00_compile_gcc")

    def test_a_test_program_that_does_not_build_shows_its_log(self):
        # A test that builds its own test program against the turn-in and
        # could not (tools/header_check.sh) says so with runner_lib.sh's
        # build mark; first_red files it under DOES NOT BUILD when the
        # exercise is written, and its log is the one that quotes the
        # compiler. With the compile layer green, another red that sorts
        # first by name (here a made-up _forbidden) was shown in its place.
        mod = "//course/hdr"
        build = subprocess.run(
            ["sh", "-c", 'RL_NAME=test_report; . "$1"; printf "%s" "$RL_BUILD_MARK"', "sh",
             os.path.join(common.WS, "tools", "runner_lib.sh")],
            stdout=subprocess.PIPE, check=True, universal_newlines=True).stdout
        self.assertTrue(build)
        header = ("header_check: FAIL — the toy test program does not build.\n\n%s\n\n"
                  "  toy_main.c:(.text+0x15): undefined reference to `sf_toy_helper'\n" % build)
        reds = [(mod + ":ex00_forbidden", "forbidden", "toy: a call it did not allow\n"),
                (mod + ":ex00_output", "output", header)]
        stamp = "/* %s */\n" % ("*" * 74)
        h42 = stamp + "".join("/*%76s*/\n" % "" for _ in range(9)) + stamp
        with tempfile.TemporaryDirectory() as d:
            write(os.path.join(d, "course", "hdr", "BUILD.bazel"),
                  'subject(\n    grader = "moulinette",\n    group = False,\n    exercises = {\n'
                  '        "00": exercise(page = 1, dir = "ex00/", files = [], allowed = None),\n'
                  '    },\n)\n')
            write(os.path.join(d, "course", "hdr", "deliverable", "ex00", "sf_toy.h"),
                  h42 + "#ifndef SF_TOY_H\n# define SF_TOY_H\n\nint\tsf_toy_helper(int n);\n\n#endif\n")
            b = bazel.Bep()
            summary = ""
            for label, layer, text in reds:
                path = os.path.join(d, "logs", label.split(":")[1], "test.log")
                write(path, text)
                summary += "%s  FAILED in 0.1s\n  %s\n" % (label, path)
                b.selected.append(label)
                b.tags[label] = [layer, "ex00"]
                b.status[label] = "FAILED"
                b.logs[label] = path
            write(os.path.join(d, "summary.log"), summary)
            nxt_path = os.path.join(d, "next.tsv")
            with open(os.path.join(d, "summary.log"), "rb") as f:
                subprocess.run(["sh", os.path.join(common.WS, "tools", "first_red.sh"), "--next", nxt_path],
                               cwd=d, stdin=f, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            nxt = report.read_next(nxt_path)
            self.assertEqual(nxt, ("build", mod, "ex00", "-"))
            self.assertEqual(report.pick_label(nxt, b), mod + ":ex00_output")

    def test_an_unreadable_log_is_no_stand_in(self):
        # Ranked by name as before: a log that is not on disk says nothing.
        b = bazel.Bep()
        for label in ("//course/proj:ex07_output", "//course/proj:ex07_issued"):
            b.selected.append(label)
            b.tags[label] = ["output", "ex07"]
            b.status[label] = "FAILED"
            b.logs[label] = "/nonexistent/" + label.split(":")[1]
        self.assertEqual(report.pick_label(("build", "//course/proj", "ex07", "-"), b),
                         "//course/proj:ex07_issued")

    def test_the_clue_word_of_a_function_is_the_function(self):
        self.assertEqual(report.clue_word("ex00 ft_one"), "ft_one")
        self.assertEqual(report.clue_word("ex07"), "ex07")

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
        self.addCleanup(self.tmp.cleanup)
        self.root = os.path.join(self.tmp.name, "root")
        self.ws = os.path.join(self.tmp.name, "ws")
        os.makedirs(self.ws)

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
