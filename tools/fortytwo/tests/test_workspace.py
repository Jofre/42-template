"""workspace.py: projects, scopes, levels and the selection, against the checkout's own facts."""

import os
import re
import subprocess
import tempfile
import unittest

from common import WS, tool_text
import workspace
from workspace import ContractError, Unit, UsageError, Workspace


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


# Paths no project of the checkout has, each a branch of the short-name rule:
# a Common Core project at any depth and in any case, one whose folder says
# c-piscine-, before and after it is lowercased, and paths of no course.
SHORT_NAME_CASES = ["cursus/Milestone_0/Libft", "cursus/libft", "cursus/Milestone_9/Get_Next_Line",
                    "cursus/Milestone_9/PUSH-swap2", "cursus/c-piscine-c-05", "cursus/Milestone_9/C-PISCINE-x",
                    "cursus", "tools/tests", "c-piscine-c-05", "c-piscine/c-piscine-c-05"]


def shell_short_name(path, fn_pattern, call, rels):
    """A short-name rule written in one of the scripts, run over each path of rels."""
    with open(os.path.join(WS, "tools", path), encoding="utf-8") as f:
        text = f.read()
    fn = re.search(fn_pattern, text, re.M | re.S).group(0)
    r = subprocess.run(["sh", "-c", call % fn, "sh"] + list(rels),
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

    def test_every_project_has_units(self):
        # An exercise is exNN; a unit of a contract of units has a name of
        # its own, never exNN-shaped, and its contract holds no exercise.
        for p in self.W.projects():
            self.assertTrue(p.wholes(), p.rel)
            for u in p.units():
                if u.kind == "exercise":
                    self.assertRegex(u.name, r"^ex\d+$")
                    self.assertFalse(p.named(), p.rel)
                else:
                    self.assertFalse(workspace.is_exercise_name(u.name), (p.rel, u))

    def test_42_reads_each_contract_as_units_awk_prints_it(self):
        # The last link of a chain: //tools/tests:units_parity holds
        # units.awk to each project's :units, the macros' own reading, and
        # 42's units are units.awk's rows, every column, in their order.
        for p in self.W.projects():
            r = subprocess.run(["awk", "-f", os.path.join(WS, "tools", "units.awk"), p.rel + "/BUILD.bazel"],
                               cwd=WS, env=dict(os.environ, LC_ALL="C"), stdout=subprocess.PIPE,
                               universal_newlines=True, check=True)
            rows = [tuple(l.split("\t")) for l in r.stdout.splitlines()]
            self.assertTrue(rows, p.rel)
            self.assertEqual([tuple(u) for u in p.units()], rows, p.rel)
            for u in p.units():
                if u.kind == "function":
                    self.assertIn(u.lib, p.wholes(), (p.rel, u))
                    self.assertEqual(u.folder, p.turnin(u.lib), (p.rel, u))

    def test_short_names_are_unique_and_resolve(self):
        shorts = [p.short for p in self.W.projects()]
        self.assertEqual(len(shorts), len(set(shorts)))
        for p in self.W.projects():
            for word in (p.short, p.name, p.rel, p.rel + "/"):
                self.assertIs(self.W.project_named(word), p, word)

    def test_the_scripts_short_names_are_42s(self):
        # submit.sh reads .submit-remotes keys, and first_red.sh words its
        # report, by the short name 42 takes: the same rule in each, over
        # every project and every branch of the rule.
        rels = self.rels() + SHORT_NAME_CASES
        want = [workspace.short_name("//" + rel) for rel in rels]
        self.assertEqual(shell_short_name(
            "submit.sh", r"^short_name\(\) \{.*?^\}",
            '%s\nfor m; do short_name "$m"; printf "%%s\\n" "$_sn"; done', rels), want)
        self.assertEqual(shell_short_name(
            "first_red.sh", r"^\tfunction shortname\(.*?^\t\}",
            "awk '%s\nBEGIN { for (i = 1; i < ARGC; i++) print shortname(\"//\" ARGV[i]) }' \"$@\"", rels),
            want)

    def test_short_name_rule(self):
        self.assertEqual(workspace.short_name("//c-piscine/c-piscine-c-05"), "c-05")
        self.assertEqual(workspace.short_name("//c-piscine-reloaded/c-piscine-reloaded"), "reloaded")
        # A Common Core project is named by its own folder's name,
        # lowercased, at any depth under cursus/.
        self.assertEqual(workspace.short_name("//cursus/Milestone_0/Libft"), "libft")
        self.assertEqual(workspace.short_name("//cursus/libft"), "libft")
        self.assertEqual(workspace.short_name("//cursus/Milestone_9/Get_Next_Line"), "get_next_line")
        self.assertEqual(workspace.short_name("//cursus/c-piscine-c-05"), "c-05")
        self.assertEqual(workspace.short_name("//cursus/Milestone_9/C-PISCINE-x"), "x")
        self.assertEqual(workspace.short_name("//cursus"), "cursus")
        self.assertEqual(workspace.short_name("//tools/tests"), "tools/tests")
        # Only A-Z is lowered, as tools/submit.sh's tr and first_red.sh's awk lower it.
        self.assertEqual(workspace.short_name("//cursus/M/\u00c9Libft"), "\u00c9libft")

    def test_short_name_is_first_reds(self):
        # first_red.sh's own shortname(), cut out of the script and run: a
        # command it suggests must name the project the way 42 reads it.
        with open(os.path.join(WS, "tools", "first_red.sh"), encoding="utf-8") as f:
            m = re.search(r"^\tfunction shortname\(.*?^\t\}$", f.read(), re.M | re.S)
        self.assertIsNotNone(m, "tools/first_red.sh has no function shortname( any more")
        projects = self.W.projects()
        self.assertTrue(projects)
        labels = [p.label for p in projects] + ["//" + rel for rel in SHORT_NAME_CASES]
        r = subprocess.run(["awk", m.group(0) + "\n{ print shortname($0) }"], input="\n".join(labels) + "\n",
                           stdout=subprocess.PIPE, universal_newlines=True, check=True)
        theirs = r.stdout.splitlines()
        self.assertEqual(len(theirs), len(labels), r.stdout)
        for label, short in zip(labels, theirs):
            self.assertEqual(workspace.short_name(label), short, label)
        for p, short in zip(projects, theirs):
            self.assertEqual(p.short, short, p.label)

    def test_contract_reading(self):
        # A key in a comment is no exercise, and nothing after the call's
        # closing ) is the contract's.
        text = (
            'load("x", "y")\n'
            "subject(\n"
            '    exercises = {\n'
            '        "00": exercise(dir = "ex00/"),  # "07": exercise( is a comment\n'
            '        "01": exercise(\n'
            '            dir = "ex01/",\n'
            "        ),\n"
            "    },\n"
            ")\n"
            'x = {"02": exercise()}\n')
        with tempfile.TemporaryDirectory() as toy:
            tree(toy, {"tools/units.awk": tool_text("units.awk"), "tools/defs_levels.bzl": LEVELS_BZL,
                       "c-piscine/c-piscine-c-05/BUILD.bazel": text})
            p = workspace.Project(toy, "c-piscine/c-piscine-c-05")
            self.assertEqual(p.exercises(), ["ex00", "ex01"])
            self.assertEqual([p.turnin(e) for e in p.exercises()], ["deliverable/ex00", "deliverable/ex01"])

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

    def user_file(self, home, text):
        folder = os.path.join(home, ".config", "42")
        os.makedirs(folder)
        with open(os.path.join(folder, "config.yaml"), "w") as f:
            f.write(text)

    def test_your_user_file_comes_after_this_checkouts_file(self):
        with tempfile.TemporaryDirectory() as ws, tempfile.TemporaryDirectory() as home:
            env = {"HOME": home}
            self.user_file(home, "# mine\nlevel: strict\n")
            self.assertEqual(workspace.resolve_level(None, env, ws), ("strict", "~/.config/42/config.yaml, line 2"))
            # tools/submit.sh does not read it: 42 submit passes it on.
            self.assertEqual(workspace.gate_level_args(None, env, ws), ["--gate-level", "strict"])
            open(os.path.join(ws, ".submit-level"), "w").close()
            self.assertEqual(workspace.resolve_level(None, env, ws)[0], "strict")
            with open(os.path.join(ws, ".submit-level"), "w") as f:
                f.write("robust\n")
            self.assertEqual(workspace.resolve_level(None, env, ws), ("robust", ".submit-level"))
            self.assertEqual(workspace.gate_level_args(None, env, ws), [])
            self.assertEqual(workspace.resolve_level(None, dict(env, SUBMIT_GATE="complete"), ws),
                             ("complete", "SUBMIT_GATE"))
            self.assertEqual(workspace.gate_level_args(None, dict(env, SUBMIT_GATE="complete"), ws), [])
            self.assertEqual(workspace.gate_level_args("all", env, ws), ["--gate-level", "all"])

    def test_a_user_file_42_cannot_read_stops_only_a_level_it_would_decide(self):
        with tempfile.TemporaryDirectory() as ws, tempfile.TemporaryDirectory() as home:
            env = {"HOME": home}
            self.user_file(home, "level: no\n")
            for resolve in (workspace.resolve_level, workspace.gate_level_args):
                with self.assertRaisesRegex(UsageError, r"~/\.config/42/config\.yaml, line 1: YAML reads no"):
                    resolve(None, env, ws)
            self.assertEqual(workspace.resolve_level("basic", env, ws), ("basic", "--level"))
            self.assertEqual(workspace.resolve_level(None, dict(env, SUBMIT_GATE="strict"), ws),
                             ("strict", "SUBMIT_GATE"))
            with open(os.path.join(ws, ".submit-level"), "w") as f:
                f.write("robust\n")
            self.assertEqual(workspace.resolve_level(None, env, ws), ("robust", ".submit-level"))

    def test_a_level_your_user_file_gets_wrong_names_its_line(self):
        with tempfile.TemporaryDirectory() as ws, tempfile.TemporaryDirectory() as home:
            self.user_file(home, "\nlevel: hard\n")
            for resolve in (workspace.resolve_level, workspace.gate_level_args):
                with self.assertRaisesRegex(UsageError,
                                            r"~/\.config/42/config\.yaml, line 2 says 'hard', which is not a level"):
                    resolve(None, {"HOME": home}, ws)

    def test_no_user_file_is_the_default(self):
        with tempfile.TemporaryDirectory() as ws, tempfile.TemporaryDirectory() as home:
            for env in ({"HOME": home}, {}, {"HOME": "relative"}, {"HOME": home, "XDG_CONFIG_HOME": "rel"}):
                self.assertEqual(workspace.resolve_level(None, env, ws), ("basic", "default"), env)
                self.assertEqual(workspace.gate_level_args(None, env, ws), [], env)
            # What the script reports itself stays its own to report.
            self.assertEqual(workspace.gate_level_args(None, {"SUBMIT_GATE": "x"}, ws), [])

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
        # BSQ's subject numbers no exercise and names no turn-in folder: its
        # one unit, bsq, turns in at deliverable/ itself, a file there is the
        # whole project's, tests/bsq/ is the unit's, and the old exercise word
        # is said with the command that lists its parts.
        bsq = self.W.project_named("bsq")
        self.assertEqual(bsq.turnin("bsq"), "deliverable")
        s = self.W.scope_of_path(os.path.join(bsq.path, "deliverable", "main.c"))
        self.assertEqual((s.project, s.ex), (bsq, None))
        s = self.W.scope_of_path(os.path.join(bsq.path, "tests", "bsq"))
        self.assertEqual((s.project, s.ex), (bsq, "bsq"))
        with self.assertRaises(UsageError) as cm:
            self.at("").resolve(["bsq", "ex00"])
        self.assertEqual(str(cm.exception), "ex00 is not a part of bsq; `42 units bsq` lists them.")

    def test_every_exercise_folder_of_every_project(self):
        for p in self.W.projects():
            for ex in p.wholes():
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
# functions = {...} of a library, a unit of a contract of units, each key a
# function, each value the external functions it may call. A key-shaped
# string in a comment, and a value's strings, are no member.
LIB_BUILD = (
    'load("//tools:defs.bzl", "c_levels")\n'
    "subject(\n"
    '    grader = "both",\n'
    "    units = {\n"
    '        "libft": unit(\n'
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
    "    units = {\n"
    '        "other": unit(functions = {"ft_strlen": [], "ft_other": ["write"]}),\n'
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
    members: the functions of a library, each a word of its own."""

    LIB = "cursus/Milestone_0/Libft"

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.ws = self.tmp.name
        tree(self.ws, {
            "tools/units.awk": tool_text("units.awk"),
            "tools/defs_levels.bzl": LEVELS_BZL,
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
            self.LIB + "/tests/ft_strlen/test_ft_strlen.c": "",
            self.LIB + "/tests/ft_split/deeper/x.txt": "",
            self.LIB + "/tests/layout/x.h": "",
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

    def test_units_of_a_library(self):
        # A key-shaped string in a comment, and a value's strings (malloc,
        # free), are no unit; a function's row is its library's folder.
        def fn(name, folder, lib):
            return Unit(name, "function", "-", folder, "defines", lib)

        self.assertEqual(self.lib.units(), [
            Unit("libft", "library", "-", "deliverable", "folder", "-"),
            fn("ft_isalpha", "deliverable", "libft"),
            fn("ft_strlen", "deliverable", "libft"),
            fn("ft_split", "deliverable", "libft")])
        self.assertEqual(self.W.project_named("Other").units(), [
            Unit("other", "library", "-", "deliverable", "folder", "-"),
            fn("ft_strlen", "deliverable", "other"),
            fn("ft_other", "deliverable", "other")])
        self.assertEqual(self.W.project_named("c-05").units(), [
            Unit("ex00", "exercise", "-", "deliverable/ex00", "folder", "-")])
        self.assertEqual(self.lib.members("libft"), ["ft_isalpha", "ft_strlen", "ft_split"])
        self.assertEqual(self.W.project_named("c-05").members("ex00"), [])

    def test_42_reads_a_contract_through_units_awk(self):
        # Three readers of a contract's text once disagreed on a '#' and a
        # '}' inside strings: two cut a line at its first '#'. There is one
        # reader now, tools/units.awk, which the selftest holds on these
        # shapes and //tools/tests:units_parity holds to the macros, and 42
        # reads through it. A '#' after the code is a comment.
        text = (
            "subject(\n"
            "    units = {\n"
            '        "libread": unit(files = ["a#b"], functions = {"ft_one": [], "ft_two": ["x}y"],'
            '  # "ft_not": [] is a comment\n'
            '            "ft_three": [], "ft_four": []},  # {"ft_no": []}\n'
            '            allowed = ["#"],\n'
            "        ),\n"
            "    },\n"
            ")\n"
            "c_levels()\n")
        tree(self.ws, {"cursus/Milestone_3/Readers/BUILD.bazel": text})
        p = Workspace(self.ws, self.ws).project_named("Readers")
        want = [("libread", "ft_one"), ("libread", "ft_two"), ("libread", "ft_three"), ("libread", "ft_four")]
        self.assertEqual([(u, f) for u in p.wholes() for f in p.members(u)], want)
        self.assertEqual([p.turnin(u) for u in p.wholes()], ["deliverable"])

    def test_member_words(self):
        for cwd, words in ((self.LIB, ["ft_strlen"]), ("", ["Libft", "ft_strlen"]),
                           ("", ["ft_strlen", "Libft"]), ("", ["Libft", "libft", "ft_strlen"]),
                           ("cursus/Milestone_1/Other", ["Libft", "ft_strlen"]),
                           (self.LIB + "/tests/ft_split", ["ft_strlen"]),
                           (self.LIB + "/tests/ft_strlen", [])):
            s = self.at(cwd).resolve(words)
            self.assertEqual((s.project.rel, s.ex, s.member, s.layer), (self.LIB, "libft", "ft_strlen", None),
                             (cwd, words))
        s = self.at(self.LIB).resolve(["ft_split", "valgrind"])
        self.assertEqual((s.ex, s.member, s.layer), ("libft", "ft_split", "valgrind"))
        self.assertEqual(s.words(), ["libft", "ft_split", "valgrind"])
        self.assertEqual(s.describe(), "libft ft_split layer valgrind")
        # With no project in scope, a function only one project has is that project's.
        s = self.at("").resolve(["ft_isalpha"])
        self.assertEqual((s.project.rel, s.ex, s.member), (self.LIB, "libft", "ft_isalpha"))
        s = self.at("").resolve(["ft_other"])
        self.assertEqual((s.project.name, s.ex, s.member), ("Other", "other", "ft_other"))
        # A member found from the folder goes with its project, and with its library.
        s = self.at(self.LIB + "/tests/ft_strlen").resolve(["Other"])
        self.assertEqual((s.project.name, s.ex, s.member), ("Other", None, None))
        s = self.at(self.LIB + "/tests/ft_strlen").resolve(["norm"])
        self.assertEqual((s.ex, s.member, s.layer), ("libft", "ft_strlen", "norm"))

    def test_member_word_errors(self):
        for cwd, words, msg in (
                ("", ["ft_strlen"], "ft_strlen of which project"),
                (self.LIB, ["ft_strlen", "ft_split"], "one function at a time")):
            with self.assertRaisesRegex(UsageError, msg, msg=(cwd, words)):
                self.at(cwd).resolve(words)

    def test_a_function_of_another_project_names_that_project(self):
        # Rejected with "'ft_strlen' is not ... a function (ft_strlen)": its
        # own word as the example, and never the project that has it.
        for cwd, words, msg in (
                ("c-piscine/c-piscine-c-05", ["ft_isalpha"],
                 "'ft_isalpha' is a function of libft, not of c-05."),
                ("c-piscine/c-piscine-c-05", ["ft_strlen"],
                 "'ft_strlen' is a function of libft and other, not of c-05."),
                (self.LIB, ["ft_other"],
                 "'ft_other' is a function of other, not of libft.")):
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
        with self.assertRaisesRegex(UsageError, r"a part of libft \(ft_isalpha\)"):
            self.at(self.LIB).resolve(["nonsense"])
        with self.assertRaisesRegex(UsageError, r"a function \(ft_isalpha\)"):
            self.at("c-piscine/c-piscine-c-05").resolve(["nonsense"])
        with self.assertRaisesRegex(UsageError, "Did you mean ft_strlen"):
            self.at(self.LIB).resolve(["ft_strlne"])
        # ...and a checkout with no library offers no function at all.
        bare = tempfile.TemporaryDirectory()
        self.addCleanup(bare.cleanup)
        tree(bare.name, {"tools/units.awk": tool_text("units.awk"), "tools/defs_levels.bzl": LEVELS_BZL,
                         "c-piscine/c-piscine-c-05/BUILD.bazel": PISCINE_BUILD})
        with self.assertRaises(UsageError) as cm:
            Workspace(bare.name, os.path.join(bare.name, "c-piscine/c-piscine-c-05")).resolve(["nonsense"])
        self.assertNotIn("function", str(cm.exception))
        self.assertIn("is not a project, an exercise (ex03) or a layer.", str(cm.exception))

    def test_a_function_folder_is_a_path_word(self):
        # docs/testing.md: "a function's name (ft_strlen) is a word too, and
        # so is its folder of tests". The path word once kept the exercise and
        # dropped the function.
        for cwd, word in (("", self.LIB + "/tests/ft_strlen"),
                          ("", self.LIB + "/tests/ft_strlen/"),
                          (self.LIB, "tests/ft_strlen"),
                          (self.LIB + "/tests", "ft_strlen/test_ft_strlen.c"),
                          ("cursus/Milestone_1/Other", "../../Milestone_0/Libft/tests/ft_strlen")):
            s = self.at(cwd).resolve([word])
            self.assertEqual((s.project.rel, s.ex, s.member), (self.LIB, "libft", "ft_strlen"), (cwd, word))
        s = self.at("").resolve([self.LIB + "/tests/ft_strlen", "valgrind"])
        self.assertEqual((s.ex, s.member, s.layer), ("libft", "ft_strlen", "valgrind"))
        # A function word beside it is the one asked for.
        s = self.at("").resolve([self.LIB + "/tests/ft_strlen", "ft_split"])
        self.assertEqual((s.ex, s.member), ("libft", "ft_split"))
        # A folder that is no unit's is the whole project.
        s = self.at("").resolve([self.LIB + "/tests/layout"])
        self.assertEqual((s.project.rel, s.ex, s.member), (self.LIB, None, None))

    def test_a_layer_no_function_has_names_the_library_command(self):
        # `42 test norm` from a function's folder keeps the function's suite
        # (most layers are per function); when Bazel finds no such test there
        # (exit 4), one line names a command that runs the layer over the
        # whole library. Typed from that same folder, the command must leave
        # the function: one that kept it would select the same empty suite
        # and print the same line again. Nor does the line say the layer "is
        # not tested per function", false of a layer a function only lacks.
        import contextlib
        import io
        import main
        import bazel
        import types
        fn = self.LIB + "/tests/ft_strlen"
        ctx = main.Ctx(self.ws, os.path.join(self.ws, fn), {},
                       types.SimpleNamespace(plain=True, show_bazel=False, dry_run=False))
        out_path = os.path.join(self.ws, "bazel.out")
        tree(self.ws, {"bazel.out": "ERROR: No test targets were found, yet testing was requested\n"})
        here = self.at(fn)
        for layer in ("norm", "valgrind"):
            scope = here.resolve([layer])
            self.assertEqual((scope.ex, scope.member, scope.layer), ("libft", "ft_strlen", layer))
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
            self.assertEqual(words, ["libft", layer])
            # Typed from the folder it is printed in, it leaves the function.
            again = here.resolve(words)
            self.assertEqual(self.W.selection(again, "basic"),
                             (["//%s/..." % self.LIB], layer + ",-manual"), text)
        # No function in scope, or no layer: Bazel's line alone.
        for scope in (workspace.Scope(self.lib, "libft", "norm"),
                      workspace.Scope(self.lib, "libft", member="ft_strlen")):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                main.report_run(ctx, scope, "basic", bazel.NO_TESTS, out_path, None, None, False)
            self.assertNotIn("of its own", buf.getvalue())
            self.assertNotIn("42 test", buf.getvalue())

    def test_a_member_selects_its_suite(self):
        S = workspace.Scope
        self.assertEqual(self.W.selection(S(self.lib, "libft", member="ft_strlen"), "basic"),
                         (["//%s:ft_strlen" % self.LIB], "lvl_basic,-manual"))
        self.assertEqual(self.W.selection(S(self.lib, "libft", member="ft_strlen"), "complete"),
                         (["//%s:ft_strlen" % self.LIB], "-manual"))
        self.assertEqual(self.W.selection(S(self.lib, "libft", "valgrind", member="ft_strlen"), "basic"),
                         (["//%s:ft_strlen" % self.LIB], "valgrind,-manual"))

    def test_42_test_and_submit_take_a_member_word(self):
        from common import run42
        rc, out, err = run42(["test", "ft_strlen", "--dry-run"], cwd=os.path.join(self.ws, self.LIB), ws=self.ws)
        self.assertEqual(rc, 0, err)
        self.assertIn("$ bazel test //%s:ft_strlen --test_tag_filters=lvl_basic,-manual" % self.LIB, out)
        rc, out, err = run42(["submit", "ft_strlen", "--dry-run"], cwd=os.path.join(self.ws, self.LIB), ws=self.ws)
        self.assertEqual(rc, 2, out)
        self.assertIn("42 submit takes a project, not ft_strlen", err)
        # ...and `42 help test` says a part, a library's function among them,
        # is a word: its name.
        rc, out, _ = run42(["help", "test"])
        self.assertIn("    a name  ", out)
        self.assertIn("(ft_strlen)", out)
        self.assertIn("[exNN|name] [layer]", out)
        self.assertIn("one line per exercise or part", out)


# Two contracts of units (units = {...}), written as a project's BUILD file
# writes one: a library whose functions are units of their own, named as its
# folder is (libft's shape), and a project that is one unit.
NAMED_LIB_BUILD = (
    "subject(\n"
    '    grader = "both",\n'
    "    group = False,\n"
    "    units = {\n"
    '        "libtoy": unit(\n'
    "            page = 1,\n"
    '            files = ["Makefile"],\n'
    "            allowed = [],\n"
    "            functions = {\n"
    '                "toy_len": [],\n'
    '                "toy_up": [],\n'
    "            },\n"
    "        ),\n"
    "    },\n"
    ")\n"
    "c_levels()\n")
NAMED_PROG_BUILD = (
    "subject(\n"
    '    grader = "both",\n'
    "    group = False,\n"
    "    units = {\n"
    '        "toy_root": unit(page = 1, files = ["Makefile"], allowed = None),\n'
    "    },\n"
    ")\n"
    "c_levels()\n")


class Named(unittest.TestCase):
    """Projects whose subject names its parts (units = {...}): each unit is a word
    of its own, a project word is the whole project, and exNN is none of them."""

    LIB = "cursus/Milestone_9/Libtoy"
    PROG = "cursus/Milestone_9/Toyprog"

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.ws = self.tmp.name
        tree(self.ws, {
            "tools/units.awk": tool_text("units.awk"),
            "tools/defs_levels.bzl": LEVELS_BZL,
            "c-piscine/c-piscine-c-05/BUILD.bazel": PISCINE_BUILD,
            self.LIB + "/BUILD.bazel": NAMED_LIB_BUILD,
            self.LIB + "/deliverable/toy_len.c": "",
            self.LIB + "/tests/libtoy/prototype.h": "",
            self.LIB + "/tests/toy_len/deeper/x.txt": "",
            self.LIB + "/tests/layout/x.h": "",
            self.PROG + "/BUILD.bazel": NAMED_PROG_BUILD,
            self.PROG + "/tests/toy_root/empty.txt": "",
        })
        self.W = Workspace(self.ws, self.ws)
        self.lib = self.W.project_named("libtoy")
        self.prog = self.W.project_named("toyprog")

    def at(self, rel):
        return Workspace(self.ws, os.path.join(self.ws, rel))

    def test_a_contract_of_units(self):
        self.assertEqual((self.lib.rel, self.prog.rel), (self.LIB, self.PROG))
        self.assertTrue(self.lib.named() and self.prog.named())
        self.assertFalse(self.W.project_named("c-05").named())
        self.assertEqual(self.lib.exercises(), [])
        self.assertEqual(self.lib.wholes(), ["libtoy"])
        self.assertEqual(self.lib.members("libtoy"), ["toy_len", "toy_up"])
        self.assertEqual((self.lib.kind("libtoy"), self.lib.kind("toy_len"), self.lib.kind("ex00")),
                         ("library", "function", None))
        self.assertEqual((self.lib.turnin("libtoy"), self.lib.turnin("toy_len")), ("deliverable", ""))
        self.assertEqual(self.prog.wholes(), ["toy_root"])

    def test_a_units_folder_is_that_unit(self):
        L, R = self.LIB, self.PROG
        cases = {
            L: (None, None),
            L + "/deliverable": (None, None),  # every unit turns in there: the whole project
            L + "/deliverable/toy_len.c": (None, None),
            L + "/tests": (None, None),
            L + "/tests/libtoy": ("libtoy", None),
            L + "/tests/toy_len": ("libtoy", "toy_len"),
            L + "/tests/toy_len/deeper/x.txt": ("libtoy", "toy_len"),
            L + "/tests/layout": (None, None),  # no unit's folder
            R + "/tests/toy_root": ("toy_root", None),
        }
        for rel, want in cases.items():
            s = self.W.scope_of_path(os.path.join(self.ws, rel))
            self.assertEqual((s.project.rel, s.ex, s.member), (rel.split("/tests")[0].split("/deliverable")[0],)
                             + want, rel)

    def test_unit_words(self):
        L = self.LIB
        for cwd, words, want in (
                ("", ["libtoy"], (L, None, None)),
                ("", ["libtoy", "libtoy"], (L, "libtoy", None)),
                ("", ["libtoy", "toy_len"], (L, "libtoy", "toy_len")),
                ("", ["toy_len", "libtoy"], (L, "libtoy", "toy_len")),
                ("", ["toy_len"], (L, "libtoy", "toy_len")),
                ("", [L + "/tests/toy_len"], (L, "libtoy", "toy_len")),
                ("", ["toy_root"], (self.PROG, "toy_root", None)),
                (L, [], (L, None, None)),
                (L + "/tests/toy_len", [], (L, "libtoy", "toy_len")),
                (L + "/tests/toy_len", ["toy_up"], (L, "libtoy", "toy_up")),
                (L + "/tests/toy_len", ["libtoy"], (L, None, None)),  # a project word is all of it
                (L + "/tests/toy_len", ["libtoy", "libtoy"], (L, "libtoy", None)),
                (L + "/tests/libtoy", ["toy_len"], (L, "libtoy", "toy_len")),
                ("c-piscine/c-piscine-c-05", ["libtoy"], (L, None, None))):
            s = self.at(cwd).resolve(words)
            self.assertEqual((s.project.rel, s.ex, s.member), want, (cwd, words))
        s = self.at(L + "/tests/toy_len").resolve(["valgrind"])
        self.assertEqual((s.ex, s.member, s.layer), ("libtoy", "toy_len", "valgrind"))
        self.assertEqual(s.words(), ["libtoy", "toy_len", "valgrind"])
        self.assertEqual(s.describe(), "libtoy toy_len layer valgrind")
        s = self.at("").resolve(["libtoy", "libtoy", "norm"])
        self.assertEqual(s.words(), ["libtoy", "libtoy", "norm"])

    def test_words_that_are_no_unit_of_it_are_said(self):
        for cwd, words, said in (
                ("", ["libtoy", "ex00"],
                 "ex00 is not a part of libtoy; `42 units libtoy` lists them."),
                (self.LIB + "/tests/toy_len", ["ex00"],
                 "ex00 is not a part of libtoy; `42 units libtoy` lists them."),
                ("", ["libtoy", "toy_len", "toy_up"], "one function at a time: toy_len and toy_up."),
                # An exNN is no part of it, whatever words come after it.
                ("", ["libtoy", "ex00", "toy_len", "toy_up"],
                 "ex00 is not a part of libtoy; `42 units libtoy` lists them."),
                ("", ["libtoy", "ex00", "libtoy", "toy_len"],
                 "ex00 is not a part of libtoy; `42 units libtoy` lists them."),
                ("", ["toyprog", "toy_root", "libtoy"], "one project at a time: toyprog and libtoy."),
                ("", ["libtoy", "toy_root"], "'toy_root' is a part of toyprog, not of libtoy."),
                ("c-piscine/c-piscine-c-05", ["toy_len"], "'toy_len' is a function of libtoy, not of c-05."),
                ("", ["c-05", "libtoy"], "one project at a time: c-05 and libtoy.")):
            with self.assertRaises(UsageError, msg=(cwd, words)) as cm:
                self.at(cwd).resolve(words)
            self.assertEqual(str(cm.exception), said, (cwd, words))
        with self.assertRaises(UsageError) as cm:
            self.at("").resolve(["libtoy", "toy_lne"])
        self.assertIn("'toy_lne' is not a project, a part of libtoy (toy_len) or a layer. Did you mean toy_len or toy_up?",
                      str(cm.exception))
        # A project with no function of its own shows one of its parts,
        # never another project's function.
        with self.assertRaises(UsageError) as cm:
            self.at(self.PROG).resolve(["nonsense"])
        self.assertIn("'nonsense' is not a project, a part of toyprog (toy_root) or a layer.", str(cm.exception))

    def test_a_unit_selects_its_suite(self):
        S = workspace.Scope
        L = "//" + self.LIB
        self.assertEqual(self.W.selection(S(self.lib), "basic"), ([L + "/..."], "lvl_basic,-manual"))
        self.assertEqual(self.W.selection(S(self.lib, "libtoy"), "basic"), ([L + ":libtoy"], "lvl_basic,-manual"))
        self.assertEqual(self.W.selection(S(self.lib, "libtoy", "norm", member="toy_len"), "basic"),
                         ([L + ":toy_len"], "norm,-manual"))

    def test_42_dry_runs(self):
        from common import run42
        L = self.LIB
        for cwd, argv, want in (
                ("", ["test", "libtoy", "toy_len"], "$ bazel test //%s:toy_len --test_tag_filters=lvl_basic,-manual"),
                ("", ["test", "libtoy", "libtoy"], "$ bazel test //%s:libtoy --test_tag_filters=lvl_basic,-manual"),
                ("", ["test", "libtoy"], "$ bazel test //%s/... --test_tag_filters=lvl_basic,-manual"),
                (L + "/tests/toy_len", ["test"], "$ bazel test //%s:toy_len --test_tag_filters=lvl_basic,-manual"),
                (L + "/tests/toy_len", ["norm"], "$ bazel test //%s:libtoy --test_tag_filters=norm,-manual")):
            rc, out, err = run42(argv + ["--dry-run"], cwd=os.path.join(self.ws, cwd), ws=self.ws)
            self.assertEqual(rc, 0, (argv, err))
            self.assertIn(want % L, out, argv)
        # 42 submit takes each word alone, and a project's: a unit is no project.
        for argv, said in ((["submit", "toy_root"], "42 submit takes a project, not toy_root."),
                           (["submit", "libtoy", "toy_len"], "42 submit takes a project, not toy_len.")):
            rc, out, err = run42(argv + ["--dry-run"], ws=self.ws)
            self.assertEqual(rc, 2, out)
            self.assertIn(said, err)
        for cwd, argv in ((L + "/tests/toy_len", ["submit"]), ("", ["submit", "libtoy", "libtoy"])):
            rc, out, err = run42(argv + ["--dry-run"], cwd=os.path.join(self.ws, cwd), ws=self.ws)
            self.assertEqual(rc, 0, err)
            self.assertIn("$ bazel run //tools:submit -- %s" % L, out)
        # A user file 42 cannot read, where it would decide the level: each
        # command stops, and names only a way out it takes.
        with tempfile.TemporaryDirectory() as home:
            os.makedirs(os.path.join(home, ".config", "42"))
            with open(os.path.join(home, ".config", "42", "config.yaml"), "w") as f:
                f.write("level: no\n")
            for argv, flag in ((["test"], True), (["norm"], False), (["submit"], True)):
                rc, out, err = run42(argv + ["--dry-run"], cwd=os.path.join(self.ws, L, "tests/toy_len"),
                                     environ={"HOME": home}, ws=self.ws)
                flat = " ".join(err.split())
                self.assertEqual(rc, 2, (argv, out, err))
                self.assertIn("YAML reads no as true or false", flat)
                self.assertIn("`42 config set level LEVEL`", flat)
                self.assertEqual("--level" in flat, flag, (argv, flat))

    def test_a_layer_no_function_has_names_the_whole_project(self):
        # A library's own suite holds none of its functions' tests, so the
        # command that runs the layer over all of it names the project.
        import contextlib
        import io
        import main
        import bazel
        import types
        fn = self.LIB + "/tests/toy_len"
        ctx = main.Ctx(self.ws, os.path.join(self.ws, fn), {},
                       types.SimpleNamespace(plain=True, show_bazel=False, dry_run=False))
        tree(self.ws, {"bazel.out": "ERROR: No test targets were found, yet testing was requested\n"})
        scope = self.at(fn).resolve(["valgrind"])
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            main.report_run(ctx, scope, "basic", bazel.NO_TESTS, os.path.join(self.ws, "bazel.out"),
                            None, None, False)
        self.assertIn("  toy_len has no valgrind test of its own. To run valgrind over all of libtoy: "
                      "42 test libtoy valgrind\n", buf.getvalue())

    def test_what_first_red_names_next_is_a_word_of_42_clues(self):
        import main
        import types
        ctx = types.SimpleNamespace(W=self.W)
        L, C = "//" + self.LIB, "//c-piscine/c-piscine-c-05"
        self.assertTrue(main.is_unit_word(ctx, L, "toy_len"))
        self.assertTrue(main.is_unit_word(ctx, L, "libtoy"))
        self.assertFalse(main.is_unit_word(ctx, L, "deliverable_files"))
        self.assertTrue(main.is_unit_word(ctx, C, "ex00"))
        self.assertFalse(main.is_unit_word(ctx, C, "deliverable_files"))
        self.assertEqual(main.library_members(ctx, L, "libtoy"), ["toy_len", "toy_up"])
        self.assertEqual(main.library_members(ctx, L, "toy_len"), [])
        self.assertEqual(main.library_members(ctx, C, "ex00"), [])

    def test_the_clues_of_a_functions_log_are_that_functions(self):
        # A library's own suite holds none of its functions' tests: the log of
        # one function's test sends to that function's clues, and the log of
        # one of the library's own tests to the library's.
        import contextlib
        import io
        import main
        import bazel
        import types
        L = "//" + self.LIB
        ctx = main.Ctx(self.ws, self.ws, {}, types.SimpleNamespace(plain=True, show_bazel=False, dry_run=False))
        log = os.path.join(self.ws, "test.log")
        tree(self.ws, {"test.log": " HINTS:\n   * Why?\n (3 more hidden hints: run with --test_env=CLUE_MODE=all)\n",
                       "next.tsv": "build\t%s\tlibtoy\t-\n" % L})
        for red, said, unit in ((L + ":toy_up_output", "more hints: 42 clues libtoy toy_up", ("libtoy", "toy_up")),
                                (L + ":libtoy_norm", "more hints: 42 clues libtoy libtoy", ("libtoy", None))):
            b = bazel.Bep()
            b.selected.append(red)
            b.tags[red] = ["output"]
            b.status[red] = "FAILED"
            b.logs[red] = log
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                main.show_next_log(ctx, None, b, os.path.join(self.ws, "next.tsv"))
            self.assertIn("THE LOG OF " + red, buf.getvalue())
            self.assertIn(said, buf.getvalue(), red)
            # Typed, the words name the unit whose test the log is.
            scope = self.W.resolve(said.split("42 clues ")[1].split())
            self.assertEqual((scope.ex, scope.member), unit, red)


class Units(unittest.TestCase):
    """42 reads a contract through tools/units.awk alone. Each case writes a
    units.awk of its own, so what 42 shows can only have come from running it."""

    C05 = "c-piscine/c-piscine-c-05"

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.ws = self.tmp.name
        tree(self.ws, {"tools/defs_levels.bzl": LEVELS_BZL, self.C05 + "/BUILD.bazel": PISCINE_BUILD})
        os.makedirs(os.path.join(self.ws, self.C05, "tests", "ex00"))

    def awk(self, program):
        tree(self.ws, {"tools/units.awk": program})
        return Workspace(self.ws, self.ws).project_named("c-05")

    def test_the_rows_are_units_awks(self):
        # The BUILD file says exercise "00"; units.awk says a library, and 42
        # says what it says.
        p = self.awk('BEGIN { printf "libzz\\tlibrary\\t-\\tdeliverable/zz\\tfolder\\t-\\n"\n'
                     '        printf "ft_a\\tfunction\\t-\\tdeliverable/zz\\tdefines\\tlibzz\\n"; exit 0 }\n')
        self.assertEqual(p.units(), [Unit("libzz", "library", "-", "deliverable/zz", "folder", "-"),
                                     Unit("ft_a", "function", "-", "deliverable/zz", "defines", "libzz")])
        self.assertEqual((p.exercises(), p.wholes()), ([], ["libzz"]))
        self.assertEqual(p.members("libzz"), ["ft_a"])
        self.assertEqual(p.turnin("libzz"), "deliverable/zz")
        self.assertEqual(p.turnin("ex00"), "")
        self.assertEqual(p.turnin("ft_a"), "")  # a function has its library's folder, and none of its own

    def test_a_line_it_cannot_read_is_said_with_its_place(self):
        # Never read as no exercise: the student is told which line, and
        # Bazel never starts.
        from common import run42
        from test_main import Env
        p = self.awk('BEGIN { print "units.awk: " ARGV[1] ":3: a line of exercises it cannot read" | "cat 1>&2"\n'
                     '        exit 2 }\n')
        said = "units.awk: %s/BUILD.bazel:3: a line of exercises it cannot read" % self.C05
        with self.assertRaises(ContractError) as cm:
            p.units()
        self.assertEqual(str(cm.exception), said)
        env = Env()
        self.addCleanup(env.close)
        rc, out, err = run42(["test", "--dry-run"], os.path.join(self.ws, self.C05, "tests", "ex00"),
                             env.environ, ws=self.ws)
        self.assertEqual((rc, out, err), (2, "", "42: %s\n" % said))
        self.assertEqual(env.called(), "")

    def test_rows_that_are_no_units_are_refused(self):
        for rows in ("ex00\\texercise\\n",
                     "ex00\\tthing\\t-\\tdeliverable\\tfolder\\t-\\n",
                     "ex00\\texercise\\t-\\tdeliverable\\tfolder\\t-\\n\\n"):
            p = self.awk('BEGIN { printf "%s"; exit 0 }\n' % rows)
            with self.assertRaisesRegex(ContractError, "not NAME KIND REQ FOLDER JUDGE LIB", msg=rows):
                p.units()

    def test_exit_1(self):
        # Silent, it is a file with no subject( call: no units. Said, it is
        # an awk that failed (busybox exits 1 on its own errors).
        self.assertEqual(self.awk("BEGIN { exit 1 }\n").units(), [])
        p = self.awk('BEGIN { print "awk: boom" | "cat 1>&2"; exit 1 }\n')
        with self.assertRaisesRegex(ContractError, "awk: boom"):
            p.units()

    def test_no_awk_is_said(self):
        self.awk("BEGIN { exit 0 }\n")
        empty = os.path.join(self.ws, "no-awk")
        os.makedirs(empty)
        p = Workspace(self.ws, self.ws, {"PATH": empty}).project_named("c-05")
        with self.assertRaisesRegex(ContractError, "cannot run awk"):
            p.units()


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
