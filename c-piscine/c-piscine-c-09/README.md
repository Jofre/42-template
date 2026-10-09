# c-piscine-c-09

C 09: three exercises, pushed as one Vogsphere repository whose root holds
`ex00/`, `ex01/` and `ex02/` — that is `deliverable/` here.

The subject sits beside this file (`en.subject.pdf`, `es.subject.pdf`); a fresh
clone of the public template has a placeholder there instead, saying where to
download the version you are graded against. Your answers are yours to write:
see `AGENTS.md` §0 for what an AI assistant may and may not do here.

| Exercise | What you write | Where |
|---|---|---|
| ex00 — libft | `libft_creator.sh` and the five sources the subject names | `deliverable/ex00/` |
| ex01 — Makefile | the `Makefile`, and nothing else | `deliverable/ex01/` |
| ex02 — ft_split | `ft_split.c` | `deliverable/ex02/` |

## The Makefile exercise

**ex01 turns in a Makefile and nothing else** — *"Files to turn in: Makefile"*,
and *"We'll only fetch your Makefile and test it with our files."* The test
builds it against the grader's `srcs/` and `includes/` from `tests/ex01/grader/`.
Those sources are placeholders that compile: what ex01 grades is the Makefile,
and the five functions' behaviour is graded in ex00, which turns them in as
loose sources. Among them is a file your Makefile must **not** compile — the
subject ends with *"Watch out for wildcards!"*.

`ex01_build` runs your Makefile the way the subject describes it: a bare `make`
builds `libft.a`, printing every command it runs, a second `make` has nothing
left to do, every compile carries the flags the subject names and every object
lands beside its source; then `all`, `libft.a` (the subject's *"and of course
libft.a"*), `clean`, `fclean` and `re`, each checked from a start state of its
own and each by what it leaves behind. A rule your Makefile lacks fails in
make's own words. A rule that does its job and exits non-zero anyway — a
cleaning rule that errors when there is nothing left to clean, say — is a
warning in `ex01_build` and a failure in `ex01_build_exit`, at `robust`: the
subject does not say how a rule exits.

Nothing but the Makefile goes in `deliverable/ex01/` — a copy of the grader's
files there, or anything else under a `srcs/` or `includes/` of your own, would
be pushed with it, and the build test fails when it finds one.
To try your Makefile by hand, build it somewhere else, from the repository root:

```sh
rm -rf /tmp/c09-ex01 && cp -r c-piscine/c-piscine-c-09/tests/ex01/grader /tmp/c09-ex01
cp c-piscine/c-piscine-c-09/deliverable/ex01/Makefile /tmp/c09-ex01/
make -C /tmp/c09-ex01 && make -C /tmp/c09-ex01     # the second run must do nothing
```

The library that comes out is built from placeholders: it proves the Makefile,
not the functions.

## Running the tests

```sh
bazel test //c-piscine/c-piscine-c-09:basic   # what is a KO at the Moulinette
bazel test //c-piscine/c-piscine-c-09:ex01    # one exercise, every layer
```

In the `basic` suite, a stub fails ex00's `output` and `build`, ex01's `build`
(the only layer it has besides `files`) and ex02's `output`: a stub script or
Makefile builds nothing, and a stub function returns nothing useful. Those reds
are your to-do list.
