# c-piscine-reloaded

Piscine Reloaded: **one project**, pushed as one Vogsphere repository whose root
holds `ex00/` … `ex27/`. It is the only course here with a single project, and it
still gets a project folder inside its course folder so that every course has the
same shape: `<course>/<project>/`.

The subject sits beside this file (`en.subject.pdf`, `es.subject.pdf`); a fresh
clone of the public template has a placeholder there instead, saying where to
download the version you are graded against. Your answers are yours to write:
see `AGENTS.md` §0 for what an AI assistant may and may not do here.

## Three kinds of exercise, one repository

| Exercises | What you write | Where |
|---|---|---|
| ex00–ex05 — shell and files | a **generator**: the commands that create the turn-in | `generators/exNN.sh` |
| ex06–ex21, ex25, ex26 — C | the source file the subject names | `deliverable/exNN/` |
| ex22, ex23 — headers | the header the subject names | `deliverable/exNN/` |
| ex24 — a Makefile | the `Makefile`, and nothing else | `deliverable/ex24/` |
| ex27 — a program | its `Makefile` and sources of your choosing | `deliverable/ex27/` |

**Shell exercises are generated**, exactly as in the Shell Piscine. An archive's
permissions and dates, and ex05's file name, cannot be stored in git, so what you
commit is the recipe: `generators/exNN.sh` runs in an empty folder, and the
turn-in it leaves there becomes `deliverable/exNN/`. That folder is rebuilt,
never edited, and `.gitignore` keeps it out of git — for ex00–ex05 only, since
the C exercises beside it are committed. Rebuild them with:

```sh
bazel run //c-piscine-reloaded/c-piscine-reloaded:generate
```

`//tools:submit` does this for you before it pushes.

## ft_putchar: declare it, never define it

The subject: *"If ft_putchar() is an authorized function, we will compile your code
with our ft_putchar.c."* Six exercises authorise it — ex06, ex07, ex08, ex15, ex18
and ex19 — and in those, `ft_putchar` is the **only** way to print: `write` is not
on their list.

So your file **declares** it, and the stub already does:

```c
void	ft_putchar(char c);
```

…and you never define it, and never turn in an `ft_putchar.c`. The Moulinette
compiles its own copy together with your file, so a definition of yours is a
second one and the program does not link — a zero before any test runs. The
`forbidden` layer says so when it finds one ("your code DEFINES a function the
grader supplies"). And the subject says *"You cannot leave any additional file in
your directory"*, so an `ft_putchar.c` of your own is an extra file as well.

The harness compiles the grader's stand-in, `tests/ft_putchar.c`, into every
build of your code, the way the Moulinette does. To compile one of these by
hand, keep your test `main.c` **outside** `deliverable/` — everything in there is
part of what you turn in, and the harness builds it — and name that file on the
command line. From a scratch directory, with `REPO` the path to this repository:

```sh
cc -Wall -Wextra -Werror main.c \
    REPO/c-piscine-reloaded/c-piscine-reloaded/deliverable/ex06/ft_print_alphabet.c \
    REPO/c-piscine-reloaded/c-piscine-reloaded/tests/ft_putchar.c
```

## The Makefile exercises

**ex24 turns in a Makefile and nothing else** — *"We'll only fetch your Makefile
and test it with our files."* The test builds it against the grader's `srcs/` and
`includes/` from `tests/ex24/grader/`. Those sources are placeholders that compile:
what is graded is the Makefile. Among them is a file your Makefile must **not**
compile, because the Norm asks for every source to be named — *"no \*.c, no
\*.o"*. A second `make` must have nothing left to do: a Makefile that relinks makes
the project non-functional. Each rule the subject names — `all`, `clean`,
`fclean` and `re` — is checked from a start state of its own and by what it
leaves behind, and a rule your Makefile lacks fails in make's own words. A rule
that does its job and exits non-zero anyway — a cleaning rule that errors when
there is nothing left to clean, say — is a warning in `ex24_build` and a failure
in `ex24_build_exit`, at `robust`: the subject does not say how a rule exits.

Nothing but the Makefile goes in `deliverable/ex24/` — a copy of the grader's
files there, or anything else under a `srcs/` or `includes/` of your own, would
be pushed with it, and the build test fails when it finds one.
To try your Makefile by hand, build it somewhere else, from the repository root:

```sh
rm -rf /tmp/ex24 && cp -r c-piscine-reloaded/c-piscine-reloaded/tests/ex24/grader /tmp/ex24
cp c-piscine-reloaded/c-piscine-reloaded/deliverable/ex24/Makefile /tmp/ex24/
make -C /tmp/ex24 && make -C /tmp/ex24     # the second run must do nothing
```

**ex27** is a program and its Makefile, like C 10 ex00: the subject names the binary
and the rules, not the source files, so any `.c` and `.h` beside the Makefile is
accepted. Anything else is an extra file — the subject allows none — including the
binary a hand-run of `make` leaves there: run `make fclean` before you submit. The
same Norm rule as ex24 applies: a second `make` must have nothing left to do,
and its rules' exit statuses are judged the same way, in `ex27_build` and
`ex27_build_exit`.

## ex22: the macro the Norm bans

The subject asks for a function-like macro, *"something that is normally banned
by the Norm, that will be the only time we autorize it"*, so a plain `norminette`
reports `ft_abs.h` as `Error!` whatever else is right about it. The harness runs
it with `-R CheckDefine`, the flag the C 08 subject names for the same exercise,
and its `norm` log says so. To check it the same way by hand, from the
repository root:

```sh
bazel run //tools:norminette -- -R CheckDefine \
    "$PWD/c-piscine-reloaded/c-piscine-reloaded/deliverable/ex22/ft_abs.h"
```

## Running the tests

```sh
bazel test //c-piscine-reloaded/c-piscine-reloaded:basic   # what is a KO at the Moulinette
bazel test //c-piscine-reloaded/c-piscine-reloaded:ex06    # one exercise, every layer
```

A stub fails its `output` layer and passes the rest, with four kinds of
exception, all of them just as unwritten: the headers fail `compile` (and ex22's
`forbidden` reports `ABS` as a call, because the macro it should be does not exist
yet), ex24 and ex27 fail `build`, and ex27 fails `file_diff`. Those reds are your
to-do list.

Most of these tests are the Piscine's own, copied from the exercise each one
repeats (the BUILD file names it) and adapted where the subject differs: ex00's
archive is `exo.tar`, and ex26's `ft_count_if` takes no length — its array ends at
the first `NULL` — and its subject counts "the elements of the array that return
1", where C 11 ex03's counts those that do "not return 0": an `f` that returns
something else is a case it leaves open, and `ex26_returns_one_output`, at
`strict`, holds one reading of it. ex04 (MAC addresses)
depends on the machine's network interfaces: as for Shell 01 ex04, its output
layer runs outside the sandbox, and on a machine with no interface to show (a
container) it checks only that `MAC.sh` is there and parses, and says SKIP for
what it prints.
