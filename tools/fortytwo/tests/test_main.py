"""main.py: the registry, the help, and the command each subcommand would run (--dry-run).

A stand-in `bazel` sits first on PATH in every test here and writes down any
call: help, --version and --dry-run must never start Bazel.
"""

import ast
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

from common import WS, run42
import main
import workspace

C05 = "c-piscine/c-piscine-c-05"
EX03 = os.path.join(WS, C05, "tests", "ex03")
FIRST_RED = " 2>&1 | sh tools/first_red.sh"


class Env:
    """A HOME, a state folder and a stand-in bazel of its own, for one test."""

    def __init__(self):
        self.tmp = tempfile.mkdtemp()
        self.bin = os.path.join(self.tmp, "bin")
        os.makedirs(self.bin)
        self.calls = os.path.join(self.tmp, "calls")
        for name in ("bazel", "bazelisk"):
            p = os.path.join(self.bin, name)
            with open(p, "w") as f:
                f.write('#!/bin/sh\necho "$0 $*" >> "%s"\nexit 0\n' % self.calls)
            os.chmod(p, 0o755)
        self.environ = {"PATH": self.bin + os.pathsep + os.environ.get("PATH", ""),
                        "HOME": self.tmp, "XDG_STATE_HOME": os.path.join(self.tmp, "state"),
                        "SUBMIT_GATE": "basic"}

    def called(self):
        try:
            with open(self.calls) as f:
                return f.read()
        except OSError:
            return ""

    def close(self):
        shutil.rmtree(self.tmp, ignore_errors=True)


class Case(unittest.TestCase):
    def setUp(self):
        self.env = Env()

    def tearDown(self):
        self.assertEqual(self.env.called(), "", "Bazel was started")
        self.env.close()

    def run42(self, argv, cwd=WS):
        return run42(argv, cwd, self.env.environ)

    def dry(self, argv, cwd=EX03):
        argv = list(argv)
        cut = argv.index("--") if "--" in argv else len(argv)  # after --, words go to the tool
        rc, out, err = self.run42(argv[:cut] + ["--dry-run"] + argv[cut:], cwd)
        self.assertEqual(rc, 0, err)
        return [l[2:] for l in out.splitlines() if l.startswith("$ ")]


class Registry(unittest.TestCase):
    def test_every_command_has_a_row_and_every_row_a_command(self):
        rows = main.load_registry(WS)
        named = {r["command"] for r in rows if r["audience"] in ("student", "maintainer")}
        self.assertEqual(named, set(main.COMMANDS))
        sub = next(a for a in main.parser()._actions if a.dest == "command")
        self.assertEqual(set(sub.choices) - {"help"}, set(main.COMMANDS))
        for r in rows:
            self.assertIn(r["audience"], ("student", "maintainer", "internal"), r)
            self.assertEqual(r["command"] == "-", r["audience"] == "internal", r)
            self.assertTrue(r["text"].strip(), r)

    def floor(self):
        """The oldest python3 tools/42.sh lets run 42."""
        with open(os.path.join(WS, "tools", "42.sh"), encoding="utf-8") as f:
            m = re.search(r"sys\.exit\(sys\.version_info < \((\d+), (\d+)\)\)", f.read())
        self.assertIsNotNone(m, "tools/42.sh no longer checks the version of python3")
        return int(m.group(1)), int(m.group(2))

    def test_every_module_parses_at_the_floor_42_sh_checks(self):
        here = os.path.join(WS, "tools", "fortytwo")
        names = sorted(f for f in os.listdir(here) if f.endswith(".py"))
        self.assertIn("main.py", names)
        for name in names:
            with open(os.path.join(here, name), encoding="utf-8") as f:
                ast.parse(f.read(), name, feature_version=self.floor())

    def test_doctor_names_the_same_floor(self):
        import doctor

        class Said(list):
            def add(self, mark, text):
                self.append(text)
        said = Said()
        doctor.check_python(said)
        self.assertIn("needs %d.%d or later" % self.floor(), said[0])


class Help(Case):
    def test_bare_42_is_help_everywhere_and_fits_80_columns(self):
        for cwd in (WS, os.path.join(WS, C05), EX03):
            for argv in ([], ["help"], ["help", "--all"], ["-h"], ["test", "-h"], ["help", "submit"]):
                rc, out, err = self.run42(argv, cwd)
                self.assertEqual((rc, err), (0, ""), (argv, cwd))
                for line in out.splitlines():
                    self.assertLessEqual(len(line), 80, (argv, line))

    def test_help_test_names_every_flag_test_takes(self):
        # The triage says "Add --all", and docs/bazel.md teaches --fresh: both
        # were flags of `42 test` its own help never named.
        _, usage, _ = self.run42(["help"])
        _, detail, _ = self.run42(["help", "test"])
        for flag in ("--level", "--fresh", "--all"):
            self.assertIn(flag, [l for l in usage.splitlines() if l.startswith("  42 test ")][0])
            self.assertIn("    " + flag, detail)

    def test_the_here_line(self):
        rc, out, _ = self.run42([], EX03)
        self.assertIn("here: c-05 ex03, level basic (from SUBMIT_GATE).", out)
        rc, out, _ = self.run42([], WS)
        self.assertIn("here: no project", out)

    def test_help_all_adds_the_maintainer_rows(self):
        _, short, _ = self.run42(["help"])
        _, every, _ = self.run42(["help", "--all"])
        self.assertNotIn("42 selftest", short)
        self.assertIn("42 selftest", every)
        # An internal row is a target no command runs: help never offers it.
        for r in main.load_registry(WS):
            if r["audience"] == "internal":
                self.assertNotIn(r["runs"], every, r)
                self.assertNotIn("42 %s " % r["runs"].split(":")[-1], every, r)

    def test_version_and_unknown(self):
        rc, out, _ = self.run42(["--version"])
        self.assertEqual(rc, 0)
        self.assertTrue(out.startswith("42 " + main.VERSION))
        rc, _, err = self.run42(["frobnicate"])
        self.assertEqual(rc, 2)
        self.assertIn("42 help", err)

    def test_an_unknown_flag_names_the_help_of_its_command(self):
        # argparse reports a flag no command takes from the top parser, whose
        # prog is "42": it once sent everyone to `42 help 42`, which is no command.
        for argv, help_ in ((["submit", "--no-gate"], "`42 help submit`"),
                            (["test", "ex03", "--bogus"], "`42 help test`"),
                            (["--bogus"], "`42 help`")):
            rc, _, err = self.run42(argv)
            self.assertEqual(rc, 2, argv)
            self.assertIn(help_ + " says how to call it", err)
            self.assertNotIn("42 help 42", err)


class DryRun(Case):
    def test_test(self):
        ex03 = "bazel test //%s:ex03" % C05
        self.assertEqual(self.dry(["test"]), [ex03 + " --test_tag_filters=lvl_basic,-manual" + FIRST_RED])
        self.assertEqual(self.dry(["test", "norminette"]), [ex03 + " --test_tag_filters=norm,-manual" + FIRST_RED])
        self.assertEqual(self.dry(["test", "--level", "strict", "--fresh"]),
                         [ex03 + " --test_tag_filters=lvl_strict,-manual --nocache_test_results" + FIRST_RED])
        self.assertEqual(self.dry(["test", "--level", "complete"]), [ex03 + " --test_tag_filters=-manual" + FIRST_RED])
        self.assertEqual(self.dry(["test", "c-06"]),
                         ["bazel test //c-piscine/c-piscine-c-06/... --test_tag_filters=lvl_basic,-manual" + FIRST_RED])
        self.assertEqual(self.dry(["test", "//%s:ex03_output" % C05]), ["bazel test //%s:ex03_output" % C05 + FIRST_RED])

    def test_clues(self):
        self.assertEqual(self.dry(["clues", "2"]), [
            "bazel test //%s:ex03 --test_tag_filters=lvl_basic,-manual" % C05,
            "bazel test '<the labels that failed>' --test_env=CLUE_MODE=2"])

    def test_watch_prints_its_command_once_and_does_not_watch(self):
        import watch
        loop = watch.Watch.loop
        watch.Watch.loop = lambda self: (_ for _ in ()).throw(AssertionError("--dry-run started the watch loop"))
        try:
            self.assertEqual(self.dry(["watch"]),
                             ["bazel test //%s:ex03 --test_tag_filters=lvl_basic,-manual" % C05 + FIRST_RED])
        finally:
            watch.Watch.loop = loop

    def test_submit(self):
        self.assertEqual(self.dry(["submit"]), ["bazel run //tools:submit -- " + C05])
        self.assertEqual(self.dry(["submit", "c-06", "--level", "strict", "-n"]),
                         ["bazel run //tools:submit -- c-piscine/c-piscine-c-06 --gate-level strict -n"])
        self.assertEqual(self.dry(["submit", "--all", "-n"], WS), ["bazel run //tools:submit -- -n"])
        rc, _, err = self.run42(["submit", "--dry-run"], WS)
        self.assertEqual(rc, 2)
        self.assertIn("--all", err)

    def test_norm(self):
        self.assertEqual(self.dry(["norm"]), ["bazel test //%s:ex03 --test_tag_filters=norm,-manual" % C05 + FIRST_RED])
        f = next(n for n in sorted(os.listdir(EX03)) if os.path.isfile(os.path.join(EX03, n)))
        self.assertEqual(self.dry(["norm", f, "--", "-R", "CheckDefine"]),
                         ["bazel run //tools:norminette -- -R CheckDefine " + os.path.join(EX03, f)])
        rc, _, err = self.run42(["norm", "no-such-file.c", "--dry-run"], EX03)
        self.assertEqual(rc, 2)

    def test_generate(self):
        self.assertEqual(self.dry(["generate"], WS), ["bazel run //tools:generate"])
        self.assertEqual(self.dry(["generate", "shell-00"]), ["bazel run //c-piscine/c-piscine-shell-00:generate"])
        rc, _, err = self.run42(["generate", "--dry-run"], EX03)
        self.assertEqual(rc, 2)
        self.assertIn("shell-00", err)

    def test_header(self):
        self.assertEqual(self.dry(["header", "ft_x.c"]), ["bazel run //tools:gen_header -- ft_x.c"])
        self.assertEqual(self.dry(["header", "--reset", "-n"]),
                         ["bazel run //tools:reset_headers -- -n %s/tests/ex03" % C05])
        self.assertEqual(self.dry(["header", "--reset", "--all"], WS), ["bazel run //tools:reset_headers"])
        rc, _, _ = self.run42(["header", "--reset", "--dry-run"], WS)
        self.assertEqual(rc, 2)

    def test_the_one_target_commands(self):
        self.assertEqual(self.dry(["init", "--login", "jdoe"]), ["bazel run //tools:init -- --login jdoe"])
        self.assertEqual(self.dry(["stop"]), ["bazel shutdown"])
        self.assertEqual(self.dry(["selftest"]), ["bazel test //tools/tests:fortytwo_test"])
        self.assertEqual(self.dry(["selftest", "--harness"]), ["bazel test //tools/tests:fortytwo_test //tools/..."])
        self.assertEqual(self.dry(["conventions"]), ["bazel run //tools:conventions"])
        self.assertEqual(self.dry(["stubcheck"]), ["bazel run //tools:stub_check -- " + C05])
        self.assertEqual(self.dry(["stubcheck"], WS), ["bazel run //tools:stub_check"])

    def test_test_at_the_root_names_the_projects(self):
        rc, _, err = self.run42(["test", "--dry-run"], WS)
        self.assertEqual(rc, 2)
        self.assertIn("c-05", err)
        rc, _, err = self.run42(["test", "--level", "strct", "--dry-run"], EX03)
        self.assertEqual(rc, 2)
        self.assertIn("strct", err)


class Notices(unittest.TestCase):
    """A file that changed during a run: each on a line of its own, the prose within 80 columns."""

    C00 = "c-piscine/c-piscine-c-00/deliverable"
    ONE = [os.path.join(WS, C00, "ex00", "ft_putchar.c")]
    TWO = [os.path.join(WS, C00, "ex01", "ft_print_alphabet.c")] + ONE

    def check(self, text, paths):
        lines = text.splitlines()
        named = ["      " + os.path.relpath(p, WS) for p in sorted(paths)]
        self.assertEqual(lines[1:1 + len(paths)], named)
        for line in lines[:1] + lines[1 + len(paths):]:
            self.assertLessEqual(len(line), 80, line)
        return " ".join(l.strip() for l in lines)

    def test_a_raced_run(self):
        self.assertIn("This file changed while the tests ran:", self.check(main.raced_notice(WS, self.ONE), self.ONE))
        said = self.check(main.raced_notice(WS, self.TWO), self.TWO)
        self.assertIn("These files changed while the tests ran:", said)
        self.assertIn("42 will not trust the cache for it.", said)

    def test_a_repair(self):
        c00 = workspace.Workspace(WS, WS).project_named("c-00")
        said = self.check(main.repair_notice(WS, self.ONE, c00, ["ex00"]), self.ONE)
        self.assertIn("42 deletes what Bazel built for c-00 and runs ex00 again without the cache, then the rest.",
                      said)
        said = self.check(main.repair_notice(WS, self.TWO, c00, []), self.TWO)
        self.assertIn("so what Bazel built from them,", said)
        self.assertIn("runs these tests again, without the cache.", said)


class Entry(unittest.TestCase):
    """main.py as tools/42.sh starts it: python3 -I, its folder found by itself."""

    def test_python_dash_I(self):
        env = Env()
        try:
            e = dict(env.environ, FT_WS=WS, FT_CWD=EX03)
            r = subprocess.run([sys.executable, "-I", os.path.join(WS, "tools", "fortytwo", "main.py")],
                               cwd=env.tmp, env=e, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               universal_newlines=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("c-05 ex03", r.stdout)
            self.assertEqual(env.called(), "")
        finally:
            env.close()


if __name__ == "__main__":
    unittest.main()
