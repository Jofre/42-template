"""The subject contract: one declaration per project, read by every macro.

WHY THIS EXISTS. What an exercise turns in, where, what the grader brings with
it and what the student may call are facts of the SUBJECT, printed in the box
at the top of each exercise. They used to be typed again at every call site
that needed one -- a c_files() list, a c_function's `allowed`, a header in
`hdrs`, a `provided_hdrs`, a c_make overlay, a glob of deliverable/exNN -- and
each copy was decided on its own, often from what the answer next to it
happened to hold. So they disagreed: C 12 ex08's header was optional to the
files layer and a build input to every other; C 09 ex01 compiled srcs/ as the
student's work while its files layer said the grader brings them; BSQ turned
in under ex00/ "like a rush", though its subject has no turn-in directory line
at all (findings 096, 108, 124, 128, 172, 177).

So each project's BUILD.bazel opens with ONE subject() call, transcribed from
the subject's header boxes, and the macros in tools/defs.bzl read it:

    subject(
        grader = "moulinette",
        group = False,
        exercises = {
            "00": exercise(
                page = 7,
                dir = "ex00/",
                files = ["ft_putchar.c"],
                allowed = ["write"],
            ),
        },
    )

and nothing else in the BUILD file names a file the student turns in, a
function they may call or a file the grader brings. That is the form for a
subject that prints "Turn-in directory: exNN/" over each exercise, and each
exercise turns in at that folder, the one its key names. A subject
that prints none -- BSQ's, Libft's, every Common Core subject's -- is divided
by its own words instead, and its contract names each part:

    subject(
        grader = "both",
        group = False,
        units = {
            "libtoy": unit(
                page = 4,
                files = ["Makefile", "libtoy.h"],
                optional = ["toy_*.c"],
                allowed = [],
                functions = {"toy_len": [], "toy_up": []},
            ),
        },
    )

A unit turns in at the root of deliverable/; its name is the first word of
its targets (libtoy_build), its suite (:libtoy), its folder under tests/ and
the word a student types after the project; a unit with `functions` is a
library, and each of its functions is a unit of its own, named after itself
(toy_len_output, :toy_len, tests/toy_len/). Every unit takes every argument
an exercise does but `dir`, and only a unit takes `functions`: an exercise
turns in no library. The macros take from either form:

    the turn-in directory   every path of every layer (turnin_dir())
    files, optional         the files layer, which c_levels() emits for every
                            exercise; the sources and headers every build
                            globs (a pattern with a / or ** in it lets them
                            sit in subfolders)
    provided                the grader's files: linked (a .c), staged and put
                            on the include path (a .h), or laid beside a
                            Makefile turned in alone -- and reported, not
                            accepted, when a copy turns up in the turn-in
    linked                  the grader's own functions, compiled: linked into
                            every program built for the exercise, and
                            reported when the student defines one
    allowed, variables      the forbidden layer's list
    grader                  every runner's words about where a failure costs
                            (RL_GRADER, which tools/defs_test.bzl's _test() hands
                            every test; tools/runner_lib.sh's rl_at), and the
                            files layer's advice about an extra file
    memory_graded           the level of the valgrind layer in the package
                            (_test()'s tags, and the audit's), and the two
                            sentences its reds quote: one for a leak, one
                            for an invalid access or a crash

What each field holds, and which layer reads it, is one table in
docs/reference.md ("The subject contract"); the exercise() arguments below say
how to transcribe each one from the subject.

THE CONTRACT IS DATA. subject() stores it, as JSON, in a rule named `subject`
(`bazel build //<project>:subject` writes it out), and each macro reads it back
through contract_or_none(). That and c_levels()' finalizer, which holds the
package's rules already, decode the rule (of kind SUBJECT_CONTRACT_KIND) with
contract_of_rule(), the one decoder of it. Hence subject() comes FIRST in the
BUILD file: a macro called before it fails, naming the fix. c_levels() fails in a
package without one, and //tools:conventions refuses a project BUILD file that
does not open with it. Beside what subject() takes, it records the order its
call writes the exercises (or units) in (`order`) and each one's functions in
(`function_order`), which units_of() lists the units in: a dict's keys are not
an order anyone wrote down. The JSON holds `exercises` or `units`, never
both, and contract_entries() reads whichever it is. tools/defs.bzl writes those units out as :units,
one line each, and tools/units.awk reads the same lines from the text of the
call for every reader outside Bazel.

EVERY CHECK IS A VALUE FIRST. exercise() and subject() fail with what
exercise_problem() and subject_problem() return, and the macros' own contract
checks (tools/defs.bzl's contract_problem()) are built the same way: a
function that returns the message, and a caller that fails with it. A package
that does not load cannot be a test, so this is what lets
tools/tests/macro_fixtures feed each check the broken contract it guards
against and compare the words, on every run (:contract_problems there).
"""

load(":grader_lib.bzl", "GraderLibInfo")

_GRADERS = ("moulinette", "defense", "both")

# The keys an exercise() entry holds, so a typo in a hand-edited entry is a
# fail() rather than a field no macro reads. An exercise's `functions` is
# always {}: it is a unit's key, kept here so that both entries hold it.
_KEYS = ("page", "dir", "files", "optional", "provided", "linked", "allowed", "variables", "strict", "functions")

# The keys a unit() entry holds: an exercise's, `dir` always None (a unit
# turns in at the root of deliverable/), and the Makefile rule that builds a
# part, with the subject's sentence naming it.
_UNIT_KEYS = _KEYS + ("goal", "goal_quote")

# unit()'s `dir` when the call does not give one: no value a BUILD file can
# write, so that dir = None is refused as dir = "x/" is -- a transcriber
# copying an exercise() entry's arguments reads why, rather than a unit that
# quietly drops what they wrote.
_NO_DIR = struct(unit_dir = "not given")

# exercise()'s `functions` when the call does not give one, for the same
# reason: functions = None written out is refused as a dict is.
_NO_FUNCTIONS = struct(exercise_functions = "not given")

# THE NAME OF A UNIT is the first word of its targets (<name>_<what>), its
# suite's name (:<name>), its folder under tests/ and the word a student
# types after the project: a lowercase letter, then lowercase letters,
# digits or _.
_NAME_FIRST = "abcdefghijklmnopqrstuvwxyz"
_NAME_CHARS = _NAME_FIRST + "0123456789_"

def _is_list_of_strings(v):
    if type(v) != "list":
        return False
    for x in v:
        if type(x) != "string" or not x:
            return False
    return True

def _relative(p):
    """Whether `p` is a path inside a directory: no leading /, no .. segment."""
    if p.startswith("/"):
        return False
    for seg in p.split("/"):
        if seg == "..":
            return False
    return True

def exercise(page, dir, files, allowed, optional = None, provided = None, linked = None, variables = None, strict = None, functions = _NO_FUNCTIONS):
    """One exercise's header box, as the subject prints it.

    Args:
        page: the page the exercise's header box is printed on, as the footer
            numbers it -- the page a reader checking this entry opens.
        dir: the "Turn-in directory" (or "Directory") line, verbatim:
            "ex00/". An exercise turns in at exNN/, the folder its key names,
            and subject() checks the two agree. A subject with no such line
            -- BSQ's, and every Common Core subject's -- turns in at
            deliverable/ itself, the root of the repository that is pushed,
            and is a contract of units (unit()): None is refused, naming that
            form. Required, so that the line is written down rather than
            forgotten.
        files: the "Files to turn in" line: the names it gives, relative to
            the turn-in directory. [] where it names none ("All the necessary
            files"). None where writing the name down would be the exercise
            itself (Shell 01 ex05's file NAME is its answer); the exercise
            then gets no files layer from here.
        allowed: the "Allowed functions" (or "Authorized", "External
            functions") line, verbatim: ["write"], or [] for "None". None
            only where the subject prints no such line: the exercise then gets
            no forbidden layer at all.
        optional: what the subject lets the turn-in hold without naming it:
            names, or glob patterns relative to the turn-in directory --
            ["*.c", "*.h"] for "and files needed for your program". A pattern
            with a / or a ** in it ("**/*.c") says the files may sit in
            subfolders (srcs/, includes/): the builds then glob the sources and
            headers the same way. Beside a Makefile ("files" or "optional"
            names one) a bare "*.c" or "*.h" is refused: the Makefile decides
            where its sources lie, so "**/*.c" is the transcription. The files
            layer walks the whole tree whatever this says. Default [].
        provided: the files the GRADER brings, as {harness copy: where the
            grader puts it}: the copy lives under tests/ -- never under
            deliverable/, and never required -- and the destination is
            relative to the turn-in directory. {"tests/ft_putchar.c":
            "ft_putchar.c"} for "we will compile your code with our
            ft_putchar.c". A .c is linked into every build of the student's
            code and judged by no layer; a .h is staged, and its directory
            joins the include path; for a Makefile turned in alone, every one
            is laid beside it before the build. A copy found in the turn-in is
            reported as the grader's, unless `optional` also names it.
            Default {}.
        linked: the functions the grader compiles in with the student's code
            from a library of its own, as {function: library label}: C 12's
            "From exercise 01 onward, we'll use our ft_create_elem" is
            {"ft_create_elem": "//oracle:c12_grader"} on every exercise from
            01 on. The library is a grader_library() (tools/grader_lib.bzl),
            never C under tests/ (that would be an answer outside the zone):
            it is linked into every program built for the exercise -- in
            place of the exercise that writes the function, which the
            harness used to link -- and its i686 twin into the ilp32 layer's;
            a student who defines the function anyway is told the grader
            brings it (the forbidden and symbols layers). The contract's
            analysis checks each label is a grader_library() whose `exports`
            name the function (linked_problem()), and a macro that cannot
            link it into what it builds fails while loading, naming itself
            (tools/defs_contract.bzl's _TAKES_LINKED). Default {}.
        variables: variables the subject allows by name, in a sentence of its
            own ("You may use the variable errno"). They join `allowed` for the
            forbidden layer. Default [].
        strict: whether a file the subject did not ask for FAILS the files
            layer rather than warning. Default: the project's.
        functions: refused, whatever its value, None too: an exercise
            turns in no library. A library whose functions each have a box
            of their own is a unit, unit(functions = ...), of a contract of
            units, which turns in at the root of deliverable/. Taken only so
            that the message can say so.

    Returns:
        The entry, as subject() stores it, `functions` {}.
    """
    problem = exercise_problem(page, dir, files, allowed, optional, provided, variables, strict, linked, functions)
    if problem:
        fail(problem)
    return _box_entry(page, dir, files, allowed, optional, provided, linked, variables, strict, {})

def _is_c_name(s):
    """Whether `s` is a C identifier: a letter or _, then letters, digits or _."""
    return type(s) == "string" and s != "" and (s[0].isalpha() or s[0] == "_") and \
           s.replace("_", "a").isalnum()

def exercise_problem(page, dir, files, allowed, optional = None, provided = None, variables = None, strict = None, linked = None, functions = _NO_FUNCTIONS):
    """What is wrong with an exercise() entry, as the message exercise() fails with; None if nothing.

    A value rather than a fail(), so that each check can be PROVEN: a package
    that fails to load cannot be a test, and a check nobody has seen fire is
    a guess. tools/tests/macro_fixtures feeds this every broken entry it
    guards against and compares the messages (its :contract_problems).

    An exercise turns in no library, and turns in at a folder of its own:
    `functions` is refused first, then dir = None, and then its box is
    checked as a unit's is (_box_problem()). Whether that folder is the one
    its key names is subject()'s check, which knows the key.

    Args:
        page: as exercise() takes it.
        dir: as exercise() takes it.
        files: as exercise() takes it.
        allowed: as exercise() takes it.
        optional: as exercise() takes it.
        provided: as exercise() takes it.
        variables: as exercise() takes it.
        strict: as exercise() takes it.
        linked: as exercise() takes it.
        functions: as exercise() takes it: any value given is the problem,
            None too.

    Returns:
        The first problem found, as the message exercise() fails with, or None.
    """
    if functions != _NO_FUNCTIONS:
        return ("exercise(functions = ...): an exercise turns in no library. A library whose " +
                "functions each have a box of their own is a unit of a contract of units, " +
                "which turns in at the root of deliverable/: subject(units = " +
                "{\"<library>\": unit(..., functions = {...})})")
    if dir == None:
        return (("exercise(dir = %r): an exercise turns in at the folder its subject's " +
                 "\"Turn-in directory\" line names, \"exNN/\" for exercise NN. A subject with " +
                 "no such line turns in at the root of deliverable/, and is a contract of " +
                 "units: subject(units = {\"<name>\": unit(...)})") % (dir,))
    return _box_problem("exercise", page, dir, files, allowed, optional, provided, variables, strict, linked, None)

def _box_entry(page, dir, files, allowed, optional, provided, linked, variables, strict, functions):
    """The keys exercise() and unit() share, in the order the contract stores them.

    Both write a box of the subject the same way, an absent list as [] and
    an absent map as {}; unit() adds its goal after them.
    """
    return {
        "page": page,
        "dir": dir,
        "files": files,
        "optional": optional or [],
        "provided": provided or {},
        "linked": linked or {},
        "allowed": allowed,
        "variables": variables or [],
        "strict": strict,
        "functions": functions or {},
    }

def _box_problem(what, page, dir, files, allowed, optional, provided, variables, strict, linked, functions):
    """What is wrong with a header box, an exercise()'s or a unit()'s; None if nothing.

    Both take the same box, and each message names the call it is in: WHAT
    is "exercise" or "unit". `dir` is None for a unit, which has none;
    `functions` is None for an exercise, which exercise_problem() refuses
    before this runs.
    """
    if type(page) != "int" or page < 1:
        return "%s(page = %r): the page the header box is printed on, a positive int" % (what, page)
    if dir != None:
        if type(dir) != "string" or not dir.endswith("/") or not _relative(dir) or dir == "/":
            return "%s(dir = %r): the subject's turn-in directory line, verbatim, like \"ex00/\"" % (what, dir)
    if files != None and type(files) != "list":
        return "%s(files = %r): a list of names, [] for none named, or None" % (what, files)
    if files and not _is_list_of_strings(files):
        return "%s(files = %r): every entry is a non-empty name" % (what, files)
    if allowed != None and type(allowed) != "list":
        return "%s(allowed = %r): the subject's list, [] for \"None\"" % (what, allowed)
    if allowed and not _is_list_of_strings(allowed):
        return "%s(allowed = %r): every entry is a function name" % (what, allowed)
    optional = optional or []
    if optional and not _is_list_of_strings(optional):
        return "%s(optional = %r): names or glob patterns" % (what, optional)
    variables = variables or []
    if variables and not _is_list_of_strings(variables):
        return "%s(variables = %r): variable names" % (what, variables)
    provided = provided or {}
    if type(provided) != "dict":
        return "%s(provided = %r): {harness copy under tests/: where the grader puts it}" % (what, provided)
    for src, dest in provided.items():
        if type(src) != "string" or not src.startswith("tests/") or not _relative(src):
            return (("%s(provided = ...): %r -- the harness's copy of a file the " +
                     "grader brings lives under tests/, never where the student turns " +
                     "in: a file the grader supplies is never the student's to write") % (what, src))
        if type(dest) != "string" or not dest or not _relative(dest):
            return "%s(provided = ...): %r -> %r: the destination is a path inside the turn-in directory" % (what, src, dest)
        if files and dest in files:
            return (("%s(provided = ...): %r is both required of the student and " +
                     "brought by the grader. A file the grader supplies is never " +
                     "required: list it in `optional` if the student may keep a copy.") % (what, dest))
    for f in (files or []) + optional:
        if not _relative(f):
            return "%s(...): %r is not a path inside the turn-in directory" % (what, f)
    linked = linked or {}
    if type(linked) != "dict":
        return "%s(linked = %r): {function the grader links: its library's label}" % (what, linked)
    for fn, lib in linked.items():
        if not _is_c_name(fn):
            return "%s(linked = ...): %r is not a C function name" % (what, fn)
        if type(lib) != "string" or not (lib.startswith("//") or lib.startswith("@")) or ":" not in lib:
            return (("%s(linked = ...): %r -> %r: the library is a grader_library() " +
                     "target, by its full label (\"//oracle:c12_grader\"), never a file " +
                     "under tests/: a C copy of the function there would be its " +
                     "exercise's answer outside the zone") % (what, fn, lib))
        for f in (files or []) + optional:
            if f.split("/")[-1] == fn + ".c":
                return (("%s(linked = ...): %r is the grader's, and %r is a file " +
                         "the student turns in for it here. A function the grader " +
                         "links is never the student's to write in the same exercise.") % (what, fn, f))

    # A MAKEFILE DECIDES WHERE ITS SOURCES LIE. "Makefile, *.h, *.c" in a
    # header box says what kind of file, never where: the Makefile names its
    # sources, in srcs/ or beside it, and the grader runs it. A bare "*.c"
    # reaches no subfolder, and since the files layer walks the whole tree it
    # failed a srcs/ layout at basic, as files nobody asked for. "**/*.c"
    # allows them anywhere, and the files layer still reports a source the
    # Makefile never compiles (make -Bn's list). A subject that does fix a
    # place writes one ("srcs/*.c"), and a shape that names files ("ft_*.c")
    # is a transcription of its own; neither is refused.
    if "Makefile" in (files or []) + optional:
        for f in optional:
            if f in ("*.c", "*.h"):
                return (("%s(optional = %r): %r beside a Makefile reaches no " +
                         "subfolder, and the Makefile decides where its sources lie: " +
                         "a turn-in with srcs/ or includes/ would fail its files layer " +
                         "as files nobody asked for. Write \"**/%s\": the files layer " +
                         "then walks the tree, and still reports a source the Makefile " +
                         "never compiles.") % (what, optional, f, f))
    if strict != None and type(strict) != "bool":
        return "%s(strict = %r): True, False, or None for the project's" % (what, strict)
    return _functions_problem(functions, allowed)

def _functions_problem(functions, allowed):
    """What is wrong with a unit()'s `functions` against its `allowed`; None if nothing."""
    functions = functions or {}
    if type(functions) != "dict":
        return ("unit(functions = %r): {function the subject's boxes name: the " +
                "External Functions its box allows}") % (functions,)
    if not functions:
        return None
    union = {}
    for fn in sorted(functions):
        if not _is_c_name(fn):
            return "unit(functions = ...): %r is not a C function name" % (fn,)
        box = functions[fn]
        if type(box) != "list" or (box and not _is_list_of_strings(box)):
            return (("unit(functions = ...): %r -> %r: the External Functions its " +
                     "box names, as a list of names, [] for \"None\"") % (fn, box))
        for f in box:
            if f not in (allowed or []):
                return (("unit(functions = ...): %s's box allows %s, which the " +
                         "unit's `allowed` does not name. `allowed` is every " +
                         "function some box allows: the forbidden layer reads it for " +
                         "the whole library.") % (fn, f))
            union[f] = True
    if allowed == None:
        return (("unit(functions = ...) with allowed = None: with `functions`, " +
                 "`allowed` is the union of the boxes' lists, [] where every box " +
                 "says \"None\""))
    unused = [f for f in allowed if f not in union]
    if unused:
        return (("unit(functions = ...): no box allows %s, and `allowed` names it. " +
                 "With `functions`, `allowed` is the union of the boxes' lists, so a " +
                 "function no box allows is allowed to no function of the library.") %
                ", ".join(unused))
    return None

def unit(page, files, allowed, optional = None, provided = None, linked = None, variables = None, strict = None, functions = None, goal = None, goal_quote = None, dir = _NO_DIR):
    """One part of a project whose subject prints no "Turn-in directory: exNN/" line.

    subject(units = {"<name>": unit(...)}) transcribes it. It takes what
    exercise() takes, from the same header box, but `dir`, and means the same
    by each (exercise()'s Args say how to transcribe one); and `functions`,
    which only a unit takes.

    Args:
        page: as exercise() takes it.
        files: as exercise() takes it, relative to the root of deliverable/.
        allowed: as exercise() takes it.
        optional: as exercise() takes it.
        provided: as exercise() takes it.
        linked: as exercise() takes it.
        variables: as exercise() takes it.
        strict: as exercise() takes it.
        functions: where the unit turns in a library of functions, each
            with a box of its own naming its External Functions (a Common
            Core library's Part 2 and Part 3), {function: the list its box
            allows}: {"ft_split": ["malloc", "free"], "ft_strlen": []}, []
            for a box that says "None" or whose part allows none. Every
            function the boxes name is a key, and `allowed` is the union of
            the lists, which is what the forbidden layer reads for the whole
            library; each function is then judged against its own box. A
            unit with functions is a LIBRARY, and each function is a unit of
            its own, named after itself: its targets are <function>_<what>,
            its suite :<function>, its folder tests/<function>/. Each name is
            held to a unit name's rules (subject()). Default {}: a unit with
            one box, `allowed`.
        goal: the Makefile rule that builds this part, as the subject names it
            ("bonus"), for one part of several turned in at the root that
            shares its files with another (subject()'s `units` says how a
            part is told written). None, the default, for the project's only
            unit, which a bare make builds (a goal there is refused), for the
            one part of several that a bare make builds, and for a part
            whose files are its own.
        goal_quote: the subject's sentence naming that rule, one line with
            its project and page. Required with goal, refused without it.
        dir: never given. A unit turns in at the root of deliverable/, the
            repository that is pushed, so any dir -- None too -- is refused,
            naming the two forms there are.

    Returns:
        The entry, as subject() stores it: exercise()'s keys, dir None, and
        goal and goal_quote.
    """
    problem = unit_problem(page, files, allowed, optional, provided, linked, variables, strict, functions, goal, goal_quote, dir)
    if problem:
        fail(problem)
    return dict(
        _box_entry(page, None, files, allowed, optional, provided, linked, variables, strict, functions),
        goal = goal,
        goal_quote = goal_quote,
    )

def _unit_dir_problem(dir):
    """The message for a unit given a dir, by unit() or in a hand-built entry."""
    return (("unit(dir = %r): a unit turns in at the root of deliverable/, the repository " +
             "that is pushed, and takes no dir. A subject that prints \"Turn-in " +
             "directory: exNN/\" over each exercise is declared with exercises = " +
             "{\"NN\": exercise(...)}; one that names a folder of its own for each part " +
             "has no form in the contract yet (V430).") % (dir,))

def unit_problem(page, files, allowed, optional = None, provided = None, linked = None, variables = None, strict = None, functions = None, goal = None, goal_quote = None, dir = _NO_DIR):
    """What is wrong with a unit() entry, as the message unit() fails with; None if nothing.

    A value for the reason exercise_problem() gives. Its box is checked as
    an exercise's is (_box_problem()), each message naming unit( where an
    exercise's names exercise(, and its `functions` against its `allowed`
    (_functions_problem()).

    Args:
        page: as unit() takes it.
        files: as unit() takes it.
        allowed: as unit() takes it.
        optional: as unit() takes it.
        provided: as unit() takes it.
        linked: as unit() takes it.
        variables: as unit() takes it.
        strict: as unit() takes it.
        functions: as unit() takes it.
        goal: as unit() takes it.
        goal_quote: as unit() takes it.
        dir: as unit() takes it: any value given is the problem.

    Returns:
        The first problem found, as the message unit() fails with, or None.
    """
    if dir != _NO_DIR:
        return _unit_dir_problem(dir)
    problem = _box_problem("unit", page, None, files, allowed, optional, provided, variables, strict, linked, functions)
    if problem:
        return problem
    if goal == None:
        if goal_quote != None:
            return ("unit(goal_quote = ...) with no goal: it quotes the subject for the " +
                    "Makefile rule goal names")
        return None
    if type(goal) != "string" or not goal or goal[0] in "-." or \
       not goal.replace("_", "a").replace("-", "a").replace(".", "a").isalnum():
        return (("unit(goal = %r): the Makefile rule that builds this part, as the subject " +
                 "names it, like \"bonus\"") % (goal,))
    if "Makefile" not in (files or []) + (optional or []):
        return (("unit(goal = %r): a goal is a rule of the unit's Makefile, and its files " +
                 "and optional name no Makefile") % (goal,))
    if type(goal_quote) != "string" or not goal_quote.strip() or "\n" in goal_quote:
        return (("unit(goal = %r) quotes no sentence: goal_quote is the subject's own words " +
                 "naming the rule, one line with its project and page") % (goal,))
    return None

def _is_unit_name(s):
    """Whether `s` is a unit's name: [a-z][a-z0-9_]*."""
    if type(s) != "string" or not s or s[0] not in _NAME_FIRST:
        return False
    for c in s.elems():
        if c not in _NAME_CHARS:
            return False
    return True

def _unit_name_problem(name, what, reserved):
    """subject()'s message for a unit or a function named `name`; None if it may be one.

    Args:
        name: the key the contract gives it.
        what: how the message names it: "\"tally\"", or "\"libtoy\"'s function
            \"toy_len\"".
        reserved: as subject() takes it.
    """
    if not _is_unit_name(name):
        return (("subject(units = ...): %s is not a unit name: a lowercase letter, then " +
                 "lowercase letters, digits or _. It is the first word of the unit's " +
                 "targets (<name>_<what>), its suite's name, its folder under tests/ and " +
                 "the word a student types after the project.") % what)
    if name.startswith("ex") and len(name) > 2 and name[2] in "0123456789":
        return (("subject(units = ...): %s is shaped like an exercise's name: ex and a digit " +
                 "begin only an exercise's, which turns in under the subject's \"Turn-in " +
                 "directory: exNN/\" and is declared in exercises = {...}, and every reader " +
                 "files a target that begins exNN under that exercise. Name the unit by " +
                 "the subject's own words.") % what)
    for r in reserved:
        if name == r or r.startswith(name + "_") or (r.endswith("_") and name.startswith(r)):
            return (("subject(units = ...): %s %s: a level, a layer, a suite or a target " +
                     "every module has, or the start of one. A unit's name is also its " +
                     "suite's and the first word of its targets, so it may not be one, begin " +
                     "one followed by _, or begin a reserved prefix. docs/reference.md lists " +
                     "them.") %
                    (what, "is a name the harness reserves" if name == r else "collides with %r, which the harness reserves" % (r,)))
    return None

# SEVERAL PARTS AT THE ROOT. A subject that divides its turn-in into parts
# (a mandatory part and a bonus, two programs) without a folder for each has
# them all at the root of deliverable/, and each part is a unit of kind
# "part". What is derived for each, never declared, is how it is told
# written from a stub (its judge, which `submit --written-only` and
# first_red read):
#
#   files  its files are its own: every name it lists is a plain file name
#          (_is_plain_name), every name each other part lists is one too,
#          and no other part lists one of its names. It names no goal, and
#          is written once one of its files holds a body.
#   goal   it may share a file with another part, so no file can say which
#          part is written: the rule of their Makefile that builds it does.
#          It is written once the Makefile is no stub and that rule (its
#          goal; for the one part a bare make builds, which names none, the
#          rule a bare make runs) does something: a prerequisite, or a
#          recipe that does more than echo.
#
# A pattern ("**/*.c") on either side could name a file of the other, and is
# not expanded against the names here: it makes the parts share.

def _is_plain_name(p):
    """Whether `p` names one file as the files layer names it: no *, no empty or . segment."""
    if "*" in p:
        return False
    for seg in p.split("/"):
        if seg in ("", "."):
            return False
    return True

def _part_names(u):
    """The names a part lists, its files then its optional, as written."""
    return (u["files"] or []) + (u["optional"] or [])

def _shared_reason(name, units, order):
    """Why the part `name` may share a file with another part, as a phrase; None if it cannot."""
    own = _part_names(units[name])
    for x in own:
        if not _is_plain_name(x):
            return "its %r is no plain file name, so it could name a file another part lists" % (x,)
    for other in order:
        if other == name:
            continue
        for y in _part_names(units[other]):
            if not _is_plain_name(y):
                return "%r lists %r, which is no plain file name, so it could name one of %r's files" % (other, y, name)
            if y in own:
                return "%r lists %r too" % (other, y)
    return None

def _parts(units, order):
    """How each part of several is told written, or why the contract cannot say.

    Args:
        units: the contract's units, each a unit() entry; more than one.
        order: their names, in the order the subject() call writes them.

    Returns:
        A pair: ({name: "files" or "goal"}, None), or (None, the message
        subject() fails with).
    """
    goals = {}
    for name in order:
        u = units[name]
        if u["functions"]:
            return None, (("subject(units = ...): %r has functions, and the project has other " +
                           "units (%s). A library is a project's only unit, each of its " +
                           "functions a unit of its own; a part of several has none.") %
                          (name, ", ".join([n for n in order if n != name])))
        if u["strict"] != None:
            return None, (("subject(units = ...): %r has strict = %r, and it is one of several " +
                           "parts at the root of deliverable/. A file no part lists is judged " +
                           "once for the whole root, by deliverable_files, under the project's " +
                           "strict: set strict on subject(), not on a part.") % (name, u["strict"]))
        if u["files"] == None:
            return None, (("subject(units = ...): %r has files = None, and it is one of several " +
                           "parts. A part's files say which files are its, and how it is told " +
                           "written: list them, [] where its box names none.") % (name,))
        if not _part_names(u):
            return None, (("subject(units = ...): %r lists no file (files = [] and no optional), " +
                           "and it is one of several parts, so nothing could say which files " +
                           "are its or when it is written.") % (name,))
        g = u["goal"]
        if g != None:
            if g in goals:
                return None, (("subject(units = ...): %r and %r both have goal = %r. A goal is " +
                               "the Makefile rule that builds one part, so no two parts name " +
                               "the same one.") % (goals[g], name, g))
            goals[g] = name
    judges = {}
    bare = None
    for name in order:
        u = units[name]
        reason = _shared_reason(name, units, order)
        if reason == None:
            if u["goal"] != None:
                return None, (("subject(units = ...): %r has goal = %r, and its files are its own: " +
                               "no other part lists one of them. A goal names the Makefile rule that " +
                               "builds a part sharing its files with another; a part whose files are " +
                               "its own is told written by them. Leave goal and goal_quote out.") %
                              (name, u["goal"]))
            judges[name] = "files"
            continue
        judges[name] = "goal"
        if "Makefile" not in _part_names(u):
            return None, (("subject(units = ...): %r may share its files with another part " +
                           "(%s), and lists no Makefile. A part that shares its files is told " +
                           "written by the rule of their Makefile that builds it: it lists the " +
                           "Makefile, and names its rule with goal unless a bare make builds " +
                           "it.") % (name, reason))
        if u["goal"] == None:
            if bare != None:
                return None, (("subject(units = ...): %r and %r may share their files, and " +
                               "neither has a goal. A bare make builds one part; each other " +
                               "part that shares its files names the Makefile rule that builds " +
                               "it (goal, with goal_quote).") % (bare, name))
            bare = name
    return judges, None

def _units_problem(units, reserved):
    """subject()'s message for a `units` map it cannot take; None if it can.

    Every name in it -- each unit's, and each function's of a library -- is
    a unit name (_unit_name_problem), held once in the project (the prefix
    rule below included), because each one is a suite, a folder under tests/
    and the first word of targets of the same package.
    """
    if type(units) != "dict" or not units:
        return ("subject(units = ...): {\"<name>\": unit(...)}, one per part of the project " +
                "the subject turns in, each named by the subject's own words")
    taken = {}
    for name, u in units.items():
        problem = _unit_name_problem(name, "%r" % (name,), reserved)
        if problem:
            return problem
        if type(u) != "dict" or sorted(u.keys()) != sorted(_UNIT_KEYS):
            return "subject(units = ...): %r is not a unit(...) entry" % (name,)
        if u["dir"] != None:
            return _unit_dir_problem(u["dir"])
        taken[name] = "the unit %r" % (name,)
    for name, u in units.items():
        for fn in u["functions"]:
            problem = _unit_name_problem(fn, "%r's function %r" % (name, fn), reserved)
            if problem:
                return problem
            if fn in taken:
                return (("subject(units = ...): %r names both %s and a function of %r: each " +
                         "unit and each function has a name of its own, which its targets, " +
                         "its suite and its folder under tests/ take") % (fn, taken[fn], name))
            taken[fn] = "a function of %r" % (name,)
    if len(units) > 1:
        _, problem = _parts(units, list(units.keys()))
        if problem:
            return problem
    else:
        for name, u in units.items():
            if u["goal"] != None:
                return (("subject(units = ...): %r has goal = %r, and it is the project's only " +
                         "unit: a goal names the Makefile rule that builds one part of several, " +
                         "and the only unit is what make builds with no goal. Leave goal and " +
                         "goal_quote out.") % (name, u["goal"]))

    # THE PREFIX RULE: a target is <unit>_<what>, and a reader finds its unit
    # as the declared name its target begins with, followed by _. Were one
    # name, followed by _, the start of another, toy_up_output would be the
    # unit toy_up's output test or the unit toy's test named up_output.
    names = sorted(taken.keys())
    for a in names:
        for b in names:
            if b != a and b.startswith(a + "_"):
                return (("subject(units = ...): %r and %r: %s_ begins %s, so a target named " +
                         "%s_... could be either's, and no reader could tell whose. Rename " +
                         "one so that neither name, followed by _, begins the other.") %
                        (a, b, a, b, b))
    return None

def linked_problem(exercises, exports, what = "exercise"):
    """What is wrong with the libraries the contract's `linked` names; None if nothing.

    exercise_problem() checks a label's shape, which is all a string can
    say: "//pkg:impl" over a cc_library of a C copy under tests/ has the
    shape too, and so has a grader_library() that exports some other name.
    Each would link, or fail to, in every program of the exercise, and a red
    there reads as the student's. This is the half that needs the target
    itself, so subject_contract runs it while it is analysed -- by
    `bazel test //...`, or `bazel build //<project>:subject` -- and
    contract_problem() in tools/defs.bzl hands it to the fixtures.

    Args:
        exercises: the contract's exercises (or units), as subject() stores
            them.
        exports: {label, as `linked` spells it: the functions its
            grader_library() exports, or None where the target is no
            grader_library()}.
        what: what an entry is called in the message: "exercise", or "unit"
            for a contract of units.

    Returns:
        The first problem found, as the message the contract fails with, or None.
    """
    for num in sorted(exercises):
        linked = exercises[num]["linked"]
        for fn in sorted(linked):
            lib = linked[fn]
            names = exports.get(lib)
            if names == None:
                return (("subject(...): %s %s links %s from %s, which is no " +
                         "grader_library() target. The grader's own function is compiled " +
                         "from Rust by grader_library() (tools/grader_lib.bzl): written " +
                         "in C -- a cc_library over a file under tests/, or anywhere " +
                         "else outside the zone -- it is the answer of the exercise that " +
                         "writes it.") % (what, num, fn, lib))
            if fn not in names:
                return (("subject(...): %s %s links %s from %s, which exports %s. " +
                         "Name a function that library exports, or export this one from " +
                         "its crate (#[no_mangle] extern \"C\") and add it to the " +
                         "grader_library()'s `exports`.") %
                        (what, num, fn, lib, ", ".join(names) or "nothing"))
    return None

# WHAT A CONTRACT IS DIVIDED INTO: one unit per exercise (or per unit of a
# contract of units), in the order the subject() call writes them, and
# right after a library, a unit with `functions`, one unit per function, in
# the order its boxes are transcribed. tools/defs.bzl writes them as :units
# (units_rows()), and tools/units.awk prints the same rows from the text;
# its header lists the words a row may hold.

def contract_entries(contract):
    """A decoded contract's entries, keyed as its subject() call keys them.

    Its exercises ({"NN": entry}), or its units ({"<name>": entry}):
    subject() writes one of the two, and a contract with neither is no
    contract, so this fails rather than return {} for it.

    Args:
        contract: a contract as json.decode() returns what subject() stored.

    Returns:
        The dict of entries.
    """
    if "units" in contract:
        return contract["units"]
    return contract["exercises"]

def turnin_folder(dir):
    """The package-relative folder an entry's `dir` turns in at.

    deliverable/exNN for an exercise, whose dir is "exNN/", and deliverable/
    itself for a unit, whose dir is None: the root of the repository that is
    pushed. tools/defs.bzl's turnin_dir() and units_of() both read it from
    here, so :units names the folder every layer uses.
    """
    return "deliverable" if dir == None else "deliverable/" + dir.rstrip("/")

def units_order_problem(contract):
    """Why a decoded contract's recorded order disagrees with its entries; None if it agrees.

    A value first, as every contract check is: //tools/tests:starlark_unit
    feeds it contracts whose order is missing or wrong. subject() writes both
    lists itself, so this fires only on a contract written by something else
    -- a hand-built one, or a subject() that stopped writing them. An
    exercise with functions is refused too: no subject() writes one, and
    units_of() lists functions for a library alone.

    Args:
        contract: a contract as json.decode() returns what subject() stored.

    Returns:
        The first disagreement, as a sentence, or None.
    """
    if "units" in contract and "exercises" in contract:
        return "the contract holds both exercises and units: tools/subject.bzl's subject() writes one of the two"
    what, one = ("units", "unit") if "units" in contract else ("exercises", "exercise")
    entries = contract.get(what) or {}
    order = contract.get("order")
    if type(order) != "list":
        return (("the contract records no `order` of its %s: tools/subject.bzl's " +
                 "subject() writes one, and no reader of its units falls back on how " +
                 "json.encode orders a dict's keys") % what)
    if sorted(order) != sorted(entries.keys()):
        return "the contract's `order` (%s) is not its %s (%s), each once" % (
            ", ".join(order),
            what,
            ", ".join(sorted(entries.keys())),
        )
    function_order = contract.get("function_order")
    if type(function_order) != "dict" or sorted(function_order.keys()) != sorted(order):
        return (("the contract's `function_order` does not hold one list per %s: " +
                 "tools/subject.bzl's subject() writes one, [] where it has no functions") % one)
    for num in order:
        want = sorted((entries[num].get("functions") or {}).keys())
        if want and what == "exercises":
            return (("the contract's exercise %s has functions (%s): an exercise turns in no " +
                     "library, and tools/subject.bzl's exercise() refuses them") % (num, ", ".join(want)))
        if sorted(function_order[num]) != want:
            return "the contract's `function_order` for %s (%s) is not its `functions` (%s), each once" % (
                num,
                ", ".join(function_order[num]),
                ", ".join(want),
            )
    return None

def units_of(contract):
    """The units a decoded contract is divided into, in the order its subject() call writes them.

    One per exercise, "exNN", or per unit of a contract of units, named by
    its key; then, after a library (a unit with `functions`), one per
    function, named after it. tools/units.awk reads the same units from the
    text of the call, and //tools/tests holds the two equal through :units
    (tools/defs.bzl's units_rows()).

    Args:
        contract: a contract as json.decode() returns what subject() stored.

    Returns:
        A list of dicts, each with:
          name      "exNN", a unit's key, or the function's name;
          kind      "exercise"; "library", a unit with functions; "project",
                    the project's only unit, with none; "part", one of several
                    units at the root (none has functions); or "function";
          key       the key of the entry it is, or for a function of the
                    library it is one of, in contract_entries(): "00",
                    "libtoy";
          num       an exercise's key ("00"); None in a contract of units;
          folder    where it turns in (turnin_folder()): deliverable/exNN
                    for an exercise, deliverable for every unit, a function
                    its library's;
          required  "mandatory" or "optional" where the contract names a
                    mandatory part, None where it names none, and None for a
                    function;
          judge     "folder" for an exercise, a library or a project,
                    "defines" for a function, and for a part "files" or
                    "goal" (_parts()): what says it is written;
          library   the name of the library a function is one of; None
                    otherwise;
          goal      the Makefile rule a part names (unit(goal = ...)); None
                    for every other unit, and for a part with none.
    """
    problem = units_order_problem(contract)
    if problem:
        fail(problem)
    named = "units" in contract
    entries = contract_entries(contract)
    several = named and len(contract["order"]) > 1
    judges = {}
    if several:
        judges, problem = _parts(entries, contract["order"])
        if problem:
            fail(problem)
    mandatory = contract.get("mandatory") or []
    out = []
    for key in contract["order"]:
        e = entries[key]
        fns = contract["function_order"][key]
        name = key if named else "ex" + key
        folder = turnin_folder(e["dir"])
        out.append({
            "name": name,
            "kind": ("part" if several else ("library" if fns else "project")) if named else "exercise",
            "key": key,
            "num": None if named else key,
            "folder": folder,
            "required": (("mandatory" if key in mandatory else "optional") if mandatory else None),
            "judge": judges.get(key, "folder"),
            "library": None,
            "goal": e.get("goal"),
        })
        for fn in fns:
            out.append({
                "name": fn,
                "kind": "function",
                "key": key,
                "num": None,
                "folder": folder,
                "required": None,
                "judge": "defines",
                "library": name,
                "goal": None,
            })
    return out

def _subject_contract_impl(ctx):
    exports = {}
    for label, dep in zip(ctx.attr.lib_labels, ctx.attr.libs):
        exports[label] = dep[GraderLibInfo].names if GraderLibInfo in dep else None
    contract = json.decode(ctx.attr.contract)
    problem = linked_problem(contract_entries(contract), exports, "unit" if "units" in contract else "exercise")
    if problem:
        fail(problem)
    out = ctx.actions.declare_file(ctx.label.name + ".json")
    ctx.actions.write(out, ctx.attr.contract + "\n")
    return [DefaultInfo(files = depset([out]))]

subject_contract = rule(
    implementation = _subject_contract_impl,
    doc = "A project's subject contract, as JSON: what subject() declared. Read by tools/defs.bzl.",
    attrs = {
        "contract": attr.string(doc = "The contract, JSON-encoded."),
        "libs": attr.label_list(
            doc = "Every library the contract's `linked` names, for linked_problem(). No " +
                  "file of theirs is built: the rule reads what each target is.",
        ),
        "lib_labels": attr.string_list(
            doc = "The same labels as `linked` spells them, in the same order: the keys " +
                  "linked_problem() looks them up by.",
        ),
    },
)

# The kind native.existing_rule() gives the rule subject() declares.
SUBJECT_CONTRACT_KIND = "subject_contract"

def contract_of_rule(r):
    """The contract the rule `r` holds, decoded; None where `r` is no subject() rule.

    The one decoder of what subject() stores: its rule `subject`, of kind
    SUBJECT_CONTRACT_KIND, holding the contract as JSON. `r` is that rule as
    native.existing_rule() or native.existing_rules() gives it, or None.
    Every reader of the contract goes through it -- each macro through
    contract_or_none() (tools/defs_contract.bzl's _contract fails where it is None),
    c_levels()' finalizer from the rules it already holds -- so a change to
    how the contract is stored is made here alone.

    Returns:
        The contract as json.decode() returns what subject() stored, or None.
    """
    if not r or r["kind"] != SUBJECT_CONTRACT_KIND:
        return None
    return json.decode(r["contract"])

def contract_or_none():
    """The calling package's subject contract, decoded; None where the package has none.

    Its rule `subject`, read through contract_of_rule().

    Returns:
        The contract as json.decode() returns what subject() stored, or None.
    """
    return contract_of_rule(native.existing_rule("subject"))

def subject(grader, group, exercises = None, units = None, strict = True, mandatory = None, mandatory_quote = None, memory_graded = None, reserved = None, name = "subject"):
    """A project's subject contract. The FIRST call in its BUILD.bazel.

    Args:
        grader: who grades the turn-in: "moulinette" (a program alone:
            Piscine Reloaded), "defense" (peers at an evaluation: the
            rushes), or "both" (the Moulinette and a defense: every other
            Piscine module and BSQ).
        group: True for a group project (the rushes): the turn-in is a team's.
        exercises: {"NN": exercise(...)}, one entry per exercise that turns
            something in, keyed by the number its tests/exNN/ folder has:
            the form for a subject that prints "Turn-in directory: exNN/"
            over each exercise, and each entry's dir is that folder, the one
            its key names. Exactly one of exercises and units.
        units: {"<name>": unit(...)}, for a subject that prints no such
            line, each part named by the subject's own words: its targets
            are <name>_<what>, its suite :<name>, its folder tests/<name>/.
            A name is a lowercase letter, then lowercase letters, digits or
            _; never ex and a digit, which begin only an exercise's name;
            never one of `reserved`; and neither it nor a function's,
            followed by _, begins another (the prefix rule). Every unit
            turns in at the root of deliverable/. Several units are the
            subject's parts (a mandatory part and a bonus, two programs):
            none has functions, and how each is told written is derived
            from its files and its goal (_parts(), above), never declared.
        strict: the project's default for exercise(strict): whether a file
            the subject did not ask for FAILS the files layer (True, where the
            subject says to turn in nothing else) or warns. Default True.
        mandatory: the keys of the exercises (or units: never a function,
            which is judged with its library) the subject itself calls its
            mandatory part, where it says so ("You have reached the end of
            the mandatory exercises..."): `submit --written-only` will not
            push the project while one of them is still a stub. None, the
            default, where the subject names no such part; it is never
            inferred, and never written for a subject that does not say it.
        mandatory_quote: the subject's sentence that says so, with its page,
            as the project's other quotes are written. Required with
            mandatory, and refused without it.
        memory_graded: the subject's own sentences saying its grader judges
            memory, as a dict of exactly two keys, each one line with its
            project and page, as the project's other quotes are written:
              "leaks"   what it says of memory left allocated: "Libft, p.3:
                        \"All heap-allocated memory must be properly freed
                        when necessary. Memory leaks will not be
                        tolerated.\"";
              "access"  what it says of a crash or an invalid access:
                        "Libft, p.3: \"Your functions should not quit
                        unexpectedly (segmentation fault, bus error, double
                        free, etc.) except for undefined behavior. ...\"",
                        the sentence whole.
            Where a subject says so, a memory finding is a KO wherever the
            project is graded, so the project's valgrind layer leaves
            strict for basic -- every test of that layer in the package,
            whichever macro emits it (tools/defs_levels.bzl's _layer_level) -- and
            each red quotes the sentence its finding breaks: "access" for an
            invalid access, an uninitialised value or a crash
            (valgrind_test.sh's --access-rule, every test of the layer),
            "leaks" for a leak (--rule, every test of it that checks
            leaks). Two sentences, because a red quoting the leak sentence
            over an invalid read, or over a probe that checks no leak, named
            a rule the finding does not break. A fact of the project,
            declared once, never per target. None, the default, where the
            subject says nothing of the kind: never inferred from a
            grader's habits.
        reserved: the names no unit may take: tools/defs.bzl's subject()
            passes its _RESERVED_UNIT_NAMES, a list held to its own
            levels, layers and module targets, which this file cannot load.
            An entry that ends in _ reserves every name that begins with it.
            Required with units; a BUILD file never passes it.
        name: unused: the contract is always the target `subject`, which is
            where every macro looks for it. Here because every macro takes a
            `name` (see c_levels in tools/defs.bzl).
    """
    problem = subject_problem(
        grader = grader,
        group = group,
        exercises = exercises,
        units = units,
        strict = strict,
        mandatory = mandatory,
        mandatory_quote = mandatory_quote,
        memory_graded = memory_graded,
        reserved = reserved,
        name = name,
    )
    if problem:
        fail(problem)
    entries = exercises if exercises != None else units

    # Every library `linked` names, so that the contract's own analysis checks
    # each is a grader_library() exporting the function (linked_problem()).
    libs = {}
    for e in entries.values():
        for lib in e["linked"].values():
            libs[lib] = True
    contract = {
        "grader": grader,
        "group": group,
        "strict": strict,
        "mandatory": mandatory or [],
        "mandatory_quote": mandatory_quote or "",
        "memory_graded": memory_graded or {},
        # THE ORDER THE CALL WRITES ITS ENTRIES IN, recorded rather than
        # read back from the dicts: units_of() lists the units in this
        # order, as tools/units.awk reads them from the text, and no
        # reader depends on how json.encode orders a dict's keys.
        "order": list(entries.keys()),
        "function_order": {k: list(e["functions"].keys()) for k, e in entries.items()},
    }

    # One map or the other, under its own key, never both: a reader that
    # asks a contract of units for its exercises fails, rather than finding
    # none (contract_entries()).
    contract["exercises" if exercises != None else "units"] = entries
    subject_contract(
        name = "subject",
        contract = json.encode(contract),
        libs = sorted(libs.keys()),
        lib_labels = sorted(libs.keys()),
        visibility = ["//visibility:public"],
    )

# What subject(memory_graded = {...}) holds: the subject's sentence for each
# kind of memory finding (see subject()'s docstring).
_MEMORY_GRADED_KEYS = ["access", "leaks"]

def _memory_graded_problem(memory_graded):
    """subject()'s message for a memory_graded it cannot take; None if it can."""
    if memory_graded == None:
        return None
    if type(memory_graded) != "dict":
        return (("subject(memory_graded = %r): a dict of the subject's own sentences, " +
                 "{\"leaks\": ..., \"access\": ...}, each one line with its project and " +
                 "page -- or leave it out where the subject says nothing of the kind") %
                (memory_graded,))
    for k in sorted(memory_graded):
        if k not in _MEMORY_GRADED_KEYS:
            return (("subject(memory_graded = {%r: ...}): not a key it takes: \"leaks\", " +
                     "the subject's sentence on memory left allocated, and \"access\", its " +
                     "sentence on a crash or an invalid access") % (k,))
    for k in _MEMORY_GRADED_KEYS:
        if k not in memory_graded:
            return (("subject(memory_graded = ...) has no %r: both \"leaks\" and \"access\", " +
                     "each the subject's own sentence, since a red quotes the one its finding " +
                     "breaks") % (k,))
        v = memory_graded[k]
        if type(v) != "string" or not v.strip() or "\n" in v:
            return (("subject(memory_graded = {%r: %r}): one line, the subject's own words " +
                     "with its project and page") % (k, v))
    return None

def subject_problem(grader, group, exercises = None, units = None, strict = True, mandatory = None, mandatory_quote = None, memory_graded = None, reserved = None, name = "subject"):
    """What is wrong with a subject() call, as the message it fails with; None if nothing.

    A value for the reason exercise_problem() gives: proven on broken
    contracts by tools/tests/macro_fixtures, without a package that fails.

    Args:
        grader: as subject() takes it.
        group: as subject() takes it.
        exercises: as subject() takes it.
        units: as subject() takes it.
        strict: as subject() takes it.
        mandatory: as subject() takes it.
        mandatory_quote: as subject() takes it.
        memory_graded: as subject() takes it.
        reserved: as subject() takes it.
        name: as subject() takes it.

    Returns:
        The first problem found, as the message subject() fails with, or None.
    """
    if name != "subject":
        return "subject(name = %r): the contract is always named `subject`: the macros look for it there" % name
    if grader not in _GRADERS:
        return "subject(grader = %r): one of %s" % (grader, ", ".join(_GRADERS))
    if type(group) != "bool":
        return "subject(group = %r): True for a group project, False otherwise" % (group,)
    if type(strict) != "bool":
        return "subject(strict = %r): True or False" % (strict,)

    # ONE MAP. A project is divided one way: by the exercises its subject
    # gives a turn-in directory each, or by the units its own words name.
    if exercises != None and units != None:
        return ("subject(exercises = ..., units = ...): both, and a project is divided one " +
                "way: exercises where the subject prints \"Turn-in directory: exNN/\" over " +
                "each exercise, units where it prints none")
    if exercises == None and units == None:
        return ("subject(...) has neither exercises nor units: exercises = {\"NN\": " +
                "exercise(...)} where the subject prints \"Turn-in directory: exNN/\" over " +
                "each exercise, units = {\"<name>\": unit(...)} where it prints none")
    if units != None:
        if reserved == None:
            return ("subject(units = ...) with no reserved names: tools/defs.bzl's subject() " +
                    "passes its _RESERVED_UNIT_NAMES, which no unit may take")
        problem = _units_problem(units, reserved)
        if problem:
            return problem
    else:
        if type(exercises) != "dict" or not exercises:
            return "subject(exercises = ...): {\"NN\": exercise(...)}, one per exercise that turns something in"
        for num, e in exercises.items():
            if type(num) != "string" or len(num) != 2 or not num.isdigit():
                return "subject(exercises = ...): key %r -- the exercise number as a two-digit string, \"00\"" % (num,)
            if type(e) != "dict" or sorted(e.keys()) != sorted(_KEYS):
                return "subject(exercises = ...): %r is not an exercise(...) entry" % (num,)
            if e["dir"] != "ex%s/" % num:
                return (("subject(exercises = ...): exercise %r turns in at %r. An exercise turns in " +
                         "at the folder its key names, \"ex%s/\", as its subject's \"Turn-in " +
                         "directory\" line says. A subject with no such line is a contract of " +
                         "units: subject(units = {\"<name>\": unit(...)})") % (num, e["dir"], num))
    problem = _memory_graded_problem(memory_graded)
    if problem:
        return problem
    if mandatory == None:
        if mandatory_quote != None:
            return ("subject(mandatory_quote = ...) with no mandatory list: it quotes the " +
                    "subject for the list it gives")
        return None
    if type(mandatory) != "list":
        if units != None:
            return "subject(mandatory = %r): a list of unit names, [\"<name>\"]" % (mandatory,)
        return "subject(mandatory = %r): a list of exercise keys, [\"00\", \"01\"]" % (mandatory,)
    if not mandatory:
        return ("subject(mandatory = []): name the %s the subject calls mandatory, " +
                "or leave mandatory out") % ("units" if units != None else "exercises")
    seen = {}
    for num in mandatory:
        if units != None and num not in units:
            libs = [n for n, u in units.items() if num in u["functions"]]
            if libs:
                return (("subject(mandatory = ...): %r is a function of %r: mandatory names " +
                         "the library, whose functions are judged with it") % (num, libs[0]))
            return "subject(mandatory = ...): %r is not a unit of this contract" % (num,)
        if units == None and num not in exercises:
            return "subject(mandatory = ...): %r is not an exercise of this contract" % (num,)
        if num in seen:
            return "subject(mandatory = ...): %r is named twice" % (num,)
        seen[num] = True
    if type(mandatory_quote) != "string" or not mandatory_quote.strip():
        return ("subject(mandatory = ...) quotes no sentence: mandatory_quote is the " +
                "subject's own words naming its mandatory part")
    return None
