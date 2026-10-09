# Why it is built this way

**For:** anyone changing the harness, or wondering why a test behaves as it does.

This page holds only the principles that are about the **whole repo**. Anything
that explains one file lives in that file — a macro's reasoning is in its
docstring in `tools/defs.bzl`, a runner's is in its header, an exercise's is in
its module `BUILD.bazel`, and the environment's is in `.bazelrc`. That is
deliberate: the person who needs to know why is the one editing the thing, and
prose kept away from its subject goes stale without anyone noticing.

What these principles ask of a project or a layer being added, item by item and
in the order it meets them, is [new-project.md](new-project.md).

---

## A check whose answer depends on which computer you sat at is not a check

A campus machine is not yours to configure. Different boxes carry different tool
versions, and one may shadow another with something from a package manager. So
every tool whose behaviour *decides a verdict* is fetched by Bazel and pinned by
SHA-256, at campus's exact build — and **nothing falls back to a copy on your
`PATH`**. A missing pinned tool fails the layer loudly rather than passing it
quietly.

Where a tool is deliberately *not* pinned, the reason is recorded beside the pin
in `tools/pins.tsv`, not argued again here.

Pinning makes a verdict reproducible; it does not make it readable. A pinned tool
reports at its own level — `nm` names `__errno_location` where the student wrote
`errno`, norminette keeps only its last `-R` flag — so every verdict is
translated back to what the student wrote and says how to reproduce it by hand,
with the pinned version and the flags that actually took effect.

The same principle decides the shell. `/bin/sh` is **not** pinned, because the
question is whether the *usage* is portable rather than whether the binary is
ours — and that is enforced from two sides: shellcheck refuses a bashism
statically, and `//tools/tests:selftest_bash` replays every self-test arm under a
second shell.

## A layer that reports OK while checking nothing is the worst defect class here

The suite's whole value is being trustable, so a false green outranks every other
kind of bug. Two mechanisms exist for it, and both are non-negotiable when adding
a layer:

- **`//tools/tests:selftest`** feeds each runner a known-bad input that *must* go
  red. Add the arm in the same commit as the layer. `want_red` insists on exit
  **1**, never merely non-zero: 2 means the harness broke and nothing ran, and
  the two must never be confused. It runs in shards, each running the arms of
  some sections and the plain code of all of them, so an arm may rely on any
  fixture made in plain code above it, and never on what another section's
  arm left behind (`selftest.sh`, "SHARDS").
- **`NO_SKIP=1`** forces every conditional gate open. A layer that skips
  everywhere is indistinguishable from one that passes everywhere, and this is
  the only thing that tells them apart. A skip that ignores `NO_SKIP` is worse
  than no gate at all.

Its sibling is a verdict that says more than the runner established. An OK line,
or a footer that names a cause, is computed from what actually ran — the files,
the counts, the flags that took effect — and names a cause only when that cause
was tested. A norm layer once printed "the Norm is satisfied" over a file
norminette had failed, because the pinned version reports only its last file's
status; a 32-bit layer blamed the size of `long` for a build that never linked. A
footer that names a cause gets a selftest arm where the premise is false and the
footer must not appear.

## Do not let a layer invent a requirement

If the subject does not ask for something, a test that demands it fails correct
work. Where a layer asserts a behaviour, the sentence that requires it is quoted
at the call site — and if you cannot find a sentence to quote, that is the
answer.

The quote is written once, at the call site, and a runner never words a
subject's sentence itself: not a shared runner, which speaks to every project
that calls it, and not one only one project calls either (the owner's ruling,
2026-10-09). Rush 01's and BSQ's runners restated their subject in words of
their own, with no page beside them; they now print the sentence their
`BUILD.bazel` hands them (`runner_quotes()`).

The same rule governs file lists: pinning a filename the subject leaves free
invents a requirement, which is why several modules glob their sources instead.

Where a rule is genuinely wanted but is *ours* rather than the subject's, it goes
in at level 3 or 4 — informative, never in the beginner's path or the submit
gate — and says at the call site whose decision it was.

Four consequences, each learned from a correct answer the harness failed:

- **An ambiguous sentence is read at `strict`, never at `basic`.** The harness
  picks one reading, writes it once, and every fixture, reference arm and hint
  for that exercise follows it. `basic` keeps only the cases every reading
  agrees on, and the reading is a target of its own: `readings` on a
  `shell_exercise` (a check script, listed in
  [reference.md](reference.md#shell-turn-ins)) or a `c_function` (a harness
  and fixture, listed in
  [reference.md](reference.md#targets-raised-above-their-layer)). A case the
  sentence does not reach is not an ambiguity of it: "ASCII order" gives no
  place to a byte above `0x7f`, so the order a reference gives one is a
  convention of this repo's, at `robust`, where "alphanumeric" reaches every
  byte and whether one above `0x7f` is in the class is a reading, at
  `strict`.
- **What the subject calls an error is an error.** No layer, at any level, may
  require a program to accept an input its subject says must be refused, and a
  status or message the subject names is required at `basic`.
- **The questions every exercise raises are decided once**, in
  [reference.md](reference.md#run-contract) — exit status, stderr, the execute
  bit — and enforced by shared helpers, never re-decided by each check.
- **An open question is not an untested one.** Where the subject leaves the
  output open, test what every reading agrees on: no signal, no hang, an output
  from the allowed set.

Each project is also graded alone: a contract fuzzed in another module is not
covered in this one, because each is its own Vogsphere repository.

## Build from the subject, and prove it on more than two trees

The answers in a clone — whoever wrote them — are one reading of the subject, in
one layout. A harness developed against them learns that reading as the rules:
the student-test run (a stranger's answers, written from the subjects alone)
found a Makefile exercise that demanded the answer's own source folders, a
header the grader supplies required from the student, all five rush variants
required of a team that owes one, and a layout the subject allows breaking the
build. Every one of them was green on the answers the harness grew up with.

So the harness is written from the subject — where the turn-in goes, which files,
which the grader supplies — and those facts are written once per project, in the
subject contract its BUILD file opens with
([reference.md](reference.md#the-subject-contract)): every macro reads them
there, because the copies typed at each call site were the ones that disagreed.
And every check is proven on more than the stubs and one correct answer: a
broken tree (a compile error, a stray `main`, a missing file), every layout the
subject allows, and every layout it does not -- a header moved to a folder the
grader's compile line never searches must be red in every layer, not only in
the one that happens to build the program. What a layer compiles with is
the grader's: its files, its include path, the directory each recipe of a
Makefile runs in. `deliverable/` is the root of the repository that is turned
in: a subject's "Turn-in directory" line puts files under it, and a subject
with no such line turns in at `deliverable/` itself.

A fixture is built to tell answers apart. One that a correct answer and a
common slip pass alike tests neither, and the student-test run found them
in every shell module: midLS's entries were named in the order of their
dates, so a listing by name read as one by date; find_sh's tree had no
directory named like a script, clean's no name that only looks like a
backup; C 01 ex03's out-parameters started at the value three of its rows
expect. So a fixture holds the look-alikes -- the near-miss name, the
second key whose order differs, the starting value no row expects (two
starting values, in a corpus, which can expect any) -- that
separate a correct answer from each slip, and from each reading the
subject leaves open, which runs as a target of its own (`readings`). A
fixture also sets keys nobody wrote down: the order its files are made and
touched in is their creation and change times' order, and midLS's reading
set the access dates last in the very order it expects. Each
slip a fixture is there to catch is proven by a selftest arm over a toy
that makes it -- a turn-in that prints fixed names, a body that stores
nothing -- never over an answer; where no fixture can hold the input,
an //oracle reference judges it instead.

A subject sentence about how the work is done, which no output shows, is read
where a layer can read it — *recursive*, *iterative* and *a fixed-size array*
are the `method` layer's — and listed as untested where none can — do-op's
*array of pointers to function* — in one table
([reference.md](reference.md#sentences-about-how)), never dropped silently.

## A rule about the whole module is checked on the whole module

A rule every test of a module keeps -- its exercise's tag, one layer, the
level that layer gives it -- was once checked inside the helper that emitted
most of them, so the tests written by hand escaped it: twelve were in no
per-exercise suite, and the manual ones were in no suite and no document. So
such a rule is checked once the whole module is declared: `c_levels()` audits
it (a finalizer, `tools/defs.bzl`'s `_audit_problems`), and a module that
breaks one does not load -- on its author's machine, before anyone runs it.
Every test is written through one path that derives what the audit reads
(`hand_test()`, or a macro), and what a reader looks a target up in
(docs/reference.md's target names, raised and manual tables) is checked
against what the audit reads. A case dict is held the same way: its keys are
declared per shape, and one a shape does not take fails where it is written
instead of doing nothing. None of it can be tripped by what a student writes:
a folder of theirs that is no exercise gets a test saying so, never a module
that will not load.

## What every runner has to get right is written once

Every runner that runs a student's program answers the same questions: how
long the run may take, how it ended, what to do when Bazel stops the test,
how to show a byte a terminal would hide, how to cut long output, which hints
to print. Answered in each runner, the answers drifted -- one runner ran the
program with no time limit and died as a bare `TIMEOUT` with an empty log,
thirty traps cleaned up on `SIGTERM` and then carried on without their files,
three called a status of 128 a crash, six renderings showed one byte six
ways (and in the output table a `$` in the text read as a line end), one
printed a clue file's maintainer comments as hints. `tools/runner_lib.sh`
is the one copy, and `//tools:conventions` refuses the hand-rolled forms, so a
runner written for the next project inherits the answers instead of
re-deciding them.

Two of those answers are principles of their own. **A run's time comes out of
the test's**: a runner stops a program a few seconds before Bazel would stop
the runner, and says which case it was on, because a test Bazel kills says
nothing at all. **How a run ended is read, never guessed**: a shell reports a
death by signal N as the status 128+N, which a program can also return, so
every run goes through `tools/exit_status`, which asks `waitpid()`.

The rules that hold runners to the library key on **what a runner is and
where a command is, never on how today's are spelled**. A script a test names
in its srcs is a runner: it sources the library, or says in one line that it
runs no student code. A program a runner starts by path -- `$BIN`, `$PROG`,
`$WORK/probe`, behind `env` or `valgrind` -- is the student's until the file
declares it a harness tool. The first versions keyed on an option spelled
`--bin`, a trap at the start of a line, `head -N`, a variable named `CLUES`,
and a probe runner written any other way passed every one of them. A lint
meant for projects not written yet is tested on the shapes those projects
might take, not only on the ones the repo already has.

## Feedback names the bug class, never the algorithm

Everything a student can read — a failure message, a `clues.tsv` line, a report —
is written for someone with far less context than the author. It names the
concept, the bug class and the subject section. It does not name the algorithm,
and it never contains an answer.

The rule for a differential hint is the sharpest form of this: name a **family**
of failing inputs, then let the reader ask what that family has in common.
*"Only sizes with a 1 in them"* is a place to look; *"handle n == 1 specially"*
is the answer, and would make the layer useless to the person it exists for.

A hint that can fire at **first red** is a question about a concept: never an
ordered list of steps, and never a fix stated outright. First red is the run on
an untouched stub, before the student has tried anything, and these hints reach
it: every `clues.tsv` row with no case label, since it fires on any failure;
the first three rows of a file, since a stub fails nearly every case and three
are shown; every row of a program's clue file, since a program case is a
test of its own and the stub fails it, so a row keyed to the case, to a line
of its output or to its memory arm fires wherever it sits in the file; and
every row of a shell exercise's file, which runs as a single case, so every
row fires at once. A list of steps written as advice (*first this, then that*)
is still the exercise's outline, handed over at the one moment the exercise
asks the student to find it. Ask which man page, which sentence of the subject,
what happens when, and leave the order to the student.

No hint may settle a case the subject leaves open, at first red or later: it
asks which sentence decides, and may name the target that holds one reading
of it. Only that target, at strict, states the reading it tests: in its own
hint and its own row of reference.md, and always as "this harness's reading",
never as the subject's. No basic hint, clue or doc names it (the owner's
ruling of 2026-10-03). That rule covers all shipped teaching prose, not only
clues (AGENTS.md §2, *Shipped teaching prose*), and a project's BUILD.bazel
ships with its comments: a comment there names the target that holds a
reading, never the reading, and never where the oracle's source is (the
owner's ruling of 2026-10-09). One label is what lets a machine hold part of
it: `//tools:conventions` refuses a reading named by another name, the label
in a hint a test other than a strict one prints, and the label or a path of
`oracle/src` in a project's BUILD comment; a reading stated in other words is
still the author's to catch.

Nor does a hint about a value that does not fit name a type to widen into:
C promises `long` only 32 bits, and the `ilp32` layer fails the `long` a
student reaches for on the strength of such a hint. It asks whether the value
has to be formed at all, and points at what C promises about each type's
width (testing.md, under `ilp32`); `//tools:conventions` refuses the forms
that shipped ("a wider type", "the accumulator's type").

The conventions check flags the marked forms of a step list (numbered steps,
sequencing words, an instruction chained with "then") and any first-red row
with no question in it. An outline with no marker, or a statement wrapped
around one question, gets past it, so keeping to the rule is still the
author's job.

## The levels exist so the suite fits the person running it

A beginner must not be drowned in seventeen layers of red; someone further along
must not be capped at what the grader happens to check. So layers are
levelled, most people live at `basic`, and the rest is opt-in. Place a new layer
at the level that matches **who needs it**: one that informs but never gates
belongs at the top of the ladder, not in a beginner's path.

## Measure the axis rather than asserting the claim

"Better" is a question, not a fact, and the axes conflict — fewer instructions,
fewer syscalls, fewer allocations, fewer lines, fewer branches, easier to be sure
it is correct. Where the repo can measure an axis it shows the number instead of
declaring a winner; that is what the `perf` and `cycles` layers are for.

The same discipline applies to the harness's own claims. A budget is a number,
never a reference implementation — source code would tell you the answer, which
no test here may do. Nor may a test's output say where one is: `oracle/` solves
most exercises, and a student finds it through its README, which says first what
reading it costs, never through a log (`tools/conventions.sh` checks the runners).

## Two audiences, always

One is whoever is working in this clone. The other is everyone who clones the
`template` branch afterwards and starts their own Piscine from it. Weigh a
decision against what it teaches the next person, not only what is convenient
today — and remember that what gets shared is the infrastructure and never the
answers.

The template is the only place the harness meets a tree where *nothing* is
written, which keeps finding real bugs no other run can: a build action that
failed on a stub Makefile once took 27 targets down as "FAILED TO BUILD" instead
of failing them one at a time with clues. So no student's file can break the
build graph, and two rules keep it so. A build action over a student's files
always produces its output: what does not compile or link becomes a stand-in
program that prints the compiler's words and exits with a reserved status
(`tools/standin.sh`), and every runner that runs a program recognises one. And
no turn-in file is ever a literal declared input, nor a glob that must not be
empty: a file a student has not written yet fails the tests that needed it, as
NOT TURNED IN, never the loading of the package. A file NAME no label can
carry ("main (1).c") is left out by the same helpers and reported by the files
layer. `//tools:conventions` checks both, and toy exercises in every broken
state prove them on every run (`//tools/tests:macro_fixtures_test`).

Telling *nothing written yet* from *written and broken* is the same lesson
again: an exercise nobody has started must never read as broken code. The
build's stand-in has two kinds for that reason — code that does not build, and
nothing to build (a stub Makefile compiles nothing) — and `first_red.sh` asks
`stub_check.sh` which one a newcomer is looking at before it says "fix this
first". And the stand-in is only ever the student's: a compiler that was
killed, or a harness file that no file of theirs reaches, fails the build
instead, because a build action that succeeds is cached, and a stand-in cached
over a loaded machine's OOM kill would blame correct code until something
changed. The reverse holds too: a crash is read from the tool's status, or from
the banner its driver prints as a line of its own, never from the student's
text — a line of theirs the compiler quotes, or a Makefile's recipes, may say
"internal compiler error" and is still their code.

The template is the product, so its defaults are a newcomer's. A clone here also
holds 42's downloaded files, local settings and filled-in remotes that a fresh
clone lacks, which is why "green here" is not evidence that the template works.
Per-student and per-team state — Vogsphere URLs, a team's assigned variant, where
Bazel caches — never lives inside a harness file, so an update to the harness
never collides with what someone typed. It lives in a file of its own: untracked
where it belongs to one clone (`.submit-remotes`, `.bazelrc.local`), or tracked
where a team shares it (rush-00's `team.bzl`), in which case the harness ships it
once and never edits it again. And the tree that is tested is the tree
that is pushed.

## Deleting a stale explanation is a fix

A comment that describes a previous version of itself costs a reader more than
silence. If a prohibition, a caveat or a count no longer holds, delete it rather
than annotating it — and prefer a rule the build can check to a number a human
has to remember.

The same goes for facts. State each one once, where it is checked, and point to
it everywhere else: a second copy is a second thing to go stale, and the copies
nobody checked are the ones that drifted.
