"""42 doctor: is this machine ready to run the tests?

Two halves, in this order. First what needs no Bazel, because asking Bazel
whether Bazel works starts the very server this may be about: the python 42
runs on, the `42` a shell finds, the launcher, where Bazel keeps its state and
the room there, memory and the servers holding it, the identity `42 init`
writes, and tmux. Then //tools:env_drift, which compares this machine's tools
with tools/pins.tsv, but only on a checkout Bazel has set up, or with --drift:
on a cold one it downloads first.

--report runs tools/env-audit.sh as a bare script, as its header asks, since it
has to work before Bazel does. It writes tools/env-reports/<host>.txt; nothing
here commits or pushes it.

The exit is 1 only on a blocker, something without which no test can run.
"""

import os
import shutil
import subprocess
import sys
import textwrap

import bazel
import report

MARK = "# 42 shim, written by tools/fortytwo/install.sh"

# Measured on 2026-10-09: a fully cold C 00 run downloaded about 686 MB and
# left 1.4 GB under the state root. Other projects fetch more.
COLD_DOWNLOAD = "about 700 MB for C 00, more for projects with other toolchains"
COLD_ROOT_GB = 1.4


class Check:
    def __init__(self):
        self.rows = []

    def add(self, mark, text):
        self.rows.append((mark, text))

    def blockers(self):
        return sum(1 for m, _ in self.rows if m == "BLOCK")


def gb(n):
    return "%.1f GB" % (n / 2 ** 30)


def check_python(c):
    v = sys.version_info
    c.add("ok", "python3 %d.%d.%d (42 needs 3.10 or later)" % (v.major, v.minor, v.micro))


def check_shim(c, ws, env):
    found = shutil.which("42", path=env.get("PATH"))
    if not found:
        c.add("warn", "no `42` on your PATH. `sh tools/fortytwo/install.sh` writes one to\n"
                      "~/.local/bin; until then, run `sh tools/42.sh`.")
        return
    try:
        with open(found, encoding="utf-8", errors="replace") as f:
            text = f.read(4096)
    except OSError:
        text = ""
    if MARK not in text:
        c.add("warn", "%s is not 42's shim: `42` may run something else." % found)
        return
    fallback = ""
    for line in text.splitlines():
        if line.startswith("FALLBACK='") and line.endswith("'"):
            fallback = line[len("FALLBACK='"):-1].replace("'\\''", "'")
    where = "the checkout you are in"
    if fallback and os.path.realpath(fallback) != os.path.realpath(ws):
        where += "; outside one, %s" % fallback
    c.add("ok", "42 on PATH: %s (it runs %s)" % (found, where))


def check_launcher(c, env):
    try:
        exe = bazel.executable(env)
    except bazel.NoBazel as e:
        c.add("BLOCK", str(e))
        return None
    real = os.path.realpath(exe)
    c.add("ok", "bazel: %s%s" % (exe, "" if real == exe else " -> " + real))
    return exe


def nearest(path):
    while path and not os.path.exists(path):
        parent = os.path.dirname(path)
        if parent == path:
            break
        path = parent
    return path


def check_state(c, ws, env):
    root = report.state_root(ws, env)
    there = nearest(root)
    if not os.access(there, os.W_OK):
        c.add("BLOCK", "Bazel keeps its state in %s, and %s cannot be written." % (root, there))
        return None
    try:
        free = shutil.disk_usage(there).free
    except OSError:
        free = None
    room = "" if free is None else ", %s free" % gb(free)
    c.add("ok", "Bazel's state: %s%s" % (root, room))
    cold = report.coldness(ws, env, root)
    if cold == "machine":
        c.add("note", "Bazel has not run on this machine yet: its first run downloads\n"
                      "%s." % COLD_DOWNLOAD)
    elif cold == "checkout":
        c.add("note", "Bazel has not run in this checkout yet: its first run sets it up.")
    if cold in ("machine", "checkout") and free is not None and free < COLD_ROOT_GB * 2 ** 30:
        c.add("warn", "a first run left %.1f GB there (C 00, measured), and %s is free."
              % (COLD_ROOT_GB, gb(free)))
    advice = subprocess.run(
        ["sh", "-c", '. "$1/tools/drives.sh" && drives_root_warning "$2" "$1"', "sh", ws, root],
        cwd=ws, env=bazel.child_env(env), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        universal_newlines=True, check=False).stdout.strip()
    if advice:
        c.add("warn", advice)
    return cold


def servers(proc="/proc"):
    """(pid, rss bytes, workspace) for every Bazel server this user can see.

    A server is a process given --output_base=: a shell whose command line
    merely names A-server.jar is not one.
    """
    out = []
    try:
        names = os.listdir(proc)
    except OSError:
        return out
    for name in names:
        if not name.isdigit():
            continue
        try:
            with open(os.path.join(proc, name, "cmdline"), "rb") as f:
                argv = f.read().split(b"\0")
        except OSError:
            continue
        flags = dict(a.decode(errors="replace").split("=", 1) for a in argv
                     if a.startswith(b"--output_base=") or a.startswith(b"--workspace_directory="))
        if "--output_base" not in flags:
            continue
        rss = 0
        try:
            with open(os.path.join(proc, name, "status"), encoding="utf-8") as f:
                for line in f:
                    if line.startswith("VmRSS:"):
                        rss = int(line.split()[1]) * 1024
        except (OSError, ValueError):
            pass
        out.append((int(name), rss, flags.get("--workspace_directory", "?")))
    return sorted(out)


def check_memory(c, ws, proc="/proc"):
    avail = None
    try:
        with open(os.path.join(proc, "meminfo"), encoding="utf-8") as f:
            for line in f:
                if line.startswith("MemAvailable:"):
                    avail = int(line.split()[1]) * 1024
    except (OSError, ValueError):
        pass
    if avail is None:
        c.add("note", "memory: this system has no /proc/meminfo to read.")
        return
    lines = ["memory: %s available." % gb(avail)]
    here = os.path.realpath(ws)
    found = servers(proc)
    for pid, rss, where in found:
        who = "this checkout" if os.path.realpath(where) == here else where
        lines.append("  a Bazel server, pid %d, holds %s (%s)" % (pid, gb(rss), who))
    if any(os.path.realpath(w) != here for _, _, w in found):
        lines.append("  `42 stop` in a checkout stops its server; an idle one stops by itself\n"
                     "  after three hours.")
    c.add("ok", "\n".join(lines))


def check_identity(c, ws, env):
    keys = {}
    try:
        with open(os.path.join(ws, ".vscode", "settings.json"), encoding="utf-8") as f:
            for line in f:
                for k in ("username", "email"):
                    tag = '"42header.%s"' % k
                    if tag in line and ":" in line:
                        v = line.split(":", 1)[1].strip().rstrip(",").strip().strip('"')
                        if v:
                            keys[k] = v
    except OSError:
        pass
    genv = dict(bazel.child_env(env), GIT_CONFIG_NOSYSTEM="1")
    mail = subprocess.run(["git", "-C", ws, "config", "--local", "--get", "user.email"],
                          env=genv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                          universal_newlines=True, check=False).stdout.strip()
    if keys.get("username") and keys.get("email") and mail:
        c.add("ok", "identity: %s <%s>" % (keys["username"], keys["email"]))
    else:
        c.add("warn", "identity: not set. `42 init` sets your 42 login and email; the file\n"
                      "headers and `42 submit` read them.")


def check_tmux(c, env):
    tmux = shutil.which("tmux", path=env.get("PATH"))
    if not tmux:
        c.add("note", "no tmux: `42 watch --tmux` needs it, and `42 watch` in a second\n"
                      "terminal does the same.")
        return
    v = subprocess.run([tmux, "-V"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                       universal_newlines=True, check=False).stdout.strip()
    c.add("ok", v or "tmux")


def show(out, c):
    for mark, text in c.rows:
        first, *rest = text.split("\n")
        out.say("  %-5s %s" % (mark, first))
        for line in rest:
            out.say("        " + line)


def run(ctx):
    out, env, ws = ctx.out, ctx.env, ctx.ws
    out.say("42 doctor: is this machine ready to run the tests?\n")
    c = Check()
    check_python(c)
    check_shim(c, ws, env)
    exe = check_launcher(c, env)
    cold = check_state(c, ws, env)
    check_memory(c, ws)
    check_identity(c, ws, env)
    check_tmux(c, env)
    show(out, c)
    rc = 1 if c.blockers() else 0

    if exe and (ctx.args.drift or cold in (None, "server")):
        argv = ["bazel", "run", "//tools:env_drift"]
        out.say("")
        ctx.show(argv)
        if not ctx.args.dry_run:
            out.say("  Comparing this machine's tools with tools/pins.tsv:\n")
            sys.stdout.flush()
            r = subprocess.run([exe] + argv[1:], cwd=ws, env=bazel.child_env(env), check=False)
            if r.returncode not in (0,):
                out.say("\n  env_drift stopped with exit %d (above)." % r.returncode)
    elif exe:
        out.say("\n" + textwrap.fill(
            "Not compared with tools/pins.tsv: on a checkout Bazel has not set up, "
            "that downloads first (%s). `42 doctor --drift` compares anyway." % COLD_DOWNLOAD,
            width=78, initial_indent="  ", subsequent_indent="  "))

    if ctx.args.report:
        argv = ["sh", "tools/env-audit.sh"]
        out.say("")
        ctx.show(argv)
        if not ctx.args.dry_run:
            sys.stdout.flush()
            r = subprocess.run(argv, cwd=ws, env=bazel.child_env(env), check=False)
            out.say("\n  The report is under tools/env-reports/ (it says where, above), and\n"
                    "  is not committed: nothing here commits or pushes it.")
            if r.returncode != 0:
                out.say("  env-audit.sh stopped with exit %d." % r.returncode)

    out.say("")
    if rc:
        out.say("Not ready: %d blocker(s) above." % c.blockers())
    else:
        out.say("Ready to run the tests.")
    return rc
