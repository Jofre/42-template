# Security policy

## Supported versions

Only the latest publish of
[github.com/Jofre/42-template](https://github.com/Jofre/42-template) is
supported. Update your copy before you report
(`git pull --no-rebase template main`; [CHANGELOG.md](CHANGELOG.md) says what
each publish changed).

## Reporting privately

Use GitHub's private report form:
<https://github.com/Jofre/42-template/security/advisories/new>. Do not open a
public issue for anything below.

## What to report here

- **A script that runs on your machine doing something it should not:** the
  setup scripts, the downloads and their checksum pins, the dev container.
- **Anything that can expose a student's work or identity:** their answers,
  their login, or where their submission is pushed.
- **A check that is wrong about what an exercise must do**, whether it passes
  code that is wrong or fails code the subject allows. Showing it takes exercise
  code, which must never be posted where everyone can read it. Put the code in
  the report's text and nowhere else. A report of this kind is never published
  as an advisory: the fix ships as an ordinary change whose tests and commit
  message hold no exercise code, and the report is closed.

## Not in scope

42's own systems (the intranet, the submission servers, the campus machines).
This project is independent of 42; see the [README](README.md#license).

## If you published your own work by accident

Make that repository private first. A fork of a public repository cannot be
made private: delete the fork, and push your work to a new private repository
instead. Then report here if the harness had a part in it.
