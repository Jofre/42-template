# 42 — workspace & test harness

A self-contained workspace for 42's courses, one folder per course and one
folder per project inside it, each named exactly as 42 names it:

| Course | Folder | What is in it |
|---|---|---|
| C Piscine | `c-piscine/` | `c-piscine-c-00` … `c-piscine-c-13`, the Shell Piscine (`c-piscine-shell-00`, `c-piscine-shell-01`), the three weekend **Rushes**, **BSQ** (the final project) and the study guide |
| Piscine Reloaded | `c-piscine-reloaded/` | one project, `c-piscine-reloaded/`: 28 exercises mixing shell, C and Makefiles — see its README |
| Common Core | `cursus/` | nothing yet; its layout is decided when Libft starts |

You write each exercise, and a test suite tells you, TDD-style, when it is
correct. One command, `42`, runs it. The tools that decide a verdict — both
campus compilers, `nm`, `diff`, `valgrind`, `norminette` — are **downloaded and
checksum-pinned** rather than taken from your machine, because a check whose
answer depends on which computer you sat at is not a check.

```
private copy → sh tools/setup.sh → a new terminal → 42 init
             → 42 test → write code → 42 test → 42 submit
```

**Your answers will live in your copy, so it has to be private — never GitHub's
*Fork* button.** Step 0 of the Quickstart sets it up.

> **Working with an AI assistant?** Read [`AGENTS.md`](AGENTS.md) first. This is
> a **learning** repo: agents here act as didactic tutors and **must not write
> exercise solutions** — 42 is peer-to-peer, and the struggle is the point.
> Helping with the infrastructure (tests, tooling, docs, environment) is fair
> game.

---

## Quickstart — from nothing to your first red test

**Every exercise here is empty.** Each C file under `deliverable/` is a *stub*:
the exact filename and signature the subject fixes, and a body that does nothing.
Each shell generator is the same. No answer ships here in C or shell, and none
ever will. What does ship is `oracle/`: Rust references that solve most of the
exercises, there because the tests compare your output against them. Reading one
before you have tried forfeits the exercise; [oracle/README.md](oracle/README.md)
says what that costs. 42 is peer-to-peer, and the struggle is the point. What
each exercise must do is in its subject, which you download yourself (see below).
A test stays red until the exercise behind it is written; turning it green is
the work.

### The terminal, in one minute

Everything here is typed into a **terminal**: a window where you type a
command, press **Enter**, and read what it prints. If you have never used one,
this is all you need for now:

- **To open one**, start the *Terminal* application (on Ubuntu, **Ctrl+Alt+T**
  opens one too), or in VS Code choose *Terminal → New Terminal*.
- **To run a command**, type it, or paste it with **Ctrl+Shift+V** (in most
  terminals Ctrl+V does not paste), then press **Enter**. Run a block one line
  at a time, in order.
- **It has finished when the prompt comes back**: the line you type on, which
  often ends in `$` or `%`. Until then it is still working, even when it prints
  nothing.
- **Ctrl+C stops** the command that is running. It does not copy here; to copy,
  select the text and press **Ctrl+Shift+C**.
- **`cd` moves you between folders**: `cd c-piscine` goes into the folder
  `c-piscine`, `cd ..` goes back up one, and `cd` alone goes to your home
  folder. `ls` lists what is in the folder you are in, and `pwd` prints which
  folder that is.
- **Type only what a block shows.** Here a block holds only what you type.
  Many guides, and some pages of this repository, put a note after a command,
  behind a `#`: leave the note out, because on campus the shell, zsh, hands it
  to the command as more words.

### 0. Your own copy: private, never a fork

Your answers will live in this repository, so your copy of it has to be
private, and it keeps the template as a remote of its own so that you can pull
the template's updates later. Once, before you write anything, open a terminal
and run:

```sh
cd
git clone https://github.com/Jofre/42-template.git 42
cd 42
git remote rename origin template
```

`cd` alone takes you to your home folder. `git clone` copies the template into
a new folder there, `42`, and `cd 42` goes into it: that folder is your copy,
and every command below is run in it or in a folder inside it. The last line
renames the template's address from `origin`, the name git pushes to, to
`template`, so that `origin` can be yours. Now create an **empty, private**
repository of your own, on GitHub or anywhere else (no README, no licence:
empty), and copy its URL. On GitHub it looks like
`https://github.com/your-name/your-repo.git`. Run these two lines with your
URL in place of that example:

```sh
git remote add origin https://github.com/your-name/your-repo.git
git push -u origin main
```

If you ran the example as it is, `git remote set-url origin` followed by your
URL puts it right. When `git push` asks for a password, GitHub takes a
*personal access token* there, never your account's password, and GitHub's
help says how to make one. Nothing shows while you type or paste it: that is
normal, press Enter. If the push fails, carry on, because
nothing below needs it, and run `git push -u origin main` again once you have
the token. That push only puts a copy of your work in your own repository:
turning it in to 42 is [step 6](#6-turn-it-in).

**Never with GitHub's *Fork* button**: a fork of a public repository is public,
and your answers would be too. **Not with *Use this template* either**: that
copies the files into a history of their own, which `git pull template main`
then refuses to merge ("refusing to merge unrelated histories"). Pulling an
update is [below](#keeping-your-work-getting-updates).

### 1. Install

**On a 42 campus machine**, or your own Linux, be in a terminal in the folder
this repository is in: the one where `ls` shows `README.md`, `tools` and
`c-piscine` (`cd` there first if you are not). Then:

```sh
sh tools/setup.sh
```

It installs `42` and Bazel, the tool `42` drives, and checks this machine. The
first time, that can take several minutes, with nothing printed for a while:
let it finish. It ends with what to do next, naming your own folder and files.
Read all of it before you close anything; it starts:

```
setup: done.

  Next, close this terminal and open a new one: ~/.zshrc now puts
  ~/.local/bin, where 42 is, on your PATH, and a terminal reads that file
  only when it opens.
```

**Do that: close the terminal, and open a new one.** `setup.sh` told your shell
where `42` is by writing it into that file, and a terminal reads the file only
when it opens. In the new terminal, type the `cd` line the message gave you, to
come back to the same folder, and check the machine:

```sh
42 doctor
```

Each check it makes is a line starting with `ok`, `note` (for your
information), `warn` (advice: the tests still run) or `BLOCK` (something no test
can run without, and what to do about it), with any detail indented under it.
When Bazel has already run in this checkout, as `sh tools/setup.sh` makes it
do, a table follows: this machine's tools against the versions this
repository pins, one tool per line, after a few lines of Bazel's own. A
`DRIFT` or `MISSING` in it is for your information, never a blocker, and the
text around the table says what it means. It all ends with
`Ready to run the tests.` once nothing blocks.

**If it says `command not found`** (`zsh: command not found: 42` on campus,
`bash: 42: command not found` elsewhere), the terminal you typed in was open
before `setup.sh` ran: close it and open another. If a new one says it too,
`42` still runs, written `sh tools/42.sh` and typed from this top folder, where
you name the project and the exercise (`sh tools/42.sh test c-00 ex01`). Then
ask a peer to look at it with you, or see
[docs/environment.md](docs/environment.md).

The first terminal you open after `setup.sh` may also print `c-piscine: warming
the build cache in the background`: it downloads and builds what the tests
need, once, while you go on typing. If the machine gets slow meanwhile,
[docs/environment.md](docs/environment.md#campus-box-or-your-own-linux) says how to turn
it off.

**On your own computer, the dev container is the easy path:** install Docker,
and VS Code with its *Dev Containers* extension, open this folder in VS Code
and accept **Reopen in Container**. `42` is already installed there; open a
terminal in VS Code and start at `42 doctor`. (If that says `42: command not
found`, `sh tools/fortytwo/install.sh` installs it.) **On your own Linux
without Docker,** install `perl`, a `cc` and the `en_US.UTF-8` locale first,
then run `sh tools/setup.sh` as on campus.

→ [**docs/environment.md**](docs/environment.md#which-path-are-you-on) is the
full story: the three paths in one table and what each installs, what
`setup.sh` actually does, and how to keep a memory-tight campus box usable.

### 2. Say who you are

```sh
42 init
```

It asks for your 42 login and email, the intranet's, and records them: the 42
header at the top of every file you write carries them, and so do your commits.
Then it offers to re-stamp the header of every file with them: on a fresh copy,
whose headers still carry a placeholder name, answer `y`.
The first commands that run the tests download what they need, so the first
`42 init` and the first `42 test` can each take minutes. After that, seconds.

### 3. Run the tests, and read one red

Each project is a folder in `c-piscine/`. In a C project, each exercise has a
folder in its `deliverable/`, holding the files you write. The shell projects
(Shell 00, Shell 01, and the first exercises of Piscine Reloaded) work
differently: there you write `generators/exNN.sh`, and `deliverable/` is made
from it ([testing.md](docs/testing.md#shell-modules-work-differently)). Go into
C 00's ex01 and run its tests:

```sh
cd c-piscine/c-piscine-c-00/deliverable/ex01
42 test
```

`42 test` runs the tests of the folder you are in. The file there is still a
stub: it compiles, and it already follows the **Norm**, 42's mandatory C style,
but it prints nothing. So the test that reads its output is red:

```
42 test: c-00 ex01, level basic (default)

first_red: 1 red target(s), 1 exercise(s), 1 module(s).

  YOUR NEXT EXERCISE

      //c-piscine/c-piscine-c-00 ex01
      42 test c-00 ex01

      Its output layer is red, which is what an unwritten exercise looks
      like. Write it until that goes green, then run the module again.


  EVERYTHING STILL RED

      MODULE                   RED  STATE                    RED EXERCISES
      c-00                       1  not written yet          ex01

      Add --all for one line per exercise.

  THE LOG OF //c-piscine/c-piscine-c-00:ex01_output

 CASE   | EXPECTED                   | GOT       | STATUS
 -------+----------------------------+-----------+-------
 line 1 | abcdefghijklmnopqrstuvwxyz | (no line) | FAIL <
 -------+----------------------------+-----------+-------
 RESULT: FAIL  (0/1 passed, 1 failed)
 --------------------------------------------------
 HINTS:
   * You must print every lowercase letter in order. What character value do you start from, when do you stop, and does your stop condition still include the final letter?
 --------------------------------------------------
 WAITING FOR THIS OUTPUT: until this test passes, the tests below check
 nothing. A run that includes them (the level named, a higher one, :exNN
 or //...) shows each one PASSED while its log says SKIP: not a pass.
   ex01_ilp32 (complete)
   ex01_memcheck (strict)
   ex01_refcost (complete)

  Stuck on a red? Talk it through with the peer on your right — that is how 42 expects you to learn.
```

- **YOUR NEXT EXERCISE** is the one to work on, with the command that runs its
  tests from any folder. Each kind of test is a **layer**: `output` checks what
  the exercise prints, `norm` checks the Norm, and so on.
- **The table** puts what the exercise must print (EXPECTED) beside what yours
  printed (GOT), line by line. `(no line)` means it printed nothing, and
  `FAIL <` marks each line that differs.
- **HINTS** are questions to think about, never answers. Three show at a time:
  a hint about one case stops showing once that case passes, which makes room
  for the next, while a hint about no case in particular shows on every
  failure until the exercise is green
  ([testing.md](docs/testing.md#reading-a-failure) says which is which).
  `42 clues` shows them all at once.
- **WAITING FOR THIS OUTPUT** is for later. Each test listed there checks
  something only once the output is right, and runs at a higher level than
  yours, the one in brackets (*Keep going*, below, says how to choose one).
- **The last line** shows at most once a week, so most reds end without it.

### 4. Go green

What the exercise must do, and which functions it may use, is in C 00's subject
([The subjects](#the-subjects), below, says where it is). Open
`ft_print_alphabet.c`, the file in this folder, in your editor, write the body,
save, and run `42 test` again. When everything passes, it says so:

```
42 test: c-00 ex01, level basic (default)
first_red: nothing failed.
```

If your code does not compile or link, the tests that run it fail, and the log
`42 test` shows says `YOUR CODE DID NOT BUILD`, with the compiler's message. If
a file is missing, it says `NOT TURNED IN`. An exercise you have not started,
whose stub `Makefile` compiles nothing, says `NOTHING TO BUILD YET`: that is not
broken code.

### 5. Keep going

- **`42 watch`** runs the tests again each time you save, until you press `q`
  ([testing.md](docs/testing.md#the-42-command) says what it watches and what it
  cannot see).
- **A whole project:** in its folder (`cd ../..` from an exercise's), `42 test`
  runs every exercise in it and names the one to work on next. From any folder,
  name it: `42 test c-05`, or `42 test c-05 ex03` for one exercise.
- **One kind of test:** `42 test norm` runs only the Norm check, and
  `42 test valgrind` only the memory one.
- **More tests:** `42 test` runs your **level**, `basic` until you choose
  another: what fails an exercise (a *KO*, in 42's word) where the project is
  graded. `42 test --level strict`
  runs more; [docs/reference.md](docs/reference.md) says what each level adds.
- **`42`** alone lists the commands you need, and `42 help test` explains one.

**When several kinds of test go red at once, work them in this order:** get the
right output first (`output`, then `diff`); then check you are not breaking
anything (`valgrind`, `asan`, `symbols`, `ilp32`, and `method` where the subject
says how the work is done); then ask whether it is optimal (`perf`, `cycles` —
usually nothing to fix, only something to think about). This is not the order
you would use in production, and the reason is that **a stub is trivially
memory-safe**: the memory layers are green on code that does nothing, so they
only start telling you something once there is an implementation to check.

### 6. Turn it in

When a project is green, `42 submit`, typed in its folder, pushes it to
Vogsphere, 42's git server. It runs every test of the project first, at your
level, and pushes nothing if one fails, even in an exercise you have not
started: [docs/submitting.md](docs/submitting.md) says how to push anyway.
Before the first time, write down your Vogsphere URLs as
[docs/submitting.md](docs/submitting.md) shows. `-n` shows what it would push,
and pushes nothing:

```sh
42 submit -n
42 submit
```

**That is the whole loop.** Behind each `42` command that tests, builds or runs
a tool is a Bazel command, the build tool underneath; add `--show_bazel` to one
to see it.
[docs/bazel.md](docs/bazel.md) takes each apart, and says how to type them
yourself where `42` cannot run. Everything below is a map; come back to it when
you need it.

---

## Keeping your work, getting updates

Your work reaches your private repository only when you send it. From the top
folder of your copy, the one holding this README, at the end of each session:

```sh
git add -A
git commit -m "c-00 ex01 and ex02"
git push origin main
```

`git add -A` takes every change, `git commit` records them under the note
between the quotes (write your own), and `git push` sends them to `origin`,
the repository of step 0. It is not a turn-in: that is `42 submit`.

This harness keeps changing — fixes, new projects, the Common Core as it
arrives — and each publish of it builds on the one before, so you pull the
changes into your own copy instead of starting over. Your copy was set up in
[Quickstart step 0](#0-your-own-copy-private-never-a-fork): a private
repository, with the template as a remote named `template`. To get an update:

```sh
git pull --no-rebase template main
```

(`--no-rebase` merges; without it, a recent git refuses to pull into a branch
that has commits of its own until you choose.) Then read the top of
[CHANGELOG.md](CHANGELOG.md): one line per publish, saying what the pull cannot
do for you — a script to re-run, a file to delete. A conflict inside
`deliverable/` or `generators/` means that exercise's stub changed under your
work: keep your code, and the CHANGELOG line says what changed and why.

What is yours alone lives in files the template never touches, so a pull never
collides with them: your Vogsphere URLs in `.submit-remotes`, and where Bazel
keeps its state in `.bazelrc.local`. One tracked file is a team's to edit: the
Rush 00 variant in `c-piscine/c-piscine-rush-00/team.bzl`. If a pull conflicts
there, keep your `ASSIGNED` line and take the rest from the template.

---

## Where everything is

| If you want to… | Read |
|---|---|
| set up a machine, or fix a build that died naming nothing | [docs/environment.md](docs/environment.md) |
| see the Bazel command behind each `42` command, or type it yourself | [docs/bazel.md](docs/bazel.md) |
| understand a red, or what a layer is for | [docs/testing.md](docs/testing.md) |
| look up a layer, a flag, an environment variable, the layout | [docs/reference.md](docs/reference.md) |
| work on BSQ, the final group project: how its tests are built, what its subject leaves open | [c-piscine/c-piscine-bsq/README.md](c-piscine/c-piscine-bsq/README.md) |
| add a project, or a layer, to the harness | [docs/new-project.md](docs/new-project.md) |
| learn the concepts the projects ask for, and the local tools to write and debug C with | [c-piscine/c-piscine-exam-prep/FINAL_EXAM_GUIDE.md](c-piscine/c-piscine-exam-prep/FINAL_EXAM_GUIDE.md), the study guide, also as a PDF and a standalone page beside it (rebuilt from the Markdown with `sh tools/exam_guide.sh`) |
| push a module to 42 | [docs/submitting.md](docs/submitting.md) |
| start a weekend group project | [docs/rushes.md](docs/rushes.md) |
| know why the harness is built as it is | [docs/design.md](docs/design.md) |
| know what `oracle/` holds before you open it: Rust references that solve most exercises | [oracle/README.md](oracle/README.md) |
| see what each publish of the template changed, and what to do after pulling it | [CHANGELOG.md](CHANGELOG.md) |

Rules for AI assistants are in [`AGENTS.md`](AGENTS.md).

## The 42 file header

Every C file 42 grades carries a header with your login and a timestamp. The
*42 Header* VS Code extension (`kube.42header`) stamps it with **Alt+Enter**,
reading the identity `42 init` recorded. Without VS Code, in an exercise's
folder:

```sh
42 header ft_putchar.c
```

prints the header for `ft_putchar.c`, for you to paste at its top: it never
writes into a file. After a change of login, `42 header --reset` re-stamps the
headers of every file in the folder you are in, and `42 header --reset -n` shows
what it would change without changing it. Running it folder by folder gives
natural, staggered timestamps rather than one project-wide instant. `-k` keeps
each file's existing `Created` and moves only `Updated`.

`tools/header_art.txt` holds the ASCII art the header draws — up to 9 rows of 33
columns, and no `*/`. A missing, oversized or malformed file falls back to a
built-in default, so a broken art file can never produce a broken header.

`42 header` prints the C form for `.c` and `.h`, and for `Makefile`, `*.mk` and
`*.sh` the same box in `#` comments, as the 42 editor plugins do; any other name
is refused. The subjects and norminette ask for the header on C files only
(norminette does not read a Makefile). If you do put one on a Makefile, it has to
be the `#` form: a C comment on its first line stops `make` with "missing
separator". A script's `#!` line has to stay line 1, so its header goes below it.

## The subjects

**They are not in this repo, and you download your own.** The subject PDFs and
the 42 Norm are 42's documents, not ours to redistribute, and 42 revises them — so
get the versions you are graded against from the intranet. Every project folder
with a 42 subject has a `SUBJECT-PLACEHOLDER.pdf` where the subject belongs: open it
for which one to download and what to call it (`en.subject.pdf`, `es.subject.pdf`). Nothing here
reads them, and `.gitignore` already ignores `*.pdf`, so a copy of this repo
cannot republish them by accident.

The workspace and its tooling stay in English, whatever language you read the
subject in.

## License

Everything here that is ours — the workspace layout, the Bazel harness, the Rust
oracle and this documentation — is MIT licensed; see [`LICENSE`](LICENSE). Copy
it, teach with it, take it apart.

42's own material is not ours to license and **none of it is here**: no subject
PDFs (a placeholder in each project folder that has one says which to download), no Norm, no
`resources.tar.gz` for the shell exercise that reads one, and no `numbers.dict` for
rush-02. Download your own from the intranet; a `<file>.DOWNLOAD-ME.txt` in the
project folder names the one path each goes to:

- shell-00 ex07's tarball: `c-piscine/c-piscine-shell-00/resources.tar.gz`, next
  to its `BUILD.bazel` (not `deliverable/ex07/`). The tests read it there, and
  ex07 SKIPS with an explanation until the file is there.
- rush-02's dictionary: `c-piscine/c-piscine-rush-02/deliverable/ex00/numbers.dict`,
  beside the program, which reads it there when it is given one argument. It is
  turned in: `.gitignore` keeps it out of your commits and `42 submit`
  pushes it anyway, so every teammate downloads their own.

This is an independent student project. "42", "42 School" and "Piscine" are
theirs; it is not affiliated with, endorsed by, or supported by 42.
