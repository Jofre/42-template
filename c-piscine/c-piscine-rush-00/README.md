# rush-00 — the rectangle

What the three rushes share -- how a defense grades a rush, and how a team
works from one clone -- is in [docs/rushes.md](../../docs/rushes.md).

`void rush(int x, int y)` plus `ft_putchar`, with `write` as the only allowed
function.

**Five variants, one exercise.** The subject ships five drawings of the same
rectangle (`rush00.c` … `rush04.c`), differing only in the characters at the
corners and walls. Your team owes exactly one — the subject's rule: the first
letter of the *team leader's* login (A = 1 … Z = 26) modulo 5 — and the rest
are bonus.

**Say which in `c-piscine/c-piscine-rush-00/team.bzl`.** It is the one line in
the project a team edits, and it ships with all five listed, so narrowing it to
yours is the first thing to do:

```python
ASSIGNED = ["03"]      # your variant(s); everything else is bonus
```

Then delete the `rush0N.c` stubs you do not owe. The subject's turn-in is three
files, `main.c`, `ft_putchar.c` and your `rush0X.c`, and that is what the files
layer then requires. Only variants in `ASSIGNED` are gated. Every other one is
tagged `manual`, so a stub you kept can never block your submission, and one you
deleted has no targets at all — with one exception, the Norm. The subject says
bonus files "are included in the norm check, and you will receive a score of 0
if there is a norm error", so a `rush0N.c` that is there is normed at `basic`,
whatever `ASSIGNED` says; an untouched stub passes it. You can still work on a
bonus variant: the first line runs every layer of one variant, the second just
its labelled table:

```sh
bazel test //c-piscine/c-piscine-rush-00:ex00_rush03
bazel test //c-piscine/c-piscine-rush-00:ex00_rush03_output
```

Every target a rush does not run by default -- rush-00's bonus variants,
rush-01's `ex00_bonus_9x9`, rush-02's two differentials `ex00_rush02_diff` and
`ex00_rush02_dictfuzz` -- runs with its module's `:manual` suite
(`bazel test //c-piscine/c-piscine-rush-02:manual`), and
[reference.md](../../docs/reference.md#manual-targets) says why each is left out.

**Every teammate's clone needs the same `team.bzl`.** It sits outside
`deliverable/`, so it never reaches the turned-in repository. A teammate whose
clone still lists all five has four variants gated that the team does not owe:
red while their stubs are there, and red as not turned in once they are deleted.
Agree on the line and make the same edit in every clone.

**Bonus files travel with the turn-in.** The subject invites other versions
"with their corresponding names", so a finished bonus variant sits in
`deliverable/ex00/` and `//tools:submit` pushes it. Two consequences: an
unfinished stub you keep is pushed too, and a folder holding several
`rush0N.c` cannot be built with `cc *.c`, since each one defines `rush`: the
subject compiles its three files together.

**No header ships.** The subject names three files, and the template gives you
nothing else. If your team wants one (the Norm keeps a struct out of a `.c`
file), any `.h` beside the sources is accepted, and so is any other `.c` --
a bonus that switches versions with an argument needs files of its own. Every
one of them is normed at basic, as the subject says bonus files are
(`ex00_extra_norm` for a `.c` that is none of the named ones). Anything else
fails the `files` layer: "You must submit only the files explicitly requested"
(p.15), and a binary or a notes file is not one of them. Either way, each `rush0N.c` may make `rush` visible to
the linker and nothing else: the subject says your main "will be modified
during the defense", so the evaluator may edit or replace `main.c`, and any
other global name can collide with theirs. The `symbols` layer checks
that, and says what to look up when it fails.

**Doing all five is worth it, and not only for the points.** The variants are not
equally revealing: `rush00` uses the same character at all four corners, so it
*cannot* fail when the corners are mixed up; `rush01`…`rush04` use one character
for both walls, so they cannot fail when horizontal and vertical are swapped.
Measured, not guessed: a "bottom corner wins over top corner" bug passes every
test on `rush00` and `rush03`, and is caught by `rush01`, `rush02` and `rush04`.
The five share one implementation shape, so the other four are mostly a table of
characters away.

**What basic holds you to.** The subject's five examples per variant, in the
labelled table (`ex00_rush0N_output`); its defense case, `rush(123, 42)`,
compared in full with the reference's picture (`ex00_rush0N_defense`, "Here is
an example of a test that will be performed"), which reports one row -- the
figures the size makes, and the row and column where your picture first
differs -- never 5208 bytes; sizes up to 400000 on a side that must come back
promptly and, where the size is legal, as `y` lines of `x` characters
(`ex00_rush0N_survive`); and the signature, `void rush(int x, int y)`, whose
types `ex00_rush0N_prototype` checks. "It must take two integer arguments,
named x and y" is checked too, at `strict` (`ex00_rush0N_prototype_names`):
a name changes nothing the program does, and only an evaluator reading your
code can mark it.

**The output is a picture, so this rush's tables escape it** — each case on one
line with `\n` marking every line ending, so a trailing space or a missing final
newline is *visible* instead of hiding in a wall of ASCII art. Rush 00's own test
program does that for every row; the other rushes, like every `output` table, show
the bytes of a failing row only, with `$` at each line end
([testing.md](../../docs/testing.md#reading-a-failure)):

```
 CASE               | EXPECTED         | GOT              | STATUS
 1x1 single cell    | o\n              | o\no\n           | FAIL <
```

Sizes the subject leaves undefined (`x` or `y` non-positive) are **never**
diffed: the requirement there is only "must never crash or hang", so those layers
assert termination and a clean sanitizer report, not bytes.

Fixtures are generated, never hand-edited:

```sh
sh c-piscine/c-piscine-rush-00/tests/ex00/regen.sh
```
