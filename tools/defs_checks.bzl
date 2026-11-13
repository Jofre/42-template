"""The checks the exercise macros compose: cases, models, and the static layers.

A program's cases (_case, _emit_cases, _CASE_KEYS), the reference model a case
is held to (_emit_model), and the layers that read a turn-in without running
it -- norm, forbidden, symbols, compile and prototype -- each declared by one
function the macros call. And the load-time checks of a call's memory and
allocation rules (allocfail_rule_problem, method_problem,
fixed_array_problem).

Loaded by the files above it, and re-exported by tools/defs.bzl, the one
file a BUILD file loads.
"""

load(
    ":defs_contract.bzl",
    _deliverable_hdrs = "deliverable_hdrs",
    _entry = "entry",
    _inc_args = "inc_args",
    _provided = "provided",
)
load(
    ":defs_levels.bzl",
    _LEVEL_NAMES = "LEVEL_NAMES",
    _SUFFIX_LAYER = "SUFFIX_LAYER",
    _call = "call",
    _is_unit_key = "is_unit_key",
    _key = "key",
    _layer_level = "layer_level",
    _memory_graded = "memory_graded",
    _prefix = "prefix",
    _uniq = "uniq",
)
load(
    ":defs_test.bzl",
    "runner_quotes",
    "shell_word",
    _test = "test",
    _waiting_args = "waiting_args",
)
load(
    ":defs_toolchain.bzl",
    _CAMPUS_CCS = "CAMPUS_CCS",
    _PINNED_CC_DATA = "PINNED_CC_DATA",
    _PINNED_NM_DATA = "PINNED_NM_DATA",
    _case_reads_tag = "case_reads_tag",
    _pinned_cc_args = "pinned_cc_args",
    _pinned_nm_args = "pinned_nm_args",
    _valgrind_args = "valgrind_args",
    _valgrind_data = "valgrind_data",
)

def _header_norm_test(num):
    """exNN_norm_header: the Norm's two header rules norminette skips, for exercise `num`.

    Emitted by c_levels() for every exercise of the contract that turns in a
    header -- one its `files` names, or any its `files` and `optional` let lie
    there (_deliverable_hdrs) -- so a project gets it from its contract, with
    no call of its own: C 08's and Reloaded's header exercises, C 12 and
    C 13's ft_list.h and ft_btree.h, a rush's or a Makefile project's own
    headers, and the Common Core's (WP-89, findings 089 and 093).
    tools/header_norm.sh says what it checks and why each verdict is built
    rather than read; it sits at strict, on the norm layer's suffix
    _norm_header, because norminette is what a grader runs and it raises
    neither.

    No test where nothing is turned in that the contract does not require: an
    exercise with no header to read is not one this rule has anything to say
    about. A header the contract requires and the turn-in lacks is a NOT
    TURNED IN test, gated (a SKIP but under NO_SKIP=1), as the norm layer's
    Notice twin is: the files and norm layers say it is missing already.
    """
    ex = _prefix(num)
    e = _entry(num, "turnin")
    named = [f for f in (e["files"] or []) if f.endswith(".h")]
    hdrs = _deliverable_hdrs(ex)
    if not hdrs and not named:
        return
    args = _pinned_cc_args()

    # Every turned-in header is READ, a subfolder's too, so none goes through
    # _inc_args(), which keeps one in a subfolder off the include path as the
    # grader's compile line does: that is the compile layers' question, and
    # tools/header_norm.sh says why its own path is generous.
    for h in hdrs:
        args += ["--header", "$(location %s)" % h]

    # What the turned-in headers may include besides each other: the
    # grader's. Their folders join the include path; they are never read.
    provided = _provided(num).hdrs
    for h in provided:
        args += ["--grader-hdr", "$(location %s)" % h]
    _test(
        name = ex + "_norm_header",
        srcs = ["//tools:header_norm.sh"],
        args = args,
        data = hdrs + provided + _PINNED_CC_DATA,
        tags = ["norm"],
        level = 2,
        turnin = hdrs,
        gated = True,
    )

def _norm_test(name, files, norm_flags = None, extra_tags = None, level = None):
    # `files` are the student's, as globs found them, so an empty list means
    # none was turned in: both targets become "not turned in" tests (see
    # _test's `turnin`) rather than norminette runs over nothing.
    # norm_flags injects extra `-R <rule>` tokens before the files, AFTER the
    # script's own -R CheckForbiddenSourceHeader. norminette keeps only the
    # last -R it is given, so a caller's -R replaces that one rather than
    # adding to it -- ["-R", "CheckDefine"] is how the c-08 headers get to
    # define function-like macros (ABS, EVEN), and the runner prints the rule
    # that took effect.
    # extra_tags is for exercises with optional parts (rush's bonus variants),
    # which pass ["manual"] to keep an unimplemented variant out of `//...`.
    # level raises this one above norm's level 1 -- used for files the student
    # neither wrote nor turns in, where a red is real but is OURS, not theirs.
    #
    # TWO TARGETS, one reading each. norminette prints "OK!" for a file whose
    # only findings are Notices and still exits 1 on them, and no subject says
    # which of the two a grader goes by. `name` holds the certain reading --
    # red on any file's Error!, a Notice only warned about -- at norm's own
    # level; `name`_notice holds the uncertain one, red on a Notice, raised to
    # strict, where a reading the subject leaves open belongs. Each is red for
    # one reason only, so a Norm Error never shows up twice.
    norm_flags = norm_flags or []
    args = norm_flags + ["$(location %s)" % f for f in files]
    _test(
        name = name,
        srcs = ["//tools:norminette_test.sh"],
        args = ["--norminette", "$(location //tools:norminette)"] + args,
        data = files + ["//tools:norminette"],
        tags = ["norm"] + (extra_tags or []),
        level = level,
        turnin = files,
    )
    _test(
        name = name + "_notice",
        srcs = ["//tools:norminette_test.sh"],
        args = ["--norminette", "$(location //tools:norminette)", "--notices-only"] + args,
        data = files + ["//tools:norminette"],
        tags = ["norm"] + (extra_tags or []),
        level = max(level or 0, 2),
        turnin = files,
        # The certain reading above already says the file is not there.
        gated = True,
    )

def _provided_names(provided_srcs):
    """The functions a grader-supplied source defines, by 42's convention.

    One function per file, named after it: tests/ft_putchar.c supplies
    ft_putchar. The forbidden and symbols layers use these names to tell a
    student who DEFINED a supplied function that the grader already does.
    """
    names = []
    for s in provided_srcs or []:
        base = s.split("/")[-1]
        if base.endswith(".c"):
            names.append(base[:-len(".c")])
    return names

def _forbidden_allowed_problem(name, allowed):
    """Why `allowed` cannot be a forbidden layer's allowlist, or None.

    [] is a subject's "Allowed functions: None" -- every call is the finding.
    None is a subject with no "Allowed functions" line at all, which forbids
    nothing, so it gets no forbidden layer: one built from it would authorise
    nothing and fail any call, a requirement the subject never wrote. Three
    call sites once passed `_allowed(num) or []` and did exactly that (V13), so
    the layer refuses None itself rather than trusting each caller's guard.

    Args:
        name: the forbidden test's name, for the sentence.
        allowed: the subject's list, or None.

    Returns:
        A sentence naming the problem, or None.
    """
    if allowed == None:
        return ("%s: the subject has no \"Allowed functions\" line (allowed = None), " +
                "and a forbidden layer would authorise nothing. Guard the call: " +
                "`if _allowed(num) != None:`, as every macro does.") % name
    return None

def _forbidden_test(name, srcs, allowed, hdrs = None, extra_tags = None, provided = None, turnin = None, inc_file = None):
    # turnin: the student files the layer reads; default `srcs`. c_header's
    # srcs is the harness's probe, and its turn-in is the header.
    # inc_file: the include directories a Makefile passes (see _compile_tests).
    # "-" sentinel: Bazel drops an empty-string arg, so an empty allowlist
    # ("only baseline builtins allowed") must be passed as a non-empty token.
    problem = _forbidden_allowed_problem(name, allowed)
    if problem:
        fail(problem)
    hdrs = hdrs or []
    allowed_csv = ",".join(allowed) if allowed else "-"
    args = _pinned_cc_args() + _pinned_nm_args() + ["--allowed", allowed_csv]
    for p in provided or []:
        args += ["--provided", p]
    args += _inc_args("--hdr", hdrs)
    if inc_file:
        args += ["--inc-file", "$(location %s)" % inc_file]
    for s in srcs:
        args += ["--src", "$(location %s)" % s]
    _test(
        name = name,
        srcs = ["//tools:forbidden_symbols.sh"],
        args = args,
        data = srcs + hdrs + _PINNED_CC_DATA + _PINNED_NM_DATA + ([inc_file] if inc_file else []),
        tags = ["forbidden"] + (extra_tags or []),
        turnin = srcs if turnin == None else turnin,
    )

def _forbidden_mode_test(name, srcs, hdrs, mode_args, data, level = None, inc_file = None):
    """forbidden_symbols.sh in one of its two other modes, --globals or --function.

    `mode_args` carries the mode, its --quotes and, for --function, the
    pinned objdump; `data` what they name. The sources, headers and a
    Makefile's include list (`inc_file`) are handed over as _forbidden_test
    hands them.
    """
    args = _pinned_cc_args() + _pinned_nm_args() + _inc_args("--hdr", hdrs)
    if inc_file:
        args += ["--inc-file", "$(location %s)" % inc_file]
    for s in srcs:
        args += ["--src", "$(location %s)" % s]
    _test(
        name = name,
        srcs = ["//tools:forbidden_symbols.sh"],
        args = args + mode_args,
        data = srcs + hdrs + _PINNED_CC_DATA + _PINNED_NM_DATA + data + ([inc_file] if inc_file else []),
        tags = ["forbidden"],
        turnin = srcs,
        level = level,
    )

def _symbols_test(name, srcs, exports, hdrs = None, extra_tags = None, functions_only = False, helpers_quote = None, inc_file = None):
    """Exactly `exports` may be visible to the linker; every helper is static.

    functions_only: compare the exported functions alone (symbols_test.sh
    --functions-only), where a variable has a test of its own (c_library's
    exNN_globals) that names it better than "make it static" would.

    helpers_quote: the subject's sentence keeping every helper static in its
    own file ("Project, p.N: \"...\""), or None. Given, the test runs with
    --no-cross, so a helper one file defines and another calls is reported
    like any other, and its red quotes the sentence (runner_quotes, key
    `helpers`). None keeps the default: such a helper may stay external, as
    two files a subject names must share one.

    inc_file: the include directories a Makefile passes (see _compile_tests).
    """
    hdrs = hdrs or []
    args = _pinned_cc_args() + _pinned_nm_args() + ["--expect", ",".join(exports)]
    data = []
    if inc_file:
        args += ["--inc-file", "$(location %s)" % inc_file]
        data.append(inc_file)
    if functions_only:
        args.append("--functions-only")
    if helpers_quote != None:
        args += ["--no-cross"] + runner_quotes(name + "_quotes", {"helpers": helpers_quote})
        data.append(":%s_quotes" % name)
    for s in srcs:
        args += ["--src", "$(location %s)" % s]
    args += _inc_args("--inc", hdrs)
    _test(
        name = name,
        srcs = ["//tools:symbols_test.sh"],
        args = args,
        data = srcs + hdrs + _PINNED_CC_DATA + _PINNED_NM_DATA + data,
        tags = ["symbols"] + (extra_tags or []),
        turnin = srcs,
    )

def _grader_hdr_args(grader_hdrs):
    """A runner's --grader-hdr for each header the grader brings, and --readme for the project's page.

    compile_check.sh and prototype_check.sh name such a header when a compile
    fails, with the -I a compile by hand needs (rl_grader_hdrs, finding 091):
    it lives under the project's tests/, where nobody looks for a file the
    subject says is provided. The project's README.md, where it has one, is
    named with it -- as text, never a dependency.
    """
    args = []
    for h in grader_hdrs or []:
        args += ["--grader-hdr", "$(location %s)" % h]
    if args and native.glob(["README.md"], allow_empty = True):
        pkg = native.package_name()
        args += ["--readme", pkg + "/README.md" if pkg else "README.md"]
    return args

def _compile_tests(ex, srcs, hdrs = None, extra_tags = None, turnin = None, inc_file = None, grader_hdrs = None):
    # turnin: the student files these compiles read; default `srcs`. c_header
    # compiles the harness's mains against a turned-in header, which is its
    # turn-in.
    #
    # THE INCLUDE PATH IS THE GRADER'S (see _inc_args): each source's own
    # folder, the headers beside the sources and the grader's -- and, for a
    # Makefile project, `inc_file`: the -I directories its recipes pass, as
    # `make -Bn` reported them to the build of its program (_student_bin's
    # includes_out). A header in a subfolder is staged, and on no path by
    # itself, so a turn-in the grader cannot compile does not pass here.
    hdrs = hdrs or []
    turnin = srcs if turnin == None else turnin
    common = []
    for s in srcs:
        common += ["--src", "$(location %s)" % s]
    common += _inc_args("--hdr", hdrs, staged = "--staged-hdr")
    common += _grader_hdr_args(grader_hdrs)
    if inc_file:
        common += ["--inc-file", "$(location %s)" % inc_file]
    for spec in _CAMPUS_CCS:
        args = ["--cc", spec["cc"]]
        for lib in spec["libs"]:
            args += ["--cc-lib", "$(location %s)" % lib]
        for lib in spec["progs_libs"]:
            args += ["--cc-progs-lib", "$(location %s)" % lib]
        if spec["under"]:
            args += ["--cc-under", "$(location %s)" % spec["under"]]
        if spec["progs"]:
            args += ["--cc-progs", "$(location %s)" % spec["progs"]]
        _test(
            name = "%s_compile_%s" % (ex, spec["label"]),
            srcs = ["//tools:compile_check.sh"],
            args = args + common,
            data = srcs + hdrs + spec["data"] + spec["libs"] + spec["progs_libs"] +
                   ([spec["progs"]] if spec["progs"] else []) + spec["progs_data"] +
                   ([inc_file] if inc_file else []),
            tags = ["compile"] + (extra_tags or []),
            turnin = turnin,
        )

# THE KEYS OF ONE CASE DICT, per shape, declared once and checked: a key
# outside its shape's set fails while loading, naming the case, instead of
# doing nothing. Before this, each macro's docstring said "an unrecognised key
# is silently ignored", and a key that worked in one macro was copied to its
# sibling where it did nothing -- `level` existed for c_header's cases and not
# for c_program's, so a program case the subject leaves open could not sit at
# strict and was left out instead (findings 115, 117, 123, 169). c_function's
# own case is its parameters; its `readings` are case dicts of their own shape.
#
# "exit", "exit_quote" and "invalid_input" place a case's exit status by the
# Run contract (docs/reference.md; _case_exit and _header_exit_error say how).
# A misspelling of one is the costliest kind: "invalid_inputs" for
# "invalid_input" quietly produced a robust _exit twin expecting 0 on an error
# input, whose failure told the student that 0 is right for a run that failed.
# So an unknown key close to a real one is named as the one it was meant to be.
_CASE_KEYS = {
    "header": ["args", "clues", "exit", "exit_quote", "labeled", "level", "main", "name", "stdin"],
    "program": ["args", "argv_file", "clues", "cwd_files", "exit", "exit_quote", "fixtures", "invalid_input", "labeled", "level", "missing_file", "name", "sanitize", "stdin", "stream", "valgrind"],
    "reading": ["clues", "escaped_values", "labeled", "level", "main", "name"],
}

# The keys a case of a shape cannot do without. A reading (c_function's
# `readings`) is a harness of its own, named, and never at basic: basic holds
# what every reading agrees on (D3).
_CASE_REQUIRED = {
    "reading": ["level", "main", "name"],
}

# WHAT A CASE COMPARES ITS RUN WITH -- its kind, exactly one of:
#   "expected": FILE     the output, byte for byte (under tests/exNN/)
#   "any_of": [FILE...]  one of several outputs, where the subject leaves the
#                        reading open and every reading is bounded (finding
#                        159: '0042' prints the number or Error, never
#                        "zero forty-two"); the report compares with the first
#   "survive": True      no output at all: the run ends by itself, killed by
#                        no signal, in time, without runaway output -- what
#                        every reading of an open case agrees on
_CASE_KINDS = ["any_of", "expected", "survive"]

# THE KEYS THAT SHAPE THE RUN ITSELF, beyond `args` and `stdin`. Each reaches
# every arm of the case -- output, its exit twin, asan, valgrind and the
# valgrind arm's gate -- because a case must run the same thing in each: a
# key only one runner honoured would test one program there and another
# everywhere else. So neither was taken until all three runners
# (diff_output.sh, asan_run.sh, valgrind_test.sh) could.
#
#   "argv_file": LABEL   more arguments, one per line of the file, after
#                        "args": an empty line is an empty argument. Bazel
#                        drops "" from `args` and splits on spaces, so
#                        `./rush-02 ref.dict ""` could not be a case
#                        (finding 157), nor could Rush 01's clue string
#                        without quotes embedded in it.
#   "cwd_files": {LABEL: NAME}  run the program as ./<its name> -- c_program's
#                        `name`, the subject's executable name -- from a
#                        folder holding only a copy of it and a copy of each
#                        LABEL as NAME. The subject's own transcript runs
#                        `./rush-02 42` beside numbers.dict (finding 162).
#                        Its "args" then name the staged files by NAME: a
#                        $(location) path does not resolve from that folder,
#                        and is refused.

# The keys that shape a comparison, which a survive case does not make.
_CASE_COMPARING = ["labeled", "sanitize", "stream"]

def _compare_flags(c, prefix = "--"):
    """A case's comparison keys (_CASE_COMPARING) as a runner's flags.

    diff_output.sh's own --stream NAME, --sanitize and --labeled, in that
    order; with prefix "--gate-", the same words for a gate that compares
    the case's output as its output test does. stream takes a value, the
    other two are flags.
    """
    flags = []
    if c.get("stream"):
        flags += [prefix + "stream", c["stream"]]
    if c.get("sanitize"):
        flags.append(prefix + "sanitize")
    if c.get("labeled"):
        flags.append(prefix + "labeled")
    return flags

def _case_problem(c, shape, program = None):
    """What is wrong with one case dict of `shape`, as a message; None if nothing.

    A value before it is a fail(), like the contract checks, so the fixtures
    can feed it broken cases (contract_problem("case", ...)). `program` is
    c_program's `name`, the file a "cwd_files" case runs the program as, so
    no staged file may take it; None where there is none to check against.
    """
    if type(c) != "dict":
        return "a case is a dict, not a %s" % type(c)
    keys = _CASE_KEYS[shape]
    for k in sorted(c):
        if k not in keys and k not in _CASE_KINDS:
            near = [n for n in keys + _CASE_KINDS if _key_stem(n) == _key_stem(k)]
            if near:
                return ("%r is not a key of a %s case: did you mean %r? An unknown key " +
                        "used to be ignored in silence.") % (k, shape, near[0])
            return ("%r is not a key of a %s case. Its keys: %s; and one of %s." %
                    (k, shape, ", ".join(keys), ", ".join(_CASE_KINDS)))
    for k in _CASE_REQUIRED.get(shape, []):
        if k not in c:
            return "a %s case needs %r: its keys are %s, and %s are required." % (
                shape,
                k,
                ", ".join(keys),
                ", ".join(_CASE_REQUIRED[shape]),
            )
    if "name" in c and (type(c["name"]) != "string" or not c["name"] or
                        " " in c["name"] or "\t" in c["name"]):
        return ("\"name\" is one word: it becomes part of a target name, and a " +
                "space there fails at run time as \"command not found\".")
    kinds = [k for k in _CASE_KINDS if k in c]
    if len(kinds) != 1:
        return ("a case compares its run one way: exactly one of %s, and it has %s." %
                (", ".join(_CASE_KINDS), ", ".join(kinds) or "none"))
    if "expected" in c and type(c["expected"]) != "string":
        return "\"expected\" is one file name under tests/exNN/; for several, \"any_of\"."
    if "any_of" in c:
        a = c["any_of"]
        if type(a) != "list" or len(a) < 2 or [f for f in a if type(f) != "string"]:
            return "\"any_of\" is a list of two or more file names under tests/exNN/."
    if "survive" in c:
        if c["survive"] != True:
            return "\"survive\" is True or absent."
        for k in _CASE_COMPARING:
            if k in c:
                return "%r shapes a comparison, and a survive case compares no output." % k
    if "level" in c and (type(c["level"]) != "int" or c["level"] < 2 or c["level"] > len(_LEVEL_NAMES)):
        return ("\"level\" raises a case to %s: 2 to %d. A case at basic needs none." %
                (", ".join(_LEVEL_NAMES[1:]), len(_LEVEL_NAMES)))
    # "valgrind" is the label a clues.tsv row takes to fire in the memory arms
    # (valgrind_test.sh hands its runner the case's name AND "valgrind" as
    # what failed), so a case of that name would take every such row into its
    # output test, and its own rows into every other case's memory arm.
    if shape == "program" and c.get("name") == "valgrind":
        return ("a case is not named \"valgrind\": a clues.tsv row keyed to " +
                "\"valgrind\" fires in every case's memory arm, so its rows would " +
                "fire there too. Name the case after the input it runs.")
    if "exit" in c and (type(c["exit"]) != "int" or c["exit"] < 0 or c["exit"] > 255):
        return "\"exit\" is a status, as an int from 0 to 255."
    if "exit_quote" in c and type(c["exit_quote"]) != "string":
        return ("\"exit_quote\" is the subject's sentence, as a string (an apostrophe " +
                "or a '$' is fine: _exit_flags quotes it, shell_word).")
    if "exit_quote" in c and "exit" not in c:
        return ("\"exit_quote\" is the subject's sentence naming the status in " +
                "\"exit\", and this case has no \"exit\".")

    # A quoted status sits at one of two levels, each with its own wording in
    # the runner (_exit_source): basic, where the sentence names the status,
    # and strict, where it is only READ as naming it -- the Run contract's row
    # for a sentence the subject leaves ambiguous. A quote raised to robust or
    # complete would be reported as "checked at strict" from a level that is
    # not, and a status a sentence names outright is never raised.
    if "exit_quote" in c and c.get("level") not in (None, 2):
        return ("\"exit_quote\" with \"level\": %r. A status the subject's sentence " +
                "names is compared at basic (no \"level\"); one the sentence is only " +
                "read as naming, at strict (\"level\": 2). No other level takes a " +
                "quote: a status that is this repo's rule has none (docs/reference.md, " +
                "\"Run contract\").") % c.get("level")
    if "invalid_input" in c and type(c["invalid_input"]) != "bool":
        return "\"invalid_input\" is True or False."
    for k in ["args", "fixtures"]:
        if k in c and (type(c[k]) != "list" or [a for a in c[k] if type(a) != "string"]):
            return "%r is a list of strings." % k

    # AN ARGUMENT BAZEL DOES NOT HAND OVER WHOLE. A test's `args` are
    # tokenised as a shell would tokenise them: a blank splits one, a quote or
    # a backslash is read as shell syntax, and "" is dropped. Rush 01's clue
    # string was held together by quotes embedded in a Starlark string, with
    # a target of its own to prove Bazel kept them (ex00_argv_guard); an
    # argument file says it with no shell in between. A $(location ...) is
    # Bazel's own, and expands to one word.
    for a in c.get("args", []):
        bare = a
        for _ in range(len(a)):
            at = bare.find("$(")
            end = bare.find(")", at) if at >= 0 else -1
            if end < 0:
                break
            bare = bare[:at] + bare[end + 1:]
        if not a or [ch for ch in [" ", "\t", "\n", "'", "\"", "\\"] if ch in bare]:
            return (("\"args\" holds %r, which Bazel does not hand the program as one " +
                     "argument: it tokenises `args` as a shell would, splitting at a " +
                     "blank, reading a quote or a backslash, dropping an empty one. " +
                     "Put the run's arguments in \"argv_file\", one per line.") % a)
    if "argv_file" in c and (type(c["argv_file"]) != "string" or not c["argv_file"]):
        return ("\"argv_file\" is the label of a file under the package, one argument " +
                "per line.")
    if "cwd_files" in c:
        cw = c["cwd_files"]
        if type(cw) != "dict" or not cw:
            return ("\"cwd_files\" is {label: name}: the files the run folder holds " +
                    "beside the program, each under the name the program opens it by.")
        names = {}
        for src, dest in cw.items():
            if type(src) != "string" or type(dest) != "string" or not src or not dest:
                return "\"cwd_files\" maps a label to a name, both strings."
            # Every part of the path a name: "." would copy the file in under
            # its own name, not this one, and "" is a leading, doubled or
            # trailing slash.
            if ([p for p in dest.split("/") if p in ["", ".", ".."]] or "=" in dest or
                [ch for ch in [" ", "\t", "'", "\""] if ch in dest]):
                return ("\"cwd_files\": %r is not a name inside the run folder (no " +
                        "leading or trailing /, no . or .. part, no =, no space or " +
                        "quote: Bazel splits `args` on them).") % dest
            # The folder holds the program under its own name, ./<name>: a file
            # staged there too, or under a folder of that name, was refused only
            # when the case ran (runner_lib.sh's rl_rundir, exit 2).
            if program and (dest == program or dest.startswith(program + "/")):
                return ("\"cwd_files\": %r is where the run folder holds the program " +
                        "itself, which runs as ./%s: stage the file under the name " +
                        "the program opens it by.") % (dest, program)
            if dest in names:
                return "\"cwd_files\": two files are staged as %r." % dest
            names[dest] = True
        for a in c.get("args", []):
            if "$(location" in a or "$(rootpath" in a or "$(execpath" in a:
                return (("\"args\" holds %r, a path from where Bazel runs the test, " +
                         "and a \"cwd_files\" case runs from its own folder, where " +
                         "that path is not. Stage the file in \"cwd_files\" and name " +
                         "it by its name there.") % a)
    if "missing_file" in c:
        return _missing_file_key_problem(c)
    return None

def _missing_file_key_problem(c):
    """Why a case's "missing_file" names no operand that could be one; None if it does.

    The key says this run hands the program a name that will not open, and
    names it. So it is one of the case's "args", word for word; it is not a
    fixture ($(location ...) names a file that is there), not an option or
    "-" (which a tool reads as standard input), and not "." or ".." (which
    are there: a directory). Whether it is absent where the program runs is
    asked at run time (diff_output.sh --absent).
    """
    m = c["missing_file"]
    if type(m) != "string" or not m:
        return "\"missing_file\" is the operand, from \"args\", that names no file."
    if m not in c.get("args", []):
        return ("\"missing_file\" is %r, and the case's \"args\" do not hold it: it " +
                "names the operand that will not open, word for word.") % m
    if "$(" in m:
        return ("\"missing_file\" is %r, a fixture Bazel stages: a file that is " +
                "there. Name an operand no file has, as no_such_file_exNN.") % m
    if m.startswith("-") or m in (".", ".."):
        return ("\"missing_file\" is %r, which a program reads as an option, as " +
                "standard input or as a directory that is there. Name an operand " +
                "no file has, as no_such_file_exNN.") % m
    cw = c.get("cwd_files")
    if type(cw) == "dict" and [d for d in cw.values() if d == m or (type(d) == "string" and d.startswith(m + "/"))]:
        return ("\"missing_file\" is %r, and \"cwd_files\" stages a file there: the run " +
                "folder holds it. Name an operand no file has, as no_such_file_exNN.") % m
    return None

def _case_refusal(c, shape, where, program = None):
    """What _case would fail with for one case dict, as a value; None if nothing.

    `where` names the call and the case's name follows it ("?" where the
    case is no dict), then _case_problem's message.
    """
    problem = _case_problem(c, shape, program)
    if not problem:
        return None
    name = c.get("name", "run") if type(c) == "dict" else "?"
    return "%s, case %r: %s" % (where, name, problem)

def _cases_problem(cases, shape, where, program = None):
    """The first of `cases` that _case would refuse, as its message; None where every one is a case.

    For a macro whose own checks read its cases before it declares
    anything (c_program): run before them, through _refuse, a case that is
    no dict gets _case's message, which names the call, where those checks
    would have stopped on a Starlark error that names nothing. And a
    fixture can watch it.
    """
    for c in cases or []:
        problem = _case_refusal(c, shape, where, program)
        if problem:
            return problem
    return None

def _case(c, shape, where, program = None):
    """One case dict of `shape`, checked: fail()s naming `where` and the case.

    `program` is c_program's `name` (see _case_problem). Returns a struct:
    `name` (default "run"), `expected` (the file names to compare with, the
    first one reported; empty for a survive case), `survive`, `level` (None
    at the layer's own).
    """
    problem = _case_refusal(c, shape, where, program)
    if problem:
        fail(problem)
    return struct(
        name = c.get("name", "run"),
        expected = [c["expected"]] if "expected" in c else c.get("any_of", []),
        survive = c.get("survive", False),
        level = c.get("level"),
    )

def _raise(layer, level):
    """A case's level for one of its arms: `level` where it is above the arm's layer, else None.

    A case's level is a floor for every arm it emits: a case the subject
    leaves open is no more certain under a sanitizer. An arm whose layer
    already sits at or above it stays where it is -- where this package
    puts the layer (_layer_level): a reading's valgrind arm stays at the
    reading's level in a project whose contract lowers the layer.
    """
    if level != None and level > _layer_level(layer, bool(_memory_graded())):
        return level
    return None

def _expected_args(ex, k, flag = "--expected", alt = "--expected-alt", survive = "--survive", tdir = None):
    """A checked case's comparison, as a runner's flags and the files they need.

    `tdir` is the folder the files are under, default tests/<ex>/: a
    function of a library's is tests/<function>/ (see _member).
    """
    if k.survive:
        return ([survive] if survive else []), []
    files = ["%s/%s" % (tdir or "tests/" + ex, f) for f in k.expected]
    args = [flag, "$(location %s)" % files[0]]
    for f in files[1:]:
        args += [alt, "$(location %s)" % f]
    return args, files

def _case_stem(ex, cases, cname):
    """Target stem for one argv scenario: `exNN`, or `exNN_<case>` when several.

    A lone scenario takes the plain name every other exercise in the repo uses.
    The infix earns its place only when there is more than one scenario to tell
    apart -- c-10 ex03 and c-11 ex05 each run a score of them, where naming
    them is the whole point. Before this rule the only infixed-but-single
    targets anywhere were c-08's ex00_compile_output, ex02_run_output and
    ex03_compile_output, which made the one module a student meets a header
    exercise in look as though it followed different conventions from the rest
    of the repo.

    It lives here because THREE loops emit per-case targets and they have to
    agree: _emit_cases() runs a prebuilt program through diff_output.sh,
    c_program() emits its own asan targets beside it, and c_header() builds no
    program on purpose (see its comment) and compiles inside header_check.sh.
    Three runners, one naming rule -- and the naming is exactly what drifted
    while each kept its own copy of it.
    """
    if len(cases) == 1:
        return ex

    # A case name becomes part of a TARGET name, so it has to be one word. A
    # space produces `//pkg:ex00_a one-cell map_output`, which Bazel accepts at
    # analysis and which then fails at run time with "Exit 127: command not
    # found" -- the test-setup script splits on the space and tries to execute
    # the first half. That is a wrong-looking failure a long way from its cause,
    # so it is caught here instead, where the name is written.
    if " " in cname or "\t" in cname:
        fail(("c_program/%s: case name %r must be one word -- it becomes part " +
              "of a target name, and a space there fails at run time as " +
              "\"command not found\" rather than at analysis.") % (ex, cname))
    return "%s_%s" % (ex, cname)

def _key_stem(k):
    """A key with case, '-', '_' and a plural 's' taken away, for "did you mean"."""
    k = k.lower().replace("-", "").replace("_", "")
    return k[:-1] if k.endswith("s") else k

def _missing_file_problem(ex, allowed, cases, why):
    """None, or why a c_program that may open files has no case naming one that will not open.

    `allowed` is the exercise's forbidden-layer list (None: no list), `cases`
    its case dicts (None: its runs are driven elsewhere, as c_argv_table
    does), `why` its no_missing_file_case sentence.

    THE PATH ITSELF, NOT ANY ERROR. A program that opens files meets a name
    that will not open, and a case list written from a subject's example
    transcript never hands it one. This guard first asked only for SOME error
    case, and that let the shape through: BSQ held five invalid maps and Rush
    02 four broken dictionaries, every one a file that opens, and neither
    list named a file that does not exist (finding 110; review of WP-50). A
    name a case marks "missing_file" is that path, said, and checked: it is
    one of the case's operands (_missing_file_key_problem) and nothing by
    that name is there when the program runs (diff_output.sh --absent).
    """
    if why != None and (type(why) != "string" or not why.strip()):
        return "c_program(%s): no_missing_file_case is a sentence saying why." % ex
    if cases == None or not allowed or "open" not in allowed:
        if why != None:
            return (("c_program(%s): no_missing_file_case says why no case names a " +
                     "file that will not open, and nothing asks for one: the contract " +
                     "does not allow open%s. Drop the sentence.") %
                    (ex, "" if cases != None else ", or the runs are driven elsewhere"))
        return None
    named = [c.get("name", "run") for c in cases if type(c) == "dict" and "missing_file" in c]
    if named and why != None:
        return (("c_program(%s): no_missing_file_case says no case names a file that " +
                 "will not open, and %s does. Drop the sentence: a reason that is no " +
                 "longer true is worse than none.") % (ex, ", ".join(named)))
    if not named and why == None:
        return (("c_program(%s): the contract allows open, and no case names a file " +
                 "that will not open. A program that opens files meets one, and a case " +
                 "list copied from the subject's transcript never hands it one; a case " +
                 "about a file's CONTENT is not that path. Add a case whose \"args\" " +
                 "hold a name no file has (no_such_file_%s), say so in " +
                 "\"missing_file\", and judge it where the Run contract puts it " +
                 "(docs/reference.md, \"A program that reads files\"); or say why " +
                 "there is none in no_missing_file_case.") % (ex, ex))
    return None

def _makefile_problem(ex, makefile, files):
    """Why c_program may not build exercise `ex` without its Makefile; None if it may.

    A subject() contract that has the exercise turn in a Makefile says the
    Makefile is how the program is built. makefile = False builds every .c
    of the folder with no -I instead: a header kept in a subfolder the
    Makefile reaches with -I does not compile, and a .c it never compiles is
    linked. C 10, C 11 ex05 and Reloaded ex27 were each declared that way and
    each fixed by hand (W5-F); the next Makefile project is refused here.
    """
    if makefile == False and "Makefile" in (files or []):
        return ("c_program(%s): makefile = False, and the subject() contract has %s " +
                "turn in a Makefile, which is how the subject builds the program: " +
                "built from every .c of the folder with no -I, a header in a " +
                "subfolder the Makefile reaches with -I does not compile, and a .c " +
                "it never compiles is linked. Pass makefile = True, or " +
                "\"once_written\" to build the folder's sources until the Makefile " +
                "compiles something (C 10's programs).") % (ex, ex)
    return None

def _model_problem(ex, model, cases):
    """None, or why a c_program's `model` cannot be held to its cases' files.

    `model` is the //oracle command a case's "args" follow, as words; each
    case with one expected file then gets exNN[_case]_model (_emit_model).
    THE FILES A MODEL MADE DRIFT FROM IT IN SILENCE otherwise: C 10's were made
    once by `oracle c10_run` and checked against the tools then, and nothing
    re-ran it, so a later fix to the model, or a fixture edited by hand,
    would first show as a correct program going red (review of WP-50).
    """
    if model == None:
        return None
    if (type(model) != "list" or not model or
        [w for w in model if type(w) != "string" or not w or " " in w or "$" in w or "'" in w]):
        return (("c_program(%s): model is the //oracle command whose answers the " +
                 "cases' expected files are, as a list of words with no blank, " +
                 "quote or '$' (C 10 ex01: [\"c10_run\", \"--prog\", \"ex01_bin\", " +
                 "\"cat\"]); each case's \"args\" follow it. It is %r.") % (ex, model))
    if not cases:
        return (("c_program(%s): model says which //oracle command made the cases' " +
                 "expected files, and there are no cases.") % ex)
    named = [c.get("name", "run") for c in cases if type(c) == "dict" and c.get("sanitize")]
    if named:
        return (("c_program(%s): model, and case %r compares a sanitized output: its " +
                 "file is the output with its address column rewritten, which no " +
                 "run answers. Hold that exercise's files to a model some other " +
                 "way, or take model off.") % (ex, named[0]))
    if not [c for c in cases if type(c) == "dict" and "expected" in c]:
        return (("c_program(%s): model, and no case has one expected file for it to " +
                 "answer (an \"any_of\" or \"survive\" case compares none that one " +
                 "run makes). Take model off.") % ex)
    return None

def _reference_exit_problem(ex, reference, cases):
    """None, or why a c_program(reference = True) case is one its reference cannot pass.

    The reference's contract is its status: 0 is an answer, any other
    status says it has no answer for the run (tools/reference_cases.sh, NO
    ANSWER). A case whose output test compares a status other than 0
    (_case_exit's basic value: the subject names it, or a quoted sentence is
    read as naming it) asks the reference for a status it cannot give with
    an answer: the reference fails it with an answer, and with none it is
    reported as a run it has no answer for -- the case's fault, said of a
    case that may be right. A survive case is no way out: it asks for no
    answer, and a status the reference gives for having none says nothing
    of the one the subject names.
    """
    if reference != True or type(cases) != "list":
        return None
    for c in cases:
        if type(c) != "dict" or _case_exit_error(ex, c):
            continue
        basic_exit, _ = _case_exit(ex, c)
        if basic_exit != None and basic_exit != 0:
            return (("c_program(%s): reference = True, and case %r has its output test " +
                     "compare the status %d. The reference answers a run with " +
                     "status 0 and says it has no answer with any other " +
                     "(tools/reference_cases.sh), so no status but 0 can be held to " +
                     "it: the case would fail with a correct answer. Take reference " +
                     "off, or give //oracle's reference programs a way to say they " +
                     "have no answer that no status of a program collides with.") %
                    (ex, c.get("name", "run"), basic_exit))
    return None

def _argv_model_problem(ex, model, no_model):
    """None, or why c_argv_table's table is not held to a model, or not said why.

    A table.txt is emitted once with `argv_table.sh --emit` from a reference
    program, and C 06's three and Reloaded's two were then held to nothing:
    an edited row, or a scenario changed without its row, would first show
    as a correct program going red. So a call names the //oracle command the
    table is (`model`, which exNN_model holds it to), or says why there is
    none (`no_model`).
    """
    if model == None and no_model == None:
        return (("c_argv_table(%s): the table was emitted from a reference program, " +
                 "and nothing holds it to one. Name the //oracle command it is, as " +
                 "model (C 06 ex01: [\"c06_run\", \"print\"]), and %s_model holds the " +
                 "committed table to what that command makes; or say why there is none " +
                 "in no_model.") % (ex, ex))
    if model != None and no_model != None:
        return (("c_argv_table(%s): model and no_model, and they say opposite things: " +
                 "keep the one that is true.") % ex)
    if no_model != None:
        if type(no_model) != "string" or not no_model.strip():
            return (("c_argv_table(%s): no_model is a sentence saying why no //oracle " +
                     "command made the table; it is %r.") % (ex, no_model))
        return None
    if (type(model) != "list" or not model or
        [w for w in model if type(w) != "string" or not w or " " in w or "$" in w or "'" in w]):
        return (("c_argv_table(%s): model is the //oracle command the table was " +
                 "emitted from, as a list of words with no blank, quote or '$' (C 06 " +
                 "ex01: [\"c06_run\", \"print\"]). It is %r.") % (ex, model))
    return None

def _emit_model(ex, cases, model, prog):
    """exNN[_case]_model for each case of `cases` with one expected file.

    tools/model_check.sh runs `oracle <model> <the case's args>` from where
    the case's program runs, with its standard input and the name it says
    will not open, and compares the stream the case compares, byte for byte,
    and the status the case names in "exit". Layer oracle, complete: it runs
    nothing of the student's and is green on every turn-in; red, it says a
    fixture and the model it came from have parted. The run is the case's
    own, from _case_run like every arm's (`prog` is c_program's `name`): its
    standard input, its argument file, and its run folder, where the model
    runs as ./<prog> beside the case's files.
    """
    for c in cases:
        if "expected" not in c:
            continue
        k = _case(c, "program", "c_program(%s)" % _call(_key(ex)))
        stem = _case_stem(ex, cases, k.name)
        expected = "tests/%s/%s" % (ex, c["expected"])
        args = [
            "--oracle",
            "$(location //oracle:oracle)",
            "--expected",
            "$(location %s)" % expected,
        ]
        run_flags, run_files = _case_run(c, prog)
        data = _uniq(["//oracle:oracle", expected] + run_files)
        if c.get("stream"):
            args += ["--stream", c["stream"]]
        args += run_flags
        if "exit" in c:
            args += ["--exit", str(c["exit"])]
        if c.get("missing_file"):
            args += ["--absent", c["missing_file"]]
        _test(
            name = "%s_model" % stem,
            srcs = ["//tools:model_check.sh"],
            args = args + ["--"] + model + c.get("args", []),
            data = data,
            tags = ["oracle"],
        )

def _case_exit_error(ex, c):
    """None, or why a c_program case's exit keys are malformed (see _case_exit)."""
    if c.get("exit_quote") != None and "exit" not in c:
        return (("c_program(%s): case %r has exit_quote but no exit -- the quote " +
                 "is the subject's sentence naming the status in \"exit\".") %
                (ex, c.get("name", "run")))
    if "exit" in c:
        code = c["exit"]
        if type(code) != "int" or code < 0 or code > 255:
            return ("c_program(%s): case %r: exit must be an int from 0 to 255, not %r" %
                    (ex, c.get("name", "run"), code))
    if "invalid_input" in c and type(c["invalid_input"]) != "bool":
        return ("c_program(%s): case %r: invalid_input is True or False, not %r" %
                (ex, c.get("name", "run"), c["invalid_input"]))

    # A name that will not open is an error path for every program that opens
    # one, so a case handing it one says what the status after it means, as a
    # stderr case does: a default twin would demand 0 from cat's 1.
    if ("missing_file" in c and "exit" not in c and "invalid_input" not in c and
        "any_of" not in c and "survive" not in c):
        return (("c_program(%s): case %r names a file that will not open " +
                 "(\"missing_file\") and does not say what its exit status means. " +
                 "Give it \"invalid_input\": True where the subject answers it with " +
                 "an error message, \"exit\" where a status is named or read, or " +
                 "\"invalid_input\": False where the subject calls it no error " +
                 "(docs/reference.md, \"Writing a c_program case\").") %
                (ex, c.get("name", "run")))

    # A case that compares stderr is almost always an error message, and one
    # that states nothing gets a twin expecting 0 from it. Every such case in
    # the repo was marked by hand, and nothing asked for the mark (review of
    # wave 3), so the next project's first unmarked "Error" would fail a
    # correct program at robust and call 0 the C convention. The same default
    # on stdout is caught at run time: the twin is told it is a default
    # (--exit-source default), and diff_output.sh refuses it when the expected
    # output mentions an error.
    # An "any_of" or "survive" case gets no twin (_case_exit), so it has no
    # default to state.
    if (c.get("stream") == "stderr" and "exit" not in c and "invalid_input" not in c and
        "any_of" not in c and "survive" not in c):
        return (("c_program(%s): case %r compares stderr and does not say what " +
                 "its exit status means. Give it \"invalid_input\": True if the " +
                 "subject answers this input with an error message (no level then " +
                 "judges the status), \"invalid_input\": False if it does not (a " +
                 "robust twin then expects 0), or \"exit\" (docs/reference.md, " +
                 "\"Writing a c_program case\").") % (ex, c.get("name", "run")))
    return None

def _case_exit(ex, c):
    """Where one c_program case's exit status is judged, by the Run contract.

    docs/reference.md ("Run contract"): a status the subject names is compared
    at basic; a non-zero exit where it names none fails only at robust. Returns
    (basic, robust): the status exNN_<case>_output compares, and the one its
    robust twin exNN_<case>_exit compares; None where that target judges none.

      "exit" + "exit_quote"  the subject names it: (N, None). With "level" 2,
                             the sentence is READ as naming it (C 10's
                             "performs the same function as the system's
                             tail": the tool's own status), so the case's
                             output test compares it at strict and says it
                             is a reading (_exit_source)
      "exit" alone           this repo's rule:     (None, N)
      "invalid_input": True  and no "exit": an input the subject answers with
                             an error message it names, where a non-zero
                             status is what an error conventionally returns:
                             (None, None)
      "any_of" or "survive"  and no "exit": a case whose reading the subject
                             leaves open (_CASE_KINDS), where one reading may
                             be an error and another not, so no status is
                             conventional: (None, None)
      "invalid_input": False the C convention, stated: (None, 0)
      neither                the C convention, by default: (None, 0). Refused
                             for a case that compares stderr or names a file
                             that will not open (_case_exit_error), and its
                             twin refuses to run when the expected
                             output mentions an error (--exit-source default):
                             a default is not a decision there.

    How the program ended is read from waitpid() (tools/exit_status), so a
    `return (-1);` is the status 255, never mistaken for a signal.
    """
    err = _case_exit_error(ex, c)
    if err:
        fail(err)
    if "exit" in c:
        if c.get("exit_quote"):
            return (c["exit"], None)
        return (None, c["exit"])
    if c.get("invalid_input") or "any_of" in c or "survive" in c:
        return (None, None)
    return (None, 0)

def _exit_source(c):
    """Whose rule a case's "exit" is, as diff_output.sh's --exit-source.

    "subject" where the subject names the status ("exit_quote", at basic);
    "reading" where the quoted sentence is read as naming it, which the Run
    contract checks at strict ("exit_quote" and "level" 2; _case_problem
    refuses a quote at any other raised level, so the runner's "checked at
    strict" is always true); "convention" where no sentence is quoted and the
    status is this repo's rule.
    """
    if not c.get("exit_quote"):
        return "convention"
    if c.get("level") == 2:
        return "reading"
    return "subject"

def _exit_flags(c, code):
    """The diff_output.sh flags that judge a case's "exit" of `code` in its output test."""
    flags = ["--exit", str(code), "--exit-source", _exit_source(c)]
    if c.get("exit_quote"):
        flags += ["--exit-quote", shell_word(c["exit_quote"])]
    return flags

def _header_exit_error(ex, c):
    """None, or why a c_header case's exit is checked below where it may be.

    By the Run contract (docs/reference.md), a status the subject does not name
    is this repo's rule and is checked at robust at the lowest: a case with
    "exit" and no "exit_quote" must carry "level" 3 or 4.
    """
    if c.get("exit") == None or c.get("exit_quote"):
        return None
    if (c.get("level") or 1) < 3:
        return (("c_header(%s): case %r asserts exit %r with no exit_quote. " +
                 "A status the subject does not name is this repo's rule, and " +
                 "the Run contract (docs/reference.md) checks one at robust: " +
                 "give the case \"level\": 3, or quote the subject's sentence " +
                 "in \"exit_quote\".") % (ex, c.get("name", "run"), c["exit"]))
    return None

# A value of the right type for every case key, for the "every documented key
# is accepted" arm of starlark_selftest_arms(); a key not listed takes a
# string.
# "missing_file" names an operand of "args", as it must.
# "level" is 2, the one raised level an "exit_quote" goes with (a reading).
_GOOD_VALUE = {
    "args": ["no_such_file_ex00"],
    "cwd_files": {"a.dict": "a"},
    "exit": 0,
    "fixtures": [],
    "invalid_input": False,
    "labeled": True,
    "level": 2,
    "missing_file": "no_such_file_ex00",
    "sanitize": True,
    "valgrind": True,
}

# A sentence //tools/tests:starlark_unit hands its script through shell_word,
# which must arrive as this one argument, its script holding the same words:
# the apostrophes and '$' of a subject's sentence, and the double quotes and
# backslash an awk expression (c_cycles' unit_expr) can hold.
_APOSTROPHE = "the system's tail, as the subject's sentence prints it: $? and $(x) too, $1 == \"\" and \\ as well"


def _survive_gate(ex, cases):
    """diff_output.sh's --gate-* flags for a survive case of `cases`, and the files they name.

    The gate is the exercise's first case at basic with one expected file
    and plain arguments (no blank but a $(location ...)'s, no quote, no
    empty one: Bazel's tokenising of `args` would not hand those over as
    one --gate-arg each), run where the test runs: no "argv_file" or
    "cwd_files", which the gate's flags do not carry -- Rush 02's first case
    runs `./rush-02 42` from a folder holding numbers.dict, and gated on it
    from anywhere else its survive cases would never run: while its
    output is red, a survive case SKIPs. A survive case asks only that the
    program ends by itself, which an unwritten one does: do-op's stub was
    green on INT_MIN / -1 at strict (review of WP-52). No such case: no gate,
    and the survive case runs as it is. NO_SKIP=1 runs it always.
    """
    for g in cases:
        if "expected" not in g or g.get("level") or g.get("argv_file") or g.get("cwd_files"):
            continue
        plain = [a.replace("$(location ", "$(location_") for a in g.get("args", [])]
        if [a for a in plain if not a or " " in a or "\t" in a or "'" in a or '"' in a]:
            continue
        gk = _case(g, "program", "c_program(%s)" % _call(_key(ex)))
        f = "tests/%s/%s" % (ex, g["expected"])
        args = [
            "--gate-expected",
            "$(location %s)" % f,
            "--gate-label",
            "%s_output" % _case_stem(ex, cases, gk.name),
        ]
        data = [f] + g.get("fixtures", [])
        args += _compare_flags(g, "--gate-")
        if g.get("stdin"):
            args += ["--gate-stdin", "$(location %s)" % g["stdin"]]
            data.append(g["stdin"])
        for a in g.get("args", []):
            args += ["--gate-arg", a]
        return args, data
    return [], []

def _survive_gate_prefix(binname, sgate, survive_flag = True):
    """A survive case's gate as a memory runner takes it, _survive_gate's flags behind its head.

    --gate-differ and --gate-bin, the program's own :binname, then `sgate`;
    with `survive_flag`, --survive first, which tells valgrind_test.sh and
    allocfail_check.sh that the case compares no output. asan_run.sh takes
    no --survive: it compares none anyway.

    Returns:
        (args, data): those options, and what the head names: the program
        and diff_output.sh. The files `sgate` names are _survive_gate's
        data, which the caller adds.
    """
    return (["--survive"] if survive_flag else []) + [
        "--gate-differ",
        "$(location //tools:diff_output.sh)",
        "--gate-bin",
        "$(location :%s)" % binname,
    ] + sgate, [":" + binname, "//tools:diff_output.sh"]

def _memory_gate(ex, cases, c, k, binname, survive):
    """(args, data, waits): the gate of one case's valgrind arm or allocation-failure sweep.

    A case with an expected file waits for its own output test: the gate
    runs the program on the case, as that test does -- its expected file(s),
    how it compares (_compare_flags) and its standard input. The runner
    hands its gate the argument file and the run folder itself. A survive
    case has no fixture of its own: it waits on the case its output test
    waits on, `survive`, which is c_program's (_survive_gate), handed over
    whole after --survive. No gate: ([], [], None), and the arm runs
    ungated. The gate's options go with it, never alone: a gate's options
    with no gate are a wiring mistake its runner refuses.

    Args:
        ex: "exNN".
        cases: c_program's cases, which name the case's output test.
        c: the case dict.
        k: _case(c, ...).
        binname: the program the gate runs, :binname.
        survive: (args, data), _survive_gate(ex, cases), or ([], []).

    Returns:
        (args, data, waits): the --gate-* options; what they name (the
        program, diff_output.sh, the fixture and stdin, as _fixture_gate's
        data does); the output test the arm waits for, or None.
    """
    if k.survive:
        sgate, sdata = survive
        if not sgate:
            return [], [], None
        args, data = _survive_gate_prefix(binname, sgate)
        return args, data + sdata, None
    gate, gate_fs = _expected_args(ex, k, "--gate-expected", "--gate-expected-alt", None)
    if not gate:
        return [], [], None
    stem = _case_stem(ex, cases, k.name)
    args = [
        "--gate-differ",
        "$(location //tools:diff_output.sh)",
        "--gate-bin",
        "$(location :%s)" % binname,
        # Its SKIP line names the test it waits for.
        "--gate-label",
        "%s_output" % stem,
    ] + gate + _compare_flags(c, "--gate-")
    data = [":" + binname, "//tools:diff_output.sh"] + gate_fs
    if c.get("stdin"):
        args += ["--gate-stdin", "$(location %s)" % c["stdin"]]
        data.append(c["stdin"])
    return args, data, "%s_output" % stem

def _case_run(c, prog):
    """How one c_program case runs, in every arm: (flags, files).

    `flags` go before a runner's `--` and take the same meaning in
    diff_output.sh, asan_run.sh and valgrind_test.sh: the stdin, the argument
    file and the run folder the case describes (_CASE_KEYS, "THE KEYS THAT
    SHAPE THE RUN ITSELF"). `files` are what they read. One helper, so that
    the arms cannot drift into running different things -- the valgrind arm
    once ran a stdin case with no stdin at all.
    """
    flags = []
    files = list(c.get("fixtures", []))
    if c.get("stdin"):
        flags += ["--stdin", "$(location %s)" % c["stdin"]]
        files.append(c["stdin"])
    if c.get("argv_file"):
        flags += ["--argv-file", "$(location %s)" % c["argv_file"]]
        files.append(c["argv_file"])
    if c.get("cwd_files"):
        flags += ["--run-as", prog]
        for src in sorted(c["cwd_files"]):
            flags += ["--cwd-file", "%s=$(location %s)" % (c["cwd_files"][src], src)]
            files.append(src)
    return flags, _uniq(files)

def _shown_bin(binname):
    """Where Bazel keeps a program of this package, for a RAN line: bazel-bin/<package>/<name>.

    What a student types at the repository root to run the program a test
    ran, once `bazel test` has built it (runner_lib.sh's rl_ran).
    """
    return "bazel-bin/%s/%s" % (native.package_name(), binname)

def _emit_cases(ex, binname, cases, prog, valgrind = False, memory_rule = None, access_rule = None, survive = ([], [])):
    """Emit one diff test (and optional valgrind test) per argv case.

    `memory_rule` is the label of the subject's memory sentence (c_program's
    memory_rule), which each valgrind arm quotes when it fails; and
    `access_rule` the label of its sentence on a crash or an invalid access
    (the contract's memory_graded), which a red that is no leak quotes.
    `survive` is the gate a survive case waits on, _survive_gate(ex, cases),
    which c_program works out once for every arm; ([], []) where there is
    none.

    And, per case, the exit status where _case_exit() says one is judged: in
    the output test when the subject names it, otherwise in a robust twin
    (_exit_twin).

    Every arm of a case prints the command it ran (--show-run) and keys its
    hints to the case's name (--case): a program case is a test of its own,
    with no named rows, so its report said nothing of what was run, and a
    clues.tsv row could name no case (findings 120, 155). `prog` is the
    program's name, which a "cwd_files" case runs it under.

    Every case is checked first (_case): its keys, its kind, its level. What
    each arm reads of it is one struct (_output_arm, _exit_twin,
    _valgrind_arm).
    """
    twins = {}
    for c in cases:
        k = _case(c, "program", "c_program(%s)" % _call(_key(ex)), prog)
        compare, expected_fs = _expected_args(ex, k)
        run_flags, run_files = _case_run(c, prog)
        basic_exit, robust_exit = _case_exit(ex, c)
        p = struct(
            c = c,
            k = k,
            stem = _case_stem(ex, cases, k.name),
            compare = compare,
            expected_fs = expected_fs,
            run_flags = run_flags,
            run_files = run_files,
            shown = ["--show-run", _shown_bin(binname), "--case", k.name],
            basic_exit = basic_exit,
            robust_exit = robust_exit,
            binname = binname,
        )
        data = _output_arm(ex, p, survive)
        _exit_twin(twins, p, data)
        if valgrind and c.get("valgrind", True):
            _valgrind_arm(ex, cases, p, survive, memory_rule, access_rule)

def _output_arm(ex, p, survive):
    """A case's output test, exNN[_case]_output; returns its data, which its exit twin shares.

    `p` is _emit_cases' struct of the case; `survive` as it takes it.
    """
    c = p.c
    data = _uniq([":" + p.binname] + p.expected_fs + p.run_files)
    args = [
        "--bin",
        "$(location :%s)" % p.binname,
    ] + p.compare + p.shown + _compare_flags(c)
    if c.get("clues"):
        clues_f = "tests/%s/%s" % (ex, c["clues"])
        args += ["--clues", "$(location %s)" % clues_f]
        data.append(clues_f)
    if p.basic_exit != None:
        args += _exit_flags(c, p.basic_exit)
    elif p.robust_exit != None:
        args += ["--note-exit", str(p.robust_exit)]

    # The name the case says will not open is checked absent where the
    # program runs, so the case cannot hand it a file that is there.
    if c.get("missing_file"):
        args += ["--absent", c["missing_file"]]

    # A survive case SKIPs while its exercise's first case is red: green
    # on a program nobody has written says nothing (_survive_gate).
    gate_args, gate_data = survive if p.k.survive else ([], [])
    w_args, w_data = _waiting_args("%s_output" % p.stem) if p.expected_fs else ([], [])
    args += gate_args + w_args + p.run_flags + ["--"] + c.get("args", [])
    _test(
        name = "%s_output" % p.stem,
        srcs = ["//tools:diff_output.sh"],
        args = args,
        data = data + [f for f in gate_data + w_data if f not in data],
        # What the case reads: its expected file(s), and every file its
        # run is handed (_case_run: fixtures, stdin, argument file, the
        # run folder's sources).
        tags = ["output", _case_reads_tag(p.expected_fs + p.run_files)],
        level = _raise("output", p.k.level),
    )
    return data

def _exit_twin(twins, p, data):
    """A case's robust exit twin, exNN[_case]_exit, where _case_exit() judges its status there.

    Tag "output", level 3: it runs the same invocation as the output test
    and judges nothing but how it ended -- the shape c_argv_table's exNN_exit
    and c_program's exNN_progname_exit have. Named _exit, not _exit_output:
    first_red reads an `output` tail as the next exercise to write, and this
    is rigour on a written one. `data` is the output test's (_output_arm).

    ONE TWIN PER RUN. Two cases can make the same run and compare its two
    streams (C 10 ex00's `empty` and `empty_stderr`): a twin judges how the
    run ended, which is one fact, so the second case's twin would judge it
    again and a wrong status would be two reds for one mistake. A twin whose
    arguments, the compared stream aside, are an earlier twin's is not
    emitted; the earlier one's name stands for both. `twins` holds each run
    emitted so far, across the cases of one _emit_cases call.
    """
    c = p.c
    e_head = [
        "--bin",
        "$(location :%s)" % p.binname,
    ]
    e_stream = ["--stream", c["stream"]] if c.get("stream") else []

    # "default": the case states nothing, so diff_output.sh checks the
    # default against what the case expects (_case_exit).
    source = "convention" if "exit" in c or "invalid_input" in c else "default"
    e_rest = [
        "--exit-only",
        "--exit",
        str(p.robust_exit),
        "--exit-source",
        source,
    ] + p.run_flags + ["--"] + c.get("args", [])

    # The run, as ONE TWIN PER RUN above reads it: what the twin is
    # handed but the file and the stream it does not compare, and the
    # level it sits at. A default's twin does read the file (the check
    # above), so there it is part of the run. What the report shows
    # (--show-run, --case) is not the run: the first case's name stands
    # for both.
    run = repr(e_head + e_rest + [max(3, p.k.level or 3)] + (p.compare if source == "default" else []))
    if p.robust_exit != None and run not in twins:
        twins[run] = p.stem
        _test(
            name = "%s_exit" % p.stem,
            srcs = ["//tools:diff_output.sh"],
            args = e_head + p.compare + p.shown + e_stream + e_rest,
            data = data,
            tags = ["output"],
            # Robust, or the case's own level where that is higher.
            level = max(3, p.k.level or 3),
        )

def _valgrind_arm(ex, cases, p, survive, memory_rule, access_rule):
    """A case's run under memcheck, exNN[_case]_valgrind; _emit_cases says which cases get one."""
    c = p.c
    vdata = _uniq([
        ":" + p.binname,
        "//tools:diff_output.sh",
    ] + p.expected_fs + p.run_files)
    vargs = [
        "--bin",
        "$(location :%s)" % p.binname,
        "--label",
        p.stem,
    ] + p.shown
    if memory_rule:
        vargs += ["--rule", "$(location %s)" % memory_rule]
        vdata.append(memory_rule)
    if access_rule:
        vargs += ["--access-rule", "$(location %s)" % access_rule]
        vdata.append(access_rule)

    # Gate on the exercise's own fixture, the way rust_diff, ilp32,
    # perf and cycles already do. Without it this was the one rigour
    # layer that spoke first: c-12 ex06 is a stub, so a student who
    # had written nothing was met with eight raw "indirectly lost"
    # records instead of "your output layer is still red — start
    # there". Leaks are the LAST thing to think about, after the
    # function produces the right bytes at all.
    #
    # A survive case has no fixture of its own: its "output" is that
    # it ended. So it waits on the case its output and asan arms wait
    # on (_survive_gate), handed to the runner whole after --survive:
    # a program nobody has written ends by itself, memory-clean, and
    # over a Makefile that builds nothing this arm met the stand-in
    # and was red at strict while the asan arm said SKIP (V253). No
    # such case: it runs ungated, as it does where a gate cannot
    # answer.
    #
    # stdin was once never forwarded, so a case that feeds the program
    # input ran a DIFFERENT path here than under the output layer -- it
    # read EOF immediately (_memory_gate forwards it).
    gate, gate_data, waits = _memory_gate(ex, cases, c, p.k, p.binname, survive)
    vargs += gate
    vdata += gate_data

    # The same clues.tsv the output arm gets. c_function has wired this
    # since the renderer was written, with the reason stated there --
    # "40 bytes in 1 blocks are definitely lost" is the report most
    # likely to leave a beginner stuck, and it was the one layer with no
    # hint attached. c_program's valgrind arm was the half that never
    # got the line, so the two macros disagreed about whether a leak
    # deserves a hint, with nothing recording a reason. It does.
    if c.get("clues"):
        vargs += ["--clues", "$(location tests/%s/%s)" % (ex, c["clues"])]
        vdata.append("tests/%s/%s" % (ex, c["clues"]))

    # BEFORE the `--`, which is not a detail: everything after it is
    # argv for the program under test, so flags appended at the end of
    # the list are handed to the student's binary and the runner sees
    # none of them.
    vargs += p.run_flags + _valgrind_args()
    vargs += ["--"] + c.get("args", [])
    _test(
        name = "%s_valgrind" % p.stem,
        srcs = ["//tools:valgrind_test.sh"],
        args = vargs,
        data = _uniq(vdata + _valgrind_data()),
        # A whole program under memcheck, at 20-50x: BSQ's readings
        # case took 22s in a full suite, a third of "small"'s 60,
        # and a run's own VALGRIND_TIMEOUT (60) did not fit inside
        # the test's (finding 066).
        size = "medium",
        tags = ["valgrind"],
        level = _raise("valgrind", p.k.level),
        # Its own case's output test: cases sharing an expected file
        # (BSQ's map errors) run the same program against it.
        waits = waits,
    )

def _reference_cases_test(ex, cases, prog):
    """exNN_reference_cases: every case of c_program(reference = True), run with //oracle's reference.

    Tag "oracle", complete. One test for the whole list, through
    tools/reference_cases.sh, which runs diff_output.sh once per case with
    `oracle run <prog>` as the program: each case's arguments are exactly its
    output test's -- the expected file(s) and how they are compared, the run
    flags (_case_run: stdin, argument file, run folder), the argv after `--`
    -- less what only a student's report needs (the RAN line, the hints, the
    exit-status note). A case's arguments travel as `--case-run NAME COUNT
    ARG...`, so an argument can be anything a case can hold, `--` included.

    The reference's status means what a program's does not: 0 says it has
    an answer, any other that it has none (tools/reference_cases.sh, NO
    ANSWER). Only a survive case may make a run the reference has no answer
    for, since it compares no output; any other case that makes one fails,
    with the reason the reference gave. For the same reason no case may have
    its output test compare a status other than 0 (_reference_exit_problem).

    WHY. A named case binds an input to an expected file, and when the files
    come from //oracle (oracle_fixtures.sh) that binding was still kept twice
    by hand: once in the reference's list of what it writes, once in the
    case. An edited number or dictionary in one of them drifted in silence --
    nothing compared them, and the owner's tree holds a stub, on which every
    case is red anyway. Running the reference on the case as written makes
    the case itself the thing checked.
    """
    args = [
        "--oracle",
        "$(location //oracle:oracle)",
        "--program",
        prog,
        "--differ",
        "$(location //tools:diff_output.sh)",
    ]
    data = ["//oracle:oracle", "//tools:diff_output.sh"]
    for c in cases:
        k = _case(c, "program", "c_program(%s)" % _call(_key(ex)))
        compare, expected_fs = _expected_args(ex, k)
        run_flags, run_files = _case_run(c, prog)
        a = list(compare) + _compare_flags(c)
        basic_exit, _ = _case_exit(ex, c)
        if basic_exit != None:
            # Whose rule the status is, as its output test says it: a
            # status a sentence is READ as naming is a reading here too,
            # never the subject's (V145). The sentence itself is left out.
            a += ["--exit", str(basic_exit), "--exit-source", _exit_source(c)]
        a += run_flags + ["--"] + c.get("args", [])
        args += ["--case-run", k.name, str(len(a))] + a
        data += expected_fs + run_files
    _test(
        name = ex + "_reference_cases",
        srcs = ["//tools:reference_cases.sh"],
        args = args,
        data = _uniq(data),
        size = "small",
        tags = ["oracle"],
    )

def _layouts(num):
    """The subject-structure checks for exercise `num`, for each header <h> its contract's `files` names.

    A header the subject dictates the contents of (C 12's ft_list.h, C 13's
    ft_btree.h) is still the student's file, and every test compiles with it,
    so a structure laid out otherwise than the subject prints is invisible to
    every layer that runs code (finding 132). Two files hold what the subject
    prints, each named after the header it checks, with static assertions
    that the student's type matches (see tools/prototype_check.sh):

        tests/layout/<h>      the layout: each field's type or size, its
                              offset, the structure's size -- what decides
                              whether two programs read one node alike
        tests/layout/tag/<h>  the names: the structure's tag, and the type
                              of each field that points to another node --
                              which memory does not see

    Only a header in `files`: one the grader brings (C 12 ex08's) is the
    grader's, and a copy the student keeps anyway is compiled by nobody who
    grades.

    c_function is the one macro that calls this. c_libft and c_header do not:
    no project of theirs has a structure file yet, and a pass-through no
    caller runs is how a check ends up misreading correct work. A file under
    tests/layout/ that no test reads fails c_levels()' audit instead of being
    dropped without a word (_audit_problems), which is where the next
    project's author learns to wire it; the toy exercises ex16 and ex17 in
    tools/tests/macro_fixtures prove the wiring, with `linked` and without.

    Returns:
        struct(files = [the layouts], tags = [the tag files]).
    """
    files = []
    tags = []
    for f in _entry(num, "layout")["files"] or []:
        if f.endswith(".h"):
            h = f.split("/")[-1]
            files += native.glob(["tests/layout/" + h], allow_empty = True)
            tags += native.glob(["tests/layout/tag/" + h], allow_empty = True)
    return struct(files = files, tags = tags)

def _prototype_test(ex, srcs, hdrs = None, extra_includes = None, required = True, layouts = None, layout_certain = False, grader_hdrs = None, name = None, extra_tags = None, inc_file = None):
    """Prototype conformance: the definition matches the signature the subject fixes.

    Tag "prototype".

    `layouts` (from _layouts()) are the subject's structures the student's
    header must hold. Each claim sits at the level its failure earns
    (reference.md's levels):

      the layout (`layouts.files`, --layout), in exNN_prototype at basic,
          where a difference is a certain KO: `layout_certain`, which
          c_function sets where the grader links a function of its own built
          on the structure (the contract's `linked`, C 12 and C 13 from ex01
          on), so a header laid out otherwise reads the grader's nodes wrong;
      the layout again, in the twin exNN_layout_prototype at strict, where
          only the grader's own test code could expose a difference (C 12's
          and C 13's ex00, where the student writes that function);
      the names (`layouts.tags`, --layout-tag), always in the twin at strict:
          a header naming the structure otherwise reads the grader's nodes
          right, and only code written against the subject's header by name
          tells them apart.

    The twin's suffix, _layout_prototype, puts it at strict by itself
    (_SUFFIX_LAYER), so no exercise needs a _RAISED entry for it.

    The subject fixes each function's return type and parameter list, and C
    links a mismatched signature happily (no name mangling), so the only symptom
    of getting it wrong is wrong values — a Moulinette KO with no local symptom.
    Force-including the contract header while compiling the deliverable puts the
    subject's declaration and the student's definition in one translation unit,
    turning the mismatch into a conflicting-types error. Green on a well-formed
    stub, like norm.

    `required` exists because this used to be emitted only `if native.glob(...)`
    found a header: a missing tests/exNN/prototype.h produced no target, no
    warning and no error, so "deliberately opted out" and "nobody wrote it yet"
    were indistinguishable — and a LEVEL 1 layer was silently absent for all of
    c-13 and six of c-12. Absence is now an analysis-time failure unless the
    BUILD file says `prototype = False` in so many words.

    `name` is the test's, default exNN_prototype (a rush variant's is
    exNN_rushNN_prototype), and `extra_tags` reach it too ("manual" for a
    variant nobody owes). `inc_file` is a Makefile's include list (see
    _compile_tests), on the path of both tests.

    Returns:
        The name of the test it declared, which the exercise's harnesses
        are given (_student_bin's `prototype`); None where it declared
        none.
    """
    hdrs = hdrs or []
    proto_f = "tests/%s/prototype.h" % ex
    if not native.glob([proto_f], allow_empty = True):
        if required:
            fail(
                ("%s: no %s, so the prototype layer would be silently absent " +
                 "for this exercise. Write the contract header (copy the shape " +
                 "of any existing tests/exNN/prototype.h), or pass " +
                 "prototype = False to record that opting out is deliberate.") %
                (ex, proto_f),
            )
        return None

    layouts = layouts or struct(files = [], tags = [])
    common = []
    for s in srcs:
        common += ["--src", "$(location %s)" % s]
    common += _inc_args("--inc", hdrs)
    for d in (extra_includes or []):
        common += ["--inc", d]
    inc_data = []
    if inc_file:
        common += ["--inc-file", "$(location %s)" % inc_file]
        inc_data = [inc_file]

    # A header the grader brings is named on a red, with the -I a compile by
    # hand needs (_grader_hdr_args).
    common += _grader_hdr_args(grader_hdrs)
    lay_args = []
    for f in layouts.files:
        lay_args += ["--layout", "$(location %s)" % f]
    tag_args = []
    for f in layouts.tags:
        tag_args += ["--layout-tag", "$(location %s)" % f]
    basic_layouts = layouts.files if layout_certain else []
    twin_layouts = ([] if layout_certain else layouts.files) + layouts.tags
    p_args = _pinned_cc_args() + ["--proto", "$(location %s)" % proto_f] + common
    if layout_certain:
        p_args += lay_args
    name = name or ex + "_prototype"
    _test(
        name = name,
        srcs = ["//tools:prototype_check.sh"],
        args = p_args,
        data = [proto_f] + srcs + hdrs + _PINNED_CC_DATA + basic_layouts + inc_data,
        tags = ["prototype"] + (extra_tags or []),
        turnin = srcs,
    )
    if twin_layouts:
        _test(
            # exNN_layout_prototype, or <name>'s own twin where it has one.
            name = name[:-len("_prototype")] + "_layout_prototype",
            srcs = ["//tools:prototype_check.sh"],
            args = _pinned_cc_args() + ([] if layout_certain else lay_args) + tag_args + common,
            data = twin_layouts + srcs + hdrs + _PINNED_CC_DATA + inc_data,
            tags = ["prototype"] + (extra_tags or []),
            level = _SUFFIX_LAYER["_layout_prototype"][1],
            turnin = srcs,
        )
    return name

def _prototype_mode_test(name, ex, srcs, hdrs, provided, mode_args, quotes, quotes_data, proto = True, tags = None, level = None, inc_file = None):
    """prototype_check.sh in --no-restrict or --declares mode, over a library's turn-in.

    `hdrs` are the TURNED-IN headers alone (--hdr: the files whose
    declarations are the student's); a header the grader brings is on the
    include path (--inc, and named on a red: _grader_hdr_args), never one
    of them. `proto` False is --all-functions, which reads no prototype.h.
    `inc_file` is the library's Makefile's include list (see _compile_tests).
    """
    proto_f = "tests/%s/prototype.h" % ex
    args = _pinned_cc_args() + mode_args
    if proto:
        args += ["--proto", "$(location %s)" % proto_f]
    for s in srcs:
        args += ["--src", "$(location %s)" % s]
    args += _inc_args("--hdr", hdrs)
    for d in provided.includes:
        args += ["--inc", d]
    if inc_file:
        args += ["--inc-file", "$(location %s)" % inc_file]
    args += _grader_hdr_args(provided.hdrs)
    _test(
        name = name,
        srcs = ["//tools:prototype_check.sh"],
        args = args + quotes,
        data = ([proto_f] if proto else []) + srcs + hdrs + provided.hdrs + _PINNED_CC_DATA + quotes_data +
               ([inc_file] if inc_file else []),
        tags = tags or ["prototype"],
        # --declares reads the headers alone; --no-restrict any file.
        turnin = hdrs if "--declares" in mode_args else srcs + hdrs,
        level = level,
    )

def _prototype_names_test(name, ex, srcs, hdrs = None, extra_includes = None, extra_tags = None, proto = "prototype.h", inc_file = None):
    """The parameter NAMES the subject fixes, at strict: tests <name>, ending _prototype_names.

    For a subject that names the parameters as well as typing them (Rush 00:
    "It must take two integer arguments, named x and y"): the definition in
    `srcs` must name them as tests/exNN/<proto> does, which says so in a
    comment quoting the subject -- prototype.h for a rush, a file of its own
    for a library (c_library's prototype_names), whose prototype.h includes
    the library's header. A names file includes nothing (tools/
    prototype_check.sh --names refuses one that does), and reads both
    through the pinned clang's AST dump. The suffix puts it at strict
    (_SUFFIX_LAYER): a name changes no behaviour, and only an evaluator
    reading the code can mark it, which is "real, but not certain". The
    basic _prototype test beside it keeps checking the types only.
    `inc_file` is a Makefile's include list (see _compile_tests).
    """
    hdrs = hdrs or []
    proto_f = "tests/%s/%s" % (ex, proto)
    p_args = _pinned_cc_args() + ["--names", "--proto", "$(location %s)" % proto_f]
    for s in srcs:
        p_args += ["--src", "$(location %s)" % s]
    p_args += _inc_args("--inc", hdrs)
    for d in (extra_includes or []):
        p_args += ["--inc", d]
    if inc_file:
        p_args += ["--inc-file", "$(location %s)" % inc_file]
    _test(
        name = name,
        srcs = ["//tools:prototype_check.sh"],
        args = p_args,
        data = [proto_f] + srcs + hdrs + _PINNED_CC_DATA + ([inc_file] if inc_file else []),
        tags = ["prototype"] + (extra_tags or []),
        turnin = srcs,
        # The level its suffix gives it (_SUFFIX_LAYER), which the audit
        # holds it to: _test() places a test by its layer alone.
        level = _SUFFIX_LAYER["_prototype_names"][1],
    )

def _allocfail_problem(num, malloc, allocfail, allocfail_rule):
    """What is wrong with a c_function call's allocfail and its sentence, or None.

    A value before it is a fail(), so the macro fixtures can feed it every
    broken call (contract_problem("allocfail", ...)).

    Args:
        num: the key the call names, for the message: an exercise, or a
            unit (a function of a library by its own name).
        malloc: as c_function takes it.
        allocfail: as c_function takes it.
        allocfail_rule: as c_function takes it.

    Returns:
        The message, or None.
    """
    where = "c_function(%s)" % _call(num)
    if allocfail_rule and not allocfail:
        return "%s sets allocfail_rule without allocfail: the sentence would back no check." % where
    if not allocfail:
        return None
    if not malloc:
        return ("%s sets allocfail but not malloc = True. A function that does not " +
                "allocate has no allocation to refuse.") % where
    why = allocfail_rule_problem(allocfail_rule)
    if why:
        return "%s sets allocfail: %s" % (where, why)
    return None

def _function_malloc_problem(num, malloc, e, stem = None):
    """c_function's message when its contract names malloc or free and `malloc` is off; None otherwise.

    c_program reads whether a program may allocate from the contract alone
    (_malloc_argument_problem). c_function cannot yet: a function that
    allocates through a helper the subject allows -- C 12's ft_create_elem,
    C 13's btree_create_node -- names neither malloc nor free, and needs
    the leak layer all the same, so `malloc` stays a call-site argument
    there. What the call may not do is contradict the contract where it
    speaks: an "Allowed functions" line naming malloc (the function
    allocates) or free (it releases, and must release everything) is one
    the leak layer is for, and a call that turns it off drops the one layer
    that sees a block never accounted for. A subject with no such line says
    nothing about this function either way, and is the call's to say.

    A value before it is a fail(), so the macro fixtures can feed it the
    broken calls (contract_problem("function_malloc", ...)).

    Args:
        num: the exercise or unit, for the message.
        malloc: as c_function takes it.
        e: its contract entry; for a function of a library, with `allowed`
            the function's own box's list (`functions`), never the union.
        stem: the function, where the call names one of the library `num`:
            it names the call and the layer.

    Returns:
        The message, or None.
    """
    allowed = e["allowed"]
    if malloc or allowed == None:
        return None
    named = [f for f in ["malloc", "free"] if f in allowed]
    if not named:
        return None
    if stem != None:
        return (("c_function(%s): the function's own allowed " +
                 "functions name %s, and malloc = %r turns off the leak layer " +
                 "(%s_valgrind), the one layer that sees a block never accounted " +
                 "for. Pass malloc = True.") %
                (_call(stem), " and ".join(named), malloc, stem))
    return (("c_function(%s): the contract's allowed functions name %s, and " +
             "malloc = %r turns off the leak layer (%s_valgrind), the one layer that " +
             "sees a block never accounted for. Pass malloc = True.") %
            (_call(num), " and ".join(named), malloc, num if _is_unit_key(num) else "exNN"))

def _malloc_argument_problem(ex, malloc):
    """c_program's message for a call that still passes `malloc`; None if it does not.

    Whether a program may allocate is its subject's, and the contract says
    it (_memcheck_allowed); a second copy at the call site is one that can
    disagree. A value before it is a fail(), so a fixture can watch it.
    """
    if malloc == None:
        return None
    return (("c_program(%s): malloc = %r. Whether the program may allocate is its " +
             "subject's \"Allowed functions\" line, which c_program reads from the " +
             "subject() contract (malloc named there, or no such line), as " +
             "corpus_memory() does: drop the argument.") % (ex, malloc))

def _memory_rule_problem(num, malloc, cases, memory_rule):
    """What is wrong with a c_program call's memory_rule, or None.

    A value before it is a fail(), so the macro fixtures can feed it every
    broken call (contract_problem("memory_rule", ...)).

    Args:
        num: the exercise, for the message.
        malloc: as c_program takes it.
        cases: as c_program takes it.
        memory_rule: as c_program takes it.

    Returns:
        The message, or None.
    """
    where = "c_program(%s)" % _call(num)
    if memory_rule == None:
        return None
    if not malloc or not cases:
        return ("%s: memory_rule is quoted by the valgrind arms, and there are none " +
                "without cases on a program its subject lets allocate (the contract's " +
                "allowed line names malloc, or there is none).") % where
    if type(memory_rule) != "string" or "\n" in memory_rule or not memory_rule.strip():
        return "%s: memory_rule is one line of the subject." % where
    return None

def allocfail_leaks_problem(allocfail, allowed):
    """Why an exercise may not have an exNN_allocfail_leaks target; None if it may.

    A decision c_function makes while loading, so it is a function of its own
    and //tools/tests:starlark_unit calls it both ways. The leak sweep replays
    the allocfail harness, so it needs one; and it asks a function to release
    what it obtained, so the subject must let it call free() -- C 07 ex05 and
    C 09 ex02 allow malloc alone (finding 084).

    Args:
      allocfail: c_function's `allocfail`, the harness file or None.
      allowed: the exercise's allowed functions from its subject() contract,
        or None where the subject names none.

    Returns:
      None, or the reason as the end of a sentence.
    """
    if not allocfail:
        return "not allocfail: the leak sweep replays the allocfail harness."
    if "free" not in (allowed or []):
        return ("the subject() contract does not let this exercise call free(): a " +
                "function that may not release a block cannot be asked to.")
    return None

def allocfail_rule_problem(rule, param = "allocfail_rule"):
    """Why `rule` cannot be an allocfail target's stated rule; None if it can.

    Every allocfail target says, under its verdict, why it asks what it asks,
    and it says it in the call site's words, handed to the runner as --rule.
    The runner used to say it itself, in one subject's words: every program's
    report quoted "handle errors coherently", C 10's included, whose subject
    has no such sentence, and Rush 02's leak target, whose rule is the
    freeing one. A runner cannot know which subject it is reading; the call
    site can, so the sentence is required there, and a target without one is
    refused while loading. A decision made while loading, so a function of its
    own that //tools/tests:starlark_unit calls both ways.

    Args:
      rule: the text the call site gives, or None.
      param: the parameter's name, for the message.

    Returns:
      None, or the reason as a sentence.
    """
    if type(rule) != "string" or not rule.strip():
        return ("%s is required: the subject's own sentence that makes a refused " +
                "allocation a question for this exercise, quoted, or -- where the " +
                "subject has none -- what this call site reads in it, said as a " +
                "reading. The report prints it under its verdict, so a student " +
                "sees whose rule it was; a runner cannot know which subject it " +
                "reads.") % param
    if "\n" in rule:
        return ("%s is one line: the runner wraps it to the report's width " +
                "itself; a long one is several literals joined with +.") % param
    return None

def method_problem(method, rule):
    """Why c_function's `method` and `method_rule` cannot emit exNN_method; None if they can.

    The method layer reads a sentence of the subject that no output can show
    (tools/method_check.sh), and prints it under its verdict in the call
    site's words, since a runner cannot know which subject it reads. So the
    sentence is required with the method, and neither comes alone. A
    decision made while loading, so a function of its own that
    //tools/tests:starlark_unit calls both ways.

    Args:
      method: "recursive", "iterative", or None.
      rule: the subject's sentence, as the call site quotes it, or None.

    Returns:
      None, or the reason as a sentence.
    """
    if method == None and rule == None:
        return None
    if method not in ("recursive", "iterative"):
        return (("method = %r: \"recursive\" where the subject asks for recursion " +
                 "(\"Create a recursive function\", \"Recursion is required\"), " +
                 "\"iterative\" where it asks for an iterative function, and nothing " +
                 "where it says neither.") % (method,))
    return _quoted_rule_problem(rule, "method_rule", "the subject's own sentence asking for it")

def fixed_array_problem(rule, max_bytes):
    """Why c_program's `fixed_array` and `fixed_array_bytes` cannot emit exNN_fixed_array; None if they can.

    `fixed_array` is the subject's sentence asking for a fixed-size array, as
    the call site quotes it; `fixed_array_bytes`, where the subject bounds
    the array, the bound in bytes, every object having to be smaller (the
    call site says how it read the subject's unit). A bound with no sentence
    would be a rule of no one's. Checked while loading, both ways, by
    //tools/tests:starlark_unit.

    Args:
      rule: the sentence, or None.
      max_bytes: an int above 1, or None.

    Returns:
      None, or the reason as a sentence.
    """
    if rule == None and max_bytes == None:
        return None
    if max_bytes != None and (type(max_bytes) != "int" or max_bytes < 2):
        return (("fixed_array_bytes = %r: the bound in bytes, an int above 1, every " +
                 "object of the program having to be smaller.") % (max_bytes,))
    return _quoted_rule_problem(
        rule,
        "fixed_array",
        "the subject's own sentence asking for a fixed-size array, and with a " +
        "bound, how its unit is read",
    )

def _quoted_rule_problem(rule, param, what):
    """Why `rule` cannot be the sentence a method-layer target prints; None if it can.

    The method layer's verdicts quote the subject (tools/method_check.sh's
    --rule), in the call site's words, as allocfail's do; one line, which
    names_file() writes for the runner.
    """
    if type(rule) != "string" or not rule.strip():
        return (("%s is required: %s, quoted, with where it is from. The report " +
                 "prints it under its verdict, so a student sees whose rule it is; " +
                 "a runner cannot know which subject it reads.") % (param, what))
    if "\n" in rule:
        return ("%s is one line: a long one is several literals joined with +." % param)
    return None


# ---------------------------------------------------------------------------
# WHAT THE FILES ABOVE THIS ONE LOAD OF IT. A load() cannot name a private
# symbol, so each one they use is given a public name here, its own without
# the underscore, and loaded back under its own name: the code reads as it did
# when tools/defs.bzl held it all. These names are for those files alone; a
# BUILD file loads //tools:defs.bzl.
header_norm_test = _header_norm_test
norm_test = _norm_test
provided_names = _provided_names
forbidden_allowed_problem = _forbidden_allowed_problem
forbidden_test = _forbidden_test
forbidden_mode_test = _forbidden_mode_test
symbols_test = _symbols_test
compile_tests = _compile_tests
CASE_KEYS = _CASE_KEYS
case_problem = _case_problem
case = _case
cases_problem = _cases_problem
raise_private = _raise
expected_args = _expected_args
case_stem = _case_stem
missing_file_problem = _missing_file_problem
makefile_problem = _makefile_problem
model_problem = _model_problem
reference_exit_problem = _reference_exit_problem
argv_model_problem = _argv_model_problem
emit_model = _emit_model
case_exit_error = _case_exit_error
exit_source = _exit_source
exit_flags = _exit_flags
header_exit_error = _header_exit_error
GOOD_VALUE = _GOOD_VALUE
APOSTROPHE = _APOSTROPHE
survive_gate = _survive_gate
survive_gate_prefix = _survive_gate_prefix
memory_gate = _memory_gate
compare_flags = _compare_flags
case_run = _case_run
shown_bin = _shown_bin
emit_cases = _emit_cases
reference_cases_test = _reference_cases_test
layouts = _layouts
prototype_test = _prototype_test
prototype_mode_test = _prototype_mode_test
prototype_names_test = _prototype_names_test
allocfail_problem = _allocfail_problem
function_malloc_problem = _function_malloc_problem
malloc_argument_problem = _malloc_argument_problem
memory_rule_problem = _memory_rule_problem
