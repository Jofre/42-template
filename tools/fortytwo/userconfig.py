"""Your user file: settings for every checkout of yours on this machine.

`42 config --global` reads and writes it. A checkout's own value wins over it,
and the environment wins over both (config.SCOPES). It lives where the XDG
Base Directory spec (0.8) puts a program's configuration: $XDG_CONFIG_HOME/42/
when that is an absolute path, else $HOME/.config/42/, else nowhere. Both are
read from the environment 42 was given, never from os.environ, so a test's or
a hand run's own HOME is the only one 42 sees.

The folder holds one file per role (FILES), so that the settings can be shown,
pasted or kept in a dotfiles repository without the secrets beside them. State
stays under $XDG_STATE_HOME/42/ (taint.py), never here.

The format is a flat subset of YAML, which 42 reads and writes itself: one
`name: value` per line, and comments and blank lines kept as they are on every
rewrite. Python has no YAML reader of its own, and 42 runs on 3.10 with nothing
installed, so no third-party parser can be assumed. Every file this module
accepts reads the same under YAML 1.1 (PyYAML) and YAML 1.2 (ruamel.yaml):
every value is that string, or a decimal both read as that number.
//tools/tests:userconfig_oracle_test holds it to both. Anything else is refused
with its line and the fix, never guessed at, because a misread setting here
would decide, unseen, what every checkout does.

It imports nothing of 42's own, so any module can import it.
"""

import errno
import fcntl
import json
import os
import re
import tempfile

CONFIG = "config.yaml"
# Every file the folder may hold: a new one is a row here, never a path
# computed somewhere else. Any other file in the folder is left alone, so a
# newer 42 can add one without breaking an older checkout's 42.
FILES = (
    (CONFIG, "settings, nothing secret: what `42 config --global` reads and writes"),
    # Reserved for a later `42 auth login` (V237): created 0600
    # with O_EXCL inside the 0700 folder, written from a prompt or stdin and
    # never from argv, refused when its mode lets anyone else read it, and
    # never printed. Nothing reads or writes it yet.
    ("credentials.yaml", "secrets: reserved, nothing writes it yet"),
)

HEADER = ("# Settings 42 reads in every checkout of yours on this machine. A checkout's\n"
          "# own value wins over these: `42 config list` shows which one is in use.\n")

BOM = b"\xef\xbb\xbf"
NAME = r"[A-Za-z][A-Za-z0-9_./-]*"
# YAML takes a name for a key only when its ':' is at most 1024 characters
# from where the name starts (YAML 1.2, 7.4.2; PyYAML refuses 1025).
MAX_NAME = 1024
# A plain value that YAML 1.1 and 1.2 both read as the same string: it starts
# with a letter or a '/' (so no number, date, time, .inf, ~ or indicator),
# holds no blank, '#' or ',', and does not end in ':'. WORDS are the ones that
# are still something else to some YAML: a bool, or null.
PLAIN = r"[A-Za-z/](?:[A-Za-z0-9_.@:/+=-]*[A-Za-z0-9_.@/+=-])?"
DECIMAL = r"0|[1-9][0-9]*"
DQ = r'"(?:[^"\\]|\\.)*"'
SQ = r"'(?:[^']|'')*'"
WORDS = frozenset("y Y yes Yes YES n N no No NO true True TRUE false False FALSE "
                  "on On ON off Off OFF null Null NULL".split())
ENTRY = re.compile(r"(%s):( +)(%s|%s|%s|%s)( +#.*)?( *)" % (NAME, DQ, SQ, DECIMAL, PLAIN))
COMMENT = re.compile(r" *#.*")
ESCAPE = re.compile(r'\\(?:["\\/bfnrt]|u[0-9A-Fa-f]{4})')
SHORT = {'"': '\\"', "\\": "\\\\", "\b": "\\b", "\f": "\\f", "\n": "\\n", "\r": "\\r", "\t": "\\t"}


class Bad(Exception):
    """A user file 42 will not read, or a value it cannot hold: the line, and why, with the fix.

    `n` is the line, or None for the whole file; `path` is set by whoever read the file.
    """

    def __init__(self, n, why, path=None):
        Exception.__init__(self, ("line %d: %s" % (n, why)) if n else why)
        self.n, self.why, self.path = n, why, path


class Unwritable(Exception):
    """The user file cannot be written here: no folder for it, or a folder 42 must not write."""


# config_dir's rule, as help and docs say it.
WHERE = ("$XDG_CONFIG_HOME/42/config.yaml when that is an absolute path, else "
         "~/.config/42/config.yaml")


def config_dir(env):
    """(the folder, None), or (None, why there is none), from env alone."""
    xdg = env.get("XDG_CONFIG_HOME", "")
    if os.path.isabs(xdg):
        return os.path.join(xdg, "42"), None
    home = env.get("HOME", "")
    if os.path.isabs(home):
        return os.path.join(home, ".config", "42"), None
    if home:
        return None, "HOME=%s is no absolute path, so 42 has no ~/.config/42 here" % home
    return None, "HOME is not set, so 42 has no ~/.config/42 here"


def notes(env):
    """What a person setting XDG_CONFIG_HOME should know: the spec says a relative one is ignored."""
    xdg = env.get("XDG_CONFIG_HOME", "")
    if xdg and not os.path.isabs(xdg):
        return ["XDG_CONFIG_HOME=%s is no absolute path, so 42 ignores it, as the XDG spec says." % xdg]
    return []


def path(env, name=CONFIG):
    """The file's path, or None when there is no folder for it."""
    folder, _ = config_dir(env)
    return os.path.join(folder, name) if folder else None


# ---------------------------------------------------------------------------
# Reading

def allowed(c):
    """Whether YAML takes c raw, as the same character in every version: printable to YAML
    1.2, and no line break to YAML 1.1 (NEL, U+2028, U+2029). A BOM counts only at the
    file's very start. A tab is a blank to neither, so it is allowed in a comment only."""
    o = ord(c)
    return (0x20 <= o <= 0x7E or 0xA0 <= o <= 0xD7FF and o not in (0x2028, 0x2029)
            or 0xE000 <= o <= 0xFFFD and o != 0xFEFF or 0x10000 <= o <= 0x10FFFF)


def split(data):
    """(BOM or b"", [(line, ends in CR)], whether the last line has its newline).

    Only LF ends a line; a CR right before it is kept apart, so a CRLF file is
    rewritten CRLF.
    """
    bom = BOM if data.startswith(BOM) else b""
    try:
        text = data[len(bom):].decode("utf-8")
    except UnicodeDecodeError as e:
        raise Bad(data[:len(bom) + e.start].count(b"\n") + 1, "a byte that is no UTF-8: save the file as UTF-8.")
    raw = text.split("\n")
    ends = raw[-1] == ""
    if ends:
        raw.pop()
    return bom, [(t[:-1], True) if t.endswith("\r") else (t, False) for t in raw], ends


def scalar(n, token):
    """The string a value token stands for."""
    if token[0] == '"':
        inner = token[1:-1]
        bad = [c for c in inner if not allowed(c)]
        if bad:
            raise Bad(n, "U+%04X, raw inside quotes, which YAML does not read the same everywhere: "
                         "write it as \\u%04X." % (ord(bad[0]), ord(bad[0])))
        if "\\" in ESCAPE.sub("", inner.replace("\\\\", "")):
            raise Bad(n, "an escape 42 does not read: inside \"...\" use only "
                         "\\\" \\\\ \\/ \\b \\f \\n \\r \\t or \\uXXXX.")
        for m in re.finditer(r"\\u([0-9A-Fa-f]{4})", inner.replace("\\\\", "")):
            if 0xD800 <= int(m.group(1), 16) <= 0xDFFF:
                raise Bad(n, "\\u%s is half of a character: write the character itself." % m.group(1))
        return json.loads(token)
    if token[0] == "'":
        bad = [c for c in token[1:-1] if not allowed(c)]
        if bad:
            raise Bad(n, "U+%04X, raw inside quotes, which YAML does not read the same everywhere: "
                         "write the value in double quotes, with \\u%04X." % (ord(bad[0]), ord(bad[0])))
        return token[1:-1].replace("''", "'")
    if token in WORDS:
        raise Bad(n, "YAML reads %s as %s, not as text: quote it, \"%s\"." % (
            token, "null" if token.lower() == "null" else "true or false", token))
    return token


def why_not(body):
    """Why a line that is no blank, comment or entry is refused, and how to write it."""
    if body[:1] == " ":
        return "an indented line: this file is flat, one `name: value` per line, at its start."
    m = re.match(r"(%s):(?: +(.*))?$" % NAME, body)
    if not m:
        if re.match(r"%s:[^ ]" % NAME, body):
            return "a blank goes after the ':', as in `name: value`."
        if body.strip() in ("---", "..."):
            return "%s may only start the file, before any setting, once." % body.strip()
        return "not `name: value`. A name is letters, digits and _ . / -, and starts with a letter."
    name, value = m.group(1), (m.group(2) or "").strip(" ")
    if not value or value.startswith("#"):
        return "%s has no value: write `%s: VALUE`, or remove the line." % (name, name)
    if re.match(r"[-+.0-9]", value):
        return ("YAML may read %s as a number, a date or a time, not as text: write it in "
                "double quotes." % value.split(" #")[0])
    if value[0] in "[{&*!|>%@`~?":
        return "%s starts with a YAML symbol: write the value in double quotes." % value.split(" #")[0]
    return ("a value with a blank, a '#', a ',' or a quote in it goes in double quotes, "
            "and a comment after it starts with a blank and '#'.")


def parse(data):
    """{name: (value, line number)} of the file's bytes, or Bad."""
    _, lines, _ = split(data)
    out, begun = {}, False
    for n, (body, _) in enumerate(lines, 1):
        if "\r" in body:
            raise Bad(n, "a carriage return inside the line, which YAML reads as a line break: remove it.")
        bad = [c for c in body if c != "\t" and not allowed(c)]
        if bad:
            raise Bad(n, "U+%04X, a character YAML does not read the same everywhere: remove it, or "
                         "write it inside double quotes as \\u%04X." % (ord(bad[0]), ord(bad[0])))
        m = ENTRY.fullmatch(body)
        comment = COMMENT.fullmatch(body)
        tab = body.find("\t")
        if tab >= 0 and not (comment and tab > body.index("#")
                             or m and m.group(4) and tab > m.start(4)):
            raise Bad(n, "a tab, which YAML takes as no blank: use spaces.")
        if not body.strip(" ") or comment:
            continue
        if body.rstrip(" ") == "---" and not begun and not out:
            begun = True
            continue
        if not m:
            raise Bad(n, why_not(body))
        name = m.group(1)
        if len(name) > MAX_NAME:
            raise Bad(n, "a name of %d characters, which YAML reads as no name: it takes at most %d."
                      % (len(name), MAX_NAME))
        if name in WORDS:
            raise Bad(n, "YAML reads the name %s as true, false or null: no setting has that name." % name)
        if name in out:
            raise Bad(n, "%s is set twice, here and on line %d: remove one." % (name, out[name][1]))
        out[name] = (scalar(n, m.group(3)), n)
    return out


class Doc:
    """The user file as read: entries {name: (value, line)}, or the error that stopped the read."""

    def __init__(self, path, entries=None, error=None, exists=False, why=None):
        self.path, self.entries, self.error, self.exists = path, entries or {}, error, exists
        self.why = why  # why there is no path, when there is none


def load(env):
    """The user file as a Doc: never raises, so a broken file breaks only what needs it."""
    folder, why = config_dir(env)
    if folder is None:
        return Doc(None, why=why)
    p = os.path.join(folder, CONFIG)
    try:
        with open(p, "rb") as f:
            data = f.read()
    except FileNotFoundError:
        return Doc(p)
    except OSError as e:
        return Doc(p, error=Bad(None, "42 cannot read it: %s." % e.strerror, p), exists=True)
    try:
        return Doc(p, parse(data), exists=True)
    except Bad as e:
        e.path = p
        return Doc(p, error=e, exists=True)


# ---------------------------------------------------------------------------
# Writing

def render(value):
    """value as one YAML value that every version reads back as that string."""
    if re.fullmatch(PLAIN, value) and value not in WORDS or re.fullmatch(DECIMAL, value):
        return value
    out = []
    for c in value:
        if c in SHORT:
            out.append(SHORT[c])
        elif 0xD800 <= ord(c) <= 0xDFFF:
            # What os.fsdecode makes of an argv byte that is no UTF-8.
            raise Bad(None, "the value holds a byte that is no UTF-8, which the user file cannot hold.")
        elif not allowed(c):
            out.append("\\u%04x" % ord(c))
        else:
            out.append(c)
    return '"%s"' % "".join(out)


def edit(data, name, value):
    """data with name set to value, or its line removed when value is None. Every other line
    is kept byte for byte, and so is the rest of the changed one: its spacing, its comment
    and its line ending. Bad when data does not parse: 42 never rewrites a file it cannot read."""
    before = parse(data)
    bom, lines, ends = split(data)
    if name in before:
        i = before[name][1] - 1
        body, cr = lines[i]
        if value is None:
            del lines[i]
        else:
            m = ENTRY.fullmatch(body)
            lines[i] = (body[:m.start(3)] + render(value) + body[m.end(3):], cr)
    elif value is not None:
        # The file's own line ending, from its last line.
        lines.append(("%s: %s" % (name, render(value)), lines[-1][1] if lines else False))
        ends = True
    text = "\n".join(body + ("\r" if cr else "") for body, cr in lines) + ("\n" if ends and lines else "")
    new = bom + text.encode("utf-8")
    want = {k: v for k, (v, _) in before.items() if k != name}
    if value is not None:
        want[name] = value
    try:
        after = {k: v for k, (v, _) in parse(new).items()}
    except Bad:
        after = None
    if after != want:
        raise Bad(None, "42 could not write %s so that it reads back as asked, so the file "
                        "was left as it was." % name)
    return new


def owner_check(folder):
    """Unwritable when the folder, or the nearest folder above it that exists, is not ours:
    `sudo 42 config` must not leave a root-owned folder in someone's home."""
    p = folder
    while not os.path.lexists(p):
        p = os.path.dirname(p)
    st = os.stat(p)
    if st.st_uid != os.geteuid():
        raise Unwritable("%s belongs to another user (uid %d), and 42 writes your user file only "
                         "into a folder of yours." % (p, st.st_uid))


def inside(path, outside):
    """The checkout of outside that path is in once every link is followed, or None."""
    real = os.path.realpath(path)
    for ws in outside:
        top = os.path.realpath(ws)
        if real == top or real.startswith(top + os.sep):
            return ws
    return None


def writable(env, outside=()):
    """The folder the user file is written in, or Unwritable: there is none here, it or the
    file it holds is inside one of outside (once its links are followed), or the folder is
    not ours. It writes nothing, so a dry run refuses what the write would."""
    folder, why = config_dir(env)
    if folder is None:
        raise Unwritable(why + ".")
    if inside(folder, outside):
        raise Unwritable("%s is inside this checkout, where it would end up in a commit: set "
                         "XDG_CONFIG_HOME or HOME to a folder outside it." % folder)
    linked(folder, outside)
    owner_check(folder)
    return folder


def linked(folder, outside):
    """Unwritable when the folder's config.yaml is a link to a file inside one of outside."""
    target = os.path.realpath(os.path.join(folder, CONFIG))
    if inside(target, outside):
        raise Unwritable("%s is a link to %s, which is inside this checkout, where it would end up "
                         "in a commit: point it outside, or remove the link." % (os.path.join(folder, CONFIG),
                                                                                target))


def store(env, name, value, outside=()):
    """Set name to value in the user file (None removes it), and return the file's path.

    The new text is written beside the file and moved over it (os.replace), not
    written in place as config.write_file does: every checkout reads this file, a
    half-written one would break all of them at once, and a file shared that way
    is the one most likely to be edited by two commands at a time. The folder is
    created 0700 and a new file 0600; an existing file keeps its mode, and a
    symlink stays a link, its target rewritten. Writes are serialised with flock
    on the folder; where a filesystem has no locks (some NFS homes), the write
    goes ahead unlocked, still never half-done. `outside` are the checkouts the
    folder, or the file a link there points to, must not be in, where the file
    would end up in a commit (writable).
    """
    folder = writable(env, outside)
    os.makedirs(folder, 0o700, exist_ok=True)
    lock = os.open(folder, os.O_RDONLY)
    try:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX)
        except OSError as e:
            if e.errno not in (errno.ENOLCK, errno.EOPNOTSUPP, errno.EINVAL):
                raise
        linked(folder, outside)  # again, under the lock: the link may have moved
        target = os.path.realpath(os.path.join(folder, CONFIG))
        try:
            with open(target, "rb") as f:
                data = f.read()
            mode = os.stat(target).st_mode & 0o7777
        except FileNotFoundError:
            data, mode = HEADER.encode("utf-8"), 0o600
        new = edit(data, name, value)
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(target), prefix=".%s." % CONFIG)
        try:
            with os.fdopen(fd, "wb") as f:
                os.fchmod(f.fileno(), mode)
                f.write(new)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp, target)
        except BaseException:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise
        return os.path.join(folder, CONFIG)
    finally:
        os.close(lock)
