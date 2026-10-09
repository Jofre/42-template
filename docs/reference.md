# Reference

**For:** anyone who knows what they want and needs to look it up.
**Nothing here explains itself** — the explanations are in
[testing.md](testing.md), [environment.md](environment.md) and
[design.md](design.md). This page is tables.

---

## The four levels

Every test carries a **layer** tag naming what kind of check it is, and each
layer sits at one of four levels. The levels are cumulative: `strict` runs
everything in `basic` too.

| level | means |
|---|---|
| `basic` | failing this is an outright KO wherever the project is graded: at 42's Moulinette, or at a defense, where evaluators grade a project its subject says no program does (the rushes) |
| `strict` | real, but not certain: conditional on the evaluator's own `main()`, on whether 42 runs a memory checker, or on a case the subject leaves open |
| `robust` | rigour this repo adds beyond any sentence in a subject |
| `complete` | portability and cost; informative more often than not |

`tools/defs.bzl`'s `_LAYER_LEVEL` is the machine-readable source of this
mapping — if this table and that constant ever disagree, the constant is right.

```sh
bazel test //c-piscine/c-piscine-c-05:basic       # one module, one level
bazel test //c-piscine/c-piscine-c-05:complete    # same as //c-piscine/c-piscine-c-05/...
```

## Run contract

The questions every exercise raises, decided once. Runners apply them through
shared helpers; a check never re-decides one. The reasons are in
[design.md](design.md#do-not-let-a-layer-invent-a-requirement).

| question | `basic` | above `basic` |
|---|---|---|
| exit status | checked only where the subject names one | a non-zero exit where the subject names none fails at `robust`; a status a sentence is only read as naming (`exit` + `exit_quote` + `"level": 2`) is compared at `strict` |
| stderr | ignored, unless the subject requires something of it: a case compares one stream, and what a program also wrote to the other is shown (`note: also written to ...`, or a count under a corpus report), never graded | ignored, unless the subject requires something of it; a corpus runner (`argv_check.sh`, `bsq_check.sh`, `file_check.sh`, `rush01_check.sh`, `rush02_check.sh`) is told which at every call (`--stderr-empty` or `--stderr-ignored REASON`), except its replay under a memory checker (`--sanitized`, `--valgrind`), where stderr carries the checker's report and no output is judged |
| execute bit on a shell turn-in | required only where the subject runs the file directly (its example shows `./name`) | — |
| a sentence the subject leaves ambiguous | not checked: only the cases every reading agrees on | read at `strict`, one reading per exercise, by a target of its own: only that target's hint and its row on this page state the reading it tests, always as "this harness's reading", never as the subject's, and no `basic` hint, clue or doc names it (AGENTS.md §2); its call site in the BUILD file says why |
| an input the subject says must fail | must fail, with the status or message the subject names | no level may require accepting it |
| a convention of this repo's own | never | `robust` or `complete`, saying whose decision it was. So is what a reference does with a case the subject's words do not reach, which is no reading of them: "ASCII order" gives no place to a byte above `0x7f` (C 06 ex03, C 11 ex06), where "alphanumeric" reaches every byte, and whether one above `0x7f` is in the class is a reading (C 02 ex09) |

Where a program runner applies the exit-status row today. A run killed by a
signal is a crash, not a return, and fails at every level. Which of the two a
run was is read from `waitpid()` by `tools/exit_status`, never guessed from the
status: a shell reports signal N as 128+N, which a program can also return
(`return (-1);` is 255), so a program that returned -1 has returned. Every
runner makes its runs through `tools/runner_lib.sh` (`rl_run`) and reads the
ending from it (`rl_classify`); `perf_run` and the shell checks' `ck_run` say
it by name too, and `//tools:conventions` refuses a script that guesses.

| runner | a plain non-zero return is noted by | and fails at `robust` in |
|---|---|---|
| `progname_test.sh` (C 06 ex00) | `exNN_progname` | `exNN_progname_exit` |
| `argv_table.sh` (C 06 ex01–ex03, Reloaded ex18–ex19) | `exNN_output`, `exNN_asan` | `exNN_exit` |
| `argv_check.sh` (C 06 ex01–ex03) | `exNN_argv_diff` | `exNN_argv_diff_exit`, which replays the same generated corpus: `exNN_exit` runs only the table's rows |
| `diff_output.sh`, for `c_program`'s cases (C 10, C 11 ex05, BSQ, Rush 01, Rush 02, Reloaded ex27) | `exNN[_case]_output` | `exNN[_case]_exit`, which runs the same invocation -- one per invocation: two cases that make the same run and compare its two streams share the first one's twin (C 10 ex00's `empty` and `empty_stderr`). A case the subject answers with an error message it names is marked `invalid_input` and gets none: a non-zero status is how an error conventionally ends. Nor does an `any_of` or `survive` case, whose reading the subject leaves open: one reading may be an error; nor one whose output test compares its status already (`exit` with `exit_quote`) |
| `header_check.sh` (`c_header`'s `exit` key: C 08 ex01) | — | the case itself, which `c_header` refuses below `robust` unless an `exit_quote` gives the subject's sentence |
| `run_check.sh` (Rush 00's own `main.c`) | `ex00_rushNN_main` | `ex00_rushNN_main_exit`. The subject's `main.c` is an example ("Example of main.c file", and the defense replaces it), so its `return (0);` names no status the turn-in must return |
| `make_test.sh` (every `c_make`: a Makefile or creator script) | `exNN_build`, for a `make` or a rule that did its job | `exNN_build_exit`, which runs the same build and rule steps and reads what each did the same way. A run that did not do its job — a rule the Makefile lacks, an `all` that built nothing, an `fclean` that left the artifact, a `clean` that left objects, a `re` that kept the old artifact, a rebuild that made nothing — is `NOT JUDGED` there: that is `exNN_build`'s finding |

A run that never reached `main` is none of these. A runner above that learns
of one stops with exit 2, a broken harness, rather than judge output or a
status nobody's program produced, and it learns from `tools/exit_status`,
which knows such a run two ways. When exec itself fails (the file is gone or
not executable, or its `#!` names an interpreter that is not there), it always
knows. When exec succeeds and the dynamic loader then stops the program (a
shared library, a symbol or a version it needs is missing), `waitpid()` sees
an ordinary exit, 127 or 1, and the helper tells it apart only by the loader's
own message, read back from the run's stderr -- so only where the runner sends
that stderr to a file. Every runner above does, and so does every corpus
runner (`argv_check.sh`, `file_check.sh`, `bsq_check.sh`, `rush01_check.sh`,
`rush02_check.sh`): stderr is never compared, but a case that wrote to it is
said, pass or fail (the stderr row above).

A status the subject does name goes in `exit` with the sentence in
`exit_quote`, and is then compared at `basic`, in the case's own output test.
No subject in the repo names one yet. A status a sentence is only READ as
naming is the same pair with `"level": 2`: C 10's "performs the same function
as the system's cat", for the status after a file that will not open (its row
among the raised targets states the reading). It is compared in the case's output test at `strict`, the row above for
a sentence the subject leaves ambiguous, and a wrong one is reported as that
reading, with the sentence (`--exit-source reading`). No other level takes an
`exit_quote`: a quoted status raised past `strict` fails at loading, since a
status the subject names is never raised and one that is this repo's rule
quotes no sentence. `c_header`'s cases take the same keys, and quote the
sentence the same way.

**Writing a `c_program` case** for a project not written yet: every case
says what its status means. An input the subject answers with an error --
an error message it names ("Error", "map error", "Dict Error", the system
tool's own diagnostics) -- carries `"invalid_input": True`; a status the
subject names carries `exit` and `exit_quote`; an `any_of` or `survive` case
judges none unless it says `exit`; anything else gets the robust twin, which
expects 0. A `survive` case says what it ran (`RAN:`), and SKIPs while its
exercise's first case at basic is red: a program nobody has written ends by
itself too, and green there said nothing (`_survive_gate`; NO_SKIP=1 runs it). The test is what the subject says the program does, not the
adjective: do-op's "invalid operator" prints 0 and its "invalid" argument
count prints nothing, two ordinary outputs, so neither is marked. A key a
case's shape does not take fail()s at loading (`_CASE_KEYS` in
`tools/defs.bzl`), naming the key it was probably meant to be, so a misspelt
`invalid_input` cannot quietly turn into a twin that expects 0 from an error.
An omitted one cannot either: a case that compares stderr, or hands the
program a name that will not open (`missing_file`), and states neither
`invalid_input` nor `exit` fail()s at loading (unless it is an `any_of` or
`survive` case, which gets no twin), and the twin of any other such case
refuses to run (exit 2, naming the key) when its expected output mentions an
error. Where the answer is no, say so: `"invalid_input": False` is a
decision, and its twin expects 0.

**A program that reads files, or imitates a system tool**, needs more cases
than the subject's example transcript, which only ever takes the happy path:
C 10's ex02 and ex03 had no error case at all; BSQ and Rush 02 had several,
every one about a file's content, and none naming a file that does not exist
(finding 110); C 10 ex03's corpus handed the program one file per case,
where the tool it imitates takes several (finding 109); do-op had none of the
number limits
(finding 118). Before calling its case list done, check that it has these,
each at the level the Run contract gives it: a name that will not open, alone
and before a good one; a directory; an empty file; several operands, where
the tool reads them as one stream or heads each one; no file operand, where
the tool reads standard input, and `-`; each form the tool accepts an option
in (`-c 20`, `-c20`); the limits of every number argument (`INT_MAX`,
`INT_MIN`, a result that does not fit). Where the program's messages or status follow a pinned tool,
take them from `//oracle`'s model of it, cross-checked against the tool --
never typed, never cut by running a system tool at test time -- name that
model in `c_program`'s `model`, so each case's `exNN_<case>_model` re-runs it
and fails the day a fixture and the model part (an edit by hand, a fix to
the model), and check
that the tool's answer does not depend on the machine: GNU `tail -c` after a
directory stops on one filesystem and reads on on another (C 10's BUILD file),
so no case asks for either. `c_program` refuses, while loading, an exercise
whose contract allows `open` and no case of which names a file that will not
open, unless `no_missing_file_case` says why there is none: a case says so in
`"missing_file"`, the operand from its `args` that names no file, which must
not be a fixture, an option, `-`, `.` or `..`; the case says what its status
means (`invalid_input`, `exit`, or an `any_of` or `survive` kind), and its
output test stops as a harness error if something by that name is where the
program runs (`diff_output.sh --absent`). That is all it checks: that the
path is taken, not that the rest of this list is there. Then measure what the list catches
rather than believing it: `tools/probe_under.sh`, as `bazel test
--run_under`, stands a program with one mistake in for the student's -- a
model of the exercise wrapped in the mistake, never an answer -- and the
targets that go red are what the list catches.

**A corpus runner's standard error** is a choice at every call, never a
default: `argv_check.sh`, `bsq_check.sh`, `file_check.sh`,
`rush01_check.sh` and `rush02_check.sh` each take `--stderr-empty` (every
generated input is valid and the subject gives a valid input no message) or
`--stderr-ignored REASON`, refuse a call with neither or both (exit 2,
`tools/runner_lib.sh`'s `rl_stderr_choice`), and `tools/defs.bzl` refuses
such a call while loading (`_RUNNER_CHOICES`); `//tools:conventions` holds
a runner that takes the pair and that table to each other.

A case's run is its `args`, then two keys for what `args` cannot say:
`argv_file`, a file of more arguments, one per line (an empty line is an
empty argument, which Bazel drops from `args`), and `cwd_files`, which runs
the program as `./<name>` -- `c_program`'s `name`, the subject's executable
name -- from a folder holding only it and the files named there (Rush 02's
`./rush-02 42` beside `numbers.dict`). Every arm of the case runs the same
thing: output, exit twin, asan, valgrind, the allocfail sweep, and the gates
of the last two. Each
opens its log with a `RAN:` line that runs it again from the repository
root -- or, for a case run from its own folder, from a folder holding the
files listed under it -- and its hints may be keyed to the case's `name`
([testing.md](testing.md#reading-a-failure)), or to `valgrind`, which fires
in the memory arm of every case whose `clues` names the file and in no output
test, so `valgrind` is no case's name: `_case_problem` refuses it. A program
keeps its hints as keyed rows of one `clues.tsv` per exercise, which every
case's `clues` names, rather than a file per case: one file is one place to
read every hint the program has, and a row can name the several cases it is
about. A target written by hand that replays a corpus and prints hints
(`bsq_check.sh`, `rush01_check.sh`) is handed the same file and `--case`
with its name after `exNN_`, and its rows are keyed to that name.
`//tools:conventions` checks that every such label names a case or a
`--case`; `c_levels()`' audit refuses a `clues_<x>.tsv` in an exercise any
of whose tests passes `--case`, and a test of it that hands its `clues.tsv`
to a runner without one (`_keyed_clue_problems`, ruling R7 of TODO.md
section 23).

**After a crash, what a missing row means** depends on who wrote the program.
The harness's own test programs (`c_function`, `c_libft`, `c_header`, the
rushes' fixtures, and the `ilp32` rebuilds of them) link
`tools/unbuffered_stdout.c`, and their output tests pass `diff_output.sh
--harness-fixture`: there the first missing row is the case that was running.
A student's own program (`c_program`) may buffer its output, so its table
marks no row and says how many lines reached the output. `diff_output.sh`
refuses `--harness-fixture` for a binary without the library's marker, and
`//tools:conventions` refuses it for one a macro did not build with
`_output_fixture_binary`.

How long a run may take is decided once too, in `tools/runner_lib.sh`, which
every runner that runs student code sources. Each run gets its own cap (the
`*_TIMEOUT` variables below) or what is left of the test's own time limit,
whichever is less; the runner keeps a few seconds of that limit back (a
tenth of it, 4 to 20 s) to write its report. So a program that never ends
is stopped by the runner, which says `did not finish within Ns: an infinite
loop, or too slow on <case>`, and a sweep stops once three runs have hung
instead of spending the test's limit rediscovering it. A test Bazel itself
reports as `TIMEOUT` ran out of even that margin.

## Suites

| suite | runs |
|---|---|
| `//<module>:exNN` | every test of one exercise, whatever emitted it, but its manual ones |
| `//<module>:basic` … `:complete` | one level, whole module |
| `//<module>:manual` | the module's [manual targets](#manual-targets), and nothing else |
| `//<module>/...` | the whole module, manual targets left out |
| `//...` | the whole repo, manual targets left out |

A module's suites come from `c_levels()`, which finds its exercises wherever
one shows up: in the subject contract, under `tests/`, and among what the
student made -- a `deliverable/exNN/` folder or a `generators/exNN.sh`. So a
module gains a suite the moment it gains an exercise, and a folder for an
exercise the subject does not have gets one too, holding the `exNN_files` test
that says so, which fails whatever the subject says about extra files: no
exercise's file list reaches it. The rest of the pushed tree -- a file at the
root of `deliverable/`, or in a folder that is no exercise's (`old/`, `ex5/`) --
is one test of the whole module, `//<module>:deliverable_files` (basic, in no
`:exNN` suite), which fails on any of it. A project that turns in at
`deliverable/` itself has none: its `exNN_files` walks the whole tree.

When a module loads, `c_levels()` also audits its tests as a whole
(`tools/defs.bzl`, `_audit_problems`), and the module does not load while one
breaks a rule: every test is named `exNN_<what>`, carries its exercise's tag,
exactly one layer and that layer's level, ends in a suffix of the [target
names](#target-names) table for that layer, and sits where that table puts it
unless the [raised targets](#targets-raised-above-their-layer) table lists it;
a manual one is in the [manual targets](#manual-targets) table; every
program that links a harness over a student's files names the `_prototype`
test of the signatures it calls, a test the module declares, or says why
there is none; every file a named case reads in a directory an
`_oracle_fixtures` test holds to `//oracle` is one of that test's `--owns`
patterns, so none is hand-typed beside the reference's unseen; every
exercise has a test; every exercise whose contract names a `Makefile`
has its `exNN_build` (a `c_make` call, where its recipe and wildcards checks
are each decided); and EACH generated corpus replayed through a corpus
runner (`tools/defs.bzl`'s `_CORPUS_RUNNERS`) has its twins under the memory
checkers -- a replay of the same corpus on the ASan build, and, where the
subject allows `malloc` or prints no allowed-functions line at all, a sample
of it under memcheck -- which `corpus_memory()` emits, reading the second
from the subject contract. "The same corpus" is the replay's arguments less
the ones that choose no input (`_CORPUS_RUN_OPTS`: the program, how a case is
judged or shown, what standard error is held to, the gate): the generator,
its size and the transport -- a map as an argument, on stdin, several per
run -- all count. A twin that replays less on purpose names what it stands
in for in `corpus_memory()`'s `covers`, with the reason, and one left without
memcheck says why in `no_valgrind`. `//tools:conventions` holds the three
tables below to the ones in `tools/defs.bzl` the audit reads,
`_CORPUS_RUNNERS` to the runners, `_CORPUS_RUN_OPTS` to options they take,
and every `//oracle` arm named `<x>_fixtures` to a test that passes it as
`--fn`. And every gate runs one of the module's output tests: a corpus
runner's (`_gate_problems`), and one that replays the case its layer runs, the
valgrind arm's and the allocfail sweep's (`_case_gate_problems`) -- the same
program, expected file, arguments, standard input and run folder. A gate
that runs the program some other way can be red on a correct program, and
its layer then SKIPs, green, wherever `NO_SKIP=1` is not set.

## The layers

| tag | level | checks |
|---|---|---|
| `norm` | basic | norminette (C) / a shell exercise's generator parses (`sh -n`); its shellcheck lint, and the lint of a script it writes, run as `_lint` and `_posix`, above basic (see [Shell turn-ins](#shell-turn-ins)). Red on any file's `Error!`, wherever it sits in the run. A Notice alone leaves the file `OK!` yet makes norminette exit 1, and no subject says which counts: this target passes it with a warning, and its `*_notice` twin, raised to strict, fails it. The log names the norminette version, the `-R` that took effect (norminette keeps only the last one) and a `bazel run //tools:norminette` command that reproduces the verdict. norminette does not enforce every rule of the Norm: a header with no protection from double inclusions at all, and the name of a struct, union or enum defined inside a `typedef`, both pass the pinned 3.3.58. `_norm_header`, at strict, checks those two in every header a project turns in |
| `compile` | basic | clean under **both** clang-12 and gcc-10 at `-Wall -Wextra -Werror` |
| `output` | basic | what the program printed, against the expected fixture. A Makefile or creator script's `exNN_build` carries this tag too: it builds the artifact, and checks each rule the subject names |
| `files` | basic | the deliverable holds every file the subject names and nothing it does not allow, anywhere under the turn-in directory: a copy in a subfolder the subject does not allow is a file nobody asked for, named by its path. Such a file is this layer's report alone: every other layer compiles the files the subject names or allows, and no other. A shell exercise's is what its generator leaves in a scratch folder (never `deliverable/`): the turn-in is listed as present or not produced, which `exNN_output` reports, and anything else fails. Where a subject asks for "a Makefile and all the necessary files" (BSQ, Rush 02, C 10, C 11 ex05, Reloaded ex27: every exercise with a `c_make` whose contract allows `.c` files by pattern), a `.c` the Makefile never compiles (by `make -Bn`) is not necessary, and counts as one; while make cannot plan a build, or the Makefile compiles nothing yet, no `.c` is judged that way. A module's `deliverable_files` covers what is outside every exercise folder |
| `forbidden` | basic | only the functions the subject authorises are called, plus any variable it allows by name (C 10's `errno`). Judged and reported under the names you wrote: where glibc compiles one into an internal symbol (`errno` into `__errno_location`, `<libgen.h>`'s `basename` into `__xpg_basename`, every `<ctype.h>` classifier into `__ctype_b_loc`), that symbol is mapped back first |
| `prototype` | basic | your definition matches the signature the subject fixes, and your header holds the structure the subject prints, where it prints one (C 12's `t_list`, C 13's `t_btree`: the project's `tests/layout/<header>`; its names, `tests/layout/tag/<header>`, at strict). A red says which: the signature, the structure, its names, a header read twice with no include guard, a name defined in two places, or a file that does not compile on its own |
| `symbols` | strict | the file exports exactly what the subject names; helpers are `static` |
| `method` | strict | how the turn-in is built, where its subject says so and nothing it prints can show it (`tools/method_check.sh`; [Sentences about how](#sentences-about-how) lists each). Recursive or iterative (`exNN_method`, `c_function`'s `method`): the exercise's own test program runs on the student's sources compiled with `-finstrument-functions`, and the layer reads whether a function of theirs is entered again while it is still running -- recursive when one is (the function, a static helper, or two calling each other), iterative when none ever is (a closed form or a table is iterative; a loop over a stack of its own is not recursive). A fixed-size array (`exNN_fixed_array`, `c_program`'s `fixed_array`): the pinned gcc names every array of variable length, every `alloca` and, where the subject bounds the array, every object of that many bytes or more -- an upper bound only, on the object and never on the stack frame that holds it |
| `valgrind` | strict | no leaks or invalid access to the heap or to unmapped memory, and every descriptor the program opened is closed. memcheck does not see a write past an array on the stack while it stays inside the stack, and its OK line says so: an ASan build sees those (the exercise's `asan` layers, where it has them). Leaks only where the subject allows `malloc`; the invalid-access and uninitialised-value half runs over `c_mem_check`'s probes too, where nothing allocates at all. Where a program's subject allows `malloc` (Rush 01, Rush 02, BSQ, C 10 ex02/ex03), a sample of 25 cases of each generated corpus runs under memcheck as well (`_valgrind` on the corpus: `ex00_sweep_valgrind`, `ex00_rush02_valgrind`, `ex00_rush02_dictfuzz_valgrind`, `ex00_bsq_valgrind`, `ex00_bsq_stdin_valgrind`, `ex00_bsq_multi_valgrind`, `exNN_file_valgrind`). A red states the rule it applies, under its verdict and once for a corpus: the subject's own sentence where `c_program` has a `memory_rule` (Rush 02's p.7), which `corpus_memory()` hands its corpus's sample too, and otherwise this harness's rule, said to be so |
| `diff` | strict | a seeded corpus, against the Rust reference in `//oracle`: hundreds of thousands of cases for a function, hundreds for a program, and among them a few far past the capacities a student might pick (arrays of 5000 ints, strings of 5000 words), since a corpus large only in its number of cases never fills a fixed-size array (finding 041). The corpora seed `0x7f`/`0x80`/`0xff` on purpose, where a signed-`char` mistake hides. Some hand-written fixtures hold such bytes too, and always where an exercise repeats a contract another module fuzzes (C 04 ex00/ex01, C 09 ex00), since each module is graded on its own files; where a fixture holds none, this layer is the first to see that class. Every block malloc hands out there starts holding `0xa5`, never a zero, in its first 4 KiB and its last bytes (`tools/dirty_malloc.c`, linked by `//tools:diffio`), so a field, count or terminator a function never writes in memory it allocated does not read as the zero most of them should hold; no memcheck layer runs such a build, where the fill would read as written |
| `diff_asan` | robust | the same corpus under ASan/UBSan, judging memory and how each run ended, never the output. For a function (`c_diff`), the first `asan_count` cases of its corpus (200000 of the 400000, by default) on its harness's ASan build; a crash names the case, symbolised by the pinned `llvm-symbolizer`. For a program, the corpus runner's `--sanitized` replay on the ASan build of the program: C 06 ex01–ex03 (on the guarded build `c_argv_table` makes, each argument in a heap block of its own, so a read past an argument's end is seen: `--guarded-argv`), C 10 ex00–ex03, Piscine Reloaded ex27, Rush 01's sweep (its 4x4 cases and the argc probes) and its reading's shape probes, Rush 02's generated dictionaries, and BSQ's maps, readings, long maps and big maps (`tools/runner_lib.sh`, "A CORPUS UNDER A MEMORY CHECKER"). Those with no guarded build say in their verdict that the arguments were not watched (`rl_mem_argv_note`). A replay under a checker makes no stderr choice: standard error is where the checker reports |
| `asan` | robust | adversarial memory probes, and every program case under ASan/UBSan |
| `allocfail` | basic | one `malloc` refused at a time; the error must be reported, not dereferenced. Opt-in per exercise, and only where the subject or a man page it cites states the contract. Its `_allocfail_leaks` target, at robust, also asks that nothing obtained before the refusal is left allocated: the repo's rigour, where the subject allows `free`. A program (`c_program`'s `allocfail`) is swept at robust as `_program_allocfail`: no grader at 42 refuses a program an allocation. Every allocfail target prints, under its verdict, the rule its call site states (`allocfail_rule`, required), and never one of its own: the runner cannot know which subject it reads |
| `ilp32` | complete | the same cases where `long` is no wider than `int`, in a build that stops at undefined behaviour (`SIGILL`) |
| `perf` | complete | how cost grows with the number of cases, in time and memory, and, where a BUILD file asks, with the length of one input (reported, never failed). Fails only past its own lines: the case-count exponent (2.6, measured twice), 5000x the reference's time or 200x its memory, or a crash |
| `cycles` | complete | instructions per unit of work, via callgrind, the allocator and a harness callback shown apart; a corpus's capacity cases, far bigger than the rest, are left out where the call says so (`c_cycles`' `max_unit`: C 07 ex03 and ex05, C 09 ex02, C 12 ex02, ex08 and ex14, C 13 ex01, ex05 and ex06), and the report says how many. Never fails on its numbers, nor on a run too long to profile (reported); fails when the function crashed under it or did not build |
| `oracle` | complete | the reference's own cross-checks (`//oracle:oracle_check`), each fixture a model of a tool made, against that model (`exNN_<case>_model`), fixtures the reference writes held to it (BSQ's, Rush 00's and Rush 02's `ex00_oracle_fixtures`), and named cases the reference program passes (Rush 02's `ex00_reference_cases`) |
| `selftest` | complete | the harness's own guards (`//tools/tests:selftest*`, and one inside modules: a twin's `exNN_twin`, see [Shell turn-ins](#shell-turn-ins)) |

`norm`, `compile`, `files`, `forbidden` and `prototype` are green on a fresh
stub. `output` is the one that is red until you write the exercise.

A test can sit above its layer's level and keep its layer tag: by its name
(the `_exit` twins of the Run contract table -- `exNN_exit`, `exNN_<case>_exit`,
`exNN_progname_exit`, `ex00_rushNN_main_exit` and `exNN_build_exit` under
`output`, `exNN_argv_diff_exit` under `diff` -- which judge only how each run
ended, never what it printed or built; `_literal`, `_regular` and
`_newest_first`; `_posix`
and `_lint`;
`_norm_notice` and `_norm_header`) or by its
BUILD file (the [raised targets](#targets-raised-above-their-layer)). A
`--test_tag_filters` on the layer selects them too.

**One exception, and the triage knows about it:** the header exercises —
c-08's, and Piscine Reloaded's ex22 and ex23 — are HEADERS, and a header that
defines nothing cannot compile the subject's own `main`, so those are red at
`compile` while still stubs. The macro exercises (c-08 ex01 and ex02,
Reloaded ex22) are red at `forbidden` too: with no macro, `EVEN(...)` or
`ABS(...)` is a call to a function nobody authorised. `first_red.sh` asks `stub_check` before blaming either on you, which
is why it never does there.
[testing.md](testing.md#which-red-should-i-fix-first) says the same from the
triage's side: it is the header exercises' documented `c_header` exception.

`//oracle` and the `//tools/tests:selftest*` targets live outside every
module, so only a whole-repo `bazel test //...` reaches them — no per-module
suite and no submit gate can. Four kinds of harness target live inside a
module, and none runs anything of yours: a twin's `exNN_twin` (`selftest`),
which guards the harness's own `tests/` folder, a program case's
`exNN_<case>_model` (`oracle`), which holds a
fixture to the model that made it, BSQ's, Rush 00's and Rush 02's
`ex00_oracle_fixtures` (`oracle`), which check that the named cases' files
are what the reference writes, and that no file the reference owns was typed
by hand, and Rush 02's `ex00_reference_cases` (`oracle`), which runs every
named case with the reference program in place of yours, so that a case and
the file it expects cannot drift apart. Each runs in its module's `:complete`
suite and its per-exercise suite, and in a submit gated at `complete`, and at
no lower level.

## Target names

The end of a target's name says which layer it is: the longest of these
suffixes it ends in. A case's or a variant's name sits in front of it
(`ex05_modzero_output`, `ex00_rush03_asan`). Where a suffix sets the level
itself, it is the one in this table, not the layer's. To read a target's
tags: `bazel query --output=build //<module>:<target> | grep tags`.

| suffix | layer | level | what it is |
|---|---|---|---|
| `_allocfail` | `allocfail` | basic | one `malloc` refused at a time |
| `_allocfail_leaks` | `allocfail` | robust | the same sweep, judging what a run that reported the error left allocated; only where the subject allows `free` (the repo's rigour) |
| `_argv_diff_exit` | `diff` | robust | the argv corpus again, judging only how each run ended (Run contract) |
| `_asan` | `asan` | robust | a run under ASan/UBSan: a program case's, argv[0]'s (`_progname_asan`), the argv table's (`_asan`, and `_argv_asan` with argv and each argument in heap blocks of exactly their size), or the adversarial probes |
| `_bonus_9x9` | `diff` | strict | Rush 01's sweep, every board size up to 9x9 required |
| `_bsq_big` | `output` | strict | BSQ: maps where the method matters (a million cells whose square is past 64 a side, 10000 lines of 100, a million cells with three obstacles), as arguments; a guard against a hang, never a deadline: one that does not finish in its time is reported as such, never as wrong (the subject sets no time limit) |
| `_bsq_big_stdin` | `output` | strict | the same maps, each on stdin |
| `_bsq_long` | `output` | basic | BSQ: maps past every capacity a program might pick (a 70000-cell line, 70000 lines, no empty cell) whose biggest square is one cell at most, so every correct program finishes them; as arguments |
| `_bsq_long_stdin` | `output` | basic | the same maps, each on stdin |
| `_bsq_multi` | `diff` | strict | BSQ's corpus, several maps per run |
| `_bsq_stdin` | `diff` | strict | BSQ's corpus, a map on stdin |
| `_build` | `output` | basic | runs the Makefile or creator script, and checks what it built, that each rule the subject lists is there, what a rule does where the subject defines it, and every check the call site quotes a sentence for (the compile commands, "Watch out for wildcards!") |
| `_build_recipe` | `output` | strict | every command the build runs that compiles a `.c` uses `cc` with `-Wall -Wextra -Werror`, where that sentence describes what the grader does and reading it as binding the recipes is one reading (C 09 ex00's script, C 10, C 11 ex05, Reloaded). A command is judged when its word names a C compiler (`cc`, anything ending in `cc`, `clang`, `c89`, `c99`, a C++ driver, a version after any of them); every other tool is left alone. A Makefile's are what `make -n` plans, looked through `env`, `sh -c` and the like, and every compiler a build of a copy of the tree ran by name (a loop's turns); a creator script's are what its trace (`sh -x`) shows, and every compiler it ran by name, trace or not |
| `_build_rules` | `output` | robust | what `clean`, `fclean` and `re` do, where the subject lists them without saying: this repo's convention |
| `_build_wildcards` | `output` | strict | the Norm's "no \*.c, no \*.o": a decoy source beside the Makefile's sources, and an object no rule made beside its objects before each cleaning rule -- in an object directory of its own too (`obj/`), where a rule that removes the directory whole names no file and is not judged |
| `_compile_clang` | `compile` | basic | clean under clang-12 at `-Wall -Wextra -Werror` |
| `_compile_gcc` | `compile` | basic | clean under gcc-10 at `-Wall -Wextra -Werror` |
| `_cycles` | `cycles` | complete | instructions per unit of work |
| `_defense` | `output` | basic | Rush 00: the subject's defense case, `rush(123, 42)`, compared in full with the reference's picture; one row, never the picture |
| `_diff` | `diff` | strict | a generated corpus against the reference (`_argv_diff`, `_file_diff`, `_bsq_diff`, `_rush02_diff`; Rush 02's `_settled_*_diff` judge only what every reading agrees on) |
| `_diff_asan` | `diff_asan` | robust | that corpus under ASan/UBSan, crashes and sanitizer reports only: for a function's corpus, its first `asan_count` cases; for a program's corpus, the corpus of the plain target whose name it extends, replayed the same way (`ex00_bsq_stdin_diff_asan` is `ex00_bsq_stdin`'s; `ex00_bsq_diff_asan` is `ex00_bsq_diff`'s), with Rush 01's `ex00_sweep_diff_asan` leaving the bonus sizes to the plain sweeps |
| `_exit` | `output` | robust | how each run ended, never what it printed (Run contract; `_<case>_exit`, `_progname_exit`, `_build_exit`) |
| `_fixed_array` | `method` | strict | the subject's fixed-size array: no array of variable length, no `alloca`, and where the subject bounds it, no object of the bound or more, the bound being one reading of the subject's sentence, stated in the target's own hint (C 10 ex01) |
| `_files` | `files` | basic | the files turned in; also a folder for an exercise the subject does not have, and `deliverable_files`, the module's files outside every exercise folder (no `exNN_` prefix: it is no exercise's) |
| `_forbidden` | `forbidden` | basic | only the functions the subject allows |
| `_ilp32` | `ilp32` | complete | the cases where `long` is no wider than `int` |
| `_issued` | `output` | basic | a file 42 issues and the subject turns in is in the turn-in (Rush 02's `numbers.dict`; `tools/resources.tsv`, `c_issued`) |
| `_layout_prototype` | `prototype` | strict | the structure's names as the subject prints them (its tag, the type of each field pointing to another node), which memory does not see; and its layout too where the grader links no function built on it (C 12's and C 13's ex00), so that only the grader's own test code could expose a difference |
| `_lint` | `norm` | robust | shellcheck's warnings on a shell exercise's generator, and on the script it writes (Shell turn-ins) |
| `_literal` | `output` | strict | a sentence of the subject that two readings part on: which reading the target tests is in its exercise's row under [Shell turn-ins](#shell-turn-ins) |
| `_main` | `output` | basic | Rush 00: the team's own `main.c` links, runs and prints |
| `_memcheck` | `valgrind` | strict | the exercise's own fixture under memcheck |
| `_method` | `method` | strict | recursive or iterative, as the subject says: whether a function of the turned-in file is entered again while it is still running, on the exercise's own test program |
| `_model` | `oracle` | complete | a program case's expected file against the `//oracle` model of the tool it was made from (`c_program`'s `model`: C 10, Reloaded ex27); runs nothing of yours |
| `_newest_first` | `output` | strict | an order by date where the subject names no direction: which direction the target tests is in its exercise's row under [Shell turn-ins](#shell-turn-ins) |
| `_norm` | `norm` | basic | norminette, or `sh -n` on a shell exercise's generator |
| `_norm_header` | `norm` | strict | the two rules of the Norm the pinned norminette skips, in every header the exercise turns in (`c_levels()` emits it from the subject contract, `tools/header_norm.sh`): "Header files must be protected from double inclusions" (III.5), decided by preprocessing a file that includes the header twice and one that includes it once: the same lines both ways is "safe to include twice", which is all the OK says, so a header with nothing a second inclusion could repeat (empty, comments alone, or only `#include`s of guarded headers) passes, guard or no guard; and the `s_`, `u_` or `e_` a struct, union or enum defined inside a `typedef` must start by (III.1). A `typedef` that only names one (`typedef struct timeval t_tv;`, or a struct defined elsewhere) defines nothing to read: libc's names are not the student's, and norminette reads a struct defined outside a `typedef` where it is defined. A required header that is missing is a gated NOT TURNED IN; an exercise that only allows headers and has none gets no test |
| `_norm_notice` | `norm` | strict | norminette's Notices, which no subject settles |
| `_norm_provided` | `norm` | complete | a file the grader brings, normed |
| `_norm_provided_notice` | `norm` | complete | its Notices |
| `_oracle_fixtures` | `oracle` | complete | the named cases' files are what `//oracle` writes (BSQ's maps and outputs, `bsq_fixtures`; Rush 00's case lists, expected tables, survival rows, ft_putchar's bytes and defense pictures, `rush00_fixtures`; Rush 02's dictionaries, argument files and expected outputs, `rush02_fixtures`), and every file its `--owns` patterns match is one the reference writes; runs nothing of yours |
| `_output` | `output` | basic | the output against the expected fixture |
| `_perf` | `perf` | complete | how cost grows with the number of cases, and with one input's length where asked |
| `_posix` | `norm` | strict | the constructs POSIX leaves undefined, in a script turn-in `/bin/sh` runs (Shell turn-ins) |
| `_probe_memcheck` | `valgrind` | strict | the adversarial probes under memcheck, no leak check |
| `_progname` | `output` | basic | C 06 ex00: `argv[0]`, under two names |
| `_program_allocfail` | `allocfail` | robust | a program's own `main` on one case, one `malloc` refused per run: it must end by itself, in time, with bounded output (the repo's rigour; no text or status judged). One target per case `c_program`'s `allocfail` lists: the first is `exNN_program_allocfail`, each other `exNN_<case>_program_allocfail` |
| `_program_allocfail_leaks` | `allocfail` | robust | the same sweep, judging what a run that ended by itself still held at exit (Rush 02's freeing rule) |
| `_prototype` | `prototype` | basic | the signature the subject fixes (return and parameter types), and the layout of the structure it prints where the grader links a function built on it |
| `_prototype_names` | `prototype` | strict | the parameter names, where the subject fixes them too (Rush 00: "named x and y"); read from the pinned clang's AST |
| `_readings` | `diff` | strict | this harness's reading of what a subject leaves open, over a corpus of the cases the readings part on, stated in the target's hints (BSQ: the count's form, a map with no final newline; Rush 01: the one argument's blanks and a sign or zero before a digit; C 02 ex09: a byte above `0x7f` in a word; C 04 ex04 and ex05 and C 07 ex04: a byte above `0x7f`, or a control byte, in a base -- each with its ASan twin `exNN_readings_diff_asan`, `c_diff`'s `readings`). One the subject's words do not reach is a convention, raised to robust and listed among the targets raised above their layer (C 11 ex06: the order of a byte above `0x7f`) |
| `_reference_cases` | `oracle` | complete | every named case of a program, run as its output test runs it with `//oracle`'s reference program in the student's place (`c_program`'s `reference`; BSQ, Rush 01, Rush 02); runs nothing of yours |
| `_refcost` | `cycles` | complete | instructions per unit of work, beside the reference's own |
| `_regular` | `output` | strict | "files" where a directory can carry a matching name: what the target tests is in its exercise's row under [Shell turn-ins](#shell-turn-ins) |
| `_rush02_dictfuzz` | `diff` | strict | Rush 02's corpus over generated dictionaries |
| `_survive` | `output` | basic | Rush 00: degenerate sizes, survival only; counter-ceiling sizes, survival and — once `rush(3, 3)` draws anything — the rectangle's shape (it was `_robust`, which is a level's name) |
| `_sweep` | `output` | basic | Rush 01: every 4x4 clue vector, each grid checked against the subject's rules alone, and the argument counts that are not one |
| `_symbols` | `symbols` | strict | exactly the symbols the subject names are exported |
| `_twin` | `selftest` | complete | Piscine Reloaded's twin shell exercises: their own `tests/exNN/` holds only the README pointing at the tests they read; runs nothing of yours |
| `_valgrind` | `valgrind` | strict | a program case under memcheck; or, for a corpus (`_file_valgrind`, `_sweep_valgrind`, `_rush02_valgrind`, `_rush02_dictfuzz_valgrind`, `_bsq_valgrind`, `_bsq_stdin_valgrind`, `_bsq_multi_valgrind`, `_readings_valgrind`), 25 of its cases spread evenly over it (a case of `_bsq_multi_valgrind` is a run of up to three maps; Rush 01's runs every probe its plain target asks for besides, from the one list both read: `ex00_sweep_valgrind` its three argc probes, 28 in all, and `ex00_readings_valgrind` its six shape probes alone), each judged as a case's own arm is |

A case named so that a longer suffix matches (a case `diff` makes
`ex00_diff_asan`, which reads as `diff_asan`) does not load: rename it.

## Targets raised above their layer

Placed higher by their BUILD file -- a test's `level`, a case's `"level"` --
than their name places them. The reasoning, in full, is at the call site. The
level suites and the gate follow the tags, so a raised target is not in the
suites below its level. Under a red, each one's log ends with its row's
"why", read from this table (`tools/runner_lib.sh`, `rl__raised`): write it
for the student who meets it there. Only a runner that sources the library
prints it, so `c_levels()`' audit refuses a raised test run by any other
(`tools/defs.bzl`'s `_LIB_RUNNERS`).

A C function's `readings` (`c_function`) land here: the C counterpart of a
shell exercise's `exNN_literal`, each is `exNN_<name>_output`, a `main` of its
own over the same files, at the level its case names (never `basic`), and the
row says which reading it takes.

| target | level | why |
|---|---|---|
| `//c-piscine/c-piscine-c-06:ex03_high_bytes_argv_diff` | robust | in every case of its corpus with an argument, a byte above `0x7f` decides the order, and "sorted in ASCII order" (page 10) does not reach one: the order the reference gives them is a convention this repo chose, not a reading of the sentence. `ex03_argv_diff`, at strict, replays the cases such a byte does not decide |
| `//c-piscine/c-piscine-c-07:ex04_base_to_space_output` | strict | whitespace in `base_to`, a case the subject leaves open between C 07's "no whitespaces" and C 04's list for writing a number, which names none: this target holds this harness's reading, and its hint says which |
| `//c-piscine/c-piscine-c-08:ex01_expr_output` | strict | EVEN applied to an expression, which the subject's own main never does |
| `//c-piscine/c-piscine-c-08:ex01_success_output` | robust | the value of SUCCESS, which the subject never gives: the Run contract holds it to the C convention for a program that did its job, at robust |
| `//c-piscine/c-piscine-c-08:ex02_long_arg_output` | strict | ABS on a `long` argument: "its argument" names no type, a case the subject leaves open |
| `//c-piscine/c-piscine-c-08:ex02_double_arg_output` | strict | ABS on a floating-point argument: the same open case |
| `//c-piscine/c-piscine-c-08:ex03_int_fields_output` | complete | whether t_point's fields are `int`, which the subject never names: a convention this repo chose |
| `//c-piscine/c-piscine-c-10:ex01_dash_output` | strict | a lone `-` among named files: "You don't need to handle options" lets it be read as an option to skip, and this harness's reading is standard input, as the system's cat reads it |
| `//c-piscine/c-piscine-c-10:ex01_dirmsg_output` | strict | cat's own message for a directory: this harness's reading of "performs the same function as the system's cat" is the tool's own wording, which no sentence fixes |
| `//c-piscine/c-piscine-c-10:ex01_errmsg_output` | strict | cat's own message for a name that will not open: this harness's reading of "performs the same function as the system's cat" is the tool's own wording |
| `//c-piscine/c-piscine-c-10:ex01_errstatus_output` | strict | cat's exit status after a name that will not open: this harness's reading of "performs the same function as the system's cat", applied to the status |
| `//c-piscine/c-piscine-c-10:ex02_attached_output` | strict | the count attached to the option, `-c20`: the subject names `-c`, not how its count is written, and this harness's reading of "the same function" takes both forms |
| `//c-piscine/c-piscine-c-10:ex02_dir_output` | strict | tail on a directory, the last of several names: its header and its exit status -- this harness's reading of "the same function as the system command tail", the tool's own behaviour |
| `//c-piscine/c-piscine-c-10:ex02_dirmsg_output` | strict | tail's own message for a directory among several names: this harness's reading of "the same function as the system command tail" is the tool's own wording |
| `//c-piscine/c-piscine-c-10:ex02_errmsg_output` | strict | tail's own message for a name that will not open: this harness's reading of "the same function as the system command tail" is the tool's own wording |
| `//c-piscine/c-piscine-c-10:ex02_errstatus_output` | strict | tail's exit status after a name that will not open: this harness's reading of "the same function as the system command tail", applied to the status |
| `//c-piscine/c-piscine-c-10:ex03_allfail_output` | strict | hexdump's closing message when not one name opens: this harness's reading of "performs the same function as the system's hexdump" is the tool's own wording |
| `//c-piscine/c-piscine-c-10:ex03_errmsg_output` | strict | hexdump's own message for a name that will not open: this harness's reading of "performs the same function as the system's hexdump" is the tool's own wording |
| `//c-piscine/c-piscine-c-10:ex03_errstatus_output` | strict | hexdump's exit status after a name that will not open: this harness's reading of "performs the same function as the system's hexdump", applied to the status |
| `//c-piscine/c-piscine-c-11:ex04_reverse_output` | strict | whether "sorted" holds in both directions, which the subject never says: this target holds this harness's reading, that an array in the reverse of f's order counts. The basic table and the diff corpus hold only arrays both readings agree on |
| `//c-piscine/c-piscine-c-11:ex05_intmin_div_output` | strict | INT_MIN / -1, whose quotient no int holds: the subject leaves the output open, so the case asks only that the program survive it |
| `//c-piscine/c-piscine-c-11:ex05_intmin_mod_output` | strict | INT_MIN % -1: the same |
| `//c-piscine/c-piscine-c-11:ex05_opsuffix_output` | strict | an operator argument such as `+x`: the subject's lenient treatment of values leaves open how the operator is read, and this harness's reading takes the argument whole |
| `//c-piscine/c-piscine-c-11:ex06_readings` | robust | every array of its corpus is one a byte above `0x7f` puts in its order, and "by ascii order" (page 13) does not reach one: the order the reference gives them is a convention this repo chose, as C 06 ex03's `ex03_high_bytes_argv_diff` is, the same question. Its hint says so. `ex06_diff`, at strict, holds the arrays such a byte does not decide |
| `//c-piscine/c-piscine-c-12:ex11_element_output` | strict | which pointer ft_list_find returns: "the address of the first element's data" against a `t_list *` return type is a reading, and this harness's reading is the prototype's (the element). The basic table accepts all three readings |
| `//c-piscine/c-piscine-rush-02:ex00_dict_crlf_strict_output` | strict | whether a CR before the newline is one of "the spaces" to trim or a byte that is not printable: the subject never says, and this target holds this harness's reading, that it is not printable (basic's `ex00_dict_crlf` accepts either) |
| `//c-piscine/c-piscine-rush-02:ex00_dict_missing_strict_output` | strict | a dictionary that does not exist: this harness's reading of "If the dictionary does not allow you to perform the conversion" covers one that cannot be opened, where the general rule also allows "simply return control" (basic's `ex00_dict_missing_output` asks only that the run end by itself) |
| `//c-piscine/c-piscine-rush-02:ex00_past_dictionary_strict_output` | strict | whether a number past the dictionary's largest scale is refused or spelt by combining scale words: the subject never says, and this harness's reading of "If the dictionary does not allow you to perform the conversion" covers it; basic's `ex00_past_dictionary` asks only that the program end by itself |
| `//c-piscine-reloaded/c-piscine-reloaded:ex22_long_arg_output` | strict | the same as C 08 ex02's, for its twin |
| `//c-piscine-reloaded/c-piscine-reloaded:ex22_double_arg_output` | strict | the same as C 08 ex02's, for its twin |
| `//c-piscine-reloaded/c-piscine-reloaded:ex23_int_fields_output` | complete | the same, for C 08 ex03's twin |
| `//c-piscine-reloaded/c-piscine-reloaded:ex26_returns_one_output` | strict | a predicate that returns 2 as well as 0 and 1: this harness's reading takes "the elements of the array that return 1" literally, where C 11 ex03 counts those that do not return 0. The basic table's predicate returns only 0 and 1, where the two agree |

## Sentences about how

What a subject says about HOW an exercise is built, which nothing the
program prints can show, and what reads each one. A sentence no layer can
read is listed too, never dropped.

| the subject says | exercises | read by |
|---|---|---|
| "Create a recursive function", "must be implemented recursively", "Recursion is required to solve this problem" | C 05 ex01, ex03, ex04, ex08; Piscine Reloaded ex13 | `exNN_method`, strict: some function of the file is entered again while it is still running |
| "Create an iterative function" ("an iterated function") | C 05 ex00, ex02; Piscine Reloaded ex12 | `exNN_method`, strict: no function of the file ever is |
| "declaring a fixed-size array" | C 10 ex00, ex01; Piscine Reloaded ex27 | `exNN_fixed_array`, strict: no array of variable length, no `alloca`. Whether the program declares an array at all is not read |
| "This array should have a size limited to slightly less than 30 ko" | C 10 ex01 | `ex01_fixed_array`, strict: every object smaller than 30720 bytes (30 x 1024, since `ulimit`, which the subject names to test it, counts KiB); an upper bound only |
| "You should use an array of pointers to function to take care of the operator" | C 11 ex05 | no layer: no output, and no call a program makes, shows that an array chose it. The exercise's hints restate the sentence, and an evaluator reads the code |

## Manual targets

A manual target is in no suite but its module's `:manual`, and no `/...`
pattern reaches it, so it runs only when named. `bazel test //<module>:manual`
runs them all; `bazel query 'tests(//<module>:manual)'` lists them, and prints
nothing for a module with none. Every one in the repo, which is this table:
`bazel query 'attr(tags, "\bmanual\b", tests(//...)) except //tools/...'`
(without the `except`, the harness's own toy fixtures under
`//tools/tests/macro_fixtures` are listed too). A manual `cc_binary` or
`cc_library` a layer builds is not a test, and is not listed. A pattern here
that matches nothing is not an error: which Rush 00 variants are manual
depends on the team's `team.bzl`.

| targets | why they do not run by default |
|---|---|
| `//c-piscine/c-piscine-rush-00:ex00_rush0*` | a variant the team does not owe: a bonus, and no gate may block on one |
| `//c-piscine/c-piscine-rush-01:ex00_bonus_9x9` | the 9x9 bonus, required: for the team that did it |
| `//c-piscine/c-piscine-rush-02:ex00_rush02_diff` | the subject fixes four outputs and no composition rule, so a disagreement with the reference is evidence to read, not a verdict; what no reading explains (Error for a valid number, Dict Error from a dictionary that can spell it, words not the dictionary's, the shapes the named cases hold at basic spelled another way) gates at strict in `ex00_settled_words_diff` |
| `//c-piscine/c-piscine-rush-02:ex00_rush02_dictfuzz` | the same, over generated dictionaries (`ex00_settled_dicts_diff` gates) |

## Which layers wait for which

A layer that cannot say anything useful yet prints `SKIP —` and exits 0, so the
suite stays green on a machine that cannot host it. **`--test_env=NO_SKIP=1`
forces every one of them open** and turns a missing tool into a failure.

| layer | stays quiet until | why |
|---|---|---|
| `diff`, `diff_asan` | the exercise's `output` fixture passes | fuzzing a wrong answer reports the same wrongness thousands of times |
| `valgrind` | same | ditto, and a stub leaks nothing |
| `output`: Rush 01's `ex00_sweep` | the subject's own example passes (`ex00_subject_output`) | the one case the subject printed says it first; 438 restatements of it do not |
| `cycles` | same | the cost of a wrong answer is not information |
| `method`'s `exNN_method` | the exercise's own `output` fixture passes (`exNN_output`'s expected output, from its test program) | a stub calls nothing twice, and a wrong answer has no method worth reading yet |
| `method`'s `exNN_fixed_array` | the pinned gcc compiles every turned-in source | a file that does not compile has no array to measure; the compile layers say why, in the compiler's words |
| `perf` | `output`, `diff` **and** `asan` pass | measuring how a broken thing scales says nothing |
| `ilp32` | the 64-bit build passes: the program `output` runs passes its fixture | otherwise it reports the same failure twice, in an unfamiliar place; and code that does not build there (a warning under `-Werror`) is no 64-bit build that passes |
| `exNN_build_exit` | `make` (or the creator script) builds the artifact | a build that made nothing did no job whose exit status means anything; `exNN_build` says why |
| a shell script turn-in's `exNN_posix`, and its half of `exNN_lint` | the generator parses and runs to its end, and writes a script `/bin/sh` can parse | there is no script to lint, or shellcheck would only repeat the parse error; `exNN_norm` or `exNN_output` says why (the generator's own lint in `exNN_lint` runs whenever the generator parses) |
| `exNN_build_rules` | the build makes the artifact | what a rule does to a tree that was never built says nothing about the rule |
| `exNN_build_recipe`, `exNN_build_wildcards` | `make -n` plans, or a build of a copy of the tree runs, a command that compiles a `.c` (the creator script runs one) | no compile command to judge, and nowhere to put a decoy source |
| Shell 01 ex04 and Reloaded ex04 (`MAC.sh`), `output` and `literal`, past "is there and parses" | the machine has `ifconfig` and publishes a hardware address besides loopback (`oracle shell01_hwaddr --machine`) | in a container a correct `MAC.sh` has nothing to print, and a red there would not be about your script |
| any layer | its tool is available | a missing valgrind is a gap, not a pass — `NO_SKIP=1` says so |

A test that waits says SKIP in its log, and Bazel shows it PASSED: a test
that ran cannot report itself skipped. So the red log of the `output` test it
waits for names it, under `WAITING FOR THIS OUTPUT`, with its level. Which
`output` test that is, is read from the gate: the program and expected file
it gates on (`--gate-bin`, `--gate-expected`), or a survive case's
`--gate-label`; where two `output` tests run that same pair (cases sharing an
expected file), the call says which with `waits = "<that test>"`
(`hand_test`, `corpus_memory`). `c_levels()`' audit refuses a gate that
resolves to no `output` test or to two, or to the `output` test of another
exercise, whose red log you would not be reading, and one that hands the
program none of the input that test's run does.

Two layers report one cause, on purpose, where each says something the other
cannot: a copy of a file the grader brings, kept in a Makefile turn-in (C 09
ex01's `srcs/`, Reloaded ex24's), fails `exNN_files` — it is pushed, under
FILES THE GRADER BRINGS — and `exNN_build` — the grader fetches the Makefile
alone, so a build that found the copy is not the build the grader runs.
Neither waits for the other: deleting the copy turns both green.

## Shell turn-ins

Where the [run contract](#run-contract) lands in the shell modules. How it is
checked is in [testing.md](testing.md#shell-modules-work-differently).

A turned-in script is run as `/bin/sh name`, never through its `#!` line: all
three shell subjects say in their general rules that shell exercises must be
executable with /bin/sh. For the same sentence, a script `/bin/sh` cannot
parse (`sh -n`) fails `output` at basic, with the shell's own message. A
check script does both through `ck_run` and `ck_sh_parses`; an exercise in
`diff` mode with `run = True` (none has one yet) runs through the same
`ck_run`. `interp` names another shell, for a subject that names one, and
drops the parse check. The run's stdin is `/dev/null`: no shell subject gives
a turn-in input on stdin, and a check that runs it once per line of a list
must not hand it the rest of that list. A run's exit status and stderr are
printed where the run happens, before the checks that judge it, when either
says something, and graded by no shell target: none of these subjects names
a status or asks anything of stderr, and no shell runner has the `robust`
exit-status target yet (the table above lists the runners that do). A `diff`-mode run killed by
a signal fails whatever it printed; how it ended is read from
`tools/exit_status`, so `exit 255` is a return, not a death.

The execute bit, by what each subject's example does with the file:

| exercise | the subject's example runs it | execute bit |
|---|---|---|
| Shell 01 ex01, ex02, ex03, ex06, ex07; Reloaded ex03 | `./name` | required (`output`, basic) |
| Shell 00 ex05, ex06 | `bash name` | not checked |
| Shell 00 ex04, ex08; Shell 01 ex04, ex08; Reloaded ex02, ex04 | not shown | not checked |

The sentences with two readings in a shell turn-in: `exNN_output` grades what
both require, and one reading runs as a target of its own, at `strict` (a
`shell_exercise`'s `readings`: a check script each), `exNN_literal`,
`exNN_regular` or `exNN_newest_first`; each exercise's row of the table
below names the sentence and states the reading its target tests, as this
harness's. A C function's reading is `exNN_<name>_output` (a
`c_function`'s `readings`: a harness and a fixture each), listed with the
[raised targets](#targets-raised-above-their-layer): C 07 ex04, C 11 ex04,
C 12 ex11 and Reloaded ex26 have one.

| exercise | `exNN_output` (basic) | at `strict` |
|---|---|---|
| Shell 00 ex02, Reloaded ex00 | the tree the archive extracts to: members named `./test0`…, a `./` entry, or a hard link recorded from either of its two names all pass | `exNN_literal`, this harness's reading: the archive exactly as the subject's `tar -cf … *` writes it: bare names in the order `*` expands them, the link recorded the way that command records it |
| Shell 00 ex04 | "sorted by modification date": the modification date alone decides the order, newest first or oldest first, since the subject names no direction | `exNN_newest_first`, this harness's reading: newest first, the direction `ls` sorts by time in |
| Shell 00 ex06 | a directory ignored as a whole listed file by file, or as the one line `dir/`: git itself prints either; the lines in any order, since the subject names none | `exNN_literal`, this harness's reading: each ignored file by its path, and never the directory in their place; the lines in the order git prints them, byte by byte |
| Shell 00 ex08, Reloaded ex02 | one command, as the shell reads the file: no `;`, `&&` or `\|\|` joining two, and no second command line; a quoted or escaped `;` is an argument, not an operator. The backups are files, and names that only look like one (`#draft`, `notes#`, `notes~old`, `~draft`) are kept and not shown | `exNN_literal`, this harness's reading: no `;` or `&&` anywhere in the file, and one command: nothing joins it to another (`;`, `&&`, `\|\|`, a pipe, `&`) and there is no second command line. `exNN_regular`, this harness's reading: "all files" as regular files only: a directory named like a backup, empty or not, is neither shown nor deleted, and nor is what it holds |
| Shell 01 ex02, Reloaded ex03 | "all files ending with .sh" (Reloaded: "all file names"): a `.sh` file inside a directory whose own name ends in `.sh` is listed; the directory's name may be listed or not | `exNN_regular`, this harness's reading: the directory's name is not listed |
| Shell 01 ex04, Reloaded ex04 | "your machine's MAC addresses": every line an address of one of this machine's interfaces, at least one of them a hardware interface's; the loopback's all-zero one allowed beside them or left out, never alone | `exNN_literal`, this harness's reading: the hardware interfaces' addresses only: the loopback's all-zero line fails |
| Shell 01 ex07 | "reverse alphabetical order": reverse order by bytes (the C locale) or by the test locale's collation (`en_US.UTF-8`), each window held to the order the whole list followed | `exNN_literal`, this harness's reading: reverse order by the test locale's collation, as a dictionary orders words |

The lint of a turn-in that is a script, split by whose rule each finding is.
`script` on the exercise's `shell_exercise` call says which turn-ins are
scripts and how the subject has each run: `"sh"` where no example runs it
(the general rule: shell exercises must be executable with `/bin/sh`),
`"./name"` where the example runs it so (run that way, its own `#!` line
picks the shell, `/bin/sh` where it names none or names sh), `"bash"` where
the example runs `bash name` (Shell 00 ex05, ex06). Which shell `script` and
the `#!` line name decides only which target below reports a construct POSIX
leaves undefined: every target that runs the script runs it as `/bin/sh
name`, as above, whatever its `#!` line says. `//tools:conventions` holds
it together with the check's `ck_sh_parses`, and `"./name"` with its
`ck_executable`. The generator's own lint is in `exNN_lint` for every
exercise, since generators are this repo's way of turning a shell exercise
in, not a subject's.

| level | target | what fails it |
|---|---|---|
| basic | `exNN_output` | a script `/bin/sh` cannot parse (`sh -n`, the check's `ck_sh_parses`); `exNN_norm` asks the same of the generator |
| strict | `exNN_posix` | a construct POSIX leaves undefined (shellcheck's SC3xxx), in a script `/bin/sh` runs: whether the grader's sh accepts one is not certain. Not emitted for a `"bash"` script, and green, saying why, on a `"./name"` script whose `#!` line names another shell, which runs it when it is typed as `./name` (`exNN_output` still runs it with `/bin/sh`) |
| robust | `exNN_lint` | any other shellcheck warning or error, in the script and in the generator; and SC3xxx too in a script the subject runs with `bash name`, or a `"./name"` script whose `#!` line names bash or another shell |

A generator runs again on every `:generate` and every `//tools:submit`.
Where the subject fixes a turn-in byte for byte, the exercise's call says
`stable = True`, and `exNN_output` runs the generator twice, in two empty
directories, the second time under an empty `HOME` and `TMPDIR` of its own,
and fails when the two runs write different bytes (`ck_stable`). No exercise
does today: every `check`-mode call says `stable = False`, Shell 00 ex03's
included, whose generator makes a fresh key on every run because making the
key is the exercise. A generator is this repo's way of turning an exercise
in, not the subject's, so its stability is graded only where the subject
fixes the file. A `check`-mode call that says neither does not load, so the next
exercise's author decides it rather than inheriting a default.

Piscine Reloaded's ex00–ex05 repeat Shell 00 and Shell 01 exercises, and run
their tests: `twin_of` on each `shell_exercise` call names the exercise, and
the twin's own `tests/exNN/` holds only a README naming that folder. A file
put beside the README is read by nothing, and `exNN_twin` fails naming it;
it is a guard on the harness's own files, so it sits at `complete`. Where
the two subjects word a sentence the shared check quotes differently --
Shell 01 ex02's "all files ending with .sh", Reloaded ex03's "all file names
that end with ".sh"" -- each call gives its own subject's words (`wording`),
and the check quotes the one its target's subject says (`ck_wording`); the
reading it applies is the same for both.

Its C exercises that repeat the Piscine's word for word (ex09-ex11 are C 01
ex00, ex02 and ex03, ex12-ex14 C 05 ex00, ex01 and ex05, ex16 C 01 ex06,
ex17 C 03 ex00, ex18 and ex19 C 06 ex01 and ex03, ex20 and ex21 C 07 ex00
and ex01, ex22 and ex23 C 08 ex02 and ex03, ex25 C 11 ex00, ex27 C 10 ex00)
keep a `tests/exNN/` of their own, since a C macro names every file from its own folder, and say
so beside their calls: `c_twin(num = "27", of =
"//c-piscine/c-piscine-c-10:ex00")`. `//tools:conventions` holds each
declared pair's folders identical, file for file and byte for byte, and two
`c_program` calls' `cases` identical but for the exercise's number, however
each call is laid out (a call written with its number in a variable cannot
be matched, and is reported); and it
reports a `tests/` folder that is all a copy of another module's with no
`c_twin` line.

## Flags

```sh
bazel test //...                          # everything: needs memory to spare
bazel test //c-piscine/c-piscine-c-00/...           # one module
bazel test //c-piscine/c-piscine-c-01:ex02_output   # a single target

bazel test //c-piscine/c-piscine-c-00/... --nocache_test_results   # re-run even a cached PASS
# a file saved during a run, and the program still runs the old one:
bazel shutdown && bazel test //c-piscine/c-piscine-c-00/... --nocache_test_results --use_action_cache=false
bazel test //c-piscine/c-piscine-c-00/... --test_output=errors     # print the log of failing tests
bazel test //c-piscine/c-piscine-c-00/... --nokeep_going           # stop at the first (harness) build error
bazel test //... --test_tag_filters=norm  # one layer, whole repo: needs memory to spare

# "show me everything that is wrong right now"
bazel test //... --nocache_test_results --test_output=errors   # needs memory to spare
```

Code that does not compile or link, or a missing turn-in file, never fails the
build: the tests that need it FAIL with the compiler's words or NOT TURNED IN,
and every other target still runs ([testing.md](testing.md#code-that-does-not-build-fails-its-own-tests-not-the-build)).
`--keep_going` (`-k`) is already on as well (`.bazelrc` sets it), for a build
error in the harness itself.

`--test_tag_filters` also filters targets you name explicitly, which is why the
per-module `:basic` / `:strict` / `:robust` / `:complete` suites exist — ask for
a suite, not a filter.

## Environment variables

Bazel does **not** pass your shell environment into a test, so these reach a
runner only via `--test_env=NAME=VALUE`. Every default is what the runner uses
when unset; none of them need setting for an ordinary run.

A per-run limit (the `*_TIMEOUT` rows) bounds the run's **own** time: wall time
less what it waited on the run queue for a CPU, which a busy machine adds and
the limit gives back, never past what is left of the test's own limit
(`tools/runqueue.h`; finding 066). A correct program is not stopped for the
queue it stood in. A program that sleeps or blocks is stopped on the wall
clock, busy machine or not. One that loops is runnable, so it queues like a
correct one and is stopped after its limit of its own CPU time, which on a
loaded machine takes up to the load times that limit in wall time: a test whose
cases all loop can then reach its own limit before the last case reaches its
per-run one, and each run it stops says how much time it gave back.

A test's own limit is its size's (`small` 60s, `medium` 300s, `large` 900s),
and a runner keeps a margin of it back to report in (`RL_MARGIN`). A test's size
gives it at least three times what it takes in a full suite run, measured on
correct answers, the slow ones included: a limit is a guard against a run that
never ends, never a speed requirement, and a second suite on the same machine
doubles every time. `bazel test //... --test_summary=short` prints each
target's time; one that takes a third of its limit or more is resized.

| variable | default | does |
|---|---|---|
| `NO_SKIP` | `0` | `1` forces every gate open; a missing tool becomes a failure |
| `CLUE_MODE` | first 3 hints | `all`, or a number (`0` is all): how many `HINTS` lines a failing layer prints, in every layer that prints hints. A value it cannot read shows 3, and the `HINTS` block says so |
| `DIFF_TIMEOUT` | `30` | seconds one program run gets under the output layer (`diff_output.sh`) |
| `ARGV_TIMEOUT` | `5` | the same, per scenario, for argv-table exercises, and per case for their argv differential |
| `FILE_TIMEOUT` | `10` | seconds one case gets under the C 10 file differential |
| `RUSH02_TIMEOUT` | `10` | seconds one number gets under the rush-02 differential |
| `SHELL_TIMEOUT` | `20` | seconds a shell exercise's generator, or its turn-in, gets per run |
| `MAKE_TIMEOUT` | unset | seconds one run of a `c_make` exercise's `make`, or of its creator script, gets (`make_test.sh`); unset, what is left of the test's own limit |
| `RL_MARGIN` | a tenth of the test's limit, 4–20 | seconds a runner keeps back from `TEST_TIMEOUT` to write its report |
| `RL_MAX_HANGS` | `3` | how many runs of a sweep may run out of their own time limit before it stops trying the rest |
| `RL_EXCERPT_WIDTH` | `300` | bytes of one line an excerpt of captured output shows before it cuts the line, and says so |
| `VALGRIND_TIMEOUT` | `60` | seconds a valgrind run gets |
| `VALGRIND_LOG_CAP` | 8 MiB | `ulimit -f` cap on what a valgrind run may write |
| `VALGRIND_FDS` | unset | `lax` turns a descriptor the program left open from a `valgrind` failure into a note |
| `MIN_DIFF_CASES` | `16` | fewer cases than this fails, rather than reporting a green "0 cases" |
| `PERF_TIMEOUT` | `25` | seconds one `perf` measurement gets; a size that runs out of it is halved and measured again, never a failure |
| `PERF_MIN_CASES` | `125` | the fewest cases `perf` halves its smallest size to before it reports the exercise too slow to measure |
| `PERF_MIN_BASELINE_MS` | `20` | below this, `perf` prints no ratio rather than dividing by noise |
| `MEM_NOISE_KIB` | `512` | RSS growth below this band is reported as flat |
| `CYCLES_OPT` | `-O2` | what `cycles` builds at; Bazel's `fastbuild` is `-O0` |
| `CYCLES_TIMEOUT` | unset | seconds the callgrind run of `cycles` gets; unset, what is left of the test's own limit |
| `HEADER_CC` | `cc` | compiler for the header-driven `output` tests, run by hand: a test is handed the pinned clang-12 (`--cc`), which wins |
| `PROTOTYPE_CC` | `cc` | compiler for the `prototype` layer, run by hand (`--cc` wins, as above) |
| `ILP32_CC` | unset | a 32-bit compiler to try first, when the pinned zig is unavailable |
| `ZIG_CACHE_HOME` | `$TMPDIR/zig-cache-42` | shared on purpose; per-test isolation costs ~15s each |
| `ASAN_OPTIONS`, `UBSAN_OPTIONS` | unset | appended after the harness's own, so your key wins |
| `ALLOCFAIL_TIMEOUT` | `10` | seconds one allocation-failure run gets |
| `ALLOCFAIL_MAX` | `64` | how many allocations one sweep refuses, one per run: all of them up to that many, and past it that many, the first ones and then spread evenly to the last (a function's `_allocfail` and a program's `_program_allocfail` alike) |
| `ALLOCFAIL_LOG_CAP` | 1 MiB | `ulimit -f` cap on what an allocation-failure run may write |
| `ALLOCFAIL_SHIM` | built in | an alternative failing-malloc shim to preload |
| `MIN_ARGV_CASES` | `12` | floor for the argv differential corpus, as `MIN_DIFF_CASES` is for the streamed one |
| `MIN_FILE_CASES` | `20` | the same floor for the file differential corpus |
| `DIFF_MAX_ROWS` | `40` | how many rows an `output` table shows (the case that was running first, then failing rows, then passing ones), and how many failing cases every differential report prints (`argv_check`, `file_check`, `bsq_check`, `rush01_check`, `rush02_check`) before it tallies the rest; `0` shows all. Whatever is left out is kept whole in the test's `test.outputs/` |
| `DIFF_CELL_MAX` | `100` | how many bytes of a long failing row an `output` table shows, around its first difference |
| `PERF_REPEATS` | `3` | how many times `perf` measures a size before taking the best; a sample of two CPU-seconds or more is not measured again |
| `PROGNAME_TIMEOUT` | `10` | seconds the argv[0] check gets per run |
| `BSQ_TIMEOUT` | `10` | seconds one bsq map gets |
| `RUSH01_TIMEOUT` | `10` | seconds one rush-01 clue vector gets |
| `RUSH01_MAX_TIMEOUTS` | `3` | how many timeouts the sweep tolerates before calling it a hang; bonus-size ones count apart, and after this many the other bonus sizes are not tried |
| `FORBIDDEN_CC` | `cc` | compiler for the forbidden-symbol layer's link probe, run by hand (`--cc` wins, as above) |
| `SYMBOLS_CC` | `cc` | compiler for the `symbols` layer, run by hand (`--cc` wins, as above) |
| `SUBMIT_GATE` | `basic` | which level `//tools:submit` must be green at before it pushes |
| `NO_C_PISCINE_PRIME` | unset | set to anything to stop `prime.sh --background` firing from a shell profile |

`bazel run` targets **do** inherit your shell environment, so a plain `export`
is enough for these:

| variable | default | does |
|---|---|---|
| `SUBMIT_GATE` | `.submit-level`, else `basic` | which level the pre-push gate demands |
| `C_PISCINE_SCRATCH` | chosen by `tools/drives.sh` | where Bazel's state goes, for `setup.sh` and for the `tools/bazel` wrapper |
| `C_PISCINE_CAMPUS` | detected (`/goinfre`, `/sgoinfre`) | `1` or `0` overrides whether this is a campus box, for `env_drift`, `init` and the wrapper |
| `C_PISCINE_TRACE_EVERY` | `5` | seconds between two samples of a prime's trace (`tools/prime_trace.sh`) |
| `NO_C_PISCINE_PRIME` | unset | set to stop the background first-build warm-up |
| `LOGIN42`, `EMAIL42` | `.vscode/settings.json` | the identity `submit` and `gen_header` use |
| `HEADER_ART` | `tools/header_art.txt` | the ASCII art `gen_header` draws |

## Run targets

[bazel.md](bazel.md) takes apart the command `42` runs for each, with the words
it is made of.

| command | with `42` | does |
|---|---|---|
| `bazel run //tools:init` | `42 init` | record your 42 login and email |
| `bazel run //tools:prime` | — | download and build everything once, on demand |
| `bazel run //tools:gen_header` | `42 header FILE` | print a 42 header: `/* */` for `.c`/`.h`, `#` for a `Makefile`, `*.mk` or `*.sh` |
| `bazel run //tools:reset_headers` | `42 header --reset --all`; `42 header --reset` in a module re-stamps that one | re-stamp existing headers after an identity change |
| `bazel run //tools:submit` | `42 submit --all`; `42 submit` in a module pushes that one | test, then push each green module to the Vogsphere URL in `.submit-remotes`; `-n` lists what it would push |
| `bazel run //<module>:generate` | `42 generate`, in the module | rebuild one module's generated deliverables, e.g. `//c-piscine/c-piscine-shell-00:generate` |
| `bazel run //tools:generate` | `42 generate`, at the root | rebuild every generated exercise: Shell 00, Shell 01 and Piscine Reloaded ex00–ex05 |
| `bazel run //tools:norminette -- PATH…` | `42 norm PATH…` | norminette on the files named; `42 norm` alone is the `norm` layer's verdict |
| `bazel run //tools:conventions` | `42 conventions` | the house-style gate over the repo |
| `bazel run //tools:env_drift` | `42 doctor --drift` | compare this machine against `tools/pins.tsv` |
| `bazel run //tools:stub_check` | `42 stubcheck` | prove no deliverable holds an answer |
| `… \| sh tools/first_red.sh` | `42 test` | what does not build, one next objective, and a module-sized summary |
| `… \| sh tools/first_red.sh --all` | `42 test --all` | ... and one line per exercise |

`42` alone lists its commands, from `tools/fortytwo/commands.tsv`. Four have no
one target to name: `42 watch`, `42 clues`, `42 doctor` and `42 stop`
([testing.md](testing.md#the-42-command)). `//tools:prime` is not a `42`
command: on a campus machine it froze the session.

## Layout

One folder per **course**, one folder per **project** inside it, each named
exactly as 42 names it. A project is one `BUILD.bazel`, one Vogsphere
repository, and its `deliverable/` is that repository's root. Where an
exercise's files go inside it is the subject's to say: its "Turn-in directory"
line (`ex00/`) puts them under `deliverable/`, and a subject with no such line
(BSQ's, every Common Core one) turns in at `deliverable/` itself.

```
c-piscine/                 <- the C Piscine
  c-piscine-c-NN/
    deliverable/exNN/      <- your solution stubs (this is what gets submitted)
    tests/exNN/            <- harness + expected output (never submitted)
    tests/exNN/grader/     <- the files a subject says the GRADER brings, staged
                              beside your Makefile by exNN_build (C 09 ex01,
                              Reloaded ex24). Placeholders: never copy them into
                              deliverable/
    tests/<file>           <- a file the grader brings to several exercises (C 08's
                              ft_stock_str.h, Reloaded's ft_putchar.c). To compile
                              by hand against one, add -I <project>/tests; never
                              copy it into deliverable/
    tests/layout/<header>  <- the structure a subject prints for a header you
                              turn in (C 12's t_list, C 13's t_btree), which the
                              prototype layer checks yours against; tag/<header>
                              holds its names (the tag, the pointer fields'
                              types). Not yours to edit, and not files to turn
                              in. Read for a c_function exercise whose `files`
                              name the header; c_levels() refuses a package with
                              one no test reads
    BUILD.bazel            <- its subject contract first, then test targets built
                              from the macros in //tools
  c-piscine-rush-NN/       <- the three weekend rushes, group projects; see
                              docs/rushes.md. rush-00's team.bzl names the
                              variant a team owes
  c-piscine-bsq/           <- the final project, a group project too
    README.md              <- its page: how its tests are built, its corpora,
                              its settings, what its subject leaves open
    deliverable/           <- its subject has no turn-in directory line, so it
                              turns in at deliverable/ itself: a Makefile, and
                              every .c and .h wherever the Makefile says
                              (srcs/ and includes/ work)
    tests/ex00/
  c-piscine-shell-NN/
    generators/exNN.sh     <- your commands (the answer); produce the deliverable
    deliverable/           <- generated, gitignored
  c-piscine-exam-prep/     <- the study guide: the concepts the projects ask
                              for and the local tools; not a project
c-piscine-reloaded/        <- Piscine Reloaded: a course with ONE project, still
  c-piscine-reloaded/         given its own folder so every course has one shape.
                              Mixes generators/ (shell, ex00-ex05) and
                              deliverable/exNN (C and Makefiles); see its README
cursus/                    <- the Common Core; laid out when its first project starts
tools/                     <- the Bazel macros (defs.bzl), the test runners, and
                              every `bazel run` target above. pins.tsv states the
                              expected tool versions; deb.bzl fetches campus's
                              exact builds
oracle/                    <- the Rust references the layers check your output
                              against. They solve most exercises, some in loops
                              that port to C almost line for line: read
                              oracle/README.md before opening one
docs/                      <- this documentation
AGENTS.md                  <- rules for AI agents: didactic only, no exercise answers
```

A whole course at one level: `bazel test //c-piscine/... --test_tag_filters=lvl_basic`
(the `/...` already leaves the manual targets out).

### The subject contract

Every project's `BUILD.bazel` opens with one `subject()` call: the header box
of each exercise, transcribed from the subject, which every macro reads
(`tools/subject.bzl`). No call site passes a function the student may call or
a file the grader brings, and `//tools:conventions` refuses a project whose
first macro call is not `subject()`. The one turn-in file a call site may
name -- a function a module archives with its own script, as C 09 ex00's
`ft_strcmp.c` -- it names with `turnin_file("00", "ft_strcmp.c")`, which
builds the path from the contract and fails while loading unless the
contract lets that exercise hold the file;
`//tools:conventions` refuses a `"deliverable/..."` spelled anywhere in a
project's `BUILD.bazel`.

| field | from the subject | what reads it |
|---|---|---|
| `grader` | who grades: `moulinette`, `defense` (peers at an evaluation) or `both` | every runner's words about where a failure costs, as `RL_GRADER` (`tools/runner_lib.sh`'s `rl_at`: "an outright KO at the defense"); the files layer's advice about an extra file |
| `group` | a group project | recorded for the team rules ([rushes.md](rushes.md#working-as-a-team)) |
| `strict` | whether it forbids files it did not ask for ("You cannot leave any additional file", "submit only the files requested"); every Piscine project does | the files layer: an extra file fails, or warns. A folder of no exercise, a file outside every exercise folder, and a file named as a program the exercise builds (c_program's `name`, c_make's `artifact`), fail either way |
| `exercise(page = ...)` | the page the header box is printed on | a reader checking the entry |
| `dir` | the "Turn-in directory" line, verbatim (`"ex00/"`); `None` where there is none | every path every layer builds: `deliverable/ex00`, or `deliverable` |
| `files` | the "Files to turn in" line: the names it gives, `[]` where it names none, `None` where the name itself is the exercise | the files layer's required set; a header named here is staged first. A `c_make`, and a `c_program(makefile = True)`, build only from a Makefile (or creator script) named here, and refuse one the contract leaves out or only allows (finding 124) |
| `optional` | what the subject allows without naming it, as names or patterns (`"*.c"`); a pattern with `/` or `**` lets files sit in subfolders. Beside a Makefile, `"*.c"` and `"*.h"` are refused while loading: the Makefile says where its sources lie, so "Makefile, \*.h, \*.c" is transcribed `"**/*.c"`, `"**/*.h"` | the files layer; the sources and headers every build globs |
| `provided` | the files the grader brings, as `{harness copy under tests/: where the grader puts it}` | linked (a `.c`) or staged and on the include path (a `.h`), never judged as the student's; laid beside a Makefile turned in alone; reported when a copy turns up in the turn-in, in a subfolder too (the files layer walks the tree where a destination has one) |
| `linked` | the functions the grader compiles in from its own code ("From exercise 01 onward, we'll use our ft_create_elem"), as `{function: grader_library() label}` -- a Rust crate under `oracle/grader/` (`tools/grader_lib.bzl`), never C under `tests/`, which would be an answer outside the zone | linked into every program the exercise builds, in place of the exercise that writes the function; its i686 archive into the `ilp32` layer's; the `forbidden` and `symbols` layers report a student's own definition of it. The contract's analysis (`bazel test //...`, or `bazel build //<project>:subject`) refuses a label that is no `grader_library()`, or whose `exports` lack the function; a macro that cannot link the library into what it builds fails while loading, naming itself (only `c_function`, `c_diff`, `c_perf`, `c_cycles` and `c_mem_check` can) |
| `allowed`, `variables` | the "Allowed functions" line, `[]` for "None", `None` where there is none; variables it allows in a sentence of its own (`errno`) | the forbidden layer; whether a program's runs, and a corpus, get a leak check (malloc named, or no line); a `c_function` whose line names malloc or free is refused `malloc = False` (its `malloc` stays the call's, for a function that allocates through a helper the subject allows) |

`c_levels()` emits the files layer for every exercise from it, and fails when
`tests/` holds an exercise the contract does not list. Every check the
contract makes is proven on every run: `//tools/tests:macro_fixtures_test`
feeds each one the broken contract it guards against and compares its message
(`contract_problems.expected` in `tools/tests/macro_fixtures`).

**A new project's harness, from its subject.** What each sentence of a
subject becomes, so that the next project does not learn it from the last
one's answers (the whole checklist, in the order a new project meets it, each
item naming the check that holds it, is [new-project.md](new-project.md)):

- *"We will compile your code with our `x.c`"*, *"we will use our own
  `x.h`"*: `provided`, the harness's copy under `tests/`. A header holds what
  the subject prints and nothing more. A source is a stub that compiles: a
  body that does the work is the answer of the exercise that turns that
  function in, outside the zone, and `//tools:conventions` refuses a
  definition with a body, outside `deliverable/` and `generators/`, of any
  function a contract's `files` turns in. `TURNIN_FN_ALLOW` there names the
  one exception, Reloaded's `ft_putchar.c` (written with stdio, with its
  reason), which AGENTS.md section 4 names too; it is not a pattern to
  repeat, and another is the owner's to allow.
- *"We'll use our `x`"*, a function: `linked`, a `grader_library()` crate
  (`tools/grader_lib.bzl`). Never C, and never another exercise's files of
  the student's: no macro links one exercise's files into another's.
- *A structure the subject prints* for a header the student turns in:
  `tests/layout/<header>` (each field's type or size, its offset, the
  structure's size) and `tests/layout/tag/<header>` (the tag, and the type
  of each field pointing to another node). `c_function` reads both; the
  layout is in `exNN_prototype` where `linked` brings a function built on the
  structure, and in the `exNN_layout_prototype` twin otherwise; the names
  are always in the twin.
- *A sentence about how the work is done*, which nothing the program prints
  can show: a row in [Sentences about how](#sentences-about-how), always,
  and a call-site argument where a layer can read it -- unlike the header
  rules, nothing emits it from the contract. *"Create a recursive
  function"*, *"Create an iterative function"*: `c_function(method =
  "recursive" | "iterative", method_rule = <the sentence, quoted with its
  page>)`, which emits `exNN_method`. *"declaring a fixed-size array"*, and
  any bound the subject puts on it: `c_program(fixed_array = <the
  sentence, quoted with its page, and how the subject's unit was read>,
  fixed_array_bytes = <the bound in bytes>)`, which emits
  `exNN_fixed_array`. A sentence no
  layer can read (do-op's *array of pointers to function*) is its row, with
  "no layer" and why, and a clue that restates it.
- *The harness* (`tests/exNN/`): an out-parameter starts at a value it must
  not end at, so a function that never writes it is a red rather than a
  lucky match. A fixture's rows are fixed, so there it starts at a value no
  row expects (C 01 ex03's `test_div_mod.c`). A corpus can expect any value
  of the type, so a differential harness runs each case twice, from two
  starting values, and reads a result as `untouched` only when it kept its
  start both times (C 01 ex03's `diff_div_mod.c`, `PRESET_A` and
  `PRESET_B`; `//tools:conventions` holds a `diff_*.c` that prints
  `untouched` to two); a pointer out-parameter starts at the address of a
  local of the harness's, which no function can return (C 07 ex02); a
  callback the function is handed (a comparator,
  an `f`, a `free_fct`) records each call it gets and the fixture prints
  them, so "never called" or "called with the wrong argument" is a row of
  its own; a predicate the function is handed returns values other than 0
  and 1 in some row, and where the subject leaves open which of them count,
  that row is a reading (`readings`), never the basic table; each row is
  labelled with the property it checks (`labeled = True`), so a clue names
  the property rather than a line number.
- *"Reproduce the behavior of the function strlcpy (man strlcpy)"*, a
  manual page of a function glibc 2.35 lacks: the page ships only in
  libbsd-dev, in section 3bsd, and the dev image installs nothing of that
  package but the pages it extracts by name from the pinned `.deb`
  (`.devcontainer/Dockerfile`, the libbsd-dev RUN). Add the page's member
  there, and a clue that sends the student to it says `man 3bsd <name>` and
  names man.openbsd.org's page beside it, for a box without the package.
  `//tools:conventions` holds both to its `LIBBSD_PAGES`; libft's
  `ft_strnstr` is the next, its page `strnstr.3bsd`, in the same `.deb`.

**The include path is the grader's.** Where a subject lets headers sit in a
subfolder (`optional = ["**/*.h"]`), the headers are staged for every build
and layer, but a subfolder is on the include path only where the grader's
compile puts it there. Rush 01's grader runs `cc -Wall -Wextra -Werror -o
rush01 *.c` with no `-I`, so a header in `includes/` is reached by
`#include "includes/name.h"` and by nothing else -- in the program the run
layers use and in the compile and forbidden layers alike, which say so when
they fail. A Makefile project's include path is the `-I` its recipes pass, as
`make -Bn` reports them: the build of its program reads them, and hands the
same list to the compile and forbidden layers.
