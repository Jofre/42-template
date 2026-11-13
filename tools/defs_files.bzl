"""c_files, c_issued and c_readme: the turn-in read as files.

The set of its names against the subject's turn-in line, a file 42 issues with
the subject, and a README the subject asks for.

Loaded by the files above it, and re-exported by tools/defs.bzl, the one
file a BUILD file loads.
"""

load(
    ":defs_contract.bzl",
    "turnin_dir",
    "turnin_file",
    "turnin_glob",
    _contract = "contract",
    _entry = "entry",
    _goal_of = "goal_of",
    _issued_problem = "issued_problem",
    _not_build_products = "not_build_products",
    _opt_values = "opt_values",
    _part_files = "part_files",
    _required = "required",
    _resolve = "resolve",
    _root_parts = "root_parts",
    _student_bin = "student_bin",
)
load(":defs_levels.bzl", _SUFFIX_LAYER = "SUFFIX_LAYER", _call = "call", _prefix = "prefix")
load(":defs_program.bzl", _PROGRAM_NAME_TAG = "PROGRAM_NAME_TAG")
load(":defs_test.bzl", "runner_quotes", "shell_word", _test = "test")
load(":names_file.bzl", "names_file")

def _built_programs(ex):
    """The names of the programs exercise `ex` builds, as declared above c_levels().

    c_make's artifact (its exNN_build test's --artifact) and c_program's
    name (the "program_name=" tag on its exNN_bin). A word with a / or a
    blank in it names no file of the turn-in, and is left out.
    """
    out = []
    build = native.existing_rule(ex + "_build")
    if build:
        out += _opt_values(list(build.get("args") or []), "--artifact")
    prog = native.existing_rule(ex + "_bin")
    if prog:
        for t in prog.get("tags") or []:
            if t.startswith(_PROGRAM_NAME_TAG):
                out.append(t[len(_PROGRAM_NAME_TAG):])
    return sorted({p: True for p in out if p and "/" not in p and " " not in p and "$" not in p}.keys())

def _turnin_names(name, d):
    """Declares names_file(name): every file of the turn-in tree `d`, by its path under `d`.

    The listing a files layer reads (--actual-list): d/** whole, less what
    //tools:submit never pushes (_not_build_products), and less a name
    holding a newline, which a list of lines cannot hold. One listing for
    c_files, a stray exercise's folder and a divided root's
    deliverable_files: three copies of it drifted once (a stray .o).

    Returns:
        ":" + name, the label of the listing.
    """
    names_file(
        name = name,
        names = [
            f[len(d) + 1:]
            for f in native.glob([d + "/**"], exclude = _not_build_products(d), allow_empty = True)
            if "\n" not in f
        ],
    )
    return ":" + name

def c_files(num = None, label = None, name = None, unit = None):
    """Deliverable file-set check (tag "files"), from the subject contract.

    The Moulinette looks at WHICH FILES were turned in before it looks at what
    they do. Nothing else here says it by name: a missing required file makes
    the other layers "not turned in" tests or stand-ins (see _test and
    _student_bin), which say the folder has nothing to check rather than which
    file the subject asks for, and an extra file is invisible entirely --
    while //tools:submit still pushes it to Vogsphere.

    c_levels() emits one for every exercise in the project's subject()
    contract, so a BUILD file does not call this: everything it checks is the
    contract's, and a list written at a call site would be a second copy of
    the subject's turn-in line. It stays public for a package that is not a
    project (tools/tests/macro_fixtures).

    What it reads from the contract:

      files      REQUIRED: a missing one FAILS, which is the whole point --
                 without this layer it is "nothing to check" somewhere else,
                 or nothing at all.
      optional   what may be there without a word: names, and patterns
                 expanded against the directory (rush-01's "*.c"), so any file
                 that is NOT one of them -- the binary a hand-run cc leaves
                 beside the sources -- is still reported.
      provided   what the GRADER brings. A copy in the turn-in is reported
                 under a heading of its own, since the student never turns
                 one in -- unless `optional` names it too (C 12 ex08's
                 ft_list.h, which page 5 asks for in every exercise).
      strict     an extra file FAILS rather than warns. Missing and extra are
                 different situations: the subject names its files exactly,
                 so a missing one is not arguable, whereas an extra one is
                 sometimes defensible (the Norm bans declaring a struct in a
                 .c file, so a rush that wants one needs a header the subject
                 never mentions).
      grader     how the warning about an extra file is worded: a person at
                 a defense can be told why it is there, a program cannot.

    The directory is the exercise's turn-in directory, globbed WHOLE: every
    file under it, each named by its path from there (srcs/main.c), because
    git pushes the tree and not one level of it. It used to be globbed flat
    unless the contract let files sit in subfolders, so a copy kept in old/
    or backup/ was never an input of any test and was pushed without a word
    (finding 102); a subfolder the contract does not allow now holds files
    nobody asked for, reported by path. Build products (*.o, *.a, *.out,
    *.gch) are left out at any depth, so having run `make` in deliverable/
    cannot fail you for producing what the exercise asked for --
    //tools:submit leaves them out of the push too -- and so is a .git
    directory, which git never pushes (_not_build_products).

    WHAT A MAKEFILE BUILDS. Where the exercise's program is built from what
    its Makefile compiles (c_program(makefile = True or "once_written"):
    BSQ, Rush 02, C 10, C 11 ex05, Reloaded ex27), that build writes the .c
    files `make -Bn` named (exNN_bin_sources.txt), and wherever else the
    contract has a Makefile turned in beside .c files allowed by pattern --
    an exercise with no c_program, its Makefile c_make's alone -- this
    declares a build for that list alone (exNN_make_bin_sources.txt,
    _manifest_build).
    This layer reads it: a .c the contract allows only as one of "the
    necessary files" and the Makefile never compiles is not necessary, and
    counts as an extra file (files_test.sh --built; finding 164). The list
    comes from native.glob, which sees the real directory at analysis time
    -- a test sandbox only ever contains files that were already declared,
    which is precisely the blind spot this closes. It reaches the runner as NAMES, in a file (tools/names_file.bzl),
    never as labels: this layer reads no file's contents, and it is the one
    layer that must report a file whose name no label can carry ("ft_putchar
    (1).c"), which every other layer drops (see _SAFE_CHARS).

    Args:
        num: the exercise number as a two-digit string ("00"). It names the
            target (exNN_files) and selects the contract entry.
        label: the heading the report is printed under; default None builds
            "<package>/<turn-in directory>". fail()s if a label contains a
            space: sh_test tokenises `args` on whitespace, so a two-word label
            would arrive as two arguments and the runner would reject the
            second as an unknown option.
        name: unused, for the reason c_levels gives: every macro takes one,
            and buildifier's unnamed-macro check holds this one to it since it
            declares a rule besides its test (the exNN_files_names list).
            Every target here is named from `num`.
        unit: in a package whose subject() contract is divided into units
            (units = {...}), the unit this call judges, in place of `num`: a
            library, the project, or one part of a root divided into parts
            (subject()'s units), by its name. A call names one of the two,
            never both (_resolve).
    """
    r = _resolve("c_files", num, unit, None)  # first: a contract error names this macro
    if r == False:
        return
    num = r.key
    e = _entry(num, "c_files")
    ex = _prefix(num)
    contract = _contract("c_files")
    if e["files"] == None:
        fail(("c_files(%s): the contract names no file for this exercise " +
              "(files = None), so there is nothing for a files layer to require.") % _call(num))
    d = turnin_dir(num)

    # sh_test args are shell-tokenised, so a label containing a space silently
    # becomes two arguments and the script rejects the second as an unknown
    # option. Catch it here, where the error names the cause.
    if label and " " in label:
        fail("c_files: label must not contain spaces (sh_test tokenises args): %r" % label)

    # A pattern is expanded against the directory, through turnin_glob(), so a
    # name no label can carry ("main (1).c") is never "allowed" by a *.c: it is
    # left for the report, which is the one place it is seen.
    optional = []
    for p in e["optional"]:
        if "*" in p:
            optional += [f[len(d) + 1:] for f in turnin_glob([d + "/" + p])]
        else:
            optional.append(p)
    provided = [v for v in e["provided"].values() if v not in optional]
    strict = contract["strict"] if e["strict"] == None else e["strict"]

    _turnin_names(ex + "_files_names", d)

    # ONE PART OF SEVERAL AT THE ROOT (subject()'s units): its own files, and
    # the other parts' as theirs. A file no part names is judged once for the
    # whole root, by deliverable_files (_parts_files).
    parts = _root_parts(contract)
    if num in parts:
        args = ["--label", label or (native.package_name() + "/" + d), "--grader", contract["grader"]]
        for f in e["files"]:
            args += ["--required", f]
        for f in optional:
            args += ["--optional", f]
        mine = e["files"] + optional
        siblings = []
        for other in parts:
            if other == num:
                continue
            for f in _part_files(_entry(other, "c_files"), d):
                if f not in mine and f not in siblings:
                    siblings.append(f)
        for f in siblings:
            args += ["--sibling", f]
        args += [
            "--actual-list",
            "$(rootpath :%s_files_names)" % ex,
            "--root",
            "--extras-elsewhere",
            "deliverable_files",
        ]
        _test(
            name = ex + "_files",
            srcs = ["//tools:files_test.sh"],
            args = args,
            data = [":%s_files_names" % ex],
            tags = ["files"],
        )
        return
    args = ["--label", label or (native.package_name() + "/" + d), "--grader", contract["grader"]]
    for f in e["files"]:
        args += ["--required", f]
    for f in optional:
        args += ["--optional", f]
    for f in provided:
        args += ["--provided", f]
    args += ["--actual-list", "$(rootpath :%s_files_names)" % ex]
    if strict:
        args.append("--strict")
    if e["dir"] == None:
        # The root of deliverable/: files left in an exNN/ folder there get
        # the command that moves them up (files_test.sh --root).
        args.append("--root")
    data = [":%s_files_names" % ex]

    # The .c files the Makefile compiles, where the program's build wrote
    # them: c_program(makefile = True) declared it above this call (c_levels()
    # emits this layer after every other macro of the module). Where no
    # build wrote one and the exercise turns in a Makefile beside .c files it
    # may name as it likes, a build for the list alone is declared here.
    built = _built_manifest(ex) or _manifest_build(num, e, d)
    if built:
        args += ["--built", "$(rootpath %s)" % built, "--build-target", ex + "_build"]
        data.append(built)

    # The programs the exercise builds, by name (_built_programs): a file of
    # that name in the turn-in is a build product, which fails even where
    # the subject leaves its file list open.
    for p in _built_programs(ex):
        args += ["--program", p]

    _test(
        name = ex + "_files",
        srcs = ["//tools:files_test.sh"],
        args = args,
        data = data,
        tags = ["files"],
    )

def c_issued(num, file, name = None):
    """A file 42 issues with the subject is in the turn-in (tag "output", basic).

    For a file tools/resources.tsv registers with the role turn-in: 42's own,
    which the template does not ship and its .gitignore keeps out of commits,
    and which the subject makes part of what is turned in -- Rush 02's
    numbers.dict, which the one-argument form `./rush-02 42` reads from where
    the program runs, under "Files to turn in: Makefile and all the necessary
    files". While it is missing the test FAILS, at basic: a SKIP exits 0, and
    //tools:submit would push a turn-in that cannot run at the defence
    (finding 162). A test of its own, not a `files` requirement of the
    contract, so that the files layer stays green on a fresh clone and this
    red reads as one more thing to do, beside the program's own.

    The contract names the file, in the exercise's `optional`, and this
    points at that entry: its path is turnin_file()'s, and loading fails
    unless the contract lists the name there (_issued_problem). Spelled here
    alone, the files layer called the file extra while this test demanded
    it, and nothing caught the two disagreeing.

    The file is found by a glob, never named as a label: absent on the
    template by design, a label would take the whole package down there. The
    test reads the registry's row for the path (tools/issued_test.sh), and its
    report is worded from it -- where to download the file, where it goes --
    so that it cannot disagree with the strip, the ignore rule, the
    placeholder and the docs, which read the same row. A path the registry
    does not list, or lists as a harness file, stops the test (exit 2).
    //tools:conventions checks that every turn-in row has its c_issued.

    Args:
        num: the exercise whose turn-in directory holds the file; the test is
            exNN_<file, dots and dashes as underscores>_issued.
        file: the name 42 gives the file, as the registry's `file` column
            and the exercise's `optional` in the contract list it.
        name: unused; every target is named from `num` and `file`.
    """
    problem = _issued_problem(num, file, _entry(num, "c_issued"))
    if problem:
        fail(problem)
    ex = _prefix(num)
    path = turnin_file(num, file)
    stem = "%s_%s" % (ex, file.replace(".", "_").replace("-", "_"))
    found = native.glob([path], allow_empty = True)
    pkg = native.package_name()
    names_file(
        name = stem + "_found",
        names = ["%s/%s" % (pkg, f) for f in found],
    )
    _test(
        name = stem + "_issued",
        srcs = ["//tools:issued_test.sh"],
        args = [
            "--registry",
            "$(location //tools:resources.tsv)",
            "--path",
            "%s/%s" % (pkg, path),
            "--found-list",
            "$(rootpath :%s_found)" % stem,
        ],
        data = ["//tools:resources.tsv", ":%s_found" % stem] + found,
        tags = ["output"],
    )

# The subject's sentences tools/readme_check.sh quotes: the basic check's
# keys, then the ones only --wording quotes.
_README_KEYS = ["file", "first-line", "sections"]
_README_WORDING_KEYS = ["ai", "language"]

def _readme_problem(num, file, quotes, sections, sentences, ai_section, ai_words, e):
    """c_readme()'s message when its arguments cannot make its two tests; None if they can.

    `e` is exercise `num`'s contract entry. The README must be in its
    `files`: a subject that asks for one says it "must be provided", the files
    layer then names it when it is missing, and the missing-file red says so.
    One in `optional` would be a file the subject lets the student leave out
    while this test demands it.
    """
    where = "c_readme(%s)" % _call(num)
    if type(file) != "string" or not file or "/" in file:
        return "%s: file = %r. It is the README's name, as the contract's `files` lists it." % (where, file)
    if file not in (e["files"] or []):
        return (("%s: file = %r is not in exercise %s's `files` (%s). A README the subject " +
                 "asks for is a file it requires: transcribe it into `files`.") %
                (where, file, num, e["files"]))
    want = sorted(_README_KEYS + _README_WORDING_KEYS)
    if type(quotes) != "dict" or sorted(quotes) != want:
        return (("%s: quotes = {key: sentence} with exactly the keys %s, each the subject's own " +
                 "words with where they are from; it has %s.") %
                (where, ", ".join(want), ", ".join(sorted(quotes)) if type(quotes) == "dict" else repr(quotes)))
    for what, words in [("sections", sections), ("sentences", sentences), ("ai_words", ai_words)]:
        if type(words) != "list" or not words:
            return "%s: %s is a list of one or more strings." % (where, what)
        for w in words:
            if type(w) != "string" or not w.strip() or "\n" in w or "\t" in w:
                return "%s: %s holds %r; each is one line of text." % (where, what, w)
    for s in sections:
        if [n for n in s.split("|") if not n.strip()]:
            return "%s: sections holds %r, with an empty name between its | marks." % (where, s)
    if type(ai_section) != "string" or not ai_section.strip() or "\n" in ai_section:
        return "%s: ai_section is the section that must mention AI, its names separated by |, as `sections` writes them." % where
    return None

def c_readme(num = None, file = None, quotes = None, sections = None, sentences = None, ai_section = None, ai_words = None, name = None, unit = None):
    """The README a subject asks the turn-in to carry, read as Markdown (tag "output").

    Two tests, both on tools/readme_check.sh, which reads the file and runs
    nothing of the student's:

      exNN_readme          basic, no language assumed: the file is there and
                           shows something (blank lines and HTML comments, the
                           stub, show nothing), its first line that shows
                           something is one span in italics (a heading whose
                           text is, too), and it has at least len(sections)
                           section headings.
      exNN_readme_wording  strict, this harness's reading in the words given
                           here: line 1 itself is in italics and reads one of
                           `sentences` and the login(s); a heading names each
                           of `sections`; the section `ai_section` names one of
                           `ai_words`.

    What the README says, and how well: no check reads that, and both tests
    say a peer does.

    The file is found by a glob, never named as a label, so a README that is
    missing makes these tests red rather than taking the package down; its
    path is turnin_file()'s, so loading fails unless the contract lets the
    exercise hold it. Every word the runner accepts and every sentence its
    messages quote is written here, at the call site (tools/runner_lib.sh, "A
    SUBJECT'S SENTENCE COMES FROM THE CALL SITE").

    Args:
        num: the exercise whose turn-in holds the README.
        file: its name, as the contract's `files` lists it ("README.md").
        quotes: {key: "Project, p.N: \\"the sentence\\""} for the keys file,
            first-line, sections (basic and strict) and ai, language
            (strict); split here into one runner_quotes() file per test.
        sections: one string per section the subject names, its accepted
            names separated by | ("Description|Descripción").
        sentences: the first-line sentences accepted at strict, each up to
            the logins, one per language the subject is printed in.
        ai_section: the section that must mention AI, written as in
            `sections`.
        ai_words: the words that name AI there, matched as words, in the
            case given.
        name: unused; the targets are named from `num`.
        unit: in a package whose subject() contract is divided into units
            (units = {...}), the unit this call judges, in place of `num`: a
            library, the project, or one part of a root divided into parts
            (subject()'s units), by its name. A call names one of the two,
            never both (_resolve).
    """
    r = _resolve("c_readme", num, unit, None)  # first: a contract error names this macro
    if r == False:
        return
    num = r.key
    _required("c_readme", file = file, quotes = quotes, sections = sections, sentences = sentences, ai_section = ai_section, ai_words = ai_words)
    problem = _readme_problem(num, file, quotes, sections, sentences, ai_section, ai_words, _entry(num, "c_readme"))
    if problem:
        fail(problem)
    ex = _prefix(num)
    path = turnin_file(num, file)
    found = native.glob([path], allow_empty = True)
    pkg = native.package_name()
    names_file(
        name = ex + "_readme_found",
        names = ["%s/%s" % (pkg, f) for f in found],
    )
    common = [
        "--path",
        shell_word("%s/%s" % (pkg, path)),
        "--found-list",
        "$(rootpath :%s_readme_found)" % ex,
    ]
    data = [":%s_readme_found" % ex] + found
    _test(
        name = ex + "_readme",
        srcs = ["//tools:readme_check.sh"],
        args = common + ["--min-sections", str(len(sections))] + runner_quotes(
            ex + "_readme_quotes",
            {k: quotes[k] for k in _README_KEYS},
        ),
        data = data + [":%s_readme_quotes" % ex],
        tags = ["output"],
    )
    wording = ["--wording"]
    for s in sentences:
        wording += ["--sentence", shell_word(s)]
    for s in sections:
        wording += ["--section", shell_word(s)]
    wording += ["--ai-section", shell_word(ai_section)]
    for w in ai_words:
        wording += ["--ai-word", shell_word(w)]
    _test(
        name = ex + "_readme_wording",
        srcs = ["//tools:readme_check.sh"],
        args = common + wording + runner_quotes(
            ex + "_readme_wording_quotes",
            {k: quotes[k] for k in _README_KEYS + _README_WORDING_KEYS},
        ),
        data = data + [":%s_readme_wording_quotes" % ex],
        tags = ["output"],
        level = _SUFFIX_LAYER["_readme_wording"][1],
    )

def _built_manifest(ex):
    """The label of the .c list `make -Bn` gave exercise `ex`'s Makefile, or None.

    Written by the plain program's build where c_program(makefile = True)
    declared one (_student_bin's sources_out): the files layer reads it to
    tell a source the Makefile compiles from one it never does.
    """
    r = native.existing_rule(ex + "_bin")
    if r and r["kind"] == "student_binary" and r.get("sources_out"):
        return ":%s_bin_sources.txt" % ex
    return None

def _manifest_build(num, e, d):
    """A build of exercise `num`'s Makefile for its .c list alone, declared; its label, or None.

    WHICH .c FILES THE MAKEFILE BUILDS, wherever the contract has the
    exercise turn in a Makefile and allows .c files by pattern ("Makefile,
    and files needed for your program"): a source the Makefile never
    compiles is no file it needs, and was one of the "files it allows"
    (finding 164). Called by c_files only where no program's build wrote
    the list already (_built_manifest) -- an exercise with no c_program,
    since one builds through its Makefile (_makefile_problem) -- so a Makefile
    is never built twice for it: c_make used to declare this wherever the
    contract allowed .c by pattern, and BSQ and Rush 02, whose programs
    write it, carried a second build that nothing read. Tagged manual, so
    only the files layer that reads it builds it. From the contract, not
    from a c_make call, so a Makefile project cannot leave it out.

    Args:
        num: the exercise, as its contract entry is keyed.
        e: its contract entry.
        d: its turn-in directory (turnin_dir(num)).
    """
    if "Makefile" not in (e["files"] or []) + e["optional"]:
        return None
    if not [p for p in e["optional"] if "*" in p and p.endswith(".c")]:
        return None
    ex = _prefix(num)
    if native.existing_rule(ex + "_make_bin"):
        # A library's, which c_library() declared (_library_includes).
        return ":%s_make_bin_sources.txt" % ex
    _student_bin(
        name = ex + "_make_bin",
        makefile = d + "/Makefile",
        make_goal = _goal_of(num),
        sources_out = ex + "_make_bin_sources.txt",
        make_data = turnin_glob([d + "/**"], exclude = _not_build_products(d)),
        tags = ["manual"],
    )
    return ":%s_make_bin_sources.txt" % ex


# ---------------------------------------------------------------------------
# WHAT THE FILES ABOVE THIS ONE LOAD OF IT. A load() cannot name a private
# symbol, so each one they use is given a public name here, its own without
# the underscore, and loaded back under its own name: the code reads as it did
# when tools/defs.bzl held it all. These names are for those files alone; a
# BUILD file loads //tools:defs.bzl.
built_programs = _built_programs
turnin_names = _turnin_names
readme_problem = _readme_problem
built_manifest = _built_manifest
manifest_build = _manifest_build
