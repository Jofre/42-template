"""main.py: the registry, the help, and the command each subcommand would run (--dry-run).

A stand-in `bazel` sits first on PATH in every test here and writes down any
call: help, --version and --dry-run must never start Bazel.
"""

import ast
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
import urllib.parse
from unittest import mock

from common import WS, run42
import main
import workspace

C05 = "c-piscine/c-piscine-c-05"
EX03 = os.path.join(WS, C05, "tests", "ex03")
FIRST_RED = " 2>&1 | sh tools/first_red.sh"


def unreleased(text):
    """The lines of a module's source that make a folder its next statement does not release."""
    def makes(st):
        v = getattr(st, "value", None)
        f = v.func if isinstance(v, ast.Call) else None
        return ((isinstance(f, ast.Attribute) and f.attr in ("TemporaryDirectory", "mkdtemp"))
                or (isinstance(f, ast.Name) and f.id == "Env"))

    def calls(stmts, names):
        for n in (n for st in stmts for n in ast.walk(st)):
            f = n.func if isinstance(n, ast.Call) else None
            if (isinstance(f, ast.Attribute) and f.attr in names) or (isinstance(f, ast.Name) and f.id in names):
                return True
        return False

    def releases(st):
        if isinstance(st, ast.Expr) and isinstance(st.value, ast.Call):
            f = st.value.func
            return isinstance(f, ast.Attribute) and f.attr == "addCleanup"
        # A try one of whose handlers calls a release, then raises again.
        return isinstance(st, ast.Try) and any(
            h.body and isinstance(h.body[-1], ast.Raise) and h.body[-1].exc is None
            and calls(h.body[:-1], ("rmtree", "cleanup", "close")) for h in st.handlers)

    found = []
    for node in ast.walk(ast.parse(text)):
        for field in ("body", "orelse", "finalbody"):
            block = getattr(node, field, None)
            if not isinstance(block, list):
                continue
            for i, st in enumerate(block):
                if isinstance(st, (ast.Assign, ast.Expr)) and makes(st):
                    if i + 1 == len(block) or not releases(block[i + 1]):
                        found.append(st.lineno)
    return found


class Env:
    """A HOME, a state folder and a stand-in bazel of its own, for one test."""

    def __init__(self):
        self.tmp = tempfile.mkdtemp()
        try:
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
                            "SUBMIT_GATE": "basic",
                            # tools/drives.sh's stand-in for /etc/bazel.bazelrc,
                            # one that does not exist: no case reads this machine's.
                            "C_PISCINE_SYSTEM_BAZELRC": os.path.join(self.tmp, "no-system-bazelrc")}
        except BaseException:
            self.close()  # no test owns it yet, so no cleanup would remove it
            raise

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
        # A cleanup runs after tearDown even when its check fails.
        self.addCleanup(self.env.close)

    def tearDown(self):
        self.assertEqual(self.env.called(), "", "Bazel was started")

    def run42(self, argv, cwd=WS):
        return run42(argv, cwd, self.env.environ)

    def dry(self, argv, cwd=EX03):
        argv = list(argv)
        cut = argv.index("--") if "--" in argv else len(argv)  # after --, words go to the tool
        rc, out, err = self.run42(argv[:cut] + ["--dry-run"] + argv[cut:], cwd)
        self.assertEqual(rc, 0, err)
        return [l[2:] for l in out.splitlines() if l.startswith("$ ")]


class CaseCleanup(unittest.TestCase):
    def test_a_case_that_starts_bazel_fails_and_leaves_no_folder(self):
        folders = []

        class Starts(Case):
            def runTest(self):
                folders.append(self.env.tmp)
                subprocess.run([os.path.join(self.env.bin, "bazel"), "version"], check=False)

        result = unittest.TestResult()
        Starts().run(result)
        self.assertEqual(len(result.failures), 1, result.errors)
        self.assertIn("Bazel was started", result.failures[0][1])
        self.assertFalse(os.path.exists(folders[0]), "the failed case left %s behind" % folders[0])

    def test_no_tear_down_removes_what_set_up_made(self):
        # tearDown never runs after a setUp that failed, and stops at its
        # first error: a folder setUp makes is removed by addCleanup.
        found = []
        here = os.path.dirname(os.path.abspath(__file__))
        for name in sorted(os.listdir(here)):
            if not (name.startswith("test_") and name.endswith(".py")):
                continue
            with open(os.path.join(here, name), encoding="utf-8") as f:
                tree = ast.parse(f.read())
            for node in ast.walk(tree):
                if isinstance(node, ast.FunctionDef) and node.name == "tearDown":
                    for call in ast.walk(node):
                        if (isinstance(call, ast.Call) and isinstance(call.func, ast.Attribute)
                                and call.func.attr in ("cleanup", "close")):
                            found.append("%s:%d" % (name, call.lineno))
        self.assertEqual(found, [], "release these with addCleanup in setUp")

    def test_a_folder_is_released_by_the_statement_after_the_one_that_makes_it(self):
        # A temporary folder (or an Env) made outside a `with` leaks when a
        # statement between it and its release fails. The next statement
        # registers the release (self.addCleanup), or is a try with a
        # handler that calls rmtree, cleanup or close and then raises again
        # with a bare raise (as Env.__init__ does). Which folder that call
        # releases is not checked.
        found = []
        here = os.path.dirname(os.path.abspath(__file__))
        for name in sorted(os.listdir(here)):
            if name.endswith(".py"):
                with open(os.path.join(here, name), encoding="utf-8") as f:
                    found += ["%s:%d" % (name, n) for n in unreleased(f.read())]
        self.assertEqual(found, [], "release each at once: self.addCleanup on the next line")

    def test_a_try_that_only_raises_again_releases_nothing(self):
        # Kept's handler releases the folder; Leaks's only raises again.
        text = textwrap.dedent("""\
            class Kept:
                def __init__(self):
                    self.tmp = tempfile.mkdtemp()
                    try:
                        os.makedirs(os.path.join(self.tmp, "bin"))
                    except BaseException:
                        shutil.rmtree(self.tmp, ignore_errors=True)
                        raise
            class Leaks:
                def __init__(self):
                    self.tmp = tempfile.mkdtemp()
                    try:
                        os.makedirs(os.path.join(self.tmp, "bin"))
                    except BaseException:
                        print("no folder for it")
                        raise
            """)
        self.assertEqual(unreleased(text), [11])  # Leaks


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
        # The usage line has no room left within 80 columns: --show_starlark is
        # named in the flags `42 help test` lists, and docs/bazel.md says more.
        self.assertIn("    --show_starlark", main.TEST_FLAGS_HELP)
        self.assertIn("    --show_starlark", detail)

    def test_help_names_every_flag_every_command_takes(self):
        # `42 stop` takes the flags every command takes, and nothing else.
        _, usage, _ = self.run42(["help"])
        sub = next(a for a in main.parser()._actions if a.dest == "command")
        flags = [f for a in sub.choices["stop"]._actions for f in a.option_strings if f != "--dry_run"]
        self.assertIn("--plain", flags)
        for flag in flags:
            self.assertRegex(usage, r"(?<![\w-])%s(?![\w-])" % re.escape(flag))

    def test_the_flags_every_command_takes_are_said_to_be_bazel_s(self):
        # `42 config` runs no Bazel, so --show_bazel shows it nothing and its
        # --dry-run writes nothing; the footer said every command printed one.
        _, usage, _ = self.run42(["help"])
        self.assertNotIn("Every command takes --show_bazel", usage)
        self.assertIn("`42 config` runs\n  none", usage)

    def test_header_usage_names_its_flags(self):
        _, detail, _ = self.run42(["help", "header"])
        for flag in ("--reset", "--all", "-n", "-k"):
            self.assertIn("[%s]" % flag if flag in ("-n", "-k") else flag, detail.splitlines()[0])

    def test_help_submit_names_every_flag_submit_takes(self):
        _, usage, _ = self.run42(["help"])
        _, detail, _ = self.run42(["help", "submit"])
        for flag in ("--all", "--level", "--written-only", "-n"):
            self.assertIn(flag, [l for l in usage.splitlines() if l.startswith("  42 submit ")][0])
            self.assertIn("    " + flag + " ", detail)

    def test_help_submit_says_what_written_only_refuses(self):
        # --written-only lets a stub through, but never a project with nothing
        # written, nor one whose subject's mandatory part is not: the help
        # said only what it lets through.
        _, detail, _ = self.run42(["help", "submit"])
        flat = " ".join(detail.split())
        self.assertIn("refuses a project with nothing written", flat)
        self.assertIn("an exercise its subject calls mandatory", flat)

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
        self.assertIn("`42 help` says how to call it", err)
        # The top parser's prog is "42": an unknown command was sent to
        # `42 help 42`, which is no command.
        self.assertNotIn("42 help 42", err)

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

    def test_a_flag_between_two_words_leaves_both_words(self):
        # argparse ended a command's words at its first flag, and refused the
        # rest as unrecognized arguments.
        self.assertEqual(self.dry(["test", "c-06", "--level", "strict", "ex00"]),
                         self.dry(["test", "c-06", "ex00", "--level", "strict"]))
        self.assertEqual(self.dry(["submit", "c-06", "-n", "c-07"]),
                         self.dry(["submit", "c-06", "c-07", "-n"]))

    def test_a_double_dash_ends_the_flags(self):
        # Read by parse_intermixed_args (Python 3.10), a flag after `--` was
        # still a flag, `42 test -- --all` ran every module, and a word after
        # it that looks like one was refused: `42 header -- -x.c`.
        p = main.parser()
        self.assertEqual(p.parse_args(["header", "--", "-x.c"]).targets, ["-x.c"])
        ns = p.parse_args(["test", "--", "--all"])
        self.assertEqual((ns.words, ns.all), (["--all"], False))
        # ...and the words before it are still read around their flags: with
        # the `--`, the top parser lost them, and refused the line.
        ns = p.parse_args(["test", "c-05", "--level", "strict", "ex00", "--", "ex01"])
        self.assertEqual((ns.words, ns.level), (["c-05", "ex00", "ex01"], "strict"))
        ns = p.parse_args(["config", "set", "--dry-run", "login", "--", "-jdoe"])
        self.assertEqual((ns.words, ns.dry_run), (["set", "login", "-jdoe"], True))
        self.assertEqual(p.parse_args(["generate", "--", "-x"]).project, "-x")
        for argv in (["stop", "--", "x"], ["generate", "c-05", "--", "x"], ["help", "--", "a", "b"]):
            with self.assertRaises(main.UsageError, msg=argv):
                p.parse_args(argv)

    def test_submit_with_a_url(self):
        # The URL goes to //tools:submit as --url, for the one project; under
        # --dry-run nothing is saved, and 42 says so.
        url = "git@git.example.com:you/c-06.git"
        self.assertEqual(self.dry(["submit", url]), ["bazel run //tools:submit -- %s --url %s" % (C05, url)])
        self.assertEqual(self.dry(["submit", "c-06", url, "-n"]),
                         ["bazel run //tools:submit -- c-piscine/c-piscine-c-06 --url %s -n" % url])
        self.assertEqual(self.dry(["submit", url, "c-06"]), self.dry(["submit", "c-06", url]))
        rc, out, _ = self.run42(["submit", url, "--dry-run"], EX03)
        self.assertIn("--dry-run saves nothing", out)
        for argv, says in ((["submit", url, url + "x"], "two URLs"),
                           (["submit", "--all", url], "--all pushes every project"),
                           (["submit", "c-06", "c-07", url], "name one project with it, not 2"),
                           (["submit", "git@git.example.com:"], "is not a repository URL"),
                           (["submit", "git@git.example.com:you/a b.git"], "holds a blank"),
                           (["submit", "c-99"], "is not a project")):
            rc, _, err = self.run42(argv + ["--dry-run"], EX03)
            self.assertEqual(rc, 2, argv)
            self.assertIn(says, err, argv)
        rc, _, err = self.run42(["submit", url, "--dry-run"], WS)
        self.assertEqual(rc, 2)
        self.assertIn("42 submit URL pushes the project you are in", err)

    def test_a_word_submit_or_generate_does_not_take_says_what_it_takes(self):
        # Each takes a project, and submit a URL too. An unknown word is
        # neither, not "an exercise or a layer" with `42 help test` to read,
        # and an exercise is refused, never read as its whole project.
        for argv, says in ((["submit", "nonsense"], "'nonsense' is not a project or a repository URL."),
                           (["submit", "c-05x"], "Did you mean c-05"),
                           (["generate", "nonsense"], "'nonsense' is not a project."),
                           (["submit", "ex03"], "42 submit takes a project, not ex03"),
                           (["generate", "ex03"], "42 generate takes a project, not ex03"),
                           (["submit", "c-05", "norm"], "42 submit takes a project, not norm")):
            for cwd in (WS, EX03):
                rc, _, err = self.run42(argv + ["--dry-run"], cwd)
                self.assertEqual(rc, 2, (argv, cwd, err))
                self.assertIn(says, err, (argv, cwd))
                self.assertNotIn("help test", err, (argv, cwd))
                self.assertNotIn("42 test", err, (argv, cwd))
                self.assertTrue(all(len(l) <= 80 for l in err.splitlines()), err)
        rc, _, err = self.run42(["test", "nonsense", "--dry-run"], EX03)
        # A function is offered, by a name a library has, only in a checkout
        # with a library (test_workspace.Deep), and never as the word refused.
        self.assertRegex(err, r"is not a project, an exercise \(ex03\)(, a function \(ft_\w+\))? or a layer")
        self.assertNotIn("(nonsense)", err)

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
        self.assertEqual(self.dry(["submit", "c-06", "--written-only"]),
                         ["bazel run //tools:submit -- c-piscine/c-piscine-c-06 --written-only"])
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


class Plain(unittest.TestCase):
    """--plain: no line that counts the seconds, even on a terminal."""

    class Tty:
        def __init__(self):
            self.written = []

        def isatty(self):
            return True

        def write(self, text):
            self.written.append(text)

        def flush(self):
            pass

    def out_for(self, argv):
        tty, saved = self.Tty(), sys.stderr
        sys.stderr = tty
        try:
            args = main.parser().parse_args(argv)
            main.Ctx(WS, EX03, {}, args).out.tick("  running... 1s")
        finally:
            sys.stderr = saved
        return tty.written

    def test_the_ticker_is_on_on_a_terminal_and_off_with_plain(self):
        for cmd in ("test", "clues", "norm", "submit"):
            self.assertTrue(self.out_for([cmd]), cmd)
            self.assertEqual(self.out_for([cmd, "--plain"]), [], cmd)


def bep_lines(*events):
    """A BEP file's text: (label, summary status or None, test.log or None) per test target.

    A test.log is a path, or a URI of its own (a remote cache's).
    """
    rows = []
    for label, status, log in events:
        rows.append({"id": {"targetConfigured": {"label": label}},
                     "configured": {"targetKind": "sh_test rule", "testSize": "SMALL", "tag": []}})
        if log:
            rows.append({"id": {"testResult": {"label": label, "run": 1, "shard": 1, "attempt": 1}},
                         "testResult": {"status": status,
                                        "testActionOutput": [{"name": "test.log", "uri": log if "://" in log else "file://" + urllib.parse.quote(log)}]}})
        if status:
            rows.append({"id": {"testSummary": {"label": label}}, "testSummary": {"overallStatus": status}})
    return "".join(json.dumps(r) + "\n" for r in rows)


class Clues(unittest.TestCase):
    """42 clues over a stand-in Bazel that answers each call with a BEP and an output of the test's.

    The targets are invented (//spike), as is every line Bazel prints here.
    """

    BROKEN = ("ERROR: /home/you/42/spike/BUILD.bazel:3:8: Linking spike/broken failed: (Exit 1)\n"
              "//spike:broken                                                  FAILED TO BUILD\n\n"
              "Executed 0 out of 1 test: 1 fails to build.\n"
              "ERROR: Build did NOT complete successfully\n")

    def setUp(self):
        self.env = Env()
        self.addCleanup(self.env.close)
        # The stand-in answers at once, so no case waits in real time: each
        # run is looked at every 0.01 s, not POLL's 0.5, and while_busy's
        # sleep only writes its length down, in self.slept. BUSY_WAIT keeps
        # its value, so a Bazel that stays busy is still tried limit/BUSY_WAIT
        # times, as it is outside the tests.
        self.slept = []
        for patch in (mock.patch.object(main.bazel, "POLL", 0.01),
                      mock.patch.object(main, "time", mock.Mock(wraps=main.time, sleep=self.slept.append))):
            patch.start()
            self.addCleanup(patch.stop)
        with open(os.path.join(self.env.bin, "bazel"), "w") as f:
            f.write('#!/bin/sh\necho "$0 $*" >> "%s"\nn=$(wc -l < "%s")\n'
                    'for a in "$@"; do case $a in --build_event_json_file=*) cp "%s/bep$n" "${a#*=}" ;; esac; done\n'
                    'cat "%s/out$n"\nexit "$(cat "%s/rc$n")"\n'
                    % (self.env.calls, self.env.calls, self.env.tmp, self.env.tmp, self.env.tmp))

    def answer(self, n, rc, out, bep):
        for name, text in (("rc", str(rc)), ("out", out), ("bep", bep)):
            with open(os.path.join(self.env.tmp, "%s%d" % (name, n)), "w") as f:
                f.write(text)

    def clues(self):
        return run42(["clues", "c-05", "ex03", "--plain"], WS, self.env.environ)

    def test_what_does_not_build_is_named_not_nothing_failed(self):
        self.answer(1, 1, self.BROKEN, bep_lines(("//spike:broken", None, None)))
        rc, out, err = self.clues()
        self.assertEqual(rc, 1, err)
        self.assertNotIn("Nothing failed", out)
        self.assertIn("spike", out)
        self.assertIn("broken", out)
        self.assertIn("THE BUILD STOPPED", out)  # first_red's report, as `42 test` shows it
        self.assertEqual(len(self.env.called().splitlines()), 1, "nothing is left to run again")

    def test_beside_a_red_test_what_did_not_build_is_named(self):
        log = os.path.join(self.env.tmp, "red.log")
        with open(log, "w") as f:
            f.write(" FAIL line 1\n " + "-" * 50 + "\n HINTS:\n   * What does a toy print?\n")
        self.answer(1, 1, self.BROKEN + "//spike:red    FAILED in 0.1s\n",
                    bep_lines(("//spike:broken", None, None), ("//spike:red", "FAILED", log)))
        self.answer(2, 3, "//spike:red    FAILED in 0.1s\n", bep_lines(("//spike:red", "FAILED", log)))
        rc, out, err = self.clues()
        self.assertEqual(rc, 1, err)  # the first run's: a target did not build
        calls = self.env.called().splitlines()
        self.assertEqual(len(calls), 2)
        self.assertIn(" //spike:red ", calls[1])
        self.assertNotIn("//spike:broken", calls[1])
        self.assertIn("   * What does a toy print?", out)
        self.assertIn("//spike:broken", out.split("What does a toy print?")[1])

    def test_a_first_run_failed_to_build_summary_is_named_not_run_again(self):
        # Bazel 9 gives a target that does not build no summary; a stand-in
        # for one that says FAILED_TO_BUILD, which no second run can explain.
        log = self.red_log()
        self.answer(1, 1, self.BROKEN + "//spike:red    FAILED in 0.1s\n",
                    bep_lines(("//spike:broken", "FAILED_TO_BUILD", None), ("//spike:red", "FAILED", log)))
        self.answer(2, 3, "//spike:red    FAILED in 0.1s\n", bep_lines(("//spike:red", "FAILED", log)))
        rc, out, err = self.clues()
        self.assertEqual(rc, 1, out + err)
        calls = self.env.called().splitlines()
        self.assertEqual(len(calls), 2)
        self.assertNotIn("//spike:broken", calls[1])
        self.assertIn("did not run", out)
        self.assertIn("    //spike:broken", out.split("did not run")[1])

    def test_a_green_run_says_nothing_failed(self):
        self.answer(1, 0, "", bep_lines(("//spike:green", "PASSED", None)))
        rc, out, _ = self.clues()
        self.assertEqual(rc, 0)
        self.assertIn("Nothing failed in c-05 ex03", out)

    def test_what_did_not_build_keeps_the_run_red_when_the_rest_passes_again(self):
        # A flaky test, or a file saved between the two runs: the second run
        # passes, and what did not build still did not.
        log = self.red_log()
        self.answer(1, 1, self.BROKEN + "//spike:red    FAILED in 0.1s\n",
                    bep_lines(("//spike:broken", None, None), ("//spike:red", "FAILED", log)))
        self.answer(2, 0, "//spike:red    PASSED in 0.1s\n", bep_lines(("//spike:red", "PASSED", log)))
        rc, out, err = self.clues()
        self.assertEqual(rc, 1, "`42 test` exits 1 when a target does not build\n" + out + err)
        self.assertIn("//spike:broken", out)

    def test_a_test_that_passes_again_keeps_the_first_runs_exit(self):
        # A flaky test: the hints shown explain the first run's red, and
        # `42 test` exits 3 on the same selection.
        log = self.red_log()
        self.answer(1, 3, "//spike:red    FAILED in 0.1s\n", bep_lines(("//spike:red", "FAILED", log)))
        self.answer(2, 0, "//spike:red    PASSED in 0.1s\n", bep_lines(("//spike:red", "PASSED", log)))
        rc, out, err = self.clues()
        self.assertEqual(rc, 3, out + err)
        self.assertIn("   * What does a toy print?", out)

    def test_a_target_the_second_run_did_not_build_is_named_not_read_from_an_older_log(self):
        # A file saved between the two runs breaks the target: the second run
        # gives it no test.log, and the one in bazel-testlogs is an earlier
        # run's, written without the hints asked for.
        ws = os.path.join(self.env.tmp, "ws")
        old = os.path.join(ws, "bazel-testlogs", "spike", "red")
        os.makedirs(old)
        os.symlink(os.path.join(WS, "tools"), os.path.join(ws, "tools"))
        with open(os.path.join(old, "test.log"), "w") as f:
            f.write(" FAIL line 1\n " + "-" * 50 + "\n HINTS:\n   * An earlier run's hint?\n")
        self.answer(1, 3, "//spike:red    FAILED in 0.1s\n", bep_lines(("//spike:red", "FAILED", self.red_log())))
        self.answer(2, 1, self.BROKEN.replace("broken", "red"), bep_lines(("//spike:red", None, None)))
        rc, out, err = run42(["clues", "//spike:red", "--plain"], ws, self.env.environ, ws=ws)
        self.assertEqual(rc, 1, out + err)  # the second run's: the target no longer builds
        self.assertNotIn("An earlier run's hint?", out)
        self.assertNotIn("What does a toy print?", out)
        self.assertIn("did not run", out)
        self.assertIn("    //spike:red", out.split("did not run")[1])

    def test_a_failed_to_build_summary_did_not_run(self):
        # Bazel 9 gives a target that does not build no summary at all; one
        # that says FAILED_TO_BUILD still says the test gave no result.
        self.answer(1, 3, "//spike:red    FAILED in 0.1s\n", bep_lines(("//spike:red", "FAILED", self.red_log())))
        self.answer(2, 1, self.BROKEN.replace("broken", "red"), bep_lines(("//spike:red", "FAILED_TO_BUILD", None)))
        rc, out, err = self.clues()
        self.assertEqual(rc, 1, out + err)
        self.assertNotIn("could not be found", out)
        self.assertIn("did not run", out)
        self.assertIn("    //spike:red", out.split("did not run")[1])

    def test_a_test_whose_log_is_not_a_file_ran_and_says_so(self):
        # A remote cache (in a ~/.bazelrc) names a test.log no file holds:
        # the test ran, and only its log is missing.
        self.answer(1, 3, "//spike:red    FAILED in 0.1s\n", bep_lines(("//spike:red", "FAILED", self.red_log())))
        self.answer(2, 3, "//spike:red    FAILED in 0.1s\n",
                    bep_lines(("//spike:red", "FAILED", "bytestream://cache.example/blobs/0a1b/123")))
        rc, out, err = self.clues()
        self.assertEqual(rc, 3, out + err)
        self.assertNotIn("did not run", out)
        self.assertIn("could not be found", out)
        self.assertIn("    //spike:red", out.split("could not be found")[1])

    def red_log(self):
        log = os.path.join(self.env.tmp, "red.log")
        with open(log, "w") as f:
            f.write(" FAIL line 1\n " + "-" * 50 + "\n HINTS:\n   * What does a toy print?\n")
        return log

    def test_a_run_that_did_not_finish_is_reported_as_42_test_reports_it(self):
        real = main.while_busy
        cases = ((2, "ERROR: Unrecognized option: --frob\n"),
                 (4, "ERROR: No test targets were found, yet testing was requested\n"),
                 (8, "ERROR: build interrupted\n"),
                 (9, "Another command is running.\n"))
        with mock.patch.object(main, "while_busy", lambda out, attempt, limit=0: real(out, attempt, 0)), \
                mock.patch.object(main.report, "coldness", lambda ws, env=None, root=None: None):
            for code, text in cases:
                with self.subTest(rc=code):
                    if os.path.exists(self.env.calls):
                        os.remove(self.env.calls)
                    self.answer(1, code, text, "")
                    self.answer(2, code, text, "")
                    rc, by_test, _ = run42(["test", "c-05", "ex03", "--plain"], WS, self.env.environ)
                    self.assertEqual(rc, code)
                    rc, out, err = self.clues()
                    self.assertEqual(rc, code, err)
                    self.assertNotIn("no hint to show", out)
                    # Word for word, but for the line `42 test` opens with.
                    header, _, said = by_test.partition("\n")
                    self.assertTrue(header.startswith("42 test: "), by_test)
                    self.assertEqual(out, said)
                    self.assertEqual(len(self.env.called().splitlines()), 2, "clues ran nothing again")

    def test_a_busy_bazel_is_waited_for(self):
        self.answer(1, 9, "Another command is running.\n", "")
        self.answer(2, 0, "", bep_lines(("//spike:green", "PASSED", None)))
        rc, out, err = self.clues()
        self.assertEqual(rc, 0, out + err)
        self.assertIn("Bazel is busy with another command", out)
        self.assertIn("Nothing failed in c-05 ex03", out)
        self.assertEqual(len(self.env.called().splitlines()), 2)
        self.assertEqual(self.slept, [main.BUSY_WAIT], "one wait before the second try")

    def test_the_second_run_waits_for_a_busy_bazel_too(self):
        log = self.red_log()
        self.answer(1, 3, "//spike:red    FAILED in 0.1s\n", bep_lines(("//spike:red", "FAILED", log)))
        self.answer(2, 9, "Another command is running.\n", "")
        self.answer(3, 3, "//spike:red    FAILED in 0.1s\n", bep_lines(("//spike:red", "FAILED", log)))
        rc, out, err = self.clues()
        self.assertEqual(rc, 3, out + err)
        self.assertIn("Bazel is busy with another command", out)
        self.assertIn("   * What does a toy print?", out)
        self.assertEqual(len(self.env.called().splitlines()), 3)
        self.assertEqual(self.slept, [main.BUSY_WAIT], "one wait before the second run's second try")

    def test_a_second_run_that_did_not_finish_shows_no_hint(self):
        log = self.red_log()
        self.answer(1, 3, "//spike:red    FAILED in 0.1s\n", bep_lines(("//spike:red", "FAILED", log)))
        self.answer(2, 8, "ERROR: build interrupted\n", bep_lines(("//spike:red", "FAILED", log)))
        rc, out, err = self.clues()
        self.assertEqual(rc, 8, out + err)
        self.assertNotIn("What does a toy print?", out)
        self.assertNotIn("prints no hints", out)
        self.assertIn("INTERRUPTED", out)


class NextLog(unittest.TestCase):
    """The log `42 test` shows under its first red, over Clues' stand-in Bazel."""

    setUp = Clues.setUp
    answer = Clues.answer

    def test_a_log_the_run_names_and_no_file_holds_is_never_an_older_runs(self):
        # The run names a test.log no file holds (a remote cache's, a tree
        # cleaned under it), and bazel-testlogs holds an earlier run's log
        # of the same target.
        ws = os.path.join(self.env.tmp, "ws")
        old = os.path.join(ws, "bazel-testlogs", "spike", "ex00_output")
        os.makedirs(old)
        os.symlink(os.path.join(WS, "tools"), os.path.join(ws, "tools"))
        with open(os.path.join(old, "test.log"), "w") as f:
            f.write(" An earlier run's line\n")
        gone = os.path.join(self.env.tmp, "gone", "test.log")
        self.answer(1, 3, "//spike:ex00_output    FAILED in 0.1s\n",
                    bep_lines(("//spike:ex00_output", "FAILED", gone)))
        rc, out, err = run42(["test", "//spike:ex00_output", "--plain"], ws, self.env.environ, ws=ws)
        self.assertEqual(rc, 3, out + err)
        self.assertNotIn("An earlier run's line", out)
        self.assertNotIn("THE LOG OF", out)
        self.assertIn("could not be found", out)

    def test_a_log_the_run_names_is_shown(self):
        log = os.path.join(self.env.tmp, "red.log")
        with open(log, "w") as f:
            f.write(" This run's line\n")
        self.answer(1, 3, "//spike:ex00_output    FAILED in 0.1s\n",
                    bep_lines(("//spike:ex00_output", "FAILED", log)))
        rc, out, err = run42(["test", "//spike:ex00_output", "--plain"], WS, self.env.environ)
        self.assertEqual(rc, 3, out + err)
        self.assertIn("THE LOG OF //spike:ex00_output", out)
        self.assertIn(" This run's line", out)


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


class HintBlock(unittest.TestCase):
    """What `42 clues` copies out of a test.log: the hints, under any heading rl_clues prints.

    The hint text is invented, never a clues.tsv row of this repository.
    """

    PREAMBLE = ('exec ${PAGER:-/usr/bin/less} "$0" || exit 1\nExecuting tests from //course/proj:ex07_output\n'
                + "-" * 77 + "\n FAIL line 1\n " + "-" * 50 + "\n")
    HEADINGS = (
        " HINTS:",
        " HINTS (none matches this case -- showing what this exercise has):",
        " HINTS (from this exercise, written for its output test rather than this one):",
    )

    def block(self, text):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "test.log")
            with open(p, "w") as f:
                f.write(text)
            return main.hint_block(p)

    def test_every_heading_starts_the_block(self):
        for heading in self.HEADINGS:
            body = [heading, "   * What does a toy print when it is given nothing?",
                    "   (1 more -- CLUE_MODE=all shows every one)"]
            self.assertEqual(self.block(self.PREAMBLE + "\n".join(body) + "\n"), body, heading)

    def test_a_log_without_hints_has_no_block(self):
        self.assertEqual(self.block(self.PREAMBLE + " RESULT: FAIL\n"), [])
        # A line of the program's own output that only begins with the word
        # starts nothing.
        self.assertEqual(self.block(self.PREAMBLE + " HINTS are what this toy prints:\n   * no\n"), [])

    def test_the_headings_rl_clues_prints(self):
        # The printer itself, over an invented clues file: each way it heads a
        # block is one hint_block reads.
        with tempfile.TemporaryDirectory() as d:
            clues = os.path.join(d, "clues.tsv")
            failed = os.path.join(d, "failed")
            with open(clues, "w") as f:
                f.write("Which toy case?\tcase_a\nWhich toy row for all?\n")
            with open(failed, "w") as f:
                f.write("case_b\n")
            for args in ([clues], [clues, failed, "", "", "toylayer"]):
                r = subprocess.run(["sh", "-c", '. "$0"; rl_clues "$@"',
                                    os.path.join(WS, "tools", "runner_lib.sh")] + args,
                                   stdout=subprocess.PIPE, universal_newlines=True, check=False)
                self.assertEqual(r.returncode, 0, args)
                printed = [l for l in r.stdout.splitlines() if l.strip(" -")]
                self.assertTrue(printed and printed[0].startswith(" HINTS"), (args, r.stdout))
                self.assertEqual(self.block(self.PREAMBLE + r.stdout), printed, args)
            with open(clues, "w") as f:
                f.write("Which toy case?\tcase_a\n")
            r = subprocess.run(["sh", "-c", '. "$0"; rl_clues "$@"', os.path.join(WS, "tools", "runner_lib.sh"),
                                clues, failed], stdout=subprocess.PIPE, universal_newlines=True, check=False)
            self.assertIn(self.HEADINGS[1], r.stdout)
            self.assertEqual(self.block(self.PREAMBLE + r.stdout)[0], self.HEADINGS[1])


class Entry(unittest.TestCase):
    """main.py as tools/42.sh starts it: with 42.sh's own flags, its folder found by itself."""

    def flags(self):
        """The flags tools/42.sh hands python3 before main.py, read from its exec line."""
        with open(os.path.join(WS, "tools", "42.sh"), encoding="utf-8") as f:
            m = re.search(r'^exec python3((?: -[A-Za-z]+)*) "\$FT_WS/tools/fortytwo/main\.py" "\$@"$',
                          f.read(), re.M)
        self.assertIsNotNone(m, "tools/42.sh no longer hands over to main.py with exec python3")
        return m.group(1).split()

    def run_main(self, main_py):
        env = Env()
        self.addCleanup(env.close)
        e = dict(env.environ, FT_WS=WS, FT_CWD=EX03)
        r = subprocess.run([sys.executable] + self.flags() + [main_py],
                           cwd=env.tmp, env=e, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("c-05 ex03", r.stdout)
        self.assertEqual(env.called(), "")

    def test_python_dash_I(self):
        self.assertIn("-I", self.flags())
        self.run_main(os.path.join(WS, "tools", "fortytwo", "main.py"))

    def test_leaves_no_bytecode(self):
        """42 writes nothing beside its modules: Python's bytecode cache went into the checkout.

        -I ignores PYTHONDONTWRITEBYTECODE, so only -B keeps it out. Run from a
        copy of 42's folder, which no earlier run can have left a cache in.
        """
        env = Env()
        self.addCleanup(env.close)
        here = os.path.join(WS, "tools", "fortytwo")
        copy = os.path.join(env.tmp, "fortytwo")
        os.makedirs(copy)
        for name in os.listdir(here):
            if name.endswith(".py") or name == "commands.tsv":
                shutil.copy(os.path.join(here, name), copy)
        self.run_main(os.path.join(copy, "main.py"))
        self.assertFalse(os.path.exists(os.path.join(copy, "__pycache__")),
                         "running main.py as tools/42.sh does left a __pycache__ beside it")


if __name__ == "__main__":
    unittest.main()
