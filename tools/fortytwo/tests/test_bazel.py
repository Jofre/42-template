"""bazel.py: the argv 42 builds, the env its child gets, the BEP it reads, and Ctrl-C."""

import ast
import json
import os
import signal
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest

from common import FIXTURES, HERE
import bazel


def bep(name):
    return bazel.read_bep(os.path.join(FIXTURES, "bep", name + ".json"))


def write_bep(path, events):
    with open(path, "w") as f:
        f.write("".join(json.dumps(e) + "\n" for e in events))


def write_exe(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)
    os.chmod(path, 0o755)


# What a load of bep.x does when it only feeds a write to x.
WRITES = ("append", "extend", "insert", "add", "update", "setdefault")


def unread_fields(modules):
    """The fields Bep.__init__ sets that no module's source reads.

    A read is an attribute load, but for one that only feeds a write: the
    container of a subscript stored to or deleted (bep.x[k] = v, del
    bep.x[k]), or the receiver of a call in WRITES (bep.x.append(v)).
    """
    trees = [ast.parse(text) for text in modules]
    cls = next(n for t in trees for n in t.body if isinstance(n, ast.ClassDef) and n.name == "Bep")
    init = next(n for n in cls.body if isinstance(n, ast.FunctionDef) and n.name == "__init__")
    fields = {t.attr for st in init.body if isinstance(st, ast.Assign)
              for t in st.targets if isinstance(t, ast.Attribute)}
    assert "logs" in fields, fields
    read = set()
    for tree in trees:
        writes = set()
        for n in ast.walk(tree):
            if isinstance(n, ast.Subscript) and isinstance(n.ctx, (ast.Store, ast.Del)):
                writes.add(id(n.value))
            elif (isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
                    and n.func.attr in WRITES):
                writes.add(id(n.func.value))
        read |= {n.attr for n in ast.walk(tree) if isinstance(n, ast.Attribute)
                 and isinstance(n.ctx, ast.Load) and id(n) not in writes}
    return sorted(fields - read)


class Argv(unittest.TestCase):
    def test_the_command_a_student_could_type(self):
        self.assertEqual(
            bazel.test_argv(["//c-piscine/c-piscine-c-05/..."], "lvl_basic,-manual", ["--nocache_test_results"]),
            ["bazel", "test", "//c-piscine/c-piscine-c-05/...", "--test_tag_filters=lvl_basic,-manual",
             "--nocache_test_results"])
        self.assertEqual(bazel.test_argv(["//x:y"]), ["bazel", "test", "//x:y"])

    def test_plumbing_is_only_the_measured_free_flags(self):
        self.assertEqual(bazel.plumbing("/r/bep.json", "ID"), [
            "--build_tests_only", "--build_event_json_file=/r/bep.json",
            "--build_event_json_file_path_conversion=false", "--invocation_id=ID"])

    def test_startup_options_go_before_the_command(self):
        self.assertEqual(bazel.with_startup(["/bin/bazel", "test", "//x:y"]),
                         ["/bin/bazel", "--noblock_for_lock", "test", "//x:y"])

    def test_shell_line_names_bazel_and_quotes(self):
        self.assertEqual(bazel.shell_line(["/usr/local/bin/bazelisk", "run", "//tools:norminette", "--", "a b.c"]),
                         "bazel run //tools:norminette -- 'a b.c'")


class RunDir(unittest.TestCase):
    def test_under_xdg_runtime_dir_else_the_temporary_folder(self):
        with tempfile.TemporaryDirectory() as d:
            r = bazel.run_dir({"XDG_RUNTIME_DIR": d})
            self.assertEqual(os.path.dirname(r), os.path.join(d, "42"))
            r2 = bazel.run_dir({"XDG_RUNTIME_DIR": os.path.join(d, "gone")})
            try:
                self.assertEqual(os.path.dirname(r2), tempfile.gettempdir())
            finally:
                os.rmdir(r2)


class Env(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.ws = os.path.join(self.tmp.name, "ws")
        open(os.path.join(self.tmp.name, "MODULE.bazel"), "w").close()  # a decoy: not a tools/ folder
        os.makedirs(os.path.join(self.ws, "tools"))
        open(os.path.join(self.ws, "MODULE.bazel"), "w").close()
        write_exe(os.path.join(self.ws, "tools", "bazel"), "#!/bin/sh\nexit 99\n")
        self.real = os.path.join(self.tmp.name, "bin")
        write_exe(os.path.join(self.real, "bazel"), "#!/bin/sh\nexit 0\n")

    def test_what_a_bazel_run_set_is_not_inherited(self):
        env = {k: "x" for k in bazel.STRIP_ENV}
        env["KEEP"] = "1"
        self.assertEqual(bazel.child_env(env), {"KEEP": "1"})

    def test_under_bazel_run_the_wrapper_folder_leaves_path(self):
        tools = os.path.join(self.ws, "tools")
        env = {"PATH": os.pathsep.join([tools, self.real]), "BAZELISK_SKIP_WRAPPER": "true", "BAZEL_REAL": "/x"}
        self.assertEqual(bazel.child_env(env)["PATH"], self.real)
        self.assertEqual(bazel.executable(env), os.path.join(self.real, "bazel"))

    def test_outside_bazel_run_path_is_untouched(self):
        tools = os.path.join(self.ws, "tools")
        env = {"PATH": os.pathsep.join([tools, self.real])}
        self.assertEqual(bazel.child_env(env)["PATH"], env["PATH"])

    def test_bazelisk_when_there_is_no_bazel_and_a_sentence_when_neither(self):
        only = os.path.join(self.tmp.name, "only")
        write_exe(os.path.join(only, "bazelisk"), "#!/bin/sh\n")
        self.assertEqual(bazel.executable({"PATH": only}), os.path.join(only, "bazelisk"))
        with self.assertRaisesRegex(bazel.NoBazel, "setup.sh"):
            bazel.executable({"PATH": os.path.join(self.tmp.name, "none")})


class Bep(unittest.TestCase):
    """Fixtures: real BEP files of trial runs, trimmed, paths anonymised."""

    def test_failed_tests_their_tags_and_logs(self):
        b = bep("failed")
        self.assertEqual(len(b.selected), 11)
        self.assertEqual(len(b.failed()), 8)
        self.assertEqual(b.does_not_build(), [])
        out = "//c-piscine/c-piscine-c-00:ex00_output"
        self.assertIn(out, b.failed())
        self.assertIn("output", b.tags[out])
        self.assertTrue(b.logs[out].startswith("/OUTPUT_BASE/"), b.logs[out])
        self.assertTrue(b.logs[out].endswith("/ex00_output/test.log"))

    def test_a_target_that_does_not_build_has_no_summary(self):
        b = bep("does_not_build")
        self.assertEqual(b.does_not_build(), ["//spike:broken"])
        self.assertEqual(b.status, {"//spike:sleeper": "PASSED"})

    def test_a_failed_to_build_summary_does_not_build(self):
        # Bazel 9 gives a target that does not build no summary at all; a
        # stand-in for one that says FAILED_TO_BUILD: no test ran either.
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "bep.json")
            write_bep(p, [{"id": {"targetConfigured": {"label": l}}, "configured": {"testSize": "SMALL"}}
                          for l in ("//spike:broken", "//spike:red")]
                      + [{"id": {"testSummary": {"label": l}}, "testSummary": {"overallStatus": s}}
                         for l, s in (("//spike:broken", "FAILED_TO_BUILD"), ("//spike:red", "FAILED"))])
            b = bazel.read_bep(p)
        self.assertEqual((b.failed(), b.does_not_build()), (["//spike:red"], ["//spike:broken"]))

    def test_a_log_uri_is_percent_decoded(self):
        # Bazel 9.2 writes a space in the output root as %20 and a '%' as
        # %25 (measured with --output_user_root='.../sp ace%x/root').
        with tempfile.TemporaryDirectory() as d:
            log = os.path.join(d, "sp ace%x", "test.log")
            os.makedirs(os.path.dirname(log))
            open(log, "w").close()
            p = os.path.join(d, "bep.json")
            write_bep(p, [{"id": {"testResult": {"label": "//spike:red"}},
                           "testResult": {"testActionOutput": [{"name": "test.log", "uri": "file://"
                                          + log.replace("%", "%25").replace(" ", "%20")}]}}])
            b = bazel.read_bep(p)
            self.assertEqual(b.logs["//spike:red"], log)
            self.assertTrue(os.path.isfile(b.logs["//spike:red"]))

    def test_a_timeout_is_a_failure(self):
        b = bep("timeout")
        self.assertEqual(b.failed(), ["//spike:sleeper"])
        self.assertEqual(b.status["//spike:sleeper"], "TIMEOUT")

    def test_nothing_selected(self):
        b = bep("no_tests")
        self.assertEqual((b.selected, b.tags, b.status, b.logs), ([], {}, {}, {}))
        self.assertEqual((b.failed(), b.does_not_build()), ([], []))

    def test_a_bad_label(self):
        b = bep("bad_label")
        self.assertEqual((b.selected, b.tags, b.status, b.logs), ([], {}, {}, {}))
        self.assertEqual((b.failed(), b.does_not_build()), ([], []))

    def test_every_field_is_one_42_reads(self):
        # A field only the tests read is BEP parsing nothing uses: each one
        # Bep sets up is read by a module of 42's, by a load that is not
        # only the way to a write (read_bep filling it is not a read).
        src = os.path.dirname(HERE)
        modules = []
        for name in sorted(os.listdir(src)):
            if name.endswith(".py"):
                with open(os.path.join(src, name), encoding="utf-8") as f:
                    modules.append(f.read())
        self.assertEqual(unread_fields(modules), [], "read by nothing but the tests")

    def test_a_field_read_bep_only_fills_is_unread(self):
        # bep.x[label] = ... and bep.x.append(...) load bep.x, to write to it.
        bazel_py = textwrap.dedent("""\
            class Bep:
                def __init__(self):
                    self.logs = {}
                    self.keyed = {}
                    self.listed = []
                    self.merged = {}
            def read_bep(bep, label):
                bep.logs[label] = 1
                bep.keyed[label] = 1
                del bep.keyed[label]
                bep.listed.append(label)
                bep.listed.extend([label])
                bep.merged.update({})
                bep.merged.setdefault(label, 1)
            """)
        self.assertEqual(unread_fields([bazel_py]), ["keyed", "listed", "logs", "merged"])
        self.assertEqual(unread_fields([bazel_py, "print(bep.logs.get(1), len(bep.listed))\n"]),
                         ["keyed", "merged"])

    def test_a_cut_last_line_and_a_missing_file(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "bep.json")
            with open(os.path.join(FIXTURES, "bep", "timeout.json")) as f:
                text = f.read()
            with open(p, "w") as f:
                f.write(text[: text.rstrip("\n").rindex("\n") + 11])
            b = bazel.read_bep(p)
            self.assertEqual(b.status["//spike:sleeper"], "TIMEOUT")
            self.assertEqual(bazel.read_bep(os.path.join(d, "none")).selected, [])


class DropOutputs(unittest.TestCase):
    """The repair (V111): a package's outputs deleted, and nothing else, only while Bazel is idle."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        t = self.tmp.name
        self.base = os.path.join(t, "base")
        self.root = os.path.join(self.base, "execroot", "_main")
        self.files = {}
        for cfg in ("k8-fastbuild", "k8-fastbuild-ST-1234"):
            for pkg in ("course/proj", "course/proj2", "tools"):
                f = os.path.join(self.root, "bazel-out", cfg, "bin", pkg, "out")
                os.makedirs(os.path.dirname(f))
                open(f, "w").close()
                self.files[(cfg, pkg)] = f
        self.fake = os.path.join(t, "bin", "bazel")
        self.rc = os.path.join(t, "rc")
        write_exe(self.fake, '#!/bin/sh\nrc=$(cat "%s" 2>/dev/null || echo 0)\n'
                             '[ "$rc" = 0 ] && echo "%s"\nexit "$rc"\n' % (self.rc, self.root))

    def left(self):
        return sorted(k for k, f in self.files.items() if os.path.exists(f))

    def test_only_that_package_in_every_configuration(self):
        self.assertEqual(bazel.drop_outputs(self.fake, self.tmp.name, ["course/proj"], {}), bazel.OK)
        self.assertEqual(self.left(), sorted(k for k in self.files if k[1] != "course/proj"))

    def test_busy_bazel_deletes_nothing(self):
        with open(self.rc, "w") as f:
            f.write("9")
        self.assertEqual(bazel.drop_outputs(self.fake, self.tmp.name, ["course/proj"], {}), bazel.LOCK_HELD)
        self.assertEqual(len(self.left()), 6)

    def test_a_held_lock_deletes_nothing(self):
        # The `with` closes the holder's pipe; the finally stops it first.
        with subprocess.Popen([sys.executable, "-c", textwrap.dedent("""\
                import fcntl, os, sys, time
                fd = os.open(sys.argv[1], os.O_RDWR | os.O_CREAT)
                fcntl.lockf(fd, fcntl.LOCK_EX, 1, 0)
                print("held", flush=True)
                time.sleep(30)
                """), os.path.join(self.base, "lock")], stdout=subprocess.PIPE, universal_newlines=True) as holder:
            try:
                self.assertEqual(holder.stdout.readline().strip(), "held")
                self.assertEqual(bazel.drop_outputs(self.fake, self.tmp.name, ["course/proj"], {}), bazel.LOCK_HELD)
                self.assertEqual(len(self.left()), 6)
            finally:
                holder.kill()

    def test_a_path_that_is_not_a_package_is_refused(self):
        for bad in ("", "/abs", "a/../b", "a//b", ".", "a/./b"):
            with self.assertRaises(ValueError, msg=bad):
                bazel.drop_outputs(self.fake, self.tmp.name, [bad], {})
        self.assertEqual(len(self.left()), 6)


# A stand-in Bazel: counts the SIGINTs it gets, and takes a second to stop
# after the first, the way Bazel does, so a second Ctrl-C lands mid-stop.
FAKE = textwrap.dedent("""\
    import signal, sys, time
    count = sys.argv[1]
    def on_int(s, f):
        with open(count, "a") as fh:
            fh.write("INT\\n")
        time.sleep(1.0)
        sys.exit(8)
    signal.signal(signal.SIGINT, on_int)
    open(count + ".ready", "w").close()
    time.sleep(30)
    sys.exit(0)
""")

# 42's side: one Child under run_foreground, as main.run_tests runs it.
PARENT = textwrap.dedent("""\
    import sys
    sys.path.insert(0, sys.argv[1])
    import bazel
    child = bazel.Child([sys.executable, sys.argv[2], sys.argv[3]], ".", sys.argv[4])
    print(bazel.run_foreground(child, interval=0.05), flush=True)
""")


class CtrlC(unittest.TestCase):
    def test_two_ctrl_c_reach_bazel_as_one_sigint(self):
        with tempfile.TemporaryDirectory() as d:
            fake, parent = os.path.join(d, "fake.py"), os.path.join(d, "parent.py")
            with open(fake, "w") as f:
                f.write(FAKE)
            with open(parent, "w") as f:
                f.write(PARENT)
            count = os.path.join(d, "count")
            src = os.path.dirname(HERE)
            p = subprocess.Popen([sys.executable, parent, src, fake, count, os.path.join(d, "out")],
                                 cwd=d, stdout=subprocess.PIPE, universal_newlines=True)
            deadline = time.monotonic() + 20
            while not os.path.exists(count + ".ready"):
                self.assertLess(time.monotonic(), deadline, "the stand-in never started")
                time.sleep(0.05)
            p.send_signal(signal.SIGINT)
            time.sleep(0.3)
            p.send_signal(signal.SIGINT)
            out, _ = p.communicate(timeout=20)
            self.assertEqual(out.strip(), "8")
            with open(count) as f:
                self.assertEqual(f.read(), "INT\n")


if __name__ == "__main__":
    unittest.main()
