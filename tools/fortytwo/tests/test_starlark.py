"""starlark.py: the query it asks, what it reads back, and the macros it knows.

No Bazel here: the queries are checked as text, and --dry-run is checked to
start nothing (test_main.Env's stand-in writes down any call).
"""

import ast
import os
import unittest

from common import WS
import starlark
import workspace
from test_main import Case, EX03, C05

# The calls a project's BUILD file makes that declare no test: Bazel's own,
# the subject() contract, and the macros that wire a file or a library.
NOT_TESTS = {"load", "subject", "exports_files", "sh_binary", "c_twin", "student_lib"}

TAG = '"[\\[ ]%s[,\\]]"'


class Expression(unittest.TestCase):
    def test_a_level(self):
        e = starlark.expression(["//p:ex03"], "lvl_basic,-manual")
        self.assertEqual(e, "attr(tags, %s, tests(//p:ex03)) except attr(tags, %s, tests(//p:ex03))"
                         % (TAG % "lvl_basic", TAG % "manual"))

    def test_complete_and_a_label(self):
        self.assertEqual(starlark.expression(["//p/..."], "-manual"),
                         "tests(//p/...) except attr(tags, %s, tests(//p/...))" % (TAG % "manual"))
        self.assertEqual(starlark.expression(["//p:ex03_output"], None), "tests(//p:ex03_output)")

    def test_two_tags_keep_either(self):
        self.assertEqual(starlark.expression(["//p"], "a,b"),
                         "(attr(tags, %s, tests(//p)) + attr(tags, %s, tests(//p)))" % (TAG % "a", TAG % "b"))


class Locations(unittest.TestCase):
    def test_parse(self):
        lines = [
            "%s/c-piscine/c-piscine-c-05/BUILD.bazel:66:11: sh_test rule //c-piscine/c-piscine-c-05:ex03_norm" % WS,
            "Loading: 0 packages loaded",
            "/elsewhere/BUILD.bazel:3:1: sh_test rule //x:y",
        ]
        self.assertEqual(starlark.locations(lines, WS), {
            "//c-piscine/c-piscine-c-05:ex03_norm": ("c-piscine/c-piscine-c-05/BUILD.bazel", 66),
            "//x:y": ("/elsewhere/BUILD.bazel", 3),
        })


class Macros(unittest.TestCase):
    """Every call a project's BUILD file makes is a macro the view knows, or one that declares no test."""

    def calls(self, path):
        with open(path, encoding="utf-8") as f:
            tree = ast.parse(f.read(), path)
        out = set()

        def take(node):
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
                out.add(node.func.id)
            elif isinstance(node, (ast.ListComp, ast.GeneratorExp)):
                take(node.elt)
        for stmt in tree.body:
            if isinstance(stmt, ast.Expr):
                take(stmt.value)
            elif isinstance(stmt, ast.For):
                for s in stmt.body:
                    if isinstance(s, ast.Expr):
                        take(s.value)
        return out

    def test_every_call(self):
        projects = workspace.Workspace(WS, WS).projects()
        self.assertGreater(len(projects), 10)
        unknown = {}
        for p in projects:
            for name in self.calls(os.path.join(WS, p.rel, "BUILD.bazel")):
                if name not in starlark.MACROS and name not in NOT_TESTS:
                    unknown.setdefault(name, []).append(p.short)
        self.assertEqual(unknown, {}, "a call --show_starlark does not know: add it to "
                         "starlark.MACROS if it declares tests, else to NOT_TESTS here")

    def test_no_name_twice(self):
        self.assertEqual(len(set(starlark.MACROS)), len(starlark.MACROS))
        self.assertFalse(set(starlark.MACROS) & NOT_TESTS)


class DryRun(Case):
    def test_it_prints_the_location_query_and_starts_nothing(self):
        rc, out, err = self.run42(["test", "--show_starlark", "--dry-run"], EX03)
        self.assertEqual(rc, 0, err)
        self.assertIn("$ bazel query ", out)
        self.assertIn("tests(//%s:ex03)" % C05, out)
        self.assertIn("--output=location", out)
        self.assertNotIn("--output=build", out)


if __name__ == "__main__":
    unittest.main()
