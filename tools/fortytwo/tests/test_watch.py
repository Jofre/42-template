"""watch.py: when it runs, when it cancels, when it waits, and when it stops.

The runs are stand-ins (no Bazel); the files are real, and each "save" moves
a file's mtime by hand, so no test depends on how fine the clock is.
"""

import io
import os
import tempfile
import unittest

import common  # noqa: F401
import watch


class Out:
    def __init__(self):
        self.lines = []

    def say(self, text=""):
        self.lines.append(text)


class Files:
    def __init__(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.paths = []
        for name in ("a.c", "b.c"):
            p = os.path.join(self.tmp.name, name)
            with open(p, "w") as f:
                f.write(name)
            self.paths.append(p)
        self.ns = 10 ** 18

    def save(self, i=0):
        self.ns += 10 ** 9
        os.utime(self.paths[i], ns=(self.ns, self.ns))

    def __call__(self):
        return list(self.paths)


class Keys:
    """quit() plays a script, one step per call: 'q', a callable (a save), or None."""

    def __init__(self, script):
        self.script = list(script)
        self.calls = 0

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        pass

    def quit(self, timeout=0.0):
        self.calls += 1
        if not self.script:
            return True
        step = self.script.pop(0)
        if step == "q":
            return True
        if callable(step):
            step()
        return False


class Run:
    """A stand-in for main.Run: asks stop() `polls` times, as Bazel would run that long."""

    log = []

    def __init__(self, rc=3, polls=2, during=None, after=None):
        self.rc, self.polls, self.during, self.after = rc, polls, during, after
        self.cancelled = False

    def go(self, stop=None):
        Run.log.append("run")
        for i in range(self.polls):
            if self.during and i in self.during:
                self.during[i]()
            if stop():
                self.cancelled = True
                Run.log.append("cancelled")
                return 8
        if self.after:  # a save after the run's last check: it ends with its result
            self.after()
        return self.rc


class Loop(unittest.TestCase):
    def setUp(self):
        self.f = Files()
        self.out = Out()
        Run.log = []

    def tearDown(self):
        self.f.tmp.cleanup()

    def watch(self, keys, runs):
        it = iter(runs)
        return watch.Watch(self.out, "proj ex00", self.f, lambda: next(it), keys=keys, poll=0)

    def test_it_runs_at_once_and_again_after_a_save(self):
        # run 1 polls twice, the idle wait three times, a save, one poll to
        # settle, run 2 polls twice, then q while idle.
        keys = Keys([None, None, None, None, None, self.f.save, None, None, None, "q"])
        rc = self.watch(keys, [Run(3), Run(0)]).loop()
        self.assertEqual(Run.log, ["run", "run"])
        self.assertEqual(rc, 0)

    def test_no_save_no_run(self):
        keys = Keys([None] * 30 + ["q"])
        self.watch(keys, [Run(3)]).loop()
        self.assertEqual(Run.log, ["run"])

    def test_a_save_during_a_run_cancels_it_and_it_runs_again(self):
        keys = Keys([None] * 6 + ["q"])
        first = Run(3, polls=4, during={1: self.f.save})
        self.watch(keys, [first, Run(3)]).loop()
        self.assertEqual(Run.log, ["run", "cancelled", "run"])
        self.assertTrue(any("saved during the run" in l for l in self.out.lines))

    def test_a_save_the_run_did_not_stop_for_runs_it_again(self):
        # Seen in the first trial of watch over an edit: the save landed in
        # the run's last half second, so the run ended with its result. The
        # contents now on disk were never tested, and watch waited for
        # another save.
        keys = Keys([None] * 6 + ["q"])
        self.watch(keys, [Run(3, after=self.f.save), Run(3)]).loop()
        self.assertEqual(Run.log, ["run", "run"])
        self.assertFalse(any("save one to run again" in l for l in self.out.lines[:-1]))

    def test_it_waits_for_the_saves_to_settle(self):
        # Saves on three polls in a row: one run after them, not three.
        keys = Keys([None, None, self.f.save, self.f.save, self.f.save, None, None, None, "q"])
        self.watch(keys, [Run(3), Run(3), Run(3)]).loop()
        self.assertEqual(Run.log, ["run", "run"])

    def test_q_during_a_run_stops_it_and_quits(self):
        keys = Keys([None, "q"])
        rc = self.watch(keys, [Run(3, polls=5), Run(3)]).loop()
        self.assertEqual(Run.log, ["run", "cancelled"])
        self.assertEqual(rc, 8)

    def test_ctrl_c_in_a_run_quits(self):
        keys = Keys([None] * 10)
        rc = self.watch(keys, [Run(8), Run(3)]).loop()
        self.assertEqual((Run.log, rc), (["run"], 8))

    def test_it_never_runs_another_scope_or_asks_for_hints(self):
        keys = Keys([None, self.f.save, None, None, "q"])
        made = []

        def make():
            made.append(1)
            return Run(3)
        watch.Watch(self.out, "proj ex00", self.f, make, keys=keys, poll=0).loop()
        self.assertEqual(len(made), 2)
        self.assertFalse(any("clues" in l for l in self.out.lines))


class RealKeys(unittest.TestCase):
    def test_a_pipe_says_q(self):
        r, w = os.pipe()
        os.write(w, b"x\nq\n")
        with os.fdopen(r) as f:
            k = watch.Keys(f)
            self.assertTrue(k.quit(1.0))
        os.close(w)

    def test_dev_null_never_quits_and_ends(self):
        with open(os.devnull) as f:
            k = watch.Keys(f)
            self.assertFalse(k.quit(0.0))
            self.assertIsNone(k.fd)
            self.assertFalse(k.quit(0.0))

    def test_no_stdin_at_all(self):
        k = watch.Keys(io.StringIO(""))
        self.assertIsNone(k.fd)
        self.assertFalse(k.quit(0.0))


class Tmux(unittest.TestCase):
    """--tmux, as --dry-run prints it: the pane runs this checkout's 42 with the scope resolved here."""

    def test_the_pane_command(self):
        from common import WS, run42
        with tempfile.TemporaryDirectory() as d:
            fake = os.path.join(d, "tmux")
            with open(fake, "w") as f:
                f.write("#!/bin/sh\nexit 0\n")
            os.chmod(fake, 0o755)
            env = {"PATH": d + os.pathsep + os.environ.get("PATH", ""), "HOME": d, "SUBMIT_GATE": "basic"}
            cwd = os.path.join(WS, "c-piscine", "c-piscine-c-05", "tests", "ex03")
            rc, out, err = run42(["watch", "--tmux", "--dry-run"], cwd, dict(env, TMUX="/tmp/x,1,0"))
            self.assertEqual(rc, 0, err)
            self.assertIn("$ tmux split-window -h -c %s 'sh %s/tools/42.sh watch c-05 ex03 --level basic'" % (cwd, WS), out)
            rc, out, err = run42(["watch", "--tmux", "--dry-run"], cwd, env)
            self.assertIn("$ tmux new-session -c %s ';' split-window -h" % cwd, out)
            rc, out, err = run42(["watch", "--tmux", "--dry-run"], cwd, {"PATH": d + "/none", "HOME": d})
            self.assertEqual(rc, 2)
            self.assertIn("needs tmux", err)


if __name__ == "__main__":
    unittest.main()
