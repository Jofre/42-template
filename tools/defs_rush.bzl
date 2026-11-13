"""The rush macros, for a group project whose rush files define the same symbol.

rush_common declares what every variant shares, rush_variant one drawing.

Loaded by the files above it, and re-exported by tools/defs.bzl, the one
file a BUILD file loads.
"""

load(
    ":defs_checks.bzl",
    _compile_tests = "compile_tests",
    _forbidden_test = "forbidden_test",
    _norm_test = "norm_test",
    _prototype_names_test = "prototype_names_test",
    _prototype_test = "prototype_test",
    _symbols_test = "symbols_test",
)
load(
    ":defs_contract.bzl",
    "turnin_dir",
    "turnin_glob",
    _allowed = "allowed",
    _entry = "entry",
    _inc_args = "inc_args",
    _student_bin = "student_bin",
    _student_lib = "student_lib_private",
    _turnin_files = "turnin_files",
    _zone = "zone",
)
load(
    ":defs_levels.bzl",
    _key = "key",
    _memory_graded = "memory_graded",
    _prefix = "prefix",
    _uniq = "uniq",
)
load(
    ":defs_test.bzl",
    _NO_GATE_TAG = "NO_GATE_TAG",
    _output_fixture_binary = "output_fixture_binary",
    _test = "test",
    _waiting_args = "waiting_args",
)
load(
    ":defs_toolchain.bzl",
    _PINNED_BUILD_DATA = "PINNED_BUILD_DATA",
    _SYMBOLIZER_DATA = "SYMBOLIZER_DATA",
    _case_reads_tag = "case_reads_tag",
    _pinned_build_args = "pinned_build_args",
    _symbolizer_args = "symbolizer_args",
    _valgrind_args = "valgrind_args",
    _valgrind_data = "valgrind_data",
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
    return turnin_glob(["%s/rush%s.h" % (turnin_dir(_key(ex)), v) for v in variants])

def rush_common(num = "00", clues = "clues_putchar.tsv", name = None):
    """The rush layers that do not depend on which variant is implemented.

    Emits: norm + both-compiler compile for main.c and ft_putchar.c, and
    ft_putchar's own output/forbidden tests — linked against ft_putchar.c ALONE,
    which is also how "the ft_putchar.c file must contain the ft_putchar
    function" gets checked.

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
            nothing for it to control."""
    _entry(num, "rush_common")  # first: a contract error names this macro
    ex = _prefix(num)

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

def _rush_graded_problem(memory_graded):
    """rush_variant's message in a package whose contract declares memory_graded; None elsewhere.

    No rush subject says its grader judges memory, and rush_variant's
    valgrind arm was never proven quoting the contract's sentences
    (_graded_rule) or sitting at basic: refused until a project needs it,
    rather than wired and unproven. A value, so the macro fixtures can feed
    it both ways (contract_problem("rush_graded", ...)).
    """
    if not memory_graded:
        return None
    return ("rush_variant: the subject() contract declares memory_graded, and no rush " +
            "subject says its grader judges memory: its valgrind arm has never been proven " +
            "quoting the contract's sentences at basic. Wire _graded_rule() into it, with a " +
            "fixture in tools/tests/macro_fixtures/graded, before a project needs it.")

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
      <p>_defense         the subject's defense case, rush(123, 42), in full;
                          it waits for <p>_output, as <p>_main does
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
    problem = _rush_graded_problem(bool(_memory_graded()))
    if problem:
        fail(problem)
    ex = _prefix(num)
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

    # The output test's own run, for the tests that wait for it: _defense and
    # _main SKIP while it is red (the owner's answer of 2026-10-10), as the
    # memory and differential layers below do. On a stub all three were red
    # for the one reason, and only the table has the hints. Each gate is this
    # run, and c_levels()' audit holds it to that: the same program, expected
    # file, standard input and --labeled as <p>_output's (_case_gate_problems),
    # and the output test it resolves to is <p>_output (_waiting_problems).
    output_gate = [
        "--gate-bin",
        "$(location :%s)" % binname,
        "--gate-expected",
        "$(location %s)" % expected_f,
        "--gate-stdin",
        "$(location %s)" % cases_f,
        "--gate-labeled",
    ]
    output_gate_data = [":" + binname, expected_f, cases_f]

    # ---- the subject's defense case, in full --------------------------------
    # "Here is an example of a test that will be performed: rush(123, 42);" --
    # the defense runs it, so a wrong picture there is a KO: basic, the whole
    # picture compared, against the reference's (tests/ex00/defense_rush0N.txt,
    # written by `oracle rush00_fixtures` and held to it by
    # ex00_oracle_fixtures). The harness reads that picture on stdin, calls
    # rush() with its size and prints ONE table row, never 5208 bytes: the
    # figures the size makes, and where the two first part (finding 141).
    # It waits for <p>_output (output_gate): the same rush(), under the
    # harness with the table and the hints.
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
            "--gate-label",
            p + "_output",
        ] + output_gate,
        data = _uniq([":" + defensebin, defense_expected, defense_picture, clues_f] + output_gate_data),
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
    # It waits for <p>_output (output_gate): a main.c calling a rush() that
    # draws nothing yet prints nothing either. <p>_main_exit does not wait:
    # how main() returns is its own, whatever rush() draws.
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
            "--gate-differ",
            "$(location //tools:diff_output.sh)",
            # Its SKIP line names the test it waits for, as _defense's does.
            "--gate-label",
            p + "_output",
        ] + output_gate,
        data = [":" + mainbin, "//tools:diff_output.sh"] + output_gate_data,
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
            # Its SKIP line names the test it waits for.
            "--gate-label",
            p + "_output",
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
            # The header's "Line:" sentence, printed above a divergence: what
            # the columns are, as every c_diff and the crash twin below show.
            "--harness-src",
            "$(location %s/diff_rush.c)" % tests,
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
            # Its SKIP line names the test it waits for.
            "--gate-label",
            p + "_output",
        ],
        data = [
            "//oracle:oracle",
            ":" + diffbin,
            "%s/diff_rush.c" % tests,
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
    #
    # IT WAITS FOR NOTHING, unlike the variant's _diff above (_NO_GATE_TAG,
    # which c_levels()' audit reads): a gate is there so a corpus does not
    # report the labelled table's red again, and this one cannot. It
    # compares no output, and none of its dimensions is a row of the table:
    # a crash on a zero or an INT_MIN width is a fault the table never
    # shows, red or green, and waiting for the table would hide it from a
    # team whose table is red for a reason of its own.
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
        tags = ["diff_asan", _NO_GATE_TAG] + extra,
    )

    # A per-variant suite, so a bonus variant can be run in one go even though
    # its tests are hidden from `//...`. The suite carries the "manual" tag too:
    # a NON-manual suite that lists manual tests drags them back into the
    # wildcard run, which is exactly what the bonus tags exist to prevent.
    # It lists every test above, in the docstring's order, and only those:
    # c_levels()' audit fails a manual suite that leaves out a test of its
    # name, or names one no rule declares (_suite_problems), as _forbidden
    # is under a contract with no Allowed line.
    native.test_suite(
        name = p,
        tests = [
            ":" + p + "_norm",
            ":" + p + "_norm_notice",
            ":" + p + "_compile_clang",
            ":" + p + "_compile_gcc",
        ] + ([":" + p + "_forbidden"] if _allowed(num) != None else []) + [
            ":" + p + "_symbols",
            ":" + p + "_prototype",
            ":" + p + "_prototype_names",
            ":" + p + "_output",
            ":" + p + "_defense",
            ":" + p + "_survive",
            ":" + p + "_main",
            ":" + p + "_main_exit",
            ":" + p + "_valgrind",
            ":" + p + "_asan",
            ":" + p + "_diff",
            ":" + p + "_diff_asan",
        ],
        tags = ["manual"],
    )


# ---------------------------------------------------------------------------
# WHAT THE FILES ABOVE THIS ONE LOAD OF IT. A load() cannot name a private
# symbol, so each one they use is given a public name here, its own without
# the underscore, and loaded back under its own name: the code reads as it did
# when tools/defs.bzl held it all. These names are for those files alone; a
# BUILD file loads //tools:defs.bzl.
rush_graded_problem = _rush_graded_problem
