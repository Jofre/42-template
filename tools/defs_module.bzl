"""c_levels() and the audit of a module as a whole.

c_levels() emits a module's suites (a level, an exercise, its manual targets)
and declares the finalizer that audits the module once it is declared
(_levels_audit, _audit_problems). And contract_problem(), every load-time check
of a call in one function, and starlark_selftest_arms(), the fail() guards on
known inputs, both for //tools/tests:starlark_unit. _MODULE_TESTS and
_GATE_LABEL_RUNNERS are read as text by //tools:conventions.

Loaded by the files above it, and re-exported by tools/defs.bzl, the one
file a BUILD file loads.
"""

load(
    ":defs_checks.bzl",
    _APOSTROPHE = "APOSTROPHE",
    _CASE_KEYS = "CASE_KEYS",
    _GOOD_VALUE = "GOOD_VALUE",
    _allocfail_problem = "allocfail_problem",
    _argv_model_problem = "argv_model_problem",
    _case = "case",
    _case_exit_error = "case_exit_error",
    _case_problem = "case_problem",
    _exit_flags = "exit_flags",
    _exit_source = "exit_source",
    _forbidden_allowed_problem = "forbidden_allowed_problem",
    _function_malloc_problem = "function_malloc_problem",
    _header_exit_error = "header_exit_error",
    _header_norm_test = "header_norm_test",
    _memory_gate = "memory_gate",
    _memory_rule_problem = "memory_rule_problem",
    _missing_file_problem = "missing_file_problem",
    _model_problem = "model_problem",
    _survive_gate = "survive_gate",
)
load(
    ":defs_contract.bzl",
    "turnin_dir",
    _GATE_FLAGS = "GATE_FLAGS",
    _LIBRARY_SUFFIXES = "LIBRARY_SUFFIXES",
    _RESERVED_UNIT_NAMES = "RESERVED_UNIT_NAMES",
    _audit_inputs = "audit_inputs",
    _contract = "contract",
    _diff_harness_problem = "diff_harness_problem",
    _entry = "entry",
    _issued_problem = "issued_problem",
    _linked_reader_problem = "linked_reader_problem",
    _loc_of = "loc_of",
    _no_contract_problem = "no_contract_problem",
    _no_entry_problem = "no_entry_problem",
    _no_linked_problem = "no_linked_problem",
    _not_build_products = "not_build_products",
    _opt_value = "opt_value",
    _opt_values = "opt_values",
    _opts = "opts",
    _part_files = "part_files",
    _provided = "provided",
    _refuse = "refuse",
    _resolve_problem = "resolve_problem",
    _root_parts = "root_parts",
    _student_folders = "student_folders",
    _turnin_file_problem = "turnin_file_problem",
    _untranscribed_problem = "untranscribed_problem",
    _waiting_lists = "waiting_lists",
    _waiting_outputs = "waiting_outputs",
    _waits_for = "waits_for",
)
load(
    ":defs_files.bzl",
    "c_files",
    _built_manifest = "built_manifest",
    _built_programs = "built_programs",
    _manifest_build = "manifest_build",
    _readme_problem = "readme_problem",
    _turnin_names = "turnin_names",
)
load(
    ":defs_levels.bzl",
    _FIXTURES = "FIXTURES",
    _GRADED_LAYER = "GRADED_LAYER",
    _LAYER_LEVEL = "LAYER_LEVEL",
    _LEVEL_NAMES = "LEVEL_NAMES",
    _LIB_RUNNERS = "LIB_RUNNERS",
    _MANUAL = "MANUAL",
    _MEMORY_GRADED = "MEMORY_GRADED",
    _MEMORY_GRADED_ACCESS = "MEMORY_GRADED_ACCESS",
    _NO_MANUAL_TAG = "NO_MANUAL_TAG",
    _RAISED = "RAISED",
    _SUFFIX_LAYER = "SUFFIX_LAYER",
    _UNIT_TAG = "UNIT_TAG",
    _call = "call",
    _glob_match = "glob_match",
    _is_ex = "is_ex",
    _is_unit_key = "is_unit_key",
    _key = "key",
    _kind_word = "kind_word",
    _layer_level = "layer_level",
    _prefix = "prefix",
    _suffix_of = "suffix_of",
    _uniq = "uniq",
    _unit_tag = "unit_tag",
)
load(
    ":defs_library.bzl",
    _libft_make_problem = "libft_make_problem",
    _library_args_problem = "library_args_problem",
    _library_entry_problem = "library_entry_problem",
    _make_problem = "make_problem",
)
load(
    ":defs_program.bzl",
    _PROGRAM_NAME_TAG = "PROGRAM_NAME_TAG",
    _make_anchor_problem = "make_anchor_problem",
)
load(":defs_rush.bzl", _rush_graded_problem = "rush_graded_problem")
load(
    ":defs_test.bzl",
    "shell_word",
    "stderr_ignored",
    _ARGV_GUARD_SUFFIX = "ARGV_GUARD_SUFFIX",
    _CORPUS_RUNNERS = "CORPUS_RUNNERS",
    _COVERS_TAG = "COVERS_TAG",
    _GATE_NO_INPUT_RUNNERS = "GATE_NO_INPUT_RUNNERS",
    _NO_GATE_TAG = "NO_GATE_TAG",
    _NO_VALGRIND_TAG = "NO_VALGRIND_TAG",
    _corpus_of = "corpus_of",
    _hand_tag_problem = "hand_tag_problem",
    _compared_run = "compared_run",
    _memcheck_allowed = "memcheck_allowed",
    _output_run = "output_run",
    _runner_choice_problem = "runner_choice_problem",
    _standin_runner_problem = "standin_runner_problem",
    _table_run = "table_run",
    _test = "test",
    _test_env_problem = "test_env_problem",
    _waiting_problems = "waiting_problems",
)
load(
    ":defs_toolchain.bzl",
    _HARNESS_PROTO_TAG = "HARNESS_PROTO_TAG",
    _harness_prototype_problem = "harness_prototype_problem",
    _path_glob_match = "path_glob_match",
)
load(":names_file.bzl", "names_file")
load(
    ":subject.bzl",
    _contract_entries = "contract_entries",
    _contract_of_rule = "contract_of_rule",
    _contract_or_none = "contract_or_none",
    _exercise_problem = "exercise_problem",
    _linked_problem = "linked_problem",
    _subject_problem = "subject_problem",
    _unit_problem = "unit_problem",
    _units_of = "units_of",
)

def _audit_problems(pkg, tests, exercises, layouts = None, fixtures = None, oracle = None, makefiles = None, malloc = None, clues = None, diffio = None, suites = None, programs = None, memory_graded = False, units = None):
    """What c_levels()' audit fails a package for, as a list of messages.

    A value before it is a fail(), like every contract check: contract_problem()
    hands the fixtures a broken package to prove each message. Module-wide rules
    are checked HERE, once the whole package is declared, and not inside the
    helper a macro happens to call: the exercise tag was added by _test() alone,
    so the hand-written sh_tests had none and every :exNN suite missed them
    (findings 070, 074, 175); a manual test was in no suite and no document
    (002); a raise or a target suffix was in one BUILD comment (038, 072).

    Nothing a student writes can make one of these: the tests come from the
    BUILD file and the macros, a folder of theirs that is no exercise gets a
    files test (c_levels), and which Rush 00 variants are manual is matched by
    a pattern. So a failure here is the harness's, at `bazel query` time, on
    the author's machine.

    A structure file under tests/layout/ that no test reads is one too: a
    macro that does not read the folder (only c_function does, through
    _layouts()) drops it without a word, and the structure it holds is then
    checked by nothing while docs/reference.md says the prototype layer
    checks it (WP-47).

    Args:
        pkg: the package, as "c-piscine/c-piscine-c-05".
        tests: every test rule of the package: {name: {"kind": ..., "tags":
            [...], "layouts": [...], "srcs": [...], "args": [...]}},
            "layouts" being the tests/layout/ files it passes a runner with
            --layout (_layout_args()); layouts, srcs and args may be absent.
        exercises: the exNN names c_levels() found: the contract's, and the
            folders under tests/, deliverable/ and generators/.
        layouts: every file under the package's tests/layout/.
        fixtures: every student_binary with a harness, as {binary: the
            prototype test its tag names, "none", or None where it carries
            no tag}. One naming a test the package does not declare, or one
            with no tag at all (built some way other than _student_bin), is
            a harness over a student's function with no check of its
            signature (finding 142).
        oracle: {"owners": {test running tools/oracle_fixtures.sh: what
            _oracle_owner read from it}, "reads": {test of a named case: the
            files its _CASE_READS_TAG lists}}. A case reading a file in an
            owner's directory that none of its --owns patterns matches reads
            a file nothing holds to the reference.
        makefiles: the exNN names whose contract `files` names a Makefile:
            each must have its exNN_build (c_make), or the Makefile it turns
            in is built by nothing that judges it.
        malloc: the exNN names whose subject() contract allows malloc, or
            prints no allowed-functions line at all (_memcheck_allowed).
        clues: every clues*.tsv under the package's tests/. One that no
            test hands a runner (`$(location FILE)` among its args) is a
            set of hints nobody is shown: Reloaded ex24's and C 09 ex01's,
            the hints of two exercises that are a Makefile alone, were
            printed by nothing, since c_make took no clue file (V4).
        diffio: the student_binary rules that link //tools:diffio, whose
            malloc fills each block it hands out (tools/dirty_malloc.c). No
            memcheck layer may run one (_diffio_memcheck_problems).
        suites: every test_suite of the package, as {name: {"tags": [...],
            "tests": [the names it lists]}} (_audit_suites). A manual one
            named N is asked for by name, to run what N_* names: it lists
            every test of the package so named (_suite_problems).
        programs: every student_binary that names its program, as {binary:
            the name its program_name= tag gives} (_audit_programs).
            c_program's exNN_bin names the program it runs, and where a
            c_make judges the same exercise its exNN_build's --artifact is
            the program the Makefile builds: the two are one program, and
            one name.
        memory_graded: whether the package's subject() contract declares
            memory_graded: its valgrind layer then sits at basic
            (_layer_level), and every test of that layer quotes a rule
            (--rule), the contract's sentence where its call quotes none.
        units: None in a package whose subject() contract has exercises. In
            one whose contract has units, every unit, {name: [its kind, the
            name of its library for a function, its own otherwise]}: a test
            is then <unit>_<what> and carries that unit's tag (_UNIT_TAG)
            and no exercise's, every unit has a test, and a library's own
            tests are the whole library's (_LIBRARY_SUFFIXES). makefiles and
            malloc then name units, and exercises is empty.

    Returns:
        The messages, in a stable order; empty when the package is sound.
    """
    problems = []
    fixture = pkg == _FIXTURES or pkg.startswith(_FIXTURES + "/")
    raised = {}
    for k, v in _RAISED.items():
        p, n = k.split(":")
        if p == pkg:
            raised[n] = v
    manual = [k.split(":")[1] for k in _MANUAL if k.split(":")[0] == pkg]
    have = {}
    for n in sorted(tests):
        tags = list(tests[n]["tags"])
        ex = n[:4]
        if n in _MODULE_TESTS:
            # A test of the whole module (c_levels() emits it): no exercise,
            # its one layer, at that layer's level.
            want = [_MODULE_TESTS[n]] + ["lvl_" + x for x in _LEVEL_NAMES[_LAYER_LEVEL[_MODULE_TESTS[n]] - 1:]]
            if sorted([t for t in tags if t in _LAYER_LEVEL or t.startswith("lvl_") or _is_ex(t)]) != sorted(want):
                problems.append(("%s: a test of the whole module is tagged %s and its level, " +
                                 "and with no exercise (tools/defs_module.bzl's _MODULE_TESTS).") %
                                (n, _MODULE_TESTS[n]))
            continue
        if units != None:
            # A PACKAGE OF UNITS: the test's unit is the one its tag names
            # (_test() derives it from the name, as it derives exNN), and its
            # name begins with that unit, so the unit's suite runs it.
            ex = _unit_tag(tags)
            if ex == None or ex not in units or not n.startswith(ex + "_"):
                problems.append(("%s: a test of a package of units is named <unit>_<what>, " +
                                 "after the unit it tests (%s), so that unit's suite runs it " +
                                 "and its name says which layer it is.") % (n, ", ".join(sorted(units))))
                continue
            several = _uniq([t[len(_UNIT_TAG):] for t in tags if t.startswith(_UNIT_TAG)])
            if len(several) > 1:
                problems.append("%s: its unit= tags (%s) are not one unit" % (n, ", ".join(several)))
            exs = [t for t in tags if _is_ex(t)]
            if exs:
                problems.append(("%s: it carries the exercise tag %s in a package of units, " +
                                 "whose suites select unit= tags") % (n, exs[0]))
            have[ex] = True
            if units[ex][0] == "library" and n[len(ex):] not in _LIBRARY_SUFFIXES:
                problems.append(("%s: unit %s is a library (its subject() contract lists its " +
                                 "`functions`), and this test is named after none of them " +
                                 "(<function>_<what>) and is none of the whole library's " +
                                 "(%s<suffix>, as c_library, c_make, c_readme and c_levels " +
                                 "name them: tools/defs_contract.bzl's _LIBRARY_SUFFIXES), so no " +
                                 "function's suite runs it.") % (n, ex, ex))
        else:
            if not _is_ex(ex) or n[4:5] != "_":
                problems.append(("%s: a project's test is named exNN_<what>, after its " +
                                 "exercise, so that exercise's :exNN suite runs it and its " +
                                 "name says which layer it is.") % n)
                continue
            have[ex] = True
            if ex not in tags:
                problems.append(("%s: it has no %s tag, so //%s:%s does not run it. Declare " +
                                 "it with a macro or hand_test(), which derive the tag from " +
                                 "the name.") % (n, ex, pkg, ex))
        if _NO_MANUAL_TAG in tags:
            problems.append("%s: the %s tag is the empty :manual suite's, and no test may carry it." % (n, _NO_MANUAL_TAG))
        layers = [t for t in tags if t in _LAYER_LEVEL]
        if len(layers) != 1:
            problems.append(("%s: it carries %d layer tags (%s); a test is exactly one " +
                             "layer (tools/defs_levels.bzl's _LAYER_LEVEL). hand_test(name, " +
                             "layer, ...) gives it one.") % (n, len(layers), ", ".join(layers) or "none"))
            continue
        layer = layers[0]
        start = 0
        for i in range(len(_LEVEL_NAMES)):
            if "lvl_" + _LEVEL_NAMES[i] in tags:
                start = i + 1
                break
        ladder = ["lvl_" + x for x in _LEVEL_NAMES[start - 1:]] if start else []
        if not start or sorted([t for t in tags if t.startswith("lvl_")]) != sorted(ladder):
            problems.append(("%s: its lvl_* tags (%s) are not a level and every level " +
                             "above it, so the level suites disagree about it. They are " +
                             "derived from its layer by _test(); do not write them.") %
                            (n, ", ".join([t for t in tags if t.startswith("lvl_")]) or "none"))
            continue
        suffix = _suffix_of(n, ex)
        if suffix == None:
            problems.append(("%s: its name ends in no suffix tools/defs_levels.bzl's " +
                             "_SUFFIX_LAYER knows, so nothing says which layer it is. " +
                             "Name it for its layer (exNN_<what>_%s), or add the " +
                             "suffix there and to docs/reference.md's \"Target names\".") % (n, layer))
            continue
        s_layer, s_level = _SUFFIX_LAYER[suffix]
        if s_layer != layer:
            problems.append(("%s: its name ends in %s, which is the %s layer's " +
                             "(_SUFFIX_LAYER), and it is tagged %s. Rename it -- a case " +
                             "name can collide with a longer suffix -- or fix its tag.") %
                            (n, suffix, s_layer, layer))
            continue
        base = s_level or _layer_level(layer, memory_graded)
        if start < base:
            problems.append("%s: it sits at %s, below its %s layer's %s.%s" %
                            (n, _LEVEL_NAMES[start - 1], suffix, _LEVEL_NAMES[base - 1],
                             (" Only a subject() contract that declares memory_graded puts " +
                              "the %s layer at basic, for the whole project.") % layer
                             if layer == _GRADED_LAYER and not s_level and start == 1 else ""))
        elif start != base and raised.get(n) != start:
            problems.append(("%s: it sits at %s, above the %s its name gives it, and " +
                             "tools/defs_levels.bzl's _RAISED does not say so. Add " +
                             "\"%s:%s\": %d there, and its reason to docs/reference.md's " +
                             "\"Targets raised above their layer\".") %
                            (n, _LEVEL_NAMES[start - 1], _LEVEL_NAMES[base - 1], pkg, n, start))
        elif start == base and n in raised:
            problems.append(("%s: _RAISED puts it at %s, and it sits at %s, where its " +
                             "name puts it. Remove the entry, or raise the test.") %
                            (n, _LEVEL_NAMES[raised[n] - 1], _LEVEL_NAMES[start - 1]))
        if n in raised and "--note" in (tests[n].get("args") or []):
            problems.append(("%s: _RAISED raises it, and it passes its runner --note, a " +
                             "second place to say why it sits above its layer. That is " +
                             "docs/reference.md's row, which its runner prints under a " +
                             "red (runner_lib.sh's rl__raised): drop --note.") % n)
        # tools/no_turnin.sh stands in for a test whose turn-in is missing
        # (_test()); its red says what is missing, and no level is its.
        srcs = tests[n].get("srcs")
        if n in raised and srcs != None and srcs != ["//tools:no_turnin.sh"] and (len(srcs) != 1 or srcs[0] not in _LIB_RUNNERS):
            problems.append(("%s: _RAISED raises it, and its runner (%s) does not source " +
                             "tools/runner_lib.sh, so its red would not say why it sits " +
                             "above its layer (runner_lib.sh's rl__raised says it). Run it " +
                             "with a runner that does, or have this one source the library " +
                             "and add it to tools/defs_levels.bzl's _LIB_RUNNERS.") %
                            (n, ", ".join(srcs) or "no srcs"))
        # A MEMORY FINDING IS A KO HERE BECAUSE THE SUBJECT SAYS SO, and its
        # red says which sentence: the contract's on a crash or an invalid
        # access (--access-rule) on every test of the layer, and on a leak
        # (--rule: the contract's, or c_program's own memory_rule) on every
        # one that checks leaks -- and on none that does not, whose red
        # would quote a rule its finding cannot break. A red at basic
        # stating this harness's rule, "not a sentence of your subject's",
        # would contradict the level it sits at.
        if memory_graded and layer == _GRADED_LAYER and srcs != ["//tools:no_turnin.sh"]:
            g_args = tests[n].get("args") or []
            if "--access-rule" not in g_args:
                problems.append(("%s: the subject() contract declares memory_graded, so it " +
                                 "sits at basic, and it quotes no sentence on an invalid access " +
                                 "(--access-rule): its red would call the rule this harness's " +
                                 "own. Hand its runner the contract's sentence, :%s " +
                                 "(_graded_rule()).") % (n, _MEMORY_GRADED_ACCESS))
            if "--no-leak-check" in g_args and "--rule" in g_args:
                problems.append(("%s: it checks no leak (--no-leak-check) and quotes a sentence " +
                                 "on leaks (--rule): its red would name a rule its finding " +
                                 "cannot break. Hand its runner the access sentence alone " +
                                 "(_graded_rule(leaks = False)).") % n)
            elif "--no-leak-check" not in g_args and "--rule" not in g_args:
                problems.append(("%s: the subject() contract declares memory_graded, so it " +
                                 "sits at basic, and it checks leaks quoting no sentence on " +
                                 "them (--rule): its red would call the rule this harness's " +
                                 "own. Hand its runner the contract's sentence, :%s " +
                                 "(_graded_rule()).") % (n, _MEMORY_GRADED))
        if "manual" in tags and not fixture and not [p for p in manual if _glob_match(p, n)]:
            problems.append(("%s: it is manual, so no suite and no /... pattern runs it, " +
                             "and tools/defs_levels.bzl's _MANUAL does not list it. Add a " +
                             "pattern there, and a row to docs/reference.md's \"Manual " +
                             "targets\" saying why it is not run by default.") % n)
    for n in sorted(raised):
        if n not in tests:
            problems.append(("_RAISED names %s:%s, which this package does not declare. " +
                             "Remove the entry.") % (pkg, n))
    for b in sorted(fixtures or {}):
        t = fixtures[b]
        if t == None:
            problems.append(("%s: it links a harness over a student's files and carries no " +
                             "%s tag, so nothing says which test checks the signatures the " +
                             "harness calls. Build it with _student_bin(), which requires " +
                             "`prototype` with a harness.") % (b, _HARNESS_PROTO_TAG))
        elif t != "none" and t not in tests:
            problems.append(("%s: a harness over a student's function names %s as the " +
                             "test of its signature, and this package declares no such " +
                             "test. Declare it (_prototype_test), or say why there is none " +
                             "(prototype = \"none: <the reason>\" at the macro's call).") % (b, t))
    owners = (oracle or {}).get("owners") or {}
    reads = (oracle or {}).get("reads") or {}
    for o in sorted(owners):
        d = owners[o]["dir"]
        pats = owners[o]["owns"]
        if not d or not pats:
            problems.append(("%s: it runs tools/oracle_fixtures.sh, and the audit cannot " +
                             "read its %s, so nothing can tell which of the cases' files " +
                             "it holds to //oracle. Pass --in-dir-of \"$(location " +
                             "tests/exNN/<a file>)\" and one --owns per pattern of files " +
                             "the reference writes, each as its own argument.") %
                            (o, "--in-dir-of $(location FILE)" if not d else "--owns"))
            continue
        for t in sorted(reads):
            for f in reads[t]:
                if not f.startswith(d + "/"):
                    continue
                if not [p for p in pats if _path_glob_match(p, f[len(d) + 1:])]:
                    problems.append(("%s: the case reads %s, in the directory %s holds to " +
                                     "//oracle's records, and none of its --owns patterns " +
                                     "(%s) matches it, so nothing compares it with the " +
                                     "reference and a hand-typed file there drifts unseen. " +
                                     "Have the reference write it (the project's *_fixtures " +
                                     "arm) and give %s an --owns pattern that matches it.") %
                                    (t, f, o, " ".join(pats), o))
    for ex in sorted(exercises):
        if ex not in have:
            problems.append(("%s: the exercise has no test, so its //%s:%s runs nothing. " +
                             "Every exercise the subject() contract lists gets a files " +
                             "layer unless its `files` is None; this one needs a macro.") %
                            (ex, pkg, ex))
    for u in sorted(units or {}):
        if u not in have:
            problems.append(("%s: the unit has no test, so its //%s:%s runs nothing. Every " +
                             "unit of the subject() contract gets a files layer unless its " +
                             "`files` is None, and a function gets the calls that judge one " +
                             "function (c_function(unit = \"<function>\"), ...); this one " +
                             "needs a macro.") % (u, pkg, u))
    read = {}
    for n in tests:
        for f in tests[n].get("layouts") or []:
            read[f] = True
    for f in sorted(layouts or []):
        if f not in read:
            problems.append(("%s: no test of this package reads it (no exNN_prototype or " +
                             "exNN_layout_prototype passes it with --layout or " +
                             "--layout-tag), so the structure it holds is checked by " +
                             "nothing. c_function reads tests/layout/<header> and " +
                             "tests/layout/tag/<header> for an exercise whose contract's " +
                             "`files` names <header>; no other macro reads the folder yet. " +
                             "Name the header in that exercise's `files`, or have the macro " +
                             "that builds it pass _layouts() to _prototype_test(), with a " +
                             "toy exercise in tools/tests/macro_fixtures proving it.") % f)

    # THE TESTS THAT WAIT FOR AN OUTPUT ARE NAMED BY IT: every test with a
    # gate (_GATE_FLAGS: the program it gates on, the file that program must
    # print, or a survive case's --gate-label) resolves to the one output test
    # it waits for, and that test hands its runner their list (--waiting,
    # _waiting_args), or its red log says nothing of the tests that show
    # PASSED beside it while they wait (_WAITING).
    problems += _waiting_problems(tests)

    # A SUITE ASKED FOR BY NAME RUNS EVERY TEST OF THAT NAME.
    problems += _suite_problems(tests, suites or {})

    # A HINT FILE NO TEST PRINTS. Read from the args, as a runner is handed
    # it: in a test's data alone it is staged and never shown.
    handed = {}
    for n in tests:
        for a in tests[n].get("args") or []:
            if a.startswith("$(") and a.endswith(")") and " " in a:
                f = a[:-1].split(" ")[-1]
                handed[f.split(":")[-1]] = True
    for f in sorted(clues or []):
        if f not in handed:
            problems.append(("%s: no test of this package hands it to a runner (no " +
                             "\"$(location %s)\" among any test's args), so its hints " +
                             "are shown to nobody. Pass it where the exercise is judged " +
                             "-- clues = \"%s\" on its macro (c_function, c_program, " +
                             "c_make, ...) -- or delete it.") % (f, f, f.split("/")[-1]))
    problems += _keyed_clue_problems(tests, clues or [])

    # A MAKEFILE THE CONTRACT ASKS FOR IS BUILT BY c_make. "recipe and
    # wildcards are decided at every c_make" binds only the c_make calls that
    # exist: a Makefile project written with c_program(makefile = True) and
    # no c_make got no rules, recipe, wildcards or relink check at all, and
    # nothing said so (finding 097's class, through an omission).
    for ex in sorted(makefiles or []):
        if ex + "_build" not in tests:
            problems.append(("%s: the subject() contract has it turn in a Makefile, and " +
                             "no %s_build judges it: no c_make(%s) here, so " +
                             "nothing checks its rules, its compile commands, its " +
                             "wildcards or a relink. Call c_make for it, deciding each " +
                             "check it runs.") % (ex, ex, _call(_key(ex))))

    # ...and the program it builds has one name. c_program's `name` and
    # c_make's `artifact` were two words for one program, and nothing
    # compared them: given two, the files layer refused both in the turn-in
    # as build products (_built_programs), and the .gitignore check read the
    # artifact alone.
    for b in sorted(programs or {}):
        ex = b[:-len("_bin")] if b.endswith("_bin") else ""
        if not (_is_ex(ex) or ex in (units or {})) or ex + "_build" not in tests:
            continue
        built = _opt_value(tests[ex + "_build"].get("args") or [], "--artifact")
        if built and built != programs[b]:
            problems.append(("%s: c_program(%s) names its program \"%s\", and " +
                             "c_make(%s) builds \"%s\" (its artifact): one " +
                             "program under two names, each refused in the turn-in as a " +
                             "build product, and one alone kept out of commits by the " +
                             ".gitignore check. Give both the name the subject gives " +
                             "the program.") % (b, _call(_key(ex)), programs[b], _call(_key(ex)), built))

    # EVERY CORPUS REPLAY HAS ITS MEMORY TWINS (finding 113).
    problems.extend(_corpus_memory_problems(tests, malloc or []))

    # ...and an argument corpus's ASan twin runs the guarded build (071).
    problems.extend(_argv_guard_replay_problems(tests, fixtures or {}))

    # ...and no memcheck layer runs a program whose malloc fills its blocks.
    problems.extend(_diffio_memcheck_problems(tests, diffio or []))

    # ...and a corpus under memcheck quotes the rule its exercise's arms do.
    problems.extend(_memory_rule_reach_problems(tests))

    # EVERY CORPUS GATE IS ONE OF THE EXERCISE'S OWN OUTPUT TESTS.
    problems.extend(_gate_problems(tests))

    # ...and so is every gate that replays the case its layer runs.
    problems.extend(_case_gate_problems(tests))

    # ...and every measuring layer's gate compares as its output test does.
    problems.extend(_measure_gate_problems(tests))

    # ...and a gate whose runner can name it in its SKIP line does.
    problems.extend(_gate_label_problems(tests))

    # EVERY DIFF LAYER WAITS for its exercise's output test, or says why not.
    problems.extend(_ungated_diff_problems(tests))
    return problems

def _argv_guard_replay_problems(tests, fixtures):
    """An argument corpus replayed under ASan off the guarded build, as messages.

    A program whose input is its arguments reads them where the kernel put
    them, which the sanitizer does not watch: a comparison that runs past an
    argument's terminator reads the next one's bytes, and the ASan build says
    nothing. c_argv_table builds the program a second way for that,
    :exNN_argvguard_bin_asan (tools/argv_guard_main.c), each argument in a
    heap block of exactly its size. C 06 ex03's corpus twins ran the
    unguarded build and passed such a comparison, their verdict silent about
    what they could not see (finding 071, the mutation run of 2026-10-03).
    So every argv_check.sh replay under --sanitized, in an exercise that has
    a guarded build, runs it (corpus_memory's `asan_bin`, which then passes
    --guarded-argv). A program's corpus runners -- Rush 01's sweep, Rush 02,
    C 10's files, BSQ's maps by name -- have no guarded build to run, and
    say instead what the sanitizer could not see of the arguments
    (tools/runner_lib.sh, rl_mem_argv_note).

    Args:
        tests: _audit_problems' tests.
        fixtures: _audit_problems' fixtures: every student_binary with a
            harness, the guarded builds among them.

    Returns:
        The messages, in a stable order.
    """
    problems = []
    for n in sorted(tests):
        t = tests[n]
        srcs = t.get("srcs") or []
        args = t.get("args") or []
        if not srcs or not srcs[0].endswith(":argv_check.sh") or "--sanitized" not in args:
            continue
        ex = _unit_of(n, t)
        if ex == None:
            # Named after no exercise: the naming audit refuses it.
            continue
        guard = ex + _ARGV_GUARD_SUFFIX
        if guard not in fixtures:
            continue
        b = _opt_value(args, "--bin")
        if b == "$(location :%s)" % guard and "--guarded-argv" in args:
            continue
        problems.append(("%s: it replays an argument corpus under ASan on %s, and %s " +
                         "has a guarded build, :%s, where each argument sits in a heap " +
                         "block of its own: on any other build a read past an argument's " +
                         "end is not seen (finding 071). Pass corpus_memory(asan_bin = " +
                         "\":%s\"), which tells argv_check.sh so (--guarded-argv).") %
                        (n, b or "no --bin", ex, guard, guard))
    return problems

def _diffio_memcheck_problems(tests, diffio):
    """A memcheck layer handed a program linking //tools:diffio, as messages.

    Every program linking //tools:diffio has malloc wrapped so that each
    block starts holding 0xa5 (tools/dirty_malloc.c), so a field a function
    never writes does not read as zero to a value diff (finding 136). memcheck
    tracks which bytes were WRITTEN, and the fill writes them: a byte the
    student's code never set reads as defined, and an uninitialised read in
    that program goes unseen. No layer runs one under memcheck today -- the
    valgrind arms run the exercise's own _bin, or a _vgbin -- and nothing
    said that none may (the wave 6 review). So a test whose runner is
    valgrind_test.sh, or that replays a corpus under --valgrind, is refused
    when a program it is handed ($(location :X) among its args) links the
    library. The program memcheck runs is the one after --bin, named by its
    $(location) in either form, :X or //pkg:X (_loc_of); a gate's program
    (--gate-bin) runs plain, before it, and may be any build.

    Args:
        tests: _audit_problems' tests.
        diffio: the student_binary rules linking //tools:diffio.

    Returns:
        The messages, in a stable order.
    """
    problems = []
    for n in sorted(tests):
        t = tests[n]
        srcs = t.get("srcs") or []
        args = t.get("args") or []
        if not (srcs and srcs[0] == "//tools:valgrind_test.sh") and "--valgrind" not in args:
            continue
        for a in _opt_values(args, "--bin"):
            b = _loc_of(a)
            if b in diffio:
                problems.append(("%s: it runs :%s under memcheck, and :%s links " +
                                 "//tools:diffio, whose malloc fills every block it hands " +
                                 "out (tools/dirty_malloc.c): memcheck reads a filled byte " +
                                 "as written, so an uninitialised read in the student's " +
                                 "code is not seen. Hand it a build without the library: " +
                                 "the exercise's _bin, or a _vgbin of its own.") % (n, b, b))
    return problems

def _memory_rule_reach_problems(tests):
    """A corpus under memcheck that quotes no rule its exercise's arms quote, as messages.

    c_program's memory_rule is the subject's own sentence about memory (Rush
    02's "Any memory allocated on the heap ... must be freed correctly"),
    and each fixed case's _valgrind arm quotes it when it fails (--rule).
    The exercise's memcheck sample of a corpus quoted none, and a red there
    would state this harness's rule as "not a sentence of your subject's"
    under the one subject that has one (V82). corpus_memory() now hands it
    over, read from the file c_program writes (:exNN_memory_rule); one
    called before that c_program finds none. So every replay of a corpus
    under --valgrind is held to the --rule its exercise's valgrind arms pass.

    Args:
        tests: _audit_problems' tests.

    Returns:
        The messages, in a stable order.
    """
    quoted = {}
    for n in sorted(tests):
        t = tests[n]
        srcs = t.get("srcs") or []
        r = _opt_value(t.get("args") or [], "--rule")
        ex = _unit_of(n, t)
        if ex != None and srcs and srcs[0] == "//tools:valgrind_test.sh" and r != None and ex not in quoted:
            quoted[ex] = [n, r]
    problems = []
    for n in sorted(tests):
        t = tests[n]
        srcs = t.get("srcs") or []
        args = t.get("args") or []
        ex = _unit_of(n, t)
        if not srcs or srcs[0] not in _CORPUS_RUNNERS or "--valgrind" not in args or ex not in quoted:
            continue
        arm, want = quoted[ex]
        got = _opt_value(args, "--rule")
        if got == want:
            continue
        problems.append(("%s: it replays a corpus under memcheck quoting %s, and %s quotes the " +
                         "subject's own sentence (--rule %s): a red here would state this " +
                         "harness's rule as not the subject's. corpus_memory() hands the " +
                         "sentence over when it comes after the c_program that declares " +
                         "it (memory_rule).") %
                        (n, "--rule " + got if got else "no rule", arm, want))
    return problems

def _keyed_clue_problems(tests, clues):
    """An exercise whose hints are keyed to its cases, with a hint file per case beside them.

    ONE KEYED clues.tsv PER EXERCISE (ruling R7). A test
    that is a case of its own -- a c_program case, a corpus runner's target --
    hands its runner its name (--case), and a row of clues.tsv keyed to that
    name fires there and nowhere else (tools/runner_lib.sh, rl_clues). The
    other way, a clues_<x>.tsv per case, was the older one, and by wave 4
    both were in use: Rush 02 keyed its rows, while C 10, C 11 ex05, BSQ,
    Rush 01 and Reloaded ex27 split theirs over twenty files, so where a
    program's hints were depended on how the module was written, and a row
    could not name the several cases it is about. So in an exercise whose
    tests pass --case:
      - a clues_<x>.tsv under its tests/ folder is refused: fold its rows
        into clues.tsv, keyed to the cases that named it;
      - every test that hands its clues.tsv to a runner passes --case too:
        a runner given no case prints every row -- rl_clues with nothing
        failed -- so a sweep would show the rows keyed to other cases.
    An exercise none of whose tests is keyed (a function's table keys its
    rows by their labels) is not held to it.

    In a contract of units every unit is held to it in its own folder, a
    library's function too, which is a unit of its own: its tests are the
    ones its tag names (_UNIT_TAG), and its hints are
    tests/<function>/clues.tsv.

    Args:
        tests: _audit_problems()' tests.
        clues: every clues*.tsv under the package's tests/.

    Returns:
        The messages, in a stable order; empty when nothing breaks the rule.
    """
    keyed = {}
    for n in sorted(tests):
        u = _unit_of(n, tests[n])
        if u != None and "--case" in _opts(tests[n].get("args") or []):
            keyed.setdefault(u, []).append(n)
    problems = []
    for f in sorted(clues):
        parts = f.split("/")
        unit = parts[1] if len(parts) == 3 else None
        if unit in keyed and parts[-1] != "clues.tsv":
            named = keyed[unit]
            shown = ([n for n in named if n.endswith("_output")] + named)[0]
            problems.append(("%s: %s keys its hints to its cases (--case, as %s does), " +
                             "so they live in one tests/%s/clues.tsv: fold these rows " +
                             "into it, each keyed to the cases that named this file " +
                             "(<hint><TAB><case>...), and delete it.") %
                            (f, unit, shown, unit))
    for n in sorted(tests):
        unit = _unit_of(n, tests[n])
        if unit not in keyed or n in keyed[unit]:
            continue
        args = tests[n].get("args") or []
        hands = [a for a in args if a.endswith("tests/%s/clues.tsv)" % unit)]
        if hands:
            problems.append(("%s: it hands %s's keyed clues.tsv to its runner without " +
                             "--case, so every row of it is shown, the rows keyed to " +
                             "other cases among them. Pass --case and the name its rows " +
                             "are keyed to (its target's name after %s_).") %
                            (n, unit, unit))
    return problems

def _unit_of(n, t):
    """What test `n` (its _audit_problems() entry `t`) is part of; None if nothing says.

    The unit its unit tag names (_UNIT_TAG), a library's function being a
    unit of its own; else exNN, where the name begins with one.
    """
    u = _unit_tag(t.get("tags") or [])
    if u != None:
        return u
    return n[:4] if _is_ex(n[:4]) else None

def _gate_run(args):
    """What a corpus runner's gate runs, from its arguments; None where it has no gate.

    {"bin", "expected", "words": the run's arguments as written, "argv_file":
    a file holding them, or None, "scenarios": an argument table, or None,
    "differ": the script --gate-differ names, which judges the run}.
    A runner takes the run's words as --gate-arg, each one word
    (bsq_check.sh, rush01_check.sh, file_check.sh); or a one-line file as
    --gate-arg-file (rush01_check.sh); or, for a dictionary program, its
    --dict and then --gate-number (rush02_check.sh); or, where the output
    test is an argument table (c_argv_table's, argv_table.sh), the table's
    rows as --gate-scenarios (argv_check.sh).
    """
    if not _opt_values(args, "--gate-differ"):
        return None
    words = _opt_values(args, "--gate-arg")
    number = _opt_values(args, "--gate-number")
    if number:
        words = _opt_values(args, "--dict")[:1] + number[:1]
    differ = _opt_value(args, "--gate-differ")
    return {
        "bin": _opt_value(args, "--gate-bin"),
        "expected": _opt_value(args, "--gate-expected"),
        "words": words,
        "argv_file": _opt_value(args, "--gate-arg-file"),
        "scenarios": _opt_value(args, "--gate-scenarios"),
        "differ": _loc_of(differ) or differ,
    }

def _gate_problems(tests):
    """A corpus replay whose gate runs its program some other way than any output test does.

    A corpus runner SKIPs while its gate -- the program run on the subject's
    example, through tools/diff_output.sh -- is red, so the gate has to run
    the program exactly as that example's own output test does. BSQ's ran it
    with no argument at all, while the example's test hands it the map: on a
    correct program the gate read an empty standard input, printed "map
    error", and every BSQ corpus target SKIPped on every correct tree, green,
    wherever NO_SKIP=1 was not set. So each gate is matched here with a
    diff_output.sh test of the package: the same program, the same expected
    file, the same arguments (or argument file), and no standard input. Or,
    for a gate on an argument table, an argv_table.sh test of the package
    comparing the same program's table, row for row (_table_run). The
    script that judges the gate (--gate-differ) is the matched test's own:
    a gate judged by argv_table.sh on the run a diff_output.sh test makes,
    or the reverse, compares another thing than that test does (V294).
    """
    problems = []
    cases = []
    named = []
    for n in sorted(tests):
        srcs = tests[n].get("srcs") or []
        run = None
        if srcs and srcs[0] == "//tools:diff_output.sh":
            run = _output_run(tests[n].get("args") or [])
        elif srcs and srcs[0] == "//tools:argv_table.sh":
            run = _table_run(tests[n].get("args") or [])
        if run != None:
            run["differ"] = srcs[0].split(":")[-1]
            cases.append(run)
            named.append((n, run))
    unmatched = {}
    for n in sorted(tests):
        srcs = tests[n].get("srcs") or []
        if not srcs or srcs[0] not in _CORPUS_RUNNERS:
            continue
        gate = _gate_run(tests[n].get("args") or [])
        if gate == None or gate in cases:
            continue
        if not gate["bin"] or not gate["expected"]:
            # A gate given in part runs nothing to match: every corpus runner
            # that takes a gate is one of _GATE_LABEL_RUNNERS, whose audit
            # (_gate_label_problems) or the waiting audit names it.
            continue
        other = [(c, r["differ"]) for c, r in named if dict(r, differ = gate["differ"]) == gate]
        if other:
            problems.append(_differ_problem(n, gate["differ"], other[0][0], other[0][1]))
            continue
        how = " ".join(gate["words"]) or "no argument"
        if gate["argv_file"]:
            how = "the arguments in " + gate["argv_file"]
        if gate["scenarios"]:
            how = "each row of " + gate["scenarios"]
        what = "%s with %s against %s" % (gate["bin"], how, gate["expected"])
        unmatched.setdefault(what, []).append(n)
    for what in sorted(unmatched):
        problems.append(("%s: the gate runs %s, and no output test of this package runs " +
                         "the program that way, so the gate can be red on a program whose " +
                         "example passes, and these layers would SKIP on every correct " +
                         "program. Pass the example case's own arguments: --gate-arg once " +
                         "per word (tools/runner_lib.sh, rl_gate), or an argument table's own " +
                         "rows as --gate-scenarios; output_gate(<that test>) reads either off " +
                         "it.") %
                        (", ".join(unmatched[what]), what))
    return problems

def _differ_problem(n, differ, case, judge):
    """Test `n`'s gate is judged by `differ` on the run test `case` makes, which `judge` judges."""
    return (("%s: the gate hands its run to %s, and the output test that runs the program " +
             "that way (%s) is judged by %s, a script that does not compare that run: " +
             "argv_table.sh refuses diff_output.sh's run and diff_output.sh refuses " +
             "argv_table.sh's (exit 2), and on that exit rl_gate runs the layer anyway, so " +
             "it never waits for that test to pass. Hand --gate-differ that test's own " +
             "script, as output_gate(<that test>) writes it for a corpus replay.") %
            (n, differ, case, judge))

# THE RUNNERS WHOSE GATE REPLAYS THE CASE THEY RUN: the gate is handed the
# words after "--" and, by the runner itself, its --argv-file, --run-as and
# --cwd-file; --gate-stdin, --gate-expected and the rest of the --gate-*
# options say how it is fed and compared. c_levels()' audit holds each such
# gate to an output test of the package (_case_gate_problems). One test of
# them is read as a gate written out whole (_whole_gate_run): a survive
# case's valgrind arm or allocfail sweep (--survive), which waits for
# another case.
_CASE_GATE_RUNNERS = [
    "//tools:allocfail_check.sh",
    "//tools:valgrind_test.sh",
]

# THE RUNNERS WHOSE GATE IS WRITTEN OUT WHOLE in its --gate-* options, and
# handed nothing of the run they gate: run_check.sh (a rush variant's own
# main.c, which waits for the variant's table) and diff_output.sh (its
# defense case, which waits so too through --gate-bin, and a survive case,
# which waits for its exercise's case on its own program). c_levels()' audit
# holds each such gate to an output test of the package the same way
# (_case_gate_problems): program, expected file, stream, comparison,
# standard input, --labeled and the words of --gate-arg.
_WHOLE_GATE_RUNNERS = [
    "//tools:diff_output.sh",
    "//tools:run_check.sh",
]

def _whole_gate_run(args):
    """The run a gate of _WHOLE_GATE_RUNNERS makes, in _compared_run()'s fields; None where none is given.

    Each field is read from the --gate-* options alone: the runner hands its
    gate no argument file, no run folder and none of the words after its
    own "--". Without --gate-bin, diff_output.sh's gate runs the case's own
    program (--bin): a survive case's, which waits for its exercise's case.
    Without --gate-differ, it is judged as diff_output.sh judges a case.
    """
    opts = _opts(args)
    if "--gate-expected" not in opts:
        return None
    differ = _opt_value(opts, "--gate-differ")
    return {
        "argv_file": None,
        "bin": _opt_value(opts, "--gate-bin") or _opt_value(opts, "--bin"),
        "cwd_files": [],
        "expected": _opt_value(opts, "--gate-expected"),
        "expected_alt": [],
        "labeled": "--gate-labeled" in opts,
        "run_as": None,
        "sanitize": "--gate-sanitize" in opts,
        "stdin": _opt_value(opts, "--gate-stdin"),
        "stream": _opt_value(opts, "--gate-stream"),
        "words": _opt_values(opts, "--gate-arg"),
        "differ": (_loc_of(differ) or differ) if "--gate-differ" in opts else "diff_output.sh",
    }

def _case_gate_problems(tests):
    """A gate that replays a case some other way than any output test of the package does.

    The program arms of c_program -- valgrind, allocfail -- SKIP while their
    gate, the case run through tools/diff_output.sh, is red; so the gate has
    to be the case's own output test. Rush 02's allocfail sweep forwarded
    stdin alone: its case runs the program beside numbers.dict (--run-as,
    --cwd-file), the gate ran it from a folder with no dictionary, and on
    every correct program the gate was red and the sweep SKIPped, green. Each
    gate of _CASE_GATE_RUNNERS is matched here with a diff_output.sh test: the
    same program, expected file(s), stream, comparison, standard input,
    arguments, argument file and run folder. So is each gate of
    _WHOLE_GATE_RUNNERS (_whole_gate_run): Rush 00's _main and _defense wait
    for their variant's table, and a gate there fed another file than the
    table's would SKIP on every correct tree.
    """
    outputs = []
    named = []
    for n in sorted(tests):
        srcs = tests[n].get("srcs") or []
        if srcs and srcs[0] == "//tools:diff_output.sh":
            run = _compared_run(tests[n].get("args") or [], False)
            if run != None:
                outputs.append(run)
                named.append((n, run))
    problems = []
    unmatched = {}
    for n in sorted(tests):
        srcs = tests[n].get("srcs") or []
        args = tests[n].get("args") or []
        if srcs and srcs[0] in _CASE_GATE_RUNNERS and "--survive" in _opts(args):
            # A survive case's valgrind arm or allocfail sweep: its gate is
            # another case, written out whole (--survive), an option.
            gate = _whole_gate_run(args)
        elif srcs and srcs[0] in _CASE_GATE_RUNNERS:
            gate = _compared_run(tests[n].get("args") or [], True)
        elif srcs and srcs[0] in _WHOLE_GATE_RUNNERS:
            gate = _whole_gate_run(tests[n].get("args") or [])
        else:
            continue
        if gate == None or gate in outputs:
            continue
        other = [c for c, r in named if dict(r, differ = gate["differ"]) == gate]
        if other:
            problems.append(_differ_problem(n, gate["differ"], other[0], "diff_output.sh"))
            continue
        how = ["on \"%s\"" % " ".join(gate["words"]) if gate["words"] else "with no argument"]
        if gate["argv_file"]:
            how.append("then the arguments in " + gate["argv_file"])
        if gate["stdin"]:
            how.append("standard input from " + gate["stdin"])
        if gate["run_as"]:
            how.append("as ./%s from a folder holding %s" % (gate["run_as"], ", ".join(gate["cwd_files"]) or "only it"))
        else:
            how.append("from the test's own folder")
        what = "%s %s, against %s%s" % (gate["bin"], ", ".join(how), gate["expected"], " (--labeled)" if gate["labeled"] else "")
        unmatched.setdefault(what, []).append(n)
    return problems + [
        ("%s: the gate runs %s, and no output test of this package runs the program " +
         "that way, so the gate can be red on a program whose case passes, and the " +
         "layer would SKIP on every correct program. Hand the runner the case's run " +
         "flags (_case_run), which it forwards to its gate, and --gate-stdin for its " +
         "standard input; a gate written out whole (run_check.sh, diff_output.sh, " +
         "valgrind_test.sh --survive) takes all of that test's run in its --gate-* " +
         "options.") %
        (", ".join(unmatched[what]), what)
        for what in sorted(unmatched)
    ]

# THE RUNNERS THAT NAME THEIR GATE'S OUTPUT TEST IN THEIR SKIP LINE, given
# --gate-label (RL_GATE_NAME, tools/runner_lib.sh; the others' own echo).
# Without it the line falls back to "this exercise's own output fixture",
# which names no test. The macros pass it on every gate they write; a
# hand-written BSQ or rush target that lost the pair still built (its
# waiting list still found it through `waits`), and its SKIP named nothing.
# allocfail_check, perf_test, ref_compare and rust_diff took no --gate-label
# at all, and said "this exercise's own output fixture" on every exercise
# (V169). tools/conventions.sh holds this list to the runners whose option
# loop takes both, and every runner that takes --gate-differ to taking
# --gate-label. diff_output.sh takes --gate-label too, but runs its own gate
# and so takes no --gate-differ: its gates are --gate-expected (a survive
# case's, and a defense case's beside --gate-bin), which the audit below
# holds to a label as well.
_GATE_LABEL_RUNNERS = [
    "//tools:allocfail_check.sh",
    "//tools:argv_check.sh",
    "//tools:asan_run.sh",
    "//tools:bsq_check.sh",
    "//tools:cycles_check.sh",
    "//tools:file_check.sh",
    "//tools:method_check.sh",
    "//tools:perf_test.sh",
    "//tools:ref_compare.sh",
    "//tools:run_check.sh",
    "//tools:rush01_check.sh",
    "//tools:rush02_check.sh",
    "//tools:rust_diff.sh",
    "//tools:valgrind_test.sh",
]

# THE MEASURING RUNNERS: the rest of _GATE_LABEL_RUNNERS (asan_run,
# cycles_check, method_check, perf_test, ref_compare, rust_diff). Their gate
# is the exercise's output fixture run through diff_output.sh, and it is
# held to the output test it waits for by _measure_gate_problems.
_MEASURE_GATE_RUNNERS = [
    r
    for r in _GATE_LABEL_RUNNERS
    if r not in _CASE_GATE_RUNNERS and r not in _WHOLE_GATE_RUNNERS and r not in _CORPUS_RUNNERS
]

# How a gate compares, beside the output test's own option for the same:
# two flags, and the file fed on standard input -- which a runner of
# _GATE_NO_INPUT_RUNNERS cannot feed its gate, and the waiting audit
# refuses in its own words (tools/defs_test.bzl, _waiting_problems).
_MEASURE_GATE_FLAGS = [("--sanitize", "--gate-sanitize"), ("--labeled", "--gate-labeled")]
_MEASURE_GATE_FILES = [("--stdin", "--gate-stdin")]

def _measure_gate_problems(tests):
    """A gate of one of _MEASURE_GATE_RUNNERS that compares otherwise than its output test, as messages.

    The gate runs the program on the output fixture and compares the run
    as the output test it waits for (_waits_for) does: with its --sanitize,
    its --labeled and its standard input, each passed as the --gate-* option
    of the same name (no standard input for _GATE_NO_INPUT_RUNNERS, which
    the waiting audit refuses over a fed output test). A gate on a hex
    dump's output test without --gate-sanitize read every right answer as
    red, and its layer SKIPped, green, for ever (F0272). _waits_for has
    already matched the program and the file; a gate it resolves to no
    output test is the waiting audit's.
    """
    outputs = _waiting_outputs(tests)
    problems = []
    for n in sorted(tests):
        srcs = tests[n].get("srcs") or []
        if not srcs or srcs[0] not in _MEASURE_GATE_RUNNERS:
            continue
        args = tests[n].get("args") or []
        if "--gate-differ" not in args:
            continue
        o, _ = _waits_for(n, tests, outputs)
        if not o:
            continue
        mine = _opts(args)
        theirs = _opts(tests[o].get("args") or [])
        off = [(own, gate) for own, gate in _MEASURE_GATE_FLAGS if (own in theirs) != (gate in mine)]
        files = [] if srcs[0] in _GATE_NO_INPUT_RUNNERS else _MEASURE_GATE_FILES
        off += [(own, gate) for own, gate in files if _opt_values(theirs, own) != _opt_values(mine, gate)]
        if off:
            problems.append(("%s: its gate does not run the program as %s, the output test it " +
                             "waits for, does (%s): on a correct program the gate can be red " +
                             "where that test is green, and the layer would SKIP on every " +
                             "correct program. Give the gate that test's run: %s.") %
                            (n, o, ", ".join([own for own, _ in off]), ", ".join(["%s for %s" % (g, own) for own, g in off])))
    return problems

def _gate_label_problems(tests):
    """A gated test of one of _GATE_LABEL_RUNNERS, or of diff_output.sh, that passes no --gate-label, as messages.

    Grouped by the output test the gate resolves to (_waits_for), which the
    message names as the fix. Where none resolves and the waiting audit says
    why, that audit names the test, and a second message here would only name
    it again with no test to pass. Where none resolves and it says nothing,
    the gate is --gate-differ alone, which no other audit names and the
    runner refuses only when the test runs: that is said here.

    A diff_output.sh test is gated by --gate-expected, an option before its
    "--" (after it, a word the program is handed): it runs its own gate,
    with no --gate-differ, and Rush 00's _defense and every survive case's
    output test were held to no label (V169).
    """
    outputs = _waiting_outputs(tests)
    missing = {}
    partial = []
    for n in sorted(tests):
        srcs = tests[n].get("srcs") or []
        args = tests[n].get("args") or []
        if srcs and srcs[0] == "//tools:diff_output.sh":
            opts = _opts(args)
            if "--gate-expected" not in opts or "--gate-label" in opts:
                continue
        elif not srcs or srcs[0] not in _GATE_LABEL_RUNNERS:
            continue
        elif "--gate-differ" not in args or "--gate-label" in args:
            continue
        o, why = _waits_for(n, tests, outputs)
        if o:
            missing.setdefault(o, []).append(n)
        elif not why:
            partial.append(n)
    return [
        ("%s: each one's runner takes --gate-label and none is passed, so the SKIP " +
         "line each prints while its gate is red names no test. Pass --gate-label %s " +
         "beside the gate's other options (--gate-differ, or diff_output.sh's " +
         "--gate-expected; in the shared gate list, if they share one).") %
        (", ".join(missing[o]), o)
        for o in sorted(missing)
    ] + [
        ("%s: its gate is --gate-differ alone, with no program (--gate-bin) and no " +
         "expected file (--gate-expected) for it to run, which its runner refuses " +
         "(exit 2) when the test runs. Pass the whole gate, and --gate-label with " +
         "the output test it waits for.") % n
        for n in partial
    ]
_DIFF_LAYERS = ["diff", "diff_asan"]

def _ungated_diff_problems(tests):
    """A non-manual diff or diff_asan test that waits for nothing with no reason, as messages."""
    ungated = []
    for n in sorted(tests):
        tags = tests[n].get("tags") or []
        args = tests[n].get("args") or []
        if "manual" in tags or not [x for x in _DIFF_LAYERS if x in tags]:
            continue
        if _NO_GATE_TAG in tags or [f for f in _GATE_FLAGS if f in args]:
            continue
        ungated.append(n)
    if not ungated:
        return []
    return [("%s: each one is a diff or diff_asan test that waits for nothing (no " +
             "--gate-bin, --gate-expected or --gate-label) and says no reason why, so " +
             "on a stub it replays its inputs and reports the output test's red again, " +
             "a red docs/reference.md (\"Which layers wait for which\") says these " +
             "layers never show. Gate it on its exercise's own output test, the one a " +
             "stub fails (output_gate(<that test>)); or, where waiting would hide a " +
             "fault that test cannot show, have the macro that emits it set " +
             "_NO_GATE_TAG with the reason written beside it.") % ", ".join(ungated)]

def _corpus_memory_problems(tests, malloc):
    """A corpus replayed on the plain build only, as messages (finding 113).

    Every generated corpus -- Rush 01's sweep, Rush 02's dictionaries, BSQ's
    maps, C 06's arguments, C 10's files -- ran on the plain build, while the
    memory layers ran each fixed case alone; so a path only generated input
    reaches (a search that ends with nothing, a long number, a map past nine
    rows, a file past one buffer) was never memory-checked. The next project's
    corpus would have been the same, so the rule is the package's: EACH plain
    replay through one of _CORPUS_RUNNERS needs a replay of the same corpus --
    its arguments less _CORPUS_RUN_OPTS, so the generator, its size and the
    transport (argv, stdin, several maps per run) all count -- on the ASan
    build (--sanitized, on :exNN_bin_asan) and, where the subject allows
    malloc (_memcheck_allowed), a sample of it under memcheck (--valgrind).
    corpus_memory() emits both. Keyed by exercise and runner alone, one twin
    stood in for every corpus that runner replayed, and the audit passed BSQ
    with its stdin and multi-map corpora checked nowhere.

    A twin that replays LESS on purpose -- Rush 01's leaves the bonus sizes,
    slow under a checker, to the plain sweep -- names the replays it stands in
    for in corpus_memory()'s `covers`, with the reason; one that leaves out
    memcheck says why in `no_valgrind`. Both arrive here as tags of the twin
    (_COVERS_TAG, _NO_VALGRIND_TAG), which hand_test() refuses to set.
    """
    problems = []
    plain = {}
    twins = {}
    waived = {}
    covers = {}
    for n in sorted(tests):
        srcs = tests[n].get("srcs") or []
        tags = tests[n].get("tags") or []

        # The exercise, or in a contract of units the unit its tag names.
        u = _unit_of(n, tests[n])
        if not srcs or srcs[0] not in _CORPUS_RUNNERS or u == None:
            continue
        args = tests[n].get("args") or []
        key = " ".join([u, srcs[0]] + _corpus_of(args))
        mode = "sanitized" if "--sanitized" in args else ("valgrind" if "--valgrind" in args else None)
        if mode == None:
            plain[n] = key
            continue
        if mode == "sanitized" and not [a for a in args if a.endswith("_bin_asan)")]:
            problems.append(("%s: it replays its corpus with --sanitized on a program " +
                             "that is not an ASan build (:%s_bin_asan), so no " +
                             "sanitizer is there to report. corpus_memory() wires it.") %
                            (n, u))
        twins[key + " " + mode] = n
        if _NO_VALGRIND_TAG in tags:
            waived[key] = n
        for t in tags:
            if t.startswith(_COVERS_TAG):
                c = covers.setdefault(t[len(_COVERS_TAG):], {})
                c[mode] = n
                c["key"] = key
                if _NO_VALGRIND_TAG in tags:
                    c["no_valgrind"] = n
    for c in sorted(covers):
        by = covers[c].get("sanitized") or covers[c].get("valgrind")
        if c not in plain:
            problems.append(("%s: its corpus_memory() covers %s, which is no plain replay " +
                             "of a corpus in this package. Name the replay it stands in " +
                             "for, or drop the entry.") % (by, c))
        elif plain[c].split(" ")[0:2] != covers[c]["key"].split(" ")[0:2]:
            problems.append(("%s: its corpus_memory() covers %s, a replay of another " +
                             "exercise or through another runner, whose memory it cannot " +
                             "speak for.") % (by, c))
        elif plain[c] + " sanitized" in twins:
            problems.append(("%s: its corpus_memory() covers %s, whose own corpus has a " +
                             "twin already (%s). Drop the entry: a reason nobody needs is " +
                             "one nobody rereads.") % (by, c, twins[plain[c] + " sanitized"]))
    for n in sorted(plain):
        key = plain[n]
        ex, runner = key.split(" ")[0:2]
        corpus = " ".join(key.split(" ")[2:]) or "its runner's default corpus"
        c = covers.get(n, {})
        if key + " sanitized" not in twins and "sanitized" not in c:
            problems.append(("%s: it replays a generated corpus (%s) through %s on the " +
                             "plain build, and no test replays that corpus under ASan/UBSan, " +
                             "so a path only it reaches is never memory-checked. Add " +
                             "corpus_memory() with the same corpus arguments beside it " +
                             "(tools/defs.bzl); where a twin replays less on purpose, name " +
                             "this replay in that corpus_memory()'s `covers`, with why.") %
                            (n, corpus, runner))
        if (ex in malloc and key + " valgrind" not in twins and key not in waived and
            "valgrind" not in c and "no_valgrind" not in c):
            problems.append(("%s: its subject allows malloc, and no test replays its " +
                             "corpus (%s) under memcheck, so a leak only that corpus reaches " +
                             "is never seen. corpus_memory() emits the arm from the subject() " +
                             "contract, or says why not in `no_valgrind`.") % (n, corpus))
    return problems

def _rules_audit(pkg, rules, exercises, layouts = None, makefiles = None, malloc = None, clues = None, memory_graded = False, units = None):
    """(tests, problems): _audit_problems() over a package's rules, as c_levels()' finalizer reads them.

    `rules` is native.existing_rules(), or the fixtures' rules shaped the
    same way (contract_problem("audit_rules")): one composition for both,
    so the fixtures prove the finalizer's own wiring of each input -- the
    tests, harnessed programs, oracle arms and diffio programs read off the
    rules (_audit_inputs), their suites and named programs -- and not a
    copy of it. The rest is the caller's, as _audit_problems() takes it.
    """
    tests, fixtures, oracle, diffio = _audit_inputs(rules)
    return tests, _audit_problems(
        pkg,
        tests,
        exercises,
        layouts = layouts,
        fixtures = fixtures,
        oracle = oracle,
        makefiles = makefiles,
        malloc = malloc,
        clues = clues,
        diffio = diffio,
        suites = _audit_suites(rules),
        programs = _audit_programs(rules),
        memory_graded = memory_graded,
        units = units,
    )

def _audit_suites(rules):
    """_audit_problems' suites, read from a package's rules (native.existing_rules()).

    Each test_suite as {"tags", "tests"}, a listed test by its name alone: a
    label as the rule holds it may name the package (":x", "//pkg:x").
    """
    suites = {}
    for n, r in rules.items():
        if r["kind"] == "test_suite":
            suites[n] = {
                "tags": list(r.get("tags") or []),
                "tests": [str(x).split(":")[-1] for x in (r.get("tests") or [])],
            }
    return suites

def _audit_programs(rules):
    """_audit_problems' programs, read from a package's rules (native.existing_rules()).

    Each student_binary carrying a program_name= tag (_PROGRAM_NAME_TAG, the
    one c_program puts on its exNN_bin), as {binary: the name it gives}.
    """
    programs = {}
    for n, r in rules.items():
        if r["kind"] == "student_binary":
            for t in r.get("tags") or []:
                if t.startswith(_PROGRAM_NAME_TAG):
                    programs[n] = t[len(_PROGRAM_NAME_TAG):]
    return programs

def _suite_problems(tests, suites):
    """_audit_problems' word on the manual suites: each lists every test of its name.

    A manual suite is one a run asks for by name, and its name says what it
    runs: rush_variant's ex00_rush03 is "every layer, one variant"
    (c-piscine/c-piscine-rush-00/README.md). Its list was written by hand,
    and four layers added to the macro after it (_prototype,
    _prototype_names, _defense, _main_exit)
    never reached it, so the suite ran 13 of a variant's 17 tests and said
    nothing. A suite that is not manual is not held to it: the :exNN suites
    select by tag and leave the manual tests out on purpose, and :manual
    lists the manual tests of a module, none of them named manual_*.

    Nor does a manual suite name a test no rule of the package declares:
    rush_variant listed <p>_forbidden, which it declares only where the
    contract has an Allowed line, and a run that named the suite, or a
    query that expands it, failed on the missing label.
    """
    problems = []
    for s in sorted(suites):
        if "manual" not in suites[s]["tags"]:
            continue
        left = [n for n in sorted(tests) if n.startswith(s + "_") and n not in suites[s]["tests"]]
        if left:
            problems.append(("%s: a manual suite, asked for by name to run every test named " +
                             "%s_*, and it leaves out %s, which nothing it promises then " +
                             "runs. List each one in its tests.") % (s, s, ", ".join(left)))
        dangling = [n for n in suites[s]["tests"] if n not in tests and n not in suites]
        if dangling:
            problems.append(("%s: a manual suite naming %s, which no rule of this package " +
                             "declares, so a run that names the suite fails on the missing " +
                             "label. List only the tests the package declares.") % (s, ", ".join(dangling)))
    return problems

def _levels_audit_impl(name, visibility, exercises, layouts, makefiles, malloc, clues, memory_graded):
    """c_levels()' finalizer: the audit, then the module's :manual suite."""
    rules = native.existing_rules()

    # A contract of units: the audit reads each unit's kind and library.
    units = None
    contract = _contract_of_rule(rules.get("subject"))
    if contract != None and "units" in contract:
        units = {u["name"]: [u["kind"], u["library"] or u["name"]] for u in _units_of(contract)}
    tests, problems = _rules_audit(
        native.package_name(),
        rules,
        exercises,
        layouts = layouts,
        makefiles = makefiles,
        malloc = malloc,
        clues = clues,
        memory_graded = memory_graded,
        units = units,
    )
    if problems:
        fail(("c_levels: //%s breaks %d module-wide rule(s) (tools/defs_module.bzl, " +
              "_audit_problems):\n  - %s") % (native.package_name(), len(problems), "\n  - ".join(problems)))

    # EVERY MANUAL TEST, in one suite that is manual itself: a non-manual
    # suite listing them would drag them back into //... (rush_variant's
    # per-variant suites say the same).
    manual = sorted([n for n in tests if "manual" in tests[n]["tags"]])
    native.test_suite(
        name = name,
        tests = [":" + n for n in manual],
        tags = ["manual"] + ([] if manual else [_NO_MANUAL_TAG]),
        visibility = visibility,
    )

# A FINALIZER (Bazel 8+): it runs once the whole BUILD file has been
# evaluated, wherever c_levels() is called in it, and native.existing_rules()
# there sees every target of the package but other finalizers'. Proven with a
# probe package on the pinned Bazel 9.2.0 before relying on it: called from a
# legacy macro in the middle of a BUILD file, it saw the tests declared after
# the call, a fail() in it stops the package from loading with its message,
# and a test_suite it declares lists manual tests by label. So c_levels() no
# longer has to be a module's last statement for a module-wide rule to see
# the whole module.
_levels_audit = macro(
    implementation = _levels_audit_impl,
    finalizer = True,
    attrs = {
        "exercises": attr.string_list(configurable = False),
        # Globbed by c_levels(): a symbolic macro cannot glob.
        "layouts": attr.string_list(configurable = False),
        "makefiles": attr.string_list(configurable = False),
        # The exNN whose corpora get a memcheck twin (_memcheck_allowed),
        # read from the contract by c_levels() as `makefiles` is.
        "malloc": attr.string_list(configurable = False),
        # Every clues*.tsv under tests/, globbed by c_levels().
        "clues": attr.string_list(configurable = False),
        # The contract declares memory_graded (_layer_level).
        "memory_graded": attr.bool(configurable = False),
    },
)

def contract_problem(check, args):
    """What a contract check would fail with, as a string; None where it passes.

    FOR tools/tests/macro_fixtures ONLY. Every check the contract makes is a
    value before it is a fail() (see tools/subject.bzl), and this is how the
    fixtures reach the ones in this file: a package that fails to load cannot
    be a test, so each check is fed the broken input it guards against and
    its message compared, on every run. A project's BUILD file never calls
    it.

    Args:
        check: which check, and what `args` holds for it --
            "exercise", "subject"  the arguments of exercise() / subject()
                                   (subject's `reserved` is
                                   _RESERVED_UNIT_NAMES unless given)
            "unit"                 the arguments of unit()
            "no_contract"          macro, num: a macro called in THIS package
                                   before any subject() -- ask it above the
                                   package's subject() to see the message
            "no_entry"             macro, num, and optionally contract (a
                                   decoded one, for this package's): a
                                   macro called on an exercise, or a unit,
                                   the contract does not list
            "resolve"              macro, and optionally num, unit and
                                   contract (likewise): what a macro's
                                   call names (_resolve_problem)
            "untranscribed"        seen: tests/exNN names, against this
                                   package's contract (c_levels' check)
            "tests_seen"           name: a folder of this package's tests/,
                                   which c_levels() must see among its
                                   tests/ex*/ (_exercise_tests_folders,
                                   the one glob c_levels() reads)
            "turnin_file"          num, name: turnin_file() in this package
            "issued"               num, file: c_issued() in this package
            "readme"               num, file, quotes, sections, sentences,
                                   ai_section, ai_words: c_readme() in this
                                   package
            "case"                 shape ("program", "header", "reading"),
                                   case: one case dict, and optionally
                                   program: c_program's name
                                   (_case_problem)
            "diff_harness"         num (the key the call names: an
                                   exercise, or a unit, a function by its
                                   own name), harness: c_diff's reader
                                   harness name (_diff_harness_problem)
            "audit"                package, tests ({name: tags}, or {name:
                                   {"tags", "srcs", "args"}}), exercises,
                                   and optionally layouts (tests/layout/
                                   files), reads ({name: the layout files
                                   it passes with --layout}), fixtures
                                   ({binary with a harness: the prototype
                                   test its tag names, or None for no
                                   tag}), makefiles (the exNN whose
                                   contract names a Makefile), malloc
                                   (the exNN whose contract allows it),
                                   clues (every clues*.tsv under tests/),
                                   suites ({name: {"tags", "tests"}}),
                                   memory_graded (a bool: the contract
                                   declares it, _layer_level); and in a
                                   contract of units, units
                                   ({unit: [its kind, the library it
                                   belongs to, or its own name]}):
                                   c_levels()' audit of a whole package,
                                   fed an invented one (_audit_problems); its
                                   messages joined with " | "
            "waiting"              tests ({name: {"tags", "args"}}): not a
                                   problem but what _waiting writes, each
                                   output test's list of who waits for it
                                   (_waiting_lists), one line
            "audit_rules"          package, exercises, rules ({name: the
                                   attributes existing_rules() gives it:
                                   kind, tags, srcs, args, harness, deps,
                                   and a test_suite's tests}), and
                                   optionally layouts, makefiles,
                                   malloc, clues, memory_graded and
                                   units: the same audit fed rules
                                   rather than what it reads from them,
                                   through c_levels()' finalizer's own
                                   composition (_rules_audit), so the
                                   reading of a tag or an argument is
                                   proven too
            "unit_folders"         units (the names of a contract's units
                                   and their functions), folders (the
                                   ones under tests/), and optionally
                                   library_dirs (the folders under a
                                   library's tests/<library>/):
                                   c_levels()' check that each is a
                                   unit's (_unit_folders_problems), its
                                   messages joined with " | "
            "unit_suites"          units (as unit_folders takes them),
                                   taken (those a target above holds):
                                   c_levels()' suite per unit
                                   (_unit_suites_problem)
            "hand_tags"            name, tag: hand_test()'s refusal of a
                                   tag _test() derives (_hand_tag_problem)
            "harness_prototype"    name, harness, prototype: _student_bin's
                                   check of its `prototype` against its
                                   `harness`
            "test_env"             name, env: _test()'s check of a test's own
                                   `env` (_test_env_problem)
            "linked"               exercises (as subject() takes them),
                                   exports ({label: names, or None for a
                                   target that is no grader_library()}): the
                                   contract's analysis check of `linked`
                                   (tools/subject.bzl's linked_problem())
            "linked_reader"        macro, num: that macro reading exercise
                                   num's entry in THIS package's contract
                                   (_linked_reader_problem)
            "linked_layer"         macro, num, layer: a layer that cannot
                                   link the grader's library, on exercise
                                   num of this package (_no_linked_problem)
            "make"                 c_make's num, quotes and the checks they
                                   back (_make_problem)
            "make_anchor"          num, anchor[, macro]: c_make (or the
                                   `macro` named, "c_program") building
                                   from `anchor` ("Makefile", or its
                                   script) on exercise num of THIS package
                                   (_make_anchor_problem)
            "allocfail"            c_function's num (the key the call
                                   names, as diff_harness takes it),
                                   malloc, allocfail and allocfail_rule
                                   (_allocfail_problem)
            "function_malloc"      num, malloc[, stem][, contract]:
                                   c_function's `malloc` on exercise or
                                   unit num of THIS package, against its
                                   contract (or the decoded one given), or
                                   against the own box of stem, a function
                                   of the library num
                                   (_function_malloc_problem)
            "memory_rule"          c_program's num, malloc, cases and
                                   memory_rule (_memory_rule_problem)
            "rush_graded"          memory_graded, a bool: rush_variant in a
                                   package whose contract declares it
                                   (_rush_graded_problem)
            "libft_make"           make[, who]: c_libft's (or who's,
                                   "c_library") dict of c_make's
                                   arguments (_libft_make_problem)
            "library_entry"        num, entry (its contract entry, as
                                   exercise() or unit() writes it):
                                   c_library's check that the part is a
                                   library, its `functions` listed and a
                                   Makefile in its `files`
                                   (_library_entry_problem)
            "library_args"         num, functions (the contract's), and
                                   the arguments c_library takes of its
                                   own -- make, hdrs, includes, prototype
                                   (True unless given), prototype_names,
                                   globals, function_lists, restrict_rule,
                                   declares_reading, helpers_rule: its
                                   check of them, `make` first
                                   (_libft_make_problem with who
                                   "c_library", then _library_args_problem)
            "standin_runner"       name, data, runner: a test of THIS package
                                   handing `data` to `runner`
                                   (_standin_runner_problem)
        args: the check's input, as a dict: a BUILD file cannot pass **kwargs.

    Returns:
        The message the check fails with, or None where it passes.
    """
    if check == "exercise":
        return _exercise_problem(**args)
    if check == "subject":
        # The names no unit may take, unless the case hands its own (None to
        # see the message for none).
        return _subject_problem(**dict({"reserved": _RESERVED_UNIT_NAMES}, **args))
    if check == "unit":
        return _unit_problem(**args)
    if check == "no_contract":
        return _no_contract_problem(
            "%s(num = \"%s\")" % (args["macro"], args["num"]),
            _contract_or_none(),
        )
    if check == "no_entry":
        return _no_entry_problem(args["num"], args["macro"], args.get("contract") or _contract("contract_problem"))
    if check == "resolve":
        return _resolve_problem(
            args["macro"],
            args.get("num"),
            args.get("unit"),
            args.get("contract") or _contract("contract_problem"),
        )
    if check == "untranscribed":
        return _untranscribed_problem(_contract("contract_problem"), args["seen"])
    if check == "tests_seen":
        if args["name"] in _exercise_tests_folders():
            return None
        return ("tests/%s: c_levels() does not see it among this package's tests/ex*/ " +
                "folders (_exercise_tests_folders), so no contract entry is asked of it.") % args["name"]
    if check == "turnin_file":
        return _turnin_file_problem(args["num"], args["name"], _entry(args["num"], "turnin_file"))
    if check == "issued":
        return _issued_problem(args["num"], args["file"], _entry(args["num"], "c_issued"))
    if check == "readme":
        return _readme_problem(
            args["num"],
            args["file"],
            args["quotes"],
            args["sections"],
            args["sentences"],
            args["ai_section"],
            args["ai_words"],
            _entry(args["num"], "c_readme"),
        )
    if check == "case":
        return _case_problem(args["case"], args["shape"], args.get("program"))
    if check == "diff_harness":
        return _diff_harness_problem(args["num"], args["harness"])
    if check == "audit":
        reads = args.get("reads") or {}
        tests = {}
        for n, t in args["tests"].items():
            # {name: tags}, or {name: {"tags", "srcs", "args"}} for a test the
            # corpus rule reads (srcs, args).
            tests[n] = dict(kind = "sh_test", **t) if type(t) == "dict" else {"kind": "sh_test", "tags": t}
            tests[n]["layouts"] = reads.get(n, [])
        return " | ".join(_audit_problems(
            args["package"],
            tests,
            args["exercises"],
            layouts = args.get("layouts"),
            fixtures = args.get("fixtures"),
            makefiles = args.get("makefiles"),
            malloc = args.get("malloc"),
            clues = args.get("clues"),
            suites = args.get("suites"),
            memory_graded = args.get("memory_graded", False),
            units = args.get("units"),
        )) or None
    if check == "waiting":
        # Not a problem but what _waiting writes, as one line: each output
        # test's list, "<output>: <test> (<level>), ...", fed invented tests
        # ({name: {"tags", "args"}}) as the audit is.
        tests = {n: dict(kind = "sh_test", **t) for n, t in args["tests"].items()}
        lists = _waiting_lists(tests)
        return " | ".join(["%s: %s" % (o, ", ".join(lists[o]) or "-") for o in sorted(lists)]) or None
    if check == "audit_rules":
        _, problems = _rules_audit(
            args["package"],
            args["rules"],
            args["exercises"],
            layouts = args.get("layouts"),
            makefiles = args.get("makefiles"),
            malloc = args.get("malloc"),
            clues = args.get("clues"),
            memory_graded = args.get("memory_graded", False),
            units = args.get("units"),
        )
        return " | ".join(problems) or None
    if check == "unit_folders":
        return " | ".join(_unit_folders_problems(args["units"], args["folders"], args.get("library_dirs"))) or None
    if check == "unit_suites":
        return _unit_suites_problem(args["units"], args["taken"])
    if check == "hand_tags":
        return _hand_tag_problem(args["name"], args["tag"])
    if check == "harness_prototype":
        return _harness_prototype_problem(args["name"], args.get("harness"), args.get("prototype"))
    if check == "test_env":
        return _test_env_problem(args["name"], args["env"])
    if check == "linked":
        return _linked_problem(args["exercises"], args["exports"])
    if check == "linked_reader":
        return _linked_reader_problem(args["num"], args["macro"], _contract_entries(_contract("contract_problem"))[args["num"]])
    if check == "linked_layer":
        return _no_linked_problem(args["num"], args["macro"], args["layer"])
    if check == "make":
        return _make_problem(**args)
    if check == "make_anchor":
        macro = args.get("macro", "c_make")
        return _make_anchor_problem(args["num"], args["anchor"], _entry(args["num"], macro), macro)
    if check == "allocfail":
        return _allocfail_problem(**args)
    if check == "function_malloc":
        c = args.get("contract")
        e = _contract_entries(c)[args["num"]] if c else _entry(args["num"], "c_function")
        stem = args.get("stem")
        if stem != None:
            e = dict(e, allowed = e["functions"][stem])
        return _function_malloc_problem(args["num"], args["malloc"], e, stem)
    if check == "memory_rule":
        return _memory_rule_problem(**args)
    if check == "rush_graded":
        return _rush_graded_problem(args["memory_graded"])
    if check == "libft_make":
        return _libft_make_problem(args["make"], args.get("who", "c_libft"))
    if check == "library_entry":
        num, e = args["num"], args["entry"]
        return _library_entry_problem(
            num,
            e,
            "c_library(%s)" % _call(num),
            _kind_word(num, e),
            "unit" if _is_unit_key(num) else "exercise",
        )
    if check == "library_args":
        # In c_library's order: its `make` first, then its own arguments,
        # each defaulted as c_library defaults it.
        return (_libft_make_problem(args.get("make") or {}, "c_library") or
                _library_args_problem(
                    args["num"],
                    args.get("hdrs"),
                    args.get("includes"),
                    args.get("prototype_names"),
                    args.get("prototype", True),
                    args.get("globals"),
                    args.get("function_lists"),
                    args["functions"],
                    args.get("restrict_rule"),
                    args.get("declares_reading"),
                    args.get("helpers_rule"),
                ))
    if check == "standin_runner":
        return _standin_runner_problem(args["name"], args["data"], args["runner"], native.package_name())
    fail("contract_problem(check = %r): not a check this knows" % (check,))

def _stray_exercise(ex, contract, where):
    """The files test of a student's folder or generator no exercise of the contract has.

    `where` is "deliverable/exNN" (the folder, reported with every file in
    it) or "generators" (the generator exNN.sh alone). The test is exNN_files,
    under the files layer, so the exercise it seems to be has a suite with a
    red in it, and the audit finds a test for every exercise it was told
    about. Never a fail(): the folder is the student's.
    """
    if where == "generators":
        names_file(
            name = ex + "_files_names",
            names = [ex + ".sh"],
        )
    else:
        _turnin_names(ex + "_files_names", where)
    args = [
        "--label",
        native.package_name() + "/" + where,
        "--grader",
        contract["grader"],
        "--stray",
        ",".join(sorted(["ex" + n for n in contract["exercises"]])),
        "--actual-list",
        "$(rootpath :%s_files_names)" % ex,
    ]

    # No --strict: a folder of no exercise fails whatever the project's
    # `strict` says, which is about an exercise's own file list.
    _test(
        name = ex + "_files",
        srcs = ["//tools:files_test.sh"],
        args = args,
        data = [":%s_files_names" % ex],
        tags = ["files"],
    )

# THE TESTS OF A WHOLE MODULE, which belong to no exercise: {name: layer}.
# Everything else in a project is exNN_<what>. c_levels() emits these, and its
# audit lets exactly these names through (docs/reference.md, "Suites").
_MODULE_TESTS = {
    "deliverable_files": "files",
}

def _outside_exercises(contract):
    """The module's deliverable_files: every file of deliverable/ in no exercise's folder.

    What sits at the root of deliverable/, or in a top-level folder that is
    not named like an exercise (old/, ex5/, "ex05 copy/"), in a project whose
    subject gives each exercise a turn-in directory. deliverable/ is the
    Vogsphere repository's root, so all of it is pushed, and no exercise's
    files layer looked there: a stray at the root was not even an input of any
    test (finding 052). An exNN/ folder is left out -- its exercise's
    exNN_files reports it, or _stray_exercise's does for one the subject lacks
    -- and so are build products, which //tools:submit does not push.
    `contract` is a contract of exercises, each of which has a folder
    (exercise() refuses dir = None): a project that turns in at the root of
    deliverable/ is a contract of units, which c_levels() never hands here.
    """
    names = []
    for f in native.glob(["deliverable/**"], exclude = _not_build_products("deliverable"), allow_empty = True):
        rel = f[len("deliverable/"):]
        if "/" in rel and _is_ex(rel.split("/")[0]):
            continue
        if "\n" not in rel:
            names.append(rel)
    names_file(
        name = "deliverable_files_names",
        names = names,
    )
    _test(
        name = "deliverable_files",
        srcs = ["//tools:files_test.sh"],
        args = [
            "--label",
            native.package_name() + "/deliverable",
            "--outside",
            ",".join(sorted(["ex" + n for n in contract["exercises"]])),
            "--actual-list",
            "$(rootpath :deliverable_files_names)",
        ],
        data = [":deliverable_files_names"],
        tags = ["files"],
    )

def _parts_files(contract):
    """deliverable_files for a project divided into parts at the root: what no part names, once.

    Every part turns in at the root of deliverable/, so one folder holds
    every part's files, and each part's own files test judges only the
    files that part names (c_files). This judges the rest once, for the
    whole root (files_test.sh --union): a file no part names, a build
    product, a .c no part's build compiles. Nothing for any other contract;
    a contract of exercises has _outside_exercises.
    """
    parts = _root_parts(contract)
    if not parts:
        return

    # Every part turns in at the root (subject()'s units), so any part's
    # turn-in directory is the root of deliverable/.
    d = turnin_dir(parts[0])
    entries = _contract_entries(contract)
    _turnin_names("deliverable_files_names", d)
    named, optional, provided, built, programs = [], [], [], [], []
    for k in parts:
        e = entries[k]
        for f in e["files"]:
            if f not in named:
                named.append(f)
        for f in _part_files(e, d)[len(e["files"]):]:
            if f not in optional and f not in named:
                optional.append(f)
        for v in e["provided"].values():
            if v not in provided and v not in optional:
                provided.append(v)
        b = _built_manifest(_prefix(k)) or _manifest_build(k, e, d)
        if b and b not in built:
            built.append(b)
        for p in _built_programs(_prefix(k)):
            if p not in programs:
                programs.append(p)
    args = ["--label", native.package_name() + "/" + d, "--grader", contract["grader"], "--union"]
    for f in named:
        args += ["--sibling", f]
    for f in optional:
        args += ["--optional", f]
    for f in provided:
        args += ["--provided", f]
    args += ["--actual-list", "$(rootpath :deliverable_files_names)"]
    if contract["strict"]:
        args.append("--strict")
    args.append("--root")
    for b in built:
        args += ["--built", "$(rootpath %s)" % b]
    for p in programs:
        args += ["--program", p]
    _test(
        name = "deliverable_files",
        srcs = ["//tools:files_test.sh"],
        args = args,
        data = [":deliverable_files_names"] + built,
        tags = ["files"],
    )

def _unit_folders_problems(names, folders, library_dirs = None):
    """Why each folder under tests/ is read by nothing, in a contract of units: one message per folder.

    A unit's files are under tests/<unit>/, a function's under
    tests/<function>/ (_member), and tests/layout/ holds the structures a
    subject prints; a folder of any other name is one no macro reads, so a
    file put there is checked by nothing. Nor is a folder under a
    library's tests/<library>/: its functions' folders are beside it, not
    under it, so whatever it holds is read by none of them. A value first, like every contract
    check: contract_problem("unit_folders") hands it to the fixtures.

    Args:
      names: the names of the contract's units and of their functions.
      folders: the folders right under tests/, by name.
      library_dirs: "<library>/<folder>", every folder right under a
        library's tests/<library>/ but one holding the grader's copies.

    Returns:
      One message per folder no macro reads (c_levels() fails with the
      first), or an empty list where each is read.
    """
    problems = []
    for f in sorted(folders):
        if f != "layout" and f not in names:
            problems.append(("tests/%s/: a folder under tests/ that is no unit's (the subject() " +
                             "contract's units and their functions), so no macro reads it. Name it " +
                             "after the unit whose files it holds, or move them; tests/layout/ is " +
                             "the one other folder.") % f)
    for d in sorted(library_dirs or []):
        problems.append(("tests/%s/: a folder under library %s's tests, where its functions' " +
                         "folders are not (each is tests/<function>/, beside it), so no macro " +
                         "reads it. Move its files to the folder of the function they are " +
                         "for, or out.") % (d, d.split("/")[0]))
    return problems

def _unit_suites_problem(names, taken):
    """c_levels()' message for a unit whose name a target already holds; None if none does.

    Each unit's suite, :<unit>, is declared under the unit's name, which no
    other target may hold. A value first, like every contract check:
    contract_problem("unit_suites") hands it to the fixtures.

    Args:
      names: the names of the contract's units and of their functions.
      taken: those of them a target of the package already has.
    """
    for u in names:
        if u in taken:
            return (("c_levels(): %s is a unit of this package, and a target already has " +
                     "that name: the unit's suite :%s is declared here") % (u, u))
    return None

def _tests_folders(folder):
    """The folders right under tests/ that `folder` matches, by name.

    `folder` is a glob of one folder name ("ex*", or "*" for a contract of
    units); the files under it are globbed at any depth, so a file names
    its folder however deep it is, and a folder that holds only folders is
    seen too (a glob of tests/<folder>/* lists no folder, and missed it).
    """
    folders = {}
    for f in native.glob(["tests/%s/**" % folder], allow_empty = True):
        parts = f.split("/")
        if len(parts) > 2:
            folders[parts[1]] = True
    return sorted(folders.keys())

def _exercise_tests_folders():
    """The tests/exNN/ folders c_levels() finds its exercises in, by name.

    c_levels() and contract_problem("tests_seen") both read them here, so
    the fixture's row checks the glob c_levels() runs, not a copy of it.
    """
    return _tests_folders("ex*")

def _level_suites():
    """The four level suites, :basic to :complete, each selecting its lvl_ tag."""
    for name in _LEVEL_NAMES:
        native.test_suite(
            name = name,
            tags = ["lvl_" + name],
        )

def _module_audit(contract, exercises):
    """The tail both kinds of contract share: the audit, :manual and the conventions' sources.

    _levels_audit, once everything is declared, over `exercises` (none in
    a contract of units, which reads its units from the contract). Which
    exercise or unit turns in a Makefile, and which may allocate (a
    function's corpus is then held to a memcheck twin, as corpus_memory()
    reads it), are read off the contract's rows (_units_of), one row per
    exercise in a contract of exercises.
    """
    rows = _units_of(contract)
    entries = _contract_entries(contract)
    _levels_audit(
        name = "manual",
        exercises = exercises,
        layouts = native.glob(["tests/layout/**"], allow_empty = True),
        clues = native.glob(["tests/**/clues*.tsv"], allow_empty = True),
        makefiles = sorted([
            r["name"]
            for r in rows
            if r["kind"] != "function" and "Makefile" in (entries[r["key"]]["files"] or [])
        ]),
        malloc = sorted([
            r["name"]
            for r in rows
            if _memcheck_allowed(entries[r["key"]])
        ]),
        memory_graded = bool(contract.get("memory_graded")),
    )
    _conventions_srcs()

def _units_levels(contract, refusals = None):
    """c_levels() for a contract of units: its files layers, suites and audit.

    What c_levels() declares for a contract of exercises, named by unit.
    Each unit gets a suite, :<unit>, selecting the tag unit=<unit> that
    _test() derives from a test's name: a library's suite holds the whole
    library's tests, and each function's tests sit in the function's own.
    A unit turns in at the root of deliverable/, so there is no
    generators/ to look for and no student folder of an exercise;
    deliverable_files is declared only where the root is divided into
    parts (_parts_files), to judge once every file no part names.
    `refusals` is c_levels()'.
    """
    rows = _units_of(contract)
    entries = _contract_entries(contract)
    names = [r["name"] for r in rows]

    # A library or a project is judged whole, as an exercise is: the files
    # layer, from the contract, where no macro emitted one already, and
    # the Norm's header rules norminette skips (_header_norm_test).
    whole = [r for r in rows if r["kind"] != "function"]
    for r in whole:
        if entries[r["key"]]["files"] == None:
            continue
        if native.existing_rule(r["name"] + "_files"):
            continue
        c_files(unit = r["name"])
    for r in whole:
        _header_norm_test(r["key"])

    _level_suites()

    # tests/ is the harness's: every folder in it is a unit's, a
    # function's or tests/layout/ (_tests_folders).
    folders = _tests_folders("*")

    # A library's own folder holds its files (prototype.h) and the grader's
    # copies, and no folder of its own: its functions' are beside it.
    library_dirs = []
    for r in whole:
        if not entries[r["key"]].get("functions"):
            continue
        t = "tests/" + r["name"]
        files = native.glob([t + "/*"], allow_empty = True)
        copies = _provided(r["key"]).overlay
        for d in native.glob([t + "/*"], exclude_directories = 0, allow_empty = True):
            if d in files or [c for c in copies if c.startswith(d + "/")]:
                continue
            library_dirs.append(d[len("tests/"):])

    # In the macro fixtures (`refusals`) each is collected and the rest is
    # declared all the same: a folder no macro reads emits nothing of its
    # own.
    for problem in _unit_folders_problems(names, folders, library_dirs):
        _refuse(problem, refusals, "c_levels()")
    _parts_files(contract)

    # ONE SUITE PER UNIT, by the unit's name, which no other target may
    # hold.
    _refuse(_unit_suites_problem(names, [u for u in names if native.existing_rule(u)]), None, "c_levels()")
    for u in names:
        native.test_suite(
            name = u,
            tags = [_UNIT_TAG + u],
        )

    # THE AUDIT AND :manual, once everything is declared (_module_audit),
    # which reads the units from the contract.
    _module_audit(contract, [])

def c_levels(name = None, refusals = None):
    """A module's suites, and the audit of the module as a whole.

    Args:
      name: unused. Bazel convention is that every macro takes a `name`, and
        buildifier's unnamed-macro check enforces it -- a student who writes
        their own macro should meet that rule here rather than be surprised
        by it later. Every target this emits is named by the ladder, by an
        exercise or by what it is (:manual), not by a caller.
      refusals: in tools/tests/macro_fixtures alone, and in a contract of
        units, the list a folder under tests/ that no macro reads is
        collected in instead of failing (_refuse), the rest declared all
        the same.

    What it emits (docs/reference.md, "Suites"):

      :basic :strict :robust :complete  one level of the whole module, each
            level with every level below it. Which layer sits at which level
            is docs/reference.md's layer table, checked against _LAYER_LEVEL;
            it is not restated here, because every copy of it drifted.
      :exNN  every non-manual test of one exercise, whatever emitted it.
      :<function>  every non-manual test of one function of a library
            exercise (the contract's `functions`), whatever emitted it.
      :manual  every manual test of the module, and nothing else.
      exNN_files  the files layer of every exercise of the subject() contract
            (unless its `files` is None, or a macro emitted one already), and
            of every folder the student made that is no exercise of it.
      exNN_norm_header  the Norm's header rules norminette skips, for every
            exercise of the contract that turns in a header
            (_header_norm_test).
      deliverable_files  the rest of the pushed tree: every file at the root
            of deliverable/ or in a folder that is no exercise's, which fails
            (_outside_exercises; where the project turns in at the root, only
            a root divided into parts has one: _parts_files).

    Naming a single target still runs it regardless of level -- these are
    suites you ASK for, not a filter you have to escape. `--test_tag_filters`
    would have been the obvious mechanism and is the wrong one: it also
    filters explicitly-named targets, so `bazel test //mod:ex00_ilp32` under a
    basic filter reports "No test targets were found" instead of running the
    test you just asked for.

    IT NEEDS THE PROJECT'S SUBJECT CONTRACT, and fails without one, and it
    refuses a tests/exNN/ the contract does not list. Call it after the
    macros of the module: a shell exercise's own files layer must exist before
    it looks. Its AUDIT does not need that: a finalizer (_levels_audit) runs
    it once the whole BUILD file has been read, wherever c_levels() is in it,
    and fails the package's loading on any break of a module-wide rule --
    see _audit_problems for the list and why they are checked here.

    A CONTRACT OF UNITS (units = {...}) gets the same, named by unit
    (_units_levels): :<unit> for each unit and each function of a library,
    in place of :exNN and :<function>, and for each library or project
    <unit>_files and, where it turns in a header, <unit>_norm_header. It
    refuses a folder under tests/ that is no unit's, and one under a
    library's tests/<library>/, where a contract of exercises refuses a
    tests/exNN/ it does not list and a folder of no function under a
    library's.
    """
    contract = _contract("c_levels")
    if "units" in contract:
        # Every read below walks the contract's exercises, which a contract
        # of units does not have: its units get the same, named by unit.
        _units_levels(contract, refusals)
        return
    if refusals != None:
        fail(("c_levels(): refusals = [...] collects what c_levels() refuses in a " +
              "contract of units, and this package's contract has exercises."))

    # THE FILES LAYER, one per exercise, from the contract -- emitted here, from
    # the one macro every project calls, so no exercise can be without one and
    # no BUILD file writes a file list of its own. A shell exercise emits its
    # own (it runs the generator first), and an exercise whose contract gives
    # no file names (files = None) gets none. Everything else is declared
    # above this call, which is where every BUILD file has it.
    for num in sorted(contract["exercises"]):
        if contract["exercises"][num]["files"] == None:
            continue
        if native.existing_rule("ex%s_files" % num):
            continue
        c_files(num)

    # THE NORM'S HEADER RULES norminette skips -- protection from double
    # inclusions, and the prefix of a name defined inside a typedef -- for
    # every exercise that turns in a header, from the contract (see
    # _header_norm_test), so no BUILD file asks for it and none can forget.
    for num in sorted(contract["exercises"]):
        _header_norm_test(num)

    _level_suites()

    # ONE SUITE PER EXERCISE, so a whole exercise can be run in one command.
    #
    # Before these, you could run one LAYER of one exercise
    # (//c-piscine/c-piscine-c-05:ex00_output) or a whole module, and nothing
    # in between: `ex00_*` is not a Bazel target pattern, and
    # --test_tag_filters is the wrong tool for the reason spelled out above.
    #
    # The exercises are FOUND, never listed by hand, and from everywhere one
    # can show up (finding 074: C 06 ex00 has no tests/ folder, and had no
    # suite): the contract; tests/exNN/; and the student's own side, a
    # deliverable/exNN/ folder or a generators/exNN.sh -- names only, from a
    # glob, so nothing in them is read. deliverable/exNN/ is skipped where a
    # generator makes it (it is generated and gitignored).
    # A tests/exNN/ that holds only folders is one too
    # (_exercise_tests_folders).
    seen = {ex: True for ex in _exercise_tests_folders()}

    # ONE SET OF EXERCISES. A tests/exNN/ with no contract entry is an
    # exercise whose turn-in nobody transcribed -- every layer of it would
    # guess -- so it does not load: tests/ is the harness's. The other way
    # round is legitimate (C 06 ex00's check needs no fixture file), and the
    # contract is where the exercise is found then.
    problem = _untranscribed_problem(contract, seen)
    if problem:
        fail(problem)
    for ex in ["ex" + n for n in contract["exercises"]]:
        seen[ex] = True

    # THE STUDENT'S SIDE never fails the loading of the package (no deliverable
    # can break the build graph): a folder or a generator for an exercise the
    # contract does not list gets a files test saying so, which fails
    # whatever the subject says about extra files: no exercise's file list
    # reaches a folder of no exercise, it is pushed with the rest, and no
    # exercise grades it. A folder not named exNN (ex5, "ex05 copy") is no
    # exercise and is not looked at here: the module's deliverable_files
    # reports it, with every file at the root.
    found = {}
    for f in native.glob(["generators/ex*.sh"], allow_empty = True):
        ex = f[len("generators/"):-len(".sh")]
        if _is_ex(ex):
            found[ex] = "generators"
    for ex, d in _student_folders().items():
        if ex not in found:
            found[ex] = d
    for ex in sorted(found):
        if ex in seen:
            continue
        seen[ex] = True
        _stray_exercise(ex, contract, found[ex])
    _outside_exercises(contract)
    for ex in sorted(seen):
        native.test_suite(
            name = ex,
            tags = [ex],
        )

    # THE AUDIT AND :manual, once everything is declared (_module_audit).
    _module_audit(contract, sorted(seen))

def _conventions_srcs():
    """The module's :conventions_srcs, the files //tools:conventions reads."""
    # EVERYTHING IN THIS MODULE THAT //tools:conventions READS, so the style
    # gate can be a TEST rather than something you have to remember to run.
    #
    # It is emitted by c_levels(), the one macro every module already calls,
    # rather than written into twenty BUILD files. conventions.sh's own header
    # argued against ever being an sh_test on exactly that ground -- "listing
    # ~140 files there, and updating that list whenever a module gains a test,
    # would be a convention nobody keeps, which is the failure this script
    # exists to prevent". A glob is not a list, and a module that calls
    # c_levels() gets this without knowing it exists. What remains hand-written
    # is one label per MODULE in //tools/tests, and //tools:conventions refuses
    # to run if any module in submit.sh's table is missing from what it can see
    # -- so the drift that is still possible is the loud kind.
    native.filegroup(
        name = "conventions_srcs",
        srcs = native.glob(
            [
                "BUILD.bazel",
                # A .bzl file the BUILD file loads (Rush 00's team.bzl): its
                # comments ship as the BUILD file's do.
                "*.bzl",
                # The module's README and any note beside it: the level ladder
                # check reads them, and a README is where a new project's
                # author writes one.
                "*.md",
                # The English subject, which the check that tools/subjects.tsv
                # is each module's subject hashes on main. In a clone of the
                # template it is the student's own download, if any, and that
                # check opens none (allow_empty, below).
                "en.subject.pdf",
                # The project's own ignore rules (Reloaded's), which the check
                # that a program the project builds is ignored reads beside
                # the root's.
                ".gitignore",
                "generators/*.sh",
                # Every file of the harness's tests/, each read by a check:
                # its scripts; every C file, not only the test_*.c mains
                # (the check that none defines a function the grader brings,
                # grader_lib.bzl; every differential harness, diff_*.c, whose
                # header's "Line:" paragraph is the diff layer's column
                # legend; the escape check, which reads the header a test
                # program prints through, Rush 00's rush_capture.h, and the
                # c_diff harness a measuring macro names); every clues*.tsv,
                # not clues.tsv alone, since a test outside the programs can
                # name a hint file of its own (Rush 00's clues_putchar.tsv),
                # and the first-red check reads them all; a shell exercise's
                # expected output, which the copy scan compares with every
                # other module's, and a case's own expected file, whose
                # labels a clues_*.tsv beside it must name; a twin's README.md
                # pointing at the tests it reads (shell_exercise's twin_of);
                # and everything else a case reads or expects, whose bytes
                # are the case: the check that a CR in one survives a commit
                # (.gitattributes) has to see them.
                "tests/**",
            ],
            allow_empty = True,
        ),
        visibility = ["//tools/tests:__pkg__"],
    )

def starlark_selftest_arms():
    """The load-time fail() guards loaded above, from defs_checks.bzl and defs_test.bzl, run on known inputs.

    A guard that fail()s at loading has no runner a selftest arm can call, and
    a guard that stopped refusing would be as silent as the key it stopped
    catching. So each is called here on an input it must refuse and on one it
    must accept, here because the guards are private names those files hand
    this one, and
    //tools/tests:starlark_unit judges the answers: a wrong one is that test
    red, naming the arm. It once fail()ed the load of tools/tests instead,
    which took every target of the package down with it, and //:gate_fast,
    where one test should have gone red. The inputs are made up (ex00, "a")
    and belong to no exercise.

    Returns:
        (arms, apostrophe): arms a list of (what, the guard's answer, a
        substring the refusal must hold, or None for an input it must
        accept); apostrophe the sentence starlark_unit hands its script
        through shell_word, to prove that quoting keeps it whole.
    """
    good = {"name": "a", "expected": "a.txt", "args": [], "clues": "clues.tsv"}
    hyphen = dict(good)
    hyphen["invalid-input"] = True
    arms = [
        # (what, the guard's answer, a substring the refusal must hold, or
        # None for an input it must accept)
        (
            "a misspelt c_program case key is refused, naming the real one",
            _case_problem(dict(good, invalid_inputs = True), "program"),
            "did you mean \"invalid_input\"",
        ),
        (
            "a hyphenated one too",
            _case_problem(hyphen, "program"),
            "did you mean \"invalid_input\"",
        ),
        (
            "an unknown c_program case key is refused",
            _case_problem(dict(good, why = "x"), "program"),
            "is not a key of a program case",
        ),
        (
            "every documented c_program key is accepted",
            _case_problem({k: _GOOD_VALUE.get(k, "x") for k in _CASE_KEYS["program"] + ["expected"]}, "program"),
            None,
        ),
        (
            "a c_program key c_header does not read is refused there",
            _case_problem(dict(good, stream = "x"), "header"),
            "is not a key of a header case",
        ),
        (
            "a cwd_files case accepts its files by name",
            _case_problem(dict(good, args = ["a"], cwd_files = {"x.dict": "a"}), "program"),
            None,
        ),
        (
            "a cwd_files case refuses a location-expanded argument",
            _case_problem(dict(good, args = ["$(location x.dict)"], cwd_files = {"x.dict": "a"}), "program"),
            "runs from its own folder",
        ),
        (
            "a cwd_files name outside the run folder is refused",
            _case_problem(dict(good, cwd_files = {"x.dict": "../a"}), "program"),
            "not a name inside the run folder",
        ),
        (
            "a cwd_files name Bazel would split is refused",
            _case_problem(dict(good, cwd_files = {"x.dict": "a b"}), "program"),
            "Bazel splits",
        ),
        (
            "an empty cwd_files is refused",
            _case_problem(dict(good, cwd_files = {}), "program"),
            "the files the run folder holds",
        ),
        (
            "an argv_file that is no label is refused",
            _case_problem(dict(good, argv_file = ["a"]), "program"),
            "one argument per line",
        ),
        (
            "a cwd_files name . is refused",
            _case_problem(dict(good, cwd_files = {"x.dict": "."}), "program"),
            "not a name inside the run folder",
        ),
        (
            "a cwd_files name that is the program file is refused",
            _case_problem(dict(good, cwd_files = {"x.dict": "toy"}), "program", "toy"),
            "where the run folder holds the program",
        ),
        (
            "...and one under a folder of that name",
            _case_problem(dict(good, cwd_files = {"x.dict": "toy/x.dict"}), "program", "toy"),
            "where the run folder holds the program",
        ),
        (
            "a cwd_files name in a folder of its own is accepted",
            _case_problem(dict(good, cwd_files = {"x.dict": "sub/x.dict"}), "program", "toy"),
            None,
        ),
        (
            "a c_program case named valgrind, a clue label, is refused",
            _case_problem(dict(good, name = "valgrind"), "program"),
            "is not named \"valgrind\"",
        ),
        (
            "exit_quote with no exit is refused",
            _case_exit_error("ex00", dict(good, exit_quote = "q")),
            "exit_quote but no exit",
        ),
        (
            "an exit status above 255 is refused",
            _case_exit_error("ex00", dict(good, exit = 256)),
            "from 0 to 255",
        ),
        (
            "an invalid_input that is not a bool is refused",
            _case_exit_error("ex00", dict(good, invalid_input = "yes")),
            "True or False",
        ),
        (
            "a quoted exit is accepted",
            _case_exit_error("ex00", dict(good, exit = 0, exit_quote = "q")),
            None,
        ),
        (
            "a stderr case that says nothing about its status is refused",
            _case_exit_error("ex00", dict(good, stream = "stderr")),
            "does not say what its exit status means",
        ),
        (
            "a stderr case marked invalid_input False is accepted",
            _case_exit_error("ex00", dict(good, stream = "stderr", invalid_input = False)),
            None,
        ),
        (
            "a stderr case with an exit is accepted",
            _case_exit_error("ex00", dict(good, stream = "stderr", exit = 1)),
            None,
        ),
        (
            "a stderr any_of case, which gets no twin, is accepted",
            _case_exit_error("ex00", dict(good, stream = "stderr", any_of = ["a", "b"])),
            None,
        ),
        (
            "shell_word() doubles a $ and keeps quotes and blanks inside single quotes",
            shell_word("($1 == \"\" ? 0 : 1)"),
            "'($$1 == \"\" ? 0 : 1)'",
        ),
        (
            "a forbidden layer for a subject with no Allowed functions line is refused",
            _forbidden_allowed_problem("ex00_forbidden", None),
            "would authorise nothing",
        ),
        (
            "...and one for \"Allowed functions: None\" is accepted",
            _forbidden_allowed_problem("ex00_forbidden", []),
            None,
        ),
        (
            "c_header: an unquoted exit below robust is refused",
            _header_exit_error("ex00", dict(good, exit = 0)),
            "checks one at robust",
        ),
        (
            "c_header: an unquoted exit at robust is accepted",
            _header_exit_error("ex00", dict(good, exit = 0, level = 3)),
            None,
        ),
        (
            "c_header: a quoted exit at basic is accepted",
            _header_exit_error("ex00", dict(good, exit = 0, exit_quote = "q")),
            None,
        ),
        (
            "a quoted exit at basic is the subject naming it",
            _exit_source(dict(good, exit = 0, exit_quote = "q")),
            "subject",
        ),
        (
            "a quoted exit raised to strict is a reading of the sentence",
            _exit_source(dict(good, exit = 1, exit_quote = "q", level = 2)),
            "reading",
        ),
        (
            "an unquoted exit is a convention of this repo",
            _exit_source(dict(good, exit = 0, level = 3)),
            "convention",
        ),
        (
            "a quoted exit raised past strict is refused, not called a reading",
            _case_problem(dict(good, exit = 1, exit_quote = "q", level = 3), "program"),
            "No other level takes a quote",
        ),
        (
            "c_header refuses it too",
            _case_problem({"name": "a", "expected": "a.txt", "exit": 0, "exit_quote": "q", "level": 4}, "header"),
            "No other level takes a quote",
        ),
        (
            "a quoted exit at strict is accepted",
            _case_problem(dict(good, exit = 1, exit_quote = "q", level = 2), "program"),
            None,
        ),
        (
            "a quoted exit at basic reaches the runner with its sentence too",
            " ".join(_exit_flags({"exit": 0, "exit_quote": "a b"}, 0)),
            "--exit 0 --exit-source subject --exit-quote 'a b'",
        ),
        (
            "a reading reaches the runner with its sentence as one argument",
            " ".join(_exit_flags(dict(good, exit = 1, exit_quote = "a b", level = 2), 1)),
            "--exit 1 --exit-source reading --exit-quote 'a b'",
        ),
        (
            "a program that may open files and names no file that will not open is refused",
            _missing_file_problem("ex00", ["open", "read"], [good], None),
            "no case names a file that will not open",
        ),
        (
            "an error case about a file's content is not that path (BSQ's and Rush 02's shape)",
            _missing_file_problem("ex00", ["open", "read"], [good, dict(good, name = "b", invalid_input = True), dict(good, name = "c", exit = 1)], None),
            "no case names a file that will not open",
        ),
        (
            "a case marking the operand that will not open is that path",
            _missing_file_problem("ex00", ["open"], [good, dict(good, name = "b", args = ["nope"], missing_file = "nope", invalid_input = True)], None),
            None,
        ),
        (
            "or a sentence saying why there is none",
            _missing_file_problem("ex00", ["open"], [good], "the subject runs it on one fixed file"),
            None,
        ),
        (
            "a sentence beside such a case is refused as stale",
            _missing_file_problem("ex00", ["open"], [dict(good, args = ["nope"], missing_file = "nope", survive = True)], "none"),
            "Drop the sentence",
        ),
        (
            "a sentence where nothing asks for one is refused too",
            _missing_file_problem("ex00", ["write"], [good], "none"),
            "nothing asks for one",
        ),
        (
            "a program that may not open files is not asked",
            _missing_file_problem("ex00", ["write"], [good], None),
            None,
        ),
        (
            "missing_file names one of the case's operands",
            _case_problem(dict(good, args = ["a"], missing_file = "b"), "program"),
            "do not hold it",
        ),
        (
            "and not a fixture, which is there",
            _case_problem(dict(good, args = ["$(location x)"], missing_file = "$(location x)"), "program"),
            "a file that is there",
        ),
        (
            "nor an option, standard input or a directory",
            _case_problem(dict(good, args = ["."], missing_file = "."), "program"),
            "as a directory that is there",
        ),
        (
            "a missing_file operand of the case is accepted",
            _case_problem(dict(good, args = ["-c", "5", "no_such_file_ex00"], missing_file = "no_such_file_ex00"), "program"),
            None,
        ),
        (
            "nor a name cwd_files stages in the run folder",
            _case_problem(dict(good, args = ["numbers.dict"], missing_file = "numbers.dict", cwd_files = {"x.dict": "numbers.dict"}), "program"),
            "the run folder holds it",
        ),
        (
            "a missing_file case that says nothing of its status is refused",
            _case_exit_error("ex00", dict(good, args = ["nope"], missing_file = "nope")),
            "does not say what its exit status means",
        ),
        (
            "one marked invalid_input is accepted",
            _case_exit_error("ex00", dict(good, args = ["nope"], missing_file = "nope", invalid_input = True)),
            None,
        ),
        (
            "a model is a list of words",
            _model_problem("ex00", "c10_run cat", [good]),
            "as a list of words",
        ),
        (
            "with no blank inside one, which Bazel would split",
            _model_problem("ex00", ["c10_run", "--prog ex00_bin"], [good]),
            "as a list of words",
        ),
        (
            "a model beside a sanitized case is refused",
            _model_problem("ex00", ["c10_run", "cat"], [good, dict(good, name = "s", sanitize = True)]),
            "compares a sanitized output",
        ),
        (
            "and one with no case it could answer",
            _model_problem("ex00", ["c10_run", "cat"], [{"name": "x", "survive": True}]),
            "no case has one expected file",
        ),
        (
            "a survive case is gated on a case run where the test runs, never on a run folder's",
            " ".join(_survive_gate("ex00", [
                dict(good, name = "folder", args = ["4"], cwd_files = {"x.dict": "n"}),
                dict(good, name = "argfile", argv_file = "a.argv"),
                dict(good, name = "here", args = ["4"]),
                {"name": "s", "survive": True},
            ])[0]),
            "--gate-label ex00_here_output",
        ),
        (
            "a case's memory gate is its output test's run, every comparing key and its stdin",
            "[%s]" % " ".join(_memory_gate("ex00", [good], dict(good, stream = "stderr", sanitize = True, labeled = True, stdin = "tests/ex00/in.txt"), _case(dict(good, stream = "stderr", sanitize = True, labeled = True, stdin = "tests/ex00/in.txt"), "program", "c_program(00)"), "ex00_bin", ([], []))[0]),
            "[--gate-differ $(location //tools:diff_output.sh) --gate-bin $(location :ex00_bin) " +
            "--gate-label ex00_output --gate-expected $(location tests/ex00/a.txt) --gate-stream stderr " +
            "--gate-sanitize --gate-labeled --gate-stdin $(location tests/ex00/in.txt)]",
        ),
        (
            "a survive case's memory gate is the survive gate, after --survive",
            "[%s]" % " ".join(_memory_gate("ex00", [good], {"name": "s", "survive": True}, _case({"name": "s", "survive": True}, "program", "c_program(00)"), "ex00_bin", (["--gate-expected", "E"], []))[0]),
            "[--survive --gate-differ $(location //tools:diff_output.sh) --gate-bin $(location :ex00_bin) --gate-expected E]",
        ),
        (
            "a model with a case of one expected file is accepted",
            _model_problem("ex00", ["c10_run", "--prog", "ex00_bin", "cat"], [good]),
            None,
        ),
        (
            "an argument table held to no model, with no reason, is refused",
            _argv_model_problem("ex01", None, None),
            "nothing holds it to one",
        ),
        (
            "and one that says both",
            _argv_model_problem("ex01", ["c06_run", "print"], "a toy"),
            "say opposite things",
        ),
        (
            "an argument table's model is a list of words",
            _argv_model_problem("ex01", "c06_run print", None),
            "as a list of words",
        ),
        (
            "and an empty reason is none",
            _argv_model_problem("ex01", None, " "),
            "no_model is a sentence",
        ),
        (
            "an argument table with its model is accepted",
            _argv_model_problem("ex01", ["c06_run", "print"], None),
            None,
        ),
        (
            "and one that says why there is none",
            _argv_model_problem("ex01", None, "the toy's table is its own"),
            None,
        ),
        (
            "a file_check call that says nothing of stderr is refused",
            _runner_choice_problem("ex00_file_diff", "//tools:file_check.sh", ["--bin", "x", "--fn", "f"]),
            "Pass exactly one of --stderr-empty, --stderr-ignored; this call has none",
        ),
        (
            "and one that says both",
            _runner_choice_problem("ex00_file_diff", "//tools:file_check.sh", ["--stderr-empty", "--stderr-ignored", "y"]),
            "this call has --stderr-empty, --stderr-ignored",
        ),
        (
            "a file_check call that holds stderr empty is accepted",
            _runner_choice_problem("ex00_file_diff", "//tools:file_check.sh", ["--bin", "x", "--stderr-empty"]),
            None,
        ),
        (
            "a replay under a memory checker makes no stderr choice, and is accepted",
            _runner_choice_problem("ex00_file_diff_asan", "//tools:file_check.sh", ["--bin", "x", "--fn", "f", "--sanitized"]),
            None,
        ),
        (
            "and one that makes one anyway is refused",
            _runner_choice_problem("ex00_file_valgrind", "//tools:file_check.sh", ["--bin", "x", "--valgrind", "v", "--stderr-empty"]),
            "drop --stderr-empty",
        ),
        (
            "a stderr reason written plainly, which Bazel would split, is refused",
            _runner_choice_problem("ex00_argv_diff", "//tools:argv_check.sh", ["--stderr-ignored", "the subject says nothing"]),
            "does not hand over as one argument",
        ),
        (
            "and one with a bare apostrophe, which fails the analysis",
            _runner_choice_problem("ex00_argv_diff", "//tools:argv_check.sh", ["--stderr-ignored", "it's"]),
            "does not hand over as one argument",
        ),
        (
            "stderr_ignored() quotes a sentence with an apostrophe as one argument",
            _runner_choice_problem("ex00_argv_diff", "//tools:argv_check.sh", stderr_ignored("the subject's words")),
            None,
        ),
        (
            "an argv_check --exit-only call that holds stderr empty is refused",
            _runner_choice_problem("ex00_argv_diff_exit", "//tools:argv_check.sh", ["--bin", "x", "--exit-only", "--stderr-empty"]),
            "--exit-only judges only how each run ended",
        ),
        (
            "and one that ignores stderr is accepted",
            _runner_choice_problem("ex00_argv_diff_exit", "//tools:argv_check.sh", ["--bin", "x", "--exit-only"] + stderr_ignored("only the ending")),
            None,
        ),
        (
            "a runner that asks for no choice is not held to one",
            _runner_choice_problem("ex00_output", "//tools:diff_output.sh", ["--bin", "x"]),
            None,
        ),
        (
            "a bsq_check call that quotes no sentence is refused",
            _runner_choice_problem("ex00_bsq", "//tools:bsq_check.sh", ["--bin", "x", "--stderr-empty"]),
            "Pass exactly one of --quotes; this call has none",
        ),
        (
            "and a replay under a memory checker, which judges no output, is accepted without one",
            _runner_choice_problem("ex00_bsq_memory", "//tools:bsq_check.sh", ["--bin", "x", "--valgrind", "v"]),
            None,
        ),
        (
            "a forbidden_symbols --globals call that quotes no sentence is refused",
            _runner_choice_problem("ex00_globals", "//tools:forbidden_symbols.sh", ["--globals", "--src", "x"]),
            "Pass exactly one of --quotes; this call has none",
        ),
        (
            "and a --function one",
            _runner_choice_problem("ex00_forbidden_functions", "//tools:forbidden_symbols.sh", ["--function", "f=", "--src", "x"]),
            "Pass exactly one of --quotes; this call has none",
        ),
        (
            "while its one-list mode, which quotes nothing, is not held to one",
            _runner_choice_problem("ex00_forbidden", "//tools:forbidden_symbols.sh", ["--allowed", "-", "--src", "x"]),
            None,
        ),
        (
            "and is refused one, which the runner would refuse when the test runs",
            _runner_choice_problem("ex00_forbidden", "//tools:forbidden_symbols.sh", ["--allowed", "-", "--quotes", "q", "--src", "x"]),
            "in its default mode, which quotes nothing",
        ),
        (
            "a prototype_check --no-restrict call that quotes no sentence is refused",
            _runner_choice_problem("ex00_prototype_restrict", "//tools:prototype_check.sh", ["--no-restrict", "--src", "x"]),
            "Pass exactly one of --quotes; this call has none",
        ),
        (
            "and a --declares one",
            _runner_choice_problem("ex00_declares_output", "//tools:prototype_check.sh", ["--declares", "--hdr", "x"]),
            "Pass exactly one of --quotes; this call has none",
        ),
        (
            "while its types mode, which quotes nothing, is not asked for one",
            _runner_choice_problem("ex00_prototype", "//tools:prototype_check.sh", ["--proto", "p", "--src", "x"]),
            None,
        ),
        (
            "and is refused one, which the runner would refuse when the test runs",
            _runner_choice_problem("ex00_prototype", "//tools:prototype_check.sh", ["--proto", "p", "--quotes", "q", "--src", "x"]),
            "in its default mode, which quotes nothing",
        ),
        (
            "an exit_quote with an ASCII apostrophe is accepted",
            _case_problem(dict(good, exit = 1, exit_quote = "the system's tool"), "program"),
            None,
        ),
        (
            "and reaches the runner quoted around it, as one argument",
            " ".join(_exit_flags({"exit": 1, "exit_quote": "the system's tool"}, 1)),
            "--exit-quote 'the system'\\''s tool'",
        ),
        (
            "an exit_quote with a dollar sign is accepted",
            _case_problem(dict(good, exit = 1, exit_quote = "echo $? says it"), "program"),
            None,
        ),
        (
            "and reaches the runner with its $ doubled, so it comes out of the expansion as itself",
            " ".join(_exit_flags({"exit": 1, "exit_quote": "echo $? says it"}, 1)),
            "--exit-quote 'echo $$? says it'",
        ),
        (
            "stderr_ignored() quotes a sentence with a '$' as one argument",
            _runner_choice_problem("ex00_argv_diff", "//tools:argv_check.sh", stderr_ignored("it's $HOME's")),
            None,
        ),
    ]
    return arms, _APOSTROPHE
