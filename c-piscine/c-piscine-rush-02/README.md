# rush-02 — numbers into words

What the three rushes share -- how a defense grades a rush, and how a team
works from one clone -- is in [docs/rushes.md](../../docs/rushes.md).

Reads a **dictionary file** and a number, and prints the number written out.
The first line below prints forty two, with 42's `numbers.dict`; the second,
one hundred thousand, with the dictionary you name:

```sh
./rush-02 42
./rush-02 numbers.dict 100000
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
all, a crash, or output without end. A run that does not finish within its
time is red too, and never judged: what it would have printed next was not
seen. `ex00_settled_words_diff`'s
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
