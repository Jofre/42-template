# Libft

Libft, the Common Core's first project: **one library, `libft.a`, of 43
functions, built by a Makefile of yours**, pushed as one Vogsphere repository
whose root is `deliverable/` itself. The subject has no "Turn-in directory"
line, and says "All files must be placed at the root of your repository."
(p.7), so nothing goes under an `ex00/`. The harness still names its one
exercise `ex00`, so every target is `ex00_<something>`, and
`bazel test //cursus/Milestone_0/Libft:ex00` runs them all.

Your peers grade it at the evaluation, and Deepthought may grade it too: "If
Deepthought is assigned to grade your work, it will occur after your
peer-evaluations." (p.3-4). Libft's subject also says its grader judges
memory: "All heap-allocated memory must be properly freed when necessary.
Memory leaks will not be tolerated." and "Your functions should not quit
unexpectedly (segmentation fault, bus error, double free, etc.) except for
undefined behavior." (p.3). So in this project the `valgrind` layer sits at
`basic`, where elsewhere it sits higher
([reference.md, "The four levels"](../../../docs/reference.md#the-four-levels)).

The subject sits beside this file (`en.subject.pdf`, `es.subject.pdf`); a fresh
clone of the public template has a placeholder there instead, saying where to
download the version you are graded against. This page describes the harness
built from version 19.3 of that subject, whose contents list no bonus chapter:
the list functions of Part 3 are part of the mandatory part. Where your
version says otherwise, yours decides. Your answers are yours to write: see
`AGENTS.md` §0 for what an AI assistant may and may not do here.

## What you turn in

| | |
|---|---|
| where | `deliverable/`, the root of the repository you push |
| what | "Makefile, libft.h, ft_\*.c" ("Files to Submit", p.7), and `README.md` ("A README.md file must be provided at the root of your Git repository.", p.17) |
| the library | `libft.a`, built by `make` at the root ("Program Name libft.a", p.7) |
| allowed functions | each function's own box: Part 1's "must not rely on any external functions" (p.8), but `ft_calloc` and `ft_strdup` "will use malloc()"; each box of Parts 2 and 3 has its own "External Function" line (pp.10-16). In all, `malloc`, `free` and `write` |

The subject names `ft_*.c`, a shape, not a list of files: which `ft_*.c` holds
which function is yours to choose, and the harness finds each function in
whichever file defines it. "Submitting unused files is not allowed." (p.7), so
`ex00_files` fails on anything else in the turn-in: a `.c` whose name is not
`ft_*.c`, a note, a test program, and an `ft_*.c` your Makefile does not
compile (`make -Bn` says which it compiles; while it compiles nothing yet, no
`.c` is judged that way). What a hand-run of `make` leaves there (`libft.a`,
the `.o` files) is not judged: build products are left out of what
`ex00_files` reads, and `bazel run //tools:submit` leaves them out of the
push.

Each file starts as a stub:

- `Makefile`: the five rules the subject names, each printing a TODO, and an
  empty list of sources. It builds nothing yet.
- `libft.h`: the `t_list` structure p.14 prints.
- `README.md`: a comment alone. What it must hold is in chapter V of the
  subject.
- one `ft_<name>.c` per function: the signature the subject fixes, `(void)`
  casts and a trivial return.

## How the tests are built

Two kinds of target: those of the **whole library**, once, and those of
**each function**, a member of the library with a suite of its own.

**The whole library.** These read every turned-in file, or build the library
as a whole:

| target | level | what it checks |
|---|---|---|
| `ex00_build` | basic | runs `make` in a copy of your turn-in: `libft.a` is built and holds each of the 43 functions; the rules `libft.a`, `all`, `clean`, `fclean` and `re` are there; every command that compiles a `.c` uses `cc` with `-Wall -Wextra -Werror`, in any order (p.3), and none holds `-std=c99` (p.8); `libft.a` is made by `ar`, and no command runs `libtool` (p.7); a second `make` has nothing left to do ("your Makefile must not perform unnecessary relinking", p.3) |
| `ex00_build_wildcards` | strict | the Norm's "no \*.c, no \*.o", which the subject does not quote: a decoy source beside yours, and an object no rule made beside your objects before each cleaning rule |
| `ex00_build_rules` | robust | what `clean`, `fclean` and `re` do, which the subject does not say (below) |
| `ex00_build_exit` | robust | how each run of `make` exits |
| `ex00_norm` | basic | norminette over every turned-in `.c` and `.h` |
| `ex00_norm_notice`, `ex00_norm_header` | strict | norminette's Notices, and the two rules of the Norm norminette does not read, in `libft.h` |
| `ex00_compile_clang`, `ex00_compile_gcc` | basic | every source clean under both campus compilers at `-Wall -Wextra -Werror` |
| `ex00_prototype` | basic | each of the 43 definitions matches the signature the subject fixes (`tests/ex00/prototype.h`) |
| `ex00_prototype_restrict` | basic | no `restrict` in the prototype of any of the 43 functions, in any file (p.8) |
| `ex00_prototype_names` | strict | the parameter names Parts 2 and 3 print |
| `ex00_layout_prototype` | strict | your header holds the `t_list` p.14 prints: its layout and its names |
| `ex00_prototype_restrict_all`, `ex00_declares_output` | strict | each holds one reading of a sentence the subject leaves open (below) |
| `ex00_forbidden` | basic | only `malloc`, `free` and `write`, the functions some box allows |
| `ex00_forbidden_functions` | basic | each function held to its own box's list: what its own code and every helper it reaches use |
| `ex00_forbidden_through` | strict | holds one reading of the boxes' lists (below) |
| `ex00_globals` | basic | "Declaring global variables is strictly forbidden." (p.7): no variable outside every function, `static` or `const` included |
| `ex00_symbols` | strict | the library's sources export no function but the 43: a helper is `static` |
| `ex00_files` | basic | the files turned in, as above |
| `ex00_readme` | basic | the README chapter V asks for, in whatever language it is written |
| `ex00_readme_wording` | strict | holds one reading of chapter V's words (below) |

**Each function.** The tests of one function are named
`ex00_ft_<name>_<layer>`, and its suite runs them all: while you write
`ft_strlen`, live in one of these two commands:

```sh
42 test Libft ft_strlen
bazel test //cursus/Milestone_0/Libft:ft_strlen
```

The first runs the function's tests at your level (`basic` unless you set
another); the second runs all of them, at every level. `42 test` in
`tests/ex00/ft_strlen/` runs the first too. Everything that is one function's
own is in that folder: its test program (`test_ft_strlen.c`), the table it
must print (`expected.txt`), its hints (`clues.tsv`), and, where it has them,
its corpus reader (`diff_ft_strlen.c`, whose header says what each column of
the corpus is) and its memory probe (`mem_ft_strlen.c`, whose header says what
fault it is aimed at). The targets a function can have:

| target | level | what it checks |
|---|---|---|
| `ex00_ft_<name>_output` | basic | its table: the test program's labelled rows against `expected.txt` |
| `ex00_ft_<name>_valgrind` | basic | the same program under memcheck, leaks included, for the 12 functions allowed `malloc` or `free` |
| `ex00_ft_<name>_memcheck` | basic | the same, with no leak check, for every other function |
| `ex00_ft_<name>_probe_memcheck` | basic | its memory probe under memcheck: inputs built to expose one memory fault (most often blocks of exactly the bytes the function may touch) |
| `ex00_ft_<name>_asan` | robust | the same probe under ASan/UBSan |
| `ex00_ft_<name>_allocfail` | basic | one `malloc` refused at a time, for the functions whose box, or the man page Part 1 sends you to, says what a failed allocation returns: `ft_calloc`, `ft_strdup`, `ft_substr`, `ft_strjoin`, `ft_strtrim`, `ft_split`, `ft_itoa`, `ft_strmapi`, `ft_lstmap` (and `ft_lstnew`, at robust: below) |
| `ex00_ft_<name>_allocfail_leaks` | robust | the same sweep, asking that a call which reported the failure leave nothing allocated (`ft_split`, `ft_lstmap`): this repo's rigour, not the subject's |
| `ex00_ft_<name>_diff`, `_diff_asan`, `_readings`, `_readings_diff_asan` | strict, robust | the corpora ([below](#the-corpora)) |
| `ex00_ft_<name>_ilp32`, `_perf`, `_cycles` | complete | the table again where `long` is no wider than `int`; how cost grows; instructions per byte, character, digit or node, with no budget ([testing.md, "The two cost layers"](../../../docs/testing.md#the-two-cost-layers)) |

Four functions also have a second table at strict, which holds one reading of a
case their subject leaves open (below). A function's memory,
allocation-failure, corpus, 32-bit and cost layers wait for its `_output` to
pass (`_perf` also waits for a sample of its corpus, on the plain build and
the ASan one), and say SKIP until then; the probes wait for nothing, and a
stub survives them
([reference.md, "Which layers wait for which"](../../../docs/reference.md#which-layers-wait-for-which)).

`bazel test //cursus/Milestone_0/Libft:basic` runs what is a KO at the
evaluation, the whole library at once;
[reference.md, "Suites"](../../../docs/reference.md#suites) has the others.

**The library is built whole.** Every program a function's tests run links
the whole library, as your Makefile defines it: the harness asks `make -Bn`
which sources your Makefile compiles, and compiles exactly those, with its own
flags and sanitizers. So a source your Makefile leaves out is missing from
every test program too. Until your Makefile compiles something (the stub
compiles nothing), every `ft_*.c` of the turn-in stands in for that list. And
since every program compiles every source, **one file that does not compile,
or a leftover `main`, turns every function red**, each saying `YOUR CODE DID
NOT BUILD` with the compiler's words
([testing.md](../../../docs/testing.md#code-that-does-not-build-fails-its-own-tests-not-the-build)).
Fix that file first: those reds are about it, not about the functions they
name.

On a fresh tree, the red you start with is the work: each function's
`_output`, `ex00_build` and `ex00_readme`. At strict, the four second tables,
`ex00_declares_output` and `ex00_readme_wording` are red too; each holds one
reading of a case the subject leaves open ([below](#what-the-subject-leaves-open)),
and whether to follow it is yours to decide.

### The named cases

Each function's table is written from what its subject says: the man page for
Part 1 ("Your version will have the same prototypes and behaviors as the
originals, adhering strictly to their definitions in the man page.", p.8), the
box for Parts 2 and 3. Each row is labelled with its case, from trivial to
subtle, and shows every byte
([testing.md, "Reading a failure"](../../../docs/testing.md#reading-a-failure)).
What the tables hold, by group:

- **The character functions** (`ft_isalpha` to `ft_tolower`): every input
  their man page defines, EOF and 0 to 255, one row per range of codes. A
  fixture that holds the whole domain needs no corpus and no probe.
- **The memory functions** (`ft_memset` to `ft_calloc`): every block
  `ft_memset`, `ft_bzero`, `ft_memcpy` and `ft_memmove` write starts dirty,
  and its row shows the bytes around the `n` it was given; each table ends on
  a row past 4096 bytes. `ft_memchr`'s table also has rows with a `c` outside
  0 to 255, at `basic`: its man page says how `c` is read.
- **The string functions** (`ft_strlen` to `ft_strdup`): each table holds a
  row whose bytes are `0x80` or more, and ends on a row past 4096 bytes.
- **Part 2** (`ft_substr` to `ft_striteri`): strings shown in the table's
  notation; a function handed a callback gets one of the test's own.
- **The four `_fd` functions**: the bytes go to a file the test opens on a
  descriptor of 3 or more, never the standard output or error, and are read back
  after each call. `ft_putchar_fd`'s table writes every value a `char` holds,
  so it has no corpus.
- **The list functions**: every list a test hands over is built by the test
  itself, never with your `ft_lstnew`, so each red is about the function it
  names. A list with no node is a `NULL` first node. Each walk stops one node
  past the last the test made, so a list that loops back prints instead of
  hanging, and nodes print as where they are (`node 3`, `NULL`), never as
  addresses.

### The corpora

Generated inputs, compared case by case with a reference's answer. A
function's corpus is one target, plus its twin on the ASan build. The seven
character functions, `ft_putchar_fd` and `ft_lstdelone` (which takes one node)
have none.

| target | level | what it replays |
|---|---|---|
| `ex00_ft_<name>_diff` | strict | 400000 seeded cases (200000 for `ft_putstr_fd`, `ft_putendl_fd` and `ft_putnbr_fd`; 20000 for `ft_calloc`), among them a few far past any size a fixed buffer might pick: strings past 4 KiB, lists of 600 and 5000 nodes |
| `ex00_ft_<name>_diff_asan` | robust | the first 200000 of them (5000 for `ft_calloc`) on the ASan/UBSan build, judging memory and how each run ended, never the output |
| `ex00_ft_<name>_readings` | strict | 20000 cases of the one kind a subject leaves open, under one reading (below): `ft_memset`, `ft_strchr`, `ft_strrchr`, `ft_substr`, `ft_split` |
| `ex00_ft_<name>_readings_diff_asan` | robust | the same cases on the ASan/UBSan build |

The corpora seed the bytes `0x7f`, `0x80` and `0xff` on purpose, and in these
replays every block `malloc` hands out starts dirty
([reference.md, "The layers"](../../../docs/reference.md#the-layers)).

## When a case fails, run it again

**A table.** A function's `_output` log shows every row (`CASE | EXPECTED |
GOT | STATUS`), the first failing one usually the most fundamental, and the
hints of the cases that failed. Once `bazel test` has built it, the test
program runs on its own from the repository root, and prints each row as the
test read it:

```sh
bazel-bin/cursus/Milestone_0/Libft/ex00_ft_strlen_bin
```

`42 clues` asks the tests that failed for all their hints
([testing.md, "The `42` command"](../../../docs/testing.md#the-42-command)).

**A corpus.** A `_diff` log lists the first divergences, each as two lines,
the reference's and yours, the inputs first and the answer after them, every
byte visible, under a legend of the columns and a list of what each family of
failing inputs points at
([testing.md](../../../docs/testing.md#the-diff-layers-hints-read-differently)).
When your function crashed or never finished, the log writes the cases to
start with as shell words, each with the command that replays it on its own,
and after a crash it names the corpus case it died on whenever the harness
could record it. A line too long to print is kept whole in
`bazel-testlogs/cursus/Milestone_0/Libft/<target>/test.outputs/`, and the log
names it.

**A memory report.** `_valgrind`, `_memcheck` and `_probe_memcheck` quote,
under their verdict, the sentence of p.3 the finding breaks
([reference.md, "The layers"](../../../docs/reference.md#the-layers)).

## Settings

Each reaches a test only through `--test_env=NAME=VALUE`; none needs setting
for an ordinary run. The full table is in
[reference.md, "Environment variables"](../../../docs/reference.md#environment-variables).

| variable | default | does |
|---|---|---|
| `CLUE_MODE` | first 3 hints | `all` prints every hint that fires |
| `DIFF_TIMEOUT` | `30` | seconds a function's test program gets under `_output` |
| `DIFF_MAX_ROWS` | `40` | how many rows a table shows; `0` shows all |
| `DIFF_CELL_MAX` | `100` | how many bytes of a long failing row a table shows, around its first difference |
| `RL_EXCERPT_WIDTH` | `300` | how many bytes of one corpus line a `_diff` report shows |
| `VALGRIND_TIMEOUT` | `60` | seconds a valgrind run gets |
| `ALLOCFAIL_MAX` | `64` | how many allocations one `_allocfail` sweep refuses, one per run |
| `MAKE_TIMEOUT` | unset | seconds one run of `make` gets under `ex00_build` and its `_exit`, `_rules` and `_wildcards` twins; unset, what is left of the test's limit |
| `NO_SKIP` | `0` | `1` opens every gate (a function's layers that wait for its table, and the `ex00_build_*` targets that wait for a build); a missing tool becomes a failure |

## What the subject leaves open

These are questions the subject, or the man page it sends you to, answers
twice or not at all. No `basic` test holds you to an answer: it checks only
what every reading agrees on. Decide each one yourself (a peer is the best
person to argue it with), and be ready to say at the evaluation which sentence
you read and how.

- **A `c` outside 0 to 255, for `ft_memset`.** man memset: it "fills the
  first n bytes of the memory area pointed to by s with the constant byte
  c". At `basic`, its table and its corpus hold only a `c` from 0 to 255. At
  `strict`, `ex00_ft_memset_wide_c_output` and `ex00_ft_memset_readings`
  hold one reading; their hints say which, as this harness's reading and
  never as the subject's.
- **A `c` outside 0 to 255, for `ft_strchr` and `ft_strrchr`.** Their man
  page does not say what such a `c` finds. At `basic`, their tables and
  corpora hold only a `c` from 0 to 255. At `strict`,
  `ex00_ft_strchr_readings` and `ex00_ft_strrchr_readings` hold one reading,
  their hints saying which.
- **A `start` past the end of `s`, for `ft_substr`.** "The substring starts
  at index ’start’ and has a maximum length of ’len’." (p.10) does not
  mention it. At `basic`, the table and the corpus hold only starts up to the
  string's length. At `strict`, `ex00_ft_substr_start_past_end_output` and
  `ex00_ft_substr_readings` hold one reading, their hints saying which.
- **A field with no byte in it, for `ft_split`**: an empty `s`, a delimiter
  at either end or beside another, a `c` of `'\0'`. The box says it splits
  "’s’ using the character ’c’ as a delimiter" and "The returned array must
  be NULL terminated." (p.11), not what such a field gives. At `basic`, the
  table and the corpus hold only strings whose every field is a word, and
  `ex00_ft_split_probe_memcheck` hands it strings with such fields and judges
  only that nothing past `s` is read. At `strict`, `ex00_ft_split_empty_fields_output`
  and `ex00_ft_split_readings` hold one reading, their hints saying which.
- **The empty list, for `ft_lstlast`.** "Returns the last node of the list."
  (p.15): a list with no node has none, and the box does not say what comes
  back. At `basic`, neither the table nor the corpus asks it. At `strict`,
  `ex00_ft_lstlast_empty_output` holds one reading, its hint saying which.
- **What `libft.h` must hold.** "Files to Submit Makefile, libft.h, ft_\*.c"
  (p.7) names the header, not its contents. At `basic`, the list functions'
  test programs include it for `t_list`, and the Norm and both compilers
  read it. At `strict`, `ex00_declares_output` holds one reading; its red
  says which.
- **Which prototypes may not use `restrict`.** p.8 says of the ’restrict’
  qualifier: "it is forbidden to include it in your own prototypes". At `basic`,
  `ex00_prototype_restrict` reads the prototypes of the 43 functions. At
  `strict`, `ex00_prototype_restrict_all` holds one reading; its red says
  which.
- **One of your functions calling another.** Each box gives its function a
  list. At `basic`, `ex00_forbidden_functions` holds each function's own code,
  and every helper it reaches, to that function's list; when it calls another
  of the 43 functions, that one is held to its own list, not to the caller's. At `strict`, `ex00_forbidden_through` holds
  one reading; its reds say which, and claim no KO.
- **The README's words.** Chapter V allows another language: "English is
  recommended; alternatively, you may use the main language of your campus."
  (p.17). At `basic`, `ex00_readme` reads what holds in any language: the
  file is there and shows something, its first line that shows something is
  in italics, and it has
  at least as many section headings as the subject names sections. At
  `strict`, `ex00_readme_wording` holds one reading, in the two languages the
  subject is printed in; its hint says which. What the README says, and how
  well, is a peer's to read.
- **What `clean`, `fclean` and `re` do.** p.7 and p.3 name the rules, never
  what they do. At `basic`, `ex00_build` asks only that each is there.
  `ex00_build_rules`, at robust, holds them to a convention of this repo's,
  which its red states.
- **A failed allocation in `ft_lstnew`.** Its box (p.14) says nothing of
  one. `ex00_ft_lstnew_allocfail`, at robust, holds it to a convention of
  this repo's, which its red states.
- **`f` returning `NULL`, for `ft_lstmap`.** The box does not say. No test
  has `f` return `NULL`, at any level: the table asks only what every reading
  of the box agrees on.
- **A new node that already leads somewhere, for `ft_lstadd_back`.** Every
  new node the tests hand it has its `next` set to `NULL`. What it does with
  another is not tested at any level.
- **The order of `del`'s calls, for `ft_lstclear`.** The box gives none, so
  the table lists the calls sorted: any order passes.

Two cases a man page leaves open, Libft's subject settles, and the tests hold
you to its words at `basic`: the classifiers return "1 if the character
matches the tested class" and "0 if the character does not match" (p.8),
where the man page says only nonzero; and "If nmemb or size is 0, then
calloc() returns a unique pointer value that can be successfully passed to
free()." (p.8).

No test asks these at any level, since their man pages leave them undefined
or say nothing of them: a value outside EOF and 0 to 255 for the character
functions; areas that overlap for `ft_memcpy` ("The memory areas must not
overlap."); a number outside the `int` range for `ft_atoi`; the value of
`ft_memcmp`'s and `ft_strncmp`'s result beyond its sign, which is all their
man pages promise, so the tables and the corpora compare the sign alone; and
the bytes `ft_strlcpy` leaves between the terminator and `size`.
