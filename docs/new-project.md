# Adding a project, or a layer

**For:** anyone adding a 42 project to this harness -- the next Common Core
project, say -- or a new layer, runner or macro to it. An AI agent doing either
reads this page first and works through it in order (AGENTS.md §6).

Every item below is a lesson a correct answer once paid for: a student-test
run, a stranger's answers written from the subjects alone, found 205 places
where the harness had learned the answers it grew up with instead of the
subjects. The *why* behind them is [design.md](design.md); the facts to look
up are [reference.md](reference.md). This page is the order you meet them in,
and what to do.

Each item ends with what holds it. **Checked by:** names the check that fails
when the item is broken -- a refusal while the package loads, the audit
`c_levels()` runs over a module (`_audit_problems`), a rule of
`//tools:conventions` (quoted by its heading), or a selftest. **(unchecked)**
means nothing does: a reviewer has to. `//tools:conventions` holds every item
here to one of the two, and every check it names to one that exists.

---

## Before you write anything

1. **Work from the subject, never from an answer.** Every answer in this
   repository, whoever wrote it, is one reading of the subject in one layout,
   and a harness built against it learns that reading as the rules: a folder
   the subject never asked for becomes required, a file the grader brings
   becomes the student's. Read the subject's header boxes and its sentences;
   do not open anyone's `deliverable/` or `generators/` to see what a project
   "looks like". **(unchecked)**
2. **Read the Run contract before deciding anything about a status, stderr,
   an execute bit or an open sentence.** Those are decided once, in
   [reference.md, "Run contract"](reference.md#run-contract), and a check never
   decides one again. **(unchecked)**

## The project's folder

3. **One folder per project, named as 42 names it**, inside its course folder
   (`cursus/<project>/`), holding one `BUILD.bazel` and the subject beside it
   as `en.subject.pdf` / `es.subject.pdf`. The template build replaces every
   subject with a placeholder; nothing in the harness reads one.
   **(unchecked)**
4. **Register the module** in two lists: a row `<path>=REPLACE_ME` in
   `tools/submit.sh`'s `REMOTES` table (never a URL: those live in
   `.submit-remotes`), and its label in `_MODULES` in
   `tools/tests/BUILD.bazel`. **Checked by:** `//tools:conventions` ("Every
   project folder has a row in tools/submit.sh's REMOTES table") when it runs
   on the workspace (`bazel run //tools:conventions`; its test sees only the
   registered modules' files, so there an unregistered project is invisible),
   and ("The REMOTES table in tools/submit.sh holds no URL"); for the list in
   tools/tests/BUILD.bazel, the test of conventions, which refuses to run
   while a module of the table is one it cannot see.
5. **A file 42 issues** (a dictionary, a tarball) gets a row in
   `tools/resources.tsv`, one path, and no second copy anywhere; one the
   subject turns in also gets a `c_issued()` call. **Checked by:**
   `//tools:conventions` ("42's own files are registered, and every message
   names the one path").
6. **A program the project builds** is named in `.gitignore` under its
   turn-in folder, so a hand-run of `make` does not get committed.
   **(unchecked)**
7. **The project's own page**, a `README.md` beside its `BUILD.bazel`: what is
   turned in and where, how its tests are built, its corpora and how to replay
   a failing case, its settings, and every question its subject leaves open,
   each with what `basic` checks and which target holds one reading of it:
   the page names that target, never the reading it tests (item 44).
   Facts every project shares stay on the shared pages, linked
   ([rushes.md, "Working as a team"](rushes.md#working-as-a-team) for a group
   project). [BSQ's](../c-piscine/c-piscine-bsq/README.md) is the model. A
   one-person Piscine module keeps the shared pages
   ([testing.md](testing.md), [reference.md](reference.md)), and gets a page
   of its own only where it extends or overrides them, as C 08's, C 09's and
   Reloaded's do (the owner's ruling, 2026-10-09).
   **Checked by:** `//tools:conventions` ("A group project, and every Common
   Core project, has a page of its own"), that those two have one, and ("A
   page's relative links and anchors resolve"), that every link and anchor
   of every page does; what a page holds, and a page for any other project,
   **(unchecked)**.

## The subject contract

8. **The BUILD file opens with `subject()`**, transcribed from the subject's
   header boxes ([reference.md, "The subject
   contract"](reference.md#the-subject-contract)): every macro reads the
   project's facts there, and no call site passes a turn-in file, an allowed
   list or a grader's file of its own. A call site names another exercise's
   file only through `turnin_file()`. **Checked by:** `subject_problem`,
   `_turnin_file_problem`, and `//tools:conventions` ("Every project reads its
   turn-in from ONE subject contract").
9. **One `"NN": exercise(...)` entry per exercise**, with `dir = "exNN/"` as
   the "Turn-in directory" line says it, or `dir = None` where the subject has
   no such line: the turn-in is then `deliverable/` itself, the root of the
   repository that is pushed. Read each subject for it: libft's and most
   Common Core subjects have none, and others print one per exercise.
   `tools/first_red.sh` reads this form as text. **Checked by:**
   `//tools:conventions` ("Every project reads its turn-in from ONE subject
   contract"), and `//tools/tests:macro_fixtures_test`, which holds the
   folders first_red reads to the macros' own.
10. **`grader` and `group`.** Who grades -- `moulinette`, `defense` or `both`
    -- is the contract's to say, and every runner words its messages from it,
    never by naming the Moulinette. **Checked by:** `subject_problem`, and
    `//tools:conventions` ("No runner names the grader; the project's contract
    does").
11. **`files` and `optional`.** A pattern says what kind of file, never where,
    unless the subject names the place: beside a Makefile, "Makefile, \*.h,
    \*.c" is `"Makefile"` with `"**/*.c"`, `"**/*.h"`, so a `srcs/` and
    `includes/` layout works. Every project is `strict` where its subject
    forbids extra files, as every Piscine one does. **Checked by:**
    `exercise_problem`.
12. **What the grader brings.** A file goes in `provided`, the harness's copy
    under `tests/`, and is never required from the student. A source there
    that defines a function some exercise turns in is a stub. Reloaded's
    `ft_putchar.c` (written with stdio, no `write()`) is the one exception,
    named in that rule's `TURNIN_FN_ALLOW` and in AGENTS.md §4, and it is not
    a pattern to repeat: a new entry needs the owner. A function another
    exercise turns in ("we'll use our `ft_create_elem`") is `linked`, a
    `grader_library()` crate under `oracle/grader/`, never C.
    **Checked by:** `linked_problem`, `//tools:conventions` ("A function the
    GRADER brings is never written in C outside the zone"), ("A function a
    student turns in is never written outside the zone") and ("What AGENTS.md
    names, the harness has").
13. **`allowed` and `variables`**, verbatim from the "Allowed functions" line:
    `[]` for "None", `None` where the subject has no such line (a rush, a
    header exercise), which emits no forbidden layer. Whether a program may
    allocate, and so gets a leak check, is read from it, never passed again.
    **Checked by:** `_forbidden_allowed_problem`, `_function_malloc_problem`,
    `_malloc_argument_problem`.

## How student code is built

14. **Student code is built through `tools/student_build.sh`, never a plain
    `cc_binary`, and no turn-in file is a declared input.** A file that does
    not compile becomes a stand-in program that fails its own tests; a file
    not written yet fails the tests that need it as NOT TURNED IN; neither
    stops the module loading. **Checked by:** `//tools:conventions` ("No
    deliverable can break the build graph") and
    `//tools/tests:macro_fixtures_test`, which builds toy exercises in every
    broken state.
15. **A runner that runs a program recognises the stand-in.** **Checked by:**
    `_standin_runner_problem`, from `_STANDIN_RUNNERS`.
16. **Compile as the grader compiles**: its files, its include path, its
    working directory. Every layer of an exercise compiles the files the
    contract names or allows and no other (`tools/defs.bzl`'s
    `_turnin_files`): a file it does not let the turn-in hold is the files
    layer's report alone, never a red in the probe, ASan or 32-bit build that
    the output fixture does not share. A header in a subfolder is reached
    through the Makefile's `-I` (read from `make -Bn`) or an `#include` that
    names the folder, never through an `-I` the grader does not pass.
    **Checked by:** `//tools/tests:macro_fixtures_test` (`:stray_reads`: no
    rule of toy ex04 reads its stray `main.c` or `toy_extra.c`); the include
    path **(unchecked)** for a macro written next, the existing ones proven
    by the same test.
17. **A Makefile the contract turns in gets a `c_make`**, and the program it
    builds a `c_program(makefile = True)`: the program is built from the
    sources and `-I` folders `make -Bn` names. Where the program is most of
    the work and its Makefile a line of it, `"once_written"` builds the
    folder's sources until the Makefile compiles anything, so the output
    tests run before it exists. Both build only from a Makefile the
    contract's `files` require.
    **Checked by:** `_audit_problems` (every Makefile has its `exNN_build`),
    `_make_anchor_problem`, `_makefile_problem`.
18. **`c_make` decides each check, at the call site.** `recipe` (`any` or
    `ordered`, at the level the subject's sentence gives it), `wildcards`
    (with the Norm's quote), or `not_checked = {check: why}`; each rule the
    subject defines quoted in `quotes`; a rule it only lists goes to
    `exNN_build_rules`, at robust; a library on `c_libft` decides the same in
    `make = {...}`. Its hints go in `clues`. **Checked by:** `_make_problem`,
    `_libft_make_problem`, and `_audit_problems` (a clue file no test hands
    a runner).

## Tests of a C function

19. **A differential harness is `tests/exNN/diff_<what>.c`**, and its header
    opens with a ` * Line:` paragraph naming every column it prints.
    **Checked by:** `_diff_harness_problem`, and `//tools:conventions` ("A
    differential harness names its columns in the shape the diff layer
    reads").
20. **What a harness hands the function is not zeroed.** A destination comes
    from `dio_garbage(cap)` or `dio_dest(s, len, cap)`, so a missing
    terminator shows; one that must be zeroed says why
    (`/* conventions: zeroed -- <why> */`). **Checked by:**
    `//tools:conventions` ("A differential harness hands the function under
    test no zeroed buffer").
21. **A harness sizes what it fills from the case**, never a fixed array
    (`dio_getline`, `dio_csv_ints`, `dio_split_all`), and every unbounded
    input has a case far past the round sizes a student picks (16, 64, 1024,
    4096, 64 KiB). **Checked by:** `//tools:conventions` ("A harness sizes
    what it fills from its input from the case"); the large cases
    **(unchecked)**.
22. **A harness that prints a byte a line cannot hold** writes
    diff_output's notation and declares `escaped_values`; **one that passes
    an address** publishes it as `@addr`, never normalised by the runner,
    and **checks it only on a block above 4 GiB**: a reader's heap sits
    below, where an address cut to 32 bits is the real one (finding 048), so
    the block goes through `tools/diffio.h`'s `dio_high`, or the file says
    where its blocks live (an output fixture's local arrays are on the
    stack). Common Core's `ft_printf` `%p` is the next one. **Checked by:**
    `//tools:conventions` ("A test program that writes an escape of its own
    declares it"), ("A dump's harness publishes the addresses it passes")
    and ("A harness that checks a printed address puts the block above 4
    GiB").
23. **Bytes above `0x7f`** are seeded where a signed `char` hides, in the
    corpus and, where another module fuzzes the same contract, in a fixture
    row of this one: each module is graded alone. A harness that decodes
    bytes has a line for that family in its legend. **Checked by:**
    `//tools:conventions` ("A string harness's legend has a line for the bytes
    above 0x7f"); the seeding **(unchecked)**.
24. **A result the function must write starts where no row expects it**: in
    a fixture at a value no row expects, in a corpus from two starting values
    (`PRESET_A`, `PRESET_B`), so "never written" is a red and not a lucky
    match. **Checked by:** `//tools:conventions` ("A differential harness that
    reads a result as never written starts it"), for a corpus; a fixture
    **(unchecked)**.
25. **A callback records its calls, a predicate returns more than 0 and 1,
    and each fixture row names the property it checks** (`labeled = True`), so
    "never called", "called with the wrong argument" and a clue are about one
    row. **(unchecked)**
26. **A structure the subject prints** for a header the student turns in goes
    in `tests/layout/<header>`, its names in `tests/layout/tag/<header>`.
    **Checked by:** `_audit_problems`, for a layout file no test reads; a
    structure the subject prints with no layout file **(unchecked)**.
27. **Every program that links a harness over student code names the test of
    the signatures it calls** (`prototype`), and `_prototype_names` is added
    where the subject fixes parameter names. **Checked by:**
    `_harness_prototype_problem` and `_audit_problems`; the names
    **(unchecked)**.
28. **A sentence about how the work is done**, which no output shows, gets a
    row in [reference.md, "Sentences about how"](reference.md#sentences-about-how),
    always, and an argument where a layer can read it: `c_function(method,
    method_rule)` for "recursive" or "iterative", `c_program(fixed_array,
    fixed_array_bytes)` for a fixed-size array. **Checked by:**
    `method_problem`, `fixed_array_problem`; the table row **(unchecked)**.

## Tests of a C program

29. **Every case says what its status means**: `invalid_input` for an error
    the subject names, `exit` with `exit_quote` for a status it names (with
    `"level": 2` for a status a sentence is only read as naming), an `any_of`
    or `survive` case where the output is open; anything else gets the robust
    twin, which expects 0. **Checked by:** `_case_problem`.
30. **A program that opens files has a case naming one that will not open**
    (`missing_file`), or says why there is none (`no_missing_file_case`).
    **Checked by:** `_missing_file_problem`.
31. **What `args` cannot say goes in `argv_file`** (arguments Bazel would
    drop or split) **or `cwd_files`** (a file the program opens by a fixed
    name, from a folder of its own). **Checked by:** `_case_problem`.
32. **A file whose bytes are the case** -- a CR, a NUL -- lives under its
    exercise's `tests/exNN/`, and one holding a CR LF in that folder's
    `fixtures/`, which `.gitattributes`' `-text` rule covers: anywhere else
    git commits a CR LF as LF, and every clone tests bytes the checkout that
    wrote the file never had (Rush 02's `crlf.dict`, once). **Checked by:**
    `//tools:conventions` ("A CR IN A FILE GIT WOULD REWRITE"), for a CR,
    and a CR in a clue, a script or a BUILD file; where a file with a NUL
    lives **(unchecked)**: git keeps such a file as it is.
33. **A program that imitates a system tool** takes its expected files from
    an `//oracle` model of the pinned tool, named in `c_program(model = [...])`;
    the tool's messages and status are a reading where the subject does not
    state them. **Checked by:** `_model_problem`, and each case's
    `exNN_<case>_model` test.
34. **The files a named case reads are written by an `//oracle` arm**
    (`<x>_fixtures`) and held by `exNN_oracle_fixtures --owns`; where
    `//oracle` has the program, `reference = True` runs every case with it.
    **Checked by:** `//tools:conventions` ("Every //oracle arm that writes a
    project's fixtures is held by a test"), for a project that has such an
    arm, and `_audit_problems`, for a file a case reads in the folder an
    `--owns` test holds that none of its patterns matches; a project with no
    `<x>_fixtures` arm, a file outside every such folder, and `reference`,
    **(unchecked)**.
35. **The cases a subject settles are named, one rule per case**: its own
    example and any case it says the defense will run, at `basic`; each error
    file breaking exactly one rule, from an input that is valid without it;
    every transport (arguments, standard input, several files) crossed with
    valid and invalid input. **(unchecked)**
36. **A program keeps its hints in one keyed `clues.tsv` per exercise**: a
    row names the cases it is about, or `valgrind`, and a target that replays
    a corpus is handed the file with `--case`. **Checked by:**
    `_keyed_clue_problems`, and `//tools:conventions` ("Every clue label names
    a case that actually exists").

## Corpora, gates and memory

37. **Every corpus runner call says what standard error is held to**:
    `--stderr-empty`, or `stderr_ignored(reason)`. **Checked by:**
    `_runner_choice_problem`, and `//tools:conventions` ("A runner that asks
    what standard error is held to is asked at every call").
38. **Every word of `args` that is a sentence goes through `shell_word()`**,
    and a runner's list of words is one word per line (`rl_list_add`).
    **Checked by:** `//tools:conventions` ("A word of a test's `args` is
    quoted by shell_word(), and by nothing else") and ("A runner's list of
    words from its command line is one word per line").
39. **A gate is one of its own exercise's output tests, run as that test
    runs it** -- the same program, expected file, arguments, standard input
    and folder -- through `rl_gate`; where two output tests share that run,
    the call names the one it waits for (`waits`). **Checked by:**
    `_gate_problems`, `_case_gate_problems`, `_waiting_problems`, and
    `//tools:conventions` ("A corpus runner's gate is tools/runner_lib.sh's
    rl_gate").
40. **Every plain corpus replay has its memory twins**, `corpus_memory()`
    over exactly its corpus; a twin that replays less names what it covers
    (`covers`), and one without memcheck says why (`no_valgrind`). **Checked
    by:** `_corpus_memory_problems`, and `//tools:conventions` ("A runner that
    replays a generated corpus can replay it under the memory").
41. **A runner that shows a sanitizer's report passes the pinned
    symbolizer.** **Checked by:** `symbolizer_problem`, and
    `//tools:conventions` ("A runner that symbolises a sanitizer's report is
    in _SYMBOLIZER_RUNNERS").
42. **A time limit is a guard against a run that never ends, never a
    deadline the subject did not set.** A test's size gives it three times
    what it takes in a full suite run, measured on correct answers -- the
    owner's, or a consenting student's, never one an agent writes; with none,
    the size waits. An input on which a correct but slow program might not
    finish does not sit at `basic`. **(unchecked)**

## Sentences the subject leaves open

43. **An open sentence is a reading.** The output test keeps only what every
    reading agrees on (`any_of`, `survive`, or a fixture holding only those
    cases); one reading runs as a target of its own (`readings`,
    `_readings`), at strict, listed in `_RAISED` with its row in
    [reference.md](reference.md#targets-raised-above-their-layer) unless its
    suffix sets the level. That row is printed under its red, so write it for
    the student who meets it there. **Checked by:** `_audit_problems` and
    `//tools:conventions` ("The target-name, raised-target and manual-target
    tables match the ones"), for the reading's level and its row;
    `diff_readings_problem`, for the shape of a `c_diff` reading; that the
    output test keeps only what every reading agrees on **(unchecked)**.
44. **Only that target states the reading**: the strict target's own hint
    and its own row in [reference.md](reference.md) may state the reading it
    tests, always as "this harness's reading", never as the subject's; no
    basic hint, clue or doc names it, at first red or later (the owner's
    ruling of 2026-10-03, AGENTS.md §2). A project's page, its BUILD
    comments (they ship too: the owner's ruling of 2026-10-09) and any other
    hint may name the target that holds one reading, never the reading.
    **Checked by:** `//tools:conventions` ("A reading is named only as this
    harness's"), for the label: a reading named by another name (the
    reference's or the oracle's among them, and a name wrapped over two
    lines of a legend, a page or what a script prints) in a hint, a check
    script, a runner, a raised target's why or a page; the label in a hint
    a test other than a strict one prints, a raised `readings` corpus's
    legend among them, or in the legend of a `c_diff`'s plain corpus, which holds
    only what every reading agrees on (the reading's cases are its
    `readings` corpus's, with a legend of its own that its ASan twin is
    never handed); a runner that prints the label and then the reading
    rather than a word that points at the input, the hints or whose it is;
    and a page that states the reading with the label (the label, then
    "is", "takes" or a colon) anywhere but its target's own row of
    reference.md; ("A readings corpus's hints name the level its target
    sits at"), for a readings corpus's level; ("A project's BUILD comment
    names neither the oracle's source"), for the label or a path of
    `oracle/src` in a comment of a project's BUILD or `.bzl` file. A
    reading stated in other words, the passive "is read as" among them (too many
    sentences say it of a byte or a path for a rule to refuse it), a page
    that states one without the label, and whether a hint that carries the
    label is its own target's, **(unchecked)**.
45. **What the subject calls an error is an error**: no target at any level
    requires accepting it, and a status or message the subject names is
    required at `basic`. A case the sentence does not reach is a convention
    of this repo's, at robust, saying so. **(unchecked)**

## Tests of a shell exercise

46. **Say how the subject runs each script turn-in**: `script = "./name"`
    where its example runs it so, `"bash"` where it runs `bash name`,
    otherwise `"sh"`. **Checked by:** `//tools:conventions` ("A shell
    exercise's call says what its check script relies on").
47. **Say whether the turn-in is one fixed file** (`stable = True`, a
    generator run twice must write the same bytes) or not. **Checked by:**
    `shell_call_problem`.
48. **A check script runs the turn-in only through `ck_run`**, shows what it
    wrote only through the library, runs git with the host's configuration
    switched off, and reaches a fixed system path only through
    `shell_exercise(redirect = ...)`. **Checked by:** `redirect_problem`, and
    `//tools:conventions` ("A check script runs the turn-in only through
    ck_run, and asks for it first") and ("Bytes are rendered by
    tools/runner_lib.sh, and by nothing else").
49. **A fixture holds the look-alikes** that tell a correct answer from each
    common slip, and from each reading: a near-miss name, a second key whose
    order differs, a directory named like a file. Each slip is proven by a
    selftest arm over a toy that makes it; open sentences reuse the
    `literal`, `regular` and `newest_first` readings before a new name.
    **(unchecked)**, beyond a new reading's suffix being registered in
    `_SUFFIX_LAYER`.
50. **Where no fixture can give a reference, add an `//oracle` command.** The
    check first reproduces the subject's examples (`ck_broken`), and names a
    failing input with `ck_detail`, never the expected value. **(unchecked)**
51. **A check only some machines can make is never manual**: it checks what
    every machine can and reports the rest with `ck_skipped`, the oracle
    deciding the skip and every probe overridable, so a selftest arm proves
    each branch on any machine; tags only the run needs go in `run_tags`.
    **Checked by:** `shell_tags_problem`, for never manual; the probes
    **(unchecked)**.
52. **An exercise another course repeats reads the original's tests**:
    `twin_of` on a `shell_exercise`, `c_twin()` beside a C one. **Checked
    by:** `//tools:conventions` ("A twin is its exercise's call again, and its
    README names the folder") and ("A C exercise that repeats another
    module's says so").

## Allocation failure and memory rules

53. **`allocfail` quotes the rule it applies** (`allocfail_rule`): the
    subject's sentence, or the reading stated as one. A program's sweep
    (`c_program(allocfail = [...])`) lists cases that allocate, sits at
    robust, and checks leaks (`allocfail_leaks`) only where the subject allows
    `free` and states a freeing rule. A case that allocates nothing reports
    NOTHING TO REFUSE, green: choose one that does. **Checked by:**
    `allocfail_rule_problem`, `allocfail_leaks_problem`,
    `program_allocfail_problem`, `_allocfail_problem`; the choice of cases
    **(unchecked)**.
54. **A memory rule valgrind applies is quoted at the call site**
    (`memory_rule`), and no runner quotes a subject of its own accord, not
    even a runner only one project calls: its messages quote what the call
    site hands it (`runner_quotes()`; the owner's ruling, 2026-10-09).
    **Checked by:** `_memory_rule_problem`, `_runner_choice_problem`
    (`_QUOTES_CHOICE`), and `//tools:conventions` ("A runner quotes no subject
    of its own accord", and "a runner's --quotes and _RUNNER_CHOICES
    disagree").
55. **`c_argv_table` comes after its `c_program`.** **Checked by:**
    `argv_guard_problem`.

## The cost layers

56. **Where one input's length is the question**, `perf_length = {oracle_fn,
    harness}`: an arm in `oracle/src/length.rs` and a `tests/exNN/len_*.c`
    that checks its own result without computing a reference. Reported,
    never gated. **(unchecked)**
57. **A cycles budget is measured**, at `-O2` on two correct answers -- the
    owner's, or a consenting student's, never one an agent writes; with
    none, the budget waits, as three of C 13's do -- and there is none where
    the cost follows the technique; a corpus with capacity cases sets
    `c_cycles(max_unit)`. **Checked by:**
    `//tools:conventions` ("The cycles row names every exercise whose c_cycles
    leaves cases out"), for `max_unit`; the budgets **(unchecked)**.

## Hints and messages

58. **A hint that can fire at first red asks a question about a concept**: no
    step list, no fix stated outright, no type to widen into, no invitation
    to read the oracle. **Checked by:** `//tools:conventions` ("A hint that
    can fire at first red asks a question"), ("A hint about a value that does
    not fit names no type to widen into") and ("No runner and no clue sends a
    student to read the oracle").
59. **A hint that sends a student to a manual page only libbsd ships** says
    `man 3bsd <name>` and names man.openbsd.org's page; the image extracts
    that page. **Checked by:** `//tools:conventions` ("A function whose manual
    page only libbsd-dev ships").
60. **A hint about a Norm rule** is checked against the pinned norminette
    (`tools/requirements.txt`), never the one on your machine.
    **(unchecked)**

## The tables a reader looks things up in

61. **A new suffix, raised test or manual test has its row**: `_SUFFIX_LAYER`
    and "Target names", `_RAISED` and "Targets raised above their layer",
    `_MANUAL` and "Manual targets", in reference.md. A test of the whole
    module is named there too. **Checked by:** `//tools:conventions` ("The
    target-name, raised-target and manual-target tables match the ones") and
    ("The tests of a whole module are named the same in the three places").
62. **A new layer** goes in `_LAYER_LEVEL` and reference.md's layer table, at
    the level that matches who needs it: one that informs but never gates
    belongs at the top. The ladder is written there once and nowhere else.
    **Checked by:** `//tools:conventions` ("The documented layer table matches
    the one the build actually uses") and ("The level ladder is written down
    once").
63. **A knob a runner reads from the environment** has its row in
    reference.md's "Environment variables". A setting `tools/runner_lib.sh`
    reads with an empty default and no such row is reset where the library
    is sourced, `NAME=""` on a line of its own, so a value left in the
    environment never reaches a runner that does not set it. **Checked by:**
    `//tools:conventions` ("Every knob a runner reads from the environment is
    in docs/reference.md's") and ("A setting tools/runner_lib.sh reads with
    an empty default is reset when").
64. **A doc that shows a whole-repo test run** says on that line that it
    needs memory to spare; a page shows one module's suite instead.
    **Checked by:** `//tools:conventions` ("A doc's whole-repo test command
    says it needs memory to spare").

## A new runner or macro

65. **Every test is a macro's or `hand_test()`'s**, never a bare `sh_test`,
    so its tags are derived like every other. **Checked by:**
    `//tools:conventions` ("Every test in a BUILD file is a macro's or
    hand_test()'s"), and `_audit_problems`.
66. **A runner sources `tools/runner_lib.sh`** and takes from it what every
    runner needs: the time budget, the run and how it ended, the signal
    traps, the byte renderer, excerpts, diffs (`rl_udiff`), a sanitizer's
    report (`rl_sanitized`, asked after every instrumented run), hints. A
    layer that is not the output test passes its own key as `rl_clues FILE
    FAILED FIRST CASE LAYER`'s LAYER (valgrind_test.sh's "valgrind"), so its
    own rows show first and the output test's are shown as the output's;
    nothing checks that a new layer passes it. **Checked by:**
    `//tools:conventions` ("A test's runner sources tools/runner_lib.sh"),
    ("Student code runs under the time budget"), ("How a program ended is read
    from tools/exit_status"), ("A signal trap ENDS the script"), ("A runner
    cuts captured output with rl_excerpt"), ("A clues.tsv is read by
    rl_clues"), ("Where two outputs part is found and shown by
    tools/runner_lib.sh alone"), ("A diff a log shows is made and shown by
    tools/runner_lib.sh's rl_udiff"), ("A sanitizer's options are set by
    rl_sanitizers"), ("A sanitizer's report is recognised by
    tools/runner_lib.sh's rl_sanitized") and ("A runner that sets the
    sanitizers up asks rl_sanitized how its run ended").
67. **Every SKIP is forced open by `NO_SKIP=1`**, says why it waits, and names
    the test to run with it, never the whole repo. **Checked by:**
    `//tools:conventions` ("Every SKIP honours NO_SKIP").
68. **A verdict says only what ran.** An OK line, or a footer that names a
    cause, is computed from the files, counts and flags that took effect, and
    a footer that names a cause gets a selftest arm where the premise is
    false. **(unchecked)**
69. **A new load-time refusal goes through `_refuse()`** and gets a
    `refusals` row in `tools/tests/macro_fixtures`, so a guard that stops
    being called turns `:contract_problems` red. **(unchecked)**: nothing
    finds a refusal written with a bare `fail()`.
70. **A tool or diagnostic script outside the zone does its work without
    the exercises' own commands.** A shell exercise's answer is a command
    line, and the same line in a check, a fixture or `tools/env-audit.sh` is
    that answer outside the zone (AGENTS.md §0): `env-audit.sh` counts a
    login's groups and `/etc/passwd`'s lines from what the kernel and the
    file hold, never through the commands a Shell 01 exercise is written
    with, and a check computes its expected value from `//oracle` or by
    construction. **(unchecked)** beyond `tools/answer_scan.sh`, which the
    template build runs and which finds a copy of this tree's own answers,
    never a different command line that does the same work.

## Proving it

71. **Every fix lands with a check that was red before it**: a selftest arm
    beside its runner's arms (`want_red` insists on exit 1, never 2), a
    `starlark_unit` or `macro_fixtures` case, or a conventions rule with its
    reason. An arm calls only helpers its file defines; a selftest toy takes
    an exercise number, and a fixture tree's TODO.md and HISTORY.md a
    writer, no other block uses. **Checked by:** `//tools:conventions`
    ("A script that calls need() defines it"), whose rules report an arm
    that "calls ... and never defines it", a toy exercise written "from two
    blocks", made "from two statements" or named "in two sections", and a
    fixture tree's TODO.md or HISTORY.md written "from two statements";
    that the check was red before it **(unchecked)**.
72. **Prove a check on more than two trees**: the stubs, a correct answer, a
    broken tree (a compile error, a stray `main`, a missing file), and every
    layout the subject allows. A judging harness also gets arms over invented
    bodies -- empty, wrong-shaped, partial -- and a runner flag that changes
    what runs gets an arm that fails when the flag is dropped from the run,
    and another when it is dropped from the gate. **Checked by:**
    `//tools/tests:macro_fixtures_test`, for the macros' toy exercises; the
    rest **(unchecked)**.
73. **Measure what a case list catches** with `tools/probe_under.sh`: a model
    of the exercise wrapped in one mistake stands in for the program, and
    the targets that go red are what the BUILD file records. Never an answer.
    **(unchecked)**
74. **Run the suite on a still tree, with `NO_SKIP=1`, and compare target
    lists as well as reds**: a target that fails analysis is missing from a
    status diff, not red, and a red on an answer that was green is a
    regression. A run that saw a file change can leave a result cached for
    the version it read, and a plain re-run serves it again, so the run
    you compare takes `--nocache_test_results`; a test program that still
    behaves like the old file needs `bazel shutdown`, then
    `--nocache_test_results --use_action_cache=false`. **(unchecked)**
75. **Look for an answer that left the zone**: `sh tools/answer_scan.sh`
    finds an answer's identifiers, header macros or Makefile lines in a file
    outside `deliverable/` and `generators/`, which a test or a comment can
    carry as easily as a solution file. **(unchecked)**: run it yourself; the
    template build runs it too.
