"""c_function: a function exercise, linked into a harness that calls it.

And _ilp32_test, the layer that builds the same harness for a 32-bit target.

Loaded by the files above it, and re-exported by tools/defs.bzl, the one
file a BUILD file loads.
"""

load(
    ":defs_checks.bzl",
    "allocfail_leaks_problem",
    "method_problem",
    _allocfail_problem = "allocfail_problem",
    _case = "case",
    _compile_tests = "compile_tests",
    _expected_args = "expected_args",
    _forbidden_test = "forbidden_test",
    _function_malloc_problem = "function_malloc_problem",
    _layouts = "layouts",
    _norm_test = "norm_test",
    _prototype_test = "prototype_test",
    _provided_names = "provided_names",
    _raise = "raise_private",
)
load(
    ":defs_contract.bzl",
    "turnin_dir",
    _allowed = "allowed",
    _deliverable_hdrs = "deliverable_hdrs",
    _deliverable_srcs = "deliverable_srcs",
    _entry = "entry",
    _fn_lib = "fn_lib",
    _inc_args = "inc_args",
    _linked = "linked",
    _member = "member",
    _no_linked = "no_linked",
    _provided = "provided",
    _refuse = "refuse",
    _required = "required",
    _resolve = "resolve",
    _student_lib = "student_lib_private",
    _zone = "zone",
)
load(":defs_levels.bzl", _call = "call", _graded_rule = "graded_rule", _prefix = "prefix")
load(
    ":defs_test.bzl",
    _fixture_gate = "fixture_gate",
    _gate_compare = "gate_compare",
    _output_fixture_binary = "output_fixture_binary",
    _test = "test",
    _waiting_args = "waiting_args",
)
load(
    ":defs_toolchain.bzl",
    _NOTATION_H = "NOTATION_H",
    _NOTATION_HDRS = "NOTATION_HDRS",
    _PINNED_BUILD_DATA = "PINNED_BUILD_DATA",
    _PINNED_CC_DATA = "PINNED_CC_DATA",
    _PINNED_LD_DATA = "PINNED_LD_DATA",
    _PINNED_NM_DATA = "PINNED_NM_DATA",
    _UNBUFFERED_C = "UNBUFFERED_C",
    _pinned_build_args = "pinned_build_args",
    _pinned_cc_args = "pinned_cc_args",
    _pinned_ld_args = "pinned_ld_args",
    _pinned_nm_args = "pinned_nm_args",
    _valgrind_args = "valgrind_args",
    _valgrind_data = "valgrind_data",
)
load(":names_file.bzl", "names_file")

def c_function(
        num = None,
        fn = None,
        test = None,
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
        refusals = None,
        name = None,
        unit = None):
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
            No project overrides it, and c-07 ex04
            -- the one exercise whose subject asks for two files -- carries a
            comment saying not to: the file set is written down once, in the
            project's subject() contract, to be CHECKED against the directory
            rather than copied into the build.
        hdrs: more headers to stage as part of the turn-in. No project
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
            the output layer and the ilp32 replay, the two that print a table,
            and never a reading: a reading's harness is its own, and says it
            in its own case ("escaped_values": True, see `readings`), which
            //tools:conventions holds a reading's main to, whatever this says.
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
            the NULL return and c-07 ex02's the -1 return in their own words,
            and c-07 ex00's and Reloaded ex20's say "reproduce the behavior of
            strdup (man strdup)", where the man page states it.
            An exercise enabled on a weaker hook than that -- this repo's own
            rigour rather than a sentence anyone can point at -- raises itself
            here instead of dragging the cited ones up with it. Default None,
            and no project needs it today, because every exercise with the
            layer on cites a contract.
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
            another, ex04_base_to_space_output at strict. A reading's "labeled"
            and "escaped_values" are its own, never the call's: its harness
            is another program, and one that prints a value raw (with "%s")
            would have a wrong answer's backslash shown as the notation's
            if the call's flag reached it. "escaped_values": True hands its
            target --escaped-values, as `escaped_values` does the exercise's
            own, and needs "labeled": True for the same reason. Default none.
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
        refusals: in tools/tests/macro_fixtures alone, the list a refusal
            of a call on a function of a library (_member), or of
            escaped_values without labeled (the call's or a reading's), is
            collected in instead of failing (_refuse).
        name: unused, for the reason c_levels gives: every macro takes one,
            and buildifier's unnamed-macro check holds this one to it since it
            declares rules (the :fn unit, the programs). Every target here is
            named from `num` and `fn`, so there is nothing for it to
            control.
        unit: in a package whose subject() contract is divided into units
            (units = {...}), the unit this call judges, in place of `num`: a
            function of a library, by its own name, the project, or one part
            of a root divided into parts (subject()'s units). A call
            names one of the two, never both (_resolve). `fn` then defaults to
            that function. A function of a library gets its own layers alone
            (see _member) -- <function>_bin, _output, the memory, allocfail,
            method and ilp32 layers and its readings -- every file under
            tests/<function>/, its programs linking c_library()'s
            :<library>_lib through the turn-in's Makefile, and none of the
            library's own (the unit :fn, norm, compile, prototype, forbidden,
            symbols: c_library declares them once). `malloc` and
            allocfail_leaks are held to the function's own box. srcs, hdrs and
            exports are the library's, and refused here; so is `prototype`
            other than its default: c_library's <library>_prototype holds
            every function.
    """
    r = _resolve("c_function", num, unit, refusals)  # first: a contract error names this macro
    if r == False:
        return
    num, call, function = r.key, r.call, r.function
    if fn == None:
        fn = function
    _required("c_function", fn = fn, test = test)
    e = _entry(num, "c_function")
    u = _member(num, function, fn, refusals, "c_function(%s)" % _call(call), srcs, hdrs, exports, None if prototype == True else prototype)
    if u == False:
        return
    problem = _function_malloc_problem(num, malloc, dict(e, allowed = e["functions"][function]) if u else e, function)
    if problem:
        fail(problem)
    if escaped_values and not labeled and _refuse(
        ("c_function(%s) sets escaped_values but not labeled = True: " +
         "the notation is the VALUE's, and only a labeled row has one.") % _call(call),
        refusals,
        "c_function(%s)" % _call(call),
    ):
        return

    # A reading is handed the notation by its own case (see `readings`), and
    # held to the same rule as the call before anything is emitted.
    for c in readings or []:
        if type(c) == "dict" and c.get("escaped_values") and not c.get("labeled"):
            unlabeled = ("c_function(%s), reading %r sets \"escaped_values\" but not " +
                         "\"labeled\": True: the notation is the VALUE's, and only a labeled row " +
                         "has one.") % (_call(call), c.get("name", "run"))
            if _refuse(unlabeled, refusals, "c_function(%s)" % _call(call)):
                return
    ex = _prefix(num)

    # Every target this call names starts with `stem`, and every file it
    # reads is under `tdir`: the exercise's or unit's, or one function's of a
    # library (see _member).
    stem = u.stem if u else ex
    tdir = u.tdir if u else "tests/" + ex
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

    # A function's programs link the library's unit through its Makefile, and
    # the library's own layers are c_library()'s (see _member).
    if u:
        deps = u.deps
        kw = u.kw
        proto_test = u.proto
    else:
        # The unit every binary of this exercise links. It builds nothing:
        # each binary compiles it with its own flags, so the ASan twin needs
        # no library of its own.
        _student_lib(
            name = _fn_lib(num, fn),
            srcs = build_srcs,
            hdrs = all_hdrs,
            includes = includes,
        )
        deps = [":" + _fn_lib(num, fn)]
        kw = {}
        _norm_test(ex + "_norm", srcs + hdrs)

        # A provided header is still held to the Norm -- it is just not the
        # STUDENT's red. Separate target, separate name, and level 4 so it can
        # never appear in the `basic` suite a beginner runs or in the submit
        # gate: what it reports is "this repo's own staged header drifted",
        # which is a maintainer's job and nothing the person doing the
        # exercise can act on.
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

    binname = stem + "_bin"
    test_f = "%s/%s" % (tdir, test)
    _output_fixture_binary(
        name = binname,
        harness = [test_f],
        prototype = proto_test or "none: prototype = False at the call site, which says why",
        deps = deps + linked.libs,
        dir = turnin_dir(num),
        **kw
    )

    expected_f = "%s/%s" % (tdir, expected)
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
    clues_f = "%s/%s" % (tdir, clues) if clues else None
    if clues:
        args += ["--clues", "$(location %s)" % clues_f]
        out_data.append(clues_f)
    w_args, w_data = _waiting_args(stem + "_output")
    _test(
        name = stem + "_output",
        srcs = ["//tools:diff_output.sh"],
        args = args + w_args,
        data = out_data + w_data,
        tags = ["output"],
    )

    # The readings the subject leaves open, each a harness of its own over the
    # same unit, above basic (see `readings`).
    for c in readings or []:
        k = _case(c, "reading", "c_function(%s)" % _call(call))
        r_bin = "%s_%s_bin" % (stem, k.name)
        reading_test_f = "%s/%s" % (tdir, c["main"])
        _output_fixture_binary(
            name = r_bin,
            harness = [reading_test_f],
            prototype = proto_test or "none: prototype = False at the call site, which says why",
            deps = deps + linked.libs,
            dir = turnin_dir(num),
            **kw
        )
        compare, expected_fs = _expected_args(ex, k, tdir = tdir)
        r_args = ["--bin", "$(location :%s)" % r_bin, "--harness-fixture"] + compare
        r_data = [":" + r_bin] + expected_fs

        # The exercise's own output is a dump whose addresses ASLR moves:
        # so is a reading's, which runs the same function. Compared raw, a
        # correct answer's addresses would differ on every run.
        if sanitize:
            r_args.append("--sanitize")
        if c.get("labeled"):
            r_args.append("--labeled")

        # Its own harness's notation, never the call's (see `readings`); one
        # without "labeled" was refused above.
        if c.get("escaped_values"):
            r_args.append("--escaped-values")
        if c.get("clues"):
            r_clues = "%s/%s" % (tdir, c["clues"])
            r_args += ["--clues", "$(location %s)" % r_clues]
            r_data.append(r_clues)
        _test(
            name = "%s_%s_output" % (stem, k.name),
            srcs = ["//tools:diff_output.sh"],
            args = r_args,
            data = r_data,
            tags = ["output"],
            level = _raise("output", k.level),
        )
    # The gate on this exercise's own fixture, which the memory, allocfail and
    # method layers below wait for: each SKIPs while the output test is red,
    # and compares the fixture as that test does (sanitize, labeled).
    gate_head, _ = _fixture_gate(stem, expected_f, compare = False)
    gate_compare = _gate_compare(stem, sanitize, labeled)
    gate = gate_head + gate_compare

    # THE MEMORY LAYER: exNN_valgrind where the subject allows malloc, and
    # exNN_memcheck, the same run with no leak check, where it does not.
    #
    # Gated on this exercise's own fixture, like every other rigour layer.
    # Until this was wired, valgrind was the one that spoke over the top of
    # the output layer: c-12 ex06 is an unwritten stub, and it answered with
    # eight raw "indirectly lost" records rather than "your output layer is
    # still red". Leaks come last — after the function produces the right
    # bytes at all.
    #
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
    leaks = bool(malloc)
    v_args = [
        "--bin",
        "$(location :%s)" % binname,
        # No space: sh_test tokenises `args` on whitespace, so a two-word
        # label would arrive as two arguments and the second would be
        # rejected as an unknown option.
        "--label",
        "%s/%s" % (ex, fn),
    ]
    if not leaks:
        v_args.append("--no-leak-check")
    v_args += gate
    v_data = [":" + binname, expected_f, "//tools:diff_output.sh"]

    # valgrind_test.sh has implemented --clues correctly since it was
    # written -- first column only, capped at three -- and no macro had ever
    # passed it one, so the layer most likely to leave a beginner stuck
    # ("40 bytes in 1 blocks are definitely lost") was the one layer with no
    # hint attached. The renderer needed nothing; only this line was missing.
    if leaks and clues:
        v_args += ["--clues", "$(location %s)" % clues_f]
        v_data.append(clues_f)

    # The subject's sentences, where its contract says the grader judges
    # memory (memory_graded): this red then sits at basic. A run with no
    # leak check quotes only the sentence on an invalid access.
    r_args, r_data = _graded_rule(leaks = leaks)
    _test(
        name = stem + ("_valgrind" if leaks else "_memcheck"),
        srcs = ["//tools:valgrind_test.sh"],
        args = v_args + r_args + _valgrind_args(),
        data = v_data + r_data + _valgrind_data(),
        size = "small",
        tags = ["valgrind"],
    )
    problem = _allocfail_problem(call, malloc, allocfail, allocfail_rule)
    if problem:
        fail(problem)
    if allocfail_leaks:
        why = allocfail_leaks_problem(allocfail, u.allowed if u else _allowed(num))
        if why:
            fail("c_function(%s) sets allocfail_leaks, and %s" % (_call(call), why))
    if allocfail:
        _no_linked(num, "c_function", "allocfail", call)
        names_file(
            name = stem + "_allocfail_rule",
            names = [allocfail_rule],
        )
        af_f = "%s/%s" % (tdir, allocfail)
        af_args = [
            "--rule",
            "$(location :%s_allocfail_rule)" % stem,
            "--harness",
            "$(location %s)" % af_f,
            "--shim",
            "$(location //tools:allocfail_shim.c)",
            "--label",
            "%s/%s" % (ex, fn),
        ]

        # Gated on the exercise's own fixture, exactly like valgrind above:
        # a stub that returns nothing has no error path worth discussing,
        # and this layer's report would speak over the top of the one red
        # test that actually matters. The flags that say how it compares
        # come after the build's.
        af_args += gate_head
        for s in build_srcs:
            af_args += ["--src", "$(location %s)" % s]
        af_args += _inc_args("--inc", all_hdrs)
        af_inc = [u.inc] if u else []
        for f in af_inc:
            af_args += ["--inc-file", "$(location %s)" % f]
        af_args += _pinned_build_args()
        af_args += gate_compare

        # What both sweeps stage, written once: a file one of them needs,
        # the other does.
        af_data = build_srcs + all_hdrs + af_inc + _PINNED_BUILD_DATA + [
            af_f,
            ":" + binname,
            ":%s_allocfail_rule" % stem,
            expected_f,
            "//tools:allocfail_shim.c",
            "//tools:allocfail_counter.h",
            "//tools:diff_output.sh",
        ]
        _test(
            name = stem + "_allocfail",
            srcs = ["//tools:allocfail_check.sh"],
            args = af_args,
            data = af_data,
            size = "small",
            tags = ["allocfail"],
            level = allocfail_level,
            turnin = srcs,
            gated = True,
        )
        if allocfail_leaks:
            _test(
                name = stem + "_allocfail_leaks",
                srcs = ["//tools:allocfail_check.sh"],
                args = af_args + ["--leaks"],
                data = af_data,
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
        fail("c_function(%s): %s" % (_call(call), why))
    if method:
        _no_linked(num, "c_function", "method", call)
        names_file(
            name = stem + "_method_rule",
            names = [method_rule],
        )
        m_args = _pinned_cc_args() + _pinned_ld_args() + [
            "--expect",
            method,
            "--rule",
            "$(location :%s_method_rule)" % stem,
            "--harness",
            "$(location %s)" % test_f,
            "--shim",
            "$(location //tools:method_shim.c)",
            # Gated on the exercise's own fixture: a stub calls nothing twice,
            # and a wrong answer has no method worth reading yet.
        ] + gate
        for s in srcs:
            m_args += ["--src", "$(location %s)" % s]
        for s in provided_srcs:
            m_args += ["--grader-src", "$(location %s)" % s]
        m_args += _inc_args("--inc", all_hdrs)
        m_inc = [u.inc] if u else []
        for f in m_inc:
            m_args += ["--inc-file", "$(location %s)" % f]

        # The fixture is compiled here, so the notation's header it may
        # include is on the include path, as on every route (tools/notation.h).
        m_args += _inc_args("--inc", [_NOTATION_H])
        _test(
            name = stem + "_method",
            srcs = ["//tools:method_check.sh"],
            args = m_args,
            data = srcs + provided_srcs + all_hdrs + m_inc + _PINNED_CC_DATA + _PINNED_LD_DATA + [
                test_f,
                expected_f,
                ":" + binname,
                ":%s_method_rule" % stem,
                "//tools:method_shim.c",
                "//tools:diff_output.sh",
            ] + _NOTATION_HDRS,
            tags = ["method"],
            turnin = srcs,
            gated = True,
        )

    # The library's forbidden and symbols layers are c_library()'s.
    if allowed != None and not u:
        _forbidden_test(
            ex + "_forbidden",
            srcs,
            allowed,
            hdrs = all_hdrs,
            provided = _provided_names(provided_srcs) + linked.names,
        )

    # Linkage hygiene: exactly the subject's function is visible to the linker.
    if exports == None:
        exports = [] if u else [fn]
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
            stem = stem,
            inc_file = u.inc if u else None,
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
        escaped_values = False,
        stem = None,
        inc_file = None):
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
        stem: what the target's name starts with, default `ex`: a function
            of a library's own name (see _member).
        inc_file: a library's Makefile's include list (see _compile_tests
            and _member's `inc`), or None.
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
    if inc_file:
        i_args += ["--inc-file", "$(location %s)" % inc_file]

    # And the notation's header the fixture may include, as the 64-bit one
    # links it (tools/notation.h): after every folder of the turn-in's, the
    # Makefile's -I list included, so tools/ is searched last and a turn-in
    # header named like one of its own is found first.
    i_args += _inc_args("--inc", [_NOTATION_H])
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
    ] + _NOTATION_HDRS + srcs + hdrs + ([inc_file] if inc_file else [])
    if clues_f:
        i_args += ["--clues", "$(location %s)" % clues_f]
        i_data.append(clues_f)
    if linked:
        for lib in linked.libs32:
            i_args += ["--lib32", "$(location %s)" % lib]
        i_data += linked.libs32
    _test(
        name = (stem or ex) + "_ilp32",
        srcs = ["//tools:ilp32_test.sh"],
        args = i_args,
        data = i_data,
        tags = ["ilp32"],
        turnin = srcs if turnin == None else turnin,
        gated = True,
    )


# ---------------------------------------------------------------------------
# WHAT THE FILES ABOVE THIS ONE LOAD OF IT. A load() cannot name a private
# symbol, so each one they use is given a public name here, its own without
# the underscore, and loaded back under its own name: the code reads as it did
# when tools/defs.bzl held it all. These names are for those files alone; a
# BUILD file loads //tools:defs.bzl.
ilp32_test = _ilp32_test
