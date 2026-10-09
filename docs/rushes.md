# The rushes

**For:** a team starting a weekend group project.

No program grades a rush. Each subject says so ("not verified by a
program"), and the team presents its work at a defense, where evaluators run
it, read it and question every member. The levels mean what they mean
everywhere else, read for that defense: `basic` is what is a KO there -- the
subject's own examples, the case it says the defense will run, the files, the
functions it allows, the Norm -- and `strict` what an evaluator may or may
not look at (a name the subject gives, a reading of a sentence it leaves
open). Every message says "at the defense" rather than naming the
Moulinette: each project's `subject()` contract says who grades it, and the
runners word it from there. Each rush's tests are also shaped by something
the subject does that no C module does. That shape is what this page
explains; the layers themselves are in [reference.md](reference.md).

---

## Working as a team

A rush is pushed to **one** Git repository for the whole team, and only what is
in it is evaluated at the defense. This harness is built around one clone. So:

- **Bring the work together in one clone**, one member's, and run the tests
  there: what is evaluated is the combined turn-in, not anyone's half of it.
- **One member runs `//tools:submit`** from that clone, with the team's URL in
  their `.submit-remotes` ([submitting.md](submitting.md)).
- **Submit never force-pushes.** It fetches the repository and commits on top of
  what is there, so a teammate's push is never erased from the history. But
  what is evaluated is the tip, and a submit makes the tip exactly the
  `deliverable/` it pushes from: a file only a teammate pushed leaves the tip,
  and their version of a shared file is replaced by yours. Submit prints a
  NOTE naming both before it pushes. Two members submitting from two clones
  therefore take turns replacing each other's work; one clone avoids that.
- **Settings that are the team's must agree.** rush-00's `ASSIGNED` (below) is
  in `team.bzl`: in a second clone, set it to the same variant(s).

BSQ, the final project, is a group project too, pushed to one repository for
the whole team, so these rules hold for its team as well; its own page is
[c-piscine/c-piscine-bsq/README.md](../c-piscine/c-piscine-bsq/README.md).

---

## rush-00 — the rectangle

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
bonus variant:

```sh
bazel test //c-piscine/c-piscine-rush-00:ex00_rush03            # every layer, one variant
bazel test //c-piscine/c-piscine-rush-00:ex00_rush03_output     # just the labelled table
```

Every target a rush does not run by default -- rush-00's bonus variants,
rush-01's `ex00_bonus_9x9`, rush-02's two differentials `ex00_rush02_diff` and
`ex00_rush02_dictfuzz` -- runs with its module's `:manual` suite
(`bazel test //c-piscine/c-piscine-rush-02:manual`), and
[reference.md](reference.md#manual-targets) says why each is left out.

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
([testing.md](testing.md#reading-a-failure)):

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

---

## rush-01 — the skyscrapers puzzle

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

```sh
bazel test //c-piscine/c-piscine-rush-01:ex00_sweep     # ~970 generated clue vectors
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
4x4 boards are always all judged. To be held to it instead of merely tolerated:

```sh
bazel test //c-piscine/c-piscine-rush-01:ex00_bonus_9x9    # manual: Error no longer passes
```

Rectangular boards are outside the subject: its one clue string cannot say which
rectangle it describes, and any other input "must be considered an error", so
nothing here asks for one.

---

## rush-02 — numbers into words

Reads a **dictionary file** and a number, and prints the number written out.

```sh
./rush-02 42                      # forty two, with 42's numbers.dict
./rush-02 numbers.dict 100000     # one hundred thousand, with the one you name
```

**Two different failures, and telling them apart is half the exercise.** `Error`
is for input that is not a number at all (`10.4`); **`Dict Error`** is for a
number you cannot spell with the dictionary you were given — an entry is missing,
or the file is malformed. Getting it right means never assuming the file has
`five` in it, or that its keys stop where you expect.

**The Makefile is a deliverable here**, as in c-10. `c_make` runs `make` and
checks that `./rush-02` appears, that every command it runs to compile a `.c`
is `cc` with `-Wall -Wextra -Werror` ("Your program must compile using cc with
the following flags", p.3: read from what `make -n` plans and what a build
runs, never from the Makefile's text), and that `make rush-02` (the subject's `$NAME` rule), `clean`
and `fclean` are there, each from a fully built tree — then the cleaning rules
once more on the tree they just cleaned, since the subject builds with `make
fclean` then `make` on a fresh clone. What `clean` and `fclean` should remove
the subject never says, so that is this repo's convention, checked at `robust`
by `ex00_build_rules`; the Norm's "no \*.c, no \*.o" (a decoy source and an
object of the grader's, which no pattern may catch) is `ex00_build_wildcards`,
at `strict`, since the subject does not say it outright. A rule that does its
job and exits non-zero anyway is a warning in `ex00_build` and a failure in
`ex00_build_exit`, at `robust`: the subject does not say how a rule exits. `c_program` builds the program through Bazel from the sources your
Makefile names (see below), with the harness's own flags, and runs the argv cases —
so a broken Makefile cannot hide behind green output tests, and a wrong program
cannot hide behind a working Makefile. Only `$NAME`, `clean` and `fclean` are
required: the subject names those three and never mentions `re` or `all`.

**Name your files whatever you like, and put them where you like.** The subject
says "a Makefile and all the necessary files" and "You are free to organize your
files as you wish", and fixes no filenames, so nothing here assumes any. Where
every other module knows its sources from the subject, this one asks *your
Makefile*: `make -Bn` prints the recipes the default goal would run without
running them, and every `.c` in them is part of your program by definition --
and a `.c` they never name is not one of "the necessary files": `ex00_files`
fails on it ("Submit only the files requested", p.9). A
`srcs/` and `includes/` layout works: every `.c` and `.h` under
`deliverable/ex00/` is staged, and the include directories are the `-I` your
recipes pass -- for the program and for the compile and forbidden layers
alike, so a Makefile that forgets `-I includes` is red everywhere, as it is
for the evaluator. A library built by a sub-make (`$(MAKE) -C libft`) works
too: its recipes are read from the directory it runs in. A `.c` your recipes
name that is not in the turn-in stops the build there, as it would stop
`make`, and the red tests say which file.

What it does **not** take from your Makefile is the rest of the flags. The same
`-Wall -Wextra -Werror` and the same sanitizers as every other module apply, so a
Makefile missing a flag cannot soften the checks. Whether the Makefile itself is
correct -- its compile commands and its rules -- stays `c_make`'s separate
question. BSQ is built the same way, from its
Makefile at the root of its `deliverable/` (its subject names no turn-in
directory).

If your Makefile builds nothing yet, the run layers **fail** rather than break:
you get a red test explaining there was no program to build, not a build error
taking the module down.

**42 issues its own `numbers.dict`.** It is 42's file, not this repo's, so the
template build strips every `*.dict` outside `tests/`, and the template carries a
`numbers.dict.DOWNLOAD-ME.txt` in the project folder instead. Download yours and
save it as `c-piscine/c-piscine-rush-02/deliverable/ex00/numbers.dict`, beside
your program: the subject's one-argument form uses it without naming it, its own
example greps it in the program's folder, and "all the necessary files" turns
it in. `.gitignore` keeps that copy out of your commits, because it is 42's, and
`//tools:submit` pushes it anyway, because it pushes `deliverable/` as it is on
disk — so every teammate, and every fresh clone, downloads their own. The
two-argument form takes any path. (`tools/resources.tsv` is where the harness
records that path.) Until the file is there, `ex00_numbers_dict_issued` is red,
at `basic`, saying where to get it: a turn-in without it answers `Dict Error`
to the subject's own `./rush-02 42` at the defence.

**Both forms are run, and neither reads your copy.** The one-argument cases
(`ex00_one_arg_*`) run exactly as the subject's transcript does: `./rush-02
42` from a folder holding only the program and a `numbers.dict` — the
harness's own dictionary, copied in under that name. A program that opens
`numbers.dict` where it runs passes, and so does one that looks beside itself.
Each case's log opens with the command it ran and the files that folder held:

```
RAN: ./rush-02 42
     from a folder that holds only:
       rush-02       a copy of bazel-bin/c-piscine/c-piscine-rush-02/ex00_bin
       numbers.dict  a copy of c-piscine/c-piscine-rush-02/tests/ex00/fixtures/ref.dict
```

The two-argument cases (`ex00_dict_arg_*` and the rest) name their dictionary.

**What `basic` asserts is what every reading of the subject agrees on.** The
subject fixes four outputs and no composition rule — whether 101 reads "one
hundred one" or "one hundred and one" is yours to decide, and bonus 1 allows
"-", "," and "and" — so the named cases stay in the transcripts' own shape:
`Error` for an empty, signed or lettered number; `Dict Error` for a broken
line, a tab inside a value, or a unit missing, from the whole number or from
the middle of one; values holding colons and runs of spaces; extra keys shaped
like the ones a number needs. What the subject states in words is held on
numbers every reading spells alike: a teen, round numbers whose leading group
is one word other than one (a million; ten digits, past unsigned int; forty,
at `ref.dict`'s largest scale), and a dictionary whose every value is made up.
Zero or three arguments, a dictionary that does not exist, and a number past
the dictionary's largest scale, are held only to ending by themselves: the
subject names no answer for them. Where
it leaves the answer open, a case accepts either (`0042`, a dictionary with CR
LF line endings), and a `strict` case holds one reading, which its own hints
state as this harness's reading (CR LF line endings, a dictionary that does
not exist, a number past the dictionary's largest scale).

**Two generated corpora gate at `strict`, judging only what no reading
explains.** `ex00_settled_words_diff` sweeps every length up to 42 digits with
`ref.dict`, and past it; `ex00_settled_dicts_diff` hands each case a fresh
dictionary of random values. Both fail `Error` for a valid number, `Dict
Error` from a dictionary that can spell it, words that are not the
dictionary's values (a space, `-`, `,` and `and` may sit between them),
the two shapes the named cases hold at `basic` spelled any other way than by
their keys (a number below 100 with a key of its own is that key's value
alone; a round number like the subject's "one hundred thousand", its group
one key other than one, is the group's value and the scale's -- keys of
`ref.dict` only: whether a key a dictionary adds, such as 45, is used is a
question the subject leaves open), nothing at
all, and a run that does not end by itself. `ex00_settled_words_diff`'s
corpus opens with those shapes. Any other difference from the reference —
your composition, which this target does not judge — is shown, marked
`passes:`, and passes. Neither judges standard error: the
subject names no message for it, so whatever a run writes there is shown
beside a case that fails, and never fails one.

**The whole comparison is yours to run, and never gates.** The same two corpora
compared output for output, every difference shown, are `manual` targets:

```sh
bazel test //c-piscine/c-piscine-rush-02:ex00_rush02_diff --test_output=all
bazel test //c-piscine/c-piscine-rush-02:ex00_rush02_dictfuzz --test_output=all
```

The reference behind them implements one reading of what the subject leaves
open, so a difference there is evidence to read, not a verdict: if every case
differs the same way, that is a convention, not a bug.

The fixtures under `tests/ex00/fixtures/` are the harness's own dictionaries,
each written to test one thing: `ref.dict` (the reference's own entries, up
to duodecillion, 10^39), `custom.dict` (the subject's replaced 20),
`quirks.dict` (blank lines, entries out of order, odd spacing, an extra key),
`decoys.dict` (extra keys shaped like the ones a number needs, before the real
ones), `colon.dict` and `spaced.dict` (colons, and runs of spaces, in a
value), `replaced.dict` (every value made up), and the broken ones —
`nocolon.dict`, `badkey.dict`, `nofive.dict` (a unit missing), `tab.dict` (a
tab inside a value) and `crlf.dict`. Every one,
and every argument file and expected output under `tests/ex00/`, is written
by `//oracle` (`oracle rush02_fixtures`), and `ex00_oracle_fixtures` fails
when a file is not what it writes, or is a dictionary, an argument file or
an expected output it does not write at all (a new case's files typed by
hand); after a change to the reference,
`bazel run //c-piscine/c-piscine-rush-02:ex00_oracle_fixtures -- --write`
rewrites them. `ex00_reference_cases` then runs every case, exactly as its
output test does, with the reference program in the team's place: a case
whose number, dictionary or folder was edited without the file it expects
fails there. Neither runs anything of yours.
