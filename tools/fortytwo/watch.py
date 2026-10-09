"""42 watch: run a scope's tests again each time one of its turn-in files is saved.

Measured before it was written (Bazel 9.2.0, 2026-10-09):
- inotify sees no edit on a 9p checkout (a Windows folder mounted into a dev
  container), so watch polls with stat alone, once a second; a sweep of the
  largest project costs about 50 ms;
- one SIGINT stops a run within about a second, with exit 8, and Bazel keeps
  its cache;
- a run that goes on over an edit can keep, and serve again, a result or even
  a program built from other contents (TODO.md V111); so can one over an undo
  (taint.raced).

So a save during a run CANCELS it, and the run starts again once the files
settle (two polls agree); the contents seen around a cancelled run are
tainted, and Run (main.py) repairs them if they come back. Watch never moves
on to the next exercise and never adds hints of its own; `q` quits.
"""

import os
import select
import shlex
import shutil
import sys
import termios
import time
import tty

import bazel
import taint
from workspace import UsageError

POLL = 1.0
STUCK = 10.0


class Keys:
    """`q` from stdin: a terminal one key at a time, a pipe line by line, /dev/null never."""

    def __init__(self, stream=None):
        stream = sys.stdin if stream is None else stream
        try:
            self.fd = stream.fileno()
        except (AttributeError, OSError, ValueError):
            self.fd = None
        self.tty = self.fd is not None and os.isatty(self.fd)
        self.saved = None

    def __enter__(self):
        if self.tty:
            try:
                self.saved = termios.tcgetattr(self.fd)
                tty.setcbreak(self.fd)  # keys one at a time; Ctrl-C is still a signal
            except termios.error:
                self.saved = None
        return self

    def __exit__(self, *exc):
        if self.saved is not None:
            termios.tcsetattr(self.fd, termios.TCSADRAIN, self.saved)

    def quit(self, timeout=0.0):
        """Wait up to timeout seconds for a key; True if it was q."""
        if self.fd is None:
            time.sleep(timeout)
            return False
        try:
            ready, _, _ = select.select([self.fd], [], [], timeout)
        except (OSError, ValueError):
            self.fd = None
            return False
        if not ready:
            return False
        data = os.read(self.fd, 64)
        if not data:  # end of input: nothing more will come from it
            self.fd = None
            return False
        return b"q" in data.lower()


class Watch:
    """The loop. make_run() gives a fresh main.Run of the scope; files() lists what to watch."""

    def __init__(self, out, describe, files, make_run, keys=None, poll=POLL, clock=time.monotonic):
        self.out = out
        self.describe = describe
        self.files = files
        self.make_run = make_run
        self.keys = keys
        self.poll = poll
        self.clock = clock

    def stats(self):
        return taint.stats(self.files())

    def wait_for_save(self, since):
        """Poll until the files differ from `since`, then until two polls agree. None if q."""
        now = since
        while now == since:
            if self.keys.quit(self.poll):
                return None
            now = self.stats()
        while True:
            if self.keys.quit(self.poll):
                return None
            again = self.stats()
            if again == now:
                return now
            now = again

    def loop(self):
        n = len(self.files())
        self.out.say("42 watch: %s. It runs the tests now, and again each time one of\n"
                     "its %d file(s) is saved. q quits; so does Ctrl-C." % (self.describe, n))
        rc = 0
        state = self.stats()
        try:
            with self.keys:
                while True:
                    self.out.say("\n-- %s %s" % (time.strftime("%H:%M:%S"), "-" * 60))
                    run = self.make_run()
                    asked = {"quit": False}
                    start = state

                    def stop():
                        if self.keys.quit(0):
                            asked["quit"] = True
                            return True
                        return self.stats() != start
                    rc = run.go(stop=stop)
                    if asked["quit"]:
                        self.out.say("  stopped.")
                        return rc
                    if rc == 8 and not run.cancelled:  # Ctrl-C reached the run
                        return rc
                    if run.cancelled:
                        self.out.say("  A file was saved during the run: it stopped, and runs again once\n"
                                     "  the saves settle.")
                        state = self.wait_for_save(start)
                    elif self.stats() != start:
                        # A save after the run's last check: it ended with its result,
                        # and the contents now on disk were never tested (seen in the
                        # first trial of watch over an edit, 2026-10-09).
                        self.out.say("\n  42 watch runs it again once the saves settle. q quits.")
                        state = self.wait_for_save(start)
                    else:
                        self.out.say("\n  Watching %d file(s): save one to run again. q quits." % len(self.files()))
                        state = self.wait_for_save(self.stats())
                    if state is None:
                        return rc
        except KeyboardInterrupt:
            self.out.say("")
            return rc


def in_tmux(ctx, scope, level, environ=None):
    """42 watch in a pane on the right: in this tmux, or in a new session with a shell on the left."""
    env = ctx.env if environ is None else environ
    tmux = shutil.which("tmux", path=env.get("PATH"))
    if not tmux:
        raise UsageError("--tmux needs tmux, and this machine has none. Run `42 watch` in a\n"
                         "second terminal instead.")
    # The pane runs this checkout's 42 with the scope and level resolved here,
    # so it watches the same tests whatever its environment or folder.
    cmd = shlex.join(["sh", os.path.join(ctx.ws, "tools", "42.sh"), "watch"] + scope.words()
                     + ["--level", level])
    if env.get("TMUX"):
        argv = [tmux, "split-window", "-h", "-c", ctx.cwd, cmd]
    else:
        argv = [tmux, "new-session", "-c", ctx.cwd, ";", "split-window", "-h", "-c", ctx.cwd, cmd]
    if ctx.args.show_bazel or ctx.args.dry_run:
        ctx.out.say("$ " + shlex.join(["tmux"] + argv[1:]))
    if ctx.args.dry_run:
        return 0
    sys.stdout.flush()
    os.execve(tmux, argv, bazel.child_env(env))
