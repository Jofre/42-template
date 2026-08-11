# Reference

**For:** anyone who knows what they want and needs to look it up.
**Nothing here explains itself** — the explanations are in
[testing.md](testing.md), [environment.md](environment.md) and
[design.md](design.md). This page is tables.

---

## The four levels

Every test carries a **layer** tag naming what kind of check it is, and each
layer sits at one of four levels. The levels are cumulative: `strict` runs
everything in `basic` too.

| level | means |
|---|---|
| `basic` | failing this is an outright KO on 42's Moulinette |
| `strict` | a real KO, but conditional on the evaluator's own `main()` |
| `robust` | rigour this repo adds; 42 does not check it |
| `complete` | portability and cost; informative more often than not |

`tools/defs.bzl`'s `_LAYER_LEVEL` is the machine-readable source of this
mapping — if this table and that constant ever disagree, the constant is right.

```sh
bazel test //c-piscine-c-05:basic       # one module, one level
bazel test //c-piscine-c-05:complete    # same as //c-piscine-c-05/...
```

## Suites

| suite | runs |
|---|---|
| `//<module>:exNN` | every layer of one exercise |
| `//<module>:basic` … `:complete` | one level, whole module |
| `//<module>/...` | the whole module |
| `//...` | the whole repo |

The per-exercise suites are generated from the exercises found under `tests/`,
so a module gains one the moment it gains an exercise.

## The layers

| tag | level | checks |
|---|---|---|
| `norm` | basic | norminette (C) / shell syntax + shellcheck |
| `compile` | basic | clean under **both** clang-12 and gcc-10 at `-Wall -Wextra -Werror` |
| `output` | basic | what the program printed, against the expected fixture |
| `files` | basic | the deliverable holds exactly the files the subject names |
| `forbidden` | basic | only the functions the subject authorises are called |
| `prototype` | basic | your definition matches the signature the subject fixes |
| `symbols` | strict | the file exports exactly what the subject names; helpers are `static` |
| `valgrind` | strict | no leaks or invalid access, for `malloc` exercises |
| `diff` | robust | a large seeded corpus, against the Rust reference in `//oracle` |
| `diff_asan` | robust | the same corpus under ASan/UBSan |
| `asan` | robust | adversarial memory probes, and every program case under ASan/UBSan |
| `allocfail` | robust | one `malloc` refused at a time; the error must be reported, not dereferenced |
| `ilp32` | complete | the same cases where `long` is no wider than `int` |
| `perf` | complete | how cost **grows** with input size, in time and memory |
| `cycles` | complete | instructions per unit of work, via callgrind |
| `oracle` | complete | the reference's own cross-checks (`//oracle:oracle_check`) |
| `selftest` | complete | the harness's own guards (`//tools/tests:selftest*`) |

`norm`, `compile`, `files`, `forbidden` and `prototype` are green on a fresh
stub. `output` is the one that is red until you write the exercise.

**One exception, and the triage knows about it:** c-08's exercises are HEADERS,
and a header that defines nothing cannot compile the subject's own `main` — so
those are red at `compile` while still stubs. `first_red.sh` asks `stub_check`
before blaming a `compile` red on you, which is why it never does there.
[testing.md](testing.md#which-red-should-i-fix-first) says the same from the
triage's side, and `docs/publishing.md` calls it "c-08's documented `c_header`
exception".

`oracle` and `selftest` live outside every module, so only a whole-repo
`bazel test //...` reaches them — no per-module suite and no submit gate can.

## Which layers wait for which

A layer that cannot say anything useful yet prints `SKIP —` and exits 0, so the
suite stays green on a machine that cannot host it. **`--test_env=NO_SKIP=1`
forces every one of them open** and turns a missing tool into a failure.

| layer | stays quiet until | why |
|---|---|---|
| `diff`, `diff_asan` | the exercise's `output` fixture passes | fuzzing a wrong answer reports the same wrongness thousands of times |
| `valgrind` | same | ditto, and a stub leaks nothing |
| `cycles` | same | the cost of a wrong answer is not information |
| `perf` | `output`, `diff` **and** `asan` pass | measuring how a broken thing scales says nothing |
| `ilp32` | the 64-bit build passes | otherwise it reports the same failure twice, in an unfamiliar place |
| any layer | its tool is available | a missing valgrind is a gap, not a pass — `NO_SKIP=1` says so |

## Flags

```sh
bazel test //...                          # everything
bazel test //c-piscine-c-00/...           # one module
bazel test //c-piscine-c-01:ex02_output   # a single target

bazel test //... --keep_going             # report every failure, not the first
bazel test //... --nocache_test_results   # re-run even a cached PASS
bazel test //... --test_output=errors     # print the log of failing tests
bazel test //... --test_tag_filters=norm  # one layer, whole repo

# "show me everything that is wrong right now"
bazel test //... --keep_going --nocache_test_results --test_output=errors
```

`--test_tag_filters` also filters targets you name explicitly, which is why the
per-module `:basic` / `:strict` / `:robust` / `:complete` suites exist — ask for
a suite, not a filter.

## Environment variables

Bazel does **not** pass your shell environment into a test, so these reach a
runner only via `--test_env=NAME=VALUE`. Every default is what the runner uses
when unset; none of them need setting for an ordinary run.

| variable | default | does |
|---|---|---|
| `NO_SKIP` | `0` | `1` forces every gate open; a missing tool becomes a failure |
| `CLUE_MODE` | first 3 hints | `all`, or a number: how many `HINTS` lines a failing table prints |
| `DIFF_TIMEOUT` | `30` | seconds one program run gets under the diff runner |
| `ARGV_TIMEOUT` | `5` | the same, per scenario, for argv-table exercises |
| `VALGRIND_TIMEOUT` | `60` | seconds a valgrind run gets |
| `VALGRIND_LOG_CAP` | 8 MiB | `ulimit -f` cap on what a valgrind run may write |
| `MIN_DIFF_CASES` | `16` | fewer cases than this fails, rather than reporting a green "0 cases" |
| `PERF_TIMEOUT` | `25` | seconds one `perf` measurement gets |
| `PERF_MIN_BASELINE_MS` | `20` | below this, `perf` prints no ratio rather than dividing by noise |
| `MEM_NOISE_KIB` | `512` | RSS growth below this band is reported as flat |
| `CYCLES_OPT` | `-O2` | what `cycles` builds at; Bazel's `fastbuild` is `-O0` |
| `MEM_CC` | `clang-12` | compiler for the adversarial `asan` probes |
| `HEADER_CC` | `cc` | compiler for the header-driven `output` tests |
| `PROTOTYPE_CC` | `cc` | compiler for the `prototype` layer |
| `SELFTEST_CC` | `cc` | compiler the `selftest` fixtures are built with |
| `ILP32_CC` | unset | a 32-bit compiler to try first, when the pinned zig is unavailable |
| `ZIG_CACHE_HOME` | `$TMPDIR/zig-cache-42` | shared on purpose; per-test isolation costs ~15s each |
| `ASAN_OPTIONS`, `UBSAN_OPTIONS` | unset | appended after the harness's own, so your key wins |
| `ALLOCFAIL_TIMEOUT` | `10` | seconds one allocation-failure run gets |
| `ALLOCFAIL_MAX` | `64` | how many allocation sites the layer walks before stopping |
| `ALLOCFAIL_LOG_CAP` | 1 MiB | `ulimit -f` cap on what an allocation-failure run may write |
| `ALLOCFAIL_CC` | `cc` | compiler for the allocation-failure harness |
| `ALLOCFAIL_SHIM` | built in | an alternative failing-malloc shim to preload |
| `MIN_ARGV_CASES` | `12` | floor for the argv differential corpus, as `MIN_DIFF_CASES` is for the streamed one |
| `MIN_FILE_CASES` | `20` | the same floor for the file differential corpus |
| `DIFF_MAX_ROWS` | `40` | how many differing cases a diff report prints before it tallies the rest |
| `PERF_REPEATS` | `3` | how many times `perf` measures before taking the best |
| `PROGNAME_TIMEOUT` | `10` | seconds the argv[0] check gets per run |
| `BSQ_TIMEOUT` | `10` | seconds one bsq map gets |
| `BSQ_MAX_FAILS` | `8` | how many differing maps bsq prints before it tallies |
| `RUSH01_TIMEOUT` | `10` | seconds one rush-01 clue vector gets |
| `RUSH01_MAX_FAILS` | `5` | how many invalid grids the sweep prints before it tallies |
| `RUSH01_MAX_TIMEOUTS` | `3` | how many timeouts the sweep tolerates before calling it a hang |
| `FORBIDDEN_CC` | `cc` | compiler for the forbidden-symbol layer's link probe |
| `SYMBOLS_CC` | `cc` | compiler for the `symbols` layer |
| `SUBMIT_GATE` | `basic` | which level `//tools:submit` must be green at before it pushes |
| `NO_C_PISCINE_PRIME` | unset | set to anything to stop `prime.sh --background` firing from a shell profile |

`bazel run` targets **do** inherit your shell environment, so a plain `export`
is enough for these:

| variable | default | does |
|---|---|---|
| `SUBMIT_GATE` | `.submit-level`, else `basic` | which level the pre-push gate demands |
| `SUBMIT_GATE_OUTPUT_BASE` | `$HOME/.cache/_bazel_submit_gate` | the gate's own Bazel output base |
| `C_PISCINE_SCRATCH` | chosen by `setup.sh` | where Bazel's state goes |
| `NO_C_PISCINE_PRIME` | unset | set to stop the background first-build warm-up |
| `LOGIN42`, `EMAIL42` | `.vscode/settings.json` | the identity `submit` and `gen_header` use |
| `HEADER_ART` | `tools/header_art.txt` | the ASCII art `gen_header` draws |

## Run targets

| command | does |
|---|---|
| `bazel run //tools:init` | record your 42 login and email |
| `bazel run //tools:prime` | download and build everything once, on demand |
| `bazel run //tools:gen_header` | print a norminette-valid 42 header |
| `bazel run //tools:reset_headers` | re-stamp existing headers after an identity change |
| `bazel run //tools:submit` | test, then push each green module to Vogsphere |
| `bazel run //tools:generate` | rebuild a shell module's deliverables |
| `bazel run //tools:conventions` | the house-style gate over the repo |
| `bazel run //tools:env_drift` | compare this machine against `tools/pins.tsv` |
| `bazel run //tools:stub_check` | prove no deliverable holds an answer |
| `… \| sh tools/first_red.sh` | one next objective, plus a module-sized summary |
| `… \| sh tools/first_red.sh --all` | ... and one line per exercise |

## Layout

```
c-piscine-c-NN/
  deliverable/exNN/    <- your solution stubs (this is what gets submitted)
  tests/exNN/          <- harness + expected output (never submitted)
  BUILD.bazel          <- test targets, built from the macros in //tools
c-piscine-rush-NN/     <- the three group projects; see docs/rushes.md
c-piscine-bsq/         <- the final project. Same shape as a rush: one
  deliverable/ex00/       deliverable, a Makefile, no source filenames fixed
  tests/ex00/             by the subject
c-piscine-shell-NN/
  generators/exNN.sh   <- your commands (the answer); produce the deliverable
  deliverable/         <- generated, gitignored
tools/                 <- the Bazel macros (defs.bzl), the test runners, and
                          every `bazel run` target above. pins.tsv states the
                          expected tool versions; deb.bzl fetches campus's
                          exact builds
oracle/                <- the Rust reference the `diff` layers check against —
                          readable, not pasteable
docs/                  <- this documentation
AGENTS.md              <- rules for AI agents: didactic only, no exercise answers
```
