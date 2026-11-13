"""shell_exercise: a shell exercise, run from its generator in a scratch folder.

Loaded by the files above it, and re-exported by tools/defs.bzl, the one
file a BUILD file loads.
"""

load(":defs_contract.bzl", _entry = "entry", _zone = "zone")
load(":defs_levels.bzl", _prefix = "prefix")
load(":defs_test.bzl", "shell_word", _test = "test")
load(":defs_toolchain.bzl", _DIFF = "DIFF", _SHELLCHECK = "SHELLCHECK")

def twin_strays(files, readme):
    """The files in a twin's own tests/exNN/ that no target reads.

    shell_exercise's twin_of reads a twin's tests from the exercise it
    repeats, so its own folder holds a README and nothing else, and exNN_twin
    names anything more. What an editor leaves beside a file it has open is
    not "anything more": vim's swap file (.README.md.swp) and its write probe
    (4913), emacs's backup (README.md~), autosave (#README.md#) and lock
    (.#README.md), JetBrains' safe-write copies. Counting those made opening
    the README the folder asks you to read a red, or, when this was a load
    error, took down every target in the package. A dotfile is never a test
    file here, so every dotfile is left out, .DS_Store included.

    Public so //tools/tests:starlark_unit can check it at load time, in both
    directions: an editor's file is no stray, a test file is.

    Args:
      files: the folder's files, as native.glob returns them.
      readme: the README's path, which is no stray either.

    Returns:
      The strays, in the order given.
    """
    strays = []
    for f in files:
        base = f.rsplit("/", 1)[-1]
        if f == readme or base.startswith(".") or base.endswith("~") or base == "4913":
            continue
        if base.startswith("#") and base.endswith("#"):
            continue
        if base.endswith("___jb_tmp___") or base.endswith("___jb_old___"):
            continue
        strays.append(f)
    return strays


def shell_call_problem(num, mode, stable, wording):
    """What is wrong with how a shell_exercise call says `stable` and `wording`.

    stable: a generator runs again on every generate and every submit, so
    the turn-in pushed is a later run's, never the one that was tested. Where
    the subject fixes one file every run must write again, byte for byte, the
    check compares two runs (ck_stable). No exercise does today: Shell 00
    ex03's key is made by the generator, which is the exercise, so two runs
    differ by design (the owner's decision, 2026-10-04). A generator is this
    repo's way of turning an exercise in, not the subject's, so nothing else
    is graded on it. Defaulted, the next fixed-file exercise would go
    unchecked with nothing said: so a check-mode call says True or False, and
    the author of each new one decides. A diff-mode run is compared with a fixed expected
    file, so a turn-in that differs from run to run fails there anyway.

    wording: {key: words}, each key a shell name, each value one line.

    Public so //tools/tests:starlark_unit can check it at load time.

    Args:
      num: the exercise's number, for the message.
      mode: "diff" or "check".
      stable: True, False, or None when the call does not say.
      wording: the call's wording, or None.

    Returns:
      The message to fail with, or "" when the call is sound.
    """
    if stable not in (None, True, False):
        return ("shell_exercise(num = \"%s\", stable = %r): True or False." % (num, stable))
    if stable and mode != "check":
        return (("shell_exercise(num = \"%s\", stable = True): the check script compares " +
                 "the two runs (ck_stable), so it needs mode = \"check\".") % num)
    if stable == None and mode == "check":
        return (("shell_exercise(num = \"%s\", mode = \"check\"): say stable = True or " +
                 "stable = False. A generator runs again on every generate and every " +
                 "submit, so the turn-in pushed is a later run's, not the one tested. " +
                 "True where the subject fixes one file every run must write again, " +
                 "byte for byte, and the check then calls ck_stable; False anywhere " +
                 "else, including a turn-in the exercise has the generator make afresh " +
                 "(Shell 00 ex03's key), since generators are this repo's and not the " +
                 "subject's.") % num)
    if wording and mode != "check":
        return (("shell_exercise(num = \"%s\", wording = ...): a check script quotes " +
                 "the subject's words (ck_wording), so it needs mode = \"check\".") % num)
    for w_key, w_text in sorted((wording or {}).items()):
        key_ok = (type(w_key) == "string" and w_key != "" and
                  (w_key[0].isalpha() or w_key[0] == "_") and
                  w_key.replace("_", "a").isalnum())
        if not key_ok or type(w_text) != "string" or not w_text or "\n" in w_text:
            return (("shell_exercise(num = \"%s\"): wording maps a key made of letters, " +
                     "digits and _ to the subject's words on one line, got %r: %r") %
                    (num, w_key, w_text))
    return ""

def shell_tags_problem(num, tags, run_tags):
    """What is wrong with a shell_exercise call's `tags` and `run_tags`, or "".

    A check that reads the machine it runs on -- Shell 01 ex01's user
    database, ex04's network interfaces, ex07's /etc/passwd -- is tagged
    "env", and it runs on every machine, at its level, like every other
    test: what a machine cannot show it, the check says by name with
    ck_skipped, which NO_SKIP=1 turns red. Made "manual" instead, it runs
    on no machine and in no gate, and Shell 01 ex04 sat there with no check
    at any level (finding 002). So "env" and "manual" together are refused.
    run_tags holds what a run of the turn-in needs ("no-sandbox", where the
    run has to see the machine as it is), and "manual" is not that. The
    tests that run an "env" turn-in are "external" too, from the macro:
    what they read of the machine is no input of Bazel's, and a cached
    PASS outlived a change to it (V102).

    Public so //tools/tests:starlark_unit can check it at load time.

    Args:
      num: the exercise's number, for the message.
      tags: the call's tags, or None.
      run_tags: the call's run_tags, or None.

    Returns:
      The message to fail with, or "" when the call is sound.
    """
    if "env" in (tags or []) and "manual" in (tags or []):
        return (("shell_exercise(num = \"%s\", tags = %r): a check that reads the " +
                 "machine runs on every machine, and says what a machine cannot show " +
                 "it with ck_skipped, which NO_SKIP=1 turns red; manual would run it " +
                 "on none, and in no gate (finding 002).") % (num, tags))
    if "manual" in (run_tags or []):
        return (("shell_exercise(num = \"%s\", run_tags = %r): run_tags holds what a " +
                 "run of the turn-in needs (\"no-sandbox\"); manual is a test's place " +
                 "in the suites, which `tags` says, and only with its reason in " +
                 "_MANUAL.") % (num, run_tags))
    return ""

def redirect_problem(num, mode, redirect):
    """What is wrong with a shell_exercise call's `redirect`, or "" when it is sound.

    redirect: {path: fixture}, one entry. The turn-in's runs read the fixture
    (a file under the exercise's tests/exNN/) when they open the path, through
    //tools:path_redirect.so, which shell_check.sh's ck_run loads -- so only
    a check-mode call has the runs it applies to. The path is the one the
    subject fixes, absolute, with no "=" (the runner takes "path=fixture" as
    one word); the fixture is relative to tests/exNN/ and stays inside it.

    These were four fail()s inline in shell_exercise, reached by Shell 01
    ex07's one sound call and by nothing else: a value now, so that
    //tools/tests:starlark_unit feeds it every broken call, both ways.

    Args:
      num: the exercise's number, for the message.
      mode: "diff" or "check".
      redirect: the call's redirect, or None.

    Returns:
      The message to fail with, or "" when the call is sound.
    """
    if redirect == None:
        return ""
    where = "shell_exercise(num = \"%s\", redirect = %r)" % (num, redirect)
    if type(redirect) != "dict" or len(redirect) != 1:
        return "%s: one {path: fixture} entry; the preload library redirects one path." % where
    r_from, r_to = redirect.items()[0]
    if type(r_from) != "string" or not r_from.startswith("/") or "=" in r_from or r_from == "/":
        return ("%s: the path the program opens is the subject's, absolute and with no " +
                "\"=\" in it, like \"/etc/passwd\".") % where
    if type(r_to) != "string" or not r_to or r_to.startswith("/") or ".." in r_to.split("/") or r_to.endswith("/"):
        return ("%s: the fixture is a file under tests/ex%s/, named relative to it, like " +
                "\"passwd\".") % (where, num)
    if mode != "check":
        return ("%s: a redirect is applied by a check script's ck_run, so it needs " +
                "mode = \"check\".") % where
    return ""

def twin_fixture(label, t_pkg, t_ex):
    """Where one of a twin's fixtures is read from.

    A twin's call names its fixtures the way its twin's call does, word for
    word (//tools:conventions compares the two calls). A label is relative to
    the package that holds the call, so the same words name a file of each
    project. One inside the repeated exercise's tests/exMM/ is one of its
    tests, and a twin reads its tests from there, as it reads the check
    script: the twin's own folder holds only its README, and a fixture copied
    into it would be a stray (exNN_twin) and a copy (conventions). Any other
    is this project's own, as Shell 00 ex07's resources.tar.gz is: the
    student saves it beside each project's BUILD.

    Public so //tools/tests:starlark_unit can check it at load time.

    Args:
      label: the fixture as the call names it.
      t_pkg: the package twin_of names, as //<module>.
      t_ex: the exercise twin_of names, as exMM.

    Returns:
      The label to stage.
    """
    rel = label[1:] if label.startswith(":") else label
    if rel.startswith("tests/%s/" % t_ex):
        return "%s:%s" % (t_pkg, rel)
    return label

def shell_exercise(
        num,
        mode,
        deliverable = None,
        expected = "expected.txt",
        check = "check.sh",
        run = False,
        interp = None,
        env = None,
        fixtures = None,
        oracle = False,
        readings = None,
        redirect = None,
        twin_of = None,
        stable = None,
        script = None,
        wording = None,
        tags = None,
        run_tags = None):
    """A shell-piscine exercise.

    The student's answer is the generator script generators/exNN.sh, which creates
    the exercise's deliverable(s) in its current directory. We run it in a scratch
    dir and validate the result (see tools/shell_test.sh).

    Emits:
      exNN_norm    syntax-check the generator (sh -n); green on a stub.
      exNN_lint    the pinned shellcheck on the generator, and on the script it
                   writes where `script` says the turn-in is one, at robust.
                   See `script`.
      exNN_posix   where /bin/sh runs that script (`script` "sh" or "./name"):
                   the POSIX-undefined constructs in it, at strict. See `script`.
      exNN_output  run the generator, then either diff the deliverable against
                   tests/exNN/<expected> (mode="diff") or run tests/exNN/<check>
                   (mode="check").
      exNN_files   run the generator, then require that it left NOTHING behind
                   but its deliverable. See `files`.
      exNN_<reading>
                   one per entry of `readings`: the same run, graded by another
                   check script, at strict. See `readings`.
      exNN_twin    a twin only: its own tests/exNN/ holds its README and
                   nothing else, at complete. See `twin_of`.

    Args:
      num: exercise number, e.g. "00".
      mode: "diff" or "check".
      deliverable: produced filename. Default: the one file the contract's
        `files` names (required for "diff"; the check globs it itself for
        awkward names, so it is optional for "check"). A name given here must
        be one the contract names.
      expected: diff mode expected-output file under tests/exNN/.
      check: check mode property script under tests/exNN/.
      run: diff mode — execute the deliverable and diff its stdout (else cat it).
        It runs as `/bin/sh name`, never through its #! line, after a check
        that /bin/sh can parse it, the way a check script's ck_run runs one
        (docs/reference.md, "Shell turn-ins").
      interp: run the deliverable with this interpreter instead of /bin/sh,
        for a subject that names another shell. It gets no parse check.
      env: list of "K=V" controlled environment entries.
      fixtures: list of file labels staged into the scratch dir before running.
      THE FILES LAYER, exNN_files, is emitted wherever the contract names the
        exercise's file. Both shell subjects say on p.3 "You must not leave any
        additional files in your directory other than those specified in the
        assignment", and neither module checked it -- appending one `echo
        leftover > oops.txt` to a generator left every layer green, and
        //tools:submit pushes what is there with `git add -A --force`.

        It FAILS on the extras half only: the deliverable is `--turnin`,
        listed as present or as "not produced", with extras strict. A
        deliverable that was not produced at all is already the output layer's
        finding, stated precisely and with that exercise's clues attached, so
        failing it here as well would print two reds for one cause -- and on
        the template branch, where every generator is a skeleton, it would
        print one per exercise for a state the module is supposed to be in.
        The report still names it, so a green files layer never reads as
        "exactly the files the subject asks for" over a turn-in that is not
        there (finding 017). Its heading names the generator, whose output in
        a scratch folder is what it lists: the deliverable/ folder on disk is
        never read (tools/shell_test.sh).

        A contract entry with files = None emits none: that is where the
        deliverable's NAME is itself the answer, the one case that cannot be
        written down here -- shell-01 ex05's file is named with shell
        metacharacters, and naming it in a BUILD file would hand over the
        exercise. A layer with no name to allow would report the exercise's
        own answer as a file nobody asked for.
      oracle: check mode only. True hands the check the //oracle binary as
        $ORACLE, for an exercise whose expected value can be neither written
        down nor built by a fixture -- shell-01 ex01's group list lives in the
        machine's user database. The alternative, computing it in the check,
        puts the answer in a file the template ships. The check calls
        ck_oracle (tools/shell_check.sh) before it reads $ORACLE.
      redirect: check mode only. {path: fixture}: the turn-in's runs read the
        fixture, a file under the exercise's tests/exNN/, when they open the
        path -- one entry. For a subject that fixes the file its program reads
        (Shell 01 ex07's /etc/passwd), where what a machine keeps there hides
        some of the exercise: a laptop's has no comment line to remove. The
        check's ck_run loads //tools:path_redirect.so into each run of the
        turn-in, and nothing else, once the runner has proven it works on
        this machine (shell_test.sh's prove_redirect); `ck_run --no-redirect`
        runs it on the machine's own file. A program that reads the file
        without opening it -- getent, through the C library's own lookups --
        is not redirected; see tools/path_redirect.c.
      readings: check mode only. {name: script}: a check script under
        tests/exNN/ for a reading of the subject that its words allow but do
        not settle, emitted as exNN_<name> one level up, at strict. An
        ambiguous sentence is read at strict, never at basic: the output
        layer grades only what every reading requires, so no reading the
        subject leaves open can fail correct work in a beginner's path or at
        the submit gate. Shell 00 ex08's "no ';'" is the example -- no ';'
        joining two commands at basic, no ';' character at all here -- and
        tests/ex08/literal.sh says why at its top. The target runs the same
        generator with the same fixtures, env and oracle, and prints no
        clues.tsv: that file is about the exercise, and each check line here
        says itself what reading it applies.

        The names in use: `literal` (the subject's words taken word for
        word), `regular` ("files" read as regular files only, where a
        directory can carry a matching name) and `newest_first` (an order
        by date that names no direction, read as `ls` sorts by time). A
        reading's name ends its target's, so it is a suffix in
        _SUFFIX_LAYER, at strict, with its row in docs/reference.md
        ("Target names"): c_levels()' audit fails a package whose target
        ends in none. Reuse one before adding one; `grep -rn 'readings = {'`
        lists where each is used.

        Named exNN_literal, not exNN_literal_output, although it carries the
        output tag: tools/first_red.sh reads a target's layer from the END of
        its name, and "..._output" would file a red reading under "your next
        exercise, not written yet" when the exercise passes at basic. A tail
        it does not know lands under "also red", which is what this is.
      twin_of: the exercise this one repeats, as the label of its suite in
        another module -- Piscine Reloaded's ex03 is
        `twin_of = "//c-piscine/c-piscine-shell-01:ex02"`. Its tests are then
        read from THAT exercise's tests/ folder: the expected file, the check
        script, every reading and the clues. One copy serves both projects.
        They used to be copied, and a copy is two files a fix has to find: the
        Reloaded half of a finding was fixed in one and not the other.

        What the call says comes with the tests, so a twin's call says it
        again, the same way: mode, readings, oracle, redirect, env, fixtures,
        files, script, stable and tags. Only the deliverable's name may
        differ (Reloaded's archive is exo.tar, Shell 00's exo2.tar), and the
        subject's own words (`wording`). A fixture in the repeated
        exercise's tests/exMM/ is one of its tests and is read from there;
        any other fixture is this project's own (twin_fixture). A test file
        or an argument that has to differ is not a twin's; give that
        exercise tests of its own. This exercise's own tests/exNN/ keeps
        only a README saying where its tests are, so the per-exercise suite
        still finds it (c_levels) and a student who opens the folder is not
        left with nothing. Any other file there, and a missing README, fail
        exNN_twin, since no target would read it; an editor's own files
        there do not (twin_strays). That target sits at complete, under the
        `selftest` tag: it guards the harness's own files, not the turn-in,
        and a rule of this repo's own stays out of basic and the submit gate
        (docs/reference.md, "Run contract"). That the README names the
        folder twin_of reads, and that this call says what its twin's says,
        are //tools:conventions' to check, because a macro can read neither
        a file nor another package's call.
      stable: True or False, and a check-mode call must say which (a
        diff-mode call leaves it out). A generator runs on every generate
        and every submit, so a turn-in that comes out different each time is
        never the file that was tested. True where the subject fixes one
        file every run must write again, byte for byte, and False anywhere
        else, including a turn-in the exercise has the generator make afresh
        (Shell 00 ex03's key), since generators are this repo's way of
        turning an exercise in, not the subject's (shell_call_problem says why
        it is never defaulted). True
        runs the generator a second time, in another empty directory, under
        an empty HOME and TMPDIR of its own (what the first run kept there
        is not the second's), before the check, and the check compares the
        two turn-ins with shell_check.sh's ck_stable -- which it must call
        (//tools:conventions holds the two together, and the check refuses
        either without the other when it runs).
      script: None, "sh", "./name" or "bash": whether the turn-in is a
        script, and how the subject has it run. All three shell subjects say
        shell exercises must be executable with /bin/sh, and an example can
        say more:
          "sh"      no example runs it (Shell 00 ex04, ex08; Shell 01 ex04,
                    ex08): /bin/sh, by the general rule;
          "./name"  the example runs it as ./name (Shell 01 ex01, ex02, ex03,
                    ex06, ex07): run that way, its own #! line picks the
                    shell, and /bin/sh where it names none or names sh (a
                    carriage return ending the line, from CRLF line ends,
                    is not part of the name). Its check asks for the execute bit (ck_executable), and
                    //tools:conventions holds the two together;
          "bash"    the example runs `bash name` (Shell 00 ex05, ex06).
        None (the default) for a turn-in that is not one: an archive, a key,
        a text file. What `script` (and a "./name" script's #! line) says
        decides which target below reports a finding, and nothing else:
        every target that runs the script runs it with /bin/sh, the general
        rule (ck_run). For a script, its lint splits by whose rule each
        finding is (docs/reference.md, "Shell turn-ins"):
          basic   /bin/sh can parse it -- the check script's ck_sh_parses,
                  in exNN_output; //tools:conventions holds a call that says
                  `script` and a check that asks it together;
          strict  exNN_posix ("sh" and "./name"): where /bin/sh runs it, the
                  constructs POSIX leaves undefined (shellcheck's SC3xxx),
                  since whether the grader's sh accepts one is not certain.
                  A "./name" script whose #! line names another shell (bash)
                  is run by that shell when typed as ./name, so this passes
                  it and says so (exNN_output still runs it with /bin/sh);
          robust  exNN_lint: every other shellcheck warning, and SC3xxx too
                  for a script bash runs -- rigour this repo adds. The
                  generator's own lint is here as well, for every exercise:
                  the generator is this repo's way of turning a shell
                  exercise in, not the subject's.
        Both targets run the generator to get the script; one that fails, or
        writes nothing, is exNN_output's to report, so they SKIP it (and
        NO_SKIP=1 makes that a failure). They carry `tags`, as exNN_files
        does, since they run the generator too.
      wording: check mode only. {key: words}: the subject's own words for a
        sentence its check scripts quote, exported to each (exNN_output and
        every reading) as $SHELL_CHECK_WORDING_<key>, which shell_check.sh's
        ck_wording reads. It is how one check serves twins whose subjects
        word the same sentence differently -- Shell 01 ex02's "all files
        ending with .sh", Piscine Reloaded ex03's "all file names that end
        with ".sh"" -- so each target quotes its own subject's sentence and
        not the other project's. It is the one argument besides `num` and
        `deliverable` a twin's call may give differently from its twin's
        (//tools:conventions). A check that asks for a key the call does not
        give stops with exit 2.
      tags: extra tags on the tests that judge the turn-in -- its output
        test, each reading, its files layer, and its lint and posix layers
        where it is a script (they run the generator too) -- and not on its
        norm layer or a twin's guard, which read the same files on every
        machine: ["env"] says the exercise reads the machine it runs on. "manual"
        keeps a test out of every suite and every gate, so it is for a test
        no machine can be trusted to run (listed in _MANUAL, with its reason
        in docs/reference.md) -- never for one tagged "env", which runs on
        every machine and says what a machine cannot show it with
        ck_skipped (shell_tags_problem). With "env", the tests that run
        the turn-in are also "external", which Bazel never serves from its
        cache: what they read of the machine is no input of Bazel's (V102).
      run_tags: extra tags on the tests that RUN the turn-in -- its output
        test and each reading -- and not on its files layer, which only runs
        the generator: ["no-sandbox"] where the run has to see the machine as
        it is (Shell 01 ex04's network interfaces). tools/tests/macro_fixtures
        proves where each lands (:shell_tags).
    """
    e = _entry(num, "shell_exercise")  # first: a contract error names this macro
    ex = _prefix(num)
    gen = "generators/%s.sh" % ex
    if e["dir"] != ex + "/":
        fail(("shell_exercise(num = \"%s\"): the contract's turn-in directory is %r. " +
              "A generated turn-in is written to deliverable/%s (tools/generate.sh), " +
              "so a shell exercise's subject line must say \"%s/\".") % (num, e["dir"], ex, ex))
    named = e["files"]
    if deliverable == None and named and len(named) == 1:
        deliverable = named[0]
    elif deliverable != None and deliverable not in (named or []):
        fail(("shell_exercise(num = \"%s\", deliverable = %r): the contract's files " +
              "do not name it. The turn-in is the subject's, written once in subject().") %
             (num, deliverable))
    files = named != None
    problem = (shell_call_problem(num, mode, stable, wording) or redirect_problem(num, mode, redirect) or
               shell_tags_problem(num, tags, run_tags))
    if problem:
        fail(problem)
    if script not in (None, "sh", "./name", "bash"):
        fail(("shell_exercise(num = \"%s\", script = %r): None, \"sh\", \"./name\" or " +
              "\"bash\" -- how the subject has the turn-in run.") % (num, script))
    if script and not deliverable:
        fail(("shell_exercise(num = \"%s\", script = %r): the script's lint needs its name, " +
              "and the contract names no one file.") % (num, script))

    # The generator as a glob finds it. It is the student's answer, so a
    # missing one is a missing turn-in: every layer below is then a "not
    # turned in" test (see _test), never a declared input Bazel fails to find
    # while analysing the package.
    turnin = _zone([gen])
    where = "generators"
    env = env or []
    fixtures = fixtures or []
    extra_tags = tags or []
    # A run of an "env" turn-in reads what Bazel does not track (V102).
    run_extra = extra_tags + (run_tags or []) + (["external"] if "env" in extra_tags else [])

    # Every test file of this exercise is visible to other packages, so a twin
    # (above) can name it and //tools/tests can run a check script on fixtures
    # of its own. Test files are shipped with the harness anyway; what this
    # opens is only that another BUILD file may reference them.
    native.exports_files(
        native.glob(["tests/%s/**" % ex], allow_empty = True),
        visibility = ["//visibility:public"],
    )

    # Where this exercise's test files are: its own tests/exNN/, or its twin's.
    if twin_of:
        t_pkg, _, t_ex = twin_of.partition(":")
        if not t_pkg.startswith("//") or not t_ex.startswith("ex") or not t_ex[2:].isdigit():
            fail(("shell_exercise(num = \"%s\"): twin_of must name the exercise " +
                  "this one repeats as //<module>:exNN, got %r") % (num, twin_of))
        if t_pkg == "//" + native.package_name():
            fail(("shell_exercise(num = \"%s\"): twin_of names an exercise of " +
                  "this same module; a twin is another project's.") % num)
        t_dir = "%s:tests/%s/" % (t_pkg, t_ex)
        fixtures = [twin_fixture(f, t_pkg, t_ex) for f in fixtures]

        # The twin's own folder holds its README and nothing else. A check
        # script or clues file copied back into it is read by no target, so
        # whoever edits it fixes nothing and is told nothing -- which is how
        # the copies drifted in the first place. exNN_twin says so the moment
        # one appears, and says it for this exercise alone: this was a fail()
        # once, and the swap file vim writes beside a README it has open made
        # every target of the package fail to load, the C exercises' too.
        # An editor's own files are not strays (twin_strays). It is tagged
        # `selftest`, so it runs at complete: a rule about the harness's own
        # folder is this repo's, not the subject's, and has no place in basic
        # or in the gate a Reloaded submission waits on.
        readme = "tests/%s/README.md" % ex
        own = native.glob(["tests/%s/**" % ex], allow_empty = True)
        twin_args = [
            "--mode",
            "twin",
            "--twin-of",
            twin_of,
            "--twin-tests",
            "%s/tests/%s/" % (t_pkg[2:], t_ex),
            "--label",
            "%s/tests/%s/" % (native.package_name(), ex),
        ]
        for f in twin_strays(own, readme):
            # A file name is whatever was typed: one word (shell_word).
            # "my notes.txt" would otherwise arrive as two words, the second
            # an unknown option.
            name = f[len("tests/%s/" % ex):]
            twin_args += ["--stray", shell_word(name)]
        if readme not in own:
            twin_args.append("--no-readme")
        _test(
            name = ex + "_twin",
            srcs = ["//tools:shell_test.sh"],
            args = twin_args,
            tags = ["selftest"],
        )
    else:
        t_dir = "tests/%s/" % ex

    _test(
        name = ex + "_norm",
        srcs = ["//tools:shell_test.sh"],
        args = [
            "--generator",
            "$(location %s)" % gen,
            "--mode",
            "norm",
        ],
        data = [gen],
        tags = ["norm"],
        turnin = turnin,
        turnin_where = where,
    )

    # The lint, split by whose rule each finding is: see `script`. Their
    # levels are their suffixes' in _SUFFIX_LAYER, which the audit holds
    # them to: _lint robust, _posix strict. Gated: a generator that is not
    # there is norm's, output's and files' NOT TURNED IN already.
    lint_args = [
        "--generator",
        "$(location %s)" % gen,
        "--shellcheck",
        "$(location %s)" % _SHELLCHECK,
        "--output-test",
        ex + "_output",
    ]
    lint_data = [gen, _SHELLCHECK]
    if script:
        lint_args += ["--deliverable", deliverable, "--script", script]
        for f in fixtures:
            lint_args += ["--fixture", "$(location %s)" % f]
            lint_data.append(f)
        for kv in env:
            lint_args += ["--env", kv]
    _test(
        name = ex + "_lint",
        srcs = ["//tools:shell_test.sh"],
        args = lint_args + ["--mode", "lint"],
        data = lint_data,
        tags = ["norm"] + (extra_tags if script else []),
        level = 3,
        turnin = turnin,
        turnin_where = where,
        gated = True,
    )
    if script in ("sh", "./name"):
        _test(
            name = ex + "_posix",
            srcs = ["//tools:shell_test.sh"],
            args = lint_args + ["--mode", "posix"],
            data = lint_data,
            tags = ["norm"] + extra_tags,
            level = 2,
            turnin = turnin,
            turnin_where = where,
            gated = True,
        )

    args = [
        "--generator",
        "$(location %s)" % gen,
        "--mode",
        mode,
        "--diff",
        "$(location %s)" % _DIFF,
    ]
    data = [gen, _DIFF]
    for f in fixtures:
        args += ["--fixture", "$(location %s)" % f]
        data.append(f)
    for kv in env:
        args += ["--env", kv]
    if deliverable:
        args += ["--deliverable", deliverable]
    if mode == "diff":
        expected_f = t_dir + expected
        args += ["--expected", "$(location %s)" % expected_f]
        data.append(expected_f)
        if run:
            # The run goes through the check library's ck_run, as every
            # check-mode run does: /bin/sh, a parse check, stderr shown.
            args += ["--run", "--check-lib", "$(location //tools:shell_check.sh)"]
            data.append("//tools:shell_check.sh")
        if interp:
            args += ["--interp", interp]
    elif mode == "check":
        # the shell_check.sh library lets check scripts emit a PASS/FAIL checklist
        args += ["--check-lib", "$(location //tools:shell_check.sh)"]
        data.append("//tools:shell_check.sh")
        if oracle:
            args += ["--oracle", "$(location //oracle:oracle)"]
            data.append("//oracle:oracle")
        if redirect:
            # Checked with the rest of the call (redirect_problem).
            r_from, r_to = redirect.items()[0]
            r_f = t_dir + r_to
            args += [
                "--redirect",
                "%s=$(location %s)" % (r_from, r_f),
                "--redirect-lib",
                "$(location //tools:path_redirect.so)",
            ]
            data += [r_f, "//tools:path_redirect.so"]

        # One word each (shell_word): the sentences have blanks.
        for w_key, w_text in sorted((wording or {}).items()):
            args += ["--wording", shell_word("%s=%s" % (w_key, w_text))]

        # The same run, graded by another script: see `readings`. Built from
        # the args above before the output layer's own --check and --clues
        # are added, so a reading shares everything with it but those two.
        for reading, r_script in sorted((readings or {}).items()):
            if reading in ("norm", "lint", "posix", "output", "files", "twin"):
                fail(("shell_exercise(num = \"%s\"): a reading named %r would " +
                      "collide with the %s_%s target.") % (num, reading, ex, reading))
            r_f = t_dir + r_script
            _test(
                name = "%s_%s" % (ex, reading),
                srcs = ["//tools:shell_test.sh"],
                args = args + ["--check", "$(location %s)" % r_f],
                data = data + [r_f],
                tags = ["output"] + run_extra,
                level = 2,
                turnin = turnin,
                turnin_where = where,
            )

        check_f = t_dir + check
        args += ["--check", "$(location %s)" % check_f]
        data.append(check_f)

        # After the readings: the second run is for the check that compares
        # it, and a reading's script, which never calls ck_stable, would be
        # refused for leaving it unread.
        if stable:
            args.append("--stable")
    else:
        fail("shell_exercise: mode must be 'diff' or 'check', got %r" % mode)
    if readings and mode != "check":
        fail(("shell_exercise(num = \"%s\"): readings are check scripts, so they " +
              "need mode = \"check\".") % num)

    # optional per-exercise foothold hint (shown on failure), if a clues.tsv
    # exists. A twin's is its source exercise's, which every twin has: a glob
    # cannot look into another package, so it is named, and a twin without
    # one fails to load rather than quietly losing its hints.
    if twin_of:
        clues_glob = [t_dir + "clues.tsv"]
    else:
        clues_glob = native.glob(["tests/%s/clues.tsv" % ex], allow_empty = True)
    if clues_glob:
        args += ["--clues", "$(location %s)" % clues_glob[0]]
        data += clues_glob

    _test(
        name = ex + "_output",
        srcs = ["//tools:shell_test.sh"],
        args = args,
        data = data,
        tags = ["output"] + run_extra,
        turnin = turnin,
        turnin_where = where,
    )

    if files:
        if not deliverable:
            fail(("shell_exercise(num = \"%s\") emits a files layer but has no " +
                  "deliverable name, so the layer would report the exercise's own " +
                  "answer as a file nobody asked for. Name the one file in the " +
                  "contract, or give it files = None there and say why it cannot " +
                  "be named.") % num)

        # The generator runs with an empty scratch dir as cwd, exactly as it does
        # under //tools:generate, where what it leaves there becomes
        # deliverable/exNN -- the directory //tools:submit pushes. So the names
        # it leaves behind here ARE the names 42 receives.
        f_args = [
            "--generator",
            "$(location %s)" % gen,
            "--mode",
            "files",
            "--diff",
            "$(location %s)" % _DIFF,
            "--files-test",
            "$(location //tools:files_test.sh)",
            "--label",
            "%s/%s" % (native.package_name(), gen),
            "--turnin",
            deliverable,
            "--strict",
        ]
        f_data = [gen, _DIFF, "//tools:files_test.sh"]
        for f in fixtures:
            f_args += ["--fixture", "$(location %s)" % f]
            f_data.append(f)
        for kv in env:
            f_args += ["--env", kv]
        _test(
            name = ex + "_files",
            srcs = ["//tools:shell_test.sh"],
            args = f_args,
            data = f_data,
            tags = ["files"] + extra_tags,
            turnin = turnin,
            turnin_where = where,
        )
