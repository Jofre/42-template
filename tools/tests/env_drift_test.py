"""//tools/tests:env_drift_test -- tools/env_drift.py, under unittest.

Two halves. The rules env_drift.py keeps from the shell it was ported from
(how a line of pins.tsv is split, what a $(...) keeps, how a version is
graded), each checked on inputs of its own. And whole runs of the launcher,
tools/env_drift.sh, on this test's interpreter, which is the fetched one
Bazel hands //tools:env_drift too: with no python3 on PATH, or one that
holds no norminette or does not start, in the C locale, and with box tools
that read their input or die by a signal.

The selftest's env_drift section checks the same script through its arms,
and two of these runs are arms there too: the one with no python3 on PATH,
and the refusals with no interpreter handed over. Both copies stay, for two
suites: this one keeps the launcher in //:gate_fast, which runs no
selftest, and the arms also run it under bash, in :selftest_bash. The rest
is what those arms cannot see from outside.
"""

import importlib.util
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

if os.environ.get("TEST_TMPDIR") and os.environ.get("TMPDIR", "/tmp").rstrip("/") in ("", "/tmp"):
    os.environ["TMPDIR"] = os.environ["TEST_TMPDIR"]

TOOLS = os.path.join(os.environ.get("TEST_SRCDIR", ""), "_main", "tools")
if not os.path.isfile(os.path.join(TOOLS, "env_drift.py")):
    TOOLS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TOOLS = os.path.abspath(TOOLS)

_spec = importlib.util.spec_from_file_location("env_drift", os.path.join(TOOLS, "env_drift.py"))
ed = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ed)


class ShellRules(unittest.TestCase):
    """What the shell did, which the port has to do the same way."""

    def test_a_row_is_split_as_read_splits_it_on_tabs(self):
        # A run of tabs is one separator, those at either end are cut, and
        # the last field takes the rest of the line.
        self.assertEqual(ed.sh_read("\ta\t\tb\tc d\te\t", 3), ["a", "b", "c d\te"])
        self.assertEqual(ed.sh_read("a", 3), ["a", "", ""])

    def test_a_last_line_with_no_newline_is_no_row_for_read_but_one_for_awk(self):
        self.assertEqual(ed.read_lines("a\nb"), ["a"])
        self.assertEqual(ed.awk_records("a\nb"), ["a", "b"])
        self.assertEqual(ed.awk_records("a\nb\n"), ["a", "b"])

    def test_a_substitution_drops_nul_bytes_and_trailing_newlines(self):
        self.assertEqual(ed.subst(b"a\0b\n\n"), "ab")
        self.assertEqual(ed.subst(b"\n\na\n"), "\n\na")

    def test_bytes_that_are_no_utf_8_come_back_out_as_they_went_in(self):
        raw = b"caf\xc3\xa9 \xff 1.2.3"
        self.assertEqual(ed.encode(ed.subst(raw)), raw)

    def test_a_column_is_padded_by_bytes_as_printf_pads_it(self):
        self.assertEqual(ed.pad("ab", 4), "ab  ")
        self.assertEqual(ed.encode(ed.pad("é", 4)), b"\xc3\xa9  ")
        self.assertEqual(ed.pad("abcdef", 4), "abcdef")

    def test_dirname_answers_as_dirname_does(self):
        tool = shutil.which("dirname")
        if tool is None:
            self.skipTest("no dirname on PATH to compare with")
        for p in ("", "/", "//", "a", "a/", "/a", "/a/b", "a//b//", "../x/y", "/a///"):
            want = subprocess.run([tool, "--", p], stdout=subprocess.PIPE, check=True).stdout
            self.assertEqual(ed.dirname(p), want.decode().rstrip("\n"), p)

    def test_cd_makes_its_pwd_from_the_words_of_the_path(self):
        self.assertEqual(ed.logical("/a/b", "../c/./d"), "/a/c/d")
        self.assertEqual(ed.logical("/a", "/x/../y"), "/y")
        self.assertEqual(ed.logical("/", "../.."), "/")

    def test_a_colon_list_keeps_an_empty_field_but_not_a_last_one(self):
        self.assertEqual(ed.colon_fields("a::b:"), ["a", "", "b"])
        self.assertEqual(ed.colon_fields(""), [])

    def test_a_status_is_128_and_the_signal_for_a_killed_child(self):
        self.assertEqual(ed.status(-11), 139)
        self.assertEqual(ed.status(3), 3)

    def test_a_name_that_is_no_variable_name_reads_as_unset(self):
        os.environ["ENV_DRIFT_TEST_SET"] = "x"
        try:
            self.assertEqual(ed.env("ENV_DRIFT_TEST_SET"), "x")
            self.assertEqual(ed.env("1BAD"), "")
            self.assertEqual(ed.env("A-B"), "")
        finally:
            del os.environ["ENV_DRIFT_TEST_SET"]


class Grading(unittest.TestCase):
    """How two version strings are compared."""

    def test_the_same_string_is_ok(self):
        self.assertEqual(ed.grade("GNU coreutils 8.32", "GNU coreutils 8.32"), "ok")

    def test_the_same_number_in_other_words_is_a_repackaging(self):
        self.assertEqual(ed.grade("GNU coreutils 8.32", "Debian coreutils 8.32-4"), "packaging")

    def test_a_bare_number_is_read_whole(self):
        # A greedy match read "3.58" out of "3.3.58".
        self.assertEqual(ed.versions("3.3.58"), ["3.3.58"])
        self.assertEqual(ed.grade("3.3.58", "3.3.51"), "patch")
        self.assertEqual(ed.grade("3.3.58", "3.4.0"), "minor")
        self.assertEqual(ed.grade("3.3.58", "4.0"), "major")

    def test_a_version_anywhere_in_a_line_of_several_is_found(self):
        line = "norminette 3.3.58 Python 3.10.12 Linux 5.15.0"
        self.assertEqual(ed.grade("3.3.58", line), "packaging")

    def test_the_tools_own_number_moving_is_drift_whatever_the_last_says(self):
        self.assertEqual(ed.grade("ip utility, iproute2-5.15.0, libbpf 0.5.0",
                                  "ip utility, iproute2-6.1.0, libbpf 0.5.0"), "major")

    def test_no_number_is_never_equal(self):
        self.assertEqual(ed.grade("1.0", "(not installed)"), "major")
        self.assertEqual(ed.grade("banner", "other banner"), "major")

    def test_the_first_line_with_a_version_is_the_one_read(self):
        self.assertEqual(ed.first_line("\nThis is perl 5, version 34 (v5.34.0)\n"),
                         "This is perl 5, version 34 (v5.34.0)")
        self.assertEqual(ed.first_line("ShellCheck - shell script analysis tool\nversion: 0.10.0\n"),
                         "version: 0.10.0")
        self.assertEqual(ed.first_line("\n  \nno number\n"), "no number")
        self.assertEqual(ed.first_line(""), "")

    def test_a_pins_banner_is_its_words_before_the_version(self):
        self.assertEqual(ed.pin_banner("GNU nm (GNU Binutils for Ubuntu) 2.38"),
                         "GNU nm (GNU Binutils for Ubuntu)")
        self.assertEqual(ed.pin_banner("0.13.0"), "")

    def test_a_compilers_default_standard_is_read_from_its_macros(self):
        self.assertEqual(ed.default_std_answer("#define __STDC_VERSION__ 201710L\n"), "201710L gnu")
        self.assertEqual(ed.default_std_answer(
            "#define __STRICT_ANSI__ 1\n#define __STDC_VERSION__ 199901L"), "199901L strict")
        self.assertEqual(ed.default_std_answer(""), "(none) gnu")

    def test_only_absolute_tool_paths_are_ones_to_judge(self):
        build = 'x\n    tool_paths = {"gcc": "/usr/bin/gcc", "ar": "wrapped/ar", "ld": "/usr/bin/ld"},\n'
        self.assertEqual(ed.tool_paths(build), ["/usr/bin/gcc", "/usr/bin/ld"])

    def test_tool_paths_are_read_across_the_lines_rules_cc_writes(self):
        # One pair a line and the `}` on the last, as a generated
        # local_config_cc BUILD has it; the list after it is not read.
        build = ('    cxx_builtin_include_directories = ["/usr/include",\n'
                 '    "/usr/include/c++/10"],\n'
                 '    tool_paths = {"ar": "/usr/bin/ar",\n'
                 '        "ld": "/nonexistent/bin/ld",\n'
                 '        "parse_headers": "cc_wrapper.sh"},\n'
                 '    compile_flags = ["-fstack-protector",\n'
                 '    "/not/a/tool"],\n')
        self.assertEqual(ed.tool_paths(build), ["/usr/bin/ar", "/nonexistent/bin/ld"])


def _script(path, body):
    with open(path, "w") as f:
        f.write("#!/bin/sh\n" + body)
    os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)
    return path


class Launcher(unittest.TestCase):
    """Whole runs of tools/env_drift.sh, as //tools:env_drift starts it."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)
        self.ws = os.path.join(self.tmp, "ws")
        os.makedirs(os.path.join(self.ws, "tools"))
        shutil.copy(os.path.join(TOOLS, "drives.sh"), os.path.join(self.ws, "tools", "drives.sh"))
        # Every program on PATH but python3: a machine whose norminette
        # cannot start.
        self.nopy = os.path.join(self.tmp, "nopy")
        os.mkdir(self.nopy)
        for d in os.environ.get("PATH", "/usr/bin:/bin").split(":"):
            if not os.path.isdir(d):
                continue
            for name in os.listdir(d):
                src = os.path.join(d, name)
                dst = os.path.join(self.nopy, name)
                if (name.startswith(("python", "pydoc", "py3")) or os.path.lexists(dst)
                        or not os.access(src, os.X_OK) or os.path.isdir(src)):
                    continue
                os.symlink(src, dst)

    def env(self, **extra):
        e = {
            "PATH": self.nopy,
            "HOME": os.path.join(self.tmp, "home"),
            "BUILD_WORKSPACE_DIRECTORY": self.ws,
            "C_PISCINE_CAMPUS": "0",
            "C_PISCINE_SYSTEM_BAZELRC": os.path.join(self.tmp, "no-system-bazelrc"),
            "C_PISCINE_GOINFRE": os.path.join(self.tmp, "no-goinfre"),
            "USER": "probe",
            "ENV_DRIFT_PYTHON": sys.executable,
            "ENV_DRIFT_MAIN": os.path.join(TOOLS, "env_drift.py"),
        }
        e.update(extra)
        return {k: v for k, v in e.items() if v is not None}

    def pins(self, *rows):
        p = os.path.join(self.tmp, "pins.tsv")
        with open(p, "w") as f:
            for r in rows:
                f.write("\t".join(r) + "\n")
        return p

    def drift(self, env, *args, stdin=b""):
        p = subprocess.run(["/bin/sh", os.path.join(TOOLS, "env_drift.sh")] + list(args),
                           env=env, cwd=self.tmp, input=stdin,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return p.returncode, p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace")

    def test_with_no_python3_on_path_a_fetched_python_tool_is_unrunnable(self):
        self.assertIsNone(shutil.which("python3", path=self.nopy))
        tool = os.path.join(self.tmp, "pytool")
        with open(tool, "w") as f:
            f.write("#!/usr/bin/env python3\nprint('3.3.58')\n")
        os.chmod(tool, 0o755)
        pins = self.pins(["norminette", "campus", "3.3.58", "norminette-version", "f", "ENV_DRIFT_TEST_FETCHED"])
        rc, out, err = self.drift(self.env(ENV_DRIFT_TEST_FETCHED=tool), "--pins", pins)
        self.assertEqual(rc, 0, out + err)
        # Missing, as any absent tool is: never a version to grade.
        self.assertIn("  norminette  campus  MISSING   (expected 3.3.58)\n", out)
        self.assertIn("0 match, 0 drifted, 1 missing", out)
        self.assertNotIn("DRIFT (major)", out)
        self.assertIn("fetched:  UNRUNNABLE (exit 127: ", out)
        self.assertIn("1 unrunnable", out)

    def norminette_run(self, python3, campus="0", **extra):
        """A norminette row asked of PYTHON3, the only python3 on PATH."""
        bin_dir = os.path.join(self.tmp, "pybin")
        os.makedirs(bin_dir, exist_ok=True)
        _script(os.path.join(bin_dir, "python3"), python3)
        pins = self.pins(["norminette", "campus", "3.3.58", "norminette-version", "f"])
        return self.drift(self.env(PATH=bin_dir + ":" + self.nopy, C_PISCINE_CAMPUS=campus, **extra),
                          "--pins", pins)

    def test_a_python3_without_norminette_is_a_missing_norminette(self):
        # -S: no site-packages, so no norminette to find.
        rc, out, err = self.norminette_run('exec "%s" -S "$@"\n' % sys.executable)
        self.assertEqual(rc, 0, out + err)
        self.assertIn("  norminette  campus  MISSING   (expected 3.3.58)\n", out)
        self.assertIn("0 match, 0 drifted, 1 missing", out)
        # On campus, an absent campus tool's own line, and no re-pin to a
        # text that is no version.
        rc, out, err = self.norminette_run('exec "%s" -S "$@"\n' % sys.executable, campus="1")
        self.assertEqual(rc, 0, out + err)
        self.assertIn("norminette (missing): expected 3.3.58, not installed", out)
        self.assertNotIn("3.3.58  ->", out)

    def test_a_python3_that_does_not_start_did_not_start(self):
        rc, out, err = self.norminette_run('echo "python3: broken" >&2\nexit 1\n')
        self.assertEqual(rc, 0, out + err)
        self.assertIn("  norminette  campus  DID NOT START (exit 1: python3: broken)\n", out)
        self.assertIn("0 match, 0 drifted, 1 missing", out)

    def test_an_installed_norminette_is_read_from_its_metadata(self):
        site = os.path.join(self.tmp, "site")
        meta = os.path.join(site, "norminette-3.3.58.dist-info")
        os.makedirs(meta)
        with open(os.path.join(meta, "METADATA"), "w") as f:
            f.write("Metadata-Version: 2.1\nName: norminette\nVersion: 3.3.58\n")
        rc, out, err = self.norminette_run('exec "%s" -S "$@"\n' % sys.executable, PYTHONPATH=site)
        self.assertEqual(rc, 0, out + err)
        self.assertIn("  norminette  campus  ok\n", out)

    def test_every_probe_sees_the_locale_its_caller_had(self):
        tool = _script(os.path.join(self.tmp, "loc"), 'echo "1.0 LC_CTYPE=${LC_CTYPE-unset}"\n')
        for value, shown in ((None, "unset"), ("C", "C"), ("", "")):
            pins = self.pins(["loc", "campus", "1.0 LC_CTYPE=" + shown, tool, "f"])
            rc, out, err = self.drift(self.env(LC_ALL=None, LANG=None, LC_CTYPE=value), "--pins", pins)
            self.assertEqual(rc, 0, out + err)
            self.assertIn("  loc         campus  ok\n", out, "LC_CTYPE %r" % (value,))

    def test_a_tool_that_reads_its_input_eats_no_row(self):
        tool = _script(os.path.join(self.tmp, "reader"), 'read -r x; echo "1.0${x:+ $x}"; cat > /dev/null\n')
        # Its input is no one's: neither the rest of pins.tsv, as it was
        # under the shell version, nor what the caller was typing.
        pins = self.pins(["reader", "campus", "1.0", tool, "f"], ["after", "campus", "1.0", "echo 1.0", "f"])
        rc, out, err = self.drift(self.env(), "--pins", pins, stdin=b"typed 9.9\n")
        self.assertEqual(rc, 0, out + err)
        self.assertIn("  reader      campus  ok\n", out)
        self.assertIn("  after       campus  ok\n", out)

    def test_a_tool_killed_by_a_signal_printed_nothing(self):
        tool = _script(os.path.join(self.tmp, "segv"), "kill -SEGV $$\n")
        pins = self.pins(["segv", "campus", "1.0", tool, "f"])
        rc, out, err = self.drift(self.env(), "--pins", pins)
        self.assertEqual(rc, 0, out + err)
        self.assertIn("DID NOT START (exit 139: (it printed nothing))", out)

    def test_with_no_interpreter_handed_over_it_refuses_and_says_how_to_run_it(self):
        for unset in ("ENV_DRIFT_PYTHON", "ENV_DRIFT_MAIN"):
            rc, out, err = self.drift(self.env(**{unset: None}), "--pins", self.pins())
            self.assertEqual(rc, 2, out + err)
            self.assertIn("run it as bazel run //tools:env_drift", err)
            self.assertEqual(out, "")

    def test_the_python_half_alone_refuses_a_hand_run(self):
        p = subprocess.run([sys.executable, "-I", os.path.join(TOOLS, "env_drift.py")],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(p.returncode, 2)
        self.assertIn(b"bazel run //tools:env_drift", p.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
