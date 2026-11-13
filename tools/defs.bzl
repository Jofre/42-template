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
  c_library   -> a Common Core library: the whole library's layers once (its
                 Makefile, Norm, compilers, prototypes, forbidden, symbols),
                 and the unit each of its FUNCTIONS links -- a c_function,
                 c_mem_check, c_diff, c_perf or c_cycles call whose `unit`
                 is one function of the library's `functions`, its targets
                 <function>_*.
  c_argv_table-> one labelled table for an argv program run over many invocations.

Layers an exercise can add:
  c_diff      -> differential value + crash-fuzz against the //oracle reference
  c_mem_check -> adversarial ASan probes (exact-size / unterminated buffers)
  c_perf      -> informative cost measurement (time AND memory growth)
  c_files     -> the deliverable file SET, against the subject's turn-in line;
                 c_levels() emits one per exercise, from the contract
  c_readme    -> the README.md a subject asks for, read as Markdown: basic in no
                 language, the subject's wording at strict
  c_levels    -> the per-module suites (a level, an exercise, the manual
                 targets), and the audit of the module as a whole
  hand_test   -> a test written out in a BUILD file, derived like a macro's
  oracle_fixtures -> a project's fixtures, held to the //oracle arm that
                 writes them

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
of deliverable/ with srcs/ and includes/), c_header, c_make, c_mem_check,
c_argv_table, rush_common and shell_exercise; the other macros (c_libft,
c_perf, c_cycles, c_reference_cost, c_twin, rush_variant, student_lib) are
covered by the modules that use them and by the rules below, not by a toy. A
toy module of its own (tools/tests/macro_fixtures/levels) proves c_levels()
and hand_test(): how exercises are found, a folder that is no exercise, the
audit passed by a test declared after the call, and the kinds of a program
case. It also holds the c_diff and c_issued toys. The toy libraries
(c_library and the calls on each function) are contracts of units of their
own: tools/tests/macro_fixtures/named_lib, named_lib_make and
named_lib_broken.
The VERDICT of each toy's layers cannot be checked by a test; it is measured
by hand, with the command in that BUILD file:

  * Every program built from deliverable sources goes through _student_bin()
    (tools/defs_contract.bzl), never cc_binary or cc_library. Code that does not
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

WHERE THE MACROS LIVE. This file is the one a BUILD file loads, and it holds
no macro of its own: it re-exports, under the names a BUILD file has always
loaded, what the files beside it define. They were one file of 16,000 lines,
read with grep because nobody could read it whole; split by layer, each is a
file one can. A comment or a message that points at a table or a helper names
the one of them that defines it (//tools:conventions holds it). Each loads
only the ones listed before it (Starlark has no cyclic load), and
docs/reference.md#layout lists them too:

  defs_toolchain.bzl  the flags and the pinned tools: _COPTS, _PINNED_CC,
                      _VG_BIN, _PINNED_CC_RUNNERS, _SYMBOLIZER_RUNNERS,
                      _CAMPUS_CCS, pinned_cc_problem
  defs_levels.bzl     the levels and the names of targets: _LAYER_LEVEL,
                      _LEVEL_NAMES, _SUFFIX_LAYER, _RAISED, _MANUAL,
                      _LIB_RUNNERS, lvl_tags, _prefix, _call
  defs_contract.bzl   subject() and the contract as the macros read it:
                      subject, _entry, _resolve, turnin_dir, turnin_file,
                      turnin_glob, _zone, _deliverable_srcs, _student_bin,
                      _student_lib, _refuse, _BUILD_PRODUCTS,
                      _RESERVED_UNIT_NAMES, _TAKES_LINKED, _MEMBER_MACROS,
                      _STUDENT_BIN_SUFFIXES, _WAITING, _waits_for
  defs_test.bzl       _test and its runner tables: _test, _STANDIN_RUNNERS,
                      _RUNNER_CHOICES, _QUOTES_ONLY_WITH, _CORPUS_RUNNERS,
                      _CORPUS_RUN_OPTS, _EXIT_STATUS_RUNNERS, hand_test,
                      oracle_fixtures, stderr_ignored, runner_quotes,
                      shell_word, output_gate, _fixture_gate,
                      _gate_compare, fixture_gate_problem, corpus_memory
  defs_checks.bzl     cases, models and the static layers: _case_problem,
                      _emit_cases, _emit_model, _survive_gate,
                      _memory_gate, _compare_flags, _case_run,
                      _norm_test, _forbidden_test, _symbols_test,
                      _compile_tests, _prototype_test
  defs_function.bzl   c_function
  defs_diff.bzl       c_mem_check, c_diff, c_perf, c_twin
  defs_program.bzl    c_program, c_argv_table
  defs_files.bzl      c_files, c_issued, c_readme
  defs_cycles.bzl     c_cycles, c_reference_cost
  defs_library.bzl    c_make, c_header, c_libft, c_library, NORM_NO_WILDCARDS,
                      _LIBFT_MAKE_KEYS
  defs_shell.bzl      shell_exercise
  defs_rush.bzl       rush_common, rush_variant
  defs_module.bzl     c_levels and its audit: c_levels, _audit_problems,
                      _MODULE_TESTS, _GATE_LABEL_RUNNERS,
                      _ungated_diff_problems, contract_problem,
                      starlark_selftest_arms
"""

load(
    ":defs_checks.bzl",
    _allocfail_leaks_problem = "allocfail_leaks_problem",
    _allocfail_rule_problem = "allocfail_rule_problem",
    _fixed_array_problem = "fixed_array_problem",
    _method_problem = "method_problem",
)
load(
    ":defs_contract.bzl",
    _exercise = "exercise",
    _reserved_unit_names_problem = "reserved_unit_names_problem",
    _student_lib = "student_lib",
    _subject = "subject",
    _test_unit_rows = "test_unit_rows",
    _turnin_dir = "turnin_dir",
    _turnin_file = "turnin_file",
    _turnin_glob = "turnin_glob",
    _unit = "unit",
    _units_order_problem = "units_order_problem",
    _units_rows = "units_rows",
)
load(":defs_cycles.bzl", _c_cycles = "c_cycles", _c_reference_cost = "c_reference_cost")
load(
    ":defs_diff.bzl",
    _c_diff = "c_diff",
    _c_mem_check = "c_mem_check",
    _c_perf = "c_perf",
    _c_twin = "c_twin",
    _diff_asan_count_problem = "diff_asan_count_problem",
    _diff_readings_problem = "diff_readings_problem",
    _twin_problem = "twin_problem",
)
load(":defs_files.bzl", _c_files = "c_files", _c_issued = "c_issued", _c_readme = "c_readme")
load(":defs_function.bzl", _c_function = "c_function")
load(":defs_levels.bzl", _lvl_tags = "lvl_tags")
load(
    ":defs_library.bzl",
    _NORM_NO_RELINK = "NORM_NO_RELINK",
    _NORM_NO_WILDCARDS = "NORM_NO_WILDCARDS",
    _c_header = "c_header",
    _c_libft = "c_libft",
    _c_library = "c_library",
    _c_make = "c_make",
)
load(
    ":defs_module.bzl",
    _c_levels = "c_levels",
    _contract_problem = "contract_problem",
    _starlark_selftest_arms = "starlark_selftest_arms",
)
load(
    ":defs_program.bzl",
    _argv_guard_build = "argv_guard_build",
    _argv_guard_problem = "argv_guard_problem",
    _c_argv_table = "c_argv_table",
    _c_program = "c_program",
    _program_allocfail_choice_problem = "program_allocfail_choice_problem",
    _program_allocfail_problem = "program_allocfail_problem",
)
load(
    ":defs_rush.bzl",
    _rush_common = "rush_common",
    _rush_owed = "rush_owed",
    _rush_variant = "rush_variant",
)
load(
    ":defs_shell.bzl",
    _redirect_problem = "redirect_problem",
    _shell_call_problem = "shell_call_problem",
    _shell_exercise = "shell_exercise",
    _shell_tags_problem = "shell_tags_problem",
    _twin_fixture = "twin_fixture",
    _twin_strays = "twin_strays",
)
load(
    ":defs_test.bzl",
    _corpus_memory = "corpus_memory",
    _corpus_no_valgrind_problem = "corpus_no_valgrind_problem",
    _fixture_gate_problem = "fixture_gate_problem",
    _hand_test = "hand_test",
    _oracle_fixtures = "oracle_fixtures",
    _output_gate = "output_gate",
    _runner_quotes = "runner_quotes",
    _shell_word = "shell_word",
    _stderr_ignored = "stderr_ignored",
)
load(
    ":defs_toolchain.bzl",
    _pinned_cc_problem = "pinned_cc_problem",
    _symbolizer_problem = "symbolizer_problem",
)

# ---------------------------------------------------------------------------
# THE PUBLIC NAMES, each defined in the file the map above gives it. A name
# added there is added here too, or no BUILD file can load it.
pinned_cc_problem = _pinned_cc_problem
symbolizer_problem = _symbolizer_problem
lvl_tags = _lvl_tags
exercise = _exercise
unit = _unit
units_order_problem = _units_order_problem
subject = _subject
units_rows = _units_rows
test_unit_rows = _test_unit_rows
turnin_glob = _turnin_glob
turnin_dir = _turnin_dir
turnin_file = _turnin_file
student_lib = _student_lib
reserved_unit_names_problem = _reserved_unit_names_problem
stderr_ignored = _stderr_ignored
runner_quotes = _runner_quotes
hand_test = _hand_test
oracle_fixtures = _oracle_fixtures
output_gate = _output_gate
corpus_no_valgrind_problem = _corpus_no_valgrind_problem
fixture_gate_problem = _fixture_gate_problem
corpus_memory = _corpus_memory
shell_word = _shell_word
allocfail_leaks_problem = _allocfail_leaks_problem
allocfail_rule_problem = _allocfail_rule_problem
method_problem = _method_problem
fixed_array_problem = _fixed_array_problem
c_function = _c_function
c_mem_check = _c_mem_check
diff_readings_problem = _diff_readings_problem
c_diff = _c_diff
c_perf = _c_perf
twin_problem = _twin_problem
c_twin = _c_twin
diff_asan_count_problem = _diff_asan_count_problem
c_program = _c_program
program_allocfail_choice_problem = _program_allocfail_choice_problem
program_allocfail_problem = _program_allocfail_problem
c_argv_table = _c_argv_table
argv_guard_problem = _argv_guard_problem
argv_guard_build = _argv_guard_build
c_files = _c_files
c_issued = _c_issued
c_readme = _c_readme
c_cycles = _c_cycles
c_reference_cost = _c_reference_cost
c_libft = _c_libft
c_library = _c_library
c_header = _c_header
NORM_NO_WILDCARDS = _NORM_NO_WILDCARDS
NORM_NO_RELINK = _NORM_NO_RELINK
c_make = _c_make
twin_strays = _twin_strays
shell_call_problem = _shell_call_problem
shell_tags_problem = _shell_tags_problem
redirect_problem = _redirect_problem
twin_fixture = _twin_fixture
shell_exercise = _shell_exercise
rush_owed = _rush_owed
rush_common = _rush_common
rush_variant = _rush_variant
contract_problem = _contract_problem
c_levels = _c_levels
starlark_selftest_arms = _starlark_selftest_arms
