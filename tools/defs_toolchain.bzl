"""The flags and the pinned tools every layer builds and runs with.

The compiler flags of a student's build (_COPTS, _ASAN_COPTS), the tags a test
carries for the audit to read (_HARNESS_PROTO_TAG, _CASE_READS_TAG), and every
pinned binary a runner is handed with its data: the cc, ld, nm, objdump and
make tools (_PINNED_CC and the rest), valgrind (_VG_BIN), the symbolizer and
the campus compilers (_CAMPUS_CCS). //tools:conventions holds two of its tables
to the runners in tools/, read as text: _PINNED_CC_RUNNERS and
_SYMBOLIZER_RUNNERS. And a few leaf helpers the files above share
(_path_glob_match, _oracle_owner, _harness_prototype_problem).

Loaded by the files above it, and re-exported by tools/defs.bzl, the one
file a BUILD file loads.
"""

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
# so this no longer reaches /usr/bin/ld.bfd through PATH.
_ASAN_LINKOPTS = ["-fsanitize=address,undefined", "-fuse-ld=bfd"]

# Unbuffered stdout for the harness's own output fixtures: see
# tools/unbuffered_stdout.c. The library, for a cc_binary, and the same file as
# a source, for the two runners that compile a fixture at test time
# (header_check.sh, ilp32_test.sh). //tools:conventions checks that the library
# reaches every output fixture and no other binary.
_UNBUFFERED = "//tools:unbuffered_stdout"
_UNBUFFERED_C = "//tools:unbuffered_stdout.c"

# The escaped-value notation's writer (tools/notation.h), the same way round:
# the header-only library every output fixture links beside _UNBUFFERED, and
# the header itself, put on the include path of every runner that compiles a
# fixture at test time (ilp32_test.sh, method_check.sh, header_check.sh,
# ref_compare.sh), so a fixture that includes it builds on every route.
# _NOTATION_HDRS is every header the library holds, notation.h and the
# fixtures' descriptor capture (tools/fd_capture.h), which those runners
# stage: both sit in tools/, so the one folder on the path reaches both.
_NOTATION = "//tools:notation"
_NOTATION_H = "//tools:notation.h"
_NOTATION_HDRS = [_NOTATION_H, "//tools:fd_capture.h"]

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
# $(location file)/.. walks through a file rather than naming its parent. Every
# runner does readlink -f then dirname (tools/runner_lib.sh, rl_vg_pin), which
# is the form that survives both a later `cd` and the runfiles tree's mix of
# real directories and symlinked files.
_VG_BIN = "@valgrind_ubuntu//:usr/bin/valgrind.bin"
_VG_MEMCHECK = "@valgrind_ubuntu//:usr/libexec/valgrind/memcheck-amd64-linux"
_VG_CALLGRIND = "@valgrind_ubuntu//:usr/libexec/valgrind/callgrind-amd64-linux"
_VG_RUNTIME = "@valgrind_ubuntu//:runtime"

def _valgrind_args(tool = _VG_MEMCHECK):
    """Flags pointing a runner at the pinned valgrind.

    Args:
        tool: the tool binary whose directory becomes $VALGRIND_LIB --
            memcheck for the leak layer, callgrind for the two cycles layers.

    Returns:
        A list of arguments to append to the runner's args.
    """
    return [
        "--valgrind",
        "$(location %s)" % _VG_BIN,
        "--valgrind-tools",
        "$(location %s)" % tool,
    ]

def _valgrind_data(tool = _VG_MEMCHECK):
    """The data deps matching _valgrind_args, including the whole tool tree.

    Args:
        tool: same file named in _valgrind_args, so $(location) can resolve it.

    Returns:
        A list of labels to append to the runner's data.
    """
    return [_VG_BIN, tool, _VG_RUNTIME]

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

# The pinned clang, for every runner that compiles at test time
# (_PINNED_CC_RUNNERS below). Each shells out to a compiler. The first four
# (forbidden, symbols, prototype and the header layer) defaulted to `cc` from
# PATH.
#
# WHAT THAT COST, measured: with a PATH holding 580 coreutils and no compiler,
# 116 forbidden + 102 symbols + 96 prototype + 7 header targets reported SKIP
# and went GREEN having compiled nothing -- 321 of them, with forbidden and
# prototype at LEVEL 1, inside the submit gate. A real red vanished with them:
# //c-piscine/c-piscine-rush-02:ex00_forbidden went FAIL -> PASS, hiding "CALLED BUT NOT
# AUTHORISED: printf".
#
# The campus-compiler note above _CAMPUS_CCS argues the rule these four were
# exempt from: "a check whose answer changes with the machine is not a check".
# The runners all accepted --cc already; nothing ever passed it.
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
# header_check.sh, method_check.sh --expect, and make_test.sh, whose
# recipes link). The clang package has no linker
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

# THE TOOLS A MAKEFILE'S RECIPES RUN, for make_test.sh (TO VERIFY V60). Its
# recipes run the compiler and the archiver they name through PATH -- `cc`,
# `gcc`, $(CC), `ar rcs` -- and those were the box's: on a box with no `cc`
# every build stopped at "make: cc: No such file or directory", and a
# Makefile's -Werror verdict changed with the box's compiler (a variable set
# and never read fails under gcc 11 and passes under campus's clang-12; x =
# x; the reverse). make_test.sh puts wrappers over these first on PATH for
# the whole run: cc, clang over the pinned build above, gcc (and c89, c99)
# over campus's gcc-10 with -B to the pinned as and ld, and ar, ranlib, as
# and ld from binutils 2.38, which load --ld-lib's libbfd. Every c_make test
# takes all of them, through c_make and never at a call site.
_PINNED_GCC = "@gcc_10_ubuntu//:usr/bin/x86_64-linux-gnu-gcc-10"
_PINNED_AS = "@binutils_x86_64_linux_gnu//:usr/bin/x86_64-linux-gnu-as"
_PINNED_AR = "@binutils_x86_64_linux_gnu//:usr/bin/x86_64-linux-gnu-ar"
_PINNED_RANLIB = "@binutils_x86_64_linux_gnu//:usr/bin/x86_64-linux-gnu-ranlib"

def _pinned_make_args():
    """The pinned build, gcc-10, and binutils' as, ar and ranlib, for make_test.sh."""
    return _pinned_build_args() + [
        "--gcc",
        "$(location %s)" % _PINNED_GCC,
        "--as",
        "$(location %s)" % _PINNED_AS,
        "--ar",
        "$(location %s)" % _PINNED_AR,
        "--ranlib",
        "$(location %s)" % _PINNED_RANLIB,
    ]

# gcc's runtime is cc1, collect2, its crt objects and libgcc, which it finds
# by walking up from its own path, and the sanitizers' shared runtimes its
# libasan.so and siblings point at (MODULE.bazel); binutils' :runtime (in _PINNED_LD_DATA) is
# what as, ar and ranlib load; and clang's sanitizer runtime is what a
# Makefile that builds with -fsanitize= links, from the pinned clang's tree.
_PINNED_MAKE_DATA = _PINNED_BUILD_DATA + [
    "@clang_12_ubuntu//:sanitizer_runtime",
    _PINNED_GCC,
    "@gcc_10_ubuntu//:runtime",
    _PINNED_AS,
    _PINNED_AR,
    _PINNED_RANLIB,
]

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
    "//tools:make_test.sh": ("always", "always"),
    "//tools:method_check.sh": ("always", "--expect"),
    "//tools:prototype_check.sh": ("always", "never"),
    "//tools:ref_compare.sh": ("always", "always"),
    "//tools:symbols_test.sh": ("always", "never"),
}

# A runner that takes a whole SET of pinned tools, and the helper that hands
# it all of them. make_test.sh refuses a partial set at run time ("--gcc is
# missing"), so a test handed _pinned_build_args() alone passed the check
# below and failed every run; this names the helper that makes it whole.
_PINNED_TOOL_SETS = {
    "//tools:make_test.sh": (
        ["--cc", "--ld", "--gcc", "--as", "--ar", "--ranlib"],
        "_pinned_make_args()",
        "_PINNED_MAKE_DATA",
    ),
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
    if runner in _PINNED_TOOL_SETS:
        flags, helper, data = _PINNED_TOOL_SETS[runner]
        missing = [f for f in flags if f not in args]
        if missing:
            return ("%s runs its recipes with the pinned tools, and these args hand " +
                    "it no %s: it refuses a partial set, and without any it would " +
                    "run the machine's (TO VERIFY V60). Add %s to its args and %s " +
                    "to its data.") % (runner, ", ".join(missing), helper, data)
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
# And what libLLVM loads beside it that a release can lack, libxml2 and ICU
# (MODULE.bazel, clang_12_ubuntu's :libllvm_deps), which rl_sanitizers' wrapper
# finds in that same folder and proves it took from there (TO VERIFY V238).
_SYMBOLIZER_DATA = [_SYMBOLIZER, _SYMBOLIZER_LIB, "@clang_12_ubuntu//:libllvm_deps"]

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
# --nm-lib and run each tool with its own directories on LD_LIBRARY_PATH,
# exported to nothing else. They also verify the resolution
# transitively (tools/runner_lib.sh, rl_binutils_pin), because the failure
# being guarded against is precisely one where the right file is exec'd and
# the wrong code runs.
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

# The pinned objdump, for forbidden_symbols.sh --function, which reads the
# relocations of each function's own section. The same kind of frontend as
# nm, over the same libraries (MODULE.bazel), proved the same way.
_PINNED_OBJDUMP = "@binutils_x86_64_linux_gnu//:usr/bin/x86_64-linux-gnu-objdump"

def _pinned_objdump_args():
    """--objdump and its --objdump-lib, for forbidden_symbols.sh --function."""
    a = ["--objdump", "$(location %s)" % _PINNED_OBJDUMP]
    for lib in _PINNED_NM_LIBS:
        a += ["--objdump-lib", "$(location %s)" % lib]
    return a

_PINNED_OBJDUMP_DATA = [_PINNED_OBJDUMP]

# The two compilers the 42 campus box and the Moulinette have: clang-12 (its
# `cc`) and gcc-10.5. Every C exercise compiles under BOTH, with -Wall -Wextra
# -Werror, because their -Werror sets differ: a warning only one compiler emits
# still fails locally instead of surfacing on the Moulinette. A well-formed stub
# compiles cleanly, exactly like the norm layer.
#
# clang is FETCHED -- campus's exact 12.0.1-19ubuntu3, pinned by sha256 in
# MODULE.bazel -- so this layer's verdict no longer depends on which box you sat
# at. That is the whole rule: a check whose answer changes with the machine is
# not a check. The libdirs go with it and are not optional; a 100 KB driver that
# cannot find libclang-cpp either fails to start or, far worse, loads the BOX's
# copy and quietly stops being the pinned compiler.
#
# gcc is fetched the same way, from Ubuntu's gcc-10 source package where clang
# comes from its llvm-toolchain-12 one (MODULE.bazel's gcc_10_ubuntu: campus's
# 10.5.0-1ubuntu1~22.04.3 gcc-10, cpp-10, gcc-10-base and libgcc-10-dev).
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
        # No progs: clang assembles internally, so there is no subprogram to point
        # at and -print-prog-name=as would answer "as" whatever we passed.
        "progs": "",
        "progs_libs": [],
        "progs_data": [],
    },
    {
        "label": "gcc",
        "cc": "$(location @gcc_10_ubuntu//:usr/bin/x86_64-linux-gnu-gcc-10)",
        "data": [
            "@gcc_10_ubuntu//:runtime",
            "@gcc_10_ubuntu//:usr/bin/x86_64-linux-gnu-gcc-10",
        ],
        # No libs of the compiler's own: the driver links against nothing
        # unusual, and what cc1 needs (libisl, libmpc, libmpfr, libgmp) are
        # leaf libraries taken from the box, the same trade clang's libtinfo
        # and libedit get. `under` matters -- gcc looks for cc1 in the tree it
        # resolves its own path to, and a GCC_EXEC_PREFIX from outside moves
        # that tree to the box's with no diagnostic (a cc1 missing from the
        # fetched tree is a loud "cannot execute 'cc1'" instead, never the
        # box's: V297).
        "libs": [],
        "under": "@gcc_10_ubuntu//:usr/bin/x86_64-linux-gnu-gcc-10",
        # gcc, unlike clang, shells out to an assembler. binutils is already
        # pinned for nm, and -B makes gcc take its target-prefixed `as` from
        # there instead of the machine's.
        "progs": "@binutils_x86_64_linux_gnu//:usr/bin/x86_64-linux-gnu-as",
        # The ASSEMBLER's libraries (compile_check.sh --cc-progs-lib), apart
        # from the compiler's `libs`, which runner_lib.sh's rl_cc_pin proves
        # the compiler loaded and gcc never loads these. The fetched `as` is
        # a frontend over libbfd and libopcodes, named by bare soname with no
        # RUNPATH, so without this directory on the loader's path it ran on
        # the box's copies where the box has binutils 2.38 and did not start
        # where it has another -- every compile then "gcc FAIL" on the
        # student's file (TO VERIFY V228). The directory holds binutils'
        # libraries alone, so the driver and cc1 load nothing different;
        # compile_check.sh proves the assembler's come from it.
        "progs_libs": ["@binutils_x86_64_linux_gnu//:usr/lib/x86_64-linux-gnu/libbfd-2.38-system.so"],
        # What it loads, staged beside it: libbfd above names one file of the
        # set, and libopcodes and libctf come with :runtime. Here and not in
        # `data`, which _fixed_array_test also stages, and which assembles
        # nothing.
        "progs_data": ["@binutils_x86_64_linux_gnu//:runtime"],
    },
]


# ---------------------------------------------------------------------------
# WHAT THE FILES ABOVE THIS ONE LOAD OF IT. A load() cannot name a private
# symbol, so each one they use is given a public name here, its own without
# the underscore, and loaded back under its own name: the code reads as it did
# when tools/defs.bzl held it all. These names are for those files alone; a
# BUILD file loads //tools:defs.bzl.
COPTS = _COPTS
ASAN_COPTS = _ASAN_COPTS
ASAN_LINKOPTS = _ASAN_LINKOPTS
UNBUFFERED = _UNBUFFERED
UNBUFFERED_C = _UNBUFFERED_C
NOTATION = _NOTATION
NOTATION_H = _NOTATION_H
NOTATION_HDRS = _NOTATION_HDRS
HARNESS_PROTO_TAG = _HARNESS_PROTO_TAG
CASE_READS_TAG = _CASE_READS_TAG
case_reads_tag = _case_reads_tag
oracle_owner = _oracle_owner
path_glob_match = _path_glob_match
harness_prototype_problem = _harness_prototype_problem
VG_CALLGRIND = _VG_CALLGRIND
valgrind_args = _valgrind_args
valgrind_data = _valgrind_data
DIFF = _DIFF
SHELLCHECK = _SHELLCHECK
MAKE = _MAKE
pinned_cc_args = _pinned_cc_args
PINNED_CC_DATA = _PINNED_CC_DATA
pinned_ld_args = _pinned_ld_args
PINNED_LD_DATA = _PINNED_LD_DATA
pinned_build_args = _pinned_build_args
PINNED_BUILD_DATA = _PINNED_BUILD_DATA
pinned_make_args = _pinned_make_args
PINNED_MAKE_DATA = _PINNED_MAKE_DATA
SYMBOLIZER_DATA = _SYMBOLIZER_DATA
symbolizer_args = _symbolizer_args
pinned_nm_args = _pinned_nm_args
PINNED_NM_DATA = _PINNED_NM_DATA
pinned_objdump_args = _pinned_objdump_args
PINNED_OBJDUMP_DATA = _PINNED_OBJDUMP_DATA
CAMPUS_CCS = _CAMPUS_CCS
