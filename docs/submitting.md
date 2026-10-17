# Submitting to 42

**For:** you, with a module finished and a Vogsphere repository waiting.

---

**Vogsphere** is 42's own git server: the intranet gives you one empty repository
per module, and whatever you push there is what gets graded: by the Moulinette,
or by the evaluators at a defense for a rush, whose subject says no program
grades it. So each
module is submitted as its **own** git repo, pushed from a campus machine whose
SSH key is registered on your intranet profile. `42 submit` automates that,
once it has each module's URL.

**1. Give it each module's URL, once.** The intranet shows each module's
Vogsphere git URL. The first time you submit a module, add it after
`42 submit`, in the module's folder (the URL here is a made-up one; yours is
the one the intranet shows):

```sh
42 submit -n git@git.example.com:you/c-00.git
42 submit git@git.example.com:you/c-00.git
```

The first line shows what would happen, as step 2 says, and saves nothing.
The second saves the URL, then tests and pushes the module, so from then on
`42 submit` alone pushes there; a URL given again replaces the one saved.
From another folder, name the module with it (`42 submit c-00 URL`). A URL is
one module's repository: `42 submit` refuses one given with `--all` or with
two modules.

You only need a campus machine for the push itself, so you can copy the URLs
from the intranet ahead of time and save them without pushing:

```sh
42 config set remote.c-00 git@git.example.com:you/c-00.git
```

`42 config list` shows the ones you have saved, and
`42 config unset remote.c-00` forgets one. A module with no URL is
**skipped, not an error**.

Both save into one file, `.submit-remotes`, in the top folder of your copy
(the one holding `README.md`), and you can also write it yourself, in your
editor. Its name starts with a dot, which hides it from most file browsers and
from `ls`; `ls -a` shows it. It holds one `KEY=URL` line per module. The key
is the module's path (`c-piscine/c-piscine-c-00`), its folder's name alone
(`c-piscine-c-00`), or the short name `42` takes on the command line
(`c-00`):

```
c-piscine/c-piscine-c-00=git@vogsphere...:...c-piscine-c-00...
c-piscine-c-01=git@vogsphere...:...c-piscine-c-01...   # the project name works too
c-02=git@vogsphere...:...c-piscine-c-02...             # and so does the short name
```

Blank lines and `#` comments are ignored. A key that names no module, a key
that names two, or two lines for the same module, fails the run instead of
guessing. `42 config set` and `42 submit URL` replace every line for the
module with one, and refuse what is not a repository URL. The list of modules
is the `REMOTES` block at the top of `tools/submit.sh`; it is shared harness
and never needs editing, and every module in it stays `REPLACE_ME` there.

`.submit-remotes` is handled like `.submit-level` (below): not gitignored, so
you can commit it in your own clone and it follows you to every machine, and
the template never carries one. The URLs identify you (they hold your login),
so if your clone is pushed anywhere public, keep the file out of it.

**2. Submit.** In the module's folder, or any folder inside it, first:

```sh
42 submit -n
```

`-n` shows what would happen and every file it would push, and pushes nothing.
Then, to push:

```sh
42 submit
```

From any other folder, name the modules (`42 submit c-00 c-01`), or push every
module that has a URL with `42 submit --all`.

The gate runs every test of the module at your level, so a module with an
exercise you have not started is `BLOCKED` too: an unwritten exercise is red.
To push the exercises you have written anyway, add `--written-only`:

```sh
42 submit --written-only
```

An exercise the test report calls *not written yet* (its files still the stub
they started as, its output red) then does not block, and every other test of
the module still has to pass: a red in an exercise you have written, or in a
test of the whole module, still blocks it. The run names each exercise it let
through, and those go to 42 as they are on disk, stubs included. A library
counts the same way: one with some functions written, whose only reds are
functions still a stub or its own tests over a Makefile or `README.md` that
is still the stub, missing or empty, is let through, and goes to 42 with those
files as they are. When the
test report cannot be read, nothing is let through, and the run says so, with
the command that shows the report. It is off unless you ask for it.

It pushes what you have written, never nothing: when every exercise of the
module is still a stub, it refuses before any test runs. Some subjects say where
their mandatory part ends (C 00, Shell 00 and Shell 01 each print a sentence
saying so, right after that part's last exercise), and for those modules it also
refuses while an exercise of that part is still a stub, naming it. A run without
`--written-only` that is blocked says the same. And when that part is all
written and only the exercises after it are not, the blocked run says so and
names them: that is your warning, and `42 submit --written-only` pushes the
module without them.

To push without any gate, add `-- --no-gate` (`42 submit -- --no-gate`), and
the module goes to 42 as it is, red exercises included. What follows `--` goes
to the script `42 submit` runs, `//tools:submit`
([bazel.md](bazel.md#42-submit)).

For each module it (1) **runs that module's tests as a gate** — a module with
failing tests, or with code that does not compile or link, or a turn-in file
missing, is reported `BLOCKED` and is not pushed; so is one whose build stopped
with no line naming a file of yours (a download that failed), which it says —
(2) regenerates the deliverables of a module with `generators/`, and (3) pushes
the green ones. The gate trusts nothing Bazel remembers: before the first
module it restarts Bazel's server (a command still running in that checkout
finishes first), and it builds and runs each module's tests again, so it takes
longer than the same `42 test` would. A result Bazel kept from a run during
which you saved a file can be wrong
([testing.md](testing.md)), and the gate is the one run that must not read one.

**Re-submitting is the same command.** Each submit fetches the Vogsphere
repository first and commits on top of what it already holds, so a second
submit is an ordinary push. Nothing is ever force-pushed, and there is no `-f`:
on a group repository, forcing would replace what a teammate pushed. If a
teammate pushes between your fetch and your push, the push is refused and says
so; run submit again. For how a team shares one repository, see
[rushes.md](rushes.md#working-as-a-team).

## What gets pushed

Exactly the module's `deliverable/` **as it is on disk** when you submit, as the
repository's root: each exercise where its subject's "Turn-in directory" line
puts it (`deliverable/ex00/` is the repository's `ex00/`), and a project whose
subject has no such line, like BSQ, at the root itself (`deliverable/Makefile`
is the repository's `Makefile`). Not
what you committed: your own commits play no part. Files your `.gitignore`
ignores are pushed too, on purpose, so that no ignore rule can quietly drop a
file the subject asks for. The only files left out are build products by
extension: `*.o`, `*.a`, `*.out` and `*.gch`.

So everything in `deliverable/` goes to 42, asked for or not: a test `main.c`,
a note to yourself, a copy kept in a subfolder. Remove what the subject does
not ask for before you submit. The `files` layer fails on a file the subject
does not ask for, in a subfolder too, and each module's `deliverable_files` on
one outside every exercise folder; a gate they stop prints their report.
`42 submit -n` lists every file it would push: read that list before the real
run. A file the subject does ask for is pushed even where `.gitignore` keeps
it out of your commits: rush-02's `numbers.dict`, which is 42's and so ignored
in the template, goes in `deliverable/ex00/` and is turned in from there
(`ex00_numbers_dict_issued` is red until it is; see
[rushes.md](rushes.md#rush-02--numbers-into-words)).

**A built program blocks the module.** If `deliverable/` holds one — an ELF
file under any name, or a file named like the program the subject names
(`bsq`, `rush-02`) — submit reports the module `BLOCKED` and pushes nothing.
The tests build from your sources and never read that file, so the push would
not be the tree that was tested, and the subject asks for the files it names,
not for what they build. `make fclean` removes it.

The pushed tree **replaces** the repository's tip: a file on the remote that is
not in your `deliverable/` is gone from the tip (it stays in the history), and
submit prints a NOTE naming it. If the last push was someone else's, a second
NOTE names each file they changed since your own last push that your version
replaces.

## How strict is the gate?

The gate demands one [level](reference.md#the-four-levels), and the default is
`basic` — which holds everything that is a KO wherever the project is graded,
at the Moulinette or at a defense. None of it is this repo being fussy; each one
is a way to score zero.

Everything **above** the chosen level still runs, and prints a NOTE when red. You
should know your sanitizer is unhappy; you just should not be blocked over it
when the module would be graded fine.

## Setting your own standard

In precedence order — `--level`, then the variable `SUBMIT_GATE`, then a
`.submit-level` file at the repo root, then `basic`. For one submit:

```sh
42 submit --level robust
```

For every command typed in this terminal (the same line in your shell's rc
file sets it in every terminal):

```sh
export SUBMIT_GATE=complete
```

For this clone, permanently (it writes the `.submit-level` file):

```sh
42 config set level complete
```

`42 test` chooses its level the same way, so the level it runs is the one the
gate checks.

`.submit-level` is **tracked** on the owner's working branch, so one owner working across
several machines gets the same standard everywhere. It is not something to
impose on anyone else, so the shareable `template` branch does not carry it and a
fresh clone there falls back to `basic`. If you set up a copy of this for a group,
drop the file or gitignore it.

## Before you push, from a campus machine

The Moulinette grades on a campus box, which can differ from whatever you develop
on — a common reason a solution passes locally and is graded KO. Check the box
you are about to push from:

```sh
42 doctor --drift
```

See [environment.md](environment.md#has-anything-drifted) for what it compares.
