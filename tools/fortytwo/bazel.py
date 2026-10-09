"""Running Bazel for 42: the one place an argv is built, a child started, a BEP read.

Measured before any of it was written (Bazel 9.2.0, 2026-10-09): every flag
added here is free -- it neither restarts the server nor discards the analysis
cache -- so a `bazel test` typed by hand hits the same cache. --action_env is
not free (it discards the cache) and is never added (tools/conventions.sh holds
42 to that).
"""

import contextlib
import fcntl
import glob
import json
import os
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import uuid

# What a child Bazel must not inherit. Under `bazel run //tools:42`, bazelisk
# has set BAZELISK_SKIP_WRAPPER and BAZEL_REAL, and a nested bazelisk that sees
# them skips tools/bazel -- the wrapper that picks this machine's state root --
# and lands on another output base (tools/prime.sh explains it). The BUILD_*
# and runfiles variables describe the `bazel run` 42 came from, not the child's.
STRIP_ENV = (
    "BAZELISK_SKIP_WRAPPER", "BAZEL_REAL",
    "BUILD_WORKSPACE_DIRECTORY", "BUILD_WORKING_DIRECTORY",
    "RUNFILES_DIR", "RUNFILES_MANIFEST_FILE", "JAVA_RUNFILES", "PYTHON_RUNFILES",
    "FT_WS", "FT_CWD",
)

# Bazel's exit codes, as 42 explains them.
OK, BUILD_FAILED, USAGE, TESTS_FAILED, NO_TESTS, INTERRUPTED, LOCK_HELD = 0, 1, 2, 3, 4, 8, 9


class NoBazel(Exception):
    pass


def _wrapper_dir(d):
    """Is d a checkout's tools/ folder, the one holding the tools/bazel wrapper?"""
    return (os.path.basename(os.path.normpath(d)) == "tools"
            and os.path.isfile(os.path.join(d, "bazel"))
            and os.path.isfile(os.path.join(d, "..", "MODULE.bazel")))


def child_env(environ=None):
    env = dict(os.environ if environ is None else environ)
    # When bazelisk runs tools/bazel it also puts tools/ first on PATH, so
    # under `bazel run` a bare `bazel` is the wrapper, which cannot run once
    # BAZEL_REAL is gone. Only then is that folder dropped.
    if "BAZELISK_SKIP_WRAPPER" in env and env.get("PATH"):
        env["PATH"] = os.pathsep.join(
            d for d in env["PATH"].split(os.pathsep) if not (d and _wrapper_dir(d)))
    for k in STRIP_ENV:
        env.pop(k, None)
    return env


def executable(environ=None):
    """The `bazel` a student types: setup.sh links it to bazelisk in ~/.local/bin."""
    env = child_env(environ)
    for name in ("bazel", "bazelisk"):
        found = shutil.which(name, path=env.get("PATH"))
        if found:
            return found
    raise NoBazel("no `bazel` on PATH. Run `sh tools/setup.sh` once, then open a new terminal.")


def test_argv(patterns, tag_filter=None, extra=(), bazel="bazel"):
    """The command a student could type for the same run (what --show_bazel prints)."""
    argv = [bazel, "test"] + list(patterns)
    if tag_filter:
        argv.append("--test_tag_filters=" + tag_filter)
    argv += list(extra)
    return argv


def plumbing(bep_path, invocation_id):
    """The flags 42 adds to every test run and never shows: each one measured free."""
    return [
        "--build_tests_only",
        "--build_event_json_file=" + bep_path,
        "--build_event_json_file_path_conversion=false",
        "--invocation_id=" + invocation_id,
    ]


def with_startup(argv, startup=("--noblock_for_lock",)):
    """argv with startup options between the binary and the command."""
    return [argv[0]] + list(startup) + argv[1:]


def shell_line(argv):
    """argv as a line to copy: the Bazel binary written as the `bazel` a student types."""
    words = list(argv)
    if words and os.path.basename(words[0]) in ("bazel", "bazelisk"):
        words[0] = "bazel"
    return " ".join(shlex.quote(a) for a in words)


def new_invocation():
    return str(uuid.uuid4())


def run_dir(environ=None):
    """A fresh folder for one run's files (output, BEP, first_red's line): never in the checkout.

    $XDG_RUNTIME_DIR/42 (a per-user tmpfs on most Linux sessions), else the
    system's temporary folder.
    """
    env = os.environ if environ is None else environ
    base = env.get("XDG_RUNTIME_DIR")
    if base and os.path.isdir(base):
        try:
            parent = os.path.join(base, "42")
            os.makedirs(parent, mode=0o700, exist_ok=True)
            return tempfile.mkdtemp(prefix="run-", dir=parent)
        except OSError:
            pass
    return tempfile.mkdtemp(prefix="42-")


class Child:
    """A Bazel run in its own session, so the terminal's Ctrl-C reaches 42 alone.

    42 then sends exactly ONE SIGINT to the process it started. bazelisk
    forwards it (measured), and Bazel cancels within a second with exit 8,
    keeping its cache. In the terminal's process group, a Ctrl-C would reach
    bazelisk and the Bazel client both, and the client would see it twice.
    """

    def __init__(self, argv, cwd, out_path, environ=None):
        self.argv = argv
        self.out = open(out_path, "wb")
        self.proc = subprocess.Popen(
            argv, cwd=cwd, env=child_env(environ), stdin=subprocess.DEVNULL,
            stdout=self.out, stderr=subprocess.STDOUT, start_new_session=True)
        self.started = time.monotonic()
        self.cancelled_at = None

    def cancel(self):
        """Ask Bazel to stop, once. It is never killed: a kill can leave the lock held."""
        if self.cancelled_at is None and self.proc.poll() is None:
            self.cancelled_at = time.monotonic()
            try:
                self.proc.send_signal(signal.SIGINT)
            except ProcessLookupError:
                pass

    def poll(self):
        return self.proc.poll()

    def wait(self, timeout=None):
        try:
            return self.proc.wait(timeout)
        finally:
            if self.proc.returncode is not None:
                self.out.close()

    def elapsed(self):
        return time.monotonic() - self.started


def run_foreground(child, tick=None, interval=0.5, cancel_when=None, stuck=None, stuck_after=10.0):
    """Wait for child; tick(elapsed, stopping) is called as it runs.

    Ctrl-C, or cancel_when() turning True, cancels it: one SIGINT, ever.
    stuck() is called once if it has not stopped stuck_after seconds later;
    it is never killed.
    """
    state = {"stopping": False, "told": False}

    def stop():
        if not state["stopping"]:
            state["stopping"] = True
            child.cancel()

    def on_int(signum, frame):
        stop()

    old = signal.signal(signal.SIGINT, on_int)
    try:
        while True:
            rc = child.poll()
            if rc is not None:
                child.wait()
                return rc
            if cancel_when is not None and not state["stopping"] and cancel_when():
                stop()
            if (stuck is not None and not state["told"] and child.cancelled_at is not None
                    and time.monotonic() - child.cancelled_at >= stuck_after):
                state["told"] = True
                stuck()
            if tick:
                tick(child.elapsed(), state["stopping"])
            time.sleep(interval)
    finally:
        signal.signal(signal.SIGINT, old)


def execution_root(exe, ws, environ=None):
    """(rc, path) of `bazel --noblock_for_lock info execution_root`: rc 9 while another command runs."""
    r = subprocess.run([exe, "--noblock_for_lock", "info", "execution_root"], cwd=ws,
                       env=child_env(environ), stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                       stderr=subprocess.DEVNULL, universal_newlines=True, check=False)
    return r.returncode, r.stdout.strip()


@contextlib.contextmanager
def base_lock(output_base):
    """The output base's client lock, taken without waiting. Yields whether it is held.

    A Bazel client takes it before it sends its command, and lets it go once
    the server has the command (blaze.cc, "Released the client-side locks"):
    holding it stops a new command from starting, not one already running.
    """
    fd = os.open(os.path.join(output_base, "lock"), os.O_RDWR | os.O_CREAT | os.O_CLOEXEC, 0o644)
    try:
        try:
            fcntl.lockf(fd, fcntl.LOCK_EX | fcntl.LOCK_NB, 1, 0)
        except OSError:
            yield False
            return
        try:
            yield True
        finally:
            fcntl.lockf(fd, fcntl.LOCK_UN, 1, 0)
    finally:
        os.close(fd)


def drop_outputs(exe, ws, packages, environ=None):
    """Delete what Bazel built for these packages, so that it builds them again. Returns an exit code.

    The repair for contents a run could not vouch for (TODO.md V111): a
    file edited while Bazel built from it can leave a program built from the
    other contents, and neither --nocache_test_results nor
    --use_action_cache=false rebuilds it. With its outputs gone, Bazel builds
    it again from the file as it is. Done only while the server is idle (it
    answered `info` without waiting) and no new command can start (the lock is
    held): LOCK_HELD when either is not so, to try again.
    """
    for pkg in packages:
        parts = pkg.split("/")
        if not pkg or pkg.startswith("/") or "" in parts or "." in parts or ".." in parts:
            raise ValueError("not a package path: %r" % pkg)
    rc, root = execution_root(exe, ws, environ)
    if rc != OK:
        return rc
    if not os.path.isdir(root):
        return BUILD_FAILED
    base = os.path.dirname(os.path.dirname(root))
    with base_lock(base) as held:
        if not held:
            return LOCK_HELD
        for bin_dir in glob.glob(os.path.join(root, "bazel-out", "*", "bin")):
            for pkg in packages:
                shutil.rmtree(os.path.join(bin_dir, pkg), ignore_errors=True)
    return OK


def exec_foreground(argv, cwd, environ=None):
    """Replace 42 with argv: the terminal, Ctrl-C and exit status are exactly a typed command's."""
    os.chdir(cwd)
    sys.stdout.flush()
    sys.stderr.flush()
    os.execvpe(argv[0], argv, child_env(environ))


class Bep:
    """What 42 reads from a run's Build Event Protocol file, and nothing else."""

    def __init__(self):
        self.selected = []      # every test target the run built or tried to (targetConfigured/aborted)
        self.tags = {}          # label -> its tags
        self.status = {}        # label -> testSummary overallStatus
        self.logs = {}          # label -> test.log path of its last attempt
        self.aborted = {}       # label -> reason
        self.exit_name = None   # buildFinished's exit code name
        self.patterns = []

    def does_not_build(self):
        """Selected and no testSummary: Bazel 9 has no FAILED_TO_BUILD summary."""
        return [l for l in self.selected if l not in self.status]

    def failed(self):
        return [l for l in self.selected if self.status.get(l) in ("FAILED", "TIMEOUT", "FLAKY", "INCOMPLETE", "REMOTE_FAILURE", "FAILED_TO_BUILD")]


def _uri_path(uri):
    return uri[len("file://"):] if uri.startswith("file://") else uri


def read_bep(path):
    bep = Bep()
    try:
        f = open(path, encoding="utf-8")
    except OSError:
        return bep
    with f:
        for line in f:
            try:
                ev = json.loads(line)
            except ValueError:
                continue  # a run cancelled mid-write leaves a partial last line
            eid = ev.get("id", {})
            if "pattern" in eid:
                bep.patterns = eid["pattern"].get("pattern", [])
            elif "targetConfigured" in eid:
                label = eid["targetConfigured"].get("label")
                conf = ev.get("configured", {})
                if label and ("testSize" in conf or conf.get("targetKind", "").endswith("_test rule")):
                    if label not in bep.tags:
                        bep.selected.append(label)
                    bep.tags[label] = conf.get("tag", [])
            elif "testSummary" in eid:
                label = eid["testSummary"].get("label")
                bep.status[label] = ev.get("testSummary", {}).get("overallStatus", "NO_STATUS")
            elif "testResult" in eid:
                label = eid["testResult"].get("label")
                for out in ev.get("testResult", {}).get("testActionOutput", []):
                    if out.get("name") == "test.log":
                        bep.logs[label] = _uri_path(out.get("uri", ""))
            elif "targetCompleted" in eid:
                label = eid["targetCompleted"].get("label")
                if "aborted" in ev and label:
                    bep.aborted[label] = ev["aborted"].get("reason", "")
            elif "buildFinished" in eid:
                bep.exit_name = ev.get("finished", {}).get("exitCode", {}).get("name")
            if "aborted" in ev and "targetCompleted" not in eid:
                label = None
                for k in ("targetConfigured", "pattern"):
                    if k in eid and isinstance(eid[k], dict):
                        label = eid[k].get("label")
                if label:
                    bep.aborted.setdefault(label, ev["aborted"].get("reason", ""))
    return bep
