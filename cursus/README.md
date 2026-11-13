# cursus — the Common Core

This folder holds the Common Core's projects, grouped by milestone: one folder
per milestone, `Milestone_N/`, and inside it one folder per project, named as
42 names it on the intranet, with each space written as an underscore
(`Python Module 00` is `Python_Module_00/`). A project's milestone is the one
the intranet's project graph puts it in: the ring it sits on around Libft, the
same rank its unlock rule asks for.

A project folder is laid out as one of `c-piscine/`'s: one `BUILD.bazel`, the
subject beside it, and, where it needs one, a page of its own. What differs is
how the subject divides it. A project whose subject names no turn-in folder,
Libft among them, turns in at `deliverable/` itself, the root of the repository
you push, and its tests are divided into the parts the subject names rather
than numbered exercises: in Libft, the library (`libft`) and each of its
functions (`ft_strlen`). Each part's tests are in `tests/<part>/`, and
`42 units <project>` lists the parts, each with the command that tests it
(`42 test libft ft_strlen`).

Only Libft has a harness so far. Every other folder holds its subject and
nothing else yet: no `BUILD.bazel`, so `bazel test` and `42` do not know it.

| milestone | project | harness |
|---|---|---|
| 0 | Libft | yes, see [its page](Milestone_0/Libft/README.md) |
| 1 | ft_printf, get_next_line, push_swap | not yet |
| 2 | A-Maze-ing, Born2beroot, Python_Module_00 to Python_Module_10, Python_Module_05_bis, Python_Module_06_bis | not yet |
| 3 | Call_Me_Maybe, Codexion, Fly-in | not yet |
| 4 | NetPractice, Pac-Man, RAG_against_the_machine | not yet |
| 5 | Agent_Smith, Inception, The_Answer_Protocol, tree_nity | not yet |
| 6 | ft_resume, ft_transcendence | not yet |

Each milestone from 2 to 6 also has an exam, Exam Rank 02 to Exam Rank 06.
The intranet issues no subject for an exam, so none has a folder here.

The subjects are 42's, in English (`en.subject.pdf`) and, where 42 issues one,
in Spanish (`es.subject.pdf`): Libft, the three of Milestone 1 and Codexion
have both. A fresh clone of the public template has none of them: download the
one you are graded against from the project's page on the intranet and save it
in the project's folder. Some projects come with more files than the subject
(push_swap's checkers, A-Maze-ing's MiniLibX, a dataset); download those from
the same page when you start the project.

Whatever a project turns in lives under its `deliverable/`, as everywhere else in
this repository; see `AGENTS.md` §0.
