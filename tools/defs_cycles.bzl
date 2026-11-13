"""c_cycles and c_reference_cost: an exercise's cost, counted in instructions.

Loaded by the files above it, and re-exported by tools/defs.bzl, the one
file a BUILD file loads.
"""

load(
    ":defs_contract.bzl",
    "turnin_glob",
    _LIBRARY_INCLUDES = "LIBRARY_INCLUDES",
    _deliverable_hdrs = "deliverable_hdrs",
    _deliverable_srcs = "deliverable_srcs",
    _entry = "entry",
    _inc_args = "inc_args",
    _linked = "linked",
    _member = "member",
    _not_build_products = "not_build_products",
    _provided = "provided",
    _refuse = "refuse",
    _required = "required",
    _resolve = "resolve",
    _student_bin = "student_bin",
    _zone = "zone",
)
load(":defs_levels.bzl", _call = "call", _prefix = "prefix")
load(":defs_test.bzl", "shell_word", _fixture_gate = "fixture_gate", _test = "test")
load(
    ":defs_toolchain.bzl",
    _NOTATION_H = "NOTATION_H",
    _NOTATION_HDRS = "NOTATION_HDRS",
    _PINNED_BUILD_DATA = "PINNED_BUILD_DATA",
    _VG_CALLGRIND = "VG_CALLGRIND",
    _pinned_build_args = "pinned_build_args",
    _valgrind_args = "valgrind_args",
    _valgrind_data = "valgrind_data",
)

def _library_includes(num, d):
    """The -I list of a library's Makefile, written once; its label.

    A LIBRARY'S INCLUDE PATH IS ITS MAKEFILE'S. Each function's program is
    built through the Makefile (_member's kw), so a header the library
    keeps in a subfolder (inc/toy.h, reached by `-I inc`) is found there;
    every layer that compiles the sources itself -- the compile, forbidden,
    prototype and symbols layers of the whole library, and a function's ilp32,
    allocfail, method, asan and cycles -- compiled with no -I, found no
    header, and blamed the include path or 32-bit portability (V198).
    ft_printf's subject allows `*/*.h` and keeps the student's libft in a
    folder of its own. One manual build of the Makefile, the same
    `make -Bn` every function's program reads, writes the list
    (tools/student_build.sh --includes-out), and each of those layers reads
    it as --inc-file; empty where the Makefile passes no -I, is not written
    yet, or compiles nothing (the layers then compile as before). It also
    writes the .c list, which the files layer reads where the contract
    allows .c by pattern (_manifest_build), so the Makefile is planned once.

    Args:
        num: the exercise.
        d: its turn-in directory (turnin_dir(num)).
    """
    ex = _prefix(num)
    _student_bin(
        name = ex + "_make_bin",
        makefile = d + "/Makefile",
        includes_out = ex + "_make_bin_includes.txt",
        sources_out = ex + "_make_bin_sources.txt",
        make_data = turnin_glob([d + "/**"], exclude = _not_build_products(d)),
        tags = ["manual"],
    )
    return _LIBRARY_INCLUDES % ex

def _budget_problem(call, budget, unit_expr, syscall_budget, output_is_input):
    """Why c_cycles refuses one of its budgets, or None.

    An instruction budget with no unit_expr is a budget per call, a figure
    with nothing to be read against (c_cycles' unit_expr). A budget of
    write() calls holds for only one way of handing a function's output to
    write() when that output is not the input it was given, so it would
    recommend that way over the others (c_cycles' syscall_budget). 0 says
    the function has no business entering the kernel, and stays open.
    """
    if budget and not unit_expr:
        return ("c_cycles(%s): budget = %s, and no unit_expr. A budget per call " +
                "has nothing to be read against: name the unit it is per " +
                "(unit_expr), one every correct answer must read or write, or " +
                "drop the budget, and the figure is printed alone.") % (_call(call), budget)
    if syscall_budget == None or syscall_budget <= 0 or output_is_input:
        return None
    return ("c_cycles(%s): syscall_budget = %s, and output_is_input is not set. " +
            "A write() budget on a function whose output is not the input it " +
            "was handed holds for only one way of handing that output to " +
            "write(), and would recommend it over the others: drop the budget, " +
            "or set output_is_input = True where the function writes the bytes " +
            "it was handed, as they are.") % (_call(call), syscall_budget)

def c_cycles(
        num = None,
        fn = None,
        oracle_fn = None,
        harness = None,
        unit_expr = None,
        unit_name = "case",
        budget = None,
        syscall_budget = None,
        output_is_input = False,
        srcs = None,
        hdrs = None,
        count = 3000,
        max_unit = None,
        gate_expected = "expected.txt",
        gate_stdin = None,
        refusals = None,
        unit = None):
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
    gate, run every syscall_budget = 0 target first — a function that
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
        fn: the student's function, by name. It is the symbol callgrind
            collects inside (--toggle-collect), so the figure covers everything
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
            here rather than reused, for the -O2 reason above, from the
            harness, srcs, what the grader brings (the contract's `provided`)
            and the grader's own archives (the contract's `linked`, passed as
            --lib and linked after the sources). The harness and srcs are
            built with debug information, and the harness's alone is marked
            (cycles_check.sh's -fdebug-prefix-map). That mark is how the
            runner tells the student's calls (a helper's write() or malloc(),
            or a grader function such as C 12's ft_create_elem that the
            subject makes them call) from the harness's (a callback it hands
            over).
        unit_expr: an awk expression over ONE tab-separated corpus line, summed
            across the corpus to give the denominator of the per-unit figure.
            Default None means one unit per case, i.e. a per-call number, which
            is the figure the paragraph above says has nothing to be read
            against -- so most callers set it, and a call with a budget must.
            The unit is every input byte the function must read at least once
            (a floor that is the same whatever technique is used), or what it
            must write: read each harness's own "Line:" comment for which
            fields those are -- copying another
            exercise's expression is how C 07 ex03 came to count the digits of
            a decimal size. It reads no column that "Line:" does not name: one
            the reference's corpus adds of its own (how many turns its own
            loop made) counts one technique's work, no floor every answer
            shares, and //tools:conventions reports one, budget or not. Corpus fields are hex-encoded (tools/diffio.h
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
            was measured from. It is read against the
            figure WITHOUT the allocator: malloc() and free() are counted in
            the figure and shown beside it, and how many blocks to ask for is
            the student's choice. Optional, and refused without a unit_expr
            (a budget per call); without one the per-unit figure is printed
            bare, with nothing to read it against. With one the runner says
            "at or near the budget", "some slack, nothing alarming", or "about
            Nx the budget ... what is the loop doing that it need not?" -- and then
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
            to write(), so it would recommend that way over the others. So a
            positive syscall_budget is refused unless output_is_input says
            the function writes the bytes it was handed. Counted for the
            student's own functions, helpers included, and never for a
            callback the harness hands over.
        output_is_input: True says the function writes the bytes it was
            handed, as they are and nothing else, the one kind of function
            a positive syscall_budget may be set on (above). Default False.
            It is the call site's statement, read here and passed to no
            test.
        srcs: the deliverable sources compiled with the harness at -O2. Default
            None globs deliverable/exNN/*.c through _deliverable_srcs(), which
            is what every project relies on today; the parameter survives as
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
            forces it open. It compares the fixture as exNN_output does, its
            --sanitize and --labeled read off that test (_fixture_gate), so
            call this below the c_function or c_libft that declares it.
        gate_stdin: a file LABEL fed to the gate run's stdin, for an exercise
            whose fixture reads input rather than taking argv. Passed through
            as given -- unlike gate_expected it is not resolved under
            tests/exNN/. No project passes one today; it is wired to `data`
            the way c_diff and c_perf wire theirs, because it used to expand the
            label with $(location) and NOT declare it, which would have failed
            analysis for whoever passed the first one.
        refusals: in tools/tests/macro_fixtures alone, the list a refusal
            of a call on a function of a library (_member) is collected in
            instead of failing (_refuse).
        unit: in a package whose subject() contract is divided into units
            (units = {...}), the unit this call judges, in place of `num`: a
            function of a library, by its own name, the project, or one part
            of a root divided into parts (subject()'s units). A call
            names one of the two, never both (_resolve). `fn` then defaults to
            that function. For a function of a library (see _member) the test
            is <function>_cycles, its harness and gate file are under
            tests/<function>/, and its gate is :<function>_bin,
            <function>_output. The runner still compiles the library's sources
            at -O2 and counts `fn` alone. srcs and hdrs are the library's, and
            refused here.
    """
    r = _resolve("c_cycles", num, unit, refusals)  # first: a contract error names this macro
    if r == False:
        return
    num, call, function = r.key, r.call, r.function
    if fn == None:
        fn = function
    _required("c_cycles", fn = fn, oracle_fn = oracle_fn, harness = harness)
    if _refuse(_budget_problem(call, budget, unit_expr, syscall_budget, output_is_input), refusals, "c_cycles(%s)" % _call(call)):
        return
    _entry(num, "c_cycles")
    u = _member(num, function, fn, refusals, "c_cycles(%s)" % _call(call), srcs, hdrs)
    if u == False:
        return
    libs = _linked(num).libs
    ex = _prefix(num)

    # Every target is named from `stem`, and every file is under `tdir`:
    # the exercise's or unit's, or one function's of a library (see _member).
    stem = u.stem if u else ex
    tdir = u.tdir if u else "tests/" + ex

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
    harness_f = "%s/%s" % (tdir, harness)
    expected_f = "%s/%s" % (tdir, gate_expected)

    # The gate on the exercise's own fixture (_fixture_gate): its SKIP line
    # names the output test, which the audit holds to the gate's program and
    # file (_waits_for).
    gate, _ = _fixture_gate(stem, expected_f, stdin = gate_stdin)
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
    ] + gate
    for src in srcs:
        args += ["--src", "$(location %s)" % src]
    args += _inc_args("--inc", hdrs)

    # A function's library: its Makefile's -I, as every build of it has them.
    inc = [u.inc] if u else []
    for f in inc:
        args += ["--inc-file", "$(location %s)" % f]

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
            fail("c_cycles(%s): max_unit counts units, and unit_expr says what one is" % _call(call))
        args += ["--max-unit", str(max_unit)]
    if budget:
        args += ["--budget", str(budget)]
    if syscall_budget != None:
        args += ["--syscall-budget", str(syscall_budget)]
    extra_data = [gate_stdin] if gate_stdin else []

    _test(
        name = stem + "_cycles",
        srcs = ["//tools:cycles_check.sh"],
        args = _pinned_build_args() + args + _valgrind_args(tool = _VG_CALLGRIND),
        data = _valgrind_data(tool = _VG_CALLGRIND) + _PINNED_BUILD_DATA + [
            "//oracle:oracle",
            "//tools:diff_output.sh",
            "//tools:diffio.h",
            harness_f,
            expected_f,
            ":%s_bin" % stem,
        ] + srcs + hdrs + inc + libs + extra_data,
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
    a row in docs/reference.md (tools/conventions.sh holds the two together),
    and a decision about where it sits in the submit gate's ladder. None of
    that would buy anything here.

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
    tests/exNN/expected.txt, the very targets c_function already declares,
    compared as exNN_output compares them, its --sanitize and --labeled read
    off that test (_fixture_gate). There is deliberately no gate_stdin knob
    -- no project needs one, and a pass-through nobody has ever run is how a
    gate ends up silently misreading a passing exercise as red and skipping
    forever. Add it WITH a caller that exercises it.
    """
    _entry(num, "c_reference_cost")  # first: a contract error names this macro
    ex = _prefix(num)

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
    ] + _fixture_gate(ex, expected_f)[0]
    for src in srcs:
        args += ["--src", "$(location %s)" % src]
    args += _inc_args("--inc", hdrs)

    # The harness is the exercise's output fixture, so it may include the
    # notation's headers its 64-bit build links (tools/notation.h): their
    # folder joins the path after the turn-in's own, so it is searched last.
    args += _inc_args("--inc", [_NOTATION_H])

    _test(
        name = ex + "_refcost",
        srcs = ["//tools:ref_compare.sh"],
        args = _pinned_build_args() + args + _valgrind_args(tool = _VG_CALLGRIND),
        data = _valgrind_data(tool = _VG_CALLGRIND) + _PINNED_BUILD_DATA + [
            "//oracle:oracle",
            "//tools:diff_output.sh",
            harness_f,
            expected_f,
            ":%s_bin" % ex,
        ] + _NOTATION_HDRS + srcs + hdrs,
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


# ---------------------------------------------------------------------------
# WHAT THE FILES ABOVE THIS ONE LOAD OF IT. A load() cannot name a private
# symbol, so each one they use is given a public name here, its own without
# the underscore, and loaded back under its own name: the code reads as it did
# when tools/defs.bzl held it all. These names are for those files alone; a
# BUILD file loads //tools:defs.bzl.
library_includes = _library_includes
