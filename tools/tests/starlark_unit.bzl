"""Checks of //tools:defs.bzl's pure helpers, run when this package loads.

selftest.sh drives the runners with inputs that must go red and inputs that
must stay green. A decision a MACRO makes never reaches a runner as input: it
is made while Bazel loads a BUILD file, from a glob, and all a runner sees is
the result. shell_exercise's twin guard was one: it was checked by hand, and
it failed every target in Piscine Reloaded whenever vim had a README open.
So such a decision is a function of its own, and this file calls it on
inputs written here, in both directions, and emits one test that reports
what disagreed.

Add a case beside the others when a macro gains a decision of this kind.
"""

load(
    "//tools:defs.bzl",
    "allocfail_leaks_problem",
    "allocfail_rule_problem",
    "argv_guard_build",
    "argv_guard_problem",
    "diff_asan_count_problem",
    "diff_readings_problem",
    "fixed_array_problem",
    "hand_test",
    "method_problem",
    "pinned_cc_problem",
    "program_allocfail_problem",
    "redirect_problem",
    "shell_call_problem",
    "shell_tags_problem",
    "shell_word",
    "symbolizer_problem",
    "twin_fixture",
    "twin_strays",
)

def _case(cases, what, got, want):
    """One check: WHAT, then got/want when they differ, into CASES."""
    cases.append(what if got == want else "FAIL %s: got %r, want %r" % (what, got, want))

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
        ],
        ["", "", ""],
    )
    _case(
        cases,
        "diff_readings_problem: a list, a misspelt key, no arm, a path or a strict level are refused",
        [
            "one reading per exercise" in diff_readings_problem("06", [{"oracle_fn": "x"}]),
            "is not a key" in diff_readings_problem("06", {"oracle_fn": "x", "clues": "c.txt"}),
            "names the //oracle arm" in diff_readings_problem("06", {"diff_clues": "c.txt"}),
            "a file name under" in diff_readings_problem("06", {"oracle_fn": "x", "diff_clues": "tests/ex06/c.txt"}),
            "is 3 or 4" in diff_readings_problem("06", {"oracle_fn": "x", "level": 2}),
        ],
        [True, True, True, True, True],
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

    hand_test(
        name = name,
        layer = "selftest",
        size = "small",
        srcs = ["starlark_unit.sh"],
        args = [shell_word(c) for c in cases],
    )
