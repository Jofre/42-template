"""workspace.py: projects, scopes, levels and the selection, against the checkout's own facts."""

import os
import re
import subprocess
import tempfile
import unittest

from common import WS
import workspace
from workspace import UsageError, Workspace


def remotes():
    """tools/submit.sh's REMOTES table: the repo's module registry (conventions.sh counts it)."""
    with open(os.path.join(WS, "tools", "submit.sh"), encoding="utf-8") as f:
        text = f.read()
    block = text.split("\nREMOTES='\n", 1)[1].split("\n'", 1)[0]
    return sorted(line.split("=", 1)[0] for line in block.splitlines() if "=" in line)


def submit_gate_tags(level):
    """submit.sh's own gate_tags(), run, for one level."""
    with open(os.path.join(WS, "tools", "submit.sh"), encoding="utf-8") as f:
        text = f.read()
    fn = re.search(r"^gate_tags\(\) \{.*?^\}", text, re.M | re.S).group(0)
    r = subprocess.run(["sh", "-c", fn + '\ngate_tags "$1"', "sh", level],
                       stdout=subprocess.PIPE, universal_newlines=True, check=False)
    return r.stdout.strip() if r.returncode == 0 else None


def shell_short_name(path, fn_pattern, call):
    """A short-name rule written in one of the scripts, run over a project's path."""
    with open(os.path.join(WS, "tools", path), encoding="utf-8") as f:
        text = f.read()
    fn = re.search(fn_pattern, text, re.M | re.S).group(0)
    r = subprocess.run(["sh", "-c", call % fn, "sh"] + list(Projects.rels()),
                       stdout=subprocess.PIPE, universal_newlines=True, check=True)
    return r.stdout.splitlines()


class Projects(unittest.TestCase):
    @staticmethod
    def rels():
        return [p.rel for p in Workspace(WS, WS).projects()]

    def setUp(self):
        self.W = Workspace(WS, WS)

    def test_every_module_of_the_registry_is_a_project(self):
        self.assertEqual(sorted(p.rel for p in self.W.projects()), remotes())

    def test_every_project_has_exercises(self):
        for p in self.W.projects():
            self.assertTrue(p.exercises(), p.rel)
            for ex in p.exercises():
                self.assertRegex(ex, r"^ex\d+$")

    def test_short_names_are_unique_and_resolve(self):
        shorts = [p.short for p in self.W.projects()]
        self.assertEqual(len(shorts), len(set(shorts)))
        for p in self.W.projects():
            for word in (p.short, p.name, p.rel, p.rel + "/"):
                self.assertIs(self.W.project_named(word), p, word)

    def test_the_scripts_short_names_are_42s(self):
        # submit.sh reads .submit-remotes keys, and first_red.sh words its
        # report, by the short name 42 takes: the same rule in each.
        want = [workspace.short_name("//" + rel) for rel in self.rels()]
        self.assertEqual(shell_short_name(
            "submit.sh", r"^short_name\(\) \{.*?^\}",
            '%s\nfor m; do short_name "$m"; printf "%%s\\n" "$_sn"; done'), want)
        self.assertEqual(shell_short_name(
            "first_red.sh", r"^\tfunction shortname\(.*?^\t\}",
            "awk '%s\nBEGIN { for (i = 1; i < ARGC; i++) print shortname(\"//\" ARGV[i]) }' \"$@\""),
            want)

    def test_short_name_rule(self):
        self.assertEqual(workspace.short_name("//c-piscine/c-piscine-c-05"), "c-05")
        self.assertEqual(workspace.short_name("//c-piscine-reloaded/c-piscine-reloaded"), "reloaded")
        self.assertEqual(workspace.short_name("//cursus/libft"), "cursus/libft")

    def test_short_name_is_first_reds(self):
        # first_red.sh's own shortname(), cut out of the script and run: a
        # command it suggests must name the project the way 42 reads it.
        with open(os.path.join(WS, "tools", "first_red.sh"), encoding="utf-8") as f:
            m = re.search(r"^\s*function shortname\(.*?^\s*\}$", f.read(), re.M | re.S)
        self.assertIsNotNone(m, "tools/first_red.sh has no function shortname( any more")
        projects = self.W.projects()
        self.assertTrue(projects)
        labels = [p.label for p in projects] + ["//cursus/libft", "//tools/tests", "c-piscine-c-05"]
        r = subprocess.run(["awk", m.group(0) + "\n{ print shortname($0) }"], input="\n".join(labels) + "\n",
                           stdout=subprocess.PIPE, universal_newlines=True, check=True)
        theirs = r.stdout.splitlines()
        self.assertEqual(len(theirs), len(labels), r.stdout)
        for label, short in zip(labels, theirs):
            self.assertEqual(workspace.short_name(label), short, label)
        for p, short in zip(projects, theirs):
            self.assertEqual(p.short, short, p.label)

    def test_contract_reading(self):
        text = (
            'load("x", "y")\n'
            "subject(\n"
            '    exercises = {\n'
            '        "00": exercise(dir = "ex00/"),  # "07": exercise( is a comment\n'
            '        "01": exercise(\n'
            '            dir = None,\n'
            "        ),\n"
            "    },\n"
            ")\n"
            'x = {"02": exercise()}\n')
        self.assertEqual(workspace.contract_exercises(text), ["ex00", "ex01"])

    def test_layers_are_read_from_defs(self):
        layers = workspace.layer_levels(WS)
        for name in ("norm", "output", "valgrind"):
            self.assertIn(name, layers)
        self.assertEqual(layers["norm"], 1)


class Levels(unittest.TestCase):
    def test_precedence(self):
        with tempfile.TemporaryDirectory() as ws:
            self.assertEqual(workspace.resolve_level(None, {}, ws), ("basic", "default"))
            with open(os.path.join(ws, ".submit-level"), "w") as f:
                f.write(" robust\n")
            self.assertEqual(workspace.resolve_level(None, {}, ws), ("robust", ".submit-level"))
            env = {"SUBMIT_GATE": "strict"}
            self.assertEqual(workspace.resolve_level(None, env, ws), ("strict", "SUBMIT_GATE"))
            self.assertEqual(workspace.resolve_level("complete", env, ws), ("complete", "--level"))

    def test_an_empty_file_is_the_default(self):
        with tempfile.TemporaryDirectory() as ws:
            open(os.path.join(ws, ".submit-level"), "w").close()
            self.assertEqual(workspace.resolve_level(None, {}, ws), ("basic", "default"))

    def test_an_invalid_level_names_its_source(self):
        with tempfile.TemporaryDirectory() as ws:
            with open(os.path.join(ws, ".submit-level"), "w") as f:
                f.write("strct")
            with self.assertRaisesRegex(UsageError, r"\.submit-level says 'strct'"):
                workspace.resolve_level(None, {}, ws)
            with self.assertRaisesRegex(UsageError, "SUBMIT_GATE says 'x'"):
                workspace.resolve_level(None, {"SUBMIT_GATE": "x"}, ws)

    def test_gate_tags_are_submits(self):
        for level in workspace.LEVELS:
            self.assertEqual(workspace.gate_tags(level), submit_gate_tags(level), level)


class Scopes(unittest.TestCase):
    def setUp(self):
        self.W = Workspace(WS, WS)
        self.c05 = self.W.project_named("c-05")

    def at(self, rel):
        return Workspace(WS, os.path.join(WS, rel))

    def test_folders(self):
        cases = {
            "": (None, None),
            "c-piscine": (None, None),
            "c-piscine/c-piscine-c-05": ("c-05", None),
            "c-piscine/c-piscine-c-05/tests": ("c-05", None),
            "c-piscine/c-piscine-c-05/tests/ex03": ("c-05", "ex03"),
            "c-piscine/c-piscine-c-05/tests/ex03/deeper": ("c-05", "ex03"),
            "c-piscine/c-piscine-c-05/deliverable": ("c-05", None),
            "c-piscine/c-piscine-c-05/deliverable/ex03": ("c-05", "ex03"),
            "c-piscine/c-piscine-c-05/deliverable/ex03/ft_x.c": ("c-05", "ex03"),
            "c-piscine/c-piscine-shell-00/generators/ex02.sh": ("shell-00", "ex02"),
            "c-piscine/c-piscine-shell-00/generators": ("shell-00", None),
        }
        for rel, (proj, ex) in cases.items():
            s = self.W.scope_of_path(os.path.join(WS, rel))
            self.assertEqual((s.project.short if s.project else None, s.ex), (proj, ex), rel)

    def test_a_turn_in_folder_is_the_contracts(self):
        # BSQ's subject names no turn-in folder: deliverable/ itself is ex00's.
        bsq = self.W.project_named("bsq")
        if bsq.turnin("ex00") == "deliverable":
            s = self.W.scope_of_path(os.path.join(bsq.path, "deliverable", "main.c"))
            self.assertEqual(s.ex, "ex00")

    def test_every_exercise_folder_of_every_project(self):
        for p in self.W.projects():
            for ex in p.exercises():
                s = self.W.scope_of_path(os.path.join(p.path, "tests", ex))
                self.assertEqual((s.project, s.ex), (p, ex), p.rel + " " + ex)
                t = p.turnin(ex)
                self.assertTrue(t == "deliverable" or t.startswith("deliverable/"), (p.rel, ex, t))

    def test_words(self):
        W = self.at("c-piscine/c-piscine-c-05/tests/ex03")
        s = W.resolve([])
        self.assertEqual((s.project.short, s.ex, s.layer), ("c-05", "ex03", None))
        s = W.resolve(["norminette"])
        self.assertEqual((s.project.short, s.ex, s.layer), ("c-05", "ex03", "norm"))
        s = W.resolve(["ex04"])
        self.assertEqual((s.project.short, s.ex), ("c-05", "ex04"))
        s = W.resolve(["c-06"])
        self.assertEqual((s.project.short, s.ex), ("c-06", None))
        s = W.resolve(["c-06", "ex01", "valgrind"])
        self.assertEqual((s.project.short, s.ex, s.layer), ("c-06", "ex01", "valgrind"))
        s = W.resolve(["ex01", "c-piscine-c-06"])
        self.assertEqual((s.project.short, s.ex), ("c-06", "ex01"))
        s = W.resolve(["//c-piscine/c-piscine-c-05:ex03_output"])
        self.assertEqual(s.label, "//c-piscine/c-piscine-c-05:ex03_output")

    def test_a_path_word(self):
        W = self.at("c-piscine")
        s = W.resolve(["c-piscine-c-05/tests/ex02"])
        self.assertEqual((s.project.short, s.ex), ("c-05", "ex02"))

    def test_word_errors(self):
        W = self.at("c-piscine/c-piscine-c-05")
        for words, msg in (
                (["nrom"], "Did you mean norm"),
                (["ex99"], "c-05 has no ex99"),
                (["//a:b", "ex03"], "give it alone"),
                (["c-05", "c-06"], "one project at a time"),
                (["norm", "output"], "one layer at a time"),
                (["ex01", "ex02"], "one exercise at a time"),
                # Two words that are nothing: the first is unknown, and said
                # so, never "one function at a time".
                (["outptu", "valgrnd"], "'outptu' is not a project.*Did you mean output"),
                # An unknown word is said before a later word's error, as it
                # always was: it can become nothing whatever comes after it.
                (["outptu", "ex01", "ex02"], "'outptu' is not a project.*Did you mean output"),
                (["outptu", "c-05", "c-06"], "'outptu' is not a project.*Did you mean output"),
                (["outptu", "norm", "output"], "'outptu' is not a project.*Did you mean output"),
                (["outptu", "//a:b"], "'outptu' is not a project.*Did you mean output")):
            with self.assertRaisesRegex(UsageError, msg):
                W.resolve(words)
        with self.assertRaisesRegex(UsageError, "of which project"):
            Workspace(WS, WS).resolve(["ex03"])


LEVELS_BZL = '_LAYER_LEVEL = {\n    "norm": 1,\n    "output": 1,\n    "valgrind": 1,\n}\n'

# A contract with members, written as a project's BUILD file writes one: the
# functions = {...} of an exercise, each key a function, each value the
# external functions it may call. A key-shaped string in a comment, and a
# value's strings, are no member.
LIB_BUILD = (
    'load("//tools:defs.bzl", "c_levels")\n'
    "subject(\n"
    '    grader = "both",\n'
    "    exercises = {\n"
    '        "00": exercise(\n'
    "            dir = None,\n"
    "            functions = {\n"
    '                "ft_isalpha": [],\n'
    '                "ft_strlen": [],\n'
    '                # "ft_commented": [],\n'
    '                "ft_split": ["malloc", "free"],\n'
    "            },\n"
    "        ),\n"
    "    },\n"
    ")\n"
    "c_levels()\n")
OTHER_BUILD = (
    "subject(\n"
    "    exercises = {\n"
    '        "00": exercise(dir = "ex00/"),\n'
    '        "01": exercise(dir = None, functions = {"ft_strlen": [], "ft_other": ["write"]}),\n'
    "    },\n"
    ")\n"
    "c_levels()\n")
PISCINE_BUILD = 'subject(\n    exercises = {\n        "00": exercise(dir = "ex00/"),\n    },\n)\nc_levels()\n'


def tree(root, files):
    for rel, text in files.items():
        path = os.path.join(root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)


class Deep(unittest.TestCase):
    """A project at any depth under its course (cursus/Milestone_0/Libft), and its
    members: the functions of a library exercise, each a word of its own."""

    LIB = "cursus/Milestone_0/Libft"

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.ws = self.tmp.name
        tree(self.ws, {
            "tools/defs.bzl": LEVELS_BZL,
            # The macro fixtures open a contract and call c_levels() at depth
            # 3, as a project does: tools/ holds no project.
            "tools/tests/macro_fixtures/levels/BUILD.bazel": PISCINE_BUILD,
            "oracle/x/y/BUILD.bazel": PISCINE_BUILD,
            "docs/x/y/BUILD.bazel": PISCINE_BUILD,
            ".hidden/x/y/BUILD.bazel": PISCINE_BUILD,
            "bazel-out/x/y/BUILD.bazel": PISCINE_BUILD,
            "c-piscine/c-piscine-c-05/BUILD.bazel": PISCINE_BUILD,
            "c-piscine/c-piscine-c-05/tests/ex00/x/BUILD.bazel": PISCINE_BUILD,
            self.LIB + "/BUILD.bazel": LIB_BUILD,
            self.LIB + "/tests/ex00/ft_strlen/test_ft_strlen.c": "",
            self.LIB + "/tests/ex00/ft_split/deeper/x.txt": "",
            self.LIB + "/tests/ex00/layout/x.h": "",
            # Inside a project nothing is another project: not under its
            # turn-in, its generators or its tests, nor any folder of its own.
            self.LIB + "/deliverable/BUILD.bazel": PISCINE_BUILD,
            self.LIB + "/generators/x/BUILD.bazel": PISCINE_BUILD,
            self.LIB + "/sub/BUILD.bazel": PISCINE_BUILD,
            "cursus/Milestone_1/Other/BUILD.bazel": OTHER_BUILD,
            # A BUILD file with no contract is no project, and the walk goes on below it.
            "cursus/Milestone_2/BUILD.bazel": "filegroup()\n",
            "cursus/Milestone_2/Third/BUILD.bazel": PISCINE_BUILD,
        })
        self.W = Workspace(self.ws, self.ws)
        self.lib = self.W.project_named("Libft")

    def at(self, rel):
        return Workspace(self.ws, os.path.join(self.ws, rel))

    def test_projects_are_found_at_any_depth_and_nowhere_else(self):
        self.assertEqual([p.rel for p in self.W.projects()], [
            "c-piscine/c-piscine-c-05", self.LIB, "cursus/Milestone_1/Other",
            "cursus/Milestone_2/Third"])
        self.assertEqual(self.lib.label, "//" + self.LIB)

    def test_contract_functions(self):
        self.assertEqual(workspace.contract_functions(LIB_BUILD),
                         {"ex00": ["ft_isalpha", "ft_strlen", "ft_split"]})
        self.assertEqual(workspace.contract_functions(OTHER_BUILD), {"ex01": ["ft_strlen", "ft_other"]})
        self.assertEqual(workspace.contract_functions(PISCINE_BUILD), {})
        self.assertEqual(self.lib.members("ex00"), ["ft_isalpha", "ft_strlen", "ft_split"])
        self.assertEqual(self.W.project_named("Other").members("ex00"), [])

    def test_the_three_contract_readers_agree(self):
        # workspace.contract_functions, first_red.sh's contract_read and
        # conventions.sh's contract_fns read the same keys. Two cut a line at
        # its first '#', and one skipped strings first: a '#' inside a string
        # before `functions = {` lost every key of the line to two of them. A
        # '}' inside a string ends no `functions` either, and a '#' after the
        # code is a comment to all three.
        text = (
            "subject(\n"
            "    exercises = {\n"
            '        "00": exercise(dir = "a#b", functions = {"ft_one": [], "ft_two": ["x}y"]}),'
            '  # "ft_not": [] is a comment\n'
            '        "01": exercise(\n'
            '            dir = "#",\n'
            '            functions = {"ft_three": [], "ft_four": []},  # {"ft_no": []}\n'
            "        ),\n"
            "    },\n"
            ")\n"
            "c_levels()\n")
        want = [("ex00", "ft_one"), ("ex00", "ft_two"), ("ex01", "ft_three"), ("ex01", "ft_four")]
        mine = [(ex, f) for ex, fs in workspace.contract_functions(text).items() for f in fs]
        self.assertEqual(mine, want)
        lib = os.path.join(self.ws, "readers")
        tree(lib, {"BUILD.bazel": text})
        r = subprocess.run(["sh", os.path.join(WS, "tools", "first_red.sh"), "--members", lib],
                           stdout=subprocess.PIPE, universal_newlines=True, check=True)
        self.assertEqual([tuple(l.split("\t")) for l in r.stdout.splitlines()], want)
        with open(os.path.join(WS, "tools", "conventions.sh"), encoding="utf-8") as f:
            fn = re.search(r"^contract_fns\(\) \{.*?^\}", f.read(), re.M | re.S).group(0)
        r = subprocess.run(["sh", "-c", fn + '\ncontract_fns "$1"', "sh", os.path.join(lib, "BUILD.bazel")],
                           stdout=subprocess.PIPE, universal_newlines=True, check=True)
        self.assertEqual([tuple(l.split("\t")) for l in r.stdout.splitlines()], want)

    def test_a_member_folder_is_that_member(self):
        L = self.LIB
        cases = {
            L + "/tests/ex00": ("ex00", None),
            L + "/tests/ex00/ft_strlen": ("ex00", "ft_strlen"),
            L + "/tests/ex00/ft_strlen/test_ft_strlen.c": ("ex00", "ft_strlen"),
            L + "/tests/ex00/ft_split/deeper": ("ex00", "ft_split"),
            L + "/tests/ex00/layout": ("ex00", None),
        }
        for rel, want in cases.items():
            s = self.W.scope_of_path(os.path.join(self.ws, rel))
            self.assertIs(s.project, self.lib, rel)
            self.assertEqual((s.ex, s.member), want, rel)

    def test_member_words(self):
        for cwd, words in ((self.LIB, ["ft_strlen"]), ("", ["Libft", "ft_strlen"]),
                           ("", ["ft_strlen", "Libft"]), ("", ["ex00", "ft_strlen", "Libft"]),
                           ("cursus/Milestone_1/Other", ["Libft", "ft_strlen"]),
                           (self.LIB + "/tests/ex00/ft_split", ["ft_strlen"]),
                           (self.LIB + "/tests/ex00/ft_strlen", [])):
            s = self.at(cwd).resolve(words)
            self.assertEqual((s.project.rel, s.ex, s.member, s.layer), (self.LIB, "ex00", "ft_strlen", None),
                             (cwd, words))
        s = self.at(self.LIB).resolve(["ft_split", "valgrind"])
        self.assertEqual((s.ex, s.member, s.layer), ("ex00", "ft_split", "valgrind"))
        self.assertEqual(s.words(), [self.LIB, "ex00", "ft_split", "valgrind"])
        self.assertEqual(s.describe(), self.LIB + " ex00 ft_split layer valgrind")
        # With no project in scope, a function only one project has is that project's.
        s = self.at("").resolve(["ft_isalpha"])
        self.assertEqual((s.project.rel, s.ex, s.member), (self.LIB, "ex00", "ft_isalpha"))
        s = self.at("").resolve(["ft_other"])
        self.assertEqual((s.project.name, s.ex, s.member), ("Other", "ex01", "ft_other"))
        # A member found from the folder goes with its project, and with its exercise.
        s = self.at(self.LIB + "/tests/ex00/ft_strlen").resolve(["Other"])
        self.assertEqual((s.project.name, s.ex, s.member), ("Other", None, None))
        s = self.at(self.LIB + "/tests/ex00/ft_strlen").resolve(["norm"])
        self.assertEqual((s.ex, s.member, s.layer), ("ex00", "ft_strlen", "norm"))
        # ...and an exercise named is the whole exercise.
        s = self.at(self.LIB + "/tests/ex00/ft_strlen").resolve(["ex00"])
        self.assertEqual((s.ex, s.member), ("ex00", None))

    def test_member_word_errors(self):
        for cwd, words, msg in (
                ("", ["ft_strlen"], "ft_strlen of which project"),
                (self.LIB, ["ft_strlen", "ft_split"], "one function at a time"),
                ("cursus/Milestone_1/Other", ["ex00", "ft_other"], "Other ex00 has no function ft_other")):
            with self.assertRaisesRegex(UsageError, msg, msg=(cwd, words)):
                self.at(cwd).resolve(words)

    def test_a_function_of_another_project_names_that_project(self):
        # Rejected with "'ft_strlen' is not ... a function (ft_strlen)": its
        # own word as the example, and never the project that has it.
        for cwd, words, msg in (
                ("c-piscine/c-piscine-c-05", ["ft_isalpha"],
                 "'ft_isalpha' is a function of %s, not of c-05." % self.LIB),
                ("c-piscine/c-piscine-c-05", ["ft_strlen"],
                 "'ft_strlen' is a function of %s and cursus/Milestone_1/Other, not of c-05." % self.LIB),
                (self.LIB, ["ft_other"],
                 "'ft_other' is a function of cursus/Milestone_1/Other, not of %s." % self.LIB)):
            with self.assertRaises(workspace.UnknownWord, msg=(cwd, words)) as cm:
                self.at(cwd).resolve(words)
            self.assertIn(msg, str(cm.exception))

    def test_two_unknown_words_are_unknown_not_two_functions(self):
        # The second word that is nothing else once made both "functions":
        # "one function at a time: outptu and valgrnd", where main said
        # which word it could not read, and what it may have meant.
        for cwd, words, bad, hint in (
                ("c-piscine/c-piscine-c-05", ["outptu", "valgrnd"], "outptu", "Did you mean output"),
                (self.LIB, ["ft_strlen", "valgrnd"], "valgrnd", "Did you mean valgrind"),
                (self.LIB, ["ft_strlne", "ft_split"], "ft_strlne", "Did you mean ft_strlen")):
            with self.assertRaises(workspace.UnknownWord, msg=(cwd, words)) as cm:
                self.at(cwd).resolve(words)
            self.assertEqual(cm.exception.word, bad, (cwd, words))
            self.assertIn(hint, str(cm.exception), (cwd, words))

    def test_an_unknown_word_says_a_function_is_one(self):
        # The example is a function of a project that has some, never the
        # word rejected.
        with self.assertRaisesRegex(UsageError, r"a function \(ft_isalpha\)"):
            self.at(self.LIB).resolve(["nonsense"])
        with self.assertRaisesRegex(UsageError, r"a function \(ft_isalpha\)"):
            self.at("c-piscine/c-piscine-c-05").resolve(["nonsense"])
        with self.assertRaisesRegex(UsageError, "Did you mean ft_strlen"):
            self.at(self.LIB).resolve(["ft_strlne"])
        # ...and a checkout with no library offers no function at all.
        bare = tempfile.TemporaryDirectory()
        self.addCleanup(bare.cleanup)
        tree(bare.name, {"tools/defs.bzl": LEVELS_BZL, "c-piscine/c-piscine-c-05/BUILD.bazel": PISCINE_BUILD})
        with self.assertRaises(UsageError) as cm:
            Workspace(bare.name, os.path.join(bare.name, "c-piscine/c-piscine-c-05")).resolve(["nonsense"])
        self.assertNotIn("function", str(cm.exception))
        self.assertIn("is not a project, an exercise (ex03) or a layer.", str(cm.exception))

    def test_a_function_folder_is_a_path_word(self):
        # docs/testing.md: "a function's name (ft_strlen) is a word too, and
        # so is its folder of tests". The path word once kept the exercise and
        # dropped the function.
        for cwd, word in (("", self.LIB + "/tests/ex00/ft_strlen"),
                          ("", self.LIB + "/tests/ex00/ft_strlen/"),
                          (self.LIB, "tests/ex00/ft_strlen"),
                          (self.LIB + "/tests/ex00", "ft_strlen/test_ft_strlen.c"),
                          ("cursus/Milestone_1/Other", "../../Milestone_0/Libft/tests/ex00/ft_strlen")):
            s = self.at(cwd).resolve([word])
            self.assertEqual((s.project.rel, s.ex, s.member), (self.LIB, "ex00", "ft_strlen"), (cwd, word))
        s = self.at("").resolve([self.LIB + "/tests/ex00/ft_strlen", "valgrind"])
        self.assertEqual((s.ex, s.member, s.layer), ("ex00", "ft_strlen", "valgrind"))
        # A function word beside it is the one asked for.
        s = self.at("").resolve([self.LIB + "/tests/ex00/ft_strlen", "ft_split"])
        self.assertEqual((s.ex, s.member), ("ex00", "ft_split"))
        # A folder that is no function's is still its exercise alone.
        s = self.at("").resolve([self.LIB + "/tests/ex00/layout"])
        self.assertEqual((s.ex, s.member), ("ex00", None))

    def test_42_norm_from_a_function_runs_the_library_norm(self):
        # From tests/ex00/ft_strlen, `42 norm` selected :ft_strlen filtered by
        # norm, a suite that holds no norm test: Bazel ran nothing.
        from common import run42
        rc, out, err = run42(["norm", "--dry-run"], cwd=os.path.join(self.ws, self.LIB, "tests/ex00/ft_strlen"),
                             ws=self.ws)
        self.assertEqual(rc, 0, err)
        self.assertIn("$ bazel test //%s:ex00 --test_tag_filters=norm,-manual" % self.LIB, out)

    def test_a_layer_no_function_has_names_the_library_command(self):
        # `42 test norm` from a function's folder keeps the function's suite
        # (most layers are per function); when Bazel finds no such test there
        # (exit 4), one line names a command that runs the layer over the
        # whole exercise. It once named `42 test <project> norm`, which from
        # that same folder keeps the function, selects the same empty suite
        # and prints the same line again; and it said the layer "is not
        # tested per function", false of a layer a function only lacks.
        import contextlib
        import io
        import main
        import bazel
        import types
        fn = self.LIB + "/tests/ex00/ft_strlen"
        ctx = main.Ctx(self.ws, os.path.join(self.ws, fn), {},
                       types.SimpleNamespace(plain=True, show_bazel=False, dry_run=False))
        out_path = os.path.join(self.ws, "bazel.out")
        tree(self.ws, {"bazel.out": "ERROR: No test targets were found, yet testing was requested\n"})
        here = self.at(fn)
        for layer in ("norm", "valgrind"):
            scope = here.resolve([layer])
            self.assertEqual((scope.ex, scope.member, scope.layer), ("ex00", "ft_strlen", layer))
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = main.report_run(ctx, scope, "basic", bazel.NO_TESTS, out_path, None, None, False)
            self.assertEqual(rc, bazel.NO_TESTS)
            text = buf.getvalue()
            self.assertNotIn("not tested per function", text)
            self.assertIn("ft_strlen has no %s test of its own." % layer, text)
            line = [l for l in text.splitlines() if "42 test" in l]
            self.assertEqual(len(line), 1, text)
            words = line[0].split("42 test", 1)[1].split()
            self.assertEqual(words, [self.LIB, "ex00", layer])
            # Typed from the folder it is printed in, it leaves the function.
            again = here.resolve(words)
            self.assertEqual(self.W.selection(again, "basic"),
                             (["//%s:ex00" % self.LIB], layer + ",-manual"), text)
        # No function in scope, or no layer: Bazel's line alone.
        for scope in (workspace.Scope(self.lib, "ex00", "norm"),
                      workspace.Scope(self.lib, "ex00", member="ft_strlen")):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                main.report_run(ctx, scope, "basic", bazel.NO_TESTS, out_path, None, None, False)
            self.assertNotIn("of its own", buf.getvalue())
            self.assertNotIn("42 test", buf.getvalue())

    def test_a_member_selects_its_suite(self):
        S = workspace.Scope
        self.assertEqual(self.W.selection(S(self.lib, "ex00", member="ft_strlen"), "basic"),
                         (["//%s:ft_strlen" % self.LIB], "lvl_basic,-manual"))
        self.assertEqual(self.W.selection(S(self.lib, "ex00", member="ft_strlen"), "complete"),
                         (["//%s:ft_strlen" % self.LIB], "-manual"))
        self.assertEqual(self.W.selection(S(self.lib, "ex00", "valgrind", member="ft_strlen"), "basic"),
                         (["//%s:ft_strlen" % self.LIB], "valgrind,-manual"))

    def test_42_test_and_submit_take_a_member_word(self):
        from common import run42
        rc, out, err = run42(["test", "ft_strlen", "--dry-run"], cwd=os.path.join(self.ws, self.LIB), ws=self.ws)
        self.assertEqual(rc, 0, err)
        self.assertIn("$ bazel test //%s:ft_strlen --test_tag_filters=lvl_basic,-manual" % self.LIB, out)
        rc, out, err = run42(["submit", "ft_strlen", "--dry-run"], cwd=os.path.join(self.ws, self.LIB), ws=self.ws)
        self.assertEqual(rc, 2, out)
        self.assertIn("42 submit takes a project, not ft_strlen", err)
        # ...and `42 help test` says a function is a word.
        rc, out, _ = run42(["help", "test"])
        self.assertIn("    a function  ", out)
        self.assertIn("[exNN] [function] [layer]", out)


class Selection(unittest.TestCase):
    def setUp(self):
        self.W = Workspace(WS, WS)
        self.c05 = self.W.project_named("c-05")

    def test_project_exercise_layer_label(self):
        S = workspace.Scope
        self.assertEqual(self.W.selection(S(self.c05), "basic"),
                         (["//c-piscine/c-piscine-c-05/..."], "lvl_basic,-manual"))
        self.assertEqual(self.W.selection(S(self.c05, "ex03"), "complete"),
                         (["//c-piscine/c-piscine-c-05:ex03"], "-manual"))
        self.assertEqual(self.W.selection(S(self.c05, "ex03", "norm"), "basic"),
                         (["//c-piscine/c-piscine-c-05:ex03"], "norm,-manual"))
        self.assertEqual(self.W.selection(S(label="//x:y"), "basic"), (["//x:y"], None))
        with self.assertRaisesRegex(UsageError, "which project"):
            self.W.selection(S(), "basic")


if __name__ == "__main__":
    unittest.main()
