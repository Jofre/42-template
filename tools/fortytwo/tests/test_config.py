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
import itertools
import shutil
import stat
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
        for f in ("submit.sh", "identity.sh", "drives.sh", "units.awk", "userconfig_line.awk",
                  "fortytwo/commands.tsv"):
            os.makedirs(os.path.dirname(os.path.join(self.ws, "tools", f)), exist_ok=True)
            shutil.copy(os.path.join(WS, "tools", f), os.path.join(self.ws, "tools", f))
        self.write(".bazelrc", BAZELRC)
        self.home = self.env.tmp
        self.environ = dict(self.env.environ, GIT_CEILING_DIRECTORIES=self.env.tmp,
                            GIT_CONFIG_NOSYSTEM="1")
        del self.environ["SUBMIT_GATE"]
        subprocess.run(["git", "init", "-q", self.ws], env=self.environ, check=True)
        patch = mock.patch.object(config, "host_cpus", lambda: 8)
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
        for title in ("42, this checkout and your user file:", "Bazel, this checkout", "Machine, read-only"):
            self.assertIn(title, text)

    def test_the_scopes_are_said_and_which_settings_your_user_file_may_hold(self):
        rc, text, err = run42(["help", "config"], self.ws, self.environ, ws=self.ws)
        flat = " ".join(text.split())
        self.assertIn("with --global your user file, %s," % config.userconfig.WHERE, flat)
        self.assertIn("`list` and `get` show every value that is set, the one in use on the setting's line; "
                      "--local or --global shows that scope's alone.", flat)
        self.assertNotIn("--local, the default", flat)
        self.assertIn("when that is an absolute path", config.userconfig.WHERE)
        self.assertIn("Your user file may hold level.", flat)
        self.assertIn("Stored in .submit-level, or in your user file (--global).", flat)


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
            # A name too long for the column (a deep project's path) is
            # printed alone on its line, its value on the next.
            self.assertRegex(text, r"\n  remote\.%s[ \n]" % re.escape(config.workspace.short_name("//" + mod)))
        self.assertEqual(len(config.remotes_table(self.ws)), 22)

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

    def test_submit_gate_in_the_environment_is_the_level_in_use(self):
        # `42 test` and tools/submit.sh both take it over the file, so it is
        # the value in use, the file's shown under it, not a note beside it.
        gate = {"SUBMIT_GATE": "robust"}
        self.ok("set", "level", "strict")
        self.assertEqual(self.ok("get", "level", environ=gate).splitlines(),
                         ["robust", "  (environment: SUBMIT_GATE)", "  not used: strict  (local: .submit-level)"])
        self.assertIn("\n  level                  robust  (environment: SUBMIT_GATE)\n"
                      "      not used: strict  (local: .submit-level)\n", self.ok("list", environ=gate))
        self.assertEqual(config.workspace.resolve_level(None, gate, self.ws), ("robust", "SUBMIT_GATE"))
        out = self.ok("set", "level", "complete", environ=gate)
        self.assertIn("note: in use instead: robust  (environment: SUBMIT_GATE), which wins over it.", out)
        # An empty one is unset to both readers.
        self.assertEqual(self.ok("get", "level", environ={"SUBMIT_GATE": ""}).splitlines(),
                         ["complete", "  (local: .submit-level)"])
        self.ok("unset", "level")
        self.assertIn("\n  level                  robust  (environment: SUBMIT_GATE)\n", self.ok("list", environ=gate))
        self.assertIn("which is not a level", self.ok("get", "level", environ={"SUBMIT_GATE": "strct"}))


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
        # line, a null, the key only as another member's value, a file with
        # no object, a one-line object (the member went after its closing
        # brace), an escaped quote (the value came out cut in two), the key
        # twice (VS Code reads the last, and 42 submit and the headers read
        # the first until V307). Then a key the 42header extension never
        # sees, each rewritten and reported done until 2026-10-16 (V189):
        # inside a /* */ comment, inside a nested object, a "[c]" language
        # override among them (the extension asks for no language), inside
        # one opened on the line that closes another, before the object,
        # inside a list.
        for shape in ('{\n  "42header.username":\n    "old"\n}\n',
                      '{\n  "42header.username": null\n}\n',
                      '{\n  "a": "42header.username"\n}\n',
                      '// only a comment\n',
                      '{"editor.tabSize": 4}\n',
                      '{\n  "42header.username": "a\\"b"\n}\n',
                      '{\n  "42header.username": "old",\n  "42header.username": "x"\n}\n',
                      '{\n  "a": 1,\n  /*\n  "42header.username": "old"\n  */\n  "b": 2\n}\n',
                      '{\n  "x": {\n    "42header.username": "old"\n  }\n}\n',
                      '{\n  "[c]": {\n    "42header.username": "old"\n  }\n}\n',
                      '{\n  "x": {\n    "y": 1 }, "z": {\n    "42header.username": "old"\n  }\n}\n',
                      '"42header.username": "old"\n{\n  "a": 1\n}\n',
                      '{\n  "a": [\n    "42header.username": "old"\n  ]\n}\n'):
            self.write(".vscode/settings.json", shape)
            err = self.failed("set", "login", "jdoe")
            self.assertIn('"42header.username": "jdoe"', err, shape)
            self.assertEqual(self.read(".vscode/settings.json"), shape)
            self.fits(err)
        self.assertEqual(self.git("user.name"), "")

    def test_a_copy_in_a_comment_is_refused_for_what_it_is(self):
        # A live member and a copy of it in a /* */ comment: VS Code reads
        # the live one alone, so the refusal said a reason that was false
        # there ("VS Code reads the last") until 2026-10-16.
        shape = '{\n  "42header.username": "new",\n  /* "42header.username": "old" */\n  "x": 1\n}\n'
        self.write(".vscode/settings.json", shape)
        err = self.failed("set", "login", "jdoe")
        self.assertNotIn("reads the last", err)
        self.assertIn("/* */", err)
        self.assertEqual(self.read(".vscode/settings.json"), shape)
        self.fits(err)

    def test_a_key_on_two_lines_is_refused_for_what_it_is(self):
        # Since V307 every reader reads what VS Code reads, the last
        # top-level member, so the refusal's reason ("VS Code and 42 submit
        # and the file headers may not read the same one") was false: this
        # script refuses because it rewrites one line, not because they
        # differ.
        for shape in ('{\n  "42header.username": "old",\n  "42header.username": "x"\n}\n',
                      '{\n  "[c]": {\n    "42header.username": "x"\n  },\n  "42header.username": "old"\n}\n'):
            self.write(".vscode/settings.json", shape)
            err = self.failed("set", "login", "jdoe")
            self.assertNotIn("may not read the same", err, shape)
            self.assertIn("yours to say", err, shape)
            self.assertEqual(self.read(".vscode/settings.json"), shape)
            self.fits(err)

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

    def test_a_block_comment_or_a_nested_object_elsewhere_is_no_refusal(self):
        # The key at the top level is rewritten whatever sits around it: a
        # /* */ comment, one over two lines, a glob holding "/*", a nested
        # object, braces and an escaped quote in a string, a '{' and a '/*'
        # in a // comment. A file is refused for where its key is, never for
        # holding one of these (the shipped settings.json has "[c]").
        for shape in ('{\n  /* mine */\n  "42header.username": "old"\n}\n',
                      '{\n  "a": 1 /*\n  x */,\n  "42header.username": "old"\n}\n',
                      '{\n  "files.exclude": {"**/*.o": true},\n  "42header.username": "old"\n}\n',
                      '{\n  "[c]": {\n    "editor.tabSize": 4\n  },\n  "42header.username": "old"\n}\n',
                      '{\n  "a": "{\\"[",\n  "42header.username": "old"\n}\n',
                      '{\n  "a": 1, // { /* no block\n  "42header.username": "old"\n}\n'):
            self.write(".vscode/settings.json", shape)
            self.ok("set", "login", "jdoe")
            self.assertEqual(self.read(".vscode/settings.json"), shape.replace('"old"', '"jdoe"'), shape)

    def test_a_commented_out_identity_is_not_the_one_read(self):
        # VS Code reads settings.json skipping its comments, and so does the
        # 42header extension; 42 config, submit and the headers took the
        # first line holding the key, a // line among them (V186).
        self.write(".vscode/settings.json",
                   '{\n  // "42header.username": "old",\n  "42header.username": "jdoe",\n'
                   '  // "42header.email": "old@x.fr",\n  "42header.email": "jdoe@student.42.fr"\n}\n')
        self.assertEqual(self.ok("get", "login").splitlines()[0], "jdoe")
        self.assertEqual(self.ok("get", "email").splitlines()[0], "jdoe@student.42.fr")

    def test_a_commented_out_identity_is_kept_and_the_live_one_set(self):
        # identity.sh refused both: the first as the key on two lines, the
        # second as the key on a line that is not the member alone (V186).
        for shape, want in (
                ('{\n  // "42header.username": "old",\n  "42header.username": "x"\n}\n',
                 '{\n  // "42header.username": "old",\n  "42header.username": "jdoe"\n}\n'),
                ('{\n  // "42header.username": "old",\n  "a": 1\n}\n',
                 '{\n  "42header.username": "jdoe",\n  // "42header.username": "old",\n  "a": 1\n}\n')):
            self.write(".vscode/settings.json", shape)
            self.ok("set", "login", "jdoe")
            self.assertEqual(self.read(".vscode/settings.json"), want, shape)
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
                ('{\n  "42header.username": "old",\n  "42header.username": "x"\n}\n', "on more than one line"),
                ('{\n  /*\n  "42header.username": "old"\n  */\n}\n', "inside a /* */ comment"),
                ('{\n  "[c]": {\n    "42header.username": "old"\n  }\n}\n', "inside a nested object"),
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
        # submit.sh's and gen_header.sh's read_42 each had a reader of its
        # own, and a fix to one missed the others; all three ask
        # tools/identity.sh now. In bytes, in every locale: under UTF-8, sed's
        # '.' stopped at a byte that is no UTF-8 and its [[:space:]] took
        # U+2003, so the three disagreed on a Latin-1 comment, a Latin-1
        # value, and an em space before the ':'. What each reads is held by
        # test_it_reads_only_the_key_vs_code_reads; this holds them together.
        # Taken as both scripts take it, through $(...), which drops a NUL.
        def shell(script, key, locale):
            return subprocess.run(
                ["sh", "-c", 'ROOT=.; eval "$(grep "^read_42() {.*}$" "$1")"; '
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
                      b'{\n  "[c]": {\n    "42header.username": "old"\n  }\n}\n',
                      b'{\n  /*\n  "42header.username": "old",\n  */\n  "42header.username": "jdoe"\n}\n',
                      b'{\n  "a": 1, // "42header.username": "old",\n  "42header.username": "jdoe"\n}\n'):
            with open(self.path(".vscode/settings.json"), "wb") as f:
                f.write(shape)
            rc, out, err = self.config("get", "login")
            got = out.splitlines()[0] if rc == 0 else ""
            for locale in ("C.UTF-8", "en_US.UTF-8"):
                for script in ("submit.sh", "gen_header.sh"):
                    self.assertEqual(got, shell(script, "login", locale), (script, locale, shape))

    def test_it_reads_only_the_key_vs_code_reads(self):
        # The readers took the first line holding the key that was no //
        # comment, wherever it sat, and agreed with one another: a "[c]"
        # override, a key in a /* */ comment and one after a member's //
        # were each read as the login, where VS Code and the 42header
        # extension read no key or the live one below it (V307). Of two live
        # members, VS Code keeps the last. A member after a missing comma is
        # one VS Code still reads, and a first fix of V307 read no key there.
        # An em space before a ':' (a blank to VS Code, a stray byte here)
        # and a NUL in a value (which the shell's $(...) drops) read jdoe
        # either way. Held here through `42 config get`, the header
        # gen_header.sh prints, and submit.sh's refusal to run with no login.
        shutil.copy(os.path.join(WS, "tools", "gen_header.sh"), self.path("tools/gen_header.sh"))
        os.makedirs(self.path(".vscode"))
        env = dict(self.environ, BUILD_WORKSPACE_DIRECTORY=self.ws)
        for shape, want in ((b'{\n  "[c]": {\n    "42header.username": "old"\n  }\n}\n', None),
                            (b'{\n  /*\n  "42header.username": "old",\n  */\n'
                             b'  "42header.username": "new"\n}\n', "new"),
                            (b'{\n  "a": 1, // "42header.username": "old",\n'
                             b'  "42header.username": "new"\n}\n', "new"),
                            (b'{\n  "42header.username": "old",\n  "42header.username": "new"\n}\n', "new"),
                            (b'{\n  "42header.username": "old",\n  "42header.username": ""\n}\n', None),
                            (b'{\n  "editor.fontSize": 14\n  "42header.username": "new"\n}\n', "new"),
                            (b'{\n  "a": "x"\n  "42header.username": "new"\n}\n', "new"),
                            (b'{\n  "a": {}\n  "42header.username": "new"\n}\n', "new"),
                            ('{\n  "42header.username"\u2003: "x",\n'
                             '  "42header.username": "jdoe"\n}\n'.encode(), "jdoe"),
                            (b'{\n  "42header.username": "jd\x00oe"\n}\n', "jdoe")):
            with open(self.path(".vscode/settings.json"), "wb") as f:
                f.write(shape)
            rc, out, err = self.config("get", "login")
            self.assertEqual(out.splitlines()[0] if rc == 0 else None, want, (shape, out, err))
            hdr = subprocess.run(["sh", self.path("tools/gen_header.sh"), "x.c"], cwd=self.ws, env=env,
                                 stdout=subprocess.PIPE, universal_newlines=True, check=True).stdout
            self.assertIn("By: %s <" % (want or "marvin"), hdr, shape)
            sub = subprocess.run(["sh", self.path("tools/submit.sh"), "-n", "--no-gate"], cwd=self.ws,
                                 env=dict(env, EMAIL42="jdoe@student.42.fr"), stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, universal_newlines=True, errors="replace",
                                 check=False).stdout
            self.assertEqual("no 42 identity found" in sub, want is None, (shape, sub))

    def test_a_member_after_a_missing_comma_is_rewritten(self):
        # Read as no key by a first fix of V307, it was refused as "could not
        # be rewritten safely", where the rewrite before that one took it.
        self.write(".vscode/settings.json",
                   '{\n  "editor.fontSize": 14\n  "42header.username": "old"\n}\n')
        self.ok("set", "login", "jdoe")
        self.assertEqual(self.read(".vscode/settings.json"),
                         '{\n  "editor.fontSize": 14\n  "42header.username": "jdoe"\n}\n')
        self.assertEqual(self.ok("get", "login").splitlines()[0], "jdoe")

    def test_the_reader_runs_in_the_environment_42_was_given(self):
        # It ran in os.environ, so a PATH 42 was given never reached it. A
        # PATH holding sh and no awk: identity.sh's reader cannot run, and
        # the login reads as unset, where os.environ's PATH read jdoe.
        self.ok("set", "login", "jdoe")
        bare = self.path("bare-bin")
        os.makedirs(bare)
        os.symlink(shutil.which("sh"), os.path.join(bare, "sh"))
        rc, out, err = self.config("get", "login", environ={"PATH": bare})
        self.assertNotIn("jdoe", out + err, (rc, out, err))

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
        self.assertEqual(out.splitlines(), ["HOST_CPUS-2 (6 on this machine)", "  (checked in: .bazelrc, line 2)"])
        self.assertNotIn("bazel.cpus", self.ok("list"))
        self.assertEqual(self.ok("get", "bazel.idle_secs").splitlines(), ["10800", "  (Bazel's default)"])
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
        self.assertEqual(out.splitlines(), ["HOST_CPUS-2 (6 on this machine)", "  (checked in: .bazelrc, line 2)",
                                            "  not used: 2  (home: ~/.bazelrc, line 1)"])
        self.assertEqual(self.ok("get", "machine.disk_cache").splitlines(),
                         ["/goinfre/me/cache", "  (local: .bazelrc.local, line 1)",
                          "  not used: /tmp/home-cache  (home: ~/.bazelrc, line 2)"])

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
        self.assertIn("note: in use instead: 2 (home: ~/.bazelrc, line 1;", " ".join(out.split()))
        self.fits(out)
        out = self.ok("get", "bazel.cpus")
        self.assertEqual(out.splitlines()[0], "2")
        self.assertIn("(home: ~/.bazelrc, line 1;", out)

    def test_every_rc_line_that_sets_it_is_listed_in_the_order_bazel_takes_them(self):
        # The one Bazel takes on the setting's line; under it each other line,
        # the next one Bazel would take first: ~/.bazelrc is read after
        # .bazelrc.local, and a build line wins over a common line wherever.
        with open(os.path.join(self.home, ".bazelrc"), "w", encoding="utf-8") as f:
            f.write("build --local_resources=cpu=2\ncommon --local_resources=cpu=5\n")
        self.write(".bazelrc.local", "build --local_resources=cpu=4\n")
        want = ["  not used: 4  (local: .bazelrc.local, line 1)",
                "  not used: HOST_CPUS-2 (6 on this machine)  (checked in: .bazelrc, line 2)",
                "  not used: 5  (home: ~/.bazelrc, line 2)"]
        out = self.ok("get", "bazel.cpus").splitlines()
        self.assertEqual(out[0], "2")
        self.assertEqual(out[2:], want)
        listed = self.ok("list")
        self.assertIn("\n".join("    " + line for line in want), listed)
        self.fits(listed)

    def test_local_is_this_checkouts_rc_files_and_one_that_wins_over_them_is_in_use(self):
        with open(os.path.join(self.home, ".bazelrc"), "w", encoding="utf-8") as f:
            f.write("build --local_resources=cpu=2\nstartup --max_idle_secs=600\n")
        self.write(".bazelrc.local", "build --local_resources=cpu=4\n")
        out = self.ok("get", "--local", "bazel.cpus").splitlines()
        self.assertEqual(out[:2], ["4", "  (local: .bazelrc.local, line 1)"])
        self.assertTrue(out[2].startswith("  in use: 2  (home: ~/.bazelrc, line 1"), out)
        rc, out, err = self.config("get", "--local", "bazel.idle_secs")
        self.assertEqual((rc, out), (1, ""), err)
        self.assertEqual(err.splitlines(), ["42: bazel.idle_secs is not set in this checkout.",
                                            "    `42 config set bazel.idle_secs VALUE` sets it.",
                                            "  in use: 600  (home: ~/.bazelrc, line 2)"])
        listed = " ".join(self.ok("list", "--local").split())
        self.assertIn("bazel.cpus 4 (local: .bazelrc.local, line 1) in use: 2 (home: ~/.bazelrc, line 1", listed)
        self.assertNotIn("600", listed)
        self.assertIn("bazel.idle_secs (not set) in use: 600 (home: ~/.bazelrc, line 2)",
                      " ".join(self.ok("list", "--local", "--all").split()))
        nothing = os.path.join(self.env.tmp, "no-rc")
        os.makedirs(nothing)
        self.assertEqual(self.ok("get", "--local", "bazel.idle_secs", environ={"HOME": nothing}).splitlines(),
                         ["10800", "  (Bazel's default)"])

    def test_a_named_config_or_a_comment_sets_nothing(self):
        self.write(".bazelrc.local", "build:fast --local_resources=cpu=1\n# build --local_resources=cpu=1\n")
        self.assertEqual(self.ok("get", "bazel.cpus").splitlines()[1:], ["  (checked in: .bazelrc, line 2)"])


class Machine(Toy):
    def test_read_only_and_shown(self):
        self.assertIn("setup.sh", self.refused("set", "machine.root", "/tmp/x"))
        self.assertIn(".bazelrc", self.refused("set", "machine.heap", "2g"))
        self.refused("unset", "machine.disk_cache")
        out = self.ok("get", "machine.heap")
        self.assertEqual(out.splitlines(), ["1024m", "  (checked in: .bazelrc, line 4)"])
        self.assertEqual(self.ok("get", "machine.disk_cache").splitlines()[0], "none")
        self.assertEqual(self.ok("get", "machine.root").splitlines()[0],
                         config.report.state_root(self.ws, self.environ))

    # C_PISCINE_SYSTEM_BAZELRC stands in for /etc/bazel.bazelrc, in the rc
    # files this module reads and in tools/drives.sh, which machine.root asks:
    # a root and a disk cache set there are this checkout's, named from that
    # file.
    def system_rc(self):
        rc = os.path.join(self.env.tmp, "system.bazelrc")
        with open(rc, "w", encoding="utf-8") as f:
            f.write("startup --output_user_root=/toy/system/root\nbuild --disk_cache=/toy/system/cache\n")
        return {"C_PISCINE_SYSTEM_BAZELRC": rc}

    def test_the_system_rc_is_the_knobs_in_drives_sh(self):
        out = self.ok("get", "machine.root", environ=self.system_rc())
        self.assertEqual(out.splitlines()[0], "/toy/system/root")
        self.assertIn("system.bazelrc", out)

    def test_the_system_rc_is_the_knobs_here(self):
        out = self.ok("get", "machine.disk_cache", environ=self.system_rc())
        self.assertEqual(out.splitlines()[0], "/toy/system/cache")
        self.assertIn("system.bazelrc", out)

    def test_list_all_fits_80_columns(self):
        self.ok("set", "login", "jdoe")
        self.ok("set", "email", "a.very.long.name.for.someone@student.42campus.example.com")
        self.ok("set", "bazel.cpus", "4")
        self.fits(self.ok("list", "--all"))
        self.fits(self.ok("list"))



class Probe(config.Setting):
    """A setting this checkout and your user file may both hold, for these tests alone: no real
    one opts in yet. PROBE stands for a variable every reader honours."""

    scopes = ("local", "global")
    store = ".probe"
    help = "A test's own setting: plain, fancy or loud."
    VALUES = ("plain", "fancy", "loud")

    def __init__(self):
        config.Setting.__init__(self, "probe")

    def path(self, cx):
        return os.path.join(cx.ws, ".probe")

    def get(self, cx):
        try:
            with open(self.path(cx), encoding="utf-8") as f:
                v = f.read().strip()
        except FileNotFoundError:
            v = ""
        if v:
            return config.Found(v, ".probe", scope="local")
        return config.Found("plain", "", user=False, scope="default")

    def check_value(self, raw):
        if raw not in self.VALUES:
            raise config.refused("%r is no probe value: %s." % (raw, ", ".join(self.VALUES)))
        return raw

    def check(self, cx, raw):
        return self.check_value(raw)

    def write(self, cx, value):
        config.write_file(self.path(cx), value + "\n")

    def unset(self, cx):
        os.remove(self.path(cx))

    def environment(self, cx):
        v = cx.env.get("PROBE")
        return [config.Found(v, "PROBE", scope="environment")] if v else []


class GlobalOnly(config.Setting):
    """A setting only your user file may hold, as a later api.* would be; no default."""

    scopes = ("global",)
    help = "A test's own setting, in your user file only."

    def __init__(self):
        config.Setting.__init__(self, "probe.everywhere")

    def get(self, cx):
        return None

    def check_value(self, raw):
        return raw


class Scopes(Toy):
    """Your user file beside this checkout's files, over Probe and GlobalOnly."""

    def setUp(self):
        Toy.setUp(self)
        real = config.settings
        patch = mock.patch.object(config, "settings", lambda cx: real(cx) + [Probe(), GlobalOnly()])
        patch.start()
        self.addCleanup(patch.stop)
        self.folder = os.path.join(self.environ["XDG_CONFIG_HOME"], "42")
        self.file = os.path.join(self.folder, "config.yaml")
        self.shown = "~/config/42/config.yaml"  # HOME is self.env.tmp

    def user(self, data):
        os.makedirs(self.folder, exist_ok=True)
        with open(self.file, "wb") as f:
            f.write(data if isinstance(data, bytes) else data.encode())

    def user_bytes(self):
        try:
            with open(self.file, "rb") as f:
                return f.read()
        except FileNotFoundError:
            return None

    def failed(self, *words, **kw):
        rc, out, err = self.config(*words, **kw)
        self.assertEqual(rc, 1, (words, out, err))
        return err

    def test_set_global_writes_your_user_file_and_every_checkout_reads_it(self):
        out = self.ok("set", "--global", "probe", "fancy")
        self.assertEqual(out, "probe (global): (not set) -> fancy\n  written to %s\n" % self.shown)
        self.assertEqual(self.user_bytes(), (config.userconfig.HEADER + "probe: fancy\n").encode())
        self.assertEqual(os.stat(self.folder).st_mode & 0o777, 0o700)
        self.assertEqual(os.stat(self.file).st_mode & 0o777, 0o600)
        self.assertEqual(self.ok("get", "probe").splitlines(), ["fancy", "  (global: %s, line 3)" % self.shown])
        other = os.path.join(self.env.tmp, "ws2")
        shutil.copytree(self.ws, other)
        rc, out, err = run42(["config", "get", "probe"], other, self.environ, ws=other)
        self.assertEqual((rc, out.splitlines()[0]), (0, "fancy"), err)
        listed = self.ok("list")
        self.assertIn("42, this checkout and your user file:\n", listed)
        self.assertIn("\n  probe                  fancy  (global: %s, line 3)\n" % self.shown, listed)

    def test_a_checkouts_own_value_wins_and_every_other_is_shown_not_used(self):
        self.ok("set", "--global", "probe", "fancy")
        self.ok("set", "probe", "loud")
        g = "(global: %s, line 3)" % self.shown
        self.assertEqual(self.ok("get", "probe").splitlines(),
                         ["loud", "  (local: .probe)", "  not used: fancy  %s" % g])
        self.assertIn("\n  probe                  loud  (local: .probe)\n      not used: fancy  %s\n" % g,
                      self.ok("list"))
        self.assertEqual(self.ok("get", "probe", environ={"PROBE": "plain"}).splitlines(),
                         ["plain", "  (environment: PROBE)", "  not used: loud  (local: .probe)",
                          "  not used: fancy  %s" % g])
        self.assertIn("probe: loud -> fancy %s" % g, self.ok("unset", "probe"))
        out = self.ok("unset", "probe")
        self.assertIn("probe is not set here: nothing to unset. Its value fancy comes from %s, line 3: "
                      "`42 config unset --global probe` removes it there." % self.shown, " ".join(out.split()))
        self.assertIn("probe (global): fancy -> plain (default)", self.ok("unset", "--global", "probe"))
        self.assertEqual(self.user_bytes(), config.userconfig.HEADER.encode())

    def test_each_scope_alone(self):
        self.ok("set", "--global", "probe", "fancy")
        self.ok("set", "probe", "loud")
        self.assertEqual(self.ok("get", "--global", "probe").splitlines(),
                         ["fancy", "  (global: %s, line 3)" % self.shown, "  in use: loud  (local: .probe)"])
        self.assertEqual(self.ok("get", "--local", "probe").splitlines(), ["loud", "  (local: .probe)"])
        local = self.ok("list", "--local")
        self.assertIn("\n  probe                  loud  (local: .probe)\n", local)
        self.assertNotIn("fancy", local)
        self.assertNotIn("probe.everywhere", self.ok("list", "--local", "--all"))
        self.assertEqual(self.ok("list", "--global").split("\n\n")[0],
                         "Your user file, which every checkout of yours reads (%s):\n"
                         "  probe                  fancy  (line 3)\n"
                         "      in use: loud  (local: .probe)" % self.shown)
        self.assertIn("\n  probe.everywhere       (not set)", self.ok("list", "--global", "--all"))

    def test_the_flag_goes_anywhere_after_config_and_one_scope_at_a_time(self):
        for words in (("--global", "set", "probe", "fancy"), ("set", "probe", "--global", "loud"),
                      ("set", "probe", "plain", "--global")):
            self.ok(*words)
            self.assertIn(b"probe: " + words[-1 if words[-1] != "--global" else -2].encode(), self.user_bytes())
        err = self.refused("get", "--global", "--local", "probe")
        self.assertIn("not allowed with argument --global", err)
        self.assertIn("`42 help config`", err)

    def test_dry_run_writes_nothing_in_either_scope(self):
        out = self.ok("set", "--global", "--dry-run", "probe", "loud")
        self.assertIn("probe (global): (not set) -> loud", out)
        self.assertIn("nothing written; without it, %s is written." % self.shown, " ".join(out.split()))
        self.assertFalse(os.path.exists(self.folder))
        self.ok("set", "--global", "probe", "loud")
        before = self.user_bytes()
        self.assertIn("nothing written", self.ok("unset", "--global", "--dry-run", "probe"))
        self.assertEqual(self.user_bytes(), before)

    def test_a_setting_whose_readers_read_only_this_checkout_is_refused_global(self):
        for words, says in ((("set", "--global", "login", "jdoe"),
                             "VS Code's 42header extension reads only .vscode/settings.json"),
                            (("get", "--global", "email"), "VS Code's 42header extension reads only"),
                            (("set", "--global", "remote.c-05", URL), "tools/submit.sh reads only .submit-remotes"),
                            (("set", "--global", "bazel.cpus", "2"), "~/.bazelrc is Bazel's own file"),
                            (("set", "--global", "machine.heap", "2g"), "read-only")):
            err = self.refused(*words)
            self.assertIn(says, " ".join(err.split()), words)
            self.fits(err)
        for words, then in ((("set", "--global", "login", "jdoe"), "`42 config set login VALUE` sets it there"),
                            (("get", "--global", "login"), "`42 config get login` shows it")):
            err = " ".join(self.refused(*words).split())
            self.assertIn("login lives in this checkout only:", err, words)
            self.assertIn(then, err, words)
        self.assertFalse(os.path.exists(self.folder))

    def test_a_setting_only_your_user_file_holds(self):
        self.assertIn("`42 config set --global probe.everywhere VALUE`",
                      " ".join(self.refused("set", "probe.everywhere", "x").split()))
        self.refused("get", "--local", "probe.everywhere")
        self.refused("unset", "probe.everywhere")
        self.assertEqual(self.config("get", "probe.everywhere")[0], 1)
        self.ok("set", "--global", "probe.everywhere", "x y")
        self.assertIn(b'probe.everywhere: "x y"\n', self.user_bytes())
        self.assertEqual(self.ok("get", "probe.everywhere").splitlines()[0], "x y")
        self.ok("unset", "--global", "probe.everywhere")
        rc, out, err = self.config("get", "--global", "probe.everywhere")
        self.assertEqual(rc, 1, (out, err))
        self.assertIn("`42 config set --global probe.everywhere VALUE` sets it", " ".join(err.split()))

    def test_the_scope_is_a_flag_not_part_of_the_name(self):
        self.assertIn("`42 config set --global probe VALUE`", self.refused("set", "global.probe", "fancy"))
        self.assertIn("`42 config get --local probe`", self.refused("get", "local.probe"))
        self.assertFalse(os.path.exists(self.folder))

    def test_a_value_it_refuses_writes_nothing(self):
        self.assertIn("no probe value", self.refused("set", "--global", "probe", "nope"))
        # What os.fsdecode makes of an argv byte that is no UTF-8.
        self.assertIn("no UTF-8", self.refused("set", "--global", "probe.everywhere", "caf\udce9"))
        self.assertFalse(os.path.exists(self.folder))

    def test_a_value_written_by_hand_that_42_refuses_is_shown_refused(self):
        self.user("probe: nope\n")
        out = " ".join(self.ok("get", "probe").split())
        self.assertIn("nope (global: %s, line 1, which 42 refuses: 'nope' is no probe value" % self.shown, out)
        self.assertIn("42 refuses it: 'nope' is no probe value", " ".join(self.ok("list", "--global").split()))

    def test_a_user_file_42_will_not_read_breaks_only_what_needs_it(self):
        before = b"probe: fancy\nlevel:\tstrict\n"
        self.user(before)
        self.ok("set", "level", "strict")
        self.assertEqual(self.ok("get", "level").splitlines()[0], "strict")
        why = "%s, line 2: a tab, which YAML takes as no blank: use spaces." % self.shown
        self.assertIn("note: %s Nothing is read from it until that is fixed." % why,
                      " ".join(self.ok("list").split()))
        self.assertEqual(self.ok("get", "probe").splitlines()[0], "plain")
        self.assertIn(why, " ".join(self.ok("get", "probe").split()))
        for words in (("set", "--global", "probe", "loud"), ("unset", "--global", "probe"), ("list", "--global"),
                      ("get", "--global", "probe")):
            err = self.failed(*words)
            self.assertIn(why, " ".join(err.split()), words)
            self.fits(err)
        self.assertEqual(self.user_bytes(), before)

    def test_names_no_setting_reads_there_are_kept_and_shown(self):
        self.ok("set", "login", "marvin")
        self.user("# mine\nprobe: fancy\nprobee: loud\nlogin: jdoe\nremote.c-05: x@y:z\n")
        self.assertIn("%s holds 3 names no setting reads there: `42 config list --global` shows them." % self.shown,
                      " ".join(self.ok("list").split()))
        listed = " ".join(self.ok("list", "--global").split())
        self.assertIn("probee loud (line 3) note: no setting of this 42 has that name: it is kept as it is. "
                      "Did you mean probe?", listed)
        self.assertIn("login jdoe (line 4) note: login lives in this checkout only, and nothing reads it here",
                      listed)
        self.assertIn("note: remote.c-05 lives in this checkout only", listed)
        self.assertEqual(self.ok("get", "login").splitlines()[0], "marvin")
        self.assertIn("%s, line 4 sets it too, and nothing reads it there" % self.shown,
                      " ".join(self.ok("get", "login").split()))
        self.ok("set", "--global", "probe", "loud")
        self.ok("unset", "--global", "probee")
        self.assertEqual(self.user_bytes(), b"# mine\nprobe: loud\nlogin: jdoe\nremote.c-05: x@y:z\n")
        self.assertIn("nothing to unset", self.ok("unset", "--global", "probe.everywhere"))
        self.assertIn("no setting 'nope'", self.refused("unset", "--global", "nope"))

    def test_no_home_is_no_user_file_and_this_checkouts_settings_still_work(self):
        bare = {"HOME": "", "XDG_CONFIG_HOME": ""}
        self.assertIn("HOME is not set", self.failed("set", "--global", "probe", "fancy", environ=bare))
        self.assertIn("HOME is not set", self.failed("list", "--global", environ=bare))
        self.ok("set", "probe", "loud", environ=bare)
        self.assertEqual(self.ok("get", "probe", environ=bare).splitlines(), ["loud", "  (local: .probe)"])

    def test_a_user_file_inside_this_checkout_is_refused(self):
        inside = {"XDG_CONFIG_HOME": self.path("cfg")}
        self.assertIn("inside this checkout", self.failed("set", "--global", "probe", "fancy", environ=inside))
        self.assertFalse(os.path.exists(self.path("cfg")))

    def test_a_dry_run_refuses_what_the_write_would(self):
        inside = {"XDG_CONFIG_HOME": self.path("cfg")}
        real = self.failed("set", "--global", "probe", "fancy", environ=inside)
        self.assertEqual(self.failed("set", "--global", "probe", "fancy", "--dry-run", environ=inside), real)
        self.assertFalse(os.path.exists(self.path("cfg")))
        os.makedirs(self.path("cfg/42"))
        self.write("cfg/42/config.yaml", "probe: fancy\n")
        real = self.failed("unset", "--global", "probe", environ=inside)
        self.assertIn("inside this checkout", real)
        self.assertEqual(self.failed("unset", "--global", "probe", "--dry-run", environ=inside), real)
        self.assertEqual(self.read("cfg/42/config.yaml"), "probe: fancy\n")
        with mock.patch.object(config.userconfig.os, "geteuid", return_value=os.geteuid() + 1):
            real = self.failed("set", "--global", "probe", "fancy")
            self.assertIn("belongs to another user", real)
            self.assertEqual(self.failed("set", "--global", "probe", "fancy", "--dry-run"), real)
        self.assertFalse(os.path.exists(self.folder))

    @unittest.skipIf(os.geteuid() == 0, "root writes into a read-only folder")
    def test_a_write_that_fails_names_your_user_file(self):
        self.ok("set", "--global", "probe", "fancy")
        os.chmod(self.folder, 0o500)
        self.addCleanup(os.chmod, self.folder, 0o700)
        err = self.failed("set", "--global", "probe", "loud")
        self.assertEqual(" ".join(err.split()), "42: could not write %s: Permission denied" % self.shown)

    def test_a_run_given_no_home_has_one_of_its_own_never_a_shared_tmp(self):
        import main
        seen = {}

        def record(argv, env):
            seen.update(env)
            return 0

        with mock.patch.dict(os.environ), mock.patch.object(main, "main", record):
            os.environ.pop("TEST_TMPDIR", None)
            run42(["config", "list"])
        self.assertNotIn(seen["HOME"], ("/tmp", "/tmp/"))
        st = os.stat(seen["HOME"])
        self.assertEqual((st.st_uid, stat.S_IMODE(st.st_mode)), (os.geteuid(), 0o700))
        self.assertEqual(seen["XDG_CONFIG_HOME"], os.path.join(seen["HOME"], ".config"))

    def test_a_relative_xdg_config_home_is_named_as_ignored(self):
        self.ok("set", "--global", "probe", "fancy", environ={"XDG_CONFIG_HOME": "cfg"})
        self.assertTrue(os.path.exists(os.path.join(self.home, ".config", "42", "config.yaml")))
        self.assertIn("XDG_CONFIG_HOME=cfg is no absolute path",
                      " ".join(self.ok("list", environ={"XDG_CONFIG_HOME": "cfg"}).split()))

    def test_help_names_the_settings_your_user_file_may_hold(self):
        rc, text, err = run42(["help", "config"], self.ws, self.environ, ws=self.ws)
        self.fits(text)
        flat = " ".join(text.split())
        self.assertIn("Your user file may hold level, probe, probe.everywhere.", flat)
        self.assertIn("Stored in .probe, or in your user file (--global).", flat)
        self.assertIn("Stored in your user file only (--global).", flat)

    def test_every_list_fits_80_columns(self):
        long_url = "git@git.example.com:you/" + "x" * 90 + ".git"
        self.ok("set", "remote.c-05", long_url)
        self.ok("set", "--global", "probe", "fancy")
        self.ok("set", "probe", "loud")
        self.ok("set", "--global", "probe.everywhere", "y" * 120)
        self.user(self.user_bytes() + b"remote.c-05: " + long_url.encode() + b"\nz" * 1 + b": " + b"w" * 99 + b"\n")
        for words in (("list",), ("list", "--all"), ("list", "--global"), ("list", "--global", "--all"),
                      ("list", "--local")):
            self.fits(self.ok(*words, environ={"PROBE": "plain"}))


class GlobalLevel(Toy):
    """level in your user file: 42 reads it, and the real tools/submit.sh, run with no level
    of its own, stops on it rather than gate on basic. The script only finds the line
    (tools/userconfig_line.awk); these hold what it finds to what 42 reads."""

    def setUp(self):
        Toy.setUp(self)
        self.folder = os.path.join(self.environ["XDG_CONFIG_HOME"], "42")
        self.file = os.path.join(self.folder, "config.yaml")
        self.shown = "~/config/42/config.yaml"  # HOME is self.env.tmp

    def user(self, data):
        os.makedirs(self.folder, exist_ok=True)
        with open(self.file, "wb") as f:
            f.write(data if isinstance(data, bytes) else data.encode())

    def line_of(self, path, name="level"):
        """The line tools/userconfig_line.awk says sets name in path, or None."""
        r = subprocess.run(["awk", "-v", "name=" + name, "-f", self.path("tools/userconfig_line.awk"), path],
                           env=dict(self.environ, LC_ALL="C"), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True, check=False)
        self.assertIn(r.returncode, (0, 1), r.stderr)
        self.assertEqual(r.stderr, "")
        return int(r.stdout) if r.returncode == 0 else None

    def script(self, *argv, **environ):
        """tools/submit.sh -n ARGV over the toy, as `bazel run` would run it: (exit, output). A
        variable given as None is unset."""
        env = dict(self.environ, BUILD_WORKSPACE_DIRECTORY=self.ws, LOGIN42="marvin", EMAIL42="marvin@42.fr",
                   **environ)
        env = {k: v for k, v in env.items() if v is not None}
        r = subprocess.run(["sh", self.path("tools/submit.sh"), "-n"] + list(argv), cwd=self.ws, env=env,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True,
                           errors="replace", check=False)
        return r.returncode, r.stdout

    def test_the_script_finds_the_line_42_reads_in_every_file_42_reads(self):
        import userconfig
        import userconfig_corpus
        path = os.path.join(self.env.tmp, "file.yaml")
        files = names = 0
        for label, data, want in userconfig_corpus.CASES:
            if isinstance(want, userconfig_corpus.Refused):
                continue
            with open(path, "wb") as f:
                f.write(data)
            entries = userconfig.parse(data)
            for name in sorted(set(userconfig_corpus.NAMES) | set(entries)):
                self.assertEqual(self.line_of(path, name), entries[name][1] if name in entries else None,
                                 (label, name))
                names += 1
            files += 1
        self.assertGreater(files, 40)
        self.assertGreater(names, 400)

    def test_a_level_line_42_refuses_is_found_too_and_a_line_that_only_mentions_it_is_not(self):
        import userconfig
        path = os.path.join(self.env.tmp, "file.yaml")
        # What someone could write meaning a level: 42 refuses each file, or
        # reads the level, so neither of the two gates on basic over it.
        for data in (b"  level: strict\n", b'"level": strict\n', b"'level': strict\n", b"- level: strict\n",
                     b"{level: strict}\n", b"level : strict\n", b"level:\tstrict\n", b"level:strict\n",
                     b"\xef\xbb\xbflevel: strict\n", b"level: strict\r\n", b"--- level: strict\n",
                     b"probe: x\n\tlevel: strict\n", b"level: strict\nlevel: robust\n", b"level:\n",
                     b"level: no\n", b"# mine\nlevel: \xff\n",
                     # A line break YAML reads where awk sees none: CR, NEL, LS, PS.
                     b"x: y\rlevel: strict\n", b"# mine\rlevel: strict\r", b"\xc2\x85level: strict\n",
                     b"x: y\xe2\x80\xa8level: strict\n", b"x: y\xe2\x80\xa9level: strict\n",
                     # A tag, an anchor, an explicit key, a flow mapping of two.
                     b"!!str level: strict\n", b"&a level: strict\n", b"? level\n: strict\n",
                     b"{a: 1, level: strict}\n"):
            with open(path, "wb") as f:
                f.write(data)
            self.assertIsNotNone(self.line_of(path), data)
            try:
                self.assertIn("level", userconfig.parse(data), data)
            except userconfig.Bad:
                pass
        for data in (b"# level: strict\n", b"  # level: strict\n", b"levels: strict\n", b"Level: strict\n",
                     b'probe: "level: x"\n', b"probe: x # level: y\n", b"remote.c-05: level@host:level\n",
                     b"mylevel: strict\n", b"level.x: strict\n", b"---\n", b"",
                     b"probe: x\r\n# level: y\r\n", b"probe: level\r\n",
                     # In a line 42 refuses, too: a word that holds it, a comment after ---.
                     b"  mylevel: strict\n", b"{my-level: strict}\n", b"--- # level: strict\n"):
            with open(path, "wb") as f:
                f.write(data)
            self.assertIsNone(self.line_of(path), data)

    def test_the_script_run_with_no_level_of_its_own_stops_on_a_level_in_your_user_file(self):
        self.assertEqual(self.script()[0], 0)
        self.user("# mine\nprobe: x\nlevel: strict\n")
        rc, out = self.script()
        self.assertEqual(rc, 2, out)
        flat = " ".join(out.split())
        self.assertIn("submit.sh: your user file sets a level, and only 42 reads that file: %s, line 3 "
                      "`42 submit` passes the level on as --gate-level." % self.shown, flat)
        self.fits(out)
        for argv, environ in ((["--gate-level", "strict"], {}), ([], {"SUBMIT_GATE": "robust"}), (["--no-gate"], {})):
            rc, out = self.script(*argv, **environ)
            self.assertEqual(rc, 0, (argv, environ, out))
            self.assertNotIn("user file", out)
        self.write(".submit-level", "complete\n")
        self.assertEqual(self.script()[0], 0)
        self.write(".submit-level", "\n")
        self.assertEqual(self.script()[0], 2)
        self.user(b"# mine\rlevel: strict\r")
        self.assertEqual(self.script()[0], 2)

    def test_a_user_file_the_script_cannot_look_into_stops_it_too(self):
        # A finder that failed is no "no level line": the gate would run on
        # basic over a file that may say otherwise.
        self.user("level: strict\n")
        os.remove(self.path("tools/userconfig_line.awk"))
        rc, out = self.script()
        self.assertEqual(rc, 2, out)
        self.assertIn("submit.sh: could not look for a level in your user file (above): %s" % self.shown,
                      " ".join(out.split()))
        self.fits(out)

    def test_the_script_looks_for_your_user_file_where_42_does(self):
        self.user("level: strict\n")
        here = {"HOME": self.env.tmp, "XDG_CONFIG_HOME": self.environ["XDG_CONFIG_HOME"]}
        elsewhere = os.path.join(self.env.tmp, "elsewhere")
        os.makedirs(os.path.join(elsewhere, ".config", "42"))
        shutil.copy(self.file, os.path.join(elsewhere, ".config", "42", "config.yaml"))
        for environ, stops in ((here, True),
                               ({"HOME": elsewhere, "XDG_CONFIG_HOME": ""}, True),
                               ({"HOME": elsewhere, "XDG_CONFIG_HOME": "relative"}, True),
                               ({"HOME": self.env.tmp, "XDG_CONFIG_HOME": ""}, False),
                               ({"HOME": "relative", "XDG_CONFIG_HOME": ""}, False),
                               ({"HOME": "", "XDG_CONFIG_HOME": ""}, False),
                               ({"HOME": None, "XDG_CONFIG_HOME": self.environ["XDG_CONFIG_HOME"]}, True),
                               ({"HOME": None, "XDG_CONFIG_HOME": None}, False)):
            rc, out = self.script(**environ)
            self.assertEqual(rc, 2 if stops else 0, (environ, out))
            self.assertEqual("your user file sets a level" in out, stops, (environ, out))
            # run42 gives a HOME of its own to an env with none: "" is none to 42.
            given = {k: "" if v is None else v for k, v in environ.items()}
            rc, got, err = run42(["config", "get", "level"], self.ws, dict(self.environ, **given), ws=self.ws)
            self.assertEqual("(global: " in " ".join(got.split()), stops, (environ, got, err))

    def test_42_config_shows_the_level_42_test_runs_wherever_it_is_set(self):
        # Two writers of one order: Setting.layers over SCOPES, and
        # workspace.level_source, which cannot import config.
        import workspace
        for local, user, gate in itertools.product((None, "robust"), (None, "strict"), (None, "complete")):
            if local:
                self.write(".submit-level", local + "\n")
            elif os.path.exists(self.path(".submit-level")):
                os.remove(self.path(".submit-level"))
            if user:
                self.user("level: %s\n" % user)
            elif os.path.exists(self.file):
                os.remove(self.file)
            environ = dict(self.environ, **({"SUBMIT_GATE": gate} if gate else {}))
            want = workspace.resolve_level(None, environ, self.ws)
            rc, out, err = run42(["config", "get", "level"], self.ws, environ, ws=self.ws)
            self.assertEqual(out.splitlines()[0], want[0], (local, user, gate, out, err))

    def test_level_set_global_is_checked_and_shown_below_what_wins_over_it(self):
        err = " ".join(self.refused("set", "--global", "level", "strct").split())
        self.assertIn("'strct' is not a level. The levels are basic, strict, robust, complete, all. "
                      "Did you mean strict?", err)
        self.assertFalse(os.path.exists(self.folder))
        self.ok("set", "--global", "level", "strict")
        g = "(global: %s, line 3)" % self.shown
        self.assertEqual(self.ok("get", "level").splitlines(), ["strict", "  " + g])
        self.ok("set", "level", "complete")
        self.assertEqual(self.ok("get", "level").splitlines(),
                         ["complete", "  (local: .submit-level)", "  not used: strict  " + g])
        self.assertEqual(self.ok("get", "level", environ={"SUBMIT_GATE": "robust"}).splitlines(),
                         ["robust", "  (environment: SUBMIT_GATE)", "  not used: complete  (local: .submit-level)",
                          "  not used: strict  " + g])
        self.assertIn("level: complete -> strict " + g, self.ok("unset", "level"))
        self.assertIn("level (global): strict -> basic (default)", self.ok("unset", "--global", "level"))

    def test_a_user_file_42_cannot_read_says_what_stops_while_it_would_decide(self):
        self.user("level: no\n")
        stops = ("`42 test`, `42 submit`, `42 watch`, `42 clues` and a bare `42 norm` stop until it is "
                 "fixed, since nothing nearer sets level.")
        self.assertIn(stops, " ".join(self.ok("list").split()))
        self.assertIn(stops, " ".join(self.ok("get", "level").split()))
        self.ok("set", "level", "robust")
        self.assertNotIn(stops, " ".join(self.ok("list").split()))
        self.assertNotIn(stops, " ".join(self.ok("get", "level").split()))
        out = self.ok("unset", "level")
        self.assertIn(stops, " ".join(out.split()))
        self.fits(out)
        self.ok("set", "level", "robust")
        self.assertIn("Nothing is read from it until that is fixed.", " ".join(self.ok("list").split()))


class Submit(Toy):
    """`42 submit c-05 URL` saves the URL through config's writer, then pushes there."""

    def setUp(self):
        Toy.setUp(self)
        shutil.copy(os.path.join(WS, "tools", "defs_levels.bzl"), self.path("tools/defs_levels.bzl"))
        for mod in (C05, "c-piscine/c-piscine-c-06"):
            self.write(mod + "/BUILD.bazel", "subject(\n    exercises = {},\n)\nc_levels(\n)\n")
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

    def test_a_level_from_your_user_file_is_passed_on_and_no_other_is(self):
        # The script reads SUBMIT_GATE and .submit-level itself, and so says
        # what they hold; your user file only 42 reads.
        self.assertEqual(self.submit()[0], 0)
        folder = os.path.join(self.environ["XDG_CONFIG_HOME"], "42")
        os.makedirs(folder)
        with open(os.path.join(folder, "config.yaml"), "w") as f:
            f.write("level: strict\n")
        self.assertEqual(self.submit()[0], 0)
        self.assertEqual(self.submit("--level", "robust")[0], 0)
        self.write(".submit-level", "robust\n")
        self.assertEqual(self.submit()[0], 0)
        self.assertEqual(self.pushed(), ["run //tools:submit -- " + C05,
                                         "run //tools:submit -- %s --gate-level strict" % C05,
                                         "run //tools:submit -- %s --gate-level robust" % C05,
                                         "run //tools:submit -- " + C05])
        os.remove(self.path(".submit-level"))
        with open(os.path.join(folder, "config.yaml"), "w") as f:
            f.write("level: no\n")
        rc, out, err = self.submit()
        self.assertEqual(rc, 2, (out, err))
        self.assertIn("~/config/42/config.yaml, line 1: YAML reads no", " ".join(err.split()))
        self.fits(err)
        self.assertEqual(len(self.ran), 4)

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
