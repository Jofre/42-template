"""Where a student is, in this repo's own terms: a project, an exercise, a layer.

Nothing here is a second copy of a fact the harness already holds. The projects
are the folders whose BUILD.bazel opens a subject() contract and calls
c_levels(); an exercise is an entry of that contract; its turn-in folder is the
contract's, read by tools/first_red.sh --turnin (the one reading
//tools/tests:turnin_dirs holds to the macros'); the layers are _LAYER_LEVEL's
in tools/defs.bzl; the level filter is tools/submit.sh's gate_tags(), so a
green `42 test` is a gate `42 submit` will pass.
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


class Project:
    """One project folder: a BUILD.bazel that opens subject() and calls c_levels()."""

    def __init__(self, ws, rel):
        self.ws = ws
        self.rel = rel  # c-piscine/c-piscine-c-05
        self.name = os.path.basename(rel)  # c-piscine-c-05
        self.label = "//" + rel
        self.short = short_name(self.label)  # c-05
        self._exercises = None
        self._turnin = {}

    def __repr__(self):
        return "Project(%r)" % self.rel

    @property
    def path(self):
        return os.path.join(self.ws, self.rel)

    def exercises(self):
        """The contract's entries, as exNN, in the order the contract lists them."""
        if self._exercises is None:
            with open(os.path.join(self.path, "BUILD.bazel"), encoding="utf-8") as f:
                self._exercises = contract_exercises(f.read())
        return self._exercises

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
        code = line.split("#", 1)[0]
        for nn in re.findall(r'"(\d+)"\s*:\s*exercise\(', code):
            ex = "ex" + nn
            if ex not in out:
                out.append(ex)
    return out


def find_projects(ws):
    """Every project of the checkout, in path order."""
    found = []
    for course in sorted(os.listdir(ws)):
        cdir = os.path.join(ws, course)
        if course.startswith((".", "bazel-")) or not os.path.isdir(cdir):
            continue
        for proj in sorted(os.listdir(cdir)):
            build = os.path.join(cdir, proj, "BUILD.bazel")
            if not os.path.isfile(build):
                continue
            with open(build, encoding="utf-8") as f:
                text = f.read()
            if re.search(r"^subject\(", text, re.M) and "c_levels(" in text:
                found.append(Project(ws, course + "/" + proj))
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


class Scope:
    """What a command applies to: a project, maybe one exercise, maybe one layer; or a label."""

    def __init__(self, project=None, ex=None, layer=None, label=None):
        self.project = project
        self.ex = ex
        self.layer = layer
        self.label = label

    def __repr__(self):
        return "Scope(%r, %r, %r, %r)" % (self.project, self.ex, self.layer, self.label)

    def describe(self):
        if self.label:
            return self.label
        words = [self.project.short] if self.project else []
        if self.ex:
            words.append(self.ex)
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
        """The scope a folder or file stands for: its project, and its exercise if it is in one."""
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
        ex = None
        if len(parts) >= 2 and parts[0] == "tests" and re.match(r"ex\d+$", parts[1]):
            ex = parts[1]
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
            ex = None
        return Scope(project=project, ex=ex)

    def resolve(self, words):
        """The scope a command's words and the current folder name together."""
        base = self.scope_of_path(self.cwd)
        project, ex, layer, label = base.project, base.ex, None, None
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
                        break
            if p is not None:
                if named_project and p is not project:
                    raise UsageError("one project at a time: %s and %s." % (project.short, p.short))
                if p is not project and not named_ex:
                    ex = None
                project, named_project = p, True
                continue
            raise UsageError(self._unknown(w))
        if ex is not None:
            if project is None:
                raise UsageError("%s of which project? Name one (42 test c-05 %s), or run it from the project's folder." % (ex, ex))
            if ex not in project.exercises():
                raise UsageError("%s has no %s. Its exercises: %s." % (
                    project.short, ex, " ".join(project.exercises())))
        return Scope(project=project, ex=ex, layer=layer)

    def _unknown(self, word):
        names = [p.short for p in self.projects()] + list(self.layers()) + list(LAYER_ALIASES)
        close = difflib.get_close_matches(word, names, n=3, cutoff=0.6)
        hint = (" Did you mean %s?" % " or ".join(close)) if close else ""
        return ("%r is not a project, an exercise (ex03) or a layer.%s "
                "`42 help test` lists what a word can be." % (word, hint))

    def project_list(self):
        """The projects, as the help and the root's error list them."""
        return " ".join(p.short for p in self.projects())

    def selection(self, scope, level):
        """(patterns, tag filter or None) for `bazel test`: the submit gate's selection.

        A project runs //<project>/... and an exercise its :exNN suite, both
        under gate_tags(level). A layer word runs that layer, whatever its
        level: asking for one by name is asking for it to run. A label runs
        with no filter, because a filter also drops a target named on the
        command line.
        """
        if scope.label:
            return [scope.label], None
        if scope.project is None:
            raise UsageError("which project? Run 42 from a project's folder, or name one: %s" % self.project_list())
        target = scope.project.label + (":" + scope.ex if scope.ex else "/...")
        if scope.layer:
            return [target], scope.layer + ",-manual"
        return [target], gate_tags(level)
