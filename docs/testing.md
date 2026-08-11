# Testing

**For:** you, mid-exercise, with something red.
**Tables live in [reference.md](reference.md)** — the layer list, the level
ladder, which layers wait for which, the flags and the environment variables.
This page is how to use them.

---

## Reading a whole run

A module is a few dozen red at once and the whole repo is hundreds. All of it is
true and none of it is an instruction, so pipe it through the triage:

```sh
bazel test //... 2>&1 | sh tools/first_red.sh
```

It sorts by module, then exercise, and splits the red into three kinds, because
they are not the same kind of problem:

- **FIX FIRST** — a red in `norm`, `compile`, `files`, `forbidden` or
  `prototype` **on an exercise you have written**. A stub passes all five, so
  this is code that breaks a rule the Moulinette scores zero for. It asks
  `stub_check` before saying so, which is why c-08's headers — red at `compile`
  while still stubs, because a header defining nothing cannot compile the
  subject's own `main` — are never blamed on you.
- **YOUR NEXT EXERCISE** — the first exercise whose `output` is red. That is
  what unwritten looks like, and it is the work. Only the first is named; the
  rest are counted.
- **ALSO RED** — the output is right and a layer above `basic` disagrees. Worth
  reading, not urgent.

It then prints **EVERYTHING STILL RED**: one line per module, with how many
targets, which exercises, and whether they are unwritten or written-and-broken.
Seven lines instead of three hundred, and that is the part that stops a full run
reading as hopeless.

For the whole picture, one line per exercise with its red layers counted
(`output x5 build`, not six separate targets):

```sh
bazel test //... 2>&1 | sh tools/first_red.sh --all
```

On a tree with 106 red, that is 95 lines against Bazel's 318 — and the exercise,
not the target, is the unit you actually think in.

Then work that one exercise, every layer at once — see [Working on one
thing at a time](#working-on-one-thing-at-a-time).

### You do not need `-k`

Bazel has two flags and the one that governs test failures is already on:
`--test_keep_going` defaults to **true**, so a failing test never stops a run —
measured here, `bazel test //...` reports the identical 1451 pass / 106 fail with
and without `-k`. What `-k` (`--keep_going`) governs is **build** errors, which
this repo deliberately has none of: a build action that cannot do its job still
produces its output and exits 1 rather than take its module down.

Which gives a free canary. **If `bazel test //...` and `bazel test //... -k` ever
disagree, a build action has regressed** — and that difference is the bug report.

### Why the run is not simply ordered

Because Bazel will not order it. It schedules tests in parallel and promises no
order, and it does not deliver one even when told to serialise: three runs of
`bazel test //c-piscine-c-10/... --local_test_jobs=1 --notest_keep_going`
stopped on `ex00_build`, then `ex02_ccarry_output`, then `ex01_two_output`. Same
command, same tree, three answers. So the run stays parallel and fast, and the
order is applied to the report, where it is deterministic and costs nothing.

## Which red should I fix first?

When several layers are red at once:

1. **Get the right output, any way you can.** `output` first, then `diff` — the
   curated table uses cases you can reason about one at a time; the differential
   corpus uses cases you did not choose.
2. **Then check you are not breaking anything.** `valgrind`, `asan`,
   `diff_asan`, `symbols`, `ilp32`.
3. **Then ask whether it is optimal.** `perf` for how the cost grows, `cycles`
   for what one unit of work costs — and usually there is nothing to fix there,
   only something to think about.

This is deliberately **not** the order you would use in production, where memory
safety gates a release. It is the order that carries information while you are
still learning the exercise: **a stub is trivially memory-safe**, so the memory
layers are green on code that does nothing at all. They only start telling you
something once there is a real implementation to check.

Nothing is downgraded by this. Every layer still runs, every red still counts,
and `//tools:submit` will not push a module with any test failing.

## Two layers whose point is not obvious

- **`symbols`** — the Moulinette compiles your file together with a `main()` you
  have never seen, so a helper named `ft_strlen` or `length` can collide with
  theirs and the *link* fails on code that is otherwise perfect. `static` gives a
  helper internal linkage and the collision stops being possible.
- **`ilp32`** — C only promises that `long` is *at least* 32 bits. Copying an
  `int` into a `long` so `INT_MIN` can be negated works on the campus box (LP64)
  and is undefined where `long` is 32 bits — every 32-bit Linux, and all of
  Windows. This layer rebuilds each exercise for `x86-linux-musl` and replays the
  exercise's own fixture.

## Reading a failure

An `*_output` test prints a per-line **PASS/FAIL table** (`CASE | EXPECTED | GOT
| STATUS`). Passing rows are shown too — they document what the function should
do. Cases run roughly trivial → harder, so the **first** failing row is usually
the most fundamental thing to fix.

Below the table, a **HINTS** block may appear. Hints are pedagogic nudges, never
answers: they name what to reconsider. They are grouped by concept,
most-fundamental first, and only three are shown at once.

Which of the rest you can reach depends on how a hint is written. A hint keyed
to particular cases stops firing once those cases pass, which lets a later one
rise into view — that is the "unlock" the footer offers. A hint keyed to no case
fires on **any** failure, so passing cases never reveals more of those; it only
removes them, all at once, when the exercise goes green. The footer says which
of the two you are looking at. Either way, to see everything now:

```sh
bazel test //c-piscine-c-03:ex00_output --test_env=CLUE_MODE=all
bazel test //c-piscine-c-03:ex00_output --test_env=CLUE_MODE=5
```

The full curated hint set for an exercise is `tests/exNN/clues.tsv`. Reading it
is fair game — no test in this repo contains an answer.

### The `diff` layer's hints read differently

`diff` stays silent until your `expected.txt` is green, then replays hundreds of
thousands of generated inputs. When it finally speaks you have already fixed
everything you could reason about, and it has no case names to hang a hint on —
only a wall of hex.

So it prints a legend for the hex columns, then a list of **which family of
failing inputs implies what**. That second part is the useful one. Do not read a
divergence as "case 4194 is wrong" — ask what the failing inputs have in common:

```
  * only sizes with a 1 in them     -> the row that is first and last at the
                                       same time
  * every size, off by one line     -> a bound on the row loop
  * fine until 128 or 256 wide      -> the type of the variable you count with
```

Each line names a place to look, never the fix.

## Proving a green suite is actually green

Layers skip rather than repeat a failure you can already see — [which waits for
which](reference.md#which-layers-wait-for-which) is a table. That keeps the red
list short and readable, but **a layer that is quiet looks exactly like a layer
that has nothing to say.**

```sh
bazel test //... --test_env=NO_SKIP=1
```

forces every gate open. Nothing is suppressed: the differential replays its
corpus against an unwritten stub, `valgrind` reports on it, `ilp32`
cross-compiles it anyway, and a missing tool becomes a failure instead of a
quiet pass. Expect far more red — that red is the work still to do, stated
twice. Use it when you want a green run to mean "checked and correct" rather
than "checked nothing".

### A test that never compiled is not a test that passed

`--test_tag_filters` runs a SUBSET, and Bazel builds only what that subset
needs. A harness that no longer compiles therefore stays invisible for as long
as nothing in the filter links it:

```sh
bazel build //...        # every target, compiled
```

is the check, and `bazel build --nobuild //...` is **not** — that stops after
analysis, so it proves the BUILD files are well formed and nothing about the C.
This is not hypothetical: a `t_list *head` used in one c-12 diff harness and
never declared survived a full `lvl_strict` sweep, because that harness is a
level-3 target and the sweep never had a reason to compile it. The failure it
produced was `FAILED TO BUILD`, which is not a line any red list shows you
unless you ask for it.

## Working on one thing at a time

The whole suite is more than you need while writing one function, and on a
memory-tight box it is more than you can afford
([environment.md](environment.md)). Ask for the narrowest suite that answers
your question:

```sh
bazel test //c-piscine-c-05:ex00      # one exercise, every layer
bazel test //c-piscine-c-05:basic     # one module, what the Moulinette grades
bazel test //c-piscine-c-05:strict    # + symbols, valgrind
bazel test //c-piscine-c-05/...       # the module, everything
```

`//<module>:exNN` is the one to live in while writing an exercise. It exists
because `ex00_*` is not a Bazel target pattern — you could run one layer or a
whole module, and nothing in between.

Ask for the suite rather than `--test_tag_filters`: a tag filter also filters
targets you name explicitly, so naming one target and one tag can quietly select
nothing.

## The two cost layers

Neither `perf` nor `cycles` can fail a test. They report, and the number is the
lesson. Both stay quiet until the exercise is correct.

`perf` answers **how the cost grows** with input size, in time and memory.
`cycles` answers **what one unit of work costs**, counted by callgrind with the
harness excluded — the constant factor `perf` is too noisy to see.

**Per unit of work, not per call.** "277 instructions per call" says nothing on
its own; per *byte* it can be read against what the work costs — a load, a
compare and an increment is about three, so 3.2 is the floor and 17.5 is not.
The unit comes from the corpus the test just ran, so it cannot drift from what
was measured.

**Budgets are numbers, never a reference implementation.** A target tells you
where you stand; source code would tell you the answer, which no test here may
do.

Why the layer exists, from two real files in this repo — the same function, both
fully correct, both green on every other layer:

| | instructions/byte | `write()` per case |
|---|---|---|
| `ft_putstr`, one `write` per character | 17.5 | 15.85 |
| `ft_putstr`, length first, then one `write` | 4.2 | 1.00 |

**4x the instructions and 16x the syscalls**, and nothing else in the suite can
tell them apart.

```sh
bazel test //c-piscine-c-01:ex05_cycles --test_output=all
```

The runners' own headers carry the measurement caveats — what callgrind cannot
count, why the layer builds at `-O2`, how the scaling exponent is fitted. See
`tools/cycles_check.sh`, `tools/perf_test.sh` and `tools/ref_compare.sh`.

## In the editor

Both reuse the same Bazel cache, so re-runs are instant:

- **Run Task** (any editor): **Terminal → Run Task… → `Bazel: test all`**.
- **Testing panel** (VS Code): the *Bazel-TestExplorer* extension shows every
  target as a red/green tree. Marketplace-only, so it is unavailable on Open VSX
  editors like Antigravity — use the task there.

A few shell exercises depend on the host (MAC address, `/etc/passwd`). They are
tagged `manual` and excluded from `bazel test //...`:

```sh
bazel test //c-piscine-shell-01:ex04_output --test_tag_filters=manual --spawn_strategy=local
```

## Shell modules work differently

For `c-piscine-shell-NN`, the answer is the **generator** — `generators/exNN.sh`
— and `deliverable/` is produced from it and gitignored. Never hand-edit a shell
deliverable:

```sh
# 1. write the commands in generators/exNN.sh
bazel run //c-piscine-shell-00:generate     # 2. rebuild the deliverable
bazel test //c-piscine-shell-00:ex01_output # 3. check it
# 4. fix the generator and repeat
```
