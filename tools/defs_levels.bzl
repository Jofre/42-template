"""The levels, and the names of an exercise's targets.

_LAYER_LEVEL gives each layer its level, _SUFFIX_LAYER the layer and level the
end of a target's name says, _RAISED the targets raised above their layer and
_MANUAL the manual ones; lvl_tags() turns a level into the cumulative lvl_*
tags. tools/first_red.sh and 42 (tools/fortytwo/workspace.py) read
_LAYER_LEVEL, _SUFFIX_LAYER and _RAISED from this file as text, and
//tools:conventions holds docs/reference.md's tables to them, so each keeps one
entry a line. And the helpers that name an exercise's targets and units
(_prefix, _key, _call, _unit_tag).

Loaded by the files above it, and re-exported by tools/defs.bzl, the one
file a BUILD file loads.
"""

load(":subject.bzl", "contract_or_none")

# Which gate level each layer belongs to. Same ladder //tools:submit uses:
#   1 basic    — every layer whose failure is an outright KO wherever the project
#                is graded: at the Moulinette, or at a defense (the rushes)
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
#                        c-04 ex00/ex01 restate C 01's ft_strlen and
#                        ft_putstr, and c-09 ex00's library C 01's ft_swap,
#                        ft_putstr and ft_strlen, which C 01 already fuzzes
#                        against the oracle (c-09 ex00's ft_strcmp has a c_diff
#                        of its own, and its ft_putchar, C 00's, is fuzzed
#                        nowhere, for the reason C 00 gives). That corpus is
#                        not coverage in the later module, which is graded on
#                        its own files: what it pins that every reading agrees
#                        on (a byte above 0x7f counted, written) goes in the
#                        later module's own output fixture.
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
    # Basic instead in a project whose subject() says its grader judges
    # memory (memory_graded; _layer_level, below).
    "valgrind": 2,
    # HOW the turn-in is built, where a subject says so and no output can
    # show it: "Create a recursive function", "Create an iterative
    # function", "by declaring a fixed-size array ... slightly less than 30
    # ko" (tools/method_check.sh). STRICT: the sentence is the subject's own,
    # but the grader only runs the program, so only an evaluator reading the
    # code marks it -- "real, but not certain" (WP-90, findings 065, 114).
    "method": 2,
    # LEVEL 2, not 3, and a demonstration shows why. Take an invented loop that
    # counts a string's bytes while `*s > 0`, where it meant to count up to the
    # terminating NUL -- the signed-char trap: where plain char is signed, a
    # byte >= 0x80 reads as negative and ends the count early. It compiles
    # clean under -Wall -Wextra -Werror, and norminette has nothing to say
    # about it. Only a string holding a byte >= 0x80 shows the wrong number,
    # and in c-01 a trap of that kind is seen by exNN_diff alone: the
    # hand-written fixture of the exercise that counts a string's bytes
    # carries no byte above 0x7f, while the generated corpora seed
    # 0x7f/0x80/0xff on purpose. So the layer holding the interesting bytes was
    # the one held above the gate. (Some fixtures do carry such bytes -- c-03's,
    # and c-04 ex00/ex01's and c-09 ex00's, whose own modules have no corpus for
    # them -- and those go red on the trap at basic.)
    #
    # Not level 1, though, and the difference from `output` is real: a
    # differential compares against a reference this repo wrote, over inputs
    # nobody typed, so a disagreement can be a place the subject left open
    # rather than a mistake. That is the same "real but not certain" line
    # `symbols` and `valgrind` sit on. One test genuinely does assert an
    # interpretation and says so at its call site -- c-06 ex03 -- and it raises
    # itself back to 3 rather than the whole layer staying there.
    "diff": 2,
    # STAYS AT 3, and must: it is emitted --crash-only (rust_diff.sh does not
    # compare values on this arm), so what it reports is a sanitizer finding
    # over generated input, or a replay an exit() in the function cut short.
    # No 42 grader runs a sanitizer.
    "diff_asan": 3,
    "asan": 3,
    # Refusing one allocation at a time. LEVEL 1, and it was 3 for a reason that
    # did not survive being looked at: "the exercise it is wired to does state
    # the requirement verbatim, but nothing proves the Moulinette exercises that
    # branch". That is an argument about the GRADER's test vectors, and the
    # level it justified left a live NULL dereference -- c-07 ex00's ft_strdup,
    # which calls malloc and dereferences the result with nothing in between --
    # red in this suite and green at the gate every fork actually submits
    # against. `bazel run //tools:submit` pushed it.
    #
    # Every c_function that enables this layer at its own level cites a contract
    # for it. c-08 ex04's subject says "It should return a NULL pointer if an
    # error occurs"; c-07 ex02's says "The size of range should be returned (or
    # -1 on error)"; c-07 ex00's, and Reloaded's ex20, which is the same
    # exercise, say "Reproduce the behavior of the function strdup (man
    # strdup)", and that man page states the NULL return. (c_program's sweeps
    # share the layer but sit at robust by suffix, _program_allocfail in
    # _SUFFIX_LAYER, and state their own rule.) None is this repo inventing a
    # requirement, which is the only thing level 1 has to be protected from --
    # and the layer stays DELIBERATELY OPT-IN per exercise, so an exercise with
    # no such sentence never meets it at all (see c_function's `allocfail`, and
    # `allocfail_level` for one enabled on a weaker hook).
    #
    # What this costs, measured: //c-piscine/c-piscine-c-07 blocks at the default gate.
    # That is the point.
    "allocfail": 1,
    "ilp32": 4,
    "perf": 4,
    "cycles": 4,
    "oracle": 4,
    "selftest": 4,
}

_LEVEL_NAMES = ["basic", "strict", "robust", "complete"]

# THE ONE LEVEL A SUBJECT LOWERS. A subject that says its grader judges
# memory -- subject(memory_graded = ...), Libft's "Memory leaks will not be
# tolerated." -- makes a leak a KO wherever that project is graded, so there
# the valgrind layer sits at basic instead of the strict above. It is the one
# change of level that goes DOWN, and a fact of the project declared once in
# its contract: never a target's `level` (which only raises), never a
# _RAISED row, never a table of targets. _test() derives every test's tags
# from it (_layer_level), _raise() a case's floor, and c_levels()' audit
# holds every test of the package to it -- and to quoting the sentences
# from the files subject() writes: --access-rule, the subject's sentence on
# a crash or an invalid access (_MEMORY_GRADED_ACCESS), on every test of the
# layer, and --rule, its sentence on a leak (_MEMORY_GRADED), on every one
# that checks leaks and on none that does not (--no-leak-check).
_GRADED_LAYER = "valgrind"
_MEMORY_GRADED = "memory_graded_leaks"
_MEMORY_GRADED_ACCESS = "memory_graded_access"

def _layer_level(layer, memory_graded = False):
    """A layer's level in a package: _LAYER_LEVEL's, but basic for _GRADED_LAYER where the contract declares memory_graded."""
    if memory_graded and layer == _GRADED_LAYER:
        return 1
    return _LAYER_LEVEL[layer]

def _memory_graded():
    """The calling package's contract's memory_graded sentences, {"leaks", "access"}; {} where it has none, or no contract."""
    return (contract_or_none() or {}).get("memory_graded") or {}

def _graded_rule(leaks = True):
    """(args, data) handing a valgrind runner the contract's memory_graded sentences, or ([], []).

    --access-rule always, the sentence on a crash or an invalid access; and
    with `leaks` (the run checks leaks) --rule, the sentence on a leak. A
    run with --no-leak-check passes leaks = False: it can find no leak, and
    its red quoting the leak sentence named a rule its finding cannot break.
    """
    if not _memory_graded():
        return [], []
    args = ["--access-rule", "$(location :%s)" % _MEMORY_GRADED_ACCESS]
    data = [":" + _MEMORY_GRADED_ACCESS]
    if leaks:
        args += ["--rule", "$(location :%s)" % _MEMORY_GRADED]
        data.append(":" + _MEMORY_GRADED)
    return args, data

# The page whose table says why each test _RAISED lists sits where it does,
# staged beside those tests (_test, runner_lib.sh's rl__raised).
_DOC_REFERENCE = "//:docs/reference.md"

# WHAT A TARGET'S NAME SAYS, AND WHERE IT SITS. Every test in a project is
# named after its exercise or unit, exNN_<what> or <unit>_<what>, and the end
# of the name says which layer it is: the LONGEST of these suffixes the name
# ends with after that front, mapped to its layer tag and, where the suffix
# itself raises the test, to the level it sits at (None: its layer's). A case
# name sits in front of it ("ex05_modzero_output", BSQ's
# "bsq_one_cell_output"), a rush variant too ("ex00_rush03_asan").
#
# c_levels()' audit fails a package whose test ends in no suffix here, or in
# one whose layer is not the test's own: a reader looking a target up in
# docs/reference.md ("Target names") must find it there, under the layer its
# tags give it. //tools:conventions holds that table and this one to the same
# rows, as it holds the layer table to _LAYER_LEVEL (finding 038: _memcheck,
# _refcost and Rush 00's _robust were in no document; the last, a basic test
# named after a level, is _survive now). A case whose name collides with a
# longer suffix ("diff" makes ex00_diff_asan, which reads as diff_asan) is
# refused by the same check: rename the case.
_SUFFIX_LAYER = {
    "_allocfail": ("allocfail", None),
    "_allocfail_leaks": ("allocfail", 3),
    "_program_allocfail": ("allocfail", 3),
    "_program_allocfail_leaks": ("allocfail", 3),
    "_argv_diff_exit": ("diff", 3),
    "_asan": ("asan", None),
    "_big": ("output", 2),
    "_big_stdin": ("output", 2),
    "_bonus_9x9": ("diff", None),
    "_build": ("output", None),
    "_build_recipe": ("output", 2),
    "_build_rules": ("output", 3),
    "_build_wildcards": ("output", 2),
    "_compile_clang": ("compile", None),
    "_compile_gcc": ("compile", None),
    "_cycles": ("cycles", None),
    "_declares_output": ("output", 2),
    "_defense": ("output", None),
    "_diff": ("diff", None),
    "_diff_asan": ("diff_asan", None),
    "_exit": ("output", 3),
    "_files": ("files", None),
    "_fixed_array": ("method", None),
    "_forbidden": ("forbidden", None),
    "_forbidden_functions": ("forbidden", None),
    "_forbidden_through": ("forbidden", 2),
    "_globals": ("forbidden", None),
    "_ilp32": ("ilp32", None),
    "_issued": ("output", None),
    "_layout_prototype": ("prototype", 2),
    "_lint": ("norm", 3),
    "_literal": ("output", 2),
    "_long": ("output", None),
    "_long_stdin": ("output", None),
    "_main": ("output", None),
    "_memcheck": ("valgrind", None),
    "_method": ("method", None),
    "_model": ("oracle", None),
    "_multi": ("diff", None),
    "_newest_first": ("output", 2),
    "_norm": ("norm", None),
    "_norm_header": ("norm", 2),
    "_norm_notice": ("norm", 2),
    "_norm_provided": ("norm", 4),
    "_norm_provided_notice": ("norm", 4),
    "_oracle_fixtures": ("oracle", None),
    "_output": ("output", None),
    "_perf": ("perf", None),
    "_posix": ("norm", 2),
    "_probe_memcheck": ("valgrind", None),
    "_progname": ("output", None),
    "_prototype": ("prototype", None),
    "_prototype_names": ("prototype", 2),
    "_prototype_restrict": ("prototype", None),
    "_prototype_restrict_all": ("prototype", 2),
    "_readings": ("diff", None),
    "_readme": ("output", None),
    "_readme_wording": ("output", 2),
    "_reference_cases": ("oracle", None),
    "_refcost": ("cycles", None),
    "_regular": ("output", 2),
    "_rush02_dictfuzz": ("diff", None),
    "_stdin": ("diff", None),
    "_survive": ("output", None),
    "_sweep": ("output", None),
    "_symbols": ("symbols", None),
    "_twin": ("selftest", None),
    "_valgrind": ("valgrind", None),
}

# TESTS RAISED ABOVE THEIR SUFFIX'S LEVEL BY THEIR BUILD FILE -- a `level` at
# the call site, or a case's "level" -- as "<package>:<target>": the level.
# The reason is at the call site, and in one line in docs/reference.md
# ("Targets raised above their layer"), which //tools:conventions holds to
# these rows. c_levels()' audit fails a package with a raise that is not here,
# or an entry here its package does not raise (finding 072: C 06 ex03's raise
# was in one BUILD comment, against the docs' own level definitions). The
# macro fixtures' entries (tools/tests/...) prove the mechanism and are not
# documented.
_RAISED = {
    "c-piscine-reloaded/c-piscine-reloaded:ex19_high_bytes_argv_diff": 3,
    "c-piscine-reloaded/c-piscine-reloaded:ex22_double_arg_output": 2,
    "c-piscine-reloaded/c-piscine-reloaded:ex22_long_arg_output": 2,
    "c-piscine-reloaded/c-piscine-reloaded:ex23_int_fields_output": 4,
    "c-piscine-reloaded/c-piscine-reloaded:ex26_returns_one_output": 2,
    "c-piscine/c-piscine-c-12:ex11_element_output": 2,
    "c-piscine/c-piscine-c-06:ex03_high_bytes_argv_diff": 3,
    "c-piscine/c-piscine-c-07:ex04_base_to_space_output": 2,
    "c-piscine/c-piscine-c-08:ex01_expr_output": 2,
    "c-piscine/c-piscine-c-08:ex01_success_output": 3,
    "c-piscine/c-piscine-c-08:ex02_double_arg_output": 2,
    "c-piscine/c-piscine-c-08:ex02_long_arg_output": 2,
    "c-piscine/c-piscine-c-08:ex03_int_fields_output": 4,
    "c-piscine/c-piscine-c-10:ex01_dash_output": 2,
    "c-piscine/c-piscine-c-10:ex01_dirmsg_output": 2,
    "c-piscine/c-piscine-c-10:ex01_errmsg_output": 2,
    "c-piscine/c-piscine-c-10:ex01_errstatus_output": 2,
    "c-piscine/c-piscine-c-10:ex02_attached_output": 2,
    "c-piscine/c-piscine-c-10:ex02_dir_output": 2,
    "c-piscine/c-piscine-c-10:ex02_dirmsg_output": 2,
    "c-piscine/c-piscine-c-10:ex02_errmsg_output": 2,
    "c-piscine/c-piscine-c-10:ex02_errstatus_output": 2,
    "c-piscine/c-piscine-c-10:ex03_allfail_output": 2,
    "c-piscine/c-piscine-c-10:ex03_errmsg_output": 2,
    "c-piscine/c-piscine-c-10:ex03_errstatus_output": 2,
    "c-piscine/c-piscine-c-11:ex04_reverse_output": 2,
    "c-piscine/c-piscine-c-11:ex06_readings": 3,
    "c-piscine/c-piscine-c-11:ex05_intmin_div_output": 2,
    "c-piscine/c-piscine-c-11:ex05_intmin_mod_output": 2,
    "c-piscine/c-piscine-c-11:ex05_opsuffix_output": 2,
    "c-piscine/c-piscine-rush-02:ex00_dict_crlf_strict_output": 2,
    "c-piscine/c-piscine-rush-02:ex00_dict_missing_strict_output": 2,
    "c-piscine/c-piscine-rush-02:ex00_past_dictionary_strict_output": 2,
    "cursus/Milestone_0/Libft:ft_lstlast_empty_output": 2,
    "cursus/Milestone_0/Libft:ft_lstnew_allocfail": 3,
    "cursus/Milestone_0/Libft:ft_memset_wide_c_output": 2,
    "cursus/Milestone_0/Libft:ft_split_empty_fields_output": 2,
    "cursus/Milestone_0/Libft:ft_substr_start_past_end_output": 2,
    "tools/tests/macro_fixtures/graded:ex02_open_output": 2,
    "tools/tests/macro_fixtures/graded:ex02_open_valgrind": 2,
    "tools/tests/macro_fixtures/levels:ex00_raised_output": 2,
    "tools/tests/macro_fixtures/levels:ex00_reading_output": 2,
    "tools/tests/macro_fixtures/levels:ex01_staged_output": 2,
    "tools/tests/macro_fixtures/levels:ex03_open_output": 3,
    "tools/tests/macro_fixtures/levels:ex03_readings": 3,
    "tools/tests/macro_fixtures/named_lib:toy_cat_open_output": 2,
    "tools/tests/macro_fixtures/named_lib:toy_cat_readings": 3,
}

# THE RUNNERS THAT SAY WHY A TEST IS RAISED: those that source
# tools/runner_lib.sh, whose EXIT trap prints, under a red, the reason
# docs/reference.md's "Targets raised above their layer" gives for a test
# _RAISED lists (rl__raised, from the RL_RAISED _test() hands it). A runner
# that does not source the library -- norminette_test.sh, files_test.sh,
# issued_test.sh -- prints nothing of it, so c_levels()' audit refuses a
# raised test whose srcs is not one of these: its red would read like any
# other, which is what handing the level over was for. //tools:conventions
# holds this list to the scripts in tools/ that source the library, both
# ways.
_LIB_RUNNERS = [
    "//tools:allocfail_check.sh",
    "//tools:argv_check.sh",
    "//tools:argv_table.sh",
    "//tools:asan_check.sh",
    "//tools:asan_run.sh",
    "//tools:bsq_check.sh",
    "//tools:compile_check.sh",
    "//tools:cycles_check.sh",
    "//tools:diff_output.sh",
    "//tools:file_check.sh",
    "//tools:forbidden_symbols.sh",
    "//tools:header_check.sh",
    "//tools:header_norm.sh",
    "//tools:ilp32_test.sh",
    "//tools:make_test.sh",
    "//tools:method_check.sh",
    "//tools:model_check.sh",
    "//tools:oracle_fixtures.sh",
    "//tools:perf_test.sh",
    "//tools:progname_test.sh",
    "//tools:prototype_check.sh",
    "//tools:readme_check.sh",
    "//tools:ref_compare.sh",
    "//tools:reference_cases.sh",
    "//tools:run_check.sh",
    "//tools:rush01_check.sh",
    "//tools:rush02_check.sh",
    "//tools:rust_diff.sh",
    "//tools:shell_test.sh",
    "//tools:symbols_test.sh",
    "//tools:valgrind_test.sh",
]

# THE MANUAL TESTS, as "<package>:<target pattern>" ('*' matches any run of
# characters). A manual test is in no suite but its module's :manual and
# matches no /... pattern, so it runs only when named: it is listed here and
# in docs/reference.md ("Manual targets"), which //tools:conventions holds to
# these rows, and c_levels()' audit fails a package with a manual test no
# pattern here matches (finding 002: eight of them were in no document that
# said how to find them). A pattern that matches nothing is not an error: which
# Rush 00 variants are manual is the team's team.bzl, and a stub nobody owes
# can be deleted. The macro fixtures are manual by construction (_test) and
# are not listed, but for one row under tools/tests/, which the audit's
# fixture of a listed manual test reads (audit-manual-listed): a package of
# its own, which nothing raises. It read Rush 01's row, and the audit also
# fails a package's _RAISED entry it does not declare, so a raise added to
# Rush 01 turned that fixture red for a reason it does not test. Like
# _RAISED's fixture rows, it is not documented.
_MANUAL = [
    "c-piscine/c-piscine-rush-00:ex00_rush0*",
    "c-piscine/c-piscine-rush-01:ex00_bonus_9x9",
    "c-piscine/c-piscine-rush-02:ex00_rush02_dictfuzz",
    "c-piscine/c-piscine-rush-02:ex00_rush02_diff",
    "tools/tests/macro_fixtures/manual:ex00_bonus_diff",
]

# The tag of a module's :manual suite when the module has no manual test. A
# test_suite with no `tests` runs every non-manual test of its package, and
# `manual` is not a filter there (Bazel ignores it in a suite's tags), so an
# empty :manual would run the whole module. This tag, which no test carries
# (the audit refuses one that does), makes it select nothing instead.
_NO_MANUAL_TAG = "no_manual_test_in_this_module"

def _is_ex(s):
    """Whether `s` is an exercise's name: "ex" and two digits."""
    return len(s) == 4 and s.startswith("ex") and s[2:].isdigit()

def _is_unit_key(k):
    """Whether a contract key names a unit ("libtoy"), not an exercise ("00")."""
    return type(k) == "string" and k[:1].isalpha()

def _prefix(k):
    """The first word of a key's targets: exNN for an exercise, the name for a unit."""
    return k if _is_unit_key(k) else "ex" + k

def _key(p):
    """The contract key a target prefix stands for: "00" for ex00, a unit's own name."""
    return p[2:] if p.startswith("ex") and p[2:].isdigit() else p

def _call(k):
    """How a message names a macro call: num = "00", or unit = "toy_len".

    `k` is the key the call names: a function of a library by its own name,
    never its library's (_resolve's `unit`).
    """
    if _is_unit_key(k):
        return "unit = %r" % (k,)
    return "num = \"%s\"" % k

def _tests_folder(k):
    """The folder a message names for a call's files: tests/exNN/, or tests/<unit>/.

    A function of a library has its own, tests/<function>/ (_member), so
    `k` is the function's name there, as for _call().
    """
    if _is_unit_key(k):
        return "tests/%s/" % k
    return "tests/ex%s/" % k

def _kind_word(k, e):
    """What a message calls key `k`'s part: an exercise, or a unit by its kind, a library or a project.

    `e` is its contract entry: a unit that lists `functions` is a library.
    """
    if not _is_unit_key(k):
        return "exercise"
    return "library" if e.get("functions") else "project"

# The tag of a unit's tests in a contract of units: unit=<name>, the unit the
# test's name begins with (_test()), which the unit's suite selects.
_UNIT_TAG = "unit="

def _unit_tag(tags):
    """The unit a test's unit= tag names (_UNIT_TAG), the first one; None if it has none."""
    for t in tags:
        if t.startswith(_UNIT_TAG):
            return t[len(_UNIT_TAG):]
    return None

def _unit_of_name(name, names):
    """The unit of `names` that, followed by _, begins `name`; None if none does.

    The longest, where two would: subject()'s prefix rule keeps a contract
    from having two, and tools/first_red.sh --unit-of reads a target's unit
    the same way.
    """
    best = None
    for u in names:
        if name.startswith(u + "_") and (best == None or len(u) > len(best)):
            best = u
    return best

def _glob_match(pattern, s):
    """Whether `s` matches `pattern`, where '*' matches any run of characters."""
    parts = pattern.split("*")
    if len(parts) == 1:
        return s == pattern
    if not s.startswith(parts[0]) or not s.endswith(parts[-1]):
        return False
    if len(parts[0]) + len(parts[-1]) > len(s):
        return False
    at = len(parts[0])
    end = len(s) - len(parts[-1])
    for p in parts[1:-1]:
        i = s.find(p, at, end)
        if i < 0:
            return False
        at = i + len(p)
    return True

def _suffix_of(name, unit):
    """The longest _SUFFIX_LAYER key `name` ends with, after its unit's name; None if none."""
    best = None
    for s in _SUFFIX_LAYER:
        if name[len(unit):].endswith(s) and (best == None or len(s) > len(best)):
            best = s
    return best

def _level_tags(tags, level = None, memory_graded = False):
    """The lvl_* tags a test carries, given its layer tags.

    level raises this one test above where its layer would put it; see _test.
    memory_graded: the package's contract declares it, and its valgrind
    layer sits at basic (_layer_level).

    CUMULATIVE on purpose: a norm test is tagged lvl_basic AND lvl_strict AND
    lvl_robust AND lvl_complete, so `test_suite(tags = ["lvl_strict"])` picks up
    everything at or below strict. test_suite's `tags` is an AND across the list
    and has no OR, so a suite has to select on ONE tag — which only works if the
    membership is baked in here rather than expressed at the suite.
    """
    lvl = 0
    for t in tags:
        if t in _LAYER_LEVEL:
            lvl = max(lvl, _layer_level(t, memory_graded))
    if level != None:
        if lvl == 0:
            fail("_level_tags: level = %d on a test with no layer tag: %r" % (level, tags))
        if level <= lvl:
            fail("_level_tags: level = %d does not raise a level-%d layer (%r). " % (level, lvl, tags) +
                 "Only UP is allowed: `basic` has to keep meaning everything that is a KO wherever the project is graded.")
        lvl = level
    if lvl == 0:
        return []
    return ["lvl_" + _LEVEL_NAMES[i] for i in range(lvl - 1, len(_LEVEL_NAMES))]

def lvl_tags(layer, level = None):
    """The tags a test rule that is NOT an sh_test needs: its layer and its level ladder.

    Two callers, each a rule of its own outside every project:
    //tools/cc_toolchain's provenance test and //tools/tests:fortytwo_test,
    a py_test. Every sh_test -- in a module or out of one -- is
    declared with hand_test(), which goes through _test() like every test a
    macro emits and so derives the exercise tag as well; the exercise tag is
    what this could not give, and the hand-written sh_tests that used it were
    in no :exNN suite (finding 070). //tools:conventions refuses lvl_tags()
    in a project's BUILD file and sh_test() in any BUILD file.

    Args:
        layer: the layer tag, as a string -- "selftest", "oracle". fail()s on
            anything _LAYER_LEVEL does not know, because _level_tags returns
            NO tag for an unrecognised one, which drops the test out of every
            level suite in silence.
        level: raise THIS test above its layer, as _test's `level` does; only
            up, for the same reason.

    Returns:
        The layer tag followed by its cumulative lvl_* tags.
    """
    _known_layer("lvl_tags", layer)
    return [layer] + _level_tags([layer], level)

def _known_layer(what, layer):
    """fail()s unless `layer` is a layer tag of _LAYER_LEVEL."""
    if layer not in _LAYER_LEVEL:
        fail(("%s: %r is not a layer. Known layers: %s. An unrecognised " +
              "tag gets no lvl_* tag at all, which drops the test out of every " +
              "level suite silently -- so this refuses rather than emits it.") %
             (what, layer, ", ".join(sorted(_LAYER_LEVEL))))

# The package of toy exercises that proves the macros on every broken state a
# student's tree can be in (see its BUILD file). Its tests are red by design, so
# they are tagged manual here and reached through its own check instead.
_FIXTURES = "tools/tests/macro_fixtures"

def _in_fixtures():
    """True in tools/tests/macro_fixtures or a package under it."""
    p = native.package_name()
    return p == _FIXTURES or p.startswith(_FIXTURES + "/")

def _uniq(xs):
    """`xs` with each item once, in order: Bazel refuses a label twice in `data`."""
    out = []
    for x in xs:
        if x not in out:
            out.append(x)
    return out


# ---------------------------------------------------------------------------
# WHAT THE FILES ABOVE THIS ONE LOAD OF IT. A load() cannot name a private
# symbol, so each one they use is given a public name here, its own without
# the underscore, and loaded back under its own name: the code reads as it did
# when tools/defs.bzl held it all. These names are for those files alone; a
# BUILD file loads //tools:defs.bzl.
LAYER_LEVEL = _LAYER_LEVEL
LEVEL_NAMES = _LEVEL_NAMES
GRADED_LAYER = _GRADED_LAYER
MEMORY_GRADED = _MEMORY_GRADED
MEMORY_GRADED_ACCESS = _MEMORY_GRADED_ACCESS
layer_level = _layer_level
memory_graded = _memory_graded
graded_rule = _graded_rule
DOC_REFERENCE = _DOC_REFERENCE
SUFFIX_LAYER = _SUFFIX_LAYER
RAISED = _RAISED
LIB_RUNNERS = _LIB_RUNNERS
MANUAL = _MANUAL
NO_MANUAL_TAG = _NO_MANUAL_TAG
is_ex = _is_ex
is_unit_key = _is_unit_key
prefix = _prefix
key = _key
call = _call
tests_folder = _tests_folder
kind_word = _kind_word
UNIT_TAG = _UNIT_TAG
unit_tag = _unit_tag
unit_of_name = _unit_of_name
glob_match = _glob_match
suffix_of = _suffix_of
level_tags = _level_tags
known_layer = _known_layer
FIXTURES = _FIXTURES
in_fixtures = _in_fixtures
uniq = _uniq
