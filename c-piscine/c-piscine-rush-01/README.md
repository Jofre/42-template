# rush-01 — the skyscrapers puzzle

What the three rushes share -- how a defense grades a rush, and how a team
works from one clone -- is in [docs/rushes.md](../../docs/rushes.md).

Reads sixteen visibility clues as **one** argument and prints the 4x4 grid of
heights that satisfies them, or `Error`. `write`, `malloc` and `free` allowed,
and the subject compiles it with `cc -Wall -Wextra -Werror -o rush01 *.c` — no
Makefile, and no fixed source filenames. That line also fixes where things may
go: `*.c` is the `.c` files of `ex00/` itself, and no `-I` is passed, so a
header of yours in a subfolder (`includes/name.h`) is found only by
`#include "includes/name.h"`. Every layer here compiles the way that line
does, so a header the evaluator's compile cannot find is red here too.

**This module validates; it does not diff.** The subject asks for "the first
solution you encounter", and 66 of the 438 solvable clue vectors have more than
one correct answer — so an expected-output fixture would fail perfectly correct
programs, grading a search order the subject never fixed. Instead the runner
checks your grid against the puzzle's own rules and says which one you broke:

```
FAULT [clue] column 1 is seen as 4 from the top, but clue 1 asks for 1.
FAULT [latin-row] row 2 holds the height 3 twice.
```

The sweep runs about 970 generated clue vectors:

```sh
bazel test //c-piscine/c-piscine-rush-01:ex00_sweep
```

**The sweep is `basic`.** It asserts nothing but the subject's own rules: any
grid that meets every view passes, and a well-formed input nothing can
satisfy must print Error. It also runs the argument lists a clue string
cannot hold -- no argument, two, and one empty one -- each of which must print
Error; the two are the subject's own example given twice, so a program that
reads one and ignores the other is caught. It waits for the subject's own
example to pass (`ex00_subject_output`), so the first thing you meet is the
one case the subject printed.

**One reading, at `strict`.** "Each element of the string is a number ranging
between '1' and '4'. This is the only acceptable input" leaves open what a
program splitting on blanks, or reading each element as a number, makes of
extra blanks, a tab, `04` or `+4`. `ex00_readings` holds one reading, and
its hints state it, as this harness's reading and never the subject's. It
varies the subject's example one way at a time, and no `basic` target asks
any of it.

**The bonus is graded only if you attempted it.** The subject offers bonus points
for other map sizes up to 9x9. The sweep feeds you those too and reads your
answer to decide what to do with them: print `Error` and it passes — that is the
correct answer for a 4x4-only program, and the run still proves you neither crash
nor hang. Print a grid and you reached for the bonus, so the grid is judged in
full — and since the sweep is `basic`, a wrong one fails `basic` and the submit
gate. That is not the bonus being required: a wrong grid is wrong under every
reading of the subject (the mandatory part wants `Error` there, the bonus a
grid that meets every view), so nothing about it is open. A bonus-size board that runs out of time is counted neither way, since
slowness on an optional part is not a verdict; but after three of them the
other bonus sizes are not tried, and the report says how many it skipped. The
4x4 boards are always all judged. To be held to it instead of merely tolerated,
run the manual target below, where `Error` no longer passes:

```sh
bazel test //c-piscine/c-piscine-rush-01:ex00_bonus_9x9
```

Rectangular boards are outside the subject: its one clue string cannot say which
rectangle it describes, and any other input "must be considered an error", so
nothing here asks for one.
