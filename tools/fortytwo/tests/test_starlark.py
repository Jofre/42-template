"""starlark.py: the query it asks, what it reads back, and the macros it knows.

No Bazel here: the queries are checked as text, and --dry-run is checked to
start nothing (test_main.Env's stand-in writes down any call).
"""

import ast
import os
import tempfile
import unittest

from common import WS
import starlark
import workspace
from test_main import Case, EX03, C05

# The calls a project's BUILD file makes that declare no test: Bazel's own,
# the subject() contract, and the macros that wire a file or a library.
NOT_TESTS = {"load", "subject", "exports_files", "sh_binary", "c_twin", "student_lib"}

# The calls made for the value they return -- an argument of another call, or
# the right side of an assignment -- and which declare no test, each with why.
VALUE_HELPERS = {
    "dict": "Starlark's own: a dictionary",
    "glob": "Bazel's own: a list of the package's files",
    "package_name": "Bazel's own: the package's path",
    "exercise": "one exercise's header box, inside subject()",
    "unit": "one unit's header box, inside subject()",
    "turnin_file": "a turn-in file's path, read from the contract",
    "rush_owed": "the rush0N.c files a team owes, from its team.bzl",
    "output_gate": "a corpus replay's (args, data) gate on an output test",
    "stderr_ignored": "a corpus runner's --stderr-ignored argument",
    "runner_quotes": "a runner's quoting args; it declares a names_file, which is no test",
}

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
        """The name of every call the file makes to a plain name, wherever it is.

        A bare statement, the right side of an assignment, a comprehension, an
        argument of another call: a test-declaring macro called as
        `X = some_macro(...)` declares its tests all the same. It used to read
        only bare statements, and the bodies of top-level for loops, which a
        BUILD file has none of.
        """
        with open(path, encoding="utf-8") as f:
            tree = ast.parse(f.read(), path)
        return {n.func.id for n in ast.walk(tree)
                if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)}

    def test_a_call_anywhere_is_seen(self):
        # A macro's tests are declared wherever it is called: on the right of
        # an assignment and inside a comprehension as much as on its own line.
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "BUILD.bazel")
            with open(path, "w", encoding="utf-8") as f:
                f.write('c_program(name = "a")\n'
                        'X = new_test_macro(name = "b")\n'
                        'G = {n: other_test_macro(name = n) for n in ["c"]}\n'
                        '[listed(name = n) for n in ["d"]]\n')
            self.assertLessEqual({"c_program", "new_test_macro", "other_test_macro", "listed"},
                                 self.calls(path))

    def test_every_call(self):
        projects = workspace.Workspace(WS, WS).projects()
        self.assertGreater(len(projects), 10)
        unknown = {}
        for p in projects:
            for name in self.calls(os.path.join(WS, p.rel, "BUILD.bazel")):
                if name not in starlark.MACROS and name not in NOT_TESTS and name not in VALUE_HELPERS:
                    unknown.setdefault(name, []).append(p.short)
        self.assertEqual(unknown, {}, "a call --show_starlark does not know: add it to "
                         "starlark.MACROS if it declares tests, else to NOT_TESTS here, "
                         "or to VALUE_HELPERS, with why, if it is called for its value")

    def test_no_name_twice(self):
        self.assertEqual(len(set(starlark.MACROS)), len(starlark.MACROS))
        self.assertFalse(set(starlark.MACROS) & NOT_TESTS)
        self.assertFalse(set(starlark.MACROS) & set(VALUE_HELPERS))
        self.assertFalse(NOT_TESTS & set(VALUE_HELPERS))


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
