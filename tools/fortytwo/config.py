"""42 config: every setting of this checkout, read and set in one place.

Each setting stays in the file its readers already read -- .submit-level,
.submit-remotes, .vscode/settings.json, .bazelrc.local -- so `42 config` is
another way into those files, never a second copy of a value. It runs no Bazel
command, the one command of 42 that does not (AGENTS.md, section 4): it has to
work when Bazel does not, and starting a server to read a file would cost far
more memory than the file.

Three kinds of setting, and every list says which a row is:
  42, this checkout     what 42's own tools read: your identity, your level,
                        where each project is pushed;
  Bazel, this checkout  the Bazel flags this checkout's .bazelrc.local may
                        override (Bazel reads it after .bazelrc);
  machine, read-only    where Bazel keeps its state on this machine, and how
                        big it may grow: shown, never set here, because
                        `sh tools/setup.sh` and .bazelrc choose them.
"""

import difflib
import os
import re
import subprocess
import textwrap

import bazel
import report
import workspace
from workspace import LEVELS, UsageError

WIDTH = 80
SYSTEM_RC = "/etc/bazel.bazelrc"
LOCAL_RC = ".bazelrc.local"

# The URL shapes git pushes to that a .submit-remotes line can hold: no blank
# (a blank before a '#' starts a comment there), and one of git's own forms.
URL_FORMS = (
    re.compile(r"[A-Za-z0-9._-]+@[A-Za-z0-9.-]+:\S+$"),  # user@host:path
    re.compile(r"(ssh|git|https?|file)://\S+$"),
    re.compile(r"/\S*$"),  # a repository on this machine
)
URL_HELP = "user@host:path, ssh://, git://, http(s)://, file:// or an absolute path"
# What [[:space:]] is to tools/submit.sh's parse_row, whose sed runs in the C
# locale, and no more: a no-break space or an ideographic space pasted from a
# page is no blank to it, so it is none here either.
BLANKS = " \t\n\r\f\v"
# Bazel's client reads --max_idle_secs as a 32-bit int, and stops on a larger
# one (measured on Bazel 9.2.0: 3000000000 is a fatal error).
INT_MAX = 2147483647


def host_cpus():
    """The CPUs this process may run on: what `nproc` says, and Bazel's HOST_CPUS."""
    try:
        return len(os.sched_getaffinity(0))
    except (AttributeError, OSError):
        return os.cpu_count() or 1


# ---------------------------------------------------------------------------
# Reading Bazel's rc files

def rc_files(ws, environ):
    """The rc files a `bazel` command in this checkout reads, in the order it reads them.

    tools/drives.sh's drives_rc_scan order: the system rc, the checkout's
    .bazelrc, the .bazelrc.local its last line imports, then the home rc.
    """
    home = environ.get("HOME")
    files = [SYSTEM_RC, os.path.join(ws, ".bazelrc"), os.path.join(ws, LOCAL_RC)]
    if home:
        files.append(os.path.join(home, ".bazelrc"))
    return files


def rc_lines(path):
    """path's lines as tools/submit.sh's `read` and Bazel take them: split at a newline and
    nowhere else, a '\\r' before it kept, and a byte that is no UTF-8 kept as it was, so a
    rewrite gives back unchanged every line it does not mean to change."""
    try:
        with open(path, "rb") as f:
            lines = f.read().decode("utf-8", "surrogateescape").split("\n")
    except OSError:
        return []
    if lines[-1] == "":
        lines.pop()
    return lines


def rc_value(ws, environ, commands, flag, value=r"(\S+)", files=None):
    """(value, file, line number) of the line Bazel takes `flag` from, or None.

    `commands` go from the least specific to the most, as ("common", "build"):
    Bazel applies the rc files command by command, every common line before
    any build line, and their order decides only within one command
    (measured on Bazel 9.2.0: a build line in .bazelrc won over a common line
    in the .bazelrc.local read after it). A line is `COMMAND --flag=VALUE ...`
    or `COMMAND --flag VALUE`; a named config (`build:x`) applies only when
    asked for, and a comment never. `files`, when given, are the only ones read.
    """
    line_rx = re.compile(r"\s*(%s)\s" % "|".join(commands))
    flag_rx = re.compile(r"(?:^|\s)--%s(?:=|\s+)%s" % (re.escape(flag), value))
    last = {}
    for path in rc_files(ws, environ) if files is None else files:
        for n, line in enumerate(rc_lines(path), 1):
            m = line_rx.match(line)
            if not m:
                continue
            for f in flag_rx.finditer(line):
                last[m.group(1)] = (f.group(1).strip('"\''), path, n)
    for command in reversed(commands):
        if command in last:
            return last[command]
    return None


def where(ws, environ, path, n=None):
    """A file as a person finds it: from the checkout, from ~, or whole."""
    home = environ.get("HOME")
    if path.startswith(ws + os.sep):
        shown = path[len(ws) + 1:]
    elif home and path.startswith(home.rstrip(os.sep) + os.sep):
        shown = "~/" + path[len(home.rstrip(os.sep)) + 1:]
    else:
        shown = path
    return "%s, line %d" % (shown, n) if n else shown


def host_cpus_value(text):
    """HOST_CPUS-2 and its kin as a number on this machine, or None."""
    m = re.fullmatch(r"HOST_CPUS(?:([-*])([0-9.]+))?", text)
    if not m:
        return int(text) if text.isdigit() else None
    n = host_cpus()
    try:
        if m.group(1) == "-":
            n = n - float(m.group(2))
        elif m.group(1) == "*":
            n = n * float(m.group(2))
    except ValueError:
        return None
    return max(1, int(n))


# ---------------------------------------------------------------------------
# The settings

class Found:
    """A setting's value and where it came from."""

    def __init__(self, value, source, user=True):
        self.value = printable(value)
        self.source = printable(source)
        self.user = user  # set by someone here, not a default or the checked-in .bazelrc


def printable(text):
    """A value read from a file, as it can be printed: a byte that is no UTF-8 shown as U+FFFD."""
    return text.encode("utf-8", "surrogateescape").decode("utf-8", "replace")


class Setting:
    group = "42"
    unsettable = None  # why `unset` is refused, if it is
    readonly = None  # why `set` is refused, if it is

    def __init__(self, name):
        self.name = name

    def get(self, cx):
        """A Found, or None when it is not set and has no default."""
        raise NotImplementedError

    def check(self, cx, raw):
        """The value to store, or a UsageError saying why not."""
        return raw

    def notes(self, cx):
        """What else decides this setting: an environment variable, a file read later."""
        return []


class Login(Setting):
    key = "username"
    kind = "login"
    env_var = "LOGIN42"
    help = ("Your 42 login: the name in every file's 42 header, and the author of "
            "what `42 submit` pushes. Letters, digits, '.', '_' and '-'.")
    store = ".vscode/settings.json (42header.username) and this checkout's git user.name"
    unsettable = "`42 submit` and the file headers need it: set another value instead."
    required = "`42 submit` and the file headers need it: `42 init` sets it."

    def get(self, cx):
        v = workspace.read_identity(cx.ws).get(self.key)
        return Found(v, ".vscode/settings.json") if v else None

    def check(self, cx, raw):
        r = identity(cx, "check", self.kind, raw)
        if r.returncode == 3:
            # The value is fine; settings.json, as it is now, cannot take it.
            raise Failed(r.stderr.strip())
        if r.returncode != 0:
            raise UsageError(r.stderr.strip().replace("identity.sh: ", "", 1))
        return raw

    def write(self, cx, value):
        r = identity(cx, "set", self.kind, value)
        if r.returncode != 0:
            raise Failed(r.stderr.strip())

    def notes(self, cx):
        v = cx.env.get(self.env_var)
        if v:
            return ["%s=%s is set in your environment: `42 submit` and `42 header` use it\n"
                    "instead of this." % (self.env_var, v)]
        return []

    def after(self, cx):
        return ["The files you already have keep the header they were stamped with:\n"
                "`42 header --reset --all` re-stamps them."]


class Email(Login):
    key = "email"
    kind = "email"
    env_var = "EMAIL42"
    help = "Your 42 email: in every file's 42 header, and the email of what `42 submit` pushes."
    store = ".vscode/settings.json (42header.email) and this checkout's git user.email"


class Failed(Exception):
    """A write that did not happen. Exit 1: the request was fine, the file was not."""


def identity(cx, action, kind, value):
    env = bazel.child_env(cx.env)
    env["BUILD_WORKSPACE_DIRECTORY"] = cx.ws
    return subprocess.run(["sh", os.path.join(cx.ws, "tools", "identity.sh"), action, kind, value],
                          cwd=cx.ws, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          universal_newlines=True, check=False)


class Level(Setting):
    help = ("The level `42 test` runs and `42 submit` gates on, when no --level "
            "is given: %s." % ", ".join(LEVELS))
    store = ".submit-level"

    def path(self, cx):
        return os.path.join(cx.ws, ".submit-level")

    def get(self, cx):
        if os.path.isfile(self.path(cx)):
            with open(self.path(cx), encoding="utf-8", errors="replace") as f:
                v = re.sub(r"[ \t\n\r]", "", f.read())
            if v:
                if v not in LEVELS:
                    return Found(v, ".submit-level, which is not a level: `42 test` refuses it")
                return Found(v, ".submit-level")
        return Found("basic", "default", user=False)

    def check(self, cx, raw):
        if raw not in LEVELS:
            close = difflib.get_close_matches(raw, LEVELS, n=1)
            raise refused("%r is not a level. The levels are %s.%s" % (
                raw, ", ".join(LEVELS), " Did you mean %s?" % close[0] if close else ""))
        return raw

    def write(self, cx, value):
        write_file(self.path(cx), value + "\n")

    def unset(self, cx):
        try:
            os.remove(self.path(cx))
        except FileNotFoundError:
            pass
        except OSError as e:
            raise Failed("could not remove %s: %s" % (self.path(cx), e.strerror))

    def notes(self, cx):
        v = cx.env.get("SUBMIT_GATE")
        if v:
            return ["SUBMIT_GATE=%s is set in your environment, and wins over this." % v]
        return []


# ---------------------------------------------------------------------------
# remote.<project>: .submit-remotes, read the way tools/submit.sh reads it

def remotes_table(ws):
    """tools/submit.sh's REMOTES table: every module a remote can be set for, in its order."""
    with open(os.path.join(ws, "tools", "submit.sh"), encoding="utf-8") as f:
        text = f.read()
    try:
        block = text.split("\nREMOTES='\n", 1)[1].split("\n'", 1)[0]
    except IndexError:
        raise RuntimeError("42: found no REMOTES table in tools/submit.sh; has its format changed?")
    mods = []
    for line in block.splitlines():
        row = parse_row(line)
        if row and row[0] not in mods:
            mods.append(row[0])
    return mods


def parse_row(line):
    """(key, url) as tools/submit.sh's parse_row() reads a line; None for a comment or a blank,
    and (None, line) for a line with no '=' once its comment is gone. A NUL is dropped first,
    as the shell's `read` drops it."""
    e = line.replace("\0", "").lstrip(BLANKS)
    if not e or e.startswith("#"):
        return None
    e = re.sub(r"[ \t\n\r\f\v]#.*$", "", e, flags=re.S)
    if "=" not in e:
        return (None, line)
    key, url = e.split("=", 1)
    key = key.strip(BLANKS).rstrip("/")
    if not key:
        return None
    return (key, url.strip(BLANKS))


def key_names(key, mod):
    """tools/submit.sh's key_names(): the path, the project name alone, or the short name."""
    return key in (mod, mod.rsplit("/", 1)[-1], workspace.short_name("//" + mod))


class Remote(Setting):
    store = ".submit-remotes"
    unsettable = None

    def __init__(self, mod, mods):
        self.mod = mod
        self.mods = mods
        self.short = workspace.short_name("//" + mod)
        # Named by its short name, unless another module has the same one.
        shared = sum(workspace.short_name("//" + m) == self.short for m in mods) > 1
        Setting.__init__(self, "remote." + (self.mod if shared else self.short))
        self.help = "The repository `42 submit` pushes %s to." % self.mod

    def path(self, cx):
        return os.path.join(cx.ws, ".submit-remotes")

    def rows(self, cx):
        """(line number, url) for every line of .submit-remotes that names this module."""
        out = []
        for n, line in enumerate(rc_lines(self.path(cx)), 1):
            row = parse_row(line)
            if row and row[0] and key_names(row[0], self.mod):
                out.append((n, row[1]))
        return out

    def get(self, cx):
        rows = self.rows(cx)
        if not rows:
            return None
        n, url = rows[0]
        if len(rows) > 1:
            return Found(url, ".submit-remotes, line %d, and %d more lines: `42 submit` refuses "
                         "a project with two URLs" % (n, len(rows) - 1))
        if url in ("", "REPLACE_ME"):
            return None  # `42 submit` skips it: no URL yet
        return Found(url, ".submit-remotes, line %d" % n)

    def check(self, cx, raw):
        url = check_url(raw)
        self.unshared(cx)
        return url

    def unshared(self, cx):
        """Refuse to touch a line whose key names this module and another: `42 submit` stops on
        it, and rewriting it would take the other module's URL away too."""
        for n, line in enumerate(rc_lines(self.path(cx)), 1):
            row = parse_row(line)
            if row and row[0] and key_names(row[0], self.mod):
                named = [m for m in self.mods if key_names(row[0], m)]
                if len(named) > 1:
                    raise refused("line %d of .submit-remotes, %r, names %d projects (%s), and "
                                  "`42 submit` stops on it: key that line by the project's path "
                                  "first." % (n, row[0], len(named), " ".join(named)))

    def unset(self, cx):
        self.unshared(cx)
        if os.path.exists(self.path(cx)):
            write_file(self.path(cx), self.rewrite(cx, None))

    def rewrite(self, cx, url):
        """.submit-remotes with this module's lines gone, and `path=url` where the first one was."""
        lines = rc_lines(self.path(cx))
        out, placed = [], False
        for line in lines:
            row = parse_row(line)
            if row and row[0] and key_names(row[0], self.mod):
                if url is not None and not placed:
                    out.append("%s=%s" % (self.mod, url))
                    placed = True
                continue
            out.append(line)
        if url is not None and not placed:
            out.append("%s=%s" % (self.mod, url))
        return "".join(l + "\n" for l in out)

    def write(self, cx, value):
        write_file(self.path(cx), self.rewrite(cx, value))


def check_url(raw):
    if not raw or raw == "REPLACE_ME":
        raise refused("give the URL of the repository: %s." % URL_HELP)
    if re.search(r"\s", raw):
        raise refused("%r holds a blank, which no repository URL has." % raw)
    if not any(rx.match(raw) for rx in URL_FORMS):
        raise refused("%r is not a repository URL. One of: %s." % (raw, URL_HELP))
    return raw


# ---------------------------------------------------------------------------
# bazel.*: .bazelrc.local

class BazelSetting(Setting):
    group = "bazel"
    store = LOCAL_RC
    # flags: (command, flag, value pattern) for each line this setting writes.
    # views: (commands, flag, value pattern with its group) for each value
    # Bazel takes, its commands from the least specific to the most.

    def marker(self):
        return "# set by `42 config set %s`" % self.name

    def sets(self, line):
        """Whether an rc line sets one of this setting's flags and nothing else: the only kind
        of line 42 config writes, comments out or removes. A line that sets other flags too is
        left as it is, or they would go with it."""
        return any(re.fullmatch(r"[ \t]*%s[ \t]+--%s(=|[ \t]+)%s[ \t\r]*" % (c, re.escape(f), v), line)
                   for c, f, v in self.flags)

    def mixed(self, cx):
        """Where .bazelrc.local sets one of these flags beside other flags."""
        path = os.path.join(cx.ws, LOCAL_RC)
        out = []
        for n, line in enumerate(rc_lines(path), 1):
            if not self.sets(line) and any(
                    re.match(r"\s*%s\s" % c, line) and re.search(r"(^|\s)--%s(=|\s+)%s" % (re.escape(f), v), line)
                    for c, f, v in self.flags):
                out.append(where(cx.ws, cx.env, path, n))
        return out

    def rewrite(self, cx, lines_to_add, why):
        """.bazelrc.local with this setting's own block gone, any other line that sets only
        its flags commented out, and lines_to_add at the end."""
        out, block = [], 0
        for line in rc_lines(os.path.join(cx.ws, LOCAL_RC)):
            if line == self.marker():
                block = len(self.flags)
                continue
            if block and self.sets(line):
                block -= 1
                continue
            block = 0
            out.append("# %s by 42 config: %s" % (why, line) if self.sets(line) else line)
        while out and not out[-1].strip():
            out.pop()
        if lines_to_add:
            out += [""] + [self.marker()] + lines_to_add
        return "".join(l + "\n" for l in out)

    def lines(self, value):
        return ["%s --%s=%s" % (c, f, value) for c, f, _ in self.flags]

    def write(self, cx, value):
        write_file(os.path.join(cx.ws, LOCAL_RC), self.rewrite(cx, self.lines(value), "replaced"))

    def unset(self, cx):
        path = os.path.join(cx.ws, LOCAL_RC)
        if not any(line == self.marker() or self.sets(line) for line in rc_lines(path)):
            mixed = self.mixed(cx)
            if mixed:
                raise Failed(wrap("%s sets %s beside other flags, and 42 config leaves that line "
                                  "to you." % (" and ".join(mixed), self.name), 4))
            raise Failed(wrap("%s comes from %s, which 42 config does not edit: change it there."
                              % (self.name, self.get(cx).source), 4))
        write_file(path, self.rewrite(cx, [], "removed"))

    def notes(self, cx):
        out = []
        local = os.path.join(cx.ws, LOCAL_RC)
        for commands, flag, value in self.views:
            if rc_value(cx.ws, cx.env, commands, flag, value, files=[local]) is None:
                continue
            won = rc_value(cx.ws, cx.env, commands, flag, value)
            if won and won[1] != local:
                out.append("%s sets it too, and Bazel takes it over this checkout's %s." % (
                    where(cx.ws, cx.env, won[1], won[2]), LOCAL_RC))
        return out + ["%s sets it beside other flags: 42 config leaves that line as it is." % w
                      for w in self.mixed(cx)]


def whole_number(raw, low, high):
    """raw as an int when it is ASCII digits from low to high, else None. str.isdigit() takes
    '\u00b2', which int() then refuses."""
    if re.fullmatch(r"[0-9]+", raw) and low <= int(raw) <= high:
        return int(raw)
    return None


class Cpus(BazelSetting):
    name = "bazel.cpus"
    flags = (("build", "local_resources", r"cpu=\S+"), ("test", "local_test_jobs", r"\S+"))
    views = ((("common", "build"), "local_resources", r"cpu=(\S+)"),
             (("common", "build", "test"), "local_test_jobs", r"(\S+)"))
    help = ("How many CPUs Bazel builds with, and how many tests it runs at once. "
            "The checked-in .bazelrc leaves two free: HOST_CPUS-2.")

    def __init__(self):
        Setting.__init__(self, self.name)

    def get(self, cx):
        cpu, jobs = (rc_value(cx.ws, cx.env, *view) for view in self.views)
        checked_in = os.path.join(cx.ws, ".bazelrc")
        user = any(f is not None and f[1] != checked_in for f in (cpu, jobs))
        if cpu is None:
            value, source = str(host_cpus()), "Bazel's default: every CPU"
        else:
            value, source = cpu[0], where(cx.ws, cx.env, cpu[1], cpu[2])
        shown = value
        num = host_cpus_value(value)
        if num is not None and value != str(num):
            shown = "%s (%d on this machine)" % (value, num)
        if jobs and jobs[0] != value:
            source += "; tests at once: %s, from %s" % (jobs[0], where(cx.ws, cx.env, jobs[1], jobs[2]))
        return Found(shown, source, user=user)

    def check(self, cx, raw):
        n = host_cpus()
        if whole_number(raw, 1, n) is None:
            raise refused("bazel.cpus is a whole number from 1 to %d, the CPUs this machine has." % n)
        return str(int(raw))

    def lines(self, value):
        return ["build --local_resources=cpu=%s" % value, "test --local_test_jobs=%s" % value]

    def after(self, cx):
        return ["The next Bazel command uses it; what it has built and cached is kept."]


class IdleSecs(BazelSetting):
    name = "bazel.idle_secs"
    flags = (("startup", "max_idle_secs", r"\S+"),)
    views = ((("startup",), "max_idle_secs", r"(\S+)"),)
    help = ("How long Bazel's server waits, idle, before it stops and frees its "
            "memory, in seconds: at least 60. Bazel's default is 10800, three hours.")

    def __init__(self):
        Setting.__init__(self, self.name)

    def get(self, cx):
        found = rc_value(cx.ws, cx.env, *self.views[0])
        if found is None:
            return Found("10800", "Bazel's default", user=False)
        value, path, n = found
        return Found(value, where(cx.ws, cx.env, path, n), user=path != os.path.join(cx.ws, ".bazelrc"))

    def check(self, cx, raw):
        if whole_number(raw, 60, INT_MAX) is None:
            raise refused("bazel.idle_secs is a whole number of seconds from 60 to %d "
                          "(0, to Bazel, is never)." % INT_MAX)
        return str(int(raw))

    def after(self, cx):
        return ["A server already running keeps the value it started with: `42 stop`\n"
                "stops it, and the next command starts one with this."]


# ---------------------------------------------------------------------------
# machine.*: read-only

class Machine(Setting):
    group = "machine"

    def __init__(self, name, help_, read, readonly):
        Setting.__init__(self, name)
        self.help = help_
        self.read = read
        self.readonly = readonly
        self.store = "read-only"

    def get(self, cx):
        return self.read(cx)


def read_root(cx):
    root = report.state_root(cx.ws, cx.env)
    env = bazel.child_env(cx.env)
    r = subprocess.run(["sh", "-c", '. "$1/tools/drives.sh" && drives_rc_root_file "$1"', "sh", cx.ws],
                       cwd=cx.ws, env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                       universal_newlines=True, check=False)
    f = r.stdout.strip()
    return Found(root, where(cx.ws, cx.env, f) if f else "tools/bazel's choice for this machine", user=False)


def read_rc(commands, flag, missing, value=r"(\S+)"):
    def read(cx):
        found = rc_value(cx.ws, cx.env, commands, flag, value)
        if found is None:
            return Found(missing, "no rc file sets it", user=False)
        return Found(found[0], where(cx.ws, cx.env, found[1], found[2]), user=False)
    return read


SETUP_CHOOSES = "`sh tools/setup.sh` chooses it for this machine (docs/environment.md)."

MACHINE = (
    ("machine.root", "Where Bazel keeps everything it downloads and builds for this checkout.",
     read_root, SETUP_CHOOSES),
    ("machine.disk_cache", "The cache every checkout on this machine shares, if there is one.",
     read_rc(("common", "build"), "disk_cache", "none"), SETUP_CHOOSES),
    ("machine.disk_cache_max", "How big that cache may grow before Bazel trims it.",
     read_rc(("common", "build"), "experimental_disk_cache_gc_max_size", "no limit"), SETUP_CHOOSES),
    ("machine.heap", "The most Java heap Bazel's server may take (not all of its memory).",
     read_rc(("startup",), "host_jvm_args", "the JVM's default", r"-Xmx(\S+)"),
     "the checked-in .bazelrc sets it, and says why that value."),
)


# ---------------------------------------------------------------------------
# The table, and finding a setting by name

def settings(cx):
    out = [Login("login"), Email("email"), Level("level")]
    mods = remotes_table(cx.ws)
    out += [Remote(m, mods) for m in mods]
    out += [Cpus(), IdleSecs()]
    out += [Machine(*m) for m in MACHINE]
    return out


def find(cx, name):
    table = settings(cx)
    for s in table:
        if s.name == name:
            return s
    if name.startswith("remote."):
        word = name[len("remote."):].rstrip("/")
        named = [s for s in table if isinstance(s, Remote) and key_names(word, s.mod)]
        if len(named) == 1:
            return named[0]
        if named:
            raise refused("%s names %d projects: give the one you mean by its path, %s." % (
                name, len(named), " or ".join("remote." + s.mod for s in named)))
        raise UsageError("%s: %r is not a project `42 submit` pushes. They are:\n    %s" % (
            name, word, wrap(" ".join(s.short for s in table if isinstance(s, Remote)), 4)))
    names = [s.name for s in table if not isinstance(s, Remote)] + ["remote.<project>"]
    close = difflib.get_close_matches(name, names, n=2)
    raise refused("no setting %r.%s `42 config --help` lists them." % (
        name, " Did you mean %s?" % " or ".join(close) if close else ""))


def refused(text):
    """A UsageError whose lines fit WIDTH once main() puts "42: " before the first."""
    return UsageError(wrap(text, 4))


def write_file(path, text):
    """Into the file, not moved over it: a rewrite in place keeps its mode and owner."""
    try:
        with open(path, "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
            f.write(text)
    except OSError as e:
        raise Failed("could not write %s: %s" % (path, e.strerror))


def wrap(text, indent, width=WIDTH):
    """text on lines of at most `width`, every line after the first indented; a `command`
    is never split across two."""
    kept = re.sub(r"`[^`]*`", lambda m: m.group(0).replace(" ", "\0"), text)
    return textwrap.fill(kept, width - indent, break_on_hyphens=False,
                         break_long_words=False).replace("\0", " ").replace("\n", "\n" + " " * indent)


# ---------------------------------------------------------------------------
# What 42 prints

GROUPS = (
    ("42", "42, this checkout"),
    ("bazel", "Bazel, this checkout (%s, read after .bazelrc)" % LOCAL_RC),
    ("machine", "Machine, read-only (`sh tools/setup.sh` and .bazelrc set these)"),
)

NAME_COL = 25  # where a value starts: two blanks, the longest name, one more


def row(s, found):
    """(text, shortened): one setting as list shows it, every line within WIDTH.

    Name, value and source on one line when they fit; else the source on a
    line of its own under the value; else, for a value too wide for that,
    the value on a line of its own too, cut in the middle if it has to be.
    """
    value = found.value if found else "(not set)"
    source = "(%s)" % found.source if found and found.source else ""
    head = "  %-*s " % (NAME_COL - 3, s.name)
    if len(head) == NAME_COL and len(head + value + "  " + source) <= WIDTH:
        return (head + value + "  " + source).rstrip(), False
    if len(head) == NAME_COL and len(head + value) <= WIDTH:
        return head + value + ("\n" + " " * NAME_COL + wrap(source, NAME_COL) if source else ""), False
    room = WIDTH - 6
    short = len(value) > room
    if short:
        keep = room - 3
        value = value[:keep // 2] + "..." + value[-(keep - keep // 2):]
    return "  %s\n      %s%s" % (s.name, value, "\n      " + wrap(source, 6) if source else ""), short


def cmd_list(cx, every):
    out = []
    shortened = False
    for group, title in GROUPS:
        lines = []
        for s in settings(cx):
            if s.group != group:
                continue
            found = s.get(cx)
            # A setting with no default is shown missing: `42 submit` refuses
            # to run without it, and calling it a default sent nobody to init.
            needed = found is None and getattr(s, "required", None)
            if not every and not needed and (found is None or not found.user):
                continue
            text, short = row(s, found)
            shortened = shortened or short
            lines.append(text)
            for note in s.notes(cx) + ([needed] if needed else []):
                lines.append("      " + wrap("note: " + note.replace("\n", " "), 6))
        if lines:
            out.append("%s:\n%s" % (wrap(title, 0), "\n".join(lines)))
    if not every:
        out.append("`42 config list --all` shows every setting, defaults too.")
    if shortened:
        out.append("A value shortened with ... is printed whole by `42 config get NAME`.")
    cx.out.say("\n\n".join(out))
    return 0


def cmd_get(cx, name):
    s = find(cx, name)
    found = s.get(cx)
    if found is None:
        cx.out.err("42: %s is not set. `42 config set %s %s` sets it." % (
            s.name, s.name, "URL" if isinstance(s, Remote) else "VALUE"))
        return 1
    cx.out.say(found.value)
    cx.out.say("  (%s)" % found.source)
    for note in s.notes(cx):
        cx.out.say("  " + wrap("note: " + note.replace("\n", " "), 2))
    return 0


def cmd_set(cx, name, raw, dry):
    s = find(cx, name)
    if s.readonly:
        raise refused("%s is read-only here: %s" % (s.name, s.readonly))
    value = s.check(cx, raw)
    old = s.get(cx)
    change = "%s: %s -> %s" % (s.name, old.value if old else "(not set)", value)
    if dry:
        cx.out.say(change)
        cx.out.say("  " + wrap("--dry-run: nothing written; without it, %s is written." % s.store, 2))
        return 0
    s.write(cx, value)
    cx.out.say(change)
    cx.out.say("  " + wrap("written to %s" % s.store, 2))
    said = getattr(s, "after", lambda cx: [])(cx)
    if isinstance(s, BazelSetting):
        said.append("%s belongs to this checkout: every Bazel command run in it reads "
                    "it, a dev container's on the same folder too." % LOCAL_RC)
    for line in said + ["note: " + n for n in s.notes(cx)]:
        cx.out.say(wrap(line.replace("\n", " "), 0))
    return 0


def cmd_unset(cx, name, dry):
    s = find(cx, name)
    if s.readonly:
        raise refused("%s is read-only here: %s" % (s.name, s.readonly))
    if s.unsettable:
        raise refused("%s cannot be unset: %s" % (s.name, s.unsettable))
    old = s.get(cx)
    if old is None or not old.user:
        cx.out.say("%s is not set here: nothing to unset." % s.name)
        return 0
    if dry:
        cx.out.say("%s: %s -> unset" % (s.name, old.value))
        cx.out.say("  " + wrap("--dry-run: nothing written; without it, %s is written." % s.store, 2))
        return 0
    s.unset(cx)
    now = s.get(cx)
    cx.out.say("%s: %s -> %s" % (s.name, old.value, "%s (%s)" % (now.value, now.source) if now else "(not set)"))
    cx.out.say("  " + wrap("written to %s" % s.store, 2))
    for n in s.notes(cx):
        cx.out.say(wrap("note: " + n.replace("\n", " "), 0))
    return 0


USAGE = "[list [--all] | get NAME | set NAME VALUE | unset NAME]"


def run(cx, words, every, dry):
    """`42 config WORDS`: exit 0 done, 1 not set or not written, 2 a request it refused."""
    verb, args = (words[0], words[1:]) if words else ("list", [])
    want = {"list": 0, "get": 1, "set": 2, "unset": 1}
    if verb not in want:
        raise refused("42 config %s: no such verb. `42 config --help` says how to call it." % verb)
    if len(args) != want[verb]:
        raise refused("42 config %s takes %s. `42 config --help` says how to call it." % (
            verb, {0: "no name", 1: "a setting's name", 2: "a setting's name and its value"}[want[verb]]))
    if every and verb != "list":
        raise refused("--all goes with 42 config list. `42 config --help` says how to call it.")
    try:
        if verb == "list":
            return cmd_list(cx, every)
        if verb == "get":
            return cmd_get(cx, args[0])
        if verb == "set":
            return cmd_set(cx, args[0], args[1], dry)
        return cmd_unset(cx, args[0], dry)
    except Failed as e:
        cx.out.err("42: %s" % e)
        return 1


def help_text(cx):
    """What `42 help config` adds below the usage: every setting, by kind."""
    out = []
    table = settings(cx)
    for group, title in GROUPS:
        out.append("\n  %s:" % title)
        seen_remote = False
        for s in table:
            if s.group != group:
                continue
            if isinstance(s, Remote):
                if seen_remote:
                    continue
                seen_remote = True
                name, text = "remote.<project>", (
                    "The repository `42 submit` pushes a project to (remote.c-05), as a URL: "
                    "%s." % URL_HELP)
            else:
                name, text = s.name, s.help
            if s.group != "machine":
                text += " Stored in %s." % s.store
            out.append("    %s\n        %s" % (name, wrap(text, 8)))
    out.append("\n  `set` checks the value before it writes, and says what it was;\n"
               "  --dry-run checks it and writes nothing. `unset` puts a setting back to\n"
               "  its default (login and email have none). Exit 1: not set, or a file\n"
               "  that could not be written. It runs no Bazel command.")
    return "\n".join(out)
