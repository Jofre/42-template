# Getting help

## Stuck on an exercise

Read the subject again, then `man`, then ask the peer on your right, and then
the one on your left. That is how 42 works, and it will serve you better than
any tool ([`AGENTS.md`, §1](AGENTS.md#1-gently-remind-them-of-42s-way--peers-over-ai)).
The issue tracker is not for help with an exercise: an issue asking for it is
closed.

## A red you do not understand

[docs/testing.md](docs/testing.md#reading-a-failure) explains how to read a
failure, and [which red to fix first](docs/testing.md#which-red-should-i-fix-first).

## Setting up, or a machine that behaves differently

[docs/environment.md](docs/environment.md) covers each kind of machine, and
`bazel run //tools:env_drift` says
[whether anything has drifted](docs/environment.md#has-anything-drifted) from
what the harness expects.

## The harness itself is wrong

Open an issue with one of the forms at
<https://github.com/Jofre/42-template/issues/new/choose>. If a check is wrong
about what an exercise must do, report it privately instead, as
[SECURITY.md](SECURITY.md) describes.
