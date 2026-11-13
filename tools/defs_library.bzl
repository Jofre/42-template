"""A turn-in built by its own Makefile, a header-only one, and the libraries.

c_make, c_header, c_libft and c_library. And the Norm's sentences a BUILD
file quotes (NORM_NO_WILDCARDS, NORM_NO_RELINK).

Loaded by the files above it, and re-exported by tools/defs.bzl, the one
file a BUILD file loads.
"""

load(
    ":defs_checks.bzl",
    _case = "case",
    _case_stem = "case_stem",
    _compile_tests = "compile_tests",
    _exit_flags = "exit_flags",
    _expected_args = "expected_args",
    _forbidden_mode_test = "forbidden_mode_test",
    _forbidden_test = "forbidden_test",
    _header_exit_error = "header_exit_error",
    _layouts = "layouts",
    _norm_test = "norm_test",
    _prototype_mode_test = "prototype_mode_test",
    _prototype_names_test = "prototype_names_test",
    _prototype_test = "prototype_test",
    _provided_names = "provided_names",
    _symbols_test = "symbols_test",
)
load(
    ":defs_contract.bzl",
    "turnin_dir",
    "turnin_glob",
    _allowed = "allowed",
    _call_kw = "call_kw",
    _deliverable_hdrs = "deliverable_hdrs",
    _deliverable_srcs = "deliverable_srcs",
    _entry = "entry",
    _goal_of = "goal_of",
    _inc_args = "inc_args",
    _linked = "linked",
    _not_build_products = "not_build_products",
    _provided = "provided",
    _refuse = "refuse",
    _required = "required",
    _resolve = "resolve",
    _student_lib = "student_lib_private",
    _zone = "zone",
)
load(":defs_cycles.bzl", _library_includes = "library_includes")
load(":defs_function.bzl", _ilp32_test = "ilp32_test")
load(
    ":defs_levels.bzl",
    _SUFFIX_LAYER = "SUFFIX_LAYER",
    _call = "call",
    _is_unit_key = "is_unit_key",
    _kind_word = "kind_word",
    _prefix = "prefix",
    _tests_folder = "tests_folder",
    _uniq = "uniq",
)
load(":defs_program.bzl", _make_anchor_problem = "make_anchor_problem")
load(
    ":defs_test.bzl",
    "runner_quotes",
    _no_orphan_prototype = "no_orphan_prototype",
    _output_fixture_binary = "output_fixture_binary",
    _test = "test",
    _waiting_args = "waiting_args",
)
load(
    ":defs_toolchain.bzl",
    _MAKE = "MAKE",
    _NOTATION_H = "NOTATION_H",
    _NOTATION_HDRS = "NOTATION_HDRS",
    _PINNED_CC_DATA = "PINNED_CC_DATA",
    _PINNED_LD_DATA = "PINNED_LD_DATA",
    _PINNED_MAKE_DATA = "PINNED_MAKE_DATA",
    _PINNED_NM_DATA = "PINNED_NM_DATA",
    _PINNED_OBJDUMP_DATA = "PINNED_OBJDUMP_DATA",
    _UNBUFFERED_C = "UNBUFFERED_C",
    _case_reads_tag = "case_reads_tag",
    _pinned_cc_args = "pinned_cc_args",
    _pinned_ld_args = "pinned_ld_args",
    _pinned_make_args = "pinned_make_args",
    _pinned_nm_args = "pinned_nm_args",
    _pinned_objdump_args = "pinned_objdump_args",
)
load(":names_file.bzl", "names_file")

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
            --shape sources, and diffs what it prints -- see the comment in the
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
        hdrs: headers turned in beside the sources. No project passes one
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
    ex = _prefix(num)
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
        "sources",
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

    # The notation's header the fixture may include (tools/notation.h), as
    # every output fixture links it: its folder, workspace-relative too.
    args += ["--inc", Label(_NOTATION_H).package]
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
        ] + _NOTATION_HDRS + srcs + hdrs + w_data,
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
    "archiver",
    "forbidden_commands",
    "forbidden_flags",
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

def _libft_make_problem(make, who = "c_libft"):
    """c_libft's or c_library's message for a `make` dict it cannot hand to c_make; None if none.

    c_library hands c_make num, artifact and symbols (the contract's
    `functions`) itself, and has no `script`: a library's build is its
    Makefile, so `script` is no argument it may carry either.
    """
    if type(make) != "dict":
        return "%s(make = %r): c_make's arguments, as a dict" % (who, make)
    own = ["num", "artifact", "symbols", "script"] if who == "c_libft" else ["num", "artifact"]
    for k in sorted(make):
        if k in own:
            return (("%s(make = {%r: ...}): %s is %s's own argument, which it " +
                     "hands to c_make itself. Pass it to %s.") % (who, k, k, who, who))
        if k == "symbols":
            return (("%s(make = {%r: ...}): the symbols the archive must hold are the " +
                     "contract's `functions`, which %s hands to c_make itself.") % (who, k, who))
        if k not in _LIBFT_MAKE_KEYS:
            return (("%s(make = {%r: ...}): no argument of c_make it may carry " +
                     "(%s; tools/defs_library.bzl's _LIBFT_MAKE_KEYS).") % (who, k, ", ".join(_LIBFT_MAKE_KEYS)))
    return None

def _quote_or_reason_problem(who, what, v, about):
    """Why `v` is neither a quoted sentence nor "none: <the reason>"; None if it is one."""
    if type(v) == "string" and v.startswith("none: ") and v[6:].strip() and "\n" not in v:
        return None
    if type(v) == "string" and v.strip() and not v.startswith("none:") and "\n" not in v and "\t" not in v:
        return None
    return (("%s: %s = %r. Quote %s, one line with where it is from " +
             "(\"Project, p.N: \\\"the sentence\\\"\"), or say why there is none: " +
             "\"none: <the reason>\".") % (who, what, v, about))

def _prototype_names_problem(who, num, p, prototype):
    """c_library's message for its prototype_names (see _library_args_problem); None if it takes it."""
    if type(p) == "string" and p.startswith("none: ") and p[6:].strip():
        return None
    if type(p) == "string" and p.endswith(".h") and "/" not in p and p != ".h" and \
       p != "prototype.h" and not p.startswith("none:"):
        if prototype == False:
            return (("%s: prototype = False says the subject fixes no prototype, so it prints " +
                     "no parameter names, and prototype_names = %r would check names nothing " +
                     "printed. Say so instead: prototype_names = \"none: <the reason>\".") % (who, p))
        return None
    return (("%s: prototype_names = %r. Name the file under %s holding the " +
             "declarations whose parameter names the subject prints, and nothing else " +
             "(prototype_names = \"prototype_names.h\": it includes nothing, and declares a " +
             "type it needs forward), or say why there is none: \"none: <the reason>\". " +
             "Never prototype.h, which states the types, and may include the library's " +
             "header.") % (who, p, _tests_folder(num)))

def _library_entry_problem(num, e, who, word, entry):
    """c_library's message for a part its contract entry makes no library; None if it is one.

    A library lists its `functions`, a box per function, and turns in a
    Makefile: each function's programs are built through it, as the grader
    builds the archive.

    Args:
      num: the part c_library was called on, an exercise ("00") or a unit
        ("libft").
      e: its contract entry.
      who: the call, for the message.
      word: what the message calls the part (_kind_word): an exercise, a
        library or a project.
      entry: what transcribes it, "exercise" or "unit".
    """
    if not (e.get("functions") or {}) and entry == "exercise":
        return (("%s: exercise %s's subject() contract lists no `functions`, so it is " +
                 "no library, and an exercise turns in none: a library is a unit of a " +
                 "contract of units, subject(units = {\"<library>\": unit(..., functions " +
                 "= {...})}) (tools/subject.bzl).") % (who, num))
    if not (e.get("functions") or {}):
        return (("%s: %s %s's subject() contract lists no `functions`, so it is " +
                 "no library. Transcribe each function's box (%s(functions = " +
                 "{...}), tools/subject.bzl).") % (who, word, num, entry))
    if "Makefile" not in (e.get("files") or []):
        return (("%s: %s %s's subject() contract turns in no Makefile, and a " +
                 "library's functions are built through it, as the grader builds " +
                 "the archive. Add it to the %s's `files`.") % (who, word, num, word))
    return None

def _library_args_problem(num, hdrs, includes, prototype_names, prototype, globals, function_lists, functions, restrict_rule = None, declares_reading = None, helpers_rule = None):
    """c_library's message for an argument it refuses; None if it takes them all.

    hdrs and includes: refused until a project needs them. Every header the
    contract lets the turn-in hold is staged already (_deliverable_hdrs),
    and an include directory or a header of the call's own would reach the
    functions' programs (through :<library>_lib) but none of the layers a runner
    compiles itself -- allocfail, method, ilp32, c_mem_check's ASan probe,
    c_cycles -- which read the turn-in's headers and its Makefile's -I
    alone (_library_includes): a library whose header needed them would be
    red there and green everywhere else. A header in a subfolder is
    reached as the grader reaches it, through the Makefile's -I.

    prototype_names: a choice the macro will not load without. A file name
    under tests/<library>/ holding the declarations whose parameter NAMES the
    subject prints, and nothing else -- never prototype.h, which states
    the TYPES and may include the library's header (a names file includes
    nothing: prototype_check.sh --names refuses one that does) -- or
    "none: <the reason>" where the subject names no parameter -- and the
    reason alone where `prototype` is False: a subject that fixes no
    prototype prints no parameter names, and a names file there would hold
    names nothing printed.

    globals: a choice the macro will not load without. The subject's
    sentence forbidding a variable outside every function, which
    <library>_globals quotes, or "none: <the reason>".

    function_lists: a choice too. {function: sentence} for exactly the
    contract's `functions`, each the sentence that gives that function its
    list (its box's External Functions row, or its part's own sentence),
    which <library>_forbidden_functions and <library>_forbidden_through
    quote under that function's red -- or "none: <the reason>". One
    sentence for every function would be untrue of most of their lists.

    restrict_rule and declares_reading: choices too, each a quoted sentence
    or "none: <the reason>" -- the reason alone where `prototype` is False,
    since both read the functions tests/<library>/prototype.h declares. The
    first is the subject's sentence forbidding `restrict` in the student's
    prototypes (<library>_prototype_restrict and
    <library>_prototype_restrict_all quote it); the second the sentence
    <library>_declares_output's reading reads (a library's header, turned
    in, declares the library's functions).

    helpers_rule: a choice too, a quoted sentence or "none: <the reason>":
    the subject's sentence keeping every helper static in its own file,
    which <library>_symbols then applies to a helper two of the library's files
    share (symbols_test.sh --no-cross) and quotes under its red. With the
    reason, such a helper may stay external, as where a subject names the
    files that share it.
    """
    who = "c_library(%s)" % _call(num)
    for k, v in [("hdrs", hdrs), ("includes", includes)]:
        if v != None:
            return (("%s: %s is refused until a project needs it. Every header the contract " +
                     "lets the turn-in hold is staged already, and %s of the call's own would " +
                     "reach the functions' programs but not the layers a runner compiles " +
                     "itself (allocfail, method, ilp32, c_mem_check's probe, c_cycles). " +
                     "Carry it to them, with a fixture, first.") % (who, k, k))
    problem = _prototype_names_problem(who, num, prototype_names, prototype)
    if problem:
        return problem
    problem = _quote_or_reason_problem(who, "globals", globals, "the subject's sentence forbidding a variable outside every function")
    if problem:
        return problem
    fl = function_lists
    if type(fl) == "dict":
        want = sorted(functions or {})
        if sorted(fl) != want:
            return (("%s: function_lists names %s; it takes exactly the contract's `functions`, " +
                     "%s, each with the sentence that gives it its list.") %
                    (who, ", ".join(sorted(fl)) or "none", ", ".join(want)))
        for f in want:
            q = fl[f]
            if type(q) != "string" or not q.strip() or q.startswith("none:") or "\n" in q or "\t" in q:
                return (("%s: function_lists[%r] = %r. Quote the sentence that gives %s its list, " +
                         "one line with where it is from.") % (who, f, q, f))
    elif not (type(fl) == "string" and fl.startswith("none: ") and fl[6:].strip() and "\n" not in fl):
        return (("%s: function_lists = %r. Quote the sentence that gives each function its list, " +
                 "as {function: sentence} for exactly the contract's `functions` -- one sentence " +
                 "for all of them is true of no list but its own -- or say why there is none: " +
                 "\"none: <the reason>\".") % (who, fl))
    for what, v, about in [
        ("restrict_rule", restrict_rule, "the subject's sentence forbidding restrict in your own prototypes"),
        ("declares_reading", declares_reading, "the sentence whose reading has the turned-in header declare each function"),
    ]:
        problem = _quote_or_reason_problem(who, what, v, about)
        if problem:
            return problem
        if prototype == False and not v.startswith("none: "):
            return (("%s: prototype = False says the subject fixes no prototype, so there is " +
                     "no %sprototype.h whose functions %s = %r would judge. Say so " +
                     "instead: %s = \"none: <the reason>\".") % (who, _tests_folder(num), what, v, what))
    return _quote_or_reason_problem(who, "helpers_rule", helpers_rule, "the subject's sentence keeping every helper static in its own file")

def c_library(
        num = None,
        artifact = "libft.a",
        hdrs = None,
        includes = None,
        prototype = True,
        prototype_names = None,
        globals = None,
        function_lists = None,
        restrict_rule = None,
        declares_reading = None,
        helpers_rule = None,
        make = None,
        refusals = None,
        name = None,
        unit = None):
    """A library's layers of the WHOLE library, once: the functions' unit, its build and its shape.

    A library (a Common Core project such as Libft) is one unit whose
    contract entry lists its `functions` (unit(functions = {...}),
    tools/subject.bzl), each with the External Functions its own box
    allows, and whose turn-in is a Makefile building one archive. What is
    the whole library's is declared here, once; what is one function's --
    its output, memory, differential corpus and costs -- is a call on that
    function (c_function, c_mem_check, c_diff, c_perf or c_cycles whose
    `unit` names it, see _member), each below this one. Emits:

      <library>_lib     the unit every function's program links, through the
                        turn-in's Makefile (a student_unit: builds nothing)
      <library>_make_bin  the Makefile's `make -Bn`, built only for what it
                        writes (manual): the -I list every layer below and
                        every function's that compiles the sources itself
                        reads (_library_includes)
      <library>_build ...  c_make over the Makefile: the archive holds
                        each of the `functions`, and what `make` asks
                        besides
      <library>_norm    norminette over every turned-in source and header
      <library>_compile_*  both campus compilers, -Wall -Wextra -Werror
      <library>_prototype  every signature tests/<library>/prototype.h
                        fixes, and the layouts the subject prints (_layouts)
      <library>_prototype_names  the parameter names the subject prints, at
                        strict: tests/<library>/<prototype_names>'s
      <library>_prototype_restrict  no `restrict` in the prototype, written or
                        through a typedef, of a function prototype.h declares,
                        in any turned-in source or header (prototype_check.sh
                        --no-restrict), which a conflicting-types compile
                        cannot see
      <library>_prototype_restrict_all  strict, this harness's reading:
                        the same of every function the turn-in declares or
                        defines, its static helpers' included
                        (--all-functions)
      <library>_declares_output  strict, this harness's reading: each
                        turned-in header, included alone, declares every function
                        prototype.h declares (--declares); red on a stub,
                        as `output` is
      <library>_forbidden  only the functions some box allows (the union, the
                        contract's `allowed`); each function's own box holds
                        its `malloc` (c_function's) and allocfail_leaks
      <library>_forbidden_functions  each function uses only its own box's
                        list: what its own code and every helper it reaches
                        reference (forbidden_symbols.sh --function), another
                        listed function held to its own list
      <library>_forbidden_through  strict, this harness's reading: what
                        another listed function uses counts against its caller too
                        (--through); its reds say so and claim no KO
      <library>_globals  no variable outside every function, external,
                        static or const (forbidden_symbols.sh --globals)
      <library>_symbols  the archive's sources export the `functions` alone
                        (functions only where <library>_globals names a
                        variable);
                        with a helpers_rule sentence, a helper one file
                        defines and another calls is no exception, and the
                        red quotes the sentence

    Refused while loading (_refuse, so the macro fixtures can watch each):
    an exercise, a unit whose contract entry lists no `functions`, a
    turn-in with no Makefile (_library_entry_problem), and an argument
    _library_args_problem refuses. subject() has held each function's name
    to the prefix rule and the reserved names already (tools/defs_contract.bzl,
    _RESERVED_UNIT_NAMES), which keep its targets from reading as the
    library's or another layer's.

    Args:
        num: an exercise's number, refused: an exercise turns in no
            library, which is a unit of a contract of units (`unit`).
        artifact: the archive the Makefile builds, as c_make takes it.
        hdrs: refused until a project needs it (_library_args_problem):
            the turned-in headers are globbed (_deliverable_hdrs).
        includes: refused until a project needs it, as hdrs.
        prototype: as c_function's: False says the subject fixes no
            prototype, and every function's harness then says so.
        prototype_names: required, a choice: the file under tests/<library>/
            holding the declarations whose parameter NAMES the subject
            prints, alone and including nothing ("prototype_names.h"; a
            type one needs is declared forward, typedef struct s_x t_x;),
            which <library>_prototype_names holds each definition's names to --
            or "none: <the reason>" where the subject prints none. Never
            prototype.h, the types' contract, which may include the
            library's header. Default None, refused: a check a project
            could forget is on with its file or off with its reason. With
            `prototype = False`, only the reason.
        globals: required, a choice: the subject's sentence forbidding a
            variable outside every function ("Project, p.N: \"...\""),
            which <library>_globals quotes, or "none: <the reason>" where it
            forbids none, and there is no <library>_globals.
        function_lists: required, a choice: {function: sentence} for
            exactly the contract's `functions`, each the sentence that gives
            that function its list -- its box's External Functions row, or
            its part's own sentence -- quoted under that function's red by
            <library>_forbidden_functions and <library>_forbidden_through;
            or "none: <the reason>", and there is neither.
        restrict_rule: required, a choice: the subject's sentence forbidding
            `restrict` in the student's own prototypes, which
            <library>_prototype_restrict and
            <library>_prototype_restrict_all quote, or "none: <the
            reason>", and there is neither. With `prototype = False`, only
            the reason.
        declares_reading: required, a choice: the sentence whose reading
            <library>_declares_output tests (a library's header, turned in,
            declares its functions), which its red quotes, or "none: <the
            reason>". With `prototype = False`, only the reason.
        helpers_rule: required, a choice: the subject's sentence keeping
            every helper static in its own file ("Project, p.N: \"...\""),
            which <library>_symbols applies to a helper two files share too
            (symbols_test.sh --no-cross) and quotes under its red; or
            "none: <the reason>", and a helper one of the library's files
            defines and another calls may stay external.
        make: more of c_make's arguments (_LIBFT_MAKE_KEYS); num, artifact
            and symbols are this macro's.
        refusals: in tools/tests/macro_fixtures alone, the list a refusal is
            collected in instead of failing (_refuse).
        name: unused, for the reason c_levels gives.
        unit: in a package whose subject() contract is divided into units
            (units = {...}), the unit this call judges, in place of `num`: a
            library or the project, by its name (a project, or a part of a
            root divided into parts, is refused, as it lists no
            `functions`). A call names one of the two, never both
            (_resolve).
    """
    r = _resolve("c_library", num, unit, refusals)  # first: a contract error names this macro
    if r == False:
        return
    num = r.key
    e = _entry(num, "c_library")
    ex = _prefix(num)
    who = "c_library(%s)" % _call(num)
    functions = e.get("functions") or {}

    # A unit is called by its kind, a library or a project, and transcribed
    # with unit(); an exercise with exercise().
    word = _kind_word(num, e)
    entry = "unit" if _is_unit_key(num) else "exercise"
    problem = _library_entry_problem(num, e, who, word, entry)
    if problem == None:
        # subject() has held every function's name to the prefix rule and
        # the reserved names (tools/defs_contract.bzl, _RESERVED_UNIT_NAMES), which
        # keep its targets from reading as the library's or another layer's.
        problem = (_libft_make_problem(make or {}, "c_library") or
                   _library_args_problem(num, hdrs, includes, prototype_names, prototype, globals, function_lists, functions, restrict_rule, declares_reading, helpers_rule))
    if _refuse(problem, refusals, who):
        return
    d = turnin_dir(num)
    srcs = _zone(_deliverable_srcs(ex))
    hdrs = _zone(_deliverable_hdrs(ex, hdrs))
    provided = _provided(num)
    linked = _linked(num)
    all_hdrs = hdrs + provided.hdrs
    extra_includes = provided.includes + (includes or [])

    # The Makefile's -I, for every layer below that compiles the sources
    # itself, and for each function's (_member's inc).
    inc = _library_includes(num, d)

    # The unit: the library's sources and headers, which each function's
    # program builds through the Makefile (see _member) -- and builds from
    # these while the Makefile compiles nothing.
    _student_lib(
        name = ex + "_lib",
        srcs = srcs + provided.srcs,
        hdrs = all_hdrs,
        includes = [d] + extra_includes,
    )
    c_make(
        artifact = artifact,
        symbols = sorted(functions),
        **dict(_call_kw(num), **(make or {}))
    )
    _norm_test(ex + "_norm", srcs + hdrs)
    if provided.hdrs:
        # As c_function's: the grader's header, a maintainer's red.
        _norm_test(ex + "_norm_provided", provided.hdrs, level = 4)
    _compile_tests(ex, srcs, all_hdrs, grader_hdrs = provided.hdrs, inc_file = inc)
    _prototype_test(
        ex,
        srcs,
        all_hdrs,
        extra_includes,
        prototype,
        layouts = _layouts(num),
        layout_certain = bool(linked.libs),
        grader_hdrs = provided.hdrs,
        inc_file = inc,
    )
    if not prototype_names.startswith("none: "):
        _prototype_names_test(ex + "_prototype_names", ex, srcs, all_hdrs, extra_includes, proto = prototype_names, inc_file = inc)
    if not restrict_rule.startswith("none: "):
        q = runner_quotes(ex + "_prototype_restrict_quotes", {"restrict": restrict_rule})
        qd = [":%s_prototype_restrict_quotes" % ex]
        _prototype_mode_test(ex + "_prototype_restrict", ex, srcs, hdrs, provided, ["--no-restrict"], q, qd, inc_file = inc)
        _prototype_mode_test(
            ex + "_prototype_restrict_all",
            ex,
            srcs,
            hdrs,
            provided,
            ["--no-restrict", "--all-functions"],
            q,
            qd,
            proto = False,
            level = _SUFFIX_LAYER["_prototype_restrict_all"][1],
            inc_file = inc,
        )
    if not declares_reading.startswith("none: "):
        _prototype_mode_test(
            ex + "_declares_output",
            ex,
            srcs,
            hdrs,
            provided,
            ["--declares"],
            runner_quotes(ex + "_declares_output_quotes", {"declares": declares_reading}),
            [":%s_declares_output_quotes" % ex],
            tags = ["output"],
            level = _SUFFIX_LAYER["_declares_output"][1],
            inc_file = inc,
        )
    allowed = _allowed(num)
    if allowed != None:
        _forbidden_test(
            ex + "_forbidden",
            srcs,
            allowed,
            hdrs = all_hdrs,
            provided = _provided_names(provided.srcs) + linked.names,
            inc_file = inc,
        )
    if not globals.startswith("none: "):
        _forbidden_mode_test(
            ex + "_globals",
            srcs,
            all_hdrs,
            ["--globals"] + runner_quotes(ex + "_globals_quotes", {"globals": globals}),
            [":%s_globals_quotes" % ex],
            inc_file = inc,
        )
    if type(function_lists) == "dict":
        lists = []
        for f in sorted(functions):
            lists += ["--function", "%s=%s" % (f, ",".join(functions[f] + e["variables"]) or "-")]
        lists += _pinned_objdump_args() + runner_quotes(
            ex + "_forbidden_functions_quotes",
            {"functions:" + f: function_lists[f] for f in function_lists},
        )
        data = [":%s_forbidden_functions_quotes" % ex] + _PINNED_OBJDUMP_DATA
        _forbidden_mode_test(ex + "_forbidden_functions", srcs, all_hdrs, lists, data, inc_file = inc)
        _forbidden_mode_test(
            ex + "_forbidden_through",
            srcs,
            all_hdrs,
            lists + ["--through"],
            data,
            level = _SUFFIX_LAYER["_forbidden_through"][1],
            inc_file = inc,
        )
    # Functions alone where exNN_globals names a variable as one; where there
    # is no exNN_globals, a variable is still this test's. With helpers_rule's
    # sentence, a helper two files share is held too, and the red quotes it.
    _symbols_test(
        ex + "_symbols",
        srcs,
        sorted(functions),
        hdrs = all_hdrs,
        functions_only = not globals.startswith("none: "),
        helpers_quote = None if helpers_rule.startswith("none: ") else helpers_rule,
        inc_file = inc,
    )

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
            these are not normed. No project needs one today. Default
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
    ex = _prefix(num)
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
            # The notation's header a case's main may include
            # (tools/notation.h): its folder, workspace-relative.
            "--inc",
            Label(_NOTATION_H).package,
        ] + compare
        data = _PINNED_CC_DATA + _PINNED_LD_DATA + [
            "//tools:diff_output.sh",
            _UNBUFFERED_C,
            hdr_f,
            case_main_f,
        ] + _NOTATION_HDRS + expected_fs + extra_f
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
# print, unnecessary, objects, relink, wildcards, archiver,
# forbidden_command, forbidden_flag) and what a rule does, where the subject
# says (all, clean, fclean, re). tools/make_test.sh --quotes reads the same
# keys.
_MAKE_QUOTE_KEYS = ["cc", "print", "unnecessary", "objects", "relink", "wildcards", "archiver", "forbidden_command", "forbidden_flag", "all", "clean", "fclean", "re"]

# The commands tools/make_test.sh always reads through to the one they run
# (its MT_WRAPS): none is ever a command word it judges, so an archiver or a
# forbidden command named one of them would judge nothing (_make_problem
# refuses it). tools/conventions.sh holds this list equal to MT_WRAPS. A
# shell is not in it: make_test.sh reads through sh, bash or dash only given
# -c STRING, and any other call of one (`sh helper.sh`) is a command word.
_MAKE_LOOKED_THROUGH = ["env", "exec", "command", "nice", "nohup", "xargs", "ccache", "distcc"]

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
        num = None,
        artifact = None,
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
        archiver = None,
        forbidden_commands = None,
        forbidden_flags = None,
        not_checked = None,
        clues = None,
        name = None,
        unit = None):
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
            relink, wildcards, archiver, forbidden_command and
            forbidden_flag back a check this macro is asked for, and
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
        archiver: the command that must make `artifact` ("ar"), for a
            subject that names it, taking ar's arguments: some command a
            bare `make` runs has it for its command word, a path, a shell
            loop, an && chain or $(AR) allowed, and creates or adds to (its
            key holds r or q) an archive named `artifact` -- or one of the
            same last component that cp, mv, ln or install then puts in
            place as `artifact`, from this folder or another (whether that
            counts is a reading, and basic keeps to what every reading
            agrees on). A member is not the archive. Read from what `make
            -n` plans, its comments and $(info ...) text left out, and
            what a stand-in on PATH logs, never from the Makefile's text.
            A line of it in a branch of the shell (then, else, elif, a
            loop's do, a case, after && or ||) that no stand-in logged is
            set aside by the rules that set $(info ...) text aside: `cat $^
            > $@ || ar rcs $@ $^` made the library with no ar, and a
            Makefile that runs the archiver only on another system is read
            as this box's shell resolves it (forbidden_commands err the
            other way, on purpose). A branch line those rules cannot judge
            counts, logged or not: the archiver by a path or behind a
            wrapper, a word the shell expands, a PATH, `.`, source or eval
            on the line, a build that stopped, or an archive the build
            wrote that no logged call and no other planned command did.
            At basic, in exNN_build, after the build made `artifact`.
            Needs the `archiver` quote. A Makefile only.
        forbidden_commands: commands no recipe of a bare `make` may run
            (["libtool"]), by command word less its path, from the same two
            records: a name only the shell spells out ($$T) is logged by a
            stand-in whether the box has the tool or not. Not seen: a call
            by a path while a plan line shows no such name, or one a
            Makefile runs past every stand-in with a PATH of its own set
            for one target. A call in a branch of the shell (then, else,
            elif, a loop's do, a case, after && or ||) is judged whether
            this box takes it or not, on its own line and on the lines the
            branch is carried to: those an if, a loop or a case left open,
            and those after a .ONESHELL line that ends on an && or an ||,
            or on a | or with a { or a ( still open in a branch. A
            conditional of make's own (ifeq on $(shell uname)) is read as
            this box's make resolves it, so a Makefile that runs the tool
            only on another system is not seen here.
            $(info ...) text is read by the same branch rule, because the
            plan alone cannot tell text from a shell line, and what it
            reads as a call is a FAIL, never a pass: the tool after a
            branch inside the text (a then, else, elif or do that starts a
            command there, a case, an && or an ||: $(info building ||
            libtool never)), and the tool in text on a later line while an
            earlier $(info ...) left such a branch open in an if, a loop
            or a case. Text that opens an if or a loop and no branch
            ($(info if needed)) carries nothing on. A build that makes no
            `artifact` is told, under its FAIL, which of them it calls,
            with the sentence (a box without the tool fails there). Only a
            bare `make` is read: a goal it does not reach (bonus) is not.
            At basic, in exNN_build. Needs the `forbidden_command` quote. A
            Makefile only. A command make_test.sh always reads through to
            the one it runs (env, ccache: _MAKE_LOOKED_THROUGH) is refused
            here and as the archiver: its name is never a command word. A
            shell is read through only given -c STRING, so `sh helper.sh`
            is a call of sh, which this can forbid.
        forbidden_flags: words no compile command may hold (["-std=c99"]),
            matched whole, so -std=c11 is another flag; read with every
            variable expanded, as make prints the command. At basic, in
            exNN_build. Needs the `forbidden_flag` quote. A Makefile only.
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
        unit: in a package whose subject() contract is divided into units
            (units = {...}), the unit this call judges, in place of `num`: a
            library, the project, or one part of a root divided into parts
            (subject()'s units), by its name. A call names one of the two,
            never both (_resolve).

    WHAT THE GRADER BRINGS -- the contract's `provided` -- is staged beside the
    student's Makefile before the build, each copy where the contract says the
    grader puts it. That is for a turn-in that is a Makefile alone: c-09 ex01
    and Piscine Reloaded ex24 both say "We'll only fetch your Makefile and test
    it with our files". The harness's copies live under tests/exNN/grader/,
    placeholders that compile, never an exercise's answer. A turn-in holding
    anything at one of those destinations, or in the top directory of one
    (srcs/, includes/), fails the test: it is an extra file in what gets
    pushed.

    A PART BUILT BY A RULE OF ITS OWN (its contract's goal) is judged by
    `make <goal>` and its exit alone: graph, relink, recipe, wildcards,
    foreign_object, archiver, forbidden_commands, forbidden_flags and rules
    are refused there, and asked for once, at the c_make of the part a bare
    make builds.
    """
    r = _resolve("c_make", num, unit, None)  # first: a contract error names this macro
    if r == False:
        return
    num = r.key
    _required("c_make", artifact = artifact)
    _entry(num, "c_make")
    ex = _prefix(num)
    symbols = symbols or []
    quotes = quotes or {}
    goal = _goal_of(num)
    for r in rules or []:
        if r not in ["all", "clean", "fclean", "re", artifact]:
            fail(("c_make(%s): rules names \"%s\", which make_test.sh has " +
                  "no check for. It checks all, clean, fclean, re and the " +
                  "artifact's own rule (\"%s\").") % (_call(num), r, artifact))
    problem = _make_problem(num, quotes, script, graph, relink, relink_source, recipe, recipe_strict, foreign_object, wildcards, not_checked, archiver, forbidden_commands, forbidden_flags, rules, goal)
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
    args = _pinned_nm_args() + _pinned_make_args() + [
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
    if goal != None:
        # A PART BUILT BY A RULE OF ITS OWN (subject()'s units): `make <goal>`
        # and how it ended, and none of the Makefile's other rules, which the
        # part a bare make builds judges (_make_problem). The subject's
        # sentence for that rule is the contract's goal_quote.
        args += ["--make-goal", goal, "--rules", "-"]
        quotes = dict(quotes, goal = _entry(num, "c_make")["goal_quote"])
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
    if archiver:
        args += ["--archiver", archiver]
    for c in forbidden_commands or []:
        args += ["--forbidden-command", c]
    for f in forbidden_flags or []:
        args += ["--forbidden-flag", f]
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
    # _uniq: nm and the binutils tools load the same libraries.
    data = turnin_glob(
        [d + "/**"],
        exclude = _not_build_products(d),
    ) + _uniq(_PINNED_NM_DATA + _PINNED_MAKE_DATA) + [_MAKE] + sorted(overlay.keys()) + quote_data + clue_data
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
    listed = [] if goal != None else (["clean", "fclean", "re"] if rules == None else rules)
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

def _make_problem(num, quotes, script = None, graph = False, relink = False, relink_source = None, recipe = None, recipe_strict = False, foreign_object = None, wildcards = False, not_checked = None, archiver = None, forbidden_commands = None, forbidden_flags = None, rules = None, goal = None):
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
        archiver: as c_make takes it.
        forbidden_commands: as c_make takes it.
        forbidden_flags: as c_make takes it.
        rules: as c_make takes it.
        goal: the contract's goal of the part c_make judges (_goal_of), or None.

    Returns:
        The message, or None.
    """
    where = "c_make(%s)" % _call(num)
    if type(quotes) != "dict":
        return "%s: quotes is a dict {key: sentence}, not %r" % (where, quotes)
    if "goal" in quotes:
        return ("%s: quotes has \"goal\", and the sentence that builds a part by a rule of its " +
                "own is the subject() contract's: its unit's goal_quote, written once there.") % where
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

    # A PART BUILT BY A RULE OF ITS OWN (its contract's goal) shares its
    # Makefile with the part a bare make builds: its c_make runs that rule,
    # and every check that judges the whole Makefile is asked for once, at
    # that other part's c_make.
    if goal != None:
        if script:
            return ("%s: this part is built by a rule of its own (make %s), and a creator " +
                    "script has no rules: a goal is a rule of the part's Makefile.") % (where, goal)
        asked = [k for k, on in [
            ("graph", graph),
            ("relink", relink),
            ("recipe", recipe != None),
            ("foreign_object", foreign_object != None),
            ("wildcards", wildcards),
            ("archiver", archiver != None),
            ("forbidden_commands", bool(forbidden_commands)),
            ("forbidden_flags", bool(forbidden_flags)),
            ("rules", rules != None),
        ] if on]
        if asked:
            said = asked[0] if len(asked) == 1 else ", ".join(asked[:-1]) + " and " + asked[-1]
            return (("%s: this part is built by a rule of its own (make %s), and %s %s the " +
                     "whole Makefile, which it shares with another part: ask for %s once, at " +
                     "the c_make of the part a bare make builds.") %
                    (where, goal, said, "judges" if len(asked) == 1 else "judge",
                     "it" if len(asked) == 1 else "them"))

    # What makes the artifact, and what a recipe may not run or pass: each a
    # command's name, or one word of a compile command, as make_test.sh
    # matches them -- a path or a blank in one would match nothing, and a
    # check that matches nothing passes every Makefile.
    names = ([("archiver", archiver)] if archiver != None else [])
    for k, v in [("forbidden_commands", forbidden_commands), ("forbidden_flags", forbidden_flags)]:
        if v != None and type(v) != "list":
            return "%s: %s is a list of strings, not %r" % (where, k, v)
        names += [(k, x) for x in (v or [])]
    for k, v in names:
        if type(v) != "string" or not v or " " in v or "\t" in v or "\n" in v:
            return "%s: %s holds %r: one word, with no blank in it." % (where, k, v)
        if k != "forbidden_flags" and ("/" in v or v.startswith("-")):
            return "%s: %s holds %r: a command's name, with no path, as its command word is matched less its path." % (where, k, v)
        if k != "forbidden_flags" and v in _MAKE_LOOKED_THROUGH:
            return "%s: %s holds %r: a command make_test.sh always reads through to the one it runs (a wrapper such as env or ccache), so no command word it judges is ever %r." % (where, k, v, v)
        if k == "forbidden_flags" and (not v.startswith("-") or v == "-"):
            return "%s: forbidden_flags holds %r: a flag, starting with -." % (where, v)
    if archiver != None and archiver in (forbidden_commands or []):
        return "%s: %s is both the archiver and a forbidden command." % (where, archiver)
    if script and (archiver != None or forbidden_commands or forbidden_flags):
        return "%s: archiver, forbidden_commands and forbidden_flags are read from a Makefile's plan, and a creator script has none." % where
    need = []
    if graph:
        need += [("graph", k) for k in ["print", "unnecessary", "objects"]]
    if recipe:
        need.append(("recipe", "cc"))
    if foreign_object:
        need.append(("foreign_object", "wildcards"))
    if wildcards:
        need.append(("wildcards", "wildcards"))
    if archiver != None:
        need.append(("archiver", "archiver"))
    if forbidden_commands:
        need.append(("forbidden_commands", "forbidden_command"))
    if forbidden_flags:
        need.append(("forbidden_flags", "forbidden_flag"))
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


# ---------------------------------------------------------------------------
# WHAT THE FILES ABOVE THIS ONE LOAD OF IT. A load() cannot name a private
# symbol, so each one they use is given a public name here, its own without
# the underscore, and loaded back under its own name: the code reads as it did
# when tools/defs.bzl held it all. These names are for those files alone; a
# BUILD file loads //tools:defs.bzl.
libft_make_problem = _libft_make_problem
library_entry_problem = _library_entry_problem
library_args_problem = _library_args_problem
make_problem = _make_problem
