# 42 C Piscine — workspace & test harness

A self-contained workspace for the 42 **C Piscine** (`c-piscine-c-00` …
`c-piscine-c-13`), the **Shell Piscine** (`c-piscine-shell-00`, `-01`), the
three weekend **Rushes**, and **BSQ** (`c-piscine-bsq`), the final project.

You implement each exercise; a Bazel-driven test suite tells you, TDD-style,
when it is correct. The tools that decide a verdict — both campus compilers,
`nm`, `diff`, `valgrind`, `norminette` — are **downloaded and checksum-pinned**
rather than taken from your machine, because a check whose answer depends on
which computer you sat at is not a check.

```
clone → set up your machine → bazel run //tools:init → write code
      → bazel test //... → bazel run //tools:submit
```

> **Working with an AI assistant?** Read [`AGENTS.md`](AGENTS.md) first. This is
> a **learning** repo: agents here act as didactic tutors and **must not write
> exercise solutions** — 42 is peer-to-peer, and the struggle is the point.
> Helping with the infrastructure (tests, tooling, docs, environment) is fair
> game.

---

## Quickstart — from nothing to your first red test

**Every exercise here is empty.** Each C file under `deliverable/` is a *stub*:
the exact filename and signature the subject fixes, and a body that does nothing.
Each shell generator is the same. No answers ship here and none ever will — 42 is
peer-to-peer, and the struggle is the point. What each exercise must do is in its
subject, which you download yourself (see below). A test stays red until the
exercise behind it is written; turning it green is the work.

### 1. Set up the machine

**On a 42 campus machine, skip Docker entirely** — the container exists to
reproduce a campus box *somewhere else*, and you have no root to run it with
anyway. One command does everything:

```sh
sh tools/setup.sh      # then open a new shell
```

**Anywhere else you need Docker**, and this repo ships a dev container holding
the tools the suite borrows from the machine. Open the folder in VS Code with
the *Dev Containers* extension and accept **"Reopen in Container"**, or:

```sh
npm install -g @devcontainers/cli
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . bash
```

Either way the first build downloads about 2 GB of pinned tools. `setup.sh`
starts that in the background from your shell profile so it is done before you
need it; `bazel run //tools:prime` does it on demand.

→ [**docs/environment.md**](docs/environment.md) is the full story: which of the
three paths you are on, what `setup.sh` actually does, and how to keep a
memory-tight campus box usable.

### 2. Say who you are

```sh
bazel run //tools:init      # prompts for your 42 login and email
```

**Bazel** is the tool that builds and runs everything here, and a **target** is
one named thing it can build or run, written `//folder:name`. This one records
your identity so the file header 42 requires carries your name.

### 3. Run the tests, and read one red

```sh
bazel test //c-piscine-c-00:basic                             # the first module
bazel test //c-piscine-c-00:ex01_output --test_output=errors  # one exercise
```

The first ends with one red per unwritten exercise and everything else green —
and that is exactly right: a stub already compiles and already satisfies the
**Norm**, 42's mandatory C style. It just prints nothing, so `output` is the
layer that fails. The second says why:

```
 CASE   | EXPECTED                   | GOT       | STATUS
 -------+----------------------------+-----------+-------
 line 1 | abcdefghijklmnopqrstuvwxyz | (no line) | FAIL <
 -------+----------------------------+-----------+-------
 RESULT: FAIL  (0/1 passed, 1 failed)
 --------------------------------------------------
 HINTS:
   * You must print every lowercase letter in order. What character value [...]
```

Hints are pedagogic nudges, never answers, and **more unlock as earlier cases
start passing**. To see them all at once:

```sh
bazel test //c-piscine-c-00:ex01_output --test_env=CLUE_MODE=all
```

### 4. Go green

Write the body in `c-piscine-c-00/deliverable/ex01/ft_print_alphabet.c` and run
that command again. Bazel prints a log only for failures, so a pass is one line:

```
//c-piscine-c-00:ex01_output                                             PASSED in 0.1s
```

On later runs the `Executed N out of M` count drops, sometimes to zero. Nothing
has gone missing: Bazel re-runs only what your edit could have changed.

### 5. Keep going

**Run one module at a level, not the whole repo.** The full suite is more than
you need while writing one function — and on a campus box it is more than you can
afford:

```sh
bazel test //c-piscine-c-05:ex00      # one exercise, every layer
bazel test //c-piscine-c-05:basic     # one module, what the Moulinette grades
bazel test //c-piscine-c-05:strict    # + symbols, valgrind
```

**When a run is all red, pipe it through the triage** — it names the one
exercise to work on next, and separates "not written yet" from "written, and
breaking a rule":

```sh
bazel test //... 2>&1 | sh tools/first_red.sh
```

**When several layers go red at once, work them in this order:** get the right
output first (`output`, then `diff`); then check you are not breaking anything
(`valgrind`, `asan`, `symbols`, `ilp32`); then ask whether it is optimal (`perf`,
`cycles` — usually nothing to fix, only something to think about). This is not
the order you would use in production, and the reason is that **a stub is
trivially memory-safe**: the memory layers are green on code that does nothing,
so they only start telling you something once there is an implementation to
check.

**That is the whole loop.** Everything below is a map; come back to it when you
need it.

---

## Where everything is

| If you want to… | Read |
|---|---|
| set up a machine, or fix a build that died naming nothing | [docs/environment.md](docs/environment.md) |
| understand a red, or what a layer is for | [docs/testing.md](docs/testing.md) |
| look up a layer, a flag, an environment variable, the layout | [docs/reference.md](docs/reference.md) |
| push a module to 42 | [docs/submitting.md](docs/submitting.md) |
| start a weekend group project | [docs/rushes.md](docs/rushes.md) |
| know why the harness is built as it is | [docs/design.md](docs/design.md) |
| read the reference implementation | [oracle/README.md](oracle/README.md) |

Rules for AI assistants are in [`AGENTS.md`](AGENTS.md).

## The 42 file header

Every C file 42 grades carries a header with your login and a timestamp. The
*42 Header* VS Code extension (`kube.42header`) stamps it with **Alt+Enter**,
reading the identity `//tools:init` recorded. Without VS Code:

```sh
bazel run //tools:gen_header -- ft_putchar.c     # print one
bazel run //tools:reset_headers                 # re-stamp after an identity change
bazel run //tools:reset_headers -- -n <target>  # dry run
```

Pass a folder or exercise path to re-stamp only that part, so headers get
natural, staggered timestamps rather than one project-wide instant. `-k` keeps
each file's existing `Created` and moves only `Updated`.

`tools/header_art.txt` holds the ASCII art the header draws — up to 9 rows of 33
columns, and no `*/`. A missing, oversized or malformed file falls back to a
built-in default, so a broken art file can never produce a broken header.

## The subjects

**They are not in this repo, and you download your own.** The subject PDFs and
the 42 Norm are 42's documents, not ours to redistribute — get them from the
intranet. Keep each module's beside it if you like: nothing here reads them, so
the name and the place are yours. `.gitignore` already ignores `*.pdf` so a fork
cannot republish them by accident.

The workspace and its tooling stay in English, whatever language you read the
subject in.

## License

Everything here that is ours — the workspace layout, the Bazel harness, the Rust
oracle and this documentation — is MIT licensed; see [`LICENSE`](LICENSE). Fork
it, teach with it, take it apart.

42's own material is not ours to license and **none of it is here**: no subject
PDFs, no Norm, no `resources.tar.gz` for the shell exercise that reads one, and
no `numbers.dict` for rush-02. Download your own from the intranet. shell-00
ex07, the one exercise that needs that tarball, SKIPS with an explanation until
you do.

This is an independent student project. "42", "42 School" and "Piscine" are
theirs; it is not affiliated with, endorsed by, or supported by 42.
