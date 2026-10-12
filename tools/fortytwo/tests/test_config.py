"""config.py: `42 config` over a toy checkout, every verb, every refusal, and every file it writes.

The toy holds the real tools/submit.sh (its REMOTES table is the list of
projects, and its parser is what a written .submit-remotes is held to), the
real tools/identity.sh (the one writer of the identity) and tools/drives.sh,
and a .bazelrc of its own. HOME is the toy's, the system rc is a path inside
it, and the machine has 8 CPUs, so nothing on the host decides a result.
"""

import json
import os
import re
import shutil
import subprocess
import unittest
from unittest import mock

from common import WS, run42
import config
from test_main import Env

C05 = "c-piscine/c-piscine-c-05"
URL = "git@git.example.com:you/c-05.git"

BAZELRC = """\
# the checked-in rc, in small
build --local_resources=cpu=HOST_CPUS-2
test --local_test_jobs=HOST_CPUS-2
startup --host_jvm_args=-Xmx1024m
try-import %workspace%/.bazelrc.local
"""


class Toy(unittest.TestCase):
    def setUp(self):
        self.env = Env()
        self.addCleanup(self.env.close)
        self.ws = os.path.join(self.env.tmp, "ws")
        for f in ("submit.sh", "identity.sh", "drives.sh", "fortytwo/commands.tsv"):
            os.makedirs(os.path.dirname(os.path.join(self.ws, "tools", f)), exist_ok=True)
            shutil.copy(os.path.join(WS, "tools", f), os.path.join(self.ws, "tools", f))
        self.write(".bazelrc", BAZELRC)
        self.home = self.env.tmp
        self.environ = dict(self.env.environ, GIT_CEILING_DIRECTORIES=self.env.tmp,
                            GIT_CONFIG_NOSYSTEM="1")
        del self.environ["SUBMIT_GATE"]
        subprocess.run(["git", "init", "-q", self.ws], env=self.environ, check=True)
        for patch in (mock.patch.object(config, "host_cpus", lambda: 8),
                      mock.patch.object(config, "SYSTEM_RC", os.path.join(self.env.tmp, "etc.bazelrc"))):
            patch.start()
            self.addCleanup(patch.stop)

    def tearDown(self):
        self.assertEqual(self.env.called(), "", "Bazel was started")

    def path(self, name):
        return os.path.join(self.ws, name)

    def write(self, name, text):
        os.makedirs(os.path.dirname(self.path(name)), exist_ok=True)
        with open(self.path(name), "w", encoding="utf-8") as f:
            f.write(text)

    def read(self, name):
        try:
            with open(self.path(name), encoding="utf-8") as f:
                return f.read()
        except FileNotFoundError:
            return None

    def config(self, *words, environ=None):
        return run42(["config"] + list(words), self.ws, dict(self.environ, **(environ or {})), ws=self.ws)

    def ok(self, *words, **kw):
        rc, out, err = self.config(*words, **kw)
        self.assertEqual(rc, 0, (words, out, err))
        return out

    def refused(self, *words, **kw):
        rc, out, err = self.config(*words, **kw)
        self.assertEqual(rc, 2, (words, out, err))
        return err

    def fits(self, text):
        for line in text.splitlines():
            self.assertLessEqual(len(line), 80, line)

    def git(self, key):
        return subprocess.run(["git", "-C", self.ws, "config", "--local", "--get", key], env=self.environ,
                              stdout=subprocess.PIPE, universal_newlines=True, check=False).stdout.strip()


class Help(Toy):
    def test_every_way_to_ask_prints_the_same_help_within_80_columns(self):
        out = [run42(argv, self.ws, self.environ, ws=self.ws)
               for argv in (["help", "config"], ["config", "--help"], ["config", "set", "-h"])]
        for rc, text, err in out:
            self.assertEqual((rc, err), (0, ""))
            self.assertEqual(text, out[0][1])
            self.fits(text)
        for name in ("login", "email", "level", "remote.<project>", "bazel.cpus", "bazel.idle_secs",
                     "machine.root", "machine.disk_cache", "machine.disk_cache_max", "machine.heap"):
            self.assertIn("\n    %s\n" % name, out[0][1])
        self.assertIn("Runs: no Bazel command", out[0][1])

    def test_the_kind_of_every_setting_is_said(self):
        text = self.ok("list", "--all")
        for title in ("42, this checkout:", "Bazel, this checkout", "Machine, read-only"):
            self.assertIn(title, text)


class Verbs(Toy):
    def test_a_bare_config_is_list(self):
        self.assertEqual(self.ok(), self.ok("list"))

    def test_a_checkout_with_only_its_identity_lists_only_that(self):
        self.write(".vscode/settings.json", '{\n  "42header.username": "jdoe",\n'
                                            '  "42header.email": "jdoe@student.42.fr"\n}\n')
        out = self.ok("list")
        self.assertEqual(re.findall(r"(?m)^  (\S+) ", out), ["login", "email"])
        self.assertIn("42 config list --all", out)

    def test_a_missing_identity_is_no_default(self):
        # login and email have no default, and `42 submit` refuses to run
        # without them: a list that called them defaults sent nobody to init.
        out = self.ok("list")
        self.assertNotIn("every setting has its default", out)
        self.assertRegex(out, r"\n  login +\(not set\)")
        self.assertRegex(out, r"\n  email +\(not set\)")
        self.assertIn("42 init", out)
        self.fits(out)

    def test_a_flag_between_the_words_is_still_a_flag(self):
        # argparse ended the words at the first flag, so `set --dry-run level
        # strict` was refused as two stray arguments.
        for words in (("set", "--dry-run", "level", "strict"), ("set", "level", "--dry-run", "strict")):
            self.assertIn("nothing written", self.ok(*words))
        self.assertIsNone(self.read(".submit-level"))
        self.assertIn("level", self.ok("list", "--all"))

    def test_list_all_names_every_project_submit_pushes(self):
        text = self.ok("list", "--all")
        for mod in config.remotes_table(self.ws):
            self.assertRegex(text, r"\n  remote\.%s " % re.escape(config.workspace.short_name("//" + mod)))
        self.assertEqual(len(config.remotes_table(self.ws)), 21)

    def test_calls_it_refuses(self):
        for words in (("frob",), ("get",), ("get", "level", "x"), ("set", "level"), ("unset",),
                      ("get", "level", "--all"), ("list", "x")):
            self.assertIn("42 config --help", self.refused(*words), words)
        self.assertIn("Did you mean level?", self.refused("get", "levle"))

    def test_a_refusal_fits_80_columns(self):
        self.fits(self.refused("set", "machine.heap", "2g"))
        self.fits(self.refused("set", "level", "strct"))
        self.fits(self.refused("get", "remote.nope"))


class Level(Toy):
    def test_default_set_get_unset(self):
        self.assertEqual(self.ok("get", "level").splitlines()[0], "basic")
        self.assertIn("(default)", self.ok("get", "level"))
        self.assertNotIn("level", self.ok("list"))
        out = self.ok("set", "level", "strict")
        self.assertIn("level: basic -> strict", out)
        self.assertEqual(self.read(".submit-level"), "strict\n")
        self.assertEqual(self.ok("get", "level").splitlines()[0], "strict")
        self.assertIn("level", self.ok("list"))
        self.assertIn("level: strict -> basic (default)", self.ok("unset", "level"))
        self.assertIsNone(self.read(".submit-level"))
        self.assertIn("nothing to unset", self.ok("unset", "level"))

    def test_what_test_and_submit_read_is_what_it_wrote(self):
        self.ok("set", "level", "robust")
        self.assertEqual(config.workspace.resolve_level(None, {}, self.ws), ("robust", ".submit-level"))

    def test_a_value_that_is_no_level_is_refused_and_nothing_written(self):
        self.write(".submit-level", "strict\n")
        self.assertIn("strict", self.refused("set", "level", "strct"))
        self.assertEqual(self.read(".submit-level"), "strict\n")

    def test_dry_run_writes_nothing(self):
        out = self.ok("set", "level", "complete", "--dry-run")
        self.assertIn("level: basic -> complete", out)
        self.assertIn("nothing written", out)
        self.assertIsNone(self.read(".submit-level"))
        self.write(".submit-level", "strict\n")
        self.ok("--dry-run", "unset", "level")
        self.assertEqual(self.read(".submit-level"), "strict\n")

    def test_submit_gate_in_the_environment_is_named(self):
        self.ok("set", "level", "strict")
        self.assertIn("SUBMIT_GATE=robust", self.ok("get", "level", environ={"SUBMIT_GATE": "robust"}))
        self.assertIn("SUBMIT_GATE=robust", self.ok("list", environ={"SUBMIT_GATE": "robust"}))


class Identity(Toy):
    def test_set_writes_settings_and_git_through_identity_sh(self):
        out = self.ok("set", "login", "jdoe")
        self.assertIn("login: (not set) -> jdoe", out)
        self.assertIn("42 header --reset --all", out)
        self.ok("set", "email", "jdoe@student.42.fr")
        with open(self.path(".vscode/settings.json"), encoding="utf-8") as f:
            settings = json.load(f)
        self.assertEqual(settings["42header.username"], "jdoe")
        self.assertEqual(settings["42header.email"], "jdoe@student.42.fr")
        self.assertEqual((self.git("user.name"), self.git("user.email")), ("jdoe", "jdoe@student.42.fr"))
        self.assertEqual(self.ok("get", "login").splitlines()[0], "jdoe")
        self.assertIn("login: jdoe -> marvin", self.ok("set", "login", "marvin"))
        with open(self.path(".vscode/settings.json"), encoding="utf-8") as f:
            self.assertEqual(json.load(f)["42header.username"], "marvin")

    def test_a_value_that_could_not_be_stored_as_typed_is_refused(self):
        # init.sh wrote `a"b` between the quotes as it came, and left a
        # settings.json no JSON reader could open: one rule now, identity.sh's.
        self.ok("set", "login", "jdoe")
        before = self.read(".vscode/settings.json")
        for words in (("login", 'a"b'), ("login", "j doe"), ("login", "jdoe@x.fr"), ("email", "x @y.fr"),
                      ("email", "nope"), ("login", "")):
            self.refused("set", *words)
            self.refused("set", *words, "--dry-run")
        self.assertEqual(self.read(".vscode/settings.json"), before)
        self.assertEqual(self.git("user.name"), "jdoe")

    def test_an_empty_settings_file_gets_a_member_with_no_comma_after_it(self):
        for start in (None, "{}\n", "{\n}\n", "  {\n\n  }\n"):
            if start is None:
                if os.path.exists(self.path(".vscode/settings.json")):
                    os.remove(self.path(".vscode/settings.json"))
            else:
                self.write(".vscode/settings.json", start)
            self.ok("set", "email", "jdoe@student.42.fr")
            self.ok("set", "login", "jdoe")
            with open(self.path(".vscode/settings.json"), encoding="utf-8") as f:
                self.assertEqual(json.load(f), {"42header.username": "jdoe",
                                                "42header.email": "jdoe@student.42.fr"}, start)
        self.write(".vscode/settings.json", '{\n  "editor.tabSize": 4\n}\n')
        self.ok("set", "login", "jdoe")
        with open(self.path(".vscode/settings.json"), encoding="utf-8") as f:
            self.assertEqual(json.load(f), {"42header.username": "jdoe", "editor.tabSize": 4})

    def failed(self, *words, **kw):
        rc, out, err = self.config(*words, **kw)
        self.assertEqual(rc, 1, (words, out, err))
        return err

    def test_a_shape_it_cannot_rewrite_is_left_as_it_was(self):
        # Each was rewritten wrong and reported done: a value on the next
        # line, a null, the key only as another member's value or in a
        # comment, a file with no object, a one-line object (the member went
        # after its closing brace), an escaped quote (the value came out cut
        # in two), the key twice.
        for shape in ('{\n  "42header.username":\n    "old"\n}\n',
                      '{\n  "42header.username": null\n}\n',
                      '{\n  "a": "42header.username"\n}\n',
                      '// only a comment\n',
                      '{"editor.tabSize": 4}\n',
                      '{\n  "42header.username": "a\\"b"\n}\n',
                      '{\n  // "42header.username": "old",\n  "42header.username": "x"\n}\n'):
            self.write(".vscode/settings.json", shape)
            err = self.failed("set", "login", "jdoe")
            self.assertIn('"42header.username": "jdoe"', err, shape)
            self.assertEqual(self.read(".vscode/settings.json"), shape)
            self.fits(err)
        self.assertEqual(self.git("user.name"), "")

    def test_the_comments_around_it_are_kept(self):
        # A // comment after the value, // lines before the '{', and one on
        # its line: each was rewritten right before 2026-10-12, then refused.
        for shape in ('{\n  "42header.username": "old", // mine\n  "a": 1\n}\n',
                      '{\n  "a": 1,\n  "42header.username": "old" // mine\n}\n',
                      '// my settings\n\n{\n  "a": 1\n}\n',
                      '{ // my settings\n  "a": 1\n}\n',
                      '{ // my settings\n}\n'):
            self.write(".vscode/settings.json", shape)
            self.ok("set", "login", "jdoe")
            text = self.read(".vscode/settings.json")
            self.assertIn("// my settings" if "settings" in shape else "// mine", text, shape)
            plain = json.loads(re.sub(r"(?m)\s*//.*$", "", text))
            self.assertEqual(plain["42header.username"], "jdoe", shape)
            self.assertEqual(self.ok("get", "login").splitlines()[0], "jdoe", shape)

    def test_a_shape_it_will_not_rewrite_is_refused_before_anything_is_written(self):
        # init.sh checks both values before writing either; a file that could
        # take the login and not the email was found only when the email was
        # set, with the new login already written beside the old email.
        shape = '{\n  "42header.email": "old@x.fr", "a": 1\n}\n'
        self.write(".vscode/settings.json", shape)
        err = self.failed("set", "email", "jdoe@student.42.fr", "--dry-run")
        self.assertIn('"42header.email": "jdoe@student.42.fr"', err)
        self.assertEqual(self.read(".vscode/settings.json"), shape)

    def test_a_refusal_says_what_it_saw(self):
        for shape, says in (
                ('{\n  // "42header.username": "old",\n  "42header.username": "x"\n}\n', "on more than one line"),
                ('{\n  "42header.username": "old", "a": 1\n}\n', "not that member alone"),
                ('{\n  "42header.username":\n    "old"\n}\n', "not that member alone"),
                ('{\n  "42header.username": "old" /* c */\n}\n', "at most a // comment after it"),
                ('\ufeff{\n  "a": 1\n}\n', "byte-order mark"),
                ('{"a": 1}\n', "does not open with its '{' alone on a line")):
            self.write(".vscode/settings.json", shape)
            err = " ".join(self.failed("set", "login", "jdoe").split())
            self.assertIn(says, err, shape)
            self.assertEqual(self.read(".vscode/settings.json"), shape)

    def test_a_git_identity_it_cannot_set_leaves_the_file_as_it_was(self):
        # settings.json was written, then git's user.name could not be, behind
        # a stale lock: a new login in one place and the old one in the other.
        before = '{\n  "42header.username": "old"\n}\n'
        self.write(".vscode/settings.json", before)
        self.write(".git/config.lock", "")
        self.assertIn("user.name", self.failed("set", "login", "jdoe"))
        self.assertEqual(self.read(".vscode/settings.json"), before)

    def full_disk(self, times):
        """PATH for a cat that fails, writing nothing, the first `times` times
        it is asked to copy anything but settings.json: a disk that is full."""
        d = os.path.join(self.env.tmp, "full")
        os.makedirs(d)
        count = os.path.join(d, "count")
        open(count, "w").close()
        with open(os.path.join(d, "cat"), "w") as f:
            f.write('#!/bin/sh\ncase "$1" in */settings.json) exec "{cat}" "$@" ;; esac\n'
                    '[ "$(wc -c < "{count}")" -ge {times} ] && exec "{cat}" "$@"\n'
                    'printf x >> "{count}"\nexit 1\n'.format(cat=shutil.which("cat"), count=count, times=times))
        os.chmod(os.path.join(d, "cat"), 0o755)
        return {"PATH": d + os.pathsep + self.environ["PATH"]}

    def test_a_write_cut_short_is_put_back(self):
        # `cat "$tmp" > settings.json` empties the file first: a write that
        # fails then left it empty, every other setting in it gone.
        before = '{\n  "editor.tabSize": 4\n}\n'
        self.write(".vscode/settings.json", before)
        err = self.failed("set", "login", "jdoe", environ=self.full_disk(1))
        self.assertIn("nothing was changed", err)
        self.assertEqual(self.read(".vscode/settings.json"), before)
        self.assertEqual(self.git("user.name"), "")

    def test_a_write_that_cannot_be_put_back_names_the_copy(self):
        before = '{\n  "editor.tabSize": 4\n}\n'
        self.write(".vscode/settings.json", before)
        err = self.failed("set", "login", "jdoe", environ=self.full_disk(9))
        kept = re.search(r"cat '([^']+)' > '([^']+)'", err)
        self.assertIsNotNone(kept, err)
        with open(kept.group(1), encoding="utf-8") as f:
            self.assertEqual(f.read(), before)
        self.assertEqual(kept.group(2), self.path(".vscode/settings.json"))
        self.assertEqual(self.git("user.name"), "")

    def git_that(self, case, then):
        """PATH for a git that runs `then` instead of itself on a command line matching `case`."""
        d = os.path.join(self.env.tmp, "gitbin")
        os.makedirs(d)
        with open(os.path.join(d, "git"), "w") as f:
            f.write('#!/bin/sh\ncase "$*" in %s) %s ;; esac\nexec "%s" "$@"\n'
                    % (case, then, shutil.which("git")))
        os.chmod(os.path.join(d, "git"), 0o755)
        return d

    def test_a_key_it_cannot_put_back_is_named(self):
        # It said "nothing was changed" over a git user.name it had set and
        # could not unset.
        before = '{\n  "editor.tabSize": 4\n}\n'
        self.write(".vscode/settings.json", before)
        env = self.full_disk(1)
        env["PATH"] = self.git_that('*"--unset user.name"', "exit 1") + os.pathsep + env["PATH"]
        err = self.failed("set", "login", "jdoe", environ=env)
        self.assertNotIn("nothing was changed", err)
        self.assertIn("config --local --unset user.name", err)
        self.assertEqual(self.read(".vscode/settings.json"), before)

    def test_a_signal_puts_back_what_was_set(self):
        # Stopped between git and the file, it left a new git login beside
        # the old one in settings.json, and its temporary files.
        before = '{\n  "42header.username": "old"\n}\n'
        self.write(".vscode/settings.json", before)
        tmp = os.path.join(self.env.tmp, "tmpdir")
        os.makedirs(tmp)
        git = self.git_that('*"user.name jdoe"', '"%s" "$@"; kill -TERM $PPID; exit 0' % shutil.which("git"))
        self.failed("set", "login", "jdoe", environ={"PATH": git + os.pathsep + self.environ["PATH"],
                                                     "TMPDIR": tmp})
        self.assertEqual(self.git("user.name"), "")
        self.assertEqual(self.read(".vscode/settings.json"), before)
        self.assertEqual(os.listdir(tmp), [])

    def test_a_dangling_link_is_left_in_place(self):
        # A write through a link to a folder that does not exist failed, and
        # the failure removed the link as a file this run had made.
        os.makedirs(self.path(".vscode"))
        os.symlink(os.path.join(self.env.tmp, "nodir", "settings.json"), self.path(".vscode/settings.json"))
        self.failed("set", "login", "jdoe")
        self.assertTrue(os.path.islink(self.path(".vscode/settings.json")))
        self.assertEqual(self.git("user.name"), "")

    def test_a_line_that_is_no_utf8_is_rewritten_in_any_locale(self):
        # Run in the caller's locale, identity.sh refused this file under
        # UTF-8, for a reason it did not have, and rewrote it under C.
        os.makedirs(self.path(".vscode"))
        for locale in ("C.UTF-8", "en_US.UTF-8"):
            with open(self.path(".vscode/settings.json"), "wb") as f:
                f.write(b'{\n  "42header.username": "old", // caf\xe9\n}\n')
            self.ok("set", "login", "jdoe", environ={"LC_ALL": locale})
            with open(self.path(".vscode/settings.json"), "rb") as f:
                self.assertEqual(f.read(), b'{\n  "42header.username": "jdoe", // caf\xe9\n}\n', locale)

    def test_an_object_holding_only_comments_gets_no_trailing_comma(self):
        self.write(".vscode/settings.json", "{\n  // mine\n}\n")
        self.ok("set", "login", "jdoe")
        text = self.read(".vscode/settings.json")
        self.assertIn("// mine", text)
        self.assertEqual(json.loads(re.sub(r"(?m)^\s*//.*\n", "", text)), {"42header.username": "jdoe"})

    def test_an_unreadable_settings_file_is_refused_and_kept(self):
        # grep's "cannot read" read as "holds no member", and the file was
        # written over with the one key: every other setting gone, exit 0.
        if os.geteuid() == 0:
            self.skipTest("root reads a file whatever its mode")
        before = '{\n  "editor.tabSize": 4\n}\n'
        self.write(".vscode/settings.json", before)
        os.chmod(self.path(".vscode/settings.json"), 0o200)
        self.addCleanup(os.chmod, self.path(".vscode/settings.json"), 0o644)
        self.assertIn("read", self.failed("set", "login", "jdoe"))
        os.chmod(self.path(".vscode/settings.json"), 0o644)
        self.assertEqual(self.read(".vscode/settings.json"), before)

    def test_a_git_identity_it_cannot_set_is_named_by_its_git_key(self):
        if os.geteuid() == 0:
            self.skipTest("root writes a directory whatever its mode")
        os.chmod(self.path(".git"), 0o555)
        self.addCleanup(os.chmod, self.path(".git"), 0o755)
        err = self.failed("set", "login", "jdoe")
        self.assertIn("user.name", err)
        self.assertNotIn("user.login", err)

    def test_it_reads_the_identity_the_way_submit_and_the_headers_do(self):
        # submit.sh and gen_header.sh take the first line that holds the key
        # and a quoted value, and only what is between the quotes. In bytes,
        # in every locale: under UTF-8, sed's '.' stopped at a byte that is no
        # UTF-8 and its [[:space:]] took U+2003, so the three disagreed on a
        # Latin-1 comment, a Latin-1 value, and an em space before the ':'.
        # Taken as both scripts take it, through $(...), which drops a NUL.
        def shell(script, key, locale):
            return subprocess.run(
                ["sh", "-c", 'SETTINGS=.vscode/settings.json; eval "$(sed -n "/^read_42() {/,/^}/p" "$1")"; '
                 'v=$(read_42 "$2"); printf "%s" "$v"', "sh",
                 self.path("tools/" + script), key], cwd=self.ws, env=dict(self.environ, LC_ALL=locale),
                stdout=subprocess.PIPE, check=True).stdout.decode("utf-8", "replace").strip()
        shutil.copy(os.path.join(WS, "tools", "gen_header.sh"), self.path("tools/gen_header.sh"))
        os.makedirs(self.path(".vscode"))
        for shape in (b'{"42header.username": "jdoe", "42header.email": "jdoe@student.42.fr"}\n',
                      b'{\n  // "42header.username": "old",\n  "42header.username": "jdoe"\n}\n',
                      b'{\n  "42header.username": "",\n  "42header.username": "jdoe"\n}\n',
                      b'{\n  "42header.username" : "jdoe" ,\n}\n',
                      b'{\n  "42header.username": "jdoe", // caf\xe9\n}\n',
                      b'{\n  "42header.username": "caf\xe9"\n}\n',
                      '{\n  "42header.username"\u2003: "x",\n  "42header.username": "jdoe"\n}\n'.encode(),
                      b'{\n  "42header.username": "jd\x00oe"\n}\n'):
            with open(self.path(".vscode/settings.json"), "wb") as f:
                f.write(shape)
            rc, out, err = self.config("get", "login")
            got = out.splitlines()[0] if rc == 0 else ""
            for locale in ("C.UTF-8", "en_US.UTF-8"):
                for script in ("submit.sh", "gen_header.sh"):
                    self.assertEqual(got, shell(script, "username", locale), (script, locale, shape))

    def test_unset_is_refused(self):
        self.ok("set", "login", "jdoe")
        self.assertIn("42 submit", self.refused("unset", "login"))
        self.assertIn("jdoe", self.read(".vscode/settings.json"))

    def test_the_environment_override_is_named(self):
        self.ok("set", "login", "jdoe")
        self.assertIn("LOGIN42=marvin", self.ok("get", "login", environ={"LOGIN42": "marvin"}))


class Remotes(Toy):
    def submit_n(self, **environ):
        """What the real tools/submit.sh -n says over the toy: one line per module it would push."""
        for mod in config.remotes_table(self.ws):
            os.makedirs(self.path(mod + "/deliverable"), exist_ok=True)
            self.write(mod + "/BUILD.bazel", "")
        env = dict(self.environ, BUILD_WORKSPACE_DIRECTORY=self.ws, LOGIN42="marvin", EMAIL42="marvin@42.fr",
                   **environ)
        r = subprocess.run(["sh", self.path("tools/submit.sh"), "-n", "--no-gate"], cwd=self.ws, env=env,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True,
                           errors="replace", check=False)
        return r.returncode, r.stdout

    def test_set_writes_the_path_and_get_reads_it(self):
        out = self.ok("set", "remote.c-05", URL)
        self.assertIn("remote.c-05: (not set) -> " + URL, out)
        self.assertEqual(self.read(".submit-remotes"), "%s=%s\n" % (C05, URL))
        self.assertEqual(self.ok("get", "remote.c-05").splitlines()[0], URL)
        for spelling in ("remote.c-piscine-c-05", "remote.%s" % C05, "remote.%s/" % C05):
            self.assertEqual(self.ok("get", spelling).splitlines()[0], URL)

    def test_every_line_for_the_module_goes_and_the_rest_stays(self):
        self.write(".submit-remotes",
                   "# my remotes\n"
                   "c-05 = git@git.example.com:you/old-short.git   # old\n"
                   "c-piscine/c-piscine-c-00=git@git.example.com:you/c-00.git\n"
                   "c-piscine-c-05=git@git.example.com:you/old-name.git\n"
                   "  # c-piscine/c-piscine-c-05=git@git.example.com:you/commented.git\n"
                   "no equals sign here")
        self.ok("set", "remote.c-05", URL)
        self.assertEqual(self.read(".submit-remotes"),
                         "# my remotes\n"
                         "%s=%s\n"
                         "c-piscine/c-piscine-c-00=git@git.example.com:you/c-00.git\n"
                         "  # c-piscine/c-piscine-c-05=git@git.example.com:you/commented.git\n"
                         "no equals sign here\n" % (C05, URL))

    def test_what_it_writes_is_what_submit_pushes(self):
        self.write(".submit-remotes", "c-05=git@git.example.com:you/two.git\n"
                                      "c-piscine-c-05=git@git.example.com:you/urls.git\n")
        rc, out = self.submit_n()
        self.assertNotEqual(rc, 0)
        self.assertIn("2 URLs", out)
        self.assertIn("`42 submit` refuses", self.ok("get", "remote.c-05"))
        self.ok("set", "remote.c-05", URL)
        self.ok("set", "remote.c-00", "/srv/git/c-00.git")
        rc, out = self.submit_n()
        self.assertEqual(rc, 0, out)
        self.assertRegex(out, r"==>\s+%s\s+->\s+%s\n" % (re.escape(C05), re.escape(URL)))
        self.assertRegex(out, r"==>\s+c-piscine/c-piscine-c-00\s+->\s+/srv/git/c-00\.git\n")
        self.assertNotIn("NOT A MODULE", out)

    def test_it_reads_a_line_the_way_submit_reads_it(self):
        self.write(".submit-remotes",
                   "  c-piscine-c-01 = git@git.example.com:you/spaced.git   # mine\n"
                   "c-piscine/c-piscine-c-02/=git@git.example.com:you/slash.git\n"
                   "c-03=git@git.example.com:you/last.git")
        rc, out = self.submit_n()
        for ex, url in (("01", "spaced"), ("02", "slash"), ("03", "last")):
            want = "git@git.example.com:you/%s.git" % url
            self.assertEqual(self.ok("get", "remote.c-" + ex).splitlines()[0], want)
            self.assertRegex(out, r"==>\s+c-piscine/c-piscine-c-%s\s+->\s+%s\n" % (ex, re.escape(want)))

    def test_a_line_whose_only_equals_sign_is_in_its_comment(self):
        # Read as KEY=URL once the comment was gone, it had no '=' left: a
        # traceback in 42, and in submit.sh a URL that was the key itself.
        self.write(".submit-remotes", "c-05 # note=x\n")
        self.ok("list")
        self.assertEqual(self.config("get", "remote.c-05")[0], 1)
        self.ok("set", "remote.c-05", URL)
        self.assertEqual(self.read(".submit-remotes"), "c-05 # note=x\n%s=%s\n" % (C05, URL))
        rc, out = self.submit_n()
        self.assertNotRegex(out, r"->\s+c-05\n")

    def test_only_what_submit_calls_a_blank_or_a_line_end_is_one(self):
        # A no-break space pasted from a page is no blank to submit.sh's sed,
        # and only a newline ends its lines.
        self.write(".submit-remotes", "c-05\u00a0=git@git.example.com:you/nbsp.git\n"
                                      "c-00=git@git.example.com:you/c-00.git\x0cc-01=x@y:z\n")
        self.assertEqual(self.config("get", "remote.c-05")[0], 1)
        self.assertEqual(self.config("get", "remote.c-01")[0], 1)
        self.assertEqual(self.ok("get", "remote.c-00").split("\n")[0],
                         "git@git.example.com:you/c-00.git\x0cc-01=x@y:z")

    def test_submit_reads_a_line_as_42_config_does_in_any_locale(self):
        # Under a UTF-8 locale GNU sed's [[:space:]] is every Unicode blank,
        # and its .* stops at a byte that is no UTF-8: submit.sh pushed to a
        # line 42 config read as no project's, to a URL one character shorter
        # than the one 42 config showed, and to one that kept its comment. A
        # machine without the locale runs sed in C, and the check holds
        # trivially there.
        wide = "git@git.example.com:you/c-01.git\u3000"
        latin = "git@git.example.com:you/c-02.git"
        with open(self.path(".submit-remotes"), "wb") as f:
            f.write(("c-05\u3000=git@git.example.com:you/wide.git\nc-01=%s\n" % wide).encode()
                    + b"c-02=" + latin.encode() + b" # caf\xe9\n")
        self.assertEqual(self.config("get", "remote.c-05")[0], 1)
        self.assertEqual(self.ok("get", "remote.c-01").split("\n")[0], wide)
        self.assertEqual(self.ok("get", "remote.c-02").split("\n")[0], latin)
        for locale in ("C.UTF-8", "en_US.UTF-8"):
            rc, out = self.submit_n(LC_ALL=locale)
            pushes = [l for l in out.splitlines() if l.startswith("==>")]
            self.assertFalse([l for l in pushes if "wide.git" in l], (locale, out))
            for url in (wide, latin):
                self.assertTrue([l for l in pushes if l.endswith(" " + url)], (locale, url, out))

    def test_a_url_submit_skips_is_not_set(self):
        # submit.sh reads an empty URL, and REPLACE_ME, as "no URL yet" and
        # skips the project, which 42 config showed as having that URL.
        for url in ("", "REPLACE_ME", "  REPLACE_ME   # later"):
            self.write(".submit-remotes", "c-05=%s\n" % url)
            rc, out = self.submit_n()
            self.assertRegex(out, r"SKIP\s+%s\s" % re.escape(C05), url)
            self.assertEqual(self.config("get", "remote.c-05")[0], 1, url)
            self.assertNotIn("remote.c-05", self.ok("list"), url)

    def test_a_nul_byte_is_dropped_as_submit_drops_it(self):
        # The shell's `read` drops a NUL, so submit.sh pushed to a URL one
        # byte shorter than the one 42 config showed.
        with open(self.path(".submit-remotes"), "wb") as f:
            f.write(b"c-0\x005=" + URL.encode().replace(b"c-05", b"c-0\x005") + b"\n")
        rc, out = self.submit_n()
        self.assertRegex(out, r"==>\s+%s\s+->\s+%s\n" % (re.escape(C05), re.escape(URL)))
        self.assertEqual(self.ok("get", "remote.c-05").splitlines()[0], URL)

    def test_bytes_it_does_not_rewrite_are_kept(self):
        with open(self.path(".submit-remotes"), "wb") as f:
            f.write(b"c-00=git@git.example.com:you/c-00.git\r\n# caf\xe9\r\n")
        self.ok("set", "remote.c-05", URL)
        with open(self.path(".submit-remotes"), "rb") as f:
            self.assertEqual(f.read(), b"c-00=git@git.example.com:you/c-00.git\r\n# caf\xe9\r\n"
                             + ("%s=%s\n" % (C05, URL)).encode())

    def test_unset_removes_its_lines(self):
        self.write(".submit-remotes", "# keep\nc-05=%s\n" % URL)
        self.assertIn("remote.c-05: %s -> (not set)" % URL, self.ok("unset", "remote.c-05"))
        self.assertEqual(self.read(".submit-remotes"), "# keep\n")
        rc, err = self.config("get", "remote.c-05")[0::2]
        self.assertEqual(rc, 1)
        self.assertIn("42 config set remote.c-05 URL", err)

    def test_what_is_no_url_or_no_project_is_refused(self):
        for bad in ("REPLACE_ME", "git@host:with space", "not a url", "relative/path", ""):
            self.refused("set", "remote.c-05", bad)
        self.assertIsNone(self.read(".submit-remotes"))
        err = self.refused("set", "remote.c-99", URL)
        self.assertIn("c-05", err)
        self.assertIn("reloaded", err)
        for good in ("ssh://git@git.example.com/you/c-05.git", "https://git.example.com/you/c-05.git",
                     "file:///srv/git/c-05.git", "/srv/git/c-05.git"):
            self.ok("set", "remote.c-05", good)
            self.assertEqual(self.ok("get", "remote.c-05").splitlines()[0], good)

    def test_a_key_that_names_two_projects_is_left_for_you_to_settle(self):
        # No two projects share a name today; one under a second course
        # folder would, and `42 submit` stops on a key naming both.
        with open(self.path("tools/submit.sh"), encoding="utf-8") as f:
            text = f.read()
        with open(self.path("tools/submit.sh"), "w", encoding="utf-8") as f:
            f.write(text.replace("\nREMOTES='\n", "\nREMOTES='\ncursus/c-piscine-c-05=REPLACE_ME\n", 1))
        err = self.refused("get", "remote.c-05")
        self.assertIn("remote.%s" % C05, err)
        self.assertIn("remote.cursus/c-piscine-c-05", err)
        self.write(".submit-remotes", "c-05=%s\n" % URL)
        rc, out = self.submit_n()
        self.assertNotEqual(rc, 0)
        self.assertIn("names more than one module", out)
        for words in (("set", "remote.%s" % C05, URL), ("unset", "remote.cursus/c-piscine-c-05")):
            self.assertIn("names 2 projects", self.refused(*words))
        self.assertEqual(self.read(".submit-remotes"), "c-05=%s\n" % URL)
        self.write(".submit-remotes", "%s=%s\n" % (C05, URL))
        self.ok("set", "remote.cursus/c-piscine-c-05", "/srv/git/cursus-c-05.git")
        self.assertEqual(self.ok("get", "remote.%s" % C05).splitlines()[0], URL)
        self.assertIn("\n  remote.cursus/c-piscine-c-05", self.ok("list"))

    def test_a_long_url_is_shortened_in_list_and_whole_in_get(self):
        long_url = "git@git.example.com:you/" + "x" * 90 + ".git"
        self.ok("set", "remote.c-05", long_url)
        for words in (("list",), ("list", "--all")):
            text = self.ok(*words)
            self.fits(text)
            self.assertIn("...", text)
            self.assertIn("42 config get NAME", text)
        self.assertEqual(self.ok("get", "remote.c-05").splitlines()[0], long_url)


class Bazel(Toy):
    def test_the_checked_in_value_is_shown_and_is_no_setting_of_yours(self):
        out = self.ok("get", "bazel.cpus")
        self.assertEqual(out.splitlines()[0], "HOST_CPUS-2 (6 on this machine)")
        self.assertIn("(.bazelrc, line 2)", out)
        self.assertNotIn("bazel.cpus", self.ok("list"))
        self.assertEqual(self.ok("get", "bazel.idle_secs").splitlines()[0], "10800")
        self.assertIsNone(self.read(".bazelrc.local"))

    def test_set_writes_one_block_and_a_second_set_replaces_it(self):
        self.write(".bazelrc.local", "startup --output_user_root=/goinfre/me/bazel\n"
                                     "build --local_resources=cpu=7\n")
        out = self.ok("set", "bazel.cpus", "4")
        self.assertIn("bazel.cpus: 7 -> 4", out)
        self.assertIn("dev container", out)
        self.ok("set", "bazel.cpus", "3")
        self.assertEqual(self.read(".bazelrc.local"),
                         "startup --output_user_root=/goinfre/me/bazel\n"
                         "# replaced by 42 config: build --local_resources=cpu=7\n"
                         "\n"
                         "# set by `42 config set bazel.cpus`\n"
                         "build --local_resources=cpu=3\n"
                         "test --local_test_jobs=3\n")
        out = self.ok("get", "bazel.cpus")
        self.assertEqual(out.splitlines()[0], "3")
        self.assertIn(".bazelrc.local, line 5", out)
        self.assertIn("bazel.cpus", self.ok("list"))

    def test_unset_goes_back_to_the_checked_in_value(self):
        self.ok("set", "bazel.cpus", "4")
        self.ok("unset", "bazel.cpus")
        self.assertNotIn("--local", self.read(".bazelrc.local").replace("# removed by 42 config", ""))
        self.assertEqual(self.ok("get", "bazel.cpus").splitlines()[0], "HOST_CPUS-2 (6 on this machine)")

    def test_values_it_refuses(self):
        # '\u00b2' is a digit to str.isdigit() and no number to int(); Bazel's
        # client takes --max_idle_secs as a 32-bit int, and stops on
        # 3000000000 (measured on Bazel 9.2.0).
        for bad in ("0", "9", "-1", "four", "2.5", "\u00b2", "\u0663"):
            self.refused("set", "bazel.cpus", bad)
            self.refused("set", "bazel.cpus", bad, "--dry-run")
        for bad in ("59", "0", "x", "\u00b2", "2147483648", "3000000000"):
            self.refused("set", "bazel.idle_secs", bad)
        self.assertIsNone(self.read(".bazelrc.local"))
        self.ok("set", "bazel.idle_secs", "2147483647")

    def test_a_build_line_wins_over_a_common_line_read_later(self):
        # Bazel applies an rc file's lines command by command -- common,
        # then build, then test -- and file order only within one command
        # (measured on Bazel 9.2.0: a .bazelrc build line beat a later
        # .bazelrc.local common line).
        with open(os.path.join(self.home, ".bazelrc"), "w", encoding="utf-8") as f:
            f.write("common --local_resources=cpu=2\ncommon --disk_cache=/tmp/home-cache\n")
        self.write(".bazelrc.local", "build --disk_cache=/goinfre/me/cache\n")
        out = self.ok("get", "bazel.cpus")
        self.assertEqual(out.splitlines()[0], "HOST_CPUS-2 (6 on this machine)")
        self.assertIn("(.bazelrc, line 2)", out)
        self.assertEqual(self.ok("get", "machine.disk_cache").splitlines()[0], "/goinfre/me/cache")

    def test_set_leaves_every_other_flag_where_it_was(self):
        self.ok("set", "bazel.cpus", "4")
        with open(self.path(".bazelrc.local"), "a", encoding="utf-8") as f:
            f.write("build --local_resources=memory=4096\n")
        self.ok("set", "bazel.cpus", "3")
        self.assertIn("\nbuild --local_resources=memory=4096\n", self.read(".bazelrc.local"))
        mixed = "build --local_resources=cpu=4 --jobs=8\ntest --local_test_jobs=2 --test_output=errors\n"
        self.write(".bazelrc.local", mixed)
        self.ok("set", "bazel.cpus", "3")
        self.assertTrue(self.read(".bazelrc.local").startswith(mixed))
        self.assertEqual(self.ok("get", "bazel.cpus").splitlines()[0], "3")
        out = self.ok("unset", "bazel.cpus")
        self.assertEqual(self.read(".bazelrc.local"), mixed)
        self.assertIn(".bazelrc.local, line 1", out)

    def test_a_test_jobs_line_alone_is_a_setting_of_yours(self):
        self.write(".bazelrc.local", "test --local_test_jobs=2\n")
        self.assertIn("bazel.cpus", self.ok("list"))
        self.ok("unset", "bazel.cpus")
        self.assertEqual(self.read(".bazelrc.local"), "# removed by 42 config: test --local_test_jobs=2\n")

    def test_unset_of_a_value_another_file_sets_says_where(self):
        with open(os.path.join(self.home, ".bazelrc"), "w", encoding="utf-8") as f:
            f.write("build --local_resources=cpu=6\n")
        rc, out, err = self.config("unset", "bazel.cpus")
        self.assertEqual(rc, 1, (out, err))
        self.assertIn("~/.bazelrc, line 1", err)
        self.assertNotIn("written to", out)
        self.assertIsNone(self.read(".bazelrc.local"))

    def test_idle_secs_says_a_running_server_keeps_its_value(self):
        # Measured on Bazel 9.2.0: a running server kept --max_idle_secs=300
        # after the rc file said 600; only a new server reads it.
        out = self.ok("set", "bazel.idle_secs", "600")
        self.assertIn("42 stop", out)
        self.assertIn("startup --max_idle_secs=600\n", self.read(".bazelrc.local"))
        self.assertEqual(self.ok("get", "bazel.idle_secs").splitlines()[0], "600")

    def test_a_home_rc_that_wins_is_named(self):
        with open(os.path.join(self.home, ".bazelrc"), "w", encoding="utf-8") as f:
            f.write("build --local_resources=cpu=2\n")
        out = self.ok("set", "bazel.cpus", "4")
        self.assertIn("~/.bazelrc, line 1 sets it too", out)
        out = self.ok("get", "bazel.cpus")
        self.assertEqual(out.splitlines()[0], "2")
        self.assertIn("(~/.bazelrc, line 1;", out)

    def test_a_named_config_or_a_comment_sets_nothing(self):
        self.write(".bazelrc.local", "build:fast --local_resources=cpu=1\n# build --local_resources=cpu=1\n")
        self.assertIn("(.bazelrc, line 2)", self.ok("get", "bazel.cpus"))


class Machine(Toy):
    def test_read_only_and_shown(self):
        self.assertIn("setup.sh", self.refused("set", "machine.root", "/tmp/x"))
        self.assertIn(".bazelrc", self.refused("set", "machine.heap", "2g"))
        self.refused("unset", "machine.disk_cache")
        out = self.ok("get", "machine.heap")
        self.assertEqual(out.splitlines()[0], "1024m")
        self.assertIn("(.bazelrc, line 4)", out)
        self.assertEqual(self.ok("get", "machine.disk_cache").splitlines()[0], "none")
        self.assertEqual(self.ok("get", "machine.root").splitlines()[0],
                         config.report.state_root(self.ws, self.environ))

    def test_list_all_fits_80_columns(self):
        self.ok("set", "login", "jdoe")
        self.ok("set", "email", "a.very.long.name.for.someone@student.42campus.example.com")
        self.ok("set", "bazel.cpus", "4")
        self.fits(self.ok("list", "--all"))
        self.fits(self.ok("list"))



class Submit(Toy):
    """`42 submit c-05 URL` saves the URL through config's writer, then pushes there."""

    def setUp(self):
        Toy.setUp(self)
        shutil.copy(os.path.join(WS, "tools", "defs.bzl"), self.path("tools/defs.bzl"))
        for mod in (C05, "c-piscine/c-piscine-c-06"):
            self.write(mod + "/BUILD.bazel", "subject(\n)\nc_levels(\n)\n")
        # `bazel run` replaces 42's process: recorded here instead.
        self.ran = []
        patch = mock.patch.object(config.bazel, "exec_foreground", lambda argv, ws, env: self.ran.append(argv))
        patch.start()
        self.addCleanup(patch.stop)

    def pushed(self):
        return [" ".join(argv[1:]) for argv in self.ran]

    def submit(self, *words):
        return run42(["submit"] + list(words), self.path(C05), self.environ, ws=self.ws)

    def test_a_url_is_saved_and_pushed_to(self):
        rc, out, err = self.submit(URL)
        self.assertEqual(rc, 0, (out, err))
        self.assertIn("saved for c-05", out)
        self.assertEqual(self.read(".submit-remotes"), "%s=%s\n" % (C05, URL))
        self.assertEqual(self.pushed(), ["run //tools:submit -- %s --url %s" % (C05, URL)])
        other = "git@git.example.com:you/c-05-again.git"
        rc, out, err = self.submit(other)
        self.assertIn("(it was %s)" % URL, out)
        self.assertEqual(self.read(".submit-remotes"), "%s=%s\n" % (C05, other))

    def test_the_same_url_again_says_nothing_and_writes_nothing(self):
        self.write(".submit-remotes", "c-05 = %s   # mine\n" % URL)
        rc, out, err = self.submit(URL)
        self.assertEqual(rc, 0, err)
        self.assertNotIn("saved", out)
        self.assertEqual(self.read(".submit-remotes"), "c-05 = %s   # mine\n" % URL)

    def test_n_and_dry_run_save_nothing(self):
        for flag, says in (("-n", "-n saves nothing"), ("--dry-run", "--dry-run saves nothing")):
            rc, out, err = self.submit(URL, flag)
            self.assertEqual(rc, 0, err)
            self.assertIn(says, out)
            self.assertIsNone(self.read(".submit-remotes"))
        self.assertEqual(self.pushed(), ["run //tools:submit -- %s --url %s -n" % (C05, URL)])

    def test_a_file_it_cannot_write_stops_the_push(self):
        if os.geteuid() == 0:
            self.skipTest("root writes a file whatever its mode")
        self.write(".submit-remotes", "# mine\n")
        os.chmod(self.path(".submit-remotes"), 0o444)
        self.addCleanup(os.chmod, self.path(".submit-remotes"), 0o644)
        rc, out, err = self.submit(URL)
        self.assertEqual(rc, 1, (out, err))
        self.assertIn(".submit-remotes", err)
        self.assertEqual(self.pushed(), [])


if __name__ == "__main__":
    unittest.main()
