"""subject(), and the contract as the macros read it.

A project's BUILD file opens with subject(): tools/subject.bzl declares the
contract, and this wrapper declares, beside it, the finalizers that write the
list each output test hands its runner of the tests that wait for it
(_waiting) and :test_units. Everything a macro asks of the contract is read
here: an exercise's or a unit's entry (_entry, _resolve), where it turns in
(turnin_dir, turnin_file, turnin_glob, _zone), its files, what the grader
brings (_provided, _linked), what it may call (_allowed), and the programs
built from a turn-in (_student_bin, _student_lib), which never fail the
build. _BUILD_PRODUCTS and _RESERVED_UNIT_NAMES are read as text by
//tools:conventions.

Loaded by the files above it, and re-exported by tools/defs.bzl, the one
file a BUILD file loads.
"""

load(
    ":defs_levels.bzl",
    _FIXTURES = "FIXTURES",
    _LAYER_LEVEL = "LAYER_LEVEL",
    _LEVEL_NAMES = "LEVEL_NAMES",
    _MEMORY_GRADED = "MEMORY_GRADED",
    _MEMORY_GRADED_ACCESS = "MEMORY_GRADED_ACCESS",
    _UNIT_TAG = "UNIT_TAG",
    _call = "call",
    _in_fixtures = "in_fixtures",
    _is_ex = "is_ex",
    _is_unit_key = "is_unit_key",
    _key = "key",
    _kind_word = "kind_word",
    _prefix = "prefix",
    _uniq = "uniq",
    _unit_of_name = "unit_of_name",
    _unit_tag = "unit_tag",
)
load(
    ":defs_toolchain.bzl",
    _ASAN_COPTS = "ASAN_COPTS",
    _ASAN_LINKOPTS = "ASAN_LINKOPTS",
    _CASE_READS_TAG = "CASE_READS_TAG",
    _COPTS = "COPTS",
    _HARNESS_PROTO_TAG = "HARNESS_PROTO_TAG",
    _harness_prototype_problem = "harness_prototype_problem",
    _oracle_owner = "oracle_owner",
)
load(":names_file.bzl", "names_file")
load(":student_build.bzl", "student_binary", "student_unit")
load(
    ":subject.bzl",
    _contract_entries = "contract_entries",
    _contract_or_none = "contract_or_none",
    _exercise = "exercise",
    _subject = "subject",
    _turnin_folder = "turnin_folder",
    _unit = "unit",
    _units_of = "units_of",
    _units_order_problem = "units_order_problem",
)

# The contract's public names, loaded from here like every other macro: a
# project's BUILD file opens with subject(... exercise(...) ...), or with
# subject(... unit(...) ...) where its subject gives no turn-in directory.
# See tools/subject.bzl.
exercise = _exercise

unit = _unit

# Why a contract's recorded order disagrees with its maps (tools/subject.bzl),
# public for //tools/tests:starlark_unit.
units_order_problem = _units_order_problem

def subject(grader, group, exercises = None, units = None, strict = True, mandatory = None, mandatory_quote = None, memory_graded = None, name = "subject"):
    """A project's subject contract (tools/subject.bzl's subject()), and who waits for each output.

    The contract, as tools/subject.bzl declares it; then the finalizer that
    writes, once the package is declared, the list each output test hands its
    runner of the tests that wait for it (_WAITING). Here and not in
    c_levels(): every package that can declare an output test has a contract,
    and one without c_levels() -- the macro fixtures -- otherwise named lists
    nothing wrote, and its output tests did not build.

    It also writes, for every reader of the contract outside Bazel, :units --
    one line per unit of the contract (units_rows()) -- and, once the package
    is declared, :test_units -- the unit each test of the package was given
    (_test_units). //tools/tests holds tools/units.awk's reading of this call
    to the first, and tools/first_red.sh --unit-of's reading of the test
    names to the second, in every package with a contract.

    Args:
        grader: as tools/subject.bzl's subject() takes it.
        group: the same.
        exercises: the same.
        units: the same. Every name in it, each unit's and each function's,
            is held to _RESERVED_UNIT_NAMES, which this hands tools/subject.bzl
            as its `reserved`: a BUILD file never passes that.
        strict: the same.
        mandatory: the same.
        mandatory_quote: the same.
        memory_graded: the same. Its two sentences are written out for the
            runners as well, to :memory_graded_leaks (_MEMORY_GRADED) and
            :memory_graded_access (_MEMORY_GRADED_ACCESS), which the
            package's valgrind reds quote (_graded_rule).
        name: the same.
    """
    _subject(
        grader = grader,
        group = group,
        exercises = exercises,
        units = units,
        strict = strict,
        mandatory = mandatory,
        mandatory_quote = mandatory_quote,
        memory_graded = memory_graded,
        reserved = _RESERVED_UNIT_NAMES,
        name = name,
    )

    # THE CONTRACT'S UNITS, one line each, as the macros read them
    # (units_rows()). Here and not in c_levels(), for the reason _waiting
    # is: every package with a contract gets it, the macro fixtures too, so
    # tools/units.awk's reading of this call is held to it everywhere.
    names_file(
        name = "units",
        names = units_rows(_contract("units")),
        visibility = ["//tools/tests:__pkg__"],
    )

    # Each sentence, one line in a file: sh_test tokenises `args` on blanks,
    # so a runner is handed its path (valgrind_test.sh's --rule and
    # --access-rule), as c_program's memory_rule is.
    if memory_graded:
        names_file(name = _MEMORY_GRADED, names = [memory_graded["leaks"]])
        names_file(name = _MEMORY_GRADED_ACCESS, names = [memory_graded["access"]])

    # Public, as the contract is: //tools/tests reads the macro fixtures'.
    _waiting(name = _WAITING, visibility = ["//visibility:public"])

    # WHICH UNIT EACH TEST IS, written once the whole package is declared.
    _test_units(name = "test_units", visibility = ["//tools/tests:__pkg__"])

def _layout_args(args):
    """The tests/layout/ files a test's `args` pass with --layout or --layout-tag, package-relative."""
    out = []
    for i in range(len(args) - 1):
        a = args[i + 1]
        if args[i] in ("--layout", "--layout-tag") and a.startswith("$(location ") and a.endswith(")"):
            out.append(a[len("$(location "):-1])
    return out

def _audit_inputs(rules):
    """_audit_problems' tests, fixtures, oracle and diffio, read from a package's rules.

    `rules` is native.existing_rules(): {name: the rule's attributes}. Its
    own function so that c_levels()' audit (_rules_audit, which
    contract_problem("audit_rules") calls too) can be fed rules shaped the
    way existing_rules() returns them, and so the reading -- a tag, an
    argument -- is proven along with the rule it feeds.
    """
    tests = {}
    fixtures = {}
    owners = {}
    reads = {}
    diffio = []
    for n, r in rules.items():
        tags = list(r.get("tags") or [])
        if r["kind"].endswith("_test"):
            tests[n] = {
                "kind": r["kind"],
                "tags": tags,
                "layouts": _layout_args(list(r.get("args") or [])),
                # A label as the rule holds it, which may name the main
                # repository ("@@//tools:x.sh"): compared from its "//".
                "srcs": [_norm_label(x) for x in (r.get("srcs") or [])],
                "args": list(r.get("args") or []),
            }
            owner = _oracle_owner(r)
            if owner != None:
                owners[n] = owner
            for t in tags:
                if t.startswith(_CASE_READS_TAG):
                    reads[n] = [f for f in t[len(_CASE_READS_TAG):].split(",") if f]

        # Every program linking a harness, read from the rule and not from the
        # tag alone: one that lost its tag, or was declared without
        # _student_bin, is then a binary with None rather than none at all.
        if r["kind"] == "student_binary" and r.get("harness"):
            fixtures[n] = None
            for t in tags:
                if t.startswith(_HARNESS_PROTO_TAG):
                    fixtures[n] = t[len(_HARNESS_PROTO_TAG):]

        # Every program linking //tools:diffio, by its deps as the rule holds
        # them (a label may name the main repository: compared from "//").
        if r["kind"] == "student_binary":
            for d in r.get("deps") or []:
                if _norm_label(d) == "//tools:diffio":
                    diffio.append(n)
    return tests, fixtures, {"owners": owners, "reads": reads}, diffio

# WHO WAITS FOR AN OUTPUT TEST, written down for it to say.
#
# A layer gated on an exercise's output (--gate-bin: diff, diff_asan,
# valgrind, memcheck, cycles, perf, allocfail, ilp32, a case's memory arms, a
# corpus; --gate-label: a survive case) says SKIP and exits 0 while that
# output is red, and Bazel 9.2 has no way for a test that ran to report itself
# skipped: the summary of a first red showed them PASSED beside the one red
# test, and they were read as "tests that pass because it compiles" (V2).
# Which output test each one waits for is known here, once the package is
# declared (_waits_for): the one its call names (_test's `waits`, a
# _WAITS_TAG; a survive case's --gate-label), or else the one output test
# that runs the same program against the same expected file -- its gate's
# --gate-bin and --gate-expected (ilp32's --expected) are that test's --bin
# and --expected. Per OUTPUT TEST, not per (program, file): BSQ's error cases
# share one expected file, and each case's memory arm waits for its own case
# alone. _waiting_name() names the list of one output test, one test a line
# with its level; the output test hands it to its runner (--waiting,
# _waiting_args), which names them under a red verdict (rl_waiting,
# tools/runner_lib.sh).
#
# subject() declares the finalizer that writes the lists (_waiting), not
# c_levels(): every package an output test can be declared in has a contract
# (the macros fail without one), and a package without c_levels() -- the
# macro fixtures -- would otherwise hand its output tests a list nothing
# writes, and none of them would build. The audit (_audit_problems) fails a
# module where a gated test resolves to no output test that hands a list, or
# to more than one, or to an output test of another exercise: its SKIP would
# be listed under that exercise's red, never its own (V104).
_WAITING = "waiting"
_WAITS_TAG = "waits="

# The arguments that say a test waits for an output: the program it gates on,
# the file that program must print, or the output test by name.
_GATE_FLAGS = ["--gate-bin", "--gate-expected", "--gate-label"]

def _norm_label(x):
    """Label `x` from its "//": a label a rule holds may name the main repository before it."""
    return "//" + str(x).split("//", 1)[-1]

def _loc_of(arg):
    """The label or path inside "$(location X)", from its last ':', or None."""
    if not (arg.startswith("$(location ") and arg.endswith(")")):
        return None
    return arg[len("$(location "):-1].split(":")[-1]

# READING A TEST'S ARGUMENTS BACK. Every runner reads its options up to a
# lone "--", and hands the program the words after it: an option name after
# it is a word of the program's. The audits read a declared test's args the
# same way, through these, and through nothing written inline.
def _opts(args):
    """The options of `args`: its words before the first lone "--", or all of them."""
    return args[:args.index("--")] if "--" in args else args

def _after_dashes(args):
    """The words after the first lone `--` in `args`: the program's own argv."""
    return args[args.index("--") + 1:] if "--" in args else []

def _opt_values(args, opt):
    """Every value `opt` takes in `args`, in order: the word after each `opt` before a "--"."""
    out = []
    for i in range(len(args) - 1):
        if args[i] == "--":
            break
        if args[i] == opt:
            out.append(args[i + 1])
    return out

def _opt_value(args, opt):
    """The first value `opt` takes in `args` before a "--" (_opt_values), or None."""
    v = _opt_values(args, opt)
    return v[0] if v else None

def _waiting_name(test):
    """The list of the tests that wait for the output test `test`."""
    return "%s_%s" % (_WAITING, test)

def _waiting_outputs(tests):
    """{output test: (its program, its expected file)}, for each that hands a list (--waiting)."""
    out = {}
    for n in sorted(tests):
        args = tests[n].get("args") or []
        if "--waiting" in args:
            out[n] = (_loc_of(_opt_value(args, "--bin") or ""), _loc_of(_opt_value(args, "--expected") or ""))
    return out

def _runs(output, gb, ge):
    """Whether an output test's (program, expected file) is a gate's: none differs, one is the same.

    An output test that builds its program in its runner (c_libft's,
    header_check.sh) has no --bin, and is told by its expected file alone.
    """
    same = 0
    for mine, theirs in [(output[0], gb), (output[1], ge)]:
        if mine and theirs:
            if mine != theirs:
                return False
            same += 1
    return same > 0

def _other_exercise(name, o, tests):
    """Why test `name` cannot wait for output test `o`, another exercise's or unit's, or "".

    V104: a test's SKIP is listed under the red of the output test it waits
    for, and a student reads the red of the exercise in front of them. In a
    contract of units the unit is read from each test's tag (_UNIT_TAG),
    which _test() derives from its name, and a library's function is a unit
    of its own: //<module>:<function> runs that function's tests alone, so a
    wait on another function's output test -- or a function's on the whole
    library's, or the library's on a function's -- would be listed under a
    red that suite never shows. A test with neither an exercise's name nor a
    unit's tag is refused: whose red it would be listed under cannot be
    told.
    """
    mu = _unit_tag((tests.get(name) or {}).get("tags") or [])
    if mu == None and not _is_ex(name[:4]):
        return (("%s: it waits for %s, and its name begins with no exercise's exNN_ and " +
                 "its tags give it no unit (unit=), so whose red its SKIP would be listed " +
                 "under cannot be told. Name it after the unit it tests (V104).") % (name, o))
    if mu != None:
        ou = _unit_tag((tests.get(o) or {}).get("tags") or [])
        if ou == mu:
            return ""
        return (("%s: it waits for %s, the output test of %s, and it is %s: its SKIP would " +
                 "be listed under a red its own suite never shows. A test waits for an " +
                 "output test of its own unit (V104).") %
                (name, o, ("the unit " + ou) if ou else "no unit", "a test of the unit " + mu))
    if o[:4] != name[:4]:
        return (("%s: it waits for %s, the output test of another exercise, so its SKIP " +
                 "would be listed under that exercise's red and never under its own. A " +
                 "test waits for an output test of its own exercise (V104).") % (name, o))
    return ""

def _waits_for(name, tests, outputs):
    """(the output test `name` waits for, None), (None, why it cannot be told), or (None, None): no gate.

    The output test is one of the test's own exercise, or of its own unit,
    a library's function or the whole library as the test is: a wait on
    another's is refused, on either path (V104, _other_exercise).
    """
    t = tests[name]
    args = t.get("args") or []
    said = _uniq([x[len(_WAITS_TAG):] for x in t["tags"] if x.startswith(_WAITS_TAG)] +
                 [x for x in [_opt_value(args, "--gate-label")] if x])
    if not said and not [f for f in _GATE_FLAGS if f in args]:
        return None, None
    gb = _loc_of(_opt_value(args, "--gate-bin") or "")
    ge = _loc_of(_opt_value(args, "--gate-expected") or (_opt_value(args, "--expected") if gb else None) or "")
    gate = "%s printing %s" % (gb or "a program it names by no $(location)", ge or "a file it names by no $(location)")
    if len(said) > 1:
        return None, ("%s: it says it waits for %s; a test waits for one output test." %
                      (name, " and ".join(said)))
    if said:
        o = said[0]
        if o not in outputs:
            return None, (("%s: it waits for %s, which is no output test of this package " +
                           "handing its list on (--waiting, _waiting_args), so no red log " +
                           "says it shows PASSED while it waits.") % (name, o))
        if (gb or ge) and not _runs(outputs[o], gb, ge):
            return None, (("%s: it says it waits for %s, and its gate is %s, which %s " +
                           "does not run: it waits for another output test.") % (name, o, gate, o))
        why = _other_exercise(name, o, tests)
        return (None, why) if why else (o, None)
    found = [o for o in sorted(outputs) if _runs(outputs[o], gb, ge)]
    if len(found) == 1:
        why = _other_exercise(name, found[0], tests)
        return (None, why) if why else (found[0], None)
    if not found:
        return None, (("%s: it waits for an output test (its gate is %s), and no output " +
                       "test of this package that runs that hands its list on (--waiting, " +
                       "_waiting_args), so no red log says it shows PASSED while it waits. " +
                       "Hand that output test's runner _waiting_args(<its name>).") % (name, gate))
    return None, (("%s: its gate is %s, which %s each run. Say which one it waits for: " +
                   "waits = \"<that output test>\" on its _test() or hand_test().") %
                  (name, gate, ", ".join(found)))

def _level_of(tags):
    """A test's level, the lowest of its lvl_* tags, or None."""
    for x in _LEVEL_NAMES:
        if "lvl_" + x in tags:
            return x
    return None

def _waiting_lists(tests):
    """{output test handing a list: its lines, "<test> (<level>)", sorted}.

    A manual test is left out of a list that is not manual itself: //... and
    every level suite leave it out, so it never shows PASSED there. In the
    macro fixtures every test is manual, and they are listed as anywhere else.
    """
    outputs = _waiting_outputs(tests)
    lists = {o: [] for o in outputs}
    for n in sorted(tests):
        o, _ = _waits_for(n, tests, outputs)
        if o == None or ("manual" in tests[n]["tags"] and "manual" not in tests[o]["tags"]):
            continue
        lvl = _level_of(tests[n]["tags"])
        lists[o].append("%s (%s)" % (n, lvl) if lvl else n)
    return lists

def _waiting_impl(name, visibility):
    """subject()'s finalizer: the list each output test names, written."""
    tests, _, _, _ = _audit_inputs(native.existing_rules())
    lists = _waiting_lists(tests)
    for o in sorted(lists):
        names_file(
            name = _waiting_name(o),
            names = lists[o],
            visibility = visibility,
        )

_waiting = macro(
    implementation = _waiting_impl,
    finalizer = True,
    attrs = {},
)

def units_rows(contract):
    """:units' lines: one per unit of a decoded contract, NAME KIND REQ FOLDER JUDGE LIB, tab-separated.

    The units are tools/subject.bzl's units_of(), in its order; a column with
    nothing to say holds "-" (REQ where the contract names no mandatory
    part, and on a function; LIB on an exercise). tools/units.awk prints the
    same lines from the text of the subject() call, and every reader outside
    Bazel reads them from there.
    """
    return [
        "\t".join([u["name"], u["kind"], u["required"] or "-", u["folder"], u["judge"], u["library"] or "-"])
        for u in _units_of(contract)
    ]

def _test_unit(tags):
    """The unit a test's tags give it: its unit, else its exNN tag, else "-".

    The unit of a contract of units by its unit tag (_UNIT_TAG), a library's
    function being a unit of its own.

    Read from the tags _test() derived, never from the name again: that is
    what :test_units holds tools/first_red.sh --unit-of's reading of the name
    to. Two different ones are joined with a comma, which no reading of a
    name prints, so the drift guard names the test instead of passing it.
    """
    units = sorted({t[len(_UNIT_TAG):]: True for t in tags if t.startswith(_UNIT_TAG)}.keys())
    if units:
        return ",".join(units)
    return ",".join(sorted({t: True for t in tags if _is_ex(t)}.keys())) or "-"

def test_unit_rows(tags):
    """:test_units' lines, "TARGET<TAB>UNIT" for each test, sorted by its name.

    Args:
        tags: {test name: its tags}, every test rule of the package.
    """
    return ["%s\t%s" % (n, _test_unit(tags[n])) for n in sorted(tags)]

def _test_units_impl(name, visibility):
    """subject()'s second finalizer: the unit each test of the package was given, written."""
    tests, _, _, _ = _audit_inputs(native.existing_rules())
    names_file(
        name = name,
        names = test_unit_rows({n: tests[n]["tags"] for n in tests}),
        visibility = visibility,
    )

# A FINALIZER OF ITS OWN, declared by subject() as _waiting is, and not a
# list c_levels()' audit writes: three of the macro fixtures call no
# c_levels(), and their tests are held to the same reading.
_test_units = macro(
    implementation = _test_units_impl,
    finalizer = True,
    attrs = {},
)

# A REFUSAL A FIXTURE CAN WATCH. A macro refuses a BUILD file while loading,
# with fail(), and a package that fails to load cannot be a test: so the
# fixtures fed each guard its broken input through the guard's own helper
# (contract_problem, starlark_selftest_arms), and a macro that stopped calling the
# helper stayed green everywhere -- deleting c_program's or _test()'s fail()
# kept every selftest and fixture green (review of WP-50). A macro whose
# refusal a fixture must see refuses through this instead, and in the macro
# fixtures alone takes `refusals`, a list: the refusal is appended there, the
# macro returns having emitted nothing, and :contract_problems compares what
# the real macro said (tools/tests/macro_fixtures/BUILD.bazel, "refused-").
def _refuse(problem, refusals, who):
    """fail(problem); or, given `refusals` in the macro fixtures, append it and return True.

    False where there is no problem. `who` names the call, for the one
    refusal of its own: `refusals` passed outside the fixtures, where it
    would turn a guard off.
    """
    if refusals != None and (type(refusals) != "list" or not _in_fixtures()):
        fail(("%s: refusals = [...] collects a refusal instead of failing, for " +
              "%s's own fixtures only. A BUILD file elsewhere would turn the " +
              "guard off with it.") % (who, _FIXTURES))
    if not problem:
        return False
    if refusals == None:
        fail(problem)
    refusals.append(problem)
    return True

# The endings a student_binary's name must have (_student_bin() refuses any
# other): "ex03_bin", "ex03_bin_asan", "ex03_diffbin_asan", "ex03_memprobe".
# A name is what a test's `data` holds, and unlike existing_rule() it does not
# depend on the binary being declared before the test that runs it. The name
# also holds a "_" and no ".", which _student_bin() checks too: a bare entry
# of `data` is a target OR a file of the package, and a data file whose name
# ends in "bin" ("expected.bin", "cabin") is then not taken for a program.
_STUDENT_BIN_SUFFIXES = ("bin", "bin_asan", "bin_allocfail", "memprobe")

def _is_student_bin_name(n):
    """Whether `n` is a name _student_bin() accepts (see _STUDENT_BIN_SUFFIXES)."""
    return n.endswith(_STUDENT_BIN_SUFFIXES) and "_" in n and "." not in n

def _dirname(path):
    """The directory part of a package-relative path, "" for a bare filename.

    Starlark has no dirname, and this is needed wherever a compile has to be
    told where a header lives: the label names a FILE, and "<file>/.." walks
    through it rather than to its parent -- a mistake this repo has made twice,
    both times ending in a pinned compiler quietly loading the box's libraries.
    """
    if "/" not in path:
        return ""
    return path.rsplit("/", 1)[0]

# The characters a turn-in file's NAME may hold for it to reach a build or a
# layer. Every other one breaks some layer between the glob and the runner: a
# blank is split in two by sh_test's argument tokenising (the files layer
# reported "ft_putchar" and "copy.c"), a parenthesis ends a $(location ...)
# early and fails the ANALYSIS of every layer that named the file, a $ starts
# a make variable. No subject names a file with any of them, so a name that
# holds one is dropped from everything that builds or reads files (_safe())
# and reported, by its real name, by the one layer that reads names only:
# c_files, through a name list written with no label at all (_names_file).
_SAFE_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._+-/"

def _safe(path):
    """Whether every character of `path` is one a label and an argument carry."""
    for c in path.elems():
        if c not in _SAFE_CHARS:
            return False
    return True

def turnin_glob(include, exclude = None):
    """A glob of the turn-in, as every macro here globs it: never failing.

    allow_empty = True, because an empty folder is a student's state and must
    fail the tests that needed its files, not the loading of the package; and
    only names _safe() accepts, because a file named "rush (copy).c" is one
    that no label or argument list can carry (see _SAFE_CHARS). c_files still
    sees such a file and reports it. For a module BUILD file that needs a
    list of turn-in files itself -- which, with the contract, none does --
    instead of a bare glob().
    """
    return [
        f
        for f in native.glob(include, exclude = exclude or [], allow_empty = True)
        if _safe(f)
    ]

# ---------------------------------------------------------------------------
# THE SUBJECT CONTRACT, as the macros read it (tools/subject.bzl declares it).
#
# Every fact below comes from the one subject() call at the top of the
# package's BUILD file: where an exercise turns in, which files it names or
# allows, what the grader brings, what may be called. No macro types one of
# them again, and no BUILD file passes one at a call site -- the parameters
# that took them (c_files' required/optional/strict/subdir, c_function's
# allowed/provided_hdrs/provided_srcs/extra_includes, c_make's anchor/overlay,
# c_program's make_data ...) are gone, so a second copy cannot be written.

def _no_contract_problem(what, contract):
    """The message a macro fails with when its package has no subject(); None if it has one.

    `contract` is contract_or_none()'s. A value first, like every contract
    check (see tools/subject.bzl): contract_problem() hands it to the
    fixtures.
    """
    if contract != None:
        return None
    return (("%s: %s declares no subject() before this call. Every project's " +
             "BUILD.bazel opens with its subject contract -- where each exercise " +
             "turns in, its files, what the grader brings, what it may call -- " +
             "transcribed from the subject (tools/subject.bzl; docs/reference.md, " +
             "\"The subject contract\"), and every macro reads it from there.") %
            (what, native.package_name() or "this package"))

def _contract(what):
    """This package's subject contract, decoded; fail()s naming `what` without one."""
    contract = _contract_or_none()
    if contract == None:
        fail(_no_contract_problem(what, contract))
    return contract

def _no_entry_problem(num, what, contract):
    """The message for a macro called on an exercise (or a unit) the contract lacks; None if it has it.

    `num` is a key of the contract's entries (tools/subject.bzl's
    contract_entries()): "00" for an exercise, a unit's own name in a
    contract of units.
    """
    entries = _contract_entries(contract)
    if entries.get(num) != None:
        return None
    if "units" in contract:
        return (("%s(%s): %r is no unit of this package's subject() contract (it has " +
                 "%s). Transcribe its part there first.") %
                (what, _call(num), num, ", ".join(sorted(entries.keys()))))
    return (("%s(%s): exercise %s is not in this package's subject() " +
             "contract (it has %s). Transcribe its header box there first.") %
            (what, _call(num), num, ", ".join(sorted(entries.keys()))))

# THE READERS OF A CONTRACT ENTRY THAT MAY MEET `linked` (the functions the
# grader compiles in: tools/grader_lib.bzl), with why. Every other reader
# fail()s on an entry that has one (_linked_reader_problem), so a macro written
# tomorrow cannot ignore the key without a word: a program it built without the
# grader's library would not link, and the red would read as the student's
# code (WP-78). A reader goes in here
# only once it links _linked(num).libs into every program it builds -- or
# builds none.
_TAKES_LINKED = {
    # Link the library into every program they build, and hand it to every
    # runner that compiles at test time (--lib, or ilp32's --lib32: its
    # 64-bit program is the output layer's, built with the library linked).
    "c_function": "links it (its allocfail layer cannot: _no_linked_problem)",
    "c_mem_check": "links it",
    "c_diff": "links it",
    "c_perf": "links it",
    "c_cycles": "links it",
    # Build no program.
    "c_files": "builds none",
    "c_readme": "builds none",
    "turnin_file": "builds none",
    "turnin_dir": "builds none",
    # The internal helpers: each reads one field, for a public macro that has
    # read its entry first (every one does, on its first line) and so has
    # passed this check already.
    "allowed": "a helper",
    "layout": "a helper",
    "linked": "a helper",
    "provided": "a helper",
    "turnin": "a helper",
    "member": "a helper",
    # Declares the library's unit, which every function's program links with
    # _linked(num).libs, and builds no program itself.
    "c_library": "builds none",
}

def _linked_reader_problem(num, what, e):
    """The message for `what` reading an entry whose `linked` it would ignore; None if it may.

    A value first, like every contract check: contract_problem() hands it to
    the fixtures.
    """
    fns = e.get("linked") or {}
    if not fns or what in _TAKES_LINKED:
        return None
    return (("%s(%s): the grader links %s into this exercise (its contract's " +
             "`linked`), and %s does not link a grader library into the programs it " +
             "builds. A correct answer would not link, and the red would read as the " +
             "student's fault. Link _linked(num).libs into every program %s builds, " +
             "as c_function does, then add it to _TAKES_LINKED in tools/defs_contract.bzl.") %
            (what, _call(num), ", ".join(sorted(fns.keys())), what, what))

def _entry(num, what):
    """Exercise `num`'s contract entry; fail()s naming `what(num = "NN")` if there is none.

    In a contract of units `num` is a unit's name, and the message names
    `what(unit = "<name>")` (_call()).

    `what` is the PUBLIC macro the BUILD file called -- c_function, c_program
    -- because that is the line a reader of the error goes looking for: every
    public macro reads its entry first, before any helper does (an internal
    helper's name, "turnin", sent a reader to a function no BUILD file calls).

    It also fail()s where the entry has a `linked` that `what` would ignore
    (_TAKES_LINKED lists the readers that may meet one).
    """
    c = _contract("%s(%s)" % (what, _call(num)))
    problem = _no_entry_problem(num, what, c)
    if problem:
        fail(problem)
    e = _contract_entries(c)[num]
    problem = _linked_reader_problem(num, what, e)
    if problem:
        fail(problem)
    return e

# THE MACROS THAT JUDGE ONE FUNCTION OF A LIBRARY (_member()). In a contract
# of units a function is a unit of its own, and a call of one of these names
# it by its name; every other macro judges a whole unit, a library or a
# project.
_MEMBER_MACROS = ["c_cycles", "c_diff", "c_function", "c_mem_check", "c_perf"]

def _resolve_problem(macro, num, unit, contract):
    """Why a macro's call cannot name what it names in `contract`; None if it can.

    A call names an exercise by `num` in a contract of exercises, and a unit
    by `unit` in a contract of units: one of the two, never both. There a
    function of a library is a unit of its own, so a member macro
    (_MEMBER_MACROS) names the function by its name, and every other macro
    names a library or a project. A project has no function, so a member
    macro takes it too: the call is the project's own. A value first, like
    every contract check: contract_problem() hands it to the fixtures.

    Args:
      macro: the public macro called, as its messages name it.
      num: the call's `num`, or None.
      unit: the call's `unit`, or None.
      contract: the package's contract, decoded.

    Returns:
      None, or the message the call is refused with.
    """
    if num != None and unit != None:
        return (("%s(num = %r, unit = %r): both, and a call names one: num an exercise of " +
                 "a contract of exercises, unit a unit of a contract of units") %
                (macro, num, unit))
    if num == None and unit == None:
        return (("%s(): neither num nor unit: num = \"NN\" names an exercise of a contract " +
                 "of exercises, unit = \"<name>\" a unit of a contract of units") % macro)
    if "units" not in contract:
        if unit != None:
            return (("%s(unit = %r): this package's contract has exercises (exercises = " +
                     "{...}), so a call names one by num = \"NN\"") % (macro, unit))
        return None
    if num != None:
        return (("%s(num = %r): this package's contract has units (units = {...}), so a " +
                 "call names one by unit = \"<name>\"") % (macro, num))
    rows = _units_of(contract)
    row = [r for r in rows if r["name"] == unit]
    if not row:
        return ("%s(unit = %r): %r is no unit of this package's contract, whose units are %s" %
                (macro, unit, unit, ", ".join([r["name"] for r in rows])))
    row = row[0]
    if row["kind"] == "function" and macro not in _MEMBER_MACROS:
        return (("%s(unit = %r): %r is a function of %r, and %s judges a whole unit: call " +
                 "it with unit = %r") % (macro, unit, unit, row["library"], macro, row["library"]))
    if row["kind"] == "library" and macro in _MEMBER_MACROS:
        return (("%s(unit = %r): %r is a library, and %s judges one function: call it with " +
                 "unit = one of %s") %
                (macro, unit, unit, macro, ", ".join([r["name"] for r in rows if r["library"] == unit])))
    return None

def _goal_of(num):
    """The Makefile rule that builds unit `num`: its contract's goal, or None.

    Set only on a part of several at the root of deliverable/ that shares
    its Makefile with another part and is not the one a bare make builds
    (subject()'s units); None for every exercise and every other unit.
    """
    contract = _contract_or_none()
    if contract == None:
        return None
    e = _contract_entries(contract).get(num)
    return e.get("goal") if e else None

def _root_parts(contract):
    """The units of a project whose root is divided among several parts, in its order; [] for any other.

    Several units turn in at the root of deliverable/ only as parts
    (subject()'s units: no library among them), so each is told apart by
    its own files or by its own Makefile rule, never by a folder.
    """
    if not contract.get("units") or len(contract["units"]) < 2:
        return []
    return list(contract["order"])

def _fn_lib(num, fn):
    """The name of c_function's library target for `fn` in `num`.

    `fn` itself -- but in a project divided into parts at the root, two
    parts may define the same function, each in files of its own or both in
    the same files, and each part's programs link a library target of their
    own: <part>_<fn>, named after the part as every other target of it is.
    """
    contract = _contract_or_none()
    if contract and _root_parts(contract):
        return _prefix(num) + "_" + fn
    return fn

def _part_files(e, d):
    """A part's own names: its `files`, then its `optional`, each pattern expanded against `d`."""
    out = list(e["files"] or [])
    for p in e["optional"]:
        if "*" in p:
            out += [f[len(d) + 1:] for f in turnin_glob([d + "/" + p])]
        else:
            out.append(p)
    return out

def _resolve(macro, num, unit, refusals):
    """What a macro's call names: struct(key, call, function), or False where it is refused.

    A macro's first step. `key` is what every later read of the contract
    takes (_entry(), _prefix()): the call's `num`, or the unit's name, or for
    a function of a library its library's name. `call` is the key the call
    named, the one its messages name it by (_call()): the call's `num`, or
    its `unit`, a function's own name. `function` is the function of a
    library the call judges, or None for an exercise, a library or a
    project. False where the call is refused (_resolve_problem()) and the
    macro, in the macro fixtures (`refusals`), must return having emitted
    nothing (_refuse).
    """
    said = ", ".join(["%s = %r" % (k, v) for k, v in [("num", num), ("unit", unit)] if v != None])
    contract = _contract("%s(%s)" % (macro, said))
    if _refuse(_resolve_problem(macro, num, unit, contract), refusals, macro):
        return False
    if unit == None:
        return struct(key = num, call = num, function = None)
    for r in _units_of(contract):
        if r["name"] == unit and r["kind"] == "function":
            return struct(key = r["library"], call = unit, function = unit)
    return struct(key = unit, call = unit, function = None)

def _call_kw(k):
    """The keyword that names key `k` to another macro, as the call named it.

    {"num": k} for an exercise, {"unit": k} for a unit: a function of a
    library is a unit named by its own name, so `k` is then the function's.
    """
    if _is_unit_key(k):
        return {"unit": k}
    return {"num": k}

def _required(macro, **kw):
    """fail()s naming the first of `kw` that is None: a parameter `macro` cannot do without.

    A macro's parameters after `num` default to None, since a call may name
    its unit by `unit` instead (_resolve()). One the macro needs is checked
    here, so a call that leaves it out still fails naming the macro.
    """
    for k, v in kw.items():
        if v == None:
            fail("%s(): %s is required" % (macro, k))

def _untranscribed_problem(contract, seen):
    """c_levels' message for tests/exNN/ folders the contract does not list; None if none.

    `seen` is the exNN names found under tests/.
    """
    declared = ["ex" + n for n in contract["exercises"]]
    untranscribed = sorted([ex for ex in seen if ex not in declared])
    if not untranscribed:
        return None
    return (("c_levels: tests/ has %s, which this project's subject() contract " +
             "does not list. Transcribe the exercise's header box into subject() " +
             "first: every layer takes its turn-in from there.") % ", ".join(untranscribed))

def _turnin_file_problem(num, name, e):
    """turnin_file()'s message when `name` is not a file the contract lets exercise `num` hold."""
    if name in (e["files"] or []) or name in e["optional"]:
        return None
    for p in e["optional"]:
        # The one pattern shape a contract uses for a file named at a call
        # site: "*.c", "*.h" -- a basename with an extension, in the turn-in
        # directory itself. A deeper pattern ("**/*.h") never names one file.
        if p.startswith("*.") and "/" not in p and "/" not in name and name.endswith(p[1:]):
            return None
    if name in e["provided"].values():
        return (("turnin_file(\"%s\", %r): the grader brings that file (the contract's " +
                 "`provided`), so it is never the student's: the harness's copy is " +
                 "under tests/.") % (num, name))
    return (("turnin_file(\"%s\", %r): the subject() contract does not let exercise %s " +
             "hold that file (files: %s; optional: %s). Name a file the subject asks " +
             "for, or transcribe it into the contract first.") %
            (num, name, num, e["files"], e["optional"]))

def _issued_problem(num, file, e):
    """c_issued()'s message when `file` is not one the contract lets it demand; None if it is.

    The file is named in the contract, by name, in the exercise's `optional`,
    and c_issued() points at that entry: it builds its path with
    turnin_file(), never by hand. A name the contract does not let the
    exercise hold is a file the files layer reports as extra while c_issued's
    test demands it -- on a strict subject, red both ways at basic. One in
    `files` is required by the files layer too, which then goes red on a
    fresh clone, where the template strips the file, with a report that
    cannot say where 42 publishes it. A pattern ("*.dict") covers it without
    naming it, and the contract is where the next reader looks for the
    project's files.
    """
    if type(file) != "string" or not file or not _safe(file) or "/" in file:
        return (("c_issued(num = \"%s\"): file = %r. It is the name 42 gives the file, " +
                 "as tools/resources.tsv lists it: no folder, no space.") % (num, file))
    where = "c_issued(num = \"%s\", file = %r)" % (num, file)
    if file in (e["files"] or []):
        return (("%s: the contract's `files` requires it, so the files layer is red on a " +
                 "fresh clone too, where the template strips it, with a report that cannot " +
                 "say where 42 publishes it. Move it to the exercise's `optional`: this test " +
                 "is what requires it.") % where)
    if file not in e["optional"]:
        return (("%s: the subject() contract does not name that file for exercise %s " +
                 "(files: %s; optional: %s), so the files layer would report it as extra " +
                 "while this test demands it. Name it in the exercise's `optional`, as the " +
                 "subject's turn-in covers it.") % (where, num, e["files"], e["optional"]))
    return None

def _diff_harness_problem(num, harness):
    """c_diff's message for a reader harness not named diff_*.c; None if it is.

    `num` is the key the call names: an exercise, or a unit (a function of
    a library by its own name).

    The name is how the harness is found by everything that reads it apart
    from the build: //tools:conventions holds every tests/**/diff_*.c to the
    header shape rust_diff.sh's print_columns reads its column legend from
    (finding 058), and each module's :conventions_srcs globs that name. A
    reader named anything else built and ran, and its legend went unchecked.
    """
    base = harness.split("/")[-1]
    if base.startswith("diff_") and base.endswith(".c") and len(base) > len("diff_.c"):
        return None
    return (("c_diff(%s, harness = %r): a differential reader harness is " +
             "named diff_<what>.c. //tools:conventions finds the harnesses by that " +
             "name to hold their header to the \"Line:\" legend the diff layer prints " +
             "(tools/rust_diff.sh, print_columns), so a reader named otherwise is " +
             "never checked. Rename the file.") % (_call(num), harness))

def turnin_dir(num):
    """The package-relative directory exercise `num` turns in at.

    deliverable/exNN for a subject whose turn-in line says "exNN/", and
    deliverable/ itself for one with no such line (BSQ, every Common Core
    project): deliverable/ is the root of the repository that is pushed.
    """
    return _turnin_folder(_entry(num, "turnin_dir")["dir"])

def _where(ex):
    """turnin_dir() for a target's `exNN` prefix, where the contract has it."""
    contract = _contract_or_none() if ex.startswith("ex") else None
    if contract != None and _contract_entries(contract).get(_key(ex)) != None:
        return turnin_dir(_key(ex))
    return "deliverable/" + ex

def _misplaced(where):
    """The exNN/ folders holding files under `where`, when it is the root of deliverable/.

    Nothing turned in at the root, and files one folder down: a root turn-in
    (BSQ, the Common Core) kept in the layout of the modules that have a
    turn-in directory -- BSQ's own, until its subject was read. A NOT TURNED
    IN test then says where they are and how to move them up (no_turnin.sh
    --misplaced). [] for any other `where`.
    """
    if where != "deliverable":
        return []
    found = {}
    for f in native.glob(["deliverable/ex*/**"], exclude = _not_build_products("deliverable"), allow_empty = True):
        d = f.split("/")[1]
        if len(d) == 4 and d[2:].isdigit():
            found["deliverable/" + d] = True
    return sorted(found.keys())

def _student_folders():
    """{exNN: its folder} for every deliverable/exNN/ there is, found by name.

    Where an exercise's folder would be, whether the contract has that
    exercise or not: c_levels() looks for the ones it does not (a folder of
    the student's for an exercise the subject lacks).
    """
    found = {}
    for d in native.glob(["deliverable/ex*"], exclude_directories = 0, allow_empty = True):
        ex = d.split("/")[1]
        if _is_ex(ex):
            found[ex] = d
    return found

def _turnin_files(num, ext):
    """Every `ext` file the contract lets exercise `num` turn in, that is there.

    THE CONTRACT'S FILE SET, AND NOTHING ELSE: each name of `files` and of
    `optional` that ends in `ext`, and each pattern there for that extension
    ("*.c", "**/*.h", "srcs/*.c"), globbed under turnin_dir(). Every layer of
    an exercise compiles what this returns -- the output fixture, the memory
    probes, ASan, the 32-bit build, the norm, compile, forbidden, prototype
    and symbols layers -- because each reads `srcs` from _deliverable_srcs()
    and its headers from _deliverable_hdrs(), both of which call this. A file
    the contract does not let the turn-in hold is the files layer's report
    (c_files), and no other layer's.

    It globbed every `ext` file of the folder, flat, and the layers then
    disagreed about a stray one: the output fixture and its memcheck linked
    the function's file out of an archive and never pulled a stray main.c
    in, while the memory probe, ASan and the 32-bit build linked every
    source directly and failed on two main()s -- C 00 ex08 and C 01 ex07,
    the mutation run of 2026-10-03 (AGENTS.md section 6, "Compile as the
    grader compiles": the grader compiles the files its subject names).
    Flat unless a pattern reaches into subfolders, as before: a subfolder is
    not where an exercise that names its files keeps them -- a copy of the
    grader's srcs/ left in C 09 ex01, say, which ex01_build reports instead.
    """
    e = _entry(num, "turnin")
    d = turnin_dir(num)
    pats = [p for p in (e["files"] or []) + e["optional"] if p.endswith(ext)]
    return turnin_glob([d + "/" + p for p in pats])

def turnin_file(num, name):
    """The package-relative path of `name` in exercise `num`'s turn-in, checked against the contract.

    For the few call sites that must name ONE turn-in file themselves: a unit
    of another exercise's sources, or a function a module archives with its
    own script (C 09 ex00's ft_strcmp.c). (C 12 ex05's probe used to link
    ex00's ft_create_elem.c this way; the grader's own copy is linked there
    now, from the contract's `linked`.) A path spelled "deliverable/ex00/..." at a
    call site is the layout decided a second time -- the way BSQ ended up
    under an ex00/ its subject never names -- so //tools:conventions refuses
    one in a project's BUILD file, and this builds it from turnin_dir()
    instead, and fails while loading unless the contract lets the exercise
    hold that file: a name in `files` or `optional`, or one a top-level
    `optional` pattern ("*.c") matches. A file the grader brings never
    qualifies: it is not the student's.

    The file may still be missing from the tree: whatever reads the path
    drops it then (_zone()), and the layers that needed it say so.

    Args:
        num: the exercise, as its contract entry is keyed ("00").
        name: the file, relative to the exercise's turn-in directory.

    Returns:
        The package-relative path: turnin_dir(num) + "/" + name.
    """
    e = _entry(num, "turnin_file")
    problem = _turnin_file_problem(num, name, e)
    if problem:
        fail(problem)
    return turnin_dir(num) + "/" + name

def _nested_in_turnin(path):
    """Whether `path` is a turn-in file in a SUBFOLDER of its exercise's turn-in directory.

    deliverable/ex00/includes/name.h is; deliverable/ex00/name.h, a
    header under tests/ and a label are not.
    """
    if not _is_student_path(path):
        return False
    contract = _contract_or_none()
    if contract == None:
        return False
    for e in _contract_entries(contract).values():
        d = _turnin_folder(e["dir"])
        if path.startswith(d + "/") and "/" in path[len(d) + 1:]:
            return True
    return False

def _inc_args(flag, hdrs, staged = None):
    """The include-path arguments a layer passes a runner for `hdrs`.

    `flag` (--hdr, --inc) and each header, whose directory the runner puts on
    -I -- except a header in a SUBFOLDER of the turn-in (includes/name.h),
    which is only staged: its directory is never put on the path, and
    `staged`, where the runner takes one, names it for the message.

    WHY. The include path a layer compiles with is the GRADER's, or the layer
    measures something else. Rush 01's grader runs `cc -Wall -Wextra -Werror
    -o rush01 *.c` in the turn-in directory: a quoted #include is searched
    beside the file that includes it and nowhere else, so a header moved to
    includes/ is found only by `#include "includes/name.h"`. A Makefile
    project's include path is the -I its recipes pass, which only `make -Bn`
    knows (_student_bin's includes_out, handed to the compile and forbidden
    layers as --inc-file). Putting every staged header's directory on -I made
    the compile layers green on a turn-in the grader cannot compile, beside a
    program that was a stand-in for the same reason (Rush 01, BSQ, Rush 02).

    A header beside the sources, one the grader brings (under tests/) and a
    harness's are on the path as before: that is where the grader has them,
    or where the harness needs them. Every layer passes its headers through
    here; //tools:conventions refuses the per-header loop written anywhere
    else in this file.
    """
    args = []
    for h in hdrs:
        if _nested_in_turnin(h):
            if staged:
                args += [staged, "$(location %s)" % h]
        else:
            args += [flag, "$(location %s)" % h]
    return args

def _provided(num):
    """What the grader brings for exercise `num`, split the way the builds use it.

    Returns a struct: srcs (the .c copies under tests/, linked with the
    student's code and judged by no layer), hdrs (the .h copies, staged and
    never normed as the student's), includes (the directories those headers
    sit in, for the compiles that #include them by name) and overlay (every
    copy, with where the grader puts it, for a Makefile turned in alone).
    """
    p = _entry(num, "provided")["provided"]
    hdrs = sorted([k for k in p if k.endswith(".h")])
    includes = []
    for h in hdrs:
        d = _dirname(h)
        if d not in includes:
            includes.append(d)
    return struct(
        srcs = sorted([k for k in p if k.endswith(".c")]),
        hdrs = hdrs,
        includes = includes,
        overlay = p,
    )

def _linked(num):
    """What the grader links into exercise `num`'s programs: the contract's `linked`.

    Returns a struct: names (the functions, for the forbidden and symbols
    layers, which tell a student who defines one that the grader brings it),
    libs (their grader_library() labels, linked into every 64-bit program the
    exercise builds, in place of the exercise that writes the function) and
    libs32 (each one's i686 archive, for the ilp32 layer: tools/grader_lib.bzl
    declares it as <label>_i686).
    """
    fns = _entry(num, "linked").get("linked") or {}
    libs = sorted({lib: True for lib in fns.values()}.keys())
    return struct(
        names = sorted(fns.keys()),
        libs = libs,
        libs32 = [lib + "_i686" for lib in libs],
    )

def _no_linked_problem(num, macro, layer, call = None):
    """The message for a `layer` of `macro` that cannot link the grader's library; None if `num` has none.

    A runner that compiles the student's code at test time links what it is
    handed (asan_check.sh and cycles_check.sh take --lib, ilp32_test.sh
    --lib32 for its 32-bit build: its 64-bit program, --gate-bin, is built
    with the library linked); the ones this is called for take none, so a program
    built there could not find the grader's function and would read as the
    student's code not linking. A whole macro that cannot is refused by
    _entry() instead (_TAKES_LINKED). A value first: contract_problem() hands
    it to the fixtures. `call` is the key the call names where it is not
    `num`: a function of the library `num` (_resolve).
    """
    linked = _linked(num)
    if not linked.libs:
        return None
    return (("%s(%s): the grader links %s into this %s (its " +
             "contract's `linked`), and the %s layer's runner cannot link a grader " +
             "library yet: its program would not link, and that would read as the " +
             "student's fault. Give the runner a --lib, as asan_check.sh and " +
             "cycles_check.sh take (ilp32_test.sh takes --lib32 for its 32-bit build; " +
             "its 64-bit program, --gate-bin, is built with the library linked).") %
            (macro, _call(call or num), ", ".join(linked.names), _kind_word(num, _entry(num, "linked")), layer))

def _no_linked(num, macro, layer, call = None):
    """fail() with _no_linked_problem()'s message, where there is one."""
    problem = _no_linked_problem(num, macro, layer, call)
    if problem:
        fail(problem)

def _allowed(num):
    """The forbidden layer's list for exercise `num`: None for no layer."""
    e = _entry(num, "allowed")
    if e["allowed"] == None:
        return None
    return e["allowed"] + e["variables"]

def _deliverable_srcs(ex):
    """Every .c file the student turns in for exercise `ex`, possibly none.

    GLOBBED, never listed. The subject's file set is written down in exactly one
    place -- this project's subject() contract -- and the files layer CHECKS it
    against the directory; compilation globs the directory for the names and
    patterns the contract gives (_turnin_files), so the two cannot drift
    apart, and a file the contract does not let it hold is compiled by no
    layer.

    They used to. Five macros -- c_function, c_mem_check, c_program, c_cycles and
    c_reference_cost -- each computed `deliverable/exNN/<fn>.c` independently, so
    an exercise whose subject asks for two files had to override `srcs` at all
    five call sites. c-07 ex04 overrode c_function and not c_cycles, and the
    result was a link error at -O2 naming ft_strlen and ft_atoi_base, which reads
    as a problem with the optimisation level rather than a missing source.

    Only these five ever needed it: c_perf, c_argv_table and c_diff name no files
    at all, referencing the targets built above them (:exNN_bin, :fn), and
    within c_function every layer -- norm, both compilers, forbidden,
    prototype, symbols, ilp32, asan, valgrind -- already reads one `srcs` local.
    The same five take their headers from _deliverable_hdrs() below: a macro
    that globs the sources and not the headers beside them builds a folder it
    has only half staged.

    Flat unless the contract says otherwise (see _turnin_files()).

    NOT used by the rush macros, and must not be. rush-00's deliverable/ex00
    holds rush00.c .. rush04.c, each defining rush(), plus main.c and
    ft_putchar.c; compiling that directory as one unit is a duplicate-symbol
    error by design. rush_common()/rush_variant() name their files explicitly
    for that reason, each through _zone().

    AN EMPTY DIRECTORY GIVES AN EMPTY LIST, and that is handled where it is
    used: the programs built from it are stand-ins that say there is no .c file
    (tools/student_build.sh), and every layer that reads the files is emitted
    as a "not turned in" test (_test's `turnin`). It used to fall back to the
    conventional file name, a literal path that Bazel then failed to find while
    ANALYSING the package -- the missing file broke every target that named it
    instead of failing the tests that needed it.
    """
    return _turnin_files(_key(ex), ".c")

def _deliverable_hdrs(ex, listed = None):
    """Every .h the contract lets exercise `ex` turn in, the named ones first.

    The same five macros read this, under the same condition: `srcs` left at
    its default. A macro that compiles the directory has to stage the headers
    in it too, because a Bazel sandbox holds only what a target declares. A
    student who moved their prototypes into a header of their own got "'ft_tail.h'
    file not found" on their own #include line from every binary and layer,
    while `make` built the same folder, and a header nothing included was never
    shown to norminette at all (C 10, C 11 ex05, Piscine Reloaded ex27). The
    subjects of those exercises leave the file layout to the student, so a
    header there is normal, and one that is not staged is the harness's fault.

    First the headers the contract's `files` names (C 12's ft_list.h), then
    `listed` (a caller's explicit hdrs), each kept in that order -- except a
    file under deliverable/ that is not there, which is dropped (see
    _zone()): the compile that needed it then fails in the compiler's words,
    and the files layer says it is missing. Then every other header the
    contract lets lie there (_turnin_files()), so a call site cannot make one
    beside the sources disappear. allow_empty, for the reason
    _deliverable_srcs() gives: most exercises have no header.
    """
    d = turnin_dir(_key(ex))
    named = [d + "/" + f for f in (_entry(_key(ex), "turnin")["files"] or []) if f.endswith(".h")]
    listed = _zone(named + [h for h in (listed or []) if h not in named])
    found = _turnin_files(_key(ex), ".h")
    return listed + [h for h in found if h not in listed]

def _in_zone(path):
    """Whether a package-relative path is in AGENTS.md section 0's zone.

    That is the student's work: anything under a deliverable/ or a generators/.
    """
    return path.startswith("deliverable/") or path.startswith("generators/") or \
           "/deliverable/" in path or "/generators/" in path

def _is_student_path(p):
    """Whether `p` names a file of the student's: a path, not a label (:, //, @), in the zone."""
    return not (p.startswith(":") or p.startswith("//") or p.startswith("@")) and _in_zone(p)

def _zone(paths):
    """`paths`, less every file of the student's that is not there.

    A path under deliverable/ or generators/ is kept only if a glob finds it; a
    label, or a harness file under tests/, is kept as given. This is how a
    caller's LITERAL deliverable path -- c-12's hdrs = ["deliverable/ex00/
    ft_list.h"], a c_make anchor, a rush's main.c -- stops being a declared
    input that Bazel fails to find while analysing the package. A literal that
    reached `data` or `srcs` unfiltered took down every target naming it, and
    before --keep_going the whole module run with it; filtered, the targets that
    need the file fail as tests, and the files layer names it.

    A turn-in path whose name _safe() refuses is dropped the same way, whoever
    globbed it: see _SAFE_CHARS.
    """
    out = []
    for p in paths:
        if not _is_student_path(p):
            out.append(p)
        elif _safe(p) and native.glob([p], allow_empty = True):
            out.append(p)
    return out

def _student_bin(
        name,
        harness = None,
        srcs = None,
        hdrs = None,
        deps = None,
        includes = None,
        asan = False,
        diffio = False,
        archive = True,
        dir = None,
        makefile = None,
        make_data = None,
        includes_out = None,
        prototype = None,
        sources_out = None,
        make_goal = None,
        linkopts = None,
        copts = None,
        tags = None):
    """THE one way to build a program from deliverable sources.

    Every binary a layer runs that holds a student's code is built here, through
    tools/student_build.bzl, and never by cc_binary or cc_library: a student's
    compile error, warning under -Werror, leftover main() or missing file then
    turns this program into a stand-in that prints the compiler's words and
    fails each test that runs it, instead of failing the BUILD (see
    tools/student_build.sh). The flags, the pinned toolchain and the way the
    student's files are linked are the ones a cc_binary had.

    WHAT DOES NOT COME THROUGH HERE, and why: the layers that compile a
    student's files INSIDE their runner, at test time -- compile, forbidden,
    symbols, prototype, the header shape (header_check.sh), asan_check, ilp32,
    allocfail, cycles and refcost. They are not build actions, so a file that
    does not compile is already that test's red, with the compiler's words,
    and never the build's. Each also compiles differently on purpose (both
    campus compilers, -m32 through the pinned zig, -O2, an allocator shim), so
    moving them here would put a test-time question into the build graph and
    buy nothing this change was for. Routing their compile LINES through one
    helper is a separate question (runner_lib.sh's).

    Args:
        name: the target, e.g. "ex03_bin".
        harness: the test's own sources and headers (a main()), always linked.
        srcs: the student's sources and headers, and any the grader supplies.
            Archived and linked after the harness, as a cc_library's were,
            unless archive = False.
        hdrs: more headers to stage (a provided one under tests/).
        deps: the exercise's own student_unit (its `:fn`), whose sources join
            the library and whose include directories follow this binary's
            own; a grader_library() the contract's `linked` names; or a
            cc_library of the harness's own, linked as a cc_binary would link
            it. Never another exercise's unit (see c_function).
        includes: package-relative include directories, first on the -I path.
        asan: build the ASan/UBSan twin (_ASAN_COPTS, _ASAN_LINKOPTS). Tagged
            manual, so it is built only when a test that runs it is.
        diffio: link //tools:diffio, the diff reader harnesses' helpers.
        archive: False links `srcs` directly, as a program exercise's are.
        dir: package-relative directory of the student's own sources; when none
            of `srcs` is under it, the stand-in says so in those words.
        makefile: the deliverable's Makefile (a package-relative path, found
            through _zone): take the sources from `make -Bn`. When it is not
            there, the program is a stand-in saying so -- unless `srcs` are
            given too: those are then built while the Makefile is missing
            or compiles nothing, and the moment it names a source it alone
            decides (tools/student_build.sh, UNTIL THE MAKEFILE IS WRITTEN;
            c_program's makefile = "once_written").
        make_data: the files to stage beside the Makefile.
        includes_out: with `makefile`, a file name to write the -I
            directories its recipes pass to, one per line: the include path
            of the compile and forbidden layers of the same turn-in
            (_compile_tests' inc_file), from the same `make -Bn`.
        prototype: REQUIRED with `harness`, refused without one. The test
            that holds the functions the harness calls to the signatures the
            subject fixes: a `_prototype` test of this package, as
            _prototype_test() returns its name; or why there is none, as a
            string that starts "none: " ("none: the subject fixes no
            prototype for ft_putchar"). A harness links a student's function
            the way the grader's main() does, and C links a mismatched
            signature without a word: the prototype layer is the only thing
            that sees one. It is required HERE, where every harness is
            built, and not in one helper: rush_variant built three harnesses
            and emitted no prototype layer at all (finding 142), and when
            the requirement moved into _output_fixture_binary, the diff,
            perf, memcheck and Rush 00's own programs still linked a harness
            without it. It is written as a tag (_HARNESS_PROTO_TAG), and
            c_levels()' audit fails a package whose harness names a test it
            lacks, or whose student_binary with a harness carries no tag.
        sources_out: with `makefile`, a file name to write the .c files its
            recipes compile to, one per line, from the turn-in directory
            ("unknown" when make could not plan the build): what the files
            layer reads to find a source the Makefile never builds
            (_built_manifest).
        make_goal: with `makefile`, the rule to plan the build with (make -Bn
            <goal>): the contract's goal, for a part of several at the root
            that a rule of its own builds (subject()'s units). None: what a
            bare make runs. Refused without `makefile`, and with `srcs`, which
            would be built in its place while that rule compiles nothing.
        linkopts: more link flags, after the sanitizer's: a program
            exercise's allocation-failure twin wraps malloc and free
            (c_program's `allocfail`), and the guarded-argv replay wraps
            main (c_argv_table).
        copts: more compile flags, after the sanitizer's, for every file
            compiled. Nothing passes any today: the guarded-argv replay
            renamed the student's main this way, and a main() renamed loses
            C's implicit return 0 (it links main wrapped instead).
        tags: more tags.
    """
    problem = _harness_prototype_problem(name, harness, prototype)
    if problem:
        fail(problem)
    copts = _COPTS + (_ASAN_COPTS if asan else []) + (copts or [])
    linkopts = (_ASAN_LINKOPTS if asan else []) + (linkopts or [])
    tags = (tags or []) + (["manual"] if asan else [])
    if harness:
        tags = tags + [_HARNESS_PROTO_TAG + ("none" if prototype.startswith("none: ") else prototype)]
    deps = (deps or []) + (["//tools:diffio"] if diffio else [])
    kw = {}
    if includes_out:
        if makefile == None:
            fail("_student_bin(%s): includes_out is the Makefile's -I list, and there is no makefile" % name)
        kw["includes_out"] = includes_out
    if sources_out:
        if makefile == None:
            fail("_student_bin(%s): sources_out is the Makefile's .c list, and there is no makefile" % name)
        kw["sources_out"] = sources_out
    if make_goal != None:
        if makefile == None:
            fail("_student_bin(%s): make_goal is a rule of the Makefile, and there is no makefile" % name)
        if srcs:
            fail(("_student_bin(%s): make_goal builds what that rule compiles, and srcs " +
                  "would be built in its place while it compiles nothing") % name)
        kw["make_goal"] = make_goal
    if makefile != None:
        found = _zone([makefile])
        if found:
            kw["makefile"] = found[0]
            kw["make_data"] = _zone(make_data or [])
        else:
            kw["missing_makefile"] = makefile
    # WHAT IT IS BUILT FOR, for the stand-in's words (student_build.sh's
    # --kind): in a contract of units, the kind of the unit the name begins
    # with, "library" for a function's programs, which are built from its
    # library's files, and "project" for a name that begins with no unit, as
    # _test() words a test of the whole project. Nothing for an exercise, so
    # a Piscine program's rule is the same.
    contract = _contract_or_none()
    if contract != None and "units" in contract:
        rows = _units_of(contract)
        u = _unit_of_name(name, [r["name"] for r in rows])
        kind = [r["kind"] for r in rows if r["name"] == u][0] if u else "project"
        kw["unit_kind"] = "library" if kind == "function" else kind
    if not _is_student_bin_name(name):
        fail(("_student_bin(name = %r): a program built from a student's files " +
              "is named ending in one of %s, with a \"_\" and no \".\" in it, so " +
              "that _test() can tell it from its label alone, wherever it is " +
              "declared, and from a data file (_STUDENT_BIN_SUFFIXES).") %
             (name, ", ".join(_STUDENT_BIN_SUFFIXES)))
    student_binary(
        name = name,
        harness = harness or [],
        srcs = _zone(srcs or []),
        hdrs = _zone(hdrs or []),
        deps = deps,
        includes = includes or [],
        copts = copts,
        linkopts = linkopts,
        archive = archive,
        dir = dir or "",
        # A sanitizer's report names file:line only if the binary keeps its
        # debug info, and fastbuild links with -Wl,-S (--strip's default,
        # "sometimes"), which drops it whatever -g the compile had.
        keep_debug = asan,
        tags = tags,
        **kw
    )

def _student_lib(name, srcs, hdrs = None, includes = None, deps = None, tags = None):
    """An exercise's files as a unit other binaries link: what `:fn` names.

    The successor of the cc_library each c_function and rush macro declared --
    same sources, same headers, same include directories -- except that it
    builds nothing, so it cannot fail. The binaries that link it compile its
    sources themselves (_student_bin), each with its own flags: the plain and
    the ASan twin used to be two libraries.

    `deps` is for a unit of the SAME turn-in, and only the rush macros pass
    one: a rush variant's rectangle calls the team's ft_putchar.c, which sits
    beside it in the turn-in. No public macro takes it any more (see
    c_function): another exercise's files are never linked in.
    """
    student_unit(
        name = name,
        srcs = _zone(srcs),
        hdrs = _zone(hdrs or []),
        includes = includes or [],
        deps = deps or [],
        tags = tags or [],
    )

def student_lib(name, srcs, hdrs = None, includes = None):
    """A unit of a student's files for a layer to link, declared by hand.

    For the one place a module needs a unit no exercise macro declares: c-09
    ex00, whose functions are archived by the student's own script, so there is
    no c_function to declare `:ft_strcmp` for its c_diff. A module BUILD file
    must never declare a cc_library or cc_binary over deliverable sources
    (//tools:conventions refuses it): one that does not compile is a BUILD
    error, not a red test. This builds nothing, so it cannot fail; the
    binaries that link it compile it (see _student_bin).

    Args:
        name: the unit's name, as c_diff's `fn` names it.
        srcs: the sources, package-relative. Literal paths are fine: a file that
            is not there is dropped (_zone), and the programs that needed it are
            stand-ins that say what failed.
        hdrs: headers to stage beside them.
        includes: package-relative include directories.

    No `deps`: a unit holds one turn-in's files, and never links another
    exercise's (see c_function, where `deps` went and why).
    """
    _student_lib(
        name = name,
        srcs = srcs,
        hdrs = hdrs,
        includes = includes,
    )

# ONE FUNCTION OF A LIBRARY. A Common Core library is one unit whose
# subject prints a box per function (Libft's Part 2 and Part 3), and whose
# turn-in is one Makefile building one archive: so the files, the Makefile,
# the Norm, both compilers, the prototypes, the union of the allowed
# functions and the exported names are the WHOLE library's (c_library,
# once), while the output, the memory layers, the differential corpus and
# the costs are each FUNCTION's. The contract lists the functions, each a
# unit with the External Functions its own box allows (subject(units =
# {"<library>": unit(..., functions = {...})}), tools/subject.bzl). A
# c_function, c_mem_check, c_diff, c_perf or c_cycles call whose `unit`
# names one of them is that function's (_resolve, _member): every target it
# emits is named <function>_<what>, every file it reads is under
# tests/<function>/, every gate waits for <function>_output, and its
# programs link the library's unit (:<library>_lib) through the turn-in's
# Makefile, as the grader builds it. c_levels() gives every unit a suite of
# its own name (//<module>:<unit>), and its audit refuses a unit with no
# test and a test of a library that is none of the whole library's.

# The tests of the whole library, as <library><rest>: what c_library,
# c_make, c_readme and the norm and contract layers c_levels() gives a unit
# name a test of the library rather than of one function. The audit takes
# these, and only these, as the library's own: a layer's suffix alone is
# no proof, since _asan, _valgrind, _diff or _output on a library are a
# function's layers that lost its name (V230). A macro that comes to emit
# another test of the whole library adds it here, or the audit refuses
# every library that has it, at load.
_LIBRARY_SUFFIXES = [
    "_build",
    "_build_exit",
    "_build_recipe",
    "_build_rules",
    "_build_wildcards",
    "_compile_clang",
    "_compile_gcc",
    "_declares_output",
    "_files",
    "_forbidden",
    "_forbidden_functions",
    "_forbidden_through",
    "_globals",
    "_layout_prototype",
    "_norm",
    "_norm_header",
    "_norm_notice",
    "_norm_provided",
    "_norm_provided_notice",
    "_prototype",
    "_prototype_names",
    "_prototype_restrict",
    "_prototype_restrict_all",
    "_readme",
    "_readme_wording",
    "_symbols",
]

# Every target name a module declares outside its exercises and units
# (c_levels(), subject()): a unit's suite, named after it, may be none of
# them (_RESERVED_UNIT_NAMES).
_MODULE_NAMES = _LEVEL_NAMES + [
    "conventions_srcs",
    "deliverable_files",
    "deliverable_files_names",
    "manual",
    "subject",
    "test_units",
    "units",
    _MEMORY_GRADED,
    _MEMORY_GRADED_ACCESS,
]

# THE NAMES NO UNIT MAY TAKE. In a contract of units (subject(units =
# {...})) a unit's name is also its suite's, the first word of its targets
# (<unit>_<what>) and the word a student types after the project
# (`42 test <project> <unit>`). So tools/subject.bzl's subject() refuses a
# unit, or a function of a library, named one of these, or named so that it
# and a _ begin one ("memory" would begin memory_graded_access), or beginning
# one that ends in _, which reserves every name it begins. It cannot load
# this file, so subject() above hands it the list as `reserved`. Reserved:
#   - the levels, and all, which 42 takes as a level;
#   - every layer, and norminette, 42's word for the norm layer;
#   - layout, the folder under tests/ that holds the grader's structures;
#   - the module's own targets (_MODULE_NAMES);
#   - the prefixes lvl_ (the level tags), manual_ (the audit holds :manual
#     to every manual_* test, _suite_problems) and waiting_ (the lists
#     _WAITING writes, waiting_<test>; and through the rule above the
#     finalizer :waiting itself).
# Sorted, one name a line. reserved_unit_names_problem() holds it to the
# tables it comes from (//tools/tests:starlark_unit), and //tools:conventions
# holds docs/reference.md's "Reserved unit names" and the words
# tools/fortytwo/workspace.py takes as a level (LEVELS) or reads as a layer
# (LAYER_ALIASES) to it.
_RESERVED_UNIT_NAMES = [
    "all",
    "allocfail",
    "asan",
    "basic",
    "compile",
    "complete",
    "conventions_srcs",
    "cycles",
    "deliverable_files",
    "deliverable_files_names",
    "diff",
    "diff_asan",
    "files",
    "forbidden",
    "ilp32",
    "layout",
    "lvl_",
    "manual",
    "manual_",
    "memory_graded_access",
    "memory_graded_leaks",
    "method",
    "norm",
    "norminette",
    "oracle",
    "output",
    "perf",
    "prototype",
    "robust",
    "selftest",
    "strict",
    "subject",
    "symbols",
    "test_units",
    "units",
    "valgrind",
    "waiting_",
]

def reserved_unit_names_problem(names = None):
    """Why a list of reserved unit names is not the harness's own; None if it is.

    The harness's own is every level, layer and target of a module's own
    (_LEVEL_NAMES, _LAYER_LEVEL, _MODULE_NAMES), all, layout, norminette and
    the prefixes lvl_, manual_ and waiting_, each once: _RESERVED_UNIT_NAMES'
    comment says why each. A level, a layer or a module target added to its
    table and not to the list would be a name a unit could take, and its
    targets and suite would then read as that one's.

    Args:
      names: the list to hold to them; _RESERVED_UNIT_NAMES where None.

    Returns:
      None, or what the list lacks, holds that nothing reserves, or holds
      twice, as a sentence.
    """
    if names == None:
        names = _RESERVED_UNIT_NAMES
    want = {}
    for n in _LEVEL_NAMES + ["all", "layout", "norminette", "lvl_", "manual_", "waiting_"] + _MODULE_NAMES + _LAYER_LEVEL.keys():
        want[n] = True
    if sorted(names) == sorted(want.keys()):
        return None
    seen = {}
    twice = {}
    for n in names:
        if n in seen:
            twice[n] = True
        seen[n] = True
    found = [
        "%s: %s" % (what, ", ".join(sorted(ns)))
        for what, ns in [
            ("missing", [n for n in want if n not in seen]),
            ("not reserved by anything", [n for n in seen if n not in want]),
            ("named twice", twice.keys()),
        ]
        if ns
    ]
    return "the reserved unit names are not the harness's own; %s" % "; ".join(found)

def _member_problem(num, function, fn, passed, library, who):
    """Why a call on one function of a library is refused; None where it may run.

    Args:
      num: the library, the unit whose `functions` list the function.
      function: the function the call's `unit` names (_resolve).
      fn: the call's `fn`, which must name the same function.
      passed: the names of the library-wide arguments the call passed
        (srcs, hdrs, exports, prototype), which are c_library()'s.
      library: whether :<library>_lib is declared above the call
        (c_library()).
      who: the call, for the message.
    """
    if fn != function:
        return (("%s: fn = %r, and the unit is the function %s: a function's calls " +
                 "judge that function alone, so fn names it, or is left out.") %
                (who, fn, function))
    if passed:
        return (("%s: %s is the whole library's, which c_library(%s) declares " +
                 "once from the subject() contract. Drop it.") %
                (who, " and ".join(passed), _call(num)))
    if not library:
        return (("%s: no :%s_lib above it. A function's programs link the library " +
                 "c_library(%s) declares: call that first, above every call on one of " +
                 "its functions.") % (who, _prefix(num), _call(num)))
    return None

def _member(num, function, fn, refusals, who, srcs = None, hdrs = None, exports = None, prototype = None):
    """One function of a library, as a macro that judges one reads it: None, False or a struct.

    None where `function` is None: the call names a whole unit, or an
    exercise, and is its own. False where the call is refused and the
    macro, in the macro fixtures (`refusals`), must return having emitted
    nothing (_refuse). Otherwise struct(stem, the function's own name, the
    start of every target the call names; tdir = "tests/<function>", where
    every file it reads is; deps = [":<library>_lib"], the library's unit
    every program links; kw, the Makefile its programs are built through
    (_student_bin's makefile and make_data, as _manifest_build() builds it:
    `make -Bn` decides, and the library's sources stand in while it
    compiles nothing); allowed, the function's own box plus the contract's
    `variables`; proto, the library's <library>_prototype, or why there is
    none; inc, the -I list of the library's Makefile, which c_library()
    writes (_library_includes) and every layer of the function that
    compiles the sources itself reads as --inc-file).

    `num` is the library's name and `function` the unit the call named
    (_resolve): the library's own files stay under tests/<library>/.

    srcs, hdrs, exports and prototype: the call's own, passed only by the
    macros that take them, and each refused where it is not None: the
    library's sources, headers, exported symbols and prototype test are
    c_library()'s, and a function's harness is held to the library's
    prototype test -- c_function's `prototype = False`, or another test
    named to c_mem_check, c_diff or c_perf, would hold it to less, or to
    nothing, unseen. c_function passes its `prototype` only where it is not
    its default.
    """
    if function == None:
        return None
    e = _entry(num, "member")
    ex = _prefix(num)
    passed = [k for k, v in [("srcs", srcs), ("hdrs", hdrs), ("exports", exports), ("prototype", prototype)] if v != None]
    problem = _member_problem(num, function, fn, passed, native.existing_rule(ex + "_lib") != None, who)
    if _refuse(problem, refusals, who):
        return False
    d = turnin_dir(num)
    kw = {}
    if "Makefile" in (e["files"] or []) + e["optional"]:
        kw = {
            "makefile": d + "/Makefile",
            "make_data": turnin_glob([d + "/**"], exclude = _not_build_products(d)),
        }
    proto = ex + "_prototype"
    if not native.existing_rule(proto):
        proto = "none: c_library(%s, prototype = False), which says why" % _call(num)
    return struct(
        stem = function,
        tdir = "tests/" + function,
        deps = [":" + ex + "_lib"],
        kw = kw,
        allowed = e["functions"][function] + e["variables"],
        proto = proto,
        inc = _LIBRARY_INCLUDES % ex,
    )

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
#
# The same list //tools:submit leaves out of the push (its ':(exclude)'
# pathspecs; //tools:conventions holds the two together): the files layers
# report what is pushed, so what is never pushed is never theirs to report.
_BUILD_PRODUCTS = ["*.o", "*.a", "*.out", "*.gch"]

def _not_build_products(d):
    """Glob exclude patterns for what is under directory `d` and never pushed.

    Build output (_BUILD_PRODUCTS), and any .git directory: //tools:submit
    keeps its scratch repository at deliverable/.git after a push (it is
    rebuilt on the next), and git never pushes a .git directory's contents.
    Left in, the first submit made the files layers that walk the whole tree
    -- deliverable_files, and BSQ's bsq_files at the root -- report .git/HEAD
    and the rest as files nobody asked for, and the next submit's gate refuse
    the module over them.
    """

    # `**/` matches zero or more segments, so this covers both d/x.o and
    # d/srcs/x.o -- a Makefile run by hand leaves its objects beside sources
    # in a subdirectory as readily as beside the Makefile.
    return [d + "/**/" + p for p in _BUILD_PRODUCTS] + [d + "/**/.git/**"]

# The label of the include list c_library() writes for exercise exNN
# (_library_includes), % "exNN".
_LIBRARY_INCLUDES = ":%s_make_bin_includes.txt"


# ---------------------------------------------------------------------------
# WHAT THE FILES ABOVE THIS ONE LOAD OF IT. A load() cannot name a private
# symbol, so each one they use is given a public name here, its own without
# the underscore, and loaded back under its own name: the code reads as it did
# when tools/defs.bzl held it all. These names are for those files alone; a
# BUILD file loads //tools:defs.bzl.
audit_inputs = _audit_inputs
WAITS_TAG = _WAITS_TAG
GATE_FLAGS = _GATE_FLAGS
loc_of = _loc_of
norm_label = _norm_label
opts = _opts
after_dashes = _after_dashes
opt_values = _opt_values
opt_value = _opt_value
waiting_name = _waiting_name
waiting_outputs = _waiting_outputs
waits_for = _waits_for
waiting_lists = _waiting_lists
refuse = _refuse
is_student_bin_name = _is_student_bin_name
dirname = _dirname
no_contract_problem = _no_contract_problem
contract = _contract
no_entry_problem = _no_entry_problem
linked_reader_problem = _linked_reader_problem
entry = _entry
resolve_problem = _resolve_problem
contract_or_none = _contract_or_none
goal_of = _goal_of
root_parts = _root_parts
fn_lib = _fn_lib
part_files = _part_files
resolve = _resolve
call_kw = _call_kw
required = _required
untranscribed_problem = _untranscribed_problem
turnin_file_problem = _turnin_file_problem
issued_problem = _issued_problem
diff_harness_problem = _diff_harness_problem
where = _where
misplaced = _misplaced
student_folders = _student_folders
turnin_files = _turnin_files
inc_args = _inc_args
provided = _provided
linked = _linked
no_linked_problem = _no_linked_problem
no_linked = _no_linked
allowed = _allowed
deliverable_srcs = _deliverable_srcs
deliverable_hdrs = _deliverable_hdrs
zone = _zone
student_bin = _student_bin
student_lib_private = _student_lib
LIBRARY_SUFFIXES = _LIBRARY_SUFFIXES
RESERVED_UNIT_NAMES = _RESERVED_UNIT_NAMES
member = _member
not_build_products = _not_build_products
LIBRARY_INCLUDES = _LIBRARY_INCLUDES
