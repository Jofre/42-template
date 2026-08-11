# Submitting to 42

**For:** you, with a module finished and a Vogsphere repository waiting.

---

**Vogsphere** is 42's own git server: the intranet gives you one empty repository
per module, and whatever you push there is what the Moulinette grades. So each
module is submitted as its **own** git repo, pushed from a campus machine whose
SSH key is registered on your intranet profile. `//tools:submit` automates that
from one editable table.

**1. Fill in the URLs.** Edit the `REMOTES` table at the top of
`tools/submit.sh`, replacing `REPLACE_ME` with each module's Vogsphere git URL.
Grab them from the intranet ahead of time; you only need to be on a campus
machine for the push itself. A `REPLACE_ME` entry is **skipped, not an error**.

```sh
c-piscine-c-00=git@vogsphere...:...c-piscine-c-00...
c-piscine-c-01=REPLACE_ME            # left as REPLACE_ME -> skipped
```

**2. Submit.**

```sh
bazel run //tools:submit                     # every module with a URL set
bazel run //tools:submit -- -n               # dry run: show what would happen
bazel run //tools:submit -- c-piscine-c-00   # only the listed module(s)
bazel run //tools:submit -- -f               # force-push (needed when re-submitting)
bazel run //tools:submit -- --no-gate        # skip the pre-push test gate
```

For each module it (1) regenerates shell deliverables, (2) **runs that module's
tests as a gate** — a module with failing tests is reported `BLOCKED` and is not
pushed — and (3) pushes the green ones.

## How strict is the gate?

The gate demands one [level](reference.md#the-four-levels), and the default is
`basic` — which holds everything that is a KO on the Moulinette. None of it is
this repo being fussy; each one is a way to score zero.

Everything **above** the chosen level still runs, and prints a NOTE when red. You
should know your sanitizer is unhappy; you just should not be blocked over it
when the Moulinette would grade the module fine.

## Setting your own standard

In precedence order — `SUBMIT_GATE`, then a `.submit-level` file at the repo
root, then `basic`:

```sh
export SUBMIT_GATE=complete                       # this shell, or your profile
echo complete > .submit-level                     # this clone, permanently
bazel run //tools:submit -- --gate-level robust   # just this once
```

`.submit-level` is **tracked** on this branch, so one owner working across
several machines gets the same standard everywhere. It is not something to
impose on anyone else, so the shareable `template` branch does not carry it and a
fresh clone there falls back to `basic`. If you fork this for a group, drop the
file or gitignore it.

## Before you push, from a campus machine

The Moulinette grades on a campus box, which can differ from whatever you develop
on — a common reason a solution passes locally and is graded KO. Check the box
you are about to push from:

```sh
bazel run //tools:env_drift
```

See [environment.md](environment.md#has-anything-drifted) for what it compares.
