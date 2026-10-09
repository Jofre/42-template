# What `42` runs

**For:** anyone who wants to see what happens underneath `42`: to understand a
run, to type a command by hand, or because `42` cannot run on this machine.

---

`42` tests nothing itself. Each of its commands that tests, builds or runs a
tool is one Bazel command, or two, that you could type yourself: `42` picks the
command from the folder you are in, runs it, and reads the result back to you.
(`42 help` is `42`'s own, and so is most of `42 doctor`, below.) This page shows those commands, and
the Bazel ideas they are made of.

## Seeing the command

Every `42` command takes two flags for this:

- `--show_bazel` runs as usual, and prints each Bazel command as it runs it.
- `--dry-run` prints them, and runs nothing.

The examples on this page are `--dry-run`s, written as a terminal shows them:
the folder you are in (your copy of the repository is `~/42` here), `$`, what
you type, and below it the command `42` would run. `42` also prints a first
line naming what it would test and at which level, left out here.

```
~/42/c-piscine/c-piscine-c-00/deliverable/ex01$ 42 test --dry-run
$ bazel test //c-piscine/c-piscine-c-00:ex01 --test_tag_filters=lvl_basic,-manual 2>&1 | sh tools/first_red.sh
```

Each of these examples is run by a test of this repository
(`tools/fortytwo/tests/test_docs.py`), which fails when the page and `42`
disagree.

## The words

### Bazel, and its server

**Bazel** is a build tool. You tell it *what* you want built or tested, and it
works out *how*: which files to compile, in which order, with which tools, and
which of that it has already done. It downloads those tools — the compilers,
`valgrind`, `norminette` — at the exact versions this repository pins. That is
why the first run is slow, and why a verdict here does not depend on your
machine.

The `bazel` on your PATH is **bazelisk**, a small launcher `setup.sh`
installed: it reads the file `.bazelversion` and runs exactly that version of
Bazel.

The first command starts a **server**: a Bazel process that stays in the
background and keeps what it has learnt in memory, so that the next command
starts fast. It often holds more than a gigabyte of memory. It stops by itself
after three hours with nothing to do, and `42 stop` stops it now:

```
~/42$ 42 stop --dry-run
$ bazel shutdown
```

### Workspace, package, target, label

- The **workspace** is the whole repository: the folder holding
  `MODULE.bazel`. Bazel finds it from any folder inside it.
- A **package** is a folder with a `BUILD.bazel` file in it. Each project is
  one: `c-piscine/c-piscine-c-00` is C 00's.
- A **target** is one thing Bazel can build, run or test, declared in a
  package's `BUILD.bazel`. Each test of an exercise is a target, one per
  **layer**: `ex01_output` checks what ex01 prints, `ex01_norm` its Norm, and
  so on ([reference.md](reference.md) lists the layers).
- A **label** names a target: `//c-piscine/c-piscine-c-00:ex01_output` is `//`
  (the top of the workspace), the package's folder, `:`, and the target's name.

### Many targets at once

- `//c-piscine/c-piscine-c-00/...` means every target in that package and in
  any package below it: here, the whole project.
- `//c-piscine/c-piscine-c-00:ex01` is a **test suite**: a target that stands
  for other targets, here every test of ex01. The harness declares one for
  each exercise, and one for each level of a project (`:basic` is one).

### Tags, and your level

Each test carries **tags**, words attached to it in its `BUILD.bazel`. This
harness tags each test with its layer (`norm`, `output`, ...), and with its
level and every level above it: a level includes the ones below it, so a test
that runs at `basic` also runs at every higher level.

`--test_tag_filters` keeps, of the tests the labels selected, only those whose
tags match: a comma separates the words, a word alone means *tagged with this*,
and `-` in front means *not tagged with this*. So
`--test_tag_filters=lvl_basic,-manual` keeps the tests tagged `lvl_basic` and
not tagged `manual`. That is how `42` turns your level into Bazel:

```
~/42/c-piscine/c-piscine-c-00/deliverable/ex01$ 42 test --level strict --dry-run
$ bazel test //c-piscine/c-piscine-c-00:ex01 --test_tag_filters=lvl_strict,-manual 2>&1 | sh tools/first_red.sh
```

At `complete`, and at `all`, every test qualifies, so only `-manual` is left:

```
~/42/c-piscine/c-piscine-c-00$ 42 test --level complete --dry-run
$ bazel test //c-piscine/c-piscine-c-00/... --test_tag_filters=-manual 2>&1 | sh tools/first_red.sh
```

`-manual` leaves out the tests that run only when you name them
([testing.md](testing.md#targets-that-run-only-when-named)). A layer named
instead of a level is the same filter on the layer's tag, whatever its level:

```
~/42/c-piscine/c-piscine-c-00/deliverable/ex01$ 42 test norm --dry-run
$ bazel test //c-piscine/c-piscine-c-00:ex01 --test_tag_filters=norm,-manual 2>&1 | sh tools/first_red.sh
```

Your level is `--level`, else the variable `SUBMIT_GATE`, else the file
`.submit-level`, else `basic`, which is how `42 submit` chooses the level it
checks too. [reference.md](reference.md) says what each level adds.

### `test` and `run`

`bazel test LABEL...` builds each test and runs it, and a test passes when its
program exits with 0. What the program prints goes to a **log file**, not to
your terminal: from the top folder, `bazel-testlogs/<package>/<target>/test.log`
(`bazel-testlogs` is a link Bazel makes there). `--test_output=errors` prints
the log of each test that fails, as soon as it fails, among the progress
lines.

`bazel run LABEL -- ARGS` builds one program and runs it in your terminal, like
any other command. Everything after `--` goes to that program, not to Bazel.
The program starts in a folder of Bazel's, not yours, which is why `42 norm`
hands norminette full paths (below).

### The cache

Bazel remembers what each test returned, for exactly the inputs it had: your
files, the harness's, the tools. Ask for a test again with none of them changed,
and it is not run: its result is reused, marked `(cached)`. A test that failed
is run again each time. The end of a `bazel test` says what ran:

```
//c-piscine/c-piscine-c-00:ex01_compile_clang                   (cached) PASSED in 0.3s
//c-piscine/c-piscine-c-00:ex01_compile_gcc                     (cached) PASSED in 0.2s
//c-piscine/c-piscine-c-00:ex01_files                           (cached) PASSED in 0.1s
//c-piscine/c-piscine-c-00:ex01_forbidden                       (cached) PASSED in 0.3s
//c-piscine/c-piscine-c-00:ex01_norm                            (cached) PASSED in 0.7s
//c-piscine/c-piscine-c-00:ex01_prototype                       (cached) PASSED in 0.3s
//c-piscine/c-piscine-c-00:ex01_output                                   FAILED in 0.1s
  /home/you/.cache/42-piscine/bazel/.../testlogs/c-piscine/c-piscine-c-00/ex01_output/test.log

Executed 1 out of 7 tests: 6 tests pass and 1 fails locally.
```

`Executed 1 out of 7`: one test ran, and six results came from the cache. On
later runs that count drops, sometimes to zero. Nothing has gone missing:
Bazel runs again only what your edit could have changed. `--fresh` runs them
all anyway, with Bazel's `--nocache_test_results`:

```
~/42/c-piscine/c-piscine-c-00$ 42 test --fresh --dry-run
$ bazel test //c-piscine/c-piscine-c-00/... --test_tag_filters=lvl_basic,-manual --nocache_test_results 2>&1 | sh tools/first_red.sh
```

A green run may also end with `There were tests whose specified size is too
big`. That is Bazel noting that a harness target declared `medium` (a longer
time limit, kept on purpose for a slow but correct answer and for the cost
layers) finished early. It is about the harness's time limits, not your code,
and nothing in a `BUILD.bazel` needs changing.

## Each command

### `42 test`

```
~/42/c-piscine/c-piscine-c-00/deliverable/ex01$ 42 test --dry-run
$ bazel test //c-piscine/c-piscine-c-00:ex01 --test_tag_filters=lvl_basic,-manual 2>&1 | sh tools/first_red.sh
```

Piece by piece:

- `bazel test` builds the tests and runs them.
- `//c-piscine/c-piscine-c-00:ex01` is what to test, and the folder you are in
  decides it: in an exercise's `deliverable/exNN` (or its `tests/exNN`), that
  exercise's suite; in the project's folder, the whole project. From any
  folder, words name it:

  ```
  ~/42/c-piscine/c-piscine-c-00$ 42 test --dry-run
  $ bazel test //c-piscine/c-piscine-c-00/... --test_tag_filters=lvl_basic,-manual 2>&1 | sh tools/first_red.sh
  ~/42$ 42 test c-05 ex03 --dry-run
  $ bazel test //c-piscine/c-piscine-c-05:ex03 --test_tag_filters=lvl_basic,-manual 2>&1 | sh tools/first_red.sh
  ```

- `--test_tag_filters=lvl_basic,-manual` is your level, as above.
- `2>&1` joins Bazel's two output streams into one. Bazel prints its progress
  and its summary on the terminal's error stream, and without this the pipe
  that follows would receive none of it.
- `| sh tools/first_red.sh` hands all of it to the **triage**, a script of this
  repository that turns a wall of results into what to do next
  ([testing.md](testing.md#reading-a-whole-run)).

`42 test` then shows the log of the first test that failed, its table and its
hints. By hand, add `--test_output=errors`, or open its `test.log`.

It also adds flags it does not show, because none of them changes a result or
the cache: `--build_tests_only` (build only what the tests need),
`--build_event_json_file` and `--invocation_id` (a record of the run, for `42`
to read), and `--noblock_for_lock`. With that last one, when another Bazel
command is already running in this checkout, Bazel returns at once instead of
waiting in silence: `42` says so, and waits up to two minutes itself.

When a file changed while a run read it, `42` also deletes what Bazel built for
that project before it runs it again ([testing.md](testing.md#the-42-command)
says why), and `--show_bazel` shows that line too.

### `42 watch`

```
~/42/c-piscine/c-piscine-c-00/deliverable/ex01$ 42 watch --dry-run
$ bazel test //c-piscine/c-piscine-c-00:ex01 --test_tag_filters=lvl_basic,-manual 2>&1 | sh tools/first_red.sh
```

The same command as `42 test`, run again each time you save. The watching is
not Bazel's: `42` looks at your files once a second, and when one changes during
a run, it stops that run, as Ctrl+C would, and starts it again once the saves
settle ([testing.md](testing.md#the-42-command)). By hand, you run the test
command again after each save.

### `42 clues`

```
~/42/c-piscine/c-piscine-c-00/deliverable/ex01$ 42 clues --dry-run
$ bazel test //c-piscine/c-piscine-c-00:ex01 --test_tag_filters=lvl_basic,-manual
$ bazel test '<the labels that failed>' --test_env=CLUE_MODE=all
```

Two commands. The first is `42 test`'s, to find out what failed; when nothing
changed since your last run, the tests that passed come from the cache, and the
ones that failed run again (*The cache*, above). The second
runs only the tests that failed, again, with `--test_env=CLUE_MODE=all`.
`--test_env` sets a variable in each test's environment, and the test reads
`CLUE_MODE` to decide how many hints to print: all of them, or a number
(`42 clues 2`). The tests that passed are left out of it, because a different
`--test_env` is a different input: every test of that command would run again
instead of coming from the cache. By hand, for one test:

```sh
bazel test //c-piscine/c-piscine-c-00:ex01_output --test_env=CLUE_MODE=all --test_output=errors
```

### `42 norm`

With no file, it is `42 test norm`:

```
~/42/c-piscine/c-piscine-c-00/deliverable/ex01$ 42 norm --dry-run
$ bazel test //c-piscine/c-piscine-c-00:ex01 --test_tag_filters=norm,-manual 2>&1 | sh tools/first_red.sh
```

With files, it runs this repository's pinned norminette on them:
`42 norm ft_print_alphabet.c`, in that folder, runs
`bazel run //tools:norminette -- /home/you/42/c-piscine/c-piscine-c-00/deliverable/ex01/ft_print_alphabet.c`.
The path is a full one because the program starts in a folder of Bazel's
(`bazel run`, above). Anything after a `--` of your own goes on to norminette.

### `42 submit`

```
~/42/c-piscine/c-piscine-c-00$ 42 submit -n --dry-run
$ bazel run //tools:submit -- c-piscine/c-piscine-c-00 -n
~/42/c-piscine/c-piscine-c-00$ 42 submit --level strict -n --dry-run
$ bazel run //tools:submit -- c-piscine/c-piscine-c-00 --gate-level strict -n
~/42$ 42 submit --all --dry-run
$ bazel run //tools:submit
```

`//tools:submit` is a script of this repository: it runs each project's tests
as a gate, at your level, and pushes the projects that pass
([submitting.md](submitting.md)). `42` names the project you are in. With
`--all` it names none, and the script then takes every project that has a URL.

### `42 generate`, `42 header`, `42 init`

Each runs one program of this repository:

```
~/42/c-piscine/c-piscine-shell-00$ 42 generate --dry-run
$ bazel run //c-piscine/c-piscine-shell-00:generate
~/42/c-piscine/c-piscine-c-00/deliverable/ex01$ 42 header ft_print_alphabet.c --dry-run
$ bazel run //tools:gen_header -- ft_print_alphabet.c
~/42/c-piscine/c-piscine-c-00$ 42 header --reset -n --dry-run
$ bazel run //tools:reset_headers -- -n c-piscine/c-piscine-c-00
~/42$ 42 init --dry-run
$ bazel run //tools:init
```

### `42 doctor`

Most of it is not Bazel, on purpose. It first checks what Bazel needs before
starting it — python, `42` and `bazel` on your PATH, where Bazel keeps its
state and the room left there, memory, your identity, tmux — so that it can
still say what is wrong when Bazel cannot start. Then, once Bazel has run on
this machine (or with `--drift`), it runs one program, which compares this
machine with the versions `tools/pins.tsv` records. Its own checks print first;
they are left out here:

```
~/42$ 42 doctor --drift --dry-run
$ bazel run //tools:env_drift
```

## When `42` cannot run

`42` needs python3 3.10 or newer. Without it, it says so and prints a command
to type instead. Every command on this page works typed by hand, from the top
folder of your copy: Bazel finds the workspace from any folder inside it, but
`sh tools/first_red.sh` is a path from the top. Typed by hand, a run shows
no log of its own: add `--test_output=errors`, or open the `test.log` the
summary names.
