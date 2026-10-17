"""doctor.py: what blocks, what it says on a cold checkout, and what it reads.

Bazel is a stand-in that writes down any call (test_main.Env): on a cold root
42 doctor must not start it, and --dry-run never does.
"""

import locale
import os
import re
import shutil
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
        self.addCleanup(self.env.close)
        self.root = tempfile.TemporaryDirectory()
        self.addCleanup(self.root.cleanup)

    def doctor(self, argv, environ=None, cold=True):
        # The servers this machine runs are not the test's: Proc covers the scan.
        # Nor is its container: these run outside one (ContainerShim covers it).
        # Nor is the disk cache a hand run's real checkout names (DiskCache
        # covers it), nor its /etc/bazel.bazelrc, which Env's
        # C_PISCINE_SYSTEM_BAZELRC points away.
        patches = [mock.patch.object(report, "state_root", lambda ws, env=None: self.root.name),
                   mock.patch.object(doctor, "servers", lambda proc="/proc": []),
                   mock.patch.object(doctor, "disk_cache", lambda ws, env: None),
                   mock.patch.object(doctor, "DOCKERENV",
                                     os.path.join(self.env.tmp, "no-dockerenv"))]
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

    def test_a_cold_ready_says_the_fetched_tools_are_checked_later(self):
        # Ready, since nothing blocks, and one line on what it could not ask:
        # whether the fetched tools start here, which needs them fetched.
        rc, out, err = self.doctor([])
        self.assertEqual(rc, 0, out + err)
        tail = out.rstrip().splitlines()[-2:]
        self.assertEqual(tail[0], "Ready to run the tests.", out)
        self.assertIn("once a first run has fetched them", tail[1])
        self.assertIn("`42 doctor --drift`", tail[1])

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


class Drift(unittest.TestCase):
    """What env_drift found decides the verdict (V240, V243).

    The stand-in bazel runs the real tools/env_drift.sh over a pins file of
    one row whose fetched binary is a stand-in too, in a workspace of its own,
    off campus: doctor reads the line env_drift prints, never a copy of it.
    """

    PIN = "GNU nm (GNU Binutils for Ubuntu) 2.38"
    ROW = "true\tcampus\t%s\techo %s\tfixture\tFT_FETCHED\n" % (PIN, PIN)

    def setUp(self):
        self.env = Env()
        self.addCleanup(self.env.close)
        self.root = tempfile.TemporaryDirectory()
        self.addCleanup(self.root.cleanup)
        self.d = tempfile.TemporaryDirectory()
        self.addCleanup(self.d.cleanup)
        os.makedirs(os.path.join(self.d.name, "ws", "tools"))
        with open(os.path.join(WS, "tools", "drives.sh"), encoding="utf-8") as f:
            self.write(os.path.join("ws", "tools", "drives.sh"), f.read())
        self.write("pins.tsv", self.ROW)

    def write(self, name, text, mode=0o644):
        p = os.path.join(self.d.name, name)
        with open(p, "w", encoding="utf-8") as f:
            f.write(text)
        os.chmod(p, mode)
        return p

    def bazel(self, body):
        self.write(os.path.join(self.env.bin, "bazel"),
                   '#!/bin/sh\necho "$0 $*" >> "%s"\n%s' % (self.env.calls, body), 0o755)

    def env_drift(self, fetched):
        """bazel run //tools:env_drift, with FT_FETCHED a binary printing `fetched`."""
        tool = self.write("fetched.sh", "#!/bin/sh\n" + fetched, 0o755)
        self.bazel('C_PISCINE_CAMPUS=0 FT_FETCHED="%s" BUILD_WORKSPACE_DIRECTORY="%s" '
                   'exec sh "%s" --pins "%s"\n'
                   % (tool, os.path.join(self.d.name, "ws"),
                      os.path.join(WS, "tools", "env_drift.sh"),
                      os.path.join(self.d.name, "pins.tsv")))

    def doctor(self):
        with mock.patch.object(report, "state_root", lambda ws, env=None: self.root.name), \
                mock.patch.object(doctor, "servers", lambda proc="/proc": []), \
                mock.patch.object(doctor, "disk_cache", lambda ws, env: None), \
                mock.patch.object(report, "coldness", lambda ws, env=None, root=None: None):
            return run42(["doctor"], WS, self.env.environ)

    def test_a_fetched_tool_that_cannot_start_blocks(self):
        # The loader's error names the pinned version: graded, it read "ok".
        self.env_drift('echo "$0: error while loading shared libraries: libbfd-2.38-system.so: '
                       'cannot open shared object file" >&2\nexit 127\n')
        rc, out, err = self.doctor()
        self.assertIn("bazel run //tools:env_drift", self.env.called())
        self.assertEqual(rc, 1, out + err)
        self.assertIn("UNRUNNABLE", out)
        self.assertRegex(out, r"BLOCK +1 fetched tool cannot start on this machine")
        self.assertIn("dev container", out)
        self.assertIn("Not ready: 1 blocker(s) above.", out)

    def test_tools_that_start_are_ready(self):
        self.env_drift('echo "GNU nm (GNU Binutils for Ubuntu) 2.38"\n')
        rc, out, err = self.doctor()
        self.assertEqual(rc, 0, out + err)
        self.assertIn("0 unrunnable", out)
        self.assertNotIn("BLOCK", out)
        self.assertTrue(out.rstrip().endswith("Ready to run the tests."), out)

    def test_a_build_that_failed_is_not_ready(self):
        # Bazel's own exit 1, which is also env_drift's: no summary line came.
        # On stdout, which doctor shows and the test keeps: on stderr it
        # reached this test's log as an ERROR beside a test that passed.
        self.bazel('echo "an external repository could not be fetched"\nexit 1\n')
        rc, out, err = self.doctor()
        self.assertEqual(rc, 1, out + err)
        self.assertIn("an external repository could not be fetched", out)
        self.assertRegex(out, r"BLOCK +env_drift did not finish \(exit 1")
        self.assertIn("usually a build or download", out)
        self.assertIn("Not ready: 1 blocker(s) above.", out)
        self.assertNotIn("Ready to run the tests.", out)

    def test_env_drift_that_refused_is_named_not_the_build(self):
        # env_drift's own exit 2, a pins file it cannot read: the build went
        # fine, so the BLOCK blames env_drift's reason, never a download.
        # Its stderr joins stdout so that the reason stays out of this log.
        self.bazel('C_PISCINE_CAMPUS=0 BUILD_WORKSPACE_DIRECTORY="%s" '
                   'exec sh "%s" --pins "%s" 2>&1\n'
                   % (os.path.join(self.d.name, "ws"),
                      os.path.join(WS, "tools", "env_drift.sh"),
                      os.path.join(self.d.name, "no-such-pins.tsv")))
        rc, out, err = self.doctor()
        self.assertEqual(rc, 1, out + err)
        self.assertIn("env_drift.sh: cannot read", out)
        self.assertRegex(out, r"BLOCK +env_drift did not finish \(exit 2")
        self.assertIn("refused to start", out)
        self.assertNotIn("build or download", out)
        self.assertIn("Not ready: 1 blocker(s) above.", out)

    def test_the_summary_line_is_the_one_env_drift_prints(self):
        # doctor's pattern over env_drift's own line, its counts filled in.
        with open(os.path.join(WS, "tools", "env_drift.sh"), encoding="utf-8") as f:
            line = re.search(r'^SUMMARY="(.*)"$', f.read(), re.M).group(1)
        m = doctor.DRIFT_SUMMARY.match("  " + re.sub(r"\$[A-Z_]+", "3", line))
        self.assertIsNotNone(m, line)
        self.assertEqual(m.group(1), "3")


class RunCleanup(unittest.TestCase):
    """Run's folders go whatever fails: a setUp after them, or the removal of one."""

    def test_a_set_up_that_fails_leaves_no_folder(self):
        folders = []

        class Fails(Run):
            def setUp(self):
                super().setUp()
                folders.extend([self.env.tmp, self.root.name])
                raise RuntimeError("a setUp that fails after its folders")

            def runTest(self):
                pass

        result = unittest.TestResult()
        Fails().run(result)
        self.assertEqual(len(result.errors), 1, result.failures)
        for d in folders:
            self.assertFalse(os.path.exists(d), "the case left %s behind" % d)

    def test_a_removal_that_fails_still_removes_the_other(self):
        folders, roots = [], []

        class Removes(Run):
            def runTest(self):
                folders.extend([self.env.tmp, self.root.name])
                roots.append(self.root)

        def fails(self):
            raise OSError("a removal that fails")

        result = unittest.TestResult()
        with mock.patch.object(tempfile.TemporaryDirectory, "cleanup", fails):
            Removes().run(result)
        # Its own cleanup(), unpatched: it also detaches the finalizer that
        # would otherwise remove the folder later, with a ResourceWarning.
        roots[0].cleanup()
        self.assertEqual(len(result.errors), 1, result.failures)
        self.assertIn("a removal that fails", result.errors[0][1])
        self.assertFalse(os.path.exists(folders[0]), "the case left %s behind" % folders[0])
        self.assertFalse(os.path.exists(folders[1]), "cleanup() left %s behind" % folders[1])


class Shim(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.TemporaryDirectory()
        self.addCleanup(self.d.cleanup)
        self.c = doctor.Check()
        # Outside a container, whatever this machine is: ContainerShim has the rest.
        p = mock.patch.object(doctor, "DOCKERENV", os.path.join(self.d.name, "no-dockerenv"))
        p.start()
        self.addCleanup(p.stop)

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
        self.assertIn("sh tools/fortytwo/install.sh", self.c.rows[0][1])


class Proc(unittest.TestCase):
    """servers() and the memory row, on a /proc of fixture files."""

    def setUp(self):
        self.d = tempfile.TemporaryDirectory()
        self.addCleanup(self.d.cleanup)
        p = self.d.name
        self.proc(100, b"/usr/lib/jvm/bin/java\0-jar\0/r/install/A-server.jar\0"
                       b"--output_base=/r/abc\0--workspace_directory=/ws/a\0", 1048576)
        # A shell whose command line names the jar is no server.
        self.proc(200, b"sh\0-c\0case $c in *A-server.jar*) echo;; esac\0", 2048)
        os.makedirs(os.path.join(p, "self"))
        with open(os.path.join(p, "meminfo"), "w") as f:
            f.write("MemTotal: 8388608 kB\nMemAvailable: 2097152 kB\n")

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


class Locale(unittest.TestCase):
    """The locale .bazelrc runs every test under, asked of this machine (V245)."""

    def test_it_is_the_one_bazelrc_sets(self):
        with open(os.path.join(WS, ".bazelrc"), encoding="utf-8") as f:
            lines = f.read().splitlines()
        self.assertIn("test --test_env=LC_ALL=%s" % doctor.TEST_LOCALE, lines)

    def test_installed(self):
        c = doctor.Check()
        doctor.check_locale(c, probe=lambda name: True)
        self.assertEqual(c.rows[0][0], "ok")
        self.assertIn(doctor.TEST_LOCALE, c.rows[0][1])

    def test_missing_is_a_warning_that_says_what_it_costs(self):
        c = doctor.Check()
        doctor.check_locale(c, probe=lambda name: False)
        self.assertEqual(c.blockers(), 0)
        mark, text = c.rows[0]
        self.assertEqual(mark, "warn")
        self.assertIn("en_US.UTF-8", text)
        self.assertIn("sudo locale-gen en_US.UTF-8", text)
        self.assertIn("shell-01 ex07", text)
        # show() puts 8 columns before each line: the row's prose, which
        # test_the_prose_fits_80_columns sees only where the locale is missing.
        for line in text.split("\n"):
            self.assertLessEqual(len(line), 72, line)

    def test_the_default_probe_leaves_the_locale_as_it_was(self):
        before = locale.setlocale(locale.LC_COLLATE)
        self.assertFalse(doctor.locale_installed("xx_XX.UTF-8"))
        self.assertTrue(doctor.locale_installed("C"))
        self.assertEqual(locale.setlocale(locale.LC_COLLATE), before)


class LocaleDistributions(unittest.TestCase):
    """The missing locale's fix differs by distribution, and the row names three (V279)."""

    def test_ubuntu_debian_and_fedora(self):
        c = doctor.Check()
        doctor.check_locale(c, probe=lambda name: False)
        text = c.rows[0][1]
        for said in ("Ubuntu", "sudo locale-gen en_US.UTF-8", "Debian", "/etc/locale.gen",
                     "en_US.UTF-8 UTF-8", "Fedora", "sudo dnf install glibc-langpack-en"):
            self.assertIn(said, text)
        for line in text.split("\n"):
            self.assertLessEqual(len(line), 72, line)


class ContainerShim(unittest.TestCase):
    """In a dev container whose postcreate.sh never ran, doctor names it (V252).

    The probe is overridden both ways (REMOTE_CONTAINERS, and the marker file
    Docker writes, here a file of the test's), and the system rc is one that
    does not exist, so no case reads this machine's.
    """

    def setUp(self):
        d = tempfile.TemporaryDirectory()
        self.addCleanup(d.cleanup)
        self.d = d.name
        for sub in ("bin", "home", "ws"):
            os.makedirs(os.path.join(self.d, sub))
        self.ws = os.path.join(self.d, "ws")
        self.marker = os.path.join(self.d, "dockerenv")
        p = mock.patch.object(doctor, "DOCKERENV", self.marker)
        p.start()
        self.addCleanup(p.stop)

    def env(self, **kw):
        return dict({"PATH": os.path.join(self.d, "bin"),
                     "HOME": os.path.join(self.d, "home"),
                     "C_PISCINE_SYSTEM_BAZELRC": os.path.join(self.d, "no-system-rc")}, **kw)

    def row(self, env):
        c = doctor.Check()
        doctor.check_shim(c, self.ws, env)
        self.assertEqual(len(c.rows), 1, c.rows)
        mark, text = c.rows[0]
        self.assertEqual(mark, "warn")
        self.assertIn("no `42` on your PATH", text)
        for line in text.split("\n"):
            self.assertLessEqual(len(line), 72, line)
        return text

    def put(self, path, text):
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)

    def test_remote_containers_names_postcreate(self):
        text = self.row(self.env(REMOTE_CONTAINERS="true"))
        self.assertIn("sh .devcontainer/postcreate.sh", text)
        self.assertNotIn("install.sh", text)

    def test_the_docker_marker_names_postcreate(self):
        self.put(self.marker, "")
        text = self.row(self.env())
        self.assertIn("sh .devcontainer/postcreate.sh", text)

    def test_the_knob_stands_in_for_the_marker(self):
        # C_PISCINE_DOCKERENV, the name tools/drives.sh reads too.
        self.put(os.path.join(self.d, "elsewhere"), "")
        text = self.row(self.env(C_PISCINE_DOCKERENV=os.path.join(self.d, "elsewhere")))
        self.assertIn("sh .devcontainer/postcreate.sh", text)

    def test_outside_a_container_the_installer(self):
        text = self.row(self.env())
        self.assertIn("sh tools/fortytwo/install.sh", text)
        self.assertNotIn("postcreate", text)

    def test_a_disk_cache_in_the_checkouts_rc_is_no_sign(self):
        # The host's setup.sh writes that file; postcreate.sh writes only
        # ~/.bazelrc, so a disk cache in the checkout's says nothing of it
        # (V329), and the step is still named.
        self.put(os.path.join(self.ws, ".bazelrc.local"), "build --disk_cache=/somewhere\n")
        text = self.row(self.env(REMOTE_CONTAINERS="true"))
        self.assertIn("sh .devcontainer/postcreate.sh", text)
        self.assertNotIn("install.sh", text)

    def test_a_disk_cache_in_the_home_rc_is_no_sign(self):
        self.put(os.path.join(self.d, "home", ".bazelrc"), "build --disk_cache /somewhere\n")
        text = self.row(self.env(REMOTE_CONTAINERS="true"))
        self.assertNotIn("postcreate", text)

    def test_an_empty_disk_cache_in_the_home_rc_is_a_line_too(self):
        # postcreate.sh keeps a line that sets the flag, with no value too.
        self.put(os.path.join(self.d, "home", ".bazelrc"), "build --disk_cache=\n")
        text = self.row(self.env(REMOTE_CONTAINERS="true"))
        self.assertNotIn("postcreate", text)


class StateFile(unittest.TestCase):
    """A root an rc file names that cannot be created here: the BLOCK names the file (V239).

    A toy checkout with tools/drives.sh, whose .bazelrc.local roots Bazel
    below a folder nobody here may write, as a host's setup.sh did for a dev
    container on the same checkout. postcreate.sh's step is offered in a
    container only (REMOTE_CONTAINERS here; the marker file is one that does
    not exist): on a host, the root it writes to ~/.bazelrc would outrank
    every checkout's.
    """

    def setUp(self):
        d = tempfile.TemporaryDirectory()
        self.addCleanup(d.cleanup)
        self.d = d.name
        self.ws = os.path.join(self.d, "ws")
        os.makedirs(os.path.join(self.ws, "tools"))
        os.makedirs(os.path.join(self.d, "home"))
        shutil.copy(os.path.join(WS, "tools", "drives.sh"), os.path.join(self.ws, "tools"))
        p = mock.patch.object(doctor, "DOCKERENV", os.path.join(self.d, "no-dockerenv"))
        p.start()
        self.addCleanup(p.stop)
        self.env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "USER": "probe",
                    "HOME": os.path.join(self.d, "home"),
                    "C_PISCINE_GOINFRE": os.path.join(self.d, "no-goinfre"),
                    "C_PISCINE_LEGACY_ROOT": os.path.join(self.d, "no-legacy"),
                    "C_PISCINE_SYSTEM_BAZELRC": os.path.join(self.d, "no-system-rc")}

    def block(self, root, **env):
        with open(os.path.join(self.ws, ".bazelrc.local"), "w", encoding="utf-8") as f:
            f.write("startup --output_user_root=%s\n" % root)
        c = doctor.Check()
        doctor.check_state(c, self.ws, dict(self.env, **env))
        self.assertEqual(c.blockers(), 1, c.rows)
        text = c.rows[0][1]
        self.assertIn(root, text)
        self.assertIn("That root is set in", text)
        self.assertIn(".bazelrc.local", text)
        for line in text.split("\n"):
            self.assertLessEqual(len(re.sub(r"/\S+", "/", line)), 72, line)
        return text

    def read_only(self):
        ro = os.path.join(self.d, "ro")
        os.makedirs(ro)
        os.chmod(ro, 0o555)
        self.addCleanup(os.chmod, ro, 0o755)
        return os.path.join(ro, "x", "bazel")

    def plain_file(self):
        # mkdir refuses this for root too, so these cases run on any machine.
        with open(os.path.join(self.d, "file"), "w"):
            pass
        return os.path.join(self.d, "file", "x", "bazel")

    @unittest.skipIf(os.geteuid() == 0, "root writes a folder of mode 555")
    def test_below_a_folder_it_cannot_write(self):
        text = self.block(self.read_only(), REMOTE_CONTAINERS="true")
        self.assertIn("cannot be written", text)
        self.assertIn("sh .devcontainer/postcreate.sh", text)
        self.assertIn("~/.bazelrc", text)

    @unittest.skipIf(os.geteuid() == 0, "root writes a folder of mode 555")
    def test_outside_a_container_no_container_step(self):
        text = self.block(self.read_only())
        self.assertNotIn("postcreate", text)
        self.assertNotIn("~/.bazelrc", text)

    def test_below_a_plain_file(self):
        text = self.block(self.plain_file(), REMOTE_CONTAINERS="true")
        self.assertIn("is not a folder", text)
        self.assertNotIn("cannot be written", text)
        self.assertIn("sh .devcontainer/postcreate.sh", text)

    def test_below_a_plain_file_outside_a_container(self):
        text = self.block(self.plain_file())
        self.assertIn("is not a folder", text)
        self.assertNotIn("postcreate", text)


class DiskCache(unittest.TestCase):
    """A disk cache an rc file names that cannot be created here: a BLOCK naming the file (V329).

    Bazel stops every command over one ("Error initializing RemoteModule",
    naming no file). A toy checkout whose .bazelrc.local names it below a
    plain file, which mkdir refuses root too, as a dev container's host's
    setup.sh named one under the host's home. The system rc is one that does
    not exist, and the container probe is overridden both ways.
    """

    def setUp(self):
        d = tempfile.TemporaryDirectory()
        self.addCleanup(d.cleanup)
        self.d = d.name
        self.ws = os.path.join(self.d, "ws")
        self.home = os.path.join(self.d, "home")
        os.makedirs(os.path.join(self.ws, "tools"))
        os.makedirs(self.home)
        shutil.copy(os.path.join(WS, "tools", "drives.sh"), os.path.join(self.ws, "tools"))
        with open(os.path.join(self.d, "file"), "w"):
            pass
        self.bad = os.path.join(self.d, "file", "x", "bazel-disk")
        p = mock.patch.object(doctor, "DOCKERENV", os.path.join(self.d, "no-dockerenv"))
        p.start()
        self.addCleanup(p.stop)
        self.env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "USER": "probe",
                    "HOME": self.home,
                    "C_PISCINE_SYSTEM_BAZELRC": os.path.join(self.d, "no-system-rc")}

    def put(self, path, text):
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)

    def local(self, text):
        self.put(os.path.join(self.ws, ".bazelrc.local"), text)

    def rows(self, **env):
        c = doctor.Check()
        doctor.check_disk_cache(c, self.ws, dict(self.env, **env))
        for _, text in c.rows:
            for line in text.split("\n"):
                self.assertLessEqual(len(re.sub(r"/\S+", "/", line)), 72, line)
        return c

    def block(self, **env):
        c = self.rows(**env)
        self.assertEqual(c.blockers(), 1, c.rows)
        return c.rows[0][1]

    def test_doctor_is_not_ready_in_a_container(self):
        # The whole run, as a student meets it: a cold checkout, no 42 yet.
        self.local("build --disk_cache=%s\nbuild --experimental_disk_cache_gc_max_size=4G\n"
                   % self.bad)
        fake = Env()
        self.addCleanup(fake.close)
        root = os.path.join(self.d, "root")
        environ = dict(fake.environ, PATH=fake.bin + os.pathsep + "/usr/bin:/bin", HOME=self.home,
                       REMOTE_CONTAINERS="true")
        with mock.patch.object(report, "state_root", lambda ws, env=None: root), \
                mock.patch.object(doctor, "servers", lambda proc="/proc": []):
            rc, out, err = run42(["doctor", "--dry-run"], self.ws, environ, ws=self.ws)
        self.assertEqual(rc, 1, out + err)
        self.assertIn(self.bad, out)
        self.assertIn(".bazelrc.local, line 1", out)
        self.assertIn("sh .devcontainer/postcreate.sh", out)
        self.assertNotIn("Ready to run the tests.", out)

    def test_below_a_plain_file_in_a_container(self):
        self.local("build --disk_cache=%s\n" % self.bad)
        text = self.block(REMOTE_CONTAINERS="true")
        self.assertIn(self.bad, text)
        self.assertIn("is not a folder", text)
        self.assertIn(".bazelrc.local, line 1", text)
        self.assertIn("sh .devcontainer/postcreate.sh", text)
        self.assertIn("`build --disk_cache=`", text)

    def test_outside_a_container_the_file_alone(self):
        self.local("build --disk_cache=%s\n" % self.bad)
        text = self.block()
        self.assertIn(".bazelrc.local, line 1", text)
        self.assertNotIn("postcreate", text)

    @unittest.skipIf(os.geteuid() == 0, "root writes a folder of mode 555")
    def test_below_a_folder_it_cannot_write(self):
        ro = os.path.join(self.d, "ro")
        os.makedirs(ro)
        os.chmod(ro, 0o555)
        self.addCleanup(os.chmod, ro, 0o755)
        self.local("build --disk_cache=%s/x/bazel-disk\n" % ro)
        self.assertIn("cannot be written", self.block())

    def test_the_home_rc_read_after_it_wins(self):
        self.local("build --disk_cache=%s\n" % self.bad)
        self.put(os.path.join(self.home, ".bazelrc"),
                 "build --disk_cache=%s\n" % os.path.join(self.d, "mine", "bazel-disk"))
        c = self.rows(REMOTE_CONTAINERS="true")
        self.assertEqual(c.blockers(), 0, c.rows)
        self.assertEqual(c.rows[0][0], "ok", c.rows)

    def test_an_empty_value_turns_the_cache_off(self):
        # Bazel takes `--disk_cache=` as no cache (measured on 9.2.0, exit 0),
        # so the line before it is not the one it uses.
        self.local("build --disk_cache=%s\n" % self.bad)
        self.put(os.path.join(self.home, ".bazelrc"), "build --disk_cache=\n")
        self.assertEqual(self.rows(REMOTE_CONTAINERS="true").rows, [])

    def test_none_says_nothing(self):
        self.local("build --experimental_disk_cache_gc_max_size=4G\n")
        self.assertEqual(self.rows().rows, [])

    def test_the_home_rc_is_edited_there(self):
        self.put(os.path.join(self.home, ".bazelrc"), "build --disk_cache=%s\n" % self.bad)
        text = self.block(REMOTE_CONTAINERS="true")
        self.assertIn("~/.bazelrc, line 1", text)
        self.assertIn("`build --disk_cache=`", text)
        self.assertNotIn("postcreate", text)

    def test_a_tilde_is_the_passwd_home(self):
        # Bazel reads `~/` from the passwd file, never from $HOME.
        self.local("build --disk_cache=~/x/bazel-disk\n")
        with mock.patch.object(doctor, "passwd_home", lambda: os.path.join(self.d, "file")):
            text = self.block()
        self.assertIn(os.path.join(self.d, "file", "x", "bazel-disk"), text)

    def test_a_relative_folder_is_the_checkouts(self):
        self.put(os.path.join(self.ws, "plain"), "")
        self.local("build --disk_cache=plain/x\n")
        self.assertIn(os.path.join(self.ws, "plain", "x"), self.block())


if __name__ == "__main__":
    unittest.main()
