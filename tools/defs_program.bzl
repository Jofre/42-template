"""c_program and c_argv_table: an exercise that owns main().

c_program runs it over its cases, with its allocfail layer
(_program_allocfail); c_argv_table runs it over a table of invocations, with
its argv guard.

Loaded by the files above it, and re-exported by tools/defs.bzl, the one
file a BUILD file loads.
"""

load(
    ":defs_checks.bzl",
    "allocfail_rule_problem",
    "fixed_array_problem",
    _argv_model_problem = "argv_model_problem",
    _case = "case",
    _case_run = "case_run",
    _case_stem = "case_stem",
    _cases_problem = "cases_problem",
    _compile_tests = "compile_tests",
    _emit_cases = "emit_cases",
    _emit_model = "emit_model",
    _forbidden_test = "forbidden_test",
    _makefile_problem = "makefile_problem",
    _malloc_argument_problem = "malloc_argument_problem",
    _memory_gate = "memory_gate",
    _memory_rule_problem = "memory_rule_problem",
    _missing_file_problem = "missing_file_problem",
    _model_problem = "model_problem",
    _norm_test = "norm_test",
    _provided_names = "provided_names",
    _raise = "raise_private",
    _reference_cases_test = "reference_cases_test",
    _reference_exit_problem = "reference_exit_problem",
    _shown_bin = "shown_bin",
    _survive_gate = "survive_gate",
    _survive_gate_prefix = "survive_gate_prefix",
)
load(
    ":defs_contract.bzl",
    "turnin_dir",
    "turnin_glob",
    _allowed = "allowed",
    _deliverable_hdrs = "deliverable_hdrs",
    _deliverable_srcs = "deliverable_srcs",
    _entry = "entry",
    _goal_of = "goal_of",
    _inc_args = "inc_args",
    _not_build_products = "not_build_products",
    _provided = "provided",
    _refuse = "refuse",
    _required = "required",
    _resolve = "resolve",
    _student_bin = "student_bin",
    _zone = "zone",
)
load(
    ":defs_levels.bzl",
    _MEMORY_GRADED = "MEMORY_GRADED",
    _MEMORY_GRADED_ACCESS = "MEMORY_GRADED_ACCESS",
    _call = "call",
    _memory_graded = "memory_graded",
    _prefix = "prefix",
    _uniq = "uniq",
)
load(
    ":defs_test.bzl",
    _ARGV_GUARD_SUFFIX = "ARGV_GUARD_SUFFIX",
    _memcheck_allowed = "memcheck_allowed",
    _no_orphan_prototype = "no_orphan_prototype",
    _test = "test",
    _waiting_args = "waiting_args",
)
load(
    ":defs_toolchain.bzl",
    _CAMPUS_CCS = "CAMPUS_CCS",
    _DIFF = "DIFF",
    _SYMBOLIZER_DATA = "SYMBOLIZER_DATA",
    _symbolizer_args = "symbolizer_args",
)
load(":names_file.bzl", "names_file")

def c_program(
        num = None,
        name = None,
        cases = None,
        srcs = None,
        hdrs = None,
        progname = False,
        malloc = None,
        makefile = False,
        no_missing_file_case = None,
        model = None,
        reference = False,
        refusals = None,
        memory_rule = None,
        allocfail = None,
        allocfail_rule = None,
        allocfail_leaks = False,
        allocfail_leaks_rule = None,
        no_allocfail = None,
        fixed_array = None,
        fixed_array_bytes = None,
        unit = None):
    """A program exercise: the deliverable owns main() and is run with argv.

    Args:
        num: the exercise number as a two-digit STRING ("00"; an int fails at
            analysis on "ex" + num). Every target this macro emits is named
            from it -- exNN_bin, exNN_bin_asan, exNN_norm, exNN_compile_clang,
            exNN_compile_gcc, exNN[_case]_output -- and it is what points the
            macro at deliverable/exNN and tests/exNN.

            fail()s if tests/exNN/prototype.h exists. A program exercise gets
            no prototype layer, because its entry point is main() and the
            compiler already fixes that signature, so a contract header here is
            wired to nothing and can only be a leftover: delete it, or move the
            exercise to a macro that reads one.
        name: the program's name, as the subject gives it ("Executable
            name: rush-02"). Unlike a rule's `name` it names no target --
            every target comes from `num` -- and no source is looked for
            under it: an empty deliverable/exNN makes the program a stand-in
            that says there is no .c file (see _student_bin), not a Bazel
            error about a file named after it. A "cwd_files" case runs the
            program under it, as ./<name>, so there it must be a file name.
            It is read in three more places, so a name other than the
            subject's is wrong in each: exNN_files fails a file of that name
            in the turn-in as a build product (_built_programs, at basic,
            and //tools:submit refuses to push it); with reference = True
            it is the program `oracle run` is given; and //tools:conventions
            holds a .gitignore to keep it out of commits, where no c_make
            builds the exercise. Where one does (makefile = True or
            "once_written"), it is the same program the Makefile builds:
            give c_make's `artifact` here too. The build runs on the
            Makefile and never on this name, and the .gitignore check reads
            the artifact there, so a name that differs is a second program
            the files layer refuses: c_levels()' audit fails the package.
        cases: the argv invocations to run, as a list of dicts. Default None
            emits no run at all, leaving the static layers and the two
            binaries; that is a real configuration rather than an oversight,
            since c-06 ex01-ex03 drive their runs from c_argv_table() instead,
            which picks :exNN_bin and :exNN_bin_asan up by name. Every case
            gets an output test and an ASan/UBSan run; where the subject lets
            the program allocate (`malloc`, below) it also gets a valgrind
            arm. Every case is checked while loading
            (_case, _CASE_KEYS): a key this shape does not take, or no kind,
            fails naming the case. Its KIND is exactly one of:
                "expected": the expected-output file's name under tests/exNN/
                            (a bare name, not a label): the output, exactly.
                "any_of":   two or more such names: the output is one of
                            them, where the subject leaves the reading open
                            and bounds it. The report compares with the first
                            and names the others.
                "survive":  True: no output is compared. The case passes when
                            the program ends by itself -- no signal, no hang,
                            no runaway output. What every reading of an open
                            case agrees on. Its report says what it ran, and
                            it SKIPs while the exercise's first case at basic
                            is red (_survive_gate): an unwritten program ends
                            by itself too.
            And its other keys:
                "name":     infix for this case's targets, default "run". With
                            a single case the targets take the plain exNN form
                            the rest of the repo uses (exNN_output, exNN_asan);
                            with several they become exNN_<name>_output.
                "level":    raise this case above basic (2 strict, 3 robust,
                            4 complete): a case the subject leaves open, or a
                            rigour of this repo's (docs/reference.md, "Run
                            contract"). Every arm of the case sits at least
                            there; a raise is listed in _RAISED.
                "args":     the argv, default []. $(location ...) is expanded
                            here, so a fixture can be passed as an argument.
                            sh_test tokenises `args` on whitespace, so an
                            argument that must itself contain spaces has to
                            carry embedded quotes -- see the Q constant and the
                            long comment above it in rush-01's BUILD.bazel.
                "fixtures": labels of the files the run reads; they are staged
                            into the output, valgrind and asan targets alike,
                            and are what makes $(location ...) inside "args"
                            resolvable.
                "stdin":    a package-relative LABEL (not a bare name under
                            tests/exNN/) fed to the program on stdin -- in the
                            output, valgrind and asan arms alike, so the three
                            cannot end up running different things.
                "argv_file": a package-relative LABEL of a file holding more
                            arguments, one per line, passed after "args": an
                            empty line is an empty argument, a line with
                            spaces one argument. What `args` cannot say,
                            since Bazel drops "" and splits on spaces.
                "cwd_files": {LABEL: NAME}: run the program as ./NAME-of-
                            the-program (this macro's `name`) from a folder
                            of its own, holding only a copy of it and a copy
                            of each LABEL under NAME: the subject's
                            `./rush-02 42` beside numbers.dict. "args" then
                            names those files by NAME, and a $(location)
                            in them is refused (it would not resolve there).
                "stream":   "stdout" (the default) or "stderr": which one is
                            compared. The other is still shown under the table
                            when the case fails, because it is usually where
                            the explanation is.
                "sanitize": a leading 16-hex-digit address column, which
                            ASLR moves (hexdump-shaped output): each row's
                            address is checked against the one the program
                            published on an "@addr <16 hex>" line before the
                            dump, and a right one is shown as its offset from
                            the first row of its block. Where nothing was
                            published only the width, case and +16 step are
                            compared (see --sanitize in diff_output.sh).
                "labeled":  every line is "CASE<TAB>VALUE" and the CASE gets a
                            column of its own; without it the CASE column is
                            just the 1-based line number.
                "clues":    name of a clues.tsv under tests/exNN/ whose hints
                            are rendered below the table when this case fails.
                            Reaches the output arm AND the valgrind arm; the
                            latter renders the hint column alone, capped at
                            three, because a leak report has no per-case table
                            to attach hints to. A row may name this case
                            ("name" above) as its label: it then fires when
                            this case fails and on no other case, where a
                            row with no label fires on every failure. A row
                            labelled "valgrind" fires in the valgrind arm of
                            every case and in no output arm, which is why no
                            case may be named "valgrind". A program keeps one
                            such file per exercise, its rows keyed to the
                            cases, rather than a file per case
                            (docs/reference.md, "Writing a c_program case").
                "exit":     the status this case must return, judged where
                            the Run contract (docs/reference.md) puts it: in
                            exNN[_case]_output, at basic, when "exit_quote"
                            is given too -- at strict when the case also has
                            "level": 2, where the sentence is read as naming
                            it (C 10's "performs the same function as the
                            system's tail": the tool's own status); otherwise
                            in the robust twin exNN[_case]_exit. Tested for
                            presence, not truth, so "exit": 0 really does pin
                            "exits 0".
                "exit_quote": the subject's sentence that names "exit" (or,
                            with "level": 2, that is read as naming it). A
                            status the subject does not name is never checked
                            at basic, and this key is what says it does: no
                            quote, no basic check. The runner shows it beside
                            a wrong status (--exit-quote), so it is a string
                            with no ASCII single quote and no $: write the
                            apostrophe as the subject prints it, a
                            typographic one.
                "invalid_input": True where the subject answers this input
                            with an error -- a message it names, such as
                            "Error", "map error" or a missing file's
                            diagnostic -- not merely where it calls the
                            input invalid: do-op prints 0 for an "invalid
                            operator", an ordinary output, and its cases
                            are not marked. With no "exit", its status is
                            then judged at no level: the subject names none,
                            and a non-zero one is what an error conventionally
                            returns. So is an "any_of" or "survive" case's,
                            whose reading the subject leaves open.
                            "invalid_input": False says the opposite, and says
                            it on purpose: the subject answers this input with
                            an ordinary output, so the case gets the robust
                            twin, which expects 0 -- the C convention for a
                            run that did its job -- and its output test notes,
                            without failing, any other return. A case with
                            none of these keys and no "exit" gets the same
                            twin by DEFAULT (--exit-source default), and a
                            default is not a decision where the case expects
                            an error: one that compares stderr is refused at
                            loading until it says True, False or "exit"
                            (_case_exit_error), and a twin whose expected
                            output mentions an error refuses to run (exit 2,
                            naming the key; diff_output.sh).
                "missing_file": the operand in "args", word for word, that
                            names no file: the run hands the program a name
                            that will not open (no_such_file_exNN). It is
                            checked while loading -- an operand of the case,
                            not a fixture, an option, "-", "." or ".." -- and
                            at run time: the output test stops (exit 2, a
                            harness error) if something by that name is
                            where the program runs (diff_output.sh --absent).
                            The case says what its status means, as a stderr
                            case does ("invalid_input", "exit", or an
                            "any_of" or "survive" kind). Where the contract
                            allows open, one case at least carries it, or
                            no_missing_file_case says why none does.
                "valgrind": default True; False drops the valgrind arm for this
                            one case. Read only where the subject lets the
                            program allocate (`malloc`).
            Any other key fail()s at loading (_CASE_KEYS), naming the key it
            was probably meant to be: a misspelt "invalid_input" used to be
            ignored in silence and produce an _exit twin expecting 0.
            Every arm of every case opens its report with a RAN line: the
            command it ran, which runs it again from the repository root --
            or, for a "cwd_files" case, from a folder holding the files
            listed under the line (tools/runner_lib.sh's rl_ran).
        srcs: the deliverable's sources. Default None globs them as the
            contract lets them lie (turnin_dir()/*.c, and subfolders where it
            says so) -- the file set is written down once, in the subject()
            contract, to be CHECKED against the directory rather than to drive
            the build. Pass a list only where the glob is wrong.
            Headers must NOT be routed through here: forbidden_symbols.sh
            compiles each --src and reads its symbols, and hands a .h back as
            exit 2, a harness error. That is what `hdrs` is for.
        hdrs: headers that belong to the deliverable. With `srcs` left at its
            default they default to every deliverable/exNN/*.h, after any
            listed here (see _deliverable_hdrs); with explicit `srcs` they are
            exactly what is listed, default none. They are staged for both
            program builds alongside the sources, so a deliverable that
            #includes its own header still builds for every layer that RUNS
            it. They also reach the static layers: the norm layer NORMS them
            beside the sources (the Norm applies to headers too), while the two
            compile layers and the forbidden layer stage them and compile with
            the GRADER's include path (_inc_args): a header's directory joins
            it only where the header sits beside the sources, and a Makefile
            project's is the -I its recipes pass. C 10, C 11 ex05 and
            Reloaded ex27 leave the file layout to the student and pass none:
            before the default, a student header there was "file not found"
            for every layer and never normed.
        progname: default False. True emits exNN_progname (tag "output", so it
            gates at level basic): the binary is copied under two names --
            "a.out", matching the subject's example, and one unrelated name --
            run as ./<name> each time, and must print exactly its own argv[0]
            plus a newline on both, without dying. The renamed run is the one
            that proves anything, since a program that hardcodes "./a.out"
            passes the first. A plain non-zero return is only noted there: the
            subject names no exit status, so by the rule in docs/reference.md
            ("Run contract") it fails at robust, in exNN_progname_exit (tag
            "output", raised to level 3), which runs the same two names and
            judges nothing but how each run ended. It also emits
            exNN_progname_asan (tag "asan"), which runs the INSTRUMENTED binary
            once, bare -- no rename, no arguments, output not compared --
            because argv[0] is where this exercise can walk off the end of a
            string it does not own, and a diff of one short line cannot see a
            read that returns the right bytes. c-06 ex00 is the only caller.
        THE FORBIDDEN LAYER'S LIST is the contract's `allowed` plus its
            `variables` (C 10's errno), as for c_function; a contract `allowed
            = None` emits no forbidden layer. What is checked is each object's
            UNDEFINED symbols, so anything the deliverable itself defines is
            always fine. Where glibc compiles a name into another symbol
            (__errno_location, __xpg_basename, __ctype_b_loc), the runner's
            alias table maps it back. What the grader brings (the contract's
            `provided`: Reloaded's ft_putchar.c) both programs link; norm,
            compile and forbidden see the student's `srcs` alone.
        malloc: never passed. Whether the program may allocate is the
            subject's "Allowed functions" line, read from the contract as
            corpus_memory() reads it (_memcheck_allowed: malloc named there,
            or no such line at all). Where it may, every case gets a
            valgrind arm (exNN[_case]_valgrind, tag "valgrind", level
            strict), each gated on that case's own output fixture so a stub
            is met with "your output layer is still red" rather than with a
            memcheck report; a "survive" case has no fixture, and its arm
            waits on the case its output test waits on (_survive_gate). A
            program that cannot allocate has nothing to leak.
            It used to be an argument, typed at each call beside the
            contract that already said it, so the two could disagree; a call
            that still passes it is refused while loading.
        memory_rule: the subject's own sentence about memory, naming where it
            is from (Rush 02, p.7: "Any memory allocated on the heap ... must
            be freed correctly."), for the valgrind arms to quote when one
            fails. Default None: they quote the contract's memory_graded
            where it declares one, and otherwise state the rule the layer
            applies and say it is this repo's, since most subjects have no
            such sentence (finding 082). Needs a subject that lets the program allocate
            (`malloc`). One line; written to a file
            (exNN_memory_rule), since sh_test tokenises `args` on blanks.
        makefile: True for a project whose subject mandates a Makefile and
            then leaves the file names to the student ("Makefile and all the
            necessary files": BSQ, Rush 02). Default False keeps the ordinary
            path, where `srcs` is the program and Bazel links it directly.
            "once_written" is True once the Makefile compiles anything, and
            until then -- no Makefile, or a stub whose recipes only echo --
            builds every source of the folder as the program, with no -I
            (tools/student_build.sh, UNTIL THE MAKEFILE IS WRITTEN): for an
            exercise whose program is most of the work and its Makefile a
            line of it (C 10, C 11 ex05, Reloaded ex27), whose output tests
            a student reads before the Makefile exists. A Makefile written
            and broken is a stand-in all the same. False is refused where
            the subject() contract has the exercise turn in a Makefile
            (_makefile_problem): the subject builds the program with it.

            When True, the two binaries are built by asking `make -Bn`, run on
            the Makefile at the top of the turn-in directory, which .c files
            the default goal compiles and which -I directories it passes (see
            tools/student_build.sh's Makefile mode), with the whole turn-in
            directory staged beside it -- every subfolder too, where the
            contract lets files sit in them (srcs/, includes/): a Makefile may
            include or read anything next to it. `srcs` then no longer has to
            BE the program -- it can stay the contract's glob, because the
            layers it still feeds (norm, both compile layers, forbidden)
            compile each file on its own and never link, so a second entry
            point among them is not their problem. An empty turn-in is the
            student's state, not a BUILD-file bug: its programs are stand-ins
            saying there is no Makefile. Nothing the grader brings is linked
            in: the Makefile decides what is compiled. Refused where the
            contract's `files` do not hold that Makefile: every output test,
            at basic, runs the program it builds (_make_anchor_problem).
        no_missing_file_case: a sentence saying why no case of this program
            names a file that will not open, where its contract allows `open`
            (one whose files are all fixed names, or all on standard input).
            Default None, and then such a program's `cases` must hold one, a
            case with "missing_file" (_missing_file_problem). A case about a
            file's CONTENT is not that path: BSQ had five invalid maps and
            Rush 02 four broken dictionaries, all files that open, and no
            case naming one that does not -- and neither had C 10's ex02 and
            ex03, which had no error case at all (finding 110). A sentence
            given beside such a case fails too, as one given where the
            contract does not allow open: a reason that is not true is worse
            than none.
        model: where the cases' expected files came from, when a model of the
            tool the program imitates made them: the //oracle command a case's
            "args" follow, as a list of words (C 10 ex01: ["c10_run",
            "--prog", "ex01_bin", "cat"]). Default None. With it, each case
            with one expected file also gets exNN[_case]_model (layer oracle,
            complete; tools/model_check.sh), which runs that command on the
            case from where its program runs -- the same arguments, standard
            input, argument file, run folder and name that will not open --
            and fails when the file, on the stream the case compares, or the
            status it names in "exit", is not what the model answers. It runs
            nothing of the student's. A fixture made once and never re-made
            drifts in silence: a later fix to the model, or an edit by hand,
            showed first as a correct program going red (review of WP-50).
            Refused with no case that has one expected file, and beside a
            "sanitize" case (_model_problem).
        reference: default False. True when //oracle holds this program's
            reference, run as `oracle run <name> ARG...`: it then emits
            exNN_reference_cases (tag "oracle", complete), which runs EVERY
            case through diff_output.sh exactly as its output test does --
            the same argv, argument file, run folder, stdin and expected
            file(s) -- with the reference in the student's place, and fails
            a case the reference does not pass (tools/reference_cases.sh).
            It runs no student code, so it says the same on any tree, the
            template's stubs included. Rush 02's cases bound a dictionary and
            a number to an expected file by hand, in two places -- the
            oracle's pairs, which write the files, and the cases here -- and
            an edited number passed, since no correct program ran on the
            owner's tree: the reference now runs the case as written.
            Its status says whether it has an answer, so a case whose output
            test compares a status other than 0 is refused
            (_reference_exit_problem).
        refusals: for tools/tests/macro_fixtures only, where a list: a refusal
            this macro makes once its arguments are read (no_missing_file_case
            and the case it asks for, `model`, `reference`'s statuses) is
            appended there instead of failing the load, and nothing is
            emitted -- so a fixture can watch the real macro refuse
            (_refuse). Anywhere else it fails.
        allocfail: the name of one of `cases`, replayed with ONE of the
            program's own malloc() calls refused per run (allocfail_check.sh
            --bin): exNN_program_allocfail, at robust; or a list of them, one
            sweep each, the first exNN_program_allocfail and each other
            exNN_<case>_program_allocfail -- a program allocates on some paths
            and not on others, so pick cases that allocate (a large input, an
            error found part-way through), and a case on which it allocates
            nothing says so (NOTHING TO REFUSE, green). The program is built
            again as exNN_bin_allocfail, beside tools/allocfail_program.c with
            malloc and free wrapped (a Makefile project through its own
            `make -Bn`). It asks what every reading of a subject's rule for
            errors agrees on: the run ends by itself -- no signal, within its
            time -- with bounded output. No text and no status are asserted:
            what a program prints or returns on this path is its subject's to
            say, and this target reads nothing into it. ROBUST, not basic: no
            42 grader refuses a program an allocation, so this is the repo's
            rigour (WP-92, finding 150). Gated on the case's own output, like
            its valgrind arm; a large count of requests is sampled, first ones
            then spread to the last. Needs a subject that lets the program
            allocate (`malloc`) and `allocfail_rule`; default None, no target.
        allocfail_rule: why this program is asked it, as one string, required
            with `allocfail` (allocfail_rule_problem): the subject's own
            sentence, quoted, or -- for a subject with none, as C 10's -- what
            the call site reads in it, said as a reading. The report prints
            it under its verdict; the runner names no subject sentence of its
            own, since it cannot know which subject it is reading. One line;
            written to a file (exNN_program_allocfail_rule) and handed to the
            runner as --rule, as c_function's allocfail_rule is.
        allocfail_leaks: True adds exNN_program_allocfail_leaks, at robust:
            the same sweep, judging whether a run that ended by itself still
            held a block it obtained at exit -- what the valgrind arm asks of
            the plain run (still-reachable counts). Needs `allocfail`, a
            subject that allows free, and `allocfail_leaks_rule`; for a subject
            that says heap memory "must be freed correctly" (Rush 02). Default
            False.
        allocfail_leaks_rule: the freeing rule that target applies, as
            `allocfail_rule` is the sweep's: the leak target prints this one,
            because the reason to ask what a run holds at exit is a different
            sentence from the reason to refuse it memory. Required with
            `allocfail_leaks`; written to exNN_program_allocfail_leaks_rule.
        no_allocfail: why this program has no allocfail sweep, as a sentence,
            where its subject lets it allocate and it has cases: then one of
            `allocfail` and this is required, and both are refused
            (program_allocfail_choice_problem). A sweep missing by omission
            reads as one nobody needed; a sweep left out says why. Refused
            where nothing asks for it (a subject that does not let the
            program allocate, or runs driven elsewhere, cases = None): a
            reason that is no longer true is worse than none. Default None.
        fixed_array: the subject's sentence asking for a fixed-size array
            ("You must complete this exercise by declaring a fixed-size
            array"), quoted with where it is from: emits exNN_fixed_array,
            the method layer at strict (tools/method_check.sh
            --fixed-array), which has the pinned gcc name every array of
            variable length and every alloca in the sources, and prints this
            sentence under its verdict. One line; written to
            exNN_fixed_array_rule. Default None, no target.
        fixed_array_bytes: where the subject bounds that array, the bound in
            bytes: every object of the program, on the stack or not, must be
            smaller, by the size gcc gives it -- an upper bound only, since
            "slightly less than" says no lower one. The sentence in
            `fixed_array` then says how the subject's unit was read
            (fixed_array_problem). Default None, no bound.
        unit: in a package whose subject() contract is divided into units
            (units = {...}), the unit this call judges, in place of `num`: a
            library, the project, or one part of a root divided into parts
            (subject()'s units), by its name. A call names one of the two,
            never both (_resolve).
    """
    r = _resolve("c_program", num, unit, refusals)  # first: a contract error names this macro
    if r == False:
        return
    num = r.key
    _required("c_program", name = name)
    _entry(num, "c_program")
    ex = _prefix(num)
    _no_orphan_prototype(ex, "c_program")
    if [c for c in (cases or []) if type(c) == "dict" and c.get("cwd_files")]:
        if (type(name) != "string" or not name or name in [".", ".."] or
            [ch for ch in ["/", " ", "\t", "'", "\""] if ch in name]):
            fail(("c_program(%s): name = %r, and a \"cwd_files\" case runs the " +
                  "program as ./<name>: give the subject's executable name.") % (ex, name))
    if makefile not in (True, False, "once_written"):
        fail(("c_program(%s): makefile = True, \"once_written\" or False. The Makefile " +
              "is the one at the top of the turn-in directory the subject() contract " +
              "names.") % ex)

    # A part built by a rule of its own (its contract's goal): its program is
    # what that rule builds, and nothing else.
    goal = _goal_of(num)
    if goal != None and makefile != True:
        fail(("c_program(%s): this part is built by a rule of its own (make %s), so its " +
              "program is what that rule builds: makefile = True.") % (ex, goal))
    allowed = _allowed(num)

    # Before anything is declared, so a refusal a fixture watches emits nothing.
    # A Makefile it builds from is one the contract requires (finding 124's
    # class, as c_make holds it), and a Makefile the contract requires is
    # the one it builds from (_makefile_problem): together, makefile is on
    # exactly where the contract's `files` hold a Makefile.
    if makefile and _refuse(
        _make_anchor_problem(num, "Makefile", _entry(num, "c_program"), "c_program"),
        refusals,
        "c_program(%s)" % ex,
    ):
        return
    if _refuse(_makefile_problem(ex, makefile, _entry(num, "c_program")["files"]), refusals, "c_program(%s)" % ex):
        return
    if _refuse(_malloc_argument_problem(ex, malloc), refusals, "c_program(%s)" % ex):
        return
    malloc = _memcheck_allowed(_entry(num, "c_program"))

    # Every case is a dict of known keys before any check below reads one
    # (_cases_problem): a case that is no dict stopped the load on a
    # Starlark error that named neither this call nor the case.
    if _refuse(_cases_problem(cases, "program", "c_program(%s)" % _call(num), name), refusals, "c_program(%s)" % ex):
        return
    if _refuse(_missing_file_problem(ex, allowed, cases, no_missing_file_case), refusals, "c_program(%s)" % ex):
        return
    if _refuse(_model_problem(ex, model, cases), refusals, "c_program(%s)" % ex):
        return
    if _refuse(_reference_exit_problem(ex, reference, cases), refusals, "c_program(%s)" % ex):
        return
    if _refuse(_memory_rule_problem(num, malloc, cases, memory_rule), refusals, "c_program(%s)" % ex):
        return
    af_choice = program_allocfail_choice_problem(
        malloc,
        cases,
        allocfail,
        no_allocfail,
        allocfail_rule,
        allocfail_leaks_rule,
    )
    if _refuse(af_choice and "c_program(%s): %s" % (ex, af_choice), refusals, "c_program(%s)" % ex):
        return
    if srcs == None:
        srcs = _deliverable_srcs(ex)
        hdrs = _deliverable_hdrs(ex, hdrs)
    srcs = _zone(srcs)
    hdrs = _zone(hdrs or [])
    provided_srcs = _provided(num).srcs
    if makefile and provided_srcs:
        fail("c_program(%s): the contract has the grader bring a source, which " % ex +
             "has no effect with makefile = True -- the Makefile decides what is compiled.")

    # What is built while the Makefile is missing or compiles nothing:
    # every source of the folder, with makefile = "once_written".
    fallback_srcs = srcs if makefile == "once_written" else None

    # Both programs, plain and instrumented, from the same files. The headers
    # are staged with the sources: a sandbox holds only what a build declares,
    # so a deliverable that #includes its own header would otherwise fail with
    # "file not found" in every layer that RUNS it while norm and both compile
    # layers, which stage `hdrs`, stayed green. They must not be routed through
    # this macro's own `srcs` parameter, though: forbidden_symbols.sh would then
    # try to read symbols out of a .h and exit 2 as a harness error.
    #
    # The instrumented one is built UNCONDITIONALLY, outside the `if cases`
    # below. It used to sit inside it, which quietly excluded the exact module
    # the memory layer exists for: c-06 ex01-ex03 drive their runs from
    # c_argv_table, not from `cases`, so they passed no cases and got no
    # sanitizer at all. c_argv_table picks this target up by name for its own
    # asan arm -- an absent one there is a hard analysis error, not a skip.
    binname = ex + "_bin"
    asan_bin = ex + "_bin_asan"

    # A Makefile project's include path is the -I its recipes pass, and only
    # `make -Bn` knows it: the plain program's build writes it here, and the
    # compile and forbidden layers below compile with it (see _inc_args).
    inc_file = (binname + "_includes.txt") if makefile else None
    for target, asan in [(binname, False), (asan_bin, True)]:
        # The program's name, for the files layer (_built_programs).
        name_tag = [] if asan else [_PROGRAM_NAME_TAG + name]
        if makefile:
            _student_bin(
                name = target,
                tags = name_tag,
                makefile = turnin_dir(num) + "/Makefile",
                make_goal = goal,
                srcs = fallback_srcs,
                includes_out = None if asan else inc_file,
                # And the .c files it compiles, for the files layer
                # (_built_manifest): the same `make -Bn`, read once.
                sources_out = None if asan else binname + "_sources.txt",
                # The WHOLE tree under it, whatever the contract lets lie
                # there: which files the program is made of is the Makefile's
                # to say, and a source it names that was left unstaged would
                # read as one missing from the turn-in. Where the layout
                # breaks the subject, the files layer says so.
                make_data = turnin_glob(
                    [turnin_dir(num) + "/**"],
                    exclude = _not_build_products(turnin_dir(num)),
                ),
                hdrs = hdrs,
                asan = asan,
            )
        else:
            _student_bin(
                name = target,
                tags = name_tag,
                srcs = srcs + provided_srcs,
                hdrs = hdrs,
                archive = False,
                dir = turnin_dir(num),
                asan = asan,
            )
    _norm_test(ex + "_norm", srcs + hdrs)
    _compile_tests(ex, srcs, hdrs, inc_file = (":" + inc_file) if inc_file else None)
    _fixed_array_test(ex, num, fixed_array, fixed_array_bytes, srcs, hdrs, inc_file)

    if progname:
        _test(
            name = ex + "_progname",
            srcs = ["//tools:progname_test.sh"],
            args = [
                "--diff",
                "$(location %s)" % _DIFF,
                "--bin",
                "$(location :%s)" % binname,
            ],
            data = [":" + binname, _DIFF],
            tags = ["output"],
        )

        # The exit status, at robust: see `progname` above and docs/reference.md.
        _test(
            name = ex + "_progname_exit",
            srcs = ["//tools:progname_test.sh"],
            args = [
                "--exit-only",
                "--bin",
                "$(location :%s)" % binname,
            ],
            data = [":" + binname],
            tags = ["output"],
            level = 3,
        )

    # Memory layer for the program shape, on :exNN_bin_asan above. c_function
    # exercises get three (c_mem_check, diff_asan, the probe under memcheck);
    # c_program got NONE, leaving c-06, c-10 and c-11 ex05 -- twelve exercises
    # that read files, walk argv and index buffers -- never built with a
    # sanitizer at all. valgrind only covers the ones that malloc, and stdout
    # diffing structurally cannot see an out-of-bounds read that returns the
    # right bytes.
    if progname:
        # The same run as exNN_progname, under the sanitizer. argv[0] handling is
        # where this exercise can walk off the end of a string it does not own.
        _test(
            name = ex + "_progname_asan",
            srcs = ["//tools:asan_run.sh"],
            args = [
                "--bin",
                "$(location :%s)" % asan_bin,
                "--label",
                "%s/progname" % ex,
            ] + _symbolizer_args(),
            data = [":" + asan_bin] + _SYMBOLIZER_DATA,
            tags = ["asan"],
        )

    if type(reference) != "bool":
        fail(("c_program(%s): reference = True or False: True runs every case with " +
              "`oracle run %s`, //oracle's reference for the program.") % (ex, name))
    if reference and not cases:
        fail(("c_program(%s): reference = True, and there is no case for the reference " +
              "to run. Drop it, or give the program its cases.") % ex)

    # The gate a survive case waits on (_survive_gate): the same for every
    # survive case and every arm, so worked out once, and only where some
    # case survives.
    survive = ([], [])
    if [c for c in (cases or []) if type(c) == "dict" and c.get("survive")]:
        survive = _survive_gate(ex, cases)
    if cases:
        rule = None
        if memory_rule:
            names_file(
                name = ex + "_memory_rule",
                names = [memory_rule],
            )
            rule = ":%s_memory_rule" % ex
        elif _memory_graded():
            # No sentence of the call's own: the contract's, which puts
            # these arms at basic (memory_graded).
            rule = ":" + _MEMORY_GRADED
        _emit_cases(
            ex,
            binname,
            cases,
            name,
            valgrind = malloc,
            memory_rule = rule,
            # The contract's sentence on an invalid access, whoever's the
            # sentence on a leak is.
            access_rule = (":" + _MEMORY_GRADED_ACCESS) if _memory_graded() else None,
            survive = survive,
        )
        if model:
            _emit_model(ex, cases, model, name)
        if reference:
            _reference_cases_test(ex, cases, name)

        for c in cases:
            k = _case(c, "program", "c_program(%s)" % _call(num))
            stem = _case_stem(ex, cases, k.name)
            run_flags, run_files = _case_run(c, name)

            # A survive case's run under the sanitizer waits on the same case
            # its output test does (_survive_gate): a program nobody has
            # written ends by itself, memory-clean, so its asan arm was green
            # on every stub while the output test said SKIP.
            gate_args, gate_data = survive if k.survive else ([], [])
            if gate_args:
                gate_args, head_data = _survive_gate_prefix(binname, gate_args, survive_flag = False)
                gate_data = gate_data + head_data
            a_args = [
                "--bin",
                "$(location :%s)" % asan_bin,
                "--label",
                stem,
                "--show-run",
                _shown_bin(asan_bin),
            ] + gate_args + run_flags + _symbolizer_args() + ["--"] + c.get("args", [])
            _test(
                name = "%s_asan" % stem,
                srcs = ["//tools:asan_run.sh"],
                args = a_args,
                data = _uniq([":" + asan_bin] + run_files + gate_data + _SYMBOLIZER_DATA),
                tags = ["asan"],
                level = _raise("asan", k.level),
            )
    if allocfail != None or allocfail_leaks:
        why = program_allocfail_problem(
            allocfail,
            [c.get("name", "run") for c in (cases or [])],
            malloc,
            allocfail_leaks,
            allowed,
            allocfail_rule,
            allocfail_leaks_rule,
        )
        if why:
            fail("c_program(%s): %s" % (_call(num), why))
        _program_allocfail(
            ex,
            num,
            name,
            cases,
            allocfail,
            allocfail_rule,
            allocfail_leaks_rule if allocfail_leaks else None,
            binname,
            makefile,
            srcs,
            hdrs,
            provided_srcs,
            survive,
        )
    if allowed != None:
        _forbidden_test(
            ex + "_forbidden",
            srcs,
            allowed,
            hdrs = hdrs,
            provided = _provided_names(provided_srcs),
            inc_file = (":" + inc_file) if inc_file else None,
        )

def program_allocfail_choice_problem(malloc, cases, allocfail, no_allocfail, rule = None, leaks_rule = None):
    """Why c_program may not leave its allocfail sweep unchosen; None if it may.

    A program whose subject lets it allocate, with cases to replay, either
    asks for the sweep (`allocfail`) or says why not (`no_allocfail`): a
    check a project could forget is a choice its macro will not load
    without (AGENTS.md, "Decide at the call site"). Nothing asked before,
    and a program project could ship without the layer with nothing to say
    so (W5-CC). A decision made while loading, so
    //tools/tests:starlark_unit calls it both ways.

    Args:
      malloc: whether the subject() contract lets the program allocate
        (_memcheck_allowed).
      cases: c_program's `cases` (None: its runs are driven elsewhere).
      allocfail: c_program's `allocfail`.
      no_allocfail: c_program's `no_allocfail`, a sentence or None.
      rule: c_program's `allocfail_rule`. Without `allocfail` it would back
        no check, and say which rule a sweep applies beside a call that has
        none (c_function refuses the same in _allocfail_problem).
      leaks_rule: c_program's `allocfail_leaks_rule`, held the same way.

    Returns:
      None, or the reason as a sentence.
    """
    if allocfail == None and (rule != None or leaks_rule != None):
        return ("sets %s without allocfail: the sentence would back no check." %
                ("allocfail_rule" if rule != None else "allocfail_leaks_rule"))
    if no_allocfail != None and (type(no_allocfail) != "string" or not no_allocfail.strip()):
        return "no_allocfail is a sentence saying why the program has no allocfail sweep."
    if allocfail != None and no_allocfail != None:
        return ("allocfail and no_allocfail together: the sweep is asked for, and " +
                "no_allocfail says why there is none. Keep the one that is true.")
    if not malloc or not cases:
        if no_allocfail != None:
            return (("no_allocfail says why there is no allocfail sweep, and nothing " +
                     "asks for one: %s. Drop the sentence.") %
                    ("the subject() contract does not let the program allocate" if not malloc else "no case is replayed here (cases = None)"))
        return None
    if allocfail == None and no_allocfail == None:
        return ("the subject() contract lets this program allocate, and it has cases, " +
                "and the call neither sweeps its allocations nor says why not. Replay " +
                "a case that allocates with each malloc() refused in turn (allocfail, " +
                "with allocfail_rule), or say in no_allocfail why the program needs " +
                "no such sweep.")
    return None

def program_allocfail_problem(allocfail, case_names, malloc, leaks, allowed, rule, leaks_rule):
    """Why c_program may not emit its allocfail targets as asked; None if it may.

    A decision made while loading, so a function of its own that
    //tools/tests:starlark_unit calls both ways.

    Args:
      allocfail: the case name c_program's `allocfail` gives, a list of
        them, or None.
      case_names: the names of its cases ("run" for an unnamed one).
      malloc: c_program's `malloc`.
      leaks: c_program's `allocfail_leaks`.
      allowed: the exercise's allowed functions from its subject() contract,
        or None where the subject names none.
      rule: c_program's `allocfail_rule`.
      leaks_rule: c_program's `allocfail_leaks_rule`.

    Returns:
      None, or the reason as a sentence.
    """
    if allocfail == None:
        return "allocfail_leaks needs allocfail: the leak sweep replays its case."
    if not malloc:
        return ("allocfail needs a subject that lets the program allocate (its " +
                "contract's allowed line names malloc, or there is none): a program " +
                "that may not allocate has no allocation to refuse.")
    names = [allocfail] if type(allocfail) == "string" else allocfail
    if type(names) != "list" or not names or [n for n in names if type(n) != "string"]:
        return ("allocfail = %r: it names the case whose argv and stdin the sweep " +
                "replays, or a list of them, one sweep each.") % (allocfail,)
    if len({n: True for n in names}) != len(names):
        return "allocfail = %r names a case twice: one sweep per case." % (allocfail,)
    for n in names:
        if n not in case_names:
            return ("allocfail = %r names no case; the cases are %s. It names the " +
                    "cases whose argv and stdin the sweeps replay.") % (n, ", ".join(case_names) or "none")
    if leaks and "free" not in (allowed or []):
        return ("allocfail_leaks, and the subject() contract does not let this " +
                "exercise call free(): a program that may not release a block " +
                "cannot be asked to.")
    why = allocfail_rule_problem(rule)
    if why:
        return why
    if leaks:
        return allocfail_rule_problem(leaks_rule, "allocfail_leaks_rule")
    if leaks_rule != None:
        return ("allocfail_leaks_rule without allocfail_leaks: there is no leak " +
                "target to print it.")
    return None

# tools/allocfail_program.c is linked as a harness and calls nothing of the
# student's: the program's own main() runs (_student_bin's `prototype`).
_AF_PROGRAM_PROTO = ("none: tools/allocfail_program.c calls none of the program's " +
                     "functions; the program's own main() runs")

def _program_allocfail(ex, num, prog, cases, cnames, rule, leaks_rule, binname, makefile, srcs, hdrs, provided_srcs, survive):
    """c_program's allocation-failure targets: see its `allocfail` and `allocfail_leaks`.

    `cnames` is the case to replay, or a list of them: the first one's sweep
    is exNN_program_allocfail, and each other's exNN_<case>_program_allocfail
    -- which requests a program makes depends on its input, so one case can
    leave error paths untried that another reaches. `leaks_rule` is None when
    there is no leak target, and that target's rule when there is one.

    Each sweep, and its gate, runs the case as its output test does: the run
    flags are _case_run's (stdin, argument file, run folder), which `prog`,
    c_program's `name`, names the program in. They once forwarded stdin
    alone, so Rush 02's one-argument case, which runs beside numbers.dict,
    ran from a folder with no dictionary: its gate was red on every correct
    program and the sweep SKIPped, and under NO_SKIP=1 it refused only what
    the missing-dictionary path asks for. c_levels()' audit holds every such
    gate to an output test of the package (_case_gate_problems). `survive`
    is c_program's _survive_gate(ex, cases), or ([], []) (_memory_gate)."""
    af_bin = ex + "_bin_allocfail"
    af_harness = ["//tools:allocfail_program.c", "//tools:allocfail_counter.h"]
    af_link = ["-Wl,--wrap=malloc", "-Wl,--wrap=free"]
    if makefile:
        _student_bin(
            name = af_bin,
            harness = af_harness,
            makefile = turnin_dir(num) + "/Makefile",
            make_goal = _goal_of(num),
            srcs = srcs if makefile == "once_written" else None,
            make_data = turnin_glob(
                [turnin_dir(num) + "/**"],
                exclude = _not_build_products(turnin_dir(num)),
            ),
            hdrs = hdrs,
            archive = False,
            linkopts = af_link,
            prototype = _AF_PROGRAM_PROTO,
            tags = ["manual"],
        )
    else:
        _student_bin(
            name = af_bin,
            harness = af_harness,
            srcs = srcs + provided_srcs,
            hdrs = hdrs,
            archive = False,
            dir = turnin_dir(num),
            linkopts = af_link,
            prototype = _AF_PROGRAM_PROTO,
            tags = ["manual"],
        )
    names = [cnames] if type(cnames) == "string" else cnames
    for cname in names:
        first = cname == names[0]
        c = [x for x in cases if x.get("name", "run") == cname][0]
        k = _case(c, "program", "c_program(%s)" % _call(num))
        run_flags, run_files = _case_run(c, prog)
        args = [
            "--bin",
            "$(location :%s)" % af_bin,
            "--label",
            "%s/%s" % (ex, cname),
            "--show-run",
            _shown_bin(af_bin),
        ]
        data = [":" + af_bin, "//tools:diff_output.sh"] + run_files

        # Gated as the case's valgrind arm is (_memory_gate). A survive
        # case has no fixture of its own: its sweep waits on the case its
        # output, asan and valgrind arms wait on (_survive_gate), handed to
        # the runner whole after --survive. A program nobody has written
        # ends by itself and allocates nothing, so its sweep refused
        # nothing and passed, the asymmetry V253 removed from the memory
        # arms (V282). No such case: it runs ungated. The runner hands its
        # gate the argument file and the run folder itself (as
        # valgrind_test.sh does); stdin has its own gate flag.
        gate, gate_data, waits = _memory_gate(ex, cases, c, k, binname, survive)
        args += gate
        data += gate_data
        args += run_flags
        # The rule each target prints reaches the runner as a file (--rule FILE,
        # as c_function's allocfail_rule and valgrind's memory_rule do), since
        # sh_test tokenises `args` on blanks.
        stem = ex if first else _case_stem(ex, cases, cname)
        targets = [(stem + "_program_allocfail", [], rule)]
        if leaks_rule != None:
            targets.append((stem + "_program_allocfail_leaks", ["--leaks"], leaks_rule))
        for name, extra, sentence in targets:
            names_file(
                name = name + "_rule",
                names = [sentence],
            )
            _test(
                name = name,
                srcs = ["//tools:allocfail_check.sh"],
                args = args + extra + ["--rule", "$(location :%s_rule)" % name, "--"] + c.get("args", []),
                data = _uniq(data + [":%s_rule" % name]),
                tags = ["allocfail"],
                # robust: the _program_allocfail suffix's level (_SUFFIX_LAYER).
                # A case raised higher takes the sweep with it.
                level = max(3, k.level or 3),
                # The output test of the case it gates on, by name: another
                # case may share its expected file.
                waits = waits,
            )

# The tag c_program puts on its exNN_bin, naming the program (_built_programs).
_PROGRAM_NAME_TAG = "program_name="

def _fixed_array_test(ex, num, rule, max_bytes, srcs, hdrs, inc_file):
    """exNN_fixed_array, the method layer's reading of a fixed-size array (c_program's `fixed_array`).

    Compiled as the compile layers compile -- the same sources, the grader's
    include path (_inc_args, and a Makefile's own -I through `inc_file`) --
    by the pinned gcc, the one campus compiler that names an object by its
    size (-Wlarger-than=), and proved pinned the way compile_check.sh proves
    it (--cc-under). Nothing is assembled, so no assembler is handed over.
    """
    why = fixed_array_problem(rule, max_bytes)
    if why:
        fail("c_program(%s): %s" % (_call(num), why))
    if rule == None:
        return
    gcc = [c for c in _CAMPUS_CCS if c["label"] == "gcc"][0]
    names_file(
        name = ex + "_fixed_array_rule",
        names = [rule],
    )
    args = [
        "--fixed-array",
        "--rule",
        "$(location :%s_fixed_array_rule)" % ex,
        "--cc",
        gcc["cc"],
        "--cc-under",
        "$(location %s)" % gcc["under"],
    ]
    if max_bytes != None:
        args += ["--max-bytes", str(max_bytes)]
    for s in srcs:
        args += ["--src", "$(location %s)" % s]
    args += _inc_args("--inc", hdrs)
    data = srcs + hdrs + gcc["data"] + [":%s_fixed_array_rule" % ex]
    if inc_file:
        args += ["--inc-file", "$(location :%s)" % inc_file]
        data.append(":" + inc_file)
    _test(
        name = ex + "_fixed_array",
        srcs = ["//tools:method_check.sh"],
        args = args,
        data = data,
        tags = ["method"],
        turnin = srcs,
        gated = True,
    )

def c_argv_table(num, scenarios = "scenarios.tsv", expected = "table.txt", clues = "clues.tsv", asan = True, model = None, no_model = None, refusals = None, name = None):
    """One labelled table for an argv program run against many invocations.

    Emits exNN_output (tag "output"), driven by //tools:argv_table.sh: the
    program is run once per row of tests/exNN/<scenarios> and every run becomes
    one row of a single "invocation -> output" PASS/FAIL table, rather than one
    opaque sh_test per invocation.

    Pairs with c_program(num, name) and no `cases`, which still builds
    :exNN_bin plus the norm/compile/forbidden layers.

    asan: replay the same scenarios against c_program's instrumented binary
      (tag "asan", so it runs from level `robust` up), and again, as
      exNN_argv_asan, against one whose argv the sanitizer can see the edges
      of. These exercises index and swap the pointers in argv, and an
      out-of-bounds read there returns bytes that are usually still the RIGHT
      bytes — so the table is structurally unable to see it. The plain replay
      sees an access the sanitizer watches (the program's own buffers, the
      heap); NOT one inside the argument strings or past argv's end, which the
      kernel lays out on the initial stack where ASan does not look -- a read
      past one argument's terminator reads the next one (finding 071). The
      guarded replay links the student's sources with main wrapped
      (-Wl,--wrap=main) and runs them under tools/argv_guard_main.c, which
      puts each argument in a heap
      block of exactly its size and argv in one of argc + 1 pointers, so
      those reads are heap-buffer-overflow reports.

    Also emits exNN_exit (tag "output", raised to level 3, robust): the same
    scenarios, judged only on how each run ended. The table fails a crash but
    only notes a plain non-zero return, because the subjects these programs
    come from name no exit status; by the rule in docs/reference.md ("Run
    contract") that return fails at robust, and this is where.

    Args:
        num: the exercise number as a two-digit string ("00"). It names the
            targets (exNN_output, exNN_asan) and locates tests/exNN/, but
            it also has to match a c_program(num = ...) call in the same
            package: the binaries it runs, :exNN_bin and (when asan)
            :exNN_bin_asan, are built there and this macro declares none of its
            own. Without that call it is a "no such target" analysis error, not
            a silent skip.
        scenarios: name of the scenario file under tests/exNN/, default
            "scenarios.tsv". One invocation per line, tab-separated:
            <label>[<TAB><arg>...]. A line with no tab runs the program with no
            arguments, an empty field is a real empty-string argument, and
            blank lines and #-comments are skipped. The label is what the
            table's CASE column shows, and it is also the name a clue group in
            `clues` lists when it should fire on that row rather than on any
            failure. These rows are the whole of this layer's coverage -- for
            c-06 ex01-ex03 this is the only layer that ever runs the program at
            all -- so a file that yields no invocation (empty, or nothing but
            comments) exits 2 as a harness error instead of reporting a pass on
            nothing. The file is a declared input, so naming one that does not
            exist is an analysis error rather than a skip.
        expected: name of the expected table under tests/exNN/, default
            "table.txt". One row per scenario, "<label><TAB><output>", where
            <output> is that run's stdout LINES joined with " | ". Generate it
            rather than typing it: running argv_table.sh --emit by hand prints
            exactly this stream from a trusted reference program, and refuses
            to if that program crashed, hung, flooded or returned a status
            other than 0. Still required by the asan arm even though nothing
            is compared there -- its size is what sizes the runaway-output
            budget for each run.
        model: the //oracle command the table was emitted from, as a list of
            words (C 06 ex01: ["c06_run", "print"]). It emits exNN_model
            (layer oracle, complete): tools/model_check.sh --argv-table runs
            argv_table.sh --emit with the model as the program, and fails
            when the stream it prints is not the committed table. It runs
            nothing of the student's and is green on every turn-in. Without
            it, a table emitted once was held to nothing afterwards: an edited
            row, or a scenario changed without its row, first showed as a
            correct program going red.
        no_model: a sentence saying why no //oracle command made the table,
            in place of `model`. The call names exactly one of the two
            (_argv_model_problem).
        refusals: the macro fixtures' own (_refuse); never in a project.
        clues: name of the hints file under tests/exNN/, default "clues.tsv".
            There is no opt-out -- it is always passed and always declared as
            an input, so the file has to exist -- and diff_output.sh renders
            the fired hints under the table when a row fails, exactly as it
            does for every other layer. Only on the plain table: the sanitizer
            arm never invokes the reporter, so it renders no hints.
        asan: default True. Replays the same scenarios against c_program's
            instrumented binary (exNN_asan) and against the guarded-argv one
            (exNN_argv_asan, built here from what c_program's :exNN_bin_asan
            is built from -- its source list, or its Makefile, asked again
            -- so that c_program call must come first: argv_guard_problem), both
            tag "asan", so from level robust
            up. Both run with --memory-only: the verdict is survival, not
            bytes, since a wrong table is the output test's finding and
            reporting it twice for one unwritten function teaches nothing the
            second time. Each says on OK only what it could see.
        name: unused, for the reason c_levels gives: every macro takes one,
            and buildifier's unnamed-macro check holds this one to it since it
            declares a rule (the guarded-argv program, exNN_argvguard_bin_asan).
            Every target here is named from `num`.
    """
    _entry(num, "c_argv_table")  # first: a contract error names this macro
    ex = _prefix(num)
    if _refuse(_argv_model_problem(ex, model, no_model), refusals, "c_argv_table(%s)" % ex):
        return
    scen_f = "tests/%s/%s" % (ex, scenarios)
    exp_f = "tests/%s/%s" % (ex, expected)
    clues_f = "tests/%s/%s" % (ex, clues)

    def _table_test(name, binlabel, tag, memory_only = False, exit_only = False, level = None, guarded = False, waiting = False):
        t_args = [
            "--bin",
            "$(location %s)" % binlabel,
            "--scenarios",
            "$(location %s)" % scen_f,
            "--expected",
            "$(location %s)" % exp_f,
            "--clues",
            "$(location %s)" % clues_f,
            "--reporter",
            "$(location //tools:diff_output.sh)",
        ]
        if memory_only:
            t_args.append("--memory-only")
        if guarded:
            t_args.append("--guarded-argv")
        if exit_only:
            t_args.append("--exit-only")
        t_data = []
        if memory_only:
            t_args += _symbolizer_args()
            t_data = _SYMBOLIZER_DATA
        if waiting:
            w_args, w_data = _waiting_args(name)
            t_args += w_args
            t_data = t_data + w_data
        _test(
            name = name,
            srcs = ["//tools:argv_table.sh"],
            args = t_args,
            data = [
                binlabel,
                scen_f,
                exp_f,
                clues_f,
                "//tools:diff_output.sh",
            ] + t_data,
            tags = [tag],
            level = level,
        )

    # The table is the exercise's output test, the one a stub fails, so the
    # corpus replays of the same program wait for it (output_gate) and its
    # red log lists them (--waiting, _waiting_args).
    _table_test(ex + "_output", ":%s_bin" % ex, "output", waiting = True)

    # The table, held to the model it was emitted from (`model` above).
    if model:
        _test(
            name = ex + "_model",
            srcs = ["//tools:model_check.sh"],
            args = [
                "--oracle",
                "$(location //oracle:oracle)",
                "--expected",
                "$(location %s)" % exp_f,
                "--argv-table",
                "$(location //tools:argv_table.sh)",
                "--scenarios",
                "$(location %s)" % scen_f,
                "--",
            ] + model,
            data = ["//oracle:oracle", exp_f, scen_f, "//tools:argv_table.sh"],
            tags = ["oracle"],
        )

    # The exit status, at robust: see the docstring and docs/reference.md.
    # Named exNN_exit, not exNN_exit_output: first_red reads an `output` tail
    # as "the next exercise to write", and this is rigour on a written one.
    _table_test(ex + "_exit", ":%s_bin" % ex, "output", exit_only = True, level = 3)
    if asan:
        # --memory-only: the instrumented replay judges memory, not bytes. A
        # wrong table is the output test's finding, and reporting it twice for
        # one unwritten function teaches nothing the second time.
        # exNN_asan, with no infix, because every other sanitizer arm in the
        # repo is spelled <stem>_asan and this was the one exception. A student
        # who learns `bazel test //mod:exNN_asan` on c-11 and tries it on c-06
        # got "no such target". The infix protected nothing: if an exercise ever
        # combined c_program(cases = ...) with c_argv_table, their two
        # exNN_output targets would already collide, so it is the output arm --
        # which never had an infix -- that decides compatibility.
        _table_test(
            ex + "_asan",
            ":%s_bin_asan" % ex,
            "asan",
            memory_only = True,
        )

        # THE GUARDED REPLAY (finding 071): the same scenarios, argv and each
        # argument in heap blocks of exactly their size (tools/
        # argv_guard_main.c), so a read past an argument's terminator or past
        # argv[argc] is a sanitizer report instead of the next argument's
        # bytes. Built from the very sources and headers c_program gave
        # :exNN_bin_asan, read off that rule rather than derived again: a
        # second derivation is one that can come to compile a different file
        # set from the program that is graded. A program built by its
        # Makefile is built the same way here: student_build.sh asks the
        # same Makefile (`make -Bn`) which sources its default goal
        # compiles, and links them with main wrapped.
        prog = native.existing_rule(ex + "_bin_asan")
        why = argv_guard_problem(prog)
        if why:
            fail("c_argv_table(num = \"%s\"): %s" % (num, why))
        guard_bin = ex + _ARGV_GUARD_SUFFIX
        from_prog = argv_guard_build(prog)
        _student_bin(
            name = guard_bin,
            harness = ["//tools:argv_guard_main.c"],
            hdrs = list(prog["hdrs"]),
            archive = False,
            dir = turnin_dir(num),
            asan = True,
            # The C runtime's call to main() reaches the guard's __wrap_main,
            # which calls the program's own as __real_main: their main()
            # keeps its name, and C's implicit return 0 with it.
            linkopts = ["-Wl,--wrap=main"],
            prototype = ("none: tools/argv_guard_main.c calls the program's own " +
                         "main(), whose signature is C's, not the subject's"),
            **from_prog
        )
        _table_test(
            ex + "_argv_asan",
            ":" + guard_bin,
            "asan",
            memory_only = True,
            guarded = True,
        )

def argv_guard_problem(prog):
    """Why c_argv_table cannot build its guarded-argv program; None if it can.

    The guarded replay compiles the program's own sources with main wrapped,
    beside tools/argv_guard_main.c, so it needs what the graded program is
    built from: c_program's :exNN_bin_asan, declared before this macro is
    called -- a list of files, which it reuses, or the Makefile, which it
    asks again (`make -Bn`, in student_build.sh). A Makefile build used to
    be refused here, which left a Makefile project with no guarded replay
    at all. A decision made while loading, so a function of its own that
    //tools/tests:starlark_unit calls both ways.

    Args:
      prog: native.existing_rule() of :exNN_bin_asan, or None.

    Returns:
      None, or the reason as a sentence.
    """
    if prog == None:
        return ("its asan arms run :exNN_bin_asan, which c_program(num = ...) " +
                "declares: call c_program first, above this call.")
    return None

def argv_guard_build(prog):
    """What c_argv_table's guarded-argv program is built from.

    _student_bin's keywords, read off c_program's :exNN_bin_asan: the
    program's own list of files, or its Makefile and the tree staged
    beside it -- never globbed a second time -- and with the Makefile, the
    sources that rule builds until the Makefile compiles anything
    (c_program's makefile = "once_written"). Those were left out, so over a
    stub Makefile the guarded program was an empty stand-in while the
    graded one ran the folder's sources (V35). A function of its own, which
    //tools/tests:starlark_unit calls on each shape.

    Args:
      prog: native.existing_rule() of :exNN_bin_asan (argv_guard_problem
        has said it is there).

    Returns:
      A dict of _student_bin's srcs, makefile, make_data and make_goal.
    """
    srcs = list(prog.get("srcs") or [])
    if prog.get("makefile"):
        built = {
            "make_data": list(prog.get("make_data") or []),
            "makefile": prog["makefile"],
        }
    elif prog.get("missing_makefile"):
        built = {"makefile": prog["missing_makefile"]}
    else:
        return {"srcs": srcs}
    if prog.get("make_goal"):
        # The rule that builds this part (c_program, a part's goal).
        built["make_goal"] = prog["make_goal"]
    if srcs:
        built["srcs"] = srcs
    return built

def _make_anchor_problem(num, anchor, e, macro = "c_make"):
    """The message when a macro builds from a file the contract does not require; None if it does.

    exNN_build runs at basic and is red without its Makefile (or creator
    script), so the subject that c_make reads as asking for one asks for it
    as a turn-in file, and the contract must say so in `files`. C 11 ex05's
    contract once left its Makefile out: the files layer then warned of an
    unrequested file beside the very build that required it, and on a strict
    project it would have failed a correct turn-in at basic (finding 124).
    Its contract was fixed by hand, which fixes nothing for the next
    project; this holds every c_make to it while loading. Only `files`: a
    file in `optional` is one the turn-in may leave out, which no basic test
    may then require.

    c_program(makefile = True) builds its program from the same Makefile,
    and every output test it declares, at basic, runs that program: the
    same class, by the other macro that builds from a Makefile. And the
    audit asks for a c_make only where the contract's `files` hold a
    Makefile (_levels_audit's `makefiles`), so a contract that left it out
    released the project from that too.

    A value before it is a fail() (c_make) or a refusal (c_program), so the
    macro fixtures can feed it the broken entries
    (contract_problem("make_anchor", ...), and c_program's `refusals`).

    Args:
        num: the exercise, for the message.
        anchor: what the macro builds from: "Makefile", or c_make's `script`.
        e: the exercise's contract entry.
        macro: "c_make", or "c_program" (makefile = True).

    Returns:
        The message, or None.
    """
    if anchor in (e["files"] or []):
        return None
    where = "%s(%s)" % (macro, _call(num))
    if macro == "c_make":
        needs = "exNN_build, at basic, fails without it"
        drop = "drop the c_make"
    else:
        needs = "with makefile = True, every output test, at basic, runs the program it builds"
        drop = "build the program from its sources (makefile = False)"
    if anchor in e["optional"]:
        return (("%s: the contract lists %s in `optional`, and %s: a file a basic test " +
                 "requires is one the turn-in must hold. Move it to the exercise's " +
                 "`files`.") % (where, anchor, needs))
    if anchor in e["provided"].values():
        return (("%s: the contract says the grader brings %s (`provided`), and %s " +
                 "builds the student's own. Name the student's in `files`, or %s.") %
                (where, anchor, macro, drop))
    return (("%s: %s builds from %s, and the subject() contract does not ask for it " +
             "(files: %s; optional: %s). The files layer would call it a file nobody " +
             "asked for, beside the build that requires it (finding 124). Transcribe the " +
             "subject's turn-in line: %s goes in the exercise's `files`.") %
            (where, macro, anchor, e["files"], e["optional"], anchor))


# ---------------------------------------------------------------------------
# WHAT THE FILES ABOVE THIS ONE LOAD OF IT. A load() cannot name a private
# symbol, so each one they use is given a public name here, its own without
# the underscore, and loaded back under its own name: the code reads as it did
# when tools/defs.bzl held it all. These names are for those files alone; a
# BUILD file loads //tools:defs.bzl.
PROGRAM_NAME_TAG = _PROGRAM_NAME_TAG
make_anchor_problem = _make_anchor_problem
