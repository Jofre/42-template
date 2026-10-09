"""Macros for scaffolding 42 C-Piscine exercises.

Every project's BUILD file opens with its SUBJECT CONTRACT -- subject() and
exercise(), from tools/subject.bzl, re-exported here -- and every macro below
reads the facts of the subject from it: where each exercise turns in, which
files it names or allows, what the grader brings, what it may call. None of
them is ever passed at a call site (see "THE SUBJECT CONTRACT" below).

Every exercise lives in two trees inside its module:
  deliverable/exNN/  -> the files the student submits (stubs to be implemented),
                        or deliverable/ itself where the subject names no
                        turn-in directory (BSQ, the Common Core): turnin_dir()
  tests/exNN/        -> the test harness + expected output (never submitted),
                        and the harness's copies of whatever the grader brings

Exercise shapes:
  c_function  -> a function with no main(); a separate harness calls it and we
                 diff stdout against expected.txt.
  c_program   -> a program that owns main() and reads argv/stdin/files; the
                 deliverable source is compiled directly and run with argument cases.
  c_header    -> a header-only deliverable (c-08). The compile happens inside the
                 runner, where the header's own diagnostics and clues can be
                 shown beside the test's table.
  c_make      -> a build-system deliverable (a Makefile or a shell script that
                 produces libft.a / a binary); we build it and check artifacts.
                 The grader's own files (the contract's `provided`) are staged
                 beside a Makefile turned in alone (c-09 ex01, Reloaded ex24).
  c_libft     -> c-09 ex00's shape: loose sources built into an archive by a
                 build system the student writes, PLUS the behaviour of those
                 sources. Its output layer compiles inside the runner too, so a
                 header turned in beside the sources can be a stub without
                 breaking the build.
  c_argv_table-> one labelled table for an argv program run over many invocations.

Layers an exercise can add:
  c_diff      -> differential value + crash-fuzz against the //oracle reference
  c_mem_check -> adversarial ASan probes (exact-size / unterminated buffers)
  c_perf      -> informative cost measurement (time AND memory growth)
  c_files     -> the deliverable file SET, against the subject's turn-in line;
                 c_levels() emits one per exercise, from the contract
  c_levels    -> the per-module suites (a level, an exercise, the manual
                 targets), and the audit of the module as a whole
  hand_test   -> a test written out in a BUILD file, derived like a macro's

Every generated test is tagged with its layer AND with cumulative lvl_* tags, so
`bazel test //<module>:basic` selects a level and `--test_tag_filters=norm`
still selects a single layer. See _LAYER_LEVEL for the mapping.

NO DELIVERABLE CAN BREAK THE BUILD GRAPH. Two rules, and every macro here keeps
both. //tools:conventions refuses what it can see, and
//tools/tests:macro_fixtures_test checks on every run, on toy exercises in
every broken state (tools/tests/macro_fixtures), what it can: that the package
loads, that each toy's program is a real one or a stand-in of the right kind,
and that every layer is emitted as layers.expected lists it -- a NOT TURNED IN
test where nothing was turned in, and only there. The toys cover c_function,
c_files, c_program (plain and Makefile, and a Makefile turned in at the root
of deliverable/ with srcs/ and includes/), c_header, c_make and shell_exercise;
the other macros (c_libft, c_mem_check, c_diff, c_perf, c_cycles,
c_reference_cost, c_argv_table, the rush macros, student_lib) are covered by
the modules that use them and by the rules below, not by a toy. A toy module
of its own (tools/tests/macro_fixtures/levels) proves c_levels() and
hand_test(): how exercises are found, a folder that is no exercise, the audit
passed by a test declared after the call, and the kinds of a program case.
The VERDICT of each toy's layers cannot be checked by a test; it is measured
by hand, with the command in that BUILD file:

  * Every program built from deliverable sources goes through _student_bin()
    (tools/student_build.bzl), never cc_binary or cc_library. Code that does not
    compile or link becomes a stand-in program that prints the compiler's words
    and fails every test that runs it -- one red test each, not FAILED TO BUILD.
  * No deliverable or generator path is ever a literal declared input. Each is
    found with a glob (allow_empty = True): _zone(), _deliverable_srcs() and
    turnin_glob(). A missing file then fails the tests that needed it, through
    _test()'s `turnin`, instead of failing the build or the loading of the
    package. And a file whose NAME no label or argument list can carry -- a
    blank, a parenthesis: "ft_putchar copy.c", "ft_putchar (1).c", what a
    desktop names a duplicate -- is dropped from every build and every layer
    by the same helpers (_safe()); the files layer, which reads names and
    never contents, is the one that reports it, by its real name.
"""

load("@rules_shell//shell:sh_test.bzl", "sh_test")
load(":names_file.bzl", "names_file")
load(":student_build.bzl", "student_binary", "student_unit")
load(
    ":subject.bzl",
    _exercise = "exercise",
    _exercise_problem = "exercise_problem",
    _linked_problem = "linked_problem",
    _subject = "subject",
    _subject_problem = "subject_problem",
)

# The contract's two public names, loaded from here like every other macro: a
# project's BUILD file opens with subject(... exercise(...) ...). See
# tools/subject.bzl.
exercise = _exercise

def subject(grader, group, exercises, strict = True, name = "subject"):
    """A project's subject contract (tools/subject.bzl's subject()), and who waits for each output.

    The contract, as tools/subject.bzl declares it; then the finalizer that
    writes, once the package is declared, the list each output test hands its
    runner of the tests that wait for it (_WAITING). Here and not in
    c_levels(): every package that can declare an output test has a contract,
    and one without c_levels() -- the macro fixtures -- otherwise named lists
    nothing wrote, and its output tests did not build.

    Args:
        grader: as tools/subject.bzl's subject() takes it.
        group: the same.
        exercises: the same.
        strict: the same.
        name: the same.
    """
    _subject(grader = grader, group = group, exercises = exercises, strict = strict, name = name)

    # Public, as the contract is: //tools/tests reads the macro fixtures'.
    _waiting(name = _WAITING, visibility = ["//visibility:public"])

# -std=gnu17 is EXPLICIT, not inherited.
#
# It is what clang-12 and gcc-10 already default to -- verified with
# `-dM -E`: both define __STDC_VERSION__ 201710L and neither defines
# __STRICT_ANSI__, on the box and on the fetched copies alike -- so nothing
# compiles differently today. What it removes is a silent dependency on a
# default.
#
# The hazard is specific and already recorded: five c-12 contracts declare a
# comparator as `int (*cmp)()` because the subject writes it that way. Under
# gnu17 `()` means "unspecified parameters" and a student's fully-typed
# comparator is correctly accepted. Under C23 `()` means `(void)`, and all five
# would begin REJECTING correct code -- an entire module going red on a
# toolchain bump nobody connected to it.
#
# Pinning it here is half the answer; the other half is that the campus box's
# own default has to keep matching, since the Moulinette compiles with no -std
# at all. tools/pins.tsv carries a row for exactly that, so a campus move shows
# up as drift rather than as a divergence nobody sees.
_COPTS = ["-Wall", "-Wextra", "-Werror", "-std=gnu17"]

# ASan+UBSan build for the crash-fuzz variant of the differential layer: the
# same corpus (c_diff's asan_count cases) is replayed through an instrumented
# harness+student to catch out-of-bounds / use-after-free / UB that returns the
# right value.
_ASAN_COPTS = ["-fsanitize=address,undefined", "-fno-sanitize-recover=all", "-g"]

# Link ASan binaries with bfd, not the (deprecated) gold linker: gold emits a
# noisy "Cannot export local symbol 'asan_extra_spill_area'" warning per binary
# when the toolchain defaults to it. The bare name resolves to the PINNED ld.bfd:
# //tools/cc_toolchain puts its linker wrappers first on clang's program search,
# so this no longer reaches /usr/bin/ld.bfd through PATH (HISTORY.md §21, #3).
_ASAN_LINKOPTS = ["-fsanitize=address,undefined", "-fuse-ld=bfd"]

# Unbuffered stdout for the harness's own output fixtures: see
# tools/unbuffered_stdout.c. The library, for a cc_binary, and the same file as
# a source, for the two runners that compile a fixture at test time
# (header_check.sh, ilp32_test.sh). //tools:conventions checks that the library
# reaches every output fixture and no other binary.
_UNBUFFERED = "//tools:unbuffered_stdout"
_UNBUFFERED_C = "//tools:unbuffered_stdout.c"

def _output_fixture_binary(name, harness, prototype, deps = None, **kwargs):
    """A student_binary whose main() is the harness's, run by diff_output.sh.

    `prototype` is _student_bin's, which every harness over a student's files
    is built with and which requires it: the test that holds the functions
    the harness calls to the signatures the subject fixes, or "none: <the
    reason>".

    The only way an output fixture is built, so none can miss the library that
    makes its stdout unbuffered: with it, the rows a fixture printed before the
    student's code crashed reach the table as real results, and the first line
    missing is the case that was running (tools/unbuffered_stdout.c). The
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
        deps = (deps or []) + [_UNBUFFERED],
        **kwargs
    )

# The tag a program built over a harness carries naming its prototype test
# ("none" where there is none). _student_bin writes it, and c_levels()' audit
# reads it from every student_binary with a harness (_audit_problems), so one
# declared some other way, without the tag, is refused there too.
_HARNESS_PROTO_TAG = "prototype_test="

# The tag a NAMED CASE's test carries, listing the files the case reads: its
# expected output(s), the files its program is handed and its stdin, as
# package paths joined by ",". c_program's and c_header's cases and Rush 00's
# named cases (each variant's table, defense and survival rows, and
# ft_putchar's) write it (_case_reads_tag), and c_levels()' audit reads it
# beside every test of the package that holds a directory's files to //oracle
# (tools/oracle_fixtures.sh, _oracle_owner): a case reading a file in that
# directory that none of the test's --owns patterns matches reads a file the
# reference never wrote and nothing compares, so it can drift in silence --
# the hole oracle_fixtures.sh's own UNOWNED check cannot see, since it only
# looks at files its patterns match.
_CASE_READS_TAG = "case_reads="

def _case_reads_tag(files):
    """The _CASE_READS_TAG for a case that reads `files`, each once, sorted."""
    return _CASE_READS_TAG + ",".join(sorted({f: True for f in files}.keys()))

def _oracle_owner(rule):
    """What a test running tools/oracle_fixtures.sh owns, from its rule; None for any other test.

    Returns {"dir": the fixtures' directory, from --in-dir-of's $(location
    FILE), or None where that cannot be read; "owns": its --owns patterns,
    relative to the directory}.
    """
    if not [s for s in (rule.get("srcs") or []) if s.split(":")[-1] == "oracle_fixtures.sh"]:
        return None
    args = list(rule.get("args") or [])
    d = None
    owns = []
    for i in range(len(args) - 1):
        v = args[i + 1]
        if args[i] == "--in-dir-of" and v.startswith("$(location ") and v.endswith(")"):
            path = v[len("$(location "):-1].strip().split(":")[-1]
            if "/" in path:
                d = path.rpartition("/")[0]
        elif args[i] == "--owns":
            owns.append(v)
    return {"dir": d, "owns": owns}

def _segment_glob_match(pattern, s):
    """Whether one path segment `s` matches `pattern`, where '*' is any run and '?' one character."""
    can = [True] + [False] * len(s)  # can[j]: the pattern so far matches s[:j]
    for c in pattern.elems():
        nxt = [False] * (len(s) + 1)
        if c == "*":
            nxt[0] = can[0]
            for j in range(1, len(s) + 1):
                nxt[j] = nxt[j - 1] or can[j]
        else:
            for j in range(1, len(s) + 1):
                nxt[j] = can[j - 1] and (c == "?" or c == s[j - 1])
        can = nxt
    return can[len(s)]

def _path_glob_match(pattern, path):
    """Whether `path` matches `pattern` as the shell globs it: no '*' or '?' crosses a '/'."""
    p = pattern.split("/")
    s = path.split("/")
    if len(p) != len(s):
        return False
    for i in range(len(p)):
        if not _segment_glob_match(p[i], s[i]):
            return False
    return True

def _harness_prototype_problem(name, harness, prototype):
    """_student_bin's message for a `prototype` it cannot use with `harness`; None if it can."""
    if not harness:
        if prototype == None:
            return None
        return (("_student_bin(%s, prototype = %r): a program with no harness is the " +
                 "student's own, built from their main(), and no harness of ours calls " +
                 "their functions in it. Pass `prototype` only with `harness`.") % (name, prototype))
    if type(prototype) == "string" and prototype.startswith("none: ") and prototype[6:].strip():
        return None
    if type(prototype) == "string" and prototype.endswith("_prototype") and ":" not in prototype:
        return None
    return (("_student_bin(%s, prototype = %r): a harness links a student's functions " +
             "the way the grader's main() does, and C links a mismatched signature " +
             "without a word. Name the package's test that checks the signatures " +
             "this harness calls (\"exNN_prototype\", as _prototype_test() returns " +
             "it), or say why there is none: \"none: <the reason>\".") % (name, prototype))

# Every test these macros emit runs in well under a second (norminette, one
# compile, an output diff, valgrind on a tiny program, a small make). Declaring
# them "small" gives a 60s timeout — a runaway loop in a student's code fails fast
# instead of hanging for the 5-min "moderate" default — and tells Bazel they are
# cheap, so it schedules more of them in parallel. New tests inherit this default.
# Which gate level each layer belongs to. Same ladder //tools:submit uses:
#   1 basic    — every layer whose failure is an outright KO wherever the project
#                is graded: at the Moulinette, or at a defense (the rushes)
#   2 strict   — real KOs, but conditional on the evaluator's main() or the module
#   3 robust   — this repo's own correctness rigour, beyond anything 42 checks
#   4 complete — portability and cost as well
#
# WHY AN EXERCISE MAY LACK A LAYER — the reason codes.
#
# Most exercises get most layers. Where one is absent it is a DECISION, and the
# question a reader always arrives with is the same: "is this an oversight?"
# That question needs one word, not a paragraph, so each absence is marked at
# its call site with a code from this list:
#
#   ZERO-INPUT           the function takes nothing to vary. `void f(void)` has
#                        one behaviour and a curated fixture already covers it,
#                        so a generator has nothing to generate.
#   SMALL-INPUT-SPACE    the input space is enumerable and the curated fixture
#                        already enumerates it. Fuzzing adds repetition.
#   REPEATED-CONTRACT    the same contract is fuzzed where it FIRST appears.
#                        c-04 ex00/ex01 and c-09 ex00 restate functions c-01 and
#                        c-02 already fuzz against the oracle. That corpus is
#                        not coverage in the later module, which is graded on
#                        its own files: what it pins that every reading agrees
#                        on (a byte above 0x7f counted, written) goes in the
#                        later module's own output fixture.
#   NO-MALLOC-ALLOWED    the subject's authorised-function list has no malloc,
#                        so there is no allocation for valgrind to report on.
#   RUNTIME-SIZED-ALLOC  the function computes its own allocation size from the
#                        input, so an exact-size ASan probe could only re-derive
#                        the implementation and call the agreement a test.
#   SENTINEL-BOUND       the bound is a NULL sentinel rather than a number, so
#                        there is no size to under-allocate by one.
#   NO-CORPUS-SHAPE      the corpus encodes a structure (a list, a tree) rather
#                        than bytes, and this exercise's shape is not one the
#                        generator can express.
#   BOUNDED-COST         every case costs within a few operations of every other,
#                        so a per-unit figure has nothing to distinguish.
#   NO-SURFACE           there is nothing for the check to inspect — a header of
#                        prototypes has no object file, no expandable call.
#
# The rule for using them: one line at the call site naming the code, plus a
# clause only where THIS exercise's reason is not obvious from the code alone.
# The long-form argument for each belongs here, once, not at every site that
# happens to hit it.
_LAYER_LEVEL = {
    "norm": 1,
    "compile": 1,
    "output": 1,
    "files": 1,
    "forbidden": 1,
    "prototype": 1,
    "symbols": 2,
    "valgrind": 2,
    # HOW the turn-in is built, where a subject says so and no output can
    # show it: "Create a recursive function", "Create an iterative
    # function", "by declaring a fixed-size array ... slightly less than 30
    # ko" (tools/method_check.sh). STRICT: the sentence is the subject's own,
    # but the grader only runs the program, so only an evaluator reading the
    # code marks it -- "real, but not certain" (WP-90, findings 065, 114).
    "method": 2,
    # LEVEL 2, not 3, and the demonstration is why. Change
    # c-piscine/c-piscine-c-01/deliverable/ex06/ft_strlen.c from `while (*str != \'\\0\')`
    # to `while (*str > 0)` -- the signed-char trap -- and it compiles clean
    # under -Wall -Wextra -Werror, norminette says OK, and the level-1 fixture
    # passes 8/8. The function returns the wrong number for any string holding a
    # byte >= 0x80, and in c-01 ONLY exNN_diff sees it: its hand-written
    # fixture carries no byte above 0x7f, while the generated corpora seed
    # 0x7f/0x80/0xff on purpose. So the layer holding the interesting bytes was
    # the one held above the gate. (Some fixtures do carry such bytes -- c-03's,
    # and c-04 ex00/ex01's and c-09 ex00's, whose own modules have no corpus for
    # them -- and those go red on the trap at basic.)
    #
    # Not level 1, though, and the difference from `output` is real: a
    # differential compares against a reference this repo wrote, over inputs
    # nobody typed, so a disagreement can be a place the subject left open
    # rather than a mistake. That is the same "real but not certain" line
    # `symbols` and `valgrind` sit on. One test genuinely does assert an
    # interpretation and says so at its call site -- c-06 ex03 -- and it raises
    # itself back to 3 rather than the whole layer staying there.
    "diff": 2,
    # STAYS AT 3, and must: it is emitted --crash-only (rust_diff.sh does not
    # compare values on this arm), so what it reports is a sanitizer finding
    # over generated input. No 42 grader runs a sanitizer.
    "diff_asan": 3,
    "asan": 3,
    # Refusing one allocation at a time. LEVEL 1, and it was 3 for a reason that
    # did not survive being looked at: "the exercise it is wired to does state
    # the requirement verbatim, but nothing proves the Moulinette exercises that
    # branch". That is an argument about the GRADER's test vectors, and the
    # level it justified left a live NULL dereference -- c-07 ex00's ft_strdup,
    # which calls malloc and dereferences the result with nothing in between --
    # red in this suite and green at the gate every fork actually submits
    # against. `bazel run //tools:submit` pushed it.
    #
    # Both exercises that enable this layer cite a contract for it. c-08 ex04's
    # subject says "It should return a NULL pointer if an error occurs"; c-07
    # ex00's says "Reproduce the behavior of the function strdup (man strdup)",
    # and that man page states the NULL return. Neither is this repo inventing a
    # requirement, which is the only thing level 1 has to be protected from --
    # and the layer stays DELIBERATELY OPT-IN per exercise, so an exercise with
    # no such sentence never meets it at all (see c_function's `allocfail`, and
    # `allocfail_level` for one enabled on a weaker hook).
    #
    # What this costs, measured: //c-piscine/c-piscine-c-07 blocks at the default gate.
    # That is the point.
    "allocfail": 1,
    "ilp32": 4,
    "perf": 4,
    "cycles": 4,
    "oracle": 4,
    "selftest": 4,
}

_LEVEL_NAMES = ["basic", "strict", "robust", "complete"]

# The page whose table says why each test _RAISED lists sits where it does,
# staged beside those tests (_test, runner_lib.sh's rl__raised).
_DOC_REFERENCE = "//:docs/reference.md"

# WHAT A TARGET'S NAME SAYS, AND WHERE IT SITS. Every test in a project is
# named exNN_<what>, and the end of the name says which layer it is: the
# LONGEST of these suffixes the name ends with, mapped to its layer tag and,
# where the suffix itself raises the test, to the level it sits at (None: its
# layer's). A case name sits in front of it ("ex05_modzero_output"), a rush
# variant too ("ex00_rush03_asan").
#
# c_levels()' audit fails a package whose test ends in no suffix here, or in
# one whose layer is not the test's own: a reader looking a target up in
# docs/reference.md ("Target names") must find it there, under the layer its
# tags give it. //tools:conventions holds that table and this one to the same
# rows, as it holds the layer table to _LAYER_LEVEL (finding 038: _memcheck,
# _refcost and Rush 00's _robust were in no document; the last, a basic test
# named after a level, is _survive now). A case whose name collides with a
# longer suffix ("diff" makes ex00_diff_asan, which reads as diff_asan) is
# refused by the same check: rename the case.
_SUFFIX_LAYER = {
    "_allocfail": ("allocfail", None),
    "_allocfail_leaks": ("allocfail", 3),
    "_program_allocfail": ("allocfail", 3),
    "_program_allocfail_leaks": ("allocfail", 3),
    "_argv_diff_exit": ("diff", 3),
    "_asan": ("asan", None),
    "_bonus_9x9": ("diff", None),
    "_bsq_big": ("output", 2),
    "_bsq_big_stdin": ("output", 2),
    "_bsq_long": ("output", None),
    "_bsq_long_stdin": ("output", None),
    "_bsq_multi": ("diff", None),
    "_bsq_stdin": ("diff", None),
    "_build": ("output", None),
    "_build_recipe": ("output", 2),
    "_build_rules": ("output", 3),
    "_build_wildcards": ("output", 2),
    "_compile_clang": ("compile", None),
    "_compile_gcc": ("compile", None),
    "_cycles": ("cycles", None),
    "_defense": ("output", None),
    "_diff": ("diff", None),
    "_diff_asan": ("diff_asan", None),
    "_exit": ("output", 3),
    "_files": ("files", None),
    "_fixed_array": ("method", None),
    "_forbidden": ("forbidden", None),
    "_ilp32": ("ilp32", None),
    "_issued": ("output", None),
    "_layout_prototype": ("prototype", 2),
    "_lint": ("norm", 3),
    "_literal": ("output", 2),
    "_main": ("output", None),
    "_memcheck": ("valgrind", None),
    "_method": ("method", None),
    "_model": ("oracle", None),
    "_newest_first": ("output", 2),
    "_norm": ("norm", None),
    "_norm_header": ("norm", 2),
    "_norm_notice": ("norm", 2),
    "_norm_provided": ("norm", 4),
    "_norm_provided_notice": ("norm", 4),
    "_oracle_fixtures": ("oracle", None),
    "_output": ("output", None),
    "_perf": ("perf", None),
    "_posix": ("norm", 2),
    "_probe_memcheck": ("valgrind", None),
    "_progname": ("output", None),
    "_prototype": ("prototype", None),
    "_prototype_names": ("prototype", 2),
    "_readings": ("diff", None),
    "_reference_cases": ("oracle", None),
    "_refcost": ("cycles", None),
    "_regular": ("output", 2),
    "_rush02_dictfuzz": ("diff", None),
    "_survive": ("output", None),
    "_sweep": ("output", None),
    "_symbols": ("symbols", None),
    "_twin": ("selftest", None),
    "_valgrind": ("valgrind", None),
}

# TESTS RAISED ABOVE THEIR SUFFIX'S LEVEL BY THEIR BUILD FILE -- a `level` at
# the call site, or a case's "level" -- as "<package>:<target>": the level.
# The reason is at the call site, and in one line in docs/reference.md
# ("Targets raised above their layer"), which //tools:conventions holds to
# these rows. c_levels()' audit fails a package with a raise that is not here,
# or an entry here its package does not raise (finding 072: C 06 ex03's raise
# was in one BUILD comment, against the docs' own level definitions). The
# macro fixtures' entries (tools/tests/...) prove the mechanism and are not
# documented.
_RAISED = {
    "c-piscine-reloaded/c-piscine-reloaded:ex22_double_arg_output": 2,
    "c-piscine-reloaded/c-piscine-reloaded:ex22_long_arg_output": 2,
    "c-piscine-reloaded/c-piscine-reloaded:ex23_int_fields_output": 4,
    "c-piscine-reloaded/c-piscine-reloaded:ex26_returns_one_output": 2,
    "c-piscine/c-piscine-c-12:ex11_element_output": 2,
    "c-piscine/c-piscine-c-06:ex03_high_bytes_argv_diff": 3,
    "c-piscine/c-piscine-c-07:ex04_base_to_space_output": 2,
    "c-piscine/c-piscine-c-08:ex01_expr_output": 2,
    "c-piscine/c-piscine-c-08:ex01_success_output": 3,
    "c-piscine/c-piscine-c-08:ex02_double_arg_output": 2,
    "c-piscine/c-piscine-c-08:ex02_long_arg_output": 2,
    "c-piscine/c-piscine-c-08:ex03_int_fields_output": 4,
    "c-piscine/c-piscine-c-10:ex01_dash_output": 2,
    "c-piscine/c-piscine-c-10:ex01_dirmsg_output": 2,
    "c-piscine/c-piscine-c-10:ex01_errmsg_output": 2,
    "c-piscine/c-piscine-c-10:ex01_errstatus_output": 2,
    "c-piscine/c-piscine-c-10:ex02_attached_output": 2,
    "c-piscine/c-piscine-c-10:ex02_dir_output": 2,
    "c-piscine/c-piscine-c-10:ex02_dirmsg_output": 2,
    "c-piscine/c-piscine-c-10:ex02_errmsg_output": 2,
    "c-piscine/c-piscine-c-10:ex02_errstatus_output": 2,
    "c-piscine/c-piscine-c-10:ex03_allfail_output": 2,
    "c-piscine/c-piscine-c-10:ex03_errmsg_output": 2,
    "c-piscine/c-piscine-c-10:ex03_errstatus_output": 2,
    "c-piscine/c-piscine-c-11:ex04_reverse_output": 2,
    "c-piscine/c-piscine-c-11:ex06_readings": 3,
    "c-piscine/c-piscine-c-11:ex05_intmin_div_output": 2,
    "c-piscine/c-piscine-c-11:ex05_intmin_mod_output": 2,
    "c-piscine/c-piscine-c-11:ex05_opsuffix_output": 2,
    "c-piscine/c-piscine-rush-02:ex00_dict_crlf_strict_output": 2,
    "c-piscine/c-piscine-rush-02:ex00_dict_missing_strict_output": 2,
    "c-piscine/c-piscine-rush-02:ex00_past_dictionary_strict_output": 2,
    "tools/tests/macro_fixtures/levels:ex00_raised_output": 2,
    "tools/tests/macro_fixtures/levels:ex00_reading_output": 2,
    "tools/tests/macro_fixtures/levels:ex01_staged_output": 2,
    "tools/tests/macro_fixtures/levels:ex03_open_output": 3,
    "tools/tests/macro_fixtures/levels:ex03_readings": 3,
}

# THE RUNNERS THAT SAY WHY A TEST IS RAISED: those that source
# tools/runner_lib.sh, whose EXIT trap prints, under a red, the reason
# docs/reference.md's "Targets raised above their layer" gives for a test
# _RAISED lists (rl__raised, from the RL_RAISED _test() hands it). A runner
# that does not source the library -- norminette_test.sh, files_test.sh,
# issued_test.sh -- prints nothing of it, so c_levels()' audit refuses a
# raised test whose srcs is not one of these: its red would read like any
# other, which is what handing the level over was for. //tools:conventions
# holds this list to the scripts in tools/ that source the library, both
# ways.
_LIB_RUNNERS = [
    "//tools:allocfail_check.sh",
    "//tools:argv_check.sh",
    "//tools:argv_table.sh",
    "//tools:asan_check.sh",
    "//tools:asan_run.sh",
    "//tools:bsq_check.sh",
    "//tools:compile_check.sh",
    "//tools:cycles_check.sh",
    "//tools:diff_output.sh",
    "//tools:file_check.sh",
    "//tools:forbidden_symbols.sh",
    "//tools:header_check.sh",
    "//tools:header_norm.sh",
    "//tools:ilp32_test.sh",
    "//tools:make_test.sh",
    "//tools:method_check.sh",
    "//tools:model_check.sh",
    "//tools:oracle_fixtures.sh",
    "//tools:perf_test.sh",
    "//tools:progname_test.sh",
    "//tools:prototype_check.sh",
    "//tools:ref_compare.sh",
    "//tools:reference_cases.sh",
    "//tools:run_check.sh",
    "//tools:rush01_check.sh",
    "//tools:rush02_check.sh",
    "//tools:rust_diff.sh",
    "//tools:shell_test.sh",
    "//tools:symbols_test.sh",
    "//tools:valgrind_test.sh",
]

# THE MANUAL TESTS, as "<package>:<target pattern>" ('*' matches any run of
# characters). A manual test is in no suite but its module's :manual and
# matches no /... pattern, so it runs only when named: it is listed here and
# in docs/reference.md ("Manual targets"), which //tools:conventions holds to
# these rows, and c_levels()' audit fails a package with a manual test no
# pattern here matches (finding 002: eight of them were in no document that
# said how to find them). A pattern that matches nothing is not an error: which
# Rush 00 variants are manual is the team's team.bzl, and a stub nobody owes
# can be deleted. The macro fixtures are manual by construction (_test) and
# are not listed, but for one row under tools/tests/, which the audit's
# fixture of a listed manual test reads (audit-manual-listed): a package of
# its own, which nothing raises. It read Rush 01's row, and the audit also
# fails a package's _RAISED entry it does not declare, so a raise added to
# Rush 01 turned that fixture red for a reason it does not test. Like
# _RAISED's fixture rows, it is not documented.
_MANUAL = [
    "c-piscine/c-piscine-rush-00:ex00_rush0*",
    "c-piscine/c-piscine-rush-01:ex00_bonus_9x9",
    "c-piscine/c-piscine-rush-02:ex00_rush02_dictfuzz",
    "c-piscine/c-piscine-rush-02:ex00_rush02_diff",
    "tools/tests/macro_fixtures/manual:ex00_bonus_diff",
]

# The tag of a module's :manual suite when the module has no manual test. A
# test_suite with no `tests` runs every non-manual test of its package, and
# `manual` is not a filter there (Bazel ignores it in a suite's tags), so an
# empty :manual would run the whole module. This tag, which no test carries
# (the audit refuses one that does), makes it select nothing instead.
_NO_MANUAL_TAG = "no_manual_test_in_this_module"

def _is_ex(s):
    """Whether `s` is an exercise's name: "ex" and two digits."""
    return len(s) == 4 and s.startswith("ex") and s[2:].isdigit()

def _glob_match(pattern, s):
    """Whether `s` matches `pattern`, where '*' matches any run of characters."""
    parts = pattern.split("*")
    if len(parts) == 1:
        return s == pattern
    if not s.startswith(parts[0]) or not s.endswith(parts[-1]):
        return False
    if len(parts[0]) + len(parts[-1]) > len(s):
        return False
    at = len(parts[0])
    end = len(s) - len(parts[-1])
    for p in parts[1:-1]:
        i = s.find(p, at, end)
        if i < 0:
            return False
        at = i + len(p)
    return True

def _suffix_of(name):
    """The longest _SUFFIX_LAYER key `name` ends with, after its exNN; None if none."""
    best = None
    for s in _SUFFIX_LAYER:
        if name[4:].endswith(s) and (best == None or len(s) > len(best)):
            best = s
    return best

def _audit_problems(pkg, tests, exercises, layouts = None, fixtures = None, oracle = None, makefiles = None, malloc = None, clues = None, diffio = None):
    """What c_levels()' audit fails a package for, as a list of messages.

    A value before it is a fail(), like every contract check: contract_problem()
    hands the fixtures a broken package to prove each message. Module-wide rules
    are checked HERE, once the whole package is declared, and not inside the
    helper a macro happens to call: the exercise tag was added by _test() alone,
    so the hand-written sh_tests had none and every :exNN suite missed them
    (findings 070, 074, 175); a manual test was in no suite and no document
    (002); a raise or a target suffix was in one BUILD comment (038, 072).

    Nothing a student writes can make one of these: the tests come from the
    BUILD file and the macros, a folder of theirs that is no exercise gets a
    files test (c_levels), and which Rush 00 variants are manual is matched by
    a pattern. So a failure here is the harness's, at `bazel query` time, on
    the author's machine.

    A structure file under tests/layout/ that no test reads is one too: a
    macro that does not read the folder (only c_function does, through
    _layouts()) drops it without a word, and the structure it holds is then
    checked by nothing while docs/reference.md says the prototype layer
    checks it (WP-47, TODO.md section 23).

    Args:
        pkg: the package, as "c-piscine/c-piscine-c-05".
        tests: every test rule of the package: {name: {"kind": ..., "tags":
            [...], "layouts": [...], "srcs": [...], "args": [...]}},
            "layouts" being the tests/layout/ files it passes a runner with
            --layout (_layout_args()); layouts, srcs and args may be absent.
        exercises: the exNN names c_levels() found: the contract's, and the
            folders under tests/, deliverable/ and generators/.
        layouts: every file under the package's tests/layout/.
        fixtures: every student_binary with a harness, as {binary: the
            prototype test its tag names, "none", or None where it carries
            no tag}. One naming a test the package does not declare, or one
            with no tag at all (built some way other than _student_bin), is
            a harness over a student's function with no check of its
            signature (finding 142).
        oracle: {"owners": {test running tools/oracle_fixtures.sh: what
            _oracle_owner read from it}, "reads": {test of a named case: the
            files its _CASE_READS_TAG lists}}. A case reading a file in an
            owner's directory that none of its --owns patterns matches reads
            a file nothing holds to the reference.
        makefiles: the exNN names whose contract `files` names a Makefile:
            each must have its exNN_build (c_make), or the Makefile it turns
            in is built by nothing that judges it.
        malloc: the exNN names whose subject() contract allows malloc, or
            prints no allowed-functions line at all (_memcheck_allowed).
        clues: every clues*.tsv under the package's tests/. One that no
            test hands a runner (`$(location FILE)` among its args) is a
            set of hints nobody is shown: Reloaded ex24's and C 09 ex01's,
            the hints of two exercises that are a Makefile alone, were
            printed by nothing, since c_make took no clue file (TODO.md, TO
            VERIFY V4).
        diffio: the student_binary rules that link //tools:diffio, whose
            malloc fills each block it hands out (tools/dirty_malloc.c). No
            memcheck layer may run one (_diffio_memcheck_problems).

    Returns:
        The messages, in a stable order; empty when the package is sound.
    """
    problems = []
    fixture = pkg == _FIXTURES or pkg.startswith(_FIXTURES + "/")
    raised = {}
    for k, v in _RAISED.items():
        p, n = k.split(":")
        if p == pkg:
            raised[n] = v
    manual = [k.split(":")[1] for k in _MANUAL if k.split(":")[0] == pkg]
    have = {}
    for n in sorted(tests):
        tags = list(tests[n]["tags"])
        ex = n[:4]
        if n in _MODULE_TESTS:
            # A test of the whole module (c_levels() emits it): no exercise,
            # its one layer, at that layer's level.
            want = [_MODULE_TESTS[n]] + ["lvl_" + x for x in _LEVEL_NAMES[_LAYER_LEVEL[_MODULE_TESTS[n]] - 1:]]
            if sorted([t for t in tags if t in _LAYER_LEVEL or t.startswith("lvl_") or _is_ex(t)]) != sorted(want):
                problems.append(("%s: a test of the whole module is tagged %s and its level, " +
                                 "and with no exercise (tools/defs.bzl's _MODULE_TESTS).") %
                                (n, _MODULE_TESTS[n]))
            continue
        if not _is_ex(ex) or n[4:5] != "_":
            problems.append(("%s: a project's test is named exNN_<what>, after its " +
                             "exercise, so that exercise's :exNN suite runs it and its " +
                             "name says which layer it is.") % n)
            continue
        have[ex] = True
        if ex not in tags:
            problems.append(("%s: it has no %s tag, so //%s:%s does not run it. Declare " +
                             "it with a macro or hand_test(), which derive the tag from " +
                             "the name.") % (n, ex, pkg, ex))
        if _NO_MANUAL_TAG in tags:
            problems.append("%s: the %s tag is the empty :manual suite's, and no test may carry it." % (n, _NO_MANUAL_TAG))
        layers = [t for t in tags if t in _LAYER_LEVEL]
        if len(layers) != 1:
            problems.append(("%s: it carries %d layer tags (%s); a test is exactly one " +
                             "layer (tools/defs.bzl's _LAYER_LEVEL). hand_test(name, " +
                             "layer, ...) gives it one.") % (n, len(layers), ", ".join(layers) or "none"))
            continue
        layer = layers[0]
        start = 0
        for i in range(len(_LEVEL_NAMES)):
            if "lvl_" + _LEVEL_NAMES[i] in tags:
                start = i + 1
                break
        ladder = ["lvl_" + x for x in _LEVEL_NAMES[start - 1:]] if start else []
        if not start or sorted([t for t in tags if t.startswith("lvl_")]) != sorted(ladder):
            problems.append(("%s: its lvl_* tags (%s) are not a level and every level " +
                             "above it, so the level suites disagree about it. They are " +
                             "derived from its layer by _test(); do not write them.") %
                            (n, ", ".join([t for t in tags if t.startswith("lvl_")]) or "none"))
            continue
        suffix = _suffix_of(n)
        if suffix == None:
            problems.append(("%s: its name ends in no suffix tools/defs.bzl's " +
                             "_SUFFIX_LAYER knows, so nothing says which layer it is. " +
                             "Name it for its layer (exNN_<what>_%s), or add the " +
                             "suffix there and to docs/reference.md's \"Target names\".") % (n, layer))
            continue
        s_layer, s_level = _SUFFIX_LAYER[suffix]
        if s_layer != layer:
            problems.append(("%s: its name ends in %s, which is the %s layer's " +
                             "(_SUFFIX_LAYER), and it is tagged %s. Rename it -- a case " +
                             "name can collide with a longer suffix -- or fix its tag.") %
                            (n, suffix, s_layer, layer))
            continue
        base = s_level or _LAYER_LEVEL[layer]
        if start < base:
            problems.append("%s: it sits at %s, below its %s layer's %s." %
                            (n, _LEVEL_NAMES[start - 1], suffix, _LEVEL_NAMES[base - 1]))
        elif start != base and raised.get(n) != start:
            problems.append(("%s: it sits at %s, above the %s its name gives it, and " +
                             "tools/defs.bzl's _RAISED does not say so. Add " +
                             "\"%s:%s\": %d there, and its reason to docs/reference.md's " +
                             "\"Targets raised above their layer\".") %
                            (n, _LEVEL_NAMES[start - 1], _LEVEL_NAMES[base - 1], pkg, n, start))
        elif start == base and n in raised:
            problems.append(("%s: _RAISED puts it at %s, and it sits at %s, where its " +
                             "name puts it. Remove the entry, or raise the test.") %
                            (n, _LEVEL_NAMES[raised[n] - 1], _LEVEL_NAMES[start - 1]))
        if n in raised and "--note" in (tests[n].get("args") or []):
            problems.append(("%s: _RAISED raises it, and it passes its runner --note, a " +
                             "second place to say why it sits above its layer. That is " +
                             "docs/reference.md's row, which its runner prints under a " +
                             "red (runner_lib.sh's rl__raised): drop --note.") % n)
        # tools/no_turnin.sh stands in for a test whose turn-in is missing
        # (_test()); its red says what is missing, and no level is its.
        srcs = tests[n].get("srcs")
        if n in raised and srcs != None and srcs != ["//tools:no_turnin.sh"] and (len(srcs) != 1 or srcs[0] not in _LIB_RUNNERS):
            problems.append(("%s: _RAISED raises it, and its runner (%s) does not source " +
                             "tools/runner_lib.sh, so its red would not say why it sits " +
                             "above its layer (runner_lib.sh's rl__raised says it). Run it " +
                             "with a runner that does, or have this one source the library " +
                             "and add it to tools/defs.bzl's _LIB_RUNNERS.") %
                            (n, ", ".join(srcs) or "no srcs"))
        if "manual" in tags and not fixture and not [p for p in manual if _glob_match(p, n)]:
            problems.append(("%s: it is manual, so no suite and no /... pattern runs it, " +
                             "and tools/defs.bzl's _MANUAL does not list it. Add a " +
                             "pattern there, and a row to docs/reference.md's \"Manual " +
                             "targets\" saying why it is not run by default.") % n)
    for n in sorted(raised):
        if n not in tests:
            problems.append(("_RAISED names %s:%s, which this package does not declare. " +
                             "Remove the entry.") % (pkg, n))
    for b in sorted(fixtures or {}):
        t = fixtures[b]
        if t == None:
            problems.append(("%s: it links a harness over a student's files and carries no " +
                             "%s tag, so nothing says which test checks the signatures the " +
                             "harness calls. Build it with _student_bin(), which requires " +
                             "`prototype` with a harness.") % (b, _HARNESS_PROTO_TAG))
        elif t != "none" and t not in tests:
            problems.append(("%s: a harness over a student's function names %s as the " +
                             "test of its signature, and this package declares no such " +
                             "test. Declare it (_prototype_test), or say why there is none " +
                             "(prototype = \"none: <the reason>\" at the macro's call).") % (b, t))
    owners = (oracle or {}).get("owners") or {}
    reads = (oracle or {}).get("reads") or {}
    for o in sorted(owners):
        d = owners[o]["dir"]
        pats = owners[o]["owns"]
        if not d or not pats:
            problems.append(("%s: it runs tools/oracle_fixtures.sh, and the audit cannot " +
                             "read its %s, so nothing can tell which of the cases' files " +
                             "it holds to //oracle. Pass --in-dir-of \"$(location " +
                             "tests/exNN/<a file>)\" and one --owns per pattern of files " +
                             "the reference writes, each as its own argument.") %
                            (o, "--in-dir-of $(location FILE)" if not d else "--owns"))
            continue
        for t in sorted(reads):
            for f in reads[t]:
                if not f.startswith(d + "/"):
                    continue
                if not [p for p in pats if _path_glob_match(p, f[len(d) + 1:])]:
                    problems.append(("%s: the case reads %s, in the directory %s holds to " +
                                     "//oracle's records, and none of its --owns patterns " +
                                     "(%s) matches it, so nothing compares it with the " +
                                     "reference and a hand-typed file there drifts unseen. " +
                                     "Have the reference write it (the project's *_fixtures " +
                                     "arm) and give %s an --owns pattern that matches it.") %
                                    (t, f, o, " ".join(pats), o))
    for ex in sorted(exercises):
        if ex not in have:
            problems.append(("%s: the exercise has no test, so its //%s:%s runs nothing. " +
                             "Every exercise the subject() contract lists gets a files " +
                             "layer unless its `files` is None; this one needs a macro.") %
                            (ex, pkg, ex))
    read = {}
    for n in tests:
        for f in tests[n].get("layouts") or []:
            read[f] = True
    for f in sorted(layouts or []):
        if f not in read:
            problems.append(("%s: no test of this package reads it (no exNN_prototype or " +
                             "exNN_layout_prototype passes it with --layout or " +
                             "--layout-tag), so the structure it holds is checked by " +
                             "nothing. c_function reads tests/layout/<header> and " +
                             "tests/layout/tag/<header> for an exercise whose contract's " +
                             "`files` names <header>; no other macro reads the folder yet. " +
                             "Name the header in that exercise's `files`, or have the macro " +
                             "that builds it pass _layouts() to _prototype_test(), with a " +
                             "toy exercise in tools/tests/macro_fixtures proving it.") % f)

    # THE TESTS THAT WAIT FOR AN OUTPUT ARE NAMED BY IT: every test with a
    # gate (_GATE_FLAGS: the program it gates on, the file that program must
    # print, or a survive case's --gate-label) resolves to the one output test
    # it waits for, and that test hands its runner their list (--waiting,
    # _waiting_args), or its red log says nothing of the tests that show
    # PASSED beside it while they wait (_WAITING).
    problems += _waiting_problems(tests)

    # A HINT FILE NO TEST PRINTS. Read from the args, as a runner is handed
    # it: in a test's data alone it is staged and never shown.
    handed = {}
    for n in tests:
        for a in tests[n].get("args") or []:
            if a.startswith("$(") and a.endswith(")") and " " in a:
                f = a[:-1].split(" ")[-1]
                handed[f.split(":")[-1]] = True
    for f in sorted(clues or []):
        if f not in handed:
            problems.append(("%s: no test of this package hands it to a runner (no " +
                             "\"$(location %s)\" among any test's args), so its hints " +
                             "are shown to nobody. Pass it where the exercise is judged " +
                             "-- clues = \"%s\" on its macro (c_function, c_program, " +
                             "c_make, ...) -- or delete it.") % (f, f, f.split("/")[-1]))
    problems += _keyed_clue_problems(tests, clues or [])

    # A MAKEFILE THE CONTRACT ASKS FOR IS BUILT BY c_make. "recipe and
    # wildcards are decided at every c_make" binds only the c_make calls that
    # exist: a Makefile project written with c_program(makefile = True) and
    # no c_make got no rules, recipe, wildcards or relink check at all, and
    # nothing said so (finding 097's class, through an omission).
    for ex in sorted(makefiles or []):
        if ex + "_build" not in tests:
            problems.append(("%s: the subject() contract has it turn in a Makefile, and " +
                             "no %s_build judges it: no c_make(num = \"%s\") here, so " +
                             "nothing checks its rules, its compile commands, its " +
                             "wildcards or a relink. Call c_make for it, deciding each " +
                             "check it runs.") % (ex, ex, ex[2:]))

    # EVERY CORPUS REPLAY HAS ITS MEMORY TWINS (finding 113).
    problems.extend(_corpus_memory_problems(tests, malloc or []))

    # ...and an argument corpus's ASan twin runs the guarded build (071).
    problems.extend(_argv_guard_replay_problems(tests, fixtures or {}))

    # ...and no memcheck layer runs a program whose malloc fills its blocks.
    problems.extend(_diffio_memcheck_problems(tests, diffio or []))

    # ...and a corpus under memcheck quotes the rule its exercise's arms do.
    problems.extend(_memory_rule_reach_problems(tests))

    # EVERY CORPUS GATE IS ONE OF THE EXERCISE'S OWN OUTPUT TESTS.
    problems.extend(_gate_problems(tests))

    # ...and so is every gate that replays the case its layer runs.
    problems.extend(_case_gate_problems(tests))
    return problems

def _argv_guard_replay_problems(tests, fixtures):
    """An argument corpus replayed under ASan off the guarded build, as messages.

    A program whose input is its arguments reads them where the kernel put
    them, which the sanitizer does not watch: a comparison that runs past an
    argument's terminator reads the next one's bytes, and the ASan build says
    nothing. c_argv_table builds the program a second way for that,
    :exNN_argvguard_bin_asan (tools/argv_guard_main.c), each argument in a
    heap block of exactly its size. C 06 ex03's corpus twins ran the
    unguarded build and passed such a comparison, their verdict silent about
    what they could not see (finding 071, the mutation run of 2026-10-03).
    So every argv_check.sh replay under --sanitized, in an exercise that has
    a guarded build, runs it (corpus_memory's `asan_bin`, which then passes
    --guarded-argv). A program's corpus runners -- Rush 01's sweep, Rush 02,
    C 10's files, BSQ's maps by name -- have no guarded build to run, and
    say instead what the sanitizer could not see of the arguments
    (tools/runner_lib.sh, rl_mem_argv_note).

    Args:
        tests: _audit_problems' tests.
        fixtures: _audit_problems' fixtures: every student_binary with a
            harness, the guarded builds among them.

    Returns:
        The messages, in a stable order.
    """
    problems = []
    for n in sorted(tests):
        t = tests[n]
        srcs = t.get("srcs") or []
        args = t.get("args") or []
        if not srcs or not srcs[0].endswith(":argv_check.sh") or "--sanitized" not in args:
            continue
        ex = n.split("_")[0]
        guard = ex + _ARGV_GUARD_SUFFIX
        if guard not in fixtures:
            continue
        bins = [args[i + 1] for i in range(len(args) - 1) if args[i] == "--bin"]
        if bins and bins[0] == "$(location :%s)" % guard and "--guarded-argv" in args:
            continue
        problems.append(("%s: it replays an argument corpus under ASan on %s, and %s " +
                         "has a guarded build, :%s, where each argument sits in a heap " +
                         "block of its own: on any other build a read past an argument's " +
                         "end is not seen (finding 071). Pass corpus_memory(asan_bin = " +
                         "\":%s\"), which tells argv_check.sh so (--guarded-argv).") %
                        (n, bins[0] if bins else "no --bin", ex, guard, guard))
    return problems

def _diffio_memcheck_problems(tests, diffio):
    """A memcheck layer handed a program linking //tools:diffio, as messages.

    Every program linking //tools:diffio has malloc wrapped so that each
    block starts holding 0xa5 (tools/dirty_malloc.c), so a field a function
    never writes does not read as zero to a value diff (finding 136). memcheck
    tracks which bytes were WRITTEN, and the fill writes them: a byte the
    student's code never set reads as defined, and an uninitialised read in
    that program goes unseen. No layer runs one under memcheck today -- the
    valgrind arms run the exercise's own _bin, or a _vgbin -- and nothing
    said that none may (the wave 6 review). So a test whose runner is
    valgrind_test.sh, or that replays a corpus under --valgrind, is refused
    when a program it is handed ($(location :X) among its args) links the
    library. The program memcheck runs is the one after --bin; a gate's
    program (--gate-bin) runs plain, before it, and may be any build.

    Args:
        tests: _audit_problems' tests.
        diffio: the student_binary rules linking //tools:diffio.

    Returns:
        The messages, in a stable order.
    """
    problems = []
    for n in sorted(tests):
        t = tests[n]
        srcs = t.get("srcs") or []
        args = t.get("args") or []
        if not (srcs and srcs[0] == "//tools:valgrind_test.sh") and "--valgrind" not in args:
            continue
        for i in range(len(args) - 1):
            a = args[i + 1]
            if args[i] != "--bin" or not (a.startswith("$(") and a.endswith(")") and " :" in a):
                continue
            b = a[:-1].split(" :")[-1]
            if b in diffio:
                problems.append(("%s: it runs :%s under memcheck, and :%s links " +
                                 "//tools:diffio, whose malloc fills every block it hands " +
                                 "out (tools/dirty_malloc.c): memcheck reads a filled byte " +
                                 "as written, so an uninitialised read in the student's " +
                                 "code is not seen. Hand it a build without the library: " +
                                 "the exercise's _bin, or a _vgbin of its own.") % (n, b, b))
    return problems

def _memory_rule_reach_problems(tests):
    """A corpus under memcheck that quotes no rule its exercise's arms quote, as messages.

    c_program's memory_rule is the subject's own sentence about memory (Rush
    02's "Any memory allocated on the heap ... must be freed correctly"),
    and each fixed case's _valgrind arm quotes it when it fails (--rule).
    The exercise's memcheck sample of a corpus quoted none, and a red there
    would state this harness's rule as "not a sentence of your subject's"
    under the one subject that has one (V82). corpus_memory() now hands it
    over, read from the file c_program writes (:exNN_memory_rule); one
    called before that c_program finds none. So every replay of a corpus
    under --valgrind is held to the --rule its exercise's valgrind arms pass.

    Args:
        tests: _audit_problems' tests.

    Returns:
        The messages, in a stable order.
    """
    def rule_of(args):
        for i in range(len(args) - 1):
            if args[i] == "--rule":
                return args[i + 1]
        return None

    quoted = {}
    for n in sorted(tests):
        t = tests[n]
        srcs = t.get("srcs") or []
        r = rule_of(t.get("args") or [])
        ex = n.split("_")[0]
        if srcs and srcs[0] == "//tools:valgrind_test.sh" and r != None and ex not in quoted:
            quoted[ex] = [n, r]
    problems = []
    for n in sorted(tests):
        t = tests[n]
        srcs = t.get("srcs") or []
        args = t.get("args") or []
        ex = n.split("_")[0]
        if not srcs or srcs[0] not in _CORPUS_RUNNERS or "--valgrind" not in args or ex not in quoted:
            continue
        arm, want = quoted[ex]
        got = rule_of(args)
        if got == want:
            continue
        problems.append(("%s: it replays a corpus under memcheck quoting %s, and %s quotes the " +
                         "subject's own sentence (--rule %s): a red here would state this " +
                         "harness's rule as not the subject's. corpus_memory() hands the " +
                         "sentence over when it comes after the c_program that declares " +
                         "it (memory_rule).") %
                        (n, "--rule " + got if got else "no rule", arm, want))
    return problems

def _keyed_clue_problems(tests, clues):
    """An exercise whose hints are keyed to its cases, with a hint file per case beside them.

    ONE KEYED clues.tsv PER EXERCISE (TODO.md section 23, ruling R7). A test
    that is a case of its own -- a c_program case, a corpus runner's target --
    hands its runner its name (--case), and a row of clues.tsv keyed to that
    name fires there and nowhere else (tools/runner_lib.sh, rl_clues). The
    other way, a clues_<x>.tsv per case, was the older one, and by wave 4
    both were in use: Rush 02 keyed its rows, while C 10, C 11 ex05, BSQ,
    Rush 01 and Reloaded ex27 split theirs over twenty files, so where a
    program's hints were depended on how the module was written, and a row
    could not name the several cases it is about. So in an exercise whose
    tests pass --case:
      - a clues_<x>.tsv under its tests/ folder is refused: fold its rows
        into clues.tsv, keyed to the cases that named it;
      - every test that hands its clues.tsv to a runner passes --case too:
        a runner given no case prints every row -- rl_clues with nothing
        failed -- so a sweep would show the rows keyed to other cases.
    An exercise none of whose tests is keyed (a function's table keys its
    rows by their labels) is not held to it.

    Args:
        tests: _audit_problems()' tests.
        clues: every clues*.tsv under the package's tests/.

    Returns:
        The messages, in a stable order; empty when nothing breaks the rule.
    """
    keyed = {}
    for n in sorted(tests):
        args = tests[n].get("args") or []
        opts = args[:args.index("--")] if "--" in args else args
        if _is_ex(n[:4]) and "--case" in opts:
            keyed.setdefault(n[:4], []).append(n)
    problems = []
    for f in sorted(clues):
        parts = f.split("/")
        if len(parts) == 3 and parts[1] in keyed and parts[2] != "clues.tsv":
            named = keyed[parts[1]]
            shown = ([n for n in named if n.endswith("_output")] + named)[0]
            problems.append(("%s: %s keys its hints to its cases (--case, as %s does), " +
                             "so they live in one tests/%s/clues.tsv: fold these rows " +
                             "into it, each keyed to the cases that named this file " +
                             "(<hint><TAB><case>...), and delete it.") %
                            (f, parts[1], shown, parts[1]))
    for n in sorted(tests):
        ex = n[:4]
        if ex not in keyed or n in keyed[ex]:
            continue
        args = tests[n].get("args") or []
        hands = [a for a in args if a.endswith("tests/%s/clues.tsv)" % ex)]
        if hands:
            problems.append(("%s: it hands %s's keyed clues.tsv to its runner without " +
                             "--case, so every row of it is shown, the rows keyed to " +
                             "other cases among them. Pass --case and the name its rows " +
                             "are keyed to (its target's name after %s_).") % (n, ex, ex))
    return problems

def _opt_values(args, opt):
    """Every value `opt` takes in `args`, in order: the word after each `opt` before a "--"."""
    out = []
    for i in range(len(args) - 1):
        if args[i] == "--":
            break
        if args[i] == opt:
            out.append(args[i + 1])
    return out

def _gate_run(args):
    """What a corpus runner's gate runs, from its arguments; None where it has no gate.

    {"bin", "expected", "words": the run's arguments as written, "argv_file":
    a file holding them, or None}. A runner takes the run's words as
    --gate-arg, each one word (bsq_check.sh, rush01_check.sh); or a one-line
    file as --gate-arg-file (rush01_check.sh); or, for a dictionary program,
    its --dict and then --gate-number (rush02_check.sh).
    """
    if not _opt_values(args, "--gate-differ"):
        return None
    words = _opt_values(args, "--gate-arg")
    number = _opt_values(args, "--gate-number")
    if number:
        words = _opt_values(args, "--dict")[:1] + number[:1]
    files = _opt_values(args, "--gate-arg-file")
    return {
        "bin": (_opt_values(args, "--gate-bin") or [None])[0],
        "expected": (_opt_values(args, "--gate-expected") or [None])[0],
        "words": words,
        "argv_file": files[0] if files else None,
    }

def _output_run(args):
    """What a diff_output.sh test runs, from its arguments: _gate_run()'s fields.

    None for a run a gate does not make, or a verdict it does not reach: one
    fed standard input, run under another name or from a folder of its own
    (--stdin, --run-as, --cwd-file), and one that judges something else than
    standard output against one file (--stream, --expected-alt, --survive,
    --exit-only).
    """
    opts = args[:args.index("--")] if "--" in args else args
    for opt in ("--stdin", "--run-as", "--cwd-file", "--stream", "--expected-alt", "--survive", "--exit-only"):
        if opt in opts:
            return None
    files = _opt_values(args, "--argv-file")
    return {
        "bin": (_opt_values(args, "--bin") or [None])[0],
        "expected": (_opt_values(args, "--expected") or [None])[0],
        "words": args[args.index("--") + 1:] if "--" in args else [],
        "argv_file": files[0] if files else None,
    }

def _gate_problems(tests):
    """A corpus replay whose gate runs its program some other way than any output test does.

    A corpus runner SKIPs while its gate -- the program run on the subject's
    example, through tools/diff_output.sh -- is red, so the gate has to run
    the program exactly as that example's own output test does. BSQ's ran it
    with no argument at all, while the example's test hands it the map: on a
    correct program the gate read an empty standard input, printed "map
    error", and every BSQ corpus target SKIPped on every correct tree, green,
    wherever NO_SKIP=1 was not set. So each gate is matched here with a
    diff_output.sh test of the package: the same program, the same expected
    file, the same arguments (or argument file), and no standard input.
    """
    problems = []
    cases = []
    for n in sorted(tests):
        srcs = tests[n].get("srcs") or []
        if srcs and srcs[0] == "//tools:diff_output.sh":
            run = _output_run(tests[n].get("args") or [])
            if run != None:
                cases.append(run)
    unmatched = {}
    for n in sorted(tests):
        srcs = tests[n].get("srcs") or []
        if not srcs or srcs[0] not in _CORPUS_RUNNERS:
            continue
        gate = _gate_run(tests[n].get("args") or [])
        if gate == None or gate in cases:
            continue
        how = " ".join(gate["words"]) or "no argument"
        if gate["argv_file"]:
            how = "the arguments in " + gate["argv_file"]
        what = "%s with %s against %s" % (gate["bin"], how, gate["expected"])
        unmatched.setdefault(what, []).append(n)
    for what in sorted(unmatched):
        problems.append(("%s: the gate runs %s, and no output test of this package runs " +
                         "the program that way, so the gate can be red on a program whose " +
                         "example passes, and these layers would SKIP on every correct " +
                         "program. Pass the example case's own arguments: --gate-arg once " +
                         "per word (tools/runner_lib.sh, rl_gate).") %
                        (", ".join(unmatched[what]), what))
    return problems

# THE RUNNERS WHOSE GATE REPLAYS THE CASE THEY RUN: the gate is handed the
# words after "--" and, by the runner itself, its --argv-file, --run-as and
# --cwd-file; --gate-stdin, --gate-expected and the rest of the --gate-*
# options say how it is fed and compared. c_levels()' audit holds each such
# gate to an output test of the package (_case_gate_problems).
_CASE_GATE_RUNNERS = [
    "//tools:allocfail_check.sh",
    "//tools:valgrind_test.sh",
]

def _compared_run(args, gate):
    """A compared run from a test's arguments: what diff_output.sh runs, or a case gate's.

    `gate` False reads a diff_output.sh test's own options; True, the
    --gate-* options of one of _CASE_GATE_RUNNERS, with the run flags the
    runner forwards to its gate. None for a test that compares no output
    (--survive, --exit-only), or a runner given no gate.
    """
    opts = args[:args.index("--")] if "--" in args else args
    p = "--gate-" if gate else "--"
    if gate and "--gate-differ" not in opts:
        return None
    if not gate and ("--survive" in opts or "--exit-only" in opts):
        return None

    def one(o):
        v = _opt_values(opts, o)
        return v[0] if v else None

    return {
        "argv_file": one("--argv-file"),
        "bin": one(p + "bin"),
        "cwd_files": sorted(_opt_values(opts, "--cwd-file")),
        "expected": one(p + "expected"),
        "expected_alt": _opt_values(opts, p + "expected-alt"),
        "labeled": (p + "labeled") in opts,
        "run_as": one("--run-as"),
        "sanitize": (p + "sanitize") in opts,
        "stdin": one(p + "stdin"),
        "stream": one(p + "stream"),
        "words": args[args.index("--") + 1:] if "--" in args else [],
    }

def _case_gate_problems(tests):
    """A gate that replays a case some other way than any output test of the package does.

    The program arms of c_program -- valgrind, allocfail -- SKIP while their
    gate, the case run through tools/diff_output.sh, is red; so the gate has
    to be the case's own output test. Rush 02's allocfail sweep forwarded
    stdin alone: its case runs the program beside numbers.dict (--run-as,
    --cwd-file), the gate ran it from a folder with no dictionary, and on
    every correct program the gate was red and the sweep SKIPped, green. Each
    gate of _CASE_GATE_RUNNERS is matched here with a diff_output.sh test: the
    same program, expected file(s), stream, comparison, standard input,
    arguments, argument file and run folder.
    """
    outputs = []
    for n in sorted(tests):
        srcs = tests[n].get("srcs") or []
        if srcs and srcs[0] == "//tools:diff_output.sh":
            run = _compared_run(tests[n].get("args") or [], False)
            if run != None:
                outputs.append(run)
    unmatched = {}
    for n in sorted(tests):
        srcs = tests[n].get("srcs") or []
        if not srcs or srcs[0] not in _CASE_GATE_RUNNERS:
            continue
        gate = _compared_run(tests[n].get("args") or [], True)
        if gate == None or gate in outputs:
            continue
        how = ["on \"%s\"" % " ".join(gate["words"]) if gate["words"] else "with no argument"]
        if gate["argv_file"]:
            how.append("then the arguments in " + gate["argv_file"])
        if gate["stdin"]:
            how.append("standard input from " + gate["stdin"])
        if gate["run_as"]:
            how.append("as ./%s from a folder holding %s" % (gate["run_as"], ", ".join(gate["cwd_files"]) or "only it"))
        else:
            how.append("from the test's own folder")
        what = "%s %s, against %s" % (gate["bin"], ", ".join(how), gate["expected"])
        unmatched.setdefault(what, []).append(n)
    return [
        ("%s: the gate runs %s, and no output test of this package runs the program " +
         "that way, so the gate can be red on a program whose case passes, and the " +
         "layer would SKIP on every correct program. Hand the runner the case's run " +
         "flags (_case_run), which it forwards to its gate, and --gate-stdin for its " +
         "standard input.") % (", ".join(unmatched[what]), what)
        for what in sorted(unmatched)
    ]

def _corpus_memory_problems(tests, malloc):
    """A corpus replayed on the plain build only, as messages (finding 113).

    Every generated corpus -- Rush 01's sweep, Rush 02's dictionaries, BSQ's
    maps, C 06's arguments, C 10's files -- ran on the plain build, while the
    memory layers ran each fixed case alone; so a path only generated input
    reaches (a search that ends with nothing, a long number, a map past nine
    rows, a file past one buffer) was never memory-checked. The next project's
    corpus would have been the same, so the rule is the package's: EACH plain
    replay through one of _CORPUS_RUNNERS needs a replay of the same corpus --
    its arguments less _CORPUS_RUN_OPTS, so the generator, its size and the
    transport (argv, stdin, several maps per run) all count -- on the ASan
    build (--sanitized, on :exNN_bin_asan) and, where the subject allows
    malloc (_memcheck_allowed), a sample of it under memcheck (--valgrind).
    corpus_memory() emits both. Keyed by exercise and runner alone, one twin
    stood in for every corpus that runner replayed, and the audit passed BSQ
    with its stdin and multi-map corpora checked nowhere.

    A twin that replays LESS on purpose -- Rush 01's leaves the bonus sizes,
    slow under a checker, to the plain sweep -- names the replays it stands in
    for in corpus_memory()'s `covers`, with the reason; one that leaves out
    memcheck says why in `no_valgrind`. Both arrive here as tags of the twin
    (_COVERS_TAG, _NO_VALGRIND_TAG), which hand_test() refuses to set.
    """
    problems = []
    plain = {}
    twins = {}
    waived = {}
    covers = {}
    for n in sorted(tests):
        srcs = tests[n].get("srcs") or []
        if not srcs or srcs[0] not in _CORPUS_RUNNERS or not _is_ex(n[:4]):
            continue
        args = tests[n].get("args") or []
        tags = tests[n].get("tags") or []
        key = " ".join([n[:4], srcs[0]] + _corpus_of(args))
        mode = "sanitized" if "--sanitized" in args else ("valgrind" if "--valgrind" in args else None)
        if mode == None:
            plain[n] = key
            continue
        if mode == "sanitized" and not [a for a in args if a.endswith("_bin_asan)")]:
            problems.append(("%s: it replays its corpus with --sanitized on a program " +
                             "that is not an ASan build (:%s_bin_asan), so no " +
                             "sanitizer is there to report. corpus_memory() wires it.") %
                            (n, n[:4]))
        twins[key + " " + mode] = n
        if _NO_VALGRIND_TAG in tags:
            waived[key] = n
        for t in tags:
            if t.startswith(_COVERS_TAG):
                c = covers.setdefault(t[len(_COVERS_TAG):], {})
                c[mode] = n
                c["key"] = key
                if _NO_VALGRIND_TAG in tags:
                    c["no_valgrind"] = n
    for c in sorted(covers):
        by = covers[c].get("sanitized") or covers[c].get("valgrind")
        if c not in plain:
            problems.append(("%s: its corpus_memory() covers %s, which is no plain replay " +
                             "of a corpus in this package. Name the replay it stands in " +
                             "for, or drop the entry.") % (by, c))
        elif plain[c].split(" ")[0:2] != covers[c]["key"].split(" ")[0:2]:
            problems.append(("%s: its corpus_memory() covers %s, a replay of another " +
                             "exercise or through another runner, whose memory it cannot " +
                             "speak for.") % (by, c))
        elif plain[c] + " sanitized" in twins:
            problems.append(("%s: its corpus_memory() covers %s, whose own corpus has a " +
                             "twin already (%s). Drop the entry: a reason nobody needs is " +
                             "one nobody rereads.") % (by, c, twins[plain[c] + " sanitized"]))
    for n in sorted(plain):
        key = plain[n]
        ex, runner = key.split(" ")[0:2]
        corpus = " ".join(key.split(" ")[2:]) or "its runner's default corpus"
        c = covers.get(n, {})
        if key + " sanitized" not in twins and "sanitized" not in c:
            problems.append(("%s: it replays a generated corpus (%s) through %s on the " +
                             "plain build, and no test replays that corpus under ASan/UBSan, " +
                             "so a path only it reaches is never memory-checked. Add " +
                             "corpus_memory() with the same corpus arguments beside it " +
                             "(tools/defs.bzl); where a twin replays less on purpose, name " +
                             "this replay in that corpus_memory()'s `covers`, with why.") %
                            (n, corpus, runner))
        if (ex in malloc and key + " valgrind" not in twins and key not in waived and
            "valgrind" not in c and "no_valgrind" not in c):
            problems.append(("%s: its subject allows malloc, and no test replays its " +
                             "corpus (%s) under memcheck, so a leak only that corpus reaches " +
                             "is never seen. corpus_memory() emits the arm from the subject() " +
                             "contract, or says why not in `no_valgrind`.") % (n, corpus))
    return problems

def _layout_args(args):
    """The tests/layout/ files a test's `args` pass with --layout or --layout-tag, package-relative."""
    out = []
    for i in range(len(args) - 1):
        a = args[i + 1]
        if args[i] in ("--layout", "--layout-tag") and a.startswith("$(location ") and a.endswith(")"):
            out.append(a[len("$(location "):-1])
    return out

def _audit_inputs(rules):
    """_audit_problems' tests, fixtures, oracle and diffio, read from a package's rules.

    `rules` is native.existing_rules(): {name: the rule's attributes}. Its
    own function so that contract_problem("audit_rules") can feed it rules
    shaped the way existing_rules() returns them, and so the reading -- a
    tag, an argument -- is proven along with the rule it feeds.
    """
    tests = {}
    fixtures = {}
    owners = {}
    reads = {}
    diffio = []
    for n, r in rules.items():
        tags = list(r.get("tags") or [])
        if r["kind"].endswith("_test"):
            tests[n] = {
                "kind": r["kind"],
                "tags": tags,
                "layouts": _layout_args(list(r.get("args") or [])),
                # A label as the rule holds it, which may name the main
                # repository ("@@//tools:x.sh"): compared from its "//".
                "srcs": ["//" + str(x).split("//", 1)[-1] for x in (r.get("srcs") or [])],
                "args": list(r.get("args") or []),
            }
            owner = _oracle_owner(r)
            if owner != None:
                owners[n] = owner
            for t in tags:
                if t.startswith(_CASE_READS_TAG):
                    reads[n] = [f for f in t[len(_CASE_READS_TAG):].split(",") if f]

        # Every program linking a harness, read from the rule and not from the
        # tag alone: one that lost its tag, or was declared without
        # _student_bin, is then a binary with None rather than none at all.
        if r["kind"] == "student_binary" and r.get("harness"):
            fixtures[n] = None
            for t in tags:
                if t.startswith(_HARNESS_PROTO_TAG):
                    fixtures[n] = t[len(_HARNESS_PROTO_TAG):]

        # Every program linking //tools:diffio, by its deps as the rule holds
        # them (a label may name the main repository: compared from "//").
        if r["kind"] == "student_binary":
            for d in r.get("deps") or []:
                if "//" + str(d).split("//", 1)[-1] == "//tools:diffio":
                    diffio.append(n)
    return tests, fixtures, {"owners": owners, "reads": reads}, diffio

def _levels_audit_impl(name, visibility, exercises, layouts, makefiles, malloc, clues):
    """c_levels()' finalizer: the audit, then the module's :manual suite."""
    tests, fixtures, oracle, diffio = _audit_inputs(native.existing_rules())
    problems = _audit_problems(
        native.package_name(),
        tests,
        exercises,
        layouts = layouts,
        fixtures = fixtures,
        oracle = oracle,
        makefiles = makefiles,
        malloc = malloc,
        clues = clues,
        diffio = diffio,
    )
    if problems:
        fail(("c_levels: //%s breaks %d module-wide rule(s) (tools/defs.bzl, " +
              "_audit_problems):\n  - %s") % (native.package_name(), len(problems), "\n  - ".join(problems)))

    # EVERY MANUAL TEST, in one suite that is manual itself: a non-manual
    # suite listing them would drag them back into //... (rush_variant's
    # per-variant suites say the same).
    manual = sorted([n for n in tests if "manual" in tests[n]["tags"]])
    native.test_suite(
        name = name,
        tests = [":" + n for n in manual],
        tags = ["manual"] + ([] if manual else [_NO_MANUAL_TAG]),
        visibility = visibility,
    )

# A FINALIZER (Bazel 8+): it runs once the whole BUILD file has been
# evaluated, wherever c_levels() is called in it, and native.existing_rules()
# there sees every target of the package but other finalizers'. Proven with a
# probe package on the pinned Bazel 9.2.0 before relying on it: called from a
# legacy macro in the middle of a BUILD file, it saw the tests declared after
# the call, a fail() in it stops the package from loading with its message,
# and a test_suite it declares lists manual tests by label. So c_levels() no
# longer has to be a module's last statement for a module-wide rule to see
# the whole module.
_levels_audit = macro(
    implementation = _levels_audit_impl,
    finalizer = True,
    attrs = {
        "exercises": attr.string_list(configurable = False),
        # Globbed by c_levels(): a symbolic macro cannot glob.
        "layouts": attr.string_list(configurable = False),
        "makefiles": attr.string_list(configurable = False),
        # The exNN whose corpora get a memcheck twin (_memcheck_allowed),
        # read from the contract by c_levels() as `makefiles` is.
        "malloc": attr.string_list(configurable = False),
        # Every clues*.tsv under tests/, globbed by c_levels().
        "clues": attr.string_list(configurable = False),
    },
)

# WHO WAITS FOR AN OUTPUT TEST, written down for it to say.
#
# A layer gated on an exercise's output (--gate-bin: diff, diff_asan,
# valgrind, memcheck, cycles, perf, allocfail, ilp32, a case's memory arms, a
# corpus; --gate-label: a survive case) says SKIP and exits 0 while that
# output is red, and Bazel 9.2 has no way for a test that ran to report itself
# skipped: the summary of a first red showed them PASSED beside the one red
# test, and they were read as "tests that pass because it compiles" (TODO.md's
# V2). Which output test each one waits for is known here, once the package is
# declared (_waits_for): the one its call names (_test's `waits`, a
# _WAITS_TAG; a survive case's --gate-label), or else the one output test
# that runs the same program against the same expected file -- its gate's
# --gate-bin and --gate-expected (ilp32's --expected) are that test's --bin
# and --expected. Per OUTPUT TEST, not per (program, file): BSQ's error cases
# share one expected file, and each case's memory arm waits for its own case
# alone. _waiting_name() names the list of one output test, one test a line
# with its level; the output test hands it to its runner (--waiting,
# _waiting_args), which names them under a red verdict (rl_waiting,
# tools/runner_lib.sh).
#
# subject() declares the finalizer that writes the lists (_waiting), not
# c_levels(): every package an output test can be declared in has a contract
# (the macros fail without one), and a package without c_levels() -- the
# macro fixtures -- would otherwise hand its output tests a list nothing
# writes, and none of them would build. The audit (_audit_problems) fails a
# module where a gated test resolves to no output test that hands a list, or
# to more than one, or to an output test of another exercise: its SKIP would
# be listed under that exercise's red, never its own (V104).
_WAITING = "waiting"
_WAITS_TAG = "waits="

# The arguments that say a test waits for an output: the program it gates on,
# the file that program must print, or the output test by name.
_GATE_FLAGS = ["--gate-bin", "--gate-expected", "--gate-label"]

def _loc_of(arg):
    """The label or path inside "$(location X)", from its last ':', or None."""
    if not (arg.startswith("$(location ") and arg.endswith(")")):
        return None
    return arg[len("$(location "):-1].split(":")[-1]

def _arg_after(args, flag):
    """The word after the first `flag` in `args`, or None."""
    for i in range(len(args) - 1):
        if args[i] == flag:
            return args[i + 1]
    return None

def _waiting_name(test):
    """The list of the tests that wait for the output test `test`."""
    return "%s_%s" % (_WAITING, test)

def _waiting_args(test):
    """(args, data) for the output test `test`: the list of who waits for it."""
    label = ":" + _waiting_name(test)
    return ["--waiting", "$(location %s)" % label], [label]

def _waiting_outputs(tests):
    """{output test: (its program, its expected file)}, for each that hands a list (--waiting)."""
    out = {}
    for n in sorted(tests):
        args = tests[n].get("args") or []
        if "--waiting" in args:
            out[n] = (_loc_of(_arg_after(args, "--bin") or ""), _loc_of(_arg_after(args, "--expected") or ""))
    return out

def _runs(output, gb, ge):
    """Whether an output test's (program, expected file) is a gate's: none differs, one is the same.

    An output test that builds its program in its runner (c_libft's,
    header_check.sh) has no --bin, and is told by its expected file alone.
    """
    same = 0
    for mine, theirs in [(output[0], gb), (output[1], ge)]:
        if mine and theirs:
            if mine != theirs:
                return False
            same += 1
    return same > 0

def _other_exercise(name, o):
    """Why test `name` cannot wait for output test `o`, an output test of another exercise, or ""."""
    if not _is_ex(name[:4]) or o[:4] == name[:4]:
        return ""
    return (("%s: it waits for %s, the output test of another exercise, so its SKIP " +
             "would be listed under that exercise's red and never under its own. A " +
             "test waits for an output test of its own exercise (V104).") % (name, o))

def _waits_for(name, t, outputs):
    """(the output test `t` waits for, None), (None, why it cannot be told), or (None, None): no gate.

    The output test is one of the test's own exercise: a wait on another's
    is refused, on either path (V104).
    """
    args = t.get("args") or []
    said = _uniq([x[len(_WAITS_TAG):] for x in t["tags"] if x.startswith(_WAITS_TAG)] +
                 [x for x in [_arg_after(args, "--gate-label")] if x])
    if not said and not [f for f in _GATE_FLAGS if f in args]:
        return None, None
    gb = _loc_of(_arg_after(args, "--gate-bin") or "")
    ge = _loc_of(_arg_after(args, "--gate-expected") or (_arg_after(args, "--expected") if gb else None) or "")
    gate = "%s printing %s" % (gb or "a program it names by no $(location)", ge or "a file it names by no $(location)")
    if len(said) > 1:
        return None, ("%s: it says it waits for %s; a test waits for one output test." %
                      (name, " and ".join(said)))
    if said:
        o = said[0]
        if o not in outputs:
            return None, (("%s: it waits for %s, which is no output test of this package " +
                           "handing its list on (--waiting, _waiting_args), so no red log " +
                           "says it shows PASSED while it waits.") % (name, o))
        if (gb or ge) and not _runs(outputs[o], gb, ge):
            return None, (("%s: it says it waits for %s, and its gate is %s, which %s " +
                           "does not run: it waits for another output test.") % (name, o, gate, o))
        return (None, _other_exercise(name, o)) if _other_exercise(name, o) else (o, None)
    found = [o for o in sorted(outputs) if _runs(outputs[o], gb, ge)]
    if len(found) == 1:
        return (None, _other_exercise(name, found[0])) if _other_exercise(name, found[0]) else (found[0], None)
    if not found:
        return None, (("%s: it waits for an output test (its gate is %s), and no output " +
                       "test of this package that runs that hands its list on (--waiting, " +
                       "_waiting_args), so no red log says it shows PASSED while it waits. " +
                       "Hand that output test's runner _waiting_args(<its name>).") % (name, gate))
    return None, (("%s: its gate is %s, which %s each run. Say which one it waits for: " +
                   "waits = \"<that output test>\" on its _test() or hand_test().") %
                  (name, gate, ", ".join(found)))

def _level_of(tags):
    """A test's level, the lowest of its lvl_* tags, or None."""
    for x in _LEVEL_NAMES:
        if "lvl_" + x in tags:
            return x
    return None

def _waiting_lists(tests):
    """{output test handing a list: its lines, "<test> (<level>)", sorted}.

    A manual test is left out of a list that is not manual itself: //... and
    every level suite leave it out, so it never shows PASSED there. In the
    macro fixtures every test is manual, and they are listed as anywhere else.
    """
    outputs = _waiting_outputs(tests)
    lists = {o: [] for o in outputs}
    for n in sorted(tests):
        o, _ = _waits_for(n, tests[n], outputs)
        if o == None or ("manual" in tests[n]["tags"] and "manual" not in tests[o]["tags"]):
            continue
        lvl = _level_of(tests[n]["tags"])
        lists[o].append("%s (%s)" % (n, lvl) if lvl else n)
    return lists

# What hands a program its input: in an output test's run, and in a gate's.
# A runner that runs the case itself (--argv-file, valgrind_test.sh's) hands
# its gate the same argument file.
_RUN_INPUT_FLAGS = ["--stdin", "--argv-file"]
_GATE_INPUT_FLAGS = ["--gate-arg", "--gate-arg-file", "--gate-stdin", "--gate-number", "--argv-file"]

def _after_dashes(args):
    """The words after the first lone `--` in `args`: the program's own argv."""
    return args[args.index("--") + 1:] if "--" in args else []

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
        w = _loc_of(_arg_after(tests[o].get("args") or [], "--waiting") or "")
        if w != _waiting_name(o):
            problems.append(("%s: it hands its runner the list %s, and its own is %s: the " +
                             "list of who waits for it is named after it (_waiting_args(%r)).") %
                            (o, w, _waiting_name(o), o))
    for n in sorted(tests):
        o, why = _waits_for(n, tests[n], outputs)
        if why:
            problems.append(why)
            continue
        if o == None:
            continue
        oargs = tests[o].get("args") or []
        gargs = tests[n].get("args") or []
        fed = [f for f in _RUN_INPUT_FLAGS if f in oargs] or _after_dashes(oargs)
        feeds = [f for f in _GATE_INPUT_FLAGS if f in gargs] or _after_dashes(gargs)
        if fed and not feeds:
            problems.append(("%s: it waits for %s, whose run hands the program input (%s), " +
                             "and its gate hands it none (no --gate-arg, --gate-stdin, ...): " +
                             "a program that passes %s fails that gate, and this test says " +
                             "SKIP forever. Give the gate %s's input.") %
                            (n, o, " ".join(fed), o, o))
    return problems

def _waiting_impl(name, visibility):
    """subject()'s finalizer: the list each output test names, written."""
    tests, _, _, _ = _audit_inputs(native.existing_rules())
    lists = _waiting_lists(tests)
    for o in sorted(lists):
        names_file(
            name = _waiting_name(o),
            names = lists[o],
            visibility = visibility,
        )

_waiting = macro(
    implementation = _waiting_impl,
    finalizer = True,
    attrs = {},
)

def _level_tags(tags, level = None):
    """The lvl_* tags a test carries, given its layer tags.

    level raises this one test above where its layer would put it; see _test.

    CUMULATIVE on purpose: a norm test is tagged lvl_basic AND lvl_strict AND
    lvl_robust AND lvl_complete, so `test_suite(tags = ["lvl_strict"])` picks up
    everything at or below strict. test_suite's `tags` is an AND across the list
    and has no OR, so a suite has to select on ONE tag — which only works if the
    membership is baked in here rather than expressed at the suite.
    """
    lvl = 0
    for t in tags:
        lvl = max(lvl, _LAYER_LEVEL.get(t, 0))
    if level != None:
        if lvl == 0:
            fail("_level_tags: level = %d on a test with no layer tag: %r" % (level, tags))
        if level <= lvl:
            fail("_level_tags: level = %d does not raise a level-%d layer (%r). " % (level, lvl, tags) +
                 "Only UP is allowed: `basic` has to keep meaning everything that is a KO wherever the project is graded.")
        lvl = level
    if lvl == 0:
        return []
    return ["lvl_" + _LEVEL_NAMES[i] for i in range(lvl - 1, len(_LEVEL_NAMES))]

def lvl_tags(layer, level = None):
    """The tags a test rule that is NOT an sh_test needs: its layer and its level ladder.

    Two callers, each a rule of its own outside every project:
    //tools/cc_toolchain's provenance test and //tools/tests:fortytwo_test,
    a py_test. Every sh_test -- in a module or out of one -- is
    declared with hand_test(), which goes through _test() like every test a
    macro emits and so derives the exercise tag as well; the exercise tag is
    what this could not give, and the hand-written sh_tests that used it were
    in no :exNN suite (finding 070). //tools:conventions refuses lvl_tags()
    in a project's BUILD file and sh_test() in any BUILD file.

    Args:
        layer: the layer tag, as a string -- "selftest", "oracle". fail()s on
            anything _LAYER_LEVEL does not know, because _level_tags returns
            NO tag for an unrecognised one, which drops the test out of every
            level suite in silence.
        level: raise THIS test above its layer, as _test's `level` does; only
            up, for the same reason.

    Returns:
        The layer tag followed by its cumulative lvl_* tags.
    """
    _known_layer("lvl_tags", layer)
    return [layer] + _level_tags([layer], level)

def _known_layer(what, layer):
    """fail()s unless `layer` is a layer tag of _LAYER_LEVEL."""
    if layer not in _LAYER_LEVEL:
        fail(("%s: %r is not a layer. Known layers: %s. An unrecognised " +
              "tag gets no lvl_* tag at all, which drops the test out of every " +
              "level suite silently -- so this refuses rather than emits it.") %
             (what, layer, ", ".join(sorted(_LAYER_LEVEL))))

# The package of toy exercises that proves the macros on every broken state a
# student's tree can be in (see its BUILD file). Its tests are red by design, so
# they are tagged manual here and reached through its own check instead.
_FIXTURES = "tools/tests/macro_fixtures"

def _in_fixtures():
    """True in tools/tests/macro_fixtures or a package under it."""
    p = native.package_name()
    return p == _FIXTURES or p.startswith(_FIXTURES + "/")

# A REFUSAL A FIXTURE CAN WATCH. A macro refuses a BUILD file while loading,
# with fail(), and a package that fails to load cannot be a test: so the
# fixtures fed each guard its broken input through the guard's own helper
# (contract_problem, starlark_selftest), and a macro that stopped calling the
# helper stayed green everywhere -- deleting c_program's or _test()'s fail()
# kept every selftest and fixture green (review of WP-50). A macro whose
# refusal a fixture must see refuses through this instead, and in the macro
# fixtures alone takes `refusals`, a list: the refusal is appended there, the
# macro returns having emitted nothing, and :contract_problems compares what
# the real macro said (tools/tests/macro_fixtures/BUILD.bazel, "refused-").
def _refuse(problem, refusals, who):
    """fail(problem); or, given `refusals` in the macro fixtures, append it and return True.

    False where there is no problem. `who` names the call, for the one
    refusal of its own: `refusals` passed outside the fixtures, where it
    would turn a guard off.
    """
    if refusals != None and (type(refusals) != "list" or not _in_fixtures()):
        fail(("%s: refusals = [...] collects a refusal instead of failing, for " +
              "%s's own fixtures only. A BUILD file elsewhere would turn the " +
              "guard off with it.") % (who, _FIXTURES))
    if not problem:
        return False
    if refusals == None:
        fail(problem)
    refusals.append(problem)
    return True

# The runners a test may hand a program built by student_binary, and how each
# tells a STAND-IN (tools/standin.sh) from a program: "checks" -- it sources
# standin.sh and calls standin_check before running it, which
# //tools:conventions verifies -- or "gate" -- it runs the program only as its
# correctness gate, through tools/diff_output.sh, which checks it there.
# _test() refuses, while loading, a test that hands a student_binary to any
# other runner: graded as a program, a stand-in was "memory-clean" to
# asan_run.sh and hundreds of wrong outputs to bsq_check.sh (findings 165,
# 173), and an option name is no way to find the next runner that does it --
# progname_test.sh takes its program as a plain argument.
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

# The options that put a corpus runner's replay under a memory checker
# (tools/runner_lib.sh, "A CORPUS UNDER A MEMORY CHECKER").
_MEMORY_MODES = ["--sanitized", "--valgrind"]

_RUNNER_CHOICES = {
    "//tools:argv_check.sh": [_STDERR_CHOICE],
    "//tools:bsq_check.sh": [_STDERR_CHOICE, _QUOTES_CHOICE],
    "//tools:file_check.sh": [_STDERR_CHOICE],
    "//tools:rush01_check.sh": [_STDERR_CHOICE, _QUOTES_CHOICE],
    "//tools:rush02_check.sh": [_STDERR_CHOICE],
}

def _runner_choice_problem(name, runner, args):
    """Why test `name`'s args make a choice `runner` asks for zero or two times; None if not.

    And, for the stderr pair, why --stderr-ignored's REASON would not reach
    the runner as one argument: Bazel tokenises a test's `args` like a shell,
    so a sentence written plainly is split at its blanks ("unknown option"
    from the runner), and one with an apostrophe fails the target's analysis
    ("unterminated quotation"). stderr_ignored() quotes it.
    """
    memory = [m for m in _MEMORY_MODES if m in args]
    for flags, what in _RUNNER_CHOICES.get(runner, []):
        given = [f for f in flags if f in args]
        if memory and flags == _STDERR_CHOICE[0]:
            if given:
                return (("%s replays its corpus under a memory checker (%s), where standard " +
                         "error carries the checker's report and no output is judged; drop " +
                         "%s, which would say otherwise (tools/defs.bzl, _RUNNER_CHOICES).") %
                        (name, memory[0], ", ".join(given)))
            continue
        if memory and flags == _QUOTES_CHOICE[0]:
            continue
        if len(given) != 1:
            return (("%s runs %s, which asks every call to say %s. Pass exactly " +
                     "one of %s; this call has %s.") %
                    (name, runner, what, ", ".join(flags), ", ".join(given) or "none"))
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
    "--gate-number": 1,
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

# The endings a student_binary's name must have (_student_bin() refuses any
# other): "ex03_bin", "ex03_bin_asan", "ex03_diffbin_asan", "ex03_memprobe".
# A name is what a test's `data` holds, and unlike existing_rule() it does not
# depend on the binary being declared before the test that runs it. The name
# also holds a "_" and no ".", which _student_bin() checks too: a bare entry
# of `data` is a target OR a file of the package, and a data file whose name
# ends in "bin" ("expected.bin", "cabin") is then not taken for a program.
_STUDENT_BIN_SUFFIXES = ("bin", "bin_asan", "bin_allocfail", "memprobe")

def _is_student_bin_name(n):
    """Whether `n` is a name _student_bin() accepts (see _STUDENT_BIN_SUFFIXES)."""
    return n.endswith(_STUDENT_BIN_SUFFIXES) and "_" in n and "." not in n

# The runners that run student code, and so read how each run ended from
# tools/exit_status, which asks waitpid(): the shell's 128+N cannot tell
# `return (-1);` from a death by signal 127 (see tools/exit_status.c). They
# make every run through tools/runner_lib.sh's rl_run. Every test _test() emits
# that names one gets the helper in its data; the runners refuse to run
# without it, so a hand-written sh_test that forgets it is red with a message,
# never quietly back on the guess. //tools:conventions refuses a runner that
# calls rl_tmo, rl_run or rl_ready and is missing here, and checks the
# hand-written sh_tests.
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
             "not in tools/defs.bzl's _STANDIN_RUNNERS. When those files " +
             "do not build, that program is a stand-in script " +
             "(tools/standin.sh), and a runner that does not ask graded " +
             "it as a program. Source standin.sh in the runner and call " +
             "standin_check before running it, then list it there.") %
            (name, ", ".join(built), runner))

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
    //tools:exit_status for one of _EXIT_STATUS_RUNNERS. A test
    whose data name a student_binary of this package must run one of
    _STANDIN_RUNNERS, or this fails while loading (what counts as naming one:
    see _STANDIN_RUNNERS). And a test whose runner asks every call for a
    choice (_RUNNER_CHOICES) makes it exactly once, or this fails while
    loading -- through _refuse(), so that in the macro fixtures `refusals`
    (a list) collects that refusal and no test is declared.
    """
    _refuse(None, refusals, kwargs.get("name"))  # `refusals` anywhere but the fixtures
    tags = kwargs.pop("tags", [])
    if waits:
        tags = tags + [_WAITS_TAG + waits]
    if _in_fixtures():
        tags = tags + ["manual"]

    # THE EXERCISE, as a tag, derived here rather than passed by thirty callers.
    # Every test name this macro emits begins with exNN_ -- checked across the
    # awkward shapes too (rush variants `ex00_rush03_output`, c_program cases
    # `ex01_blob_output`, c-08's `ex01_success_output`) -- so the prefix is a
    # reliable source and there is one place to get it wrong instead of thirty.
    # c_levels() turns these into a per-exercise suite.
    ex_tag = kwargs.get("name", "")[:4]
    if not _is_ex(ex_tag):
        ex_tag = None
    all_tags = tags + _level_tags(tags, level) + ([ex_tag] if ex_tag else [])
    if turnin != None and not turnin:
        where = turnin_where or _where(ex_tag or "")
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
    # that name a runner. hand_test() comes through here too; only a bare
    # sh_test would have to list it itself, and //tools:conventions checks that.
    if _RUNNER_LIB not in data:
        data = data + [_RUNNER_LIB]

    # After the NOT TURNED IN swap: no_turnin.sh runs nothing, so it gets no helper.
    uses = kwargs.get("srcs", []) + data
    if _EXIT_STATUS not in uses and [r for r in _EXIT_STATUS_RUNNERS if r in uses]:
        data = data + [_EXIT_STATUS]

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
    env = dict(kwargs.pop("env", None) or {})
    problem = _test_env_problem(kwargs.get("name"), env)
    if problem:
        fail(problem)
    r = native.existing_rule("subject")
    if r and r["kind"] == "subject_contract":
        env["RL_GRADER"] = json.decode(r["contract"])["grader"]

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
    """Why a test's own `env` is refused, or None: it may not set RL_GRADER or RL_RAISED.

    Who grades a project is its subject() contract's `grader`, and _test()
    hands it to every test of the package. One set by hand is a second answer
    to "who grades this", which stops matching the subject the day either
    changes -- the runners' words about where a failure costs would then be
    wrong with every test still green. RL_RAISED, the level a test sits at
    above its layer, is _RAISED's the same way.
    """
    if "RL_GRADER" in env:
        return ("%s sets RL_GRADER itself. Who grades a project is its " +
                "subject() contract's `grader`, and _test() hands it to every " +
                "test of the package; drop it from `env`.") % name
    if "RL_RAISED" in env:
        return ("%s sets RL_RAISED itself. Which tests sit above their layer " +
                "is _RAISED's (tools/defs.bzl), and _test() hands it to each " +
                "of them; drop it from `env`.") % name
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
    to the rules it gives (tools/defs.bzl, _audit_problems).

    Args:
        name: the target; in a project, exNN_<what>, ending in a suffix of
            _SUFFIX_LAYER that is this layer's (docs/reference.md, "Target
            names"). The audit fails a package whose test does not.
        layer: the layer tag, one of _LAYER_LEVEL ("diff", "selftest", ...).
        level: raise THIS test above its layer, only up (see _test). In a
            project a raise is listed in _RAISED, with its reason in
            docs/reference.md; the audit fails one that is not.
        tags: further tags that are not a layer, a level or an exercise:
            "manual", which keeps a test out of every suite but :manual and
            out of //... (listed in _MANUAL, with the reason in the docs).
        **kwargs: everything else sh_test takes: srcs, args, data, size,
            timeout, shard_count, env. `waits`, the output test of its own
            exercise a gated one waits for where its gate alone cannot tell
            (see _test). And, in
            the macro fixtures alone, `refusals` (see _test and _refuse).
    """
    for t in tags or []:
        if t.startswith(_WAITS_TAG):
            fail(("hand_test(name = %r): tags = [%r]. Say which output test it waits " +
                  "for with waits = \"<that test>\", which the audit holds to its " +
                  "gate.") % (name, t))
        if t.startswith(_COVERS_TAG) or t == _NO_VALGRIND_TAG:
            fail(("hand_test(name = %r): tags = [%r]. That tag is corpus_memory()'s, " +
                  "which sets it from its `covers` or `no_valgrind` and asks for the " +
                  "reason as a sentence: written here, it would excuse a corpus from " +
                  "its memory twins with no reason anywhere.") % (name, t))
    _hand_test(name, layer, level, tags, **kwargs)

def _hand_test(name, layer, level = None, tags = None, **kwargs):
    """hand_test() without its guard on corpus_memory()'s own tags."""
    _known_layer("hand_test(name = %r)" % name, layer)
    tags = tags or []
    for t in tags:
        if t in _LAYER_LEVEL or t.startswith("lvl_") or _is_ex(t):
            fail(("hand_test(name = %r): tags = [%r]. The layer is `layer`, and the " +
                  "level ladder and the exercise tag are derived from it and from " +
                  "the name; a second copy is one that can disagree.") % (name, t))
    _test(name = name, level = level, tags = [layer] + tags, **kwargs)

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
        stem: the targets' front, exNN_<what> (ex00_bsq, ex02_file): the plain
            replay's name less its layer's suffix, where it has one.
        runner: the corpus runner, one of _CORPUS_RUNNERS.
        args: the runner's arguments for the corpus, without --bin: the
            generator, its size AND its transport, as the plain replay passes
            them -- a corpus a program reads on standard input passes the
            runner's --mode stdin here too (BSQ's ex00_bsq_stdin), or its twins
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
    """
    ex = stem.split("_")[0]
    if not _is_ex(ex):
        fail("corpus_memory(stem = %r): a stem is exNN_<what>, so the targets land in :exNN." % stem)
    if runner not in _CORPUS_RUNNERS:
        fail(("corpus_memory(stem = %r): %s is not one of tools/defs.bzl's " +
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

    valgrind = _memcheck_allowed(_entry(ex[2:], "corpus_memory"))
    if no_valgrind != None:
        _reason("no_valgrind", no_valgrind)
        if not valgrind:
            fail(("corpus_memory(stem = %r): no_valgrind, but exercise %s's subject " +
                  "allows no malloc, so there is no memcheck arm to leave out.") % (stem, ex))
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

    def _uniq(labels):
        out = []
        for label in labels:
            if label not in out:
                out.append(label)
        return out

    guarded = ["--guarded-argv"] if asan_bin.endswith(_ARGV_GUARD_SUFFIX) else []
    _hand_test(
        name = stem + "_diff_asan",
        layer = "diff_asan",
        tags = tags + ([_NO_VALGRIND_TAG] if no_valgrind != None else []),
        size = size,
        srcs = [runner],
        args = ["--bin", "$(location %s)" % asan_bin] + args + ["--sanitized"] + guarded + _symbolizer_args(),
        data = _uniq([asan_bin, runner] + data + _SYMBOLIZER_DATA),
        waits = waits,
    )
    if valgrind:
        # The subject's own sentence about memory, where its c_program
        # declared one (memory_rule): a red quotes it once under its
        # verdict, as each fixed case's _valgrind arm does (V82). Read from
        # the file c_program writes, never passed again;
        # _memory_rule_reach_problems refuses a twin without it.
        rule = ex + "_memory_rule"
        rule_args = []
        rule_data = []
        if native.existing_rule(rule):
            rule_args = ["--rule", "$(location :%s)" % rule]
            rule_data = [":" + rule]
        _hand_test(
            name = stem + "_valgrind",
            layer = "valgrind",
            tags = tags,
            # A sample of the corpus under memcheck, at 20-50x: never
            # "small", whatever the plain and ASan replays take. BSQ's and
            # Rush 01's readings samples took 18-23s with two suites on the
            # machine, a third of "small"'s 60 (finding 066).
            size = "medium" if size == "small" else size,
            srcs = [runner],
            args = ["--bin", "$(location %s)" % bin] + args + _valgrind_args() +
                   ["--sample", str(sample)] + rule_args,
            # valgrind_test.sh judges each sampled case; the runner finds it
            # beside itself in the runfiles (rl_mem_ready).
            data = _uniq([bin, runner, "//tools:valgrind_test.sh"] + data + _valgrind_data() + rule_data),
            waits = waits,
        )

def _no_orphan_prototype(ex, macro):
    """Refuse a tests/exNN/prototype.h that the calling macro will never read.

    _function_layers()'s `required` guard exists because "deliberately opted out"
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
            ("%s(num = \"%s\") found tests/%s/prototype.h, which it will never " +
             "use: %s exercises get no prototype layer. Delete the file, or " +
             "move the exercise to a macro that has one.") %
            (macro, ex[2:], ex, macro),
        )

def _dirname(path):
    """The directory part of a package-relative path, "" for a bare filename.

    Starlark has no dirname, and this is needed wherever a compile has to be
    told where a header lives: the label names a FILE, and "<file>/.." walks
    through it rather than to its parent -- a mistake this repo has made twice,
    both times ending in a pinned compiler quietly loading the box's libraries.
    """
    if "/" not in path:
        return ""
    return path.rsplit("/", 1)[0]

# The characters a turn-in file's NAME may hold for it to reach a build or a
# layer. Every other one breaks some layer between the glob and the runner: a
# blank is split in two by sh_test's argument tokenising (the files layer
# reported "ft_putchar" and "copy.c"), a parenthesis ends a $(location ...)
# early and fails the ANALYSIS of every layer that named the file, a $ starts
# a make variable. No subject names a file with any of them, so a name that
# holds one is dropped from everything that builds or reads files (_safe())
# and reported, by its real name, by the one layer that reads names only:
# c_files, through a name list written with no label at all (_names_file).
_SAFE_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._+-/"

def _safe(path):
    """Whether every character of `path` is one a label and an argument carry."""
    for c in path.elems():
        if c not in _SAFE_CHARS:
            return False
    return True

def turnin_glob(include, exclude = None):
    """A glob of the turn-in, as every macro here globs it: never failing.

    allow_empty = True, because an empty folder is a student's state and must
    fail the tests that needed its files, not the loading of the package; and
    only names _safe() accepts, because a file named "rush (copy).c" is one
    that no label or argument list can carry (see _SAFE_CHARS). c_files still
    sees such a file and reports it. For a module BUILD file that needs a
    list of turn-in files itself -- which, with the contract, none does --
    instead of a bare glob().
    """
    return [
        f
        for f in native.glob(include, exclude = exclude or [], allow_empty = True)
        if _safe(f)
    ]

# ---------------------------------------------------------------------------
# THE SUBJECT CONTRACT, as the macros read it (tools/subject.bzl declares it).
#
# Every fact below comes from the one subject() call at the top of the
# package's BUILD file: where an exercise turns in, which files it names or
# allows, what the grader brings, what may be called. No macro types one of
# them again, and no BUILD file passes one at a call site -- the parameters
# that took them (c_files' required/optional/strict/subdir, c_function's
# allowed/provided_hdrs/provided_srcs/extra_includes, c_make's anchor/overlay,
# c_program's make_data ...) are gone, so a second copy cannot be written.

def _no_contract_problem(what, r):
    """The message a macro fails with when its package has no subject(); None if it has one.

    `r` is native.existing_rule("subject"). A value first, like every
    contract check (see tools/subject.bzl): contract_problem() hands it to the
    fixtures.
    """
    if r and r["kind"] == "subject_contract":
        return None
    return (("%s: %s declares no subject() before this call. Every project's " +
             "BUILD.bazel opens with its subject contract -- where each exercise " +
             "turns in, its files, what the grader brings, what it may call -- " +
             "transcribed from the subject (tools/subject.bzl; docs/reference.md, " +
             "\"The subject contract\"), and every macro reads it from there.") %
            (what, native.package_name() or "this package"))

def _contract(what):
    """This package's subject contract, decoded; fail()s naming `what` without one."""
    r = native.existing_rule("subject")
    problem = _no_contract_problem(what, r)
    if problem:
        fail(problem)
    return json.decode(r["contract"])

def _no_entry_problem(num, what, contract):
    """The message for a macro called on an exercise the contract lacks; None if it has it."""
    if contract["exercises"].get(num) != None:
        return None
    return (("%s(num = \"%s\"): exercise %s is not in this package's subject() " +
             "contract (it has %s). Transcribe its header box there first.") %
            (what, num, num, ", ".join(sorted(contract["exercises"].keys()))))

# THE READERS OF A CONTRACT ENTRY THAT MAY MEET `linked` (the functions the
# grader compiles in: tools/grader_lib.bzl), with why. Every other reader
# fail()s on an entry that has one (_linked_reader_problem), so a macro written
# tomorrow cannot ignore the key without a word: a program it built without the
# grader's library would not link, and the red would read as the student's
# code (WP-78, TODO.md section 23). A reader goes in here
# only once it links _linked(num).libs into every program it builds -- or
# builds none.
_TAKES_LINKED = {
    # Link the library into every program they build, and hand it to every
    # runner that compiles at test time (--lib, or ilp32's --lib32: its
    # 64-bit program is the output layer's, built with the library linked).
    "c_function": "links it (its allocfail layer cannot: _no_linked_problem)",
    "c_mem_check": "links it",
    "c_diff": "links it",
    "c_perf": "links it",
    "c_cycles": "links it",
    # Build no program.
    "c_files": "builds none",
    "turnin_file": "builds none",
    "turnin_dir": "builds none",
    # The internal helpers: each reads one field, for a public macro that has
    # read its entry first (every one does, on its first line) and so has
    # passed this check already.
    "allowed": "a helper",
    "layout": "a helper",
    "linked": "a helper",
    "provided": "a helper",
    "turnin": "a helper",
}

def _linked_reader_problem(num, what, e):
    """The message for `what` reading an entry whose `linked` it would ignore; None if it may.

    A value first, like every contract check: contract_problem() hands it to
    the fixtures.
    """
    fns = e.get("linked") or {}
    if not fns or what in _TAKES_LINKED:
        return None
    return (("%s(num = \"%s\"): the grader links %s into this exercise (its contract's " +
             "`linked`), and %s does not link a grader library into the programs it " +
             "builds. A correct answer would not link, and the red would read as the " +
             "student's fault. Link _linked(num).libs into every program %s builds, " +
             "as c_function does, then add it to _TAKES_LINKED in tools/defs.bzl.") %
            (what, num, ", ".join(sorted(fns.keys())), what, what))

def _entry(num, what):
    """Exercise `num`'s contract entry; fail()s naming `what(num = "NN")` if there is none.

    `what` is the PUBLIC macro the BUILD file called -- c_function, c_program
    -- because that is the line a reader of the error goes looking for: every
    public macro reads its entry first, before any helper does (an internal
    helper's name, "turnin", sent a reader to a function no BUILD file calls).

    It also fail()s where the entry has a `linked` that `what` would ignore
    (_TAKES_LINKED lists the readers that may meet one).
    """
    c = _contract("%s(num = \"%s\")" % (what, num))
    problem = _no_entry_problem(num, what, c)
    if problem:
        fail(problem)
    problem = _linked_reader_problem(num, what, c["exercises"][num])
    if problem:
        fail(problem)
    return c["exercises"][num]

def _untranscribed_problem(contract, seen):
    """c_levels' message for tests/exNN/ folders the contract does not list; None if none.

    `seen` is the exNN names found under tests/.
    """
    declared = ["ex" + n for n in contract["exercises"]]
    untranscribed = sorted([ex for ex in seen if ex not in declared])
    if not untranscribed:
        return None
    return (("c_levels: tests/ has %s, which this project's subject() contract " +
             "does not list. Transcribe the exercise's header box into subject() " +
             "first: every layer takes its turn-in from there.") % ", ".join(untranscribed))

def _turnin_file_problem(num, name, e):
    """turnin_file()'s message when `name` is not a file the contract lets exercise `num` hold."""
    if name in (e["files"] or []) or name in e["optional"]:
        return None
    for p in e["optional"]:
        # The one pattern shape a contract uses for a file named at a call
        # site: "*.c", "*.h" -- a basename with an extension, in the turn-in
        # directory itself. A deeper pattern ("**/*.h") never names one file.
        if p.startswith("*.") and "/" not in p and "/" not in name and name.endswith(p[1:]):
            return None
    if name in e["provided"].values():
        return (("turnin_file(\"%s\", %r): the grader brings that file (the contract's " +
                 "`provided`), so it is never the student's: the harness's copy is " +
                 "under tests/.") % (num, name))
    return (("turnin_file(\"%s\", %r): the subject() contract does not let exercise %s " +
             "hold that file (files: %s; optional: %s). Name a file the subject asks " +
             "for, or transcribe it into the contract first.") %
            (num, name, num, e["files"], e["optional"]))

def _issued_problem(num, file, e):
    """c_issued()'s message when `file` is not one the contract lets it demand; None if it is.

    The file is named in the contract, by name, in the exercise's `optional`,
    and c_issued() points at that entry: it builds its path with
    turnin_file(), never by hand. A name the contract does not let the
    exercise hold is a file the files layer reports as extra while c_issued's
    test demands it -- on a strict subject, red both ways at basic. One in
    `files` is required by the files layer too, which then goes red on a
    fresh clone, where the template strips the file, with a report that
    cannot say where 42 publishes it. A pattern ("*.dict") covers it without
    naming it, and the contract is where the next reader looks for the
    project's files.
    """
    if type(file) != "string" or not file or [c for c in file.elems() if c not in _SAFE_CHARS] or "/" in file:
        return (("c_issued(num = \"%s\"): file = %r. It is the name 42 gives the file, " +
                 "as tools/resources.tsv lists it: no folder, no space.") % (num, file))
    where = "c_issued(num = \"%s\", file = %r)" % (num, file)
    if file in (e["files"] or []):
        return (("%s: the contract's `files` requires it, so the files layer is red on a " +
                 "fresh clone too, where the template strips it, with a report that cannot " +
                 "say where 42 publishes it. Move it to the exercise's `optional`: this test " +
                 "is what requires it.") % where)
    if file not in e["optional"] or _turnin_file_problem(num, file, e):
        return (("%s: the subject() contract does not name that file for exercise %s " +
                 "(files: %s; optional: %s), so the files layer would report it as extra " +
                 "while this test demands it. Name it in the exercise's `optional`, as the " +
                 "subject's turn-in covers it.") % (where, num, e["files"], e["optional"]))
    return None

def _diff_harness_problem(num, harness):
    """c_diff's message for a reader harness not named diff_*.c; None if it is.

    The name is how the harness is found by everything that reads it apart
    from the build: //tools:conventions holds every tests/**/diff_*.c to the
    header shape rust_diff.sh's print_columns reads its column legend from
    (finding 058), and each module's :conventions_srcs globs that name. A
    reader named anything else built and ran, and its legend went unchecked.
    """
    base = harness.split("/")[-1]
    if base.startswith("diff_") and base.endswith(".c") and len(base) > len("diff_.c"):
        return None
    return (("c_diff(num = \"%s\", harness = %r): a differential reader harness is " +
             "named diff_<what>.c. //tools:conventions finds the harnesses by that " +
             "name to hold their header to the \"Line:\" legend the diff layer prints " +
             "(tools/rust_diff.sh, print_columns), so a reader named otherwise is " +
             "never checked. Rename the file.") % (num, harness))

def contract_problem(check, args):
    """What a contract check would fail with, as a string; None where it passes.

    FOR tools/tests/macro_fixtures ONLY. Every check the contract makes is a
    value before it is a fail() (see tools/subject.bzl), and this is how the
    fixtures reach the ones in this file: a package that fails to load cannot
    be a test, so each check is fed the broken input it guards against and
    its message compared, on every run. A project's BUILD file never calls
    it.

    Args:
        check: which check, and what `args` holds for it --
            "exercise", "subject"  the arguments of exercise() / subject()
            "no_contract"          macro, num: a macro called in THIS package
                                   before any subject() -- ask it above the
                                   package's subject() to see the message
            "no_entry"             macro, num: a macro called on an exercise
                                   this package's contract does not list
            "untranscribed"        seen: tests/exNN names, against this
                                   package's contract (c_levels' check)
            "turnin_file"          num, name: turnin_file() in this package
            "issued"               num, file: c_issued() in this package
            "case"                 shape ("program", "header", "reading"),
                                   case: one case dict, and optionally
                                   program: c_program's name
                                   (_case_problem)
            "diff_harness"         num, harness: c_diff's reader harness
                                   name (_diff_harness_problem)
            "audit"                package, tests ({name: tags}, or {name:
                                   {"tags", "srcs", "args"}}), exercises,
                                   and optionally layouts (tests/layout/
                                   files), reads ({name: the layout files
                                   it passes with --layout}), fixtures
                                   ({binary with a harness: the prototype
                                   test its tag names, or None for no
                                   tag}), makefiles (the exNN whose
                                   contract names a Makefile) and malloc
                                   (the exNN whose contract allows it):
                                   c_levels()' audit of a whole package,
                                   fed an invented one (_audit_problems); its
                                   messages joined with " | "
            "audit_rules"          package, exercises, rules ({name: the
                                   attributes existing_rules() gives it:
                                   kind, tags, srcs, args, harness, deps}), and
                                   optionally layouts, makefiles and
                                   malloc: the same audit fed
                                   rules rather than what it reads from
                                   them (_audit_inputs), so the reading of
                                   a tag or an argument is proven too
            "harness_prototype"    name, harness, prototype: _student_bin's
                                   check of its `prototype` against its
                                   `harness`
            "test_env"             name, env: _test()'s check of a test's own
                                   `env` (_test_env_problem)
            "linked"               exercises (as subject() takes them),
                                   exports ({label: names, or None for a
                                   target that is no grader_library()}): the
                                   contract's analysis check of `linked`
                                   (tools/subject.bzl's linked_problem())
            "linked_reader"        macro, num: that macro reading exercise
                                   num's entry in THIS package's contract
                                   (_linked_reader_problem)
            "linked_layer"         macro, num, layer: a layer that cannot
                                   link the grader's library, on exercise
                                   num of this package (_no_linked_problem)
            "make"                 c_make's num, quotes and the checks they
                                   back (_make_problem)
            "make_anchor"          num, anchor[, macro]: c_make (or the
                                   `macro` named, "c_program") building
                                   from `anchor` ("Makefile", or its
                                   script) on exercise num of THIS package
                                   (_make_anchor_problem)
            "allocfail"            c_function's num, malloc, allocfail and
                                   allocfail_rule (_allocfail_problem)
            "function_malloc"      num, malloc: c_function's `malloc` on
                                   exercise num of THIS package, against its
                                   contract (_function_malloc_problem)
            "memory_rule"          c_program's num, malloc, cases and
                                   memory_rule (_memory_rule_problem)
            "libft_make"           make: c_libft's dict of c_make's
                                   arguments (_libft_make_problem)
            "standin_runner"       name, data, runner: a test of THIS package
                                   handing `data` to `runner`
                                   (_standin_runner_problem)
        args: the check's input, as a dict: a BUILD file cannot pass **kwargs.

    Returns:
        The message the check fails with, or None where it passes.
    """
    if check == "exercise":
        return _exercise_problem(**args)
    if check == "subject":
        return _subject_problem(**args)
    if check == "no_contract":
        return _no_contract_problem(
            "%s(num = \"%s\")" % (args["macro"], args["num"]),
            native.existing_rule("subject"),
        )
    if check == "no_entry":
        return _no_entry_problem(args["num"], args["macro"], _contract("contract_problem"))
    if check == "untranscribed":
        return _untranscribed_problem(_contract("contract_problem"), args["seen"])
    if check == "turnin_file":
        return _turnin_file_problem(args["num"], args["name"], _entry(args["num"], "turnin_file"))
    if check == "issued":
        return _issued_problem(args["num"], args["file"], _entry(args["num"], "c_issued"))
    if check == "case":
        return _case_problem(args["case"], args["shape"], args.get("program"))
    if check == "diff_harness":
        return _diff_harness_problem(args["num"], args["harness"])
    if check == "audit":
        reads = args.get("reads") or {}
        tests = {}
        for n, t in args["tests"].items():
            # {name: tags}, or {name: {"tags", "srcs", "args"}} for a test the
            # corpus rule reads (srcs, args).
            tests[n] = dict(kind = "sh_test", **t) if type(t) == "dict" else {"kind": "sh_test", "tags": t}
            tests[n]["layouts"] = reads.get(n, [])
        return " | ".join(_audit_problems(
            args["package"],
            tests,
            args["exercises"],
            layouts = args.get("layouts"),
            fixtures = args.get("fixtures"),
            makefiles = args.get("makefiles"),
            malloc = args.get("malloc"),
            clues = args.get("clues"),
        )) or None
    if check == "waiting":
        # Not a problem but what _waiting writes, as one line: each output
        # test's list, "<output>: <test> (<level>), ...", fed invented tests
        # ({name: {"tags", "args"}}) as the audit is.
        tests = {n: dict(kind = "sh_test", **t) for n, t in args["tests"].items()}
        lists = _waiting_lists(tests)
        return " | ".join(["%s: %s" % (o, ", ".join(lists[o]) or "-") for o in sorted(lists)]) or None
    if check == "audit_rules":
        tests, fixtures, oracle, diffio = _audit_inputs(args["rules"])
        return " | ".join(_audit_problems(
            args["package"],
            tests,
            args["exercises"],
            layouts = args.get("layouts"),
            fixtures = fixtures,
            oracle = oracle,
            makefiles = args.get("makefiles"),
            malloc = args.get("malloc"),
            diffio = diffio,
        )) or None
    if check == "harness_prototype":
        return _harness_prototype_problem(args["name"], args.get("harness"), args.get("prototype"))
    if check == "test_env":
        return _test_env_problem(args["name"], args["env"])
    if check == "linked":
        return _linked_problem(args["exercises"], args["exports"])
    if check == "linked_reader":
        return _linked_reader_problem(args["num"], args["macro"], _contract("contract_problem")["exercises"][args["num"]])
    if check == "linked_layer":
        return _no_linked_problem(args["num"], args["macro"], args["layer"])
    if check == "make":
        return _make_problem(**args)
    if check == "make_anchor":
        macro = args.get("macro", "c_make")
        return _make_anchor_problem(args["num"], args["anchor"], _entry(args["num"], macro), macro)
    if check == "allocfail":
        return _allocfail_problem(**args)
    if check == "function_malloc":
        return _function_malloc_problem(args["num"], args["malloc"], _entry(args["num"], "c_function"))
    if check == "memory_rule":
        return _memory_rule_problem(**args)
    if check == "libft_make":
        return _libft_make_problem(args["make"])
    if check == "standin_runner":
        return _standin_runner_problem(args["name"], args["data"], args["runner"], native.package_name())
    fail("contract_problem(check = %r): not a check this knows" % (check,))

def turnin_dir(num):
    """The package-relative directory exercise `num` turns in at.

    deliverable/exNN for a subject whose turn-in line says "exNN/", and
    deliverable/ itself for one with no such line (BSQ, every Common Core
    project): deliverable/ is the root of the repository that is pushed.
    """
    d = _entry(num, "turnin_dir")["dir"]
    return "deliverable" if d == None else "deliverable/" + d.rstrip("/")

def _where(ex):
    """turnin_dir() for a target's `exNN` prefix, where the contract has it."""
    r = native.existing_rule("subject")
    if ex.startswith("ex") and r and r["kind"] == "subject_contract":
        if json.decode(r["contract"])["exercises"].get(ex[2:]) != None:
            return turnin_dir(ex[2:])
    return "deliverable/" + ex

def _misplaced(where):
    """The exNN/ folders holding files under `where`, when it is the root of deliverable/.

    Nothing turned in at the root, and files one folder down: a root turn-in
    (BSQ, the Common Core) kept in the layout of the modules that have a
    turn-in directory -- BSQ's own, until its subject was read. A NOT TURNED
    IN test then says where they are and how to move them up (no_turnin.sh
    --misplaced). [] for any other `where`.
    """
    if where != "deliverable":
        return []
    found = {}
    for f in native.glob(["deliverable/ex*/**"], exclude = _not_build_products("deliverable"), allow_empty = True):
        d = f.split("/")[1]
        if len(d) == 4 and d[2:].isdigit():
            found["deliverable/" + d] = True
    return sorted(found.keys())

def _student_folders(contract):
    """{exNN: its folder} for every deliverable/exNN/ there is, found by name.

    Where an exercise's folder would be, whether the contract has that
    exercise or not: c_levels() looks for the ones it does not (a folder of
    the student's for an exercise the subject lacks). {} in a project that
    turns in at deliverable/ itself, whose subfolders are its turn-in's own.
    """
    if [e for e in contract["exercises"].values() if e["dir"] == None]:
        return {}
    found = {}
    for d in native.glob(["deliverable/ex*"], exclude_directories = 0, allow_empty = True):
        ex = d.split("/")[1]
        if _is_ex(ex):
            found[ex] = d
    return found

def _turnin_files(num, ext):
    """Every `ext` file the contract lets exercise `num` turn in, that is there.

    THE CONTRACT'S FILE SET, AND NOTHING ELSE: each name of `files` and of
    `optional` that ends in `ext`, and each pattern there for that extension
    ("*.c", "**/*.h", "srcs/*.c"), globbed under turnin_dir(). Every layer of
    an exercise compiles what this returns -- the output fixture, the memory
    probes, ASan, the 32-bit build, the norm, compile, forbidden, prototype
    and symbols layers -- because each reads `srcs` from _deliverable_srcs()
    and its headers from _deliverable_hdrs(), both of which call this. A file
    the contract does not let the turn-in hold is the files layer's report
    (c_files), and no other layer's.

    It globbed every `ext` file of the folder, flat, and the layers then
    disagreed about a stray one: the output fixture and its memcheck linked
    the function's file out of an archive and never pulled a stray main.c
    in, while the memory probe, ASan and the 32-bit build linked every
    source directly and failed on two main()s -- C 00 ex08 and C 01 ex07,
    the mutation run of 2026-10-03 (AGENTS.md section 6, "Compile as the
    grader compiles": the grader compiles the files its subject names).
    Flat unless a pattern reaches into subfolders, as before: a subfolder is
    not where an exercise that names its files keeps them -- a copy of the
    grader's srcs/ left in C 09 ex01, say, which ex01_build reports instead.
    """
    e = _entry(num, "turnin")
    d = turnin_dir(num)
    pats = [p for p in (e["files"] or []) + e["optional"] if p.endswith(ext)]
    return turnin_glob([d + "/" + p for p in pats])

def turnin_file(num, name):
    """The package-relative path of `name` in exercise `num`'s turn-in, checked against the contract.

    For the few call sites that must name ONE turn-in file themselves: a unit
    of another exercise's sources, or a function a module archives with its
    own script (C 09 ex00's ft_strcmp.c). (C 12 ex05's probe used to link
    ex00's ft_create_elem.c this way; the grader's own copy is linked there
    now, from the contract's `linked`.) A path spelled "deliverable/ex00/..." at a
    call site is the layout decided a second time -- the way BSQ ended up
    under an ex00/ its subject never names -- so //tools:conventions refuses
    one in a project's BUILD file, and this builds it from turnin_dir()
    instead, and fails while loading unless the contract lets the exercise
    hold that file: a name in `files` or `optional`, or one a top-level
    `optional` pattern ("*.c") matches. A file the grader brings never
    qualifies: it is not the student's.

    The file may still be missing from the tree: whatever reads the path
    drops it then (_zone()), and the layers that needed it say so.

    Args:
        num: the exercise, as its contract entry is keyed ("00").
        name: the file, relative to the exercise's turn-in directory.

    Returns:
        The package-relative path: turnin_dir(num) + "/" + name.
    """
    e = _entry(num, "turnin_file")
    problem = _turnin_file_problem(num, name, e)
    if problem:
        fail(problem)
    return turnin_dir(num) + "/" + name

def _nested_in_turnin(path):
    """Whether `path` is a turn-in file in a SUBFOLDER of its exercise's turn-in directory.

    deliverable/ex00/includes/name.h is; deliverable/ex00/name.h, a
    header under tests/ and a label are not.
    """
    r = native.existing_rule("subject")
    if not r or r["kind"] != "subject_contract" or path.startswith(":") or \
       path.startswith("//") or path.startswith("@") or not _in_zone(path):
        return False
    for e in json.decode(r["contract"])["exercises"].values():
        d = "deliverable" if e["dir"] == None else "deliverable/" + e["dir"].rstrip("/")
        if path.startswith(d + "/") and "/" in path[len(d) + 1:]:
            return True
    return False

def _inc_args(flag, hdrs, staged = None):
    """The include-path arguments a layer passes a runner for `hdrs`.

    `flag` (--hdr, --inc) and each header, whose directory the runner puts on
    -I -- except a header in a SUBFOLDER of the turn-in (includes/name.h),
    which is only staged: its directory is never put on the path, and
    `staged`, where the runner takes one, names it for the message.

    WHY. The include path a layer compiles with is the GRADER's, or the layer
    measures something else. Rush 01's grader runs `cc -Wall -Wextra -Werror
    -o rush01 *.c` in the turn-in directory: a quoted #include is searched
    beside the file that includes it and nowhere else, so a header moved to
    includes/ is found only by `#include "includes/name.h"`. A Makefile
    project's include path is the -I its recipes pass, which only `make -Bn`
    knows (_student_bin's includes_out, handed to the compile and forbidden
    layers as --inc-file). Putting every staged header's directory on -I made
    the compile layers green on a turn-in the grader cannot compile, beside a
    program that was a stand-in for the same reason (Rush 01, BSQ, Rush 02).

    A header beside the sources, one the grader brings (under tests/) and a
    harness's are on the path as before: that is where the grader has them,
    or where the harness needs them. Every layer passes its headers through
    here; //tools:conventions refuses the per-header loop written anywhere
    else in this file.
    """
    args = []
    for h in hdrs:
        if _nested_in_turnin(h):
            if staged:
                args += [staged, "$(location %s)" % h]
        else:
            args += [flag, "$(location %s)" % h]
    return args

def _provided(num):
    """What the grader brings for exercise `num`, split the way the builds use it.

    Returns a struct: srcs (the .c copies under tests/, linked with the
    student's code and judged by no layer), hdrs (the .h copies, staged and
    never normed as the student's), includes (the directories those headers
    sit in, for the compiles that #include them by name) and overlay (every
    copy, with where the grader puts it, for a Makefile turned in alone).
    """
    p = _entry(num, "provided")["provided"]
    hdrs = sorted([k for k in p if k.endswith(".h")])
    includes = []
    for h in hdrs:
        d = _dirname(h)
        if d not in includes:
            includes.append(d)
    return struct(
        srcs = sorted([k for k in p if k.endswith(".c")]),
        hdrs = hdrs,
        includes = includes,
        overlay = p,
    )

def _linked(num):
    """What the grader links into exercise `num`'s programs: the contract's `linked`.

    Returns a struct: names (the functions, for the forbidden and symbols
    layers, which tell a student who defines one that the grader brings it),
    libs (their grader_library() labels, linked into every 64-bit program the
    exercise builds, in place of the exercise that writes the function) and
    libs32 (each one's i686 archive, for the ilp32 layer: tools/grader_lib.bzl
    declares it as <label>_i686).
    """
    fns = _entry(num, "linked").get("linked") or {}
    libs = sorted({lib: True for lib in fns.values()}.keys())
    return struct(
        names = sorted(fns.keys()),
        libs = libs,
        libs32 = [lib + "_i686" for lib in libs],
    )

def _no_linked_problem(num, macro, layer):
    """The message for a `layer` of `macro` that cannot link the grader's library; None if `num` has none.

    A runner that compiles the student's code at test time links what it is
    handed (asan_check.sh and cycles_check.sh take --lib, ilp32_test.sh
    --lib32 for its 32-bit build: its 64-bit program, --gate-bin, is built
    with the library linked); the ones this is called for take none, so a program
    built there could not find the grader's function and would read as the
    student's code not linking. A whole macro that cannot is refused by
    _entry() instead (_TAKES_LINKED). A value first: contract_problem() hands
    it to the fixtures.
    """
    linked = _linked(num)
    if not linked.libs:
        return None
    return (("%s(num = \"%s\"): the grader links %s into this exercise (its " +
             "contract's `linked`), and the %s layer's runner cannot link a grader " +
             "library yet: its program would not link, and that would read as the " +
             "student's fault. Give the runner a --lib, as asan_check.sh and " +
             "cycles_check.sh take (ilp32_test.sh takes --lib32 for its 32-bit build; " +
             "its 64-bit program, --gate-bin, is built with the library linked).") %
            (macro, num, ", ".join(linked.names), layer))

def _no_linked(num, macro, layer):
    """fail() with _no_linked_problem()'s message, where there is one."""
    problem = _no_linked_problem(num, macro, layer)
    if problem:
        fail(problem)

def _allowed(num):
    """The forbidden layer's list for exercise `num`: None for no layer."""
    e = _entry(num, "allowed")
    if e["allowed"] == None:
        return None
    return e["allowed"] + e["variables"]

def _deliverable_srcs(ex):
    """Every .c file the student turns in for exercise `ex`, possibly none.

    GLOBBED, never listed. The subject's file set is written down in exactly one
    place -- this project's subject() contract -- and the files layer CHECKS it
    against the directory; compilation globs the directory for the names and
    patterns the contract gives (_turnin_files), so the two cannot drift
    apart, and a file the contract does not let it hold is compiled by no
    layer.

    They used to. Five macros -- c_function, c_mem_check, c_program, c_cycles and
    c_reference_cost -- each computed `deliverable/exNN/<fn>.c` independently, so
    an exercise whose subject asks for two files had to override `srcs` at all
    five call sites. c-07 ex04 overrode c_function and not c_cycles, and the
    result was a link error at -O2 naming ft_strlen and ft_atoi_base, which reads
    as a problem with the optimisation level rather than a missing source.

    Only these five ever needed it: c_perf, c_argv_table and c_diff name no files
    at all, referencing the targets built above them (:exNN_bin, :fn), and
    within c_function every layer -- norm, both compilers, forbidden,
    prototype, symbols, ilp32, asan, valgrind -- already reads one `srcs` local.
    The same five take their headers from _deliverable_hdrs() below: a macro
    that globs the sources and not the headers beside them builds a folder it
    has only half staged.

    Flat unless the contract says otherwise (see _turnin_files()).

    NOT used by the rush macros, and must not be. rush-00's deliverable/ex00
    holds rush00.c .. rush04.c, each defining rush(), plus main.c and
    ft_putchar.c; compiling that directory as one unit is a duplicate-symbol
    error by design. rush_common()/rush_variant() name their files explicitly
    for that reason, each through _zone().

    AN EMPTY DIRECTORY GIVES AN EMPTY LIST, and that is handled where it is
    used: the programs built from it are stand-ins that say there is no .c file
    (tools/student_build.sh), and every layer that reads the files is emitted
    as a "not turned in" test (_test's `turnin`). It used to fall back to the
    conventional file name, a literal path that Bazel then failed to find while
    ANALYSING the package -- the missing file broke every target that named it
    instead of failing the tests that needed it.
    """
    return _turnin_files(ex[2:], ".c")

def _deliverable_hdrs(ex, listed = None):
    """Every .h the contract lets exercise `ex` turn in, the named ones first.

    The same five macros read this, under the same condition: `srcs` left at
    its default. A macro that compiles the directory has to stage the headers
    in it too, because a Bazel sandbox holds only what a target declares. A
    student who moved their prototypes into a header of their own got "'ft_tail.h'
    file not found" on their own #include line from every binary and layer,
    while `make` built the same folder, and a header nothing included was never
    shown to norminette at all (C 10, C 11 ex05, Piscine Reloaded ex27). The
    subjects of those exercises leave the file layout to the student, so a
    header there is normal, and one that is not staged is the harness's fault.

    First the headers the contract's `files` names (C 12's ft_list.h), then
    `listed` (a caller's explicit hdrs), each kept in that order -- except a
    file under deliverable/ that is not there, which is dropped (see
    _zone()): the compile that needed it then fails in the compiler's words,
    and the files layer says it is missing. Then every other header the
    contract lets lie there (_turnin_files()), so a call site cannot make one
    beside the sources disappear. allow_empty, for the reason
    _deliverable_srcs() gives: most exercises have no header.
    """
    d = turnin_dir(ex[2:])
    named = [d + "/" + f for f in (_entry(ex[2:], "turnin")["files"] or []) if f.endswith(".h")]
    listed = _zone(named + [h for h in (listed or []) if h not in named])
    found = _turnin_files(ex[2:], ".h")
    return listed + [h for h in found if h not in listed]

def _in_zone(path):
    """Whether a package-relative path is in AGENTS.md section 0's zone.

    That is the student's work: anything under a deliverable/ or a generators/.
    """
    return path.startswith("deliverable/") or path.startswith("generators/") or \
           "/deliverable/" in path or "/generators/" in path

def _zone(paths):
    """`paths`, less every file of the student's that is not there.

    A path under deliverable/ or generators/ is kept only if a glob finds it; a
    label, or a harness file under tests/, is kept as given. This is how a
    caller's LITERAL deliverable path -- c-12's hdrs = ["deliverable/ex00/
    ft_list.h"], a c_make anchor, a rush's main.c -- stops being a declared
    input that Bazel fails to find while analysing the package. A literal that
    reached `data` or `srcs` unfiltered took down every target naming it, and
    before --keep_going the whole module run with it; filtered, the targets that
    need the file fail as tests, and the files layer names it.

    A turn-in path whose name _safe() refuses is dropped the same way, whoever
    globbed it: see _SAFE_CHARS.
    """
    out = []
    for p in paths:
        if p.startswith(":") or p.startswith("//") or p.startswith("@") or not _in_zone(p):
            out.append(p)
        elif _safe(p) and native.glob([p], allow_empty = True):
            out.append(p)
    return out

def _student_bin(
        name,
        harness = None,
        srcs = None,
        hdrs = None,
        deps = None,
        includes = None,
        asan = False,
        diffio = False,
        archive = True,
        dir = None,
        makefile = None,
        make_data = None,
        includes_out = None,
        prototype = None,
        sources_out = None,
        linkopts = None,
        copts = None,
        tags = None):
    """THE one way to build a program from deliverable sources.

    Every binary a layer runs that holds a student's code is built here, through
    tools/student_build.bzl, and never by cc_binary or cc_library: a student's
    compile error, warning under -Werror, leftover main() or missing file then
    turns this program into a stand-in that prints the compiler's words and
    fails each test that runs it, instead of failing the BUILD (see
    tools/student_build.sh). The flags, the pinned toolchain and the way the
    student's files are linked are the ones a cc_binary had.

    WHAT DOES NOT COME THROUGH HERE, and why: the layers that compile a
    student's files INSIDE their runner, at test time -- compile, forbidden,
    symbols, prototype, the header shape (header_check.sh), asan_check, ilp32,
    allocfail, cycles and refcost. They are not build actions, so a file that
    does not compile is already that test's red, with the compiler's words,
    and never the build's. Each also compiles differently on purpose (both
    campus compilers, -m32 through the pinned zig, -O2, an allocator shim), so
    moving them here would put a test-time question into the build graph and
    buy nothing this change was for. Routing their compile LINES through one
    helper is a separate question (runner_lib.sh's).

    Args:
        name: the target, e.g. "ex03_bin".
        harness: the test's own sources and headers (a main()), always linked.
        srcs: the student's sources and headers, and any the grader supplies.
            Archived and linked after the harness, as a cc_library's were,
            unless archive = False.
        hdrs: more headers to stage (a provided one under tests/).
        deps: the exercise's own student_unit (its `:fn`), whose sources join
            the library and whose include directories follow this binary's
            own; a grader_library() the contract's `linked` names; or a
            cc_library of the harness's own, linked as a cc_binary would link
            it. Never another exercise's unit (see c_function).
        includes: package-relative include directories, first on the -I path.
        asan: build the ASan/UBSan twin (_ASAN_COPTS, _ASAN_LINKOPTS). Tagged
            manual, so it is built only when a test that runs it is.
        diffio: link //tools:diffio, the diff reader harnesses' helpers.
        archive: False links `srcs` directly, as a program exercise's are.
        dir: package-relative directory of the student's own sources; when none
            of `srcs` is under it, the stand-in says so in those words.
        makefile: the deliverable's Makefile (a package-relative path, found
            through _zone): take the sources from `make -Bn`. When it is not
            there, the program is a stand-in saying so -- unless `srcs` are
            given too: those are then built while the Makefile is missing
            or compiles nothing, and the moment it names a source it alone
            decides (tools/student_build.sh, UNTIL THE MAKEFILE IS WRITTEN;
            c_program's makefile = "once_written").
        make_data: the files to stage beside the Makefile.
        includes_out: with `makefile`, a file name to write the -I
            directories its recipes pass to, one per line: the include path
            of the compile and forbidden layers of the same turn-in
            (_compile_tests' inc_file), from the same `make -Bn`.
        prototype: REQUIRED with `harness`, refused without one. The test
            that holds the functions the harness calls to the signatures the
            subject fixes: a `_prototype` test of this package, as
            _prototype_test() returns its name; or why there is none, as a
            string that starts "none: " ("none: the subject fixes no
            prototype for ft_putchar"). A harness links a student's function
            the way the grader's main() does, and C links a mismatched
            signature without a word: the prototype layer is the only thing
            that sees one. It is required HERE, where every harness is
            built, and not in one helper: rush_variant built three harnesses
            and emitted no prototype layer at all (finding 142), and when
            the requirement moved into _output_fixture_binary, the diff,
            perf, memcheck and Rush 00's own programs still linked a harness
            without it. It is written as a tag (_HARNESS_PROTO_TAG), and
            c_levels()' audit fails a package whose harness names a test it
            lacks, or whose student_binary with a harness carries no tag.
        sources_out: with `makefile`, a file name to write the .c files its
            recipes compile to, one per line, from the turn-in directory
            ("unknown" when make could not plan the build): what the files
            layer reads to find a source the Makefile never builds
            (_built_manifest).
        linkopts: more link flags, after the sanitizer's: a program
            exercise's allocation-failure twin wraps malloc and free
            (c_program's `allocfail`), and the guarded-argv replay wraps
            main (c_argv_table).
        copts: more compile flags, after the sanitizer's, for every file
            compiled. Nothing passes any today: the guarded-argv replay
            renamed the student's main this way, and a main() renamed loses
            C's implicit return 0 (it links main wrapped instead).
        tags: more tags.
    """
    problem = _harness_prototype_problem(name, harness, prototype)
    if problem:
        fail(problem)
    copts = _COPTS + (_ASAN_COPTS if asan else []) + (copts or [])
    linkopts = (_ASAN_LINKOPTS if asan else []) + (linkopts or [])
    tags = (tags or []) + (["manual"] if asan else [])
    if harness:
        tags = tags + [_HARNESS_PROTO_TAG + ("none" if prototype.startswith("none: ") else prototype)]
    deps = (deps or []) + (["//tools:diffio"] if diffio else [])
    kw = {}
    if includes_out:
        if makefile == None:
            fail("_student_bin(%s): includes_out is the Makefile's -I list, and there is no makefile" % name)
        kw["includes_out"] = includes_out
    if sources_out:
        if makefile == None:
            fail("_student_bin(%s): sources_out is the Makefile's .c list, and there is no makefile" % name)
        kw["sources_out"] = sources_out
    if makefile != None:
        found = _zone([makefile])
        if found:
            kw["makefile"] = found[0]
            kw["make_data"] = _zone(make_data or [])
        else:
            kw["missing_makefile"] = makefile
    if not _is_student_bin_name(name):
        fail(("_student_bin(name = %r): a program built from a student's files " +
              "is named ending in one of %s, with a \"_\" and no \".\" in it, so " +
              "that _test() can tell it from its label alone, wherever it is " +
              "declared, and from a data file (_STUDENT_BIN_SUFFIXES).") %
             (name, ", ".join(_STUDENT_BIN_SUFFIXES)))
    student_binary(
        name = name,
        harness = harness or [],
        srcs = _zone(srcs or []),
        hdrs = _zone(hdrs or []),
        deps = deps,
        includes = includes or [],
        copts = copts,
        linkopts = linkopts,
        archive = archive,
        dir = dir or "",
        # A sanitizer's report names file:line only if the binary keeps its
        # debug info, and fastbuild links with -Wl,-S (--strip's default,
        # "sometimes"), which drops it whatever -g the compile had.
        keep_debug = asan,
        tags = tags,
        **kw
    )

def _student_lib(name, srcs, hdrs = None, includes = None, deps = None, tags = None):
    """An exercise's files as a unit other binaries link: what `:fn` names.

    The successor of the cc_library each c_function and rush macro declared --
    same sources, same headers, same include directories -- except that it
    builds nothing, so it cannot fail. The binaries that link it compile its
    sources themselves (_student_bin), each with its own flags: the plain and
    the ASan twin used to be two libraries.

    `deps` is for a unit of the SAME turn-in, and only the rush macros pass
    one: a rush variant's rectangle calls the team's ft_putchar.c, which sits
    beside it in the turn-in. No public macro takes it any more (see
    c_function): another exercise's files are never linked in.
    """
    student_unit(
        name = name,
        srcs = _zone(srcs),
        hdrs = _zone(hdrs or []),
        includes = includes or [],
        deps = deps or [],
        tags = tags or [],
    )

def student_lib(name, srcs, hdrs = None, includes = None):
    """A unit of a student's files for a layer to link, declared by hand.

    For the one place a module needs a unit no exercise macro declares: c-09
    ex00, whose functions are archived by the student's own script, so there is
    no c_function to declare `:ft_strcmp` for its c_diff. A module BUILD file
    must never declare a cc_library or cc_binary over deliverable sources
    (//tools:conventions refuses it): one that does not compile is a BUILD
    error, not a red test. This builds nothing, so it cannot fail; the
    binaries that link it compile it (see _student_bin).

    Args:
        name: the unit's name, as c_diff's `fn` names it.
        srcs: the sources, package-relative. Literal paths are fine: a file that
            is not there is dropped (_zone), and the programs that needed it are
            stand-ins that say what failed.
        hdrs: headers to stage beside them.
        includes: package-relative include directories.

    No `deps`: a unit holds one turn-in's files, and never links another
    exercise's (see c_function, where `deps` went and why).
    """
    _student_lib(
        name = name,
        srcs = srcs,
        hdrs = hdrs,
        includes = includes,
    )

def _stray_exercise(ex, contract, where):
    """The files test of a student's folder or generator no exercise of the contract has.

    `where` is "deliverable/exNN" (the folder, reported with every file in
    it) or "generators" (the generator exNN.sh alone). The test is exNN_files,
    under the files layer, so the exercise it seems to be has a suite with a
    red in it, and the audit finds a test for every exercise it was told
    about. Never a fail(): the folder is the student's.
    """
    if where == "generators":
        names = [ex + ".sh"]
    else:
        names = [
            f[len(where) + 1:]
            for f in native.glob([where + "/**"], exclude = _not_build_products(where), allow_empty = True)
            if "\n" not in f
        ]
    names_file(
        name = ex + "_files_names",
        names = names,
    )
    args = [
        "--label",
        native.package_name() + "/" + where,
        "--grader",
        contract["grader"],
        "--stray",
        ",".join(sorted(["ex" + n for n in contract["exercises"]])),
        "--actual-list",
        "$(rootpath :%s_files_names)" % ex,
    ]

    # No --strict: a folder of no exercise fails whatever the project's
    # `strict` says, which is about an exercise's own file list.
    _test(
        name = ex + "_files",
        srcs = ["//tools:files_test.sh"],
        args = args,
        data = [":%s_files_names" % ex],
        tags = ["files"],
    )

# THE TESTS OF A WHOLE MODULE, which belong to no exercise: {name: layer}.
# Everything else in a project is exNN_<what>. c_levels() emits these, and its
# audit lets exactly these names through (docs/reference.md, "Suites").
_MODULE_TESTS = {
    "deliverable_files": "files",
}

def _outside_exercises(contract):
    """The module's deliverable_files: every file of deliverable/ in no exercise's folder.

    What sits at the root of deliverable/, or in a top-level folder that is
    not named like an exercise (old/, ex5/, "ex05 copy/"), in a project whose
    subject gives each exercise a turn-in directory. deliverable/ is the
    Vogsphere repository's root, so all of it is pushed, and no exercise's
    files layer looked there: a stray at the root was not even an input of any
    test (finding 052). An exNN/ folder is left out -- its exercise's
    exNN_files reports it, or _stray_exercise's does for one the subject lacks
    -- and so are build products, which //tools:submit does not push. Not
    emitted where the project turns in at deliverable/ itself (BSQ, the Common
    Core): the whole tree is that exercise's, and its exNN_files walks it.
    """
    if [e for e in contract["exercises"].values() if e["dir"] == None]:
        return
    names = []
    for f in native.glob(["deliverable/**"], exclude = _not_build_products("deliverable"), allow_empty = True):
        rel = f[len("deliverable/"):]
        if "/" in rel and _is_ex(rel.split("/")[0]):
            continue
        if "\n" not in rel:
            names.append(rel)
    names_file(
        name = "deliverable_files_names",
        names = names,
    )
    _test(
        name = "deliverable_files",
        srcs = ["//tools:files_test.sh"],
        args = [
            "--label",
            native.package_name() + "/deliverable",
            "--outside",
            ",".join(sorted(["ex" + n for n in contract["exercises"]])),
            "--actual-list",
            "$(rootpath :deliverable_files_names)",
        ],
        data = [":deliverable_files_names"],
        tags = ["files"],
    )

def _header_norm_test(num):
    """exNN_norm_header: the Norm's two header rules norminette skips, for exercise `num`.

    Emitted by c_levels() for every exercise of the contract that turns in a
    header -- one its `files` names, or any its `files` and `optional` let lie
    there (_deliverable_hdrs) -- so a project gets it from its contract, with
    no call of its own: C 08's and Reloaded's header exercises, C 12 and
    C 13's ft_list.h and ft_btree.h, a rush's or a Makefile project's own
    headers, and the Common Core's (WP-89, findings 089 and 093).
    tools/header_norm.sh says what it checks and why each verdict is built
    rather than read; it sits at strict, on the norm layer's suffix
    _norm_header, because norminette is what a grader runs and it raises
    neither.

    No test where nothing is turned in that the contract does not require: an
    exercise with no header to read is not one this rule has anything to say
    about. A header the contract requires and the turn-in lacks is a NOT
    TURNED IN test, gated (a SKIP but under NO_SKIP=1), as the norm layer's
    Notice twin is: the files and norm layers say it is missing already.
    """
    ex = "ex" + num
    e = _entry(num, "turnin")
    named = [f for f in (e["files"] or []) if f.endswith(".h")]
    hdrs = _deliverable_hdrs(ex)
    if not hdrs and not named:
        return
    args = _pinned_cc_args()

    # Every turned-in header is READ, a subfolder's too, so none goes through
    # _inc_args(), which keeps one in a subfolder off the include path as the
    # grader's compile line does: that is the compile layers' question, and
    # tools/header_norm.sh says why its own path is generous.
    for h in hdrs:
        args += ["--header", "$(location %s)" % h]

    # What the turned-in headers may include besides each other: the
    # grader's. Their folders join the include path; they are never read.
    provided = _provided(num).hdrs
    for h in provided:
        args += ["--grader-hdr", "$(location %s)" % h]
    _test(
        name = ex + "_norm_header",
        srcs = ["//tools:header_norm.sh"],
        args = args,
        data = hdrs + provided + _PINNED_CC_DATA,
        tags = ["norm"],
        level = 2,
        turnin = hdrs,
        gated = True,
    )

def c_levels(name = None):
    """A module's suites, and the audit of the module as a whole.

    Args:
      name: unused. Bazel convention is that every macro takes a `name`, and
        buildifier's unnamed-macro check enforces it -- a student who writes
        their own macro should meet that rule here rather than be surprised
        by it later. Every target this emits is named by the ladder, by an
        exercise or by what it is (:manual), not by a caller.

    What it emits (docs/reference.md, "Suites"):

      :basic :strict :robust :complete  one level of the whole module, each
            level with every level below it. Which layer sits at which level
            is docs/reference.md's layer table, checked against _LAYER_LEVEL;
            it is not restated here, because every copy of it drifted.
      :exNN  every non-manual test of one exercise, whatever emitted it.
      :manual  every manual test of the module, and nothing else.
      exNN_files  the files layer of every exercise of the subject() contract
            (unless its `files` is None, or a macro emitted one already), and
            of every folder the student made that is no exercise of it.
      exNN_norm_header  the Norm's header rules norminette skips, for every
            exercise of the contract that turns in a header
            (_header_norm_test).
      deliverable_files  the rest of the pushed tree: every file at the root
            of deliverable/ or in a folder that is no exercise's, which fails
            (_outside_exercises; none where the project turns in at the root).

    Naming a single target still runs it regardless of level -- these are
    suites you ASK for, not a filter you have to escape. `--test_tag_filters`
    would have been the obvious mechanism and is the wrong one: it also
    filters explicitly-named targets, so `bazel test //mod:ex00_ilp32` under a
    basic filter reports "No test targets were found" instead of running the
    test you just asked for.

    IT NEEDS THE PROJECT'S SUBJECT CONTRACT, and fails without one, and it
    refuses a tests/exNN/ the contract does not list. Call it after the
    macros of the module: a shell exercise's own files layer must exist before
    it looks. Its AUDIT does not need that: a finalizer (_levels_audit) runs
    it once the whole BUILD file has been read, wherever c_levels() is in it,
    and fails the package's loading on any break of a module-wide rule --
    see _audit_problems for the list and why they are checked here.
    """
    contract = _contract("c_levels")

    # THE FILES LAYER, one per exercise, from the contract -- emitted here, from
    # the one macro every project calls, so no exercise can be without one and
    # no BUILD file writes a file list of its own. A shell exercise emits its
    # own (it runs the generator first), and an exercise whose contract gives
    # no file names (files = None) gets none. Everything else is declared
    # above this call, which is where every BUILD file has it.
    for num in sorted(contract["exercises"]):
        if contract["exercises"][num]["files"] == None:
            continue
        if native.existing_rule("ex%s_files" % num):
            continue
        c_files(num)

    # THE NORM'S HEADER RULES norminette skips -- protection from double
    # inclusions, and the prefix of a name defined inside a typedef -- for
    # every exercise that turns in a header, from the contract (see
    # _header_norm_test), so no BUILD file asks for it and none can forget.
    for num in sorted(contract["exercises"]):
        _header_norm_test(num)

    for name in _LEVEL_NAMES:
        native.test_suite(
            name = name,
            tags = ["lvl_" + name],
        )

    # ONE SUITE PER EXERCISE, so a whole exercise can be run in one command.
    #
    # Before these, you could run one LAYER of one exercise
    # (//c-piscine/c-piscine-c-05:ex00_output) or a whole module, and nothing
    # in between: `ex00_*` is not a Bazel target pattern, and
    # --test_tag_filters is the wrong tool for the reason spelled out above.
    #
    # The exercises are FOUND, never listed by hand, and from everywhere one
    # can show up (finding 074: C 06 ex00 has no tests/ folder, and had no
    # suite): the contract; tests/exNN/; and the student's own side, a
    # deliverable/exNN/ folder or a generators/exNN.sh -- names only, from a
    # glob, so nothing in them is read. deliverable/exNN/ is skipped where a
    # generator makes it (it is generated and gitignored), and everywhere in
    # a project that turns in at deliverable/ itself, whose subfolders are
    # its turn-in's own (its files layer reports an exNN/ there).
    seen = {}
    for f in native.glob(["tests/ex*/*"], allow_empty = True):
        parts = f.split("/")
        if len(parts) > 2:
            seen[parts[1]] = True

    # ONE SET OF EXERCISES. A tests/exNN/ with no contract entry is an
    # exercise whose turn-in nobody transcribed -- every layer of it would
    # guess -- so it does not load: tests/ is the harness's. The other way
    # round is legitimate (C 06 ex00's check needs no fixture file), and the
    # contract is where the exercise is found then.
    problem = _untranscribed_problem(contract, seen)
    if problem:
        fail(problem)
    for ex in ["ex" + n for n in contract["exercises"]]:
        seen[ex] = True

    # THE STUDENT'S SIDE never fails the loading of the package (no deliverable
    # can break the build graph): a folder or a generator for an exercise the
    # contract does not list gets a files test saying so, which fails
    # whatever the subject says about extra files: no exercise's file list
    # reaches a folder of no exercise, it is pushed with the rest, and no
    # exercise grades it. A folder not named exNN (ex5, "ex05 copy") is no
    # exercise and is not looked at here: the module's deliverable_files
    # reports it, with every file at the root.
    found = {}
    for f in native.glob(["generators/ex*.sh"], allow_empty = True):
        ex = f[len("generators/"):-len(".sh")]
        if _is_ex(ex):
            found[ex] = "generators"
    for ex, d in _student_folders(contract).items():
        if ex not in found:
            found[ex] = d
    for ex in sorted(found):
        if ex in seen:
            continue
        seen[ex] = True
        _stray_exercise(ex, contract, found[ex])
    _outside_exercises(contract)
    for ex in sorted(seen):
        native.test_suite(
            name = ex,
            tags = [ex],
        )

    # THE AUDIT AND :manual, once everything is declared (see _levels_audit).
    _levels_audit(
        name = "manual",
        exercises = sorted(seen),
        layouts = native.glob(["tests/layout/**"], allow_empty = True),
        clues = native.glob(["tests/**/clues*.tsv"], allow_empty = True),
        makefiles = sorted([
            "ex" + n
            for n, e in contract["exercises"].items()
            if "Makefile" in (e["files"] or [])
        ]),
        malloc = sorted([
            "ex" + n
            for n, e in contract["exercises"].items()
            if _memcheck_allowed(e)
        ]),
    )

    # EVERYTHING IN THIS MODULE THAT //tools:conventions READS, so the style
    # gate can be a TEST rather than something you have to remember to run.
    #
    # It is emitted here, from the one macro every module already calls, rather
    # than written into twenty BUILD files. conventions.sh's own header argued
    # against ever being an sh_test on exactly that ground -- "listing ~140
    # files there, and updating that list whenever a module gains a test, would
    # be a convention nobody keeps, which is the failure this script exists to
    # prevent". A glob is not a list, and a module that calls c_levels() gets
    # this without knowing it exists. What remains hand-written is one label per
    # MODULE in //tools/tests, and //tools:conventions refuses to run if any
    # module in submit.sh's table is missing from what it can see -- so the
    # drift that is still possible is the loud kind.
    native.filegroup(
        name = "conventions_srcs",
        srcs = native.glob(
            [
                "BUILD.bazel",
                # A .bzl file the BUILD file loads (Rush 00's team.bzl): its
                # comments ship as the BUILD file's do.
                "*.bzl",
                # The module's README and any note beside it: the level ladder
                # check reads them, and a README is where a new project's
                # author writes one.
                "*.md",
                "generators/*.sh",
                "tests/**/*.sh",
                # Every C file of the harness, not only the test_*.c mains:
                # the check that none defines a function the grader brings
                # (grader_lib.bzl); every differential harness (diff_*.c),
                # whose header's "Line:" paragraph is the diff layer's column
                # legend (the legend-shape check); and the escape check, which
                # reads the header a test program prints through (Rush 00's
                # rush_capture.h) and the c_diff harness a measuring macro
                # names.
                "tests/**/*.c",
                "tests/**/*.h",
                # clues*.tsv, not clues.tsv: a test outside the programs can
                # still name a hint file of its own (Rush 00's putchar test,
                # clues_putchar.tsv), and the first-red check reads them all.
                "tests/**/clues*.tsv",
                # A shell exercise's expected output, which the copy scan
                # compares with every other module's (it says so when a file
                # a shell_exercise call names is not in this list); and a
                # case's own expected file, whose labels a clues_*.tsv beside
                # it must name.
                "tests/**/*.txt",
                # A twin's pointer to the tests it reads (shell_exercise's
                # twin_of), which conventions checks against the call.
                "tests/**/README.md",
                # Everything else a case reads or expects, whose bytes are
                # the case: the check that a CR in one survives a commit
                # (.gitattributes) has to see them.
                "tests/**",
            ],
            allow_empty = True,
        ),
        visibility = ["//tools/tests:__pkg__"],
    )

    # EACH EXERCISE'S TURN-IN FOLDER, as these macros compute it
    # (turnin_dir), one "exNN FOLDER" line per exercise of the contract.
    # tools/first_red.sh runs on a log, outside Bazel, and reads the same
    # subject() from the text of this file; //tools/tests:macro_fixtures_test
    # holds its reading to these lines for every module, so a contract written
    # in a form it misreads is a red test rather than a written exercise
    # called "not written yet". //tools:conventions only asks that it find an
    # entry.
    names_file(
        name = "turnin_dirs",
        names = ["ex%s %s" % (n, turnin_dir(n)) for n in sorted(contract["exercises"])],
        visibility = ["//tools/tests:__pkg__"],
    )

# ---------------------------------------------------------------------------
# The pinned valgrind, as (args, data) for any layer that runs it.
#
# One definition rather than five call sites, because the flags and the data
# deps have to agree: a runner handed --valgrind-tools whose tree was not staged
# gets a path that resolves to nothing, and valgrind then either refuses to
# start or -- the failure this repo has been bitten by four times -- quietly
# picks up the box's copy, reports the pinned version and goes green.
#
# `tool` names ONE file inside valgrind's tool directory, and the runner derives
# $VALGRIND_LIB from it. That is not a roundabout way of passing a directory:
# $(location) on the :runtime filegroup refuses (many files), and
# $(location file)/.. walks through a file rather than naming its parent. The
# runner does readlink -f then dirname, which is the form that survives both a
# later `cd` and the runfiles tree's mix of real directories and symlinked
# files.
_VG_BIN = "@valgrind_ubuntu//:usr/bin/valgrind.bin"
_VG_MEMCHECK = "@valgrind_ubuntu//:usr/libexec/valgrind/memcheck-amd64-linux"
_VG_CALLGRIND = "@valgrind_ubuntu//:usr/libexec/valgrind/callgrind-amd64-linux"
_VG_ANNOTATE = "@valgrind_ubuntu//:usr/bin/callgrind_annotate"
_VG_RUNTIME = "@valgrind_ubuntu//:runtime"

def _valgrind_args(tool = _VG_MEMCHECK, annotate = False):
    """Flags pointing a runner at the pinned valgrind.

    Args:
        tool: the tool binary whose directory becomes $VALGRIND_LIB --
            memcheck for the leak layer, callgrind for the two cycles layers.
        annotate: also pass --callgrind-annotate, for the layers that parse a
            profile rather than only producing one.

    Returns:
        A list of arguments to append to the runner's args.
    """
    args = [
        "--valgrind",
        "$(location %s)" % _VG_BIN,
        "--valgrind-tools",
        "$(location %s)" % tool,
    ]
    if annotate:
        args += ["--callgrind-annotate", "$(location %s)" % _VG_ANNOTATE]
    return args

def _valgrind_data(tool = _VG_MEMCHECK, annotate = False):
    """The data deps matching _valgrind_args, including the whole tool tree.

    Args:
        tool: same file named in _valgrind_args, so $(location) can resolve it.
        annotate: stage callgrind_annotate too.

    Returns:
        A list of labels to append to the runner's data.
    """
    data = [_VG_BIN, tool, _VG_RUNTIME]
    if annotate:
        data.append(_VG_ANNOTATE)
    return data

def _norm_test(name, files, norm_flags = None, extra_tags = None, level = None):
    # `files` are the student's, as globs found them, so an empty list means
    # none was turned in: both targets become "not turned in" tests (see
    # _test's `turnin`) rather than norminette runs over nothing.
    # norm_flags injects extra `-R <rule>` tokens before the files, AFTER the
    # script's own -R CheckForbiddenSourceHeader. norminette keeps only the
    # last -R it is given, so a caller's -R replaces that one rather than
    # adding to it -- ["-R", "CheckDefine"] is how the c-08 headers get to
    # define function-like macros (ABS, EVEN), and the runner prints the rule
    # that took effect.
    # extra_tags is for exercises with optional parts (rush's bonus variants),
    # which pass ["manual"] to keep an unimplemented variant out of `//...`.
    # level raises this one above norm's level 1 -- used for files the student
    # neither wrote nor turns in, where a red is real but is OURS, not theirs.
    #
    # TWO TARGETS, one reading each. norminette prints "OK!" for a file whose
    # only findings are Notices and still exits 1 on them, and no subject says
    # which of the two a grader goes by. `name` holds the certain reading --
    # red on any file's Error!, a Notice only warned about -- at norm's own
    # level; `name`_notice holds the uncertain one, red on a Notice, raised to
    # strict, where a reading the subject leaves open belongs. Each is red for
    # one reason only, so a Norm Error never shows up twice.
    norm_flags = norm_flags or []
    args = norm_flags + ["$(location %s)" % f for f in files]
    _test(
        name = name,
        srcs = ["//tools:norminette_test.sh"],
        args = ["--norminette", "$(location //tools:norminette)"] + args,
        data = files + ["//tools:norminette"],
        tags = ["norm"] + (extra_tags or []),
        level = level,
        turnin = files,
    )
    _test(
        name = name + "_notice",
        srcs = ["//tools:norminette_test.sh"],
        args = ["--norminette", "$(location //tools:norminette)", "--notices-only"] + args,
        data = files + ["//tools:norminette"],
        tags = ["norm"] + (extra_tags or []),
        level = max(level or 0, 2),
        turnin = files,
        # The certain reading above already says the file is not there.
        gated = True,
    )

def _provided_names(provided_srcs):
    """The functions a grader-supplied source defines, by 42's convention.

    One function per file, named after it: tests/ft_putchar.c supplies
    ft_putchar. The forbidden and symbols layers use these names to tell a
    student who DEFINED a supplied function that the grader already does.
    """
    names = []
    for s in provided_srcs or []:
        base = s.split("/")[-1]
        if base.endswith(".c"):
            names.append(base[:-len(".c")])
    return names

def _forbidden_allowed_problem(name, allowed):
    """Why `allowed` cannot be a forbidden layer's allowlist, or None.

    [] is a subject's "Allowed functions: None" -- every call is the finding.
    None is a subject with no "Allowed functions" line at all, which forbids
    nothing, so it gets no forbidden layer: one built from it would authorise
    nothing and fail any call, a requirement the subject never wrote. Three
    call sites once passed `_allowed(num) or []` and did exactly that (V13), so
    the layer refuses None itself rather than trusting each caller's guard.

    Args:
        name: the forbidden test's name, for the sentence.
        allowed: the subject's list, or None.

    Returns:
        A sentence naming the problem, or None.
    """
    if allowed == None:
        return ("%s: the subject has no \"Allowed functions\" line (allowed = None), " +
                "and a forbidden layer would authorise nothing. Guard the call: " +
                "`if _allowed(num) != None:`, as every macro does.") % name
    return None

def _forbidden_test(name, srcs, allowed, hdrs = None, extra_tags = None, provided = None, turnin = None, inc_file = None):
    # turnin: the student files the layer reads; default `srcs`. c_header's
    # srcs is the harness's probe, and its turn-in is the header.
    # inc_file: the include directories a Makefile passes (see _compile_tests).
    # "-" sentinel: Bazel drops an empty-string arg, so an empty allowlist
    # ("only baseline builtins allowed") must be passed as a non-empty token.
    problem = _forbidden_allowed_problem(name, allowed)
    if problem:
        fail(problem)
    hdrs = hdrs or []
    allowed_csv = ",".join(allowed) if allowed else "-"
    args = _pinned_cc_args() + _pinned_nm_args() + ["--allowed", allowed_csv]
    for p in provided or []:
        args += ["--provided", p]
    args += _inc_args("--hdr", hdrs)
    if inc_file:
        args += ["--inc-file", "$(location %s)" % inc_file]
    for s in srcs:
        args += ["--src", "$(location %s)" % s]
    _test(
        name = name,
        srcs = ["//tools:forbidden_symbols.sh"],
        args = args,
        data = srcs + hdrs + _PINNED_CC_DATA + _PINNED_NM_DATA + ([inc_file] if inc_file else []),
        tags = ["forbidden"] + (extra_tags or []),
        turnin = srcs if turnin == None else turnin,
    )

# The 42 campus box compiles with clang-12 (its `cc`) and has gcc-10.5. Compile
# every C exercise under BOTH, with -Wall -Wextra -Werror, so a warning only one
# compiler emits still fails locally instead of surfacing on the Moulinette. A
# well-formed stub compiles cleanly, exactly like the norm layer.
# The two compilers every C exercise is checked under, because the Moulinette
# has both and their -Werror sets differ.
#
# clang is FETCHED -- campus's exact 12.0.1-19ubuntu3, pinned by sha256 in
# MODULE.bazel -- so this layer's verdict no longer depends on which box you sat
# at. That is the whole rule: a check whose answer changes with the machine is
# not a check. The libdirs go with it and are not optional; a 100 KB driver that
# cannot find libclang-cpp either fails to start or, far worse, loads the BOX's
# copy and quietly stops being the pinned compiler.
#
# gcc-10 is still the box's. There is no gcc in the LLVM packages and Ubuntu's
# gcc-10 is spread across cpp-10, gcc-10-base, libgcc-10-dev and the fixed
# headers -- a bigger assembly than this one, and the next item in TODO 14.
# The pinned diff, and the two runners that hand a unified diff straight to a
# student. Everything else here compares bytes itself -- the diff LAYER never
# shells out, despite the name -- so this is the whole surface.
_DIFF = "@diffutils_ubuntu//:usr/bin/diff"

# The pinned shellcheck, for the shell modules' norm layer. Same binary
# //tools:conventions uses. It is pinned for the same reason `diff` is: its
# version decides which warnings exist, so a host copy makes a student's verdict
# depend on which machine they sat at.
_SHELLCHECK = "@shellcheck_linux_x86_64//:shellcheck"

# The pinned make. Reached by the two scripts that drive a student Makefile --
# make_test.sh, which grades it, and student_build.sh, which asks it which
# files the program is made of (tools/student_build.bzl stages it).
_MAKE = "@make_ubuntu//:usr/bin/make"

# The pinned clang, for the four runners that COMPILE something themselves --
# forbidden, symbols, prototype and the header layer. Each shells out to a
# compiler and each defaulted to `cc` from PATH.
#
# WHAT THAT COST, measured: with a PATH holding 580 coreutils and no compiler,
# 116 forbidden + 102 symbols + 96 prototype + 7 header targets reported SKIP
# and went GREEN having compiled nothing -- 321 of them, with forbidden and
# prototype at LEVEL 1, inside the submit gate. A real red vanished with them:
# //c-piscine/c-piscine-rush-02:ex00_forbidden went FAIL -> PASS, hiding "CALLED BUT NOT
# AUTHORISED: printf".
#
# defs.bzl:435 already argues the rule these four were exempt from: "a check
# whose answer changes with the machine is not a check". The runners all
# accepted --cc already; nothing ever passed it.
#
# The libs travel with it. A fetched clang that cannot find libclang-cpp does
# not fail -- the loader falls back to this machine's copy and the layer reports
# on a compiler nobody pinned.
_PINNED_CC = "@clang_12_ubuntu//:usr/lib/llvm-12/bin/clang-12"
_PINNED_CC_LIBS = [
    "@clang_12_ubuntu//:usr/lib/llvm-12/lib/libclang-cpp.so.12",
    "@clang_12_ubuntu//:usr/lib/x86_64-linux-gnu/libLLVM-12.so.1",
]

def _pinned_cc_args():
    """--cc and its --cc-lib pair, for a runner that compiles something."""
    a = ["--cc", "$(location %s)" % _PINNED_CC]
    for lib in _PINNED_CC_LIBS:
        a += ["--cc-lib", "$(location %s)" % lib]
    return a

_PINNED_CC_DATA = [_PINNED_CC, "@clang_12_ubuntu//:runtime"] + _PINNED_CC_LIBS

# THE LINKER, for a runner that LINKS what it compiles at test time
# (asan_check.sh, allocfail_check.sh, cycles_check.sh, ref_compare.sh,
# header_check.sh, method_check.sh --expect). The clang package has no linker
# of its own, so a link by the pinned clang ran the box's /usr/bin/ld, and the
# first four did not even get the pinned clang: they took clang-12, cc or gcc
# from PATH (TO VERIFY V38; LD_DEBUG under C 07 ex00's asan and allocfail
# targets showed the box's libclang-cpp, gcc and /bin/ld). Bazel's own C
# toolchain links with these binutils (//tools/cc_toolchain); a runner reaches
# the frontend through the wrapper rl_ld_pin writes (tools/runner_lib.sh),
# which puts libbfd's and libctf's directory on the loader's path and proves
# the loader and the driver both took it.
_PINNED_LD = "@binutils_x86_64_linux_gnu//:usr/bin/x86_64-linux-gnu-ld.bfd"
_PINNED_LD_LIBS = [
    "@binutils_x86_64_linux_gnu//:usr/lib/x86_64-linux-gnu/libbfd-2.38-system.so",
]

def _pinned_ld_args():
    """--ld and its --ld-lib, for a runner that links what it compiles."""
    a = ["--ld", "$(location %s)" % _PINNED_LD]
    for lib in _PINNED_LD_LIBS:
        a += ["--ld-lib", "$(location %s)" % lib]
    return a

_PINNED_LD_DATA = [_PINNED_LD, "@binutils_x86_64_linux_gnu//:runtime"] + _PINNED_LD_LIBS

def _pinned_build_args():
    """The pinned clang, its libraries and its tree, and the pinned linker.

    For a runner that compiles AND links at test time and takes all three
    (rl_cc_pin's CC, LIBS and UNDER; rl_ld_pin's LD and LIBS).
    """
    return _pinned_cc_args() + ["--cc-under", "$(location %s)" % _PINNED_CC] + _pinned_ld_args()

_PINNED_BUILD_DATA = _PINNED_CC_DATA + _PINNED_LD_DATA

# THE RUNNERS THAT COMPILE AT TEST TIME, and when each links: "always", a
# flag whose presence makes the run do it, or "never". A runner listed here
# compiles with the --cc it is handed, and links with the --ld, and a test
# that hands it neither is refused while loading (pinned_cc_problem): one
# that forgot compiled with whatever the machine had, which is how asan_check
# and allocfail_check came to take clang-12 and cc from PATH while every
# other compile layer was handed the pinned clang (TO VERIFY V38).
# //tools:conventions holds this table to the runners: one that takes --cc is
# listed, and one listed as linking proves its linker with rl_ld_pin.
_PINNED_CC_RUNNERS = {
    "//tools:allocfail_check.sh": ("--src", "--src"),
    "//tools:asan_check.sh": ("always", "always"),
    "//tools:compile_check.sh": ("always", "never"),
    "//tools:cycles_check.sh": ("--harness", "--harness"),
    "//tools:forbidden_symbols.sh": ("always", "never"),
    "//tools:header_check.sh": ("always", "always"),
    "//tools:header_norm.sh": ("always", "never"),
    "//tools:method_check.sh": ("always", "--expect"),
    "//tools:prototype_check.sh": ("always", "never"),
    "//tools:ref_compare.sh": ("always", "always"),
    "//tools:symbols_test.sh": ("always", "never"),
}

def _pinned_when(when, args):
    """Whether a _PINNED_CC_RUNNERS condition holds for these args."""
    return when == "always" or (when != "never" and when in args)

def pinned_cc_problem(runner, args):
    """Why a test of `runner` with `args` would compile or link with the box's tools; None if not.

    A decision made while loading, so a function of its own that
    //tools/tests:starlark_unit calls both ways.

    Args:
      runner: the test's runner, its first src ("//tools:asan_check.sh").
      args: the test's args.

    Returns:
      None, or the reason as a sentence.
    """
    if runner not in _PINNED_CC_RUNNERS:
        return None
    compiles, links = _PINNED_CC_RUNNERS[runner]
    if _pinned_when(compiles, args) and "--cc" not in args:
        return ("%s compiles, and these args hand it no --cc: it would compile with " +
                "a compiler from the machine, whose warnings and errors are not " +
                "campus's (TO VERIFY V38). Add _pinned_cc_args() (or " +
                "_pinned_build_args()) to its args and their data.") % runner
    if _pinned_when(links, args) and "--ld" not in args:
        return ("%s links, and these args hand it no --ld: the pinned clang " +
                "package has no linker, so every link would run the machine's " +
                "/usr/bin/ld (TO VERIFY V38). Add _pinned_ld_args() to its args " +
                "and _PINNED_LD_DATA to its data.") % runner
    return None

# The pinned llvm-symbolizer, campus's 12.0.1-19ubuntu3 build, for every runner
# that shows a sanitizer's report: without it each frame is a bare offset into a
# binary in Bazel's cache (finding 051), and the sanitizer runtime would
# otherwise use whatever `llvm-symbolizer` a PATH search finds. Like clang it is
# a frontend that loads libLLVM by bare soname, so the runner is handed that
# library too and proves the loader took it (rl_sanitizers, tools/runner_lib.sh).
_SYMBOLIZER = "@clang_12_ubuntu//:usr/lib/llvm-12/bin/llvm-symbolizer"
_SYMBOLIZER_LIB = "@clang_12_ubuntu//:usr/lib/x86_64-linux-gnu/libLLVM-12.so.1"
_SYMBOLIZER_DATA = [_SYMBOLIZER, _SYMBOLIZER_LIB]

def _symbolizer_args():
    """--symbolizer and --symbolizer-lib, for a runner that shows a sanitizer's report."""
    return [
        "--symbolizer",
        "$(location %s)" % _SYMBOLIZER,
        "--symbolizer-lib",
        "$(location %s)" % _SYMBOLIZER_LIB,
    ]

# THE RUNNERS THAT SHOW A SANITIZER'S REPORT, and the flag that makes one do
# it (None: every run does). Each macro used to add _symbolizer_args() by
# hand, and one that forgot handed the runner no symbolizer: rl_sanitizers
# then sets symbolize=0, and every frame of the report is a bare offset into a
# binary in Bazel's cache -- finding 051 again, silently. _test() refuses such
# a test while loading (symbolizer_problem), whatever wrote it: a macro, or a
# hand_test in a BUILD file. //tools:conventions holds this table to the
# runners: one that hands rl_sanitizers a symbolizer is listed here, and one
# listed here hands it one. perf_test.sh is not listed: its sanitizer run is a
# gate whose report is never shown.
_SYMBOLIZER_RUNNERS = {
    "//tools:argv_check.sh": "--sanitized",
    "//tools:argv_table.sh": "--memory-only",
    "//tools:asan_check.sh": None,
    "//tools:asan_run.sh": None,
    "//tools:bsq_check.sh": "--sanitized",
    "//tools:file_check.sh": "--sanitized",
    "//tools:rush01_check.sh": "--sanitized",
    "//tools:rush02_check.sh": "--sanitized",
    "//tools:rust_diff.sh": "--crash-only",
}

def symbolizer_problem(runner, args):
    """Why a test of `runner` with `args` would show an unsymbolised report; None if not.

    A decision made while loading, so a function of its own that
    //tools/tests:starlark_unit calls both ways.

    Args:
      runner: the test's runner, its first src ("//tools:asan_run.sh").
      args: the test's args.

    Returns:
      None, or the reason as a sentence.
    """
    if runner not in _SYMBOLIZER_RUNNERS:
        return None
    flag = _SYMBOLIZER_RUNNERS[runner]
    if flag != None and flag not in args:
        return None
    if "--symbolizer" in args and "--symbolizer-lib" in args:
        return None
    return ("%s%s shows a sanitizer's report, and these args hand it no " +
            "--symbolizer and --symbolizer-lib: every frame would be a bare offset " +
            "into a binary in Bazel's cache (finding 051). Add _symbolizer_args() " +
            "to its args and _SYMBOLIZER_DATA to its data.") % (
        runner,
        (" " + flag) if flag else "",
    )

# THE SAME PROBLEM, ONE PACKAGE OVER, and it went unnoticed for longer because
# nm answers `--version` correctly either way.
#
# binutils ships FRONTENDS. `readelf -d` on the fetched x86_64-linux-gnu-nm: no
# RPATH, no RUNPATH, `NEEDED libbfd-2.38-system.so` -- and ldd resolved that to
# /lib/x86_64-linux-gnu/. So 44 KB was pinned and the 1.5 MB doing the work was
# the box's, while the tool went on printing "GNU nm (GNU Binutils for Ubuntu)
# 2.38" out of its own .rodata and tools/pins.tsv read green.
#
# Three layers read this tool's output to decide whether a deliverable exports
# something it should not, calls a function the subject forbids, or built the
# archive c-09 asks for.
#
# Same shape as the clang pair above, and for the same reason: the library has
# to be fetched AND has to be on the loader's path, so the runners take
# --nm-lib and export LD_LIBRARY_PATH. They also verify the resolution
# transitively, because the failure being guarded against is precisely one
# where the right file is exec'd and the wrong code runs.
_PINNED_NM = "@binutils_x86_64_linux_gnu//:usr/bin/x86_64-linux-gnu-nm"
_PINNED_NM_LIBS = [
    "@binutils_x86_64_linux_gnu//:usr/lib/x86_64-linux-gnu/libbfd-2.38-system.so",
]

def _pinned_nm_args():
    """--nm and its --nm-lib, for a runner that reads a symbol table."""
    a = ["--nm", "$(location %s)" % _PINNED_NM]
    for lib in _PINNED_NM_LIBS:
        a += ["--nm-lib", "$(location %s)" % lib]
    return a

_PINNED_NM_DATA = [_PINNED_NM, "@binutils_x86_64_linux_gnu//:runtime"] + _PINNED_NM_LIBS

_CAMPUS_CCS = [
    {
        "label": "clang",
        "cc": "$(location @clang_12_ubuntu//:usr/lib/llvm-12/bin/clang-12)",
        "data": [
            "@clang_12_ubuntu//:usr/lib/llvm-12/bin/clang-12",
            "@clang_12_ubuntu//:runtime",
        ],
        # The libraries by name, not their directories: Bazel expands
        # $(location) to a FILE, and there is no dirname in Starlark. The
        # runner takes each one's directory. Two of them because the packages
        # put them in two places -- the front end beside the driver, the back
        # end in the multiarch library dir.
        "libs": [
            "@clang_12_ubuntu//:usr/lib/llvm-12/lib/libclang-cpp.so.12",
            "@clang_12_ubuntu//:usr/lib/x86_64-linux-gnu/libLLVM-12.so.1",
        ],
        "under": "@clang_12_ubuntu//:usr/lib/llvm-12/bin/clang-12",
        # None: clang assembles internally, so there is no subprogram to point
        # at and -print-prog-name=as would answer "as" whatever we passed.
        "progs": "",
    },
    {
        "label": "gcc",
        "cc": "$(location @gcc_10_ubuntu//:usr/bin/x86_64-linux-gnu-gcc-10)",
        "data": [
            "@gcc_10_ubuntu//:runtime",
            "@gcc_10_ubuntu//:usr/bin/x86_64-linux-gnu-gcc-10",
        ],
        # No libs: the driver links against nothing unusual, and what cc1 needs
        # (libisl, libmpc, libmpfr, libgmp) are leaf libraries taken from the
        # box, the same trade clang's libtinfo and libedit get. `under` is what
        # matters here instead -- gcc locates cc1 by walking up from its own
        # path, so an unstaged tree means the box's cc1 with no diagnostic.
        "libs": [],
        "under": "@gcc_10_ubuntu//:usr/bin/x86_64-linux-gnu-gcc-10",
        # gcc, unlike clang, shells out to an assembler. binutils is already
        # pinned for nm, and -B makes gcc take its target-prefixed `as` from
        # there instead of the machine's.
        "progs": "@binutils_x86_64_linux_gnu//:usr/bin/x86_64-linux-gnu-as",
    },
]

def _symbols_test(name, srcs, exports, hdrs = None, extra_tags = None):
    """Exactly `exports` may be visible to the linker; every helper is static."""
    hdrs = hdrs or []
    args = _pinned_cc_args() + _pinned_nm_args() + ["--expect", ",".join(exports)]
    for s in srcs:
        args += ["--src", "$(location %s)" % s]
    args += _inc_args("--inc", hdrs)
    _test(
        name = name,
        srcs = ["//tools:symbols_test.sh"],
        args = args,
        data = srcs + hdrs + _PINNED_CC_DATA + _PINNED_NM_DATA,
        tags = ["symbols"] + (extra_tags or []),
        turnin = srcs,
    )

def _grader_hdr_args(grader_hdrs):
    """A runner's --grader-hdr for each header the grader brings, and --readme for the project's page.

    compile_check.sh and prototype_check.sh name such a header when a compile
    fails, with the -I a compile by hand needs (rl_grader_hdrs, finding 091):
    it lives under the project's tests/, where nobody looks for a file the
    subject says is provided. The project's README.md, where it has one, is
    named with it -- as text, never a dependency.
    """
    args = []
    for h in grader_hdrs or []:
        args += ["--grader-hdr", "$(location %s)" % h]
    if args and native.glob(["README.md"], allow_empty = True):
        pkg = native.package_name()
        args += ["--readme", pkg + "/README.md" if pkg else "README.md"]
    return args

def _compile_tests(ex, srcs, hdrs = None, extra_tags = None, turnin = None, inc_file = None, grader_hdrs = None):
    # turnin: the student files these compiles read; default `srcs`. c_header
    # compiles the harness's mains against a turned-in header, which is its
    # turn-in.
    #
    # THE INCLUDE PATH IS THE GRADER'S (see _inc_args): each source's own
    # folder, the headers beside the sources and the grader's -- and, for a
    # Makefile project, `inc_file`: the -I directories its recipes pass, as
    # `make -Bn` reported them to the build of its program (_student_bin's
    # includes_out). A header in a subfolder is staged, and on no path by
    # itself, so a turn-in the grader cannot compile does not pass here.
    hdrs = hdrs or []
    turnin = srcs if turnin == None else turnin
    common = []
    for s in srcs:
        common += ["--src", "$(location %s)" % s]
    common += _inc_args("--hdr", hdrs, staged = "--staged-hdr")
    common += _grader_hdr_args(grader_hdrs)
    if inc_file:
        common += ["--inc-file", "$(location %s)" % inc_file]
    for spec in _CAMPUS_CCS:
        args = ["--cc", spec["cc"]]
        for lib in spec["libs"]:
            args += ["--cc-lib", "$(location %s)" % lib]
        if spec["under"]:
            args += ["--cc-under", "$(location %s)" % spec["under"]]
        if spec["progs"]:
            args += ["--cc-progs", "$(location %s)" % spec["progs"]]
        _test(
            name = "%s_compile_%s" % (ex, spec["label"]),
            srcs = ["//tools:compile_check.sh"],
            args = args + common,
            data = srcs + hdrs + spec["data"] + spec["libs"] +
                   ([spec["progs"]] if spec["progs"] else []) +
                   ([inc_file] if inc_file else []),
            tags = ["compile"] + (extra_tags or []),
            turnin = turnin,
        )

# THE KEYS OF ONE CASE DICT, per shape, declared once and checked: a key
# outside its shape's set fails while loading, naming the case, instead of
# doing nothing. Before this, each macro's docstring said "an unrecognised key
# is silently ignored", and a key that worked in one macro was copied to its
# sibling where it did nothing -- `level` existed for c_header's cases and not
# for c_program's, so a program case the subject leaves open could not sit at
# strict and was left out instead (findings 115, 117, 123, 169). c_function's
# own case is its parameters; its `readings` are case dicts of their own shape.
#
# "exit", "exit_quote" and "invalid_input" place a case's exit status by the
# Run contract (docs/reference.md; _case_exit and _header_exit_error say how).
# A misspelling of one is the costliest kind: "invalid_inputs" for
# "invalid_input" quietly produced a robust _exit twin expecting 0 on an error
# input, whose failure told the student that 0 is right for a run that failed.
# So an unknown key close to a real one is named as the one it was meant to be.
_CASE_KEYS = {
    "header": ["args", "clues", "exit", "exit_quote", "labeled", "level", "main", "name", "stdin"],
    "program": ["args", "argv_file", "clues", "cwd_files", "exit", "exit_quote", "fixtures", "invalid_input", "labeled", "level", "missing_file", "name", "sanitize", "stdin", "stream", "valgrind"],
    "reading": ["clues", "labeled", "level", "main", "name"],
}

# The keys a case of a shape cannot do without. A reading (c_function's
# `readings`) is a harness of its own, named, and never at basic: basic holds
# what every reading agrees on (D3).
_CASE_REQUIRED = {
    "reading": ["level", "main", "name"],
}

# WHAT A CASE COMPARES ITS RUN WITH -- its kind, exactly one of:
#   "expected": FILE     the output, byte for byte (under tests/exNN/)
#   "any_of": [FILE...]  one of several outputs, where the subject leaves the
#                        reading open and every reading is bounded (finding
#                        159: '0042' prints the number or Error, never
#                        "zero forty-two"); the report compares with the first
#   "survive": True      no output at all: the run ends by itself, killed by
#                        no signal, in time, without runaway output -- what
#                        every reading of an open case agrees on
_CASE_KINDS = ["any_of", "expected", "survive"]

# THE KEYS THAT SHAPE THE RUN ITSELF, beyond `args` and `stdin`. Each reaches
# every arm of the case -- output, its exit twin, asan, valgrind and the
# valgrind arm's gate -- because a case must run the same thing in each: a
# key only one runner honoured would test one program there and another
# everywhere else. So neither was taken until all three runners
# (diff_output.sh, asan_run.sh, valgrind_test.sh) could.
#
#   "argv_file": LABEL   more arguments, one per line of the file, after
#                        "args": an empty line is an empty argument. Bazel
#                        drops "" from `args` and splits on spaces, so
#                        `./rush-02 ref.dict ""` could not be a case
#                        (finding 157), nor could Rush 01's clue string
#                        without quotes embedded in it.
#   "cwd_files": {LABEL: NAME}  run the program as ./<its name> -- c_program's
#                        `name`, the subject's executable name -- from a
#                        folder holding only a copy of it and a copy of each
#                        LABEL as NAME. The subject's own transcript runs
#                        `./rush-02 42` beside numbers.dict (finding 162).
#                        Its "args" then name the staged files by NAME: a
#                        $(location) path does not resolve from that folder,
#                        and is refused.

# The keys that shape a comparison, which a survive case does not make.
_CASE_COMPARING = ["labeled", "sanitize", "stream"]

def _case_problem(c, shape, program = None):
    """What is wrong with one case dict of `shape`, as a message; None if nothing.

    A value before it is a fail(), like the contract checks, so the fixtures
    can feed it broken cases (contract_problem("case", ...)). `program` is
    c_program's `name`, the file a "cwd_files" case runs the program as, so
    no staged file may take it; None where there is none to check against.
    """
    if type(c) != "dict":
        return "a case is a dict, not a %s" % type(c)
    keys = _CASE_KEYS[shape]
    for k in sorted(c):
        if k not in keys and k not in _CASE_KINDS:
            near = [n for n in keys + _CASE_KINDS if _key_stem(n) == _key_stem(k)]
            if near:
                return ("%r is not a key of a %s case: did you mean %r? An unknown key " +
                        "used to be ignored in silence.") % (k, shape, near[0])
            return ("%r is not a key of a %s case. Its keys: %s; and one of %s." %
                    (k, shape, ", ".join(keys), ", ".join(_CASE_KINDS)))
    for k in _CASE_REQUIRED.get(shape, []):
        if k not in c:
            return "a %s case needs %r: its keys are %s, and %s are required." % (
                shape,
                k,
                ", ".join(keys),
                ", ".join(_CASE_REQUIRED[shape]),
            )
    if "name" in c and (type(c["name"]) != "string" or not c["name"] or
                        " " in c["name"] or "\t" in c["name"]):
        return ("\"name\" is one word: it becomes part of a target name, and a " +
                "space there fails at run time as \"command not found\".")
    kinds = [k for k in _CASE_KINDS if k in c]
    if len(kinds) != 1:
        return ("a case compares its run one way: exactly one of %s, and it has %s." %
                (", ".join(_CASE_KINDS), ", ".join(kinds) or "none"))
    if "expected" in c and type(c["expected"]) != "string":
        return "\"expected\" is one file name under tests/exNN/; for several, \"any_of\"."
    if "any_of" in c:
        a = c["any_of"]
        if type(a) != "list" or len(a) < 2 or [f for f in a if type(f) != "string"]:
            return "\"any_of\" is a list of two or more file names under tests/exNN/."
    if "survive" in c:
        if c["survive"] != True:
            return "\"survive\" is True or absent."
        for k in _CASE_COMPARING:
            if k in c:
                return "%r shapes a comparison, and a survive case compares no output." % k
    if "level" in c and (type(c["level"]) != "int" or c["level"] < 2 or c["level"] > len(_LEVEL_NAMES)):
        return ("\"level\" raises a case to %s: 2 to %d. A case at basic needs none." %
                (", ".join(_LEVEL_NAMES[1:]), len(_LEVEL_NAMES)))
    # "valgrind" is the label a clues.tsv row takes to fire in the memory arms
    # (valgrind_test.sh hands its runner the case's name AND "valgrind" as
    # what failed), so a case of that name would take every such row into its
    # output test, and its own rows into every other case's memory arm.
    if shape == "program" and c.get("name") == "valgrind":
        return ("a case is not named \"valgrind\": a clues.tsv row keyed to " +
                "\"valgrind\" fires in every case's memory arm, so its rows would " +
                "fire there too. Name the case after the input it runs.")
    if "exit" in c and (type(c["exit"]) != "int" or c["exit"] < 0 or c["exit"] > 255):
        return "\"exit\" is a status, as an int from 0 to 255."
    if "exit_quote" in c and type(c["exit_quote"]) != "string":
        return ("\"exit_quote\" is the subject's sentence, as a string (an apostrophe " +
                "or a '$' is fine: _exit_flags quotes it, shell_word).")
    if "exit_quote" in c and "exit" not in c:
        return ("\"exit_quote\" is the subject's sentence naming the status in " +
                "\"exit\", and this case has no \"exit\".")

    # A quoted status sits at one of two levels, each with its own wording in
    # the runner (_exit_source): basic, where the sentence names the status,
    # and strict, where it is only READ as naming it -- the Run contract's row
    # for a sentence the subject leaves ambiguous. A quote raised to robust or
    # complete would be reported as "checked at strict" from a level that is
    # not, and a status a sentence names outright is never raised.
    if "exit_quote" in c and c.get("level") not in (None, 2):
        return ("\"exit_quote\" with \"level\": %r. A status the subject's sentence " +
                "names is compared at basic (no \"level\"); one the sentence is only " +
                "read as naming, at strict (\"level\": 2). No other level takes a " +
                "quote: a status that is this repo's rule has none (docs/reference.md, " +
                "\"Run contract\").") % c.get("level")
    if "invalid_input" in c and type(c["invalid_input"]) != "bool":
        return "\"invalid_input\" is True or False."
    for k in ["args", "fixtures"]:
        if k in c and (type(c[k]) != "list" or [a for a in c[k] if type(a) != "string"]):
            return "%r is a list of strings." % k

    # AN ARGUMENT BAZEL DOES NOT HAND OVER WHOLE. A test's `args` are
    # tokenised as a shell would tokenise them: a blank splits one, a quote or
    # a backslash is read as shell syntax, and "" is dropped. Rush 01's clue
    # string was held together by quotes embedded in a Starlark string, with
    # a target of its own to prove Bazel kept them (ex00_argv_guard); an
    # argument file says it with no shell in between. A $(location ...) is
    # Bazel's own, and expands to one word.
    for a in c.get("args", []):
        bare = a
        for _ in range(len(a)):
            at = bare.find("$(")
            end = bare.find(")", at) if at >= 0 else -1
            if end < 0:
                break
            bare = bare[:at] + bare[end + 1:]
        if not a or [ch for ch in [" ", "\t", "\n", "'", "\"", "\\"] if ch in bare]:
            return (("\"args\" holds %r, which Bazel does not hand the program as one " +
                     "argument: it tokenises `args` as a shell would, splitting at a " +
                     "blank, reading a quote or a backslash, dropping an empty one. " +
                     "Put the run's arguments in \"argv_file\", one per line.") % a)
    if "argv_file" in c and (type(c["argv_file"]) != "string" or not c["argv_file"]):
        return ("\"argv_file\" is the label of a file under the package, one argument " +
                "per line.")
    if "cwd_files" in c:
        cw = c["cwd_files"]
        if type(cw) != "dict" or not cw:
            return ("\"cwd_files\" is {label: name}: the files the run folder holds " +
                    "beside the program, each under the name the program opens it by.")
        names = {}
        for src, dest in cw.items():
            if type(src) != "string" or type(dest) != "string" or not src or not dest:
                return "\"cwd_files\" maps a label to a name, both strings."
            # Every part of the path a name: "." would copy the file in under
            # its own name, not this one, and "" is a leading, doubled or
            # trailing slash.
            if ([p for p in dest.split("/") if p in ["", ".", ".."]] or "=" in dest or
                [ch for ch in [" ", "\t", "'", "\""] if ch in dest]):
                return ("\"cwd_files\": %r is not a name inside the run folder (no " +
                        "leading or trailing /, no . or .. part, no =, no space or " +
                        "quote: Bazel splits `args` on them).") % dest
            # The folder holds the program under its own name, ./<name>: a file
            # staged there too, or under a folder of that name, was refused only
            # when the case ran (runner_lib.sh's rl_rundir, exit 2).
            if program and (dest == program or dest.startswith(program + "/")):
                return ("\"cwd_files\": %r is where the run folder holds the program " +
                        "itself, which runs as ./%s: stage the file under the name " +
                        "the program opens it by.") % (dest, program)
            if dest in names:
                return "\"cwd_files\": two files are staged as %r." % dest
            names[dest] = True
        for a in c.get("args", []):
            if "$(location" in a or "$(rootpath" in a or "$(execpath" in a:
                return (("\"args\" holds %r, a path from where Bazel runs the test, " +
                         "and a \"cwd_files\" case runs from its own folder, where " +
                         "that path is not. Stage the file in \"cwd_files\" and name " +
                         "it by its name there.") % a)
    if "missing_file" in c:
        return _missing_file_key_problem(c)
    return None

def _missing_file_key_problem(c):
    """Why a case's "missing_file" names no operand that could be one; None if it does.

    The key says this run hands the program a name that will not open, and
    names it. So it is one of the case's "args", word for word; it is not a
    fixture ($(location ...) names a file that is there), not an option or
    "-" (which a tool reads as standard input), and not "." or ".." (which
    are there: a directory). Whether it is absent where the program runs is
    asked at run time (diff_output.sh --absent).
    """
    m = c["missing_file"]
    if type(m) != "string" or not m:
        return "\"missing_file\" is the operand, from \"args\", that names no file."
    if m not in c.get("args", []):
        return ("\"missing_file\" is %r, and the case's \"args\" do not hold it: it " +
                "names the operand that will not open, word for word.") % m
    if "$(" in m:
        return ("\"missing_file\" is %r, a fixture Bazel stages: a file that is " +
                "there. Name an operand no file has, as no_such_file_exNN.") % m
    if m.startswith("-") or m in (".", ".."):
        return ("\"missing_file\" is %r, which a program reads as an option, as " +
                "standard input or as a directory that is there. Name an operand " +
                "no file has, as no_such_file_exNN.") % m
    cw = c.get("cwd_files")
    if type(cw) == "dict" and [d for d in cw.values() if d == m or (type(d) == "string" and d.startswith(m + "/"))]:
        return ("\"missing_file\" is %r, and \"cwd_files\" stages a file there: the run " +
                "folder holds it. Name an operand no file has, as no_such_file_exNN.") % m
    return None

def _case(c, shape, where, program = None):
    """One case dict of `shape`, checked: fail()s naming `where` and the case.

    `program` is c_program's `name` (see _case_problem). Returns a struct:
    `name` (default "run"), `expected` (the file names to compare with, the
    first one reported; empty for a survive case), `survive`, `level` (None
    at the layer's own).
    """
    problem = _case_problem(c, shape, program)
    if problem:
        name = c.get("name", "run") if type(c) == "dict" else "?"
        fail("%s, case %r: %s" % (where, name, problem))
    return struct(
        name = c.get("name", "run"),
        expected = [c["expected"]] if "expected" in c else c.get("any_of", []),
        survive = c.get("survive", False),
        level = c.get("level"),
    )

def _raise(layer, level):
    """A case's level for one of its arms: `level` where it is above the arm's layer, else None.

    A case's level is a floor for every arm it emits: a case the subject
    leaves open is no more certain under a sanitizer. An arm whose layer
    already sits at or above it stays where it is.
    """
    if level != None and level > _LAYER_LEVEL[layer]:
        return level
    return None

def _expected_args(ex, k, flag = "--expected", alt = "--expected-alt", survive = "--survive"):
    """A checked case's comparison, as a runner's flags and the files they need."""
    if k.survive:
        return ([survive] if survive else []), []
    files = ["tests/%s/%s" % (ex, f) for f in k.expected]
    args = [flag, "$(location %s)" % files[0]]
    for f in files[1:]:
        args += [alt, "$(location %s)" % f]
    return args, files

def _case_stem(ex, cases, cname):
    """Target stem for one argv scenario: `exNN`, or `exNN_<case>` when several.

    A lone scenario takes the plain name every other exercise in the repo uses.
    The infix earns its place only when there is more than one scenario to tell
    apart -- c-10 ex03 has 11 and c-11 ex05 has 17, where naming them is the
    whole point. Before this rule the only infixed-but-single targets anywhere
    were c-08's ex00_compile_output, ex02_run_output and ex03_compile_output,
    which made the one module a student meets a header exercise in look as
    though it followed different conventions from the rest of the repo.

    It lives here because THREE loops emit per-case targets and they have to
    agree: _emit_cases() runs a prebuilt program through diff_output.sh,
    c_program() emits its own asan targets beside it, and c_header() builds no
    program on purpose (see its comment) and compiles inside header_check.sh.
    Three runners, one naming rule -- and the naming is exactly what drifted
    while each kept its own copy of it.
    """
    if len(cases) == 1:
        return ex

    # A case name becomes part of a TARGET name, so it has to be one word. A
    # space produces `//pkg:ex00_a one-cell map_output`, which Bazel accepts at
    # analysis and which then fails at run time with "Exit 127: command not
    # found" -- the test-setup script splits on the space and tries to execute
    # the first half. That is a wrong-looking failure a long way from its cause,
    # so it is caught here instead, where the name is written.
    if " " in cname or "\t" in cname:
        fail(("c_program/%s: case name %r must be one word -- it becomes part " +
              "of a target name, and a space there fails at run time as " +
              "\"command not found\" rather than at analysis.") % (ex, cname))
    return "%s_%s" % (ex, cname)

def _key_stem(k):
    """A key with case, '-', '_' and a plural 's' taken away, for "did you mean"."""
    k = k.lower().replace("-", "").replace("_", "")
    return k[:-1] if k.endswith("s") else k

def _missing_file_problem(ex, allowed, cases, why):
    """None, or why a c_program that may open files has no case naming one that will not open.

    `allowed` is the exercise's forbidden-layer list (None: no list), `cases`
    its case dicts (None: its runs are driven elsewhere, as c_argv_table
    does), `why` its no_missing_file_case sentence.

    THE PATH ITSELF, NOT ANY ERROR. A program that opens files meets a name
    that will not open, and a case list written from a subject's example
    transcript never hands it one. This guard first asked only for SOME error
    case, and that let the shape through: BSQ held five invalid maps and Rush
    02 four broken dictionaries, every one a file that opens, and neither
    list named a file that does not exist (finding 110; review of WP-50). A
    name a case marks "missing_file" is that path, said, and checked: it is
    one of the case's operands (_missing_file_key_problem) and nothing by
    that name is there when the program runs (diff_output.sh --absent).
    """
    if why != None and (type(why) != "string" or not why.strip()):
        return "c_program(%s): no_missing_file_case is a sentence saying why." % ex
    if cases == None or not allowed or "open" not in allowed:
        if why != None:
            return (("c_program(%s): no_missing_file_case says why no case names a " +
                     "file that will not open, and nothing asks for one: the contract " +
                     "does not allow open%s. Drop the sentence.") %
                    (ex, "" if cases != None else ", or the runs are driven elsewhere"))
        return None
    named = [c.get("name", "run") for c in cases if type(c) == "dict" and "missing_file" in c]
    if named and why != None:
        return (("c_program(%s): no_missing_file_case says no case names a file that " +
                 "will not open, and %s does. Drop the sentence: a reason that is no " +
                 "longer true is worse than none.") % (ex, ", ".join(named)))
    if not named and why == None:
        return (("c_program(%s): the contract allows open, and no case names a file " +
                 "that will not open. A program that opens files meets one, and a case " +
                 "list copied from the subject's transcript never hands it one; a case " +
                 "about a file's CONTENT is not that path. Add a case whose \"args\" " +
                 "hold a name no file has (no_such_file_%s), say so in " +
                 "\"missing_file\", and judge it where the Run contract puts it " +
                 "(docs/reference.md, \"A program that reads files\"); or say why " +
                 "there is none in no_missing_file_case.") % (ex, ex))
    return None

def _makefile_problem(ex, makefile, files):
    """Why c_program may not build exercise `ex` without its Makefile; None if it may.

    A subject() contract that has the exercise turn in a Makefile says the
    Makefile is how the program is built. makefile = False builds every .c
    of the folder with no -I instead: a header kept in a subfolder the
    Makefile reaches with -I does not compile, and a .c it never compiles is
    linked. C 10, C 11 ex05 and Reloaded ex27 were each declared that way and
    each fixed by hand (W5-F); the next Makefile project is refused here.
    """
    if makefile == False and "Makefile" in (files or []):
        return ("c_program(%s): makefile = False, and the subject() contract has %s " +
                "turn in a Makefile, which is how the subject builds the program: " +
                "built from every .c of the folder with no -I, a header in a " +
                "subfolder the Makefile reaches with -I does not compile, and a .c " +
                "it never compiles is linked. Pass makefile = True, or " +
                "\"once_written\" to build the folder's sources until the Makefile " +
                "compiles something (C 10's programs).") % (ex, ex)
    return None

def _model_problem(ex, model, cases):
    """None, or why a c_program's `model` cannot be held to its cases' files.

    `model` is the //oracle command a case's "args" follow, as words; each
    case with one expected file then gets exNN[_case]_model (_emit_model).
    THE FILES A MODEL MADE DRIFT FROM IT IN SILENCE otherwise: C 10's were made
    once by `oracle c10_run` and checked against the tools then, and nothing
    re-ran it, so a later fix to the model, or a fixture edited by hand,
    would first show as a correct program going red (review of WP-50).
    """
    if model == None:
        return None
    if (type(model) != "list" or not model or
        [w for w in model if type(w) != "string" or not w or " " in w or "$" in w or "'" in w]):
        return (("c_program(%s): model is the //oracle command whose answers the " +
                 "cases' expected files are, as a list of words with no blank, " +
                 "quote or '$' (C 10 ex01: [\"c10_run\", \"--prog\", \"ex01_bin\", " +
                 "\"cat\"]); each case's \"args\" follow it. It is %r.") % (ex, model))
    if not cases:
        return (("c_program(%s): model says which //oracle command made the cases' " +
                 "expected files, and there are no cases.") % ex)
    named = [c.get("name", "run") for c in cases if type(c) == "dict" and c.get("sanitize")]
    if named:
        return (("c_program(%s): model, and case %r compares a sanitized output: its " +
                 "file is the output with its address column rewritten, which no " +
                 "run answers. Hold that exercise's files to a model some other " +
                 "way, or take model off.") % (ex, named[0]))
    if not [c for c in cases if type(c) == "dict" and "expected" in c]:
        return (("c_program(%s): model, and no case has one expected file for it to " +
                 "answer (an \"any_of\" or \"survive\" case compares none that one " +
                 "run makes). Take model off.") % ex)
    return None

def _emit_model(ex, cases, model, prog):
    """exNN[_case]_model for each case of `cases` with one expected file.

    tools/model_check.sh runs `oracle <model> <the case's args>` from where
    the case's program runs, with its standard input and the name it says
    will not open, and compares the stream the case compares, byte for byte,
    and the status the case names in "exit". Layer oracle, complete: it runs
    nothing of the student's and is green on every turn-in; red, it says a
    fixture and the model it came from have parted. The run is the case's
    own, from _case_run like every arm's (`prog` is c_program's `name`): its
    standard input, its argument file, and its run folder, where the model
    runs as ./<prog> beside the case's files.
    """
    for c in cases:
        if "expected" not in c:
            continue
        k = _case(c, "program", "c_program(num = \"%s\")" % ex[2:])
        stem = _case_stem(ex, cases, k.name)
        expected = "tests/%s/%s" % (ex, c["expected"])
        args = [
            "--oracle",
            "$(location //oracle:oracle)",
            "--expected",
            "$(location %s)" % expected,
        ]
        run_flags, run_files = _case_run(c, prog)
        data = _uniq(["//oracle:oracle", expected] + run_files)
        if c.get("stream"):
            args += ["--stream", c["stream"]]
        args += run_flags
        if "exit" in c:
            args += ["--exit", str(c["exit"])]
        if c.get("missing_file"):
            args += ["--absent", c["missing_file"]]
        _test(
            name = "%s_model" % stem,
            srcs = ["//tools:model_check.sh"],
            args = args + ["--"] + model + c.get("args", []),
            data = data,
            tags = ["oracle"],
        )

def _case_exit_error(ex, c):
    """None, or why a c_program case's exit keys are malformed (see _case_exit)."""
    if c.get("exit_quote") != None and "exit" not in c:
        return (("c_program(%s): case %r has exit_quote but no exit -- the quote " +
                 "is the subject's sentence naming the status in \"exit\".") %
                (ex, c.get("name", "run")))
    if "exit" in c:
        code = c["exit"]
        if type(code) != "int" or code < 0 or code > 255:
            return ("c_program(%s): case %r: exit must be an int from 0 to 255, not %r" %
                    (ex, c.get("name", "run"), code))
    if "invalid_input" in c and type(c["invalid_input"]) != "bool":
        return ("c_program(%s): case %r: invalid_input is True or False, not %r" %
                (ex, c.get("name", "run"), c["invalid_input"]))

    # A name that will not open is an error path for every program that opens
    # one, so a case handing it one says what the status after it means, as a
    # stderr case does: a default twin would demand 0 from cat's 1.
    if ("missing_file" in c and "exit" not in c and "invalid_input" not in c and
        "any_of" not in c and "survive" not in c):
        return (("c_program(%s): case %r names a file that will not open " +
                 "(\"missing_file\") and does not say what its exit status means. " +
                 "Give it \"invalid_input\": True where the subject answers it with " +
                 "an error message, \"exit\" where a status is named or read, or " +
                 "\"invalid_input\": False where the subject calls it no error " +
                 "(docs/reference.md, \"Writing a c_program case\").") %
                (ex, c.get("name", "run")))

    # A case that compares stderr is almost always an error message, and one
    # that states nothing gets a twin expecting 0 from it. Every such case in
    # the repo was marked by hand, and nothing asked for the mark (review of
    # wave 3), so the next project's first unmarked "Error" would fail a
    # correct program at robust and call 0 the C convention. The same default
    # on stdout is caught at run time: the twin is told it is a default
    # (--exit-source default), and diff_output.sh refuses it when the expected
    # output mentions an error.
    # An "any_of" or "survive" case gets no twin (_case_exit), so it has no
    # default to state.
    if (c.get("stream") == "stderr" and "exit" not in c and "invalid_input" not in c and
        "any_of" not in c and "survive" not in c):
        return (("c_program(%s): case %r compares stderr and does not say what " +
                 "its exit status means. Give it \"invalid_input\": True if the " +
                 "subject answers this input with an error message (no level then " +
                 "judges the status), \"invalid_input\": False if it does not (a " +
                 "robust twin then expects 0), or \"exit\" (docs/reference.md, " +
                 "\"Writing a c_program case\").") % (ex, c.get("name", "run")))
    return None

def _case_exit(ex, c):
    """Where one c_program case's exit status is judged, by the Run contract.

    docs/reference.md ("Run contract"): a status the subject names is compared
    at basic; a non-zero exit where it names none fails only at robust. Returns
    (basic, robust): the status exNN_<case>_output compares, and the one its
    robust twin exNN_<case>_exit compares; None where that target judges none.

      "exit" + "exit_quote"  the subject names it: (N, None). With "level" 2,
                             the sentence is READ as naming it (C 10's
                             "performs the same function as the system's
                             tail": the tool's own status), so the case's
                             output test compares it at strict and says it
                             is a reading (_exit_source)
      "exit" alone           this repo's rule:     (None, N)
      "invalid_input": True  and no "exit": an input the subject answers with
                             an error message it names, where a non-zero
                             status is what an error conventionally returns:
                             (None, None)
      "any_of" or "survive"  and no "exit": a case whose reading the subject
                             leaves open (_CASE_KINDS), where one reading may
                             be an error and another not, so no status is
                             conventional: (None, None)
      "invalid_input": False the C convention, stated: (None, 0)
      neither                the C convention, by default: (None, 0). Refused
                             for a case that compares stderr or names a file
                             that will not open (_case_exit_error), and its
                             twin refuses to run when the expected
                             output mentions an error (--exit-source default):
                             a default is not a decision there.

    How the program ended is read from waitpid() (tools/exit_status), so a
    `return (-1);` is the status 255, never mistaken for a signal.
    """
    err = _case_exit_error(ex, c)
    if err:
        fail(err)
    if "exit" in c:
        if c.get("exit_quote"):
            return (c["exit"], None)
        return (None, c["exit"])
    if c.get("invalid_input") or "any_of" in c or "survive" in c:
        return (None, None)
    return (None, 0)

def _exit_source(c):
    """Whose rule a case's "exit" is, as diff_output.sh's --exit-source.

    "subject" where the subject names the status ("exit_quote", at basic);
    "reading" where the quoted sentence is read as naming it, which the Run
    contract checks at strict ("exit_quote" and "level" 2; _case_problem
    refuses a quote at any other raised level, so the runner's "checked at
    strict" is always true); "convention" where no sentence is quoted and the
    status is this repo's rule.
    """
    if not c.get("exit_quote"):
        return "convention"
    if c.get("level") == 2:
        return "reading"
    return "subject"

def _exit_flags(c, code):
    """The diff_output.sh flags that judge a case's "exit" of `code` in its output test."""
    flags = ["--exit", str(code), "--exit-source", _exit_source(c)]
    if c.get("exit_quote"):
        flags += ["--exit-quote", shell_word(c["exit_quote"])]
    return flags

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

def _header_exit_error(ex, c):
    """None, or why a c_header case's exit is checked below where it may be.

    By the Run contract (docs/reference.md), a status the subject does not name
    is this repo's rule and is checked at robust at the lowest: a case with
    "exit" and no "exit_quote" must carry "level" 3 or 4.
    """
    if c.get("exit") == None or c.get("exit_quote"):
        return None
    if (c.get("level") or 1) < 3:
        return (("c_header(%s): case %r asserts exit %r with no exit_quote. " +
                 "A status the subject does not name is this repo's rule, and " +
                 "the Run contract (docs/reference.md) checks one at robust: " +
                 "give the case \"level\": 3, or quote the subject's sentence " +
                 "in \"exit_quote\".") % (ex, c.get("name", "run"), c["exit"]))
    return None

# A value of the right type for every case key, for starlark_selftest's
# "every documented key is accepted" arm; a key not listed takes a string.
# "missing_file" names an operand of "args", as it must.
# "level" is 2, the one raised level an "exit_quote" goes with (a reading).
_GOOD_VALUE = {
    "args": ["no_such_file_ex00"],
    "cwd_files": {"a.dict": "a"},
    "exit": 0,
    "fixtures": [],
    "invalid_input": False,
    "labeled": True,
    "level": 2,
    "missing_file": "no_such_file_ex00",
    "sanitize": True,
    "valgrind": True,
}

def starlark_selftest(name):
    """The fail() guards above, run on known inputs while Bazel loads the file.

    A guard that fail()s at loading has no runner a selftest arm can call, and
    a guard that stopped refusing would be as silent as the key it stopped
    catching. So each is called here on an input it must refuse and on one it
    must accept; a wrong answer fail()s the load of tools/tests, which reds
    `bazel test //tools/tests/...` with the arm's name. The test this emits
    only prints what was checked. The inputs are made up (ex00, "a") and
    belong to no exercise.

    Args:
        name: the sh_test that lists the arms.
    """
    good = {"name": "a", "expected": "a.txt", "args": [], "clues": "clues.tsv"}
    hyphen = dict(good)
    hyphen["invalid-input"] = True
    arms = [
        # (what, the guard's answer, a substring the refusal must hold, or
        # None for an input it must accept)
        (
            "a misspelt c_program case key is refused, naming the real one",
            _case_problem(dict(good, invalid_inputs = True), "program"),
            "did you mean \"invalid_input\"",
        ),
        (
            "a hyphenated one too",
            _case_problem(hyphen, "program"),
            "did you mean \"invalid_input\"",
        ),
        (
            "an unknown c_program case key is refused",
            _case_problem(dict(good, why = "x"), "program"),
            "is not a key of a program case",
        ),
        (
            "every documented c_program key is accepted",
            _case_problem({k: _GOOD_VALUE.get(k, "x") for k in _CASE_KEYS["program"] + ["expected"]}, "program"),
            None,
        ),
        (
            "a c_program key c_header does not read is refused there",
            _case_problem(dict(good, stream = "x"), "header"),
            "is not a key of a header case",
        ),
        (
            "a cwd_files case accepts its files by name",
            _case_problem(dict(good, args = ["a"], cwd_files = {"x.dict": "a"}), "program"),
            None,
        ),
        (
            "a cwd_files case refuses a location-expanded argument",
            _case_problem(dict(good, args = ["$(location x.dict)"], cwd_files = {"x.dict": "a"}), "program"),
            "runs from its own folder",
        ),
        (
            "a cwd_files name outside the run folder is refused",
            _case_problem(dict(good, cwd_files = {"x.dict": "../a"}), "program"),
            "not a name inside the run folder",
        ),
        (
            "a cwd_files name Bazel would split is refused",
            _case_problem(dict(good, cwd_files = {"x.dict": "a b"}), "program"),
            "Bazel splits",
        ),
        (
            "an empty cwd_files is refused",
            _case_problem(dict(good, cwd_files = {}), "program"),
            "the files the run folder holds",
        ),
        (
            "an argv_file that is no label is refused",
            _case_problem(dict(good, argv_file = ["a"]), "program"),
            "one argument per line",
        ),
        (
            "a cwd_files name . is refused",
            _case_problem(dict(good, cwd_files = {"x.dict": "."}), "program"),
            "not a name inside the run folder",
        ),
        (
            "a cwd_files name that is the program file is refused",
            _case_problem(dict(good, cwd_files = {"x.dict": "toy"}), "program", "toy"),
            "where the run folder holds the program",
        ),
        (
            "...and one under a folder of that name",
            _case_problem(dict(good, cwd_files = {"x.dict": "toy/x.dict"}), "program", "toy"),
            "where the run folder holds the program",
        ),
        (
            "a cwd_files name in a folder of its own is accepted",
            _case_problem(dict(good, cwd_files = {"x.dict": "sub/x.dict"}), "program", "toy"),
            None,
        ),
        (
            "a c_program case named valgrind, a clue label, is refused",
            _case_problem(dict(good, name = "valgrind"), "program"),
            "is not named \"valgrind\"",
        ),
        (
            "exit_quote with no exit is refused",
            _case_exit_error("ex00", dict(good, exit_quote = "q")),
            "exit_quote but no exit",
        ),
        (
            "an exit status above 255 is refused",
            _case_exit_error("ex00", dict(good, exit = 256)),
            "from 0 to 255",
        ),
        (
            "an invalid_input that is not a bool is refused",
            _case_exit_error("ex00", dict(good, invalid_input = "yes")),
            "True or False",
        ),
        (
            "a quoted exit is accepted",
            _case_exit_error("ex00", dict(good, exit = 0, exit_quote = "q")),
            None,
        ),
        (
            "a stderr case that says nothing about its status is refused",
            _case_exit_error("ex00", dict(good, stream = "stderr")),
            "does not say what its exit status means",
        ),
        (
            "a stderr case marked invalid_input False is accepted",
            _case_exit_error("ex00", dict(good, stream = "stderr", invalid_input = False)),
            None,
        ),
        (
            "a stderr case with an exit is accepted",
            _case_exit_error("ex00", dict(good, stream = "stderr", exit = 1)),
            None,
        ),
        (
            "a stderr any_of case, which gets no twin, is accepted",
            _case_exit_error("ex00", dict(good, stream = "stderr", any_of = ["a", "b"])),
            None,
        ),
        (
            "shell_word() doubles a $ and keeps quotes and blanks inside single quotes",
            shell_word("($1 == \"\" ? 0 : 1)"),
            "'($$1 == \"\" ? 0 : 1)'",
        ),
        (
            "a forbidden layer for a subject with no Allowed functions line is refused",
            _forbidden_allowed_problem("ex00_forbidden", None),
            "would authorise nothing",
        ),
        (
            "...and one for \"Allowed functions: None\" is accepted",
            _forbidden_allowed_problem("ex00_forbidden", []),
            None,
        ),
        (
            "c_header: an unquoted exit below robust is refused",
            _header_exit_error("ex00", dict(good, exit = 0)),
            "checks one at robust",
        ),
        (
            "c_header: an unquoted exit at robust is accepted",
            _header_exit_error("ex00", dict(good, exit = 0, level = 3)),
            None,
        ),
        (
            "c_header: a quoted exit at basic is accepted",
            _header_exit_error("ex00", dict(good, exit = 0, exit_quote = "q")),
            None,
        ),
        (
            "a quoted exit at basic is the subject naming it",
            _exit_source(dict(good, exit = 0, exit_quote = "q")),
            "subject",
        ),
        (
            "a quoted exit raised to strict is a reading of the sentence",
            _exit_source(dict(good, exit = 1, exit_quote = "q", level = 2)),
            "reading",
        ),
        (
            "an unquoted exit is a convention of this repo",
            _exit_source(dict(good, exit = 0, level = 3)),
            "convention",
        ),
        (
            "a quoted exit raised past strict is refused, not called a reading",
            _case_problem(dict(good, exit = 1, exit_quote = "q", level = 3), "program"),
            "No other level takes a quote",
        ),
        (
            "c_header refuses it too",
            _case_problem({"name": "a", "expected": "a.txt", "exit": 0, "exit_quote": "q", "level": 4}, "header"),
            "No other level takes a quote",
        ),
        (
            "a quoted exit at strict is accepted",
            _case_problem(dict(good, exit = 1, exit_quote = "q", level = 2), "program"),
            None,
        ),
        (
            "a quoted exit at basic reaches the runner with its sentence too",
            " ".join(_exit_flags({"exit": 0, "exit_quote": "a b"}, 0)),
            "--exit 0 --exit-source subject --exit-quote 'a b'",
        ),
        (
            "a reading reaches the runner with its sentence as one argument",
            " ".join(_exit_flags(dict(good, exit = 1, exit_quote = "a b", level = 2), 1)),
            "--exit 1 --exit-source reading --exit-quote 'a b'",
        ),
        (
            "a program that may open files and names no file that will not open is refused",
            _missing_file_problem("ex00", ["open", "read"], [good], None),
            "no case names a file that will not open",
        ),
        (
            "an error case about a file's content is not that path (BSQ's and Rush 02's shape)",
            _missing_file_problem("ex00", ["open", "read"], [good, dict(good, name = "b", invalid_input = True), dict(good, name = "c", exit = 1)], None),
            "no case names a file that will not open",
        ),
        (
            "a case marking the operand that will not open is that path",
            _missing_file_problem("ex00", ["open"], [good, dict(good, name = "b", args = ["nope"], missing_file = "nope", invalid_input = True)], None),
            None,
        ),
        (
            "or a sentence saying why there is none",
            _missing_file_problem("ex00", ["open"], [good], "the subject runs it on one fixed file"),
            None,
        ),
        (
            "a sentence beside such a case is refused as stale",
            _missing_file_problem("ex00", ["open"], [dict(good, args = ["nope"], missing_file = "nope", survive = True)], "none"),
            "Drop the sentence",
        ),
        (
            "a sentence where nothing asks for one is refused too",
            _missing_file_problem("ex00", ["write"], [good], "none"),
            "nothing asks for one",
        ),
        (
            "a program that may not open files is not asked",
            _missing_file_problem("ex00", ["write"], [good], None),
            None,
        ),
        (
            "missing_file names one of the case's operands",
            _case_problem(dict(good, args = ["a"], missing_file = "b"), "program"),
            "do not hold it",
        ),
        (
            "and not a fixture, which is there",
            _case_problem(dict(good, args = ["$(location x)"], missing_file = "$(location x)"), "program"),
            "a file that is there",
        ),
        (
            "nor an option, standard input or a directory",
            _case_problem(dict(good, args = ["."], missing_file = "."), "program"),
            "as a directory that is there",
        ),
        (
            "a missing_file operand of the case is accepted",
            _case_problem(dict(good, args = ["-c", "5", "no_such_file_ex00"], missing_file = "no_such_file_ex00"), "program"),
            None,
        ),
        (
            "nor a name cwd_files stages in the run folder",
            _case_problem(dict(good, args = ["numbers.dict"], missing_file = "numbers.dict", cwd_files = {"x.dict": "numbers.dict"}), "program"),
            "the run folder holds it",
        ),
        (
            "a missing_file case that says nothing of its status is refused",
            _case_exit_error("ex00", dict(good, args = ["nope"], missing_file = "nope")),
            "does not say what its exit status means",
        ),
        (
            "one marked invalid_input is accepted",
            _case_exit_error("ex00", dict(good, args = ["nope"], missing_file = "nope", invalid_input = True)),
            None,
        ),
        (
            "a model is a list of words",
            _model_problem("ex00", "c10_run cat", [good]),
            "as a list of words",
        ),
        (
            "with no blank inside one, which Bazel would split",
            _model_problem("ex00", ["c10_run", "--prog ex00_bin"], [good]),
            "as a list of words",
        ),
        (
            "a model beside a sanitized case is refused",
            _model_problem("ex00", ["c10_run", "cat"], [good, dict(good, name = "s", sanitize = True)]),
            "compares a sanitized output",
        ),
        (
            "and one with no case it could answer",
            _model_problem("ex00", ["c10_run", "cat"], [{"name": "x", "survive": True}]),
            "no case has one expected file",
        ),
        (
            "a survive case is gated on a case run where the test runs, never on a run folder's",
            " ".join(_survive_gate("ex00", [
                dict(good, name = "folder", args = ["4"], cwd_files = {"x.dict": "n"}),
                dict(good, name = "argfile", argv_file = "a.argv"),
                dict(good, name = "here", args = ["4"]),
                {"name": "s", "survive": True},
            ])[0]),
            "--gate-label ex00_here_output",
        ),
        (
            "a model with a case of one expected file is accepted",
            _model_problem("ex00", ["c10_run", "--prog", "ex00_bin", "cat"], [good]),
            None,
        ),
        (
            "a file_check call that says nothing of stderr is refused",
            _runner_choice_problem("ex00_file_diff", "//tools:file_check.sh", ["--bin", "x", "--fn", "f"]),
            "Pass exactly one of --stderr-empty, --stderr-ignored; this call has none",
        ),
        (
            "and one that says both",
            _runner_choice_problem("ex00_file_diff", "//tools:file_check.sh", ["--stderr-empty", "--stderr-ignored", "y"]),
            "this call has --stderr-empty, --stderr-ignored",
        ),
        (
            "a file_check call that holds stderr empty is accepted",
            _runner_choice_problem("ex00_file_diff", "//tools:file_check.sh", ["--bin", "x", "--stderr-empty"]),
            None,
        ),
        (
            "a replay under a memory checker makes no stderr choice, and is accepted",
            _runner_choice_problem("ex00_file_diff_asan", "//tools:file_check.sh", ["--bin", "x", "--fn", "f", "--sanitized"]),
            None,
        ),
        (
            "and one that makes one anyway is refused",
            _runner_choice_problem("ex00_file_valgrind", "//tools:file_check.sh", ["--bin", "x", "--valgrind", "v", "--stderr-empty"]),
            "drop --stderr-empty",
        ),
        (
            "a stderr reason written plainly, which Bazel would split, is refused",
            _runner_choice_problem("ex00_argv_diff", "//tools:argv_check.sh", ["--stderr-ignored", "the subject says nothing"]),
            "does not hand over as one argument",
        ),
        (
            "and one with a bare apostrophe, which fails the analysis",
            _runner_choice_problem("ex00_argv_diff", "//tools:argv_check.sh", ["--stderr-ignored", "it's"]),
            "does not hand over as one argument",
        ),
        (
            "stderr_ignored() quotes a sentence with an apostrophe as one argument",
            _runner_choice_problem("ex00_argv_diff", "//tools:argv_check.sh", stderr_ignored("the subject's words")),
            None,
        ),
        (
            "a runner that asks for no choice is not held to one",
            _runner_choice_problem("ex00_output", "//tools:diff_output.sh", ["--bin", "x"]),
            None,
        ),
        (
            "a bsq_check call that quotes no sentence is refused",
            _runner_choice_problem("ex00_bsq", "//tools:bsq_check.sh", ["--bin", "x", "--stderr-empty"]),
            "Pass exactly one of --quotes; this call has none",
        ),
        (
            "and a replay under a memory checker, which judges no output, is accepted without one",
            _runner_choice_problem("ex00_bsq_memory", "//tools:bsq_check.sh", ["--bin", "x", "--valgrind", "v"]),
            None,
        ),
        (
            "an exit_quote with an ASCII apostrophe is accepted",
            _case_problem(dict(good, exit = 1, exit_quote = "the system's tool"), "program"),
            None,
        ),
        (
            "and reaches the runner quoted around it, as one argument",
            " ".join(_exit_flags({"exit": 1, "exit_quote": "the system's tool"}, 1)),
            "--exit-quote 'the system'\\''s tool'",
        ),
        (
            "an exit_quote with a dollar sign is accepted",
            _case_problem(dict(good, exit = 1, exit_quote = "echo $? says it"), "program"),
            None,
        ),
        (
            "and reaches the runner with its $ doubled, so it comes out of the expansion as itself",
            " ".join(_exit_flags({"exit": 1, "exit_quote": "echo $? says it"}, 1)),
            "--exit-quote 'echo $$? says it'",
        ),
        (
            "stderr_ignored() quotes a sentence with a '$' as one argument",
            _runner_choice_problem("ex00_argv_diff", "//tools:argv_check.sh", stderr_ignored("it's $HOME's")),
            None,
        ),
    ]
    wrong = []
    for what, got, want in arms:
        if want == None and got != None:
            wrong.append("%s -- it refused: %s" % (what, got))
        elif want != None and (got == None or want not in got):
            wrong.append("%s -- it answered %r" % (what, got))
    if wrong:
        fail("starlark_selftest: a defs.bzl guard no longer does its job:\n  " +
             "\n  ".join(wrong))
    hand_test(
        name = name,
        layer = "selftest",
        size = "small",
        srcs = ["starlark_selftest.sh"],
        # Each arm's name as one argument, through shell_word, as an
        # exit_quote reaches diff_output.sh: Bazel expands args and then
        # tokenises them like a shell. The script counts them, and checks
        # that a sentence with apostrophes and '$' arrived whole -- quoted
        # any other way, it splits, loses a '$', or the package fails to
        # load on an unterminated quote or a '$' Bazel cannot expand.
        args = [
            "--arms",
            str(len(arms)),
            "--apostrophe",
            shell_word(_APOSTROPHE),
        ] + [shell_word(what) for what, _, _ in arms],
    )

# A sentence starlark_selftest() hands its script through shell_word, which
# must arrive as this one argument, its script holding the same words: the
# apostrophes and '$' of a subject's sentence, and the double quotes and
# backslash an awk expression (c_cycles' unit_expr) can hold.
_APOSTROPHE = "the system's tail, as the subject's sentence prints it: $? and $(x) too, $1 == \"\" and \\ as well"


def _survive_gate(ex, cases):
    """diff_output.sh's --gate-* flags for a survive case of `cases`, and the files they name.

    The gate is the exercise's first case at basic with one expected file
    and plain arguments (no blank but a $(location ...)'s, no quote, no
    empty one: Bazel's tokenising of `args` would not hand those over as
    one --gate-arg each), run where the test runs: no "argv_file" or
    "cwd_files", which the gate's flags do not carry -- Rush 02's first case
    runs `./rush-02 42` from a folder holding numbers.dict, and gated on it
    from anywhere else its survive cases would never run: while its
    output is red, a survive case SKIPs. A survive case asks only that the
    program ends by itself, which an unwritten one does: do-op's stub was
    green on INT_MIN / -1 at strict (review of WP-52). No such case: no gate,
    and the survive case runs as it is. NO_SKIP=1 runs it always.
    """
    for g in cases:
        if "expected" not in g or g.get("level") or g.get("argv_file") or g.get("cwd_files"):
            continue
        plain = [a.replace("$(location ", "$(location_") for a in g.get("args", [])]
        if [a for a in plain if not a or " " in a or "\t" in a or "'" in a or '"' in a]:
            continue
        gk = _case(g, "program", "c_program(num = \"%s\")" % ex[2:])
        f = "tests/%s/%s" % (ex, g["expected"])
        args = [
            "--gate-expected",
            "$(location %s)" % f,
            "--gate-label",
            "%s_output" % _case_stem(ex, cases, gk.name),
        ]
        data = [f] + g.get("fixtures", [])
        if g.get("stream"):
            args += ["--gate-stream", g["stream"]]
        if g.get("stdin"):
            args += ["--gate-stdin", "$(location %s)" % g["stdin"]]
            data.append(g["stdin"])
        if g.get("sanitize"):
            args.append("--gate-sanitize")
        if g.get("labeled"):
            args.append("--gate-labeled")
        for a in g.get("args", []):
            args += ["--gate-arg", a]
        return args, data
    return [], []

def _uniq(xs):
    """`xs` with each item once, in order: Bazel refuses a label twice in `data`."""
    out = []
    for x in xs:
        if x not in out:
            out.append(x)
    return out

def _case_run(c, prog):
    """How one c_program case runs, in every arm: (flags, files).

    `flags` go before a runner's `--` and take the same meaning in
    diff_output.sh, asan_run.sh and valgrind_test.sh: the stdin, the argument
    file and the run folder the case describes (_CASE_KEYS, "THE KEYS THAT
    SHAPE THE RUN ITSELF"). `files` are what they read. One helper, so that
    the arms cannot drift into running different things -- the valgrind arm
    once ran a stdin case with no stdin at all.
    """
    flags = []
    files = list(c.get("fixtures", []))
    if c.get("stdin"):
        flags += ["--stdin", "$(location %s)" % c["stdin"]]
        files.append(c["stdin"])
    if c.get("argv_file"):
        flags += ["--argv-file", "$(location %s)" % c["argv_file"]]
        files.append(c["argv_file"])
    if c.get("cwd_files"):
        flags += ["--run-as", prog]
        for src in sorted(c["cwd_files"]):
            flags += ["--cwd-file", "%s=$(location %s)" % (c["cwd_files"][src], src)]
            files.append(src)
    return flags, _uniq(files)

def _shown_bin(binname):
    """Where Bazel keeps a program of this package, for a RAN line: bazel-bin/<package>/<name>.

    What a student types at the repository root to run the program a test
    ran, once `bazel test` has built it (runner_lib.sh's rl_ran).
    """
    return "bazel-bin/%s/%s" % (native.package_name(), binname)

def _emit_cases(ex, binname, cases, prog, valgrind = False, memory_rule = None):
    """Emit one diff test (and optional valgrind test) per argv case.

    `memory_rule` is the label of the subject's memory sentence (c_program's
    memory_rule), which each valgrind arm quotes when it fails.

    And, per case, the exit status where _case_exit() says one is judged: in
    the output test when the subject names it, otherwise in a robust twin,
    exNN[_case]_exit (tag "output", level 3), which runs the same invocation
    and judges nothing but how it ended -- the shape c_argv_table's exNN_exit
    and c_program's exNN_progname_exit have. Named _exit, not _exit_output:
    first_red reads an `output` tail as the next exercise to write, and this is
    rigour on a written one.

    Every arm of a case prints the command it ran (--show-run) and keys its
    hints to the case's name (--case): a program case is a test of its own,
    with no named rows, so its report said nothing of what was run, and a
    clues.tsv row could name no case (findings 120, 155). `prog` is the
    program's name, which a "cwd_files" case runs it under.

    Every case is checked first (_case): its keys, its kind, its level.

    ONE TWIN PER RUN. Two cases can make the same run and compare its two
    streams (C 10 ex00's `empty` and `empty_stderr`): a twin judges how the
    run ended, which is one fact, so the second case's twin would judge it
    again and a wrong status would be two reds for one mistake. A twin whose
    arguments, the compared stream aside, are an earlier twin's is not
    emitted; the earlier one's name stands for both.
    """
    twins = {}
    for c in cases:
        k = _case(c, "program", "c_program(num = \"%s\")" % ex[2:], prog)
        stem = _case_stem(ex, cases, k.name)
        compare, expected_fs = _expected_args(ex, k)
        run_flags, run_files = _case_run(c, prog)
        shown = ["--show-run", _shown_bin(binname), "--case", k.name]
        data = _uniq([":" + binname] + expected_fs + run_files)
        args = [
            "--bin",
            "$(location :%s)" % binname,
        ] + compare + shown
        if c.get("stream"):
            args += ["--stream", c["stream"]]
        if c.get("sanitize"):
            args.append("--sanitize")
        if c.get("labeled"):
            args.append("--labeled")
        if c.get("clues"):
            clues_f = "tests/%s/%s" % (ex, c["clues"])
            args += ["--clues", "$(location %s)" % clues_f]
            data.append(clues_f)
        basic_exit, robust_exit = _case_exit(ex, c)
        if basic_exit != None:
            args += _exit_flags(c, basic_exit)
        elif robust_exit != None:
            args += ["--note-exit", str(robust_exit)]

        # The name the case says will not open is checked absent where the
        # program runs, so the case cannot hand it a file that is there.
        if c.get("missing_file"):
            args += ["--absent", c["missing_file"]]

        # A survive case SKIPs while its exercise's first case is red: green
        # on a program nobody has written says nothing (_survive_gate).
        gate_args, gate_data = _survive_gate(ex, cases) if k.survive else ([], [])
        w_args, w_data = _waiting_args("%s_output" % stem) if expected_fs else ([], [])
        args += gate_args + w_args + run_flags + ["--"] + c.get("args", [])
        _test(
            name = "%s_output" % stem,
            srcs = ["//tools:diff_output.sh"],
            args = args,
            data = data + [f for f in gate_data + w_data if f not in data],
            # What the case reads: its expected file(s), and every file its
            # run is handed (_case_run: fixtures, stdin, argument file, the
            # run folder's sources).
            tags = ["output", _case_reads_tag(expected_fs + run_files)],
            level = _raise("output", k.level),
        )
        e_head = [
            "--bin",
            "$(location :%s)" % binname,
        ]
        e_stream = ["--stream", c["stream"]] if c.get("stream") else []

        # "default": the case states nothing, so diff_output.sh checks the
        # default against what the case expects (_case_exit).
        source = "convention" if "exit" in c or "invalid_input" in c else "default"
        e_rest = [
            "--exit-only",
            "--exit",
            str(robust_exit),
            "--exit-source",
            source,
        ] + run_flags + ["--"] + c.get("args", [])

        # The run, as ONE TWIN PER RUN above reads it: what the twin is
        # handed but the file and the stream it does not compare, and the
        # level it sits at. A default's twin does read the file (the check
        # above), so there it is part of the run. What the report shows
        # (--show-run, --case) is not the run: the first case's name stands
        # for both.
        run = repr(e_head + e_rest + [max(3, k.level or 3)] + (compare if source == "default" else []))
        if robust_exit != None and run not in twins:
            twins[run] = stem
            e_args = e_head + compare + shown + e_stream + e_rest
            _test(
                name = "%s_exit" % stem,
                srcs = ["//tools:diff_output.sh"],
                args = e_args,
                data = data,
                tags = ["output"],
                # Robust, or the case's own level where that is higher.
                level = max(3, k.level or 3),
            )
        if valgrind and c.get("valgrind", True):
            vdata = _uniq([
                ":" + binname,
                "//tools:diff_output.sh",
            ] + expected_fs + run_files)
            vargs = [
                "--bin",
                "$(location :%s)" % binname,
                "--label",
                stem,
            ] + shown
            if memory_rule:
                vargs += ["--rule", "$(location %s)" % memory_rule]
                vdata.append(memory_rule)

            # Gate on the exercise's own fixture, the way rust_diff, ilp32,
            # perf and cycles already do. Without it this was the one rigour
            # layer that spoke first: c-12 ex06 is a stub, so a student who
            # had written nothing was met with eight raw "indirectly lost"
            # records instead of "your output layer is still red — start
            # there". Leaks are the LAST thing to think about, after the
            # function produces the right bytes at all.
            #
            # A survive case has no fixture to gate on: its "output" is that
            # it ended, and the memory report of a run that ended is news. So
            # its arm runs ungated, as it does where a gate cannot answer.
            gate, _ = _expected_args(ex, k, "--gate-expected", "--gate-expected-alt", None)
            if gate:
                vargs += [
                    "--gate-differ",
                    "$(location //tools:diff_output.sh)",
                    "--gate-bin",
                    "$(location :%s)" % binname,
                ] + gate
            if c.get("stream"):
                vargs += ["--gate-stream", c["stream"]]
            if c.get("sanitize"):
                vargs.append("--gate-sanitize")
            if c.get("labeled"):
                vargs.append("--gate-labeled")

            # stdin was never forwarded, so a case that feeds the program input
            # ran a DIFFERENT path here than under the output layer — it read
            # EOF immediately. The runner forwards the argument file and the
            # run folder to its gate itself; stdin has its own gate flag.
            if c.get("stdin"):
                vargs += [
                    "--gate-stdin",
                    "$(location %s)" % c["stdin"],
                ]

            # The same clues.tsv the output arm gets. c_function has wired this
            # since the renderer was written, with the reason stated there --
            # "40 bytes in 1 blocks are definitely lost" is the report most
            # likely to leave a beginner stuck, and it was the one layer with no
            # hint attached. c_program's valgrind arm was the half that never
            # got the line, so the two macros disagreed about whether a leak
            # deserves a hint, with nothing recording a reason. It does.
            if c.get("clues"):
                vargs += ["--clues", "$(location tests/%s/%s)" % (ex, c["clues"])]
                vdata.append("tests/%s/%s" % (ex, c["clues"]))

            # BEFORE the `--`, which is not a detail: everything after it is
            # argv for the program under test, so flags appended at the end of
            # the list are handed to the student's binary and the runner sees
            # none of them.
            vargs += run_flags + _valgrind_args()
            vargs += ["--"] + c.get("args", [])
            _test(
                name = "%s_valgrind" % stem,
                srcs = ["//tools:valgrind_test.sh"],
                args = vargs,
                data = _uniq(vdata + _valgrind_data()),
                # A whole program under memcheck, at 20-50x: BSQ's readings
                # case took 22s in a full suite, a third of "small"'s 60,
                # and a run's own VALGRIND_TIMEOUT (60) did not fit inside
                # the test's (finding 066).
                size = "medium",
                tags = ["valgrind"],
                level = _raise("valgrind", k.level),
                # Its own case's output test: cases sharing an expected file
                # (BSQ's map errors) run the same program against it.
                waits = "%s_output" % stem if gate else None,
            )

def _reference_cases_test(ex, cases, prog):
    """exNN_reference_cases: every case of c_program(reference = True), run with //oracle's reference.

    Tag "oracle", complete. One test for the whole list, through
    tools/reference_cases.sh, which runs diff_output.sh once per case with
    `oracle run <prog>` as the program: each case's arguments are exactly its
    output test's -- the expected file(s) and how they are compared, the run
    flags (_case_run: stdin, argument file, run folder), the argv after `--`
    -- less what only a student's report needs (the RAN line, the hints, the
    exit-status note). A case's arguments travel as `--case-run NAME COUNT
    ARG...`, so an argument can be anything a case can hold, `--` included.

    WHY. A named case binds an input to an expected file, and when the files
    come from //oracle (oracle_fixtures.sh) that binding was still kept twice
    by hand: once in the reference's list of what it writes, once in the
    case. An edited number or dictionary in one of them drifted in silence --
    nothing compared them, and the owner's tree holds a stub, on which every
    case is red anyway. Running the reference on the case as written makes
    the case itself the thing checked.
    """
    args = [
        "--oracle",
        "$(location //oracle:oracle)",
        "--program",
        prog,
        "--differ",
        "$(location //tools:diff_output.sh)",
    ]
    data = ["//oracle:oracle", "//tools:diff_output.sh"]
    for c in cases:
        k = _case(c, "program", "c_program(num = \"%s\")" % ex[2:])
        compare, expected_fs = _expected_args(ex, k)
        run_flags, run_files = _case_run(c, prog)
        a = list(compare)
        if c.get("stream"):
            a += ["--stream", c["stream"]]
        if c.get("sanitize"):
            a.append("--sanitize")
        if c.get("labeled"):
            a.append("--labeled")
        basic_exit, _ = _case_exit(ex, c)
        if basic_exit != None:
            a += ["--exit", str(basic_exit), "--exit-source", "subject"]
        a += run_flags + ["--"] + c.get("args", [])
        args += ["--case-run", k.name, str(len(a))] + a
        data += expected_fs + run_files
    _test(
        name = ex + "_reference_cases",
        srcs = ["//tools:reference_cases.sh"],
        args = args,
        data = _uniq(data),
        size = "small",
        tags = ["oracle"],
    )

def _layouts(num):
    """The subject-structure checks for exercise `num`, for each header <h> its contract's `files` names.

    A header the subject dictates the contents of (C 12's ft_list.h, C 13's
    ft_btree.h) is still the student's file, and every test compiles with it,
    so a structure laid out otherwise than the subject prints is invisible to
    every layer that runs code (finding 132). Two files hold what the subject
    prints, each named after the header it checks, with static assertions
    that the student's type matches (see tools/prototype_check.sh):

        tests/layout/<h>      the layout: each field's type or size, its
                              offset, the structure's size -- what decides
                              whether two programs read one node alike
        tests/layout/tag/<h>  the names: the structure's tag, and the type
                              of each field that points to another node --
                              which memory does not see

    Only a header in `files`: one the grader brings (C 12 ex08's) is the
    grader's, and a copy the student keeps anyway is compiled by nobody who
    grades.

    c_function is the one macro that calls this. c_libft and c_header do not:
    no project of theirs has a structure file yet, and a pass-through no
    caller runs is how a check ends up misreading correct work. A file under
    tests/layout/ that no test reads fails c_levels()' audit instead of being
    dropped without a word (_audit_problems), which is where the next
    project's author learns to wire it; the toy exercises ex16 and ex17 in
    tools/tests/macro_fixtures prove the wiring, with `linked` and without.

    Returns:
        struct(files = [the layouts], tags = [the tag files]).
    """
    files = []
    tags = []
    for f in _entry(num, "layout")["files"] or []:
        if f.endswith(".h"):
            h = f.split("/")[-1]
            files += native.glob(["tests/layout/" + h], allow_empty = True)
            tags += native.glob(["tests/layout/tag/" + h], allow_empty = True)
    return struct(files = files, tags = tags)

def _prototype_test(ex, srcs, hdrs = None, extra_includes = None, required = True, layouts = None, layout_certain = False, grader_hdrs = None, name = None, extra_tags = None):
    """Prototype conformance: the definition matches the signature the subject fixes.

    Tag "prototype".

    `layouts` (from _layouts()) are the subject's structures the student's
    header must hold. Each claim sits at the level its failure earns
    (reference.md's levels):

      the layout (`layouts.files`, --layout), in exNN_prototype at basic,
          where a difference is a certain KO: `layout_certain`, which
          c_function sets where the grader links a function of its own built
          on the structure (the contract's `linked`, C 12 and C 13 from ex01
          on), so a header laid out otherwise reads the grader's nodes wrong;
      the layout again, in the twin exNN_layout_prototype at strict, where
          only the grader's own test code could expose a difference (C 12's
          and C 13's ex00, where the student writes that function);
      the names (`layouts.tags`, --layout-tag), always in the twin at strict:
          a header naming the structure otherwise reads the grader's nodes
          right, and only code written against the subject's header by name
          tells them apart.

    The twin's suffix, _layout_prototype, puts it at strict by itself
    (_SUFFIX_LAYER), so no exercise needs a _RAISED entry for it.

    The subject fixes each function's return type and parameter list, and C
    links a mismatched signature happily (no name mangling), so the only symptom
    of getting it wrong is wrong values — a Moulinette KO with no local symptom.
    Force-including the contract header while compiling the deliverable puts the
    subject's declaration and the student's definition in one translation unit,
    turning the mismatch into a conflicting-types error. Green on a well-formed
    stub, like norm.

    `required` exists because this used to be emitted only `if native.glob(...)`
    found a header: a missing tests/exNN/prototype.h produced no target, no
    warning and no error, so "deliberately opted out" and "nobody wrote it yet"
    were indistinguishable — and a LEVEL 1 layer was silently absent for all of
    c-13 and six of c-12. Absence is now an analysis-time failure unless the
    BUILD file says `prototype = False` in so many words.

    `name` is the test's, default exNN_prototype (a rush variant's is
    exNN_rushNN_prototype), and `extra_tags` reach it too ("manual" for a
    variant nobody owes).

    Returns:
        The name of the test it declared, which the exercise's harnesses
        are given (_student_bin's `prototype`); None where it declared
        none.
    """
    hdrs = hdrs or []
    proto_f = "tests/%s/prototype.h" % ex
    if not native.glob([proto_f], allow_empty = True):
        if required:
            fail(
                ("%s: no %s, so the prototype layer would be silently absent " +
                 "for this exercise. Write the contract header (copy the shape " +
                 "of any existing tests/exNN/prototype.h), or pass " +
                 "prototype = False to record that opting out is deliberate.") %
                (ex, proto_f),
            )
        return None

    layouts = layouts or struct(files = [], tags = [])
    common = []
    for s in srcs:
        common += ["--src", "$(location %s)" % s]
    common += _inc_args("--inc", hdrs)
    for d in (extra_includes or []):
        common += ["--inc", d]

    # A header the grader brings is named on a red, with the -I a compile by
    # hand needs (_grader_hdr_args).
    common += _grader_hdr_args(grader_hdrs)
    lay_args = []
    for f in layouts.files:
        lay_args += ["--layout", "$(location %s)" % f]
    tag_args = []
    for f in layouts.tags:
        tag_args += ["--layout-tag", "$(location %s)" % f]
    basic_layouts = layouts.files if layout_certain else []
    twin_layouts = ([] if layout_certain else layouts.files) + layouts.tags
    p_args = _pinned_cc_args() + ["--proto", "$(location %s)" % proto_f] + common
    if layout_certain:
        p_args += lay_args
    name = name or ex + "_prototype"
    _test(
        name = name,
        srcs = ["//tools:prototype_check.sh"],
        args = p_args,
        data = [proto_f] + srcs + hdrs + _PINNED_CC_DATA + basic_layouts,
        tags = ["prototype"] + (extra_tags or []),
        turnin = srcs,
    )
    if twin_layouts:
        _test(
            # exNN_layout_prototype, or <name>'s own twin where it has one.
            name = name[:-len("_prototype")] + "_layout_prototype",
            srcs = ["//tools:prototype_check.sh"],
            args = _pinned_cc_args() + ([] if layout_certain else lay_args) + tag_args + common,
            data = twin_layouts + srcs + hdrs + _PINNED_CC_DATA,
            tags = ["prototype"] + (extra_tags or []),
            level = _SUFFIX_LAYER["_layout_prototype"][1],
            turnin = srcs,
        )
    return name

def _prototype_names_test(name, ex, srcs, hdrs = None, extra_includes = None, extra_tags = None):
    """The parameter NAMES the subject fixes, at strict: tests <name>, ending _prototype_names.

    For a subject that names the parameters as well as typing them (Rush 00:
    "It must take two integer arguments, named x and y"): the definition in
    `srcs` must name them as tests/exNN/prototype.h does, which says so in a
    comment quoting the subject. tools/prototype_check.sh --names reads both
    through the pinned clang's AST dump. The suffix puts it at strict
    (_SUFFIX_LAYER): a name changes no behaviour, and only an evaluator
    reading the code can mark it, which is "real, but not certain". The
    basic _prototype test beside it keeps checking the types only.
    """
    hdrs = hdrs or []
    proto_f = "tests/%s/prototype.h" % ex
    p_args = _pinned_cc_args() + ["--names", "--proto", "$(location %s)" % proto_f]
    for s in srcs:
        p_args += ["--src", "$(location %s)" % s]
    p_args += _inc_args("--inc", hdrs)
    for d in (extra_includes or []):
        p_args += ["--inc", d]
    _test(
        name = name,
        srcs = ["//tools:prototype_check.sh"],
        args = p_args,
        data = [proto_f] + srcs + hdrs + _PINNED_CC_DATA,
        tags = ["prototype"] + (extra_tags or []),
        turnin = srcs,
        # The level its suffix gives it (_SUFFIX_LAYER), which the audit
        # holds it to: _test() places a test by its layer alone.
        level = _SUFFIX_LAYER["_prototype_names"][1],
    )

def _allocfail_problem(num, malloc, allocfail, allocfail_rule):
    """What is wrong with a c_function call's allocfail and its sentence, or None.

    A value before it is a fail(), so the macro fixtures can feed it every
    broken call (contract_problem("allocfail", ...)).

    Args:
        num: the exercise, for the message.
        malloc: as c_function takes it.
        allocfail: as c_function takes it.
        allocfail_rule: as c_function takes it.

    Returns:
        The message, or None.
    """
    where = "c_function(num = \"%s\")" % num
    if allocfail_rule and not allocfail:
        return "%s sets allocfail_rule without allocfail: the sentence would back no check." % where
    if not allocfail:
        return None
    if not malloc:
        return ("%s sets allocfail but not malloc = True. A function that does not " +
                "allocate has no allocation to refuse.") % where
    why = allocfail_rule_problem(allocfail_rule)
    if why:
        return "%s sets allocfail: %s" % (where, why)
    return None

def _function_malloc_problem(num, malloc, e):
    """c_function's message when its contract names malloc or free and `malloc` is off; None otherwise.

    c_program reads whether a program may allocate from the contract alone
    (_malloc_argument_problem). c_function cannot yet: a function that
    allocates through a helper the subject allows -- C 12's ft_create_elem,
    C 13's btree_create_node -- names neither malloc nor free, and needs
    the leak layer all the same, so `malloc` stays a call-site argument
    there. What the call may not do is contradict the contract where it
    speaks: an "Allowed functions" line naming malloc (the function
    allocates) or free (it releases, and must release everything) is one
    the leak layer is for, and a call that turns it off drops the one layer
    that sees a block never accounted for. A subject with no such line says
    nothing about this function either way, and is the call's to say.

    A value before it is a fail(), so the macro fixtures can feed it the
    broken calls (contract_problem("function_malloc", ...)).

    Args:
        num: the exercise, for the message.
        malloc: as c_function takes it.
        e: the exercise's contract entry.

    Returns:
        The message, or None.
    """
    allowed = e["allowed"]
    if malloc or allowed == None:
        return None
    named = [f for f in ["malloc", "free"] if f in allowed]
    if not named:
        return None
    return (("c_function(num = \"%s\"): the contract's allowed functions name %s, and " +
             "malloc = %r turns off the leak layer (exNN_valgrind), the one layer that " +
             "sees a block never accounted for. Pass malloc = True.") %
            (num, " and ".join(named), malloc))

def _malloc_argument_problem(ex, malloc):
    """c_program's message for a call that still passes `malloc`; None if it does not.

    Whether a program may allocate is its subject's, and the contract says
    it (_memcheck_allowed); a second copy at the call site is one that can
    disagree. A value before it is a fail(), so a fixture can watch it.
    """
    if malloc == None:
        return None
    return (("c_program(%s): malloc = %r. Whether the program may allocate is its " +
             "subject's \"Allowed functions\" line, which c_program reads from the " +
             "subject() contract (malloc named there, or no such line), as " +
             "corpus_memory() does: drop the argument.") % (ex, malloc))

def _memory_rule_problem(num, malloc, cases, memory_rule):
    """What is wrong with a c_program call's memory_rule, or None.

    A value before it is a fail(), so the macro fixtures can feed it every
    broken call (contract_problem("memory_rule", ...)).

    Args:
        num: the exercise, for the message.
        malloc: as c_program takes it.
        cases: as c_program takes it.
        memory_rule: as c_program takes it.

    Returns:
        The message, or None.
    """
    where = "c_program(num = \"%s\")" % num
    if memory_rule == None:
        return None
    if not malloc or not cases:
        return ("%s: memory_rule is quoted by the valgrind arms, and there are none " +
                "without cases on a program its subject lets allocate (the contract's " +
                "allowed line names malloc, or there is none).") % where
    if type(memory_rule) != "string" or "\n" in memory_rule or not memory_rule.strip():
        return "%s: memory_rule is one line of the subject." % where
    return None

def allocfail_leaks_problem(allocfail, allowed):
    """Why an exercise may not have an exNN_allocfail_leaks target; None if it may.

    A decision c_function makes while loading, so it is a function of its own
    and //tools/tests:starlark_unit calls it both ways. The leak sweep replays
    the allocfail harness, so it needs one; and it asks a function to release
    what it obtained, so the subject must let it call free() -- C 07 ex05 and
    C 09 ex02 allow malloc alone (finding 084).

    Args:
      allocfail: c_function's `allocfail`, the harness file or None.
      allowed: the exercise's allowed functions from its subject() contract,
        or None where the subject names none.

    Returns:
      None, or the reason as the end of a sentence.
    """
    if not allocfail:
        return "not allocfail: the leak sweep replays the allocfail harness."
    if "free" not in (allowed or []):
        return ("the subject() contract does not let this exercise call free(): a " +
                "function that may not release a block cannot be asked to.")
    return None

def allocfail_rule_problem(rule, param = "allocfail_rule"):
    """Why `rule` cannot be an allocfail target's stated rule; None if it can.

    Every allocfail target says, under its verdict, why it asks what it asks,
    and it says it in the call site's words, handed to the runner as --rule.
    The runner used to say it itself, in one subject's words: every program's
    report quoted "handle errors coherently", C 10's included, whose subject
    has no such sentence, and Rush 02's leak target, whose rule is the
    freeing one. A runner cannot know which subject it is reading; the call
    site can, so the sentence is required there, and a target without one is
    refused while loading. A decision made while loading, so a function of its
    own that //tools/tests:starlark_unit calls both ways.

    Args:
      rule: the text the call site gives, or None.
      param: the parameter's name, for the message.

    Returns:
      None, or the reason as a sentence.
    """
    if type(rule) != "string" or not rule.strip():
        return ("%s is required: the subject's own sentence that makes a refused " +
                "allocation a question for this exercise, quoted, or -- where the " +
                "subject has none -- what this call site reads in it, said as a " +
                "reading. The report prints it under its verdict, so a student " +
                "sees whose rule it was; a runner cannot know which subject it " +
                "reads.") % param
    if "\n" in rule:
        return ("%s is one line: the runner wraps it to the report's width " +
                "itself; a long one is several literals joined with +.") % param
    return None

def method_problem(method, rule):
    """Why c_function's `method` and `method_rule` cannot emit exNN_method; None if they can.

    The method layer reads a sentence of the subject that no output can show
    (tools/method_check.sh), and prints it under its verdict in the call
    site's words, since a runner cannot know which subject it reads. So the
    sentence is required with the method, and neither comes alone. A
    decision made while loading, so a function of its own that
    //tools/tests:starlark_unit calls both ways.

    Args:
      method: "recursive", "iterative", or None.
      rule: the subject's sentence, as the call site quotes it, or None.

    Returns:
      None, or the reason as a sentence.
    """
    if method == None and rule == None:
        return None
    if method not in ("recursive", "iterative"):
        return (("method = %r: \"recursive\" where the subject asks for recursion " +
                 "(\"Create a recursive function\", \"Recursion is required\"), " +
                 "\"iterative\" where it asks for an iterative function, and nothing " +
                 "where it says neither.") % (method,))
    return _quoted_rule_problem(rule, "method_rule", "the subject's own sentence asking for it")

def fixed_array_problem(rule, max_bytes):
    """Why c_program's `fixed_array` and `fixed_array_bytes` cannot emit exNN_fixed_array; None if they can.

    `fixed_array` is the subject's sentence asking for a fixed-size array, as
    the call site quotes it; `fixed_array_bytes`, where the subject bounds
    the array, the bound in bytes, every object having to be smaller (the
    call site says how it read the subject's unit). A bound with no sentence
    would be a rule of no one's. Checked while loading, both ways, by
    //tools/tests:starlark_unit.

    Args:
      rule: the sentence, or None.
      max_bytes: an int above 1, or None.

    Returns:
      None, or the reason as a sentence.
    """
    if rule == None and max_bytes == None:
        return None
    if max_bytes != None and (type(max_bytes) != "int" or max_bytes < 2):
        return (("fixed_array_bytes = %r: the bound in bytes, an int above 1, every " +
                 "object of the program having to be smaller.") % (max_bytes,))
    return _quoted_rule_problem(
        rule,
        "fixed_array",
        "the subject's own sentence asking for a fixed-size array, and with a " +
        "bound, how its unit is read",
    )

def _quoted_rule_problem(rule, param, what):
    """Why `rule` cannot be the sentence a method-layer target prints; None if it can.

    The method layer's verdicts quote the subject (tools/method_check.sh's
    --rule), in the call site's words, as allocfail's do; one line, which
    names_file() writes for the runner.
    """
    if type(rule) != "string" or not rule.strip():
        return (("%s is required: %s, quoted, with where it is from. The report " +
                 "prints it under its verdict, so a student sees whose rule it is; " +
                 "a runner cannot know which subject it reads.") % (param, what))
    if "\n" in rule:
        return ("%s is one line: a long one is several literals joined with +." % param)
    return None

def c_function(
        num,
        fn,
        test,
        srcs = None,
        hdrs = None,
        expected = "expected.txt",
        sanitize = False,
        labeled = False,
        escaped_values = False,
        clues = None,
        malloc = False,
        exports = None,
        prototype = True,
        ilp32 = True,
        allocfail = None,
        allocfail_rule = None,
        allocfail_level = None,
        readings = None,
        allocfail_leaks = False,
        method = None,
        method_rule = None,
        name = None):
    """A function exercise: library + norm + harness binary + stdout diff.

    Four parameters here exist to be turned OFF or ON per exercise -- `exports`,
    `prototype`, `ilp32` and `allocfail`. Each is documented once, under Args:
    below; this preamble used to restate all four in full, so the same paragraph
    appeared twice in one docstring and the two copies had already begun to
    disagree about who used them.

    Args:
        num: the exercise number as a two-character STRING, "00", "07", "16".
            Every path and every target name here is built by concatenating it
            -- deliverable/exNN/, tests/exNN/, exNN_output -- so "0" would
            quietly look in deliverable/ex0/ and emit a target nobody can find.
            (An integer does not even get that far: "ex" + 0 is a Starlark type
            error.)
        fn: the subject's function. It does three jobs: it names the unit of
            the exercise's files that other binaries link (:fn, a student_unit
            -- so it has to be unique within the module), it is the default
            `exports` entry, and it labels the valgrind and allocfail reports
            as "exNN/fn".
        test: the harness, named relative to tests/exNN/ -- a main() that calls
            fn and prints. It is compiled into exNN_bin against the student's
            library and is never turned in. A function exercise's deliverable
            has no main() at all, which is exactly why this shape needs a
            harness the student does not write.
        srcs: the deliverable sources. Defaults to a GLOB of the .c files
            the contract names or allows in the turn-in directory, and no
            other (see _deliverable_srcs, _turnin_files). When there are none,
            the exercise's programs are stand-ins saying so and its static
            layers are "not turned in" tests; nothing fails to build.
            Nothing in the repo overrides it, and c-07 ex04
            -- the one exercise whose subject asks for two files -- carries a
            comment saying not to: the file set is written down once, in the
            project's subject() contract, to be CHECKED against the directory
            rather than copied into the build.
        hdrs: more headers to stage as part of the turn-in. No call site
            needs one: the headers the contract's `files` names (C 12's and
            C 13's ft_list.h / ft_btree.h, which the subject dictates the
            contents of but still asks for) come first, and every other one
            the contract lets lie in the turn-in directory after them (see
            _deliverable_hdrs). They are staged for every build of the
            exercise, each one's directory reaches the compile, forbidden,
            symbols, prototype, ilp32 and allocfail runners as an -I, and they
            are norminette-checked along with srcs -- which is right, because
            the Moulinette norms them too. A named header that is missing is
            dropped (_zone), never a Bazel "missing input" error: the compile
            that needed it fails in the compiler's words, and the files layer
            names it.

        WHAT THE GRADER BRINGS comes from the contract's `provided`, never from
        a call site. A header there (C 08's ft_stock_str.h, the ft_list.h C 12
        ex08's page says the grader uses) is staged from tests/ for every
        layer, its directory joins the include path -- the unit's, and the
        prototype and ilp32 runners' -- and it is NOT normed as the student's:
        a file the grade never looks at cannot fail the grade, so a red there
        would be a red that does not exist on the Moulinette. It gets
        exNN_norm_provided at complete instead. A source there (Piscine
        Reloaded's ft_putchar.c: "If ft_putchar() is an authorized function,
        we will compile your code with our ft_putchar.c") joins every BUILD of
        the student's code (the unit, so the harness, c_diff and c_perf get
        it; ilp32; allocfail) and none of the layers that judge the student's
        own files: norm, compile, forbidden, prototype and symbols see `srcs`
        alone, so ft_putchar stays an undefined, authorised call there.
        Forbidden and symbols do get the NAMES, one per file by 42's
        convention (ft_putchar.c supplies ft_putchar), so a student who
        defines one anyway is told so rather than told about the write()
        inside it. And each provided source defines its functions WEAK: a
        student's second definition then wins the link instead of breaking
        the build for every other test (see tests/ft_putchar.c).

        NO OTHER EXERCISE'S FILES ARE LINKED IN. There used to be a `deps`
        here, for an exercise that calls a function an earlier exercise of
        the same student wrote. The five that used it (c-12 ex01, ex04, ex05,
        ex16 and c-13 ex04) call a function their subject says the GRADER
        brings ("From exercise 01 onward, we'll use our ft_create_elem"),
        and linking the student's ex00 there made a bug in ex00 an
        unexplained red in a correct ex04 (finding 136). The contract's
        `linked` links the grader's copy instead (see _linked()). With no
        call site left, `deps` was code no test ran, which a next project
        could reach for in exactly that mistake, so it is gone: a subject
        that has one exercise call another's function names who brings it,
        and that is `linked` (the grader's) or the exercise's own files.
        expected: the fixture the harness's stdout is compared against, a
            filename under tests/exNN/; defaults to "expected.txt". The same
            file is the correctness GATE for the valgrind and allocfail layers
            -- both SKIP while it is red, so a memory report never speaks over
            the top of a wrong answer -- and it is what the 32-bit rebuild is
            diffed against too.
        sanitize: the fixture is a hex dump whose leading 16-hex-digit address
            column cannot be written into a fixture, because ASLR moves it on
            every run. The harness publishes each address it passes on a line
            of its own ("@addr <16 hex>") before the dump, and diff_output.sh
            takes that line out, checks every row's address against it (the
            k-th row's is that address plus 16k) and shows a right one as its
            offset, which is what the fixture holds. A harness that publishes
            nothing would get the width, letter case and +16 step compared,
            never the value, so //tools:conventions refuses a c_function with
            sanitize = True whose harness (or a reading's) never writes
            "@addr". Default False; c-02 ex12 (ft_print_memory) is the only
            user. It is forwarded to the valgrind and allocfail gates, to the
            ilp32 replay and to every reading, so they all read the fixture
            the same way.
        labeled: each line of the harness output and of the fixture is
            "CASE<TAB>VALUE", and the CASE is shown in its own column instead
            of the 1-based line number. Default False. Worth turning on
            wherever a reader has to tell the cases apart -- and it is what
            gives `clues` the case labels its hint groups are addressed to.
            Forwarded to the gates and to ilp32, like `sanitize`.
        escaped_values: with `labeled`, the harness writes each VALUE in the
            notation the table renders bytes in (\\\\ a backslash, \\n a
            line break, \\t a tab, \\xHH any other byte outside printable
            ASCII), because the value holds a byte that cannot travel raw: C 02
            ex01 and ex10 show a whole buffer, NULs included. diff_output.sh
            then keeps the notation's backslashes instead of escaping them a
            second time, and checks the expected file is written in it (see
            HARNESS-ESCAPED VALUES there). Default False. //tools:conventions
            refuses a harness that writes an escape of its own (a string
            literal starting with an escaped backslash) without it. Reaches
            the output layer and the ilp32 replay, the two that print a table.
        clues: a tab-separated hint file under tests/exNN/, conventionally
            clues.tsv: one concept group per line, the hint text first and then
            the CASE labels that belong to it. A group fires when ANY of its
            member cases fails; a line with no labels fires on any failure.
            Default None, which means a failing test shows the table and no
            hints -- a real loss for a beginner, so nearly every call site
            passes one. Fired hints print under the table, most fundamental
            first, capped at three (--test_env=CLUE_MODE=all lifts the cap, an
            integer sets it). It reaches the output layer, the ilp32 replay and
            -- when malloc = True -- the valgrind report, which has no per-case
            table to attach hints to and so prints the hint column of the first
            three lines. It does NOT reach the allocfail layer.
        malloc: this exercise is allowed to allocate; emits exNN_valgrind.
            Refused False where the contract's allowed functions name malloc
            or free (_function_malloc_problem): a call-site argument still,
            because a function may allocate through a helper the subject
            allows (C 12's ft_create_elem), which the contract cannot say.
            Default False, and it belongs off wherever the subject's "Allowed
            functions" line does not include malloc: there, a deliverable that
            allocates fails exNN_forbidden first, and a leak layer would be
            watching for something that cannot happen (c-00's BUILD.bazel
            writes that rule out in full, and c-11 points back at it). Where it
            is ON it is the only layer in the suite that can see a block
            allocated and never accounted for: a leak changes no output byte
            and crashes nothing, and rust_diff.sh, asan_run.sh and
            asan_check.sh all set detect_leaks=0 on purpose so that leaks stay
            this layer's finding. c-12's comment above ex01 works one such
            output-identical leak through end to end.
        THE FORBIDDEN LAYER'S LIST is the contract's `allowed` (plus its
            `variables`), the subject's "Allowed functions" line as written.
            forbidden_symbols.sh compiles each source alone and reads the
            functions it actually CALLS out of nm, so an unauthorised call
            fails here instead of on the Moulinette. What it forgives besides
            the list: a function this exercise's own sources define, and a
            short baseline of compiler-emitted builtins (memcpy/memmove/memset
            and friends), which code generation inserts rather than you. A
            contract `allowed = None` -- a subject with no such line -- emits
            no forbidden layer at all. Where glibc compiles a name into another
            symbol (the <ctype.h> classifiers into __ctype_b_loc), the runner's
            alias table maps it back.
        exports: the global symbols the deliverable may define. Defaults to
            exactly [fn] -- the Moulinette links your file with a main() you
            have never seen, so every non-static helper is a name that can
            collide with theirs. Pass a list when a subject legitimately asks
            for several public functions, or [] to skip the layer. A helper
            that one of the exercise's own files defines and another calls is
            exempt automatically, since `static` would stop it linking, so a
            multi-file exercise does not have to enumerate its cross-file
            helpers here.
        prototype: require tests/exNN/prototype.h and check the deliverable's
            signature against it, by force-including that header while
            compiling the definition: C has no name mangling, so a wrong
            signature still links and the only symptom is wrong values. Default
            True, and a MISSING header is then an analysis-time fail() rather
            than a silently absent layer -- that silence had cost all of c-13
            and six of c-12 a level-1 layer. Pass False only to record a
            deliberate opt-out; it suppresses that fail() and nothing else, so
            an exercise that has the header anyway still gets the layer.
        ilp32: also build and run the SAME harness against the same fixture on
            a 32-bit target, where long is no wider than int (see
            tools/ilp32_test.sh) -- which turns "widen the int into a long so
            INT_MIN is representable" from a platform accident into a red test.
            Default True. It rebuilds `test` + `srcs`, and the grader's
            `linked` library as its i686 twin, with the hermetic zig Bazel
            fetches, which in its default debug mode also stops the program (SIGILL) at undefined
            behaviour such as a signed overflow. Skips loudly where no 32-bit
            compiler can be found, and skips as well while the ordinary 64-bit
            fixture is still failing -- checked by rebuilding the same files
            with the pinned clang -- so a red here means something about the
            32-bit build. NO_SKIP=1 runs it past that gate and turns the
            missing-compiler skip into a failure; the report then says whether
            the 64-bit build passed, and blames the type model only when it
            did.
        allocfail: the name of a tests/exNN/ file, conventionally af_<fn>.c,
            defining af_case(), which makes ONE call into the deliverable. The
            layer then reruns it with each of its malloc calls refused in turn,
            and requires it to report the error rather than use the pointer
            (see tools/allocfail_check.sh). Default None. Setting it without
            malloc = True is a fail(): "sets allocfail but not malloc = True. A
            function that does not allocate has no allocation to refuse."

            DELIBERATELY OPT-IN, and the reason is the same one every c_files
            block records: pinning a behaviour the subject does not ask for
            invents a requirement. Most allocating exercises ask for NULL on
            LOGICAL conditions (min >= max, an invalid base) and say nothing
            about a failed allocation. Setting it without allocfail_rule
            is a fail(): if you cannot find a sentence to quote, that is the
            answer.
        allocfail_rule: the sentence that says what the function does
            when an allocation fails, naming where it is from -- the
            exercise's subject ('C 08, p.11: "It should return a NULL pointer
            if an error occurs."'), or the man page it sends you to (C 07
            ex00: man strdup). Required with `allocfail`
            (allocfail_rule_problem). Both allocfail targets print it under
            their verdict, and no other sentence, as the standard they apply:
            a runner cannot know which subject it is reading (finding 082: it
            used to quote C 08's at every exercise). One line; written to a
            file (exNN_allocfail_rule) and handed to the runner as --rule,
            since sh_test tokenises `args` on blanks.
        allocfail_level: raise THIS exercise's allocfail test above the layer's
            own level -- the same knob, and the same upward-only restriction,
            as _test's `level`.

            It exists because the justification for this layer is per-exercise
            and _LAYER_LEVEL can hold only one number. The layer sits where the
            exercises that CITE a contract put it: c-08 ex04's subject states
            the NULL return in its own words, and c-07 ex00's says "reproduce
            the behavior of strdup (man strdup)", where the man page states it.
            An exercise enabled on a weaker hook than that -- this repo's own
            rigour rather than a sentence anyone can point at -- raises itself
            here instead of dragging the cited ones up with it. Default None,
            and no call site needs it today, because both live ones cite a
            contract.
        readings: the readings of a sentence the subject leaves open, each a
            case dict (keys: _CASE_KEYS["reading"], and its kind) run by a
            harness of its own over the same unit, at strict or above. D3 puts
            an ambiguous sentence at strict at most, and `test` holds only what
            every reading agrees on; a reading is where the harness writes the
            one it takes down, with a clue that says so. Each emits
            exNN_<name>_bin, built from tests/exNN/<main> like the fixture's
            binary (the grader's `linked` functions included), and
            exNN_<name>_output at the case's "level" -- which it must name,
            since a reading is never basic -- listed in _RAISED with its row
            in docs/reference.md. Only the output layer runs it: valgrind,
            allocfail and ilp32 replay `test`, and every other layer's gate
            reads `test`'s fixture. C 12 ex11's "returns the address of the
            first element's data" against a t_list * return type is one,
            ex11_element_output at strict; C 07 ex04's whitespace in base_to
            another, ex04_base_to_space_output at strict. Default none.
        allocfail_leaks: True adds exNN_allocfail_leaks, at robust: the same
            sweep with free() wrapped too, judging whether a run that reported
            the error left any block it had obtained still allocated
            (allocfail_check.sh --leaks). The basic exNN_allocfail keeps its
            verdict: no subject asks for the release and no grader at 42
            injects a refusal, so this is the repo's own rigour, which is what
            robust is for (finding 084). Needs `allocfail`, and refused unless
            the subject() contract lets the exercise call free(): a function
            that may not call it cannot be asked to release anything. Default
            False.
        method: "recursive" or "iterative", where the subject says which
            the function must be ("Create a recursive function", "Recursion
            is required", "Create an iterative function"): emits exNN_method,
            the method layer at strict (tools/method_check.sh). It runs the
            exercise's own `test` once more, with the student's sources --
            and only those -- compiled at -O0 with -finstrument-functions,
            and reads whether a function of theirs was entered again while
            it was still running: recursive is "some was" (the function, a
            static helper, two that call each other), iterative "none ever
            was" (a closed form or a table is iterative; a loop over a stack
            of its own is not recursive). Gated on this exercise's output
            fixture, like the memory layers, and compares it as they do
            (`sanitize`, `labeled`). Needs `method_rule`; refused where the
            grader links a function (the runner links no library).
            Default None, no target.
        method_rule: the subject's sentence that asks for `method`, quoted,
            with where it is from: the report prints it under its verdict
            (method_problem). One line; written to exNN_method_rule.
        name: unused, for the reason c_levels gives: every macro takes one,
            and buildifier's unnamed-macro check holds this one to it since it
            declares rules (the :fn unit, the programs). Every target here is
            named from `num` and `fn`, so there is nothing for it to
            control."""
    _entry(num, "c_function")  # first: a contract error names this macro
    problem = _function_malloc_problem(num, malloc, _entry(num, "c_function"))
    if problem:
        fail(problem)
    if escaped_values and not labeled:
        fail(("c_function(num = \"%s\") sets escaped_values but not labeled = True: " +
              "the notation is the VALUE's, and only a labeled row has one.") % num)
    ex = "ex" + num
    if srcs == None:
        srcs = _deliverable_srcs(ex)
        hdrs = _deliverable_hdrs(ex, hdrs)
    srcs = _zone(srcs)
    hdrs = _zone(hdrs or [])
    provided = _provided(num)
    provided_hdrs = provided.hdrs
    provided_srcs = provided.srcs
    extra_includes = provided.includes
    allowed = _allowed(num)
    linked = _linked(num)

    # Every layer below stages BOTH kinds -- a header the harness needs in order
    # to compile is needed whoever wrote it. The single place the two part
    # company is _norm_test, which sees `hdrs` alone: see the docstring.
    all_hdrs = hdrs + provided_hdrs
    includes = [turnin_dir(num)] + extra_includes

    # What gets LINKED is the student's code plus whatever the grader supplies;
    # what gets JUDGED below (norm, compile, forbidden, prototype, symbols) is
    # the student's code alone.
    build_srcs = srcs + provided_srcs

    # The unit every binary of this exercise links. It builds nothing: each
    # binary compiles it with its own flags, so the ASan twin needs no library
    # of its own.
    _student_lib(
        name = fn,
        srcs = build_srcs,
        hdrs = all_hdrs,
        includes = includes,
    )
    _norm_test(ex + "_norm", srcs + hdrs)

    # A provided header is still held to the Norm -- it is just not the
    # STUDENT's red. Separate target, separate name, and level 4 so it can never
    # appear in the `basic` suite a beginner runs or in the submit gate: what it
    # reports is "this repo's own staged header drifted", which is a maintainer's
    # job and nothing the person doing the exercise can act on.
    if provided_hdrs:
        _norm_test(ex + "_norm_provided", provided_hdrs, level = 4)

    _compile_tests(ex, srcs, all_hdrs, grader_hdrs = provided_hdrs)

    # Declared ahead of the fixture that links the function, which names it.
    # The subject's structure, at basic where the grader links a function
    # built on it (see _prototype_test), at strict elsewhere.
    proto_test = _prototype_test(
        ex,
        srcs,
        all_hdrs,
        extra_includes,
        prototype,
        layouts = _layouts(num),
        layout_certain = bool(linked.libs),
        grader_hdrs = provided_hdrs,
    )

    binname = ex + "_bin"
    test_f = "tests/%s/%s" % (ex, test)
    _output_fixture_binary(
        name = binname,
        harness = [test_f],
        prototype = proto_test or "none: prototype = False at the call site, which says why",
        deps = [":" + fn] + linked.libs,
        dir = turnin_dir(num),
    )

    expected_f = "tests/%s/%s" % (ex, expected)
    out_data = [":" + binname, expected_f]
    args = [
        "--bin",
        "$(location :%s)" % binname,
        # An _output_fixture_binary: after a crash its first missing row is
        # the case that was running (diff_output.sh checks the binary).
        "--harness-fixture",
        "--expected",
        "$(location %s)" % expected_f,
    ]
    if sanitize:
        args.append("--sanitize")
    if labeled:
        args.append("--labeled")
    if escaped_values:
        args.append("--escaped-values")

    # Hoisted out of the `if` so it is initialised on every path. It is only ever
    # USED when `clues` is set, but buildifier cannot see that the guard at the
    # ilp32 block below is the same condition, and reports it as possibly
    # uninitialised. A warning that is always noise teaches people to ignore
    # warnings, so the cheaper fix is to remove the ambiguity.
    clues_f = "tests/%s/%s" % (ex, clues) if clues else None
    if clues:
        args += ["--clues", "$(location %s)" % clues_f]
        out_data.append(clues_f)
    w_args, w_data = _waiting_args(ex + "_output")
    _test(
        name = ex + "_output",
        srcs = ["//tools:diff_output.sh"],
        args = args + w_args,
        data = out_data + w_data,
        tags = ["output"],
    )

    # The readings the subject leaves open, each a harness of its own over the
    # same unit, above basic (see `readings`).
    for c in readings or []:
        k = _case(c, "reading", "c_function(num = \"%s\")" % num)
        r_bin = "%s_%s_bin" % (ex, k.name)
        reading_test_f = "tests/%s/%s" % (ex, c["main"])
        _output_fixture_binary(
            name = r_bin,
            harness = [reading_test_f],
            prototype = proto_test or "none: prototype = False at the call site, which says why",
            deps = [":" + fn] + linked.libs,
            dir = turnin_dir(num),
        )
        compare, expected_fs = _expected_args(ex, k)
        r_args = ["--bin", "$(location :%s)" % r_bin, "--harness-fixture"] + compare
        r_data = [":" + r_bin] + expected_fs

        # The exercise's own output is a dump whose addresses ASLR moves:
        # so is a reading's, which runs the same function. Compared raw, a
        # correct answer's addresses would differ on every run.
        if sanitize:
            r_args.append("--sanitize")
        if c.get("labeled"):
            r_args.append("--labeled")
        if c.get("clues"):
            r_clues = "tests/%s/%s" % (ex, c["clues"])
            r_args += ["--clues", "$(location %s)" % r_clues]
            r_data.append(r_clues)
        _test(
            name = "%s_%s_output" % (ex, k.name),
            srcs = ["//tools:diff_output.sh"],
            args = r_args,
            data = r_data,
            tags = ["output"],
            level = _raise("output", k.level),
        )
    if malloc:
        # Gated on this exercise's own fixture, like every other rigour layer.
        # Until this was wired, valgrind was the one that spoke over the top of
        # the output layer: c-12 ex06 is an unwritten stub, and it answered with
        # eight raw "indirectly lost" records rather than "your output layer is
        # still red". Leaks come last — after the function produces the right
        # bytes at all.
        v_args = [
            "--bin",
            "$(location :%s)" % binname,
            # No space: sh_test tokenises `args` on whitespace, so a two-word
            # label would arrive as two arguments and the second would be
            # rejected as an unknown option.
            "--label",
            "%s/%s" % (ex, fn),
            "--gate-differ",
            "$(location //tools:diff_output.sh)",
            "--gate-bin",
            "$(location :%s)" % binname,
            "--gate-expected",
            "$(location %s)" % expected_f,
        ]
        if sanitize:
            v_args.append("--gate-sanitize")
        if labeled:
            v_args.append("--gate-labeled")
        v_data = [":" + binname, expected_f, "//tools:diff_output.sh"]

        # valgrind_test.sh has implemented --clues correctly since it was
        # written -- first column only, capped at three -- and no macro had ever
        # passed it one, so the layer most likely to leave a beginner stuck
        # ("40 bytes in 1 blocks are definitely lost") was the one layer with no
        # hint attached. The renderer needed nothing; only this line was missing.
        if clues:
            v_args += ["--clues", "$(location %s)" % clues_f]
            v_data.append(clues_f)
        _test(
            name = ex + "_valgrind",
            srcs = ["//tools:valgrind_test.sh"],
            args = v_args + _valgrind_args(),
            data = v_data + _valgrind_data(),
            size = "small",
            tags = ["valgrind"],
        )
    else:
        # NO-MALLOC-ALLOWED LICENSES THE LEAK HALF, AND ONLY THE LEAK HALF.
        #
        # Where a subject's "Allowed functions" line has no malloc, this repo
        # dropped the whole memory layer, reasoning that "there is no allocation
        # for valgrind to report on". True of leaks. memcheck reports nine
        # classes and four of them are leaks; invalid read, invalid write,
        # invalid free and uninitialised value need no allocation at all, and
        # ASan -- which these exercises DO get, wherever a c_mem_check probe or
        # a c_diff crash-fuzz arm exists -- has no uninitialised-memory checker
        # of any kind.
        #
        # MEASURED, on the shape half this Piscine is built out of: a fixed
        # 4-byte buffer with 3 bytes filled and all 4 handed to write() runs
        # SILENTLY under -fsanitize=address,undefined -fno-sanitize-recover=all,
        # and memcheck says "Syscall param write(buf) points to uninitialised
        # byte(s)". c-00 ex06/ex08, c-02 ex11/ex12 and c-04 ex02/ex04 all build
        # their output that way.
        #
        # rush_variant has emitted a valgrind arm unconditionally for a module
        # whose allowed list is ["write"] since it was written, so this is the
        # rule the repo was already following in one place and contradicting in
        # the others.
        #
        # Gated on the exercise's own fixture, exactly like the arm above: a
        # memory report over a function that is not yet returning the right
        # bytes speaks over the one red that matters.
        m_args = [
            "--bin",
            "$(location :%s)" % binname,
            "--label",
            "%s/%s" % (ex, fn),
            "--no-leak-check",
            "--gate-differ",
            "$(location //tools:diff_output.sh)",
            "--gate-bin",
            "$(location :%s)" % binname,
            "--gate-expected",
            "$(location %s)" % expected_f,
        ]
        if sanitize:
            m_args.append("--gate-sanitize")
        if labeled:
            m_args.append("--gate-labeled")
        _test(
            name = ex + "_memcheck",
            srcs = ["//tools:valgrind_test.sh"],
            args = m_args + _valgrind_args(),
            data = [":" + binname, expected_f, "//tools:diff_output.sh"] +
                   _valgrind_data(),
            size = "small",
            tags = ["valgrind"],
        )
    problem = _allocfail_problem(num, malloc, allocfail, allocfail_rule)
    if problem:
        fail(problem)
    if allocfail_leaks:
        why = allocfail_leaks_problem(allocfail, _allowed(num))
        if why:
            fail("c_function(num = \"%s\") sets allocfail_leaks, and %s" % (num, why))
    if allocfail:
        _no_linked(num, "c_function", "allocfail")
        names_file(
            name = ex + "_allocfail_rule",
            names = [allocfail_rule],
        )
        af_f = "tests/%s/%s" % (ex, allocfail)
        af_args = [
            "--rule",
            "$(location :%s_allocfail_rule)" % ex,
            "--harness",
            "$(location %s)" % af_f,
            "--shim",
            "$(location //tools:allocfail_shim.c)",
            "--label",
            "%s/%s" % (ex, fn),
            # Gated on the exercise's own fixture, exactly like valgrind above:
            # a stub that returns nothing has no error path worth discussing,
            # and this layer's report would speak over the top of the one red
            # test that actually matters.
            "--gate-differ",
            "$(location //tools:diff_output.sh)",
            "--gate-bin",
            "$(location :%s)" % binname,
            "--gate-expected",
            "$(location %s)" % expected_f,
        ]
        for s in build_srcs:
            af_args += ["--src", "$(location %s)" % s]
        af_args += _inc_args("--inc", all_hdrs)
        af_args += _pinned_build_args()
        if sanitize:
            af_args.append("--gate-sanitize")
        if labeled:
            af_args.append("--gate-labeled")
        _test(
            name = ex + "_allocfail",
            srcs = ["//tools:allocfail_check.sh"],
            args = af_args,
            data = build_srcs + all_hdrs + _PINNED_BUILD_DATA + [
                af_f,
                ":" + binname,
                ":%s_allocfail_rule" % ex,
                expected_f,
                "//tools:allocfail_shim.c",
                "//tools:allocfail_counter.h",
                "//tools:diff_output.sh",
            ],
            size = "small",
            tags = ["allocfail"],
            level = allocfail_level,
            turnin = srcs,
            gated = True,
        )
        if allocfail_leaks:
            _test(
                name = ex + "_allocfail_leaks",
                srcs = ["//tools:allocfail_check.sh"],
                args = af_args + ["--leaks"],
                data = build_srcs + all_hdrs + _PINNED_BUILD_DATA + [
                    af_f,
                    ":" + binname,
                    ":%s_allocfail_rule" % ex,
                    expected_f,
                    "//tools:allocfail_shim.c",
                    "//tools:allocfail_counter.h",
                    "//tools:diff_output.sh",
                ],
                size = "small",
                tags = ["allocfail"],
                # robust: the _allocfail_leaks suffix's level (_SUFFIX_LAYER),
                # the repo's own rigour -- see allocfail_leaks above.
                level = 3,
                turnin = srcs,
                gated = True,
            )

    why = method_problem(method, method_rule)
    if why:
        fail("c_function(num = \"%s\"): %s" % (num, why))
    if method:
        _no_linked(num, "c_function", "method")
        names_file(
            name = ex + "_method_rule",
            names = [method_rule],
        )
        m_args = _pinned_cc_args() + _pinned_ld_args() + [
            "--expect",
            method,
            "--rule",
            "$(location :%s_method_rule)" % ex,
            "--harness",
            "$(location %s)" % test_f,
            "--shim",
            "$(location //tools:method_shim.c)",
            # Gated on the exercise's own fixture: a stub calls nothing twice,
            # and a wrong answer has no method worth reading yet.
            "--gate-differ",
            "$(location //tools:diff_output.sh)",
            "--gate-bin",
            "$(location :%s)" % binname,
            "--gate-expected",
            "$(location %s)" % expected_f,
        ]
        # The gate compares the fixture as the output test does, or a
        # sanitized or labeled one would read red on a right answer and the
        # layer would stand down for good -- as the memory layers' gates.
        if sanitize:
            m_args.append("--gate-sanitize")
        if labeled:
            m_args.append("--gate-labeled")
        for s in srcs:
            m_args += ["--src", "$(location %s)" % s]
        for s in provided_srcs:
            m_args += ["--grader-src", "$(location %s)" % s]
        m_args += _inc_args("--inc", all_hdrs)
        _test(
            name = ex + "_method",
            srcs = ["//tools:method_check.sh"],
            args = m_args,
            data = srcs + provided_srcs + all_hdrs + _PINNED_CC_DATA + _PINNED_LD_DATA + [
                test_f,
                expected_f,
                ":" + binname,
                ":%s_method_rule" % ex,
                "//tools:method_shim.c",
                "//tools:diff_output.sh",
            ],
            tags = ["method"],
            turnin = srcs,
            gated = True,
        )

    if allowed != None:
        _forbidden_test(
            ex + "_forbidden",
            srcs,
            allowed,
            hdrs = all_hdrs,
            provided = _provided_names(provided_srcs) + linked.names,
        )

    # Linkage hygiene: exactly the subject's function is visible to the linker.
    if exports == None:
        exports = [fn]
    if exports:
        # The pinned clang as well as the pinned nm: this test used to get
        # the nm alone, so it compiled with the box's cc (SYMBOLS_CC's
        # default) while _symbols_test, beside it, was handed the pinned one
        # -- found by pinned_cc_problem the day it was written (TO VERIFY V38).
        sym_args = _pinned_cc_args() + _pinned_nm_args() + ["--expect", ",".join(exports)]
        for p in _provided_names(provided_srcs) + linked.names:
            sym_args += ["--provided", p]
        for s in srcs:
            sym_args += ["--src", "$(location %s)" % s]
        sym_args += _inc_args("--inc", all_hdrs)
        _test(
            name = ex + "_symbols",
            srcs = ["//tools:symbols_test.sh"],
            args = sym_args,
            data = srcs + all_hdrs + _PINNED_CC_DATA + _PINNED_NM_DATA,
            tags = ["symbols"],
            turnin = srcs,
        )

    # The same cases replayed where long is no wider than int.
    if ilp32:
        _ilp32_test(
            ex,
            test_f,
            expected_f,
            build_srcs,
            all_hdrs,
            extra_includes,
            sanitize,
            labeled,
            clues_f if clues else None,
            ":" + binname,
            turnin = srcs,
            linked = linked,
            escaped_values = escaped_values,
        )

def _ilp32_test(
        ex,
        test_f,
        expected_f,
        srcs,
        hdrs,
        extra_includes,
        sanitize,
        labeled,
        clues_f,
        gate_bin,
        turnin = None,
        linked = None,
        escaped_values = False):
    """The 32-bit replay of one exercise's own fixture (tag "ilp32").

    Rebuilds the SAME harness and the SAME sources against a target where long
    is no wider than int, and diffs against the same expected file -- which
    turns "widen the int into a long so INT_MIN is representable" from a
    platform accident into a red test.

    Extracted from c_function so that c_libft can have it too. It was written
    inline there, which is the only reason c-09's two exercises went without: a
    libft bundle has the same harness/sources/fixture shape the runner wants,
    and the gap was a macro boundary rather than a decision anyone made.

    Args:
        ex: "exNN", used to name the target.
        test_f: the harness under tests/exNN/ -- the same main() the 64-bit
            output layer runs.
        expected_f: the fixture both replays are compared against.
        srcs: the deliverable sources, rebuilt from scratch for the 32-bit
            target; nothing is linked from the 64-bit build.
        hdrs: headers to stage; each one's DIRECTORY joins the include path.
        extra_includes: package-relative directories to add to it as well.
        sanitize: the fixture is a hex dump whose address column is rewritten
            before comparison, as in the 64-bit layer.
        labeled: the fixture is "CASE<TAB>VALUE"; show the case column.
        clues_f: this exercise's hint file, or None.
        gate_bin: the label of the program *_output runs, the same harness
            over the same files: the layer's 64-bit gate (--gate-bin). Its
            own rebuild with every warning silenced passed code *_output
            reports as not building, and then said the 64-bit build passes.
        turnin: the student's own sources among `srcs`, as a glob found them
            (see _test); default `srcs`. None of them there: the layer is a
            "not turned in" test.
        linked: _linked()'s struct for the exercise, or None: each library
            the grader links goes to the runner as --lib32, its i686 twin,
            for the 32-bit build; the 64-bit program has the x86_64 archive
            linked already.
        escaped_values: c_function's; the harness writes each value in the
            table's notation (diff_output.sh --escaped-values).
    """
    i_args = [
        "--gate-bin",
        "$(location %s)" % gate_bin,
        "--zig",
        "$(location @zig_linux_x86_64//:zig)",
        "--differ",
        "$(location //tools:diff_output.sh)",
        "--harness",
        "$(location %s)" % test_f,
        # The same unbuffered stdout as the 64-bit fixture, so a crash here
        # keeps the rows before it too (tools/unbuffered_stdout.c).
        "--harness-src",
        "$(location %s)" % _UNBUFFERED_C,
        "--expected",
        "$(location %s)" % expected_f,
    ]
    for s in srcs:
        i_args += ["--src", "$(location %s)" % s]
    i_args += _inc_args("--inc", hdrs)
    for d in (extra_includes or []):
        i_args += ["--inc", d]
    if sanitize:
        i_args.append("--sanitize")
    if labeled:
        i_args.append("--labeled")
    if escaped_values:
        i_args.append("--escaped-values")
    i_data = [
        gate_bin,
        test_f,
        _UNBUFFERED_C,
        expected_f,
        "//tools:diff_output.sh",
        "@zig_linux_x86_64//:zig",
        "@zig_linux_x86_64//:sdk",
    ] + srcs + hdrs
    if clues_f:
        i_args += ["--clues", "$(location %s)" % clues_f]
        i_data.append(clues_f)
    if linked:
        for lib in linked.libs32:
            i_args += ["--lib32", "$(location %s)" % lib]
        i_data += linked.libs32
    _test(
        name = ex + "_ilp32",
        srcs = ["//tools:ilp32_test.sh"],
        args = i_args,
        data = i_data,
        tags = ["ilp32"],
        turnin = srcs if turnin == None else turnin,
        gated = True,
    )

def c_mem_check(num, fn, probe, srcs = None, hdrs = None, prototype = None, name = None):
    """Memory-safety layer: run fn plus a probe under ASan/UBSan (tag "asan").

    Catches out-of-bounds reads and writes past an n/size bound that still
    return the correct VALUE and so slip past stdout diffing.

    Emits three targets: exNN_asan (the probe under ASan/UBSan), exNN_memprobe
    (the same probe compiled plain, tagged manual so it is built only when
    something runs it) and exNN_probe_memcheck (that binary under the pinned
    memcheck with leak reporting off) -- see the block above the memcheck arm
    for why one sanitizer is not enough.

    Args:
        num: the exercise number as a two-character STRING, "00", "07", "12" --
            the same one the exercise's c_function() was given. It selects
            deliverable/exNN/ and tests/exNN/ and names every target this
            macro emits: exNN_asan (tag "asan", level `robust`) and
            exNN_probe_memcheck (tag "valgrind", level `strict`), over the
            exNN_memprobe binary.
        fn: the subject's function, used for ONE thing here: it labels the
            memcheck report ("exNN/<fn>-probe"). It is not part of any target
            name -- exNN_asan is named from num alone. Keep it identical to the
            c_function() call for the same num.
        probe: an adversarial main() under tests/exNN/, named mem_*.c by
            convention. It hands the function blocks sized to fit EXACTLY, with
            nothing valid on either side, so that a single step past what the
            function was given lands in a sanitizer redzone instead of on a
            harmless neighbouring byte. That is the whole point of the layer:
            an out-of-bounds read that still returns the right value is
            invisible to every diff of stdout. Probes here are written so that
            an unimplemented stub survives them (it touches nothing, so it
            cannot overrun anything), which is why this layer needs no
            correctness gate of the kind valgrind and allocfail carry. Say at
            the CALL SITE which fault the probe is aimed at -- every existing
            call site does -- and put the details in the probe's own header
            comment.
        srcs: the deliverable sources compiled together with the probe.
            Defaults to a GLOB of deliverable/exNN/*.c; when there is none, the
            probe layers are "not turned in" tests and the memcheck program is
            a stand-in that says so (see _test and _student_bin). Override it
            only when the probe cannot be built from one exercise's directory
            alone; no call site does. A function the grader brings (the
            contract's `linked`: c-12 ex05's real push_strs builds its nodes
            with the grader's ft_create_elem) is linked into both probe
            builds without it: the runner takes the library's archive with
            --lib, and the memcheck program links it.
        hdrs: headers the probe or the sources include but which do not live
            beside them -- the sibling exercise's ft_list.h that the srcs
            override above dragged in. What the grader brings (the contract's
            `provided`: C 08's ft_stock_str.h, Reloaded's ft_putchar.c) is
            added on its own: a header is staged and on the -I list, a source
            is linked into both probe builds. Each is staged as a data dependency and its DIRECTORY is added
            to -I; none of them is compiled. With `srcs` left at its default,
            every deliverable/exNN/*.h is added after the ones listed (see
            _deliverable_hdrs): a directory on the -I list is not enough on its
            own, because a header that is not declared is not in the sandbox.
            Unlike c_function's hdrs these are not norm-checked here; the norm
            layer for a turned-in header belongs to the c_function() call.
            Their directories reach the -I list of both the sanitized compile
            and the plain one.
        prototype: the test that checks the signatures this macro's harness
            calls, as _student_bin requires of every harness: default
            "exNN_prototype", the one c_function declares for this exercise.
            c_levels()' audit fails a package that does not declare it. Where
            there is none, say why: "none: <the reason>".
        name: unused, for the reason c_levels gives: every macro takes one,
            and buildifier's unnamed-macro check holds this one to it since it
            declares a rule (a program built from the student's files, see
            _student_bin). Every target here is named from `num`, so there is
            nothing for it to control.
    """
    _entry(num, "c_mem_check")  # first: a contract error names this macro
    ex = "ex" + num
    if srcs == None:
        srcs = _deliverable_srcs(ex)
        hdrs = _deliverable_hdrs(ex, hdrs)
    own_srcs = _zone(srcs)
    provided = _provided(num)
    hdrs = _zone(hdrs or [])
    hdrs = hdrs + [h for h in provided.hdrs if h not in hdrs]
    srcs = own_srcs + provided.srcs
    probe_f = "tests/%s/%s" % (ex, probe)

    # The grader's own functions (the contract's `linked`): the x86_64
    # archive, linked after the sources in both probe builds.
    libs = _linked(num).libs

    # --probe-src as well as --probe: the same file, but the runner reads its
    # header COMMENT out of it to explain a failure. Every probe already says
    # what it allocates and what an off-by-one would look like, written beside
    # the allocation; that beats any sentence written twice, and it cannot
    # drift from the probe because it is the probe.
    args = [
        "--probe",
        "$(location %s)" % probe_f,
        "--probe-src",
        "$(location %s)" % probe_f,
    ]
    for s in srcs:
        args += ["--src", "$(location %s)" % s]
    args += _inc_args("--hdr", hdrs)
    for lib in libs:
        args += ["--lib", "$(location %s)" % lib]
    _test(
        name = ex + "_asan",
        srcs = ["//tools:asan_check.sh"],
        args = _pinned_build_args() + args + _symbolizer_args(),
        data = _uniq(srcs + [probe_f] + hdrs + libs + _SYMBOLIZER_DATA + _PINNED_BUILD_DATA +
                     ["@clang_12_ubuntu//:sanitizer_runtime"]),
        tags = ["asan"],
        turnin = own_srcs,
    )

    # THE SAME PROBE UNDER MEMCHECK, for the class ASan structurally cannot see.
    #
    # NO-MALLOC-ALLOWED drops the whole valgrind layer wherever a subject
    # forbids malloc, on the ground that "there is no allocation for valgrind to
    # report on". That is true of the LEAK half and false of the rest: invalid
    # read, invalid write, invalid free and uninitialised value all need no
    # allocation whatsoever, and ASan has no uninitialised-memory checker at
    # all. Measured, on the exact shape c-00 ex06/ex08, c-02 ex11/ex12 and c-04
    # ex02/ex04 are built out of -- a fixed 4-byte buffer with 3 bytes filled,
    # all 4 handed to write() -- ASan+UBSan run silently and memcheck says
    # "Syscall param write(buf) points to uninitialised byte(s)".
    #
    # Leak checking is OFF here and that is not a carveout: the probe is OUR
    # main(), written to hand the function an exactly-sized block and exit, so a
    # leak report would be a finding about the probe. The exercise's own leaks,
    # where its subject allows allocation at all, are exNN_valgrind's.
    #
    # Tagged `valgrind`, so it sits at level 2 with the rest of memcheck's
    # findings: real, and conditional on something outside the subject.
    probe_dirs = depset(
        [_dirname(f) for f in [probe_f] + srcs + hdrs],
    ).to_list()

    # Every file linked directly, probe first, as the cc_binary this used to be
    # linked them: the probe is a main() over exactly these sources.
    _student_bin(
        name = ex + "_memprobe",
        harness = [probe_f],
        prototype = prototype or ex + "_prototype",
        srcs = srcs,
        hdrs = hdrs,
        deps = libs,
        includes = probe_dirs,
        archive = False,
        dir = turnin_dir(num),
        tags = ["manual"],
    )
    _test(
        name = ex + "_probe_memcheck",
        srcs = ["//tools:valgrind_test.sh"],
        args = [
            "--bin",
            "$(location :%s_memprobe)" % ex,
            # NO SPACE in the label: sh_test tokenises `args` on whitespace,
            # so "ex00/ft_foreach probe" arrives as two arguments and the
            # runner rejects the second as an unknown option. The same trap
            # c_files fail()s on and c_function's valgrind arm documents.
            "--label",
            "%s/%s-probe" % (ex, fn),
            "--no-leak-check",
        ] + _valgrind_args(),
        data = [":%s_memprobe" % ex] + _valgrind_data(),
        size = "small",
        tags = ["valgrind"],
    )

def diff_readings_problem(num, readings):
    """What is wrong with a c_diff call's `readings`, or "" when it is sound.

    One dict: "oracle_fn" (the arm writing the cases the readings part on, a
    name, required), and optionally "diff_clues" (a file under tests/exNN/),
    "count" (a positive int) and "level" (3 or 4: the reading's own level,
    strict, is the diff layer's). An unknown key fails, as a case key does.

    Public so //tools/tests:starlark_unit can check it at load time.

    Args:
      num: the exercise's number, for the message.
      readings: the call's readings, or None.

    Returns:
      The message to fail with, or "" when the call is sound.
    """
    if readings == None:
        return ""
    where = "c_diff(num = \"%s\", readings = %r)" % (num, readings)
    if type(readings) != "dict":
        return "%s: one dict, {\"oracle_fn\": ..., ...}: one reading per exercise." % where
    keys = ["count", "diff_clues", "level", "oracle_fn"]
    for k in sorted(readings):
        if k not in keys:
            return "%s: %r is not a key; the keys are %s." % (where, k, ", ".join(keys))
    o = readings.get("oracle_fn")
    if type(o) != "string" or not o or " " in o:
        return ("%s: \"oracle_fn\" names the //oracle arm that writes the cases the " +
                "readings part on, one word.") % where
    if "diff_clues" in readings and (type(readings["diff_clues"]) != "string" or
                                     not readings["diff_clues"] or "/" in readings["diff_clues"]):
        return "%s: \"diff_clues\" is a file name under tests/ex%s/." % (where, num)
    if "count" in readings and (type(readings["count"]) != "int" or readings["count"] < 1):
        return "%s: \"count\" is the corpus's size, a positive int." % where
    if "level" in readings and readings["level"] not in (3, 4):
        return ("%s: \"level\" is 3 or 4, where the reading is this repo's convention " +
                "rather than one reading of the sentence; a reading sits at strict, the " +
                "diff layer's own level, and needs none.") % where
    return ""

def c_diff(
        num,
        fn,
        harness,
        oracle_fn,
        seed = 1,
        count = 400000,
        asan_count = 200000,
        sanitize = True,
        diff_clues = None,
        gate_bin = None,
        gate_expected = "expected.txt",
        gate_labeled = False,
        gate_sanitize = False,
        gate_stdin = None,
        perf = True,
        perf_count = 200000,
        perf_length = None,
        size = "small",
        prototype = None,
        readings = None,
        name = None):
    """Live differential test (tag "diff").

    Diffs the student's function output against the Rust reference
    //oracle:oracle over a FIXED, seeded set of inputs. The reference emits
    `<hex-inputs>\\t<reference-output>` per case; a small reader harness
    (tests/exNN/<harness>) replays the same inputs through the student's fn and
    reprints `<hex-inputs>\\t<student-output>`; tools/rust_diff.sh byte-diffs the
    two. Links the unit of files the exercise's c_function already declared (:fn).

    Deterministic: same seed+count => identical cases every run (no test-time
    entropy). The reference is Rust under //oracle, built hermetically by Bazel
    (no system rustc) and run as a data dep of this test; it is never compiled
    into a deliverable/.

    Args:
        num: the exercise number as a STRING -- "04", never 4. Every target and
            path here is built from "ex" + num, and Starlark does not add an int
            to a string, so a bare 4 is an immediate analysis-time type error;
            "4" is worse, because it builds an "ex4" that quietly matches no
            files. Only ONE c_diff can attach to a given exercise, because the
            target names it derives are fixed (:exNN_diffbin, :exNN_diff); c-09
            ex00 records that constraint at its call site, where ft_strlen was
            left to c-01's arm rather than fighting for the name.
        fn: the unit of files the harness links, by target name -- the one
            c_function already declared for this exercise. That is why this
            layer declares no deliverable sources of its own (only the harness
            under tests/) and so cannot drift from the file set c_function
            globbed. With sanitize on, the same unit is compiled again under
            the sanitizer for the crash-fuzz binary. An exercise with no
            c_function, like c-09 ex00 whose sources are archived by the
            student's own build script, declares its unit with student_lib().
        harness: filename under tests/exNN/ of the READER: a small main() that
            takes the reference's cases on stdin, decodes the input fields (hex
            wherever the input is bytes), calls fn, and reprints "<the same
            input fields>\\t<student output>". tools/diffio.h is linked in
            automatically and holds the decode and print helpers -- among them
            dio_garbage and dio_dest, the destination buffer for a function
            that writes a string, whose free bytes are never 0. It is
            grader-side infrastructure and never a submission, so it may use
            libc freely and need not be norm-clean. Named diff_<what>.c, or
            this macro fails: //tools:conventions finds the harnesses by that
            name, to hold the header's "Line:" legend and the destination
            rule.
        oracle_fn: which arm of //oracle:oracle generates the corpus, e.g.
            "c07_strdup". The reference is run as `oracle <oracle_fn> <seed>
            <count>`; an unknown name exits 2 and this layer fails rather than
            quietly comparing nothing. Each arm's exact line format is
            documented beside it in oracle/src/<module>.rs, and the harness has
            to reprint the input fields byte for byte or every case "diverges".
        seed: default 1. Seeds the reference's SplitMix64, so seed and count fix
            the corpus exactly: same cases every run, on every machine, no
            wall-clock and no test-time entropy anywhere. Change it only to
            explore a different tail -- each generator emits its pinned contract
            corners FIRST, so only the random remainder moves.
        count: how many cases to ask the reference for; default 400000. This is
            the heaviest layer in the repo -- diff plus diff_asan are about 53%
            of a full run's CPU -- and roughly 90% of that is the reference
            GENERATING the corpus rather than the student replaying it, so this
            is the dial worth turning. Lower it for a function that write()s one
            byte at a time, as several subjects require: the writers in c-00
            ex07, c-01 ex05, c-02 ex11, c-04 ex02 and c-04 ex04 are
            syscall-bound on the replay side and run at 100000. A generator
            whose input space is finite simply ignores a larger request
            (c05_fibonacci enumerates 53 inputs, and that is the whole space).
            Fewer than 16 produced lines is a FAILURE rather than "OK (0
            cases)", because a differential layer that silently tests nothing is
            worse than no layer; MIN_DIFF_CASES in the environment moves that
            floor.
        asan_count: cases for the crash-fuzz twin; default 200000, deliberately
            below count -- the instrumented replay is slower per case, and this
            arm only asks whether the memory access is safe, not whether the
            value is right. Never above count: a call that lowers count below
            it raises count back or names an asan_count no larger
            (diff_asan_count_problem). Ignored when sanitize = False.
        sanitize: default True. Emits the second target, exNN_diff_asan: the
            same corpus replayed through an ASan/UBSan build of harness plus
            student, asserting no memory error and no UB. Values are NOT
            compared there -- a memory-safe stub passes it -- because its job is
            the out-of-bounds read that returns the right answer and so slips
            past the value diff. Leaks are excluded on purpose (detect_leaks=0);
            those belong to the valgrind layer. Turning this off also requires
            perf = False: the perf layer this macro emits gates on
            :exNN_diffbin_asan, which only this flag declares, and c_diff has no
            parameter for pointing that gate somewhere else -- so the pair
            sanitize = False, perf = True is a missing-target error at analysis
            time.
        WHAT ELSE IS LINKED is the contract's `linked`, the grader's own
            functions, into both binaries; never another exercise's files
            (see c_function: `deps` is gone, with its reason).
        diff_clues: a diff_clues.txt under tests/exNN/, printed WHOLE when the
            corpus diverges.

            Named apart from `clues` because the two file formats are not
            interchangeable, and the parameter is the only thing that says so.
            A clues.tsv is a table -- hint in column one, the case names it
            belongs to after -- rendered by cutting that column and capping it
            at three, so one failure never hands over the whole hint file. A
            diff_clues.txt is prose: a legend, then a list of which FAMILY of
            failing inputs implies what. Run a prose file through the tiered
            renderer and a student gets three bulleted fragments of a cut-off
            sentence, which is exactly what happened to the one file that
            existed before this parameter was named.

            Nothing is capped here, and the reason is structural rather than
            generous: a generated corpus has no fixture case names, so there is
            nothing to attribute a hint to and nothing to unlock by passing more
            cases. The tiering has no input. This layer is also gated behind the
            *_output layer, so its reader has already exhausted every case they
            could reason about; rationing the explanation at that point protects
            nothing.
        gate_bin: the binary the correctness gate runs; defaults to :exNN_bin,
            the fixture binary c_function or c_libft already built for this
            exercise. While that fixture is red this layer SKIPs, green, saying
            why: the *_output layer is telling the same story far better -- a
            labelled table, cases ordered trivial to subtle, hints attached --
            and measured across the repo, 43 of 43 diff failures were
            duplicating an already-red functional layer. DERIVED rather than
            re-declared so it cannot drift; a hand-written gate that drifts
            skips forever while looking green. Pass "" to run the corpus
            ungated. The gate fails OPEN by design: no gate, or a gate binary
            that cannot run, still runs the differential, since a wrongly
            skipped layer would turn a real divergence green. NO_SKIP=1 forces
            every gated layer to run anyway -- `bazel test //...
            --test_env=NO_SKIP=1` before trusting an all-green sweep.
        gate_expected: the fixture the gate diffs against, resolved under
            tests/exNN/; default "expected.txt". Unused when gate_bin is "".
        gate_labeled: pass True when this exercise's c_function (or c_libft)
            sets labeled = True. It tells diff_output.sh that each line is
            "CASE<TAB>VALUE" and belongs in its own column -- cosmetic for a
            gate whose output is discarded, but kept in step so the gate is
            demonstrably running the fixture the way its own layer runs it.
        gate_sanitize: MUST match this exercise's c_function(sanitize = ...).
            diff_output.sh --sanitize checks each row of a leading 16-hex-digit
            address column (the ft_print_memory shape) against the address the
            harness published on its "@addr" line, and shows a right one as its
            offset from the first row of its block -- the width, case and +16
            step alone are compared only where nothing was published (see
            --sanitize in diff_output.sh). That changes the VERDICT it reaches,
            not just its rendering: a mismatch makes the gate read a passing
            exercise as red, and this layer then skips forever while the suite
            looks green. Leave it False for a c_libft exercise: that shape has
            no sanitize flag and never passes --sanitize to its own output
            layer.
        gate_stdin: a file label fed to the gate binary's stdin, for a fixture
            that reads input. A LABEL, passed through as given -- unlike
            gate_expected it is not resolved under tests/exNN/.
        perf: default True -- also emit this exercise's c_perf layer, wired to
            the same reader binary, seed, reference arm and gate as this one
            (and to perf_count in place of count). It is free to add because it
            reuses everything c_diff already built, and it says nothing until
            output, differential and ASan are all green (see c_perf's own gate),
            so an unfinished exercise skips in milliseconds rather than
            measuring nonsense. That ordering is what lets it default to on.
            Pass False where the corpus cannot be made bigger or smaller: c-05
            ex04's corpus is a fixed 53 cases, and a scaling exponent is derived
            by varying the case COUNT.
        perf_count: the count handed to that c_perf layer; default 200000, well
            under this layer's own because perf measures three sizes (count/4,
            count/2 and count) and pays for a corpus generation at each. It
            measures shape, not throughput. Ignored when perf = False.
        perf_length: c_perf's `length`, handed through: the series that
            measures how one call grows with the length of its input. Default
            None, no series. Ignored when perf = False.
        size: Bazel test size for BOTH exNN_diff and exNN_diff_asan; default
            "small", i.e. a 60s timeout -- which is also what makes a runaway
            loop in a student's code fail fast instead of hanging. Standalone
            the slowest exercise is ~4.7s at 400k, but a full-suite run
            schedules dozens at once and contention inflated that ~3.2x when
            measured, so the headroom is real but finite: raise this to "medium"
            (300s) before pushing count much past 1M. c-05 ex04 does exactly
            that for a different reason -- the recursive answer that module
            teaches costs phi^n, and the layer must not fail a student for
            writing the intended solution -- and c-05 ex05 and ex07 and
            Reloaded ex14 for a third: a correct but slow answer measured up to
            55s there with the whole suite running, and the runner keeps a
            tenth of the limit back to report in. Size a new exercise's layer
            by the slowest correct answer the subject allows, measured under
            a full suite, not by the reference's time. It does not reach the
            perf target, which is always "medium".
        prototype: the test that checks the signatures this macro's harness
            calls, as _student_bin requires of every harness: default
            "exNN_prototype", the one c_function declares for this exercise.
            c_levels()' audit fails a package that does not declare it. Where
            there is none, say why: "none: <the reason>".
        readings: the reading this harness takes of a sentence the subject
            leaves open, where a generated corpus is what tells the readings
            apart: {"oracle_fn": the //oracle arm of a corpus every case of
            which the readings part on, "diff_clues": its own hint file
            (optional), "count": its size (optional, default 20000: the
            corpus is one family, not the exercise's whole input space, and
            its ASan twin replays as many or `asan_count`, the fewer),
            "level": above strict (optional)}. D3 reads an ambiguous sentence
            at strict at most, and only there: so `oracle_fn`'s corpus holds
            only the cases every reading agrees on, and this one the rest.
            Emits exNN_readings, the same harness and gate over that corpus
            (layer diff, strict, the `_readings` suffix BSQ's and Rush 01's
            corpus readings take), and, with `sanitize`, its crash-fuzz twin
            exNN_readings_diff_asan, so the parted cases stay under ASan:
            moved out of the main corpus without a twin, a byte above 0x7f
            no reading agrees on would have left the one layer that sees a
            signed-char index read out of bounds. The twin is handed no
            `diff_clues`: it sits above strict, and a legend that states the
            reading is the strict target's alone. C 02 ex09 takes one (its
            BUILD file says which reading), and C 11 ex06 one at "level": 3:
            "ascii order" does not reach a byte above 0x7f, so the order its
            reference gives one is a convention of this repo's, as C 06
            ex03's is (docs/reference.md, "Run contract"), listed in _RAISED;
            tools/conventions.sh holds the corpus's hint file to its level.
            One per exercise, as the target's name allows. Checked by
            diff_readings_problem().
            Default None.
        name: unused, for the reason c_levels gives: every macro takes one,
            and buildifier's unnamed-macro check holds this one to it since it
            declares a rule (a program built from the student's files, see
            _student_bin). Every target here is named from `num`, so there is
            nothing for it to control.
    hermetically by Bazel — no system rustc needed."""
    _entry(num, "c_diff")  # first: a contract error names this macro
    problem = _diff_harness_problem(num, harness) or diff_readings_problem(num, readings)
    if problem:
        fail(problem)
    ex = "ex" + num

    # What the grader links into this exercise (the contract's `linked`) is
    # linked into both programs.
    deps = _linked(num).libs
    prototype = prototype or ex + "_prototype"
    binname = ex + "_diffbin"
    _student_bin(
        name = binname,
        harness = ["tests/%s/%s" % (ex, harness)],
        prototype = prototype,
        deps = [":" + fn] + deps,
        diffio = True,
    )

    # The harness SOURCE ships with the test, not just the binary built from it.
    # rust_diff.sh reads the "Line: <col>\t<col>..." sentence out of its header
    # comment and prints it above a divergence, so the hex columns are labelled
    # even for an exercise with no diff_clues.txt of its own. That comment sits
    # beside the parsing code it describes, which is what stops the legend and
    # the parser drifting apart -- they are the same lines.
    harness_src = "tests/%s/%s" % (ex, harness)
    data = ["//oracle:oracle", ":" + binname, harness_src]
    args = [
        "--oracle",
        "$(location //oracle:oracle)",
        "--oracle-fn",
        oracle_fn,
        "--seed",
        str(seed),
        "--count",
        str(count),
        "--student-bin",
        "$(location :%s)" % binname,
        "--harness-src",
        "$(location %s)" % harness_src,
    ]
    clue_args = []
    clue_data = []
    if diff_clues:
        clues_f = "tests/%s/%s" % (ex, diff_clues)
        clue_args = ["--clues", "$(location %s)" % clues_f]
        clue_data = [clues_f]
    args += clue_args
    data += clue_data

    # ---- correctness gate: don't replay 400k cases while the curated fixture
    # is still red. Derived from the targets c_function already builds for this
    # exercise, NOT re-declared here: a hand-written gate drifts, and a drifted
    # gate skips forever while looking green. gate_sanitize must match the
    # exercise's c_function(sanitize=...) for the same reason — --sanitize
    # changes diff_output.sh's verdict.
    gate_args = []
    gate_data = []
    if gate_bin == None:
        gate_bin = ":" + ex + "_bin"
    if gate_bin:
        gate_expected_f = "tests/%s/%s" % (ex, gate_expected)
        gate_args = [
            "--gate-differ",
            "$(location //tools:diff_output.sh)",
            "--gate-bin",
            "$(location %s)" % gate_bin,
            "--gate-expected",
            "$(location %s)" % gate_expected_f,
        ]
        gate_data = ["//tools:diff_output.sh", gate_bin, gate_expected_f]
        if gate_labeled:
            gate_args.append("--gate-labeled")
        if gate_sanitize:
            gate_args.append("--gate-sanitize")
        if gate_stdin:
            gate_args += ["--gate-stdin", "$(location %s)" % gate_stdin]
            gate_data.append(gate_stdin)
    args += gate_args
    data += gate_data
    _test(
        # `count` cases per exercise (400k by default) — by far the heaviest
        # layer here: measured across a full run, diff + diff_asan are ~53% of
        # the suite's CPU while norm/output/compile/forbidden/symbols together
        # are about 8 seconds. Cost is dominated by the ORACLE generating the
        # corpus (~90%), not by the student replaying it, so raising `count`
        # costs roughly what the generator costs and per-case generator cost
        # varies ~4x between exercises.
        #
        # "small" keeps the 60s timeout. Standalone the slowest exercise is
        # ~4.7s at 400k; a full-suite run schedules dozens at once and CPU
        # contention inflated that ~3.2x when measured, so there is real but
        # finite headroom. Raise `size` to "medium" (300s) before raising
        # `count` much beyond 1M, and lower a heavy exercise's `count` if you
        # want it faster.
        name = ex + "_diff",
        srcs = ["//tools:rust_diff.sh"],
        args = args,
        data = data,
        size = size,
        tags = ["diff"],
    )

    # Cost measurement, on the same harness and the same reference inputs. It
    # reuses everything c_diff already built, so a perf target is free to add and
    # says nothing until the exercise is correct AND memory-safe (see c_perf's
    # own gate). That ordering is why this can default to on: an unfinished
    # exercise skips in milliseconds rather than measuring nonsense.
    if perf:
        # c_perf's memory-safety gate defaults to :exNN_diffbin_asan, and that
        # target only exists when sanitize is on -- so this pair would fail
        # analysis with "no such target", naming a label neither call site
        # mentions. Say which two arguments disagree instead, and name the way
        # out: an exercise that genuinely has no ASan arm can gate on the first
        # two rungs by passing gate_asan_bin = "" to c_perf directly.
        if not sanitize:
            fail(("c_diff(num = %r): sanitize = False with perf = True. The perf " +
                  "layer's gate wants :%s_diffbin_asan, which only sanitize = True " +
                  "builds. Set perf = False, or leave sanitize on.") % (num, ex))
        c_perf(
            num = num,
            fn = fn,
            oracle_fn = oracle_fn,
            seed = seed,
            count = perf_count,
            enabled = True,
            gate_expected = gate_expected,
            gate_labeled = gate_labeled,
            gate_sanitize = gate_sanitize,
            gate_stdin = gate_stdin,
            gate_bin = gate_bin,
            length = perf_length,
        )

    # Crash-fuzz variant (tag "diff_asan"): replay the corpus through an
    # ASan/UBSan-instrumented harness+student and assert no memory error / UB.
    # Value correctness is not checked here, so a memory-safe stub passes; this
    # catches out-of-bounds reads that return the right value on valid inputs.
    asan_count_problem = diff_asan_count_problem(num, count, asan_count, sanitize)
    if asan_count_problem:
        fail(asan_count_problem)
    if sanitize:
        asan_bin = ex + "_diffbin_asan"

        # The same unit, compiled under the sanitizer: there is no separate
        # _asan library any more, because each binary compiles what it links
        # with its own flags.
        _student_bin(
            name = asan_bin,
            harness = ["tests/%s/%s" % (ex, harness)],
            prototype = prototype,
            deps = [":" + fn] + deps,
            diffio = True,
            asan = True,
        )
        _test(
            name = ex + "_diff_asan",
            srcs = ["//tools:rust_diff.sh"],
            args = [
                "--oracle",
                "$(location //oracle:oracle)",
                "--oracle-fn",
                oracle_fn,
                "--seed",
                str(seed),
                "--count",
                str(asan_count),
                "--crash-only",
                "--student-bin",
                "$(location :%s)" % asan_bin,
                # What the columns are, and the exercise's diff hints: a crash
                # report shows the case that crashed, and both explain it.
                "--harness-src",
                "$(location %s)" % harness_src,
            ] + clue_args + gate_args + _symbolizer_args(),
            data = ["//oracle:oracle", ":" + asan_bin, harness_src] + clue_data +
                   gate_data + _SYMBOLIZER_DATA,
            size = size,
            tags = ["diff_asan"],
        )

    # The reading's corpus: the same harness, gate and hints' shape, over the
    # cases the readings part on, and its crash-fuzz twin (see `readings`).
    if readings:
        r_count = readings.get("count", 20000)
        r_level = readings.get("level")
        r_clue_args = []
        r_clue_data = []
        if readings.get("diff_clues"):
            r_clues_f = "tests/%s/%s" % (ex, readings["diff_clues"])
            r_clue_args = ["--clues", "$(location %s)" % r_clues_f]
            r_clue_data = [r_clues_f]
        r_common = [
            "--oracle",
            "$(location //oracle:oracle)",
            "--oracle-fn",
            readings["oracle_fn"],
            "--seed",
            str(seed),
        ]
        _test(
            name = ex + "_readings",
            srcs = ["//tools:rust_diff.sh"],
            args = r_common + [
                "--count",
                str(r_count),
                "--student-bin",
                "$(location :%s)" % binname,
                "--harness-src",
                "$(location %s)" % harness_src,
            ] + r_clue_args + gate_args,
            data = ["//oracle:oracle", ":" + binname, harness_src] + r_clue_data + gate_data,
            size = size,
            tags = ["diff"],
            level = _raise("diff", r_level),
        )
        # The twin is handed no legend. It judges memory and how the run
        # ended, never a value, so the reading decides nothing there; and it
        # sits at diff_asan's level, above strict, where the reading's legend
        # may not be printed: it states the reading, which only the strict
        # target's own hint does (AGENTS.md section 2). The harness's "Line:"
        # sentence still names the columns of the case that crashed. Rush 01's
        # and BSQ's readings twins (corpus_memory) carry no hints either.
        if sanitize:
            _test(
                name = ex + "_readings_diff_asan",
                srcs = ["//tools:rust_diff.sh"],
                args = r_common + [
                    "--count",
                    str(min(r_count, asan_count)),
                    "--crash-only",
                    "--student-bin",
                    "$(location :%s)" % (ex + "_diffbin_asan"),
                    "--harness-src",
                    "$(location %s)" % harness_src,
                ] + gate_args + _symbolizer_args(),
                data = ["//oracle:oracle", ":" + ex + "_diffbin_asan", harness_src] +
                       gate_data + _SYMBOLIZER_DATA,
                size = size,
                tags = ["diff_asan"],
                level = _raise("diff_asan", r_level),
            )

def c_perf(
        num,
        fn,
        oracle_fn,
        harness = None,
        seed = 1,
        count = 200000,
        baseline_bin = None,
        gate_exponent = "2.6",
        gate_slowdown = "5000",
        gate_memory = "200",
        gate_bin = None,
        gate_expected = "expected.txt",
        gate_labeled = False,
        gate_sanitize = False,
        gate_stdin = None,
        gate_asan_bin = None,
        gate_count = 4000,
        enabled = False,
        prototype = None,
        length = None,
        name = None):
    """Performance layer (tag "perf") — SCAFFOLDING, informative by default.

    No other layer asks how much WORK the answer cost. This one runs the
    exercise's existing diff harness over N, 2N and 4N cases and fits the growth
    exponent, so an accidental quadratic (a scan nested inside a scan, a strlen
    re-evaluated per iteration) shows up as a number the student can read. It
    reuses c_diff's reader harness verbatim — no new per-exercise C to write.

    It is deliberately not a style gate: several times slower than a reference
    is a fine place to be, and failing someone for it teaches the wrong thing.
    Only a growth exponent past `gate_exponent`, or (in ratio mode) a slowdown
    past `gate_slowdown` / memory past `gate_memory`, turns the test red — the
    band where the code looks like it would stop finishing on a bigger input —
    and a measured run that crashes. These are this repo's own lines, at
    `complete`, and docs/testing.md ("The two cost layers") lists them; a size
    that does not finish within PERF_TIMEOUT is halved and measured again,
    and one that never fits is reported, never failed (red only under
    NO_SKIP=1, where a layer that measured nothing is).

    WHAT n IS: the number of cases, each one call on one small corpus line. So
    the exponent says how many calls add up, not how one call grows with its
    input -- a cubic sort over arrays of a dozen ints is linear in how many
    arrays there are (finding 044). Where one input's length is the question,
    `length` adds a series that measures that, and it is never gated.

    It runs LAST in the pedagogic order and enforces that itself: the script
    checks the exercise's output fixture, then the differential corpus, then the
    ASan/UBSan build, and SKIPs naming the stage if any is not green. Nobody
    should be tuning a loop while the answer is still wrong or the memory access
    is still unsafe. gate_* below wire those checks; they default to the same
    files c_function/c_diff already declare for this exercise.

    gate_sanitize MUST match the exercise's c_function(sanitize=...) — it
    changes diff_output.sh's verdict, so a mismatch would make the gate misread
    a passing exercise as red and skip forever. gate_labeled is cosmetic (it
    only picks the CASE column) and is accepted for symmetry.

    enabled: False (the default) tags the target "manual", so it is built and
      runnable but stays out of `bazel test //...` and out of the submit gate.
      Flip to True per exercise once its thresholds have been calibrated.
    baseline_bin: a binary that REPLAYS the corpus, to enable ratio mode.
      //oracle:oracle is NOT one — it generates rather than replays (see the
      header of tools/perf_test.sh). Leave None until `oracle bench` exists.
    harness: defaults to the diff harness c_diff already declares for this
      exercise, i.e. the :exNN_diffbin target.

    Args:
        num: the exercise number as a STRING -- "04", never 4. Starlark will not
            add an int to a string, so a bare 4 fails at analysis time on the
            first "ex" + num. The target is exNN_perf and every default below is
            derived from that stem (:exNN_bin, :exNN_diffbin,
            :exNN_diffbin_asan), so a wrong num misses all of them at once. In
            practice it arrives from the exercise's c_diff call, which is this
            macro's only caller in the repo.
        fn: the exercise's function, e.g. "ft_is_prime". It names the unit
            linked in when this macro builds its own reader binary (see
            harness), and it supplies the "exNN/fn" label the report is headed
            with -- one label, no spaces, because a test rule's `args` are
            shell-tokenised and the second word would arrive as an unknown
            option.
        oracle_fn: which arm of //oracle:oracle generates the corpus, e.g.
            "c05_is_prime" -- normally the same arm the exercise's c_diff uses,
            so the layer that measures and the layer that compares are looking
            at the same inputs. It is also what the reference baseline is looked
            up by: perf_test.sh probes `oracle bench <oracle_fn>`, the arm that
            replays a corpus and computes the answers without generating or
            printing them. An arm with no bench half is not an error -- the
            report says the reference was not compared and the scaling figures
            stand on their own.
        harness: filename under tests/exNN/ of the reader harness. The default,
            None, means REUSE :exNN_diffbin -- the binary c_diff already
            declared for this exercise -- which is the whole reason a perf layer
            costs no new per-exercise C. Naming one here instead builds a
            separate :exNN_perfbin (tagged "manual"), which is only wanted for
            an exercise that has a perf layer and no differential layer; with
            the default and no c_diff, :exNN_diffbin does not exist and Bazel
            says so at analysis time.
        seed: default 1, and it reaches every corpus this layer generates -- the
            three measured sizes, the 200-case memory floor, and the gate corpus
            of stages 2 and 3. Fixed rather than random so that two runs measure
            the same work, which is the only way a second reading can confirm or
            refute the first (see gate_exponent).
        count: the LARGEST of the three measured sizes; default 200000. The
            harness is run over count/4, count/2 and count cases and the growth
            exponent p in cost ~ n^p is fitted by least squares on log(CPU)
            against log(cases) across all three points, each point being the
            best of PERF_REPEATS (3) runs -- the minimum, not the mean, because
            interference can only ever make a run slower. count/4 is floored at
            1000, so anything under 4000 collapses to 1000/2000/4000 and stops
            varying. Keep it well below c_diff's count: corpus generation
            dominates and this layer generates four of them, and it is measuring
            SHAPE rather than throughput. A size that does not finish within
            PERF_TIMEOUT (25s) halves all three and measures again, down to
            PERF_MIN_CASES; a wall clock establishes neither an exponent nor a
            ratio, so it never fails the layer.
        baseline_bin: a binary that REPLAYS the corpus, which is what turns on
            ratio mode (slowdown and peak-memory multiples beside the scaling
            figures). //oracle:oracle invoked the usual way is NOT one: `oracle
            <fn> <seed> <count>` GENERATES cases -- seeded RNG, hex encoding,
            formatting, about 90% of a diff test's cost -- so timing it would
            measure the generator and not the reference. That is what the
            `oracle bench` arm exists for, and this macro always asks for it
            (see oracle_fn); set baseline_bin only for a reference of your own,
            as it takes precedence over that probe. Whatever you pass, remember
            both sides are timed WITH their harness -- corpus parsing on both,
            printing on the student's, which the reference does not do -- so the
            report only interprets gaps too large for harness overhead to
            explain.
        gate_exponent: the fitted exponent at or above which the test turns RED;
            default "2.6", a string because it is handed to awk unparsed. It
            sits well past a clean quadratic on purpose: an honest O(n^2) still
            only warns, and only the band where the code looks like it would
            stop finishing on a larger input fails. Three things keep it from
            firing on noise, which matters because this is the only way this
            layer can tell a student that correct code is broken. Timings under
            15ms of CPU are reported as too fast to measure and no exponent is
            fitted at all. Three timings that do not RISE with the case count
            are reported and never gated -- more work cannot take less time, so
            the machine was busy and the fit is describing that. And a first
            reading over the gate is measured again from scratch and has to
            survive the second reading: noise does not reproduce, while a
            genuinely quadratic function is quadratic every time it is asked.
        gate_slowdown: wall-time multiple over the baseline at which the test
            turns red; default "5000". Ratio mode only, so it is inert until a
            bench arm or a baseline_bin exists, and it is skipped as well when
            the reference finishes in under PERF_MIN_BASELINE_MS (20ms), where
            dividing by the baseline would not mean anything. The enormous
            default is the point: several times slower than a reference is a
            fine place for a student to be, and failing them for it teaches the
            wrong thing.
        gate_memory: peak-RSS multiple over the baseline at which the test turns
            red; default "200" -- the band that suggests an unbounded allocation
            rather than a merely wasteful one. Ratio mode only, on the same
            terms as gate_slowdown. The scaling half reports memory separately
            and never gates on it, as a growth FACTOR above a measured floor
            rather than an exponent: peak RSS is quantised by the allocator and
            noisy enough that a function which allocates nothing can measure
            lower at the largest size than at the smallest.
        gate_bin: stage 1 of the correctness gate -- the exercise's own fixture
            binary, defaulting to :exNN_bin, run against gate_expected. While it
            is red the layer SKIPs (exit 0) naming the stage, so a student's
            attention stays on the one test that matters instead of being split
            across a performance report they cannot act on yet. Defaulting to
            the target c_function or c_libft already declares is what keeps the
            gate from drifting out of sync with the layer it gates on; pass an
            explicit value only for a hand-wired exercise, and "" to drop stage
            1 entirely. Stages 2 and 3 still run in that case, but gate_count
            stops being forwarded with them (it rides along with stage 1's
            flags), so the runner falls back to its own 4000.
        gate_expected: the fixture stage 1 diffs against, resolved under
            tests/exNN/; default "expected.txt". Unused when gate_bin is "".
        gate_labeled: cosmetic, and accepted for symmetry with the other gate_*
            flags: it only picks out the CASE column of diff_output.sh's table,
            which the gate discards. Pass it anyway when the exercise's
            c_function (or c_libft) sets labeled = True, so the gate visibly
            runs the fixture the same way its own layer does.
        gate_sanitize: MUST match the exercise's c_function(sanitize = ...).
            Unlike gate_labeled this one changes the VERDICT diff_output.sh
            reaches -- it checks each address of a leading address column
            against the one the harness published ("@addr"), and shows a right
            one as its offset within its block (see --sanitize in
            diff_output.sh) -- and a mismatch makes the gate misread a passing
            exercise as red, after which the layer skips forever while looking
            green. Leave it False for a c_libft exercise, which has no sanitize
            flag of its own.
        gate_stdin: a file label fed to the stage-1 binary's stdin, for a
            fixture that reads input. A LABEL, passed through as given: unlike
            gate_expected it is not resolved under tests/exNN/. Ignored when
            gate_bin is "", along with the rest of stage 1.
        gate_asan_bin: stage 3 -- the ASan/UBSan binary the gate corpus is
            replayed through, defaulting to :exNN_diffbin_asan, the twin c_diff
            builds when its own sanitize is on. Thinking about how fast a
            function is while it still reads out of bounds is wasted effort, so
            a sanitizer or UB report here SKIPs the layer too. Pass "" to drop
            stage 3, and pass a real target if c_diff was called with sanitize =
            False -- the default then names a target nobody built, which is an
            analysis-time error rather than a skipped stage.
        gate_count: how many cases the gate corpus holds, shared by stage 2 (the
            student's harness replaying it must reproduce the reference byte for
            byte) and stage 3; default 4000, and see gate_bin for the one case
            where it is not forwarded. Small on purpose: this is a precondition
            check and not a second differential layer, which already ran at
            c_diff's own count. Both stages fail OPEN -- if the reference cannot
            generate, or generates nothing, they are passed over rather than
            treated as failures, since a harness problem is not a state of the
            exercise. NO_SKIP=1 in the environment forces every stage open and
            says so in the report, so that "all green" can be told apart from
            "everything skipped".
        enabled: False (the default) adds the "manual" tag, so the target is
            built and runnable by name but stays out of `bazel test //...` and
            out of the submit gate; flip it per exercise once its thresholds
            have been calibrated. c_diff always passes True, so in practice
            every exercise whose c_diff leaves perf at its default gets a live
            perf target at level 4 (complete), and the "manual" default only
            applies to a c_perf written out by hand.
        prototype: as c_diff's, and IGNORED unless harness or `length` is
            set: with harness = None this macro builds no binary of its own
            for the case-count series -- it reuses :exNN_diffbin, which names
            its own.
        length: None, or a dict asking for the LENGTH series -- how one call's
            cost grows with the length of its input, which the case-count
            scaling cannot see. Reported, never gated: where it matters (a
            sort, a split) the exponent is the algorithm, and a line on it
            would recommend one (C 12's cost comment). Keys:
              "oracle_fn": an //oracle arm run as `oracle <arm> <seed> <cases>
                  <length>`, writing <cases> lines whose one input has exactly
                  <length> elements (oracle/src/length.rs);
              "harness": a file under tests/exNN/ that reads those lines, of
                  any length, calls the function and CHECKS its result,
                  exiting 3 at the first wrong one (a wrong result is not
                  timed); built as :exNN_lenbin with the exercise's unit and
                  the grader's `linked` libraries, held to `prototype`;
              "base": the first length, default 250 (the runner doubles it
                  while a run is too short to time, and halves it on a run
                  that does not finish);
              "cases": how many lines at each length, default 20.
        name: unused, for the reason c_levels gives: every macro takes one,
            and buildifier's unnamed-macro check holds this one to it since it
            declares a rule (a program built from the student's files, see
            _student_bin). Every target here is named from `num`, so there is
            nothing for it to control.
    """
    _entry(num, "c_perf")  # first: a contract error names this macro
    ex = "ex" + num
    deps = _linked(num).libs
    tags = ["perf"] + ([] if enabled else ["manual"])

    # Reuse c_diff's reader binary when it exists; build our own only if this
    # exercise has a perf layer without a diff layer.
    if harness == None:
        binname = ex + "_diffbin"
    else:
        binname = ex + "_perfbin"
        _student_bin(
            name = binname,
            harness = ["tests/%s/%s" % (ex, harness)],
            prototype = prototype or ex + "_prototype",
            deps = [":" + fn] + deps,
            diffio = True,
            tags = ["manual"],
        )

    args = [
        "--runner",
        "$(location //tools:perf_run)",
        "--student-bin",
        "$(location :%s)" % binname,
        "--oracle",
        "$(location //oracle:oracle)",
        "--oracle-fn",
        oracle_fn,
        "--seed",
        str(seed),
        "--count",
        str(count),
        "--label",
        "%s/%s" % (ex, fn),
        "--gate-exponent",
        gate_exponent,
        "--gate-slowdown",
        gate_slowdown,
        "--gate-memory",
        gate_memory,
    ]

    # Ask for the oracle-backed baseline. perf_test.sh probes `oracle bench <fn>`
    # and silently falls back to scaling-only where no bench arm exists yet, so
    # this is safe to pass for every exercise.
    args.append("--baseline-oracle")
    data = ["//tools:perf_run", "//oracle:oracle", ":" + binname]

    if length != None:
        bad = [k for k in length if k not in ["oracle_fn", "harness", "base", "cases"]]
        if bad or "oracle_fn" not in length or "harness" not in length:
            fail(("c_perf(num = %r): length takes oracle_fn and harness, and " +
                  "base and cases; got %r") % (num, sorted(length.keys())))
        lenbin = ex + "_lenbin"
        _student_bin(
            name = lenbin,
            harness = ["tests/%s/%s" % (ex, length["harness"])],
            prototype = prototype or ex + "_prototype",
            deps = [":" + fn] + deps,
            tags = ["manual"],
        )
        args += [
            "--length-oracle-fn",
            length["oracle_fn"],
            "--length-bin",
            "$(location :%s)" % lenbin,
            "--length-base",
            str(length.get("base", 250)),
            "--length-cases",
            str(length.get("cases", 20)),
        ]
        data.append(":" + lenbin)
    if baseline_bin:
        args += ["--baseline-bin", "$(location %s)" % baseline_bin]
        data.append(baseline_bin)

    # ---- the correctness gate: output, then differential, then memory safety.
    # Defaults point at the very targets c_function/c_diff already build for
    # this exercise, so the gate cannot drift out of sync with the layers it is
    # gating on. Pass explicit values only where an exercise is hand-wired (e.g.
    # c-09 ex00, whose functional target is ex00_func_test/ex00_func_bin).
    if gate_bin == None:
        gate_bin = ":" + ex + "_bin"
    if gate_asan_bin == None:
        gate_asan_bin = ":" + ex + "_diffbin_asan"
    if gate_bin:
        expected_f = "tests/%s/%s" % (ex, gate_expected)
        args += [
            "--gate-differ",
            "$(location //tools:diff_output.sh)",
            "--gate-bin",
            "$(location %s)" % gate_bin,
            "--gate-expected",
            "$(location %s)" % expected_f,
            "--gate-count",
            str(gate_count),
        ]
        data += ["//tools:diff_output.sh", gate_bin, expected_f]
        if gate_labeled:
            args.append("--gate-labeled")
        if gate_sanitize:
            args.append("--gate-sanitize")
        if gate_stdin:
            args += ["--gate-stdin", "$(location %s)" % gate_stdin]
            data.append(gate_stdin)
    if gate_asan_bin:
        args += ["--gate-asan-bin", "$(location %s)" % gate_asan_bin]
        data.append(gate_asan_bin)

    _test(
        name = ex + "_perf",
        srcs = ["//tools:perf_test.sh"],
        args = args,
        data = data,
        # Three runs at N, 2N, 4N plus three corpus generations. Generation
        # dominates (see the timings in tools/perf_test.sh), so keep `count`
        # well below c_diff's: this layer measures shape, not throughput.
        size = "medium",
        tags = tags,
    )

def c_twin(num, of):
    """Declare that exercise `num` repeats another module's: its tests are that one's.

    Piscine Reloaded repeats sixteen C exercises of the Piscine word for word
    (its BUILD file names each beside its calls), and its tests/exNN folders
    were copies of theirs, byte for byte -- or but for the name of an include
    guard, which every module spells after itself --
    with each case list written out a second time: a fix that reached one
    copy left the other behind, and nothing said so. A C exercise's macros
    name every file from their own folder, so the two cannot share one set
    of files as the shell twins do (shell_exercise's twin_of); this declares
    the repeat instead, and //tools:conventions holds the pair to each other
    -- the two tests/ folders file for file and byte for byte, and two
    c_program calls' `cases` token for token, in any layout, but for the
    exercise's number --
    and reports a tests/ folder that is all a copy of another module's with
    no such line. It emits nothing.

    Args:
        num: this exercise, as a two-digit string ("27").
        of: the exercise it repeats, as "//<module>:exNN".
    """
    if type(num) != "string" or not _is_ex("ex" + num):
        fail("c_twin(num = %r): num is the exercise's two digits, as a string." % (num,))
    if (type(of) != "string" or not of.startswith("//") or ":" not in of or
        not _is_ex(of.rpartition(":")[2]) or of.rpartition(":")[0] == "//" + native.package_name()):
        fail(("c_twin(num = %r, of = %r): `of` names the exercise of ANOTHER module this " +
              "one repeats, as \"//<module>:exNN\".") % (num, of))

def c_program(
        num,
        name,
        cases = None,
        srcs = None,
        hdrs = None,
        progname = False,
        malloc = None,
        makefile = False,
        no_missing_file_case = None,
        model = None,
        reference = False,
        refusals = None,
        memory_rule = None,
        allocfail = None,
        allocfail_rule = None,
        allocfail_leaks = False,
        allocfail_leaks_rule = None,
        fixed_array = None,
        fixed_array_bytes = None):
    """A program exercise: the deliverable owns main() and is run with argv.

    Args:
        num: the exercise number as a two-digit STRING ("00"; an int fails at
            analysis on "ex" + num). Every target this macro emits is named
            from it -- exNN_bin, exNN_bin_asan, exNN_norm, exNN_compile_clang,
            exNN_compile_gcc, exNN[_case]_output -- and it is what points the
            macro at deliverable/exNN and tests/exNN.

            fail()s if tests/exNN/prototype.h exists. A program exercise gets
            no prototype layer, because its entry point is main() and the
            compiler already fixes that signature, so a contract header here is
            wired to nothing and can only be a leftover: delete it, or move the
            exercise to a macro that reads one.
        name: the program's name, as the subject gives it ("Executable
            name: rush-02"). Unlike a rule's `name` it names no target --
            every target comes from `num` -- and no file is looked for under
            it: an empty deliverable/exNN makes the program a stand-in that
            says there is no .c file (see _student_bin), not a Bazel error
            about a file named after it. A "cwd_files" case runs the program
            under it, as ./<name>, so there it must be a file name.
        cases: the argv invocations to run, as a list of dicts. Default None
            emits no run at all, leaving the static layers and the two
            binaries; that is a real configuration rather than an oversight,
            since c-06 ex01-ex03 drive their runs from c_argv_table() instead,
            which picks :exNN_bin and :exNN_bin_asan up by name. Every case
            gets an output test and an ASan/UBSan run; where the subject lets
            the program allocate (`malloc`, below) it also gets a valgrind
            arm. Every case is checked while loading
            (_case, _CASE_KEYS): a key this shape does not take, or no kind,
            fails naming the case. Its KIND is exactly one of:
                "expected": the expected-output file's name under tests/exNN/
                            (a bare name, not a label): the output, exactly.
                "any_of":   two or more such names: the output is one of
                            them, where the subject leaves the reading open
                            and bounds it. The report compares with the first
                            and names the others.
                "survive":  True: no output is compared. The case passes when
                            the program ends by itself -- no signal, no hang,
                            no runaway output. What every reading of an open
                            case agrees on. Its report says what it ran, and
                            it SKIPs while the exercise's first case at basic
                            is red (_survive_gate): an unwritten program ends
                            by itself too.
            And its other keys:
                "name":     infix for this case's targets, default "run". With
                            a single case the targets take the plain exNN form
                            the rest of the repo uses (exNN_output, exNN_asan);
                            with several they become exNN_<name>_output.
                "level":    raise this case above basic (2 strict, 3 robust,
                            4 complete): a case the subject leaves open, or a
                            rigour of this repo's (docs/reference.md, "Run
                            contract"). Every arm of the case sits at least
                            there; a raise is listed in _RAISED.
                "args":     the argv, default []. $(location ...) is expanded
                            here, so a fixture can be passed as an argument.
                            sh_test tokenises `args` on whitespace, so an
                            argument that must itself contain spaces has to
                            carry embedded quotes -- see the Q constant and the
                            long comment above it in rush-01's BUILD.bazel.
                "fixtures": labels of the files the run reads; they are staged
                            into the output, valgrind and asan targets alike,
                            and are what makes $(location ...) inside "args"
                            resolvable.
                "stdin":    a package-relative LABEL (not a bare name under
                            tests/exNN/) fed to the program on stdin -- in the
                            output, valgrind and asan arms alike, so the three
                            cannot end up running different things.
                "argv_file": a package-relative LABEL of a file holding more
                            arguments, one per line, passed after "args": an
                            empty line is an empty argument, a line with
                            spaces one argument. What `args` cannot say,
                            since Bazel drops "" and splits on spaces.
                "cwd_files": {LABEL: NAME}: run the program as ./NAME-of-
                            the-program (this macro's `name`) from a folder
                            of its own, holding only a copy of it and a copy
                            of each LABEL under NAME: the subject's
                            `./rush-02 42` beside numbers.dict. "args" then
                            names those files by NAME, and a $(location)
                            in them is refused (it would not resolve there).
                "stream":   "stdout" (the default) or "stderr": which one is
                            compared. The other is still shown under the table
                            when the case fails, because it is usually where
                            the explanation is.
                "sanitize": a leading 16-hex-digit address column, which
                            ASLR moves (hexdump-shaped output): each row's
                            address is checked against the one the program
                            published on an "@addr <16 hex>" line before the
                            dump, and a right one is shown as its offset from
                            the first row of its block. Where nothing was
                            published only the width, case and +16 step are
                            compared (see --sanitize in diff_output.sh).
                "labeled":  every line is "CASE<TAB>VALUE" and the CASE gets a
                            column of its own; without it the CASE column is
                            just the 1-based line number.
                "clues":    name of a clues.tsv under tests/exNN/ whose hints
                            are rendered below the table when this case fails.
                            Reaches the output arm AND the valgrind arm; the
                            latter renders the hint column alone, capped at
                            three, because a leak report has no per-case table
                            to attach hints to. A row may name this case
                            ("name" above) as its label: it then fires when
                            this case fails and on no other case, where a
                            row with no label fires on every failure. A row
                            labelled "valgrind" fires in the valgrind arm of
                            every case and in no output arm, which is why no
                            case may be named "valgrind". A program keeps one
                            such file per exercise, its rows keyed to the
                            cases, rather than a file per case
                            (docs/reference.md, "Writing a c_program case").
                "exit":     the status this case must return, judged where
                            the Run contract (docs/reference.md) puts it: in
                            exNN[_case]_output, at basic, when "exit_quote"
                            is given too -- at strict when the case also has
                            "level": 2, where the sentence is read as naming
                            it (C 10's "performs the same function as the
                            system's tail": the tool's own status); otherwise
                            in the robust twin exNN[_case]_exit. Tested for
                            presence, not truth, so "exit": 0 really does pin
                            "exits 0".
                "exit_quote": the subject's sentence that names "exit" (or,
                            with "level": 2, that is read as naming it). A
                            status the subject does not name is never checked
                            at basic, and this key is what says it does: no
                            quote, no basic check. The runner shows it beside
                            a wrong status (--exit-quote), so it is a string
                            with no ASCII single quote and no $: write the
                            apostrophe as the subject prints it, a
                            typographic one.
                "invalid_input": True where the subject answers this input
                            with an error -- a message it names, such as
                            "Error", "map error" or a missing file's
                            diagnostic -- not merely where it calls the
                            input invalid: do-op prints 0 for an "invalid
                            operator", an ordinary output, and its cases
                            are not marked. With no "exit", its status is
                            then judged at no level: the subject names none,
                            and a non-zero one is what an error conventionally
                            returns. So is an "any_of" or "survive" case's,
                            whose reading the subject leaves open.
                            "invalid_input": False says the opposite, and says
                            it on purpose: the subject answers this input with
                            an ordinary output, so the case gets the robust
                            twin, which expects 0 -- the C convention for a
                            run that did its job -- and its output test notes,
                            without failing, any other return. A case with
                            none of these keys and no "exit" gets the same
                            twin by DEFAULT (--exit-source default), and a
                            default is not a decision where the case expects
                            an error: one that compares stderr is refused at
                            loading until it says True, False or "exit"
                            (_case_exit_error), and a twin whose expected
                            output mentions an error refuses to run (exit 2,
                            naming the key; diff_output.sh).
                "missing_file": the operand in "args", word for word, that
                            names no file: the run hands the program a name
                            that will not open (no_such_file_exNN). It is
                            checked while loading -- an operand of the case,
                            not a fixture, an option, "-", "." or ".." -- and
                            at run time: the output test stops (exit 2, a
                            harness error) if something by that name is
                            where the program runs (diff_output.sh --absent).
                            The case says what its status means, as a stderr
                            case does ("invalid_input", "exit", or an
                            "any_of" or "survive" kind). Where the contract
                            allows open, one case at least carries it, or
                            no_missing_file_case says why none does.
                "valgrind": default True; False drops the valgrind arm for this
                            one case. Read only where the subject lets the
                            program allocate (`malloc`).
            Any other key fail()s at loading (_CASE_KEYS), naming the key it
            was probably meant to be: a misspelt "invalid_input" used to be
            ignored in silence and produce an _exit twin expecting 0.
            Every arm of every case opens its report with a RAN line: the
            command it ran, which runs it again from the repository root --
            or, for a "cwd_files" case, from a folder holding the files
            listed under the line (tools/runner_lib.sh's rl_ran).
        srcs: the deliverable's sources. Default None globs them as the
            contract lets them lie (turnin_dir()/*.c, and subfolders where it
            says so) -- the file set is written down once, in the subject()
            contract, to be CHECKED against the directory rather than to drive
            the build. Pass a list only where the glob is wrong.
            Headers must NOT be routed through here: forbidden_symbols.sh
            compiles each --src and reads its symbols, and hands a .h back as
            exit 2, a harness error. That is what `hdrs` is for.
        hdrs: headers that belong to the deliverable. With `srcs` left at its
            default they default to every deliverable/exNN/*.h, after any
            listed here (see _deliverable_hdrs); with explicit `srcs` they are
            exactly what is listed, default none. They are staged for both
            program builds alongside the sources, so a deliverable that
            #includes its own header still builds for every layer that RUNS
            it. They also reach the static layers: the norm layer NORMS them
            beside the sources (the Norm applies to headers too), while the two
            compile layers and the forbidden layer stage them and compile with
            the GRADER's include path (_inc_args): a header's directory joins
            it only where the header sits beside the sources, and a Makefile
            project's is the -I its recipes pass. C 10, C 11 ex05 and
            Reloaded ex27 leave the file layout to the student and pass none:
            before the default, a student header there was "file not found"
            for every layer and never normed.
        progname: default False. True emits exNN_progname (tag "output", so it
            gates at level basic): the binary is copied under two names --
            "a.out", matching the subject's example, and one unrelated name --
            run as ./<name> each time, and must print exactly its own argv[0]
            plus a newline on both, without dying. The renamed run is the one
            that proves anything, since a program that hardcodes "./a.out"
            passes the first. A plain non-zero return is only noted there: the
            subject names no exit status, so by the rule in docs/reference.md
            ("Run contract") it fails at robust, in exNN_progname_exit (tag
            "output", raised to level 3), which runs the same two names and
            judges nothing but how each run ended. It also emits
            exNN_progname_asan (tag "asan"), which runs the INSTRUMENTED binary
            once, bare -- no rename, no arguments, output not compared --
            because argv[0] is where this exercise can walk off the end of a
            string it does not own, and a diff of one short line cannot see a
            read that returns the right bytes. c-06 ex00 is the only caller.
        THE FORBIDDEN LAYER'S LIST is the contract's `allowed` plus its
            `variables` (C 10's errno), as for c_function; a contract `allowed
            = None` emits no forbidden layer. What is checked is each object's
            UNDEFINED symbols, so anything the deliverable itself defines is
            always fine. Where glibc compiles a name into another symbol
            (__errno_location, __xpg_basename, __ctype_b_loc), the runner's
            alias table maps it back. What the grader brings (the contract's
            `provided`: Reloaded's ft_putchar.c) both programs link; norm,
            compile and forbidden see the student's `srcs` alone.
        malloc: never passed. Whether the program may allocate is the
            subject's "Allowed functions" line, read from the contract as
            corpus_memory() reads it (_memcheck_allowed: malloc named there,
            or no such line at all). Where it may, every case gets a
            valgrind arm (exNN[_case]_valgrind, tag "valgrind", level
            strict), each gated on that case's own output fixture so a stub
            is met with "your output layer is still red" rather than with a
            memcheck report; a "survive" case has no fixture, and its arm
            runs ungated. A program that cannot allocate has nothing to leak.
            It used to be an argument, typed at each call beside the
            contract that already said it, so the two could disagree; a call
            that still passes it is refused while loading.
        memory_rule: the subject's own sentence about memory, naming where it
            is from (Rush 02, p.7: "Any memory allocated on the heap ... must
            be freed correctly."), for the valgrind arms to quote when one
            fails. Default None: they state the rule the layer applies and
            say it is this repo's, since most subjects have no such sentence
            (finding 082). Needs a subject that lets the program allocate
            (`malloc`). One line; written to a file
            (exNN_memory_rule), since sh_test tokenises `args` on blanks.
        makefile: True for a project whose subject mandates a Makefile and
            then leaves the file names to the student ("Makefile and all the
            necessary files": BSQ, Rush 02). Default False keeps the ordinary
            path, where `srcs` is the program and Bazel links it directly.
            "once_written" is True once the Makefile compiles anything, and
            until then -- no Makefile, or a stub whose recipes only echo --
            builds every source of the folder as the program, with no -I
            (tools/student_build.sh, UNTIL THE MAKEFILE IS WRITTEN): for an
            exercise whose program is most of the work and its Makefile a
            line of it (C 10, C 11 ex05, Reloaded ex27), whose output tests
            a student reads before the Makefile exists. A Makefile written
            and broken is a stand-in all the same. False is refused where
            the subject() contract has the exercise turn in a Makefile
            (_makefile_problem): the subject builds the program with it.

            When True, the two binaries are built by asking `make -Bn`, run on
            the Makefile at the top of the turn-in directory, which .c files
            the default goal compiles and which -I directories it passes (see
            tools/student_build.sh's Makefile mode), with the whole turn-in
            directory staged beside it -- every subfolder too, where the
            contract lets files sit in them (srcs/, includes/): a Makefile may
            include or read anything next to it. `srcs` then no longer has to
            BE the program -- it can stay the contract's glob, because the
            layers it still feeds (norm, both compile layers, forbidden)
            compile each file on its own and never link, so a second entry
            point among them is not their problem. An empty turn-in is the
            student's state, not a BUILD-file bug: its programs are stand-ins
            saying there is no Makefile. Nothing the grader brings is linked
            in: the Makefile decides what is compiled. Refused where the
            contract's `files` do not hold that Makefile: every output test,
            at basic, runs the program it builds (_make_anchor_problem).
        no_missing_file_case: a sentence saying why no case of this program
            names a file that will not open, where its contract allows `open`
            (one whose files are all fixed names, or all on standard input).
            Default None, and then such a program's `cases` must hold one, a
            case with "missing_file" (_missing_file_problem). A case about a
            file's CONTENT is not that path: BSQ had five invalid maps and
            Rush 02 four broken dictionaries, all files that open, and no
            case naming one that does not -- and neither had C 10's ex02 and
            ex03, which had no error case at all (finding 110). A sentence
            given beside such a case fails too, as one given where the
            contract does not allow open: a reason that is not true is worse
            than none.
        model: where the cases' expected files came from, when a model of
            the tool the program imitates made them: the //oracle command a
            case's "args" follow, as a list of words (C 10 ex01: ["c10_run",
            "--prog", "ex01_bin", "cat"]). Default None. With it, each case
            with one expected file also gets exNN[_case]_model (layer oracle,
            complete; tools/model_check.sh), which runs that command on the
            case from where its program runs -- the same arguments, standard
            input, argument file, run folder and name that will not open --
            and fails when the file, on
            the stream the case compares, or the status it names in "exit",
            is not what the model answers. It runs nothing of the student's.
            A fixture made once and never re-made drifts in silence: a later
            fix to the model, or an edit by hand, showed first as a correct
            program going red (review of WP-50). Refused with no case that
            has one expected file, and beside a "sanitize" case
            (_model_problem).
        reference: default False. True when //oracle holds this program's
            reference, run as `oracle run <name> ARG...`: it then emits
            exNN_reference_cases (tag "oracle", complete), which runs EVERY
            case through diff_output.sh exactly as its output test does --
            the same argv, argument file, run folder, stdin and expected
            file(s) -- with the reference in the student's place, and fails
            a case the reference does not pass (tools/reference_cases.sh).
            It runs no student code, so it says the same on any tree, the
            template's stubs included. Rush 02's cases bound a dictionary and
            a number to an expected file by hand, in two places -- the
            oracle's pairs, which write the files, and the cases here -- and
            an edited number passed, since no correct program ran on the
            owner's tree: the reference now runs the case as written.
        refusals: for tools/tests/macro_fixtures only, where a list: a refusal
            this macro makes once its arguments are read (no_missing_file_case
            and the case it asks for, `model`) is appended there instead of
            failing the load, and nothing is emitted -- so a fixture can
            watch the real macro refuse (_refuse). Anywhere else it fails.
        allocfail: the name of one of `cases`, replayed with ONE of the
            program's own malloc() calls refused per run (allocfail_check.sh
            --bin): exNN_program_allocfail, at robust; or a list of them, one
            sweep each, the first exNN_program_allocfail and each other
            exNN_<case>_program_allocfail -- a program allocates on some paths
            and not on others, so pick cases that allocate (a large input, an
            error found part-way through), and a case on which it allocates
            nothing says so (NOTHING TO REFUSE, green). The program is built
            again as exNN_bin_allocfail, beside tools/allocfail_program.c with
            malloc and free wrapped (a Makefile project through its own
            `make -Bn`). It asks what every reading of a subject's rule for
            errors agrees on: the run ends by itself -- no signal, within its
            time -- with bounded output. No text and no status are asserted:
            what a program prints or returns on this path is its subject's to
            say, and this target reads nothing into it. ROBUST, not basic: no 42
            grader refuses a program an allocation, so this is the repo's
            rigour (TODO.md §23, WP-92, finding 150). Gated on the case's own
            output, like its valgrind arm; a large count of requests is
            sampled, first ones then spread to the last. Needs a subject that
            lets the program allocate (`malloc`) and `allocfail_rule`;
            default None, no target.
        allocfail_rule: why this program is asked it, as one string, required
            with `allocfail` (allocfail_rule_problem): the subject's own
            sentence, quoted, or -- for a subject with none, as C 10's -- what
            the call site reads in it, said as a reading. The report prints
            it under its verdict; the runner names no subject sentence of its
            own, since it cannot know which subject it is reading. One line;
            written to a file (exNN_program_allocfail_rule) and handed to the
            runner as --rule, as c_function's allocfail_rule is.
        allocfail_leaks: True adds exNN_program_allocfail_leaks, at robust:
            the same sweep, judging whether a run that ended by itself still
            held a block it obtained at exit -- what the valgrind arm asks of
            the plain run (still-reachable counts). Needs `allocfail`, a
            subject that allows free, and `allocfail_leaks_rule`; for a subject
            that says heap memory "must be freed correctly" (Rush 02). Default
            False.
        allocfail_leaks_rule: the freeing rule that target applies, as
            `allocfail_rule` is the sweep's: the leak target prints this one,
            because the reason to ask what a run holds at exit is a different
            sentence from the reason to refuse it memory. Required with
            `allocfail_leaks`; written to exNN_program_allocfail_leaks_rule.
        fixed_array: the subject's sentence asking for a fixed-size array
            ("You must complete this exercise by declaring a fixed-size
            array"), quoted with where it is from: emits exNN_fixed_array,
            the method layer at strict (tools/method_check.sh
            --fixed-array), which has the pinned gcc name every array of
            variable length and every alloca in the sources, and prints this
            sentence under its verdict. One line; written to
            exNN_fixed_array_rule. Default None, no target.
        fixed_array_bytes: where the subject bounds that array, the bound in
            bytes: every object of the program, on the stack or not, must be
            smaller, by the size gcc gives it -- an upper bound only, since
            "slightly less than" says no lower one. The sentence in
            `fixed_array` then says how the subject's unit was read
            (fixed_array_problem). Default None, no bound.
    """
    _entry(num, "c_program")  # first: a contract error names this macro
    ex = "ex" + num
    _no_orphan_prototype(ex, "c_program")
    if [c for c in (cases or []) if type(c) == "dict" and c.get("cwd_files")]:
        if (type(name) != "string" or not name or name in [".", ".."] or
            [ch for ch in ["/", " ", "\t", "'", "\""] if ch in name]):
            fail(("c_program(%s): name = %r, and a \"cwd_files\" case runs the " +
                  "program as ./<name>: give the subject's executable name.") % (ex, name))
    if makefile not in (True, False, "once_written"):
        fail(("c_program(%s): makefile = True, \"once_written\" or False. The Makefile " +
              "is the one at the top of the turn-in directory the subject() contract " +
              "names.") % ex)
    allowed = _allowed(num)

    # Before anything is declared, so a refusal a fixture watches emits nothing.
    # A Makefile it builds from is one the contract requires (finding 124's
    # class, as c_make holds it), and a Makefile the contract requires is
    # the one it builds from (_makefile_problem): together, makefile is on
    # exactly where the contract's `files` hold a Makefile.
    if makefile and _refuse(
        _make_anchor_problem(num, "Makefile", _entry(num, "c_program"), "c_program"),
        refusals,
        "c_program(%s)" % ex,
    ):
        return
    if _refuse(_makefile_problem(ex, makefile, _entry(num, "c_program")["files"]), refusals, "c_program(%s)" % ex):
        return
    if _refuse(_malloc_argument_problem(ex, malloc), refusals, "c_program(%s)" % ex):
        return
    malloc = _memcheck_allowed(_entry(num, "c_program"))
    if _refuse(_missing_file_problem(ex, allowed, cases, no_missing_file_case), refusals, "c_program(%s)" % ex):
        return
    if _refuse(_model_problem(ex, model, cases), refusals, "c_program(%s)" % ex):
        return
    if _refuse(_memory_rule_problem(num, malloc, cases, memory_rule), refusals, "c_program(%s)" % ex):
        return
    if srcs == None:
        srcs = _deliverable_srcs(ex)
        hdrs = _deliverable_hdrs(ex, hdrs)
    srcs = _zone(srcs)
    hdrs = _zone(hdrs or [])
    provided_srcs = _provided(num).srcs
    if makefile and provided_srcs:
        fail("c_program(%s): the contract has the grader bring a source, which " % ex +
             "has no effect with makefile = True -- the Makefile decides what is compiled.")

    # What is built while the Makefile is missing or compiles nothing:
    # every source of the folder, with makefile = "once_written".
    fallback_srcs = srcs if makefile == "once_written" else None

    # Both programs, plain and instrumented, from the same files. The headers
    # are staged with the sources: a sandbox holds only what a build declares,
    # so a deliverable that #includes its own header would otherwise fail with
    # "file not found" in every layer that RUNS it while norm and both compile
    # layers, which stage `hdrs`, stayed green. They must not be routed through
    # this macro's own `srcs` parameter, though: forbidden_symbols.sh would then
    # try to read symbols out of a .h and exit 2 as a harness error.
    #
    # The instrumented one is built UNCONDITIONALLY, outside the `if cases`
    # below. It used to sit inside it, which quietly excluded the exact module
    # the memory layer exists for: c-06 ex01-ex03 drive their runs from
    # c_argv_table, not from `cases`, so they passed no cases and got no
    # sanitizer at all. c_argv_table picks this target up by name for its own
    # asan arm -- an absent one there is a hard analysis error, not a skip.
    binname = ex + "_bin"
    asan_bin = ex + "_bin_asan"

    # A Makefile project's include path is the -I its recipes pass, and only
    # `make -Bn` knows it: the plain program's build writes it here, and the
    # compile and forbidden layers below compile with it (see _inc_args).
    inc_file = (binname + "_includes.txt") if makefile else None
    for target, asan in [(binname, False), (asan_bin, True)]:
        # The program's name, for the files layer (_built_programs).
        name_tag = [] if asan else [_PROGRAM_NAME_TAG + name]
        if makefile:
            _student_bin(
                name = target,
                tags = name_tag,
                makefile = turnin_dir(num) + "/Makefile",
                srcs = fallback_srcs,
                includes_out = None if asan else inc_file,
                # And the .c files it compiles, for the files layer
                # (_built_manifest): the same `make -Bn`, read once.
                sources_out = None if asan else binname + "_sources.txt",
                # The WHOLE tree under it, whatever the contract lets lie
                # there: which files the program is made of is the Makefile's
                # to say, and a source it names that was left unstaged would
                # read as one missing from the turn-in. Where the layout
                # breaks the subject, the files layer says so.
                make_data = turnin_glob(
                    [turnin_dir(num) + "/**"],
                    exclude = _not_build_products(turnin_dir(num)),
                ),
                hdrs = hdrs,
                asan = asan,
            )
        else:
            _student_bin(
                name = target,
                tags = name_tag,
                srcs = srcs + provided_srcs,
                hdrs = hdrs,
                archive = False,
                dir = turnin_dir(num),
                asan = asan,
            )
    _norm_test(ex + "_norm", srcs + hdrs)
    _compile_tests(ex, srcs, hdrs, inc_file = (":" + inc_file) if inc_file else None)
    _fixed_array_test(ex, num, fixed_array, fixed_array_bytes, srcs, hdrs, inc_file)

    if progname:
        _test(
            name = ex + "_progname",
            srcs = ["//tools:progname_test.sh"],
            args = [
                "--diff",
                "$(location %s)" % _DIFF,
                "$(location :%s)" % binname,
            ],
            data = [":" + binname, _DIFF],
            tags = ["output"],
        )

        # The exit status, at robust: see `progname` above and docs/reference.md.
        _test(
            name = ex + "_progname_exit",
            srcs = ["//tools:progname_test.sh"],
            args = [
                "--exit-only",
                "$(location :%s)" % binname,
            ],
            data = [":" + binname],
            tags = ["output"],
            level = 3,
        )

    # Memory layer for the program shape, on :exNN_bin_asan above. c_function
    # exercises get three (c_mem_check, diff_asan, the probe under memcheck);
    # c_program got NONE, leaving c-06, c-10 and c-11 ex05 -- twelve exercises
    # that read files, walk argv and index buffers -- never built with a
    # sanitizer at all. valgrind only covers the ones that malloc, and stdout
    # diffing structurally cannot see an out-of-bounds read that returns the
    # right bytes.
    if progname:
        # The same run as exNN_progname, under the sanitizer. argv[0] handling is
        # where this exercise can walk off the end of a string it does not own.
        _test(
            name = ex + "_progname_asan",
            srcs = ["//tools:asan_run.sh"],
            args = [
                "--bin",
                "$(location :%s)" % asan_bin,
                "--label",
                "%s/progname" % ex,
            ] + _symbolizer_args(),
            data = [":" + asan_bin] + _SYMBOLIZER_DATA,
            tags = ["asan"],
        )

    if type(reference) != "bool":
        fail(("c_program(%s): reference = True or False: True runs every case with " +
              "`oracle run %s`, //oracle's reference for the program.") % (ex, name))
    if reference and not cases:
        fail(("c_program(%s): reference = True, and there is no case for the reference " +
              "to run. Drop it, or give the program its cases.") % ex)
    if cases:
        rule = None
        if memory_rule:
            names_file(
                name = ex + "_memory_rule",
                names = [memory_rule],
            )
            rule = ":%s_memory_rule" % ex
        _emit_cases(ex, binname, cases, name, valgrind = malloc, memory_rule = rule)
        if model:
            _emit_model(ex, cases, model, name)
        if reference:
            _reference_cases_test(ex, cases, name)

        for c in cases:
            k = _case(c, "program", "c_program(num = \"%s\")" % num)
            stem = _case_stem(ex, cases, k.name)
            run_flags, run_files = _case_run(c, name)

            # A survive case's run under the sanitizer waits on the same case
            # its output test does (_survive_gate): a program nobody has
            # written ends by itself, memory-clean, so its asan arm was green
            # on every stub while the output test said SKIP.
            gate_args, gate_data = _survive_gate(ex, cases) if k.survive else ([], [])
            if gate_args:
                gate_args = [
                    "--gate-differ",
                    "$(location //tools:diff_output.sh)",
                    "--gate-bin",
                    "$(location :%s)" % binname,
                ] + gate_args
                gate_data = gate_data + [":" + binname, "//tools:diff_output.sh"]
            a_args = [
                "--bin",
                "$(location :%s)" % asan_bin,
                "--label",
                stem,
                "--show-run",
                _shown_bin(asan_bin),
            ] + gate_args + run_flags + _symbolizer_args() + ["--"] + c.get("args", [])
            _test(
                name = "%s_asan" % stem,
                srcs = ["//tools:asan_run.sh"],
                args = a_args,
                data = _uniq([":" + asan_bin] + run_files + gate_data + _SYMBOLIZER_DATA),
                tags = ["asan"],
                level = _raise("asan", k.level),
            )
    if allocfail != None or allocfail_leaks:
        why = program_allocfail_problem(
            allocfail,
            [c.get("name", "run") for c in (cases or [])],
            malloc,
            allocfail_leaks,
            allowed,
            allocfail_rule,
            allocfail_leaks_rule,
        )
        if why:
            fail("c_program(num = \"%s\"): %s" % (num, why))
        _program_allocfail(
            ex,
            num,
            name,
            cases,
            allocfail,
            allocfail_rule,
            allocfail_leaks_rule if allocfail_leaks else None,
            binname,
            makefile,
            srcs,
            hdrs,
            provided_srcs,
        )
    if allowed != None:
        _forbidden_test(
            ex + "_forbidden",
            srcs,
            allowed,
            hdrs = hdrs,
            provided = _provided_names(provided_srcs),
            inc_file = (":" + inc_file) if inc_file else None,
        )

def program_allocfail_problem(allocfail, case_names, malloc, leaks, allowed, rule, leaks_rule):
    """Why c_program may not emit its allocfail targets as asked; None if it may.

    A decision made while loading, so a function of its own that
    //tools/tests:starlark_unit calls both ways.

    Args:
      allocfail: the case name c_program's `allocfail` gives, a list of
        them, or None.
      case_names: the names of its cases ("run" for an unnamed one).
      malloc: c_program's `malloc`.
      leaks: c_program's `allocfail_leaks`.
      allowed: the exercise's allowed functions from its subject() contract,
        or None where the subject names none.
      rule: c_program's `allocfail_rule`.
      leaks_rule: c_program's `allocfail_leaks_rule`.

    Returns:
      None, or the reason as a sentence.
    """
    if allocfail == None:
        return "allocfail_leaks needs allocfail: the leak sweep replays its case."
    if not malloc:
        return ("allocfail needs a subject that lets the program allocate (its " +
                "contract's allowed line names malloc, or there is none): a program " +
                "that may not allocate has no allocation to refuse.")
    names = [allocfail] if type(allocfail) == "string" else allocfail
    if type(names) != "list" or not names or [n for n in names if type(n) != "string"]:
        return ("allocfail = %r: it names the case whose argv and stdin the sweep " +
                "replays, or a list of them, one sweep each.") % (allocfail,)
    if len({n: True for n in names}) != len(names):
        return "allocfail = %r names a case twice: one sweep per case." % (allocfail,)
    for n in names:
        if n not in case_names:
            return ("allocfail = %r names no case; the cases are %s. It names the " +
                    "cases whose argv and stdin the sweeps replay.") % (n, ", ".join(case_names) or "none")
    if leaks and "free" not in (allowed or []):
        return ("allocfail_leaks, and the subject() contract does not let this " +
                "exercise call free(): a program that may not release a block " +
                "cannot be asked to.")
    why = allocfail_rule_problem(rule)
    if why:
        return why
    if leaks:
        return allocfail_rule_problem(leaks_rule, "allocfail_leaks_rule")
    if leaks_rule != None:
        return ("allocfail_leaks_rule without allocfail_leaks: there is no leak " +
                "target to print it.")
    return None

# tools/allocfail_program.c is linked as a harness and calls nothing of the
# student's: the program's own main() runs (_student_bin's `prototype`).
_AF_PROGRAM_PROTO = ("none: tools/allocfail_program.c calls none of the program's " +
                     "functions; the program's own main() runs")

def _program_allocfail(ex, num, prog, cases, cnames, rule, leaks_rule, binname, makefile, srcs, hdrs, provided_srcs):
    """c_program's allocation-failure targets: see its `allocfail` and `allocfail_leaks`.

    `cnames` is the case to replay, or a list of them: the first one's sweep
    is exNN_program_allocfail, and each other's exNN_<case>_program_allocfail
    -- which requests a program makes depends on its input, so one case can
    leave error paths untried that another reaches. `leaks_rule` is None when
    there is no leak target, and that target's rule when there is one.

    Each sweep, and its gate, runs the case as its output test does: the run
    flags are _case_run's (stdin, argument file, run folder), which `prog`,
    c_program's `name`, names the program in. They once forwarded stdin
    alone, so Rush 02's one-argument case, which runs beside numbers.dict,
    ran from a folder with no dictionary: its gate was red on every correct
    program and the sweep SKIPped, and under NO_SKIP=1 it refused only what
    the missing-dictionary path asks for. c_levels()' audit holds every such
    gate to an output test of the package (_case_gate_problems)."""
    af_bin = ex + "_bin_allocfail"
    af_harness = ["//tools:allocfail_program.c", "//tools:allocfail_counter.h"]
    af_link = ["-Wl,--wrap=malloc", "-Wl,--wrap=free"]
    if makefile:
        _student_bin(
            name = af_bin,
            harness = af_harness,
            makefile = turnin_dir(num) + "/Makefile",
            srcs = srcs if makefile == "once_written" else None,
            make_data = turnin_glob(
                [turnin_dir(num) + "/**"],
                exclude = _not_build_products(turnin_dir(num)),
            ),
            hdrs = hdrs,
            archive = False,
            linkopts = af_link,
            prototype = _AF_PROGRAM_PROTO,
            tags = ["manual"],
        )
    else:
        _student_bin(
            name = af_bin,
            harness = af_harness,
            srcs = srcs + provided_srcs,
            hdrs = hdrs,
            archive = False,
            dir = turnin_dir(num),
            linkopts = af_link,
            prototype = _AF_PROGRAM_PROTO,
            tags = ["manual"],
        )
    names = [cnames] if type(cnames) == "string" else cnames
    for cname in names:
        first = cname == names[0]
        c = [x for x in cases if x.get("name", "run") == cname][0]
        k = _case(c, "program", "c_program(num = \"%s\")" % num)
        gate, gate_fs = _expected_args(ex, k, "--gate-expected", "--gate-expected-alt", None)
        run_flags, run_files = _case_run(c, prog)
        args = [
            "--bin",
            "$(location :%s)" % af_bin,
            "--label",
            "%s/%s" % (ex, cname),
            "--show-run",
            _shown_bin(af_bin),
        ]
        data = [":" + af_bin, "//tools:diff_output.sh"] + run_files
        if gate:
            args += [
                "--gate-differ",
                "$(location //tools:diff_output.sh)",
                "--gate-bin",
                "$(location :%s)" % binname,
            ] + gate
            data += [":" + binname] + gate_fs
        if c.get("stream"):
            args += ["--gate-stream", c["stream"]]
        if c.get("sanitize"):
            args.append("--gate-sanitize")
        if c.get("labeled"):
            args.append("--gate-labeled")
        # The runner hands its gate the argument file and the run folder
        # itself (as valgrind_test.sh does); stdin has its own gate flag.
        if c.get("stdin"):
            args += [
                "--gate-stdin",
                "$(location %s)" % c["stdin"],
            ]
        args += run_flags
        # The rule each target prints reaches the runner as a file (--rule FILE,
        # as c_function's allocfail_rule and valgrind's memory_rule do), since
        # sh_test tokenises `args` on blanks.
        stem = ex if first else _case_stem(ex, cases, cname)
        targets = [(stem + "_program_allocfail", [], rule)]
        if leaks_rule != None:
            targets.append((stem + "_program_allocfail_leaks", ["--leaks"], leaks_rule))
        for name, extra, sentence in targets:
            names_file(
                name = name + "_rule",
                names = [sentence],
            )
            _test(
                name = name,
                srcs = ["//tools:allocfail_check.sh"],
                args = args + extra + ["--rule", "$(location :%s_rule)" % name, "--"] + c.get("args", []),
                data = _uniq(data + [":%s_rule" % name]),
                tags = ["allocfail"],
                # robust: the _program_allocfail suffix's level (_SUFFIX_LAYER).
                # A case raised higher takes the sweep with it.
                level = max(3, k.level or 3),
                # The output test of the case it gates on, by name: another
                # case may share its expected file.
                waits = "%s_output" % _case_stem(ex, cases, k.name) if gate else None,
            )

# What a build LEAVES BEHIND, as opposed to what a student turned in. Running
# `make` or the creator script inside deliverable/ -- the first thing anyone does
# on c-09 ex00, whose entire job is to produce libft.a -- drops these there.
# .gitignore keeps them out of git, but native.glob reads the real directory, so
# a layer that globs without this sees them as deliverables.
#
# ONE list, shared, because c_files and c_make were written separately and
# disagreed: c_make excluded build products and wrote down why, c_files did not,
# and c-09 is the module that calls BOTH on the same directory with strict =
# True. The result was a student being failed with "this subject does not allow
# extra files: libft.a" for having done the exercise.
#
# The same list //tools:submit leaves out of the push (its ':(exclude)'
# pathspecs; //tools:conventions holds the two together): the files layers
# report what is pushed, so what is never pushed is never theirs to report.
_BUILD_PRODUCTS = ["*.o", "*.a", "*.out", "*.gch"]

def _not_build_products(d):
    """Glob exclude patterns for what is under directory `d` and never pushed.

    Build output (_BUILD_PRODUCTS), and any .git directory: //tools:submit
    keeps its scratch repository at deliverable/.git after a push (it is
    rebuilt on the next), and git never pushes a .git directory's contents.
    Left in, the first submit made the files layers that walk the whole tree
    -- deliverable_files, and BSQ's ex00_files at the root -- report .git/HEAD
    and the rest as files nobody asked for, and the next submit's gate refuse
    the module over them.
    """

    # `**/` matches zero or more segments, so this covers both d/x.o and
    # d/srcs/x.o -- a Makefile run by hand leaves its objects beside sources
    # in a subdirectory as readily as beside the Makefile.
    return [d + "/**/" + p for p in _BUILD_PRODUCTS] + [d + "/**/.git/**"]

def _built_programs(ex):
    """The names of the programs exercise `ex` builds, as declared above c_levels().

    c_make's artifact (its exNN_build test's --artifact) and c_program's
    name (the "program_name=" tag on its exNN_bin). A word with a / or a
    blank in it names no file of the turn-in, and is left out.
    """
    out = []
    build = native.existing_rule(ex + "_build")
    if build and build.get("args"):
        a = list(build["args"])
        for i in range(len(a) - 1):
            if a[i] == "--artifact":
                out.append(a[i + 1])
    prog = native.existing_rule(ex + "_bin")
    if prog:
        for t in prog.get("tags") or []:
            if t.startswith(_PROGRAM_NAME_TAG):
                out.append(t[len(_PROGRAM_NAME_TAG):])
    return sorted({p: True for p in out if p and "/" not in p and " " not in p and "$" not in p}.keys())

# The tag c_program puts on its exNN_bin, naming the program (_built_programs).
_PROGRAM_NAME_TAG = "program_name="

def _fixed_array_test(ex, num, rule, max_bytes, srcs, hdrs, inc_file):
    """exNN_fixed_array, the method layer's reading of a fixed-size array (c_program's `fixed_array`).

    Compiled as the compile layers compile -- the same sources, the grader's
    include path (_inc_args, and a Makefile's own -I through `inc_file`) --
    by the pinned gcc, the one campus compiler that names an object by its
    size (-Wlarger-than=), and proved pinned the way compile_check.sh proves
    it (--cc-under). Nothing is assembled, so no assembler is handed over.
    """
    why = fixed_array_problem(rule, max_bytes)
    if why:
        fail("c_program(num = \"%s\"): %s" % (num, why))
    if rule == None:
        return
    gcc = [c for c in _CAMPUS_CCS if c["label"] == "gcc"][0]
    names_file(
        name = ex + "_fixed_array_rule",
        names = [rule],
    )
    args = [
        "--fixed-array",
        "--rule",
        "$(location :%s_fixed_array_rule)" % ex,
        "--cc",
        gcc["cc"],
        "--cc-under",
        "$(location %s)" % gcc["under"],
    ]
    if max_bytes != None:
        args += ["--max-bytes", str(max_bytes)]
    for s in srcs:
        args += ["--src", "$(location %s)" % s]
    args += _inc_args("--inc", hdrs)
    data = srcs + hdrs + gcc["data"] + [":%s_fixed_array_rule" % ex]
    if inc_file:
        args += ["--inc-file", "$(location :%s)" % inc_file]
        data.append(":" + inc_file)
    _test(
        name = ex + "_fixed_array",
        srcs = ["//tools:method_check.sh"],
        args = args,
        data = data,
        tags = ["method"],
        turnin = srcs,
        gated = True,
    )

def c_files(num, label = None, name = None):
    """Deliverable file-set check (tag "files"), from the subject contract.

    The Moulinette looks at WHICH FILES were turned in before it looks at what
    they do. Nothing else here says it by name: a missing required file makes
    the other layers "not turned in" tests or stand-ins (see _test and
    _student_bin), which say the folder has nothing to check rather than which
    file the subject asks for, and an extra file is invisible entirely --
    while //tools:submit still pushes it to Vogsphere.

    c_levels() emits one for every exercise in the project's subject()
    contract, so a BUILD file does not call this: everything it checks is the
    contract's, and a list written at a call site would be a second copy of
    the subject's turn-in line. It stays public for a package that is not a
    project (tools/tests/macro_fixtures).

    What it reads from the contract:

      files      REQUIRED: a missing one FAILS, which is the whole point --
                 without this layer it is "nothing to check" somewhere else,
                 or nothing at all.
      optional   what may be there without a word: names, and patterns
                 expanded against the directory (rush-01's "*.c"), so any file
                 that is NOT one of them -- the binary a hand-run cc leaves
                 beside the sources -- is still reported.
      provided   what the GRADER brings. A copy in the turn-in is reported
                 under a heading of its own, since the student never turns
                 one in -- unless `optional` names it too (C 12 ex08's
                 ft_list.h, which page 5 asks for in every exercise).
      strict     an extra file FAILS rather than warns. Missing and extra are
                 different situations: the subject names its files exactly,
                 so a missing one is not arguable, whereas an extra one is
                 sometimes defensible (the Norm bans declaring a struct in a
                 .c file, so a rush that wants one needs a header the subject
                 never mentions).
      grader     how the warning about an extra file is worded: a person at
                 a defense can be told why it is there, a program cannot.

    The directory is the exercise's turn-in directory, globbed WHOLE: every
    file under it, each named by its path from there (srcs/main.c), because
    git pushes the tree and not one level of it. It used to be globbed flat
    unless the contract let files sit in subfolders, so a copy kept in old/
    or backup/ was never an input of any test and was pushed without a word
    (finding 102); a subfolder the contract does not allow now holds files
    nobody asked for, reported by path. Build products (*.o, *.a, *.out,
    *.gch) are left out at any depth, so having run `make` in deliverable/
    cannot fail you for producing what the exercise asked for --
    //tools:submit leaves them out of the push too -- and so is a .git
    directory, which git never pushes (_not_build_products).

    WHAT A MAKEFILE BUILDS. Where the exercise's program is built from what
    its Makefile compiles (c_program(makefile = True or "once_written"):
    BSQ, Rush 02, C 10, C 11 ex05, Reloaded ex27), that build writes the .c
    files `make -Bn` named (exNN_bin_sources.txt), and wherever else the
    contract has a Makefile turned in beside .c files allowed by pattern --
    an exercise with no c_program, its Makefile c_make's alone -- this
    declares a build for that list alone (exNN_make_bin_sources.txt,
    _manifest_build).
    This layer reads it: a .c the contract allows only as one of "the
    necessary files" and the Makefile never compiles is not necessary, and
    counts as an extra file (files_test.sh --built; finding 164). The list
    comes from native.glob, which sees the real directory at analysis time
    -- a test sandbox only ever contains files that were already declared,
    which is precisely the blind spot this closes. It reaches the runner as NAMES, in a file (tools/names_file.bzl),
    never as labels: this layer reads no file's contents, and it is the one
    layer that must report a file whose name no label can carry ("ft_putchar
    (1).c"), which every other layer drops (see _SAFE_CHARS).

    Args:
        num: the exercise number as a two-digit string ("00"). It names the
            target (exNN_files) and selects the contract entry.
        label: the heading the report is printed under; default None builds
            "<package>/<turn-in directory>". fail()s if a label contains a
            space: sh_test tokenises `args` on whitespace, so a two-word label
            would arrive as two arguments and the runner would reject the
            second as an unknown option.
        name: unused, for the reason c_levels gives: every macro takes one,
            and buildifier's unnamed-macro check holds this one to it since it
            declares a rule besides its test (the exNN_files_names list).
            Every target here is named from `num`."""
    e = _entry(num, "c_files")  # first: a contract error names this macro
    ex = "ex" + num
    contract = _contract("c_files")
    if e["files"] == None:
        fail(("c_files(num = \"%s\"): the contract names no file for this exercise " +
              "(files = None), so there is nothing for a files layer to require.") % num)
    d = turnin_dir(num)
    actual = native.glob(
        [d + "/**"],
        exclude = _not_build_products(d),
        allow_empty = True,
    )

    # sh_test args are shell-tokenised, so a label containing a space silently
    # becomes two arguments and the script rejects the second as an unknown
    # option. Catch it here, where the error names the cause.
    if label and " " in label:
        fail("c_files: label must not contain spaces (sh_test tokenises args): %r" % label)

    # A pattern is expanded against the directory, through turnin_glob(), so a
    # name no label can carry ("main (1).c") is never "allowed" by a *.c: it is
    # left for the report, which is the one place it is seen.
    optional = []
    for p in e["optional"]:
        if "*" in p:
            optional += [f[len(d) + 1:] for f in turnin_glob([d + "/" + p])]
        else:
            optional.append(p)
    provided = [v for v in e["provided"].values() if v not in optional]
    strict = contract["strict"] if e["strict"] == None else e["strict"]

    names_file(
        name = ex + "_files_names",
        names = [f[len(d) + 1:] for f in actual if "\n" not in f],
    )
    args = ["--label", label or (native.package_name() + "/" + d), "--grader", contract["grader"]]
    for f in e["files"]:
        args += ["--required", f]
    for f in optional:
        args += ["--optional", f]
    for f in provided:
        args += ["--provided", f]
    args += ["--actual-list", "$(rootpath :%s_files_names)" % ex]
    if strict:
        args.append("--strict")
    if e["dir"] == None:
        # The root of deliverable/: files left in an exNN/ folder there get
        # the command that moves them up (files_test.sh --root).
        args.append("--root")
    data = [":%s_files_names" % ex]

    # The .c files the Makefile compiles, where the program's build wrote
    # them: c_program(makefile = True) declared it above this call (c_levels()
    # emits this layer after every other macro of the module). Where no
    # build wrote one and the exercise turns in a Makefile beside .c files it
    # may name as it likes, a build for the list alone is declared here.
    built = _built_manifest(ex) or _manifest_build(num, e, d)
    if built:
        args += ["--built", "$(rootpath %s)" % built, "--build-target", ex + "_build"]
        data.append(built)

    # The programs the exercise builds, by name (_built_programs): a file of
    # that name in the turn-in is a build product, which fails even where
    # the subject leaves its file list open.
    for p in _built_programs(ex):
        args += ["--program", p]

    _test(
        name = ex + "_files",
        srcs = ["//tools:files_test.sh"],
        args = args,
        data = data,
        tags = ["files"],
    )

def c_issued(num, file, name = None):
    """A file 42 issues with the subject is in the turn-in (tag "output", basic).

    For a file tools/resources.tsv registers with the role turn-in: 42's own,
    which the template does not ship and its .gitignore keeps out of commits,
    and which the subject makes part of what is turned in -- Rush 02's
    numbers.dict, which the one-argument form `./rush-02 42` reads from where
    the program runs, under "Files to turn in: Makefile and all the necessary
    files". While it is missing the test FAILS, at basic: a SKIP exits 0, and
    //tools:submit would push a turn-in that cannot run at the defence
    (finding 162). A test of its own, not a `files` requirement of the
    contract, so that the files layer stays green on a fresh clone and this
    red reads as one more thing to do, beside the program's own.

    The contract names the file, in the exercise's `optional`, and this
    points at that entry: its path is turnin_file()'s, and loading fails
    unless the contract lists the name there (_issued_problem). Spelled here
    alone, the files layer called the file extra while this test demanded
    it, and nothing caught the two disagreeing.

    The file is found by a glob, never named as a label: absent on the
    template by design, a label would take the whole package down there. The
    test reads the registry's row for the path (tools/issued_test.sh), and its
    report is worded from it -- where to download the file, where it goes --
    so that it cannot disagree with the strip, the ignore rule, the
    placeholder and the docs, which read the same row. A path the registry
    does not list, or lists as a harness file, stops the test (exit 2).
    //tools:conventions checks that every turn-in row has its c_issued.

    Args:
        num: the exercise whose turn-in directory holds the file; the test is
            exNN_<file, dots and dashes as underscores>_issued.
        file: the name 42 gives the file, as the registry's `file` column
            and the exercise's `optional` in the contract list it.
        name: unused; every target is named from `num` and `file`.
    """
    problem = _issued_problem(num, file, _entry(num, "c_issued"))
    if problem:
        fail(problem)
    ex = "ex" + num
    path = turnin_file(num, file)
    stem = "%s_%s" % (ex, file.replace(".", "_").replace("-", "_"))
    found = native.glob([path], allow_empty = True)
    pkg = native.package_name()
    names_file(
        name = stem + "_found",
        names = ["%s/%s" % (pkg, f) for f in found],
    )
    _test(
        name = stem + "_issued",
        srcs = ["//tools:issued_test.sh"],
        args = [
            "--registry",
            "$(location //tools:resources.tsv)",
            "--path",
            "%s/%s" % (pkg, path),
            "--found-list",
            "$(rootpath :%s_found)" % stem,
        ],
        data = ["//tools:resources.tsv", ":%s_found" % stem] + found,
        tags = ["output"],
    )

def _built_manifest(ex):
    """The label of the .c list `make -Bn` gave exercise `ex`'s Makefile, or None.

    Written by the plain program's build where c_program(makefile = True)
    declared one (_student_bin's sources_out): the files layer reads it to
    tell a source the Makefile compiles from one it never does.
    """
    r = native.existing_rule(ex + "_bin")
    if r and r["kind"] == "student_binary" and r.get("sources_out"):
        return ":%s_bin_sources.txt" % ex
    return None

def _manifest_build(num, e, d):
    """A build of exercise `num`'s Makefile for its .c list alone, declared; its label, or None.

    WHICH .c FILES THE MAKEFILE BUILDS, wherever the contract has the
    exercise turn in a Makefile and allows .c files by pattern ("Makefile,
    and files needed for your program"): a source the Makefile never
    compiles is no file it needs, and was one of the "files it allows"
    (finding 164). Called by c_files only where no program's build wrote
    the list already (_built_manifest) -- an exercise with no c_program,
    since one builds through its Makefile (_makefile_problem) -- so a Makefile
    is never built twice for it: c_make used to declare this wherever the
    contract allowed .c by pattern, and BSQ and Rush 02, whose programs
    write it, carried a second build that nothing read. Tagged manual, so
    only the files layer that reads it builds it. From the contract, not
    from a c_make call, so a Makefile project cannot leave it out.

    Args:
        num: the exercise, as its contract entry is keyed.
        e: its contract entry.
        d: its turn-in directory (turnin_dir(num)).
    """
    if "Makefile" not in (e["files"] or []) + e["optional"]:
        return None
    if not [p for p in e["optional"] if "*" in p and p.endswith(".c")]:
        return None
    ex = "ex" + num
    _student_bin(
        name = ex + "_make_bin",
        makefile = d + "/Makefile",
        sources_out = ex + "_make_bin_sources.txt",
        make_data = turnin_glob([d + "/**"], exclude = _not_build_products(d)),
        tags = ["manual"],
    )
    return ":%s_make_bin_sources.txt" % ex

def c_cycles(
        num,
        fn,
        oracle_fn,
        harness,
        unit_expr = None,
        unit_name = "case",
        budget = None,
        syscall_budget = None,
        srcs = None,
        hdrs = None,
        count = 3000,
        max_unit = None,
        gate_expected = "expected.txt",
        gate_labeled = False,
        gate_sanitize = False,
        gate_stdin = None):
    """Instruction and syscall accounting for one function (tag "cycles").

    Counts INSTRUCTIONS via callgrind, attributed to the exercise's function and
    what it calls, excluding the harness. Deterministic — the same number every
    run — where the perf layer's wall time is mostly harness noise.

    Reported per UNIT OF WORK (bytes scanned, digits printed) rather than per
    call, because a per-call figure has nothing to be read against. `unit_expr`
    is an awk expression over one tab-separated corpus line, so the unit is
    derived from the very inputs the test ran.

    budget / syscall_budget are NUMBERS a good implementation achieves — never a
    reference implementation. A target tells a student where they stand; source
    code would tell them the answer, which a test here must never do.

    NEITHER BUDGET CAN FAIL THE TEST. This layer reports and never gates: every
    branch prints and the runner ends in exit 0. That is deliberate — an
    instruction count is something to think about, not a rule, and the one thing
    worse than no budget is a budget that reds correct code for being written
    differently. Say it here because the alternative reading is available: a
    syscall_budget of 0 reads like the assertion "this function must not enter
    the kernel", and it is a statement, not an assertion. If you ever want it to
    gate, run all 24 syscall_budget = 0 targets first — a function that
    legitimately writes would become a brand-new false red.

    It builds its own binary at -O2 rather than reusing Bazel's: `fastbuild` is
    -O0, which inflated ft_strlen from 3.2 to 11.4 instructions per byte and
    would have made optimal code look three times too slow.

    Args:
        num: exercise number as a string, "07" not 7, because it is pasted into
            names: tests/exNN/ for the fixtures below, and :exNN_bin for the
            correctness gate. That last one is a hard dependency -- this layer
            measures an exercise some other macro (c_function, c_libft,
            c_program) has already given a harness binary, and attaching it to
            an exercise without one is a Bazel analysis error, not a skip.
        fn: the student's function, by name. It is the symbol asked of
            callgrind_annotate -- INCLUSIVELY, so the figure covers everything
            that function calls and nothing the harness does around it. An
            empty deliverable directory makes this layer a "not turned in"
            test (see _test). A symbol the profile does not carry
            (inlined away, or, in the runner's own words, not defined by the
            deliverable) SKIPs green; NO_SKIP=1 turns that into a failure.
        oracle_fn: which arm of //oracle:oracle generates the corpus, e.g.
            "c01_strlen" -- normally the same arm c_diff already names for this
            exercise. It is run as `oracle <arm> 1 <count>`: the seed is fixed
            at 1 here, where c_diff and c_perf expose one, because an
            instruction count is only worth comparing with last week's if the
            inputs did not move. An arm that no longer exists yields an empty
            corpus and SKIPs green -- again, NO_SKIP=1 makes it speak.
        harness: the reader harness under tests/exNN/, in practice the very
            diff_*.c file c_diff uses: it reads corpus lines on stdin, calls fn
            and prints. //tools:diffio.h is on its include path. It is rebuilt
            here rather than reused, for the -O2 reason above, and the rebuild
            is the harness and srcs and nothing else -- the harness without
            debug information and srcs with it, which is how the runner tells
            the student's calls (a helper's write() or malloc()) from the
            harness's (a callback it hands over) -- there is no library to
            pass, so a harness that needs one (as c-12's diff harnesses need
            the grader's ft_create_elem) cannot be measured by this layer.
        unit_expr: an awk expression over ONE tab-separated corpus line, summed
            across the corpus to give the denominator of the per-unit figure.
            Default None means one unit per case, i.e. a per-call number, which
            is the figure the paragraph above says has nothing to be read
            against -- so most callers set it. The unit is every input byte the
            function must read at least once (a floor that is the same whatever
            technique is used), or what it must write: read each harness's own
            "Line:" comment for which fields those are -- copying another
            exercise's expression is how C 07 ex03 came to count the digits of
            a decimal size. Corpus fields are hex-encoded (tools/diffio.h
            decodes them), so the byte count of an input is length($1)/2 and
            not length($1). Write ordinary awk, blanks, quotes and $ included:
            the macro passes it through shell_word(), which carries it over
            Bazel's expansion and tokenising of `args` as written. The runner
            exits 2 (the harness broke, nothing was measured) when awk refuses
            the expression, or when it counts fewer than one unit per case,
            which is how a wrong field shows.
        unit_name: what one unit IS, singular, as printed in "per byte" / "per
            digit" and in the closing advice. Default "case", which is exactly
            what a missing unit_expr measures. fail()s on a space: it is one
            word of the report ("per element"), and Bazel would split it.
        budget: instructions per unit that a good implementation achieves,
            MEASURED at -O2 on correct answers and never guessed, and only
            where it does not depend on the technique: a per-unit cost that
            follows the lookup a student chose (ft_split, ft_convert_base, a
            sort) gets none, because a budget would recommend the technique it
            was measured from. It is read against the figure WITHOUT the
            allocator: malloc() and free() are counted in the figure and shown
            beside it, and how many blocks to ask for is the student's choice.
            Optional; without one the per-unit figure is printed bare, with
            nothing to read it against. With one the runner says "at or near
            the budget", "some slack, nothing alarming", or "about Nx the
            budget ... what is the loop doing that it need not?" -- and then
            exits 0 either way, as the paragraph above insists. Tested for
            truth rather than for None, so budget = 0 reads as no budget at
            all; nothing runs in zero instructions, so there was nothing for it
            to say.
        syscall_budget: write() calls per case, counted from callgrind's own
            call records rather than priced, since kernel time is not in the
            instruction count at all. Tested against None, NOT for truth, and
            the asymmetry with `budget` is the whole point: 0 has to get
            through, because it is the strongest thing a target here can say --
            "this function has no business entering the kernel" -- and the
            runner has a branch that compares the RAW count for it (one stray
            write across 3000 cases averages to 0.00 and would otherwise read
            as "at budget"). It is still only a statement; it cannot fail the
            test. A function whose job IS output cannot be budgeted below 1
            per case, and one whose output differs from its input gets none
            at all: a write() budget holds for only one way of handing output
            to write(), so it would recommend that way over the others.
            Counted for the student's own functions, helpers included, and
            never for a callback the harness hands over.
        srcs: the deliverable sources compiled with the harness at -O2. Default
            None globs deliverable/exNN/*.c through _deliverable_srcs(), which
            is what every call site relies on today; the parameter survives as
            the escape hatch for a deliverable that is not simply that
            directory. Read _deliverable_srcs()'s docstring before setting it:
            naming files at one macro's call site while leaving another at its
            default is exactly how c-07 ex04 came to be compiled by halves -- a
            link error at -O2 naming a function the exercise's other source
            defines, which reads as a problem with the optimisation level
            rather than as a missing file.
        hdrs: headers the harness and the sources include. With `srcs` left
            at its default, every deliverable/exNN/*.h is added after the ones
            listed (see _deliverable_hdrs) -- c-12's ft_list.h, c-13's
            ft_btree.h -- and what the grader brings (the contract's
            `provided`, c-12 ex08's ft_list.h) after those; list only a
            header that lives elsewhere. A header nobody declares is not staged into
            the sandbox at all, so before this existed every c-12/c-13 cycles
            target died at its -O2 rebuild on "'ft_list.h' file not found" the
            moment NO_SKIP=1 opened its gate: a broken BUILD rule wearing the
            look of a broken deliverable.
        count: how many corpus cases to profile. Default 3000, and small on
            purpose -- callgrind runs ~90x slower than native, and instruction
            counts are deterministic, so a larger corpus buys no precision and
            only test time. (The test is declared "medium" for the same
            reason.)
        max_unit: leave out every case of more than this many units: the
            cases a corpus holds to test CAPACITY (finding 041), which the diff
            and diff_asan layers judge. Without it, C 07's two split strings of
            hundreds and thousands of words were half the bytes profiled, and
            the figure per byte measured their mix rather than the function's
            usual cost. The report says how many it left out. Needs
            unit_expr; default None keeps every case.
        gate_expected: this exercise's own output fixture under tests/exNN/,
            default "expected.txt". Before measuring anything the runner
            replays :exNN_bin against it through diff_output.sh and SKIPs --
            saying so -- when it does not pass. Counting the instructions of a
            wrong answer is not information, and a beginner whose exNN_output
            is red should not also be told about instructions per byte. Same
            gate the diff, perf, valgrind and allocfail layers use; NO_SKIP=1
            forces it open.
        gate_labeled: pass --labeled to that gate run. Cosmetic here and
            accepted for symmetry with the other gated layers: --labeled only
            picks the table's CASE column, the verdict compares whole lines,
            and this gate throws the table away. Set it to match the exercise's
            c_function/c_libft(labeled = ...) anyway, so the call sites can be
            read against each other.
        gate_sanitize: pass --sanitize to the gate run, and it MUST likewise
            agree with the exercise's c_function(sanitize = ...): --sanitize
            changes diff_output.sh's verdict, so a mismatch makes the gate
            misread a correct exercise as red and this layer then skips
            forever while looking green.
        gate_stdin: a file LABEL fed to the gate run's stdin, for an exercise
            whose fixture reads input rather than taking argv. Passed through
            as given -- unlike gate_expected it is not resolved under
            tests/exNN/. No call site passes one today; it is wired to `data`
            the way c_diff and c_perf wire theirs, because it used to expand the
            label with $(location) and NOT declare it, which would have failed
            analysis for whoever passed the first one.
    """
    _entry(num, "c_cycles")  # first: a contract error names this macro
    libs = _linked(num).libs
    ex = "ex" + num

    # sh_test tokenises args on spaces, so a two-word unit name silently becomes
    # two arguments and the script rejects the second. Catch it where the error
    # names the cause. (c_files learned this the same way.)
    if " " in unit_name:
        fail("c_cycles: unit_name must be a single word (sh_test tokenises args): %r" % unit_name)
    if srcs == None:
        srcs = _deliverable_srcs(ex)
        hdrs = _deliverable_hdrs(ex, hdrs)
    srcs = _zone(srcs)
    hdrs = _zone(hdrs or [])

    # What the grader brings is compiled in too, as every other build of the
    # student's code has it (the contract's `provided`).
    provided = _provided(num)
    hdrs = hdrs + [h for h in provided.hdrs if h not in hdrs]
    own_srcs = srcs
    srcs = srcs + provided.srcs
    harness_f = "tests/%s/%s" % (ex, harness)
    expected_f = "tests/%s/%s" % (ex, gate_expected)

    args = [
        "--oracle",
        "$(location //oracle:oracle)",
        "--oracle-fn",
        oracle_fn,
        "--symbol",
        fn,
        "--harness",
        "$(location %s)" % harness_f,
        "--inc",
        "$(location //tools:diffio.h)",
        "--count",
        str(count),
        "--unit-name",
        unit_name,
        "--gate-differ",
        "$(location //tools:diff_output.sh)",
        "--gate-bin",
        "$(location :%s_bin)" % ex,
        "--gate-expected",
        "$(location %s)" % expected_f,
    ]
    for src in srcs:
        args += ["--src", "$(location %s)" % src]
    args += _inc_args("--inc", hdrs)

    # The grader's own functions (the contract's `linked`), linked after
    # the sources.
    for lib in libs:
        args += ["--lib", "$(location %s)" % lib]
    if unit_expr:
        # Bazel expands `args` ($1 alone is an error there) and then splits
        # them as a shell would, removing quotes and backslashes: shell_word()
        # carries the expression over both, so a caller writes ordinary awk.
        # It used to double the '$' here and refuse a blank, a quote or a
        # backslash it could not carry (finding 131): a second quoting of an
        # args word, which //tools:conventions refuses.
        args += ["--unit-expr", shell_word(unit_expr)]
    if max_unit != None:
        if not unit_expr:
            fail("c_cycles(num = %r): max_unit counts units, and unit_expr says what one is" % num)
        args += ["--max-unit", str(max_unit)]
    if budget:
        args += ["--budget", str(budget)]
    if syscall_budget != None:
        args += ["--syscall-budget", str(syscall_budget)]
    if gate_labeled:
        args.append("--gate-labeled")
    if gate_sanitize:
        args.append("--gate-sanitize")
    extra_data = []
    if gate_stdin:
        args += ["--gate-stdin", "$(location %s)" % gate_stdin]
        extra_data.append(gate_stdin)

    _test(
        name = ex + "_cycles",
        srcs = ["//tools:cycles_check.sh"],
        args = _pinned_build_args() + args + _valgrind_args(tool = _VG_CALLGRIND, annotate = True),
        data = _valgrind_data(tool = _VG_CALLGRIND, annotate = True) + _PINNED_BUILD_DATA + [
            "//oracle:oracle",
            "//tools:diff_output.sh",
            "//tools:diffio.h",
            harness_f,
            expected_f,
            ":%s_bin" % ex,
        ] + srcs + hdrs + libs + extra_data,
        # callgrind is ~90x slower than native; 3000 cases keeps it a few
        # seconds. Instruction counts are deterministic, so more cases would
        # buy nothing.
        size = "medium",
        tags = ["cycles"],
        turnin = own_srcs,
        gated = True,
    )

def c_reference_cost(
        num,
        fn,
        oracle_fn,
        harness,
        units,
        unit_name = "solution",
        kind = "search",
        srcs = None,
        hdrs = None):
    """Instructions per unit of work, beside an optimised reference's (tag "cycles").

    INFORMATIVE ONLY: this layer can never fail on what it measures.

    c_cycles reads a per-unit figure against a BUDGET — a number written into
    the BUILD file. That works where the floor is arguable from first
    principles: a byte scan is a load, a compare and an increment, so "3.2 per
    byte" reads itself. It does not work for a search. Nobody can say from first
    principles what one of the 724 ten-queens boards ought to cost, so a budget
    there would be a number someone invented and then defended as physics — and
    this repo would rather print nothing than print a figure a student cannot
    tell is wrong (see the note at the foot of c-piscine/c-piscine-c-05/BUILD.bazel, where
    exactly that killed a modelled unit for the arithmetic family).

    So this layer measures against something instead of asserting at it. The
    //oracle arm named by `oracle_fn` does the SAME job and produces the SAME
    bytes as the student's binary — for ex08, all 724 boards plus the count, and
    measured, exactly 725 write() calls on each side. Identical output through
    an identical number of syscalls means the two instruction counts differ by
    the algorithm and by nothing else, which is the only comparison worth
    showing a student. (An oracle that printed nothing would look wildly cheaper
    for the dishonest reason that it skipped all the formatting.)

    WHY IT MUST NOT GATE. Being several times a tuned reference is a perfectly
    good place to be on an exercise whose subject asks only for 724 correct
    boards. The figure is here to raise a question — the same tree, the same
    syscalls, so where does the difference live? — not to grade an answer that
    is already correct. The runner exits 0 whatever the ratio says; the only red
    this target can produce is its own plumbing breaking.

    Correctness first, like every other rigour layer: the runner re-runs this
    exercise's own output fixture and SKIPs while it is red. A student whose
    function prints the wrong boards must not be handed a cost figure — the cost
    of a wrong answer is not information, and it would arrive on top of the one
    failure they should be reading.

    Tagged "cycles" and NOT given a tag of its own, deliberately. It is the same
    kind of measurement (callgrind, instructions, per unit of work, level
    `complete`), and a new layer tag is not free: it needs an _LAYER_LEVEL entry,
    a row in docs/reference.md, the layer count in AGENTS.md bumped, and a decision about
    where it sits in the submit gate's ladder. None of that would buy anything
    here.

    Args:
      num: exercise number, e.g. "08".
      fn: the subject's function. It names the default deliverable source, forms
        the report's label, and reaches the runner as --symbol. It is NOT what
        the count is attributed to: unlike c_cycles, this layer measures WHOLE
        PROCESS totals on both sides, because the reference is a different
        binary in a different language and the two share no symbol to compare.
        That is fair here only because both processes do the same job end to
        end, and it errs safe — the startup both include is common, so it can
        only pull the ratio towards 1.0.
      oracle_fn: the //oracle arm that does the same job and prints the same
        bytes. It must PRINT: a reference that skipped the formatting would look
        cheaper for a reason that has nothing to do with the algorithm.
      harness: the main() under tests/exNN/ that calls fn. The runner compiles it
        with the deliverable at -O2 itself, because Bazel's fastbuild is -O0 and
        would inflate the student's side ~3.6x against an optimised reference.
      units: how many units of work ONE run performs — 724 solutions for ex08.
        A constant, because the function takes no input and always does the same
        search. It divides the instruction count, so it must be positive.
      unit_name: what one unit is called in the report. One word, no spaces.
      kind: which closing interpretation the report ends with, "search" or
        "output". Everything before it — the build, the two profiled runs, the
        table, the refusal to gate — is identical; only the paragraph that says
        WHERE the difference lives forks, because only that part was ever
        exercise-specific. A backtracking search is explained by the shape of
        its tree and the price of testing one candidate; an exercise whose whole
        job is emitting a fixed byte stream has no tree and no candidate, and
        the same words would send a student hunting for a search that is not in
        their file. For "output" the axis is how many times the program enters
        the kernel to hand its bytes over — precisely the axis the instruction
        ratio cannot see, since callgrind counts user instructions and a
        syscall's cost is almost all on the other side of the mode switch.
      srcs: defaults to the exercise's deliverable, like every other macro here.
      hdrs: headers to stage for that -O2 compile; each one's directory joins
        the include path. With `srcs` at its default, every deliverable/exNN/*.h
        is added after the ones listed (see _deliverable_hdrs).

    Gate wiring is derived, not parameterised: :exNN_bin and
    tests/exNN/expected.txt, the very targets c_function already declares. There
    are deliberately no gate_labeled / gate_sanitize / gate_stdin knobs — the one
    caller needs none of them, and a pass-through nobody has ever run is how a
    gate ends up silently misreading a passing exercise as red and skipping
    forever. Add them WITH a caller that exercises them.
    """
    _entry(num, "c_reference_cost")  # first: a contract error names this macro
    ex = "ex" + num

    # sh_test tokenises `args` on whitespace, so any value containing a space
    # arrives as two arguments and the runner rejects the second as an unknown
    # option. This repo has now been bitten three times (c_files' label,
    # c_cycles' unit_name and unit_expr) and the symptom is always the same: a
    # red test blaming something that is not the cause. Check everything that is
    # passed through verbatim, here, where the message can name the real one.
    if kind not in ("search", "output"):
        fail("c_reference_cost: kind must be \"search\" or \"output\", got %r" % (kind,))

    for argname, value in [
        ("unit_name", unit_name),
        ("oracle_fn", oracle_fn),
        ("fn", fn),
    ]:
        if " " in value:
            fail(("c_reference_cost: %s must be a single word (sh_test " +
                  "tokenises args): %r") % (argname, value))

    # `units` divides both instruction counts. Zero or negative would divide by
    # zero in the runner and print a figure that means nothing, and since this
    # layer never fails on its numbers, nothing downstream would catch it. It is
    # a per-exercise constant, so checking it at analysis time is free.
    if type(units) != "int" or units <= 0:
        fail("c_reference_cost: units must be a positive integer, got %r" % (units,))

    if srcs == None:
        srcs = _deliverable_srcs(ex)
        hdrs = _deliverable_hdrs(ex, hdrs)
    srcs = _zone(srcs)
    hdrs = _zone(hdrs or [])

    # What the grader brings is compiled in too, as every other build of the
    # student's code has it (the contract's `provided`).
    provided = _provided(num)
    hdrs = hdrs + [h for h in provided.hdrs if h not in hdrs]
    own_srcs = srcs
    srcs = srcs + provided.srcs
    harness_f = "tests/%s/%s" % (ex, harness)
    expected_f = "tests/%s/expected.txt" % ex

    args = [
        "--oracle",
        "$(location //oracle:oracle)",
        "--oracle-fn",
        oracle_fn,
        "--symbol",
        fn,
        "--harness",
        "$(location %s)" % harness_f,
        "--kind",
        kind,
        "--units",
        str(units),
        "--unit-name",
        unit_name,
        # No space, for the tokenising reason above; the fail() at the top of
        # this macro is what keeps that true when `fn` changes.
        "--label",
        "%s/%s" % (ex, fn),
        # Correctness gate. Derived from what c_function already built for this
        # exercise rather than re-declared, because a hand-written gate drifts
        # and a drifted gate skips forever while looking green.
        "--gate-differ",
        "$(location //tools:diff_output.sh)",
        "--gate-bin",
        "$(location :%s_bin)" % ex,
        "--gate-expected",
        "$(location %s)" % expected_f,
    ]
    for src in srcs:
        args += ["--src", "$(location %s)" % src]
    args += _inc_args("--inc", hdrs)

    _test(
        name = ex + "_refcost",
        srcs = ["//tools:ref_compare.sh"],
        args = _pinned_build_args() + args + _valgrind_args(tool = _VG_CALLGRIND, annotate = True),
        data = _valgrind_data(tool = _VG_CALLGRIND, annotate = True) + _PINNED_BUILD_DATA + [
            "//oracle:oracle",
            "//tools:diff_output.sh",
            harness_f,
            expected_f,
            ":%s_bin" % ex,
        ] + srcs + hdrs,
        # Two callgrind runs (student and reference) plus an -O2 compile of the
        # student's side. callgrind is ~90x slower than native, and the searches
        # themselves are tens of millions of instructions, so this is seconds —
        # but "medium" (300s) is what c_cycles uses for the same tool and there
        # is no reason to be tighter than the layer it shares a tag with.
        size = "medium",
        tags = ["cycles"],
        turnin = own_srcs,
        gated = True,
    )

def c_argv_table(num, scenarios = "scenarios.tsv", expected = "table.txt", clues = "clues.tsv", asan = True, name = None):
    """One labelled table for an argv program run against many invocations.

    Emits exNN_output (tag "output"), driven by //tools:argv_table.sh: the
    program is run once per row of tests/exNN/<scenarios> and every run becomes
    one row of a single "invocation -> output" PASS/FAIL table, rather than one
    opaque sh_test per invocation.

    Pairs with c_program(num, name) and no `cases`, which still builds
    :exNN_bin plus the norm/compile/forbidden layers.

    asan: replay the same scenarios against c_program's instrumented binary
      (tag "asan", so it runs from level `robust` up), and again, as
      exNN_argv_asan, against one whose argv the sanitizer can see the edges
      of. These exercises index and swap the pointers in argv, and an
      out-of-bounds read there returns bytes that are usually still the RIGHT
      bytes — so the table is structurally unable to see it. The plain replay
      sees an access the sanitizer watches (the program's own buffers, the
      heap); NOT one inside the argument strings or past argv's end, which the
      kernel lays out on the initial stack where ASan does not look -- a read
      past one argument's terminator reads the next one (finding 071). The
      guarded replay links the student's sources with main wrapped
      (-Wl,--wrap=main) and runs them under tools/argv_guard_main.c, which
      puts each argument in a heap
      block of exactly its size and argv in one of argc + 1 pointers, so
      those reads are heap-buffer-overflow reports.

    Also emits exNN_exit (tag "output", raised to level 3, robust): the same
    scenarios, judged only on how each run ended. The table fails a crash but
    only notes a plain non-zero return, because the subjects these programs
    come from name no exit status; by the rule in docs/reference.md ("Run
    contract") that return fails at robust, and this is where.

    Args:
        num: the exercise number as a two-digit string ("00"). It names the
            targets (exNN_output, exNN_asan) and locates tests/exNN/, but
            it also has to match a c_program(num = ...) call in the same
            package: the binaries it runs, :exNN_bin and (when asan)
            :exNN_bin_asan, are built there and this macro declares none of its
            own. Without that call it is a "no such target" analysis error, not
            a silent skip.
        scenarios: name of the scenario file under tests/exNN/, default
            "scenarios.tsv". One invocation per line, tab-separated:
            <label>[<TAB><arg>...]. A line with no tab runs the program with no
            arguments, an empty field is a real empty-string argument, and
            blank lines and #-comments are skipped. The label is what the
            table's CASE column shows, and it is also the name a clue group in
            `clues` lists when it should fire on that row rather than on any
            failure. These rows are the whole of this layer's coverage -- for
            c-06 ex01-ex03 this is the only layer that ever runs the program at
            all -- so a file that yields no invocation (empty, or nothing but
            comments) exits 2 as a harness error instead of reporting a pass on
            nothing. The file is a declared input, so naming one that does not
            exist is an analysis error rather than a skip.
        expected: name of the expected table under tests/exNN/, default
            "table.txt". One row per scenario, "<label><TAB><output>", where
            <output> is that run's stdout LINES joined with " | ". Generate it
            rather than typing it: running argv_table.sh --emit by hand prints
            exactly this stream from a trusted reference program, and refuses
            to if that program crashed, hung or flooded. Still required by the
            asan arm even though nothing is compared there -- its size is what
            sizes the runaway-output budget for each run.
        clues: name of the hints file under tests/exNN/, default "clues.tsv".
            There is no opt-out -- it is always passed and always declared as
            an input, so the file has to exist -- and diff_output.sh renders
            the fired hints under the table when a row fails, exactly as it
            does for every other layer. Only on the plain table: the sanitizer
            arm never invokes the reporter, so it renders no hints.
        asan: default True. Replays the same scenarios against c_program's
            instrumented binary (exNN_asan) and against the guarded-argv one
            (exNN_argv_asan, built here from what c_program's :exNN_bin_asan
            is built from -- its source list, or its Makefile, asked again
            -- so that c_program call must come first: argv_guard_problem), both
            tag "asan", so from level robust
            up. Both run with --memory-only: the verdict is survival, not
            bytes, since a wrong table is the output test's finding and
            reporting it twice for one unwritten function teaches nothing the
            second time. Each says on OK only what it could see.
        name: unused, for the reason c_levels gives: every macro takes one,
            and buildifier's unnamed-macro check holds this one to it since it
            declares a rule (the guarded-argv program, exNN_argvguard_bin_asan).
            Every target here is named from `num`.
    """
    _entry(num, "c_argv_table")  # first: a contract error names this macro
    ex = "ex" + num
    scen_f = "tests/%s/%s" % (ex, scenarios)
    exp_f = "tests/%s/%s" % (ex, expected)
    clues_f = "tests/%s/%s" % (ex, clues)

    def _table_test(name, binlabel, tag, memory_only = False, exit_only = False, level = None, guarded = False):
        t_args = [
            "--bin",
            "$(location %s)" % binlabel,
            "--scenarios",
            "$(location %s)" % scen_f,
            "--expected",
            "$(location %s)" % exp_f,
            "--clues",
            "$(location %s)" % clues_f,
            "--reporter",
            "$(location //tools:diff_output.sh)",
        ]
        if memory_only:
            t_args.append("--memory-only")
        if guarded:
            t_args.append("--guarded-argv")
        if exit_only:
            t_args.append("--exit-only")
        t_data = []
        if memory_only:
            t_args += _symbolizer_args()
            t_data = _SYMBOLIZER_DATA
        _test(
            name = name,
            srcs = ["//tools:argv_table.sh"],
            args = t_args,
            data = [
                binlabel,
                scen_f,
                exp_f,
                clues_f,
                "//tools:diff_output.sh",
            ] + t_data,
            tags = [tag],
            level = level,
        )

    _table_test(ex + "_output", ":%s_bin" % ex, "output")

    # The exit status, at robust: see the docstring and docs/reference.md.
    # Named exNN_exit, not exNN_exit_output: first_red reads an `output` tail
    # as "the next exercise to write", and this is rigour on a written one.
    _table_test(ex + "_exit", ":%s_bin" % ex, "output", exit_only = True, level = 3)
    if asan:
        # --memory-only: the instrumented replay judges memory, not bytes. A
        # wrong table is the output test's finding, and reporting it twice for
        # one unwritten function teaches nothing the second time.
        # exNN_asan, with no infix, because every other sanitizer arm in the
        # repo is spelled <stem>_asan and this was the one exception. A student
        # who learns `bazel test //mod:exNN_asan` on c-11 and tries it on c-06
        # got "no such target". The infix protected nothing: if an exercise ever
        # combined c_program(cases = ...) with c_argv_table, their two
        # exNN_output targets would already collide, so it is the output arm --
        # which never had an infix -- that decides compatibility.
        _table_test(
            ex + "_asan",
            ":%s_bin_asan" % ex,
            "asan",
            memory_only = True,
        )

        # THE GUARDED REPLAY (finding 071): the same scenarios, argv and each
        # argument in heap blocks of exactly their size (tools/
        # argv_guard_main.c), so a read past an argument's terminator or past
        # argv[argc] is a sanitizer report instead of the next argument's
        # bytes. Built from the very sources and headers c_program gave
        # :exNN_bin_asan, read off that rule rather than derived again: a
        # second derivation is one that can come to compile a different file
        # set from the program that is graded. A program built by its
        # Makefile is built the same way here: student_build.sh asks the
        # same Makefile (`make -Bn`) which sources its default goal
        # compiles, and links them with main wrapped.
        prog = native.existing_rule(ex + "_bin_asan")
        why = argv_guard_problem(prog)
        if why:
            fail("c_argv_table(num = \"%s\"): %s" % (num, why))
        guard_bin = ex + _ARGV_GUARD_SUFFIX
        from_prog = argv_guard_build(prog)
        _student_bin(
            name = guard_bin,
            harness = ["//tools:argv_guard_main.c"],
            hdrs = list(prog["hdrs"]),
            archive = False,
            dir = turnin_dir(num),
            asan = True,
            # The C runtime's call to main() reaches the guard's __wrap_main,
            # which calls the program's own as __real_main: their main()
            # keeps its name, and C's implicit return 0 with it.
            linkopts = ["-Wl,--wrap=main"],
            prototype = ("none: tools/argv_guard_main.c calls the program's own " +
                         "main(), whose signature is C's, not the subject's"),
            **from_prog
        )
        _table_test(
            ex + "_argv_asan",
            ":" + guard_bin,
            "asan",
            memory_only = True,
            guarded = True,
        )

# The name c_argv_table gives its guarded-argv program after "exNN": what
# corpus_memory reads a guarded replay from, and what the audit looks for.
_ARGV_GUARD_SUFFIX = "_argvguard_bin_asan"

def argv_guard_problem(prog):
    """Why c_argv_table cannot build its guarded-argv program; None if it can.

    The guarded replay compiles the program's own sources with main wrapped,
    beside tools/argv_guard_main.c, so it needs what the graded program is
    built from: c_program's :exNN_bin_asan, declared before this macro is
    called -- a list of files, which it reuses, or the Makefile, which it
    asks again (`make -Bn`, in student_build.sh). A Makefile build used to
    be refused here, which left a Makefile project with no guarded replay
    at all. A decision made while loading, so a function of its own that
    //tools/tests:starlark_unit calls both ways.

    Args:
      prog: native.existing_rule() of :exNN_bin_asan, or None.

    Returns:
      None, or the reason as a sentence.
    """
    if prog == None:
        return ("its asan arms run :exNN_bin_asan, which c_program(num = ...) " +
                "declares: call c_program first, above this call.")
    return None

def argv_guard_build(prog):
    """What c_argv_table's guarded-argv program is built from.

    _student_bin's keywords, read off c_program's :exNN_bin_asan: the
    program's own list of files, or its Makefile and the tree staged
    beside it -- never globbed a second time -- and with the Makefile, the
    sources that rule builds until the Makefile compiles anything
    (c_program's makefile = "once_written"). Those were left out, so over a
    stub Makefile the guarded program was an empty stand-in while the
    graded one ran the folder's sources (V35). A function of its own, which
    //tools/tests:starlark_unit calls on each shape.

    Args:
      prog: native.existing_rule() of :exNN_bin_asan (argv_guard_problem
        has said it is there).

    Returns:
      A dict of _student_bin's srcs, makefile and make_data.
    """
    srcs = list(prog.get("srcs") or [])
    if prog.get("makefile"):
        built = {
            "make_data": list(prog.get("make_data") or []),
            "makefile": prog["makefile"],
        }
    elif prog.get("missing_makefile"):
        built = {"makefile": prog["missing_makefile"]}
    else:
        return {"srcs": srcs}
    if srcs:
        built["srcs"] = srcs
    return built

def c_libft(
        num,
        test,
        artifact = "libft.a",
        symbols = None,
        script = None,
        hdrs = None,
        includes = None,
        expected = "expected.txt",
        clues = "clues.tsv",
        exports = None,
        prototype = True,
        labeled = False,
        make = None,
        name = None):
    """A libft bundle (c-09 ex00): an archive the student's own build produces.

    Several loose sources, built into an archive by a build system the student
    writes, PLUS the behaviour of those sources.

    c_make alone only proves the archive exists and exports the right symbols —
    it never runs the code. This macro adds the layers every other exercise
    shape already gets, so a libft cannot be greener than a c_function merely
    because of how it is packaged:

      exNN_build        the archive + its symbol table          (via c_make)
      exNN_norm         norminette over every loose source
      exNN_compile_*    both campus compilers, -Wall -Wextra -Werror
      exNN_output       the sources actually behave correctly
      exNN_forbidden    only the authorised functions are called
      exNN_prototype    every signature matches the subject's contract
      exNN_symbols      the archive exports exactly the subject's names

    The last two used to be missing, which made the docstring above false for
    the exercises with the STRONGEST claim on them: c-09's libft bundles are
    the ones whose sources are archived and linked against an evaluator's unseen
    main(), so a mistyped signature or a stray exported helper is exactly the
    collision that shape invites. c_make's --symbols is not a substitute — it
    greps nm for the PRESENCE of the required names and cannot see an EXTRA
    export, which is the half that actually collides.

    Naming matches every other shape on purpose (exNN_output, :exNN_bin, not
    exNN_func_test / :exNN_func_bin): the gates in c_perf — and anything later
    that keys off a functional layer — derive their targets by convention, and a
    module that spells its layers differently silently opts out of them.

    Args:
        num: exercise number as a string, "01" not 1. It names every target
            listed above (exNN_build, exNN_norm, exNN_output, ...), the
            :exNN_bin the correctness gates run, and the tests/exNN/ directory
            the fixtures are read from.
        THE SOURCES are the .c files the contract's `files` names -- the
            subject's own names, written where the layers read them, rather
            than a glob of the folder. They are compiled DIRECTLY together
            with `test` -- not taken out of the archive, which is exNN_build's
            business -- so the behaviour layers keep working while the
            student's build system does not.
        test: a main() under tests/exNN/ exercising all of `srcs`. exNN_output
            compiles it with them AT TEST TIME, through header_check.sh
            --shape libft, and diffs what it prints -- see the comment in the
            body for why that is not a prebuilt program. The same sources also
            build :exNN_bin, tagged manual, for the correctness gates:
            c_diff, c_perf and c_cycles reach for :exNN_bin without being told,
            so a shape that named it differently would opt out of them. The
            file name is yours (c-09 ex00 spells it test_libft.c).
        artifact: the file the build must have produced, default "libft.a".
            make_test.sh deletes it before building, so an archive left behind
            by running make by hand cannot report a green.
        symbols: the names the subject requires the archive to define. Two
            layers read this one list: exNN_build greps nm for their PRESENCE,
            and exNN_symbols -- through `exports`, which defaults to it --
            requires the sources to export these and nothing else. Default None
            drops both halves at once, which is rarely what you want. c-09
            names the five in a single constant so its two exercises cannot
            drift apart.
        script: build with `sh <name>` instead of `make`, for c-09 ex00 whose
            deliverable IS a shell script (libft_creator.sh). A bare file name,
            not a label. It also skips make_test.sh's rule work -- the
            clean/fclean/re checks and the incremental-build ones -- which have
            no meaning for a script.
        hdrs: headers turned in beside the sources. No caller passes one
            today: c-09 ex01's includes/ft.h was the one, and the grader
            supplies it now. Not merely staged: they are normed with the
            sources, compiled into the output layer's test program, and their
            directory joins the include path of the compile, forbidden,
            prototype and symbols layers, so a header that breaks the Norm or
            contradicts a signature is caught like any other deliverable -- and
            one that is still a stub is a red exNN_output, not a build error.
        includes: extra include directories, package-relative, put on the
            output layer's compile, :exNN_bin and the prototype layer, for
            sources that #include a header from a sibling directory.
        expected: the expected-output file under tests/exNN/, default
            "expected.txt", diffed against what the test program prints.
        clues: the exercise's hint file under tests/exNN/, default "clues.tsv",
            which diff_output.sh renders under the failure table. Unlike
            c_function's, it is NOT opt-in -- the flag is always passed, so the
            file must exist or the target will not analyse. c-09 ex00 has one;
            a new caller owes its students the same.
        THE FORBIDDEN LAYER'S LIST is the contract's `allowed`: the bundled
            functions are the same ones the earlier modules restrict, so the
            restriction carries over -- a printf in the archived copy used to
            be green locally and a KO on the Moulinette.
        exports: the exact set of global symbols the sources may define,
            defaulting to `symbols` so that the subject's required list doubles
            as the permitted one and a stray non-static helper is caught rather
            than tolerated. That is the half c_make cannot see: it greps nm for
            presence, while an EXTRA export is invisible to it and is precisely
            what collides when an evaluator links your archive against a main()
            you have never seen. Pass [] to skip the layer.
        prototype: require tests/exNN/prototype.h and check every definition in
            `srcs` against the signatures it declares. Pass False only to
            record a deliberate opt-out: the header's absence is otherwise an
            analysis-time failure, so that a missing contract cannot go
            unnoticed the way it did for c-12 and c-13.
        labeled: the expected file and the program's output are "CASE<TAB>VALUE"
            lines, and diff_output.sh shows the CASE in its own column instead
            of numbering the rows. Default False, which is what c-09 ex00's
            fixture is written for.
        make: c_make's other arguments, for the build of the archive, as a
            dict: {"quotes": ..., "recipe": "any", "recipe_strict": True}
            (c-09 ex00: the sentence about the script's compile commands,
            judged at strict). Every check c_make runs is reachable from
            here -- rules, graph, relink, foreign_object, wildcards and the
            rest -- and c_make holds them to its own rules (_make_problem):
            a Makefile-built library decides recipe and wildcards as every
            Makefile does. It once forwarded four arguments by name, so a
            library built by a Makefile could decline the wildcards check
            and never ask for it. num, artifact, symbols and script are this
            macro's own, and refused here (_libft_make_problem).
        name: unused, for the reason c_levels gives: every macro takes one,
            and buildifier's unnamed-macro check holds this one to it since it
            declares a rule (a program built from the student's files, see
            _student_bin). Every target here is named from `num`, so there is
            nothing for it to control.
    """
    _entry(num, "c_libft")  # first: a contract error names this macro
    ex = "ex" + num
    d = turnin_dir(num)

    # The subject's own names for them (the contract's `files`), and still
    # only what is there: see _zone().
    srcs = _zone([d + "/" + f for f in (_entry(num, "c_libft")["files"] or []) if f.endswith(".c")])
    hdrs = _zone(hdrs or [])
    includes = includes or []
    allowed = _allowed(num)

    # No graph = True here any more. It was passed for both c-09 calls because
    # ex01's subject is the one that says "your Makefile should not run any
    # unnecessary commands", "should not compile any file unnecessarily" and
    # ".o files should be near their corresponding .c files"; ex01 is a c_make
    # of its own now, and passes it there, where the subject that says so is.
    # The --script arm (ex00) never reaches those checks.
    problem = _libft_make_problem(make or {})
    if problem:
        fail(problem)
    c_make(
        num = num,
        artifact = artifact,
        symbols = symbols,
        script = script,
        **(make or {})
    )

    _norm_test(ex + "_norm", srcs + hdrs)
    _compile_tests(ex, srcs, hdrs)

    # THE OUTPUT LAYER COMPILES AT TEST TIME, not through a prebuilt program --
    # the same move, for the same reason, as c_header's (see its body).
    #
    # The harness main() reaches the bundled functions through whatever the
    # student turned in, and when c-09 ex01 was a bundle that included a
    # HEADER (the grader supplies it now; see that BUILD file). A header
    # still at its stub -- include guards and nothing else -- leaves every call
    # in the harness an implicit declaration, and under -Werror a cc_binary
    # built from it was a BUILD failure: `bazel test //...` on a fresh clone
    # stopped at "Build did NOT complete successfully" instead of showing one
    # red test. The template dodged that by shipping includes/ft.h filled in,
    # which handed every clone c-08 ex00's whole answer (its five prototypes)
    # under an approval in tools/stub_check.sh. Compiled inside
    # header_check.sh, the unwritten header is a red exNN_output carrying the
    # compiler's diagnostics and this exercise's clues, and the approval is
    # gone.
    #
    # :exNN_bin is still built from the same files, TAGGED MANUAL, because the
    # correctness gates find it by name: c-09 ex00's c_diff, c_perf and
    # c_cycles all run it before replaying their corpora. `manual` keeps it
    # out of `bazel build //...`, so it is compiled only when a gate asks for
    # it. Like every program built from a student's files it cannot fail the
    # build (see _student_bin): an unwritten header makes it a stand-in, which
    # fails the gate that runs it, and the gated layer skips.
    # Declared ahead of the fixture that links the functions, which names it.
    proto_test = _prototype_test(ex, srcs, hdrs, includes, prototype)

    binname = ex + "_bin"
    test_f = "tests/%s/%s" % (ex, test)
    _output_fixture_binary(
        name = binname,
        harness = [test_f],
        prototype = proto_test or "none: prototype = False at the call site, which says why",
        srcs = srcs,
        hdrs = hdrs,
        includes = includes,
        archive = False,
        dir = turnin_dir(num),
        tags = ["manual"],
    )

    expected_f = "tests/%s/%s" % (ex, expected)
    clues_f = "tests/%s/%s" % (ex, clues)
    args = _pinned_cc_args() + _pinned_ld_args() + [
        "--shape",
        "libft",
        "--differ",
        "$(location //tools:diff_output.sh)",
        "--main",
        "$(location %s)" % test_f,
        "--harness-src",
        "$(location %s)" % _UNBUFFERED_C,
        "--expected",
        "$(location %s)" % expected_f,
        "--clues",
        "$(location %s)" % clues_f,
    ]
    for s in srcs:
        args += ["--src", "$(location %s)" % s]
    args += _inc_args("--hdr", hdrs)

    # Package-relative on the way in, workspace-relative on the way out: the
    # runner starts in the runfiles root, where the package is a subdirectory.
    for d in includes:
        args += ["--inc", "%s/%s" % (native.package_name(), d)]
    if labeled:
        args.append("--labeled")
    w_args, w_data = _waiting_args(ex + "_output")
    _test(
        name = ex + "_output",
        srcs = ["//tools:header_check.sh"],
        args = args + w_args,
        data = _PINNED_CC_DATA + _PINNED_LD_DATA + [
            "//tools:diff_output.sh",
            _UNBUFFERED_C,
            test_f,
            expected_f,
            clues_f,
        ] + srcs + hdrs + w_data,
        tags = ["output"],
        turnin = srcs,
    )

    if allowed != None:
        _forbidden_test(ex + "_forbidden", srcs, allowed, hdrs = hdrs)

    # Export set, not merely presence. `symbols` is what c_make greps nm for and
    # is the subject's REQUIRED list; the same list is the permitted list here,
    # so an extra non-static helper is caught rather than tolerated.
    if exports == None:
        exports = symbols
    if exports:
        _symbols_test(ex + "_symbols", srcs, exports, hdrs = hdrs)

    # The 32-bit replay, which this shape went without for no reason anyone
    # decided: the layer was written inline in c_function, so a libft bundle --
    # which has the identical harness/sources/fixture shape the runner wants --
    # simply never reached it. c-09's five functions include ft_strlen and
    # ft_strcmp, both of which return values a wider `long` can hide.
    _ilp32_test(
        ex,
        test_f,
        expected_f,
        srcs,
        hdrs,
        includes,
        False,
        labeled,
        clues_f,
        ":" + binname,
    )

# c_make's arguments that c_libft's `make` may carry: every one but those
# c_libft passes itself. A new c_make argument is refused there until it is
# added here, which names this list.
_LIBFT_MAKE_KEYS = [
    "foreign_object",
    "graph",
    "not_checked",
    "quotes",
    "recipe",
    "recipe_strict",
    "relink",
    "relink_source",
    "rules",
    "wildcards",
]

def _libft_make_problem(make):
    """c_libft's message for a `make` dict it cannot hand to c_make; None if none."""
    if type(make) != "dict":
        return "c_libft(make = %r): c_make's arguments, as a dict" % (make,)
    for k in sorted(make):
        if k in ["num", "artifact", "symbols", "script"]:
            return (("c_libft(make = {%r: ...}): %s is c_libft's own argument, which it " +
                     "hands to c_make itself. Pass it to c_libft.") % (k, k))
        if k not in _LIBFT_MAKE_KEYS:
            return (("c_libft(make = {%r: ...}): no argument of c_make it may carry " +
                     "(%s; tools/defs.bzl's _LIBFT_MAKE_KEYS).") % (k, ", ".join(_LIBFT_MAKE_KEYS)))
    return None

def c_header(num, main, hdr = None, extra_srcs = None, cases = None, norm_flags = None, probe = None):
    """A header-only exercise (c-08): norm the .h, compile a main that uses it.

    Args:
        num: exercise number as a string, "00" not 0. Besides naming the
            targets and the tests/exNN/ directory, it is what
            _no_orphan_prototype() looks under: a tests/exNN/prototype.h beside
            a header exercise is an analysis-time failure, because this shape
            has no prototype layer that could read it -- the deliverable IS the
            declarations, so there is nothing for a contract header to check
            them against.
        hdr: the header the student turns in, as a file name in the turn-in
            directory. Default None takes the one .h the contract's `files`
            names, which is where it belongs; a name given here must be one of
            those. It is the entire deliverable: the only file the norm layer
            reads, the -I every test main compiles against, and (with `probe`)
            the header whose macros the forbidden layer expands.
        main: a test main() under tests/exNN/ that uses everything the subject
            says this header must declare. It is compiled AT TEST TIME by
            header_check.sh rather than built ahead of it, so that an unwritten
            header shows up as a red test carrying the compiler's diagnostics
            beside this exercise's table and clues -- the comment in the body
            says why. Every case that does not name a main of its own uses
            this one.
        extra_srcs: further .c files under tests/exNN/, compiled into each
            case's binary beside the main. Harness-side helpers, never
            deliverables -- the norm layer reads `hdr` and nothing else, so
            these are not normed. Nothing in the repo needs one today. Default
            None. They do join the compile layers, and their directories join
            the include path, like every other source these runners are handed.
        cases: the runs to emit, as a list of dicts. Default None means one
            case, {"name": "compile", "expected": "expected.txt", "args": []},
            which compiles `main` against the header and diffs what it prints.
            Every case is checked while loading (_case, _CASE_KEYS): a key
            this shape does not take fails naming the case. Its KIND is one
            of "expected" (a file under tests/exNN/ to diff against),
            "any_of" (two or more, the output being one of them) or
            "survive" (True: only that the program ends by itself), as for
            c_program's cases. Its other keys:
              "name"      the target infix, default "run". With a single case
                          the target is exNN_output; with several it is
                          exNN_<name>_output. See _case_stem() for why a lone
                          case does not get the infix.
              "main"      compile THIS main instead of the macro's, for a case
                          that uses the header a different way. Every distinct
                          main named here also joins the compile layers, so a
                          fixture cannot exercise a main that nothing checks.
              "args"      argv handed to the built program, e.g. ["x"].
              "labeled"   the output is "CASE<TAB>VALUE" lines and the CASE
                          gets its own column instead of a line number.
              "clues"     a hints file under tests/exNN/, shown below the
                          failure table and also after a COMPILE error, which
                          is the failure this shape actually produces most.
                          Deliberately per case rather than a default: making
                          it a default would turn a missing clues.tsv into an
                          analysis error for every future caller (see c-08
                          ex00's comment, which spells the whole case out).
              "level"     raise just this case above the output layer's level
                          1, for a case whose lesson is real but which this
                          subject does not actually demand -- so a beginner
                          does not meet it at `basic`. Upwards only;
                          _level_tags() fail()s on a level that does not raise.
                          c-08 ex01's "expr" case is the example, with its
                          reasoning at the call site.
              "exit"      also assert the built program exits with this code,
                          forwarded to header_check.sh's --exit. It exists
                          because this shape's only other verdict is what the
                          program PRINTED, and a header can define a constant
                          that a main RETURNS rather than prints -- invisible to
                          a stdout diff. 0 is a legitimate value here, so the
                          test is `!= None`, not truthiness. By the Run
                          contract (docs/reference.md), a status the subject
                          does not name is checked at robust at the lowest: a
                          case with "exit" and no "exit_quote" must carry
                          "level" 3 or 4, and its failure says the rule is
                          this repo's (fail()s at analysis otherwise).
              "exit_quote" the subject's sentence naming "exit". With no
                          "level" the case checks it at basic and words a
                          failure as the subject's rule; with "level": 2 the
                          sentence is only READ as naming the status, and a
                          failure is worded as that reading, checked at
                          strict. Either way the report quotes the sentence
                          (header_check.sh --exit-quote, forwarded to
                          diff_output.sh), as a c_program case's does. Any
                          other level with a quote fails at loading
                          (_case_problem): a status that is this repo's rule
                          quotes no sentence.
              "stdin"     a package-relative label fed to the program on
                          stdin, as in a c_program case.
            Any other key fails while loading (_CASE_KEYS), the ones only
            c_program reads -- "stream", "fixtures", "sanitize", "valgrind",
            "invalid_input" -- included: a c_program case dict copied across
            is refused, not half-read.
        norm_flags: extra tokens spliced in ahead of the file list when the
            norm layer runs, as separate list items because sh_test splits
            `args` on whitespace: ["-R", "CheckDefine"], not
            ["-R CheckDefine"]. Default None. The runner passes
            -R CheckForbiddenSourceHeader ahead of these, and norminette keeps
            only the LAST -R, so an -R here replaces that one. c-08 ex01 and
            ex02 need CheckDefine because their subject mandates it: those
            headers define function-like macros (EVEN, ABS), which the Norm
            otherwise refuses.
        probe: a tests/exNN/probe_*.c that expands this header's macro once and
            calls nothing else, which gives the `forbidden` layer an object
            file to inspect -- with the contract's allowlist, empty where the
            subject says "Allowed functions: None", as c-08's does for every
            exercise. A macro
            leaves no trace in a header until something expands it, so without
            a probe there is nothing for nm to read and the layer cannot exist;
            that is how a header whose ABS expands into a libc call could pass
            all thirteen of ex02's checks and still be a KO. Only for headers
            with a CALLABLE surface: ex00 is prototypes and ex03 a lone typedef,
            so neither can reach a libc function in the first place.
    """
    _entry(num, "c_header")  # first: a contract error names this macro
    ex = "ex" + num
    _no_orphan_prototype(ex, "c_header")
    extra_srcs = extra_srcs or []
    named = [f for f in (_entry(num, "c_header")["files"] or []) if f.endswith(".h")]
    if hdr == None:
        if len(named) != 1:
            fail(("c_header(num = \"%s\"): the contract's files name %d headers (%s); " +
                  "say which one is this exercise's with hdr = ...") % (num, len(named), ", ".join(named)))
        hdr = named[0]
    elif hdr not in named:
        fail(("c_header(num = \"%s\", hdr = %r): the contract's files do not name it " +
              "(%s). The turn-in is the subject's, written once in subject().") % (num, hdr, ", ".join(named)))
    hdr_f = "%s/%s" % (turnin_dir(num), hdr)

    # The header as a glob finds it: empty when it was not turned in, and then
    # every layer below is a "not turned in" test (see _test) instead of a
    # declared input Bazel fails to find while analysing the package.
    turnin = _zone([hdr_f])
    _norm_test(ex + "_norm", turnin, norm_flags = norm_flags)

    # c-08's subject says "Allowed functions: None" for every exercise here, so
    # the allowlist is empty and any undefined symbol at all is the finding. This
    # is the same _forbidden_test every other module gets, on the same runner,
    # reading the same nm output -- the probe is the only thing that differs,
    # because the deliverable is a header rather than a .c.
    # A subject with no "Allowed functions" line (allowed = None) gets no
    # forbidden layer, as in every other macro: one authorising nothing would
    # fail any call, a requirement the subject never wrote.
    if probe and _allowed(num) != None:
        probe_f = "tests/%s/%s" % (ex, probe)
        _forbidden_test(ex + "_forbidden", [probe_f], allowed = _allowed(num), hdrs = turnin, turnin = turnin)

    main_f = "tests/%s/%s" % (ex, main)
    extra_f = ["tests/%s/%s" % (ex, s) for s in extra_srcs]

    # Every case checked first (_case), before anything reads a key of one.
    if cases == None:
        cases = [{"name": "compile", "expected": "expected.txt", "args": []}]
    checked = [_case(c, "header", "c_header(num = \"%s\")" % num) for c in cases]

    # Every main any case drives has to compile, not just the default one.
    case_mains = []
    for c in cases:
        if c.get("main") and c["main"] != main:
            m = "tests/%s/%s" % (ex, c["main"])
            if m not in case_mains:
                case_mains.append(m)
    _compile_tests(ex, [main_f] + extra_f + case_mains, hdrs = turnin, turnin = turnin)

    # No program is built here: the header is compiled inside the runner. For
    # a header exercise the header IS the answer, so an unwritten one does not
    # compile -- and what the student has to read then is the compiler's
    # complaint about tests/exNN/test_*.c (a file they never wrote) beside this
    # exercise's table and hints, which header_check.sh prints and a build
    # stand-in (see _student_bin) would not.
    for c, k in zip(cases, checked):
        stem = _case_stem(ex, cases, k.name)
        compare, expected_fs = _expected_args(ex, k)
        case_main_f = "tests/%s/%s" % (ex, c["main"]) if c.get("main") else main_f
        args = _pinned_cc_args() + _pinned_ld_args() + [
            "--differ",
            "$(location //tools:diff_output.sh)",
            "--hdr",
            "$(location %s)" % hdr_f,
            "--main",
            "$(location %s)" % case_main_f,
            "--harness-src",
            "$(location %s)" % _UNBUFFERED_C,
        ] + compare
        data = _PINNED_CC_DATA + _PINNED_LD_DATA + [
            "//tools:diff_output.sh",
            _UNBUFFERED_C,
            hdr_f,
            case_main_f,
        ] + expected_fs + extra_f
        for s in extra_f:
            args += ["--src", "$(location %s)" % s]
        if c.get("labeled"):
            args.append("--labeled")
        if c.get("exit") != None:
            err = _header_exit_error(ex, c)
            if err:
                fail(err)
            args += _exit_flags(c, c["exit"])
        if c.get("stdin"):
            args += ["--stdin", "$(location %s)" % c["stdin"]]
            data.append(c["stdin"])
        if c.get("clues"):
            clues_f = "tests/%s/%s" % (ex, c["clues"])
            args += ["--clues", "$(location %s)" % clues_f]
            data.append(clues_f)
        args += ["--"] + c.get("args", [])
        _test(
            name = "%s_output" % stem,
            srcs = ["//tools:header_check.sh"],
            args = args,
            data = data,
            tags = ["output", _case_reads_tag(
                expected_fs + ([c["stdin"]] if c.get("stdin") else []),
            )],
            level = k.level,
            turnin = turnin,
        )

# The sentences c_make's `quotes` may hold: what each check applies (cc,
# print, unnecessary, objects, relink, wildcards) and what a rule does, where
# the subject says (all, clean, fclean, re). tools/make_test.sh --quotes reads
# the same keys.
_MAKE_QUOTE_KEYS = ["cc", "print", "unnecessary", "objects", "relink", "wildcards", "all", "clean", "fclean", "re"]

# THE NORM'S SENTENCES a c_make call quotes, written once: they are a fact of
# every project that binds the Norm, not of one subject, and a copy typed out
# at each call site is one more place a revision of the Norm has to reach
# (AGENTS.md §6, "declare a project's facts once"). The Norm, version 4.1,
# III.11 "Makefile", page 16. A BUILD file loads these and never spells
# them out (//tools:conventions refuses it).
NORM_NO_WILDCARDS = "The Norm, v4.1, III.11: \"All source files needed to compile your project must be explicitly named in your Makefile. Eg: no “*.c”, no “*.o” , etc ...\""
NORM_NO_RELINK = "The Norm, v4.1, III.11: \"If the makefile relinks when not necessary, the project will be considered non-functional.\""

# The name of the object c_make's `foreign_object` plants in a directory, the
# one make_test.sh --wildcards-only plants too.
_FOREIGN_OBJECT = "zz_graders_own_file.o"

def c_make(
        num,
        artifact,
        symbols = None,
        script = None,
        rules = None,
        graph = False,
        relink = False,
        relink_source = None,
        quotes = None,
        recipe = None,
        recipe_strict = False,
        foreign_object = None,
        wildcards = False,
        not_checked = None,
        clues = None,
        name = None):
    """A build-system exercise: run make/script, assert the artifact + symbols.

    Args:
        num: the exercise number as a two-character STRING, "00", "05". It
            names the target (exNN_build) and selects the contract entry, whose
            turn-in directory is where make runs: the Makefile (or the
            `script`) at its top is what the test builds, and the whole tree
            under it is the test's input.
        artifact: what the build must produce, as a bare filename -- "libft.a",
            "do-op". It is removed before the build, so a stale copy left by a
            hand-run of make cannot pass the test for the Makefile.
        symbols: global symbols the artifact must export, checked with nm.
            Default None, which checks none. An archive that builds and exports
            nothing the subject asked for is the failure this catches.
        script: a creator script to run instead of make, for a subject that
            asks for one (c-09 ex00's). Default None, meaning make.
        rules: which make rules THIS subject mandates, e.g. ["clean", "fclean"].
            Left unset, make_test.sh's own default of clean/fclean/re applies.

            PASS THE SUBJECT'S LIST, and read it from the subject rather than
            from a neighbouring module: `re` and `all` are the two that differ.
            Demanding a rule the subject never names reds a correct Makefile at
            level basic, which gates submit -- the same "do not invent a
            requirement" rule every c_files block follows.

            (This paragraph used to say the default "is what c-10 and c-09
            want". Neither was true: c-10 passes an explicit list without `re`,
            and c-09 had no c_make call of its own then. A docstring that keeps
            a census of its own callers is a docstring that goes stale -- state
            the rule, not the roll call.)

            Each mandated rule is checked from a start state of its own, and
            a rule the Makefile lacks fails in make's own words; see "THE RULE
            STEPS" in make_test.sh. Besides all, clean, fclean and re, a rule
            may be the artifact's own name -- C 09 ex01's "and of course
            libft.a", rush-02's "$NAME" -- and `make <artifact>` must then
            build it. Any other name fails here, at analysis, naming this
            call: a rule nobody checks would be listed as mandated and checked
            by nobody. The runner refuses one too, for a hand-run.

            A run that does its job and exits non-zero anyway -- a clean that
            errors on nothing to clean, an all that builds and then fails --
            is a WARNING in exNN_build, and a FAIL in exNN_build_exit, the
            robust twin this macro emits beside it (docs/reference.md, "Run
            contract"): no subject says how a rule exits.

            [] IS NOT None HERE. An empty list means "this subject mandates no
            rule at all", which c-piscine-bsq is: it asks only that the
            Makefile compiles the project and does not relink. None means "no
            opinion, take the default". Collapsing the two -- which `if rules:`
            did -- silently handed bsq clean/fclean/re and would have failed a
            conformant Makefile on three rules its subject never mentions.
        graph: run the incremental-build checks (no unnecessary work, .o
            placement). Default False. Only c-09 ex01's subject asks for those;
            see make_test.sh's gate comment.
        relink: run the no-unnecessary-work check ALONE, worded for a subject
            that says "must not relink" and says nothing about where objects
            land. Default False. graph implies it, so pass one or the other,
            never both.
        relink_source: where the no-relink rule comes from, for the failure
            message: None (the subject's own words -- BSQ) or "norm", for a
            project whose subject never says it and whose Makefiles fall
            under the Norm's (Piscine Reloaded). Either way the sentence is
            quotes["relink"]: for the Norm, NORM_NO_RELINK.
        quotes: {key: sentence}, the sentences of THIS project's subject (or
            of the Norm it binds) that the checks apply, each naming where
            it is from -- 'C 09, p.6: "..."' -- and quoted by the message of
            the check that fails, and by nothing else (finding 082: the
            runner used to quote C 09's definitions at every project). The
            keys are _MAKE_QUOTE_KEYS: cc, print, unnecessary, objects,
            relink and wildcards back a check this macro is asked for, and
            one asked for without its sentence fails here -- a requirement
            nobody can quote is one the layer would be inventing; all,
            clean, fclean and re are what the subject says those rules DO.
            What clean, fclean and re do is judged at basic where their
            sentences are here, and otherwise at robust, by exNN_build_rules,
            against this repo's convention, which it says is ours: a subject
            that lists "all, clean, fclean" and defines none of them (C 10)
            makes their effect a convention. That a listed rule exists is
            basic everywhere. Written to a file (exNN_make_quotes.txt), since
            sh_test tokenises `args` on blanks.
        recipe: None, "any" or "ordered": every command a bare `make` runs
            that compiles a .c file runs cc -- the command word, a path
            allowed -- with -Wall, -Wextra and -Werror, "ordered" in that
            order (C 09 ex01, "in that order"). Link and archive commands are
            not held to it: the sentences are about compiling. Needs the
            `cc` quote. For a creator script, what the script ran (sh -x).
        recipe_strict: False puts the recipe check in exNN_build, at basic,
            where the subject binds the build itself ("Your program must
            compile using cc with the following flags": BSQ, Rush 02; C 09
            ex01's own bullet). True emits it alone as exNN_build_recipe, at
            strict, where the sentence says what the grader does ("Moulinette
            compiles with the following flags: -Wall -Wextra -Werror, using
            cc": C 09 ex00's script, C 10, C 11 ex05, Reloaded) and reading
            it as binding the recipes is one reading.
        foreign_object: a directory of the turn-in ("srcs"), where the
            grader's own files sit, for a subject that says "Watch out for
            wildcards!" (C 09 ex01, Reloaded ex24). An object no rule made is
            put there before each cleaning rule, which must leave it; a
            clean that deletes by pattern does not (finding 105). At basic,
            in exNN_build. Needs the `wildcards` quote.
        wildcards: emit exNN_build_wildcards, at strict: the Norm's "no
            *.c, no *.o" for a Makefile whose subject binds the Norm and does
            not say it outright (C 10, C 11 ex05, BSQ, Rush 02, Reloaded
            ex27). A decoy source beside those the Makefile compiles, and an
            object no rule made beside its objects before each cleaning
            rule. Needs the `wildcards` quote, the Norm's sentence.
        not_checked: {check: why}, for a check this call leaves off, and the
            reason, naming what the subject says instead. `recipe` and
            `wildcards` are off unless asked for, and a check that is off by
            default is off by omission too: a Makefile project whose author
            never thought of its compile commands passed a gcc build at every
            level (finding 097). So each is decided at the call site, and a
            call that does neither is refused at load: `recipe` set, or
            "recipe" here, for every build; `wildcards = True`, or
            "wildcards" here, for a Makefile (a creator script has no
            pattern rules). The reason is for whoever reads the call next --
            a new project's author, a reviewer -- and nothing prints it.
        clues: a hint file under tests/exNN/ ("clues.tsv"), printed under
            any FAIL of every target this emits (make_test.sh --clues), or
            None. For an exercise that is a Makefile and nothing else (C 09
            ex01, Reloaded ex24), whose hints are about the Makefile: a
            program's clues.tsv is keyed to its cases, and its own layers
            print it. c_levels()' audit fails a module with a clue file no
            test prints, which is how these two were found dead.
        name: unused, for the reason c_levels gives: every macro takes one,
            and buildifier's unnamed-macro check holds this one to it since it
            declares a rule (the file of `quotes`, a names_file). Every target
            here is named from `num`, so there is nothing for it to control.

    WHAT THE GRADER BRINGS -- the contract's `provided` -- is staged beside the
    student's Makefile before the build, each copy where the contract says the
    grader puts it. That is for a turn-in that is a Makefile alone: c-09 ex01
    and Piscine Reloaded ex24 both say "We'll only fetch your Makefile and test
    it with our files". The harness's copies live under tests/exNN/grader/,
    placeholders that compile, never an exercise's answer. A turn-in holding
    anything at one of those destinations, or in the top directory of one
    (srcs/, includes/), fails the test: it is an extra file in what gets
    pushed.
    """
    _entry(num, "c_make")  # first: a contract error names this macro
    ex = "ex" + num
    symbols = symbols or []
    quotes = quotes or {}
    for r in rules or []:
        if r not in ["all", "clean", "fclean", "re", artifact]:
            fail(("c_make(num = \"%s\"): rules names \"%s\", which make_test.sh has " +
                  "no check for. It checks all, clean, fclean, re and the " +
                  "artifact's own rule (\"%s\").") % (num, r, artifact))
    problem = _make_problem(num, quotes, script, graph, relink, relink_source, recipe, recipe_strict, foreign_object, wildcards, not_checked)
    if problem:
        fail(problem)
    problem = _make_anchor_problem(num, script or "Makefile", _entry(num, "c_make"))
    if problem:
        fail(problem)

    # The two targets' names, for the runner's messages that send a student
    # from one to the other. The macro names them, so the macro says them.
    build = ex + "_build"
    d = turnin_dir(num)
    anchor = d + "/" + (script or "Makefile")
    args = _pinned_nm_args() + [
        "--make",
        "$(location %s)" % _MAKE,
        "--anchor",
        "$(location %s)" % anchor,
        "--artifact",
        artifact,
        "--build-target",
        build,
    ]
    if script:
        args += ["--script", script]
    if symbols:
        args += ["--symbols", ",".join(symbols)]
    if rules != None:
        # "-" rather than "" for the empty set: sh_test tokenises `args` on
        # whitespace, so an empty string is not reliably a separate argv
        # element, and a flag whose value silently vanishes takes the NEXT
        # argument as its value. make_test.sh maps "-" back to "no rules".
        args += ["--rules", ",".join(rules) if rules else "-"]
    if graph:
        args.append("--graph")
    elif relink:
        args.append("--relink")
    if relink_source:
        args += ["--relink-source", relink_source]
    quote_data = []
    if quotes:
        names_file(
            name = ex + "_make_quotes",
            names = ["%s\t%s" % (k, quotes[k]) for k in sorted(quotes)],
        )
        args += ["--quotes", "$(location :%s_make_quotes)" % ex]
        quote_data = [":%s_make_quotes" % ex]
    if recipe:
        args += ["--recipe-cc", recipe]
    if foreign_object:
        args += ["--foreign-object", foreign_object + "/" + _FOREIGN_OBJECT]
    clue_data = []
    if clues:
        clue_f = "tests/%s/%s" % (ex, clues)
        args += ["--clues", "$(location %s)" % clue_f]
        clue_data = [clue_f]
    overlay = _provided(num).overlay
    for src in sorted(overlay.keys()):
        args += ["--overlay", "$(location %s)" % src, overlay[src]]
    # Build PRODUCTS are excluded so this test's inputs cannot include what
    # the test is supposed to produce. Running make (or the creator script)
    # by hand leaves libft.a and *.o in deliverable/; .gitignore keeps them
    # out of git but not out of native.glob, and a test whose result depends
    # on untracked files is not a test. make_test.sh also rm -f's the
    # artifact before building, which closes the same hole from the other
    # side.
    data = turnin_glob(
        [d + "/**"],
        exclude = _not_build_products(d),
    ) + _PINNED_NM_DATA + [_MAKE] + sorted(overlay.keys()) + quote_data + clue_data
    _test(
        name = build,
        srcs = ["//tools:make_test.sh"],
        # A strict recipe check is exNN_build_recipe's, not this one's.
        args = _drop_flag(args, "--recipe-cc") if recipe_strict else args,
        data = data,
        size = "small",
        tags = ["output"],
        # The anchor as a glob finds it: no Makefile (or creator script)
        # there makes this a "not turned in" test, not an analysis error on
        # a $(location) of a file nobody staged.
        turnin = _zone([anchor]),
    )

    # The exit status of every run above, at robust (docs/reference.md, "Run
    # contract"): the same build and rule steps, judged only by how each run
    # ended. Named exNN_build_exit, not ..._exit_output: first_red reads an
    # `output` tail as the next exercise to write, and this is rigour on a
    # written one.
    _test(
        name = build + "_exit",
        srcs = ["//tools:make_test.sh"],
        args = args + ["--exit-only"],
        data = data,
        size = "small",
        tags = ["output"],
        level = 3,
        # No Makefile: exNN_build already says so at basic, and this twin has
        # no run to judge, so it stands down as a gated layer does.
        turnin = _zone([anchor]),
        gated = True,
    )

    # What clean, fclean and re DO, where the subject lists a rule and does
    # not say: this repo's convention, at robust (see `quotes`). Emitted only
    # where one rests on it, so no module carries a target that has nothing
    # to judge.
    listed = ["clean", "fclean", "re"] if rules == None else rules
    needs = {"clean": ["clean"], "fclean": ["fclean", "clean"], "re": ["re", "fclean", "clean"]}
    if not script and [r for r in needs if r in listed and [k for k in needs[r] if k not in quotes]]:
        _test(
            name = build + "_rules",
            srcs = ["//tools:make_test.sh"],
            args = args + ["--rules-only"],
            data = data,
            size = "small",
            tags = ["output"],
            level = 3,
            turnin = _zone([anchor]),
            gated = True,
        )

    # The compile commands, alone, where the sentence about cc is a reading
    # of what binds the build (strict; see `recipe_strict`).
    if recipe and recipe_strict:
        _test(
            name = build + "_recipe",
            srcs = ["//tools:make_test.sh"],
            args = args + ["--recipe-only"],
            data = data,
            size = "small",
            tags = ["output"],
            level = 2,
            turnin = _zone([anchor]),
            gated = True,
        )

    # The Norm's "no *.c, no *.o", at strict (see `wildcards`).
    if wildcards:
        _test(
            name = build + "_wildcards",
            srcs = ["//tools:make_test.sh"],
            args = args + ["--wildcards-only"],
            data = data,
            size = "small",
            tags = ["output"],
            level = 2,
            turnin = _zone([anchor]),
            gated = True,
        )

def _drop_flag(args, flag):
    """`args` without `flag` and the value after it."""
    out = []
    skip = False
    for a in args:
        if skip:
            skip = False
            continue
        if a == flag:
            skip = True
            continue
        out.append(a)
    return out

def _make_anchor_problem(num, anchor, e, macro = "c_make"):
    """The message when a macro builds from a file the contract does not require; None if it does.

    exNN_build runs at basic and is red without its Makefile (or creator
    script), so the subject that c_make reads as asking for one asks for it
    as a turn-in file, and the contract must say so in `files`. C 11 ex05's
    contract once left its Makefile out: the files layer then warned of an
    unrequested file beside the very build that required it, and on a strict
    project it would have failed a correct turn-in at basic (finding 124).
    Its contract was fixed by hand, which fixes nothing for the next
    project; this holds every c_make to it while loading. Only `files`: a
    file in `optional` is one the turn-in may leave out, which no basic test
    may then require.

    c_program(makefile = True) builds its program from the same Makefile,
    and every output test it declares, at basic, runs that program: the
    same class, by the other macro that builds from a Makefile. And the
    audit asks for a c_make only where the contract's `files` hold a
    Makefile (_levels_audit's `makefiles`), so a contract that left it out
    released the project from that too.

    A value before it is a fail() (c_make) or a refusal (c_program), so the
    macro fixtures can feed it the broken entries
    (contract_problem("make_anchor", ...), and c_program's `refusals`).

    Args:
        num: the exercise, for the message.
        anchor: what the macro builds from: "Makefile", or c_make's `script`.
        e: the exercise's contract entry.
        macro: "c_make", or "c_program" (makefile = True).

    Returns:
        The message, or None.
    """
    if anchor in (e["files"] or []):
        return None
    where = "%s(num = \"%s\")" % (macro, num)
    if macro == "c_make":
        needs = "exNN_build, at basic, fails without it"
        drop = "drop the c_make"
    else:
        needs = "with makefile = True, every output test, at basic, runs the program it builds"
        drop = "build the program from its sources (makefile = False)"
    if anchor in e["optional"]:
        return (("%s: the contract lists %s in `optional`, and %s: a file a basic test " +
                 "requires is one the turn-in must hold. Move it to the exercise's " +
                 "`files`.") % (where, anchor, needs))
    if anchor in e["provided"].values():
        return (("%s: the contract says the grader brings %s (`provided`), and %s " +
                 "builds the student's own. Name the student's in `files`, or %s.") %
                (where, anchor, macro, drop))
    return (("%s: %s builds from %s, and the subject() contract does not ask for it " +
             "(files: %s; optional: %s). The files layer would call it a file nobody " +
             "asked for, beside the build that requires it (finding 124). Transcribe the " +
             "subject's turn-in line: %s goes in the exercise's `files`.") %
            (where, macro, anchor, e["files"], e["optional"], anchor))

def _make_problem(num, quotes, script = None, graph = False, relink = False, relink_source = None, recipe = None, recipe_strict = False, foreign_object = None, wildcards = False, not_checked = None):
    """What is wrong with a c_make call's quotes and the checks they back, or None.

    Every check that says what a subject requires quotes the sentence that
    requires it, at the call site (docs/design.md, "Do not let a layer invent
    a requirement"), so a check asked for without its sentence is a mistake
    of the call site's, and so is a sentence under a key nothing reads. A
    value before it is a fail(), so the macro fixtures can feed it every
    broken call (contract_problem("make", ...)).

    Args:
        num: the exercise, for the message.
        quotes: as c_make takes it.
        script: as c_make takes it.
        graph: as c_make takes it.
        relink: as c_make takes it.
        relink_source: as c_make takes it.
        recipe: as c_make takes it.
        recipe_strict: as c_make takes it.
        foreign_object: as c_make takes it.
        wildcards: as c_make takes it.
        not_checked: as c_make takes it.

    Returns:
        The message, or None.
    """
    where = "c_make(num = \"%s\")" % num
    if type(quotes) != "dict":
        return "%s: quotes is a dict {key: sentence}, not %r" % (where, quotes)
    for k in sorted(quotes):
        if k not in _MAKE_QUOTE_KEYS:
            return "%s: quotes has \"%s\", which no check reads. The keys are %s." % (where, k, ", ".join(_MAKE_QUOTE_KEYS))
        v = quotes[k]
        if type(v) != "string" or not v.strip():
            return "%s: quotes[\"%s\"] is the subject's sentence, as a non-empty string." % (where, k)
        if "\n" in v or "\t" in v:
            return "%s: quotes[\"%s\"] holds a newline or a tab: it is one line of a file." % (where, k)
    if recipe not in [None, "any", "ordered"]:
        return "%s: recipe is None, \"any\" or \"ordered\", not %r" % (where, recipe)
    if recipe_strict and not recipe:
        return "%s: recipe_strict says where the recipe check goes, and there is no recipe." % where
    if script and (graph or relink or foreign_object or wildcards):
        return "%s: a creator script has no rules and no objects to judge; graph, relink, foreign_object and wildcards are for a Makefile." % where
    if foreign_object != None and (not foreign_object or foreign_object.startswith("/") or ".." in foreign_object.split("/") or foreign_object.endswith("/")):
        return "%s: foreign_object is a directory of the turn-in, like \"srcs\", not %r" % (where, foreign_object)
    need = []
    if graph:
        need += [("graph", k) for k in ["print", "unnecessary", "objects"]]
    if recipe:
        need.append(("recipe", "cc"))
    if foreign_object:
        need.append(("foreign_object", "wildcards"))
    if wildcards:
        need.append(("wildcards", "wildcards"))
    if relink_source not in [None, "norm"]:
        return "%s: relink_source is None (the subject's words) or \"norm\", not %r" % (where, relink_source)
    if relink_source and not relink and not graph:
        return "%s: relink_source says whose the no-relink rule is, and relink is not asked for." % where

    # The Norm's sentence is quoted like a subject's (NORM_NO_RELINK): the
    # runner used to carry its own copy for relink_source = "norm".
    if relink and not graph:
        need.append(("relink", "relink"))
    for flag, k in need:
        if k not in quotes:
            return ("%s: %s checks what a subject's sentence requires, and quotes has no " +
                    "\"%s\". Quote it -- or drop the check: a requirement nobody can " +
                    "quote is one the layer would be inventing.") % (where, flag, k)

    # THE CHECKS THAT ARE OFF UNLESS ASKED FOR are decided, one way or the
    # other, at the call site: on, or off with the reason (see not_checked).
    not_checked = {} if not_checked == None else not_checked
    if type(not_checked) != "dict":
        return "%s: not_checked is a dict {check: why}, not %r" % (where, not_checked)
    on = {"recipe": recipe != None, "wildcards": wildcards}
    for k in sorted(not_checked):
        if k not in on:
            return "%s: not_checked has \"%s\", which is no check that is off by default. They are %s." % (where, k, ", ".join(sorted(on)))
        v = not_checked[k]
        if type(v) != "string" or not v.strip():
            return "%s: not_checked[\"%s\"] is why the check is off, as a non-empty string." % (where, k)
        if on[k]:
            return "%s: not_checked says why %s is off, and %s is asked for." % (where, k, k)
    if recipe == None and "recipe" not in not_checked:
        return ("%s: recipe is not decided. Set it (\"any\", or \"ordered\"), with the " +
                "subject's sentence about how the build compiles quoted under \"cc\" -- or " +
                "say why not, in not_checked = {\"recipe\": \"...\"}. Left unset, a build that " +
                "compiles with gcc, or without -Werror, is green at every level.") % where
    if not script and not wildcards and "wildcards" not in not_checked:
        return ("%s: wildcards is not decided. Pass wildcards = True, with the Norm's " +
                "\"no *.c, no *.o\" quoted under \"wildcards\", where the subject binds the " +
                "Norm -- or say why not, in not_checked = {\"wildcards\": \"...\"}.") % where
    return None

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

def diff_asan_count_problem(num, count, asan_count, sanitize):
    """What is wrong with how a c_diff call sizes its ASan twin.

    The twin (exNN_diff_asan) replays the first `asan_count` cases of the
    corpus the plain replay (exNN_diff) value-checks `count` of. A twin that
    replays more than `count` checks cases for memory whose values nobody
    compares (V34: seven calls lowered `count` and left the twin at its
    default). The owner's rule (2026-10-04): the twin replays at most the plain
    replay's cases, so a call that lowers `count` below the default
    `asan_count` says so, by raising `count` back or by naming an
    `asan_count` no larger.

    Public so //tools/tests:starlark_unit can check it at load time.

    Args:
      num: the exercise's number, for the message.
      count: the plain replay's cases.
      asan_count: the twin's cases.
      sanitize: whether the call emits the twin at all.

    Returns:
      The message to fail with, or "" when the call is sound.
    """
    if sanitize and asan_count > count:
        return (("c_diff(num = \"%s\"): its ASan twin would replay %d cases of a corpus " +
                 "whose plain replay value-checks %d, so %d cases would be checked for " +
                 "memory and never for their value. Raise count to at least %d, or name " +
                 "asan_count = %d or fewer.") % (num, asan_count, count, asan_count - count,
                                                  asan_count, count))
    return ""


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
        puts the answer in a file the template ships.
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
        word: Shell 00 ex02, ex06, ex08), `regular` ("files" read as
        regular files only: Shell 00 ex08, Shell 01 ex02, where a directory
        can carry a matching name) and `newest_first` (an order by date
        that names no direction, read as `ls` sorts by time: Shell 00 ex04). A reading's name ends its target's, so
        it is a suffix in _SUFFIX_LAYER, at strict, with its row in
        docs/reference.md ("Target names"): c_levels()' audit fails a
        package whose target ends in none. Reuse one before adding one.

        Named exNN_literal, not exNN_literal_output, although it carries the
        output tag: //tools:first_red reads a target's layer from the END of
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
                    shell, and /bin/sh where it names none or names sh. Its
                    check asks for the execute bit (ck_executable), and
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
    ex = "ex" + num
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

# ---------------------------------------------------------------- rush (group project)
#
# The Rush is shaped unlike the other modules, so it gets its own macros
# instead of bending c_function:
#
#   * one exercise, three files owed and up to seven present: main.c,
#     ft_putchar.c and one of rush00.c..rush04.c, plus any bonus variants. The
#     rush files each define the SAME `rush` symbol — five different drawings
#     of the same rectangle — so they can never share a library or a binary.
#     Every layer is emitted once PER VARIANT, with a variant-qualified target
#     prefix (ex00_rush03_output, …).
#   * a team owes exactly ONE variant (team leader's initial mod 5); the other
#     four are bonus. The team names it in the package's team.bzl (ASSIGNED),
#     which rush_owed() turns into the files the files layer requires. Tests
#     for a variant outside ASSIGNED are tagged "manual", which keeps them out
#     of `bazel test //...` AND out of the submit gate's
#     `bazel test //MOD/... --test_tag_filters=-manual`, so unimplemented stubs
#     cannot block a push, and a variant outside it whose file was deleted gets
#     no targets at all. Run a bonus one with its per-variant suite:
#     `bazel test //c-piscine/c-piscine-rush-00:ex00_rush03`.
#   * main.c belongs to the student and is REPLACED at the defense, so nothing
#     diffs its output: the harnesses call rush() themselves, and main.c only
#     has to compile, link with the other two files, run and print something.

# The five interchangeable drawings the subject defines (chapters V..IX).
_RUSH_VARIANTS = ["00", "01", "02", "03", "04"]

def rush_owed(assigned):
    """The rush0N.c files a team owes, one per variant in its team.bzl.

    The subject's turn-in line is "main.c, ft_putchar.c, rush0X.c", with 0X the
    team's variant. This supplies the rush0X.c part for c_files' `required`, so
    the files layer asks for what THIS team owes rather than for all five: a
    list written for a team that did every variant failed, at basic and so at
    the submit gate, the three-file turn-in the subject asks for.

    The list is checked here, because nothing downstream would notice a wrong
    one: an entry that is not a variant would gate nothing and require a file
    no variant builds, and an empty list would gate no variant at all while
    the module still reported green. Each of those fail()s at analysis time,
    naming team.bzl.

    Args:
        assigned: the ASSIGNED list from the package's team.bzl -- the
            variants the team owes, each a two-character string "00".."04".
            Usually one; a team that finished bonus variants and wants them
            gated lists those too.

    Returns:
        The file names, in the order given: ["rush03.c"] for ["03"].
    """
    where = "%s/team.bzl" % native.package_name()
    if not assigned:
        fail("%s: ASSIGNED is empty. List the variant your team owes, e.g. [\"03\"]." % where)
    seen = []
    for v in assigned:
        if v not in _RUSH_VARIANTS:
            fail("%s: ASSIGNED holds %r, which is not a variant. Use two-character strings from %s." % (where, v, _RUSH_VARIANTS))
        if v in seen:
            fail("%s: ASSIGNED lists %r twice." % (where, v))
        seen.append(v)
    return ["rush%s.c" % v for v in assigned]

def _rush_variant_hdrs(ex, variant = None):
    """Deliverable headers owned by one variant (rush0N.h), or by all of them.

    Enumerated rather than globbed with a character class: Bazel's glob knows
    only `*` and `**`, so "rush0[0-4].h" silently matches nothing."""
    variants = [variant] if variant else _RUSH_VARIANTS
    return turnin_glob(["%s/rush%s.h" % (turnin_dir(ex[2:]), v) for v in variants])

def rush_common(num = "00", clues = "clues_putchar.tsv", name = None):
    """The rush layers that do not depend on which variant is implemented.

    Emits: norm + both-compiler compile for main.c and ft_putchar.c, and
    ft_putchar's own output/forbidden tests — linked against ft_putchar.c ALONE,
    which is also how "the ft_putchar.c file must contain the ft_putchar

    Args:
        num: the exercise number as a two-digit string; defaults to "00", which
            is the whole story here -- the Rush is one exercise, however many
            variants a team turns in. It selects deliverable/exNN and
            tests/exNN and prefixes everything it emits (exNN_shared_norm,
            exNN_shared_compile_clang/gcc, exNN_putchar_forbidden,
            exNN_putchar_symbols, exNN_putchar_bin, exNN_putchar_output), and
            it has to be the num rush_variant() is given, since the two macros
            read the same directories.

            The unit it declares, :ft_putchar, is NOT prefixed, because
            rush_variant() links it by that exact name. So rush_common()
            belongs in the package exactly once -- a
            second call is a duplicate-target error whatever `num` says, since
            nothing here checks for it -- and a package with rush_variant() and
            no rush_common() does not analyse.

            Everything else it reads is fixed rather than parameterised:
            deliverable/exNN/main.c and ft_putchar.c, any *.h beside them,
            and tests/exNN/test_putchar.c with tests/exNN/putchar.txt. The
            headers are split by name: rush0N.h belongs to that variant and is
            normed by the variant's own (manual) test, so only the SHARED ones
            are normed here, while all of them are staged for the libraries and
            for the compile, forbidden and symbols layers.
        clues: name of the hints file for exNN_putchar_output under tests/exNN/,
            default "clues_putchar.tsv". Deliberately a different file from the
            variants' clues.tsv, and not merely a copy: this test links
            ft_putchar.c ALONE and its table is unlabeled, so a clue group with
            no member labels fires on any failure at all, and what it has to
            talk about is putting one byte on the screen -- not the rectangle
            the variants draw. Required: it is declared as an input, so a
            missing file is an analysis error rather than a hintless test.
        name: unused, for the reason c_levels gives: every macro takes one,
            and buildifier's unnamed-macro check holds this one to it since it
            declares a rule (a program built from the student's files, see
            _student_bin). Every target here is named from `num`, so there is
            nothing for it to control.
    function" gets checked."""
    _entry(num, "rush_common")  # first: a contract error names this macro
    ex = "ex" + num

    # The harness files are visible to //tools/tests, whose selftest builds
    # survive_rush.c and test_defense.c over bodies of its own: every tree the
    # suite runs passes both, so only there can either be shown to go red.
    native.exports_files(
        native.glob(["tests/%s/**" % ex], allow_empty = True),
        visibility = ["//tools/tests:__pkg__"],
    )

    # The two files every variant shares, each as a glob finds it (_zone): a
    # team that has not pushed one yet gets red tests naming it, never a
    # package Bazel cannot analyse.
    main_c = _zone([turnin_dir(num) + "/main.c"])
    putchar_c = _zone([turnin_dir(num) + "/ft_putchar.c"])
    inc = [turnin_dir(num)]

    # The Norm bans declaring a struct/typedef in a .c file, so a team that wants
    # one has to put it in a header next to the sources. Nothing in the subject's
    # file list mentions a header, so none may exist — hence the glob. A header
    # named after a variant (rush03.h) belongs to that variant's layers; anything
    # else is shared. Headers are never "compiled": they are declared so Bazel
    # stages them, and normed, because the Norm checks bonus files too.
    variant_hdrs = _rush_variant_hdrs(ex)
    shared_hdrs = [
        h
        for h in _turnin_files(num, ".h")
        if h not in variant_hdrs
    ]
    all_hdrs = shared_hdrs + variant_hdrs

    # The unit every variant links for ft_putchar. It builds nothing; each
    # program compiles it with its own flags (see _student_lib).
    _student_lib(
        name = "ft_putchar",
        srcs = putchar_c,
        hdrs = all_hdrs,
        includes = inc,
    )

    # Only the SHARED headers are normed here: a header belonging to a bonus
    # variant is normed by that variant's (manual) norm test, so a half-written
    # rush03.h cannot fail a gated test.
    _norm_test(ex + "_shared_norm", main_c + putchar_c + shared_hdrs)

    # Every other .c the team turned in: a bonus of its own shape (the
    # subject's "single binary accepting a command line argument to switch
    # from one version to another" needs files no variant names), which the
    # contract allows, and "If you have bonus files/functions, they are
    # included in the norm check" -- at basic, like the variants' own. Only
    # emitted when there is one: an empty list would be a "not turned in" test
    # for files nobody owes.
    known = ["main.c", "ft_putchar.c"] + ["rush%s.c" % v for v in _RUSH_VARIANTS]
    extra_c = [f for f in _turnin_files(num, ".c") if f.split("/")[-1] not in known]
    if extra_c:
        _norm_test(ex + "_extra_norm", extra_c)
    _compile_tests(ex + "_shared", main_c + putchar_c, hdrs = all_hdrs)
    # None (no "Allowed functions" line): no forbidden layer, as in every
    # other macro -- not one that authorises nothing.
    if _allowed(num) != None:
        _forbidden_test(ex + "_putchar_forbidden", putchar_c, _allowed(num), hdrs = all_hdrs)

    # ft_putchar.c is linked against a main() the team does not control at the
    # defense, so it may export ft_putchar and nothing else.
    _symbols_test(ex + "_putchar_symbols", putchar_c, ["ft_putchar"], hdrs = all_hdrs)

    binname = ex + "_putchar_bin"
    _output_fixture_binary(
        name = binname,
        harness = ["tests/%s/test_putchar.c" % ex],
        prototype = ("none: the subject fixes no prototype for ft_putchar, only " +
                     "that \"the ft_putchar.c file must contain the ft_putchar function\""),
        deps = [":ft_putchar"],
        dir = turnin_dir(num),
    )
    expected_f = "tests/%s/putchar.txt" % ex
    clues_f = "tests/%s/%s" % (ex, clues)
    _test(
        name = ex + "_putchar_output",
        srcs = ["//tools:diff_output.sh"],
        args = [
            "--bin",
            "$(location :%s)" % binname,
            "--harness-fixture",
            "--expected",
            "$(location %s)" % expected_f,
            "--clues",
            "$(location %s)" % clues_f,
        ],
        data = [":" + binname, expected_f, clues_f],
        # What the case reads, for c_levels()' audit (_CASE_READS_TAG): Rush
        # 00's putchar.txt is written by the reference (rush00_fixtures).
        tags = ["output", _case_reads_tag([expected_f])],
    )

def rush_variant(
        variant,
        name = None,
        num = "00",
        gated = True,
        exports = None,
        seed = 1,
        # rush draws a whole rectangle per case through ft_putchar, i.e. one
        # write() per character — syscall-bound like the c-00/c-04 putnbr
        # family, and measured at 34s of a 60s budget at 4200.
        count = 2000,
        asan_count = 1500,
        clues = "clues.tsv",
        diff_clues = "diff_clues.txt"):
    """Every test layer for ONE rush variant ("00".."04").

    Layers, in the order a student meets them:
      <p>_norm            norminette on rush0N.c
      <p>_norm_notice     its Notices, the reading no subject settles (strict)
      <p>_compile_clang/gcc   both campus compilers, -Wall -Wextra -Werror
      <p>_forbidden       only write() (plus the exercise's own functions)
      <p>_prototype       void rush(int x, int y), the types (tests/ex00/prototype.h)
      <p>_prototype_names ... and the names x and y the subject gives them (strict)
      <p>_output          the curated, labelled table (tests/ex00/cases.tsv)
      <p>_defense         the subject's defense case, rush(123, 42), in full
      <p>_survive         degenerate sizes: survival; counter ceilings: survival
                          and, once rush(3, 3) draws anything, the rectangle's
                          shape (tests/ex00/survive_rush.c)
      <p>_main            the student's own main.c links, runs and prints
      <p>_main_exit       ... and returns 0 (robust: the subject names no status)
      <p>_valgrind        uninitialised bytes handed to write()
      <p>_asan            out-of-bounds writes into a fixed internal buffer
      <p>_diff            thousands of sizes against the Rust reference
      <p>_diff_asan       the degenerate corpus replayed under ASan/UBSan
    where <p> is e.g. ex00_rush03.

    Args:
        variant: which drawing, "00".."04". It selects deliverable/exNN/rushV.c,
            the reference function rush_vN, and the target prefix.
        name: unused. Bazel convention is that every macro takes a `name`, and
            buildifier's unnamed-macro check enforces it; every target this
            emits is named from `variant` and `num`, so there is nothing for a
            caller to control.
        num: the exercise number as a two-character STRING; "00" everywhere,
            since a rush has one exercise.
        gated: default True. False tags every emitted test "manual" but the
            Norm pair, which is how the four variants a team does NOT owe stay
            out of `bazel test //...` and out of the submit gate -- see the
            block comment above rush_common. A team owes exactly one variant;
            failing them on four unwritten bonuses would be a gate that blocks
            a push over work nobody asked for. The Norm is the exception
            because the subject makes it one: bonus files "are included in the
            norm check, and you will receive a score of 0 if there is a norm
            error". So a rushV.c that is there is normed at basic, gated or
            not, and an untouched stub passes it. False with no rushV.c in the
            directory emits nothing at all: the subject asks for one rush0X.c,
            so a team deletes the stubs it does not owe, and a bonus variant
            nobody wrote has nothing to say even when asked for by name. A
            GATED variant
            with no file still emits, because team.bzl says that file is owed:
            its layers are "not turned in" tests and its programs stand-ins
            saying so, and ex00_files reports it MISSING.
        exports: the global symbols rush0N.c may define, default ["rush"].
            The evaluator may edit or replace main.c at the defense ("your
            main function will be modified"), so every non-static
            helper is a name that can collide with theirs and fail the link on
            otherwise perfect code.
        seed: the differential corpus seed, default 1. Fixed so a failure is
            reproducible; change it to widen coverage deliberately, not to make
            a red go away.
        count: how many sizes the differential replays, default 2000. rush
            draws a whole rectangle per case through ft_putchar -- one write()
            per character, syscall-bound like the c-00/c-04 putnbr family --
            and 4200 was measured at 34s of a 60s budget.
        asan_count: the same corpus under ASan/UBSan, default 1500. Lower
            because instrumentation costs, and because this arm is looking for
            a memory fault rather than a wrong drawing.
        clues: the hint file for the output layer, under tests/exNN/.
        diff_clues: the hint file for the differential layers, under
            tests/exNN/. Separate from `clues` because a differential failure
            and a fixture failure send a student to different places.
    """
    _entry(num, "rush_variant")  # first: a contract error names this macro
    ex = "ex" + num
    p = "%s_rush%s" % (ex, variant)
    lib = "rush" + variant
    src = _zone([turnin_dir(num) + "/rush%s.c" % variant])
    if not gated and not src:
        return

    # Every file of the team's as a glob finds it (_zone). A gated variant
    # whose rush0N.c is not there yet still emits every layer: the static
    # ones become "not turned in" tests and the programs stand-ins that say
    # so, and ex00_files names the file as MISSING.
    main_c = _zone([turnin_dir(num) + "/main.c"])
    putchar_c = _zone([turnin_dir(num) + "/ft_putchar.c"])
    tests = "tests/%s" % ex
    capture_h = "%s/rush_capture.h" % tests
    oracle_fn = "rush_v%s" % variant[1:]
    extra = ["manual"] if not gated else []

    # A struct cannot be declared in a .c file (Norm III.4), so rush0N.c may come
    # with a rush0N.h beside it; a header shared by every variant may exist too.
    # Both are staged and compile-checked; only the variant's own is normed here.
    own_hdrs = _rush_variant_hdrs(ex, variant)
    all_hdrs = [
        h
        for h in _turnin_files(num, ".h")
        if h not in _rush_variant_hdrs(ex) or h in own_hdrs
    ]

    # ---- static layers -----------------------------------------------------
    # The Norm pair carries no `extra`: a bonus file that is there is normed
    # whatever team.bzl says (see `gated` above).
    _norm_test(p + "_norm", src + own_hdrs)
    _compile_tests(p, src, hdrs = all_hdrs, extra_tags = extra)

    # One forbidden_symbols call for all three files: the script pools the
    # symbols each file DEFINES before judging the ones they call, so this is
    # what lets main.c call rush() and rush0N.c call ft_putchar() while still
    # rejecting printf/putchar/malloc.
    if _allowed(num) != None:
        _forbidden_test(
            p + "_forbidden",
            src + putchar_c + main_c,
            _allowed(num),
            hdrs = all_hdrs,
            extra_tags = extra,
            turnin = src,
        )

    # Linkage hygiene, and this module is where it bites hardest: the subject
    # has the EVALUATOR modify main.c at the defense, so rush0N.c is linked
    # against a main() the team has never seen. Any non-static helper is a name
    # that can collide with one of theirs and fail the link on code that is
    # otherwise perfect — and a helper called `length` is about as collidable as
    # a name gets. rush0N.c may export rush, and nothing else.
    # exports defaults to just "rush": that is what the subject's file list
    # implies, and it is what a team should aim for. A team whose rush0N.h
    # declares helpers has to export them (a prototype in a header is a promise
    # of external linkage), so they can widen this list to the set they actually
    # mean to publish. That is not weakening the layer — it still fails the
    # moment a NEW name appears, which is the regression worth catching. The
    # narrower fix, if you want it, is `static` on each helper plus dropping its
    # prototype from the header; the struct stays there because Norm III.4 bans
    # declaring one in a .c.
    _symbols_test(
        p + "_symbols",
        src,
        exports or ["rush"],
        hdrs = all_hdrs,
        extra_tags = extra,
    )

    # ---- the student's rectangle, as a unit --------------------------------
    # `extra` (= ["manual"] for a bonus variant) reaches the unit and the
    # programs too, not just the tests: `manual` only removes a target from
    # wildcard expansion, and `bazel test //MOD/...` builds every non-test target
    # the pattern matches (--build_tests_only is off by default). A bonus variant
    # left mid-edit could no longer break the build -- its programs would be
    # stand-ins -- but nothing about a variant the team does not owe is worth
    # compiling on every run.
    _student_lib(
        name = lib,
        srcs = src,
        hdrs = all_hdrs,
        includes = [turnin_dir(num)],
        deps = [":ft_putchar"],
        tags = extra,
    )

    # ---- the signature the subject fixes -----------------------------------
    # "The function must be prototyped as follows: void rush(int x, int y);"
    # -- the types at basic, like every function exercise's, and "It must take
    # two integer arguments, named x and y" -- the names at strict: a name
    # changes nothing the program does, and only an evaluator reading the code
    # can mark it. Every harness below links rush() as the evaluator's main()
    # would, and names this test (_student_bin's `prototype`): C
    # links a mismatched signature without a word, and before this no variant
    # had the layer at all (finding 142).
    proto_test = _prototype_test(
        ex,
        src,
        all_hdrs,
        name = p + "_prototype",
        extra_tags = extra,
    )
    _prototype_names_test(
        p + "_prototype_names",
        ex,
        src,
        all_hdrs,
        extra_tags = extra,
    )

    # ---- curated pedagogic table ------------------------------------------
    cases_f = "%s/cases.tsv" % tests
    clues_f = "%s/%s" % (tests, clues)
    expected_f = "%s/rush%s.txt" % (tests, variant)
    binname = p + "_bin"
    _output_fixture_binary(
        name = binname,
        harness = ["%s/test_rush.c" % tests, capture_h],
        prototype = proto_test,
        deps = [":" + lib],
        diffio = True,
        dir = turnin_dir(num),
        tags = extra,
    )
    _test(
        name = p + "_output",
        srcs = ["//tools:diff_output.sh"],
        args = [
            "--bin",
            "$(location :%s)" % binname,
            "--harness-fixture",
            "--expected",
            "$(location %s)" % expected_f,
            "--stdin",
            "$(location %s)" % cases_f,
            "--labeled",
            # test_rush.c prints each rectangle as ONE value, its line breaks
            # and backslashes written by rc_escape in the table's notation
            # (rush_capture.h), and the oracle writes rush0N.txt the same way.
            "--escaped-values",
            "--clues",
            "$(location %s)" % clues_f,
        ] + _waiting_args(p + "_output")[0],
        data = [":" + binname, expected_f, cases_f, clues_f] + _waiting_args(p + "_output")[1],
        tags = ["output", _case_reads_tag([expected_f, cases_f])] + extra,
    )

    # ---- the subject's defense case, in full --------------------------------
    # "Here is an example of a test that will be performed: rush(123, 42);" --
    # the defense runs it, so a wrong picture there is a KO: basic, the whole
    # picture compared, against the reference's (tests/ex00/defense_rush0N.txt,
    # written by `oracle rush00_fixtures` and held to it by
    # ex00_oracle_fixtures). The harness reads that picture on stdin, calls
    # rush() with its size and prints ONE table row, never 5208 bytes: the
    # figures the size makes, and where the two first part (finding 141).
    defense_expected = "%s/defense.txt" % tests
    defense_picture = "%s/defense_rush%s.txt" % (tests, variant)
    defensebin = p + "_defensebin"
    _output_fixture_binary(
        name = defensebin,
        harness = ["%s/test_defense.c" % tests, capture_h],
        prototype = proto_test,
        deps = [":" + lib],
        dir = turnin_dir(num),
        tags = extra,
    )
    _test(
        name = p + "_defense",
        srcs = ["//tools:diff_output.sh"],
        args = [
            "--bin",
            "$(location :%s)" % defensebin,
            "--harness-fixture",
            "--expected",
            "$(location %s)" % defense_expected,
            "--stdin",
            "$(location %s)" % defense_picture,
            "--labeled",
            "--clues",
            "$(location %s)" % clues_f,
        ],
        data = [":" + defensebin, defense_expected, defense_picture, clues_f],
        tags = ["output", _case_reads_tag([defense_expected, defense_picture])] + extra,
    )

    # ---- degenerate + hostile sizes: survival, and a legal size's shape ----
    edge_f = "%s/edge_cases.tsv" % tests
    survive_expected = "%s/survive.txt" % tests
    # Named for what it checks, not for a level: it was <p>_robust, a basic
    # test named after the level above (finding 038), and its files with it.
    survivebin = p + "_survivebin"
    _output_fixture_binary(
        name = survivebin,
        harness = ["%s/survive_rush.c" % tests, capture_h],
        prototype = proto_test,
        deps = [":" + lib],
        diffio = True,
        dir = turnin_dir(num),
        tags = extra,
    )
    _test(
        name = p + "_survive",
        srcs = ["//tools:diff_output.sh"],
        args = [
            "--bin",
            "$(location :%s)" % survivebin,
            "--harness-fixture",
            "--expected",
            "$(location %s)" % survive_expected,
            "--stdin",
            "$(location %s)" % edge_f,
            "--labeled",
            "--clues",
            "$(location %s)" % clues_f,
        ],
        data = [":" + survivebin, survive_expected, edge_f, clues_f],
        tags = ["output", _case_reads_tag([survive_expected, edge_f])] + extra,
    )

    # ---- the student's own main.c, built exactly as the subject says -------
    mainbin = p + "_mainbin"
    _student_bin(
        name = mainbin,
        srcs = main_c + putchar_c + src,
        hdrs = all_hdrs,
        includes = [turnin_dir(num)],
        archive = False,
        dir = turnin_dir(num),
        tags = extra,
    )
    # The subject's example main returns 0 but names no exit status, so by the
    # Run contract (docs/reference.md) a plain non-zero return is only noted
    # here, and fails at robust in <p>_main_exit, which judges nothing else.
    _test(
        name = p + "_main",
        srcs = ["//tools:run_check.sh"],
        args = [
            "--bin",
            "$(location :%s)" % mainbin,
            "--label",
            # sh_test args are shell-tokenised, so no spaces in a single arg
            "main.c+ft_putchar.c+rush%s.c" % variant,
            "--min-bytes",
            "1",
            "--note-exit",
            "0",
            "--timeout",
            "20",
        ],
        data = [":" + mainbin],
        tags = ["output"] + extra,
    )
    _test(
        name = p + "_main_exit",
        srcs = ["//tools:run_check.sh"],
        args = [
            "--bin",
            "$(location :%s)" % mainbin,
            "--label",
            "main.c+ft_putchar.c+rush%s.c" % variant,
            "--exit",
            "0",
            "--exit-only",
            # The subject names no status: a failure says the check is the C
            # convention, which only this caller knows.
            "--exit-source",
            "convention",
            "--timeout",
            "20",
        ],
        data = [":" + mainbin],
        tags = ["output"] + extra,
        level = 3,
    )

    # ---- memory layers -----------------------------------------------------
    vgbin = p + "_vgbin"
    _student_bin(
        name = vgbin,
        harness = ["%s/vg_rush.c" % tests, capture_h],
        prototype = proto_test,
        deps = [":" + lib],
        dir = turnin_dir(num),
        tags = extra,
    )

    # Named flags and a correctness gate, exactly like c_function's arm. This was
    # the last caller passing the binary positionally, and the only one of the
    # three with no gate at all -- so a rush team whose rush0N.c is still a stub
    # got a raw memcheck report printed over the top of the output layer they
    # should have been reading, which is the precise failure the gate was added
    # elsewhere to prevent. It reuses the output layer's own fixture above, so
    # the two can never describe different runs.
    _test(
        name = p + "_valgrind",
        srcs = ["//tools:valgrind_test.sh"],
        args = [
            "--bin",
            "$(location :%s)" % vgbin,
            "--label",
            p,
            "--gate-differ",
            "$(location //tools:diff_output.sh)",
            "--gate-bin",
            "$(location :%s)" % binname,
            "--gate-expected",
            "$(location %s)" % expected_f,
            "--gate-stdin",
            "$(location %s)" % cases_f,
            "--gate-labeled",
            "--clues",
            "$(location %s)" % clues_f,
        ] + _valgrind_args(),
        data = [
            ":" + vgbin,
            ":" + binname,
            expected_f,
            cases_f,
            clues_f,
            "//tools:diff_output.sh",
        ] + _valgrind_data(),
        tags = ["valgrind"] + extra,
    )
    probe_f = "%s/mem_rush.c" % tests
    asan_args = [
        "--probe",
        "$(location %s)" % probe_f,
    ]
    for s in src + putchar_c:
        asan_args += ["--src", "$(location %s)" % s]
    asan_args += _inc_args("--hdr", [capture_h])
    asan_args += _inc_args("--hdr", all_hdrs)
    _test(
        name = p + "_asan",
        srcs = ["//tools:asan_check.sh"],
        args = _pinned_build_args() + asan_args + _symbolizer_args(),
        data = _uniq([probe_f, capture_h] + src + putchar_c + all_hdrs + _SYMBOLIZER_DATA +
                     _PINNED_BUILD_DATA + ["@clang_12_ubuntu//:sanitizer_runtime"]),
        tags = ["asan"] + extra,
        turnin = src,
    )

    # ---- live differential against //oracle --------------------------------
    diff_clues_f = "%s/%s" % (tests, diff_clues)
    diffbin = p + "_diffbin"
    _student_bin(
        name = diffbin,
        harness = ["%s/diff_rush.c" % tests, capture_h],
        prototype = proto_test,
        deps = [":" + lib],
        diffio = True,
        dir = turnin_dir(num),
        tags = extra,
    )
    _test(
        name = p + "_diff",
        size = "medium",
        srcs = ["//tools:rust_diff.sh"],
        args = [
            "--oracle",
            "$(location //oracle:oracle)",
            "--oracle-fn",
            oracle_fn,
            "--seed",
            str(seed),
            "--count",
            str(count),
            "--student-bin",
            "$(location :%s)" % diffbin,
            "--clues",
            "$(location %s)" % diff_clues_f,
            # Same gate as c_diff, with the rush fixture's own shape: the
            # labelled table is driven from cases.tsv on stdin. --stdin changes
            # diff_output.sh's verdict, so omitting it would make the gate
            # misread a passing variant as red and skip forever.
            "--gate-differ",
            "$(location //tools:diff_output.sh)",
            "--gate-bin",
            "$(location :%s)" % binname,
            "--gate-expected",
            "$(location %s)" % expected_f,
            "--gate-stdin",
            "$(location %s)" % cases_f,
            "--gate-labeled",
        ],
        data = [
            "//oracle:oracle",
            ":" + diffbin,
            diff_clues_f,
            "//tools:diff_output.sh",
            ":" + binname,
            expected_f,
            cases_f,
        ],
        tags = ["diff"] + extra,
    )

    # Crash-fuzz twin: the SAME harness under ASan/UBSan, replaying the
    # degenerate corpus (rush_vN_edge) in --crash-only mode. Values are not
    # compared there — the subject does not define them — so this asks only
    # whether a zero/negative/INT_MIN dimension is survivable, and catches the
    # negation of INT_MIN that UBSan alone can see.
    asan_diffbin = p + "_diffbin_asan"
    _student_bin(
        name = asan_diffbin,
        harness = ["%s/diff_rush.c" % tests, capture_h],
        prototype = proto_test,
        deps = [":" + lib],
        diffio = True,
        dir = turnin_dir(num),
        asan = True,
    )
    _test(
        name = p + "_diff_asan",
        size = "medium",
        srcs = ["//tools:rust_diff.sh"],
        args = [
            "--oracle",
            "$(location //oracle:oracle)",
            "--oracle-fn",
            oracle_fn + "_edge",
            "--seed",
            str(seed),
            "--count",
            str(asan_count),
            "--crash-only",
            "--student-bin",
            "$(location :%s)" % asan_diffbin,
            "--harness-src",
            "$(location %s/diff_rush.c)" % tests,
            "--clues",
            "$(location %s)" % diff_clues_f,
        ] + _symbolizer_args(),
        data = [
            "//oracle:oracle",
            ":" + asan_diffbin,
            "%s/diff_rush.c" % tests,
            diff_clues_f,
        ] + _SYMBOLIZER_DATA,
        tags = ["diff_asan"] + extra,
    )

    # A per-variant suite, so a bonus variant can be run in one go even though
    # its tests are hidden from `//...`. The suite carries the "manual" tag too:
    # a NON-manual suite that lists manual tests drags them back into the
    # wildcard run, which is exactly what the bonus tags exist to prevent.
    native.test_suite(
        name = p,
        tests = [
            ":" + p + "_norm",
            ":" + p + "_norm_notice",
            ":" + p + "_compile_clang",
            ":" + p + "_compile_gcc",
            ":" + p + "_forbidden",
            ":" + p + "_symbols",
            ":" + p + "_output",
            ":" + p + "_survive",
            ":" + p + "_main",
            ":" + p + "_valgrind",
            ":" + p + "_asan",
            ":" + p + "_diff",
            ":" + p + "_diff_asan",
        ],
        tags = ["manual"],
    )
