"""userconfig.py: where the user file lives, the grammar it is read in, and every way it is written.

No case reads this machine's own ~/.config/42: each env names a folder of the
test's, and os.environ is never what decides a path.
"""

import ast
import errno
import fcntl
import os
import stat
import tempfile
import unittest
from unittest import mock

from common import WS
import userconfig
from userconfig_corpus import CASES, NAMES, Refused


class Location(unittest.TestCase):
    def test_xdg_config_home_then_home_then_none(self):
        for env, want in (
                ({"XDG_CONFIG_HOME": "/x", "HOME": "/h"}, "/x/42"),
                ({"XDG_CONFIG_HOME": "/x/", "HOME": "/h"}, "/x/42"),
                ({"XDG_CONFIG_HOME": "/", "HOME": "/h"}, "/42"),
                ({"XDG_CONFIG_HOME": "", "HOME": "/h"}, "/h/.config/42"),
                ({"XDG_CONFIG_HOME": "rel", "HOME": "/h"}, "/h/.config/42"),
                ({"HOME": "/h"}, "/h/.config/42"),
                ({"HOME": "/h/"}, "/h/.config/42"),
                ({"HOME": "/"}, "/.config/42"),
                ({"XDG_CONFIG_HOME": "/x"}, "/x/42")):
            self.assertEqual(userconfig.config_dir(env), (want, None), env)
            self.assertEqual(userconfig.path(env), want + "/config.yaml", env)

    def test_no_absolute_home_is_no_user_file_and_says_why(self):
        for env, why in (({}, "HOME is not set"), ({"HOME": ""}, "HOME is not set"),
                         ({"HOME": "rel"}, "HOME=rel is no absolute path"),
                         ({"XDG_CONFIG_HOME": "rel"}, "HOME is not set")):
            folder, said = userconfig.config_dir(env)
            self.assertIsNone(folder, env)
            self.assertIn(why, said)
            self.assertIsNone(userconfig.path(env))
            self.assertIsNone(userconfig.load(env).path)

    def test_only_the_env_given_decides_never_os_environ(self):
        with mock.patch.dict(os.environ, {"HOME": "/elsewhere", "XDG_CONFIG_HOME": "/elsewhere"}):
            self.assertEqual(userconfig.config_dir({})[0], None)
            self.assertEqual(userconfig.config_dir({"HOME": "/h"})[0], "/h/.config/42")

    def test_a_relative_xdg_config_home_is_named_as_ignored(self):
        self.assertEqual(userconfig.notes({"XDG_CONFIG_HOME": "/x"}), [])
        self.assertEqual(userconfig.notes({}), [])
        [note] = userconfig.notes({"XDG_CONFIG_HOME": "cfg"})
        self.assertIn("XDG_CONFIG_HOME=cfg is no absolute path", note)

    def test_the_files_it_may_hold_are_one_table(self):
        self.assertEqual([f for f, _ in userconfig.FILES], ["config.yaml", "credentials.yaml"])
        self.assertEqual(userconfig.path({"HOME": "/h"}, "credentials.yaml"), "/h/.config/42/credentials.yaml")

    def test_only_userconfig_names_where_the_file_lives(self):
        # One resolver: a second place that computes the folder is a second
        # thing to keep in step with the spec and with this one.
        here = os.path.join(WS, "tools", "fortytwo")
        others = []
        for name in sorted(os.listdir(here)):
            if name.endswith(".py") and name != "userconfig.py":
                with open(os.path.join(here, name), encoding="utf-8") as f:
                    text = f.read()
                if "XDG_CONFIG_HOME" in text or ".config/42" in text or '".config"' in text:
                    others.append(name)
        self.assertEqual(others, [])


def read(data):
    """What userconfig.parse makes of data, as CASES writes it."""
    try:
        return {k: v for k, (v, _) in userconfig.parse(data).items()}
    except userconfig.Bad as e:
        return Refused(e.n, e.why)


class Grammar(unittest.TestCase):
    def test_every_case(self):
        for label, data, want in CASES:
            got = read(data)
            if isinstance(want, Refused):
                self.assertIsInstance(got, Refused, label)
                self.assertEqual(got.line, want.line, (label, got))
                self.assertIn(want.words, got.words, label)
            else:
                self.assertEqual(got, want, label)

    def test_the_line_of_each_entry(self):
        self.assertEqual(userconfig.parse(b"# c\n\na: x\nb: w\n"), {"a": ("x", 3), "b": ("w", 4)})

    def test_every_name_42_has_is_a_name_here(self):
        for n in NAMES:
            self.assertEqual(read(("%s: x\n" % n).encode()), {n: "x"})

    def test_a_refusal_says_how_to_write_it(self):
        for data, fix in ((b"a: no\n", '"no"'), (b"a: 0755\n", "double quotes"), (b"a:\tx\n", "use spaces"),
                          (b"  a: x\n", "one `name: value` per line"), (b"a:\n", "`a: VALUE`")):
            self.assertIn(fix, read(data).words, data)


# Values a setting could hold, each awkward to some YAML.
AWKWARD = ["strict", "no", "NO", "y", "~", "null", "", " ", "0", "0755", "012", "1_0", "12:30", "2026-10-23",
           "1e3", ".inf", "-1", "+1", "0x1f", "1.5", "a b", "a #b", "a#b", "#a", "a:", "a: b", "a,b", "[a]",
           "{a: b}", "&a", "*a", "!a", "|", ">", "@a", "%a", "`a`", "?a", "-", "- a", "'", '"', "\\", "\\n",
           "\t", "\n", "\r", "\x00", "\x7f", "\x85", "\u2028", "\u2029", "\ufeff", "\ufffe", "\u00e9",
           "\U0001f600", "git@git.example.com:you/c-05.git", "ssh://h:22/x", "/abs", "/", "a/", "a=b",
           "jdoe@student.42.fr", "C:\\x", "line1\nline2", "--", "---", "...", "= ", "<<", "a  b", " a", "a "]


class Render(unittest.TestCase):
    def test_every_value_reads_back_as_itself(self):
        for v in AWKWARD:
            line = "k: %s\n" % userconfig.render(v)
            self.assertEqual(read(line.encode("utf-8")), {"k": v}, (v, line))

    def test_a_plain_value_stays_plain(self):
        for v in ("strict", "git@git.example.com:you/c-05.git", "600", "/srv/x"):
            self.assertEqual(userconfig.render(v), v)
        for v in ("no", "0755", "a b", ""):
            self.assertTrue(userconfig.render(v).startswith('"'), v)

    def test_hole_a_byte_that_is_no_utf8_is_a_refusal_not_a_traceback(self):
        with self.assertRaises(userconfig.Bad) as e:
            userconfig.render("a\udcff")
        self.assertIn("no UTF-8", str(e.exception))


class Edit(unittest.TestCase):
    def test_a_new_name_is_one_more_line(self):
        self.assertEqual(userconfig.edit(b"# c\na: x\n", "b", "v w"), b'# c\na: x\nb: "v w"\n')
        self.assertEqual(userconfig.edit(b"", "a", "x"), b"a: x\n")

    def test_set_then_unset_of_a_new_name_is_the_same_file(self):
        before = b"# c\n\na: x  # mine\n"
        self.assertEqual(userconfig.edit(userconfig.edit(before, "b", "w"), "b", None), before)

    def test_an_overwrite_keeps_the_spacing_and_the_comment(self):
        self.assertEqual(userconfig.edit(b"a:   x   # mine  \nb: w\n", "a", "z"), b"a:   z   # mine  \nb: w\n")

    def test_hole_an_overwrite_on_a_crlf_line_with_a_comment(self):
        self.assertEqual(userconfig.edit(b"a: x # mine\r\nb: w\r\n", "a", "z"), b"a: z # mine\r\nb: w\r\n")

    def test_hole_an_append_to_a_crlf_file_is_crlf(self):
        self.assertEqual(userconfig.edit(b"a: x\r\n", "b", "w"), b"a: x\r\nb: w\r\n")

    def test_a_file_with_no_final_newline(self):
        self.assertEqual(userconfig.edit(b"a: x", "b", "w"), b"a: x\nb: w\n")
        self.assertEqual(userconfig.edit(b"a: x", "a", "z"), b"a: z")
        self.assertEqual(userconfig.edit(b"a: x\nb: w", "b", None), b"a: x")

    def test_a_remove_takes_the_line_and_nothing_else(self):
        self.assertEqual(userconfig.edit(b"# c\na: x # mine\nb: w\n", "a", None), b"# c\nb: w\n")
        self.assertEqual(userconfig.edit(b"a: x\n", "zz", None), b"a: x\n")

    def test_names_42_does_not_know_are_kept(self):
        self.assertEqual(userconfig.edit(b"logn: jdoe\n", "login", "jdoe"), b"logn: jdoe\nlogin: jdoe\n")

    def test_a_bom_and_a_document_start_are_kept(self):
        self.assertEqual(userconfig.edit(b"\xef\xbb\xbf---\na: x\n", "a", "w"), b"\xef\xbb\xbf---\na: w\n")

    def test_a_file_it_cannot_read_is_never_rewritten(self):
        for data in (b"a: no\n", b"a: x\na: w\n", b"a: \xff\n"):
            with self.assertRaises(userconfig.Bad):
                userconfig.edit(data, "b", "w")

    def test_a_name_no_reader_would_read_back_is_refused(self):
        with self.assertRaises(userconfig.Bad) as e:
            userconfig.edit(b"", "on", "x")
        self.assertIn("reads back", str(e.exception))

    def test_a_name_yaml_would_take_for_no_key_is_refused(self):
        self.assertIn("a" * 1024, userconfig.parse(userconfig.edit(b"", "a" * 1024, "x")))
        with self.assertRaises(userconfig.Bad):
            userconfig.edit(b"", "a" * 1025, "x")


class Store(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = self.tmp.name
        self.env = {"HOME": self.home}
        self.dir = os.path.join(self.home, ".config", "42")
        self.file = os.path.join(self.dir, "config.yaml")
        old = os.umask(0o022)
        self.addCleanup(os.umask, old)

    def bytes(self, p=None):
        with open(p or self.file, "rb") as f:
            return f.read()

    def mode(self, p):
        return stat.S_IMODE(os.stat(p).st_mode)

    def test_a_first_write_makes_the_folder_0700_and_the_file_0600_with_its_header(self):
        self.assertEqual(userconfig.store(self.env, "level", "strict"), self.file)
        self.assertEqual(self.mode(self.dir), 0o700)
        self.assertEqual(self.mode(os.path.dirname(self.dir)), 0o755)
        self.assertEqual(self.mode(self.file), 0o600)
        self.assertEqual(self.bytes(), userconfig.HEADER.encode() + b"level: strict\n")
        self.assertEqual(userconfig.load(self.env).entries, {"level": ("strict", 3)})

    def test_an_existing_file_and_folder_keep_their_modes(self):
        os.makedirs(self.dir, 0o755)
        with open(self.file, "w") as f:
            f.write("a: x\n")
        os.chmod(self.dir, 0o750)
        os.chmod(self.file, 0o644)
        userconfig.store(self.env, "b", "w")
        self.assertEqual((self.mode(self.dir), self.mode(self.file)), (0o750, 0o644))
        self.assertEqual(self.bytes(), b"a: x\nb: w\n")

    def test_a_symlink_stays_a_link_and_its_target_is_written(self):
        os.makedirs(self.dir)
        target = os.path.join(self.home, "dotfiles", "42.yaml")
        os.makedirs(os.path.dirname(target))
        with open(target, "w") as f:
            f.write("a: x\n")
        os.symlink(target, self.file)
        userconfig.store(self.env, "a", "w")
        self.assertTrue(os.path.islink(self.file))
        self.assertEqual(self.bytes(target), b"a: w\n")
        self.assertEqual(os.listdir(os.path.dirname(target)), ["42.yaml"])

    def test_a_failed_move_leaves_the_old_file_and_no_temp_file(self):
        userconfig.store(self.env, "a", "x")
        before = self.bytes()
        with mock.patch.object(userconfig.os, "replace", side_effect=OSError(errno.EIO, "I/O error")):
            with self.assertRaises(OSError):
                userconfig.store(self.env, "a", "w")
        self.assertEqual(self.bytes(), before)
        self.assertEqual(os.listdir(self.dir), ["config.yaml"])

    def test_a_malformed_file_is_left_byte_for_byte(self):
        os.makedirs(self.dir)
        with open(self.file, "wb") as f:
            f.write(b"a: no # oops\n")
        with self.assertRaises(userconfig.Bad):
            userconfig.store(self.env, "b", "w")
        self.assertEqual(self.bytes(), b"a: no # oops\n")

    def test_no_home_is_unwritable_and_creates_nothing(self):
        with self.assertRaises(userconfig.Unwritable) as e:
            userconfig.store({}, "a", "x")
        self.assertIn("HOME is not set", str(e.exception))
        self.assertEqual(os.listdir(self.home), [])

    def test_a_folder_inside_the_checkout_is_refused(self):
        ws = os.path.join(self.home, "ws")
        os.makedirs(ws)
        for env in ({"HOME": ws}, {"XDG_CONFIG_HOME": os.path.join(ws, "cfg")}, {"XDG_CONFIG_HOME": ws}):
            with self.assertRaises(userconfig.Unwritable) as e:
                userconfig.store(env, "a", "x", outside=[ws])
            self.assertIn("inside this checkout", str(e.exception))
        self.assertEqual(os.listdir(ws), [])
        # A checkout beside the folder is no checkout around it.
        userconfig.store({"XDG_CONFIG_HOME": ws + "-not"}, "a", "x", outside=[ws])

    def test_a_folder_of_another_user_is_refused(self):
        with mock.patch.object(userconfig.os, "geteuid", return_value=os.geteuid() + 1):
            with self.assertRaises(userconfig.Unwritable) as e:
                userconfig.store(self.env, "a", "x")
        self.assertIn("belongs to another user", str(e.exception))
        self.assertFalse(os.path.exists(os.path.join(self.home, ".config")))

    @unittest.skipIf(os.geteuid() == 0, "root writes into a read-only folder")
    def test_a_read_only_folder_is_an_os_error_and_the_file_is_kept(self):
        userconfig.store(self.env, "a", "x")
        os.chmod(self.dir, 0o500)
        self.addCleanup(os.chmod, self.dir, 0o700)
        with self.assertRaises(PermissionError):
            userconfig.store(self.env, "a", "w")
        self.assertEqual(userconfig.load(self.env).entries, {"a": ("x", 3)})

    def test_a_filesystem_with_no_locks_still_writes(self):
        for n in (errno.ENOLCK, errno.EOPNOTSUPP, errno.EINVAL):
            with mock.patch.object(userconfig.fcntl, "flock", side_effect=OSError(n, os.strerror(n))):
                userconfig.store(self.env, "a", "x%d" % n)
            self.assertEqual(userconfig.load(self.env).entries, {"a": ("x%d" % n, 3)})
        with mock.patch.object(userconfig.fcntl, "flock", side_effect=OSError(errno.EBADF, "Bad file")):
            with self.assertRaises(OSError):
                userconfig.store(self.env, "a", "w")

    def test_the_file_is_read_under_the_lock_and_synced_before_it_is_moved(self):
        userconfig.store(self.env, "a", "x")
        calls = []
        flock, fsync, replace, real_open = userconfig.fcntl.flock, userconfig.os.fsync, userconfig.os.replace, open

        def record_flock(fd, op):
            calls.append(("flock", os.path.samestat(os.fstat(fd), os.stat(self.dir)), op))
            return flock(fd, op)

        def record_open(path, *a, **kw):
            calls.append(("open", path))
            return real_open(path, *a, **kw)

        def record_fsync(fd):
            calls.append(("fsync", os.fstat(fd).st_ino))
            return fsync(fd)

        def record_replace(src, dst):
            calls.append(("replace", os.stat(src).st_ino, dst))
            return replace(src, dst)

        with mock.patch.object(userconfig.fcntl, "flock", record_flock), \
                mock.patch.object(userconfig, "open", record_open, create=True), \
                mock.patch.object(userconfig.os, "fsync", record_fsync), \
                mock.patch.object(userconfig.os, "replace", record_replace):
            userconfig.store(self.env, "a", "w")
        # The new file is synced, then moved over the old: never the old one synced.
        self.assertEqual([c[0] for c in calls], ["flock", "open", "fsync", "replace"])
        self.assertEqual(calls[0][1:], (True, fcntl.LOCK_EX))
        self.assertEqual(calls[1][1], self.file)
        self.assertEqual((calls[2][1], calls[3][2]), (calls[3][1], self.file))
        self.assertEqual(userconfig.load(self.env).entries, {"a": ("w", 3)})

    def test_a_file_linked_into_the_checkout_is_refused(self):
        ws = os.path.join(self.home, "ws")
        os.makedirs(ws)
        os.makedirs(self.dir)
        os.symlink(os.path.join(ws, "mine.yaml"), self.file)
        for check in (userconfig.store, userconfig.writable):
            with self.assertRaises(userconfig.Unwritable) as e:
                check(self.env, *(("a", "x") if check is userconfig.store else ()), outside=[ws])
            self.assertIn("inside this checkout", str(e.exception))
        self.assertEqual(os.listdir(ws), [])

    def test_a_folder_linked_into_the_checkout_is_refused(self):
        ws = os.path.join(self.home, "ws")
        os.makedirs(os.path.join(ws, "cfg"))
        os.symlink(os.path.join(ws, "cfg"), os.path.join(self.home, "cfg"))
        os.symlink(ws, os.path.join(self.home, "home"))
        os.symlink(ws, os.path.join(self.home, "named"))
        # The folder is refused as itself, before a link to its file is looked
        # for; and a checkout named through a link is still the checkout.
        for env, outside in (({"XDG_CONFIG_HOME": os.path.join(self.home, "cfg")}, ws),
                             ({"HOME": os.path.join(self.home, "home")}, ws),
                             ({"XDG_CONFIG_HOME": os.path.join(ws, "cfg")}, os.path.join(self.home, "named"))):
            for check in (userconfig.store, userconfig.writable):
                with self.assertRaises(userconfig.Unwritable) as e:
                    check(env, *(("a", "x") if check is userconfig.store else ()), outside=[outside])
                self.assertIn("is inside this checkout, where it would end up in a commit: set XDG_CONFIG_HOME "
                              "or HOME to a folder outside it.", str(e.exception), env)
        self.assertEqual(sorted(os.listdir(ws)), ["cfg"])
        self.assertEqual(os.listdir(os.path.join(ws, "cfg")), [])

    def test_writable_refuses_what_store_would_and_writes_nothing(self):
        ws = os.path.join(self.home, "ws")
        os.makedirs(ws)
        self.assertEqual(userconfig.writable(self.env, outside=[ws]), self.dir)
        with self.assertRaises(userconfig.Unwritable):
            userconfig.writable({"XDG_CONFIG_HOME": os.path.join(ws, "cfg")}, outside=[ws])
        with self.assertRaises(userconfig.Unwritable):
            userconfig.writable({})
        with mock.patch.object(userconfig.os, "geteuid", return_value=os.geteuid() + 1):
            with self.assertRaises(userconfig.Unwritable):
                userconfig.writable(self.env)
        self.assertEqual(sorted(os.listdir(self.home)), ["ws"])
        self.assertEqual(os.listdir(ws), [])

    def test_unset_removes_the_line(self):
        userconfig.store(self.env, "a", "x")
        userconfig.store(self.env, "b", "w")
        userconfig.store(self.env, "a", None)
        self.assertEqual(self.bytes(), userconfig.HEADER.encode() + b"b: w\n")


class Load(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.env = {"XDG_CONFIG_HOME": self.tmp.name}
        self.file = os.path.join(self.tmp.name, "42", "config.yaml")

    def put(self, data):
        os.makedirs(os.path.dirname(self.file), exist_ok=True)
        with open(self.file, "wb") as f:
            f.write(data)

    def test_no_file_is_nothing_set(self):
        doc = userconfig.load(self.env)
        self.assertEqual((doc.path, doc.entries, doc.error, doc.exists), (self.file, {}, None, False))

    def test_a_malformed_file_is_an_error_with_its_path_and_line(self):
        self.put(b"a: x\nb: no\n")
        doc = userconfig.load(self.env)
        self.assertEqual((doc.entries, doc.exists), ({}, True))
        self.assertEqual((doc.error.path, doc.error.n), (self.file, 2))

    def test_a_folder_where_the_file_should_be_is_an_error(self):
        os.makedirs(self.file)
        doc = userconfig.load(self.env)
        self.assertEqual((doc.error.path, doc.error.n), (self.file, None))
        self.assertIn("cannot read it", doc.error.why)


class Floor(unittest.TestCase):
    def test_it_imports_only_the_standard_library_of_python_3_10(self):
        with open(userconfig.__file__, encoding="utf-8") as f:
            tree = ast.parse(f.read())
        names = {a.name.split(".")[0] for n in ast.walk(tree) if isinstance(n, ast.Import) for a in n.names}
        names |= {n.module.split(".")[0] for n in ast.walk(tree) if isinstance(n, ast.ImportFrom)}
        self.assertEqual(names, {"errno", "fcntl", "json", "os", "re", "tempfile"})


if __name__ == "__main__":
    unittest.main()
