# Oracle — reference implementations for live differential testing

This is grader tooling: a set of **reference implementations, written in Rust**,
that are **compiled and run during `bazel test`** and whose output is compared,
at runtime, against the student's C function on the same inputs.

## If you are starting from the template — read this first

**This directory answers most of the Piscine.** Not in C, and not in a form you
can paste, but the algorithm is here for every exercise that has a `diff` layer —
in `c00.rs`…`c13.rs`, `rush00.rs`,
`rush01.rs`, `rush01_bonus.rs`, `rush02.rs` and `bsq.rs`. It has to be: the differential
test layer compares your output against it at runtime, so removing it would take
the harness down.

There is no `c06.rs`, `c08.rs` or `c10.rs`, and eleven further `ft_`-shaped
exercises have no arm either — those modules are checked by their own fixtures
instead. Do not read a missing reference as "this exercise is unchecked"; read
it as "this exercise has no *differential* layer". TODO.md tracks the gap.

Nobody is going to stop you reading it. But be clear about the trade you would be
making. The Piscine is two weeks of getting stuck and unstuck; the value is
entirely in the second half of that, and the exercises are ordered so each one
builds the intuition the next assumes. Reading the answer skips the getting
unstuck and leaves the ordering pointless — you arrive at c-13 without what c-05
was supposed to give you, and the exam does not care how the code got written.

Use the layer instead of the source. When a differential test fails it prints the
exact input and both outputs, which is strictly more useful than the reference
implementation and costs you nothing.

## Why Rust, committed in the repo

The source ships with the repo. Most of it is built from iterators and slices
and does not port cleanly to norm-compliant C — no `for`, no `while` with the
same idioms, different ownership — so most of it is not a copy-paste answer, and
anyone who works out how to port it has learned the exercise.

**That is not true of all of it, and it would be dishonest to claim otherwise.**
The arithmetic arms are close to C already: `o_is_prime` and `o_find_next_prime`
in `c05.rs` are plain `while` loops with an `i += 6` wheel that transliterate
almost line for line. They stay that way on purpose — the `#[inline(never)]`
above them is what keeps them attributable under callgrind, and rewriting them
as iterator chains to widen the language gap would inline them away and break
the `cycles` layer.

So the language is not the safeguard. The safeguard is the section above: the
differential layer prints the exact input and both outputs when it fails, which
is more useful than the reference source and costs you nothing. The reference
lives only in `oracle/`; it is never compiled into a `deliverable/`.

## How a test runs (live differential)

For each wired exercise, `tools/rust_diff.sh`:

1. runs the already-built reference (`//oracle:oracle`, a runfiles data dep) to
   emit `<hex-inputs>\t<reference-output>` for a fixed, seeded set of cases,
2. feeds the **same** inputs to the student's compiled C harness, producing
   `<hex-inputs>\t<student-output>`,
3. byte-exact diffs the two. Any mismatch prints the exact input and both
   outputs.

The reference is built **by Bazel**, once, with the hermetic Rust toolchain
`rules_rust` fetches (see `MODULE.bazel`). No `rustc` is needed on PATH, on this
machine or on a campus box — that is the point of doing it through Bazel rather
than shelling out to a system compiler at test time.

Corpus generation is ~90% of a differential test's wall time; the student's
replay and the byte compare are close to free. If a `diff` layer feels slow, the
generator is what to look at.

### Multi-line reference output (rush)

Every corpus line is one case, which normally means the reference output is one
line. The rush rectangles are not: `rush(5, 3)` prints three lines. They are
therefore **escaped onto a single line** — `'\\' -> "\\\\"`, `'\n' -> "\\n"`, any other
byte outside `0x20..0x7e` -> `\xHH` — by `esc()` in `src/rush00.rs`, and the C
reader harness escapes the student's captured bytes with byte-identical rules
(`c-piscine-rush-00/tests/ex00/rush_capture.h`). Escaping the backslash is not
cosmetic: variant 1 draws its corners with one. The upside is that a divergence
prints as two readable lines in which trailing spaces and a missing final
newline are visible.

### One input, many correct outputs (rush01)

`rush01_solve` is the reference for `c-piscine-rush-01` ex00, the 4x4
skyscrapers puzzle. It is the only corpus here whose answer field holds a **set**
rather than a value, and the reason is the subject's own wording.

Each line is TAB-separated:

```
<16 space-separated clues>\t<solution>\t<solution>...
```

Field 1 is the argv string the student's `rush01` is invoked with, verbatim —
four columns from above, four from below, four rows from the left, four from the
right. Every field after it is one grid that answers it, written as the 16 digits
in row-major order with no spaces, and together they are **every** grid that
does. A vector with no solution carries no solution field, so the line ends in a
tab and `Error` is the correct output — which is also how a consumer can tell the
two kinds apart from the last byte alone.

`|` looks like the natural separator and is **not available**: `rush01_check.sh`
strips `/`, `,`, `|` and spaces from *inside* a solution field, so that a
reference may write one grid as `1234/2341/3412/4123`. A `|` between two
solutions is therefore read as a 32-digit grid and the whole corpus is rejected —
the sweep exits 2 and every student is reddened, including a correct one. The
separator lives in one constant (`SOL_SEP`), and `check()` asserts the emitted
bytes hold no `|` and that line 0 is the subject's example with a literal tab.

Of the 4^16 = 4 294 967 296 well-formed inputs, exactly **438 are solvable** —
the 576 Latin squares of order 4 realise that many distinct clue vectors: 372
with one solution, 34 with two, 28 with four, 4 with six (372 + 68 + 112 + 24 =
576). Those 66 multi-solution vectors are the whole design. The subject asks for
"the first solution you encounter", so *which* grid a correct program prints
follows from the order it searches in, which the subject does not fix. **A
byte-comparison against one stored grid would fail correct programs for looping
in a different order.** The runner must therefore validate the student's output —
a Latin square meeting all 16 clues — and shipping the complete solution set here
lets it do that as a set-membership test instead of re-implementing the puzzle.

Two practical notes for a runner author:

- **Field 1 contains spaces.** Split on TAB, never on whitespace, and pass the
  field as one argv element (`"$clues"`). Bazel's `sh_test` re-tokenises `args`
  on whitespace — this repo has been bitten by that three times — so the clue
  string has to reach the binary from a corpus file at run time, not through
  `args = [...]`. Verified end to end: `IFS=$'\t' read -r clues sols` then
  `set -- "$clues"` gives `$# = 1`, and the program sees `argc == 2` with the
  whole vector in `argv[1]`.
- **Every vector in the corpus is well-formed** (16 tokens, all `1`..`4`). The
  subject's *other* error branch — wrong argument count, non-digit, out of range,
  empty string — is not representable in this format and belongs to an argv-case
  table, not here. What this corpus covers is the harder half: well-formed input
  with no solution.

The corpus is `max(count, 876)` lines: all 438 solvable vectors (the subject's
example first, then the multi-solution ones, then the rest) merged with at least
438 unsolvable ones, so any slice a consumer takes holds both a grid to validate
and an `Error` to expect. The merge is drawn from the seed rather than
alternating, and that is not fussiness: a consumer that caps its case count
takes every k-th line, and against a strictly alternating corpus every **even**
stride selects one class and nothing else — cap 876 cases at 400, land on a
stride of 2, and the sweep replays 400 `Error` cases without validating one
grid, then reports a pass. Any fixed period has a stride that erases it, so the
interleaving is drawn; `check()` asserts a mix survives every stride from 2 to 12
at every offset. Growth above the floor is all unsolvable
cases — the solvable half is already complete and cannot grow. The unsolvable
half is curated shapes, then single-clue perturbations of solvable vectors (a
near miss can only be rejected by finishing the work), then uniform draws, which
is what the input space actually looks like. Measured at `-O2`: 876 lines in
3 ms, 400 000 in 0.40 s; `bench rush01_solve` replays 400 000 in 0.71 s.

The **bonus** (sizes up to 9x9) has no *bench* arm: a bonus must never gate, so
there is nothing to time it against, and the exhaustive table is 4x4-specific
anyway (order 5 has 161 280 Latin squares, order 6 has 812 851 200). It does
have a reference — `rush01_bonus.rs`, which is the largest module here — reached
through the `rush01_bonus` and `rush01_rect` arms and consumed by the `manual`
targets in `c-piscine-rush-01/BUILD.bazel`. This paragraph used to say the bonus
had no arm at all, full stop, which is how 1 699 lines went unmentioned.

### Corpora for PROGRAMS, not functions (bsq, c06, c10)

Every corpus above feeds a C harness that LINKS the student's function and
streams cases through one process. Eight exercises have no function to link:
`bsq`, three of c-06's and all four of c-10's are programs, so a case is a fork
and an exec. That changes two things and nothing else.

**The count stays in the hundreds**, not the hundreds of thousands. That is a
property of the subject rather than a shortcut, and it is why these corpora lead
with hand-chosen cases and only then generate: with 200 cases to spend, the ones
that are spent deliberately matter.

**The whole case is escaped onto one line**, because the input is no longer a
few integers. `esc_posix`/`unesc_posix` in `src/common.rs` do it with `\n`,
`\t`, `\\` and `\0NNN` — **octal, not `\xHH`**. The consumer is `/bin/sh`,
which is dash here, and dash's `printf %b` decodes `\0NNN` while printing
`\xHH` back literally. (`rush00.rs` keeps its hex form: its consumer is a C
reader.) Both modules' `check()` assert that the escape round-trips and that it
never emits `\x`, which is what stops the two forms being "unified" into one
that silently breaks the shell side.

| arm | exercise | one case is |
| --- | --- | --- |
| `bsq_maps` | bsq | a valid map file, and the map with the square drawn |
| `bsq_mixed` | bsq | valid and invalid files interleaved by the reference |
| `c06_print_params` | c-06 ex01 | an argument list, and the arguments one per line |
| `c06_rev_params` | c-06 ex02 | the same, printed last to first |
| `c06_sort_params` | c-06 ex03 | the same, in ASCII order — **unsigned**, so `0xff` sorts above every letter |
| `c10_display_file` | c-10 ex00 | a file's contents, and the same bytes back |
| `c10_cat` | c-10 ex01 | one to three files, and their concatenation |
| `c10_tail` | c-10 ex02 | a file and `-c N`, and its last N bytes |
| `c10_hexdump` | c-10 ex03 | a file and `-C`, and `hexdump -C`'s exact output |

c-10's four walk the boundaries around every buffer size people choose — 4, 8,
16, 32, 64, 128, 256, 512, 1024, 4096 and the ~30 000 its ex01 subject names —
at each one testing size-1, size and size+1, because all four exercises are a
read loop around a fixed-size array and a read loop is wrong at exactly those
lengths. `c10_hexdump`'s format was taken from the tool's own output rather than
from memory, and the whole reference was cross-checked against the system
`hexdump -C`, `tail -c` and `cat`: 340 cases, zero mismatches.

**c-10's corpus carries NUL bytes**, which is why `tools/file_check.sh` decodes
each file straight into a file with `printf '%b' "$field" > "$dest"` and never
through a shell variable — a variable cannot hold a NUL, dash drops it silently,
and a deliberately broken `strlen(buf)` program passed 60 of 60 until that was
fixed. `esc_posix`'s own note in `src/common.rs` says the same thing about
values that DO travel through a variable.

c-06 ex00 has no arm. It is entirely about `argv[0]`, which means the binary has
to be COPIED to a name and run there, and `tools/progname_test.sh` already does
exactly that under two names while also checking the exit status. A corpus of
more names would be a second copy of a layer that exists.

### Zero-input arms: the seven at a glance

Seven arms sit in this crate but take no part in the loop above, because there
is no loop for them to be in. Each has exactly one correct output: nothing can
be seeded and nothing can be varied, so none of them has a differential layer
and none should.

`c00_print_combn` is the newest and the odd one: `ft_print_combn` DOES take an
argument, but the subject fixes its domain at nine values ("The value of n will
be such that: 0 < n < 10"), so the whole domain is one fixture rather than a
corpus. Its `gen` output is `c-piscine-c-00/tests/ex08/expected.txt`, nine
newline-terminated lines. Before it existed the harness drove four of the nine;
the arm was required to reproduce those four BYTE FOR BYTE, which is what makes
the five it added trustworthy rather than merely plausible.

| arm | exercise | prints | bytes |
| --- | --- | --- | --- |
| `c00_print_alphabet` | c-00 ex01 | `abc…xyz` | 26 |
| `c00_print_reverse_alphabet` | c-00 ex02 | `zyx…cba` | 26 |
| `c00_print_numbers` | c-00 ex03 | `0123456789` | 10 |
| `c00_print_comb` | c-00 ex05 | the 120 strictly increasing digit trios, `", "`-separated | 598 |
| `c00_print_comb2` | c-00 ex06 | the 4 950 ordered pairs of two-digit numbers, `", "`-separated | 34 648 |
| `c05_ten_queens` | c-05 ex08 | the 724 ten-queens boards, then the count | 7 968 |
| `c00_print_combn` | c-00 ex08 | all nine lines, n = 1…9, each newline-terminated | 7 148 |

For **all seven**, `gen`'s output IS the answer rather than a corpus, and both
`gen` and `bench` do the same thing and both PRINT. What differs between the
c-00 five and ten queens is the *write() framing*, and that difference is the
whole point of the c-00 five — see the two sections below, in order.

None of the six emits a trailing newline that its fixture does not have; the
five c-00 fixtures contain **no newline at all**.

### The zero-input reference (c-05 ex08, ten queens)

`c05_ten_queens` prints the 724 solutions of the ten-queens puzzle and returns
724. The exercise's curated fixture is already exhaustive — so ex08 has no
differential layer and correctly should not have one.

What this arm feeds instead is `tools/ref_compare.sh`: an **informative cost
comparison**, the student's instructions per solution against this reference's.
Three consequences are worth knowing before editing it.

- **It is optimised on purpose.** A reference written the way the exercise is
  first written would report a ratio near 1.0 and say nothing at all. The gap
  *is* the message. It is never a gate — `ref_compare.sh` exits 0 whatever the
  numbers say — and the student-facing text names where the difference lives,
  never the technique. A cost figure is a door held open, not a push through it.
- **`gen` and `bench` do the same thing and both PRINT**, which no other bench
  arm here does (everywhere else printing is excluded precisely because it would
  swamp the measurement). The student's function must print too, so a silent
  reference would keep every formatted digit and every syscall out of its own
  count while the student still paid for them, inflating the ratio with work
  nobody can avoid. Both sides necessarily emit the same 7 968 bytes; this side
  emits them in 725 `write()` calls, one per line, and against a student who
  frames their output the same way that leaves the search as the only thing the
  ratio is measuring. Do not record that as a given — a student printing one
  character at a time makes thousands of calls instead, and then part of the gap
  is I/O. `ref_compare.sh` measures both counts and claims less when they
  differ; this crate's job is only to pay for the same output.
- **`gen`'s output is the answer, not a corpus.** Every other generator prints
  inputs paired with reference outputs; a zero-input function's corpus is its
  one and only case. So `oracle c05_ten_queens <seed> <count>` — both arguments
  ignored, deliberately — prints the complete expected output of ex08: 724 board
  lines of ten digits ascending, then the count line. See *What it does not
  assert* below for what that does and does not prove about the fixture.

### The zero-input references (c-00 ex01, ex02, ex03, ex05, ex06)

`c00_print_alphabet`, `c00_print_reverse_alphabet`, `c00_print_numbers`,
`c00_print_comb` and `c00_print_comb2` are the same idea as ten queens, and
`c-piscine-c-00/BUILD.bazel` already records at length why none of the five gets
a `c_diff`: they are all `void f(void)`, so a differential layer would replay one
identical case 400 000 times and prove nothing `tests/exNN/expected.txt` has not
already proved.

Two of the three ten-queens bullets carry over unchanged. **`gen`'s output is the
answer**: `oracle c00_print_comb <seed> <count>` accepts and ignores both numbers
and prints exactly the 598 bytes of `c-piscine-c-00/tests/ex05/expected.txt`, and
the same holds for the other four against ex01, ex02, ex03 and ex06. And **`gen`
and `bench` do the same thing and both print**, for the same reason: the
student's function must print, so a silent reference would keep the bytes and the
syscalls out of its own count while the student still paid for them.

The third bullet is where these five **diverge from ten queens**, and getting it
backwards would leave the layer with nothing to say.

- **Ten queens matches a student's write() framing on purpose; these five do
  not.** There, printing is incidental and the search is the subject, so parity
  at 725 calls is what makes the instruction ratio a statement about the search.
  Here there is no search. Emitting 26 letters or 4 950 pairs costs a few
  thousand instructions however it is written, so the instruction column is the
  *less* interesting one — at this size both totals are mostly process startup,
  and the reference's Rust runtime is the larger of the two. The column that is
  actually about the two implementations is the other one: **how many times each
  side entered the kernel to hand over the same bytes.**

  These exercises authorise exactly one function, `write()`, and the natural
  first solution calls it once per character. So each arm here emits its whole
  output in **one `write()`**, which is the floor, and the distance to it is the
  message. These are recorded figures, taken against finished c-00
  implementations; `ref_compare.sh --kind output` prints both counts side by
  side, so you can read your own row once yours is written:

  | exercise | student `write()` | reference `write()` | bytes |
  | --- | --- | --- | --- |
  | ex01 | 26 | 1 | 26 |
  | ex02 | 26 | 1 | 26 |
  | ex03 | 10 | 1 | 10 |
  | ex05 | 479 | 1 | 598 |
  | ex06 | 9 899 | 1 | 34 648 |

  That is the gap `AGENTS.md` names for `ft_putstr` — *"a perfectly correct
  `ft_putstr` was running at 16x the syscall budget and nobody knew, because
  nothing in the suite ever said so."* A reference framed the way a first
  solution is framed would report parity on both columns and close the gap back
  up. **Do not "fix" these arms into per-character writes for symmetry with ten
  queens.** It is the same principle — pay for the same output, then let the
  difference speak — applied to a job whose entire cost *is* the printing.

  One write is a floor, never a demand. Nothing gates on it, `ref_compare.sh`
  cannot fail on a number, and a student who writes one character at a time has
  written a correct `ft_print_comb`: the subject asked for the bytes, not for a
  buffer.

The one-write property is a claim about the *process*, not about bytes, so
`oracle check` cannot see it (a `Vec<u8>` looks identical either way) and it is
verified by measurement instead. Counted with `ref_compare.sh`'s own callgrind
parser, stdout to `/dev/null`: **one `write()` per arm, for all five, in both
`gen` and `bench`** — while `c05_ten_queens` still makes its 725. In `src/c00.rs`
that rests on two properties of std's stdout, both written down at `emit_once`:
none of the five outputs contains a newline, so the `LineWriter` never flushes
mid-stream and the short arms leave on one explicit `flush()`; and a write larger
than its 1 KiB buffer (ex05 and ex06) bypasses the buffer entirely. A refactor
that buffers differently can cost the syscall silently, so re-measure rather than
assume.

## Why this is not flaky (the determinism contract)

- Inputs come from a **fixed seed** (a hand-rolled SplitMix64 — no external
  crate, no `rand`, no hidden dependency). Same commit → same inputs → same
  result, every run. No wall-clock, no per-run entropy.
- The reference is the single source of inputs; the student side only replays
  them, so the two sides can never disagree about *which* inputs ran.
- Every case is self-describing: a failure is always "input=…, got X, want Y",
  never "some random input somewhere".
- Breadth is by **construction**, not luck: each generator emits exhaustive
  small cases, every boundary value, then a seeded random tail. To widen
  coverage you raise the case count or change the seed — a deliberate,
  reviewable commit, not run-to-run drift.

## Guarding against a bugged reference

A wrong reference would fail correct students, so `oracle check` holds every one
of them to a standard before it is trusted. It is worth being exact about
*which* standard, because this is the target the repo points at to argue its own
results are trustworthy — and this section used to claim more than the code
delivers.

### What `oracle check` actually asserts

`check_all()` sums the failure count of each module's `check()` — `c00`–`c13`,
`rush00`, `rush01`, `rush02`, plus `rush01_bonus::check()`,
`rush01_bonus::check_rect()` and `bsq::check()`, twenty calls in all —
and a non-zero total exits 1. (This list named eleven and called the first rush
module `rush`, a file renamed to `rush00.rs`; in the one section whose stated
purpose is being exhaustive.) The checks come
in three kinds, all of them **internal to the crate**. Kinds 1 and 2 are in every
module; kind 3 is in only two, so do not read it as blanket coverage:

1. **Hand-written case tables** — literal input/output pairs typed into the Rust
   source and verified once by a human. These pin the values a property cannot:
   `c09`'s `strcmp` table fixes the exact byte difference including high bytes
   (`0x80` vs `0x7f` → `1`, `"abc"` vs `"abcd"` → `-100`), and `rush` replays the
   subject's own worked examples from chapters V…IX verbatim (chapter V is
   Rush00 and IX is Rush04, per the rush-00 subject).
2. **Property assertions over a seeded sweep** — what must hold for *every*
   input rather than for a listed one: sort output is ordered **and** a multiset
   permutation of its input; `swap` and `rev` are involutions; `div_mod`
   satisfies `a == (a/b)*b + a%b` with `|a%b| < |b|` and the C remainder sign;
   `atoi`/`putnbr` and `convert_base` round-trip; `strlcat`'s return equals
   `min(strlen(dest),size)+strlen(src)`; `strncmp` agrees in sign with `strcmp`;
   `split`'s tokens contain no separator and concatenate back to the input with
   its separators removed; the btree traversals are permutations of one multiset
   and infix equals sorted order; every board `c05_ten_queens` prints is legal
   (no two queens on a line or a diagonal), the 724 of them are strictly
   ascending — distinctness and the fixture's ordering in one test — and the
   stream it emits is those boards followed by the count line and nothing else,
   that last line being the one part of the output no board-level property can
   see. The c-00 zero-input five are held to the properties their subjects
   actually state rather than to a byte count: the alphabet is 26 lowercase
   letters ascending **by one** from `a` to `z` (and the reverse arm is its
   mirror, which neither arm's own properties can see); `c00_print_comb`'s items
   are strictly increasing digit trios, each present exactly once, the list
   strictly ascending, with no separator before the first or after the last;
   `c00_print_comb2`'s are `AA BB` pairs with both members zero-padded to two
   digits and `AA < BB`, likewise complete and ascending. Byte lengths are
   asserted too, but written as arithmetic (`120*3 + 119*2`) so the number stays
   a consequence of the shape rather than a constant someone has to trust.

   The **width** of that sweep is per-module and deliberately not uniform, so
   cite the module's own number rather than a round one: `c03` 5 000, `c04`
   20 000 + 5 000, `c05` 506 exhaustive probes (`-5…500`) plus 2 000 random,
   `c13` 8 000 generated corpora, `rush01` all 438 solvable vectors plus 4 000
   random well-formed ones, the rest 20 000 — each off its own fixed seed.
   Five references are not sampled at all but held against a **second,
   independently written construction in the same crate**: `rush` renders
   *every* 1…60 × 1…60 box for all five variants; `c05_ten_queens` must agree
   board for board and in order with a deliberately naive re-scanning search that
   shares none of its logic; and `c00_print_comb` / `c00_print_comb2` must agree
   byte for byte with a **generate-and-filter** enumeration that visits all 1 000
   trios (resp. all 10 000 pairs) and discards the ones that are not ordered,
   formats through `format!` instead of digit arithmetic, and places its
   separators with `Vec::join` instead of deciding per item. Every axis those two
   arms could be wrong on — a loop bound, a base offset, the leading zero, the
   side the separator goes on — is a different axis in the check than in the
   reference. What that second opinion buys is
   narrower than it looks, and worth stating precisely rather than waving at: a
   board that survives the legality test *is* a ten-queens solution and there
   are exactly 724 of those, so count + legality + distinctness already pin the
   set on their own. The naive search is really an independent opinion on the
   constant `724` itself — otherwise just a number a human typed — and on the
   order. Both earn their keep, measured on a scratch copy: a wrong shift
   direction turns 724 boards into 82 297 (caught several times over), while
   inverting only the candidate ORDER leaves 724 legal, distinct boards that
   nothing rejects but the ascending assertion and the naive comparison.

   `rush01` is the fifth, and the one where the second opinion is doing the most
   work rather than the least. Its table never *solves* anything — it enumerates
   the 576 Latin squares by stacking permutations and reads each one's clue
   vector off afterwards — so the check runs a genuine solver over all 438
   vectors and demands the same grids in the same order: cell-by-cell placement
   under row/column masks, pruning on clues as each line completes, sharing
   nothing below "read a row, read a column". The two visibility counters are
   split the same way (running maximum on one side, re-scan on the other, agreed
   over all 256 four-tuples) so a bug in counting cannot cancel itself out. What
   that buys, precisely: an *omission*. Count and legality pin ten queens'
   fixture on their own, but nothing pins the claim that the solution fields
   list **every** solution — and a missing grid is a correct student's output rejected, which is
   the worst failure this repo has. That claim is exactly what the second solver
   checks.
3. **Generator self-checks** — that the *corpus* still contains what it claims,
   which nothing else in the suite would notice. **Only `c00`, `rush` and
   `rush01` do this.** `c00` asserts its corpus head still pins `0`, `±1` and the
   `i32` boundaries instead of letting them drift into the random tail; `rush`
   asserts its size table stays inside the contract, holds no duplicates, and
   still covers both the subject's sizes and the ceiling dimensions; `rush01`
   parses its own emitted bytes back — a clue field of 16 single digits, then one
   16-digit solution field per solution — re-validates every listed grid from
   scratch against the clue vector it is filed under, and asserts the corpus
   still holds all 438 solvable vectors, the curated unsolvable ones, the
   subject's example on line 0 with a literal tab, no `|` anywhere, a mix of both
   kinds under every stride 2..12 at every offset, and the same bytes on a second
   run with the same seed.

### What it does not assert

**It never calls libc, and it never reads the curated `expected.txt` fixtures.**
The crate is std-only with zero dependencies: no `extern "C"`, no `#[link]`, no
`unsafe`, and nothing in `oracle/src/` opens a file or uses `include_str!` (grep
it). No line count here, deliberately: it would rot, and the property it was
supporting does not depend on one.
There is no C library on the other side of any comparison here.

That matters most for the fixtures. Where a hand-written case above happens to
match a curated `expected.txt` line, it was **transcribed by hand** — the two
are a snapshot, not a link, so editing a fixture does not make `oracle check` go
red, and the pair can drift apart in silence. The fixtures do gate the
*student*, through the output layer and `rust_diff.sh --gate-expected`; they
just do not gate the reference. (libc's only role in this repo is offline and
human-driven: `tools/gen_expected.sh` can compile a harness against a libc
wrapper to author a fixture. No BUILD rule references it and no test re-runs
it.)

`c05_ten_queens` is the one place worth restating that in, because its `gen`
output is not *like* a fixture, it **is** one: `oracle c05_ten_queens 0 0` and
`c-piscine-c-05/tests/ex08/expected.txt` are the same 7 968 bytes (md5
`a87b35c5…`, `cmp` clean, checked by hand when the arm was added). That is real
provenance for a fixture that previously had none: an independently written
search reproduces it exactly.

The pair is still a snapshot and not a link — nothing in the suite re-diffs the
two files, so editing `expected.txt` will not make `oracle check` go red. But
unlike the transcribed tables, the properties the check enforces pin *one side*
of the pair completely, and that is worth following through. A board that
survives the legality test **is** a ten-queens solution and there are exactly
724 of those, so "724 legal boards, all distinct" cannot describe any set but
the complete one; "strictly ascending" then fixes their order, and the count
line is asserted on top. Those together admit exactly one byte string. So a
green check leaves `oracle c05_ten_queens` with one possible output, and a
future divergence from `expected.txt` can only be an edit to the fixture, never
a regression in the reference. That is less than a re-diff would give and more
than the transcribed tables get — which is the useful thing to know when
deciding which side to trust if the two ever disagree.

The c-00 zero-input five are `gen`-output-is-a-fixture in the same way, and were
checked the same way by hand when the arms were added — `oracle <arm> 0 0` piped
straight into `cmp` against each exercise's `expected.txt`, clean on all five and
at several `(seed, count)` pairs to confirm both arguments really are ignored:

| arm | fixture | bytes | md5 (both sides) |
| --- | --- | --- | --- |
| `c00_print_alphabet` | `c-piscine-c-00/tests/ex01/expected.txt` | 26 | `c3fcd3d7…` |
| `c00_print_reverse_alphabet` | `…/ex02/expected.txt` | 26 | `34a1a896…` |
| `c00_print_numbers` | `…/ex03/expected.txt` | 10 | `781e5e24…` |
| `c00_print_comb` | `…/ex05/expected.txt` | 598 | `7665e0a3…` |
| `c00_print_comb2` | `…/ex06/expected.txt` | 34 648 | `022b798e…` |

Their check pins one side of each pair the same way ten queens' does, and by the
same argument: 120 distinct strictly-increasing trios out of the 120 that exist
is the complete set and no other, "strictly ascending" fixes the order, the
separator assertions fix the joins, and the emit-path assertion fixes that
nothing is appended. Those together admit exactly one byte string per arm, so a
green check leaves each with one possible output.

These five have one thing ten queens does not, and it is the sibling of the
crate's "never reads the fixtures" rule rather than an exception to it: **the
crate still never opens a file, but its consumer does the re-diff.**
`tools/ref_compare.sh --kind output` runs `cmp` between the arm's `bench` output
and `--gate-expected` before it will report any number, and exits 2 if they
differ. So wherever an exercise is wired that way, arm-versus-fixture is checked
live at test time and the pair cannot drift in silence — which is strictly more
than `c05_ten_queens` gets, whose `--kind search` path checks only the line count
and the final line. That guarantee lives in the BUILD wiring, not in here: an arm
invoked without `--gate-expected` is back to being a snapshot.

So a green `oracle check` means the references agree with their own tables and
their own invariants. That is worth having — it is what catches a generator or
reference regression before a correct student's `_diff` does — but it is
strictly weaker than agreement with libc or with the fixtures, and it should not
be quoted as either.

For one function libc could not have served as the cross-check anyway: the c-04
subject defines an `ft_atoi` that consumes an arbitrary RUN of signs
(`" ---+--+1234ab567"` → `-1234`), so libc's `atoi`, which stops after one sign,
would be the wrong answer rather than a second opinion. See the comment on
`c_diff(num = "03")` in `c-piscine-c-04/BUILD.bazel`.

`do_op` (c-11 ex05) has **no generator and no reference** — it is a `c_program`
covered by argv cases only. It used to be listed here; it never existed.

All of the above runs as `oracle check`, wired into the suite as
**`//oracle:oracle_check`** and therefore gating every `bazel test //...`.
Without that target it is dead code, and a regression in a reference would
instead surface as a *correct* student's `_diff` going red — which is why even a
guard this modest has to be a real test.

## Build / run by hand

```sh
cd oracle
cargo run --offline -- <fn> <seed> <count>   # e.g. c03_strcmp 42 2000

# the zero-input arms ignore both numbers and print their exercise's expected
# output, so every one of them is its own regression test:
cargo run --offline -- c05_ten_queens 0 0 | cmp - ../c-piscine-c-05/tests/ex08/expected.txt
cargo run --offline -- c00_print_alphabet 0 0 | cmp - ../c-piscine-c-00/tests/ex01/expected.txt
cargo run --offline -- c00_print_reverse_alphabet 0 0 | cmp - ../c-piscine-c-00/tests/ex02/expected.txt
cargo run --offline -- c00_print_numbers 0 0 | cmp - ../c-piscine-c-00/tests/ex03/expected.txt
cargo run --offline -- c00_print_comb 0 0 | cmp - ../c-piscine-c-00/tests/ex05/expected.txt
cargo run --offline -- c00_print_comb2 0 0 | cmp - ../c-piscine-c-00/tests/ex06/expected.txt

# `bench <arm>` must print the same bytes as `<arm> 0 0` for all six, and reads
# nothing from stdin (so it cannot block on an inherited terminal):
cargo run --offline -- bench c00_print_comb2 </dev/null | cmp - ../c-piscine-c-00/tests/ex06/expected.txt

# rush01: 876 lines at the floor, 438 of them ending in a bare tab (`Error`).
# `bench` here does read a corpus, and solves each vector rather than looking it
# up — a table probe timed against a student's search would say nothing:
cargo run --offline -- rush01_solve 1 0 > /tmp/rush01.tsv
awk -F'\t' '$2==""' /tmp/rush01.tsv | wc -l      # 438 — the `Error` cases
awk -F'\t' 'NF>2' /tmp/rush01.tsv | wc -l        # 66  — the multi-solution ones
cargo run --offline -- bench rush01_solve < /tmp/rush01.tsv
```

Std-only, zero dependencies — no network needed to build.
