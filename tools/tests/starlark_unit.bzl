"""Checks of //tools:defs.bzl's pure helpers, run when this package loads.

selftest.sh drives the runners with inputs that must go red and inputs that
must stay green. A decision a MACRO makes never reaches a runner as input: it
is made while Bazel loads a BUILD file, from a glob, and all a runner sees is
the result. shell_exercise's twin guard was one: it was checked by hand, and
it failed every target in Piscine Reloaded whenever vim had a README open.
So such a decision is a function of its own, and this file calls it on
inputs written here, in both directions, and emits one test that reports
what disagreed. The fail() guards' arms are written beside the guards, in
tools/defs_module.bzl, where their private names are in reach
(starlark_selftest_arms()), and judged here with the rest: a guard that
answers wrong is this test red, never a package that fails to load.

Add a case beside the others when a macro gains a decision of this kind.
"""

load(
    "//tools:defs.bzl",
    "allocfail_leaks_problem",
    "allocfail_rule_problem",
    "argv_guard_build",
    "argv_guard_problem",
    "corpus_no_valgrind_problem",
    "diff_asan_count_problem",
    "diff_readings_problem",
    "fixed_array_problem",
    "fixture_gate_problem",
    "hand_test",
    "lvl_tags",
    "method_problem",
    "pinned_cc_problem",
    "program_allocfail_choice_problem",
    "program_allocfail_problem",
    "redirect_problem",
    "reserved_unit_names_problem",
    "shell_call_problem",
    "shell_tags_problem",
    "shell_word",
    "starlark_selftest_arms",
    "symbolizer_problem",
    "test_unit_rows",
    "twin_fixture",
    "twin_problem",
    "twin_strays",
    "unit",
    "units_order_problem",
    "units_rows",
)

def _case(cases, what, got, want):
    """One check: WHAT, then got/want when they differ, into CASES."""
    cases.append(what if got == want else "FAIL %s: got %r, want %r" % (what, got, want))

def _arm_case(cases, what, got, want):
    """One guard arm into CASES: GOT None where WANT is None, else holding WANT.

    Args:
      cases: the list the row is appended to.
      what: the arm's name.
      got: the guard's answer, a refusal or None.
      want: a substring the refusal must hold, or None for an input the
        guard must accept.
    """
    if want == None:
        cases.append(what if got == None else "FAIL %s: it refused: %s" % (what, got))
    elif got == None or want not in got:
        cases.append("FAIL %s: it answered %r, want a refusal holding %r" % (what, got, want))
    else:
        cases.append(what)

def starlark_unit(name):
    """Emits NAME, a test that fails naming each case that disagreed.

    Args:
      name: the test's name.
    """
    cases = []

    # allocfail_leaks_problem: where an exNN_allocfail_leaks target may exist.
    _case(
        cases,
        "allocfail_leaks_problem: a harness and free() allowed is fine",
        allocfail_leaks_problem("af_toy.c", ["malloc", "free"]),
        None,
    )
    _case(
        cases,
        "allocfail_leaks_problem: malloc alone is refused",
        allocfail_leaks_problem("af_toy.c", ["malloc"]) != None,
        True,
    )
    _case(
        cases,
        "allocfail_leaks_problem: no allowed line is refused",
        allocfail_leaks_problem("af_toy.c", None) != None,
        True,
    )
    _case(
        cases,
        "allocfail_leaks_problem: no allocfail harness is refused",
        allocfail_leaks_problem(None, ["malloc", "free"]) != None,
        True,
    )

    # allocfail_rule_problem: the rule an allocfail target prints is the call
    # site's, so the call site must give one.
    _case(
        cases,
        "allocfail_rule_problem: a sentence is fine",
        allocfail_rule_problem("The subject: \"a toy rule\"."),
        None,
    )
    for what, rule in [("None", None), ("an empty string", ""), ("blanks", "   ")]:
        _case(
            cases,
            "allocfail_rule_problem: %s is refused" % what,
            allocfail_rule_problem(rule) != None,
            True,
        )
    _case(
        cases,
        "allocfail_rule_problem: two lines are refused",
        allocfail_rule_problem("one\ntwo") != None,
        True,
    )

    # diff_asan_count_problem: c_diff's ASan twin replays at most the cases the
    # plain replay value-checks (V34, the owner's choice of 2026-10-04).
    _case(cases, "diff_asan_count_problem: the defaults are fine",
          diff_asan_count_problem("01", 400000, 200000, True), "")
    _case(cases, "diff_asan_count_problem: as many as the plain replay is fine",
          diff_asan_count_problem("01", 200000, 200000, True), "")
    _case(cases, "diff_asan_count_problem: a twin past the plain replay is refused",
          diff_asan_count_problem("01", 100000, 200000, True) != "", True)
    _case(cases, "diff_asan_count_problem: no twin, nothing to refuse",
          diff_asan_count_problem("01", 100000, 200000, False), "")

    # method_problem: c_function's exNN_method needs the method and the
    # sentence that asks for it, both or neither.
    toy = "the toy subject, p.1: \"Create a toy function.\""
    _case(cases, "method_problem: neither is fine", method_problem(None, None), None)
    for m in ["recursive", "iterative"]:
        _case(cases, "method_problem: %s with its sentence is fine" % m, method_problem(m, toy), None)
    _case(
        cases,
        "method_problem: a method no reading names is refused",
        method_problem("tail-recursive", toy) != None,
        True,
    )
    _case(cases, "method_problem: a method with no sentence is refused", method_problem("recursive", None) != None, True)
    _case(cases, "method_problem: a sentence with no method is refused", method_problem(None, toy) != None, True)
    _case(cases, "method_problem: two lines are refused", method_problem("iterative", "one\ntwo") != None, True)

    # fixed_array_problem: c_program's exNN_fixed_array needs the sentence,
    # and a bound only with it, in bytes above 1.
    _case(cases, "fixed_array_problem: neither is fine", fixed_array_problem(None, None), None)
    _case(cases, "fixed_array_problem: a sentence alone is fine", fixed_array_problem(toy, None), None)
    _case(cases, "fixed_array_problem: a sentence and a bound are fine", fixed_array_problem(toy, 64), None)
    _case(cases, "fixed_array_problem: a bound with no sentence is refused", fixed_array_problem(None, 64) != None, True)
    for what, b in [("0", 0), ("1", 1), ("a string", "30 ko")]:
        _case(
            cases,
            "fixed_array_problem: a bound of %s is refused" % what,
            fixed_array_problem(toy, b) != None,
            True,
        )

    # program_allocfail_problem: where c_program may emit its allocfail targets.
    mf = ["malloc", "free"]
    r = "The subject: \"a toy rule\"."
    _case(
        cases,
        "program_allocfail_problem: a named case, malloc, free allowed is fine",
        program_allocfail_problem("one", ["one", "two"], True, True, mf, r, r),
        None,
    )
    _case(
        cases,
        "program_allocfail_problem: the sweep alone needs no free()",
        program_allocfail_problem("one", ["one"], True, False, ["malloc"], r, None),
        None,
    )
    _case(
        cases,
        "program_allocfail_problem: a case that does not exist is refused",
        program_allocfail_problem("three", ["one", "two"], True, False, mf, r, None) != None,
        True,
    )
    _case(
        cases,
        "program_allocfail_problem: a list of cases, one sweep each, is fine",
        program_allocfail_problem(["one", "two"], ["one", "two"], True, False, mf, r, None),
        None,
    )
    _case(
        cases,
        "program_allocfail_problem: a list naming a case that does not exist is refused",
        program_allocfail_problem(["one", "three"], ["one", "two"], True, False, mf, r, None) != None,
        True,
    )
    _case(
        cases,
        "program_allocfail_problem: a case named twice is refused",
        program_allocfail_problem(["one", "one"], ["one", "two"], True, False, mf, r, None) != None,
        True,
    )
    _case(
        cases,
        "program_allocfail_problem: an empty list is refused",
        program_allocfail_problem([], ["one"], True, False, mf, r, None) != None,
        True,
    )
    _case(
        cases,
        "program_allocfail_problem: a subject that does not let it allocate is refused",
        program_allocfail_problem("one", ["one"], False, False, mf, r, None) != None,
        True,
    )
    _case(
        cases,
        "program_allocfail_problem: leaks without free() is refused",
        program_allocfail_problem("one", ["one"], True, True, ["malloc"], r, r) != None,
        True,
    )
    _case(
        cases,
        "program_allocfail_problem: leaks without allocfail is refused",
        program_allocfail_problem(None, ["one"], True, True, mf, r, r) != None,
        True,
    )
    _case(
        cases,
        "program_allocfail_problem: no allocfail_rule is refused",
        program_allocfail_problem("one", ["one"], True, False, mf, None, None) != None,
        True,
    )
    _case(
        cases,
        "program_allocfail_problem: leaks without its own rule is refused",
        program_allocfail_problem("one", ["one"], True, True, mf, r, None) != None,
        True,
    )
    _case(
        cases,
        "program_allocfail_problem: a leaks rule with no leak target is refused",
        program_allocfail_problem("one", ["one"], True, False, mf, r, r) != None,
        True,
    )

    # program_allocfail_choice_problem: a program whose subject lets it
    # allocate, and that has cases, chooses the sweep or says why not.
    one = [{"name": "one", "expected": "e.txt"}]
    why = "every case is a fixed table the program never grows"
    _case(
        cases,
        "program_allocfail_choice_problem: malloc, cases and neither is refused",
        program_allocfail_choice_problem(True, one, None, None) != None,
        True,
    )
    _case(
        cases,
        "program_allocfail_choice_problem: malloc, cases and allocfail is fine",
        program_allocfail_choice_problem(True, one, "one", None),
        None,
    )
    _case(
        cases,
        "program_allocfail_choice_problem: malloc, cases and a reason is fine",
        program_allocfail_choice_problem(True, one, None, why),
        None,
    )
    _case(
        cases,
        "program_allocfail_choice_problem: allocfail and a reason together are refused",
        program_allocfail_choice_problem(True, one, "one", why) != None,
        True,
    )
    _case(
        cases,
        "program_allocfail_choice_problem: a blank reason is refused",
        program_allocfail_choice_problem(True, one, None, "  ") != None,
        True,
    )
    _case(
        cases,
        "program_allocfail_choice_problem: a reason that is no string is refused",
        program_allocfail_choice_problem(True, one, None, True) != None,
        True,
    )
    _case(
        cases,
        "program_allocfail_choice_problem: no malloc asks for nothing",
        program_allocfail_choice_problem(False, one, None, None),
        None,
    )
    _case(
        cases,
        "program_allocfail_choice_problem: no cases ask for nothing",
        program_allocfail_choice_problem(True, None, None, None),
        None,
    )
    _case(
        cases,
        "program_allocfail_choice_problem: a reason where nothing asks for one is refused",
        program_allocfail_choice_problem(False, one, None, why) != None,
        True,
    )
    _case(
        cases,
        "program_allocfail_choice_problem: ...and where the runs are driven elsewhere",
        program_allocfail_choice_problem(True, None, None, why) != None,
        True,
    )
    _case(
        cases,
        "program_allocfail_choice_problem: a rule beside no_allocfail is refused",
        program_allocfail_choice_problem(True, one, None, why, "The toy rule.", None) != None,
        True,
    )
    _case(
        cases,
        "program_allocfail_choice_problem: ...and a leak rule with no sweep at all",
        program_allocfail_choice_problem(False, one, None, None, None, "The toy rule.") != None,
        True,
    )
    _case(
        cases,
        "program_allocfail_choice_problem: a rule beside allocfail is fine",
        program_allocfail_choice_problem(True, one, "one", None, "The toy rule.", None),
        None,
    )

    # symbolizer_problem: a test of a runner that shows a sanitizer's report
    # hands it the pinned symbolizer, or it is refused while loading.
    sym = ["--symbolizer", "s", "--symbolizer-lib", "l"]
    for runner, args, want in [
        ("//tools:asan_run.sh", ["--bin", "b"], True),
        ("//tools:asan_run.sh", ["--bin", "b"] + sym, False),
        ("//tools:asan_check.sh", ["--src", "x.c"], True),
        ("//tools:rust_diff.sh", ["--crash-only"], True),
        ("//tools:rust_diff.sh", ["--crash-only"] + sym, False),
        ("//tools:rust_diff.sh", ["--student-bin", "b"], False),
        ("//tools:argv_table.sh", ["--memory-only"], True),
        ("//tools:argv_table.sh", ["--bin", "b"], False),
        ("//tools:asan_run.sh", ["--bin", "b", "--symbolizer", "s"], True),
        ("//tools:perf_test.sh", ["--gate-asan-bin", "b"], False),
    ]:
        _case(
            cases,
            "symbolizer_problem: %s %s is %s" % (runner, " ".join(args), "refused" if want else "fine"),
            symbolizer_problem(runner, args) != None,
            want,
        )

    # pinned_cc_problem: a test of a runner that compiles at test time hands
    # it the pinned compiler, and one that links the pinned linker, or it is
    # refused while loading (TO VERIFY V38: asan_check and allocfail_check
    # took theirs from PATH, and c_function's symbols test was handed nm
    # alone). A mode that builds nothing (allocfail's --bin, cycles' --bin)
    # needs neither, and one that compiles without linking no --ld.
    cc = ["--cc", "c"]
    ld = ["--ld", "l"]
    mk = ["--gcc", "g", "--as", "a", "--ar", "r", "--ranlib", "n"]
    for runner, args, want in [
        ("//tools:asan_check.sh", ["--src", "x.c"], True),
        ("//tools:asan_check.sh", ["--src", "x.c"] + cc, True),
        ("//tools:asan_check.sh", ["--src", "x.c"] + cc + ld, False),
        ("//tools:allocfail_check.sh", ["--src", "x.c"] + cc, True),
        ("//tools:allocfail_check.sh", ["--src", "x.c"] + cc + ld, False),
        ("//tools:allocfail_check.sh", ["--bin", "b"], False),
        ("//tools:cycles_check.sh", ["--harness", "h.c"], True),
        ("//tools:cycles_check.sh", ["--bin", "b"], False),
        ("//tools:ref_compare.sh", ["--src", "x.c"] + cc, True),
        ("//tools:symbols_test.sh", ["--src", "x.c"], True),
        ("//tools:symbols_test.sh", ["--src", "x.c"] + cc, False),
        ("//tools:header_check.sh", ["--main", "m.c"] + cc, True),
        ("//tools:header_check.sh", ["--main", "m.c"] + cc + ld, False),
        ("//tools:method_check.sh", ["--expect", "recursive"] + cc, True),
        ("//tools:method_check.sh", ["--fixed-array"] + cc, False),
        ("//tools:diff_output.sh", ["--bin", "b"], False),
        # A Makefile's recipes compile and link (TO VERIFY V60), with the
        # whole set make_test.sh takes: the build alone is refused there.
        ("//tools:make_test.sh", ["--anchor", "a"], True),
        ("//tools:make_test.sh", ["--anchor", "a"] + cc, True),
        ("//tools:make_test.sh", ["--anchor", "a"] + cc + ld, True),
        ("//tools:make_test.sh", ["--anchor", "a"] + cc + ld + mk[:6], True),
        ("//tools:make_test.sh", ["--anchor", "a"] + cc + ld + mk, False),
    ]:
        _case(
            cases,
            "pinned_cc_problem: %s %s is %s" % (runner, " ".join(args), "refused" if want else "fine"),
            pinned_cc_problem(runner, args) != None,
            want,
        )

    # argv_guard_problem: the guarded-argv build reuses what c_program's
    # program is built from -- its sources, or its Makefile -- so it needs
    # that program declared first.
    for what, prog, want in [
        ("a program built from a list of sources", {"srcs": (":a.c",), "hdrs": (), "makefile": None, "missing_makefile": ""}, False),
        ("an empty turn-in's program", {"srcs": (), "hdrs": (), "makefile": None, "missing_makefile": ""}, False),
        ("no c_program before it", None, True),
        ("a Makefile build", {"srcs": (), "hdrs": (), "makefile": ":deliverable/Makefile", "missing_makefile": ""}, False),
        ("a Makefile build with no Makefile yet", {"srcs": (), "hdrs": (), "makefile": None, "missing_makefile": "deliverable/Makefile"}, False),
    ]:
        _case(
            cases,
            "argv_guard_problem: %s is %s" % (what, "refused" if want else "fine"),
            argv_guard_problem(prog) != None,
            want,
        )

    # argv_guard_build: the guarded-argv program is built from what the
    # graded one is, the sources a Makefile not written yet leaves to be
    # built included (c_program's makefile = "once_written"; V35).
    for what, prog, want in [
        (
            "a program built from a list of sources",
            {"srcs": (":a.c",), "makefile": None, "missing_makefile": ""},
            {"srcs": [":a.c"]},
        ),
        (
            "a Makefile build",
            {"srcs": (), "makefile": ":deliverable/Makefile", "make_data": (":deliverable/a.c",), "missing_makefile": ""},
            {"make_data": [":deliverable/a.c"], "makefile": ":deliverable/Makefile"},
        ),
        (
            "a Makefile build with its sources until the Makefile compiles any",
            {"srcs": (":a.c",), "makefile": ":deliverable/Makefile", "make_data": (":deliverable/a.c",), "missing_makefile": ""},
            {"make_data": [":deliverable/a.c"], "makefile": ":deliverable/Makefile", "srcs": [":a.c"]},
        ),
        (
            "the same with no Makefile yet",
            {"srcs": (":a.c",), "makefile": None, "missing_makefile": "deliverable/Makefile"},
            {"makefile": "deliverable/Makefile", "srcs": [":a.c"]},
        ),
        (
            "a Makefile build of a part's own rule",
            {"srcs": (), "makefile": ":deliverable/Makefile", "make_data": (":deliverable/a.c",), "missing_makefile": "", "make_goal": "bonus"},
            {"make_data": [":deliverable/a.c"], "makefile": ":deliverable/Makefile", "make_goal": "bonus"},
        ),
        (
            "a part's own rule with no Makefile yet",
            {"srcs": (), "makefile": None, "missing_makefile": "deliverable/Makefile", "make_goal": "bonus"},
            {"makefile": "deliverable/Makefile", "make_goal": "bonus"},
        ),
    ]:
        _case(cases, "argv_guard_build: " + what, argv_guard_build(prog), want)
    d = "tests/ex03/"
    readme = d + "README.md"

    # twin_strays: what a twin's own folder may hold besides its README.
    _case(
        cases,
        "twin_strays: a README alone is clean",
        twin_strays([readme], readme),
        [],
    )
    _case(
        cases,
        "twin_strays: an editor's files beside the README are no strays",
        twin_strays([
            readme,
            d + ".README.md.swp",
            d + ".README.md.swo",
            d + "README.md~",
            d + "#README.md#",
            d + ".#README.md",
            d + "4913",
            d + "README.md___jb_tmp___",
            d + ".DS_Store",
        ], readme),
        [],
    )
    _case(
        cases,
        "twin_strays: a test file copied back is a stray, a nested one too",
        twin_strays([readme, d + "check.sh", d + "clues.tsv", d + "sub/literal.sh"], readme),
        [d + "check.sh", d + "clues.tsv", d + "sub/literal.sh"],
    )
    _case(
        cases,
        "twin_strays: a file named like the README elsewhere is a stray",
        twin_strays([d + "sub/README.md", d + "README.txt"], readme),
        [d + "sub/README.md", d + "README.txt"],
    )

    # twin_fixture: a twin's fixture is its twin's when it is one of the
    # tests, and this project's own otherwise.
    t_pkg = "//c-piscine/c-piscine-shell-00"
    _case(
        cases,
        "twin_fixture: a fixture in the exercise's tests folder is the twin's",
        [
            twin_fixture("tests/ex02/fixtures/in.txt", t_pkg, "ex02"),
            twin_fixture(":tests/ex02/in.txt", t_pkg, "ex02"),
        ],
        [t_pkg + ":tests/ex02/fixtures/in.txt", t_pkg + ":tests/ex02/in.txt"],
    )
    _case(
        cases,
        "twin_fixture: any other fixture is this project's own",
        [
            twin_fixture("resources.tar.gz", t_pkg, "ex02"),
            twin_fixture("tests/ex020/in.txt", t_pkg, "ex02"),
            twin_fixture("tests/ex03/in.txt", t_pkg, "ex02"),
            twin_fixture("//other/pkg:in.txt", t_pkg, "ex02"),
        ],
        ["resources.tar.gz", "tests/ex020/in.txt", "tests/ex03/in.txt", "//other/pkg:in.txt"],
    )

    # diff_readings_problem: c_diff's one reading, a corpus of its own.
    _case(
        cases,
        "diff_readings_problem: none, or an arm with its hints, size and level, is sound",
        [
            diff_readings_problem("06", None),
            diff_readings_problem("06", {"oracle_fn": "c11_sort_string_tab_readings"}),
            diff_readings_problem("09", {"oracle_fn": "x_readings", "diff_clues": "diff_clues_readings.txt", "count": 1000, "level": 3}),
            diff_readings_problem("00", {"oracle_fn": "c03_strcmp", "harness": "diff_strcmp_readings.c"}),
        ],
        ["", "", "", ""],
    )
    _case(
        cases,
        "diff_readings_problem: a list, a misspelt key, no arm, a path, a strict level or a misnamed reader are refused",
        [
            "one reading per exercise" in diff_readings_problem("06", [{"oracle_fn": "x"}]),
            "is not a key" in diff_readings_problem("06", {"oracle_fn": "x", "clues": "c.txt"}),
            "names the //oracle arm" in diff_readings_problem("06", {"diff_clues": "c.txt"}),
            "a file name under" in diff_readings_problem("06", {"oracle_fn": "x", "diff_clues": "tests/ex06/c.txt"}),
            "is 3 or 4" in diff_readings_problem("06", {"oracle_fn": "x", "level": 2}),
            # A reader of its own (V206): a file under tests/exNN/, named as
            # c_diff's harness is, so conventions finds its "Line:" legend.
            "a file name under" in diff_readings_problem("00", {"oracle_fn": "x", "harness": "tests/ex00/diff_x.c"}),
            "is named diff_<what>.c" in diff_readings_problem("00", {"oracle_fn": "x", "harness": "exact.c"}),
            "a file name under" in diff_readings_problem("00", {"oracle_fn": "x", "harness": 3}),
        ],
        [True, True, True, True, True, True, True, True],
    )

    # shell_tags_problem: a check that reads the machine is never manual, and
    # run_tags holds only what a run needs.
    _case(
        cases,
        "shell_tags_problem: env alone, no-sandbox for the runs, and nothing at all are sound",
        [
            shell_tags_problem("01", ["env"], None),
            shell_tags_problem("04", ["env"], ["no-sandbox"]),
            shell_tags_problem("02", None, None),
            shell_tags_problem("05", ["manual"], None),
        ],
        ["", "", "", ""],
    )
    _case(
        cases,
        "shell_tags_problem: a check that reads the machine made manual is refused",
        "manual would run it on none" in shell_tags_problem("01", ["env", "manual"], None),
        True,
    )
    _case(
        cases,
        "shell_tags_problem: manual in run_tags is refused",
        "run_tags holds what a run" in shell_tags_problem("04", ["env"], ["no-sandbox", "manual"]),
        True,
    )

    # shell_call_problem: a check-mode call says whether its generator must
    # write the same turn-in every time, and its wording is one line per key.
    _case(
        cases,
        "shell_call_problem: a check-mode call that says stable either way is sound",
        [
            shell_call_problem("03", "check", True, None),
            shell_call_problem("04", "check", False, None),
            shell_call_problem("00", "diff", None, None),
            shell_call_problem("00", "diff", False, None),
        ],
        ["", "", "", ""],
    )
    _case(
        cases,
        "shell_call_problem: a check-mode call that says nothing of stable is refused",
        "say stable = True or stable = False" in shell_call_problem("04", "check", None, None),
        True,
    )
    _case(
        cases,
        "shell_call_problem: stable = True needs a check to compare the runs",
        "needs mode = \"check\"" in shell_call_problem("00", "diff", True, None),
        True,
    )
    _case(
        cases,
        "shell_call_problem: wording, a shell name to one line, spaces and quotes kept",
        shell_call_problem("02", "check", False, {"files": "all file names that end with \".sh\""}),
        "",
    )
    _case(
        cases,
        "shell_call_problem: wording keyed by no shell name, or over two lines, is refused",
        [
            "wording maps a key" in shell_call_problem("02", "check", False, {k: v})
            for k, v in [("2files", "x"), ("fi-les", "x"), ("", "x"), ("files", ""), ("files", "a\nb")]
        ],
        [True, True, True, True, True],
    )
    _case(
        cases,
        "shell_call_problem: wording needs a check to quote it",
        "needs mode = \"check\"" in shell_call_problem("00", "diff", None, {"files": "x"}),
        True,
    )

    # redirect_problem: one {path the subject fixes: fixture under tests/exNN/},
    # applied by a check script's runs.
    _case(
        cases,
        "redirect_problem: none, and one absolute path to one fixture in check mode, are sound",
        [
            redirect_problem("07", "diff", None),
            redirect_problem("07", "check", None),
            redirect_problem("07", "check", {"/etc/passwd": "passwd"}),
            redirect_problem("07", "check", {"/etc/toy.conf": "fixtures/toy.conf"}),
        ],
        ["", "", "", ""],
    )
    for what, mode, r, words in [
        ("two entries", "check", {"/a": "a", "/b": "b"}, "one {path: fixture} entry"),
        ("no entry", "check", {}, "one {path: fixture} entry"),
        ("a list", "check", ["/etc/passwd", "passwd"], "one {path: fixture} entry"),
        ("a relative path", "check", {"etc/passwd": "passwd"}, "absolute and with no"),
        ("a path with =", "check", {"/etc/a=b": "passwd"}, "absolute and with no"),
        ("the root", "check", {"/": "passwd"}, "absolute and with no"),
        ("an absolute fixture", "check", {"/etc/passwd": "/tmp/passwd"}, "a file under tests/ex07/"),
        ("a fixture above tests/exNN/", "check", {"/etc/passwd": "../ex06/passwd"}, "a file under tests/ex07/"),
        ("a fixture that is a folder", "check", {"/etc/passwd": "fixtures/"}, "a file under tests/ex07/"),
        ("an empty fixture name", "check", {"/etc/passwd": ""}, "a file under tests/ex07/"),
        ("diff mode", "diff", {"/etc/passwd": "passwd"}, "needs mode = \"check\""),
    ]:
        _case(
            cases,
            "redirect_problem: %s is refused" % what,
            words in redirect_problem("07", mode, r),
            True,
        )

    # lvl_tags: its `level` raises the one rule above its layer. No caller
    # passes it today, so this is what holds the branch.
    _case(
        cases,
        "lvl_tags: a layer alone gets its own ladder",
        lvl_tags("allocfail"),
        ["allocfail", "lvl_basic", "lvl_strict", "lvl_robust", "lvl_complete"],
    )
    _case(
        cases,
        "lvl_tags: level raises the rule up the ladder",
        lvl_tags("allocfail", level = 3),
        ["allocfail", "lvl_robust", "lvl_complete"],
    )

    # units_rows: a contract's units in the order its call writes them, a
    # library's functions right after it, "-" where a column has nothing to say.
    # An exercise turns in at its own folder and has no functions; a library
    # is a unit of a contract of units.
    _toy = {
        "exercises": {
            "00": {"dir": "ex00/", "functions": {}},
            "01": {"dir": "ex01/", "functions": {}},
        },
        "order": ["01", "00"],
        "function_order": {"00": [], "01": []},
        "mandatory": [],
    }
    _libtoy = {
        "units": {"libtoy": {"dir": None, "functions": {"toy_b": [], "toy_a": []}}},
        "order": ["libtoy"],
        "function_order": {"libtoy": ["toy_b", "toy_a"]},
        "mandatory": [],
    }
    _case(
        cases,
        "units_rows: the call's order, each exercise in its own folder, no mandatory part",
        units_rows(_toy),
        [
            "ex01\texercise\t-\tdeliverable/ex01\tfolder\t-",
            "ex00\texercise\t-\tdeliverable/ex00\tfolder\t-",
        ],
    )
    _case(
        cases,
        "units_rows: a mandatory part makes every other exercise optional",
        [r.split("\t")[2] for r in units_rows(dict(_toy, mandatory = ["00"]))],
        ["optional", "mandatory"],
    )
    # A project divided into parts at the root: each part is of kind part,
    # told written by its own files, or by the Makefile rule that builds it.
    _pfiles = {
        "units": {
            "base": unit(page = 1, files = ["toy_tally.c", "toy_tally.h"], allowed = None),
            "bonus": unit(page = 2, files = ["toy_tally_bonus.c", "toy_tally_bonus.h"], allowed = None),
        },
        "order": ["base", "bonus"],
        "function_order": {"base": [], "bonus": []},
        "mandatory": ["base"],
    }
    _case(
        cases,
        "units_rows: parts with files of their own, each judged by its files",
        units_rows(_pfiles),
        ["base\tpart\tmandatory\tdeliverable\tfiles\t-", "bonus\tpart\toptional\tdeliverable\tfiles\t-"],
    )
    _pgoal = {
        "units": {
            "sorter": unit(page = 1, files = ["Makefile"], optional = ["**/*.c", "**/*.h"], allowed = None),
            "checker": unit(page = 2, files = ["Makefile"], optional = ["**/*.c", "**/*.h"], allowed = None,
                            goal = "bonus", goal_quote = "Toy, p.2: \"make bonus builds the checker.\""),
        },
        "order": ["sorter", "checker"],
        "function_order": {"sorter": [], "checker": []},
        "mandatory": ["sorter"],
    }
    _case(
        cases,
        "units_rows: parts that share one Makefile, each judged by its rule",
        units_rows(_pgoal),
        ["sorter\tpart\tmandatory\tdeliverable\tgoal\t-", "checker\tpart\toptional\tdeliverable\tgoal\t-"],
    )
    _case(
        cases,
        "units_rows: the call's order, functions after their library",
        units_rows(_libtoy),
        [
            "libtoy\tlibrary\t-\tdeliverable\tfolder\t-",
            "toy_b\tfunction\t-\tdeliverable\tdefines\tlibtoy",
            "toy_a\tfunction\t-\tdeliverable\tdefines\tlibtoy",
        ],
    )
    _case(
        cases,
        "units_rows: a mandatory library, never its functions",
        [r.split("\t")[2] for r in units_rows(dict(_libtoy, mandatory = ["libtoy"]))],
        ["mandatory", "-", "-"],
    )
    _case(cases, "units_order_problem: the order subject() writes is fine", units_order_problem(_toy), None)
    _case(cases, "units_order_problem: ...and a library's", units_order_problem(_libtoy), None)
    for what, broken in [
        ("no order", {k: v for k, v in _toy.items() if k != "order"}),
        ("an exercise left out of the order", dict(_toy, order = ["01"])),
        ("an exercise twice", dict(_toy, order = ["01", "00", "00"])),
        ("no function_order", {k: v for k, v in _toy.items() if k != "function_order"}),
        ("an exercise with no list", dict(_toy, function_order = {"00": []})),
        ("an exercise with functions", dict(
            _toy,
            exercises = {
                "00": {"dir": "ex00/", "functions": {"toy_a": []}},
                "01": {"dir": "ex01/", "functions": {}},
            },
            function_order = {"00": ["toy_a"], "01": []},
        )),
        ("a function left out", dict(_libtoy, function_order = {"libtoy": ["toy_b"]})),
        ("a library with no list", dict(_libtoy, function_order = {})),
    ]:
        _case(cases, "units_order_problem: %s is refused" % what, units_order_problem(broken) != None, True)

    # test_unit_rows: the unit each test's tags give it, by name.
    _case(
        cases,
        "test_unit_rows: two exercises' tests, a test of the whole module, sorted",
        test_unit_rows({
            "ex01_output": ["output", "ex01", "lvl_basic"],
            "deliverable_files": ["files", "lvl_basic"],
            "ex00_toy_a_output": ["output", "ex00"],
            "ex00_build": ["build", "ex00", "ex00"],
        }),
        ["deliverable_files\t-", "ex00_build\tex00", "ex00_toy_a_output\tex00", "ex01_output\tex01"],
    )
    _case(
        cases,
        "test_unit_rows: two exercises' tags are both printed, never one picked",
        test_unit_rows({"ex01_output": ["ex01", "ex02"]}),
        ["ex01_output\tex01,ex02"],
    )
    _case(
        cases,
        "test_unit_rows: a unit's tag gives its unit, a function's included",
        test_unit_rows({
            "toy_a_output": ["output", "unit=toy_a"],
            "libtoy_build": ["unit=libtoy"],
            "deliverable_files": ["files"],
        }),
        ["deliverable_files\t-", "libtoy_build\tlibtoy", "toy_a_output\ttoy_a"],
    )

    # reserved_unit_names_problem: the names no unit may take are every
    # level, layer and target of a module's own, and the words and prefixes
    # beside them, each once: a layer added without its entry is refused here.
    _case(
        cases,
        "reserved_unit_names_problem: tools/defs.bzl's own list is fine",
        reserved_unit_names_problem(),
        None,
    )
    _case(
        cases,
        "reserved_unit_names_problem: a list missing names is refused",
        reserved_unit_names_problem(["basic"]) != None,
        True,
    )
    _case(
        cases,
        "reserved_unit_names_problem: a name nothing reserves is named",
        "frob" in (reserved_unit_names_problem(["frob"]) or ""),
        True,
    )
    _case(
        cases,
        "reserved_unit_names_problem: an empty list is refused",
        "missing:" in (reserved_unit_names_problem([]) or ""),
        True,
    )

    # twin_problem: c_twin names a repeated exercise by its number, and a
    # contract of units has none, so the call is refused there while loading.
    _case(
        cases,
        "twin_problem: an exercise of a contract of exercises is fine",
        twin_problem("27", {"exercises": {}}),
        None,
    )
    _case(
        cases,
        "twin_problem: a contract of units refuses it",
        twin_problem("00", {"units": {}}) != None,
        True,
    )
    _case(
        cases,
        "twin_problem: ...naming the call",
        'c_twin(num = "00")' in (twin_problem("00", {"units": {}}) or ""),
        True,
    )

    # corpus_no_valgrind_problem: no_valgrind where the subject allows no
    # malloc is refused, naming whose subject it is -- an exercise's in the
    # words it always had, the entry's in a contract of units.
    _case(
        cases,
        "corpus_no_valgrind_problem: malloc allowed is fine",
        corpus_no_valgrind_problem("ex05_big", "exercise", "ex05", True),
        None,
    )
    _case(
        cases,
        "corpus_no_valgrind_problem: an exercise's words are today's",
        corpus_no_valgrind_problem("ex05_big", "exercise", "ex05", False),
        ("corpus_memory(stem = \"ex05_big\"): no_valgrind, but exercise ex05's subject " +
         "allows no malloc, so there is no memcheck arm to leave out."),
    )
    _case(
        cases,
        "corpus_no_valgrind_problem: a library's names the library",
        "but library libtoy's subject" in (corpus_no_valgrind_problem("ft_toylen_big", "library", "libtoy", False) or ""),
        True,
    )

    # fixture_gate_problem: a gate reads its comparison off the output test it
    # waits for, so one with no such test above it is refused, by name.
    _case(
        cases,
        "fixture_gate_problem: an output test declared above is fine",
        fixture_gate_problem("ex05", {"kind": "sh_test"}),
        None,
    )
    _case(
        cases,
        "fixture_gate_problem: none declared names the test",
        "a gate on ex05_output: no test of that name" in (fixture_gate_problem("ex05", None) or ""),
        True,
    )
    _case(
        cases,
        "fixture_gate_problem: a rule that is no test is none",
        "no test of that name" in (fixture_gate_problem("ex05", {"kind": "filegroup"}) or ""),
        True,
    )

    # The fail() guards, each on an input it must refuse and one it must
    # accept (tools/defs_module.bzl, starlark_selftest_arms).
    arms, apostrophe = starlark_selftest_arms()
    for what, got, want in arms:
        _arm_case(cases, what, got, want)

    hand_test(
        name = name,
        layer = "selftest",
        size = "small",
        srcs = ["starlark_unit.sh"],
        # Each case as one argument, through shell_word, as an exit_quote
        # reaches diff_output.sh: Bazel expands args and then tokenises them
        # like a shell. The script counts them, and checks that a sentence
        # with apostrophes and '$' arrived whole -- quoted any other way, it
        # splits, loses a '$', or the package fails to load on an
        # unterminated quote or a '$' Bazel cannot expand.
        args = [
            "--cases",
            str(len(cases)),
            "--apostrophe",
            shell_word(apostrophe),
        ] + [shell_word(c) for c in cases],
    )
