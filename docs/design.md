# Why it is built this way

**For:** anyone changing the harness, or wondering why a test behaves as it does.

This page holds only the principles that are about the **whole repo**. Anything
that explains one file lives in that file — a macro's reasoning is in its
docstring in `tools/defs.bzl`, a runner's is in its header, an exercise's is in
its module `BUILD.bazel`, and the environment's is in `.bazelrc`. That is
deliberate: the person who needs to know why is the one editing the thing, and
prose kept away from its subject goes stale without anyone noticing.

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
  the two must never be confused.
- **`NO_SKIP=1`** forces every conditional gate open. A layer that skips
  everywhere is indistinguishable from one that passes everywhere, and this is
  the only thing that tells them apart. A skip that ignores `NO_SKIP` is worse
  than no gate at all.

## Do not let a layer invent a requirement

If the subject does not ask for something, a test that demands it fails correct
work. Where a layer asserts a behaviour, the sentence that requires it is quoted
at the call site — and if you cannot find a sentence to quote, that is the
answer.

The same rule governs file lists: pinning a filename the subject leaves free
invents a requirement, which is why several modules glob their sources instead.

Where a rule is genuinely wanted but is *ours* rather than the subject's, it goes
in at level 3 or 4 — informative, never in the beginner's path or the submit
gate — and says at the call site whose decision it was.

## Feedback names the bug class, never the algorithm

Everything a student can read — a failure message, a `clues.tsv` line, a report —
is written for someone with far less context than the author. It names the
concept, the bug class and the subject section. It does not name the algorithm,
and it never contains an answer.

The rule for a differential hint is the sharpest form of this: name a **family**
of failing inputs, then let the reader ask what that family has in common.
*"Only sizes with a 1 in them"* is a place to look; *"handle n == 1 specially"*
is the answer, and would make the layer useless to the person it exists for.

## The levels exist so the suite fits the person running it

A beginner must not be drowned in seventeen layers of red; someone further along
must not be capped at what the Moulinette happens to check. So layers are
levelled, most people live at `basic`, and the rest is opt-in. Place a new layer
at the level that matches **who needs it**: one that informs but never gates
belongs at the top of the ladder, not in a beginner's path.

## Measure the axis rather than asserting the claim

"Better" is a question, not a fact, and the axes conflict — fewer instructions,
fewer syscalls, fewer allocations, fewer lines, fewer branches, easier to be sure
it is correct. Where the repo can measure an axis it shows the number instead of
declaring a winner; that is what the `perf` and `cycles` layers are for, and why
neither of them can fail a test.

The same discipline applies to the harness's own claims. A budget is a number,
never a reference implementation — source code would tell you the answer, which
no test here may do.

## Two audiences, always

One is whoever is working in this clone. The other is everyone who clones the
`template` branch afterwards and starts their own Piscine from it. Weigh a
decision against what it teaches the next person, not only what is convenient
today — and remember that what gets shared is the infrastructure and never the
answers.

The template is the only place the harness meets a tree where *nothing* is
written, which keeps finding real bugs no other run can: a build action that
failed on a stub Makefile once took 27 targets down as "FAILED TO BUILD" instead
of failing them one at a time with clues. A build action here must always produce
its output — write a program that explains itself and exits 1.

## Deleting a stale explanation is a fix

A comment that describes a previous version of itself costs a reader more than
silence. If a prohibition, a caveat or a count no longer holds, delete it rather
than annotating it — and prefer a rule the build can check to a number a human
has to remember.
