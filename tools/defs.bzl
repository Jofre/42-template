"""Macros for scaffolding 42 C-Piscine exercises.

Every exercise lives in two trees inside its module:
  deliverable/exNN/  -> the files the student submits (stubs to be implemented)
  tests/exNN/        -> the test harness + expected output (never submitted)

Exercise shapes:
  c_function  -> a function with no main(); a separate harness calls it and we
                 diff stdout against expected.txt.
  c_program   -> a program that owns main() and reads argv/stdin/files; the
                 deliverable source is compiled directly and run with argument cases.
  c_header    -> a header-only deliverable (c-08). The compile happens inside the
                 runner, not in a cc_binary, so an unwritten header is a red TEST
                 rather than a Bazel build failure.
  c_make      -> a build-system deliverable (a Makefile or a shell script that
                 produces libft.a / a binary); we build it and check artifacts.
  c_libft     -> c-09's shape: loose sources built into an archive by a build
                 system the student writes, PLUS the behaviour of those sources.
  c_argv_table-> one labelled table for an argv program run over many invocations.

Layers an exercise can add:
  c_diff      -> differential value + crash-fuzz against the //oracle reference
  c_mem_check -> adversarial ASan probes (exact-size / unterminated buffers)
  c_perf      -> informative cost measurement (time AND memory growth)
  c_files     -> the deliverable file SET, against the subject's turn-in line
  c_levels    -> the per-module basic/strict/robust/complete suites

Every generated test is tagged with its layer AND with cumulative lvl_* tags, so
`bazel test //<module>:basic` selects a level and `--test_tag_filters=norm`
still selects a single layer. See _LAYER_LEVEL for the mapping.
"""

load("@rules_cc//cc:defs.bzl", "cc_binary", "cc_library")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

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
# when the campus toolchain defaults to it. bfd is present on the campus box and
# the devcontainer alike (it is the default `ld`).
_ASAN_LINKOPTS = ["-fsanitize=address,undefined", "-fuse-ld=bfd"]

# Every test these macros emit runs in well under a second (norminette, one
# compile, an output diff, valgrind on a tiny program, a small make). Declaring
# them "small" gives a 60s timeout — a runaway loop in a student's code fails fast
# instead of hanging for the 5-min "moderate" default — and tells Bazel they are
# cheap, so it schedules more of them in parallel. New tests inherit this default.
# Which gate level each layer belongs to. Same ladder //tools:submit uses:
#   1 basic    — every layer whose failure is an outright KO on the Moulinette
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
#                        c-02 already fuzz against the oracle.
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
    "diff": 3,
    "diff_asan": 3,
    "asan": 3,
    # Refusing one allocation at a time. Level 3, not 1: the exercise it is
    # wired to does state the requirement verbatim, but nothing proves the
    # Moulinette exercises that branch, so this is the repo's own rigour rather
    # than a reproduction of 42's gate.
    "allocfail": 3,
    "ilp32": 4,
    "perf": 4,
    "cycles": 4,
    "oracle": 4,
    "selftest": 4,
}

_LEVEL_NAMES = ["basic", "strict", "robust", "complete"]

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
                 "Only UP is allowed: `basic` has to keep meaning everything the Moulinette would KO.")
        lvl = level
    if lvl == 0:
        return []
    return ["lvl_" + _LEVEL_NAMES[i] for i in range(lvl - 1, len(_LEVEL_NAMES))]

def _test(size = "small", level = None, **kwargs):
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
        level is what makes `basic` mean "everything the Moulinette would KO you
        for".
    """
    tags = kwargs.pop("tags", [])

    # THE EXERCISE, as a tag, derived here rather than passed by thirty callers.
    # Every test name this macro emits begins with exNN_ -- checked across the
    # awkward shapes too (rush variants `ex00_rush03_output`, c_program cases
    # `ex01_blob_output`, c-08's `ex01_success_output`) -- so the prefix is a
    # reliable source and there is one place to get it wrong instead of thirty.
    # c_levels() turns these into a per-exercise suite.
    ex_tag = kwargs.get("name", "").split("_")[0]
    if not ex_tag.startswith("ex"):
        ex_tag = None
    all_tags = tags + _level_tags(tags, level) + ([ex_tag] if ex_tag else [])
    sh_test(size = size, tags = all_tags, **kwargs)

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

def _deliverable_srcs(ex, fallback):
    """Every .c file the student turns in for exercise `ex`.

    GLOBBED, never listed. The subject's file set is written down in exactly one
    place -- the c_files() call for this exercise -- and that copy exists to be
    CHECKED against the directory, not to drive the build. Compilation reads the
    directory itself, so the two cannot drift apart.

    They used to. Five macros -- c_function, c_mem_check, c_program, c_cycles and
    c_reference_cost -- each computed `deliverable/exNN/<fn>.c` independently, so
    an exercise whose subject asks for two files had to override `srcs` at all
    five call sites. c-07 ex04 overrode c_function and not c_cycles, and the
    result was a link error at -O2 naming ft_strlen and ft_atoi_base, which reads
    as a problem with the optimisation level rather than a missing source.

    Only these five ever needed it: c_perf, c_argv_table and c_diff name no files
    at all, referencing the targets built above them (:exNN_bin, :fn, :fn_asan),
    and within c_function every layer -- norm, both compilers, forbidden,
    prototype, symbols, ilp32, asan, valgrind -- already reads one `srcs` local.

    Flat, not recursive: c-09 ex01 keeps its sources under a srcs/ subdirectory
    and is driven by c_libft with explicit srcs, so `**/*.c` would sweep those
    into unrelated targets for no gain.

    NOT used by the rush macros, and must not be. rush-00's deliverable/ex00
    holds rush00.c .. rush04.c, each defining rush(), plus main.c and
    ft_putchar.c; compiling that directory as one unit is a duplicate-symbol
    error by design. rush_common()/rush_variant() name their files explicitly
    for that reason.

    The fallback covers an exercise whose directory is empty -- an unimplemented
    one on the template branch. Naming the conventional file keeps Bazel's error
    pointing at the missing deliverable instead of at an empty source list.
    """
    found = native.glob(["deliverable/%s/*.c" % ex], allow_empty = True)
    if found:
        return found
    return ["deliverable/%s/%s.c" % (ex, fallback)]

def c_levels(name = None):
    """Per-module suites so you can run one level while you work.

    Args:
      name: unused. Bazel convention is that every macro takes a `name`, and
        buildifier's unnamed-macro check enforces it -- a student who writes
        their own macro should meet that rule here rather than be surprised
        by it later. This macro emits four fixed targets (basic, strict,
        robust, complete) whose names come from the level ladder, not from a
        caller, so there is nothing for it to control.

        bazel test //c-piscine-c-05:basic       # what the Moulinette grades
        bazel test //c-piscine-c-05:strict      # + symbols, valgrind
        bazel test //c-piscine-c-05:robust      # + diff, diff_asan, asan
        bazel test //c-piscine-c-05/...         # everything, as before

    That list used to be repeated as a comment above all twenty c_levels()
    calls, one identical copy per module. A rule stated once per instance is
    not a rule -- it is twenty chances to drift -- so it lives here, next to
    the macro that implements it, and the call sites say nothing.

    Naming a single target still runs it regardless of level — these are suites
    you ASK for, not a filter you have to escape. `--test_tag_filters` would
    have been the obvious mechanism and is the wrong one: it also filters
    explicitly-named targets, so `bazel test //mod:ex00_ilp32` under a basic
    filter reports "No test targets were found" instead of running the test you
    just asked for.
    """
    for name in _LEVEL_NAMES:
        native.test_suite(
            name = name,
            tags = ["lvl_" + name],
        )

    # ONE SUITE PER EXERCISE, so a whole exercise can be run in one command.
    #
    # Before these, you could run one LAYER of one exercise
    # (//c-piscine-c-05:ex00_output) or a whole module, and nothing in between:
    # `ex00_*` is not a Bazel target pattern, and --test_tag_filters is the
    # wrong tool for the reason spelled out above -- it also filters targets you
    # name explicitly.
    #
    # The exercise numbers are DISCOVERED from tests/, not passed in. Every
    # module has a tests/exNN/ per exercise, including the shapes with no
    # deliverable sources to glob (c-08's headers, the shell modules, whose
    # deliverable/ is generated and gitignored). A hand-maintained list here
    # would be one more thing to forget when a module gains an exercise.
    seen = {}
    for f in native.glob(["tests/ex*/*"], allow_empty = True):
        parts = f.split("/")
        if len(parts) > 2:
            seen[parts[1]] = True
    for ex in sorted(seen):
        native.test_suite(
            name = ex,
            tags = [ex],
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
    # norm_flags injects extra `-R <rule>` tokens before the files (the script
    # always passes -R CheckForbiddenSourceHeader). e.g. ["-R", "CheckDefine"]
    # lets header exercises define function-like macros (ABS, EVEN).
    # extra_tags is for exercises with optional parts (rush's bonus variants),
    # which pass ["manual"] to keep an unimplemented variant out of `//...`.
    # level raises this one above norm's level 1 -- used for files the student
    # neither wrote nor turns in, where a red is real but is OURS, not theirs.
    norm_flags = norm_flags or []
    _test(
        name = name,
        srcs = ["//tools:norminette_test.sh"],
        args = ["--norminette", "$(location //tools:norminette)"] +
               norm_flags + ["$(location %s)" % f for f in files],
        data = files + ["//tools:norminette"],
        tags = ["norm"] + (extra_tags or []),
        level = level,
    )

def _forbidden_test(name, srcs, allowed, hdrs = None, extra_tags = None):
    # "-" sentinel: Bazel drops an empty-string arg, so an empty allowlist
    # ("only baseline builtins allowed") must be passed as a non-empty token.
    hdrs = hdrs or []
    allowed_csv = ",".join(allowed) if allowed else "-"
    args = ["--nm", "$(location @binutils_x86_64_linux_gnu//:usr/bin/x86_64-linux-gnu-nm)", "--allowed", allowed_csv]
    for h in hdrs:
        args += ["--hdr", "$(location %s)" % h]
    for s in srcs:
        args += ["--src", "$(location %s)" % s]
    _test(
        name = name,
        srcs = ["//tools:forbidden_symbols.sh"],
        args = args,
        data = srcs + hdrs + ["@binutils_x86_64_linux_gnu//:usr/bin/x86_64-linux-gnu-nm"],
        tags = ["forbidden"] + (extra_tags or []),
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

# The pinned make. Reached by the two runners that drive a student Makefile --
# make_test.sh, which grades it, and make_srcs_build.sh, which asks it which
# files the program is made of.
_MAKE = "@make_ubuntu//:usr/bin/make"

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

def _makefile_binaries(ex, makefile, make_data, copts, asan_copts, asan_linkopts):
    """Build exNN_bin and exNN_bin_asan from the Makefile's own source list.

    For the modules whose subject mandates a Makefile and then says only "and
    all the necessary files", nobody but the team knows what the program is made
    of -- so nothing here may assume it. A glob of deliverable/exNN/*.c is not
    the program: it sweeps in a second front end or a kept experiment and the
    link dies on a duplicate main while `make` is perfectly happy. A list in the
    BUILD file is the same assumption with an extra copy to go stale.

    cc_binary cannot help, because it needs its srcs at analysis time and the
    Makefile has not been consulted by then. So the compile moves into an action
    that can ask: see tools/make_srcs_build.sh, which runs `make -Bn` and takes
    the .c files out of the recipes.

    Only the SOURCE LIST comes from the Makefile. Flags stay ours -- the same
    -Wall -Wextra -Werror and the same sanitizer every other module gets -- so a
    Makefile that forgets a flag cannot soften these layers, and the exercise is
    still testable under ASan although no student Makefile builds an
    instrumented binary. Whether the Makefile itself works is c_make's question,
    asked separately on purpose.

    Args:
        ex: "exNN", the prefix every emitted target is named from.
        makefile: package-relative path to the deliverable's Makefile.
        make_data: every file to stage beside it -- normally a bare glob of the
            deliverable directory. It must be the whole directory rather than
            the sources: a Makefile may include another file or read anything
            sitting next to it, and a missing one fails as a make error.
        copts: compile flags for the plain binary.
        asan_copts: compile flags for the instrumented one.
        asan_linkopts: link flags for the instrumented one.

    Returns:
        (plain_target_name, asan_target_name), both file targets rather than
        cc_binary rules; everything downstream takes a path, so nothing else
        can tell the difference.
    """
    for suffix, cflags, ldflags in [
        ("_bin", copts, []),
        ("_bin_asan", asan_copts, asan_linkopts),
    ]:
        # Through `sh`, not executed directly: tools/*.sh carry no execute bit
        # in this repo (every sh_test wrapper invokes them the same way), and a
        # genrule running one directly dies with a bare "Exit 126".
        cmd = ["sh", "$(location //tools:make_srcs_build.sh)"]
        cmd += ["--anchor", "$(location %s)" % makefile]
        cmd += ["--cc", _CAMPUS_CCS[0]["cc"]]
        for lib in _CAMPUS_CCS[0]["libs"]:
            cmd += ["--cc-lib", "$(location %s)" % lib]
        cmd += ["--out", "$@"]
        # Always produce the output. See the script's header: an unwritten
        # deliverable is this repo's normal state, and a build action that
        # fails takes the whole module's tests down as "FAILED TO BUILD"
        # instead of failing them one at a time with their clues.
        cmd += ["--stub-on-failure"]
        cmd += ["--make", "$(location %s)" % _MAKE]
        for f in cflags:
            cmd += ["--copt", f]
        for f in ldflags:
            cmd += ["--linkopt", f]
        native.genrule(
            name = ex + suffix + "_build",
            # The compiler's own files ride along in srcs so $(location)
            # resolves for them; the genrule stages them like any other input.
            srcs = make_data + _CAMPUS_CCS[0]["data"] + _CAMPUS_CCS[0]["libs"] +
                   [_MAKE],
            outs = [ex + suffix],
            cmd = " ".join(cmd),
            tools = ["//tools:make_srcs_build.sh"],
            # The instrumented binary is built only when something asks for it,
            # matching the "manual" tag its cc_binary twin carries elsewhere.
            tags = ["manual"] if suffix == "_bin_asan" else [],
        )
    return (ex + "_bin", ex + "_bin_asan")

def _symbols_test(name, srcs, exports, hdrs = None, extra_tags = None):
    """Exactly `exports` may be visible to the linker; every helper is static."""
    hdrs = hdrs or []
    args = ["--nm", "$(location @binutils_x86_64_linux_gnu//:usr/bin/x86_64-linux-gnu-nm)", "--expect", ",".join(exports)]
    for s in srcs:
        args += ["--src", "$(location %s)" % s]
    for h in hdrs:
        args += ["--inc", "$(location %s)" % h]
    _test(
        name = name,
        srcs = ["//tools:symbols_test.sh"],
        args = args,
        data = srcs + hdrs + ["@binutils_x86_64_linux_gnu//:usr/bin/x86_64-linux-gnu-nm"],
        tags = ["symbols"] + (extra_tags or []),
    )

def _compile_tests(ex, srcs, hdrs = None, extra_tags = None):
    hdrs = hdrs or []
    common = []
    for s in srcs:
        common += ["--src", "$(location %s)" % s]
    for h in hdrs:
        common += ["--hdr", "$(location %s)" % h]
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
                   ([spec["progs"]] if spec["progs"] else []),
            tags = ["compile"] + (extra_tags or []),
        )

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
    agree: _emit_cases() runs a prebuilt cc_binary through diff_output.sh,
    c_program() emits its own asan targets beside it, and c_header() has no
    cc_binary on purpose (see its comment) and compiles inside header_check.sh.
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
def _emit_cases(ex, binname, cases, valgrind = False):
    """Emit one diff test (and optional valgrind test) per argv case."""
    for c in cases:
        cname = c.get("name", "run")
        stem = _case_stem(ex, cases, cname)
        expected_f = "tests/%s/%s" % (ex, c["expected"])
        data = [":" + binname, expected_f] + c.get("fixtures", [])
        args = [
            "--bin",
            "$(location :%s)" % binname,
            "--expected",
            "$(location %s)" % expected_f,
        ]
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
        if c.get("stdin"):
            args += ["--stdin", "$(location %s)" % c["stdin"]]
            data.append(c["stdin"])
        if "exit" in c:
            args += ["--exit", str(c["exit"])]
        args += ["--"] + c.get("args", [])
        _test(
            name = "%s_output" % stem,
            srcs = ["//tools:diff_output.sh"],
            args = args,
            data = data,
            tags = ["output"],
        )
        if valgrind and c.get("valgrind", True):
            vdata = [
                ":" + binname,
                expected_f,
                "//tools:diff_output.sh",
            ] + c.get("fixtures", [])
            vargs = [
                "--bin",
                "$(location :%s)" % binname,
                "--label",
                stem,
                # Gate on the exercise's own fixture, the way rust_diff, ilp32,
                # perf and cycles already do. Without it this was the one rigour
                # layer that spoke first: c-12 ex06 is a stub, so a student who
                # had written nothing was met with eight raw "indirectly lost"
                # records instead of "your output layer is still red — start
                # there". Leaks are the LAST thing to think about, after the
                # function produces the right bytes at all.
                "--gate-differ",
                "$(location //tools:diff_output.sh)",
                "--gate-bin",
                "$(location :%s)" % binname,
                "--gate-expected",
                "$(location %s)" % expected_f,
            ]
            if c.get("stream"):
                vargs += ["--gate-stream", c["stream"]]
            if c.get("sanitize"):
                vargs.append("--gate-sanitize")
            if c.get("labeled"):
                vargs.append("--gate-labeled")
            # stdin was never forwarded, so a case that feeds the program input
            # ran a DIFFERENT path here than under the output layer — it read
            # EOF immediately. Latent today (c-10 ex01 is the only stdin case
            # and is not malloc = True), but the layers must agree on what they
            # are running.
            if c.get("stdin"):
                vargs += [
                    "--stdin",
                    "$(location %s)" % c["stdin"],
                    "--gate-stdin",
                    "$(location %s)" % c["stdin"],
                ]
                vdata.append(c["stdin"])

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
            vargs += _valgrind_args()
            vargs += ["--"] + c.get("args", [])
            _test(
                name = "%s_valgrind" % stem,
                srcs = ["//tools:valgrind_test.sh"],
                args = vargs,
                data = vdata + _valgrind_data(),
                size = "small",
                tags = ["valgrind"],
            )

def _prototype_test(ex, srcs, hdrs = None, extra_includes = None, required = True):
    """Prototype conformance (tag "prototype"): the deliverable's definition
    matches the signature the subject fixes.

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
        return

    p_args = ["--proto", "$(location %s)" % proto_f]
    for s in srcs:
        p_args += ["--src", "$(location %s)" % s]
    for h in hdrs:
        p_args += ["--inc", "$(location %s)" % h]
    for d in (extra_includes or []):
        p_args += ["--inc", d]
    _test(
        name = ex + "_prototype",
        srcs = ["//tools:prototype_check.sh"],
        args = p_args,
        data = [proto_f] + srcs + hdrs,
        tags = ["prototype"],
    )

def c_function(
        num,
        fn,
        test,
        srcs = None,
        hdrs = None,
        provided_hdrs = None,
        deps = None,
        extra_includes = None,
        expected = "expected.txt",
        sanitize = False,
        labeled = False,
        clues = None,
        malloc = False,
        allowed = None,
        exports = None,
        prototype = True,
        ilp32 = True,
        allocfail = None):
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
        fn: the subject's function. It does four jobs: it names the cc_library
            the harness links against and its ASan twin <fn>_asan (so it has to
            be unique within the module), it is the default `exports` entry, it
            is the fallback source name when the deliverable directory is still
            empty, and it labels the valgrind and allocfail reports as
            "exNN/fn".
        test: the harness, named relative to tests/exNN/ -- a main() that calls
            fn and prints. It is compiled into exNN_bin against the student's
            library and is never turned in. A function exercise's deliverable
            has no main() at all, which is exactly why this shape needs a
            harness the student does not write.
        srcs: the deliverable sources. Defaults to a GLOB of
            deliverable/exNN/*.c (see _deliverable_srcs), falling back to
            deliverable/exNN/<fn>.c when that directory is still empty, so an
            unimplemented exercise fails on the missing file rather than on an
            empty source list. Nothing in the repo overrides it, and c-07 ex04
            -- the one exercise whose subject asks for two files -- carries a
            comment saying not to: the file set is written down once, in that
            exercise's c_files() call, to be CHECKED against the directory
            rather than copied into the build.
        hdrs: headers that are PART OF THE TURN-IN -- the student writes them
            and pushes them (c-12's and c-13's ft_list.h / ft_btree.h, which
            the subject dictates the contents of but still asks for). They
            become the cc_library's hdrs, each one's directory reaches the
            compile, forbidden, symbols, prototype, ilp32 and allocfail runners
            as an -I, and they are norminette-checked along with srcs -- which
            is right, because the Moulinette norms them too.
        provided_hdrs: headers the exercise compiles AGAINST but does not turn
            in -- staged from tests/ so our harness can build at all, while the
            Moulinette supplies its own copy (c-08's ft_stock_str.h). Identical
            to hdrs in every layer except one: they are NOT normed.

            The distinction is not cosmetic. A file the grade never looks at
            cannot fail the grade, so a red here would be a red that does not
            exist on the Moulinette -- the false-red class, which teaches
            students to distrust the suite. The test is simply whether the file
            is in deliverable/: if it is, it is `hdrs`; if it lives under
            tests/ because only we need it, it is `provided_hdrs`.
        deps: extra cc targets linked into the HARNESS binary. Five exercises
            need it -- c-12 ex01, ex04, ex05, ex16 and c-13 ex04 -- because
            their subject authorises calling the previous exercise's function,
            so the harness has to link that exercise's library as well as this
            one's. It reaches the harness and nothing else: the symbols,
            allocfail and ilp32 layers rebuild `srcs` on their own and know
            nothing about it.
        extra_includes: extra include directories, package-relative, added to
            the cc_library's `includes` and passed on to the prototype and
            ilp32 runners. c-08 ex04/ex05 pass ["tests"], because the provided
            ft_stock_str.h lives under tests/ rather than beside the
            deliverable and #include "ft_stock_str.h" would not otherwise
            resolve for the library and harness compiles.
        expected: the fixture the harness's stdout is compared against, a
            filename under tests/exNN/; defaults to "expected.txt". The same
            file is the correctness GATE for the valgrind and allocfail layers
            -- both SKIP while it is red, so a memory report never speaks over
            the top of a wrong answer -- and it is what the 32-bit rebuild is
            diffed against too.
        sanitize: the fixture is a hex dump whose leading 16-hex-digit address
            column cannot be compared literally, because ASLR moves it on every
            run. diff_output.sh then rewrites each address to its offset from
            the first row of its block, so what is compared is the column's
            WIDTH, its letter CASE and the +16 STEP rather than a value no test
            outside the process can know. Default False; c-02 ex12
            (ft_print_memory) is the only user. It is forwarded to the valgrind
            and allocfail gates and to the ilp32 replay, so all four layers
            read the fixture the same way.
        labeled: each line of the harness output and of the fixture is
            "CASE<TAB>VALUE", and the CASE is shown in its own column instead
            of the 1-based line number. Default False. Worth turning on
            wherever a reader has to tell the cases apart -- and it is what
            gives `clues` the case labels its hint groups are addressed to.
            Forwarded to the gates and to ilp32, like `sanitize`.
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
        allowed: the subject's "Allowed functions" line, copied as written --
            ["write"], ["malloc", "free"], or [] where the subject says
            "Authorized: None". forbidden_symbols.sh compiles each source alone
            and reads the functions it actually CALLS out of nm, so an
            unauthorised call fails here instead of on the Moulinette. What it
            forgives besides the list: a function this exercise's own sources
            define, and a short baseline of compiler-emitted builtins
            (memcpy/memmove/memset and friends), which code generation inserts
            rather than you. Mind the two spellings: [] emits the layer with an
            empty allowlist, while the default None emits NO forbidden layer at
            all, which is only right for an exercise whose subject fixes no
            such list.
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
            Default True. It rebuilds `test` + `srcs` with the hermetic zig
            Bazel fetches and links nothing else, so `deps` is not on that
            command line. Skips loudly where no 32-bit compiler can be found,
            and skips as well while the ordinary 64-bit fixture is still
            failing, so a red here always means the one thing this layer exists
            to say. NO_SKIP=1 runs it past that gate and turns the
            missing-compiler skip into a failure.
        allocfail: the name of a tests/exNN/ file, conventionally af_<fn>.c,
            defining af_case(), which makes ONE call into the deliverable. The
            layer then reruns it with each of its malloc calls refused in turn,
            and requires it to report the error rather than use the pointer
            (see tools/allocfail_check.sh). Default None. Setting it without
            malloc = True is a fail(): "sets allocfail but not malloc = True. A
            function that does not allocate has no allocation to refuse."

            DELIBERATELY OPT-IN, and the reason is the same one every c_files
            block records: pinning a behaviour the subject does not ask for
            invents a requirement. Across every C-Piscine subject, "return a
            NULL pointer if an error occurs" is stated exactly once, for c-08
            ex04. c-07's six allocating exercises ask for NULL on LOGICAL
            conditions (min >= max, an invalid base) and say nothing about
            allocation failure; c-11/c-12/c-13 say nothing at all. Quote the
            sentence at the call site when you turn this on; if you cannot find
            one to quote, that is the answer."""
    ex = "ex" + num
    hdrs = hdrs or []
    provided_hdrs = provided_hdrs or []
    deps = deps or []

    # Every layer below stages BOTH kinds -- a header the harness needs in order
    # to compile is needed whoever wrote it. The single place the two part
    # company is _norm_test, which sees `hdrs` alone: see the docstring.
    all_hdrs = hdrs + provided_hdrs
    if srcs == None:
        srcs = _deliverable_srcs(ex, fn)
    includes = ["deliverable/" + ex] + (extra_includes or [])

    cc_library(
        name = fn,
        srcs = srcs,
        hdrs = all_hdrs,
        includes = includes,
        copts = _COPTS,
    )

    # ASan/UBSan-instrumented twin of the student's library, linked into the
    # crash-fuzz variant of c_diff (built only when that test runs).
    cc_library(
        name = fn + "_asan",
        srcs = srcs,
        hdrs = all_hdrs,
        includes = includes,
        copts = _COPTS + _ASAN_COPTS,
        tags = ["manual"],
    )
    _norm_test(ex + "_norm", srcs + hdrs)

    # A provided header is still held to the Norm -- it is just not the
    # STUDENT's red. Separate target, separate name, and level 4 so it can never
    # appear in the `basic` suite a beginner runs or in the submit gate: what it
    # reports is "this repo's own staged header drifted", which is a maintainer's
    # job and nothing the person doing the exercise can act on.
    if provided_hdrs:
        _norm_test(ex + "_norm_provided", provided_hdrs, level = 4)

    _compile_tests(ex, srcs, all_hdrs)

    binname = ex + "_bin"
    test_f = "tests/%s/%s" % (ex, test)
    cc_binary(
        name = binname,
        srcs = [test_f],
        deps = [":" + fn] + deps,
        copts = _COPTS,
    )

    expected_f = "tests/%s/%s" % (ex, expected)
    out_data = [":" + binname, expected_f]
    args = [
        "--bin",
        "$(location :%s)" % binname,
        "--expected",
        "$(location %s)" % expected_f,
    ]
    if sanitize:
        args.append("--sanitize")
    if labeled:
        args.append("--labeled")
    # Hoisted out of the `if` so it is initialised on every path. It is only ever
    # USED when `clues` is set, but buildifier cannot see that the guard at the
    # ilp32 block below is the same condition, and reports it as possibly
    # uninitialised. A warning that is always noise teaches people to ignore
    # warnings, so the cheaper fix is to remove the ambiguity.
    clues_f = "tests/%s/%s" % (ex, clues) if clues else None
    if clues:
        args += ["--clues", "$(location %s)" % clues_f]
        out_data.append(clues_f)
    _test(
        name = ex + "_output",
        srcs = ["//tools:diff_output.sh"],
        args = args,
        data = out_data,
        tags = ["output"],
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
    if allocfail:
        if not malloc:
            fail(("c_function(num = \"%s\") sets allocfail but not malloc = True. " +
                  "A function that does not allocate has no allocation to refuse.") % num)
        af_f = "tests/%s/%s" % (ex, allocfail)
        af_args = [
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
        for s in srcs:
            af_args += ["--src", "$(location %s)" % s]
        for h in all_hdrs:
            af_args += ["--inc", "$(location %s)" % h]
        if sanitize:
            af_args.append("--gate-sanitize")
        if labeled:
            af_args.append("--gate-labeled")
        _test(
            name = ex + "_allocfail",
            srcs = ["//tools:allocfail_check.sh"],
            args = af_args,
            data = srcs + all_hdrs + [
                af_f,
                ":" + binname,
                expected_f,
                "//tools:allocfail_shim.c",
                "//tools:diff_output.sh",
            ],
            size = "small",
            tags = ["allocfail"],
        )

    if allowed != None:
        _forbidden_test(ex + "_forbidden", srcs, allowed, hdrs = all_hdrs)

    _prototype_test(ex, srcs, all_hdrs, extra_includes, prototype)

    # Linkage hygiene: exactly the subject's function is visible to the linker.
    if exports == None:
        exports = [fn]
    if exports:
        sym_args = ["--nm", "$(location @binutils_x86_64_linux_gnu//:usr/bin/x86_64-linux-gnu-nm)", "--expect", ",".join(exports)]
        for s in srcs:
            sym_args += ["--src", "$(location %s)" % s]
        for h in all_hdrs:
            sym_args += ["--inc", "$(location %s)" % h]
        _test(
            name = ex + "_symbols",
            srcs = ["//tools:symbols_test.sh"],
            args = sym_args,
            data = srcs + all_hdrs + ["@binutils_x86_64_linux_gnu//:usr/bin/x86_64-linux-gnu-nm"],
            tags = ["symbols"],
        )

    # The same cases replayed where long is no wider than int.
    if ilp32:
        i_args = [
            "--zig",
            "$(location @zig_linux_x86_64//:zig)",
            "--differ",
            "$(location //tools:diff_output.sh)",
            "--harness",
            "$(location %s)" % test_f,
            "--expected",
            "$(location %s)" % expected_f,
        ]
        for s in srcs:
            i_args += ["--src", "$(location %s)" % s]
        for h in all_hdrs:
            i_args += ["--inc", "$(location %s)" % h]
        for d in (extra_includes or []):
            i_args += ["--inc", d]
        if sanitize:
            i_args.append("--sanitize")
        if labeled:
            i_args.append("--labeled")
        i_data = [
            test_f,
            expected_f,
            "//tools:diff_output.sh",
            "@zig_linux_x86_64//:zig",
            "@zig_linux_x86_64//:sdk",
        ] + srcs + all_hdrs
        if clues:
            i_args += ["--clues", "$(location %s)" % clues_f]
            i_data.append(clues_f)
        _test(
            name = ex + "_ilp32",
            srcs = ["//tools:ilp32_test.sh"],
            args = i_args,
            data = i_data,
            tags = ["ilp32"],
        )

def c_mem_check(num, fn, probe, srcs = None, hdrs = None):
    """Memory-safety layer: compile the student's fn + a probe under ASan/UBSan and
    RUN it (tag "asan"). Catches out-of-bounds reads/writes past an n/size bound
    that still return the correct VALUE and so slip past stdout diffing.

    hdrs: headers the probe/source include but don't live beside them (e.g. a
    provided ft_stock_str.h under tests/); each is staged and its directory added

    Args:
        num: the exercise number as a two-character STRING, "00", "07", "12" --
            the same one the exercise's c_function() was given. It selects
            deliverable/exNN/ and tests/exNN/ and names the single target this
            macro emits, exNN_asan (tag "asan", so it lands at level `robust`).
        fn: the subject's function, used for ONE thing here: it is the fallback
            source name, deliverable/exNN/<fn>.c, for an exercise whose
            deliverable directory is still empty. It is not part of any target
            name -- exNN_asan is named from num alone -- so wherever the
            directory does have sources, which is everywhere but an
            unimplemented exercise, a typo in it changes nothing and shows
            nothing. Keep it identical to the c_function() call for the same
            num.
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
            Defaults to a GLOB of deliverable/exNN/*.c, falling back to
            deliverable/exNN/<fn>.c when that directory is empty. Override it
            when the probe cannot be built from one exercise's directory alone:
            c-12 ex05 names both deliverable/ex05/ft_list_push_strs.c and
            deliverable/ex00/ft_create_elem.c, because a real push_strs builds
            its nodes with ft_create_elem. There is no `deps` here to do that
            with -- the runner compiles a plain list of files with one host
            compiler, it does not link Bazel targets.
        hdrs: headers the probe or the sources include but which do not live
            beside them -- a provided ft_stock_str.h under tests/, or the
            sibling exercise's ft_list.h that the srcs override above dragged
            in. Each is staged as a data dependency and its DIRECTORY is added
            to -I; none of them is compiled. Defaults to none, which is right
            whenever every include resolves next to a file already named, since
            the probe's own directory and each source's directory are added to
            -I automatically. Unlike c_function's hdrs these are not
            norm-checked here; the norm layer for a turned-in header belongs to
            the c_function() call.
    to -I so the compile can resolve the #include."""
    ex = "ex" + num
    hdrs = hdrs or []
    if srcs == None:
        srcs = _deliverable_srcs(ex, fn)
    probe_f = "tests/%s/%s" % (ex, probe)

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
    for h in hdrs:
        args += ["--hdr", "$(location %s)" % h]
    _test(
        name = ex + "_asan",
        srcs = ["//tools:asan_check.sh"],
        args = args,
        data = srcs + [probe_f] + hdrs,
        tags = ["asan"],
    )

def c_diff(
        num,
        fn,
        harness,
        oracle_fn,
        seed = 1,
        count = 400000,
        asan_count = 200000,
        sanitize = True,
        deps = None,
        diff_clues = None,
        gate_bin = None,
        gate_expected = "expected.txt",
        gate_labeled = False,
        gate_sanitize = False,
        gate_stdin = None,
        perf = True,
        perf_count = 200000,
        size = "small"):
    """Live differential test (tag "diff").

    Diffs the student's function output against the Rust reference
    //oracle:oracle over a FIXED, seeded set of inputs. The reference emits
    `<hex-inputs>\\t<reference-output>` per case; a small reader harness
    (tests/exNN/<harness>) replays the same inputs through the student's fn and
    reprints `<hex-inputs>\\t<student-output>`; tools/rust_diff.sh byte-diffs the
    two. Reuses the cc_library the exercise's c_function already built (:fn).

    Deterministic: same seed+count => identical cases every run (no test-time
    entropy). Anti-copy: the reference lives in Rust under //oracle, compiled

    Args:
        num: the exercise number as a STRING -- "04", never 4. Every target and
            path here is built from "ex" + num, and Starlark does not add an int
            to a string, so a bare 4 is an immediate analysis-time type error;
            "4" is worse, because it builds an "ex4" that quietly matches no
            files. Only ONE c_diff can attach to a given exercise, because the
            target names it derives are fixed (:exNN_diffbin, :exNN_diff); c-09
            ex00 records that constraint at its call site, where ft_strlen was
            left to c-01's arm rather than fighting for the name.
        fn: the cc_library the harness links, by target name -- the one
            c_function already declared for this exercise. That is why this
            layer declares no deliverable sources of its own (only the harness
            under tests/) and so cannot drift from the file set c_function
            globbed. With sanitize on it also links :<fn>_asan, the instrumented
            twin c_function builds beside it. An exercise whose library is
            hand-written, like c-09 ex00 whose sources are archived by the
            student's own build script, has to declare both libraries by hand.
        harness: filename under tests/exNN/ of the READER: a small main() that
            takes the reference's cases on stdin, decodes the input fields (hex
            wherever the input is bytes), calls fn, and reprints "<the same
            input fields>\\t<student output>". tools/diffio.h is linked in
            automatically and holds the decode and print helpers. It is
            grader-side infrastructure and never a submission, so it may use
            libc freely and need not be norm-clean.
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
            value is right. Ignored when sanitize = False.
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
        deps: extra cc_library targets to link into the harness, for an exercise
            the subject lets build on an earlier one -- c-12 ex01 is authorised
            to use the ft_create_elem written for ex00 (see its `allowed` list),
            so its diff harness has to link :ft_create_elem too. The same list
            goes into both binaries, and note that the crash-fuzz build takes
            these deps UNINSTRUMENTED (only :fn gets an _asan twin here), so a
            stray write inside a dep's own code is not guaranteed to be
            reported.
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
            --sanitize normalises a leading 16-hex-digit address column to an
            offset from the first row of its block (the ft_print_memory shape),
            and that changes the VERDICT diff_output.sh reaches, not just its
            rendering. A mismatch makes the gate read a passing exercise as red,
            and this layer then skips forever while the suite looks green. Leave
            it False for a c_libft exercise: that shape has no sanitize flag and
            never passes --sanitize to its own output layer.
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
        size: Bazel test size for BOTH exNN_diff and exNN_diff_asan; default
            "small", i.e. a 60s timeout -- which is also what makes a runaway
            loop in a student's code fail fast instead of hanging. Standalone
            the slowest exercise is ~4.7s at 400k, but a full-suite run
            schedules dozens at once and contention inflated that ~3.2x when
            measured, so the headroom is real but finite: raise this to "medium"
            (300s) before pushing count much past 1M. c-05 ex04 does exactly
            that for a different reason -- the recursive answer that module
            teaches costs phi^n, and the layer must not fail a student for
            writing the intended solution. It does not reach the perf target,
            which is always "medium".
    hermetically by Bazel — no system rustc needed."""
    ex = "ex" + num
    deps = deps or []
    binname = ex + "_diffbin"
    cc_binary(
        name = binname,
        srcs = ["tests/%s/%s" % (ex, harness)],
        deps = [":" + fn, "//tools:diffio"] + deps,
        copts = _COPTS,
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
    if diff_clues:
        clues_f = "tests/%s/%s" % (ex, diff_clues)
        args += ["--clues", "$(location %s)" % clues_f]
        data.append(clues_f)

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
        )

    # Crash-fuzz variant (tag "diff_asan"): replay the corpus through an
    # ASan/UBSan-instrumented harness+student and assert no memory error / UB.
    # Value correctness is not checked here, so a memory-safe stub passes; this
    # catches out-of-bounds reads that return the right value on valid inputs.
    if sanitize:
        asan_bin = ex + "_diffbin_asan"
        cc_binary(
            name = asan_bin,
            srcs = ["tests/%s/%s" % (ex, harness)],
            deps = [":" + fn + "_asan", "//tools:diffio"] + deps,
            copts = _COPTS + _ASAN_COPTS,
            linkopts = _ASAN_LINKOPTS,
            # bfd (in _ASAN_LINKOPTS) rejects Bazel's gold/lld-only --start-lib
            # grouping, so drop that feature for these binaries. They have a
            # handful of deps, so plain archive linking is fine.
            features = ["-supports_start_end_lib"],
            tags = ["manual"],
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
            ] + gate_args,
            data = ["//oracle:oracle", ":" + asan_bin] + gate_data,
            size = size,
            tags = ["diff_asan"],
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
        deps = None):
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
    band where the code looks like it would stop finishing on a bigger input.

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
        fn: the exercise's function, e.g. "ft_is_prime". It names the cc_library
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
            SHAPE rather than throughput. A single size that does not finish
            within PERF_TIMEOUT (25s) is killed and fails the layer outright --
            an implementation that far off does not need a precise multiple
            attached to it.
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
            reaches -- it normalises a leading address column to an offset
            within its block, so an ASLR value can still be compared -- and a
            mismatch makes the gate misread a passing exercise as red, after
            which the layer skips forever while looking green. Leave it False
            for a c_libft exercise, which has no sanitize flag of its own.
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
        deps: extra cc_library targets to link into the reader binary. IGNORED
            unless harness is set, because with harness = None this macro builds
            no binary at all -- it reuses :exNN_diffbin, which already carries
            whatever deps its c_diff call declared.
    """
    ex = "ex" + num
    deps = deps or []
    tags = ["perf"] + ([] if enabled else ["manual"])

    # Reuse c_diff's reader binary when it exists; build our own only if this
    # exercise has a perf layer without a diff layer.
    if harness == None:
        binname = ex + "_diffbin"
    else:
        binname = ex + "_perfbin"
        cc_binary(
            name = binname,
            srcs = ["tests/%s/%s" % (ex, harness)],
            deps = [":" + fn, "//tools:diffio"] + deps,
            copts = _COPTS,
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

def c_program(
        num,
        name,
        cases = None,
        srcs = None,
        hdrs = None,
        progname = False,
        allowed = None,
        malloc = False,
        makefile = None,
        make_data = None):
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
        name: the conventional stem of the deliverable source. Unlike a rule's
            `name` it names no target -- every target comes from `num` -- and
            it is read ONLY when `srcs` is left at its default AND
            deliverable/exNN holds no .c file at all. Naming
            deliverable/exNN/<name>.c there keeps Bazel's error pointing at the
            deliverable nobody has written yet instead of at an empty source
            list.
        cases: the argv invocations to run, as a list of dicts. Default None
            emits no run at all, leaving the static layers and the two
            binaries; that is a real configuration rather than an oversight,
            since c-06 ex01-ex03 drive their runs from c_argv_table() instead,
            which picks :exNN_bin and :exNN_bin_asan up by name. Every case
            gets an output test and an ASan/UBSan run; with malloc = True it
            also gets a valgrind arm. Keys of one case dict:
                "name":     infix for this case's targets, default "run". With
                            a single case the targets take the plain exNN form
                            the rest of the repo uses (exNN_output, exNN_asan);
                            with several they become exNN_<name>_output.
                "expected": REQUIRED -- the expected-output file's name under
                            tests/exNN/ (a bare name, not a label). Nothing
                            checks for it, so leaving it out is a raw Starlark
                            key error at analysis rather than a message.
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
                "stream":   "stdout" (the default) or "stderr": which one is
                            compared. The other is still shown under the table
                            when the case fails, because it is usually where
                            the explanation is.
                "sanitize": normalise a leading 16-hex-digit address column to
                            its offset from the first row of its block, so an
                            ASLR-randomised pointer can still be compared for
                            width, case and step (hexdump-shaped output).
                "labeled":  every line is "CASE<TAB>VALUE" and the CASE gets a
                            column of its own; without it the CASE column is
                            just the 1-based line number.
                "clues":    name of a clues.tsv under tests/exNN/ whose hints
                            are rendered below the table when this case fails.
                            Reaches the output arm AND the valgrind arm; the
                            latter renders the hint column alone, capped at
                            three, because a leak report has no per-case table
                            to attach hints to.
                "exit":     also assert the exit status. Tested for presence,
                            not truth, so "exit": 0 really does pin "exits 0".
                "valgrind": default True; False drops the valgrind arm for this
                            one case. Read only when malloc = True.
            An unrecognised key is silently ignored -- there is no schema check
            here -- so a key borrowed from another macro's case dicts does
            nothing at all rather than failing.
        srcs: the deliverable's sources. Default None globs deliverable/exNN/*.c
            -- the file set is written down once, in this exercise's c_files()
            call, to be CHECKED against the directory rather than to drive the
            build -- and falls back to deliverable/exNN/<name>.c when the
            directory is empty. Pass a list only where the glob is wrong.
            Headers must NOT be routed through here: forbidden_symbols.sh
            compiles each --src and reads its symbols, and hands a .h back as
            exit 2, a harness error. That is what `hdrs` is for.
        hdrs: headers that belong to the deliverable, default []. They are
            staged into both cc_binary targets alongside the sources (cc_binary
            accepts headers in `srcs` and compiles only the .c files), so a
            deliverable that #includes its own header still builds for every
            layer that RUNS it. They also reach the static layers: the norm
            layer NORMS them beside the sources (the Norm applies to headers
            too), while the two compile layers and the forbidden layer only add
            their directory to the include path.
        progname: default False. True emits exNN_progname (tag "output", so it
            gates at level basic): the binary is copied under two names --
            "a.out", matching the subject's example, and one unrelated name --
            run as ./<name> each time, and must print exactly its own argv[0]
            plus a newline and exit 0 on both. The renamed run is the one that
            proves anything, since a program that hardcodes "./a.out" passes
            the first. It also emits exNN_progname_asan (tag "asan"), which
            runs the INSTRUMENTED binary once, bare -- no rename, no arguments,
            output not compared -- because argv[0] is where this exercise can
            walk off the end of a string it does not own, and a diff of one
            short line cannot see a read that returns the right bytes. c-06
            ex00 is the only caller.
        allowed: the functions the subject authorises, e.g. ["write"]. Default
            None emits no forbidden layer at all; [] means "nothing beyond the
            compiler's own builtins" and reaches the script as the "-"
            sentinel, because Bazel drops an empty-string argument. What is
            checked is each object's UNDEFINED symbols, so anything the
            deliverable itself defines is always fine.
        malloc: default False. True adds a valgrind arm per case
            (exNN[_case]_valgrind, tag "valgrind", level strict), each gated on
            that case's own output fixture so a stub is met with "your output
            layer is still red" rather than with a memcheck report. Set it
            where the subject authorises malloc; a program that cannot allocate
            has nothing to leak. It has no effect without `cases`, since the
            arms are emitted one per case.
        makefile: package-relative path to the deliverable's Makefile, for the
            modules whose subject mandates one and then leaves the filenames to
            the team. Default None keeps the ordinary path, where `srcs` is the
            program and Bazel links it directly.

            When set, the two binaries are built by asking `make -Bn` which .c
            files the default goal compiles (see _makefile_binaries), and `srcs`
            no longer has to BE the program -- it can stay a plain glob, because
            the layers it still feeds (norm, both compile layers, forbidden)
            compile each file on its own and never link, so a second entry point
            among them is not their problem. Requires make_data.
        make_data: the files to stage beside the Makefile, normally
            glob(["deliverable/exNN/*"]). Only read when `makefile` is set, and
            required then. The whole directory rather than the sources: a
            Makefile may include another file or read anything next to it.
    """
    ex = "ex" + num
    _no_orphan_prototype(ex, "c_program")
    hdrs = hdrs or []
    if srcs == None:
        srcs = _deliverable_srcs(ex, name)
    if makefile and not make_data:
        fail("c_program(%s): makefile needs make_data -- the Makefile cannot be " % ex +
             "staged on its own, since it may include or read anything beside it.")

    binname = ex + "_bin"
    # srcs + hdrs, not srcs. cc_binary sandboxes its compile and stages only what
    # it is given, so a deliverable that #includes its own header fails to build
    # here with "file not found" — while _norm_test, _compile_tests and
    # _forbidden_test all stage `hdrs` correctly and stay green. The result is a
    # module where norm and both compile layers pass and every layer that RUNS
    # the program is red, which reads as a harness bug rather than a missing
    # input. cc_binary accepts headers in `srcs` and compiles only the .c files,
    # so this is safe; the header must NOT be pushed through this macro's own
    # `srcs` parameter, because forbidden_symbols.sh would then try to read
    # symbols out of a .h and exit 2 as a harness error.
    if makefile:
        binname, makefile_asan_bin = _makefile_binaries(
            ex,
            makefile,
            make_data,
            _COPTS,
            _COPTS + _ASAN_COPTS,
            _ASAN_LINKOPTS,
        )
    else:
        makefile_asan_bin = None
        cc_binary(
            name = binname,
            srcs = srcs + hdrs,
            copts = _COPTS,
        )
    _norm_test(ex + "_norm", srcs + hdrs)
    _compile_tests(ex, srcs, hdrs)

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
    # Memory layer for the program shape. c_function exercises get three (the
    # _asan twin, c_mem_check, diff_asan); c_program got NONE, leaving c-06,
    # c-10 and c-11 ex05 — twelve exercises that read files, walk argv and index
    # buffers — never built with a sanitizer at all. valgrind only covers the
    # ones that malloc, and stdout diffing structurally cannot see an
    # out-of-bounds read that returns the right bytes.
    #
    # The instrumented binary is built UNCONDITIONALLY, outside the `if cases`
    # below. It used to sit inside it, which quietly excluded the exact module
    # the comment above names as the reason the layer exists: c-06 ex01-ex03
    # drive their runs from c_argv_table, not from `cases`, so they passed no
    # cases and got no sanitizer at all. c_argv_table picks this target up by
    # name for its own asan arm — an absent one there is a hard analysis error,
    # not a silent skip.
    asan_bin = ex + "_bin_asan"
    if makefile_asan_bin == None:
        cc_binary(
            name = asan_bin,
            srcs = srcs + hdrs,
            copts = _COPTS + _ASAN_COPTS,
            linkopts = _ASAN_LINKOPTS,
            features = ["-supports_start_end_lib"],
            tags = ["manual"],
        )

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
            ],
            data = [":" + asan_bin],
            tags = ["asan"],
        )

    if cases:
        _emit_cases(ex, binname, cases, valgrind = malloc)

        for c in cases:
            cname = c.get("name", "run")
            stem = _case_stem(ex, cases, cname)
            a_args = [
                "--bin",
                "$(location :%s)" % asan_bin,
                "--label",
                stem,
            ]
            a_data = [":" + asan_bin] + c.get("fixtures", [])
            if c.get("stdin"):
                a_args += ["--stdin", "$(location %s)" % c["stdin"]]
                a_data.append(c["stdin"])
            a_args += ["--"] + c.get("args", [])
            _test(
                name = "%s_asan" % stem,
                srcs = ["//tools:asan_run.sh"],
                args = a_args,
                data = a_data,
                tags = ["asan"],
            )
    if allowed != None:
        _forbidden_test(ex + "_forbidden", srcs, allowed, hdrs = hdrs)

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
_BUILD_PRODUCTS = ["*.o", "*.a", "*.out"]

def _not_build_products(d):
    """Glob exclude patterns for build output under directory `d`."""

    # `**/` matches zero or more segments, so this covers both d/x.o and
    # d/srcs/x.o -- c-09 ex01 keeps its sources in a subdirectory.
    return [d + "/**/" + p for p in _BUILD_PRODUCTS]

def c_files(num, required, optional = None, strict = False, subdir = None, label = None):
    """Deliverable file-set check (tag "files").

    The Moulinette looks at WHICH FILES were turned in before it looks at what
    they do. Nothing else here can see that: a missing required file is a Bazel
    ANALYSIS error today (a label-not-found wall of text, not a test result),
    and an extra file is invisible entirely — while //tools:submit still pushes
    it to Vogsphere.

    This paragraph used to be copied above fifteen of the c_files() calls in
    the repo. It is stated once, here; a module's own call site says only what
    is TRUE OF THAT MODULE -- rush-01's `required` is empty because its subject
    names no file at all, and that is worth a sentence where it happens.

    Missing a required file FAILS; an extra file WARNS and still passes. Those
    are different situations: the subject names its files exactly, so a missing
    one is not arguable, whereas an extra one is often defensible (the Norm bans
    declaring a struct in a .c file, so a rush that wants one needs a header the
    subject never mentions). Pass strict = True where a subject really forbids
    extras. `optional` silences the warning for a file you have already decided
    to keep.

    The actual file list comes from native.glob, which sees the real directory
    at analysis time — a test sandbox only ever contains files that were already
    declared, which is precisely the blind spot this closes.

    Args:
        num: the exercise number as a two-digit string ("00"). It names the
            target (exNN_files) -- including when `subdir` sends the check at
            another directory -- and, unless `subdir` overrides it, selects the
            directory deliverable/exNN whose real contents are globbed at
            analysis time.
        required: the file names the subject's "Files to turn in" line asks
            for, e.g. ["ft_putchar.c"]. Bare names, compared against the
            basenames found in the directory -- a path here would never match.
            A missing one FAILS the test, which is the whole point: without
            this layer it is a Bazel analysis error somewhere else, or nothing
            at all. [] is legitimate where the subject fixes no name (see
            rush-01, which requires nothing and lists its globbed sources as
            `optional` instead).
        optional: names that may be present without being reported as extra,
            default []. For a file you have already decided to keep, or for a
            subject that leaves its source names free: rush-01 passes the
            basenames of the very globs its build uses, so any file that is NOT
            one of its sources -- the rush01 binary a hand-run cc leaves in the
            directory, say -- is still reported. Directories never appear:
            native.glob excludes them by default, so c-09 ex01's srcs/ and
            includes/ are invisible to this layer with or without them here.
        strict: default False -- an extra file WARNS and the test still passes.
            The asymmetry is deliberate: the subject names its files exactly,
            so a missing one is not arguable, while an extra one often is (the
            Norm bans declaring a struct in a .c file, so a rush that wants one
            needs a header the subject never mentions) and a human reviews it.
            True where a subject really does forbid extras, which is nearly
            every c_files call in the repo. Build products (*.o, *.a, *.out)
            are excluded from the glob before any of this, so having run `make`
            in deliverable/ cannot fail you for producing what the exercise
            asked for.
        subdir: the directory to check, relative to the package; default None
            means deliverable/exNN. Whatever it names is globbed FLAT (one
            level, files only), with build products excluded at any depth, and
            it also feeds the default `label`. No module needs it today.
        label: the heading the report is printed under; default None builds
            "<package>/<dir>", e.g. c-piscine-c-00/deliverable/ex00. fail()s if
            a label is given and contains a space: sh_test tokenises `args` on
            whitespace, so a two-word label would arrive as two arguments and
            the runner would reject the second as an unknown option. Failing
            here names the cause instead.
    """
    ex = "ex" + num
    optional = optional or []
    d = subdir or ("deliverable/" + ex)
    actual = native.glob([d + "/*"], exclude = _not_build_products(d), allow_empty = True)

    # sh_test args are shell-tokenised, so a label containing a space silently
    # becomes two arguments and the script rejects the second as an unknown
    # option. Catch it here, where the error names the cause.
    if label and " " in label:
        fail("c_files: label must not contain spaces (sh_test tokenises args): %r" % label)

    args = ["--label", label or (native.package_name() + "/" + d)]
    for f in required:
        args += ["--required", f]
    for f in optional:
        args += ["--optional", f]
    for f in actual:
        args += ["--actual", "$(location %s)" % f]
    if strict:
        args.append("--strict")

    _test(
        name = ex + "_files",
        srcs = ["//tools:files_test.sh"],
        args = args,
        data = actual,
        tags = ["files"],
    )

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
        count = 3000,
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
        fn: the student's function, by name, doing two jobs. It is the symbol
            asked of callgrind_annotate -- INCLUSIVELY, so the figure covers
            everything that function calls and nothing the harness does around
            it -- and it is the file name `srcs` falls back to when the
            deliverable directory is empty. A symbol the profile does not carry
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
            is `cc harness srcs` and nothing else -- there is no `deps` to pass,
            so a harness that needs another exercise's object (as c-12's diff
            harnesses do) cannot be measured by this layer.
        unit_expr: an awk expression over ONE tab-separated corpus line, summed
            across the corpus to give the denominator of the per-unit figure.
            Default None means one unit per case, i.e. a per-call number, which
            is the figure the paragraph above says has nothing to be read
            against -- so most callers set it. Corpus fields are hex-encoded
            (tools/diffio.h decodes them), so the byte count of an input is
            length($1)/2 and not length($1). Write ordinary awk: the macro
            doubles the $ for you, since Bazel expands `args` for Make
            variables, where a bare $1 is an error. fail()s if it contains a
            space -- sh_test splits `args` on whitespace and the tail would
            arrive as an unknown option -- and awk never needs one:
            ($1>3?sqrt($1):1). A sum that comes out zero or unparseable falls
            back to the case count rather than dividing by zero.
        unit_name: what one unit IS, singular, as printed in "per byte" / "per
            digit" and in the closing advice. Default "case", which is exactly
            what a missing unit_expr measures. fail()s on a space, same
            tokenisation reason as unit_expr.
        budget: instructions per unit that a good implementation achieves.
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
            test. One write() per string is the floor for a function whose job
            IS output -- see c-02 ex11's call site, where a 0 copied from the
            pure-transform targets beside it said something false with
            confidence.
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
        count: how many corpus cases to profile. Default 3000, and small on
            purpose -- callgrind runs ~90x slower than native, and instruction
            counts are deterministic, so a larger corpus buys no precision and
            only test time. (The test is declared "medium" for the same
            reason.)
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
    ex = "ex" + num
    # sh_test tokenises args on spaces, so a two-word unit name silently becomes
    # two arguments and the script rejects the second. Catch it where the error
    # names the cause. (c_files learned this the same way.)
    if " " in unit_name:
        fail("c_cycles: unit_name must be a single word (sh_test tokenises args): %r" % unit_name)
    if unit_expr and " " in unit_expr:
        fail("c_cycles: unit_expr must contain no spaces (sh_test tokenises args). " +
             "awk does not need them: write ($1>3?sqrt($1):1). Got: %r" % unit_expr)
    if srcs == None:
        srcs = _deliverable_srcs(ex, fn)
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
    if unit_expr:
        # Bazel runs `args` through Make-variable expansion, where a bare $1 is
        # an error. Escape it here so a caller can write ordinary awk ($1, $2)
        # rather than having to know that.
        args += ["--unit-expr", unit_expr.replace("$", "$$")]
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
        args = args + _valgrind_args(tool = _VG_CALLGRIND, annotate = True),
        data = _valgrind_data(tool = _VG_CALLGRIND, annotate = True) + [
            "//oracle:oracle",
            "//tools:diff_output.sh",
            "//tools:diffio.h",
            harness_f,
            expected_f,
            ":%s_bin" % ex,
        ] + srcs + extra_data,
        # callgrind is ~90x slower than native; 3000 cases keeps it a few
        # seconds. Instruction counts are deterministic, so more cases would
        # buy nothing.
        size = "medium",
        tags = ["cycles"],
    )

def c_reference_cost(
        num,
        fn,
        oracle_fn,
        harness,
        units,
        unit_name = "solution",
        kind = "search",
        srcs = None):
    """Instructions per unit of work, beside an optimised reference's (tag "cycles").

    INFORMATIVE ONLY: this layer can never fail on what it measures.

    c_cycles reads a per-unit figure against a BUDGET — a number written into
    the BUILD file. That works where the floor is arguable from first
    principles: a byte scan is a load, a compare and an increment, so "3.2 per
    byte" reads itself. It does not work for a search. Nobody can say from first
    principles what one of the 724 ten-queens boards ought to cost, so a budget
    there would be a number someone invented and then defended as physics — and
    this repo would rather print nothing than print a figure a student cannot
    tell is wrong (see the note at the foot of c-piscine-c-05/BUILD.bazel, where
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

    Gate wiring is derived, not parameterised: :exNN_bin and
    tests/exNN/expected.txt, the very targets c_function already declares. There
    are deliberately no gate_labeled / gate_sanitize / gate_stdin knobs — the one
    caller needs none of them, and a pass-through nobody has ever run is how a
    gate ends up silently misreading a passing exercise as red and skipping
    forever. Add them WITH a caller that exercises them.
    """
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
        srcs = _deliverable_srcs(ex, fn)
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

    _test(
        name = ex + "_refcost",
        srcs = ["//tools:ref_compare.sh"],
        args = args + _valgrind_args(tool = _VG_CALLGRIND, annotate = True),
        data = _valgrind_data(tool = _VG_CALLGRIND, annotate = True) + [
            "//oracle:oracle",
            "//tools:diff_output.sh",
            harness_f,
            expected_f,
            ":%s_bin" % ex,
        ] + srcs,
        # Two callgrind runs (student and reference) plus an -O2 compile of the
        # student's side. callgrind is ~90x slower than native, and the searches
        # themselves are tens of millions of instructions, so this is seconds —
        # but "medium" (300s) is what c_cycles uses for the same tool and there
        # is no reason to be tighter than the layer it shares a tag with.
        size = "medium",
        tags = ["cycles"],
    )

def c_argv_table(num, scenarios = "scenarios.tsv", expected = "table.txt", clues = "clues.tsv", asan = True):
    """One labelled table for an argv program run against many invocations.

    Emits exNN_output (tag "output"), driven by //tools:argv_table.sh: the
    program is run once per row of tests/exNN/<scenarios> and every run becomes
    one row of a single "invocation -> output" PASS/FAIL table, rather than one
    opaque sh_test per invocation.

    Pairs with c_program(num, name, allowed = [...]) and no `cases`, which still
    builds :exNN_bin plus the norm/compile/forbidden layers.

    asan: replay the same scenarios against c_program's instrumented binary
      (tag "asan", so it runs from level `robust` up). These exercises index and
      swap the pointers in argv, and an out-of-bounds read there returns bytes
      that are usually still the RIGHT bytes — so the table above is
      structurally unable to see it. Together with the crash detection in
      argv_table.sh this closes the gap that left c-06 ex01-ex03 with no memory
      checking of any kind.

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
            instrumented binary (tag "asan", so it runs from level robust up).
            These exercises index and swap the pointers in argv, where an
            out-of-bounds read returns bytes that are usually still the RIGHT
            bytes, so the table above is structurally unable to see it. The
            replay runs with --memory-only: the verdict is survival, not bytes,
            since a wrong table is the output test's finding and reporting it
            twice for one unwritten function teaches nothing the second time.
    """
    ex = "ex" + num
    scen_f = "tests/%s/%s" % (ex, scenarios)
    exp_f = "tests/%s/%s" % (ex, expected)
    clues_f = "tests/%s/%s" % (ex, clues)

    def _table_test(name, binlabel, tag, memory_only = False):
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
            ],
            tags = [tag],
        )

    _table_test(ex + "_output", ":%s_bin" % ex, "output")
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

def c_libft(
        num,
        srcs,
        test,
        anchor,
        artifact = "libft.a",
        symbols = None,
        script = None,
        hdrs = None,
        includes = None,
        expected = "expected.txt",
        clues = "clues.tsv",
        allowed = None,
        exports = None,
        prototype = True,
        labeled = False):
    """A libft bundle (c-09): several loose sources, built into an archive by a
    build system the student writes, PLUS the behaviour of those sources.

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
    the two exercises with the STRONGEST claim on them: c-09 ex00/ex01 are the
    ones whose sources are archived and linked against an evaluator's unseen
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
            :exNN_bin those layers run, and the tests/exNN/ directory the
            fixtures are read from.
        srcs: the loose sources the student turns in, listed explicitly rather
            than globbed. Globbing is what _deliverable_srcs() does for the
            other C shapes and it would not serve here: that glob is
            deliberately flat, and c-09 ex01 keeps its five sources under a
            srcs/ subdirectory. They are compiled DIRECTLY into :exNN_bin
            together with `test` -- not taken out of the archive, which is
            exNN_build's business -- so the behaviour layers keep working while
            the student's build system does not.
        test: a main() under tests/exNN/ exercising all of `srcs`, compiled
            with them into :exNN_bin, whose stdout the exNN_output layer diffs.
            The file name is yours (c-09 spells it test_libft.c in both
            exercises); what convention fixes is the TARGET it lands in --
            c_perf and c_cycles reach for :exNN_bin without being told, so a
            shape that named its binary differently would opt out of them.
        anchor: a LABEL of any file inside this exercise's deliverable
            directory -- in practice the Makefile or the creator script itself.
            make_test.sh takes its DIRECTORY as the subtree it stages into a
            writable scratch copy and builds there, because Bazel runfiles are
            read-only.
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
            no meaning for a script; that is why the c_make call in the body
            can ask for graph checks unconditionally.
        hdrs: headers turned in beside the sources -- c-09 ex01's
            includes/ft.h. Not merely staged: they are normed with the sources,
            compiled into :exNN_bin, and their directory joins the include path
            of the compile, forbidden, prototype and symbols layers, so a
            header that breaks the Norm or contradicts a signature is caught
            like any other deliverable.
        includes: extra include directories, package-relative, put on the
            cc_binary and passed on to the prototype layer. c-09 ex01 needs
            "deliverable/ex01/includes" so that a source in srcs/ can
            #include "ft.h" from its sibling directory.
        expected: the expected-output file under tests/exNN/, default
            "expected.txt", diffed against what :exNN_bin prints.
        clues: the exercise's hint file under tests/exNN/, default "clues.tsv",
            which diff_output.sh renders under the failure table. Unlike
            c_function's, it is NOT opt-in -- the flag is always passed, so the
            file must exist or the target will not analyse. Both c-09 exercises
            have one; a new caller owes its students the same.
        allowed: the libc functions this subject authorises, e.g. ["write"].
            Default None emits no forbidden layer at all; [] means "nothing
            beyond the compiler's own builtins". The bundled functions are the
            same ones the earlier modules restrict, so the restriction carries
            over -- c-09's call site records what a printf in the archived copy
            used to cost: green locally, KO on the Moulinette.
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
            of numbering the rows. Default False, which is what c-09's two
            fixtures are written for.
    """
    ex = "ex" + num
    hdrs = hdrs or []
    includes = includes or []

    # graph = True is c-09's, and only c-09's. Its ex01 subject is the one that
    # says "your Makefile should not run any unnecessary commands", "should not
    # compile any file unnecessarily" and ".o files should be near their
    # corresponding .c files" -- three bullets no other module's subject makes.
    # This used to be inferred inside make_test.sh from the exercise having more
    # than one .c, which selected c-09 only by the accident that c-10's
    # exercises have one source each; stating it here is what that script's own
    # comment asked for. The --script arm (ex00) is skipped by make_test.sh
    # anyway, so passing it for both c_libft calls is harmless and honest.
    c_make(
        num = num,
        anchor = anchor,
        artifact = artifact,
        symbols = symbols,
        script = script,
        graph = True,
    )

    _norm_test(ex + "_norm", srcs + hdrs)
    _compile_tests(ex, srcs, hdrs)

    binname = ex + "_bin"
    test_f = "tests/%s/%s" % (ex, test)
    cc_binary(
        name = binname,
        srcs = [test_f] + srcs + hdrs,
        includes = includes,
        copts = _COPTS,
    )

    expected_f = "tests/%s/%s" % (ex, expected)
    clues_f = "tests/%s/%s" % (ex, clues)
    args = [
        "--bin",
        "$(location :%s)" % binname,
        "--expected",
        "$(location %s)" % expected_f,
        "--clues",
        "$(location %s)" % clues_f,
    ]
    if labeled:
        args.append("--labeled")
    _test(
        name = ex + "_output",
        srcs = ["//tools:diff_output.sh"],
        args = args,
        data = [":" + binname, expected_f, clues_f],
        tags = ["output"],
    )

    if allowed != None:
        _forbidden_test(ex + "_forbidden", srcs, allowed, hdrs = hdrs)

    _prototype_test(ex, srcs, hdrs, includes, prototype)

    # Export set, not merely presence. `symbols` is what c_make greps nm for and
    # is the subject's REQUIRED list; the same list is the permitted list here,
    # so an extra non-static helper is caught rather than tolerated.
    if exports == None:
        exports = symbols
    if exports:
        _symbols_test(ex + "_symbols", srcs, exports, hdrs = hdrs)

def c_header(num, hdr, main, extra_srcs = None, cases = None, norm_flags = None, probe = None):
    """A header-only exercise (c-08): norm the .h, compile a main that uses it.

    Args:
        num: exercise number as a string, "00" not 0. Besides naming the
            targets and the tests/exNN/ directory, it is what
            _no_orphan_prototype() looks under: a tests/exNN/prototype.h beside
            a header exercise is an analysis-time failure, because this shape
            has no prototype layer that could read it -- the deliverable IS the
            declarations, so there is nothing for a contract header to check
            them against.
        hdr: the header the student turns in, as a file name under
            deliverable/exNN/. It is the entire deliverable: the only file the
            norm layer reads, the -I every test main compiles against, and
            (with `probe`) the header whose macros the forbidden layer expands.
        main: a test main() under tests/exNN/ that uses everything the subject
            says this header must declare. It is compiled AT TEST TIME by
            header_check.sh rather than by a cc_binary, so that an unwritten
            header shows up as a red test carrying the compiler's diagnostics
            and this exercise's clues, instead of aborting the whole build --
            the comment in the body says why at length. Every case that does
            not name a main of its own uses this one.
        extra_srcs: further .c files under tests/exNN/, compiled into each
            case's binary beside the main. Harness-side helpers, never
            deliverables -- the norm layer reads `hdr` and nothing else, so
            these are not normed. Nothing in the repo needs one today. Default
            None. They do join the compile layers, and their directories join
            the include path, like every other source these runners are handed.
        cases: the runs to emit, as a list of dicts. Default None means one
            case, {"name": "compile", "expected": "expected.txt", "args": []},
            which compiles `main` against the header and diffs what it prints.
            Recognised keys:
              "expected"  (required) the file under tests/exNN/ to diff
                          against; leaving it out is a Starlark key error.
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
                          a stdout diff. Use it only where a value is actually
                          required of the header: it makes a claim about the
                          exercise's contract, so quote the source at the call
                          site or say plainly whose decision it is. 0 is a
                          legitimate value here, so the test is `!= None`, not
                          truthiness.
            Keys _emit_cases() understands and this macro does not -- "stream",
            "stdin", "fixtures", "sanitize", "valgrind" -- are ignored in
            silence, so do not copy a c_program case dict across.
        norm_flags: extra tokens spliced in ahead of the file list when the
            norm layer runs, as separate list items because sh_test splits
            `args` on whitespace: ["-R", "CheckDefine"], not
            ["-R CheckDefine"]. Default None. -R CheckForbiddenSourceHeader is
            always passed by the runner and is not yours to add. c-08 ex01 and
            ex02 need CheckDefine because their subject mandates it: those
            headers define function-like macros (EVEN, ABS), which the Norm
            otherwise refuses.
        probe: a tests/exNN/probe_*.c that expands this header's macro once and
            calls nothing else, which gives the `forbidden` layer an object
            file to inspect -- with an empty allowlist, since c-08's subject
            says "Allowed functions: None" for every exercise here. A macro
            leaves no trace in a header until something expands it, so without
            a probe there is nothing for nm to read and the layer cannot exist;
            that is how a header whose ABS expands into a libc call could pass
            all thirteen of ex02's checks and still be a KO. Only for headers
            with a CALLABLE surface: ex00 is prototypes and ex03 a lone typedef,
            so neither can reach a libc function in the first place.
    """
    ex = "ex" + num
    _no_orphan_prototype(ex, "c_header")
    extra_srcs = extra_srcs or []
    hdr_f = "deliverable/%s/%s" % (ex, hdr)
    _norm_test(ex + "_norm", [hdr_f], norm_flags = norm_flags)

    # c-08's subject says "Allowed functions: None" for every exercise here, so
    # the allowlist is empty and any undefined symbol at all is the finding. This
    # is the same _forbidden_test every other module gets, on the same runner,
    # reading the same nm output -- the probe is the only thing that differs,
    # because the deliverable is a header rather than a .c.
    if probe:
        probe_f = "tests/%s/%s" % (ex, probe)
        _forbidden_test(ex + "_forbidden", [probe_f], allowed = [], hdrs = [hdr_f])

    main_f = "tests/%s/%s" % (ex, main)
    extra_f = ["tests/%s/%s" % (ex, s) for s in extra_srcs]

    # Every main any case drives has to compile, not just the default one.
    case_mains = []
    for c in (cases or []):
        if c.get("main") and c["main"] != main:
            m = "tests/%s/%s" % (ex, c["main"])
            if m not in case_mains:
                case_mains.append(m)
    _compile_tests(ex, [main_f] + extra_f + case_mains, hdrs = [hdr_f])

    # No cc_binary here, deliberately. For a header exercise the header IS the
    # answer, so an unwritten one does not compile — and a cc_binary that does
    # not compile is a Bazel BUILD failure, not a test result: a wall of clang
    # diagnostics about tests/exNN/test_*.c (a file the student never wrote), no
    # table, no hint, and `bazel test //...` aborting with FAILED TO BUILD
    # instead of showing a red test beside the others. Every other stub in this
    # repo produces a legible red test; compiling inside the runner makes this
    # shape behave the same way. (tools/ilp32_test.sh does this for the same
    # reason: keep a compile that is expected to fail out of the build graph.)
    if cases == None:
        cases = [{"name": "compile", "expected": "expected.txt", "args": []}]
    for c in cases:
        cname = c.get("name", "run")
        stem = _case_stem(ex, cases, cname)
        expected_f = "tests/%s/%s" % (ex, c["expected"])
        case_main_f = "tests/%s/%s" % (ex, c["main"]) if c.get("main") else main_f
        args = [
            "--differ",
            "$(location //tools:diff_output.sh)",
            "--hdr",
            "$(location %s)" % hdr_f,
            "--main",
            "$(location %s)" % case_main_f,
            "--expected",
            "$(location %s)" % expected_f,
        ]
        data = [
            "//tools:diff_output.sh",
            hdr_f,
            case_main_f,
            expected_f,
        ] + extra_f
        for s in extra_f:
            args += ["--src", "$(location %s)" % s]
        if c.get("labeled"):
            args.append("--labeled")
        if c.get("exit") != None:
            args += ["--exit", str(c["exit"])]
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
            tags = ["output"],
            level = c.get("level"),
        )

def c_make(num, anchor, artifact, symbols = None, script = None, rules = None, graph = False, relink = False):
    """A build-system exercise: run make/script, assert the artifact + symbols.

    rules: which make rules THIS subject mandates, e.g. ["clean", "fclean"].
        Left unset, make_test.sh's own default of clean/fclean/re applies.

        PASS THE SUBJECT'S LIST, and read it from the subject rather than from
        a neighbouring module: `re` and `all` are the two that differ. Demanding
        a rule the subject never names reds a correct Makefile at level basic,
        which gates submit -- the same "do not invent a requirement" rule every
        c_files block follows.

        (This paragraph used to say the default "is what c-10 and c-09 want".
        Neither was true: c-10 passes an explicit list without `re`, and c-09
        has no c_make call at all. A docstring that keeps a census of its own
        callers is a docstring that goes stale -- state the rule, not the roll
        call.)
        [] IS NOT None HERE. An empty list means "this subject mandates no
        rule at all", which c-piscine-bsq is: it asks only that the Makefile
        compiles the project and does not relink. None means "no opinion, take
        the default". Collapsing the two -- which `if rules:` did -- silently
        handed bsq clean/fclean/re and would have failed a conformant Makefile
        on three rules its subject never mentions.
    graph: run the incremental-build checks (no unnecessary work, .o placement).
        Only c-09 ex01's subject asks for those; see make_test.sh's gate comment.
    relink: run the no-unnecessary-work check ALONE, worded for a subject that
        says "must not relink" and says nothing about where objects land. graph
        implies it, so pass one or the other, never both.
    """
    ex = "ex" + num
    symbols = symbols or []
    args = ["--nm", "$(location @binutils_x86_64_linux_gnu//:usr/bin/x86_64-linux-gnu-nm)",
            "--make", "$(location %s)" % _MAKE,
            "--anchor", "$(location %s)" % anchor, "--artifact", artifact]
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
    _test(
        name = ex + "_build",
        srcs = ["//tools:make_test.sh"],
        args = args,
        # Build PRODUCTS are excluded so this test's inputs cannot include what
        # the test is supposed to produce. Running make (or the creator script)
        # by hand leaves libft.a and *.o in deliverable/; .gitignore keeps them
        # out of git but not out of native.glob, and a test whose result depends
        # on untracked files is not a test. make_test.sh also rm -f's the
        # artifact before building, which closes the same hole from the other
        # side.
        data = native.glob(
            ["deliverable/%s/**" % ex],
            exclude = _not_build_products("deliverable/%s" % ex),
        ) + ["@binutils_x86_64_linux_gnu//:usr/bin/x86_64-linux-gnu-nm", _MAKE],
        size = "small",
        tags = ["output"],
    )

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
        tags = None):
    """A shell-piscine exercise.

    The student's answer is the generator script generators/exNN.sh, which creates
    the exercise's deliverable(s) in its current directory. We run it in a scratch
    dir and validate the result (see tools/shell_test.sh).

    Emits:
      exNN_norm    syntax-check the generator (sh -n [+ shellcheck]); green on a stub.
      exNN_output  run the generator, then either diff the deliverable against
                   tests/exNN/<expected> (mode="diff") or run tests/exNN/<check>
                   (mode="check").

    Args:
      num: exercise number, e.g. "00".
      mode: "diff" or "check".
      deliverable: produced filename (required for "diff"; the check globs it itself
        for awkward names so it is optional for "check").
      expected: diff mode expected-output file under tests/exNN/.
      check: check mode property script under tests/exNN/.
      run: diff mode — execute the deliverable and diff its stdout (else cat it).
      interp: run the deliverable via this interpreter (sh/bash) instead of ./name.
      env: list of "K=V" controlled environment entries.
      fixtures: list of file labels staged into the scratch dir before running.
      tags: extra tags (e.g. ["manual", "env"] for host-coupled exercises).
    """
    ex = "ex" + num
    gen = "generators/%s.sh" % ex
    env = env or []
    fixtures = fixtures or []
    extra_tags = tags or []

    _test(
        name = ex + "_norm",
        srcs = ["//tools:shell_test.sh"],
        args = [
            "--generator",
            "$(location %s)" % gen,
            "--mode",
            "norm",
            "--diff",
            "$(location %s)" % _DIFF,
            "--shellcheck",
            "$(location %s)" % _SHELLCHECK,
        ],
        data = [gen, _DIFF, _SHELLCHECK],
        tags = ["norm"],
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
        expected_f = "tests/%s/%s" % (ex, expected)
        args += ["--expected", "$(location %s)" % expected_f]
        data.append(expected_f)
        if run:
            args.append("--run")
        if interp:
            args += ["--interp", interp]
    elif mode == "check":
        check_f = "tests/%s/%s" % (ex, check)
        args += ["--check", "$(location %s)" % check_f]
        data.append(check_f)
        # the shell_check.sh library lets check scripts emit a PASS/FAIL checklist
        args += ["--check-lib", "$(location //tools:shell_check.sh)"]
        data.append("//tools:shell_check.sh")
    else:
        fail("shell_exercise: mode must be 'diff' or 'check', got %r" % mode)

    # optional per-exercise foothold hint (shown on failure), if a clues.tsv exists
    clues_glob = native.glob(["tests/%s/clues.tsv" % ex], allow_empty = True)
    if clues_glob:
        args += ["--clues", "$(location %s)" % clues_glob[0]]
        data += clues_glob

    _test(
        name = ex + "_output",
        srcs = ["//tools:shell_test.sh"],
        args = args,
        data = data,
        tags = ["output"] + extra_tags,
    )

# ---------------------------------------------------------------- rush (group project)
#
# The Rush is shaped unlike the other modules, so it gets its own pair of macros
# instead of bending c_function:
#
#   * one exercise, SEVEN deliverable files: main.c, ft_putchar.c and
#     rush00.c..rush04.c. The five rush files each define the SAME `rush`
#     symbol — five different drawings of the same rectangle — so they can never
#     share a library or a binary. Every layer is emitted once PER VARIANT, with
#     a variant-qualified target prefix (ex00_rush03_output, …).
#   * a team owes exactly ONE variant (team leader's initial mod 5); the other
#     four are bonus. Tests for a variant that is not in the BUILD file's
#     ASSIGNED list are tagged "manual", which keeps them out of
#     `bazel test //...` AND out of the submit gate's
#     `bazel test //MOD/... --test_tag_filters=-manual`, so four unimplemented
#     stubs cannot block a push. Run one anyway with its per-variant suite:
#     `bazel test //c-piscine-rush-00:ex00_rush03`.
#   * main.c belongs to the student and is REPLACED at the defense, so nothing
#     diffs its output: the harnesses call rush() themselves, and main.c only
#     has to compile, link with the other two files, run and print something.

# The five interchangeable drawings the subject defines (chapters V..IX).
_RUSH_VARIANTS = ["00", "01", "02", "03", "04"]

def _rush_variant_hdrs(ex, variant = None):
    """Deliverable headers owned by one variant (rush0N.h), or by all of them.

    Enumerated rather than globbed with a character class: Bazel's glob knows
    only `*` and `**`, so "rush0[0-4].h" silently matches nothing."""
    variants = [variant] if variant else _RUSH_VARIANTS
    return native.glob(
        ["deliverable/%s/rush%s.h" % (ex, v) for v in variants],
        allow_empty = True,
    )

def rush_common(num = "00", clues = "clues_putchar.tsv"):
    """The rush layers that do not depend on which variant is implemented.

    Emits: norm + both-compiler compile for main.c and ft_putchar.c, and
    ft_putchar's own output/forbidden tests — linked against ft_putchar.c ALONE,
    which is also how "the ft_putchar.c file must contain the ft_putchar

    Args:
        num: the exercise number as a two-digit string; defaults to "00", which
            is the whole story here -- the Rush is one exercise with seven
            deliverable files. It selects deliverable/exNN and tests/exNN and
            prefixes everything it emits (exNN_shared_norm,
            exNN_shared_compile_clang/gcc, exNN_putchar_forbidden,
            exNN_putchar_symbols, exNN_putchar_bin, exNN_putchar_output), and
            it has to be the num rush_variant() is given, since the two macros
            read the same directories.

            The two libraries it declares, :ft_putchar and :ft_putchar_asan,
            are NOT prefixed, because rush_variant() links them by those exact
            names. So rush_common() belongs in the package exactly once -- a
            second call is a duplicate-target error whatever `num` says, since
            nothing here checks for it -- and a package with rush_variant() and
            no rush_common() does not analyse.

            Everything else it reads is fixed rather than parameterised:
            deliverable/exNN/main.c and ft_putchar.c, any *.h beside them, and
            tests/exNN/test_putchar.c with tests/exNN/expected_putchar.txt. The
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
    function" gets checked."""
    ex = "ex" + num
    main_c = "deliverable/%s/main.c" % ex
    putchar_c = "deliverable/%s/ft_putchar.c" % ex
    inc = ["deliverable/" + ex]

    # The Norm bans declaring a struct/typedef in a .c file, so a team that wants
    # one has to put it in a header next to the sources. Nothing in the subject's
    # file list mentions a header, so none may exist — hence the glob. A header
    # named after a variant (rush03.h) belongs to that variant's layers; anything
    # else is shared. Headers are never "compiled": they are declared so Bazel
    # stages them, and normed, because the Norm checks bonus files too.
    variant_hdrs = _rush_variant_hdrs(ex)
    shared_hdrs = [
        h
        for h in native.glob(["deliverable/%s/*.h" % ex], allow_empty = True)
        if h not in variant_hdrs
    ]
    all_hdrs = shared_hdrs + variant_hdrs

    cc_library(
        name = "ft_putchar",
        srcs = [putchar_c],
        hdrs = all_hdrs,
        includes = inc,
        copts = _COPTS,
    )
    cc_library(
        name = "ft_putchar_asan",
        srcs = [putchar_c],
        hdrs = all_hdrs,
        includes = inc,
        copts = _COPTS + _ASAN_COPTS,
        tags = ["manual"],
    )
    # Only the SHARED headers are normed here: a header belonging to a bonus
    # variant is normed by that variant's (manual) norm test, so a half-written
    # rush03.h cannot fail a gated test.
    _norm_test(ex + "_shared_norm", [main_c, putchar_c] + shared_hdrs)
    _compile_tests(ex + "_shared", [main_c, putchar_c], hdrs = all_hdrs)
    _forbidden_test(ex + "_putchar_forbidden", [putchar_c], ["write"], hdrs = all_hdrs)

    # ft_putchar.c is linked against a main() the team does not control at the
    # defense, so it may export ft_putchar and nothing else.
    _symbols_test(ex + "_putchar_symbols", [putchar_c], ["ft_putchar"], hdrs = all_hdrs)

    binname = ex + "_putchar_bin"
    cc_binary(
        name = binname,
        srcs = ["tests/%s/test_putchar.c" % ex],
        deps = [":ft_putchar"],
        copts = _COPTS,
    )
    expected_f = "tests/%s/expected_putchar.txt" % ex
    clues_f = "tests/%s/%s" % (ex, clues)
    _test(
        name = ex + "_putchar_output",
        srcs = ["//tools:diff_output.sh"],
        args = [
            "--bin",
            "$(location :%s)" % binname,
            "--expected",
            "$(location %s)" % expected_f,
            "--clues",
            "$(location %s)" % clues_f,
        ],
        data = [":" + binname, expected_f, clues_f],
        tags = ["output"],
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

    gated=False tags each emitted test "manual" (see the block comment above).
    Layers, in the order a student meets them:
      <p>_norm            norminette on rush0N.c
      <p>_compile_clang/gcc   both campus compilers, -Wall -Wextra -Werror
      <p>_forbidden       only write() (plus the exercise's own functions)
      <p>_output          the curated, labelled table (tests/ex00/cases.tsv)
      <p>_robust          degenerate + counter-ceiling sizes: survival only
      <p>_main            the student's own main.c links, runs and prints
      <p>_valgrind        uninitialised bytes handed to write()
      <p>_asan            out-of-bounds writes into a fixed internal buffer
      <p>_diff            thousands of sizes against the Rust reference
      <p>_diff_asan       the degenerate corpus replayed under ASan/UBSan
    where <p> is e.g. ex00_rush03."""
    ex = "ex" + num
    p = "%s_rush%s" % (ex, variant)
    lib = "rush" + variant
    src = "deliverable/%s/rush%s.c" % (ex, variant)
    main_c = "deliverable/%s/main.c" % ex
    putchar_c = "deliverable/%s/ft_putchar.c" % ex
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
        for h in native.glob(["deliverable/%s/*.h" % ex], allow_empty = True)
        if h not in _rush_variant_hdrs(ex) or h in own_hdrs
    ]

    # ---- static layers -----------------------------------------------------
    _norm_test(p + "_norm", [src] + own_hdrs, extra_tags = extra)
    _compile_tests(p, [src], hdrs = all_hdrs, extra_tags = extra)

    # One forbidden_symbols call for all three files: the script pools the
    # symbols each file DEFINES before judging the ones they call, so this is
    # what lets main.c call rush() and rush0N.c call ft_putchar() while still
    # rejecting printf/putchar/malloc.
    _forbidden_test(
        p + "_forbidden",
        [src, putchar_c, main_c],
        ["write"],
        hdrs = all_hdrs,
        extra_tags = extra,
    )

    # Linkage hygiene, and this module is where it bites hardest: the subject
    # has the EVALUATOR replace main.c at the defense, so rush0N.c is linked
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
        [src],
        exports or ["rush"],
        hdrs = all_hdrs,
        extra_tags = extra,
    )

    # ---- the student's rectangle, as a library -----------------------------
    # `extra` (= ["manual"] for a bonus variant) has to reach the LIBRARY and the
    # BINARIES too, not just the tests: `manual` only removes a target from
    # wildcard expansion, and `bazel test //MOD/...` builds every non-test target
    # the pattern matches (--build_tests_only is off by default). Without this, a
    # bonus variant left mid-edit breaks the submit gate with a build error that no
    # test table explains.
    cc_library(
        name = lib,
        srcs = [src],
        hdrs = all_hdrs,
        includes = ["deliverable/" + ex],
        deps = [":ft_putchar"],
        copts = _COPTS,
        tags = extra,
    )
    cc_library(
        name = lib + "_asan",
        srcs = [src],
        hdrs = all_hdrs,
        includes = ["deliverable/" + ex],
        deps = [":ft_putchar_asan"],
        copts = _COPTS + _ASAN_COPTS,
        tags = ["manual"],
    )

    # ---- curated pedagogic table ------------------------------------------
    cases_f = "%s/cases.tsv" % tests
    clues_f = "%s/%s" % (tests, clues)
    expected_f = "%s/expected_rush%s.txt" % (tests, variant)
    binname = p + "_bin"
    cc_binary(
        name = binname,
        srcs = ["%s/test_rush.c" % tests, capture_h],
        deps = [":" + lib, "//tools:diffio"],
        copts = _COPTS,
        tags = extra,
    )
    _test(
        name = p + "_output",
        srcs = ["//tools:diff_output.sh"],
        args = [
            "--bin",
            "$(location :%s)" % binname,
            "--expected",
            "$(location %s)" % expected_f,
            "--stdin",
            "$(location %s)" % cases_f,
            "--labeled",
            "--clues",
            "$(location %s)" % clues_f,
        ],
        data = [":" + binname, expected_f, cases_f, clues_f],
        tags = ["output"] + extra,
    )

    # ---- degenerate + hostile sizes: survival only -------------------------
    edge_f = "%s/edge_cases.tsv" % tests
    robust_expected = "%s/expected_robust.txt" % tests
    robustbin = p + "_robustbin"
    cc_binary(
        name = robustbin,
        srcs = ["%s/robust_rush.c" % tests, capture_h],
        deps = [":" + lib, "//tools:diffio"],
        copts = _COPTS,
        tags = extra,
    )
    _test(
        name = p + "_robust",
        srcs = ["//tools:diff_output.sh"],
        args = [
            "--bin",
            "$(location :%s)" % robustbin,
            "--expected",
            "$(location %s)" % robust_expected,
            "--stdin",
            "$(location %s)" % edge_f,
            "--labeled",
            "--clues",
            "$(location %s)" % clues_f,
        ],
        data = [":" + robustbin, robust_expected, edge_f, clues_f],
        tags = ["output"] + extra,
    )

    # ---- the student's own main.c, built exactly as the subject says -------
    mainbin = p + "_mainbin"
    cc_binary(
        name = mainbin,
        srcs = [main_c, putchar_c, src] + all_hdrs,
        includes = ["deliverable/" + ex],
        copts = _COPTS,
        tags = extra,
    )
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
            "--exit",
            "0",
            "--timeout",
            "20",
        ],
        data = [":" + mainbin],
        tags = ["output"] + extra,
    )

    # ---- memory layers -----------------------------------------------------
    vgbin = p + "_vgbin"
    cc_binary(
        name = vgbin,
        srcs = ["%s/vg_rush.c" % tests, capture_h],
        deps = [":" + lib],
        copts = _COPTS,
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
        "--src",
        "$(location %s)" % src,
        "--src",
        "$(location %s)" % putchar_c,
        "--hdr",
        "$(location %s)" % capture_h,
    ]
    for h in all_hdrs:
        asan_args += ["--hdr", "$(location %s)" % h]
    _test(
        name = p + "_asan",
        srcs = ["//tools:asan_check.sh"],
        args = asan_args,
        data = [probe_f, src, putchar_c, capture_h] + all_hdrs,
        tags = ["asan"] + extra,
    )

    # ---- live differential against //oracle --------------------------------
    diff_clues_f = "%s/%s" % (tests, diff_clues)
    diffbin = p + "_diffbin"
    cc_binary(
        name = diffbin,
        srcs = ["%s/diff_rush.c" % tests, capture_h],
        deps = [":" + lib, "//tools:diffio"],
        copts = _COPTS,
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
    cc_binary(
        name = asan_diffbin,
        srcs = ["%s/diff_rush.c" % tests, capture_h],
        deps = [":" + lib + "_asan", "//tools:diffio"],
        copts = _COPTS + _ASAN_COPTS,
        linkopts = _ASAN_LINKOPTS,
        features = ["-supports_start_end_lib"],
        tags = ["manual"],
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
        ],
        data = ["//oracle:oracle", ":" + asan_diffbin],
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
            ":" + p + "_compile_clang",
            ":" + p + "_compile_gcc",
            ":" + p + "_forbidden",
            ":" + p + "_symbols",
            ":" + p + "_output",
            ":" + p + "_robust",
            ":" + p + "_main",
            ":" + p + "_valgrind",
            ":" + p + "_asan",
            ":" + p + "_diff",
            ":" + p + "_diff_asan",
        ],
        tags = ["manual"],
    )
