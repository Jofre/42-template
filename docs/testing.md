# Testing

**For:** you, mid-exercise, with something red.
**Tables live in [reference.md](reference.md)** — the layer list, the level
ladder, which layers wait for which, the flags and the environment variables.
This page is how to use them.
**The commands here are Bazel's**, the ones `42` types for you: `42 test` in a
module's folder does what the first one below does
([The `42` command](#the-42-command)), and [bazel.md](bazel.md) pairs each
`42` command with its Bazel form.

---

## Reading a whole run

A module is a few dozen red at once and the whole repo is hundreds. All of it is
true and none of it is an instruction, so pipe it through the triage:

```sh
bazel test //c-piscine/c-piscine-c-05:basic 2>&1 | sh tools/first_red.sh
```

It sorts by module, then exercise, and splits the red into kinds, because they
are not the same kind of problem:

- **DOES NOT BUILD** — code that does not compile or link, or a turn-in file
  that is missing. It comes first, with the compiler's or linker's own line
  (`deliverable/ex00/ft_foo.c:16:3: error: ...`, `multiple definition of
  'main'`, `missing turn-in file: ...`), because it is graded 0 and nothing that
  needs it can run. It also counts what never ran. When this block is printed
  the triage exits 1, and it never says "nothing failed". It is said only
  when a line of the log names a file of yours: a target that failed to build
  with no such line (a broken harness file, a download that failed) is listed
  as **DID NOT RUN**, under "THE BUILD STOPPED", with the first error. A run
  that stopped for another reason (Ctrl-C) is reported as stopped too. None of
  it is blamed on your code.
- **FIX FIRST** — a red at `basic` in `norm`, `compile`, `files`, `forbidden`
  or `prototype` **on an exercise you have written**. A stub passes all five, so
  this is code that breaks a rule that scores zero wherever the project is
  graded. It asks
  `stub_check` before saying so, which is why the header exercises (c-08,
  Reloaded ex22 and ex23) — red at `compile` while still stubs, because a
  header defining nothing cannot compile the subject's own `main`, and the
  macro ones (c-08 ex01 and ex02, Reloaded ex22) at `forbidden` as well, since
  with no macro `EVEN(...)` or `ABS(...)` is a call to a function nobody
  authorised — are never blamed on you. A module's `deliverable_files` (a file
  outside every exercise folder) is listed here under its own name, whatever
  else is written: a stub leaves nothing there.
- **YOUR NEXT EXERCISE** — the first exercise with a red `output` target at
  `basic` (a rush's `_defense`, `_survive` or `_sweep` too). On a stub
  that is what unwritten looks like, and it is the work. On a file you have
  written it is a bug, and the triage says so and names the test log to read,
  rather than calling it unwritten. Only the first is named; the rest are
  counted.
- **RAN OUT OF TIME** — a test Bazel stopped at its time limit. The runners
  stop a program themselves a few seconds before that and say so (see "When
  a test did not finish" below), so this one said nothing, and no cause is
  named: an endless loop, a very slow method, or a machine too loaded to
  finish in time. Run that target alone; if it still times out, it is the
  code.
- **ALSO RED** — the output is right and a target above `basic` disagrees. Worth
  reading, not urgent. Which layer a target is, and at which level it sits, is
  read from the tables `c_levels()`' audit holds every test to
  (`tools/defs.bzl`), so a triage never files a red at another level than
  [reference.md](reference.md#target-names) gives it. A target raised above its
  layer is named as it is (`ex04_reverse_output` reads `reverse_output`, never
  `output`): its row among the raised targets says why it sits there.

It then prints **EVERYTHING STILL RED**: one line per module, with how many
targets, a state — does not build, written and breaking a rule, written with a
wrong output, partly written, not written yet, ran out of time, rigour only, or
did not run — and the exercises that are red: `ex00, ex04` when the three
between them are green, a range such as `ex00-ex02` only where every exercise
in it is red. Seven lines instead of three hundred, and that is the part that
stops a full run reading as hopeless.

For the whole picture, one line per exercise with its red layers counted
(`output x5 build`, not six separate targets):

```sh
bazel test //... 2>&1 | sh tools/first_red.sh --all   # the whole repo: needs memory to spare
```

On a tree with 106 red, that is 95 lines against Bazel's 318 — and the exercise,
not the target, is the unit you actually think in.

Then work that one exercise, every layer at once — see [Working on one
thing at a time](#working-on-one-thing-at-a-time).

### Code that does not build fails its own tests, not the build

Every program a test runs is built from your files by one build step,
`tools/student_build.sh`, and that step never fails because of them. A syntax
error, a warning under `-Werror`, a leftover `main()`, a file that is not
there: each of those makes the program a **stand-in**, a small script that
prints what the compiler or the linker said. Every test that runs it then
**FAILS** on its own, with those words in its log under
`YOUR CODE DID NOT BUILD`, and no hints of the exercise (none of them is about
a build). Every other exercise runs as usual.

When there was **nothing to compile** — no `.c` file, no `Makefile`, or a
`Makefile` whose default goal compiles no source, which is what the stub
`Makefile` of an exercise you have not started looks like — the stand-in says
`NOTHING TO BUILD YET` instead. That is not broken code, and nothing reports it
as such.

A layer that reads your files instead of running them (norm, compile,
forbidden, prototype, symbols) says **NOT TURNED IN** when there is none of
them to read, and fails. A layer that waits for your exercise to pass before
it says anything (ilp32, allocfail, cycles, norm's Notice reading) skips
instead, as it does when your code does not compile: the files, norm and
compile layers already say what is missing. A missing `Makefile` (one renamed
`makefile`) is the same: its programs are stand-ins saying there is no
Makefile, and its layers are NOT TURNED IN.

A file whose **name** holds a blank, a parenthesis or any character outside
`A-Z a-z 0-9 . _ + -` — `ft_putchar copy.c`, `ft_putchar (1).c`, the way a
desktop names a copy — is left out of every build and every layer, because no
Bazel label or argument list can carry it whole. The exercise's `files` layer
is the one that reports it, by its real name.

`first_red.sh` reads the log of each failed test and files an exercise whose
log holds a stand-in or a NOT TURNED IN under **DOES NOT BUILD**, with the
compiler's line or the missing file, never under "not written yet" — except a
`NOTHING TO BUILD YET` over files that are still stubs, which is exactly an
exercise not written yet, and is filed as one.

A **build error** can still happen, but it is the harness's, never your
code's: a file of the harness that does not compile and reads nothing of
yours, a compiler that was killed or crashed (run it again), a download that
failed.
Bazel has two keep-going flags. `--test_keep_going` is on by default, so a
failing test never stops a run. `--keep_going` (`-k`) is the one for build
errors, and `.bazelrc` turns it on, so the targets that need the broken step
print **FAILED TO BUILD** and every other target still runs. Without `-k`, the
first failed step ends the run, and everything that had not run yet prints
**NO STATUS**, which says nothing about those targets, good or bad. Bazel ends
such a run with `ERROR: Build did NOT complete successfully` and exit status
1, and lists only the first few FAILED TO BUILD targets. `first_red.sh` reads
that too, and does not call it yours: those exercises are listed as not run.

### Why the run is not simply ordered

Because Bazel will not order it. It schedules tests in parallel and promises no
order, and it does not deliver one even when told to serialise: three runs of
`bazel test //c-piscine/c-piscine-c-10/... --local_test_jobs=1 --notest_keep_going --nokeep_going`
stopped on `ex00_build`, then `ex02_ccarry_output`, then `ex01_two_output`. Same
command, same tree, three answers. So the run stays parallel and fast, and the
order is applied to the report, where it is deterministic and costs nothing.
(`--nokeep_going` because `.bazelrc` sets `-k`: with it on, `--notest_keep_going`
alone no longer stops at the first red test.)

## Which red should I fix first?

When several layers are red at once:

1. **Get the right output, any way you can.** `output` first, then `diff` — the
   curated table uses cases you can reason about one at a time; the differential
   corpus uses cases you did not choose.
2. **Then check you are not breaking anything.** `valgrind`, `asan`,
   `diff_asan`, `symbols`, `ilp32` -- and `method`, where the subject says
   how the work is done (recursive, iterative, a fixed-size array): it waits
   for the right output, then reads how you reached it.
3. **Then ask whether it is optimal.** `perf` for how the cost grows, `cycles`
   for what one unit of work costs — and usually there is nothing to fix there,
   only something to think about.

This is deliberately **not** the order you would use in production, where memory
safety gates a release. It is the order that carries information while you are
still learning the exercise: **a stub is trivially memory-safe**, so the memory
layers are green on code that does nothing at all. They only start telling you
something once there is a real implementation to check.

Nothing is downgraded by this. Every layer still runs, every red still counts,
and `//tools:submit` will not push a module with any test failing.

## Layers whose point is not obvious

- **`symbols`** — the Moulinette compiles your file together with a `main()` you
  have never seen, so a helper named `ft_strlen` or `length` can collide with
  theirs and the *link* fails on code that is otherwise perfect. `static` gives a
  helper internal linkage and the collision stops being possible.
- **`method`** — a few subjects say how a function is built, not only what it
  returns: "Create a recursive function", "an iterative function", "declaring
  a fixed-size array". No output shows that, so this layer reads it from how
  the program runs (is a function of yours entered again while it is still
  running?) or from what the compiler measures (an array whose size is only
  known once the program runs, or one past the subject's bound). It sits at
  `strict`: the grader only runs your program, an evaluator reads the code.
- **`ilp32`** — C only promises that `long` is *at least* 32 bits. Copying an
  `int` into a `long` so `INT_MIN` can be negated works on the campus box (LP64)
  and is undefined where `long` is 32 bits — every 32-bit Linux, and all of
  Windows. What C does promise is a minimum width per type (`<limits.h>`):
  `int` at least 16 bits, `long` at least 32, `long long` at least 64. A value
  held in a type too narrow for it on some platform is a bug on that platform,
  whichever type it is; the hints for `INT_MIN` and for products that outgrow
  an `int` ask whether the value has to be formed at all, and leave the choice
  to you. This layer rebuilds each exercise for `x86-linux-musl` and replays the
  exercise's own fixture. That build also **stops the program at undefined
  behaviour**: a signed `int` that overflows, or an index past the end of an
  array, dies there on `SIGILL`, where the 64-bit build ran past it silently.
  So a red here is not always about `long`, and the report says which it saw:
  it blames the type model only when the program ran to the end with other
  output and the ordinary 64-bit build passes the same cases. For a `SIGILL`,
  `diff_asan` or `asan` names the line.

## How your code is built

Every layer builds your code itself, with Bazel, from what is in the
exercise's turn-in directory -- `deliverable/exNN/`, or `deliverable/` itself
where the subject names no turn-in directory, as BSQ's does: every `.c` there
is compiled, and every `.h` beside them is staged for the compiler and checked
by `norm`, whatever you named them. A function exercise is linked with the
test's own `main()` from `tests/exNN/`; a program is linked on its own, as
yours. Only files directly in that directory are read, not a subfolder, unless
the subject lets your files sit in subfolders: BSQ and Rush 02 (every `.c` and
`.h`, wherever your Makefile says) and Rush 01's headers. What the grader brings
-- C 08's `ft_stock_str.h`, Reloaded's `ft_putchar.c`, C 09 ex01's `srcs/` --
comes from `tests/`, never from your folder. Which is which, for every
exercise, is the project's subject contract ([reference.md](reference.md#the-subject-contract)).

Your `Makefile` is not what builds the program the tests run. It is graded on
its own, by `exNN_build`. So if `make` builds your folder and a layer says it
does not compile, or the other way round, compare which files each one sees.
BSQ and Rush 02 go one step further: they ask your Makefile which `.c` files
make up the program and which `-I` directories it passes, then compile those
with the harness's own flags (see [rushes.md](rushes.md)).

Two kinds of file are compiled with yours from outside `deliverable/exNN/`:

- **A file the subject says the grader supplies** — Piscine Reloaded's
  `ft_putchar.c`, C 08's `ft_stock_str.h`, C 12 ex08's `ft_list.h` ("we will use
  our own ft_list.h"). The harness keeps its copy under `tests/`. You need not
  turn it in; if the subject lets you keep a copy anyway (C 12 ex08), yours is
  the one compiled, and it is normed.
- **A function the subject says the grader brings** — C 12's `ft_create_elem`
  and C 13's `btree_create_node`, "from exercise 01 onward, we'll use our ...".
  From ex01 on, every program the tests build links the grader's copy, never
  your ex00, in every layer that runs one, the 32-bit `ilp32` one included: a
  bug in your ex00 is ex00's red alone. That copy is built on the structure
  the subject prints, so a `ft_list.h` or `ft_btree.h` that lays the structure
  out differently fails there as it would at the grader, and the `prototype`
  layer says why. The harness compiles that copy from Rust
  (`tools/grader_lib.bzl` says why), and your code calls it as the
  subject's prototype declares it; defining it again in a later exercise is
  a second definition the grader's link refuses, which the `forbidden` and
  `symbols` layers report.

## Reading a failure

An `*_output` test prints a per-line **PASS/FAIL table** (`CASE | EXPECTED | GOT
| STATUS`). Passing rows are shown too — they document what the function should
do. Cases run roughly trivial → harder, so the **first** failing row is usually
the most fundamental thing to fix (after a crash, the marked row is: see below).

**The RESULT line says why it failed.** `FAIL (2/5 passed, 3 failed)` is about
rows. `FAIL (lines match, bytes differ)` means every row matched and the bytes
still differ: the report under the table says when the final newline is the
only difference, and shows that line both ways. `FAIL (output right; exited 1,
this case expects 0)` is about the exit status alone, and says whose rule that
status is — the subject's, or this repo's convention, which only `robust`
checks ([reference.md](reference.md#run-contract)). When no row failed, only
the hints keyed to no case are shown, since a hint about a case would point at
code that works.

**Every row shows its bytes**, a failing one also `$` where a line ended,
as `cat -e` marks it; `\t` a tab; `\\` a backslash; `\x24` a dollar that is in the text, so a
`$` is only ever a line end; and `\xHH` any other byte outside printable
ASCII, in hex (`\x00` a NUL, `\x0d` a carriage return, `\xff`). A trailing
space or a stray NUL is therefore visible, and a legend under the table names
the marks its shown rows hold. A few test programs print a value that cannot
travel raw — Rush 00 prints a whole rectangle as one value, C 02 ex01 and ex10
and C 03 ex05 a whole buffer, NUL bytes included — and they write it in these same marks, with one
more, `\n` for a line break inside that value; those cells are shown as the
program wrote them, so `/\\\n` is a slash, one backslash and a line break.
The tables, argument lines and excerpts the runners in `tools/` print use
these marks, and the legend under each names the marks that what it shows
holds, never a fixed list; a module's own check script
(`tests/exNN/check.sh`) says what it found in its own words. An excerpt of
what a compiler or a program wrote (under `stderr:`) uses the same `\xHH` for
a control byte, doubles a backslash that would otherwise read as the start of
one (the text `\x01` is `\\x01`), and leaves the rest of its text as it was,
so a compiler's `^` still points at the right column. A
long row is cut to a window around its first difference (`DIFF_CELL_MAX`),
and a long passing row at its end. A `CASE` label is text and is shown as
written, but for a control byte, which is `\xHH` there too. A case whose expected output is at
least 30% bytes a terminal cannot show is not tabled at all: you get both
sizes, the first byte that differs (counted from 1, as `cmp` counts) and each
side's bytes from just before it, in these same marks, with a `^` under that
byte. The runners that compare whole files (C 10's) show a failing case the
same way.

**After a crash, a hang or a runaway** the table still shows every row, in
the order the cases run, and a paragraph under it says what the ending means
(`SIGSEGV`, `SIGABRT`, `SIGILL`, a timeout, or output that never stopped).
What the rows mean depends on whose program ran:

- **The harness's own test program** — the `main` in `tests/` that calls
  your function case by case, which is most exercises (C 08's headers and
  Rush 00's included). It prints each case as it runs, so a crash does not take the
  earlier rows with it: the rows above the marked one are real results, the
  marked row — `running when the program died`, `running when time ran out`,
  or `running when its output was cut off` — is the case that was running,
  and its hints come first. The rows after it read `not reached`: they never
  ran, so they say nothing about your code yet.
- **Your own program** — where you write `main` (C 10, C 11 ex05, BSQ,
  Rush 01, Rush 02, Reloaded ex27). Nothing is marked. A program whose output is buffered, as
  `printf`'s is when it goes to a file, loses whatever was still in the
  buffer when it dies, so a row reading `(no line)` is not necessarily one it
  never reached; RESULT says how many lines reached the output.

**A program's case says what it ran.** Each case of a program is a test of
its own (`exNN_<case>_output`, and its `_exit`, `_asan` and `_valgrind`
arms), and each opens its log with the command it ran:

```
RAN: bazel-bin/c-piscine/c-piscine-c-11/ex05_bin 42 '*' 21
```

Run that line from the repository root, once `bazel test` has built the
program, to see the run for yourself: a fixture is named by its path in the
repository, an argument a shell would split or expand is quoted, and an
empty one reads `''`. A case run from a folder of its own -- Rush 02's
one-argument form reads `numbers.dict` from the folder it runs in -- says so
under that line, with where each file of the folder came from. Every case's
arguments are written in the module's `BUILD.bazel`, in its `c_program`
call.

A program that returns -1 from `main` has returned (its status is 255), not
crashed: how a run ended is read from the operating system, not guessed from
the number.

**A case compares one stream; the other is only shown.** Standard output,
usually, or standard error where the subject names an error message written
there. What a program also wrote to the other stream is never graded — no
subject here asks anything of it ([reference.md](reference.md#run-contract))
— but it is never hidden either: a passing case says `note: also written to
stderr (not compared by this case)` with its first lines, and a generated
corpus says how many of its cases wrote to standard error and shows the
first. A debug line left in is what that note is for.

**A generated case can be run again.** The layers that replay a generated
corpus (`exNN_argv_diff`, `exNN_file_diff`, BSQ's `ex00_bsq_*`, Rush 01's
`ex00_sweep`, Rush 02's corpus) print each failing case whole: its input
with every byte visible, what was expected and what came out, and the
command line that runs it again. The input it ran on — a map, a dictionary,
the files a C 10 program read — is kept under
`bazel-testlogs/<package>/<target>/test.outputs/`, which is where that
command line expects to be run. The report prints
the first `DIFF_MAX_ROWS` failing cases (40) and tallies the rest; every one
of them is in `test.outputs/differences.txt`, and
`--test_env=DIFF_MAX_ROWS=0` prints them all.

**A generated corpus runs under the memory checkers too.** Each fixed case
of a program has its own `_asan` and `_valgrind` arm, but the inputs only a
corpus holds — a long number, a map past twenty rows, a file past one buffer,
a vector with no solution, a map read after another in the same run — reach
code those cases never run. So every corpus target of a program has twins
named after it, which replay the same inputs the same way: `ex00_bsq_stdin`'s
are `ex00_bsq_stdin_diff_asan`, on the ASan/UBSan build of your program, and,
where the subject allows `malloc` (Rush 01, Rush 02, BSQ, C 10 ex02 and
ex03), `ex00_bsq_stdin_valgrind`, which runs 25 of its cases, spread over the
whole corpus, under memcheck. They judge memory and how each run ended, never
the output — that is the plain replay's finding — and a case that went wrong
is printed with its input, the command line that runs it again, and the
checker's own report, and what each kind of finding means is said once,
after the cases; output without end is reported as such, not as a hang,
and a run that does not finish in its time is said apart and never judged
wrong (the target stays red: a case nobody judged has not passed).
While your program does not build they say SKIP, as every memory layer does.
A target that runs probes rather than a corpus (Rush 01's argument-count and
shape probes) has twins too, and they run exactly the probes it judges.

Below the table, a **HINTS** block may appear. Hints are pedagogic nudges, never
answers: they name what to reconsider. They are grouped by concept,
most-fundamental first, and only three are shown at once.

Which of the rest you can reach depends on how a hint is written. A hint keyed
to particular cases stops firing once those cases pass, which lets a later one
rise into view — that is the "unlock" the footer offers. A hint keyed to no case
fires on **any** failure, so passing cases never reveals more of those; it only
removes them, all at once, when the exercise goes green. A program's case is a
test of its own, so a hint there is keyed to the case's name: it fires on that
case and no other, and on every failure of it. So is a program's target that
replays a corpus (BSQ's and Rush 01's `ex00_readings`, Rush 01's
`ex00_sweep`), keyed by its name after `ex00_`. A hint keyed to `valgrind` is
about memory: it fires in a memcheck test (`_valgrind`), never when an output
is wrong, and comes first there; the hints keyed to nothing (or, for a
program, to the case) follow it under a heading saying they were written for
the output test, and a hint keyed to another case does not show. An exercise that is a Makefile alone has no cases: its `_build` tests
end any failure with its hints, every one of them keyed to nothing. The
footer says which of these you are looking at. Either way, to see
everything now:

```sh
bazel test //c-piscine/c-piscine-c-03:ex00_output --test_env=CLUE_MODE=all
bazel test //c-piscine/c-piscine-c-03:ex00_output --test_env=CLUE_MODE=5
```

The full curated hint set for an exercise is `tests/exNN/clues.tsv` -- for a
program, every case's rows in one file, each keyed to the cases it is about
-- plus, outside the programs, any `clues_*.tsv` beside it where one test
carries hints of its own. Reading them is fair game — no test in this repo
contains an answer. Every layer that prints hints reads that file the same
way, `CLUE_MODE` included.

### When a test did not finish

Every run of your code has a time limit, and when it runs out the test says so
in one sentence:

```
rust_diff: FAIL — did not finish within 52s: an infinite loop, or too slow on the input at or after case 18214 of 400000 (fn=c05_is_prime, seed=1).
```

It cannot tell the two apart from outside — a program that never stops and a
correct one far too slow for the input look the same — so it names both, and
the case it was on. Most layers expect each run to finish almost at once, so
start with a loop whose condition never becomes false on that input. When the
number is not the run's own limit but what was left of the test's (a sweep of
hundreds of cases, most of which passed), the report says that too: the case
it names is the one that was running, and the ones after it were never tried.
A machine busy with other work stops a correct answer that way too, so
`tools/first_red.sh` files such a test under RAN OUT OF TIME with Bazel's own
`TIMEOUT`s, not as a wrong answer: run the target on its own before you look
for the loop. The exceptions are a test that had already judged some cases
wrong before its time ran out, and one in which some run had already run out
of its own limit: it says how many, and first_red files it with the failures,
because a busy machine slows a program down but does not change what it
prints, and a run's own limit counts its own time, not its wait for a CPU.

Output a test cuts short says how much it left out, and where the rest is:

```
    ... 34 more line(s), full text in bazel-testlogs/c-piscine/c-piscine-c-05/ex04_diff/test.outputs/harness-stderr.txt
```

A differential that generates its inputs keeps the input of each failing case
it shows in the same place, with the command that runs it again: Rush 02's
generated dictionaries (`case-N.dict`) and BSQ's maps (`case-N.map`).

### Reading a sanitizer report

`asan`, `diff_asan` and an argv program's `exNN_asan` run your code built with
AddressSanitizer and UBSan, which stop it at the first access outside a block
it owns, or the first undefined operation. The report opens with what it was
— `heap-buffer-overflow`, `READ of size 1` — then one frame per line, the top
one being where the access happened, then which block was overrun and by how
much (`0 bytes to the right of 3-byte region`). Each frame names a function,
and where it is yours, a file and a line: the harness symbolises it with the
pinned `llvm-symbolizer` (campus's 12.0.1 build; `tools/pins.tsv`), never one
found on your `PATH`, so the report reads the same on every machine. The
shadow-memory map ASan prints under it is left out; the whole report is saved
beside the test's log, and the log says where.

`diff_asan` also says which generated case it was on (`It happened on corpus
case #N`), shows that line, and prints the same column legend and hints as
`diff`. It replays the first `asan_count` cases of the `diff` corpus (200000
of the 400000, by default), not all of them.

### When `forbidden` names something you did not write

`forbidden` compiles your file and reads the calls out of the object file, so it
sees the names the C library's headers turned your code into: `errno` becomes a
call to `__errno_location()`, `<libgen.h>`'s `basename` becomes
`__xpg_basename`, and every `<ctype.h>` classifier (`isalpha`, `isspace`, …)
becomes `__ctype_b_loc`. The layer maps those back before it judges anything,
so a subject that allows `errno` or `basename` is taken at its word, and a
refusal names what you wrote, with its file and line, and then the symbol nm
saw (`seen by nm as __ctype_b_loc`). A function reached through a `#define` of
your own counts where the macro is used, and is reported at the line that
names it, which can be in your header. A `__` name it cannot map is still
reported: look in your file for what you used from a header.

### What a `norm` log tells you

Each `norm` target prints norminette's report, then a verdict, then how it ran:
the norminette version, the `-R` rule that applied — norminette keeps only the
**last** `-R` it is given — and a `bazel run //tools:norminette -- …` command
that asks the same question by hand, from the repository root. A norminette you
installed yourself may be another version with other rules;
`bazel run //tools:env_drift` compares the two.

- The verdict comes from each file's own `OK!` / `Error!` line. norminette's
  exit status follows only the **last** file it checked, so it is not used.
- A **Notice** leaves the file `OK!`, yet norminette still exits 1 on it, and no
  subject says which of the two counts. So `exNN_norm` passes with a warning,
  and its twin `exNN_norm_notice`, at `strict`, fails.
- A file norminette cannot parse ends its run: nothing is printed for the other
  files, and the log says how many it judged.
- norminette does not check every rule of the Norm. Two it skips are read, at
  `strict`, by `exNN_norm_header`, in every header an exercise turns in: a
  header must be protected from double inclusions (it is preprocessed included
  once and included twice, and must give the same lines both ways; that is
  all the check can see, so a header with nothing to repeat passes with or
  without a guard), and a struct, union or enum defined inside a `typedef`
  takes its prefix like any other (`s_`, `u_`, `e_`). A `typedef` of a
  struct defined elsewhere, or of libc's (`struct timeval`), defines nothing
  there and is not read.

### The `diff` layer's hints read differently

`diff` stays silent until your `expected.txt` is green, then replays hundreds of
thousands of generated inputs. When it finally speaks you have already fixed
everything you could reason about, and it has no case names to hang a hint on —
only a wall of hex.

So it prints a legend for the hex columns, then a list of **which family of
failing inputs implies what**. That second part is the useful one. Do not read a
divergence as "case 4194 is wrong" — ask what the failing inputs have in common:

```
  * only sizes with a 1 in them     -> the row that is first and last at the
                                       same time
  * every size, off by one line     -> a bound on the row loop
  * fine until 128 or 256 wide      -> the type of the variable you count with
```

Each line names a place to look, never the fix.

C 06's differential (`exNN_argv_diff`) runs whole programs on generated
arguments and has no such list. It shows every byte of a failing case — a byte
a terminal cannot print as `\xHH`, a line end as `$`, an output with no final
newline marked as one — and, when there is one, a property every failing case
has and some passing cases lack:

```
  what the failing cases share:
    * every failing case has an argument holding a byte above 0x7f; the N cases without that all passed
```

## Proving a green suite is actually green

Layers skip rather than repeat a failure you can already see — [which waits for
which](reference.md#which-layers-wait-for-which) is a table. That keeps the red
list short and readable, but **a layer that is quiet looks exactly like a layer
that has nothing to say.**

```sh
bazel test //c-piscine/c-piscine-c-05/... --test_env=NO_SKIP=1   # //... for the whole repo, with memory to spare
```

forces every gate open. Nothing is suppressed: the differential replays its
corpus against an unwritten stub, `valgrind` reports on it, `ilp32`
cross-compiles it anyway, and a missing tool becomes a failure instead of a
quiet pass. Expect far more red — that red is the work still to do, stated
twice. Use it when you want a green run to mean "checked and correct" rather
than "checked nothing". A `valgrind` report opened this way over an exercise
whose `output` is red says so on its first lines: the test frees what it
built the way a right answer builds it, so a wrong one can leave something it
could not take apart, and `*_output` is the report to read first.

### A test that never compiled is not a test that passed

`--test_tag_filters` chooses which tests RUN, not what is built: `bazel test`
still builds every target its patterns name (everything under a `/...`, every
test of a suite such as `:exNN`, the ones the filter drops included), unless
`--build_tests_only` is given, and nothing here gives it. A level suite such as
`//<module>:basic` names only its own level's tests, so it never builds a
harness further up the ladder. Where a target the filter dropped is built and
fails, the only sign is an `ERROR:` line above "All tests passed but there were
other errors during the build.": no test line names it. And a harness that
does not compile is normally a stand-in rather than a build error (below). So
a broken harness can stay invisible to every run, filtered or not:

```sh
bazel build //... --action_env=STUDENT_BUILD_STRICT=1   # every test program, compiled
```

is the check, on a tree whose exercises compile (the stubs, or answers), and
`bazel build --nobuild //...` is **not** — that stops after analysis, so it
proves the BUILD files are well formed and nothing about the C. The
`STUDENT_BUILD_STRICT=1` matters too: a program that does not compile is
normally a stand-in rather than a build error (see [above](#code-that-does-not-build-fails-its-own-tests-not-the-build)).
Without it, a file of the harness that does not compile fails the build only
when no file of the student's reaches it (the builder asks the preprocessor
which headers it read); one that includes a turn-in header is a stand-in,
because a header that does not declare what the subject says fails there
first. With it, every file of the HARNESS that does not compile fails the
build again, as it should. `docs/publishing.md` runs it on the template. This is not hypothetical: a `t_list *head` used in one c-12 diff
harness and never declared survived a full `lvl_strict` sweep, which never ran
it: that harness is a level-3 target.

## Working on one thing at a time

The whole suite is more than you need while writing one function, and on a
memory-tight box it is more than you can afford
([environment.md](environment.md)). Ask for the narrowest suite that answers
your question:

```sh
bazel test //c-piscine/c-piscine-c-05:ex00      # one exercise, every layer
bazel test //c-piscine/c-piscine-c-05:basic     # one module, what is a KO where it is graded
bazel test //c-piscine/c-piscine-c-05:strict    # + what strict adds (reference.md)
bazel test //c-piscine/c-piscine-c-05/...       # the module, everything
```

`//<module>:exNN` is the one to live in while writing an exercise. It exists
because `ex00_*` is not a Bazel target pattern — you could run one layer or a
whole module, and nothing in between.

Ask for the suite rather than `--test_tag_filters`: a tag filter also filters
targets you name explicitly, so naming one target and one tag can quietly select
nothing.

## The `42` command

`42` types the Bazel commands on this page for you. Add `--show_bazel` to see
the ones it runs, or `--dry-run` to see them and run nothing;
[bazel.md](bazel.md) takes each one apart. It adds only flags that keep Bazel's
cache, so a command typed by hand afterwards hits the same results.
`sh tools/setup.sh` installs it as `~/.local/bin/42`; in a checkout where setup has not run, `sh tools/42.sh` is
the same command. `42` alone lists the commands, and `42 help --all` adds the
maintainers'.

**Where you are decides what runs.** In a module's folder, `42 test` runs that
module; in an exercise's folder (`deliverable/exNN` or `tests/exNN`), that
exercise; at the root it asks which. Words narrow it, in any order: a module
(`c-05`), an exercise (`ex03`), a layer (`norm`, `valgrind`), as in
`42 test ex03 valgrind`. The level is `--level`, else `SUBMIT_GATE`, else
`.submit-level`, else `basic`, which is how `//tools:submit`'s gate chooses
it, and `42 test` selects the same tests that gate does: a module that is
green under `42 test` is one submit will not block. A layer named runs whatever
its level, as naming one target does.

**`42 clues`** asks the tests that failed for all of their hints, and
`42 clues 5` for five ([Reading a failure](#reading-a-failure) explains how
hints are rationed). It never re-runs a test that passed.

**`42 watch`** runs the tests again each time you save a file they read: the
exercise's turn-in folder, or the module's, and a shell exercise's
generator. It never moves on to another exercise and never shows more hints
than `42 test` would. `q` quits. What it can and cannot see:

- It polls, once a second, because some checkouts tell inotify nothing (a
  Windows folder mounted into the dev container is one). A file changed and
  changed back within that second can go unseen: save it once more.
- A save during a run stops that run, and the tests run again once the saves
  settle. A run that goes on over an edit can build from one version of the
  file and test another, then keep that result and serve it again on a later,
  still run. Bazel does not notice, so `42` does: it remembers what a run
  could not vouch for, and when that version of the file comes back it
  deletes what Bazel built for the module and runs it again without the
  cache. It says so when it does.

The same can happen to a `bazel test` you typed, if you saved while it ran.
`42 test` checks for it on its own runs only. By hand, run the same command
again with `--nocache_test_results`; if a test program still behaves like
your old file, run `bazel shutdown`, then the same command with
`--nocache_test_results --use_action_cache=false`. The repair `42` makes is
narrower: it deletes what Bazel built for that one module (`--show_bazel`
shows the command), so nothing else is built again.

**`42 doctor`** checks the machine before Bazel does anything: python, the
`42` on your PATH, bazelisk, where Bazel keeps its state and how much room is
left there, memory, your identity, tmux. It then runs `//tools:env_drift` when
Bazel is already warm (`--drift` asks for it anyway), and `--report` writes the
campus report (`tools/env-audit.sh`). **`42 stop`** stops this checkout's Bazel
server, which gives its memory back. The other commands (`submit`, `norm`,
`generate`, `header`, `init`) each run one target, and `42 help` names it.

## The two cost layers

Both report, and the number is the lesson. Both stay quiet until the exercise
is correct. **`cycles` never fails on what it measures**: a budget only changes
the sentence printed, and a run too long to profile is reported too. **`perf`
fails in three cases**, each a line this repo draws at `complete` — the time
over the number of cases growing at n^2.6 or steeper, confirmed by a second
measurement; and, against the reference, 5000 times its time or 200 times its
peak memory. Either layer also fails when a measured run crashes, as every
layer does (a signal fails at every level). Nothing else turns them red: a size
too slow to finish within `PERF_TIMEOUT` is halved and measured again, and one
that never fits is reported, not failed — under `NO_SKIP=1`, the maintainers'
sweep, a layer that measured nothing is red.

Their targets, like the long differentials, are declared `medium`: a time limit
of 300 s rather than 60, so that a slow but correct answer, and callgrind's own
slowdown, are measured rather than timed out. When they finish well inside the
shorter limit, which is most runs, Bazel ends the run with `There were tests
whose specified size is too big`. That is its note about the harness's time
limits, not about your code; the sizes are chosen, and stay.

`perf` answers **how the cost grows**, in time and memory. Its scaling varies
the **number of cases**, each one a small input, so it sees how many calls add
up, not how one call grows with a longer input: a cubic sort over arrays of a
dozen ints is linear in how many arrays it is given. Where one input's length is
the question (C 01 ex08, C 12 ex14) a **length series** follows, a few cases at
three lengths, and its exponent — what doubling the input does to one call — is
reported and never gated: for a sort, that exponent *is* the algorithm, and a
line drawn on it would recommend one.
`cycles` answers **what one unit of work costs**, counted by callgrind with the
harness excluded — the constant factor `perf` is too noisy to see.

**Per unit of work, not per call.** "277 instructions per call" says nothing on
its own; per *byte* it can be read against what the work costs. Where a target
has a budget the runner prints it beside your figure: `ex05_cycles` (`ft_putstr`)
says a good implementation manages about 4.5 instructions per byte, and 17.5 is
about four times that. The unit is counted from the corpus the test just ran —
every input byte the function must read at least once, or every byte it must
write — so it is the same whatever technique you chose, and cannot drift from
what was measured.

**The allocator is shown apart.** A function that calls `malloc()` is charged
for it, and the runner prints the figure with the allocator and without it, and
what each `malloc()`/`free()` call cost. How many blocks to ask for is your
choice; the budget is read against the figure without them.

**Budgets are numbers, never a reference implementation.** A target tells you
where you stand; source code would tell you the answer, which no test here may
do. They are measured at `-O2` on correct answers, and a target where the cost
per unit follows the technique — a lookup, a sort — has none, because a budget
would recommend the technique it was measured from.

Why the layer exists, from two real files in this repo — the same function, both
fully correct, both green on every other layer:

| | instructions/byte | `write()` per case |
|---|---|---|
| `ft_putstr`, implementation A | 17.5 | 15.85 |
| `ft_putstr`, implementation B | 4.2 | 1.00 |

**4x the instructions and 16x the syscalls**, and nothing else in the suite can
tell them apart. The layer's `write()` budget for this exercise is 1 per case,
and B sits on it. What B does differently is not written here, for the reason
the paragraph above gives: working that out from the numbers is the exercise.

```sh
bazel test //c-piscine/c-piscine-c-01:ex05_cycles --test_output=all
```

The runners' own headers carry the measurement caveats — what callgrind cannot
count, why the layer builds at `-O2`, how the scaling exponent is fitted. See
`tools/cycles_check.sh`, `tools/perf_test.sh` and `tools/ref_compare.sh`.

## In the editor

Both reuse the same Bazel cache, so re-runs are instant:

- **Run Test Task** (any editor): runs `Bazel: test this module (basic)`, the
  `:basic` suite of the module the open file belongs to. **Terminal → Run
  Task…** lists it beside `Bazel: test all (the whole repo: needs memory to spare)`,
  which a campus box does not have the memory for.
- **Testing panel** (VS Code): the *Bazel-TestExplorer* extension shows every
  target as a red/green tree. Marketplace-only, so it is unavailable on Open VSX
  editors like Antigravity — use the task there.

**Save, then run — not during a run.** A file you save while a run is going
(by hand, or an editor's format-on-save) can leave a result cached for the
version the test read, and running the same command again serves it again:
a compile layer can show PASSED on code that does not compile. If a result
looks wrong after you saved mid-run, run it again with
`--nocache_test_results`. If the program still behaves like your old file,
run `bazel shutdown`, then the same command with
`--nocache_test_results --use_action_cache=false`.

## Targets that run only when named

A few targets are tagged `manual`: no suite but their module's `:manual` runs
them, and `bazel test //...` leaves them out. Naming one runs it; so does the
module's `:manual`, which runs them all:

```sh
bazel test //c-piscine/c-piscine-rush-02:manual              # run them all
bazel query 'tests(//c-piscine/c-piscine-rush-02:manual)'    # list them
```

Which they are, and why each is left out, is
[reference.md's table](reference.md#manual-targets). A `--test_tag_filters`
does not select them: Bazel ignores `manual` as a tag to include, so
`--test_tag_filters=manual` runs the ordinary tests instead. As a tag to
exclude it does work: `-manual` drops a manual target even one you name.

## Shell modules work differently

For `c-piscine-shell-NN`, and for Piscine Reloaded's ex00–ex05, the answer is
the **generator** — `generators/exNN.sh` — and `deliverable/` is produced from
it and gitignored. Never hand-edit a shell deliverable:

```sh
# 1. write the commands in generators/exNN.sh
bazel test //c-piscine/c-piscine-shell-00:ex01_output # 2. check it
# 3. fix the generator and repeat
bazel run //c-piscine/c-piscine-shell-00:generate     # to look at what it makes
```

The tests never read `deliverable/`. Each one runs `generators/exNN.sh` in a
scratch folder of its own and checks what that run made, and its log's first
line says so (`checking a fresh copy built from generators/exNN.sh …`). So there
is nothing to rebuild before a test: `:generate` writes the same generator's
output to `deliverable/exNN`, for you to look at or run by hand, and
`//tools:submit` regenerates it before it tests and pushes, so the tree that is
tested is the tree that is pushed. `exNN_files` lists what the run left: the
file the subject asks for, as `present` or `not produced` (`exNN_output` says
why, with the exercise's hints), and anything else, which fails.

What is tested and what is pushed come from the same generator, not from one
run of it: it runs again on every test, every `:generate` and every
`//tools:submit`. A generator whose output can differ from run to run (Shell
00 ex03's makes a new key each time, which is the exercise) is checked for
what every run's output shows, and the file 42 receives is its last run's.

Every module's `:generate` refuses to replace a `deliverable/exNN` that holds
anything the generator did not produce on that run (a file you put there by
hand, C sources, 42's `resources.tar.gz`, anything while the generator is still
the skeleton), or that is a file rather than a folder, because those files were
never committed and replacing the folder would lose them. It names the file,
carries on with the other exercises, lists everything it did not generate at the
end, and exits non-zero, so `//tools:submit` stops that module too. A generator
that exits non-zero is reported as failed and leaves its `deliverable/exNN` as it
was. One that exits 0 but makes less than last time is refused the same way:
what it printed says why.

Shell 00 ex07 reads 42's `resources.tar.gz` from the module folder, and only
from there: save it as `c-piscine/c-piscine-shell-00/resources.tar.gz`, next to
that module's `BUILD.bazel`.

**Reading a shell `exNN_output` log.** It is a checklist, one `[PASS]` or
`[FAIL]` per property, and three kinds of line need explaining:

- If the file you turn in is not there, the checklist stops at that line:
  `RESULT: FAIL (the file does not exist; nothing else was checked)`. A check
  that asserts an absence (no spaces, no look-alike) would otherwise pass on
  nothing.
- `name parses under /bin/sh (sh -n)`: the test runs your script with
  `/bin/sh`, as the subject requires, not through its `#!` line. A construct
  only bash knows can work in your terminal and fail here; the shell's own
  message is printed under the line.
- `ran: sh name`: printed only when a run exited non-zero or wrote to stderr,
  with the exit status and the first five lines of that stderr; what it
  leaves out is counted, and kept whole in the test's `test.outputs/`. It is printed
  where the run happens, so it sits above the checks that judge that run: a
  check that runs your script more than once (another user, another range,
  the subject's second example) prints the block for a later run further
  down, in the middle of the list. It is usually the line that explains the
  `[FAIL]`s under it.

**What a machine lets a check see.** Three Shell 01 exercises read the
machine, and each check says, as a `[SKIP]` line, what a machine could not
show it — never a pass. `NO_SKIP=1` turns each into a failure. Bazel runs
the tests that run these turn-ins every time, never from its cache: what
they read of the machine is no file Bazel tracks, so a cached pass could
outlive the machine it was earned on.

- ex01 (`print_groups.sh`) joins a user's groups with commas, and a list of
  one group has no comma: the check drives a user in two groups or more when
  the machine has one (the dev container's `student` is), and otherwise says
  `cannot observe the comma join`.
- ex07 (`r_dwssap.sh`) reads `/etc/passwd`, and a laptop's has no comment
  line and too few logins for the subject's 7..15 window. So every run but
  the last reads an invented file instead,
  `c-piscine/c-piscine-shell-01/tests/ex07/passwd`, handed to the program
  when it opens `/etc/passwd`; the last run is on the machine's own file.
  The log says which file each run read. Where that cannot be arranged (the
  library that does it did not load), the steps only the invented file shows
  are skipped, by name. A program that reads the file other than by opening
  it by exactly that name (through `getent`, or as `/etc//passwd`, or as
  `passwd` from `/etc`) is not handed the invented one, and its runs are
  judged against a file it never read; the subject's is `cat /etc/passwd`.
  When the names such a run printed are this machine's own logins, the log
  says so under the line that failed them, and asks which file it read.
- ex04 (`MAC.sh`) prints this machine's addresses, and is checked at `basic`
  on every machine, outside the sandbox. A machine without `ifconfig`, or with
  no hardware address on any interface, is one where a correct `MAC.sh`
  cannot run or prints nothing: there both `ex04_output` and `ex04_literal`
  check that `MAC.sh` is there and parses, and SKIP what it prints, before
  running it (a failure under `NO_SKIP=1`).

Piscine Reloaded's ex00–ex05 are Shell 00 and Shell 01 exercises again, and
they run the Piscine exercise's tests: each `tests/exNN/` there holds only a
README naming the folder its tests are in. A test file put beside it is read
by nothing, and `exNN_twin` fails saying so (an editor's swap and backup
files do not count). That target guards the harness, not your work, so it
runs at `complete` only.

**The execute bit** is required where the [run
contract](reference.md#run-contract) says: only where the subject's own example
runs the file directly, as `./name`. There, a script without it fails `output`
on a line of its own, with a one-line hint under it; anywhere else nothing
checks the bit. Which exercises those are is listed in
[reference.md](reference.md#shell-turn-ins).

The bit has to come from the generator. The test runs your generator in a
scratch directory and reads the mode of the file *that run* made, which is also
what `:generate` and `//tools:submit` turn in. A `chmod` on `deliverable/`
changes nothing the test reads: the test never looks there, and the next
`:generate` rebuilds the file anyway. Nor does the generator's own mode count,
since it is run with `sh` — and Bazel, which keys its cached results on the
contents its files had when it read them, would not re-run a test for a
change of mode alone.

**When a sentence has two readings** (the [run contract](reference.md#run-contract)
again), `exNN_output` grades only what both readings require, and the other
reading runs as a target of its own, above `basic`: for a shell exercise, at
`strict`, `exNN_literal`, `exNN_regular` or `exNN_newest_first`, each named
for the reading it holds, and for a C function `exNN_<name>_output` (C 07's
`ex04_base_to_space_output`, C 11's `ex04_reverse_output`, C 12's
`ex11_element_output`, Reloaded's `ex26_returns_one_output`), at the level its
BUILD file gives it. Where a generated corpus is what tells the readings
apart, the `diff` layer's corpus holds only the cases they agree on, and the
others run as `exNN_readings`, at `strict` (C 02's `ex09_readings`, BSQ's and
Rush 01's `ex00_readings`) -- or at `robust`, where the subject's words do not
reach those cases at all, so that what the reference does with them is a
convention of this repo's, not a reading (C 11's `ex06_readings` and C 06's
`ex03_high_bytes_argv_diff`: the order of a byte above `0x7f` under "ASCII
order"). A correct
answer under either reading is never red at `basic`, and no `basic` hint names
a reading: only the target that holds one states it, in its own hint and its
row in reference.md, as this harness's reading and never the subject's
(AGENTS.md §2). The exercises that have
one, and what each level reads, are listed in reference.md: the shell ones
under [Shell turn-ins](reference.md#shell-turn-ins), the C ones among the
[targets raised above their layer](reference.md#targets-raised-above-their-layer)
and the corpora's in the [target names](reference.md#target-names)' `_readings` row.

**The lint.** `exNN_norm` only asks whether `/bin/sh` can parse the
generator. shellcheck reads it in `exNN_lint`, at `robust`, and where the
turn-in is itself a script, reads that too: where `/bin/sh` runs it, the
constructs POSIX leaves undefined in `exNN_posix`, at `strict`, and its
other warnings in `exNN_lint`. Which finding sits where, and why, is in
[reference.md](reference.md#shell-turn-ins).

**Writing the check for a shell exercise.** A fixture that holds only what
the subject's example shows passes the slips students actually make: Shell
00's fixtures were fixed one at a time (findings 009, 010, 014, 015, 021 and
022) before each held what tells the readings and the common slips apart.
So a fixture holds the look-alikes as well as the targets -- a name that
only looks like the one asked for, a tracked file a pattern matches, an
entry of the other kind, two timestamps that disagree -- and nothing the
subject leaves open is graded at `basic`: where a sentence has two
readings, `exNN_output` checks what every reading agrees on and one reading
is a check script of its own in `shell_exercise`'s `readings` (`literal.sh`,
`regular.sh`, `newest_first.sh`), at `strict`. Then each slip the fixture is there to catch is
proven once, by a selftest arm whose invented toy makes exactly that slip
(tools/tests/selftest.sh): a fixture never run against the mistake it is for
is a guess about it.

**A C function's open case** is split the same way, by `c_function`'s
`readings`: `exNN_output` holds only the cases every reading agrees on, and
each case the subject leaves open is a `main` of its own over the same files
(`tests/exNN/<main>`), run as `exNN_<name>_output` at the level its case
names -- `strict` to `complete`, never `basic`. Only the output layer runs a
reading. Each one is in `tools/defs.bzl`'s `_RAISED`, with a row in
[reference.md](reference.md#targets-raised-above-their-layer) saying which
reading it takes (C 07 ex04's `ex04_base_to_space_output` is one).
