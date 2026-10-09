# Environment

**For:** anyone setting a machine up, and anyone whose build just died for a
reason that named nothing.

---

## Which path are you on

**Docker is not a requirement of this repo.** It is one way to get an
environment, and on a 42 campus machine it is the wrong one — you have no root
to run it with, and the box already is what the container imitates.

Whatever you sit at, this repo downloads the tools that decide a verdict. The
table is only about what it still takes from the machine underneath, which
[the first list below](#what-the-harness-borrows-from-the-box) names.

| You are on… | You install | It borrows from the box |
|---|---|---|
| **A 42 campus machine** | nothing but `sh tools/setup.sh` | the short list below — the box has all of it |
| **Your own Mac / Windows / Linux, with Docker** — the easy path | **Docker**, plus VS Code + *Dev Containers* or the `@devcontainers/cli` | the same list, supplied by the container image |
| **Your own Linux, no Docker** | `perl`, a `cc` and the `en_US.UTF-8` locale; then `sh tools/setup.sh` | the same list, from your distro |

Rows 1 and 3 are the same path and differ only in whether you had to install the
borrowed tools yourself. The container is the easy path off campus because it
also carries everything in [the second list](#what-the-docs-ask-you-to-run-by-hand),
which no test needs and you will still want.

If you are unsure: **if `ls /goinfre` succeeds you are on a campus box.** That is
the same test `tools/setup.sh` and `//tools:env_drift` use.

`setup.sh` itself needs `git`, a shell, one of python3/wget/curl to download
with, and one of `sha256sum`/`shasum`/python3 to verify the download.

### What the harness borrows from the box

Bazel's own C toolchain is the pinned pair: every program a test builds
through Bazel is compiled by the `clang-12` and `gcc-10` it fetches
(`MODULE.bazel`, `//tools/cc_toolchain`). Every layer that compiles or links
at test time is handed that compiler (`--cc`) and the binutils 2.38 linker
(`--ld`), and proves before its first compile that it loaded them rather than
the box's -- `asan`, `allocfail`, `cycles` and `refcost` too, which used to
take a compiler from the box.
`valgrind`, `make`, `nm`, `diff` and `llvm-symbolizer` (which turns a
sanitizer report's frames into files and lines) are pinned `.deb`s Bazel
fetches too, and the layers that use them run the fetched copy rather than the
box's. That is what `tools/pins.tsv`'s `fetched-as` column records and what
`bazel run //tools:env_drift` compares. What is still borrowed:

- `/bin/sh`, which runs every script here ([design.md](design.md) says why the
  shell is held to portable usage rather than pinned);
- `perl`, which runs `callgrind_annotate`, the script the `cycles` layer reads
  its counts with;
- the `en_US.UTF-8` locale, which `.bazelrc` sets for every test;
- a `cc`, and the `ar` beside it: a Makefile exercise's `build` layers run
  your Makefile with the pinned `make`, and its recipes run the compiler and
  archiver they name from your `PATH`, as they would at your prompt. No other
  layer takes one from the box: every level of
  `//c-piscine/c-piscine-c-07` passes on a `PATH` holding no compiler,
  assembler or linker at all (measured), and the toolchain Bazel would
  otherwise detect from the box is never fetched.

### What the docs ask you to run by hand

**No test needs any of these.** The study guide and the subjects ask you
to type them yourself: to debug, to read a manual page, to compile as a grader
would. The copies Bazel fetches are for the test layers only; they sit in its cache,
not on your `PATH`. The dev container installs each at the version
`tools/pins.tsv` records, and a campus box carries them too (whether it has
strlcpy's page is one of the facts `sh tools/env-audit.sh` records there). On
your own Linux without Docker, install the ones you want; the package names are
Ubuntu 22.04's, the campus release:

| Command | What for | Install |
|---|---|---|
| `gdb`, `lldb-12` | the study guide's debugger chapter | `sudo apt install gdb lldb-12` |
| `valgrind` | its memory chapter | `sudo apt install valgrind` |
| `gcc-10`, `clang-12` | compiling by hand under both campus compilers (on campus, `cc` is `clang-12` and `gcc` is `gcc-10`) | `sudo apt install gcc-10 clang-12` |
| `nm`, `ar` | reading a program's symbols, building a library by hand | `sudo apt install binutils` |
| `norminette` | the Norm, at your prompt | `pip3 install --user norminette==3.3.58`, the version `tools/pins.tsv` pins: another version can mean other rules, and a `norm` log prints the `bazel run //tools:norminette -- …` command that runs the pinned copy |
| `pypdf` | reading a subject in a terminal: the dev container has no PDF viewer, so it carries this, and `python3 -c 'import sys,pypdf; print("\n".join(p.extract_text() for p in pypdf.PdfReader(sys.argv[1]).pages))' <project>/en.subject.pdf` prints one | nothing, where you have a PDF viewer; otherwise `pip3 install --user pypdf==6.14.2`, the version the image pins |
| `man 3bsd strlcpy` | C 02 ex10's and C 03 ex05's manual page, one page for `strlcpy` and `strlcat`. glibc 2.35 has neither function, so the page ships only in `libbsd-dev` | `sudo apt install libbsd-dev`, for the page: never `#include <bsd/string.h>` or link `-lbsd`, which a campus box need not have. The dev container carries the two pages and nothing else of the package. With no page installed, read [man.openbsd.org's strlcpy page](https://man.openbsd.org/strlcpy.3) |

---

## Campus box, or your own Linux

```sh
sh tools/setup.sh
```

One command, once in **every checkout** — every clone and every worktree — then
close the terminal and open a new one. It runs *before* Bazel exists, so it is
POSIX `sh` and assumes nothing beyond a shell, `git` and one way to fetch a
file. It:

1. **Installs bazelisk** into `~/.local/bin` (~7 MB, SHA-256 verified before it
   is ever made executable). Bazelisk rather than Bazel, because it reads
   `.bazelversion` and fetches the exact Bazel this repo pins — so your version
   cannot drift from everyone else's. A bare `bazel` already on `PATH` is
   deliberately **not** accepted: real Bazel ignores `.bazelversion`. Beside it
   goes `42`, a small script that runs the `tools/42.sh` of the checkout you
   type it in (`tools/fortytwo/install.sh` writes it).
2. **Points Bazel's state somewhere with room** (see below).
3. **Writes `PATH` and `BAZELISK_HOME` into your shell profile**, between
   markers so a second run replaces the block rather than appending one. You do
   not need to export them by hand.
4. **Runs `//tools:env_drift`**, comparing this machine against `tools/pins.tsv`.
   On a campus box that is the run that matters: it answers *have they upgraded
   anything?*

Four things about it that are not guessable:

- **It is idempotent and sticky.** Re-running it does not relocate your cache: it
  reads the path already recorded in `.bazelrc.local` and keeps it. To move it on
  purpose, stop the server first and name the new place:
  `bazel shutdown`, then `C_PISCINE_SCRATCH=/goinfre/$USER sh tools/setup.sh`.
  That records the new root over the old line, which stays as a comment. A root
  set in your `~/.bazelrc` wins over `.bazelrc.local`, so `setup.sh` warns if
  one does.
- **`.bazelrc.local` belongs to one checkout.** It is gitignored and sits in the
  checkout's own folder, so a second clone or a new worktree has none until you
  run `sh tools/setup.sh` there too. Without it the build still gets a per-user
  place (see below), but not the shared disk cache that lets the background
  prime's work reach your build.
- **It writes your login shell's rc file even if that file does not exist yet**,
  detected from `getent passwd`. If your login shell is `fish` it says so and
  prints the lines to add by hand.
- **It starts the first big download in the background** the next time you open
  a terminal, using its own Bazel output base so that a command you type never
  waits for it, though a small machine can be slow while it runs. To turn it
  off for good, put the line `export NO_C_PISCINE_PRIME=1` in your shell's rc
  file (`~/.zshrc`, or `~/.bashrc` for bash), above the block `setup.sh` wrote
  there, and open a new terminal. `bazel run //tools:prime` does it on demand.
- **Every prime writes down what the machine did while it ran**, the one at
  login and `bazel run //tools:prime` alike: memory, swap, the disk queue and
  each Bazel server's memory, every few seconds, into a small file under
  `~/.local/state/42-piscine/prime-traces/`, in a folder named after the
  machine, since your home folder follows you between machines (the five
  newest of each machine are kept). It is
  there for a box that freezes while it primes, because it is written as it
  goes: after a reset it still holds the seconds before. A login prime that
  stopped that way — no end, and the machine restarted since — is not
  started again by itself; it says so when you open a terminal, and
  `bazel run //tools:prime` lifts it.

**If a terminal says `command not found` about `42` (or about `bazel`)
afterwards** (`zsh: command not found: 42` on campus,
`bash: 42: command not found` elsewhere),
`~/.local/bin` is not on your `PATH` yet. That is what the new terminal was
for: a terminal reads your shell's rc file (`~/.zshrc` for zsh, the campus
login shell; `~/.bashrc` for bash) only when it opens, so one that was open
before `setup.sh` ran never sees the change. Close it and open another. Until
then, `sh tools/42.sh`, from the checkout's top folder, is the same `42`.

### Where the state goes, and why not all in one place

Bazel keeps everything it downloads and builds under one **output root**, and it
has to be **yours alone**: two students on one machine sharing a root collide on
its lock, or the second cannot write the first one's directory at all. A
Bazel rc file cannot say "per user" (it expands nothing but `%workspace%`), so
the root is decided in this order:

1. `--output_user_root` on the command line;
2. an rc file that sets it — the checkout's `.bazelrc.local`, which `setup.sh`
   writes, or your own `~/.bazelrc`;
3. **otherwise `tools/bazel`**, a wrapper bazelisk runs on every `bazel`
   command in this repo, which adds the root `setup.sh` would have chosen.
   So a checkout where `setup.sh` never ran is still per-user.

`bazel info output_base` says which one applied: the root is the folder above
it. One exception keeps
anybody's state from moving: off campus, a `/tmp/bazelcache` that is already
yours (where this repo used to send every checkout) is kept — by the wrapper,
and by `setup.sh`, which then records no root of its own. Once that folder is
gone, the wrapper moves to the usual place by itself.

`setup.sh` and the wrapper choose the same way — `tools/drives.sh` holds the
list — by **trying candidates in order** and checking each is genuinely
writable, not by testing for one path:

1. `$C_PISCINE_SCRATCH` — you said so; nothing overrules it. An absolute path:
   `setup.sh` refuses a relative one, and the wrapper says it cannot use it.
2. `/goinfre/$USER` — a 42 box: large, local, not quota'd.
3. `$XDG_CACHE_HOME` or `~/.cache` — any other machine. It survives a reboot, so
   the pinned downloads are fetched once rather than after every restart.
4. `/tmp/$USER` — last resort, and per-user on purpose: `/tmp` is shared, and two
   people on one path fight over the same lock.

The root is the chosen directory's `bazel/` folder. On a campus box,
`//tools:init` and `//tools:env_drift` warn when this checkout's state sits in
your quota'd home or under a path with no login in it, and print the commands
that move it: `bazel shutdown`, then `setup.sh` with `C_PISCINE_SCRATCH` naming
the place, plus the line to delete first if your `~/.bazelrc` sets the root.
Which drives a campus box actually offers, and how big, is recorded by
`sh tools/env-audit.sh` (below): the order above is revisited from those
reports.

| what | size | why it is where it is |
|---|---|---|
| `~/.local/bin/bazelisk` | ~7 MB | `$HOME` is the only thing that follows you to another machine, and this is the piece small enough to belong there |
| `$SCRATCH/bazel` | GBs | Bazel's output and install bases. Rebuildable |
| `$SCRATCH/bazelisk` | ~63 MB | the Bazel bazelisk downloads |

---

## Dev container

You need **Docker** installed and started — Docker Desktop on macOS/Windows,
Docker Engine on Linux. Check it with `docker run hello-world`. Then:

**With VS Code:** clone, open the folder, accept *"Reopen in Container"* (or
**Dev Containers: Reopen in Container** from the Command Palette). The first
build takes a few minutes while Docker downloads Ubuntu and installs the
toolchain. When it is done the integrated terminal is already inside the
container at `/workspaces/<repo>`, with a prompt starting `student@piscine`.

**Without VS Code:** install the Dev Containers command line once, build the
container (a few minutes, the first time), then open a shell inside it, all from
the repository's top folder:

```sh
npm install -g @devcontainers/cli
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . bash
```

or with plain Docker:

```sh
docker build -t 42env .devcontainer
docker run -it --rm -v "$PWD":/workspaces/42 -w /workspaces/42 42env bash
```

---

## Keeping a small, memory-tight box usable

Everything here matters on a campus box and almost nowhere else.

### Disk: a small `$HOME`

A full run of this repo is **measured at 8.9 GB**, and a 42 `$HOME` is usually
capped at 5 GB with no sudo — so the build would die partway through with a disk
error that never names the cause. `sh tools/setup.sh` handles this, and
`tools/bazel` keeps a checkout without it off `$HOME` on campus; the manual form
is a path of your own, with your login in it, in that checkout's
`.bazelrc.local`:

```
startup --output_user_root=/tmp/jdoe/bazel
```

That file is imported at the **bottom** of `.bazelrc`, so it wins — Bazel takes
the last value it reads for a startup option. To move it for one command
instead, pass it on the command line, which beats every rc file:

```sh
bazel --output_user_root=/tmp/jdoe/bazel test //c-piscine/c-piscine-c-00:basic
```

### Disk: it may be inodes, not bytes

Bazel keys its output base on the **workspace path**, so every clone and every
git worktree gets its own full tree — and deleting the checkout does not delete
the base it left behind. They accumulate. Measured here: eight output bases
exhausted a 16.7-million-inode filesystem while **122 GB was still free**, and
the build failed with "no space left on device" — a true message about the wrong
resource.

So if a build starts failing that way, check `df -i` before `df -h`, and reset
with `rm -rf "$SCRATCH/bazel"`. They all rebuild.

### Memory: the habits matter more than the flags

A campus box is a 6-core i5-8500 with 8 GB of RAM and about **2.5 GB free at
idle**, and the Bazel server settles around **1.4 GB of RSS** whatever you cap it
at. `.bazelrc` already limits parallelism; that is the smaller half.

1. **Do not run `//...` on a 2.5 GB-free machine.** Use the per-module suites
   ([testing.md](testing.md#working-on-one-thing-at-a-time)).
2. **`bazel shutdown` when you stop.** The server stays up after every command,
   and by default leaves only after three idle hours (`--max_idle_secs`).
3. **Watch for orphaned servers.** Each output root gets its own, so changing
   `--output_user_root` leaves the previous one running — 3.5 GB across two,
   measured. List them and kill the stale one **by PID**;
   `bazel --output_user_root=<old> shutdown` looks right and does nothing.
   `.bazelrc` carries the one-liner that lists them with their roots.

### A fetch that fails naming nothing

A campus box may not reach Bazel's Central Registry, and that surfaces as an
unrelated-looking fetch error partway through a build. If a first build dies
somewhere odd, check the network before hunting the error.

---

## What is pinned, and what is not

Every C exercise is compiled twice, under **both** compilers the campus box
carries, so a `-Werror` warning only one of them emits fails here instead of on
the Moulinette. Those compilers are **downloaded, not borrowed**: Bazel fetches
campus's exact builds and checks each against a SHA-256.

**The rule: a check whose answer depends on which computer you sat at is not a
check.** Nothing falls back to a copy on your `PATH` — a missing pinned tool
fails the layer loudly rather than passing it quietly.

`tools/pins.tsv` is the single statement of which versions are expected, which
are pinned, and which are only watched — including the reason for each
deliberate non-pin. Read it there rather than here; `MODULE.bazel` carries the
per-tool detail of *why this SHA*.

A campus box and the dev container both carry these installed as well, for
your own hands ([what the docs ask you to run by
hand](#what-the-docs-ask-you-to-run-by-hand)). The build never uses those
copies, and their versions can differ from the pinned ones: a `norm` log names
the norminette version it ran and prints the `bazel run //tools:norminette -- …`
command that reproduces its verdict with the pinned copy.

### Has anything drifted?

```sh
bazel run //tools:env_drift
```

compares three things — the pin, this box, and what Bazel actually fetched — and
grades the differences rather than matching them, so a packaging change is
forgiven and a patch-level move is not. It warns and exits 0: a student sitting
at an upgraded campus machine has done nothing wrong. It never re-pins itself,
because a pin changed by a script is a change to what the suite tests that
nobody decided. Its advice is for whoever can act on it: on a campus box it
lists the campus-kind drift worth reporting; anywhere else it says there is
nothing to do, because the suite runs the fetched copies, not your machine's.

To capture a campus machine in the first place, run there:

```sh
sh tools/env-audit.sh --commit --push
```

It records the toolchain and the facts the harness's own defaults depend on:
every drive a student can use (free space, owner, mode, and whether it is
RAM-backed, network or local), what `tools/drives.sh` would choose there, the
`norminette` on `PATH` beside the pinned one, the memory limits (`ulimit`,
cgroup), how the box behaves under memory pressure (swap, the dirty-page
limits, the disk schedulers, the kernel's out-of-memory and hung-task lines),
the prime traces (above), whether libbsd is installed, and the clock and
timezone. It needs a shell and git, nothing else; it writes nothing but its
report and never reads `~/.ssh`. If a box froze while it primed, run it again
after the reset: the trace that stopped with the machine is in the report.
