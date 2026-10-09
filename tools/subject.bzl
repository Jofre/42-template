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
at all (findings 096, 108, 124, 128, 172, 177; TODO.md §23, classes 1
and 2).

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
function they may call or a file the grader brings. The macros take from it:

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
                            (RL_GRADER, which tools/defs.bzl's _test() hands
                            every test; tools/runner_lib.sh's rl_at), and the
                            files layer's advice about an extra file

What each field holds, and which layer reads it, is one table in
docs/reference.md ("The subject contract"); the exercise() arguments below say
how to transcribe each one from the subject.

THE CONTRACT IS DATA. subject() stores it, as JSON, in a rule named `subject`
(`bazel build //<project>:subject` writes it out), and each macro reads it back
with native.existing_rule() -- which is why subject() comes FIRST in the BUILD
file: a macro called before it fails, naming the fix. c_levels() fails in a
package without one, and //tools:conventions refuses a project BUILD file that
does not open with it.

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
# fail() rather than a field no macro reads.
_KEYS = ("page", "dir", "files", "optional", "provided", "linked", "allowed", "variables", "strict")

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

def exercise(page, dir, files, allowed, optional = None, provided = None, linked = None, variables = None, strict = None):
    """One exercise's header box, as the subject prints it.

    Args:
        page: the page the exercise's header box is printed on, as the footer
            numbers it -- the page a reader checking this entry opens.
        dir: the "Turn-in directory" (or "Directory") line, verbatim: "ex00/".
            None when the subject has no such line -- BSQ's, and every Common
            Core subject's -- and then the exercise turns in at deliverable/
            itself, which is the root of the repository that is pushed.
            Required, so that "no line" is written down rather than forgotten.
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
            (tools/defs.bzl's _TAKES_LINKED). Default {}.
        variables: variables the subject allows by name, in a sentence of its
            own ("You may use the variable errno"). They join `allowed` for the
            forbidden layer. Default [].
        strict: whether a file the subject did not ask for FAILS the files
            layer rather than warning. Default: the project's.

    Returns:
        The entry, as subject() stores it.
    """
    problem = exercise_problem(page, dir, files, allowed, optional, provided, variables, strict, linked)
    if problem:
        fail(problem)
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
    }

def exercise_problem(page, dir, files, allowed, optional = None, provided = None, variables = None, strict = None, linked = None):
    """What is wrong with an exercise() entry, as the message exercise() fails with; None if nothing.

    A value rather than a fail(), so that each check can be PROVEN: a package
    that fails to load cannot be a test, and a check nobody has seen fire is
    a guess. tools/tests/macro_fixtures feeds this every broken entry it
    guards against and compares the messages (its :contract_problems).

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

    Returns:
        The first problem found, as the message exercise() fails with, or None.
    """
    if type(page) != "int" or page < 1:
        return "exercise(page = %r): the page the header box is printed on, a positive int" % (page,)
    if dir != None:
        if type(dir) != "string" or not dir.endswith("/") or not _relative(dir) or dir == "/":
            return (("exercise(dir = %r): the subject's turn-in directory line, verbatim, " +
                     "like \"ex00/\" -- or None when the subject has none") % (dir,))
    if files != None and type(files) != "list":
        return "exercise(files = %r): a list of names, [] for none named, or None" % (files,)
    if files and not _is_list_of_strings(files):
        return "exercise(files = %r): every entry is a non-empty name" % (files,)
    if allowed != None and type(allowed) != "list":
        return "exercise(allowed = %r): the subject's list, [] for \"None\"" % (allowed,)
    if allowed and not _is_list_of_strings(allowed):
        return "exercise(allowed = %r): every entry is a function name" % (allowed,)
    optional = optional or []
    if optional and not _is_list_of_strings(optional):
        return "exercise(optional = %r): names or glob patterns" % (optional,)
    variables = variables or []
    if variables and not _is_list_of_strings(variables):
        return "exercise(variables = %r): variable names" % (variables,)
    provided = provided or {}
    if type(provided) != "dict":
        return "exercise(provided = %r): {harness copy under tests/: where the grader puts it}" % (provided,)
    for src, dest in provided.items():
        if type(src) != "string" or not src.startswith("tests/") or not _relative(src):
            return (("exercise(provided = ...): %r -- the harness's copy of a file the " +
                     "grader brings lives under tests/, never where the student turns " +
                     "in: a file the grader supplies is never the student's to write") % (src,))
        if type(dest) != "string" or not dest or not _relative(dest):
            return "exercise(provided = ...): %r -> %r: the destination is a path inside the turn-in directory" % (src, dest)
        if files and dest in files:
            return (("exercise(provided = ...): %r is both required of the student and " +
                     "brought by the grader. A file the grader supplies is never " +
                     "required: list it in `optional` if the student may keep a copy.") % (dest,))
    for f in (files or []) + optional:
        if not _relative(f):
            return "exercise(...): %r is not a path inside the turn-in directory" % (f,)
    linked = linked or {}
    if type(linked) != "dict":
        return "exercise(linked = %r): {function the grader links: its library's label}" % (linked,)
    for fn, lib in linked.items():
        if type(fn) != "string" or not fn or not (fn[0].isalpha() or fn[0] == "_") or \
           not fn.replace("_", "a").isalnum():
            return "exercise(linked = ...): %r is not a C function name" % (fn,)
        if type(lib) != "string" or not (lib.startswith("//") or lib.startswith("@")) or ":" not in lib:
            return (("exercise(linked = ...): %r -> %r: the library is a grader_library() " +
                     "target, by its full label (\"//oracle:c12_grader\"), never a file " +
                     "under tests/: a C copy of the function there would be its " +
                     "exercise's answer outside the zone") % (fn, lib))
        for f in (files or []) + optional:
            if f.split("/")[-1] == fn + ".c":
                return (("exercise(linked = ...): %r is the grader's, and %r is a file " +
                         "the student turns in for it here. A function the grader " +
                         "links is never the student's to write in the same exercise.") % (fn, f))

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
                return (("exercise(optional = %r): %r beside a Makefile reaches no " +
                         "subfolder, and the Makefile decides where its sources lie: " +
                         "a turn-in with srcs/ or includes/ would fail its files layer " +
                         "as files nobody asked for. Write \"**/%s\": the files layer " +
                         "then walks the tree, and still reports a source the Makefile " +
                         "never compiles.") % (optional, f, f))
    if strict != None and type(strict) != "bool":
        return "exercise(strict = %r): True, False, or None for the project's" % (strict,)
    return None

def linked_problem(exercises, exports):
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
        exercises: the contract's exercises, as subject() stores them.
        exports: {label, as `linked` spells it: the functions its
            grader_library() exports, or None where the target is no
            grader_library()}.

    Returns:
        The first problem found, as the message the contract fails with, or None.
    """
    for num in sorted(exercises):
        linked = exercises[num]["linked"]
        for fn in sorted(linked):
            lib = linked[fn]
            names = exports.get(lib)
            if names == None:
                return (("subject(...): exercise %s links %s from %s, which is no " +
                         "grader_library() target. The grader's own function is compiled " +
                         "from Rust by grader_library() (tools/grader_lib.bzl): written " +
                         "in C -- a cc_library over a file under tests/, or anywhere " +
                         "else outside the zone -- it is the answer of the exercise that " +
                         "writes it.") % (num, fn, lib))
            if fn not in names:
                return (("subject(...): exercise %s links %s from %s, which exports %s. " +
                         "Name a function that library exports, or export this one from " +
                         "its crate (#[no_mangle] extern \"C\") and add it to the " +
                         "grader_library()'s `exports`.") %
                        (num, fn, lib, ", ".join(names) or "nothing"))
    return None

def _subject_contract_impl(ctx):
    exports = {}
    for label, dep in zip(ctx.attr.lib_labels, ctx.attr.libs):
        exports[label] = dep[GraderLibInfo].names if GraderLibInfo in dep else None
    problem = linked_problem(json.decode(ctx.attr.contract)["exercises"], exports)
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

def subject(grader, group, exercises, strict = True, name = "subject"):
    """A project's subject contract. The FIRST call in its BUILD.bazel.

    Args:
        grader: who grades the turn-in: "moulinette" (a program, every
            Piscine module and BSQ), "defense" (peers at an evaluation, the
            rushes), or "both".
        group: True for a group project (the rushes): the turn-in is a team's.
        exercises: {"NN": exercise(...)}, one entry per exercise that turns
            something in, keyed by the number its tests/exNN/ folder has.
        strict: the project's default for exercise(strict): whether a file
            the subject did not ask for FAILS the files layer (True, where the
            subject says to turn in nothing else) or warns. Default True.
        name: unused: the contract is always the target `subject`, which is
            where every macro looks for it. Here because every macro takes a
            `name` (see c_levels in tools/defs.bzl).
    """
    problem = subject_problem(grader, group, exercises, strict, name)
    if problem:
        fail(problem)

    # Every library `linked` names, so that the contract's own analysis checks
    # each is a grader_library() exporting the function (linked_problem()).
    libs = {}
    for e in exercises.values():
        for lib in e["linked"].values():
            libs[lib] = True
    subject_contract(
        name = "subject",
        contract = json.encode({
            "grader": grader,
            "group": group,
            "strict": strict,
            "exercises": exercises,
        }),
        libs = sorted(libs.keys()),
        lib_labels = sorted(libs.keys()),
        visibility = ["//visibility:public"],
    )

def subject_problem(grader, group, exercises, strict = True, name = "subject"):
    """What is wrong with a subject() call, as the message it fails with; None if nothing.

    A value for the reason exercise_problem() gives: proven on broken
    contracts by tools/tests/macro_fixtures, without a package that fails.

    Args:
        grader: as subject() takes it.
        group: as subject() takes it.
        exercises: as subject() takes it.
        strict: as subject() takes it.
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
    if type(exercises) != "dict" or not exercises:
        return "subject(exercises = ...): {\"NN\": exercise(...)}, one per exercise that turns something in"
    roots = []
    for num, e in exercises.items():
        if type(num) != "string" or len(num) != 2 or not num.isdigit():
            return "subject(exercises = ...): key %r -- the exercise number as a two-digit string, \"00\"" % (num,)
        if type(e) != "dict" or sorted(e.keys()) != sorted(_KEYS):
            return "subject(exercises = ...): %r is not an exercise(...) entry" % (num,)
        if e["dir"] == None:
            roots.append(num)
    if roots and len(exercises) > 1:
        return (("subject(exercises = ...): %s turn(s) in at the root of deliverable/ " +
                 "(dir = None), and the project has other exercises. A root turn-in " +
                 "is the whole repository, so it is the project's only exercise.") %
                ", ".join(roots))
    return None
