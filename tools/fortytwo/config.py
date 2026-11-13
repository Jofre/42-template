"""42 config: every setting of this checkout, read and set in one place.

Each setting stays in the file its readers already read -- .submit-level,
.submit-remotes, .vscode/settings.json, .bazelrc.local -- so `42 config` is
another way into those files, never a second copy of a value. It runs no Bazel
command, one of the two commands of 42 that do not (AGENTS.md, section 4): it
has to work when Bazel does not, and starting a server to read a file would
cost far more memory than the file.

Three kinds of setting, and every list says which a row is:
  42, this checkout     what 42's own tools read: your identity, your level,
                        where each project is pushed (titled "and your user
                        file" while one of them may live there too);
  Bazel, this checkout  the Bazel flags this checkout's .bazelrc.local may
                        override (Bazel reads it after .bazelrc);
  machine, read-only    where Bazel keeps its state on this machine, and how
                        big it may grow: shown, never set here, because
                        `sh tools/setup.sh` and .bazelrc choose them.

A setting may also live in your user file, which every checkout of yours
reads (userconfig.py says where it is), once every one of its readers
reads that file too, or is handed its value by 42 as a flag and stops when
run without it (level: tools/submit.sh's --gate-level, workspace.level_source):
the user file is then a layer they all resolve, never a second copy. SCOPES is
the order, a checkout's own value first. An
environment variable every reader honours (SUBMIT_GATE) wins over both, and
one that only some readers honour (LOGIN42) is a note. `42 config list`
shows every layer that is set, the one in use on the setting's line.
"""

import difflib
import os
import re
import subprocess

import bazel
import report
import userconfig
import workspace
from workspace import LEVELS, WIDTH, UsageError, where, wrap

# Where a setting may live, the one that wins first: this checkout's own file
# for it, then your user file. `42 config` resolves it through Setting.layers;
# workspace.level_source writes the same order out for level, since workspace
# cannot import config, and test_config.GlobalLevel holds the two together.
SCOPES = ("local", "global")

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
    .bazelrc, the .bazelrc.local its last line imports, then the home rc. The
    system rc is C_PISCINE_SYSTEM_BAZELRC's file when that is set, as there.
    """
    home = environ.get("HOME")
    files = [environ.get("C_PISCINE_SYSTEM_BAZELRC") or SYSTEM_RC,
             os.path.join(ws, ".bazelrc"), os.path.join(ws, LOCAL_RC)]
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


def rc_settings(ws, environ, commands, flag, value=r"(\S+)", files=None):
    """Every (value, file, line number) that sets `flag`: the one Bazel takes first, then
    the rest in the order Bazel would take them, each if the ones before it were gone.

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
    hits = []
    for path in rc_files(ws, environ) if files is None else files:
        for n, line in enumerate(rc_lines(path), 1):
            m = line_rx.match(line)
            if not m:
                continue
            for f in flag_rx.finditer(line):
                hits.append((commands.index(m.group(1)), len(hits), (f.group(1).strip('"\''), path, n)))
    return [hit for _, _, hit in sorted(hits, reverse=True)]


def rc_value(ws, environ, commands, flag, value=r"(\S+)", files=None):
    """(value, file, line number) of the line Bazel takes `flag` from, or None."""
    hits = rc_settings(ws, environ, commands, flag, value, files)
    return hits[0] if hits else None


def rc_scope(ws, environ, path):
    """Which of Bazel's rc files path is, as a list tags a value it sets."""
    home = environ.get("HOME")
    if path == os.path.join(ws, ".bazelrc"):
        return "checked in"
    if path == os.path.join(ws, LOCAL_RC):
        return "local"
    if home and path == os.path.join(home, ".bazelrc"):
        return "home"
    return "system"


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
    """A setting's value, where it came from, and the scope that set it."""

    def __init__(self, value, source, user=True, scope=None):
        self.value = printable(value)
        self.source = printable(source)
        self.user = user  # set by someone here, not a default or the checked-in .bazelrc
        self.scope = scope  # its tag in a list: local, global, environment, default, home, ...

    def tag(self):
        """Where it came from, as every list and get shows it: (scope: where)."""
        text = ": ".join(t for t in (self.scope, self.source) if t)
        return "(%s)" % text if text else ""

    def same(self, other):
        return other is not None and (self.value, self.source, self.scope) == (other.value, other.source, other.scope)


def printable(text):
    """A value read from a file, as it can be printed: a byte that is no UTF-8 shown as U+FFFD."""
    return text.encode("utf-8", "surrogateescape").decode("utf-8", "replace")


def user_doc(cx):
    """The user file as read, once per command (a write forgets it): every layer reads this one."""
    doc = getattr(cx, "user_file", None)
    if doc is None:
        doc = cx.user_file = userconfig.load(cx.env)
    return doc


def user_error(cx, doc):
    """A user file 42 will not read, as a message: the file, the line, why, and the fix."""
    e = doc.error
    return "%s: %s" % (where(cx.ws, cx.env, doc.path, e.n), e.why)


class Setting:
    group = "42"
    scopes = ("local",)  # the SCOPES it may be set in; ("local", "global") opts it in
    unsettable = None  # why `unset` is refused, if it is
    readonly = None  # why `set` is refused, if it is
    # Why no reader of it reads your user file, when "global" is not in scopes.
    local_only = "no reader of it reads your user file"
    # The commands that stop, when "global" is in scopes, while your user file
    # cannot be read and nothing nearer sets it: it would decide their value.
    stops = None

    def __init__(self, name):
        self.name = name

    def get(self, cx):
        """This checkout's Found, its default when nothing here sets it; None when it has none."""
        raise NotImplementedError

    def check(self, cx, raw):
        """The value to store, or a UsageError saying why not."""
        return raw

    def check_value(self, raw):
        """The value to store in your user file, or a UsageError saying why not. From raw
        alone: every checkout reads that file, so no one checkout's files can decide it. A
        setting whose scopes hold "global" says it."""
        raise NotImplementedError

    def environment(self, cx):
        """A Found for each environment variable set for it, the one that wins first. Only a
        variable every reader of the setting honours is one; notes() says any other."""
        return []

    def scoped(self, cx, scope):
        """The Found one scope gives it, or None: this checkout's (its default included), or
        your user file's."""
        if scope == "local":
            return self.get(cx)
        return global_found(cx, self)

    def layers(self, cx):
        """Every Found set for it, the one its readers use first, then the rest in the order
        they would win: the environment, then each of SCOPES it may be set in."""
        out = self.environment(cx)
        for scope in SCOPES:
            if scope in self.scopes:
                found = self.scoped(cx, scope)
                if found is not None and found.user:
                    out.append(found)
        return out

    def default(self, cx):
        """The Found it has when nothing sets it, or None."""
        found = self.get(cx)
        return found if found is not None and not found.user else None

    def resolve(self, cx):
        """The Found its readers use: the first of its layers, else its default, else None."""
        layers = self.layers(cx)
        return layers[0] if layers else self.default(cx)

    def notes(self, cx):
        """What else decides this setting: an environment variable not every reader honours."""
        return []


def global_found(cx, s):
    """Your user file's Found for s, or None: not set there, or a file 42 will not read."""
    doc = user_doc(cx)
    if s.name not in doc.entries:
        return None
    value, n = doc.entries[s.name]
    source = where(cx.ws, cx.env, doc.path, n)
    try:
        s.check_value(value)
    except UsageError as e:
        source += ", which 42 refuses: %s" % " ".join(str(e).split())
    return Found(value, source, scope="global")


class Login(Setting):
    key = "username"
    kind = "login"
    env_var = "LOGIN42"
    help = ("Your 42 login: the name in every file's 42 header, and the author of "
            "what `42 submit` pushes. Letters, digits, '.', '_' and '-'.")
    store = ".vscode/settings.json (42header.username) and this checkout's git user.name"
    unsettable = "`42 submit` and the file headers need it: set another value instead."
    required = "`42 submit` and the file headers need it: `42 init` sets it."
    local_only = "VS Code's 42header extension reads only .vscode/settings.json"

    def get(self, cx):
        v = workspace.read_identity(cx.ws, bazel.child_env(cx.env)).get(self.key)
        return Found(v, ".vscode/settings.json", scope="local") if v else None

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
    # `42 test`, `42 submit`, `42 watch`, `42 clues` and a bare `42 norm` read it in
    # workspace.level_source; tools/submit.sh gets it from `42 submit` as
    # --gate-level, and stops when run without one.
    scopes = ("local", "global")
    stops = "`42 test`, `42 submit`, `42 watch`, `42 clues` and a bare `42 norm`"

    def path(self, cx):
        return os.path.join(cx.ws, ".submit-level")

    def get(self, cx):
        if os.path.isfile(self.path(cx)):
            with open(self.path(cx), encoding="utf-8", errors="replace") as f:
                v = re.sub(r"[ \t\n\r]", "", f.read())
            if v:
                if v not in LEVELS:
                    return Found(v, ".submit-level, which is not a level: `42 test` refuses it", scope="local")
                return Found(v, ".submit-level", scope="local")
        return Found("basic", "", user=False, scope="default")

    def environment(self, cx):
        # `42 test` (workspace.resolve_level) and tools/submit.sh both take
        # SUBMIT_GATE over the file, and both read an empty one as unset.
        v = cx.env.get("SUBMIT_GATE")
        if not v:
            return []
        if v not in LEVELS:
            return [Found(v, "SUBMIT_GATE, which is not a level: `42 test` refuses it", scope="environment")]
        return [Found(v, "SUBMIT_GATE", scope="environment")]

    def check(self, cx, raw):
        return self.check_value(raw)

    def check_value(self, raw):
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
    local_only = "tools/submit.sh reads only .submit-remotes"

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
                         "a project with two URLs" % (n, len(rows) - 1), scope="local")
        if url in ("", "REPLACE_ME"):
            return None  # `42 submit` skips it: no URL yet
        return Found(url, ".submit-remotes, line %d" % n, scope="local")

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
    local_only = ("Bazel reads its rc files and never your user file: ~/.bazelrc is Bazel's "
                  "own file for every checkout of yours")
    # flags: (command, flag, value pattern) for each line this setting writes.
    # views: (commands, flag, value pattern with its group) for each value
    # Bazel takes, its commands from the least specific to the most.

    def shown(self, value):
        """A value as a list shows it."""
        return value

    def layers(self, cx):
        """Every rc line that sets its value, the one Bazel takes first (as get() says it, with
        all get() adds), then the rest in the order Bazel would take them: Bazel's own order,
        not SCOPES, since 42 decides none of it."""
        won = self.get(cx)
        hits = rc_settings(cx.ws, cx.env, *self.views[0])
        checked_in = os.path.join(cx.ws, ".bazelrc")
        rest = [Found(self.shown(v), where(cx.ws, cx.env, path, n), user=path != checked_in,
                      scope=rc_scope(cx.ws, cx.env, path)) for v, path, n in hits[1:]]
        return ([won] if hits or won.user else []) + rest

    def scoped(self, cx, scope):
        """This checkout's: the line of its .bazelrc.local or .bazelrc that Bazel takes first,
        else Bazel's default when no rc file sets it; never ~/.bazelrc's or the system's, which
        are no file of this checkout's."""
        for f in self.layers(cx):
            if f.scope in ("local", "checked in"):
                return f
        found = self.get(cx)
        return found if found is not None and found.scope == "Bazel's default" else None

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
        # Which rc file wins over which is in the layers a list shows, for
        # the first view; a second one (bazel.cpus's tests at once) is said
        # here.
        out = []
        local = os.path.join(cx.ws, LOCAL_RC)
        for commands, flag, value in self.views[1:]:
            if rc_value(cx.ws, cx.env, commands, flag, value, files=[local]) is None:
                continue
            won = rc_value(cx.ws, cx.env, commands, flag, value)
            if won and won[1] != local:
                out.append("%s sets --%s too, and Bazel takes it over this checkout's %s." % (
                    where(cx.ws, cx.env, won[1], won[2]), flag, LOCAL_RC))
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
            value, source, scope = str(host_cpus()), "every CPU", "Bazel's default"
        else:
            value, source = cpu[0], where(cx.ws, cx.env, cpu[1], cpu[2])
            scope = rc_scope(cx.ws, cx.env, cpu[1])
        if jobs and jobs[0] != value:
            source += "; tests at once: %s, from %s" % (jobs[0], where(cx.ws, cx.env, jobs[1], jobs[2]))
        return Found(self.shown(value), source, user=user, scope=scope)

    def shown(self, value):
        num = host_cpus_value(value)
        if num is not None and value != str(num):
            return "%s (%d on this machine)" % (value, num)
        return value

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
            return Found("10800", "", user=False, scope="Bazel's default")
        value, path, n = found
        return Found(value, where(cx.ws, cx.env, path, n), user=path != os.path.join(cx.ws, ".bazelrc"),
                     scope=rc_scope(cx.ws, cx.env, path))

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
    local_only = "42 reads it from what sets up Bazel on this machine, and sets none of it"

    def __init__(self, name, help_, read, readonly):
        Setting.__init__(self, name)
        self.help = help_
        self.read = read
        self.readonly = readonly
        self.store = "read-only"

    def get(self, cx):
        return self.read(cx)

    def layers(self, cx):
        """As a Bazel setting's: every rc line that sets it, the one Bazel takes first."""
        view = getattr(self.read, "view", None)
        if view is None:
            return []
        hits = rc_settings(cx.ws, cx.env, *view)
        return [found_at(cx, hit) for hit in hits]


def read_root(cx):
    root = report.state_root(cx.ws, cx.env)
    env = bazel.child_env(cx.env)
    r = subprocess.run(["sh", "-c", '. "$1/tools/drives.sh" && drives_rc_root_file "$1"', "sh", cx.ws],
                       cwd=cx.ws, env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                       universal_newlines=True, check=False)
    f = r.stdout.strip()
    if f:
        return Found(root, where(cx.ws, cx.env, f), user=False, scope=rc_scope(cx.ws, cx.env, f))
    return Found(root, "tools/bazel's choice for this machine", user=False)


def found_at(cx, hit):
    """A machine setting's Found from one rc line: never a setting of yours, since it is read-only."""
    value, path, n = hit
    return Found(value, where(cx.ws, cx.env, path, n), user=False, scope=rc_scope(cx.ws, cx.env, path))


def read_rc(commands, flag, missing, value=r"(\S+)"):
    def read(cx):
        found = rc_value(cx.ws, cx.env, commands, flag, value)
        if found is None:
            return Found(missing, "no rc file sets it", user=False)
        return found_at(cx, found)
    read.view = (commands, flag, value)
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


def known(cx, name):
    """The setting find() gives name, or None where find() refuses it."""
    try:
        return find(cx, name)
    except UsageError:
        return None


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


# ---------------------------------------------------------------------------
# What 42 prints

GROUPS = (
    ("42", "42, this checkout"),
    ("bazel", "Bazel, this checkout (%s, read after .bazelrc)" % LOCAL_RC),
    ("machine", "Machine, read-only (`sh tools/setup.sh` and .bazelrc set these)"),
)

NAME_COL = 25  # where a value starts: two blanks, the longest name, one more


def titles(table):
    """GROUPS, the title of a group that holds a setting your user file may hold saying so."""
    out = []
    for group, title in GROUPS:
        if any(s.group == group and "global" in s.scopes for s in table):
            title = title.replace("this checkout", "this checkout and your user file", 1)
        out.append((group, title))
    return out


def cut(value, room):
    """(value within room columns, whether it was cut): cut in the middle if it has to be."""
    if len(value) <= room:
        return value, False
    keep = room - 3
    return value[:keep // 2] + "..." + value[-(keep - keep // 2):], True


def row(name, found):
    """(text, shortened): one setting as list shows it, every line within WIDTH.

    Name, value and where it came from on one line when they fit; else where
    on a line of its own under the value; else, for a value too wide for that,
    the value on a line of its own too, cut in the middle if it has to be.
    """
    value = found.value if found else "(not set)"
    source = found.tag() if found else ""
    head = "  %-*s " % (NAME_COL - 3, name)
    if len(head) == NAME_COL and len(head + value + "  " + source) <= WIDTH:
        return (head + value + "  " + source).rstrip(), False
    if len(head) == NAME_COL and len(head + value) <= WIDTH:
        return head + value + ("\n" + " " * NAME_COL + wrap(source, NAME_COL) if source else ""), False
    value, short = cut(value, WIDTH - 6)
    return "  %s\n      %s%s" % (name, value, "\n      " + wrap(source, 6) if source else ""), short


def layer_line(word, found, indent, room=None):
    """(text, shortened): another layer of a setting under its line, `not used: VALUE  (tag)`
    or `in use: VALUE  (tag)`; its value cut to room when room is given."""
    value, short = cut(found.value, room) if room else (found.value, False)
    return " " * indent + wrap("%s: %s  %s" % (word, value, found.tag()), indent), short


def note_line(note, indent):
    return " " * indent + wrap("note: " + note.replace("\n", " "), indent)


def user_file_notes(cx, table):
    """What a list says of your user file below every group: a line 42 will not read, or
    the names in it no setting reads there."""
    doc = user_doc(cx)
    out = ["note: " + n for n in userconfig.notes(cx.env)]
    if doc.error:
        out.append("note: %s Nothing is read from it until that is fixed.%s" % (
            user_error(cx, doc), "".join(" " + stopped(cx, s) for s in table if stopped(cx, s))))
    else:
        read = {s.name for s in table if "global" in s.scopes}
        unread = [name for name in doc.entries if name not in read]
        if unread:
            out.append("%s holds %d name%s no setting reads there: `42 config list --global` shows %s." % (
                where(cx.ws, cx.env, doc.path), len(unread), "" if len(unread) == 1 else "s",
                "it" if len(unread) == 1 else "them"))
    return [wrap(text, 0) for text in out]


def stopped(cx, s):
    """What stops while your user file cannot be read, for s, or None: nothing does, or
    something nearer sets s."""
    if s.stops and "global" in s.scopes and user_doc(cx).error and not s.layers(cx):
        return "%s stop until it is fixed, since nothing nearer sets %s." % (s.stops, s.name)
    return None


def global_notes(cx, s):
    """What get says of your user file for one setting."""
    doc = user_doc(cx)
    if "global" in s.scopes:
        if doc.error:
            return ["%s Nothing is read from it until that is fixed.%s" % (
                user_error(cx, doc), " " + stopped(cx, s) if stopped(cx, s) else "")]
        return []
    if s.name in doc.entries:
        return ["%s sets it too, and nothing reads it there: %s." % (
            where(cx.ws, cx.env, doc.path, doc.entries[s.name][1]), s.local_only)]
    return []


def in_scope(s, scope, verb):
    """Refuse a scope the setting cannot live in, saying where it lives and why."""
    value = {"get": "", "unset": "", "set": " URL" if isinstance(s, Remote) else " VALUE"}[verb]
    if scope == "global" and "global" not in s.scopes:
        raise refused("%s lives in this checkout only: %s. `42 config %s %s%s` %s." % (
            s.name, s.local_only, verb, s.name, value,
            "sets it there" if verb == "set" else "shows it"))
    if scope == "local" and "local" not in s.scopes:
        raise refused("%s lives in your user file only: `42 config %s --global %s%s`." % (
            s.name, verb, s.name, value))


def user_path(cx):
    """Your user file's path, as a person finds it; Failed when there is none here."""
    doc = user_doc(cx)
    if doc.path is None:
        raise Failed(wrap(doc.why + ".", 4))
    if doc.error:
        raise Failed(wrap(user_error(cx, doc), 4))
    return where(cx.ws, cx.env, doc.path)


def store(cx, name, value):
    """name set to value in your user file (None removes it), or Failed: a file 42 will not
    rewrite, or could not."""
    try:
        userconfig.store(cx.env, name, value, outside=(cx.ws,))
    except userconfig.Bad as e:
        path = userconfig.path(cx.env)
        raise Failed(wrap("%s: %s" % (where(cx.ws, cx.env, path, e.n), e.why) if e.n else e.why, 4))
    except userconfig.Unwritable as e:
        raise Failed(wrap(str(e), 4))
    except OSError as e:
        # e.filename may be the temporary file it was writing, which is gone.
        raise Failed(wrap("could not write %s: %s" % (
            where(cx.ws, cx.env, userconfig.path(cx.env)), e.strerror), 4))
    finally:
        cx.user_file = None


def check_writable(cx):
    """Failed when a write of your user file would be refused: what a dry run checks."""
    try:
        userconfig.writable(cx.env, outside=(cx.ws,))
    except userconfig.Unwritable as e:
        raise Failed(wrap(str(e), 4))


def cmd_list(cx, every, scope=None):
    if scope == "global":
        return list_global(cx, every)
    out = []
    shortened = False
    table = settings(cx)
    for group, title in titles(table):
        lines = []
        for s in table:
            if s.group != group or scope and scope not in s.scopes:
                continue
            if scope:
                found, others = s.scoped(cx, scope), []
            else:
                layers = s.layers(cx)
                found, others = (layers[0], layers[1:]) if layers else (s.default(cx), [])
            # A setting with no default is shown missing: `42 submit` refuses
            # to run without it, and calling it a default sent nobody to init.
            needed = found is None and getattr(s, "required", None)
            if not every and not needed and not any(f.user for f in [found] + others if f):
                continue
            text, short = row(s.name, found)
            shortened = shortened or short
            lines.append(text)
            for f in others:
                text, short = layer_line("not used", f, 6, WIDTH - 6 - len("not used: "))
                shortened = shortened or short
                lines.append(text)
            won = s.resolve(cx) if scope else None
            if won is not None and (found is None or not found.same(won)):
                text, short = layer_line("in use", won, 6, WIDTH - 6 - len("in use: "))
                shortened = shortened or short
                lines.append(text)
            for note in s.notes(cx) + ([needed] if needed else []):
                lines.append(note_line(note, 6))
        if lines:
            out.append("%s:\n%s" % (wrap(title, 0), "\n".join(lines)))
    if not scope:
        out += user_file_notes(cx, table)
    if not every:
        out.append("`42 config list --all` shows every setting, defaults too.")
    if shortened:
        out.append("A value shortened with ... is printed whole by `42 config get NAME`.")
    cx.out.say("\n\n".join(out))
    return 0


def list_global(cx, every):
    """`42 config list --global`: your user file, every name in it, and what reads each."""
    shown = user_path(cx)
    doc = user_doc(cx)
    table = settings(cx)
    lines, shortened = [], False
    for name, (value, n) in doc.entries.items():
        s = known(cx, name)
        text, short = row(name, Found(value, "line %d" % n))
        shortened = shortened or short
        lines.append(text)
        note = None
        if s is None:
            close = difflib.get_close_matches(name, [t.name for t in table], n=1)
            note = "no setting of this 42 has that name: it is kept as it is.%s" % (
                " Did you mean %s?" % close[0] if close else "")
        elif "global" not in s.scopes:
            note = "%s lives in this checkout only, and nothing reads it here: %s." % (s.name, s.local_only)
        else:
            try:
                s.check_value(value)
            except UsageError as e:
                note = "42 refuses it: %s" % " ".join(str(e).split())
            won = s.resolve(cx)
            if won is not None and won.scope != "global":
                text, short = layer_line("in use", won, 6, WIDTH - 6 - len("in use: "))
                shortened = shortened or short
                lines.append(text)
        if note:
            lines.append(note_line(note, 6))
    if every:
        lines += [row(s.name, None)[0] for s in table if "global" in s.scopes and s.name not in doc.entries]
    title = "Your user file, which every checkout of yours reads (%s)" % shown
    if lines:
        out = [wrap(title + ":", 0) + "\n" + "\n".join(lines)]
    else:
        out = [wrap(title + ": nothing set in it yet.", 0)]
    out += [wrap("note: " + n, 0) for n in userconfig.notes(cx.env)]
    if not every:
        out.append("`42 config list --global --all` shows every setting it may hold.")
    if shortened:
        out.append("A value shortened with ... is printed whole by `42 config get --global NAME`.")
    cx.out.say("\n\n".join(out))
    return 0


def cmd_get(cx, name, scope=None):
    s = find(cx, name)
    in_scope(s, scope, "get")
    if scope == "global":
        user_path(cx)
    if scope:
        found, others = s.scoped(cx, scope), []
    else:
        layers = s.layers(cx)
        found, others = (layers[0], layers[1:]) if layers else (s.default(cx), [])
    if found is None:
        if scope == "global":
            cx.out.err(wrap("42: %s is not set in your user file, %s. `42 config set --global %s %s` sets it." % (
                s.name, user_path(cx), s.name, "URL" if isinstance(s, Remote) else "VALUE"), 4))
        else:
            cx.out.err(wrap("42: %s is not set%s. `42 config set %s %s` sets it." % (
                s.name, " in this checkout" if scope else "", s.name, "URL" if isinstance(s, Remote) else "VALUE"), 4))
        won = s.resolve(cx) if scope else None
        if won is not None:
            cx.out.err(layer_line("in use", won, 2)[0])
        return 1
    cx.out.say(found.value)
    cx.out.say("  " + wrap(found.tag(), 2))
    for f in others:
        cx.out.say(layer_line("not used", f, 2)[0])
    won = s.resolve(cx) if scope else None
    if won is not None and not found.same(won):
        cx.out.say(layer_line("in use", won, 2)[0])
    for note in s.notes(cx) + global_notes(cx, s):
        cx.out.say(note_line(note, 2))
    return 0


def cmd_set(cx, name, raw, dry, scope=None):
    s = find(cx, name)
    if s.readonly:
        raise refused("%s is read-only here: %s" % (s.name, s.readonly))
    scope = scope or "local"
    in_scope(s, scope, "set")
    if scope == "global":
        written = user_path(cx)
        value = s.check_value(raw)
        try:
            userconfig.render(value)
        except userconfig.Bad as e:
            raise refused("%s: %s" % (s.name, e.why))
        old = s.scoped(cx, "global")
    else:
        written = s.store
        value = s.check(cx, raw)
        old = s.get(cx)
    change = "%s%s: %s -> %s" % (s.name, " (global)" if scope == "global" else "",
                                 old.value if old else "(not set)", value)
    if dry:
        if scope == "global":
            check_writable(cx)
        cx.out.say(change)
        cx.out.say("  " + wrap("--dry-run: nothing written; without it, %s is written." % written, 2))
        return 0
    if scope == "global":
        store(cx, s.name, value)
    else:
        s.write(cx, value)
    cx.out.say(change)
    cx.out.say("  " + wrap("written to %s" % written, 2))
    said = getattr(s, "after", lambda cx: [])(cx)
    if isinstance(s, BazelSetting):
        said.append("%s belongs to this checkout: every Bazel command run in it reads "
                    "it, a dev container's on the same folder too." % LOCAL_RC)
    won = s.resolve(cx)
    if won is not None and won.scope != scope:
        said.append("note: in use instead: %s  %s, which wins over it." % (won.value, won.tag()))
    for line in said + ["note: " + n for n in s.notes(cx)]:
        cx.out.say(wrap(line.replace("\n", " "), 0))
    return 0


def cmd_unset(cx, name, dry, scope=None):
    if scope == "global":
        return unset_global(cx, name, dry)
    s = find(cx, name)
    if s.readonly:
        raise refused("%s is read-only here: %s" % (s.name, s.readonly))
    in_scope(s, "local", "unset")
    if s.unsettable:
        raise refused("%s cannot be unset: %s" % (s.name, s.unsettable))
    old = s.get(cx)
    if old is None or not old.user:
        said = "%s is not set here: nothing to unset." % s.name
        held = s.scoped(cx, "global") if "global" in s.scopes else None
        if held is not None:
            said += " Its value %s comes from %s: `42 config unset --global %s` removes it there." % (
                held.value, held.source, s.name)
        cx.out.say(wrap(said, 0))
        return 0
    if dry:
        cx.out.say("%s: %s -> unset" % (s.name, old.value))
        cx.out.say("  " + wrap("--dry-run: nothing written; without it, %s is written." % s.store, 2))
        return 0
    s.unset(cx)
    now = s.resolve(cx)
    cx.out.say("%s: %s -> %s" % (s.name, old.value, "%s %s" % (now.value, now.tag()) if now else "(not set)"))
    cx.out.say("  " + wrap("written to %s" % s.store, 2))
    for n in s.notes(cx) + global_notes(cx, s):
        cx.out.say(wrap("note: " + n.replace("\n", " "), 0))
    return 0


def unset_global(cx, name, dry):
    """`42 config unset --global NAME`: any name your user file holds, one this 42 knows or not,
    since removing it breaks no reader of this version."""
    written = user_path(cx)
    doc = user_doc(cx)
    s = known(cx, name)
    key = s.name if s is not None and s.name in doc.entries else name
    if key not in doc.entries:
        if s is None:
            find(cx, name)  # a name nothing knows: its refusal, and Did you mean
        cx.out.say("%s is not set in your user file: nothing to unset." % s.name)
        return 0
    value = doc.entries[key][0]
    if dry:
        check_writable(cx)
        cx.out.say("%s (global): %s -> unset" % (key, value))
        cx.out.say("  " + wrap("--dry-run: nothing written; without it, %s is written." % written, 2))
        return 0
    store(cx, key, None)
    now = s.resolve(cx) if s is not None and "global" in s.scopes else None
    cx.out.say("%s (global): %s -> %s" % (key, value, "%s %s" % (now.value, now.tag()) if now else "(not set)"))
    cx.out.say("  " + wrap("written to %s" % written, 2))
    return 0


def run(cx, words, every, dry, scope=None):
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
    m = re.match(r"(global|local)\.(.+)", args[0]) if args else None
    if m and not (verb == "unset" and scope == "global"):
        raise refused("no setting %r: the scope is a flag, as in `42 config %s --%s %s%s`." % (
            args[0], verb, m.group(1), m.group(2), " VALUE" if verb == "set" else ""))
    try:
        if verb == "list":
            return cmd_list(cx, every, scope)
        if verb == "get":
            return cmd_get(cx, args[0], scope)
        if verb == "set":
            return cmd_set(cx, args[0], args[1], dry, scope)
        return cmd_unset(cx, args[0], dry, scope)
    except Failed as e:
        cx.out.err("42: %s" % e)
        return 1


def help_text(cx):
    """What `42 help config` adds below the usage: every setting, by kind, and the scopes."""
    out = []
    table = settings(cx)
    for group, title in titles(table):
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
                if "local" in s.scopes:
                    text += " Stored in %s" % s.store
                    text += ", or in your user file (--global)." if "global" in s.scopes else "."
                else:
                    text += " Stored in your user file only (--global)."
            out.append("    %s\n        %s" % (name, wrap(text, 8)))
    takes = [s.name for s in table if "global" in s.scopes]
    out.append("\n  " + wrap(
        "Where: `set` and `unset` change this checkout's own file for a setting, or with "
        "--global your user file, %s, which every checkout of yours reads. A checkout's own "
        "value wins over your user file's, and an environment variable every reader honours "
        "wins over both. `list` and `get` show every value that is set, the one in use on the "
        "setting's line; --local or --global shows that scope's alone. %s" % (
            userconfig.WHERE, "Your user file may hold %s." % ", ".join(takes) if takes
            else "No setting may live in your user file yet."), 2))
    out.append("\n  " + wrap(
        "`set` checks the value before it writes, and says what it was; --dry-run checks it "
        "and writes nothing. `unset` removes this checkout's value, and what is in use is "
        "then your user file's or the default (login and email have none); `unset --global` "
        "removes your user file's. Exit 1: not set, or a file that could not be written. It "
        "runs no Bazel command.", 2))
    return "\n".join(out)
