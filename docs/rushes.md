# The rushes

**For:** a team starting a weekend group project.

Each rush is graded like any other module, but each one's tests are shaped by
something the subject does that no C module does. That shape is what this page
explains; the layers themselves are in [reference.md](reference.md).

---

## rush-00 — the rectangle

`void rush(int x, int y)` plus `ft_putchar`, with `write` as the only allowed
function.

**Five variants, one exercise.** The subject ships five drawings of the same
rectangle (`rush00.c` … `rush04.c`), differing only in the characters at the
corners and walls. Your team owes exactly one — the first letter of the *team
leader's* login (A = 1 … Z = 26) modulo 5, a rule 42 states in the group note —
and the rest are bonus.

Say which at the top of `c-piscine-rush-00/BUILD.bazel`. It ships with all five
listed, so narrowing it to yours is the first thing to do:

```python
ASSIGNED = ["00"]      # your variant(s); everything else is bonus
```

Only variants in `ASSIGNED` are gated. Every other one is tagged `manual`, so
untouched stubs can never block your submission — but you can still work on one:

```sh
bazel test //c-piscine-rush-00:ex00_rush03            # every layer, one variant
bazel test //c-piscine-rush-00:ex00_rush03_output     # just the labelled table
```

**Doing all five is worth it, and not only for the points.** The variants are not
equally revealing: `rush00` uses the same character at all four corners, so it
*cannot* fail when the corners are mixed up; `rush01`…`rush04` use one character
for both walls, so they cannot fail when horizontal and vertical are swapped.
Measured, not guessed: a "bottom corner wins over top corner" bug passes every
test on `rush00` and `rush03`, and is caught by `rush01`, `rush02` and `rush04`.
The five share one implementation shape, so the other four are mostly a table of
characters away.

**The output is a picture, so the tables escape it** — each case on one line with
`\n` marking every line ending, so a trailing space or a missing final newline is
*visible* instead of hiding in a wall of ASCII art:

```
 CASE               | EXPECTED         | GOT              | STATUS
 1x1 single cell    | o\n              | o\no\n           | FAIL <
```

Sizes the subject leaves undefined (`x` or `y` non-positive) are **never**
diffed: the requirement there is only "must never crash or hang", so those layers
assert termination and a clean sanitizer report, not bytes.

Fixtures are generated, never hand-edited:

```sh
sh c-piscine-rush-00/tests/ex00/regen.sh
```

---

## rush-01 — the skyscrapers puzzle

Reads sixteen visibility clues as **one** argument and prints the 4x4 grid of
heights that satisfies them, or `Error`. `write`, `malloc` and `free` allowed,
and the subject compiles it with `cc -Wall -Wextra -Werror -o rush01 *.c` — no
Makefile, and no fixed source filenames.

**This module validates; it does not diff.** The subject asks for "the first
solution you encounter", and 66 of the 438 solvable clue vectors have more than
one correct answer — so an expected-output fixture would fail perfectly correct
programs, grading a search order the subject never fixed. Instead the runner
checks your grid against the puzzle's own rules and says which one you broke:

```
FAULT [clue] column 1 is seen as 4 from the top, but clue 1 asks for 1.
FAULT [latin-row] row 2 holds the height 3 twice.
```

```sh
bazel test //c-piscine-rush-01:ex00_sweep     # ~970 generated clue vectors
```

**The bonus is graded only if you attempted it.** The subject offers bonus points
for other map sizes up to 9x9. The sweep feeds you those too and reads your
answer to decide what to do with them: print `Error` and it passes — that is the
correct answer for a 4x4-only program, and the run still proves you neither crash
nor hang. Print a grid and you reached for the bonus, so the grid is judged in
full. To be held to it instead of merely tolerated:

```sh
bazel test //c-piscine-rush-01:ex00_bonus_9x9    # manual: Error no longer passes
```

Rectangular boards are an extension **this repo defines, not the subject** — a
clue count does not determine (W, H), so a rectangle is unreadable from a bare
list. The opt-in convention and its target are documented in
`c-piscine-rush-01/BUILD.bazel`; it is deliberately not gated, because being
reddened for disagreeing with an invention of ours you never read would not be
fair.

---

## rush-02 — numbers into words

Reads a **dictionary file** and a number, and prints the number written out.

```sh
./rush-02 numbers.dict 42         # forty two
./rush-02 numbers.dict 100000     # one hundred thousand
```

**Two different failures, and telling them apart is half the exercise.** `Error`
is for input that is not a number at all (`10.4`); **`Dict Error`** is for a
number you cannot spell with the dictionary you were given — an entry is missing,
or the file is malformed. Getting it right means never assuming the file has
`five` in it, or that its keys stop where you expect.

**The Makefile is a deliverable here**, as in c-10. `c_make` runs `make fclean`
then `make` and checks that `./rush-02` appears and that `clean` and `fclean` do
what the subject says; `c_program` compiles the sources through Bazel and runs
the argv cases — so a broken Makefile cannot hide behind green output tests, and
a wrong program cannot hide behind a working Makefile. Only `clean` and `fclean`
are required: the subject names those two and never mentions `re` or `all`.

**Name your files whatever you like.** The subject says "a Makefile and all the
necessary files" and fixes no filenames, so nothing here assumes any. Where every
other module knows its sources from the subject, this one asks *your Makefile*:
`make -Bn` prints the recipes the default goal would run without running them,
and every `.c` in them is part of your program by definition.

What it does **not** take from your Makefile is the flags. The same
`-Wall -Wextra -Werror` and the same sanitizers as every other module apply, so a
Makefile missing a flag cannot soften the checks. Whether the Makefile itself is
correct stays `c_make`'s separate question.

If your Makefile builds nothing yet, the run layers **fail** rather than break:
you get a red test explaining there was no program to build, not a build error
taking the module down.

**42 issues its own `numbers.dict`.** Two copies of it are tracked here
(`c-piscine-rush-02/numbers.dict` and the one inside `deliverable/ex00/`),
because the module is turned in with one — they are 42's file, not this repo's,
and `//tools:make_template` strips every `*.dict` so the template branch carries
none. On a fresh clone of the template, download yours and keep it wherever you
like — the path is an argument. The fixtures under
`tests/ex00/fixtures/` are the harness's own dictionaries, written to break a
parser in specific ways: a missing entry, no colon, a malformed key, one whose
words are entirely made up (a program printing English rather than reading the
file fails that one), and one full of odd-but-legal whitespace.
