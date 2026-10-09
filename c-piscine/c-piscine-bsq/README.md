# c-piscine-bsq

BSQ, the C Piscine's final project: **one program, `bsq`, built by a Makefile
of yours**, pushed as one Vogsphere repository whose root is `deliverable/`
itself. Its subject has no "Turn-in directory" line, so nothing goes under an
`ex00/`. The harness still names its one exercise `ex00`, so every target is
`ex00_<something>`, and `bazel test //c-piscine/c-piscine-bsq:ex00` runs them
all.

The subject sits beside this file (`en.subject.pdf`, `es.subject.pdf`); a fresh
clone of the public template has a placeholder there instead, saying where to
download the version you are graded against. This page describes the harness
built from version 9.2 of that subject: where yours says otherwise, yours
decides. Your answers are yours to write: see `AGENTS.md` §0 for what an AI
assistant may and may not do here.

## What you turn in

| | |
|---|---|
| where | `deliverable/`, the root of the repository you push |
| what | a `Makefile` and "all the necessary files": every `.c` and `.h` it compiles, wherever the Makefile says (`srcs/` and `includes/` work) |
| the program | `bsq`, built by `make` |
| allowed functions | `open`, `close`, `read`, `write`, `malloc`, `free`, `exit` |

The subject asks for "only the files requested", so `ex00_files` fails on
anything else in the turn-in: a `bsq` a hand-run of `make` left there (delete
it before you submit), a note, a test map, and a `.c` your Makefile never
compiles, which is not one of "the necessary files" (`make -Bn` says which it
compiles; while it compiles nothing yet, no `.c` is judged that way).

## A group project

"Each member of the group must be fully aware of all the details of the
project. [...] This understanding may be verified during the evaluation." The
subject has it graded twice: by the Moulinette, and at a defense where "only
the work inside your repository will be evaluated". So BSQ is pushed as a rush
is: one repository for the team, whose work is brought together in one clone,
from which one member submits. The rules for that are in
[docs/rushes.md, "Working as a team"](../../docs/rushes.md#working-as-a-team),
and they hold here too.

One more, about the 42 header: it names its author, so each member stamps
their own files. `bazel run //tools:reset_headers` with no argument re-stamps
every deliverable in the tree with the login of whoever runs it, so in a clone
that holds the team's work, give it your own files only:

```sh
bazel run //tools:reset_headers -- c-piscine/c-piscine-bsq/deliverable/<your file>
```

## How the tests are built

Two halves, so that neither can hide the other.

**Your Makefile** is `ex00_build`'s, at `basic`. It runs `make` in a copy of
your turn-in and checks what the subject says of it: a bare `make` builds
`bsq`; every command it runs to compile a `.c` uses `cc` with `-Wall -Wextra
-Werror` ("Your program must compile using cc with the following flags"); and a
second `make` has nothing left to do ("Your Makefile must not relink"). The
subject names no rule beyond that, so no `clean`, `fclean` or `re` is asked
for. `ex00_build_wildcards` (strict) plants a decoy source and a foreign object
for the Norm's "no \*.c, no \*.o", which the subject does not quote, and
`ex00_build_exit` (robust) judges how each run of `make` exits.

**Your program** is built by Bazel, not by your Makefile's recipes. The run
layers ask `make -Bn` which sources and which `-I` folders the default goal
would compile, and build `bsq` from exactly those, with the harness's own
flags and sanitizers. So a Makefile that leaves out a source, or forgets an
`-I`, is red in the run layers as well as in `ex00_build`, and one that leaves
out a flag cannot soften them. It is the same build as Rush 02's,
[described in docs/rushes.md](../../docs/rushes.md#rush-02--numbers-into-words).
Until your Makefile compiles something, there is no program: every run layer
fails saying so, rather than breaking the build.

`ex00_norm`, `ex00_compile_clang`, `ex00_compile_gcc` and `ex00_forbidden` read
every `.c` and `.h` of the turn-in, subfolders included.

### The named cases

Each case of the `c_program` call in `BUILD.bazel` is a test of its own,
`ex00_<case>_output` at `basic`, with arms of its own: `_asan` (robust),
`_valgrind` (strict: the subject allows `malloc`), and, on a case whose map is
valid under every reading, `_exit` (robust), which fails a non-zero return
where the subject names no status (the
[Run contract](../../docs/reference.md#run-contract)). The cases:

- the subject's own example, as an argument (`subject_example`) and on
  standard input (`stdin_map`), and small maps around it (`one_cell`,
  `no_empty_cell`, and `tall_map`, twenty rows);
- one rule per case, of the subject's "Definition of a valid file" or of what
  it says the first line holds (the number of lines on the map), each broken
  alone and late in its file (`dup_chars`, `ragged_line`, `undeclared_char`,
  `count_zero`, `count_short`, `nonprintable_char`, `zero_width`), and the
  characters the subject says a first line may use (`space_char`,
  `digit_chars`);
- the subject's rule for two squares of the same size (`tie_top_first`);
- several files in one run (`two_maps`, `error_then_map`), a name no file has
  (`missing_alone`, `map_then_missing`, `missing_then_map`), and an invalid map
  on standard input (`stdin_invalid`);
- one case the subject leaves open, `no_final_newline` (below).

Every file a case reads, and every output it expects, is written by
`//oracle`'s reference (`oracle bsq_fixtures`): `ex00_oracle_fixtures`
(complete) fails when one was edited by hand, and `ex00_reference_cases`
(complete) runs every case with the reference in your program's place. Neither
runs anything of yours.

### The corpora

Generated maps, compared with the reference's answer map by map. Each is one
target, plus its twins under the memory checkers: `<stem>_diff_asan` (robust),
every map on the ASan build, and `<stem>_valgrind` (strict), 25 of them under
memcheck. The big maps have no memcheck twin, at memcheck's 20 to 50 times.

| stem | level | what it replays |
|---|---|---|
| `ex00_bsq` (the plain target is `ex00_bsq_diff`) | strict | 120 maps of `bsq_mixed`, valid and invalid interleaved, one per run, named as an argument |
| `ex00_bsq_stdin` | strict | 60 maps of the same generator, each on standard input |
| `ex00_bsq_multi` | strict | 40 maps of it, three per run: the one target that checks the empty line between two outputs |
| `ex00_readings` | strict | the forms the subject leaves open, under one reading, which its hints state (below) |
| `ex00_bsq_long`, `ex00_bsq_long_stdin` | basic | three maps past every capacity a program might pick (a line of 70000 cells, 70000 lines, a 300 x 300 map), whose biggest square is one cell at most: every correct program finishes them |
| `ex00_bsq_big`, `ex00_bsq_big_stdin` | strict | four maps where the method matters (a million cells, ten thousand lines of a hundred, a million cells with three obstacles) |

**Every corpus waits for the example.** While `ex00_subject_example_output` is
red, each target above says SKIP and Bazel shows it PASSED, since a corpus run
over a program that fails the subject's own example only repeats that red.
That output test's red log lists every target that waits for it, and
`--test_env=NO_SKIP=1` runs them anyway.

**A time limit is a guard, never a deadline.** The subject sets no time
limit, so none of these fails a program for being slow: a map of the corpora
gets `BSQ_TIMEOUT` (10 s), one of the long maps 280 s and one of the big maps
210 s, after which it is reported as DID NOT FINISH -- an infinite loop, or
too slow -- and counted apart from a wrong answer. That is why the big maps
sit at `strict`.

**Running out of memory.** `ex00_program_allocfail` and
`ex00_stdin_map_program_allocfail` (robust) run the example, as an argument
and on standard input, refusing one of your `malloc` calls per run. They ask
only that the program end by itself, in time, with bounded output: no message
and no status. No grader at 42 refuses a program an allocation, so this is the
repo's rigour, not the subject's.

## When a case fails, run it again

A named case's log opens with the command it ran, `RAN: ...`: run that line
from the repository root, once `bazel test` has built the program
([testing.md, "Reading a failure"](../../docs/testing.md#reading-a-failure)).
To see what your own build does with it, `make` in `deliverable/` and hand
that `bsq` the same file.

A corpus target prints each failing map whole -- every byte visible, what was
expected and what came out -- and keeps the map in
`bazel-testlogs/c-piscine/c-piscine-bsq/<target>/test.outputs/`, with the line
that replays it (`replay: ./bsq case-17.map`). Run that line in that folder, with
your program's path in place of `./bsq`: the harness's build of it is
`bazel-bin/c-piscine/c-piscine-bsq/ex00_bin`. The report prints the first 40
failing maps and counts the rest; all of them are in that folder's
`differences.txt`.

## Settings

Each reaches a test only through `--test_env=NAME=VALUE`; none needs setting
for an ordinary run. The full table is in
[reference.md, "Environment variables"](../../docs/reference.md#environment-variables).

| variable | default | does |
|---|---|---|
| `BSQ_TIMEOUT` | `10` | seconds one map of a corpus gets |
| `DIFF_TIMEOUT` | `30` | seconds one named case gets |
| `DIFF_MAX_ROWS` | `40` | how many failing maps a corpus report prints; `0` prints all |
| `CLUE_MODE` | first 3 hints | `all` prints every hint that fires |
| `VALGRIND_FDS` | unset | `lax` turns a descriptor left open into a note |
| `NO_SKIP` | `0` | `1` runs every target that waits for the example |

The hints are in [`tests/ex00/clues.tsv`](tests/ex00/clues.tsv), each row
keyed to the cases it is about.

## What the subject leaves open

These are questions the subject answers twice or not at all. No `basic` test
holds you to an answer: it checks only what every reading agrees on. Decide
each one with your team, and be ready to say at the evaluation which sentence
you read and how.

- **A last row with no newline after it.** "Lines are separated by the usual
  newline character" says what is between lines. At `basic`,
  `ex00_no_final_newline_output` accepts either verdict a reading can give,
  and checks what both agree on: every line your program prints ends with a
  newline, and it neither crashes nor hangs. At `strict`, `ex00_readings`
  holds one reading; its hints say which, as this harness's reading and never
  the subject's.
- **How the number of lines is written.** "The first line must start with a
  valid positive number" does not say whether `09`, `+9`, ` 9` or `9 ` is one.
  At `basic`, no case and no corpus map holds such a form. At `strict`,
  `ex00_readings` holds one reading, its hints saying which.
- **The "full" character inside the map.** The subject describes the map as
  "lines containing 'empty' characters and 'obstacle' characters", and its
  validity list says "The characters on the map can only be those introduced
  in the first line", which are three. No test holds a map body with the full
  character in it, in either direction.
- **More rows than the first line announces.** A file with fewer rows does
  not hold the map it promises; for more, the subject does not say. No test
  holds one, in either direction.
- **A byte above `0x7f` among the three characters.** Whether it is
  "printable" depends on the locale. No test holds one.
- **Exit status and standard error.** The subject names neither. No case
  compares standard error: what your program writes there is shown beside a
  failing case, never graded. No `basic` test judges a status; on a case whose
  map is valid under every reading, `_exit` (robust) fails a non-zero return,
  this repo's rule and not the subject's.

Not covered yet: a directory, or a file your program may not read, named as an
argument. The second would have to be made while the test runs, which a
sandbox may not allow.
