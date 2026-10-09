# Contributing

Thank you for wanting to make this harness better. This page says what is
welcome, what never is, and how a change reaches the public repository,
[github.com/Jofre/42-template](https://github.com/Jofre/42-template). What the
workspace is and how to use it is in the [README](README.md).

## The one rule: no answers

This harness exists so that each student writes the exercises themselves, so
nothing contributed to it, and nothing said about it in public, may hold an
exercise's answer, in code or in prose.
[`AGENTS.md`, §0](AGENTS.md#0-prime-directive--this-is-a-place-to-learn-not-to-be-given-answers)
says what counts as one. What it forbids an AI assistant to write here, it
forbids every contributor too.

## Stuck on an exercise?

Issues are not the place: see [SUPPORT.md](SUPPORT.md).

## Reporting a problem

Open an issue with one of the forms at
<https://github.com/Jofre/42-template/issues/new/choose>: a harness bug, a
subject that no longer matches the harness, a setup problem, or a docs fix or
idea.

One kind of bug never goes in a public issue: **a check that is wrong about
what an exercise must do**, whether it passes code that is wrong or fails code
the subject allows. Showing either takes exercise code, or says in words what
the right behaviour is, so report it privately, as [SECURITY.md](SECURITY.md)
describes.

## Proposing a change

Welcome: the test harness, its tools, tests and clues, the docs, and the
environment ([`AGENTS.md`, §3](AGENTS.md#3-what-you-can-do-freely--the-infrastructure)).
Never accepted: a filled-in exercise, or anything the rule above forbids.

**Where to make it.** A pull request comes from a fork, and a fork of this
repository is public. So make the change in a fresh fork that holds nothing but
the change, never in the copy you do your exercises in.

**How a pull request lands.** The public repository is published from the
maintainer's source tree, so a pull request is not merged as it stands. When one
is accepted, the maintainer applies the change there and closes the pull
request, and the change arrives with the next publish, whose line in
[CHANGELOG.md](CHANGELOG.md) names you.

Before you open one:

- **Changing the harness** (a project, a layer, a runner, a macro): read
  [`AGENTS.md`, §6](AGENTS.md#6-building-or-changing-the-harness) and
  [docs/new-project.md](docs/new-project.md) first. Every fix comes with a check
  that was red before it.
- **Run the harness's own checks:** `bazel run //tools:conventions`, and the
  self-tests, `bazel test //tools/tests/...` (it takes a while;
  [docs/design.md](docs/design.md) says what they guard).
- **Leave every exercise a stub.** `sh tools/stub_check.sh` checks every one.
- **Commit messages:** one subject line that states what is now true, such as
  `generate: a project that does not exist exits 2`. Leave
  [CHANGELOG.md](CHANGELOG.md) alone: it gets one line per publish, written by
  the maintainer.
- **Working with an AI assistant?** It follows [AGENTS.md](AGENTS.md), and so
  does what it writes for you.

## Issue and pull request threads are public pages

Everything said in them ships to every reader, so they follow the same rule as
text that ships with the harness
([`AGENTS.md`, §2](AGENTS.md#shipped-teaching-prose-has-no-timing-gate)).

## Conduct

Everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md).
