"""42 doctor: is this machine ready to run the tests?

Two halves, in this order. First what needs no Bazel, because asking Bazel
whether Bazel works starts the very server this may be about: the python 42
runs on, the `42` a shell finds, the launcher, where Bazel keeps its state and
the room there, the disk cache an rc file names, memory and the servers holding
it, the locale the tests run under, the identity `42 init` writes, and tmux.
Then //tools:env_drift, which compares this machine's tools with
tools/pins.tsv, but only on a checkout Bazel has set up, or with --drift: on a
cold one it downloads first.

--report runs tools/env-audit.sh as a bare script, as its header asks, since it
has to work before Bazel does. It writes tools/env-reports/<host>.txt; nothing
here commits or pushes it.

The exit is 1 only on a blocker, something without which no test can run: no
bazel, a state folder that cannot be written, a disk cache an rc file names
that cannot be created (Bazel stops every command over it), and, once env_drift
has run, a fetched tool it says cannot start on this machine (its UNRUNNABLE
count, read from its summary line), or an env_drift that never printed that
line: usually a build or download that failed, which stops every test too, or,
with exit 2, env_drift refusing to start (a missing command, a pins file it
cannot read) or Bazel refusing an option. Its exit status decides only what
that BLOCK says, never whether there is one: `bazel run` exits 1 for a build
that failed and passes env_drift's own status on too. On a cold checkout
env_drift does not run, so "Ready" says that the fetched tools are checked by
`42 doctor --drift` once a first run has fetched them.
"""

import locale
import os
import pwd
import re
import shutil
import subprocess
import sys
import textwrap

import bazel
import config
import report
import workspace

MARK = "# 42 shim, written by tools/fortytwo/install.sh"

# Measured on 2026-10-09: a fully cold C 00 run downloaded about 686 MB and
# left 1.4 GB under the state root. Other projects fetch more.
COLD_DOWNLOAD = "about 700 MB for C 00, more for projects with other toolchains"
COLD_ROOT_GB = 1.4

# The locale .bazelrc runs every test under (its test --test_env=LC_ALL).
TEST_LOCALE = "en_US.UTF-8"

# env_drift's summary line (tools/env_drift.sh's header), and its count of
# fetched tools that did not start.
DRIFT_SUMMARY = re.compile(r"^\s*\d+ match, \d+ drifted, \d+ missing, \d+ fetch-drift, "
                           r"(\d+) unrunnable, \d+ recorded\s*$")

# The file Docker writes at the root of every container it starts. With the
# variable the dev container's editor sets (REMOTE_CONTAINERS), it says this
# runs in a container, as tools/drives.sh's drives_in_container asks it;
# C_PISCINE_DOCKERENV stands in for it there and here, and a test may also
# point this at a file of its own.
DOCKERENV = "/.dockerenv"


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


def in_container(env):
    """Whether this runs in a container: the dev container's variable, or Docker's file."""
    return (bool(env.get("REMOTE_CONTAINERS"))
            or os.path.exists(env.get("C_PISCINE_DOCKERENV") or DOCKERENV))


def check_shim(c, ws, env):
    found = shutil.which("42", path=env.get("PATH"))
    if not found:
        # In a container, the two things .devcontainer/postcreate.sh does
        # first both missing say it never ran: Antigravity did not run it on
        # two rebuilds (V252), and plain `docker run` never does. Its disk
        # cache goes into ~/.bazelrc, and nowhere else: one in the checkout's
        # .bazelrc.local is the host's setup.sh's, no sign of postcreate
        # (V329), and a line there with no value is still a line it keeps.
        home = env.get("HOME")
        rc = [os.path.join(home, ".bazelrc")] if home else []
        if in_container(env) and not config.rc_value(ws, env, ("common", "build"), "disk_cache",
                                                     r"(\S*)", files=rc):
            c.add("warn", "no `42` on your PATH, and ~/.bazelrc names no disk cache:\n"
                          "this container's .devcontainer/postcreate.sh has not run (an\n"
                          "editor may skip it). `sh .devcontainer/postcreate.sh` sets up\n"
                          "both; until then, run `sh tools/42.sh`.")
            return
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


def rc_root_file(ws, env):
    """The rc file that names the output root, as tools/drives.sh finds it, or ""."""
    return subprocess.run(
        ["sh", "-c", '. "$1/tools/drives.sh" && drives_rc_root_file "$1"', "sh", ws],
        cwd=ws, env=bazel.child_env(env), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        universal_newlines=True, check=False).stdout.strip()


def check_state(c, ws, env):
    root = report.state_root(ws, env)
    there = nearest(root)
    if not (os.path.isdir(there) and os.access(there, os.W_OK)):
        why = "cannot be written" if os.path.isdir(there) else "is not a folder"
        text = "Bazel keeps its state in %s, and %s %s." % (root, there, why)
        # A root another machine wrote into the checkout's .bazelrc.local
        # (V239): a dev container's host, whose setup.sh roots Bazel under a
        # home the container cannot create. The file is the host's too, so the
        # fix is the container's ~/.bazelrc, read after it. Only in a
        # container: on a host, a root in ~/.bazelrc would outrank the one
        # every checkout there records.
        rc = rc_root_file(ws, env)
        if rc:
            text += "\nThat root is set in %s." % config.where(ws, env, rc)
        if rc == os.path.join(ws, config.LOCAL_RC) and in_container(env):
            text += ("\nIf another machine sharing this checkout wrote it (a dev\n"
                     "container's host), leave it as it is and run\n"
                     "`sh .devcontainer/postcreate.sh` here: it gives this one a root\n"
                     "of its own in ~/.bazelrc.")
        c.add("BLOCK", text)
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


def passwd_home():
    """This user's home as the passwd file has it, which Bazel's `~/` is ("" if none)."""
    try:
        return pwd.getpwuid(os.getuid()).pw_dir
    except KeyError:
        return ""


def disk_cache(ws, env):
    """(folder, file, line number) of the disk cache Bazel takes, or None.

    The winning line of the rc files Bazel reads (config.rc_value), an empty
    value included: `build --disk_cache=` turns the cache off, and a line
    before it no longer counts. `~/` is the passwd file's home, as Bazel
    reads it whatever $HOME says (measured on Bazel 9.2.0), and a relative
    folder is the checkout's.
    """
    found = config.rc_value(ws, env, ("common", "build"), "disk_cache", r"(\S*)")
    if not found or not found[0]:
        return None
    path, rc, n = found
    if path == "~" or path.startswith("~/"):
        path = os.path.join(passwd_home() or env.get("HOME") or "/", path[2:])
    return os.path.join(ws, path), rc, n


def check_disk_cache(c, ws, env):
    """A disk cache Bazel cannot create stops every command it runs (V329).

    "Error initializing RemoteModule", naming no file, before any build.
    The line can come from another machine: a dev container's host, whose
    setup.sh writes one into the checkout's .bazelrc.local under its own
    home. As check_state, the file is the host's too, and the container's
    ~/.bazelrc, read after it, is where its own line goes.
    """
    found = disk_cache(ws, env)
    if not found:
        return
    path, rc, n = found
    there = nearest(path)
    if os.path.isdir(there) and os.access(there, os.W_OK):
        c.add("ok", "Bazel's disk cache: %s" % path)
        return
    why = "cannot be written" if os.path.isdir(there) else "is not a folder"
    text = ("Bazel's disk cache is %s, and %s %s:\nevery Bazel command stops "
            "over it. It is set in %s." % (path, there, why, config.where(ws, env, rc, n)))
    home = env.get("HOME")
    if home and rc == os.path.join(home, ".bazelrc"):
        text += ("\nName a folder this machine can create there, or write\n"
                 "`build --disk_cache=` in its place, which turns the cache off.")
    elif in_container(env) and rc == os.path.join(ws, config.LOCAL_RC):
        text += ("\nIf another machine sharing this checkout wrote it (a dev\n"
                 "container's host), leave it as it is and run\n"
                 "`sh .devcontainer/postcreate.sh` here: it gives this one a disk\n"
                 "cache of its own in ~/.bazelrc, which Bazel reads after it. If\n"
                 "it finds none, a line `build --disk_cache=` in ~/.bazelrc turns\n"
                 "the cache off.")
    c.add("BLOCK", text)


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


def locale_installed(name):
    """Whether this machine has the locale `name`; this process's is left as it was."""
    before = locale.setlocale(locale.LC_COLLATE)
    try:
        locale.setlocale(locale.LC_COLLATE, name)
        return True
    except locale.Error:
        return False
    finally:
        locale.setlocale(locale.LC_COLLATE, before)


def check_locale(c, probe=locale_installed):
    if probe(TEST_LOCALE):
        c.add("ok", "locale: %s, which .bazelrc runs every test under" % TEST_LOCALE)
        return
    c.add("warn", "locale: no %s, which .bazelrc runs every test under. Every\n"
                  "test log then carries a setlocale warning, and shell-01 ex07's\n"
                  "checks skip the one property that needs it. To install it:\n"
                  "  Ubuntu: `sudo locale-gen %s`\n"
                  "  Debian: uncomment `%s UTF-8` in /etc/locale.gen, then\n"
                  "          `sudo locale-gen`\n"
                  "  Fedora: `sudo dnf install glibc-langpack-en`"
                  % (TEST_LOCALE, TEST_LOCALE, TEST_LOCALE))


def check_identity(c, ws, env):
    keys = workspace.read_identity(ws, bazel.child_env(env))
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


def run_drift(out, exe, ws, env):
    """bazel run //tools:env_drift, its lines shown as they come.

    Returns (exit status, its unrunnable count, or None where no summary line
    came: env_drift did not finish).
    """
    unrunnable = None
    with subprocess.Popen([exe, "run", "//tools:env_drift"], cwd=ws, env=bazel.child_env(env),
                          stdout=subprocess.PIPE, universal_newlines=True,
                          errors="replace") as p:
        for line in p.stdout:
            line = line.rstrip("\n")
            out.say(line)
            m = DRIFT_SUMMARY.match(line)
            if m:
                unrunnable = int(m.group(1))
    return p.returncode, unrunnable


def drift_rows(c, status, unrunnable):
    """What env_drift's run adds to the verdict: a BLOCK, or nothing."""
    if unrunnable is None and status == 2:
        # env_drift's own refusal (tools/env_drift.sh's header), and Bazel's
        # for an option it rejects: both exit 2, and both print why.
        c.add("BLOCK", "env_drift did not finish (exit 2, above), so this machine's tools\n"
                       "were not checked. Exit 2 means env_drift refused to start (a\n"
                       "command it needs or a file it reads is missing) or Bazel refused\n"
                       "an option: the lines above say which. Fix that, then run\n"
                       "`42 doctor` again.")
    elif unrunnable is None:
        c.add("BLOCK", "env_drift did not finish (exit %d, above), so this machine's tools\n"
                       "were not checked. That is usually a build or download that failed,\n"
                       "which stops every test too: fix what it names, then run\n"
                       "`42 doctor` again." % status)
    elif unrunnable:
        c.add("BLOCK", "%d fetched tool%s cannot start on this machine (UNRUNNABLE above),\n"
                       "and every test that runs one fails. Work in the dev container\n"
                       "(docs/environment.md): it is the system they were built for."
              % (unrunnable, "" if unrunnable == 1 else "s"))


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
    check_disk_cache(c, ws, env)
    check_memory(c, ws)
    check_locale(c)
    check_identity(c, ws, env)
    check_tmux(c, env)
    show(out, c)

    unchecked = False
    if exe and (ctx.args.drift or cold in (None, "server")):
        argv = ["bazel", "run", "//tools:env_drift"]
        out.say("")
        ctx.show(argv)
        if not ctx.args.dry_run:
            out.say("  Comparing this machine's tools with tools/pins.tsv:\n")
            sys.stdout.flush()
            status, unrunnable = run_drift(out, exe, ws, env)
            late = Check()
            drift_rows(late, status, unrunnable)
            if late.rows:
                out.say("")
                show(out, late)
                c.rows += late.rows
            elif status != 0:
                out.say("\n  env_drift stopped with exit %d (above)." % status)
    elif exe:
        unchecked = True
        out.say("\n" + textwrap.fill(
            "Not compared with tools/pins.tsv: on a checkout Bazel has not set up, "
            "that downloads first (%s). `42 doctor --drift` compares anyway." % COLD_DOWNLOAD,
            width=78, initial_indent="  ", subsequent_indent="  "))
    rc = 1 if c.blockers() else 0

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
        if unchecked:
            out.say("`42 doctor --drift` checks the fetched tools once a first run has "
                    "fetched them.")
    return rc
