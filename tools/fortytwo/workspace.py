"""Where a student is, in this repo's own terms: a project, an exercise, a member, a layer.

Nothing here is a second copy of a fact the harness already holds. The projects
are the folders whose BUILD.bazel opens a subject() contract and calls
c_levels(), at any depth under their course (cursus/Milestone_0/Libft); an
exercise is an entry of that contract, and a member one key of its
`functions = {...}` (a library's function, whose tests are its own suite);
its turn-in folder is the
contract's, read by tools/first_red.sh --turnin (the one reading
//tools/tests:macro_fixtures_test holds to each project's :turnin_dirs); the
layers are _LAYER_LEVEL's in tools/defs.bzl; the level filter is
tools/submit.sh's gate_tags(), so a green `42 test` is a gate `42 submit` will
pass.
"""

import difflib
import os
import re
import subprocess

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


class Project:
    """One project folder: a BUILD.bazel that opens subject() and calls c_levels()."""

    def __init__(self, ws, rel):
        self.ws = ws
        self.rel = rel  # c-piscine/c-piscine-c-05
        self.name = os.path.basename(rel)  # c-piscine-c-05
        self.label = "//" + rel
        self.short = short_name(self.label)  # c-05
        self._exercises = None
        self._functions = None
        self._turnin = {}

    def __repr__(self):
        return "Project(%r)" % self.rel

    @property
    def path(self):
        return os.path.join(self.ws, self.rel)

    def _contract(self):
        with open(os.path.join(self.path, "BUILD.bazel"), encoding="utf-8") as f:
            return f.read()

    def exercises(self):
        """The contract's entries, as exNN, in the order the contract lists them."""
        if self._exercises is None:
            self._exercises = contract_exercises(self._contract())
        return self._exercises

    def members(self, ex):
        """The functions exNN's contract entry names, in its order: [] for an exercise
        with no `functions`. Each is a suite of its own, //<project>:<function>."""
        if self._functions is None:
            self._functions = contract_functions(self._contract())
        return self._functions.get(ex, [])

    def member_exercises(self, name):
        """The exercises that have a member of that name."""
        return [ex for ex in self.exercises() if name in self.members(ex)]

    def turnin(self, ex):
        """deliverable/exNN, or deliverable for a subject with no turn-in folder."""
        if ex not in self._turnin:
            r = subprocess.run(
                ["sh", os.path.join(self.ws, "tools", "first_red.sh"), "--turnin", self.path, ex],
                cwd=self.ws, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                universal_newlines=True, check=False)
            self._turnin[ex] = r.stdout.strip() if r.returncode == 0 else ""
        return self._turnin[ex]

    def has_generators(self):
        return os.path.isfile(os.path.join(self.path, "BUILD.bazel")) and _calls(
            os.path.join(self.path, "BUILD.bazel"), r'^\s*name = "generate",')


def short_name(label):
    """A label as first_red.sh's shortname() writes it: //c-piscine/c-piscine-c-05 -> c-05.

    The same rule, so a command first_red suggests names the project the way
    42 reads it. //tools/tests:fortytwo_test holds the two to agree on every
    project.
    """
    l = label[2:] if label.startswith("//") else label
    parts = l.split("/")
    if len(parts) > 1 and parts[-1].startswith("c-piscine-"):
        l = parts[-1]
    if l.startswith("c-piscine-"):
        l = l[len("c-piscine-"):]
    return l


def _calls(path, pattern):
    rx = re.compile(pattern)
    with open(path, encoding="utf-8") as f:
        return any(rx.search(line) for line in f)


def _code(line):
    """A line of a BUILD file with its comment dropped: from the first '#' that is
    in no string. conventions.sh's contract_fns and first_red.sh's
    contract_read read a line the same way (a '#' in `dir = "a#b"` is no
    comment), and //tools/tests:fortytwo_test holds the three to agree."""
    quoted = False
    i = 0
    while i < len(line):
        c = line[i]
        if quoted and c == "\\":
            i += 2
            continue
        if c == '"':
            quoted = not quoted
        elif c == "#" and not quoted:
            return line[:i]
        i += 1
    return line


def _close(code, start):
    """The index of the first '}' from start that is in no string, or len(code)."""
    quoted = False
    i = start
    while i < len(code):
        c = code[i]
        if quoted and c == "\\":
            i += 2
            continue
        if c == '"':
            quoted = not quoted
        elif c == "}" and not quoted:
            return i
        i += 1
    return len(code)


def contract_exercises(text):
    """exNN for every `"NN": exercise(` entry of the subject() call, comments dropped."""
    out = []
    inside = False
    for line in text.splitlines():
        if not inside:
            inside = line.startswith("subject(")
            continue
        if line.startswith(")"):
            break
        code = _code(line)
        for nn in re.findall(r'"(\d+)"\s*:\s*exercise\(', code):
            ex = "ex" + nn
            if ex not in out:
                out.append(ex)
    return out


def contract_functions(text):
    """{exNN: [function, ...]} for every exercise whose entry of the subject() call
    has a `functions = {...}`: its keys, in order. Comments are dropped, and a
    value's strings (the external functions a member may call) are no key."""
    lines = []
    inside = False
    for line in text.splitlines():
        if not inside:
            inside = line.startswith("subject(")
            continue
        if line.startswith(")"):
            break
        lines.append(_code(line))
    code = "\n".join(lines)
    out = {}
    ex = None
    pos = 0
    rx = re.compile(r'"(\d+)"\s*:\s*exercise\(|\bfunctions\s*=\s*\{')
    while True:
        m = rx.search(code, pos)
        if not m:
            break
        if m.group(1) is not None:
            ex = "ex" + m.group(1)
            pos = m.end()
            continue
        end = _close(code, m.end())
        if ex is not None:
            names = out.setdefault(ex, [])
            for name in re.findall(r'"([^"]+)"\s*:', code[m.end():end]):
                if name not in names:
                    names.append(name)
        pos = end
    return out


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


def find_projects(ws):
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
                found.append(Project(ws, sub))
            else:
                walk(sub)

    for course in sorted(os.listdir(ws)):
        if course.startswith((".", "bazel-")) or course in NOT_COURSES or not os.path.isdir(os.path.join(ws, course)):
            continue
        walk(course)
    return found


def layer_levels(ws):
    """_LAYER_LEVEL from tools/defs.bzl: {layer: level number}, in its order.

    Read, never copied: a layer added there is a word 42 knows the same day.
    An empty result is an error, because a reading that silently finds nothing
    would turn every layer word into "did you mean".
    """
    path = os.path.join(ws, "tools", "defs.bzl")
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


def resolve_level(flag, environ, ws):
    """(level, where it came from): --level, then SUBMIT_GATE, then .submit-level, then basic.

    tools/submit.sh's order, read the way it reads them (the file with every
    blank removed), so `42 test` runs what the gate will.
    """
    if flag:
        value, source = flag, "--level"
    elif environ.get("SUBMIT_GATE"):
        value, source = environ["SUBMIT_GATE"], "SUBMIT_GATE"
    else:
        value, source = "", "default"
        path = os.path.join(ws, ".submit-level")
        if os.path.isfile(path):
            with open(path, encoding="utf-8", errors="replace") as f:
                value = re.sub(r"[ \t\n\r]", "", f.read())
            source = ".submit-level"
        if not value:
            value, source = "basic", "default"
    if value not in LEVELS:
        raise UsageError("%s says %r, which is not a level. The levels are %s." % (
            source, value, ", ".join(LEVELS)))
    return value, source


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
    """What a command applies to: a project, maybe one exercise and one of its
    members, maybe one layer; or a label."""

    def __init__(self, project=None, ex=None, layer=None, label=None, member=None):
        self.project = project
        self.ex = ex
        self.layer = layer
        self.label = label
        self.member = member

    def __repr__(self):
        return "Scope(%r, %r, %r, %r, member=%r)" % (self.project, self.ex, self.layer, self.label, self.member)

    def describe(self):
        if self.label:
            return self.label
        words = [self.project.short] if self.project else []
        if self.ex:
            words.append(self.ex)
        if self.member:
            words.append(self.member)
        if self.layer:
            words.append("layer " + self.layer)
        return " ".join(words)

    def words(self):
        """The 42 words that name this scope again."""
        if self.label:
            return [self.label]
        out = [self.project.short] if self.project else []
        if self.ex:
            out.append(self.ex)
        if self.member:
            out.append(self.member)
        if self.layer:
            out.append(self.layer)
        return out


class Workspace:
    def __init__(self, ws, cwd):
        self.ws = os.path.realpath(ws)
        self.cwd = os.path.realpath(cwd)
        self._projects = None
        self._layers = None

    def projects(self):
        if self._projects is None:
            self._projects = find_projects(self.ws)
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
        """The scope a folder or file stands for: its project, its exercise if it is
        in one, and its member if it is in one's tests (tests/exNN/<function>/)."""
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
        if len(parts) >= 2 and parts[0] == "tests" and re.match(r"ex\d+$", parts[1]):
            ex = parts[1]
            if len(parts) >= 3 and parts[2] in project.members(ex):
                member = parts[2]
        elif len(parts) >= 2 and parts[0] == "generators":
            m = re.match(r"(ex\d+)\.sh$", parts[1])
            ex = m.group(1) if m else None
        elif parts and parts[0] == "deliverable":
            # The contract's turn-in folders, the longest that holds the path:
            # never a guess from the folder names on disk (first_red.sh says why).
            best = ""
            for e in project.exercises():
                t = project.turnin(e)
                if t and (inner == t or inner.startswith(t + "/")) and len(t) > len(best):
                    best, ex = t, e
        if ex is not None and ex not in project.exercises():
            ex = member = None
        return Scope(project=project, ex=ex, member=member)

    def resolve(self, words):
        """The scope a command's words and the current folder name together.

        A word that is no label, exercise, layer or project is a member's: one
        of the project in scope, once every other word has named that project;
        with none in scope, of the one project that has it. A word that is no
        member there either is an unknown word, said as one; and one that is
        no project's member is said at once, before any later word's error.
        """
        base = self.scope_of_path(self.cwd)
        project, ex, layer, label = base.project, base.ex, None, None
        member = base.member
        path_member = None  # the function a path word's folder is
        rest = []  # the words that are nothing else: functions, or unknown
        named_project = named_ex = False
        layers = self.layers()
        for w in words:
            if w.startswith("//"):
                if len(words) > 1:
                    raise UsageError("a label (%s) is run as it is: give it alone." % w)
                return Scope(label=w)
            if re.match(r"ex\d+$", w):
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
                if p is not project:
                    member = None
                    if not named_ex:
                        ex = None
                project, named_project = p, True
                continue
            # A word no project has as a function can never become one,
            # whatever a later word names: it is unknown now, before any
            # later word's error, as it always was.
            if not any(q.member_exercises(w) for q in self.projects()):
                raise UnknownWord(self._unknown(w, project), w)
            rest.append(w)
        if named_ex:
            member = path_member  # an exercise named is the whole exercise
        if rest:
            # Each word is read before two are refused as two functions: an
            # unknown word is said as one, with what it may have meant.
            found = [self._member(w, project, ex if named_ex else None) for w in rest]
            if len(found) > 1:
                raise UsageError("one function at a time: %s and %s." % (rest[0], rest[1]))
            project, ex, member = found[0]
        if ex is not None:
            if project is None:
                raise UsageError("%s of which project? Name one (42 test c-05 %s), or run it from the project's folder." % (ex, ex))
            if ex not in project.exercises():
                raise UsageError("%s has no %s. Its exercises: %s." % (
                    project.short, ex, " ".join(project.exercises())))
        return Scope(project=project, ex=ex, layer=layer, member=member)

    def _member(self, word, project, ex):
        """(project, exercise, member) for a member word: the project in scope's,
        else the one project that has it. ex, when a word named it, must hold it."""
        if project is not None:
            exs = project.member_exercises(word)
            if not exs:
                elsewhere = [p for p in self.projects() if p is not project and p.member_exercises(word)]
                if elsewhere:
                    raise UnknownWord("%r is a function of %s, not of %s." % (
                        word, " and ".join(p.short for p in elsewhere), project.short), word)
                raise UnknownWord(self._unknown(word, project), word)
        else:
            hits = [p for p in self.projects() if p.member_exercises(word)]
            if not hits:
                raise UnknownWord(self._unknown(word), word)
            if len(hits) > 1:
                raise UsageError("%s of which project? It is a function of %s: name one with it (%s %s)." % (
                    word, " and ".join(p.short for p in hits), hits[0].name, word))
            project = hits[0]
            exs = project.member_exercises(word)
        if ex is not None and ex not in exs:
            if ex not in project.exercises():
                return project, ex, None  # resolve() says the project has no such exercise
            raise UsageError("%s %s has no function %s: it is one of %s." % (
                project.short, ex, word, " ".join(exs)))
        return project, ex or exs[0], word

    def _example_member(self, project=None):
        """A function to show as an example: the project in scope's first, else
        the first of any project; None when no project has one."""
        for p in ([project] if project else []) + self.projects():
            for ex in p.exercises():
                if p.members(ex):
                    return p.members(ex)[0]
        return None

    def _unknown(self, word, project=None):
        names = [p.short for p in self.projects()] + list(self.layers()) + list(LAYER_ALIASES)
        for p in ([project] if project else self.projects()):
            for ex in p.exercises():
                names += p.members(ex)
        close = difflib.get_close_matches(word, names, n=3, cutoff=0.6)
        hint = (" Did you mean %s?" % " or ".join(close)) if close else ""
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
