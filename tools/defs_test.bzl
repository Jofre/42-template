"""_test(), the one place a test is declared, and the tables it holds a runner to.

Every test a macro emits is declared by _test(), which tags it with its layer
and its level, stages the runner library and the exit-status shim beside it,
and refuses, while loading, a call its runner cannot take: _STANDIN_RUNNERS,
_RUNNER_CHOICES, _CORPUS_RUNNERS and _EXIT_STATUS_RUNNERS, each held to tools/
by //tools:conventions as text. hand_test() is its door for a test written
out in a BUILD file; output_gate() and corpus_memory() are the layers every
kind of exercise shares.

Loaded by the files above it, and re-exported by tools/defs.bzl, the one
file a BUILD file loads.
"""

load("@rules_shell//shell:sh_test.bzl", "sh_test")
load(
    ":defs_contract.bzl",
    _WAITS_TAG = "WAITS_TAG",
    _after_dashes = "after_dashes",
    _contract_or_none = "contract_or_none",
    _entry = "entry",
    _is_student_bin_name = "is_student_bin_name",
    _loc_of = "loc_of",
    _misplaced = "misplaced",
    _norm_label = "norm_label",
    _opt_value = "opt_value",
    _opt_values = "opt_values",
    _opts = "opts",
    _refuse = "refuse",
    _student_bin = "student_bin",
    _waiting_name = "waiting_name",
    _waiting_outputs = "waiting_outputs",
    _waits_for = "waits_for",
    _where = "where",
)
load(
    ":defs_levels.bzl",
    _DOC_REFERENCE = "DOC_REFERENCE",
    _LAYER_LEVEL = "LAYER_LEVEL",
    _LEVEL_NAMES = "LEVEL_NAMES",
    _RAISED = "RAISED",
    _UNIT_TAG = "UNIT_TAG",
    _call = "call",
    _graded_rule = "graded_rule",
    _in_fixtures = "in_fixtures",
    _is_ex = "is_ex",
    _key = "key",
    _known_layer = "known_layer",
    _level_tags = "level_tags",
    _memory_graded = "memory_graded",
    _uniq = "uniq",
    _unit_of_name = "unit_of_name",
)
load(
    ":defs_toolchain.bzl",
    "pinned_cc_problem",
    "symbolizer_problem",
    _NOTATION = "NOTATION",
    _SYMBOLIZER_DATA = "SYMBOLIZER_DATA",
    _UNBUFFERED = "UNBUFFERED",
    _symbolizer_args = "symbolizer_args",
    _valgrind_args = "valgrind_args",
    _valgrind_data = "valgrind_data",
)
load(":names_file.bzl", "names_file")
load(":subject.bzl", _turnin_folder = "turnin_folder", _units_of = "units_of")

def _output_fixture_binary(name, harness, prototype, deps = None, **kwargs):
    """A student_binary whose main() is the harness's, run by diff_output.sh.

    `prototype` is _student_bin's, which every harness over a student's files
    is built with and which requires it: the test that holds the functions
    the harness calls to the signatures the subject fixes, or "none: <the
    reason>".

    The only way an output fixture is built, so none can miss the library that
    makes its stdout unbuffered: with it, the rows a fixture printed before the
    student's code crashed reach the table as real results, and the first line
    missing is the case that was running (tools/unbuffered_stdout.c). Nor the
    header that writes diff_output.sh's escaped-value notation
    (tools/notation.h, //tools:notation), which a fixture with
    escaped_values includes rather than writing its own. The
    output test that runs it passes diff_output.sh --harness-fixture, which
    says so, and which diff_output.sh refuses for a binary without the
    library's marker. Never for a student's own program, and never for a
    diff, perf, cycles or refcost binary; conventions.sh refuses both.

    Built by _student_bin like every program that holds a student's code, so
    code that does not build makes it a stand-in (tools/standin.sh), which
    diff_output.sh reports before it looks for the marker. The library is a
    cc_library of the harness's own, linked whole (alwayslink) as a
    cc_binary's deps were.
    """
    _student_bin(
        name = name,
        harness = harness,
        prototype = prototype,
        deps = (deps or []) + [_UNBUFFERED, _NOTATION],
        **kwargs
    )

# What makes an argv_table.sh test compare no table a gate can replay.
_TABLE_REFUSALS = {
    "--memory-only": "it checks memory alone",
    "--exit-only": "it is judged by its exit alone",
    "--emit": "it prints a reference's table to make the expected file from",
}

def _table_refusal(args):
    """Why an argv_table.sh test compares no table a gate replays: (option, what it does), or None."""
    for opt in _TABLE_REFUSALS:
        if opt in args:
            return (opt, _TABLE_REFUSALS[opt])
    return None

def _table_run(args):
    """What an argv_table.sh test compares, from its arguments: _gate_run()'s fields but differ.

    None for one that compares no table (_table_refusal). The program runs
    once per row of --scenarios, with no word of its own. A caller that
    matches gates sets differ, from the test's runner (_gate_problems).
    """
    if _table_refusal(args):
        return None
    return {
        "bin": _opt_value(args, "--bin"),
        "expected": _opt_value(args, "--expected"),
        "words": [],
        "argv_file": None,
        "scenarios": _opt_value(args, "--scenarios"),
    }

def _compared_run(args, gate):
    """A compared run from a test's arguments: what diff_output.sh runs, or a case gate's.

    The one reading of diff_output.sh's options that shape a run. `gate`
    False reads a diff_output.sh test's own options; True, the --gate-*
    options of one of _CASE_GATE_RUNNERS (tools/defs_module.bzl), with the
    run flags the runner forwards to its gate. None for a test that
    compares no output (--survive, --exit-only), or a runner given no gate.
    "differ" is the script that judges the run: diff_output.sh for the
    test's own, the one --gate-differ names for a gate (V294).
    """
    opts = _opts(args)
    p = "--gate-" if gate else "--"
    if gate and "--gate-differ" not in opts:
        return None
    if not gate and ("--survive" in opts or "--exit-only" in opts):
        return None
    differ = _opt_value(opts, "--gate-differ")
    return {
        "argv_file": _opt_value(opts, "--argv-file"),
        "bin": _opt_value(opts, p + "bin"),
        "cwd_files": sorted(_opt_values(opts, "--cwd-file")),
        "expected": _opt_value(opts, p + "expected"),
        "expected_alt": _opt_values(opts, p + "expected-alt"),
        "labeled": (p + "labeled") in opts,
        "run_as": _opt_value(opts, "--run-as"),
        "sanitize": (p + "sanitize") in opts,
        "stdin": _opt_value(opts, p + "stdin"),
        "stream": _opt_value(opts, p + "stream"),
        "words": _after_dashes(args),
        "differ": (_loc_of(differ) or differ) if gate else "diff_output.sh",
    }

# The fields of a diff_output.sh test's run (_compared_run) a corpus gate
# replays: it hands its differ the program, the expected file and the words
# (or an argument file), and nothing else. A run with any other field set
# is one a gate does not make (_output_refusal), a field added later
# included. --labeled changes only how the table is drawn.
_GATE_REPLAYED = ["argv_file", "bin", "differ", "expected", "labeled", "words"]

# What each other field of a run does, by the option that sets it.
_RUN_FIELDS = {
    "cwd_files": ("--cwd-file", "it is run from a folder of its own"),
    "expected_alt": ("--expected-alt", "it accepts a second expected file"),
    "run_as": ("--run-as", "it is run under another name"),
    "sanitize": ("--sanitize", "its output is rewritten before it is compared"),
    "stdin": ("--stdin", "it is fed standard input"),
    "stream": ("--stream", "it is judged on another stream"),
}

def _output_refusal(args):
    """Why a diff_output.sh test makes a run a corpus gate does not: (option, what it does), or None.

    A gate does not make a run fed standard input, run under another name
    or from a folder of its own, judged on something else than standard
    output against one file, or whose output is rewritten before it is
    compared (the address column of a hex dump): every field of
    _compared_run() outside _GATE_REPLAYED. A corpus gate hands its differ
    none of these, so on a correct program a gate matched with such a test
    would run red where the test is green, and every replay behind it would
    SKIP, green, for ever: BSQ's no-argument gate, once more.
    """
    opts = _opts(args)
    for opt, what in [("--survive", "it waits for another case and compares no output"), ("--exit-only", "it is judged by its exit alone")]:
        if opt in opts:
            return (opt, what)
    run = _compared_run(args, False)
    for f in sorted(run):
        if f not in _GATE_REPLAYED and run[f] != None and run[f] != [] and run[f] != False:
            return _RUN_FIELDS.get(f, ("--" + f.replace("_", "-"), "it shapes the run"))
    return None

def _output_run(args):
    """What a diff_output.sh test runs, from its arguments: _gate_run()'s fields but differ.

    _compared_run()'s fields a corpus gate replays; None for a run it does
    not make (_output_refusal). A caller that matches gates sets differ,
    from the test's runner (_gate_problems).
    """
    if _output_refusal(args):
        return None
    run = _compared_run(args, False)
    return {
        "bin": run["bin"],
        "expected": run["expected"],
        "words": run["words"],
        "argv_file": run["argv_file"],
        "scenarios": None,
    }

# THE DIFF LAYERS WAIT (V251, V150). docs/reference.md's "Which layers wait
# for which" says a diff or diff_asan test stays quiet until its exercise's
# own output test passes: on a stub, a corpus replayed over a program the
# subject's example already fails reports that one red again, hundreds of
# times and far less usefully. Nothing held the row to the build, and C 06's,
# C 10's and Reloaded's corpus replays waited for nothing: C 10's four went
# red on every fresh stub, at strict, beside the output test that said it
# first. So each non-manual test of the two layers has a gate (_GATE_FLAGS,
# as _waits_for reads one; output_gate() writes one off the output test), or
# a declared reason to wait for nothing: the tag below, which only a macro
# sets, with the reason written beside the line that sets it (rush_variant's
# crash-only twin, which compares no output and replays no row of the
# table). hand_test() refuses the tag, so a BUILD file cannot excuse a test
# without a reason anywhere; a manual test waits for nothing by choice, run
# only when someone names it.
_NO_GATE_TAG = "no_gate"

# The tag _test puts beside the "manual" it adds to a test of
# tools/tests/macro_fixtures that its macro had not made manual. Its name
# holds no "manual", so a probe that reads a test's tags for "manual" never
# counts it (the knobs fixture's c_perf `enabled`).
_FIXTURE_HOLD = "fixture_hold"

def _waiting_args(test):
    """(args, data) for the output test `test`: the list of who waits for it.

    In a package whose contract has units, --suite names the suite of the
    test's unit, which the runner's red says to run where an exercise's
    says :exNN (tools/runner_lib.sh, rl_waiting).
    """
    label = ":" + _waiting_name(test)
    args = ["--waiting", "$(location %s)" % label]
    contract = _contract_or_none()
    if contract != None and "units" in contract:
        u = _unit_of_name(test, [r["name"] for r in _units_of(contract)])
        if u:
            args += ["--suite", u]
    return args, [label]

# What hands a program its input: in an output test's run, and in a gate's.
# A runner that runs the case itself (--argv-file, valgrind_test.sh's) hands
# its gate the same argument file. An argument table (argv_table.sh's
# --scenarios, one run per row) is its gate's --gate-scenarios.
_RUN_INPUT_FLAGS = ["--stdin", "--argv-file", "--scenarios"]
_GATE_INPUT_FLAGS = ["--gate-arg", "--gate-arg-file", "--gate-stdin", "--gate-number", "--argv-file", "--gate-scenarios"]

# The gated runners whose option loop takes none of _GATE_INPUT_FLAGS: their
# gate runs the program with no input at all, so it cannot wait for an
# output test whose run is fed one. _waiting_problems says so in a message
# of its own, which names no option the runner would refuse as unknown, and
# _measure_gate_problems compares no input for them.
_GATE_NO_INPUT_RUNNERS = ["//tools:method_check.sh"]

def _waiting_problems(tests):
    """_audit_problems' word on the waiting lists.

    Each gated test resolves to one output test that hands its list on
    (_waits_for). And its gate hands the program input where that test's run
    does: BSQ's corpora gated on `ex00_bin` with no map at all, which a
    correct program answers with "map error", never the example's square, so
    on every program that passes the example they said SKIP -- "your own
    example is not passing yet" -- and checked nothing unless NO_SKIP=1.
    """
    problems = []
    outputs = _waiting_outputs(tests)
    for o in sorted(outputs):
        w = _loc_of(_opt_value(tests[o].get("args") or [], "--waiting") or "")
        if w != _waiting_name(o):
            problems.append(("%s: it hands its runner the list %s, and its own is %s: the " +
                             "list of who waits for it is named after it (_waiting_args(%r)).") %
                            (o, w, _waiting_name(o), o))
    for n in sorted(tests):
        o, why = _waits_for(n, tests, outputs)
        if why:
            problems.append(why)
            continue
        if o == None:
            continue
        oargs = tests[o].get("args") or []
        gargs = tests[n].get("args") or []
        fed = [f for f in _RUN_INPUT_FLAGS if f in oargs] or _after_dashes(oargs)
        feeds = [f for f in _GATE_INPUT_FLAGS if f in gargs] or _after_dashes(gargs)
        runner = (tests[n].get("srcs") or [None])[0]
        if fed and not feeds and runner in _GATE_NO_INPUT_RUNNERS:
            problems.append(("%s: it waits for %s, whose run hands the program input (%s), " +
                             "and %s hands its gate no input at all: it takes none of " +
                             "the options that would, so no gate of it can run the program " +
                             "as %s does. Gate it on an output test whose run hands the " +
                             "program no input, or give the runner the option that test's " +
                             "input needs.") %
                            (n, o, " ".join(fed), runner.split(":")[-1], o))
        elif fed and not feeds:
            problems.append(("%s: it waits for %s, whose run hands the program input (%s), " +
                             "and its gate hands it none (no --gate-arg, --gate-stdin, ...): " +
                             "a program that passes %s fails that gate, and this test says " +
                             "SKIP forever. Give the gate %s's input.") %
                            (n, o, " ".join(fed), o, o))
    return problems

# The runners a test may hand a program built by student_binary, and how each
# tells a STAND-IN (tools/standin.sh) from a program: "checks" -- it sources
# standin.sh and calls standin_check before running it, which
# //tools:conventions verifies -- or "gate" -- it runs the program only as its
# correctness gate, through tools/diff_output.sh, which checks it there.
# _test() refuses, while loading, a test that hands a student_binary to any
# other runner: graded as a program, a stand-in was "memory-clean" to
# asan_run.sh and hundreds of wrong outputs to bsq_check.sh (findings 165,
# 173), and an option name is no way to find the next runner that does it --
# progname_test.sh took its program as a plain argument. (It takes --bin now:
# tools/probe_under.sh finds a program by its flag, and //tools:conventions
# holds every "checks" row here to a --bin or --student-bin.)
#
# WHAT THAT CHECK SEES: every test _test() emits -- a macro's, or a
# hand_test() in a BUILD file -- and in its `data` the labels of THIS package
# that name a student_binary, by NAME alone: _student_bin() holds every one to
# _STUDENT_BIN_SUFFIXES, and a name is in `data` wherever the BUILD file
# declares the binary. It also asked native.existing_rule() for the target's
# kind, which sees only what is declared ABOVE the test -- the same check
# gave two answers for one test depending on where its binary was declared.
# Every spelling of a label of this package counts (":ex00_bin", "ex00_bin",
# "//<package>:ex00_bin"). A binary of ANOTHER package is not seen: the one
# test that takes them, //tools/tests:macro_fixtures_test, reads stand-ins on
# purpose, and //tools:conventions holds a runner to the rule by its --bin
# handling and by standin.sh in its test's data.
_STANDIN_RUNNERS = {
    "//tools:allocfail_check.sh": "checks",
    "//tools:argv_check.sh": "checks",
    "//tools:argv_table.sh": "checks",
    "//tools:asan_run.sh": "checks",
    "//tools:bsq_check.sh": "checks",
    "//tools:cycles_check.sh": "checks",
    "//tools:diff_output.sh": "checks",
    "//tools:file_check.sh": "checks",
    "//tools:ilp32_test.sh": "gate",
    "//tools:method_check.sh": "gate",
    "//tools:perf_test.sh": "checks",
    "//tools:progname_test.sh": "checks",
    "//tools:ref_compare.sh": "gate",
    "//tools:run_check.sh": "checks",
    "//tools:rush01_check.sh": "checks",
    "//tools:rush02_check.sh": "checks",
    "//tools:rust_diff.sh": "checks",
    "//tools:valgrind_test.sh": "checks",
}

# THE CHOICES A RUNNER ASKS EVERY CALL TO MAKE, as {runner: [(flags, what)]}:
# each call passes exactly one of `flags`. A default is not a decision. A
# flag a call site had to remember is one the next call site forgets:
# file_check.sh ignored stderr unless told --stderr-empty, and argv_check.sh,
# bsq_check.sh and rush02_check.sh threw it away on every run, so a new corpus
# would ignore it by omission, never because its subject says nothing of it
# (review of WP-50). rush01_check.sh decided it in its own header for its one
# subject, the last corpus runner whose call said nothing of it. The runner
# refuses such a call too (exit 2, tools/runner_lib.sh's rl_stderr_choice);
# this is the same refusal while loading, before anything runs. _test()
# applies it to every test, hand_test()'s included. //tools:conventions holds
# a runner that takes the pair to a row here, and a row here to a runner that
# takes it.
#
# Not here: diff_output.sh, whose case says which stream it compares
# ("stream").
#
# A REPLAY UNDER A MEMORY CHECKER (--sanitized, --valgrind: corpus_memory())
# makes no stderr choice, and may not: standard error is where the checker
# writes the report that replay reads, and it judges no output, so "held
# empty" would claim a check it does not make and "ignored, because ..." would
# be untrue of the one stream it does read. The mode is the answer to the
# question, and the runners agree (tools/runner_lib.sh's rl_stderr_choice).
_STDERR_CHOICE = (
    ["--stderr-empty", "--stderr-ignored"],
    "what standard error is held to: --stderr-empty where the subject " +
    "gives the corpus's valid inputs no message, or --stderr-ignored " +
    "REASON, a sentence saying why it is not judged (docs/reference.md, " +
    "\"Run contract\": stderr is ignored unless the subject requires " +
    "something of it)",
)

# A RUNNER ONE PROJECT CALLS QUOTES ITS SUBJECT FROM THE CALL SITE. Rush 01's
# and BSQ's runners restated their subject in words of their own ("the subject
# prints it verbatim"), a second copy with no page beside it (V90; the owner's
# ruling, 2026-10-09). Their messages now quote the sentence the call site
# hands them (runner_quotes()), so a call without one would print a fault
# with no sentence behind it. Under a memory checker no output is judged and
# nothing is quoted, so there it is not asked for.
_QUOTES_CHOICE = (
    ["--quotes"],
    "the subject's sentences its messages quote: runner_quotes(), " +
    "transcribed from the project's own subject with where each is from",
)

# A RUNNER WHOSE DEFAULT MODE QUOTES NOTHING asks for --quotes only in the
# modes that do: forbidden_symbols.sh's one-list check names the allowed list
# it was handed and quotes no sentence, while its --globals and --function
# reds quote the call site's (and the runner refuses --quotes without them);
# prototype_check.sh's types mode reads the contract alone, while its
# --no-restrict and --declares reds quote the call site's; symbols_test.sh's
# default mode quotes nothing, while its --no-cross red quotes the call
# site's sentence keeping helpers static (c_library's helpers_rule).
_QUOTES_ONLY_WITH = {
    "//tools:forbidden_symbols.sh": ["--globals", "--function"],
    "//tools:prototype_check.sh": ["--no-restrict", "--declares"],
    "//tools:symbols_test.sh": ["--no-cross"],
}

# The options that put a corpus runner's replay under a memory checker
# (tools/runner_lib.sh, "A CORPUS UNDER A MEMORY CHECKER").
_MEMORY_MODES = ["--sanitized", "--valgrind"]

_RUNNER_CHOICES = {
    "//tools:argv_check.sh": [_STDERR_CHOICE],
    "//tools:bsq_check.sh": [_STDERR_CHOICE, _QUOTES_CHOICE],
    "//tools:file_check.sh": [_STDERR_CHOICE],
    "//tools:forbidden_symbols.sh": [_QUOTES_CHOICE],
    "//tools:prototype_check.sh": [_QUOTES_CHOICE],
    "//tools:readme_check.sh": [_QUOTES_CHOICE],
    "//tools:rush01_check.sh": [_STDERR_CHOICE, _QUOTES_CHOICE],
    "//tools:rush02_check.sh": [_STDERR_CHOICE],
    "//tools:symbols_test.sh": [_QUOTES_CHOICE],
}

def _runner_choice_problem(name, runner, args):
    """Why test `name`'s args make a choice `runner` asks for zero or two times; None if not.

    And, for the stderr pair, why --stderr-ignored's REASON would not reach
    the runner as one argument: Bazel tokenises a test's `args` like a shell,
    so a sentence written plainly is split at its blanks ("unknown option"
    from the runner), and one with an apostrophe fails the target's analysis
    ("unterminated quotation"). stderr_ignored() quotes it.

    And argv_check's --exit-only with --stderr-empty, the pair the runner
    refuses: the mode never reads standard error.
    """
    memory = [m for m in _MEMORY_MODES if m in args]
    for choice in _RUNNER_CHOICES.get(runner, []):
        flags, what = choice[0], choice[1]
        given = [f for f in flags if f in args]
        if memory and flags == _STDERR_CHOICE[0]:
            if given:
                return (("%s replays its corpus under a memory checker (%s), where standard " +
                         "error carries the checker's report and no output is judged; drop " +
                         "%s, which would say otherwise (tools/defs_test.bzl, _RUNNER_CHOICES).") %
                        (name, memory[0], ", ".join(given)))
            continue
        if memory and flags == _QUOTES_CHOICE[0]:
            continue
        if (flags == _QUOTES_CHOICE[0] and runner in _QUOTES_ONLY_WITH and
            not [o for o in _QUOTES_ONLY_WITH[runner] if o in args]):
            if given:
                return (("%s runs %s in its default mode, which quotes nothing, " +
                         "so the runner refuses %s; drop it, or pass one of %s, " +
                         "whose messages quote it (tools/defs_test.bzl, _QUOTES_ONLY_WITH).") %
                        (name, runner, ", ".join(given), ", ".join(_QUOTES_ONLY_WITH[runner])))
            continue
        if len(given) != 1:
            return (("%s runs %s, which asks every call to say %s. Pass exactly " +
                     "one of %s; this call has %s.") %
                    (name, runner, what, ", ".join(flags), ", ".join(given) or "none"))
    if runner == "//tools:argv_check.sh" and "--exit-only" in args and "--stderr-empty" in args:
        return (("%s passes --exit-only with --stderr-empty, but --exit-only judges only how " +
                 "each run ended and never reads standard error, so the PASS line would say " +
                 "nothing reached it unchecked; pass stderr_ignored() instead, as the runner " +
                 "asks.") % name)
    if "--stderr-ignored" in args and runner in _RUNNER_CHOICES:
        i = args.index("--stderr-ignored")
        why = args[i + 1] if i + 1 < len(args) else ""
        if not _one_shell_word(why):
            return (("%s passes --stderr-ignored %r, which Bazel's tokenising of " +
                     "`args` does not hand over as one argument. Write it as " +
                     "stderr_ignored(\"<the reason>\") (tools/defs.bzl), which quotes " +
                     "it.") % (name, why))
    return None

def _one_shell_word(w):
    """True if Bazel's expansion and shell-like tokenising of `args` make exactly one argument of `w`.

    Either a plain word (no blank, quote, backslash or '$'), or one quoted the
    way shell_word() quotes: in single quotes, each apostrophe as '\\'' and
    each '$' doubled.
    """
    if not w:
        return False
    if len(w) >= 2 and w.startswith("'") and w.endswith("'"):
        inner = w[1:-1].replace("'\\''", "").replace("$$", "")
        return "'" not in inner and "$" not in inner
    for c in [" ", "\t", "\n", "'", "\"", "\\", "$"]:
        if c in w:
            return False
    return True

def stderr_ignored(reason):
    """["--stderr-ignored", REASON] for a corpus runner's args, REASON as one argument.

    A corpus runner's call says what standard error is held to (_RUNNER_CHOICES):
    --stderr-empty, or this, with a sentence saying why stderr is not judged.
    Bazel tokenises `args` like a shell, so the sentence is quoted here
    (shell_word): written plainly it reached the runner split at its blanks,
    and with an apostrophe it failed the target's analysis.

    Args:
        reason: the sentence, as the PASS line prints it, apostrophes and
            '$' included.

    Returns:
        The two arguments, to append to a test's `args`.
    """
    if type(reason) != "string" or not reason.strip():
        fail("stderr_ignored(): the reason is a sentence saying why standard error is not judged.")
    return ["--stderr-ignored", shell_word(reason)]

def runner_quotes(name, quotes):
    """Declares the subject's sentences a runner one project calls quotes; returns its args.

    A runner only one project calls says nothing of that subject in its own
    words (_QUOTES_CHOICE, V90): the sentence a message quotes is written
    here, once, in the project's BUILD.bazel, as make_test.sh's are through
    c_make's `quotes`. Declares `name`, a file of KEY<TAB>TEXT lines, and
    returns the args that hand it over; list `:name` in each test's `data`
    (Bazel refuses the `$(location)` otherwise). The runner refuses a key it
    does not quote and a key it quotes that has no line (exit 2).

    Args:
        name: the file's target name, as `exNN_<runner>_quotes`.
        quotes: {key: "Project, p.N: \"the sentence\""}, each value the
            subject's own words with where they are from. The runner's
            header lists its keys.

    Returns:
        ["--quotes", "$(location :name)"], to append to a test's `args`.
    """
    if type(quotes) != "dict" or not quotes:
        fail("runner_quotes(%s): quotes is {key: sentence}, each sentence the subject's own with where it is from." % name)
    for k in sorted(quotes):
        q = quotes[k]
        if type(q) != "string" or not q.strip() or "\t" in q or "\n" in q:
            fail("runner_quotes(%s): the quote for %s is one line of text, with no TAB." % (name, k))
    names_file(
        name = name,
        names = ["%s\t%s" % (k, quotes[k]) for k in sorted(quotes)],
    )
    return ["--quotes", "$(location :%s)" % name]

# THE CORPUS RUNNERS: the runners that replay a generated corpus on a program
# (--bin, --oracle, a sweep), each able to replay it under a memory checker
# (--sanitized, --valgrind: tools/runner_lib.sh, "A CORPUS UNDER A MEMORY
# CHECKER"). Every corpus used to run on the plain build only, so a path only
# generated input reaches was never memory-checked (finding 113). c_levels()'
# audit holds a package that replays a corpus through one of these to the
# twins corpus_memory() emits; //tools:conventions holds this list to the
# runners: every runner that takes --bin and --oracle and sweeps is here, and
# every one here takes the memory options.
_CORPUS_RUNNERS = [
    "//tools:argv_check.sh",
    "//tools:bsq_check.sh",
    "//tools:file_check.sh",
    "//tools:rush01_check.sh",
    "//tools:rush02_check.sh",
]

# THE OPTIONS OF A CORPUS RUNNER THAT DO NOT CHOOSE ITS CORPUS, with how many
# values each takes: the program, how a case is judged or shown (what standard
# error is held to, a readings corpus's wording, --settled's rules, the note a
# failure prints, the hints and the case they are keyed to, the subject's
# sentences a message quotes), the floors a corpus is held to, the output gate, and the
# memory checker itself. Every other argument is the corpus -- the generator (--fn, --oracle-fn, --corpus),
# its seed and size (--seed, --count, --fixed, --max-cases), and how a case
# reaches the program (--mode, --group, --dict, --probe-argc) -- and c_levels()'
# audit holds each plain replay to twins that replay the same one. It used to
# hold an (exercise, runner) pair to one twin, so one twin covered every other
# corpus through that runner: BSQ's maps on stdin and in groups, and Rush 02's
# numbers, were memory-checked nowhere and the audit passed. An option missing
# here makes the audit ask for a twin that differs only by it, which is the
# loud way to be wrong; //tools:conventions holds every row to an option a
# corpus runner takes.
_CORPUS_RUN_OPTS = {
    "--access-rule": 1,
    "--bin": 1,
    "--case": 1,
    "--clues": 1,
    "--exit-only": 0,
    "--expect-reordering": 0,
    "--expect-substring": 1,
    "--expect-transform": 0,
    "--gate-arg": 1,
    "--gate-arg-file": 1,
    "--gate-bin": 1,
    "--gate-differ": 1,
    "--gate-expected": 1,
    "--gate-label": 1,
    "--gate-number": 1,
    "--gate-scenarios": 1,
    "--guarded-argv": 0,
    "--label": 1,
    "--max-size": 1,
    "--quotes": 1,
    "--readings": 0,
    "--rule": 1,
    "--sample": 1,
    "--sanitized": 0,
    "--settled": 0,
    "--show": 1,
    "--symbolizer": 1,
    "--symbolizer-lib": 1,
    "--stderr-empty": 0,
    "--stderr-ignored": 1,
    "--timeout": 1,
    "--valgrind": 1,
    "--valgrind-tools": 1,
}

# The tags corpus_memory() puts on the twins it emits, which the audit reads:
# a plain replay it stands in for although it replays less (`covers`, with the
# reason in the call), and a memcheck twin it leaves out (`no_valgrind`, the
# same). hand_test() refuses both, so a twin cannot claim either without the
# sentence corpus_memory() requires.
_COVERS_TAG = "corpus_covers="
_NO_VALGRIND_TAG = "corpus_no_valgrind"

def _corpus_of(args):
    """A corpus replay's arguments without those of _CORPUS_RUN_OPTS: what it replays."""
    out = []
    skip = 0
    for a in args:
        if skip:
            skip -= 1
        elif a in _CORPUS_RUN_OPTS:
            skip = _CORPUS_RUN_OPTS[a]
        else:
            out.append(a)
    return out

def _memcheck_allowed(entry):
    """Whether an exercise's corpus gets a memcheck twin: its subject allows malloc.

    An `allowed` of None is a subject that prints no "Allowed functions" line
    (tools/subject.bzl), which restricts nothing -- malloc included -- so its
    corpus is held to a leak check like one whose line names malloc. Read as
    "malloc not allowed", the next project transcribed that way would have had
    no leak check on any of its corpora.
    """
    return entry["allowed"] == None or "malloc" in entry["allowed"]

# The runners that run student code, and so read how each run ended from
# tools/exit_status, which asks waitpid(): the shell's 128+N cannot tell
# `return (-1);` from a death by signal 127 (see tools/exit_status.c). They
# make every run through tools/runner_lib.sh's rl_run. Every test _test() emits
# that names one gets the helper in its data, and one that lists it itself is
# refused (_staged_by_hand); the runners refuse to run without it, so a test
# that reached one without it would be red with a message, never quietly back
# on the guess. //tools:conventions refuses a runner that calls rl_tmo, rl_run
# or rl_ready and is missing here.
_EXIT_STATUS_RUNNERS = [
    "//tools:allocfail_check.sh",
    "//tools:argv_check.sh",
    "//tools:argv_table.sh",
    "//tools:asan_check.sh",
    "//tools:asan_run.sh",
    "//tools:bsq_check.sh",
    "//tools:cycles_check.sh",
    "//tools:diff_output.sh",
    "//tools:file_check.sh",
    "//tools:make_test.sh",
    "//tools:method_check.sh",
    "//tools:perf_test.sh",
    "//tools:progname_test.sh",
    "//tools:ref_compare.sh",
    "//tools:run_check.sh",
    "//tools:rush01_check.sh",
    "//tools:rush02_check.sh",
    "//tools:rust_diff.sh",
    "//tools:shell_test.sh",
    # shell_check.sh is not a runner: check scripts source it, and its ck_run
    # runs the turn-in through the helper, which it finds beside itself.
    "//tools:shell_check.sh",
    "//tools:valgrind_test.sh",
]
_EXIT_STATUS = "//tools:exit_status"

# Every runner sources it; see _test().
_RUNNER_LIB = "//tools:runner_lib.sh"

# make_test.sh's database readers, and the runner that reads them; see _test().
_MAKE_DB = "//tools:make_db.awk"
_MAKE_TEST = "//tools:make_test.sh"

def _staged_by_hand(name, srcs, data):
    """Why test `name` lists in its data a helper _test() stages itself; None if it lists none.

    _test() hands runner_lib.sh to every test, and exit_status to every one
    whose srcs or data name one of _EXIT_STATUS_RUNNERS. A copy listed by hand
    changes nothing, and it reads as though a runner's helpers had to be
    listed: 37 copies did, in seven BUILD files, after _test() had staged
    both for every test.
    """
    if _RUNNER_LIB in data:
        return (("%s lists %s in its data, which _test() hands to every test itself " +
                 "(tools/defs_test.bzl): drop it from the list.") % (name, _RUNNER_LIB))
    runners = [r for r in _EXIT_STATUS_RUNNERS if r in srcs + data]
    if _EXIT_STATUS in data and runners:
        return (("%s lists %s in its data, which _test() hands itself to a test naming " +
                 "%s, one of _EXIT_STATUS_RUNNERS (tools/defs_test.bzl): drop it from the list.") %
                (name, _EXIT_STATUS, runners[0]))
    return None

def _own_target(label, pkg):
    """The target name `label` gives in package `pkg`, or None for another package's.

    ":ex00_bin", a bare "ex00_bin" and "//<pkg>:ex00_bin" -- that last one
    also behind the main repository's "@" (or the two of its canonical name)
    -- are this package's; a file path ("tests/ex00/x.txt") and another
    repository's label ("@valgrind_ubuntu//:usr/bin/valgrind.bin") are not.
    """
    if label.lstrip("@").startswith("//"):
        label = label.lstrip("@")
    if label.startswith(":"):
        return label[1:]
    if label.startswith("//"):
        p, _, n = label[2:].partition(":")
        return n if p == pkg and n else None
    if label.startswith("@") or "/" in label or ":" in label:
        return None
    return label

def _student_binaries_in(data, pkg):
    """The entries of `data` that name a student_binary of package `pkg`.

    By name alone (see _STANDIN_RUNNERS): the same answer wherever in the BUILD
    file the binary is declared.
    """
    return [d for d in data if _is_student_bin_name(_own_target(d, pkg) or "")]

def _standin_runner_problem(name, data, runner, pkg):
    """What _test() fails with when a test hands a student's program to a runner that cannot read a stand-in; None if nothing.

    A value first, like every contract check, so that
    tools/tests/macro_fixtures can feed it every spelling it must catch
    (contract_problem's "standin_runner").
    """
    built = _student_binaries_in(data, pkg)
    if not built or runner in _STANDIN_RUNNERS:
        return None
    return (("%s hands %s, built from a student's files, to %s, which is " +
             "not in tools/defs_test.bzl's _STANDIN_RUNNERS. When those files " +
             "do not build, that program is a stand-in script " +
             "(tools/standin.sh), and a runner that does not ask graded " +
             "it as a program. Source standin.sh in the runner and call " +
             "standin_check before running it, then list it there.") %
            (name, ", ".join(built), runner))

# size defaults to "small": almost every test these macros emit (norminette, one
# compile, an output diff, a small make) runs in well under a second. "small"
# gives a 60s timeout, so a runaway loop in a student's code fails fast instead
# of hanging for the 5-min "moderate" default, and it tells Bazel the test is
# cheap, so it schedules more of them in parallel. A test that cannot fit in
# that budget (a corpus or a whole program under memcheck, finding 066) passes
# size = "medium" at its own call site and says why there.
def _test(size = "small", level = None, turnin = None, turnin_where = None, gated = False, refusals = None, waits = None, **kwargs):
    """A test, placed on the gate ladder by its layer tag.

    level: raise THIS test above where its layer would normally sit. The default
        is right almost everywhere -- a norm failure is a KO whichever exercise it
        is in -- but a layer's level answers "how bad is this kind of failure",
        and once in a while a single case inside a layer is checking something
        stricter than its subject actually demands. Failing a beginner for that
        is what AGENTS.md's "place a new layer at the level that matches who
        needs it" rules out, and deleting the case would throw away a real lesson.
        Moving that one case up keeps both.

        Only ever UP: a case cannot be excused below its layer, because the layer
        level is what makes `basic` mean "everything that is a KO wherever the
        project is graded".
    turnin: the files of the turn-in this test reads, AS A GLOB FOUND THEM --
        never a literal path. None: it reads none, or copes with none itself
        (every layer that runs a built program does: the program is a stand-in
        then). An EMPTY list: what it needs is not there. The test is still
        emitted, under the same name, tags and level, as tools/no_turnin.sh,
        which fails saying what is missing. Before this, a missing file was a
        declared input that failed the package's analysis ("missing input
        file"), or a runner handed no file exited 2 as though the harness had
        broken.
    turnin_where: the package-relative place those files belong, for that
        message; default the exercise's turn-in directory (turnin_dir()), from
        the test's name.
    gated: this layer stands down (SKIP) while its exercise has nothing for it
        to say yet -- a correctness gate on the output, or a layer another one
        already reports for (norm's Notice reading). Its NOT TURNED IN is then
        a SKIP too, unless NO_SKIP=1, as every gated layer's other skips are:
        a missing file is already red in the files, norm and compile layers,
        and was ten more reds at robust and complete for the same one file,
        where a file that does not compile skips those layers.
    waits: the output test of its own exercise this one waits for, by name,
        where its gate alone cannot tell (_waits_for): several output tests
        run its program against the same expected file, as the cases of a
        c_program sharing one do. A tag (_WAITS_TAG), read by the audit and
        by _waiting, which lists it in that output test's red log.

    Every test also gets //tools:standin.sh in its runfiles: the build
    stand-in contract every runner that runs a built program reads. And
    //tools:runner_lib.sh, which every runner sources, with
    //tools:exit_status for one of _EXIT_STATUS_RUNNERS, and
    //tools:make_db.awk for one whose srcs or data name make_test.sh; a test
    whose data lists runner_lib.sh or exit_status itself is refused
    (_staged_by_hand). A test
    whose data name a student_binary of this package must run one of
    _STANDIN_RUNNERS, or this fails while loading (what counts as naming one:
    see _STANDIN_RUNNERS). And a test whose runner asks every call for a
    choice (_RUNNER_CHOICES) makes it exactly once, or this fails while
    loading -- through _refuse(), so that in the macro fixtures `refusals`
    (a list) collects that refusal and no test is declared.
    """
    _refuse(None, refusals, kwargs.get("name"))  # `refusals` anywhere but the fixtures
    if _refuse(_staged_by_hand(kwargs.get("name"), kwargs.get("srcs", []), kwargs.get("data", [])),
               refusals, kwargs.get("name")):
        return
    contract = _contract_or_none()
    named = contract != None and "units" in contract
    tags = kwargs.pop("tags", [])
    if waits:
        tags = tags + [_WAITS_TAG + waits]
    # Every fixture test is manual, run by name alone. Where the macro made
    # it manual already, nothing is added, and FIXTURE_HOLD says the fixture
    # did: a knob that makes a test manual (c_perf's `enabled`) is then told
    # apart from the fixture's own tag by that, never by a "manual" written
    # twice.
    if _in_fixtures() and "manual" not in tags:
        tags = tags + ["manual", _FIXTURE_HOLD]

    # THE EXERCISE, as a tag, derived here rather than passed by thirty callers.
    # Every test name this macro emits begins with exNN_ -- checked across the
    # awkward shapes too (rush variants `ex00_rush03_output`, c_program cases
    # `ex01_blob_output`, c-08's `ex01_success_output`) -- so the prefix is a
    # reliable source and there is one place to get it wrong instead of thirty.
    # c_levels() turns these into a per-exercise suite.
    ex_tag = kwargs.get("name", "")[:4]
    if named or not _is_ex(ex_tag):
        ex_tag = None

    # THE UNIT, in a contract of units, from the name the same way: the unit
    # that, followed by _, begins it, whose suite (c_levels()) selects this
    # tag -- for a function of a library, the function. A name that begins
    # with no unit gets none, and the audit refuses it (_audit_problems).
    unit_tags = []
    unit_kind = None
    if named:
        unit_kind = "project"
        rows = _units_of(contract)
        u = _unit_of_name(kwargs.get("name", ""), [r["name"] for r in rows])
        if u:
            unit_tags.append(_UNIT_TAG + u)
            unit_kind = [r["kind"] for r in rows if r["name"] == u][0]

    # The level, where the contract lowers the layer's (memory_graded).
    all_tags = tags + _level_tags(tags, level, bool(_memory_graded())) + ([ex_tag] if ex_tag else []) + unit_tags
    if turnin != None and not turnin:
        # A unit turns in at the root of deliverable/ (tools/subject.bzl).
        where = turnin_where or (_turnin_folder(None) if named else _where(ex_tag or ""))
        pkg_where = "%s/%s" % (native.package_name(), where) if native.package_name() else where
        kwargs["srcs"] = ["//tools:no_turnin.sh"]
        kwargs["args"] = [
            "--test",
            "//%s:%s" % (native.package_name(), kwargs["name"]),
            "--where",
            pkg_where,
        ] + (["--gated"] if gated else [])

        for d in _misplaced(where):
            kwargs["args"] += ["--misplaced", "%s/%s" % (native.package_name(), d) if native.package_name() else d]
        kwargs["data"] = []
    else:
        runner = kwargs.get("srcs", [None])[0]
        why = symbolizer_problem(runner, kwargs.get("args", []))
        if why:
            fail("%s: %s" % (kwargs.get("name"), why))
        why = pinned_cc_problem(runner, kwargs.get("args", []))
        if why:
            fail("%s: %s" % (kwargs.get("name"), why))
        problem = _standin_runner_problem(
            kwargs.get("name"),
            kwargs.get("data", []),
            runner,
            native.package_name(),
        )
        if problem:
            fail(problem)
        choice = _runner_choice_problem(kwargs.get("name"), runner, kwargs.get("args", []))
        if _refuse(choice, refusals, kwargs.get("name")):
            return
    data = kwargs.pop("data", [])
    if "//tools:standin.sh" not in data:
        data = data + ["//tools:standin.sh"]

    # THE SHARED RUNNER HELPERS, to every test. A runner sources
    # tools/runner_lib.sh from the runfiles tree -- its $0 is this target's name
    # in the calling package, not tools/ -- so a test without the file in its
    # data cannot start. Added here once rather than at the thirty call sites
    # that name a runner. hand_test() comes through here too, and a BUILD file
    # declares no sh_test of its own (//tools:conventions), so no test lists
    # it itself -- and one that does is refused (_staged_by_hand).
    if _RUNNER_LIB not in data:
        data = data + [_RUNNER_LIB]

    # After the NOT TURNED IN swap: no_turnin.sh runs nothing, so it gets no helper.
    uses = kwargs.get("srcs", []) + data
    if _EXIT_STATUS not in uses and [r for r in _EXIT_STATUS_RUNNERS if r in uses]:
        data = data + [_EXIT_STATUS]

    # make_test.sh reads make's database with tools/make_db.awk, found beside
    # runner_lib.sh, so every test it runs in gets it, as above.
    if _MAKE_DB not in uses and _MAKE_TEST in uses:
        data = data + [_MAKE_DB]

    # WHO GRADES THIS PROJECT, for the runners' words: the contract's
    # `grader`, as RL_GRADER, which tools/runner_lib.sh's rl_at turns into
    # "at the Moulinette" or "at the defense". A runner never names a grader
    # of its own: they all named the Moulinette, and told a rush team -- whom
    # no program grades -- that a forbidden call was a KO there (finding 145).
    # A test outside every project (//tools/tests, //oracle) gets none, and
    # its runners word it without naming anyone.
    # Only the contract says it: a caller's own RL_GRADER is refused, not
    # kept (_test_env_problem). //tools/tests:macro_fixtures_test reads the
    # one handed here off every toy test.
    # WHAT IT TESTS, the same way: in a contract of units, the kind of the
    # unit the name begins with (library, function, project or part), and
    # "project" for a test of the whole project (deliverable_files), as
    # RL_UNIT_KIND, which tools/runner_lib.sh's rl_noun turns into "this
    # library". A test of an exercise gets none, and its runners say
    # "exercise" as they always have, so a Piscine log is unchanged. A
    # caller's own RL_UNIT_KIND is refused as RL_GRADER is.
    env = dict(kwargs.pop("env", None) or {})
    problem = _test_env_problem(kwargs.get("name"), env)
    if problem:
        fail(problem)
    if contract != None:
        env["RL_GRADER"] = contract["grader"]
        if unit_kind:
            env["RL_UNIT_KIND"] = unit_kind

    # WHY IT SITS ABOVE ITS LAYER, under its red. A test _RAISED lists sits
    # higher than its name puts it, and the reason was in its BUILD comment
    # and in docs/reference.md's "Targets raised above their layer" alone:
    # its log said nothing, so a red at strict read like any other (C 06
    # ex03 printed its own --note; the rest none). The level goes to the
    # runner as RL_RAISED, and the table that gives the reason -- held to
    # _RAISED row for row by //tools:conventions -- is staged beside it, so
    # the reason is written once and shown from there (runner_lib.sh,
    # rl__raised).
    # The level is handed whatever the test already stages: a test whose data
    # listed the page itself once got no RL_RAISED, and its red said nothing.
    level_of = _RAISED.get("%s:%s" % (native.package_name(), kwargs.get("name")))
    if level_of != None and kwargs.get("srcs") != ["//tools:no_turnin.sh"]:
        env["RL_RAISED"] = _LEVEL_NAMES[level_of - 1]
        if _DOC_REFERENCE not in data:
            data = data + [_DOC_REFERENCE]
    if env:
        kwargs["env"] = env
    sh_test(size = size, tags = all_tags, data = data, **kwargs)

def _test_env_problem(name, env):
    """Why a test's own `env` is refused, or None: it may not set RL_GRADER, RL_RAISED or RL_UNIT_KIND.

    Who grades a project is its subject() contract's `grader`, and _test()
    hands it to every test of the package. One set by hand is a second answer
    to "who grades this", which stops matching the subject the day either
    changes -- the runners' words about where a failure costs would then be
    wrong with every test still green. RL_RAISED, the level a test sits at
    above its layer, is _RAISED's the same way. RL_UNIT_KIND, the kind of
    what the test tests, is the contract's units the same way.
    """
    if "RL_GRADER" in env:
        return ("%s sets RL_GRADER itself. Who grades a project is its " +
                "subject() contract's `grader`, and _test() hands it to every " +
                "test of the package; drop it from `env`.") % name
    if "RL_RAISED" in env:
        return ("%s sets RL_RAISED itself. Which tests sit above their layer " +
                "is _RAISED's (tools/defs_levels.bzl), and _test() hands it to each " +
                "of them; drop it from `env`.") % name
    if "RL_UNIT_KIND" in env:
        return ("%s sets RL_UNIT_KIND itself. What kind of unit a test " +
                "tests is its subject() contract's, and _test() hands it " +
                "to every test of a contract of units; drop it from `env`.") % name
    return None

def hand_test(name, layer, level = None, tags = None, **kwargs):
    """An sh_test written out in a BUILD file, placed like every test a macro emits.

    For the checks no macro emits: a corpus runner (BSQ's three, C 06's argv
    and C 10's file differentials, Rush 01's sweep and its guard, Rush 02's
    two), and the harness's own tests outside every project (//tools/tests,
    //oracle). It goes through _test(), so everything _test() derives it
    derives here too: the exercise tag from the name (exNN_...), which puts
    the test in its exercise's :exNN suite -- the tag lvl_tags() never gave,
    so every hand-written test was missing from its suite (findings 070, 074,
    175) -- the level ladder from the layer, the build stand-in contract for
    a runner handed a student's program, and `manual` in the macro fixtures.
    //tools:conventions refuses sh_test() in a BUILD file, so there is one
    way to write a test, and c_levels()' audit holds every test of a project
    to the rules it gives (tools/defs_module.bzl, _audit_problems). A project's
    fixtures test, which holds its files to an //oracle arm, is
    oracle_fixtures()'s.

    Args:
        name: the target; in a project, exNN_<what>, ending in a suffix of
            _SUFFIX_LAYER that is this layer's (docs/reference.md, "Target
            names"). The audit fails a package whose test does not.
        layer: the layer tag, one of _LAYER_LEVEL ("diff", "selftest", ...).
        level: raise THIS test above its layer, only up (see _test). In a
            project a raise is listed in _RAISED, with its reason in
            docs/reference.md; the audit fails one that is not.
        tags: further tags that are not a layer, a level, an exercise or
            a unit (unit=<name>), which _test() derives from the name:
            "manual", which keeps a test out of every suite but :manual and
            out of //... (listed in _MANUAL, with the reason in the docs).
        **kwargs: everything else sh_test takes: srcs, args, data, size,
            timeout, shard_count, env. `waits`, the output test of its own
            exercise a gated one waits for where its gate alone cannot tell
            (see _test). And, in
            the macro fixtures alone, `refusals` (see _test and _refuse),
            which also collects this call's own refusals of a tag only a
            macro sets, and then declares nothing.
    """
    refusals = kwargs.get("refusals")
    who = "hand_test(name = %r)" % name
    for t in tags or []:
        if t.startswith(_WAITS_TAG) and _refuse(
            ("hand_test(name = %r): tags = [%r]. Say which output test it waits " +
             "for with waits = \"<that test>\", which the audit holds to its " +
             "gate.") % (name, t),
            refusals,
            who,
        ):
            return
        if (t.startswith(_COVERS_TAG) or t == _NO_VALGRIND_TAG) and _refuse(
            ("hand_test(name = %r): tags = [%r]. That tag is corpus_memory()'s, " +
             "which sets it from its `covers` or `no_valgrind` and asks for the " +
             "reason as a sentence: written here, it would excuse a corpus from " +
             "its memory twins with no reason anywhere.") % (name, t),
            refusals,
            who,
        ):
            return
        if t == _NO_GATE_TAG and _refuse(
            ("hand_test(name = %r): tags = [%r]. That tag excuses a diff layer " +
             "from waiting for its exercise's output test, and only a macro sets " +
             "it, with the reason beside it (tools/defs_module.bzl, _ungated_diff_problems): " +
             "written here, it would excuse one with no reason anywhere. Give it " +
             "a gate (output_gate).") % (name, t),
            refusals,
            who,
        ):
            return
    _hand_test(name, layer, level, tags, **kwargs)

def _hand_tag_problem(name, t):
    """Why hand_test() refuses tag `t`, one _test() derives; None if it takes it.

    The layer is hand_test()'s `layer`; the level ladder, the exercise tag
    and a unit's tag are derived from it and from the name (_test()). A
    value, so contract_problem("hand_tags") hands it to the fixtures.
    """
    if t in _LAYER_LEVEL or t.startswith("lvl_") or _is_ex(t) or t.startswith(_UNIT_TAG):
        return (("hand_test(name = %r): tags = [%r]. The layer is `layer`, and the " +
                 "level ladder and the exercise or unit tag are derived from it and " +
                 "from the name; a second copy is one that can disagree.") % (name, t))
    return None

def _hand_test(name, layer, level = None, tags = None, **kwargs):
    """hand_test() without its guard on corpus_memory()'s own tags."""
    _known_layer("hand_test(name = %r)" % name, layer)
    tags = tags or []
    for t in tags:
        problem = _hand_tag_problem(name, t)
        if problem:
            fail(problem)
    _test(name = name, level = level, tags = [layer] + tags, **kwargs)

def oracle_fixtures(name, fn, dir, in_dir_of, owns):
    """The test that holds a project's fixtures to the //oracle arm that writes them.

    `oracle FN` writes one record a file, and tools/oracle_fixtures.sh fails
    when a file under `dir` differs from its record, and when a file that one
    of `owns` matches is named by no record (a hand-typed one joining them
    unseen). It runs nothing of the student's, so it sits with the
    reference's own checks (layer oracle). Rush 00, Rush 02 and BSQ each
    wrote it out as a hand_test(), and two of them typed their patterns
    twice, as --owns and as the data's glob, held equal by a comment alone.
    Here one list makes both, so what is staged is what is owned: a plain
    name is staged as itself and a pattern globbed, so no glob names one
    literal file (//tools:conventions keeps that shape for 42's material).
    A pattern that matches no file stops the build (an empty glob is an
    error), and the runner refuses one that owns nothing (exit 2).

    Args:
        name: the target, <unit>_oracle_fixtures (exNN_oracle_fixtures for
            an exercise).
        fn: the //oracle arm that writes the files, "<x>_fixtures".
            //tools:conventions holds every such arm to a call that names it.
        dir: the fixtures' directory, relative to the package, ending in "/".
        in_dir_of: a file in `dir` that `owns` stages; the runner reads the
            directory from its path.
        owns: the patterns of the files the arm writes, relative to `dir`.
    """
    globbed = [dir + p for p in owns if "*" in p]
    hand_test(
        name = name,
        layer = "oracle",
        size = "small",
        srcs = ["//tools:oracle_fixtures.sh"],
        args = [
            "--oracle",
            "$(location //oracle:oracle)",
            "--fn",
            fn,
            "--in-dir-of",
            "$(location %s%s)" % (dir, in_dir_of),
        ] + [a for p in owns for a in ["--owns", p]],
        data = [
            "//oracle:oracle",
            "//tools:oracle_fixtures.sh",
        ] + [dir + p for p in owns if "*" not in p] + (native.glob(globbed) if globbed else []),
    )

def _location_label(arg):
    """The label inside "$(location X)", as written, or None."""
    if arg and arg.startswith("$(location ") and arg.endswith(")"):
        return arg[len("$(location "):-1]
    return None

def output_gate(test, refusals = None):
    """(args, data): a corpus replay's gate on `test`, an output test of this package.

    Every diff layer waits for its exercise's own output test, the one a
    stub fails (docs/reference.md, "Which layers wait for which"; c_levels()'
    audit, _ungated_diff_problems): while it is red the replay says SKIP,
    since a corpus replayed over a program the example already fails says
    that red again, hundreds of times and less usefully. The gate runs the
    program exactly as that test does, so it is read off the test, never
    written a second time: a diff_output.sh case (c_program's
    exNN_<case>_output) hands its program its words, each one --gate-arg;
    an argument table (c_argv_table's exNN_output) is run whole again,
    --gate-scenarios. --gate-label names the test in the SKIP line and in
    the test's own red log, which lists who waits for it. c_levels()' audit
    holds every gate to an output test that runs the program the same way
    (_gate_problems, _waiting_problems), the hand-written ones too.

    For argv_check.sh and file_check.sh, the runners that take both kinds.
    Call it below the macro that declares `test`.

    Args:
        test: the output test's name, "exNN_<case>_output" or "exNN_output".
        refusals: in tools/tests/macro_fixtures alone, the list this call's
            refusal is collected in instead of failing (_refuse); it then
            returns None.

    Returns:
        (args, data): the --gate-* options, to add to the replay's args (in
        corpus_memory's `args` too, so its twins wait behind the same gate),
        and what they name but the gate's program -- the replay's own
        :exNN_bin, which a replay lists already and corpus_memory adds to
        its twins.
    """
    who = "output_gate(%r)" % test
    _refuse(None, refusals, who)  # `refusals` anywhere but the fixtures
    r = native.existing_rule(test)
    if (r == None or not r["kind"].endswith("_test")) and _refuse(
        ("output_gate(%r): no test of that name is declared above this call in " +
         "//%s. The gate is read off the output test, so call it below the macro " +
         "that declares it (c_program, c_argv_table).") % (test, native.package_name()),
        refusals,
        who,
    ):
        return None
    runner = _norm_label((r.get("srcs") or [""])[0])
    args = list(r.get("args") or [])
    if "--waiting" not in args and _refuse(
        ("output_gate(%r): it hands its runner no list of who waits for it " +
         "(--waiting, _waiting_args), so its red log would never say what waits " +
         "for it. A test a gate waits for is an output test that hands one.") % test,
        refusals,
        who,
    ):
        return None
    if runner == "//tools:diff_output.sh":
        run = _output_run(args)
        why = _output_refusal(args)
        if why == None and run["argv_file"]:
            why = ("--argv-file", "it reads its arguments from a file, which a corpus gate does not hand its program")
        if why and _refuse(
            ("output_gate(%r): that case is run in a way a gate does not replay (%s: %s). " +
             "Wait for a case of the same exercise that hands its program its words " +
             "after \"--\" and compares its standard output against one file.") % (test, why[0], why[1]),
            refusals,
            who,
        ):
            return None
        gate = ["--gate-differ", "$(location //tools:diff_output.sh)"]
        data = ["//tools:diff_output.sh"]
        words = []
        for w in run["words"]:
            words += ["--gate-arg", w]
            if _location_label(w):
                data.append(_location_label(w))
    elif runner == "//tools:argv_table.sh":
        run = _table_run(args)
        why = _table_refusal(args)
        if why and _refuse(
            "output_gate(%r): that table compares nothing a gate replays (%s: %s)." % (test, why[0], why[1]),
            refusals,
            who,
        ):
            return None
        gate = ["--gate-differ", "$(location //tools:argv_table.sh)"]
        # argv_table.sh renders its verdict through diff_output.sh, which it
        # finds beside itself.
        data = ["//tools:argv_table.sh", "//tools:diff_output.sh", _location_label(run["scenarios"])]
        words = ["--gate-scenarios", run["scenarios"]]
    else:
        # Fails the load, or, in the macro fixtures, collects the refusal.
        _refuse(
            ("output_gate(%r): its runner is %s; a gate replays a diff_output.sh case " +
             "or an argv_table.sh table.") % (test, runner),
            refusals,
            who,
        )
        return None
    data.append(_location_label(run["expected"]))
    return gate + ["--gate-bin", run["bin"], "--gate-expected", run["expected"]] + words + ["--gate-label", test], data

def fixture_gate_problem(stem, rule):
    """Why a gate on `stem`'s output fixture cannot be built here, or None.

    _fixture_gate reads what the gate compares off <stem>_output, so that
    test is declared above the call that gates on it.

    Args:
        stem: the exercise or unit the gate waits for, "exNN" or "ft_x".
        rule: native.existing_rule(stem + "_output"), None where none is
            declared.
    """
    if rule == None or not rule["kind"].endswith("_test"):
        return ("a gate on %s_output: no test of that name is declared above this " +
                "call in //%s. A gate compares the fixture as that output test " +
                "does, and reads how off it, so call this macro below the one that " +
                "declares it (c_function, c_libft).") % (stem, native.package_name())
    return None

def _gate_compare(stem, sanitize = None, labeled = None):
    """The flags a fixture gate compares with: --gate-sanitize, --gate-labeled.

    Each is the output test's own --sanitize and --labeled, read off
    <stem>_output where the caller does not say: a gate that compared the
    fixture another way would read a right answer as red under --sanitize,
    and its layer would stand down for good. --labeled changes only how a
    table is drawn, which a gate never shows, and is passed all the same,
    so the gate is the output test's run, word for word.

    Args:
        stem: the exercise or unit, "exNN" or "ft_x".
        sanitize: True or False where the caller already knows (c_function,
            which declares that test), None to read it off the test.
        labeled: likewise.
    """
    if sanitize == None or labeled == None:
        rule = native.existing_rule(stem + "_output")
        problem = fixture_gate_problem(stem, rule)
        if problem:
            fail(problem)
        args = list(rule.get("args") or [])
        if sanitize == None:
            sanitize = "--sanitize" in args
        if labeled == None:
            labeled = "--labeled" in args
    return (["--gate-sanitize"] if sanitize else []) + (["--gate-labeled"] if labeled else [])

def _fixture_gate(stem, expected_f, bin = None, stdin = None, sanitize = None, labeled = None, compare = True):
    """(args, data): a layer's gate on `stem`'s own output fixture.

    The memory, allocation-failure, method, cycles and corpus layers of a
    function wait for its output test: while that is red they SKIP, since
    their report over a wrong answer speaks over the one red that matters.
    The gate runs diff_output.sh over the fixture as the output test does
    (_gate_compare), and its SKIP line names that test (--gate-label), which
    c_levels()' audit holds to the gate's program and file (_waits_for).

    Args:
        stem: the exercise or unit, "exNN" or "ft_x"; the test waited for is
            <stem>_output.
        expected_f: the fixture, a path under tests/.
        bin: the program the gate runs, a label; :<stem>_bin by default.
        stdin: a file the gate's run reads on standard input, or None.
        sanitize: as _gate_compare takes it.
        labeled: likewise.
        compare: False leaves _gate_compare's flags out, for a caller that
            places them itself.

    Returns:
        (args, data): the --gate-* options, and what they name:
        diff_output.sh, the program and the fixture (and stdin).
    """
    if bin == None:
        bin = ":%s_bin" % stem
    args = [
        "--gate-differ",
        "$(location //tools:diff_output.sh)",
        "--gate-bin",
        "$(location %s)" % bin,
        "--gate-expected",
        "$(location %s)" % expected_f,
        "--gate-label",
        stem + "_output",
    ]
    data = ["//tools:diff_output.sh", bin, expected_f]
    if compare:
        args += _gate_compare(stem, sanitize, labeled)
    if stdin:
        args += ["--gate-stdin", "$(location %s)" % stdin]
        data.append(stdin)
    return args, data

def corpus_no_valgrind_problem(stem, kind, name, valgrind):
    """Why corpus_memory(no_valgrind = ...) is refused, or None.

    no_valgrind leaves out the memcheck arm of a corpus whose program may
    allocate. Where the subject allows no malloc there is no such arm, and
    the sentence explains nothing: refused, naming whose subject it is --
    "exercise ex05", or in a contract of units the entry the allowed list
    is read from ("library libft", "project bsq").
    """
    if valgrind:
        return None
    return ("corpus_memory(stem = %r): no_valgrind, but %s %s's subject " +
            "allows no malloc, so there is no memcheck arm to leave out.") % (stem, kind, name)

def corpus_memory(stem, runner, args, data, bin = None, asan_bin = None, sample = 25, size = "medium", no_valgrind = None, covers = None, waits = None):
    """A corpus runner's replay under the memory checkers (finding 113).

    The memory layers ran each FIXED case only (c_program's _asan and
    _valgrind arms) and every generated corpus ran on the plain build, so a
    path only generated input reaches -- a search that found nothing, a long
    number, a map past nine rows, a file past one buffer -- was never
    memory-checked. This emits the corpus's replay under them, through the
    runner's own --sanitized and --valgrind (tools/runner_lib.sh, "A CORPUS
    UNDER A MEMORY CHECKER"):

      <stem>_diff_asan  every case on the ASan/UBSan build, judging memory and
                        how each run ended, never the output: layer diff_asan
                        (robust), with every crash-fuzz twin.
      <stem>_valgrind   where the exercise's subject() contract allows malloc
                        (its `allowed` names it, or there is no such line:
                        _memcheck_allowed): `sample` cases spread evenly over
                        the corpus, each through valgrind_test.sh as a fixed
                        case's _valgrind arm is, leaks included. Layer
                        valgrind (strict). Read from the contract, not
                        passed: whether the subject allows malloc is a fact
                        about the project, declared once.

    Both go through hand_test()'s placement, so c_levels()' audit holds them
    like every other test -- and it holds a package to them: EACH plain
    replay through one of _CORPUS_RUNNERS needs twins replaying the same
    corpus (its arguments less _CORPUS_RUN_OPTS: _audit_problems), so `args`
    is the plain replay's, less --bin. What a run under a checker asserts,
    every reading of a subject agrees on, so neither needs a `manual` tag
    where the plain replay has one (Rush 02).

    Args:
        stem: the targets' front, exNN_<what> (ex02_file): the plain
            replay's name less its layer's suffix, where it has one. In a
            package whose subject() contract is divided into units, it is
            <unit> or <unit>_<what>, after the unit it tests (BSQ's bsq,
            bsq_stdin).
        runner: the corpus runner, one of _CORPUS_RUNNERS.
        args: the runner's arguments for the corpus, without --bin: the
            generator, its size AND its transport, as the plain replay passes
            them -- a corpus a program reads on standard input passes the
            runner's --mode stdin here too (BSQ's bsq_stdin), or its twins
            replay another corpus than the one they stand for, which the audit
            refuses. Read them from one table that the plain replay reads as
            well (C 06's C06_ARGV_CORPORA, C 10's C10_FILE_CORPORA).
        data: what those arguments name, without the program.
        bin: the plain program, for memcheck; default :exNN_bin.
        asan_bin: its ASan build; default :exNN_bin_asan. A program whose
            input is its arguments replays on c_argv_table's guarded build,
            :exNN_argvguard_bin_asan, where each argument sits in a heap
            block of its own; the twin then tells argv_check.sh so
            (--guarded-argv), whose verdict says what the sanitizer could
            see of the arguments either way (finding 071). c_levels()' audit
            refuses an argv_check.sh replay under ASan that does not run the
            guarded build of an exercise that has one.
        sample: how many cases memcheck runs.
        size: the Bazel size of both tests.
        no_valgrind: why this corpus gets no memcheck arm although malloc is
            allowed -- a sentence, never a bare flag: BSQ's million-cell maps,
            minutes for a correct program at memcheck's 20-50x.
        covers: {plain replay: why} -- the plain replays of this exercise and
            runner that these twins stand in for although they replay LESS,
            each with its reason as a sentence: Rush 01's sweep, whose bonus
            sizes a correct solver may take seconds on, which under a checker
            is a timeout that says nothing about memory. Without it the audit
            asks every plain replay for twins of exactly its corpus.
        waits: the output test of its own exercise the plain replay's gate
            (in `args`) waits for, where the gate alone cannot tell
            (hand_test's `waits`): both twins replay behind the same gate.
            The gate's own program (--gate-bin, the plain :exNN_bin) is
            added to each twin's data here, since a twin runs another build.
    """
    contract = _contract_or_none()
    if contract != None and "units" in contract:
        # In a contract of units the stem begins with its unit's name, and
        # the entry is that unit's, or its library's for a function.
        rows = _units_of(contract)
        names = [r["name"] for r in rows]
        ex = stem if stem in names else _unit_of_name(stem, names)
        if ex == None:
            fail(("corpus_memory(stem = %r): a stem is <unit> or <unit>_<what>, after a " +
                  "unit of this package's contract (%s)") % (stem, ", ".join(names)))
        key = [r["key"] for r in rows if r["name"] == ex][0]
        owner = [r for r in rows if r["name"] == ex][0]
        who = ("library", owner["library"]) if owner["kind"] == "function" else (owner["kind"], ex)
    else:
        ex = stem.split("_")[0]
        if not _is_ex(ex):
            fail("corpus_memory(stem = %r): a stem is exNN_<what>, so the targets land in :exNN." % stem)
        key = _key(ex)
        who = ("exercise", ex)
    if runner not in _CORPUS_RUNNERS:
        fail(("corpus_memory(stem = %r): %s is not one of tools/defs_test.bzl's " +
              "_CORPUS_RUNNERS, the runners that take --sanitized and --valgrind.") %
             (stem, runner))
    for a in ["--sanitized", "--valgrind", "--valgrind-tools", "--sample", "--rule", "--bin", "--symbolizer", "--symbolizer-lib"]:
        if a in args:
            fail(("corpus_memory(stem = %r): args holds %s, which this macro " +
                  "passes itself; give it the plain replay's corpus arguments.") % (stem, a))

    def _reason(what, why):
        if type(why) != "string" or len(why.split(" ")) < 4:
            fail(("corpus_memory(stem = %r): %s is a reason, as a sentence; got %r.") %
                 (stem, what, why))

    valgrind = _memcheck_allowed(_entry(key, "corpus_memory"))
    gate_bin = _location_label(_opt_value(args, "--gate-bin"))
    if no_valgrind != None:
        _reason("no_valgrind", no_valgrind)
        problem = corpus_no_valgrind_problem(stem, who[0], who[1], valgrind)
        if problem:
            fail(problem)
    tags = []
    for n, why in sorted((covers or {}).items()):
        if not n.startswith(ex + "_") or ":" in n:
            fail(("corpus_memory(stem = %r): covers names %r; it takes the names of " +
                  "plain replays of %s in this package (\"%s_sweep\"), each with the " +
                  "reason these twins stand in for it.") % (stem, n, ex, ex))
        _reason("covers[%r]" % n, why)
        tags.append(_COVERS_TAG + n)
    valgrind = valgrind and no_valgrind == None
    bin = bin or ":%s_bin" % ex
    asan_bin = asan_bin or ":%s_bin_asan" % ex

    guarded = ["--guarded-argv"] if asan_bin.endswith(_ARGV_GUARD_SUFFIX) else []
    gate_data = [gate_bin] if gate_bin else []
    _hand_test(
        name = stem + "_diff_asan",
        layer = "diff_asan",
        tags = tags + ([_NO_VALGRIND_TAG] if no_valgrind != None else []),
        size = size,
        srcs = [runner],  # one of _CORPUS_RUNNERS
        args = ["--bin", "$(location %s)" % asan_bin] + args + ["--sanitized"] + guarded + _symbolizer_args(),
        data = _uniq([asan_bin, runner] + data + gate_data + _SYMBOLIZER_DATA),
        waits = waits,
    )
    if valgrind:
        # The subject's own sentence about memory, where its c_program
        # declared one (memory_rule): a red quotes it once under its
        # verdict, as each fixed case's _valgrind arm does (V82). Read from
        # the file c_program writes, never passed again;
        # _memory_rule_reach_problems refuses a twin without it. Without
        # one, the contract's (memory_graded), as c_program's arms quote it;
        # the contract's sentence on an invalid access either way.
        rule = ex + "_memory_rule"
        rule_args, rule_data = _graded_rule()
        if native.existing_rule(rule):
            rule_args, rule_data = _graded_rule(leaks = False)
            rule_args = rule_args + ["--rule", "$(location :%s)" % rule]
            rule_data = rule_data + [":" + rule]
        _hand_test(
            name = stem + "_valgrind",
            layer = "valgrind",
            tags = tags,
            # A sample of the corpus under memcheck, at 20-50x: never
            # "small", whatever the plain and ASan replays take. BSQ's and
            # Rush 01's readings samples took 18-23s with two suites on the
            # machine, a third of "small"'s 60 (finding 066).
            size = "medium" if size == "small" else size,
            srcs = [runner],  # one of _CORPUS_RUNNERS
            args = ["--bin", "$(location %s)" % bin] + args + _valgrind_args() +
                   ["--sample", str(sample)] + rule_args,
            # valgrind_test.sh judges each sampled case; the runner finds it
            # beside itself in the runfiles (rl_mem_ready).
            data = _uniq([bin, runner, "//tools:valgrind_test.sh"] + data + gate_data + _valgrind_data() + rule_data),
            waits = waits,
        )

def _no_orphan_prototype(ex, macro):
    """Refuse a tests/exNN/prototype.h that the calling macro will never read.

    _prototype_test()'s `required` guard exists because "deliberately opted out"
    and "nobody wrote it yet" were indistinguishable for a MISSING prototype
    layer. This is the mirror: a contract header that is WRITTEN and wired to
    nothing. c-08 ex01 carried one for months; it did not even compile — a stray
    line of the exercise's test main sat in it where a declaration belonged,
    which is itself the proof that nothing ever read it.

    Neither shape has a definition for a prototype layer to check. A header
    exercise's deliverable IS the declarations, and a program exercise's entry
    point is main, whose signature the compiler already fixes. So the file can
    only be a leftover, and saying so at analysis time costs nothing.
    """
    if native.glob(["tests/%s/prototype.h" % ex], allow_empty = True):
        fail(
            ("%s(%s) found tests/%s/prototype.h, which it will never " +
             "use: %s exercises get no prototype layer. Delete the file, or " +
             "move the exercise to a macro that has one.") %
            (macro, _call(_key(ex)), ex, macro),
        )

def shell_word(text):
    """`text` as ONE argument of a test's `args`, exactly as written.

    Bazel reads a test's `args` twice: it expands $(...) and $$, and then
    splits the result into arguments as a Bourne shell would. So each '$' is
    doubled, to come out of the expansion as itself, and the whole is put in
    single quotes, each apostrophe closed, escaped and reopened ('\\''), to
    come out of the split as one argument: a subject's sentence, a file name
    with a blank, a hint with an apostrophe or a '$'. The one quoting of an
    `args` word: there were two, and one said a '$' could not be quoted at
    all, so stderr_ignored() and exit_quote refused one that the other quoted
    (--stray, --wording) without trouble. //tools:conventions refuses a
    hand-written quoting in a .bzl file.

    Args:
        text: the argument, as the runner must receive it.

    Returns:
        The quoted word, to put in `args`.
    """
    return "'" + text.replace("$", "$$").replace("'", "'\\''") + "'"

# The name c_argv_table gives its guarded-argv program after "exNN": what
# corpus_memory reads a guarded replay from, and what the audit looks for.
_ARGV_GUARD_SUFFIX = "_argvguard_bin_asan"


# ---------------------------------------------------------------------------
# WHAT THE FILES ABOVE THIS ONE LOAD OF IT. A load() cannot name a private
# symbol, so each one they use is given a public name here, its own without
# the underscore, and loaded back under its own name: the code reads as it did
# when tools/defs.bzl held it all. These names are for those files alone; a
# BUILD file loads //tools:defs.bzl.
output_fixture_binary = _output_fixture_binary
table_run = _table_run
compared_run = _compared_run
output_run = _output_run
NO_GATE_TAG = _NO_GATE_TAG
GATE_NO_INPUT_RUNNERS = _GATE_NO_INPUT_RUNNERS
waiting_args = _waiting_args
waiting_problems = _waiting_problems
runner_choice_problem = _runner_choice_problem
CORPUS_RUNNERS = _CORPUS_RUNNERS
COVERS_TAG = _COVERS_TAG
NO_VALGRIND_TAG = _NO_VALGRIND_TAG
corpus_of = _corpus_of
memcheck_allowed = _memcheck_allowed
standin_runner_problem = _standin_runner_problem
test = _test
test_env_problem = _test_env_problem
hand_tag_problem = _hand_tag_problem
no_orphan_prototype = _no_orphan_prototype
fixture_gate = _fixture_gate
gate_compare = _gate_compare
ARGV_GUARD_SUFFIX = _ARGV_GUARD_SUFFIX
