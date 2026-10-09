"""taint.py: the files a scope watches, their snapshots, and the contents a run could not vouch for."""

import os
import tempfile
import unittest

import common  # noqa: F401  (puts tools/fortytwo on sys.path)
import taint


class FakeProject:
    """The two things watched_files asks of a project."""

    def __init__(self, path, turnins):
        self.path = path
        self._turnins = turnins

    def turnin(self, ex):
        return self._turnins.get(ex)


def touch(path, text="x"):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


class Watched(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        self.p = FakeProject(self.root, {"ex00": "deliverable/ex00", "ex01": "deliverable"})

    def tearDown(self):
        self.tmp.cleanup()

    def rel(self, paths):
        return sorted(os.path.relpath(p, self.root) for p in paths)

    def test_an_exercise_watches_its_turn_in_folder_and_generator(self):
        touch(os.path.join(self.root, "deliverable/ex00/a.c"))
        touch(os.path.join(self.root, "deliverable/ex00/sub/b.h"))
        touch(os.path.join(self.root, "deliverable/ex02/c.c"))
        touch(os.path.join(self.root, "generators/ex00.sh"))
        touch(os.path.join(self.root, "generators/ex02.sh"))
        self.assertEqual(self.rel(taint.watched_files(self.p, "ex00")),
                         ["deliverable/ex00/a.c", "deliverable/ex00/sub/b.h", "generators/ex00.sh"])

    def test_a_project_watches_every_turn_in_and_generator(self):
        touch(os.path.join(self.root, "deliverable/ex00/a.c"))
        touch(os.path.join(self.root, "generators/ex03.sh"))
        touch(os.path.join(self.root, "tests/ex00/expected"))
        self.assertEqual(self.rel(taint.watched_files(self.p)),
                         ["deliverable/ex00/a.c", "generators/ex03.sh"])

    def test_editor_temp_files_and_hidden_folders_are_not_turn_ins(self):
        d = os.path.join(self.root, "deliverable/ex00")
        for name in ("a.c", ".a.c.swp", ".a.c.swx", ".a.c.svz", "a.c~", "4913", ".#a.c", "#a.c#", "a.c.tmp"):
            touch(os.path.join(d, name))
        touch(os.path.join(d, ".git/x"))
        self.assertEqual(self.rel(taint.watched_files(self.p, "ex00")), ["deliverable/ex00/a.c"])

    def test_a_file_created_or_deleted_is_seen(self):
        a = os.path.join(self.root, "deliverable/ex00/a.c")
        touch(a)
        before = taint.snapshot(taint.watched_files(self.p, "ex00"))
        b = os.path.join(self.root, "deliverable/ex00/b.c")
        touch(b)
        os.remove(a)
        after = taint.snapshot(taint.watched_files(self.p, "ex00"))
        self.assertEqual(sorted(taint.raced(before, {}, after, {})), sorted([a, b]))

    def test_a_missing_turn_in_folder_watches_nothing(self):
        self.assertEqual(taint.watched_files(self.p, "ex00"), [])


class Snapshots(unittest.TestCase):
    def test_contents_not_times(self):
        with tempfile.TemporaryDirectory() as d:
            f = os.path.join(d, "a.c")
            touch(f, "one")
            s1 = taint.snapshot([f])
            os.utime(f, (1, 1))
            self.assertEqual(taint.snapshot([f]), s1)
            touch(f, "two")
            self.assertNotEqual(taint.snapshot([f]), s1)
            self.assertNotEqual(taint.stat_key(f), None)
            os.remove(f)
            self.assertEqual(taint.snapshot([f]), {f: None})
            self.assertEqual(taint.stat_key(f), None)


class Raced(unittest.TestCase):
    """What a run leaves tainted: every content of a file it saw change, or saw saved."""

    def test_a_still_file_taints_nothing(self):
        self.assertEqual(taint.raced({"/f": "B"}, {"/f": (1, 1, 1)}, {"/f": "B"}, {"/f": (1, 1, 1)}), {})

    def test_contents_that_changed_taint_both(self):
        self.assertEqual(taint.raced({"/f": "B"}, {"/f": (1, 1, 1)}, {"/f": "A"}, {"/f": (2, 1, 1)}),
                         {"/f": ["B", "A"]})

    def test_an_undo_during_the_run_taints_the_contents_it_came_back_to(self):
        # B, then A, then B again while Bazel ran. The contents are the
        # same at both ends, but the build may have read A under B's name.
        self.assertEqual(taint.raced({"/f": "B"}, {"/f": (1, 9, 1)}, {"/f": "B"}, {"/f": (2, 9, 1)}),
                         {"/f": ["B"]})

    def test_a_file_created_or_deleted(self):
        self.assertEqual(taint.raced({}, {}, {"/new": "N"}, {"/new": (1, 1, 1)}), {"/new": ["N"]})
        self.assertEqual(taint.raced({"/gone": "G"}, {"/gone": (1, 1, 1)}, {"/gone": None}, {"/gone": None}),
                         {"/gone": ["G"]})


class Store(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.env = {"XDG_STATE_HOME": os.path.join(self.tmp.name, "state"), "HOME": self.tmp.name}
        self.ws = os.path.join(self.tmp.name, "ws")
        os.makedirs(self.ws)

    def tearDown(self):
        self.tmp.cleanup()

    def test_state_lives_outside_the_checkout_one_folder_per_checkout(self):
        d = taint.state_dir(self.ws, self.env)
        self.assertTrue(d.startswith(self.env["XDG_STATE_HOME"] + os.sep + "42" + os.sep))
        other = os.path.join(self.tmp.name, "ws2")
        os.makedirs(other)
        self.assertNotEqual(d, taint.state_dir(other, self.env))
        self.assertTrue(taint.state_dir(self.ws, {"HOME": "/h"}).startswith("/h/.local/state/42/"))

    def test_add_hit_clear_and_persist(self):
        t = taint.Taint(self.ws, self.env)
        t.add("/f", "h1")
        t.add("/f", None)
        self.assertEqual(t.hits({"/f": "h1", "/g": "h1"}), ["/f"])
        self.assertEqual(t.hits({"/f": "h2"}), [])
        self.assertEqual(t.hits({"/f": None}), [])
        t.save()
        t2 = taint.Taint(self.ws, self.env)
        self.assertEqual(t2.hits({"/f": "h1"}), ["/f"])
        t2.discharge("/f", "h1")
        t2.save()
        self.assertEqual(taint.Taint(self.ws, self.env).hits({"/f": "h1"}), [])
        self.assertEqual(taint.Taint(self.ws, self.env).data, {})

    def test_a_discharge_keeps_the_other_contents_of_the_file(self):
        t = taint.Taint(self.ws, self.env)
        t.add("/f", "before")
        t.add("/f", "after")
        t.discharge("/f", "after")
        t.discharge("/f", "never-seen")
        self.assertEqual(t.hits({"/f": "before"}), ["/f"])
        self.assertEqual(t.hits({"/f": "after"}), [])

    def test_only_the_last_eight_contents_are_kept(self):
        t = taint.Taint(self.ws, self.env)
        for i in range(10):
            t.add("/f", "h%d" % i)
        t.add("/f", "h9")
        self.assertEqual(t.hits({"/f": "h0"}), [])
        self.assertEqual(t.hits({"/f": "h2"}), ["/f"])
        self.assertEqual(len(t.data["/f"]), 8)

    def test_a_damaged_file_is_an_empty_store(self):
        t = taint.Taint(self.ws, self.env)
        os.makedirs(os.path.dirname(t.path))
        with open(t.path, "w") as f:
            f.write("{not json")
        self.assertEqual(taint.Taint(self.ws, self.env).data, {})


if __name__ == "__main__":
    unittest.main()
