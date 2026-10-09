"""What a run shows: first_red's report, then the log of the one test it names next.

42 writes no verdict of its own. The states and their wording are
tools/first_red.sh's; the table and the hints are the test's own log, copied.
What 42 adds is the glue around them (the phase line, a footer) and the peer
nudge, which is shipped prose under AGENTS.md section 2: no advice of its own.
"""

import hashlib
import os
import subprocess
import time

from bazel import child_env

LOG_CAP = 80

# The layers a fresh stub passes (first_red.sh's STUB_GREEN): a red one at basic
# is the "ko" bucket, so its log is the one to show for that bucket.
STUB_GREEN = ("norm", "compile", "files", "forbidden", "prototype")

NUDGE = "Stuck on a red? Talk it through with the peer on your right — that is how 42 expects you to learn."
NUDGE_EVERY = 7 * 24 * 3600


def state_root(ws, environ=None):
    """The output_user_root this checkout's Bazel uses, predicted the way tools/bazel picks it."""
    env = child_env(environ)
    r = subprocess.run(
        ["sh", "-c", '. "$1/tools/drives.sh" && drives_predicted_root "$1"', "sh", ws],
        cwd=ws, env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        universal_newlines=True, check=False)
    root = r.stdout.strip()
    if not root:
        user = env.get("USER") or env.get("LOGNAME") or ""
        root = os.path.join(env.get("HOME", "/"), ".cache", "bazel", "_bazel_" + user)
    return root


def output_base(ws, root):
    return os.path.join(root, hashlib.md5(os.path.realpath(ws).encode()).hexdigest())


def server_alive(base):
    try:
        with open(os.path.join(base, "server", "server.pid.txt"), encoding="utf-8") as f:
            pid = int(f.read().strip())
        os.kill(pid, 0)
        return pid
    except (OSError, ValueError):
        return None


def coldness(ws, environ=None, root=None):
    """'machine', 'checkout', 'server' or None: how much a run must set up before it tests.

    No Bazel call: asking Bazel would start the very server this is about.
    """
    root = root or state_root(ws, environ)
    base = output_base(ws, root)
    if not os.path.isdir(base):
        repos = os.path.join(root, "cache", "repos", "v1")
        try:
            empty = not os.listdir(repos)
        except OSError:
            empty = True
        return "machine" if empty else "checkout"
    if not server_alive(base):
        return "server"
    return None


PHASE = {
    "machine": ("first run on this machine: Bazel downloads its tools (about 700 MB, once).\n"
                "Ctrl-C is safe: what has finished downloading is kept."),
    "checkout": "first run in this checkout: Bazel sets it up (a minute or so).",
    "server": "starting Bazel...",
}


def first_red(ws, out_path, next_path, all_lines=False):
    """first_red.sh over a run's output, its suggestions written as 42 commands. (text, rc)"""
    argv = ["sh", os.path.join(ws, "tools", "first_red.sh"), "--cmd", "42", "--next", next_path]
    if all_lines:
        argv.append("--all")
    with open(out_path, "rb") as f:
        r = subprocess.run(argv, cwd=ws, stdin=f, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, check=False)
    return r.stdout.decode("utf-8", "replace"), r.returncode


def read_next(next_path):
    """(bucket, module, exercise, label) first_red names next, or None."""
    try:
        with open(next_path, encoding="utf-8") as f:
            line = f.readline().rstrip("\n")
    except OSError:
        return None
    parts = line.split("\t")
    if len(parts) != 4:
        return None
    return tuple(parts)


# The layers whose log says most, per bucket first_red names: for a build
# failure, the log that quotes the compiler, then the one naming a missing
# file; for a broken rule, the layers a stub passes. Ties go by label, so the
# same state shows the same log on every run: the events arrive in no fixed
# order.
PREFER = {"build": ("compile", "files"), "ko": STUB_GREEN}


def pick_label(nxt, bep):
    """The test whose log to show for what first_red names next, or None.

    first_red names a label for a red output and a timeout; for the other
    buckets it names an exercise, and the label is that exercise's red test
    of the layer PREFER puts first, else its first red test by name.
    """
    bucket, module, ex, label = nxt
    if label != "-":
        return label
    prefix = module + ":" + ex
    order = PREFER.get(bucket, ())

    def rank(l):
        tags = set(bep.tags.get(l, ()))
        first = next((i for i, layer in enumerate(order) if layer in tags), len(order))
        return (first, l)
    mine = sorted((l for l in bep.failed() if l == prefix or l.startswith(prefix + "_")), key=rank)
    with_log = [l for l in mine if bep.logs.get(l)]
    return with_log[0] if with_log else None


def log_path(ws, label, bep):
    p = bep.logs.get(label)
    if p and os.path.isfile(p):
        return p
    pkg, _, name = label[2:].partition(":")
    p = os.path.join(ws, "bazel-testlogs", pkg, name, "test.log")
    return p if os.path.isfile(p) else None


def log_body(path, cap=LOG_CAP):
    """The runner's part of a test.log, verbatim: (lines, how many more there were).

    Bazel writes three lines of its own first: a pager line, "Executing tests
    from <label>" and a rule. They say nothing a student needs.
    """
    with open(path, encoding="utf-8", errors="replace") as f:
        lines = f.read().split("\n")
    if lines and lines[0].startswith("exec ${PAGER"):
        lines = lines[1:]
    if len(lines) >= 2 and lines[0].startswith("Executing tests from") and set(lines[1]) == {"-"}:
        lines = lines[2:]
    while lines and not lines[-1].strip():
        lines.pop()
    if len(lines) > cap:
        return lines[:cap], len(lines) - cap
    return lines, 0


def nudge_due(state_dir, now=None):
    """True at most once a week per checkout, and records that it was shown."""
    now = time.time() if now is None else now
    path = os.path.join(state_dir, "nudge")
    try:
        if now - os.path.getmtime(path) < NUDGE_EVERY:
            return False
    except OSError:
        pass
    try:
        os.makedirs(state_dir, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write("%d\n" % now)
    except OSError:
        return False  # a nudge that cannot remember it was shown is not shown
    return True
