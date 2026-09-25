# Environment

**For:** anyone setting a machine up, and anyone whose build just died for a
reason that named nothing.

---

## Which path are you on

**Docker is not a requirement of this repo.** It is one way to get an
environment, and on a 42 campus machine it is the wrong one — you have no root
to run it with, and the box already is what the container imitates.

Whatever you sit at, this repo downloads the tools that decide a verdict. The
question below is only about the handful it still borrows from the machine
underneath.

| You are on… | You install | It borrows from the box |
|---|---|---|
| **A 42 campus machine** | nothing but `sh tools/setup.sh` | `/bin/sh`, `perl`, and the `cc` that links test binaries — the box has all of them |
| **Your own Mac / Windows / Linux** | **Docker**, plus VS Code + *Dev Containers* or the `@devcontainers/cli` | the same list, supplied by the container image |
| **Your own Linux, no Docker** | `perl`, a `cc`, a binary named `clang-12`, and the `en_US.UTF-8` locale; then `sh tools/setup.sh` | the same list, from your distro |

`valgrind`, `make`, `nm`, `diff`, `gcc-10` and `clang-12` are **not** on those
lists any more: every one is a pinned `.deb` Bazel fetches (`MODULE.bazel`), and
the layers that use them run the fetched copy rather than the box's. That is
what `tools/pins.tsv`'s `fetched-as` column records and what
`bazel run //tools:env_drift` compares. The box still supplies `/bin/sh`, `perl`
(callgrind_annotate is a perl script) and the `cc` Bazel's own toolchain
auto-detects.

Rows 1 and 3 are the same path and differ only in whether you had to install the
borrowed tools yourself.

If you are unsure: **if `ls /goinfre` succeeds you are on a campus box.** That is
the same test `tools/setup.sh` and `//tools:env_drift` use.

`setup.sh` itself needs `git`, a shell, one of python3/wget/curl to download
with, and one of `sha256sum`/`shasum`/python3 to verify the download.

---

## Campus box, or your own Linux

```sh
sh tools/setup.sh
```

One command, once per machine, then open a new shell. It runs *before* Bazel
exists, so it is POSIX `sh` and assumes nothing beyond a shell, `git` and one way
to fetch a file. It:

1. **Installs bazelisk** into `~/.local/bin` (~7 MB, SHA-256 verified before it
   is ever made executable). Bazelisk rather than Bazel, because it reads
   `.bazelversion` and fetches the exact Bazel this repo pins — so your version
   cannot drift from everyone else's. A bare `bazel` already on `PATH` is
   deliberately **not** accepted: real Bazel ignores `.bazelversion`.
2. **Points Bazel's state somewhere with room** (see below).
3. **Writes `PATH` and two cache variables into your shell profile**, between
   markers so a second run replaces the block rather than appending one. You do
   not need to export them by hand.
4. **Runs `//tools:env_drift`**, comparing this machine against `tools/pins.tsv`.
   On a campus box that is the run that matters: it answers *have they upgraded
   anything?*

Three things about it that are not guessable:

- **It is idempotent and sticky.** Re-running it does not relocate your cache: it
  reads the path already recorded in `.bazelrc.local` and keeps it.
- **It writes your login shell's rc file even if that file does not exist yet**,
  detected from `getent passwd`. If your login shell is `fish` it says so and
  prints the three lines to add by hand.
- **It starts the first big download in the background** the next time you open
  a terminal, using its own Bazel output base so it can never block a command
  you type. `export NO_C_PISCINE_PRIME=1` turns that off;
  `bazel run //tools:prime` does it on demand.

**If `bazel: command not found` afterwards**, `~/.local/bin` is not on your
`PATH` yet — that is what "open a new shell" was for. `. ~/.bashrc` does the same
without opening one.

### Where the state goes, and why not all in one place

`setup.sh` picks a scratch directory by **trying candidates in order** and
checking each is genuinely writable — not by testing for one path:

1. `$C_PISCINE_SCRATCH` — you said so; nothing overrules it.
2. `/goinfre/$USER` — a 42 box: large, local, not quota'd.
3. `$XDG_CACHE_HOME` or `~/.cache` — any other machine. It survives a reboot, so
   the pinned downloads are fetched once rather than after every restart.
4. `/tmp/$USER` — last resort, and per-user on purpose: `/tmp` is shared, and two
   people on one path fight over the same lock.

| what | size | why it is where it is |
|---|---|---|
| `~/.local/bin/bazelisk` | ~7 MB | `$HOME` is the only thing that follows you to another machine, and this is the piece small enough to belong there |
| `$SCRATCH/bazel` | GBs | Bazel's output and install bases. Rebuildable |
| `$SCRATCH/bazelisk` | ~63 MB | the Bazel bazelisk downloads |
| `$SCRATCH/bazel-gate` | GBs | `//tools:submit` runs its pre-push gate on a **separate** output base, because a `bazel run` holds the lock on the main one for its whole run and the nested `bazel test` would deadlock. It passes `--output_base` explicitly, which overrides `--output_user_root` — so this is the one path that flag cannot move for you |

---

## Dev container

You need **Docker** installed and started — Docker Desktop on macOS/Windows,
Docker Engine on Linux. Check it with `docker run hello-world`. Then:

**With VS Code:** clone, open the folder, accept *"Reopen in Container"* (or
**Dev Containers: Reopen in Container** from the Command Palette). The first
build takes a few minutes while Docker downloads Ubuntu and installs the
toolchain. When it is done the integrated terminal is already inside the
container at `/workspaces/<repo>`, with a prompt starting `student@piscine`.

**Without VS Code:**

```sh
npm install -g @devcontainers/cli             # one-time
devcontainer up --workspace-folder .          # build it — a few minutes, once
devcontainer exec --workspace-folder . bash   # a shell inside the container
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
error that never names the cause. `sh tools/setup.sh` handles this; the manual
form is a path of your own in `.bazelrc.local`:

```
startup --output_user_root=/tmp/bazelcache-jdoe
```

That file is imported at the **bottom** of `.bazelrc`, so it wins — Bazel takes
the last value it reads for a startup option. To move it for one command
instead, pass it on the command line, which beats every rc file:

```sh
bazel --output_user_root=/tmp/bazelcache-jdoe test //...
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
2. **`bazel shutdown` when you stop.** The server does not exit on its own.
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

A campus box and the dev container both carry these installed as well, so you can
compile or run `norminette` by hand on either. The build never uses those copies.

### Has anything drifted?

```sh
bazel run //tools:env_drift
```

compares three things — the pin, this box, and what Bazel actually fetched — and
grades the differences rather than matching them, so a packaging change is
forgiven and a patch-level move is not. It warns and exits 0: a student sitting
at an upgraded campus machine has done nothing wrong. It never re-pins itself,
because a pin changed by a script is a change to what the suite tests that
nobody decided.

To capture a campus machine's toolchain in the first place, run there:

```sh
sh tools/env-audit.sh --commit --push
```

It needs a shell and git, nothing else; it is read-only and never reads `~/.ssh`.
