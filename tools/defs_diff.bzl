"""The layers that hold an exercise to a reference or a budget.

c_mem_check (adversarial ASan probes), c_diff (differential value and
crash-fuzz against //oracle), c_perf (time and memory growth) and c_twin.

Loaded by the files above it, and re-exported by tools/defs.bzl, the one
file a BUILD file loads.
"""

load(":defs_checks.bzl", _raise = "raise_private")
load(
    ":defs_contract.bzl",
    "turnin_dir",
    _call_kw = "call_kw",
    _contract_or_none = "contract_or_none",
    _deliverable_hdrs = "deliverable_hdrs",
    _deliverable_srcs = "deliverable_srcs",
    _diff_harness_problem = "diff_harness_problem",
    _dirname = "dirname",
    _entry = "entry",
    _fn_lib = "fn_lib",
    _inc_args = "inc_args",
    _linked = "linked",
    _member = "member",
    _provided = "provided",
    _required = "required",
    _resolve = "resolve",
    _student_bin = "student_bin",
    _zone = "zone",
)
load(
    ":defs_levels.bzl",
    _call = "call",
    _graded_rule = "graded_rule",
    _is_ex = "is_ex",
    _prefix = "prefix",
    _tests_folder = "tests_folder",
    _uniq = "uniq",
)
load(":defs_test.bzl", _fixture_gate = "fixture_gate", _test = "test")
load(
    ":defs_toolchain.bzl",
    _PINNED_BUILD_DATA = "PINNED_BUILD_DATA",
    _SYMBOLIZER_DATA = "SYMBOLIZER_DATA",
    _pinned_build_args = "pinned_build_args",
    _symbolizer_args = "symbolizer_args",
    _valgrind_args = "valgrind_args",
    _valgrind_data = "valgrind_data",
)

def c_mem_check(num = None, fn = None, probe = None, srcs = None, hdrs = None, prototype = None, refusals = None, name = None, unit = None):
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
            exNN_probe_memcheck (tag "valgrind", at the package's valgrind
            level: `strict`, or `basic` where the subject() contract declares
            memory_graded, see _layer_level), over the exNN_memprobe binary.
            For a function of a library (`unit`), every one of them is
            <function>_<what> instead.
        fn: the subject's function. For an exercise it is used for ONE thing
            here: it labels the memcheck report ("exNN/<fn>-probe"), and no
            target name holds it -- exNN_asan is named from num alone. For a
            function of a library it names that function, so it is in every
            target name (<fn>_asan). Keep it identical to the c_function()
            call for the same exercise or unit.
        probe: an adversarial main() under tests/exNN/, named mem_*.c by
            convention. It hands the function blocks sized to fit EXACTLY, with
            nothing valid on either side, so that a single step past what the
            function was given lands in a sanitizer redzone instead of on a
            harmless neighbouring byte. That is the whole point of the layer:
            an out-of-bounds read that still returns the right value is
            invisible to every diff of stdout. Probes here are written so that
            an unimplemented stub survives them (it touches nothing, so it
            cannot overrun anything), which is why this layer needs no
            correctness gate of the kind valgrind and allocfail carry. The
            probe's own header comment, which opens the file, is where the
            fault it is aimed at is written down: asan_check.sh prints it
            under an out-of-bounds red of the probe, and //tools:conventions
            holds each probe a call names to one. A comment at the call site is
            optional, for what the call itself does unusually (a function of
            a library, code the grader links).
        srcs: the deliverable sources compiled together with the probe.
            Defaults to a GLOB of the .c files the contract names or allows in
            the turn-in directory (see _deliverable_srcs); when there is none, the
            probe layers are "not turned in" tests and the memcheck program is
            a stand-in that says so (see _test and _student_bin). Override it
            only when the probe cannot be built from one exercise's directory
            alone; no project does. A function the grader brings (the
            contract's `linked`: c-12 ex05's real push_strs builds its nodes
            with the grader's ft_create_elem) is linked into both probe
            builds without it: the runner takes the library's archive with
            --lib, and the memcheck program links it.
        hdrs: headers the probe or the sources include but which do not live
            beside them; no project passes one today. What the grader
            brings (the contract's `provided`: C 08's ft_stock_str.h,
            Reloaded's ft_putchar.c) is
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
        refusals: in tools/tests/macro_fixtures alone, the list a refusal
            of a call on a function of a library (_member) is collected in
            instead of failing (_refuse).
        name: unused, for the reason c_levels gives: every macro takes one,
            and buildifier's unnamed-macro check holds this one to it since it
            declares a rule (a program built from the student's files, see
            _student_bin). Every target here is named from `num`, so there is
            nothing for it to control.
        unit: in a package whose subject() contract is divided into units
            (units = {...}), the unit this call judges, in place of `num`: a
            function of a library, by its own name, the project, or one part
            of a root divided into parts (subject()'s units). A call
            names one of the two, never both (_resolve). `fn` then defaults to
            that function. For a function of a library (see _member) the
            targets are <function>_asan, <function>_memprobe and
            <function>_probe_memcheck, the probe is under tests/<function>/,
            and the memcheck program links c_library()'s :<library>_lib
            through the turn-in's Makefile. srcs, hdrs and `prototype` are the
            library's, and refused here: the probe is held to c_library's
            <library>_prototype.
    """
    r = _resolve("c_mem_check", num, unit, refusals)  # first: a contract error names this macro
    if r == False:
        return
    num, call, function = r.key, r.call, r.function
    if fn == None:
        fn = function
    _required("c_mem_check", fn = fn, probe = probe)
    _entry(num, "c_mem_check")
    u = _member(num, function, fn, refusals, "c_mem_check(%s)" % _call(call), srcs, hdrs, prototype = prototype)
    if u == False:
        return
    ex = _prefix(num)
    stem = u.stem if u else ex
    tdir = u.tdir if u else "tests/" + ex
    if srcs == None:
        srcs = _deliverable_srcs(ex)
        hdrs = _deliverable_hdrs(ex, hdrs)
    own_srcs = _zone(srcs)
    provided = _provided(num)
    hdrs = _zone(hdrs or [])
    hdrs = hdrs + [h for h in provided.hdrs if h not in hdrs]
    srcs = own_srcs + provided.srcs
    probe_f = "%s/%s" % (tdir, probe)

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
    # A function's library: its Makefile's -I, as every build of it has them.
    inc = [u.inc] if u else []
    for f in inc:
        args += ["--inc-file", "$(location %s)" % f]
    for lib in libs:
        args += ["--lib", "$(location %s)" % lib]
    _test(
        name = stem + "_asan",
        srcs = ["//tools:asan_check.sh"],
        args = _pinned_build_args() + args + _symbolizer_args(),
        data = _uniq(srcs + [probe_f] + hdrs + inc + libs + _SYMBOLIZER_DATA + _PINNED_BUILD_DATA +
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
    # Tagged `valgrind`, so it sits at the package's valgrind level with the
    # rest of memcheck's findings (_layer_level): `strict` -- real, and
    # conditional on something outside the subject -- or `basic` where the
    # contract's memory_graded makes memory a sentence of the subject.
    probe_dirs = depset(
        [_dirname(f) for f in [probe_f] + srcs + hdrs],
    ).to_list()

    # Every file linked directly, probe first, as the cc_binary this used to be
    # linked them: the probe is a main() over exactly these sources. A
    # function's are the library's unit, built as its Makefile builds it.
    _student_bin(
        name = stem + "_memprobe",
        harness = [probe_f],
        prototype = prototype or (u.proto if u else ex + "_prototype"),
        srcs = provided.srcs if u else srcs,
        hdrs = hdrs,
        deps = (u.deps if u else []) + libs,
        includes = probe_dirs,
        archive = False,
        dir = turnin_dir(num),
        tags = ["manual"],
        **(u.kw if u else {})
    )
    r_args, r_data = _graded_rule(leaks = False)
    _test(
        name = stem + "_probe_memcheck",
        srcs = ["//tools:valgrind_test.sh"],
        args = [
            "--bin",
            "$(location :%s_memprobe)" % stem,
            # NO SPACE in the label: sh_test tokenises `args` on whitespace,
            # so "ex00/ft_foreach probe" arrives as two arguments and the
            # runner rejects the second as an unknown option. The same trap
            # c_files fail()s on and c_function's valgrind arm documents.
            "--label",
            "%s/%s-probe" % (ex, fn),
            "--no-leak-check",
        ] + r_args + _valgrind_args(),
        data = [":%s_memprobe" % stem] + r_data + _valgrind_data(),
        size = "small",
        tags = ["valgrind"],
    )

def diff_readings_problem(num, readings):
    """What is wrong with a c_diff call's `readings`, or "" when it is sound.

    One dict: "oracle_fn" (the arm writing the cases the readings part on, a
    name, required), and optionally "diff_clues" (a file under tests/exNN/),
    "count" (a positive int), "harness" (a reader of its own, a diff_<what>.c
    under tests/exNN/, as c_diff's `harness` is) and "level" (3 or 4: the
    reading's own level, strict, is the diff layer's). An unknown key fails,
    as a case key does.

    Public so //tools/tests:starlark_unit can check it at load time.

    Args:
      num: the key the call names, for the message: the exercise's
        number, or in a contract of units the unit's name (a function of a
        library by its own, whose folder is tests/<function>/).
      readings: the call's readings, or None.

    Returns:
      The message to fail with, or "" when the call is sound.
    """
    if readings == None:
        return ""
    where = "c_diff(%s, readings = %r)" % (_call(num), readings)
    if type(readings) != "dict":
        return "%s: one dict, {\"oracle_fn\": ..., ...}: one reading per exercise." % where
    keys = ["count", "diff_clues", "harness", "level", "oracle_fn"]
    for k in sorted(readings):
        if k not in keys:
            return "%s: %r is not a key; the keys are %s." % (where, k, ", ".join(keys))
    o = readings.get("oracle_fn")
    if type(o) != "string" or not o or " " in o:
        return ("%s: \"oracle_fn\" names the //oracle arm that writes the cases the " +
                "readings part on, one word.") % where
    if "diff_clues" in readings and (type(readings["diff_clues"]) != "string" or
                                     not readings["diff_clues"] or "/" in readings["diff_clues"]):
        return "%s: \"diff_clues\" is a file name under %s." % (where, _tests_folder(num))
    if "count" in readings and (type(readings["count"]) != "int" or readings["count"] < 1):
        return "%s: \"count\" is the corpus's size, a positive int." % where
    if "harness" in readings:
        h = readings["harness"]
        if type(h) != "string" or not h or "/" in h:
            return "%s: \"harness\" is a file name under %s." % (where, _tests_folder(num))
        hp = _diff_harness_problem(num, h)
        if hp:
            return "%s: \"harness\": %s" % (where, hp)
    if "level" in readings and readings["level"] not in (3, 4):
        return ("%s: \"level\" is 3 or 4, where the reading is this repo's convention " +
                "rather than one reading of the sentence; a reading sits at strict, the " +
                "diff layer's own level, and needs none.") % where
    return ""

def c_diff(
        num = None,
        fn = None,
        harness = None,
        oracle_fn = None,
        seed = 1,
        count = 400000,
        asan_count = 200000,
        sanitize = True,
        diff_clues = None,
        gate_bin = None,
        gate_expected = "expected.txt",
        gate_stdin = None,
        perf = True,
        perf_count = 200000,
        perf_length = None,
        size = "small",
        prototype = None,
        readings = None,
        refusals = None,
        name = None,
        unit = None):
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
            dio_garbage and dio_dest (dio_dest_hex from a hex field), the
            destination buffer for a function that writes a string, whose
            free bytes are never 0. It is grader-side infrastructure and
            never a submission, so it may use libc freely and need not be
            norm-clean. Named diff_<what>.c, or this macro fails:
            //tools:conventions finds the harnesses by that name, to hold the
            header's "Line:" legend and the destination rule.
        oracle_fn: which arm of //oracle:oracle generates the corpus, e.g.
            "c07_strdup". The reference is run as `oracle <oracle_fn> <seed>
            <count>`; an unknown name exits 2 and this layer fails rather than
            quietly comparing nothing. Each arm's exact line format is what
            `oracle <oracle_fn> 1 5` prints, and the harness has to reprint
            the input fields byte for byte or every case "diverges".
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
            Fewer than 16 produced lines is a harness error (exit 2, nothing
            was checked) rather than "OK (0 cases)", because a differential
            layer that silently tests nothing is worse than no layer;
            MIN_DIFF_CASES in the environment moves that floor.
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
            ungated, which c_levels()' audit refuses in a project
            (_ungated_diff_problems: every diff layer waits for its
            exercise's output test, or its macro says why not); only the
            harness's own fixtures turn it. The gate fails OPEN by design: no gate, or a gate binary
            that cannot run, still runs the differential, since a wrongly
            skipped layer would turn a real divergence green. NO_SKIP=1 forces
            every gated layer to run anyway -- `bazel test //...
            --test_env=NO_SKIP=1` before trusting an all-green sweep.
        gate_expected: the fixture the gate diffs against, resolved under
            tests/exNN/; default "expected.txt". Unused when gate_bin is "".
            The gate compares it as exNN_output does: that test's --sanitize
            (which changes the verdict, see diff_output.sh) and --labeled are
            read off it (_fixture_gate), never restated here, so call c_diff
            below the c_function or c_libft that declares it.
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
            "harness": a reader of its own (optional; a diff_<what>.c under
            tests/exNN/, built as `harness` is), where the reading is in what
            a case's result is read as rather than in which cases there
            are: C 03 ex00's plain reader prints a sign, its readings reader
            the int (V206). Such a reading has no ASan twin: its cases are
            the plain corpus's, which exNN_diff_asan replays already, and a
            twin judges no value, so it would only repeat that replay
            (V299). "level": above strict (optional)}. D3 reads an
            ambiguous sentence at strict at most, and only there: so
            `oracle_fn`'s corpus holds only the cases every reading agrees
            on, and this one the rest -- or, with a "harness", cases the
            plain corpus holds too, each result read as the reading reads
            it, which every reading does not agree on.
            Emits exNN_readings, the same harness (or its own) and gate over
            that corpus (layer diff, strict, the `_readings` suffix BSQ's and
            Rush 01's corpus readings take), and, with `sanitize` and no
            "harness", its crash-fuzz twin exNN_readings_diff_asan, so the
            parted cases stay under ASan: moved out of the main corpus
            without a twin, a byte above 0x7f no reading agrees on would have
            left the one layer that sees a signed-char index read out of
            bounds. The twin is handed no
            `diff_clues`: it sits above strict, and a legend that states the
            reading is the strict target's alone. C 02 ex09 takes one (its
            BUILD file says which reading), and C 11 ex06 one at "level": 3:
            "ascii order" does not reach a byte above 0x7f, so the order its
            reference gives one is a convention of this repo's, as C 06 ex03's
            is (docs/reference.md, "Run contract"), listed in _RAISED;
            tools/conventions.sh holds the corpus's hint file to its level.
            One per exercise, as the target's name allows. Checked by
            diff_readings_problem().
            Default None.
        refusals: in tools/tests/macro_fixtures alone, the list a refusal
            of a call on a function of a library (_member) is collected in
            instead of failing (_refuse).
        name: unused, for the reason c_levels gives: every macro takes one,
            and buildifier's unnamed-macro check holds this one to it since it
            declares a rule (a program built from the student's files, see
            _student_bin). Every target here is named from `num`, so there is
            nothing for it to control.
        unit: in a package whose subject() contract is divided into units
            (units = {...}), the unit this call judges, in place of `num`: a
            function of a library, by its own name, the project, or one part
            of a root divided into parts (subject()'s units). A call
            names one of the two, never both (_resolve). `fn` then defaults to
            that function. For a function of a library (see _member) every
            target is <function>_<what> (diffbin, diff, diff_asan, readings,
            readings_diff_asan, and c_perf's, which it is handed on to), every
            file is under tests/<function>/, the gate defaults to
            :<function>_bin, and both programs link c_library()'s
            :<library>_lib through the turn-in's Makefile. `prototype` is the
            library's, and refused here: both are held to c_library's
            <library>_prototype.
    hermetically by Bazel — no system rustc needed."""
    r = _resolve("c_diff", num, unit, refusals)  # first: a contract error names this macro
    if r == False:
        return
    num, call, function = r.key, r.call, r.function
    if fn == None:
        fn = function
    _required("c_diff", fn = fn, harness = harness, oracle_fn = oracle_fn)
    _entry(num, "c_diff")
    u = _member(num, function, fn, refusals, "c_diff(%s)" % _call(call), prototype = prototype)
    if u == False:
        return
    problem = _diff_harness_problem(call, harness) or diff_readings_problem(call, readings)
    if problem:
        fail(problem)
    ex = _prefix(num)

    # Every target is named from `stem`, and every file is under `tdir`:
    # the exercise's or unit's, or one function's of a library (see _member).
    stem = u.stem if u else ex
    tdir = u.tdir if u else "tests/" + ex

    # What the grader links into this exercise (the contract's `linked`) is
    # linked into both programs.
    deps = _linked(num).libs
    lib_deps = u.deps if u else [":" + _fn_lib(num, fn)]
    kw = u.kw if u else {}
    prototype = prototype or (u.proto if u else ex + "_prototype")
    binname = stem + "_diffbin"
    _student_bin(
        name = binname,
        harness = ["%s/%s" % (tdir, harness)],
        prototype = prototype,
        deps = lib_deps + deps,
        diffio = True,
        **kw
    )

    # The harness SOURCE ships with the test, not just the binary built from it.
    # rust_diff.sh reads the "Line: <col>\t<col>..." sentence out of its header
    # comment and prints it above a divergence, so the hex columns are labelled
    # even for an exercise with no diff_clues.txt of its own. That comment sits
    # beside the parsing code it describes, which is what stops the legend and
    # the parser drifting apart -- they are the same lines.
    harness_src = "%s/%s" % (tdir, harness)
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
        clues_f = "%s/%s" % (tdir, diff_clues)
        clue_args = ["--clues", "$(location %s)" % clues_f]
        clue_data = [clues_f]
    args += clue_args
    data += clue_data

    # ---- correctness gate: don't replay 400k cases while the curated fixture
    # is still red. Derived from the targets c_function already builds for this
    # exercise, and compared as its output test compares (_fixture_gate), NOT
    # re-declared here: a hand-written gate drifts, and a drifted gate skips
    # forever while looking green -- --sanitize changes diff_output.sh's
    # verdict.
    gate_args = []
    gate_data = []
    if gate_bin == None:
        gate_bin = ":" + stem + "_bin"
    if gate_bin:
        gate_args, gate_data = _fixture_gate(
            stem,
            "%s/%s" % (tdir, gate_expected),
            bin = gate_bin,
            stdin = gate_stdin,
        )
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
        name = stem + "_diff",
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
            fail(("c_diff(%s): sanitize = False with perf = True. The perf " +
                  "layer's gate wants :%s_diffbin_asan, which only sanitize = True " +
                  "builds. Set perf = False, or leave sanitize on.") % (_call(call), stem))
        c_perf(
            fn = fn,
            oracle_fn = oracle_fn,
            seed = seed,
            count = perf_count,
            enabled = True,
            gate_expected = gate_expected,
            gate_stdin = gate_stdin,
            gate_bin = gate_bin,
            length = perf_length,
            **_call_kw(call)
        )

    # Crash-fuzz variant (tag "diff_asan"): replay the corpus through an
    # ASan/UBSan-instrumented harness+student and assert no memory error / UB.
    # Value correctness is not checked here, so a memory-safe stub passes; this
    # catches out-of-bounds reads that return the right value on valid inputs.
    asan_count_problem = diff_asan_count_problem(num, count, asan_count, sanitize)
    if asan_count_problem:
        fail(asan_count_problem)
    if sanitize:
        asan_bin = stem + "_diffbin_asan"

        # The same unit, compiled under the sanitizer: there is no separate
        # _asan library any more, because each binary compiles what it links
        # with its own flags.
        _student_bin(
            name = asan_bin,
            harness = ["%s/%s" % (tdir, harness)],
            prototype = prototype,
            deps = lib_deps + deps,
            diffio = True,
            asan = True,
            **kw
        )
        _test(
            name = stem + "_diff_asan",
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
            r_clues_f = "%s/%s" % (tdir, readings["diff_clues"])
            r_clue_args = ["--clues", "$(location %s)" % r_clues_f]
            r_clue_data = [r_clues_f]

        # A reader of its own, or the plain one (see `readings`).
        r_bin = binname
        r_src = harness_src
        if readings.get("harness"):
            r_bin = stem + "_readingsbin"
            r_src = "%s/%s" % (tdir, readings["harness"])
            _student_bin(
                name = r_bin,
                harness = [r_src],
                prototype = prototype,
                deps = lib_deps + deps,
                diffio = True,
                **kw
            )
        r_common = [
            "--oracle",
            "$(location //oracle:oracle)",
            "--oracle-fn",
            readings["oracle_fn"],
            "--seed",
            str(seed),
        ]
        _test(
            name = stem + "_readings",
            srcs = ["//tools:rust_diff.sh"],
            args = r_common + [
                "--count",
                str(r_count),
                "--student-bin",
                "$(location :%s)" % r_bin,
                "--harness-src",
                "$(location %s)" % r_src,
            ] + r_clue_args + gate_args,
            data = ["//oracle:oracle", ":" + r_bin, r_src] + r_clue_data + gate_data,
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
        # and BSQ's readings twins (corpus_memory) carry no hints either. A
        # reading with a reader of its own has none (V299): its cases are the
        # plain corpus's, so exNN_diff_asan replays them already, and the
        # twin would run them again through the plain ASan reader -- 20000
        # cases repeated, and a crash would show the reading's reference
        # under the plain reader's "Line:", which names that column for what
        # the plain reader prints.
        if sanitize and not readings.get("harness"):
            _test(
                name = stem + "_readings_diff_asan",
                srcs = ["//tools:rust_diff.sh"],
                args = r_common + [
                    "--count",
                    str(min(r_count, asan_count)),
                    "--crash-only",
                    "--student-bin",
                    "$(location :%s)" % (stem + "_diffbin_asan"),
                    "--harness-src",
                    "$(location %s)" % harness_src,
                ] + gate_args + _symbolizer_args(),
                data = ["//oracle:oracle", ":" + stem + "_diffbin_asan", harness_src] +
                       gate_data + _SYMBOLIZER_DATA,
                size = size,
                tags = ["diff_asan"],
                level = _raise("diff_asan", r_level),
            )

def c_perf(
        num = None,
        fn = None,
        oracle_fn = None,
        harness = None,
        seed = 1,
        count = 200000,
        baseline_bin = None,
        gate_exponent = "2.6",
        gate_slowdown = "5000",
        gate_memory = "200",
        gate_bin = None,
        gate_expected = "expected.txt",
        gate_stdin = None,
        gate_asan_bin = None,
        gate_count = 4000,
        enabled = False,
        prototype = None,
        length = None,
        refusals = None,
        name = None,
        unit = None):
    """Performance layer (tag "perf"), at `complete`: it reports, and fails only past a gate.

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

    Stage 1 compares the fixture as exNN_output does: that test's --sanitize
    and --labeled are read off it (_fixture_gate), since --sanitize changes
    diff_output.sh's verdict and a gate that compared otherwise would misread
    a passing exercise as red and skip forever.

    c_diff emits this layer for every exercise it declares (perf = True, its
      default, passes enabled = True); only a c_perf written out by hand
      starts "manual" (see enabled below).
    baseline_bin: a binary that REPLAYS the corpus, to enable ratio mode.
      //oracle:oracle is NOT one — it generates rather than replays (see the
      header of tools/perf_test.sh). Leave None and the reference baseline is
      `oracle bench <oracle_fn>`, which this macro asks for with
      --baseline-oracle.
    harness: defaults to the diff harness c_diff already declares for this
      exercise, i.e. the :exNN_diffbin target.

    Args:
        num: the exercise number as a STRING -- "04", never 4. Starlark will not
            add an int to a string, so a bare 4 fails at analysis time on the
            first "ex" + num. The target is exNN_perf and every default below is
            derived from that stem (:exNN_bin, :exNN_diffbin,
            :exNN_diffbin_asan), so a wrong num misses all of them at once. In
            practice it arrives from the exercise's c_diff call, which is this
            macro's only caller in every project.
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
        gate_slowdown: CPU-time multiple over the baseline at which the test
            turns red; default "5000". Ratio mode only, so it is inert until a
            bench arm or a baseline_bin exists, and it is skipped as well when
            the reference spends under PERF_MIN_BASELINE_MS (20ms) of CPU, where
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
            1 entirely. Stages 2 and 3 still run in that case, gate_count with
            them.
        gate_expected: the fixture stage 1 diffs against, resolved under
            tests/exNN/; default "expected.txt". Unused when gate_bin is "".
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
            byte) and stage 3; default 4000, forwarded whether or not stage 1
            runs. Small on purpose: this is a precondition
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
                  <length> elements;
              "harness": a file under tests/exNN/ that reads those lines, of
                  any length, calls the function and CHECKS its result,
                  exiting 3 at the first wrong one (a wrong result is not
                  timed); built as :exNN_lenbin with the exercise's unit and
                  the grader's `linked` libraries, held to `prototype`;
              "base": the first length, default 250 (the runner doubles it
                  while a run is too short to time, and halves it on a run
                  that does not finish);
              "cases": how many lines at each length, default 20.
        refusals: in tools/tests/macro_fixtures alone, the list a refusal
            of a call on a function of a library (_member) is collected in
            instead of failing (_refuse).
        name: unused, for the reason c_levels gives: every macro takes one,
            and buildifier's unnamed-macro check holds this one to it since it
            declares a rule (a program built from the student's files, see
            _student_bin). Every target here is named from `num`, so there is
            nothing for it to control.
        unit: in a package whose subject() contract is divided into units
            (units = {...}), the unit this call judges, in place of `num`: a
            function of a library, by its own name, the project, or one part
            of a root divided into parts (subject()'s units). A call
            names one of the two, never both (_resolve). `fn` then defaults to
            that function. For a function of a library (see _member) its
            programs are <function>_diffbin, _perfbin and _lenbin, linking
            c_library()'s :<library>_lib through the turn-in's Makefile, its
            test <function>_perf, its files under tests/<function>/, and its
            gates default to :<function>_bin and :<function>_diffbin_asan.
            c_diff hands its own on. `prototype` is the library's, and refused
            here.
    """
    r = _resolve("c_perf", num, unit, refusals)  # first: a contract error names this macro
    if r == False:
        return
    num, call, function = r.key, r.call, r.function
    if fn == None:
        fn = function
    _required("c_perf", fn = fn, oracle_fn = oracle_fn)
    _entry(num, "c_perf")
    u = _member(num, function, fn, refusals, "c_perf(%s)" % _call(call), prototype = prototype)
    if u == False:
        return
    ex = _prefix(num)

    # Every target is named from `stem`, and every file is under `tdir`:
    # the exercise's or unit's, or one function's of a library (see _member).
    stem = u.stem if u else ex
    tdir = u.tdir if u else "tests/" + ex
    lib_deps = u.deps if u else [":" + _fn_lib(num, fn)]
    kw = u.kw if u else {}
    prototype = prototype or (u.proto if u else ex + "_prototype")
    deps = _linked(num).libs
    tags = ["perf"] + ([] if enabled else ["manual"])

    # Reuse c_diff's reader binary when it exists; build our own only if this
    # exercise has a perf layer without a diff layer.
    if harness == None:
        binname = stem + "_diffbin"
    else:
        binname = stem + "_perfbin"
        _student_bin(
            name = binname,
            harness = ["%s/%s" % (tdir, harness)],
            prototype = prototype,
            deps = lib_deps + deps,
            diffio = True,
            tags = ["manual"],
            **kw
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
            fail(("c_perf(%s): length takes oracle_fn and harness, and " +
                  "base and cases; got %r") % (_call(call), sorted(length.keys())))
        lenbin = stem + "_lenbin"
        _student_bin(
            name = lenbin,
            harness = ["%s/%s" % (tdir, length["harness"])],
            prototype = prototype,
            deps = lib_deps + deps,
            tags = ["manual"],
            **kw
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
    # gating on. Pass explicit values only for an exercise whose layers do not
    # follow that naming (c_libft's docstring says why every shape keeps it).
    if gate_bin == None:
        gate_bin = ":" + stem + "_bin"
    if gate_asan_bin == None:
        gate_asan_bin = ":" + stem + "_diffbin_asan"
    if gate_bin:
        gate_args, gate_data = _fixture_gate(
            stem,
            "%s/%s" % (tdir, gate_expected),
            bin = gate_bin,
            stdin = gate_stdin,
        )
        args += gate_args
        data += gate_data

    # Stages 2 and 3 run with or without stage 1, and both read the corpus
    # this sizes.
    args += ["--gate-count", str(gate_count)]
    if gate_asan_bin:
        args += ["--gate-asan-bin", "$(location %s)" % gate_asan_bin]
        data.append(gate_asan_bin)

    _test(
        name = stem + "_perf",
        srcs = ["//tools:perf_test.sh"],
        args = args,
        data = data,
        # Three runs at N, 2N, 4N plus three corpus generations. Generation
        # dominates (see the timings in tools/perf_test.sh), so keep `count`
        # well below c_diff's: this layer measures shape, not throughput.
        size = "medium",
        tags = tags,
    )

def twin_problem(num, contract):
    """Why c_twin(num = ...) is refused in this contract, or None.

    c_twin names the exercise that repeats another module's by its number,
    and a contract of units has no numbers: a unit's tests that repeat
    another module's cannot be declared a repeat, and the call named a
    tests/exNN/ folder the package does not have, which the twin rules of
    //tools:conventions then reported as two folders holding different
    files.
    """
    if contract != None and "units" in contract:
        return ("c_twin(num = %r): this package's subject() contract names units, " +
                "and c_twin declares only an exercise that repeats another module's, " +
                "by its number. Drop the call; a unit's tests are its own.") % (num,)
    return None

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
    c_program or c_header calls' `cases` token for token, in any layout, but
    for the exercise's number, and so every argument of their c_header,
    c_diff and c_cycles calls that the c_twin check's `for _mk in` loop in
    tools/conventions.sh names (that loop is the one list of them), and the
    layers that replay a corpus (hand_test and corpus_memory calls naming
    one of _CORPUS_RUNNERS), as written --
    and reports a tests/ folder that is all a copy of another module's with
    no such line. It emits nothing. In a contract of units it fails while
    loading (twin_problem): a unit has no number to name.

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
    problem = twin_problem(num, _contract_or_none())
    if problem:
        fail(problem)

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
        return (("c_diff(%s): its ASan twin would replay %d cases of a corpus " +
                 "whose plain replay value-checks %d, so %d cases would be checked for " +
                 "memory and never for their value. Raise count to at least %d, or name " +
                 "asan_count = %d or fewer.") % (_call(num), asan_count, count, asan_count - count,
                                                  asan_count, count))
    return ""
