"""Where a student is, in this repo's own terms: a project, an exercise or a unit, a member, a layer.

Nothing here is a second copy of a fact the harness already holds. The projects
are the folders whose BUILD.bazel opens a subject() contract and calls
c_levels(), at any depth under their course (cursus/Milestone_0/Libft). A
project's exercises, or the named units of a contract of units (a library, a
project), a library's functions (members, each a suite of its own) and each
one's turn-in folder are the rows tools/units.awk prints for that contract
(Project.units()); //tools/tests:units_parity holds units.awk to each
project's :units, the macros' own reading. The layers are _LAYER_LEVEL's in
tools/defs_levels.bzl; the level filter is tools/submit.sh's gate_tags(), so a green
`42 test` is a gate `42 submit` will pass.
"""

import collections
import difflib
import os
import re
import string
import subprocess
import textwrap

import userconfig

LEVELS = ("basic", "strict", "robust", "complete", "all")

# A word a student types for a layer that is not its tag. Only aliases that
# cannot be anything else: a project, an exercise or another layer.
LAYER_ALIASES = {"norminette": "norm"}


class UsageError(Exception):
    """A request 42 cannot turn into a run. Exit 2, as Bazel's own usage errors."""


class UnknownWord(UsageError):
    """A word resolve() reads as nothing: no project, exercise, layer or label. A
    command that takes fewer kinds of word says so in an error of its own."""

    def __init__(self, message, word):
        UsageError.__init__(self, message)
        self.word = word


# One row of tools/units.awk, its columns in its order (its header says what each holds).
Unit = collections.namedtuple("Unit", "name kind req folder judge lib")

# The KINDs a row may hold: exercise in a contract of exercises; library,
# project and part in a contract of units (part reserved so that a row of
# one is read), and function for each of a library's functions. Any other
# word is refused, never taken as no unit.
UNIT_KINDS = ("exercise", "function", "library", "project", "part")


class ContractError(RuntimeError):
    """A contract 42 cannot read: tools/units.awk refused a line of it, could
    not run, or printed a row that is no unit. main() says it and exits 2.
    42 has no reader of its own to fall back on, and reading the contract as
    no exercise would make every word of that project an unknown one.
    Deliberately no UsageError: cmd_submit catches UsageError to try a word
    as a URL, which would swallow this one."""


def read_units(ws, rel, environ=None):
    """The rows of `awk -f tools/units.awk REL/BUILD.bazel`, run in checkout ws.

    Exit 0 is its rows. Exit 1 with nothing said is a file with no subject()
    call, so no units, as the old reader found none. Anything else, or any
    word on stderr, is a ContractError carrying what it said ("units.awk:
    FILE:LINE: ..."); an awk that exits 1 on its own error says so on stderr.
    The path is relative to the checkout, so the message names a file the
    student can open. It runs in ENVIRON (os.environ when None), the
    environment 42 was given, as read_identity does (V307), under LC_ALL=C
    as every caller of units.awk runs it.
    """
    build = os.path.join(rel, "BUILD.bazel")
    try:
        r = subprocess.run(["awk", "-f", os.path.join(ws, "tools", "units.awk"), build], cwd=ws,
                           env=dict(os.environ if environ is None else environ, LC_ALL="C"),
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           encoding="utf-8", errors="replace", check=False)
    except OSError as e:
        raise ContractError("cannot run awk, which reads %s's contract: %s." % (build, e.strerror or e))
    said = r.stderr.strip()
    if r.returncode == 1 and not said:
        return []
    if r.returncode != 0 or said:
        raise ContractError(said or "tools/units.awk exited %d reading %s, and said nothing." % (r.returncode, build))
    rows = r.stdout.split("\n")
    if rows and rows[-1] == "":
        rows.pop()
    units = []
    for n, line in enumerate(rows, 1):
        cols = line.split("\t")
        if len(cols) != len(Unit._fields) or cols[1] not in UNIT_KINDS:
            raise ContractError("tools/units.awk's row %d for %s is %r, not NAME KIND REQ FOLDER JUDGE LIB." % (n, build, line))
        units.append(Unit(*cols))
    return units


class Project:
    """One project folder: a BUILD.bazel that opens subject() and calls c_levels()."""

    def __init__(self, ws, rel, environ=None):
        self.ws = ws
        self.rel = rel  # c-piscine/c-piscine-c-05
        self.name = os.path.basename(rel)  # c-piscine-c-05
        self.label = "//" + rel
        self.short = short_name(self.label)  # c-05
        self.environ = environ  # the environment 42 was given; None is os.environ
        self._units = None

    def __repr__(self):
        return "Project(%r)" % self.rel

    @property
    def path(self):
        return os.path.join(self.ws, self.rel)

    def units(self):
        """The contract's units, as tools/units.awk prints them: one Unit per row, in its order.
        Read once per Project; a contract edited during `42 watch` is read by the next 42."""
        if self._units is None:
            self._units = read_units(self.ws, self.rel, self.environ)
        return self._units

    def exercises(self):
        """exNN for each exercise of the contract, in the order the contract lists them."""
        return [u.name for u in self.units() if u.kind == "exercise"]

    def wholes(self):
        """Every unit that is no function, in the contract's order: exNN for an exercise, the
        name of a unit of a contract of units (a library, a project). What a Scope's ex holds."""
        return [u.name for u in self.units() if u.kind != "function"]

    def named(self):
        """Whether the contract is one of units (units = {...}), whose units have names of their
        own: one row holds a library, a project or a part. A contract of exercises holds none."""
        return any(u.kind in ("library", "project", "part") for u in self.units())

    def kind(self, name):
        """The KIND of the row of that name (exercise, library, project, part or function), or
        None for a name that is no unit of the contract."""
        return next((u.kind for u in self.units() if u.name == name), None)

    def members(self, ex):
        """The functions a library of a contract of units names, in its order; [] for any
        other unit. Each is a unit and a suite of its own, //<project>:<function>."""
        return [u.name for u in self.units() if u.kind == "function" and u.lib == ex]

    def member_exercises(self, name):
        """The library that has a function of that name, as a list: [] for a name that is
        no function of the contract."""
        return [ex for ex in self.wholes() if name in self.members(ex)]

    def has_unit_word(self, word):
        """Whether 42 takes word alone as one of its units: in a contract of units, any
        unit's name, a library's functions included. An exercise's word is exNN, read by
        its shape."""
        return self.named() and self.kind(word) is not None

    def turnin(self, ex):
        """deliverable/exNN for an exercise, or deliverable for every unit of a contract of units
        (a subject with no turn-in folder): the row's FOLDER, which is defs.bzl's turnin_dir(). ""
        for a name that is no exercise or unit of the contract (a function has its library's)."""
        return next((u.folder for u in self.units() if u.kind != "function" and u.name == ex), "")

    def has_generators(self):
        return os.path.isfile(os.path.join(self.path, "BUILD.bazel")) and _calls(
            os.path.join(self.path, "BUILD.bazel"), r'^\s*name = "generate",')


# A-Z to a-z and nothing else, as tools/submit.sh's tr and first_red.sh's
# awk lower a name: str.lower() would lower letters they leave alone.
_ASCII_LOWER = str.maketrans(string.ascii_uppercase, string.ascii_lowercase)


def short_name(label):
    """A label as first_red.sh's shortname() writes it: //c-piscine/c-piscine-c-05 -> c-05,
    //cursus/Milestone_0/Libft -> libft.

    A Piscine project is its folder's name without c-piscine-; a Common Core
    project (under cursus/, at any depth) is its own folder's name with A-Z
    lowercased; any other path stays whole (tools/tests). The same rule
    as first_red.sh's shortname() and tools/submit.sh's short_name(), so a
    command first_red suggests and a .submit-remotes key name the project
    the way 42 reads it: //tools/tests:fortytwo_test holds the three to
    agree, and //tools:conventions refuses two modules with one short name.
    """
    l = label[2:] if label.startswith("//") else label
    parts = l.split("/")
    if len(parts) > 1 and parts[-1].startswith("c-piscine-"):
        l = parts[-1]
    elif len(parts) > 1 and parts[0] == "cursus":
        l = parts[-1].translate(_ASCII_LOWER)
    if l.startswith("c-piscine-"):
        l = l[len("c-piscine-"):]
    return l


def _unit_noun(projects, word):
    """How an error names what word is in those projects: "a function" where each has it as
    one (a library's member), "a part" where one has it as a unit of its own."""
    return "a function" if all(p.member_exercises(word) for p in projects) else "a part"


def _calls(path, pattern):
    rx = re.compile(pattern)
    with open(path, encoding="utf-8") as f:
        return any(rx.search(line) for line in f)


# The top-level folders that are no course: the harness's own (tools/ holds
# macro fixtures that open a contract and call c_levels() just as a project
# does), the oracle and the docs.
NOT_COURSES = ("tools", "oracle", "docs")
# The folders of a project that hold no other project: what is turned in, its
# generators and its tests.
NOT_PROJECTS = ("deliverable", "generators", "tests")


def is_project(path):
    """A folder whose BUILD.bazel opens a subject() contract and calls c_levels()."""
    build = os.path.join(path, "BUILD.bazel")
    if not os.path.isfile(build):
        return False
    with open(build, encoding="utf-8") as f:
        text = f.read()
    return bool(re.search(r"^subject\(", text, re.M)) and "c_levels(" in text


def find_projects(ws, environ=None):
    """Every project of the checkout, in path order.

    Below each course folder at any depth (c-piscine/c-piscine-c-05,
    cursus/Milestone_0/Libft), by a walk that never enters a dot folder, a
    bazel-* link or a NOT_PROJECTS folder, and stops at the first project on
    each path: a folder inside a project is that project's.
    """
    found = []
    seen = set()

    def walk(rel):
        here = os.path.join(ws, rel)
        real = os.path.realpath(here)
        if real in seen:
            return
        seen.add(real)
        for name in sorted(os.listdir(here)):
            sub = rel + "/" + name
            if name.startswith((".", "bazel-")) or name in NOT_PROJECTS or not os.path.isdir(os.path.join(ws, sub)):
                continue
            if is_project(os.path.join(ws, sub)):
                found.append(Project(ws, sub, environ))
            else:
                walk(sub)

    for course in sorted(os.listdir(ws)):
        if course.startswith((".", "bazel-")) or course in NOT_COURSES or not os.path.isdir(os.path.join(ws, course)):
            continue
        walk(course)
    return found


def layer_levels(ws):
    """_LAYER_LEVEL from tools/defs_levels.bzl: {layer: level number}, in its order.

    Read, never copied: a layer added there is a word 42 knows the same day.
    An empty result is an error, because a reading that silently finds nothing
    would turn every layer word into "did you mean".
    """
    path = os.path.join(ws, "tools", "defs_levels.bzl")
    out = {}
    inside = False
    with open(path, encoding="utf-8") as f:
        for line in f:
            if not inside:
                inside = line.startswith("_LAYER_LEVEL = {")
                continue
            if line.startswith("}"):
                break
            m = re.match(r'\s*"([a-z0-9_]+)"\s*:\s*(\d+)\s*,', line)
            if m:
                out[m.group(1)] = int(m.group(2))
    if not out:
        raise RuntimeError("42: found no layer in _LAYER_LEVEL (%s); has its format changed?" % path)
    return out


def gate_tags(level):
    """tools/submit.sh's gate_tags(), for the same level: the same tests."""
    if level in ("basic", "strict", "robust"):
        return "lvl_%s,-manual" % level
    if level in ("complete", "all"):
        return "-manual"
    raise UsageError("not a level: %r" % level)


WIDTH = 80


def wrap(text, indent, width=WIDTH):
    """text on lines of at most `width`, every line after the first indented; a `command`
    is never split across two."""
    kept = re.sub(r"`[^`]*`", lambda m: m.group(0).replace(" ", "\0"), text)
    return textwrap.fill(kept, width - indent, break_on_hyphens=False,
                         break_long_words=False).replace("\0", " ").replace("\n", "\n" + " " * indent)


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


# Where tools/submit.sh finds a level itself: one from anywhere else reaches it
# only as --gate-level.
SCRIPT_READS = ("SUBMIT_GATE", ".submit-level", "default")


def level_source(flag, environ, ws, takes_flag=True):
    """(level, where it came from), unchecked: --level, then SUBMIT_GATE, then .submit-level,
    then your user file, then basic. takes_flag: whether the command takes --level, which a
    user file 42 cannot read is then told to give.

    tools/submit.sh's order, read the way it reads them (the file with every
    blank removed), so `42 test` runs what the gate will. The script does not
    read your user file: `42 submit` passes a level from it on (gate_level_args),
    and the script run without one stops when the file has a level line. A file
    42 cannot read is a UsageError here, and only here, where it would decide.
    """
    if flag:
        return flag, "--level"
    if environ.get("SUBMIT_GATE"):
        return environ["SUBMIT_GATE"], "SUBMIT_GATE"
    path = os.path.join(ws, ".submit-level")
    if os.path.isfile(path):
        with open(path, encoding="utf-8", errors="replace") as f:
            value = re.sub(r"[ \t\n\r]", "", f.read())
        if value:
            return value, ".submit-level"
    doc = userconfig.load(environ)
    if doc.error:
        raise UsageError(wrap("%s: %s Your level is read from it, since nothing nearer sets one: fix "
                              "that, %s`42 config set level LEVEL` sets this checkout's." % (
                                  where(ws, environ, doc.path, doc.error.n), doc.error.why,
                                  "give --level, or " if takes_flag else "or "), 4))
    if "level" in doc.entries:
        value, n = doc.entries["level"]
        return value, where(ws, environ, doc.path, n)
    return "basic", "default"


def checked_level(value, source):
    """(value, source), or a UsageError naming the source when value is no level."""
    if value not in LEVELS:
        raise UsageError("%s says %r, which is not a level. The levels are %s." % (
            source, value, ", ".join(LEVELS)))
    return value, source


def resolve_level(flag, environ, ws, takes_flag=True):
    """(level, where it came from), as level_source() finds it, or a UsageError when it is no
    level."""
    return checked_level(*level_source(flag, environ, ws, takes_flag))


def gate_level_args(flag, environ, ws):
    """What `42 submit` adds to the script's words: --gate-level LEVEL when the level comes
    from somewhere the script does not read, else nothing: where it reads, the script says
    itself what it found."""
    value, source = level_source(flag, environ, ws)
    if source in SCRIPT_READS:
        return []
    return ["--gate-level", checked_level(value, source)[0]]


def read_identity(ws, environ=None):
    """{"username": ..., "email": ...}: the 42header.* keys of .vscode/settings.json that are set.

    Read by `sh tools/identity.sh get`, the one reader tools/submit.sh and
    tools/gen_header.sh use too, so 42 shows the identity they use: a reader
    of its own here agreed with theirs on a key VS Code does not read (V307).
    It reads bytes; one that is no UTF-8 is U+FFFD here, which only 42's own
    output shows, and a NUL is dropped, as the shell's $(...) drops it. No
    reader (an identity.sh that is missing, a file it cannot read) is no key.
    It runs in ENVIRON (os.environ when None), the environment 42 was given.
    """
    keys = {}
    for k, kind in (("username", "login"), ("email", "email")):
        try:
            r = subprocess.run(["sh", os.path.join(ws, "tools", "identity.sh"), "get", kind], cwd=ws,
                               env=dict(os.environ if environ is None else environ,
                                        BUILD_WORKSPACE_DIRECTORY=ws),
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False)
        except OSError:
            return keys
        v = r.stdout.decode("utf-8", "replace").replace("\0", "")
        if r.returncode == 0 and v:
            keys[k] = v
    return keys


class Scope:
    """What a command applies to: a project, maybe one exercise or unit, maybe
    one layer; or a label. In a contract of units, ex holds a unit's name (a
    library, a project) and member one of a library's functions, each a unit
    of its own."""

    def __init__(self, project=None, ex=None, layer=None, label=None, member=None):
        self.project = project
        self.ex = ex
        self.layer = layer
        self.label = label
        self.member = member

    def __repr__(self):
        return "Scope(%r, %r, %r, %r, member=%r)" % (self.project, self.ex, self.layer, self.label, self.member)

    def unit_words(self):
        """The words of its exercise or unit: exNN; a unit's name; a function of a
        library by its own name alone, which is a unit of its own and says which
        library."""
        if self.member:
            return [self.member]
        return [self.ex] if self.ex else []

    def describe(self):
        if self.label:
            return self.label
        words = ([self.project.short] if self.project else []) + self.unit_words()
        if self.layer:
            words.append("layer " + self.layer)
        return " ".join(words)

    def words(self):
        """The 42 words that name this scope again."""
        if self.label:
            return [self.label]
        out = ([self.project.short] if self.project else []) + self.unit_words()
        if self.layer:
            out.append(self.layer)
        return out


def is_exercise_name(word):
    """exNN, the name of an exercise of a contract of exercises. No unit of a contract of
    units is named so: subject() refuses one."""
    return re.match(r"ex\d+$", word) is not None


class Workspace:
    def __init__(self, ws, cwd, environ=None):
        self.ws = os.path.realpath(ws)
        self.cwd = os.path.realpath(cwd)
        self.environ = environ  # the environment 42 was given; None is os.environ
        self._projects = None
        self._layers = None

    def projects(self):
        if self._projects is None:
            self._projects = find_projects(self.ws, self.environ)
        return self._projects

    def layers(self):
        if self._layers is None:
            self._layers = layer_levels(self.ws)
        return self._layers

    def project_named(self, word):
        w = word.rstrip("/")
        for p in self.projects():
            if w in (p.short, p.name, p.rel, p.label):
                return p
        return None

    def rel(self, path):
        """path relative to the checkout, or None when it is outside it.

        Its folder is resolved, so a checkout reached through a symlink is
        still the checkout; a file's own link is not followed, since a link
        to a file elsewhere (Bazel's runfiles are all such links) is still
        the file where it is named.
        """
        p = os.path.abspath(path)
        if not os.path.isdir(p):
            head, tail = os.path.split(p)
            p = os.path.join(os.path.realpath(head), tail)
        else:
            p = os.path.realpath(p)
        r = os.path.relpath(p, self.ws)
        return None if r == ".." or r.startswith("../") else r

    def scope_of_path(self, path):
        """The scope a folder or file stands for: its project, and its exercise if it
        is in one. In a contract of units, a unit's folder of tests (tests/<unit>/)
        is that unit, a function's (tests/<function>/) that function of its
        library, and deliverable/, which every unit turns in at, the whole
        project."""
        rel = self.rel(path)
        if rel is None or rel == ".":
            return Scope()
        project = None
        for p in self.projects():
            if rel == p.rel or rel.startswith(p.rel + "/"):
                project = p
                break
        if project is None:
            return Scope()
        inner = rel[len(project.rel) + 1:] if rel != project.rel else ""
        parts = inner.split("/") if inner else []
        ex = member = None
        if len(parts) >= 2 and parts[0] == "tests" and is_exercise_name(parts[1]):
            ex = parts[1]
        elif len(parts) >= 2 and parts[0] == "tests" and project.named():
            if project.kind(parts[1]) == "function":
                ex, member = project.member_exercises(parts[1])[0], parts[1]
            elif project.kind(parts[1]) is not None:
                ex = parts[1]
        elif len(parts) >= 2 and parts[0] == "generators":
            m = re.match(r"(ex\d+)\.sh$", parts[1])
            ex = m.group(1) if m else None
        elif parts and parts[0] == "deliverable" and not project.named():
            # The contract's turn-in folders, the longest that holds the path:
            # never a guess from the folder names on disk (first_red.sh says why).
            best = ""
            for e in project.exercises():
                t = project.turnin(e)
                if t and (inner == t or inner.startswith(t + "/")) and len(t) > len(best):
                    best, ex = t, e
        if ex is not None and ex not in project.wholes():
            ex = member = None
        return Scope(project=project, ex=ex, member=member)

    def resolve(self, words):
        """The scope a command's words and the current folder name together.

        A word that is no label, exercise, layer or project is a unit's: in a
        contract of units, the name of any of its units, a library's functions
        (members) included; one of the project in scope, once every other
        word has named that project; with none in scope, of the one project
        that has it. A word that is no unit there either is an unknown word,
        said as one; and one that is no project's unit is said at once, before
        any later word's error.

        In a contract of units, a project word is the whole project wherever
        42 runs, and the project's name said again after it is its unit of
        that name (42 test libft libft); an exNN word there is said to be none
        of its parts.
        """
        base = self.scope_of_path(self.cwd)
        project, ex, layer, label = base.project, base.ex, None, None
        member = base.member
        path_member = None  # the function a path word's folder is
        rest = []  # the words that are nothing else: units, or unknown
        named_project = named_ex = False
        layers = self.layers()
        for w in words:
            if w.startswith("//"):
                if len(words) > 1:
                    raise UsageError("a label (%s) is run as it is: give it alone." % w)
                return Scope(label=w)
            if is_exercise_name(w):
                if named_ex:
                    raise UsageError("one exercise at a time: %s and %s." % (ex, w))
                ex, named_ex = w, True
                continue
            lw = LAYER_ALIASES.get(w, w)
            if lw in layers:
                if layer is not None:
                    raise UsageError("one layer at a time: %s and %s." % (layer, lw))
                layer = lw
                continue
            # After the project is named, a name of its units is that unit,
            # even one that is also a project's name: its own (libft libft).
            if named_project and project.named() and project.kind(w) not in (None, "exercise"):
                rest.append(w)
                continue
            p = self.project_named(w)
            if p is None and (os.sep in w or w in (".", "..")):
                for cand in (os.path.join(self.cwd, w), os.path.join(self.ws, w)):
                    if os.path.exists(cand):
                        s = self.scope_of_path(cand)
                        if s.project is None:
                            raise UsageError("%s is not inside a project." % w)
                        p = s.project
                        if s.ex and not named_ex:
                            ex, named_ex = s.ex, True
                            # A function's folder of tests is that function,
                            # as it is when 42 runs in it.
                            if s.member and path_member is None:
                                path_member = s.member
                        break
            if p is not None:
                if named_project and p is not project:
                    raise UsageError("one project at a time: %s and %s." % (project.short, p.short))
                # In a contract of units the project named is all of it,
                # whatever unit the folder 42 runs in is.
                if p is not project or p.named():
                    member = None
                    if not named_ex:
                        ex = None
                project, named_project = p, True
                continue
            # A word no project has as a unit can never become one,
            # whatever a later word names: it is unknown now, before any
            # later word's error, as it always was.
            if not any(q.has_unit_word(w) for q in self.projects()):
                raise UnknownWord(self._unknown(w, project), w)
            rest.append(w)
        if named_ex:
            member = path_member  # an exercise named is the whole exercise
        if rest:
            # Each word is read before two are refused as two functions: an
            # unknown word is said as one, with what it may have meant.
            found = [self._member(w, project, ex if named_ex else None) for w in rest]
            # An exNN the project lacks comes back for each word as that
            # exNN, no unit of it, and the end below says so, as it does
            # for one word.
            lacks = [f for f in found if f[1] not in f[0].wholes()]
            if lacks:
                project, ex = lacks[0][:2]
            else:
                fns = [f for f in found if f[2] is not None]
                whole = [f for f in found if f[2] is None]
                if len(fns) > 1:
                    raise UsageError("one function at a time: %s and %s." % (fns[0][2], fns[1][2]))
                if len(whole) > 1:
                    raise UsageError("one part at a time: %s and %s." % (whole[0][1], whole[1][1]))
                if fns and whole:
                    (wp, wu, _), (fp, fu, fn) = whole[0], fns[0]
                    if wp is not fp:
                        raise UsageError("one project at a time: %s and %s." % (wp.short, fp.short))
                    if wu != fu:
                        raise UsageError("%s %s has no function %s: it is one of %s." % (
                            wp.short, wu, fn, " ".join(wp.member_exercises(fn))))
                if fns:
                    project, ex, member = fns[0]
                else:
                    project, ex = whole[0][:2]
                    member = path_member  # a unit named is the whole unit
        if ex is not None:
            if project is None:
                raise UsageError("%s of which project? Name one (42 test c-05 %s), or run it from the project's folder." % (ex, ex))
            if ex not in project.wholes():
                if project.named():
                    raise UsageError("%s is not a part of %s; `42 units %s` lists them." % (
                        ex, project.short, project.short))
                raise UsageError("%s has no %s. Its exercises: %s." % (
                    project.short, ex, " ".join(project.exercises())))
        return Scope(project=project, ex=ex, layer=layer, member=member)

    def _member(self, word, project, ex):
        """(project, library, function) for a word that names a library's function,
        and (project, unit, None) for one that names any other unit of a contract
        of units: the project in scope's, else the one project that has it. ex,
        when a word named it, must hold it."""
        if project is not None:
            if not project.has_unit_word(word):
                elsewhere = [p for p in self.projects() if p is not project and p.has_unit_word(word)]
                if elsewhere:
                    raise UnknownWord("%r is %s of %s, not of %s." % (
                        word, _unit_noun(elsewhere, word), " and ".join(p.short for p in elsewhere),
                        project.short), word)
                raise UnknownWord(self._unknown(word, project), word)
        else:
            hits = [p for p in self.projects() if p.has_unit_word(word)]
            if not hits:
                raise UnknownWord(self._unknown(word), word)
            if len(hits) > 1:
                raise UsageError("%s of which project? It is %s of %s: name one with it (%s %s)." % (
                    word, _unit_noun(hits, word), " and ".join(p.short for p in hits), hits[0].name, word))
            project = hits[0]
        exs = project.member_exercises(word)
        if not exs:  # a unit of its own, no library's function
            if ex is not None and ex != word:
                if ex not in project.wholes():
                    return project, ex, None  # resolve() says the project has no such part
                raise UsageError("one part at a time: %s and %s." % (ex, word))
            return project, word, None
        if ex is not None and ex not in exs:
            if ex not in project.wholes():
                return project, ex, None  # resolve() says the project has no such exercise
            raise UsageError("%s %s has no function %s: it is one of %s." % (
                project.short, ex, word, " ".join(exs)))
        return project, ex or exs[0], word

    def _example_member(self, project=None):
        """A function to show as an example: the project in scope's first, else
        the first of any project; None when no project has one."""
        for p in ([project] if project else []) + self.projects():
            for ex in p.wholes():
                if p.members(ex):
                    return p.members(ex)[0]
        return None

    def _unknown(self, word, project=None):
        names = [p.short for p in self.projects()] + list(self.layers()) + list(LAYER_ALIASES)
        for p in ([project] if project else self.projects()):
            names += [u.name for u in p.units() if u.kind != "exercise"]
        close = difflib.get_close_matches(word, names, n=3, cutoff=0.6)
        hint = (" Did you mean %s?" % " or ".join(close)) if close else ""
        if project is not None and project.named():
            # Its own function, else its own first part: never another
            # project's function, which is no part of it.
            own = [m for u in project.wholes() for m in project.members(u)]
            kinds = "a part of %s (%s) or a layer" % (project.short, (own or project.wholes())[0])
        else:
            example = self._example_member(project)
            kinds = ("an exercise (ex03), a function (%s) or a layer" % example) if example \
                else "an exercise (ex03) or a layer"
        return ("%r is not a project, %s.%s "
                "`42 help test` lists what a word can be." % (word, kinds, hint))

    def close_projects(self, word):
        """The projects whose short names are close to word, closest first."""
        return difflib.get_close_matches(word, [p.short for p in self.projects()], n=3, cutoff=0.6)

    def project_list(self):
        """The projects, as the help and the root's error list them."""
        return " ".join(p.short for p in self.projects())

    def selection(self, scope, level):
        """(patterns, tag filter or None) for `bazel test`: the submit gate's selection.

        A project runs //<project>/..., an exercise its :exNN suite and a
        member its own (:ft_strlen), each under gate_tags(level). A layer word runs that layer, whatever its
        level: asking for one by name is asking for it to run. A label runs
        with no filter, because a filter also drops a target named on the
        command line.
        """
        if scope.label:
            return [scope.label], None
        if scope.project is None:
            raise UsageError("which project? Run 42 from a project's folder, or name one: %s" % self.project_list())
        if scope.member:
            target = scope.project.label + ":" + scope.member
        else:
            target = scope.project.label + (":" + scope.ex if scope.ex else "/...")
        if scope.layer:
            return [target], scope.layer + ",-manual"
        return [target], gate_tags(level)
