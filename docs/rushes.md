# The rushes

**For:** a team starting a weekend group project.

No program grades a rush. Each subject says so ("not verified by a
program"), and the team presents its work at a defense, where evaluators run
it, read it and question every member. The levels mean what they mean
everywhere else, read for that defense: `basic` is what is a KO there -- the
subject's own examples, the case it says the defense will run, the files, the
functions it allows, the Norm -- and `strict` what an evaluator may or may
not look at (a name the subject gives, a reading of a sentence it leaves
open). Every message says "at the defense" rather than naming the
Moulinette: each project's `subject()` contract says who grades it, and the
runners word it from there. Each rush's tests are also shaped by something
the subject does that no C module does. That shape is what each rush's own
page explains (below); the layers themselves are in [reference.md](reference.md).

---

## Working as a team

A rush is pushed to **one** Git repository for the whole team, and only what is
in it is evaluated at the defense. This harness is built around one clone. So:

- **Bring the work together in one clone**, one member's, and run the tests
  there: what is evaluated is the combined turn-in, not anyone's half of it.
- **One member runs `42 submit`** from that clone, with the team's URL
  ([submitting.md](submitting.md)).
- **Submit never force-pushes.** It fetches the repository and commits on top of
  what is there, so a teammate's push is never erased from the history. But
  what is evaluated is the tip, and a submit makes the tip exactly the
  `deliverable/` it pushes from: a file only a teammate pushed leaves the tip,
  and their version of a shared file is replaced by yours. Submit prints a
  NOTE naming both before it pushes. Two members submitting from two clones
  therefore take turns replacing each other's work; one clone avoids that.
- **Settings that are the team's must agree.** rush-00's `ASSIGNED` (its page,
  below) is in `team.bzl`: in a second clone, set it to the same variant(s).

BSQ, the final project, is a group project too, pushed to one repository for
the whole team, so these rules hold for its team as well; its own page is
[c-piscine/c-piscine-bsq/README.md](../c-piscine/c-piscine-bsq/README.md).

---

## Each rush's page

Each rush's page is the README.md beside its BUILD file: what its subject
asks that no C module does, and how its tests are built around that.

- [rush-00 — the rectangle](../c-piscine/c-piscine-rush-00/README.md)
- [rush-01 — the skyscrapers puzzle](../c-piscine/c-piscine-rush-01/README.md)
- [rush-02 — numbers into words](../c-piscine/c-piscine-rush-02/README.md)
