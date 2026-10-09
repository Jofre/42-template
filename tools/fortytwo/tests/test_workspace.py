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


class Projects(unittest.TestCase):
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

    def test_short_name_rule(self):
        self.assertEqual(workspace.short_name("//c-piscine/c-piscine-c-05"), "c-05")
        self.assertEqual(workspace.short_name("//c-piscine-reloaded/c-piscine-reloaded"), "reloaded")
        self.assertEqual(workspace.short_name("//cursus/libft"), "cursus/libft")

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
                (["ex01", "ex02"], "one exercise at a time")):
            with self.assertRaisesRegex(UsageError, msg):
                W.resolve(words)
        with self.assertRaisesRegex(UsageError, "of which project"):
            Workspace(WS, WS).resolve(["ex03"])


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
