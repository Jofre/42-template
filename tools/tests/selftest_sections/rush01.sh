# ------------------------------------------------------------------ rush01
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# rush01_check.sh is the ONLY correctness check c-piscine-rush-01 has. It does
# not diff: the subject asks for "the first solution you encounter" and 66 of
# the 438 solvable clue vectors have more than one answer, so it VALIDATES the
# printed grid instead (a Latin square meeting all 16 visibility clues). If
# that validation ever stopped validating, every rush01 submission would pass
# and nothing else in the repo would notice.
#
# The corpus is written here rather than taken from //oracle so these stay in the
# fast selftest -- the reference needs a Rust build. Without --oracle the runner
# judges a printed grid by MEMBERSHIP: it has to be one of the solutions the
# corpus lists. Which RULE a wrong grid breaks is //oracle's rush01_validate,
# held to its own tables and properties by `oracle check`; every Bazel target
# passes --oracle, so students get the rule. Its shape is the documented
# one: <16 clues>\t<solution>..., and a line with no solution field means Error
# is the right answer. The six solvable vectors were enumerated independently of
# this repo (all 576 Latin squares of order 4 -> 438 distinct clue vectors, 372
# of them with a unique solution, which reproduces oracle/README.md's figures);
# the four unsolvable ones are vectors that enumeration proves no square yields.
mkdir -p "$WORK/r1"
{
	printf '1 2 2 2 4 1 2 3 1 2 2 2 4 1 2 3\t4321321421431432\n'
	printf '1 2 2 2 4 1 3 2 1 2 3 2 3 2 1 2\t4312324121341423\n'
	printf '1 2 2 2 4 2 1 3 1 2 2 3 3 1 2 2\t4231312424131342\n'
	printf '1 2 2 2 4 2 3 1 1 2 2 3 2 2 3 1\t4213314224311324\n'
	printf '1 2 2 2 4 3 1 2 1 2 3 3 3 3 1 2\t4132342123141243\n'
	printf '1 2 2 2 4 3 2 1 1 2 3 4 2 2 2 1\t4123341223411234\n'
	printf '3 2 4 1 1 1 3 1 2 1 1 4 4 1 2 1\t\n'
	printf '4 1 1 2 1 4 1 2 1 2 3 4 2 1 3 2\t\n'
	printf '1 2 3 1 1 1 2 4 4 3 4 4 3 3 2 2\t\n'
	printf '2 1 3 4 3 4 3 1 1 4 2 3 2 4 4 1\t\n'
} > "$WORK/r1/corpus.tsv"

# A solver that answers each solvable vector correctly and Errors on the rest.
cat > "$WORK/r1/good.sh" <<'R1_GOOD'
#!/bin/sh
case "$1" in
  "1 2 2 2 4 1 2 3 1 2 2 2 4 1 2 3") printf '4 3 2 1\n3 2 1 4\n2 1 4 3\n1 4 3 2\n' ;;
  "1 2 2 2 4 1 3 2 1 2 3 2 3 2 1 2") printf '4 3 1 2\n3 2 4 1\n2 1 3 4\n1 4 2 3\n' ;;
  "1 2 2 2 4 2 1 3 1 2 2 3 3 1 2 2") printf '4 2 3 1\n3 1 2 4\n2 4 1 3\n1 3 4 2\n' ;;
  "1 2 2 2 4 2 3 1 1 2 2 3 2 2 3 1") printf '4 2 1 3\n3 1 4 2\n2 4 3 1\n1 3 2 4\n' ;;
  "1 2 2 2 4 3 1 2 1 2 3 3 3 3 1 2") printf '4 1 3 2\n3 4 2 1\n2 3 1 4\n1 2 4 3\n' ;;
  "1 2 2 2 4 3 2 1 1 2 3 4 2 2 2 1") printf '4 1 2 3\n3 4 1 2\n2 3 4 1\n1 2 3 4\n' ;;
  *) printf 'Error\n' ;;
esac
R1_GOOD
# Always prints ONE valid Latin square. It is a real grid and it satisfies its
# own clues -- for every other vector it is simply the wrong answer, which is
# exactly what a validator that stopped checking the clues would wave through.
printf '#!/bin/sh\nprintf %s\n' "'1 2 3 4\\n2 3 4 1\\n3 4 1 2\\n4 1 2 3\\n'" > "$WORK/r1/wrong.sh"
printf '#!/bin/sh\nprintf %s\n' "'Error\\n'" > "$WORK/r1/allerr.sh"
# Not a Latin square at all: every cell the same height.
printf '#!/bin/sh\nprintf %s\n' "'1 1 1 1\\n1 1 1 1\\n1 1 1 1\\n1 1 1 1\\n'" > "$WORK/r1/notlatin.sh"
chmod +x "$WORK/r1"/*.sh

# Every call says what standard error is held to (rush01_check.sh refuses one
# that does not, exit 2), as every corpus runner's does.
R1_WHY="the selftest's solvers answer on standard output"
# And the subject's sentence a verdict quotes (--quotes), which the call
# site hands over: a toy's, with where it is from.
R1_QUOTES="$WORK/r1/quotes.tsv"
printf 'error\tToy, p.1: "display Error and a newline."\n' > "$R1_QUOTES"
r1_run() { "$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/$1.sh" \
	--corpus "$WORK/r1/corpus.tsv" --label "selftest-$1"; }

want_green "rush01: a correct solver passes"                    -- r1_run good
want_red   "rush01: a valid grid that ignores the clues fails"   -- once r1_run wrong
want_red   "rush01: Error for a solvable vector fails"           -- r1_run allerr
want_red   "rush01: a grid that is not a Latin square fails"     -- r1_run notlatin
want_out   "rush01: without --oracle, a wrong grid is named as such" \
	'not-a-solution' -- once r1_run wrong

# A SOLUTION WRITTEN WITH SEPARATORS, which the corpus format allows: `/`,
# `,`, `|` and spaces inside a solution are stripped (rush01_check.sh's
# header). The checked copy was stripped, but the solutions were joined into
# the case's record raw, with a space between them, and split again on
# spaces: "4321 3214 2143 1432" became four solutions of four digits, none
# a grid, and a correct solver failed with "not-a-solution". The same
# corpus, its solutions written with spaces, then with slashes.
for _r1s in spaced:' ' slashed:/; do
	awk -F'\t' -v OFS='\t' -v s="${_r1s#*:}" '$2 != "" {
		$2 = substr($2, 1, 4) s substr($2, 5, 4) s substr($2, 9, 4) s substr($2, 13, 4)
	} 1' "$WORK/r1/corpus.tsv" > "$WORK/r1/corpus_${_r1s%%:*}.tsv"
done
r1_sep() { "$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/$1.sh" \
	--corpus "$WORK/r1/corpus_$2.tsv" --label "selftest-$1-$2"; }
want_green "rush01: a corpus solution written with spaces in it" -- r1_sep good spaced
want_green "rush01: ...as one written with slashes"              -- r1_sep good slashed
want_red   "rush01: ...over which a wrong grid still fails"      -- r1_sep wrong spaced

# DIFF_MAX_ROWS, the one knob (finding 167): RUSH01_MAX_FAILS is gone, and
# every block the report leaves out is kept in test.outputs. An arm that
# reads a block past the first, or asserts that no block says something,
# runs with DIFF_MAX_ROWS=0, every block printed whatever the caller set.
r1_rows() { env TEST_UNDECLARED_OUTPUTS_DIR="$WORK/r1/rows" TEST_TARGET=//mod:ex00_sweep \
	DIFF_MAX_ROWS=1 "$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/allerr.sh" \
	--corpus "$WORK/r1/corpus.tsv" --label selftest-rows; }
want_out "rush01: DIFF_MAX_ROWS caps the cases it prints" \
	'5 more failing case(s) not shown here; all 6 are in' -- r1_rows
want_green "rush01: ...and keeps all of them" -- \
	"$SH" -c '[ "$(grep -c "^ CASE " "$1")" -eq 6 ]' _ "$WORK/r1/rows/differences.txt"

# A LINE PAST 8 KiB IS STILL THE PROGRAM'S. The judge built its sentences
# with sprintf("%s") over what the program printed, and mawk caps sprintf at
# 8192 bytes and exits 2 past it -- the judge's own code for a harness
# verdict -- so one long line read "HARNESS FAILURE ... Nothing above is a
# verdict on your program", with no case shown. Three of those sentences: a
# value that is no digit on a malformed input (a board of as many rows as
# lines printed), a false Error, a row that is no row. Every other case is
# answered right, so those three are all there is to judge.
{
	cat "$WORK/r1/corpus.tsv"
	printf '1 2 3 x\t\n'
} > "$WORK/r1/corpus_bad.tsv"
cat > "$WORK/r1/long.sh" <<'R1_LONG'
#!/bin/sh
x=$(printf '%9000s' '' | tr ' ' x)
case "$1" in
  "1 2 3 x") printf '%s\n' "$x" ;;
  "1 2 2 2 4 1 2 3 1 2 2 2 4 1 2 3") printf 'error%s\n' "$x" ;;
  "1 2 2 2 4 1 3 2 1 2 3 2 3 2 1 2") for r in 1 2 3 4; do printf '1 2 3 %s\n' "$x"; done ;;
  *) exec sh "${0%/*}/good.sh" "$@" ;;
esac
R1_LONG
chmod +x "$WORK/r1/long.sh"
r1_long() { "$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/long.sh" \
	--corpus "$WORK/r1/corpus_bad.tsv" --label selftest-long; }
want_red   "rush01: a line past 8 KiB gets a verdict, not a harness failure" -- once r1_long
want_broken_none "rush01: ...with no awk limit reached" 'program limit exceeded' -- once r1_long
want_broken_none "rush01: ...and no case called a harness problem" 'HARNESS' -- once r1_long
want_out   "rush01: ...naming a false Error" 'FAULT [false-error] it printed "errorxxxx' -- once r1_long
want_out   "rush01: ...a row's value that is no digit" \
	'FAULT [row-format] line 1 is not a row of this grid: value 4 is "xxxx' -- once r1_long
want_out   "rush01: ...what a malformed input printed" 'FAULT [bad-error-text]' -- once r1_long
want_out   "rush01: ...each shown line cut at the width" '[... line cut here, 8700 more bytes]' -- once r1_long
# The judge's own harness verdict is now a code awk never exits with (5), so
# an awk that does fall over is told apart: a harness problem still, shown
# with its status and its own words, never a silent one. A stand-in awk
# that falls over as the judge and only as the judge.
mkdir -p "$WORK/r1/awkbin"
printf '#!/bin/sh
for a; do [ "$a" = mode=judge ] && { echo "awk: the stand-in judge fell over" >&2; exit 2; }; done
exec %s "$@"
' \
	"$(command -v awk)" > "$WORK/r1/awkbin/awk"
chmod +x "$WORK/r1/awkbin/awk"
r1_awkfell() { (PATH="$WORK/r1/awkbin:$PATH"; export PATH; r1_run good); }
want_broken "rush01: a judge that falls over is a harness problem" \
	'this checker (its awk judge) stopped with' -- once r1_awkfell
want_broken "rush01: ...shown with its own words" 'the stand-in judge fell over' -- once r1_awkfell

# ...and a report of long lines stays under the runner's own `ulimit -f`,
# which covers its log when that is a file, as a test's is, and the blocks
# it keeps for test.outputs. Each case printed a 200000-byte line and each
# block showed it whole: the runner was killed by SIGXFSZ (153) a few blocks
# in, its log cut mid-line, and differences.txt cut short with it.
printf '#!/bin/sh\nprintf "%%200000s\\n" "" | tr " " y\n' > "$WORK/r1/wide.sh"
chmod +x "$WORK/r1/wide.sh"
r1_wide() { env TEST_UNDECLARED_OUTPUTS_DIR="$WORK/r1/wide$1" TEST_TARGET=//mod:ex00_sweep DIFF_MAX_ROWS="$1" \
	"$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/wide.sh" \
	--corpus "$WORK/r1/corpus.tsv" --label selftest-wide > "$WORK/r1/wide$1.log" 2>&1; }
want_red   "rush01: long lines on every case end in a verdict, logged to a file" -- r1_wide 40
want_out   "rush01: ...which the log holds" 'rush01_check: FAIL' -- cat "$WORK/r1/wide40.log"
r1_wide 1
want_green "rush01: ...and test.outputs keeps every case" -- \
	"$SH" -c '[ "$(grep -c "^ CASE " "$1")" -eq 10 ]' _ "$WORK/r1/wide1/differences.txt"
# stderr is never graded, and a case that wrote to it is said (finding 156).
printf '#!/bin/sh\necho "debug: $1" >&2\nexec "%s" "%s" "$@"\n' "$SH" "$WORK/r1/good.sh" > "$WORK/r1/noisy.sh"
chmod +x "$WORK/r1/noisy.sh"
want_green "rush01: a solver that also writes to stderr passes" -- once r1_run noisy
want_out   "rush01: ...and the report says so" '10 case(s) also wrote to standard error (not graded' -- \
	once r1_run noisy
# ...because the call said so: what standard error is held to is a choice at
# every call, as for every corpus runner. This one decided it in its header
# and took no choice, the one corpus runner whose call said nothing of it.
want_out   "rush01: the OK line says why stderr was not judged" \
	"Standard error was not judged: $R1_WHY" -- once r1_run noisy
want_broken "rush01: a call that says nothing of stderr refuses" \
	'say what standard error is held to' -- \
	"$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --bin "$WORK/r1/good.sh" --corpus "$WORK/r1/corpus.tsv"
# The subject's sentence a verdict quotes comes from the call site (V90): a
# call with none, or with a key this runner does not quote and none for the
# one it does, refuses (exit 2); a verdict on the error's spelling prints it.
want_broken "rush01: a call with no --quotes refuses" \
	'--quotes FILE is required' -- \
	"$SH" "$TOOLS/rush01_check.sh" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/good.sh" --corpus "$WORK/r1/corpus.tsv"
printf 'tie\tToy, p.1: "another runner\047s key."\n' > "$WORK/r1/quotes_other.tsv"
r1_other() { "$SH" "$TOOLS/rush01_check.sh" --quotes "$WORK/r1/quotes_other.tsv" --stderr-ignored "$R1_WHY" \
	--bin "$WORK/r1/good.sh" --corpus "$WORK/r1/corpus.tsv"; }
want_broken "rush01: ...a key it does not quote" "line 1: unknown key 'tie'" -- once r1_other
want_broken "rush01: ...and no line for the one it does" "no line for the key 'error'" -- once r1_other
printf '#!/bin/sh\nprintf %s\n' "'error\\n'" > "$WORK/r1/lowerr.sh"
chmod +x "$WORK/r1/lowerr.sh"
want_out "rush01: Error spelled otherwise quotes the call site's sentence" \
	'Toy, p.1: "display Error and a newline."' -- r1_run lowerr
# ...and so does every other verdict on what an input with no solution
# prints: what goes there is the subject's to say, and a runner that says it
# in its own words adds rules the subject may not have. The fakes answer as
# good.sh does, except where it prints Error: twice, nothing, or KO.
for _r1e in 'twoerr:printf "Error\\nError\\n"' 'noerr::' 'koerr:printf "KO\\n"'; do
	printf '#!/bin/sh\n_o=$("%s" "%s" "$@")\nif [ "$_o" = Error ]; then %s; else printf "%%s\\n" "$_o"; fi\n' \
		"$SH" "$WORK/r1/good.sh" "${_r1e#*:}" > "$WORK/r1/${_r1e%%:*}.sh"
	chmod +x "$WORK/r1/${_r1e%%:*}.sh"
done
want_out "rush01: two lines for Error quote the call site's sentence" \
	'Toy, p.1: "display Error and a newline."' -- once r1_run twoerr
want_broken_none "rush01: ...and add no rule of the runner's" 'Nothing may accompany it' -- once r1_run twoerr
want_out "rush01: ...and so does nothing at all" \
	'Toy, p.1: "display Error and a newline."' -- once r1_run noerr
want_broken_none "rush01: ...adding no rule of the runner's" 'an error prints Error' -- once r1_run noerr
want_out "rush01: ...and so does something else" \
	'Toy, p.1: "display Error and a newline."' -- once r1_run koerr
want_broken_none "rush01: ...adding none there either" 'Nothing else and nothing besides' -- once r1_run koerr
r1_quiet() { "$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-empty --bin "$WORK/r1/$1.sh" \
	--corpus "$WORK/r1/corpus.tsv" --label "selftest-quiet-$1"; }
want_red   "rush01: --stderr-empty fails a right answer with a message" -- once r1_quiet noisy
want_out   "rush01: ...naming the fault" 'wrote-to-stderr' -- once r1_quiet noisy
want_green "rush01: --stderr-empty passes a quiet solver" -- r1_quiet good
# THE SWEEP UNDER A SANITIZER (finding 113): memory and endings, never the
# grid. The fake answers right, and on the second unsolvable vector -- after
# its search found nothing, the path no fixed case reached -- writes what ASan
# writes and ends as abort_on_error ends a run.
printf '#!/bin/sh\ncase "$1" in\n  "%s") echo "==1==ERROR: AddressSanitizer: heap-use-after-free" >&2; kill -ABRT $$ ;;\nesac\nexec "%s" "%s" "$@"\n' \
	"4 1 1 2 1 4 1 2 1 2 3 4 2 1 3 2" "$SH" "$WORK/r1/good.sh" > "$WORK/r1/san.sh"
chmod +x "$WORK/r1/san.sh"
r1_san() { "$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --bin "$WORK/r1/$1.sh" \
	--corpus "$WORK/r1/corpus.tsv" --label "selftest-san-$1" --sanitized; }
want_red   "rush01 --sanitized: a sanitizer report is red" -- once r1_san san
want_out   "rush01 --sanitized: ...naming the vector" 'argv: "4 1 1 2 1 4 1 2 1 2 3 4 2 1 3 2"' -- \
	once r1_san san
want_out   "rush01 --sanitized: ...with the report" 'heap-use-after-free' -- once r1_san san
want_out   "rush01 --sanitized: ...headed by what it was, in words" \
	'the sanitizer stopped it at its first finding: it used a block after freeing it (heap-use-after-free)' -- once r1_san san
want_broken_none "rush01 --sanitized: ...not headed by SIGABRT's other causes (V50)" \
	'stack smashing' -- once r1_san san
want_green "rush01 --sanitized: a clean solver passes" -- once r1_san good
want_out   "rush01 --sanitized: ...saying what it judged" 'all 10 case(s) of the corpus ran under ASan/UBSan' -- \
	once r1_san good
# ...and what it could not see (finding 071's class): the sixteen values are
# an argument, laid out where the sanitizer does not watch, and no guarded
# build exists for a program's own main. Said nothing before (the wave 6
# review); argv_check.sh's replays said it already.
want_out   "rush01 --sanitized: ...and that its argument was unwatched" \
	'Reads inside the argument strings, or past argv'"'"'s end, are invisible' -- once r1_san good
want_broken_none "rush01 --sanitized: ...naming no build it does not have" '--guarded-argv' -- \
	once r1_san good
want_green "rush01 --sanitized: a wrong grid is not its finding" -- r1_san wrong
# THE PROBES UNDER A CHECKER ARE THE PLAIN REPLAY'S: one list (probe_list)
# feeds both. The memory replay once ran its own copy of the argc probes, and
# kept a two-argument vector the plain probes had dropped, so its twin ran
# inputs the target it stands in for no longer judged. These toys report a
# sanitizer error only on the probe in question: two arguments that are each
# the --gate-arg vector, and a tab inside the one argument.
printf '#!/bin/sh\nif [ "$#" -eq 2 ] && [ "$1" = "$2" ] && [ "$1" = "%s" ]; then\n  echo "==1==ERROR: AddressSanitizer: heap-use-after-free" >&2; exit 1\nfi\necho Error\n' \
	"4 3 2 1 1 2 2 2 4 3 2 1 1 2 2 2" > "$WORK/r1/san_twice.sh"
printf '#!/bin/sh\ncase "$1" in *"%s"*) echo "==1==ERROR: AddressSanitizer: stack-buffer-overflow" >&2; exit 1 ;; esac\necho Error\n' \
	"$(printf '\t')" > "$WORK/r1/san_tab.sh"
chmod +x "$WORK/r1/san_twice.sh" "$WORK/r1/san_tab.sh"
r1_probes() { _r1p=$1; shift; "$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --bin "$WORK/r1/$_r1p.sh" --label "selftest-probes" \
	--gate-arg "4 3 2 1 1 2 2 2 4 3 2 1 1 2 2 2" --probes-only --sanitized "$@"; }
want_red   "rush01 --sanitized: the argc probes are the plain replay's" -- once r1_probes san_twice --probe-argc
want_out   "rush01 --sanitized: ...two arguments, each the vector accepted alone" \
	'PROBE 2/3  argv: 2 argument(s)  -- (two arguments, each "4 3 2 1 1 2 2 2 4 3 2 1 1 2 2 2")  [sanitizer]' -- \
	r1_probes san_twice --probe-argc
want_red   "rush01 --sanitized: ...and so are the shape probes" -- once r1_probes san_tab --probe-shape
want_out   "rush01 --sanitized: ...the tab among them" '-- a tab between two values  [sanitizer]' -- \
	once r1_probes san_tab --probe-shape
# ...shown as \t: dash's echo turned the rendering's \t back into a tab (V175).
want_out   "rush01 --sanitized: ...its argument rendered" \
	'argv: "4\t3 2 1 1 2 2 2 4 3 2 1 1 2 2 2"  -- a tab between two values  [sanitizer]' -- \
	r1_probes san_tab --probe-shape
want_out   "rush01 --sanitized: ...with a key to the tab" '(byte for byte: \t a tab)' -- \
	once r1_probes san_tab --probe-shape
# ...and, like every failing block, its replay line: the memory twin's
# blocks printed none (V175's review).
want_out   "rush01 --sanitized: ...and the shape probe's replay line" \
	"replay:   ./rush01 \"\$(printf -- '4\\0113 2 1 1 2 2 2 4 3 2 1 1 2 2 2')\"" -- \
	r1_probes san_tab --probe-shape
want_out   "rush01 --sanitized: ...and the argc probe's, both arguments" \
	"replay:   ./rush01 '4 3 2 1 1 2 2 2 4 3 2 1 1 2 2 2' '4 3 2 1 1 2 2 2 4 3 2 1 1 2 2 2'" -- \
	once r1_probes san_twice --probe-argc
# The gate (runner_lib.sh's rl_gate): while the subject's own example is
# red, the probes wait, and the SKIP line names the output test they wait
# for (--gate-label). san_tab answers Error, never the example's grid.
printf 'a grid\n' > "$WORK/r1/gate_grid.txt"
want_out   "rush01: a red gate SKIPs, naming the test it waits for" \
	'SKIP — ex00_subject_output, this exercise' -- \
	env -u NO_SKIP "$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" \
		--bin "$WORK/r1/san_tab.sh" --label "selftest-probes" --gate-arg "4 3 2 1 1 2 2 2 4 3 2 1 1 2 2 2" --probes-only \
		--probe-shape --gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/r1/san_tab.sh" \
		--gate-expected "$WORK/r1/gate_grid.txt" --gate-label ex00_subject_output
want_out   "rush01 --sanitized: ...every one run" 'all 6 case(s) of the corpus ran under ASan/UBSan' -- \
	r1_probes good --probe-shape

# And the guards that protect the guard: a case list with no unsolvable case
# never tests the error path, one with no solvable case validates a program
# that only ever prints Error, and one of fewer than 8 cases proves nothing.
# The runner refuses each as a HARNESS error (exit 2, want_broken), in one
# sentence for all three that gives the counts. So each list below trips one
# guard alone, and its arm pins the counts that only that guard refuses:
# with a list of six cases, all solvable, the case-count guard refused it
# first, and the guard on Error cases could be deleted with its arm green.
# The lines are the corpus's own, a vector repeated where eight are needed.
r1_lopsided() {  # r1_lopsided LIST -- good.sh over "$WORK/r1/LIST.tsv"
	"$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/good.sh" \
		--corpus "$WORK/r1/$1.tsv" --label selftest-lopsided
}
{ head -6 "$WORK/r1/corpus.tsv"; head -2 "$WORK/r1/corpus.tsv"; } > "$WORK/r1/solvable_only.tsv"
{ tail -4 "$WORK/r1/corpus.tsv"; tail -4 "$WORK/r1/corpus.tsv"; } > "$WORK/r1/error_only.tsv"
{ head -3 "$WORK/r1/corpus.tsv"; tail -2 "$WORK/r1/corpus.tsv"; } > "$WORK/r1/five.tsv"
want_broken "rush01: a corpus with no Error case is refused" \
	'8 case(s), 8 solvable, 0 with no solution.' -- r1_lopsided solvable_only
want_broken "rush01: ...and one with no solvable case" \
	'8 case(s), 0 solvable, 8 with no solution.' -- r1_lopsided error_only
want_broken "rush01: ...and one of fewer than 8 cases" \
	'5 case(s), 3 solvable, 2 with no solution.' -- r1_lopsided five

# An input the subject says must be an error is an error, whatever a corpus
# claims. The runner once read "-w N <clues>" as a rectangle,
# a convention of this repo's own that the subject forbids ("any other input
# must be considered an error"), and a corpus listing a grid for it made the
# subject's Error a false-error. Both halves: such a corpus is refused as the
# HARNESS's mistake, and a program that prints a grid for it is told the input
# is not well formed.
R1_FLAG='-w 2 1 2 2 2 1 2 1 2 1 2'
{ cat "$WORK/r1/corpus.tsv"; printf '%s\t121221\n' "$R1_FLAG"; } > "$WORK/r1/flag_listed.tsv"
want_broken "rush01: a grid listed for a flagged input is refused" \
	'not a well-formed clue vector' -- \
	"$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/good.sh" \
		--corpus "$WORK/r1/flag_listed.tsv" --max-size 9 --label selftest-flag
{ cat "$WORK/r1/corpus.tsv"; printf '%s\t\n' "$R1_FLAG"; } > "$WORK/r1/flag.tsv"
cat > "$WORK/r1/flagged.sh" <<'R1_FLAGGED'
#!/bin/sh
case "$*" in
  "-w 2 "*) printf '1 2\n2 1\n1 2\n' ;;
  *) exec "$(dirname "$0")/good.sh" "$@" ;;
esac
R1_FLAGGED
chmod +x "$WORK/r1/flagged.sh"
want_out   "rush01: a grid for a flagged input answers bad input" \
	'this is NOT a well-formed input' -- \
	"$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/flagged.sh" \
		--corpus "$WORK/r1/flag.tsv" --label selftest-flagged

# THE PROBES (finding 153, 152). --probe-argc's two-argument probe used an
# 8-value string that is an error on its own, so Error was right whatever the
# program did with argc: good.sh above reads only $1, and it passed. The probe
# now gives a string the program must accept alone, twice.
R1_G='1 2 2 2 4 1 2 3 1 2 2 2 4 1 2 3'
printf '#!/bin/sh\n[ $# -eq 1 ] || { printf "Error\\n"; exit 0; }\nexec "$(dirname "$0")/good.sh" "$@"\n' \
	> "$WORK/r1/argc.sh"
# Two loose readers of the one argument: one splits on runs of blanks (a tab
# too) and trims both ends, one skips a '+' or a '0' in front of the first
# value. Each answers the well-formed vector like good.sh.
printf '#!/bin/sh\n[ $# -eq 1 ] || { printf "Error\\n"; exit 0; }\nc=$(printf "%%s" "$1" | tr -s " \\t" "  " | sed "s/^ //; s/ $//")\nexec "$(dirname "$0")/good.sh" "$c"\n' \
	> "$WORK/r1/loose.sh"
printf '#!/bin/sh\n[ $# -eq 1 ] || { printf "Error\\n"; exit 0; }\nc=$(printf "%%s" "$1" | sed "s/^[+0]*//")\nexec "$(dirname "$0")/good.sh" "$c"\n' \
	> "$WORK/r1/atoi.sh"
chmod +x "$WORK/r1/argc.sh" "$WORK/r1/loose.sh" "$WORK/r1/atoi.sh"
r1_probe() { _r1p=$1; shift; "$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/$_r1p.sh" \
	--label "selftest-$_r1p" "$@"; }
want_red   "rush01: --probe-argc catches a program reading one of two arguments" -- \
	once r1_probe good --corpus "$WORK/r1/corpus.tsv" --probe-argc --gate-arg "$R1_G"
want_out   "rush01: ...and says it read one and ignored the other" \
	'it read one clue string and ignored the other' -- \
	once r1_probe good --corpus "$WORK/r1/corpus.tsv" --probe-argc --gate-arg "$R1_G"
want_red   "rush01: ...without --gate-arg, from the corpus's first solvable vector" -- \
	r1_probe good --corpus "$WORK/r1/corpus.tsv" --probe-argc
want_green "rush01: a program that checks its argument count passes them" -- \
	once r1_probe argc --corpus "$WORK/r1/corpus.tsv" --probe-argc --gate-arg "$R1_G"
# THE BASE MUST BE ACCEPTED ALONE, not only well formed: a vector with no
# solution, or of another board than the required one, makes Error the right
# answer to every probe built from it, so the probes catch nothing -- good.sh
# reads only $1, and passed --probe-argc over sixteen 1s. The size is read off
# the vector; whether it has a solution is the reference's to say (--oracle,
# a toy here) or the gate's expected output's. With neither nothing can say,
# and the runner solves no board itself.
R1_DEAD='1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1'
want_broken "rush01: a base vector of another board is refused" \
	'it is the clue string of a 1x1 board, and the one required is 4x4' -- \
	r1_probe good --probes-only --probe-argc --gate-arg '1 1 1 1'
printf 'Error\n' > "$WORK/r1/gate_error.txt"
want_broken "rush01: ...and one the gate expects Error for" \
	"the gate's expected output for it (--gate-expected) is Error" -- \
	r1_probe good --probes-only --probe-argc --gate-arg "$R1_DEAD" \
		--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/r1/good.sh" \
		--gate-expected "$WORK/r1/gate_error.txt"
printf '#!/bin/sh\n[ "$1 $2" = "run rush01" ] || exit 3\nprintf "Error\\n"\n' > "$WORK/r1/oracle_error.sh"
printf '#!/bin/sh\n[ "$1 $2" = "run rush01" ] || exit 3\nprintf "4 3 2 1\\n3 2 1 4\\n2 1 4 3\\n1 4 3 2\\n"\n' \
	> "$WORK/r1/oracle_grid.sh"
printf '#!/bin/sh\necho "the reference fell over" >&2\nexit 3\n' > "$WORK/r1/oracle_fails.sh"
chmod +x "$WORK/r1/oracle_error.sh" "$WORK/r1/oracle_grid.sh" "$WORK/r1/oracle_fails.sh"
want_broken "rush01: ...and one the reference answers Error" \
	'the reference answers it Error: it has no solution' -- \
	r1_probe good --probes-only --probe-argc --gate-arg "$R1_DEAD" --oracle "$WORK/r1/oracle_error.sh"
want_broken "rush01: ...a reference that fails on it is a harness error" \
	"failed on the probes' base" -- \
	r1_probe good --probes-only --probe-argc --gate-arg "$R1_G" --oracle "$WORK/r1/oracle_fails.sh"
want_red   "rush01: ...and a base it solves keeps the probes" -- \
	r1_probe good --probes-only --probe-argc --gate-arg "$R1_G" --oracle "$WORK/r1/oracle_grid.sh"
# A probe's stderr is named as a failing probe is, PROBE k/N, and the note
# counts runs once a probe has run: it said "2 case(s) also wrote to standard
# error" over two probes and no case (V15).
printf '#!/bin/sh\n[ $# -eq 1 ] || { echo "debug: argc is $#" >&2; printf "Error\\n"; exit 0; }\nexec "$(dirname "$0")/good.sh" "$@"\n' \
	> "$WORK/r1/argc_noisy.sh"
chmod +x "$WORK/r1/argc_noisy.sh"
want_out   "rush01: a probe that wrote to stderr is named PROBE k/N's way" \
	'The first, probe 1/' -- \
	once r1_probe argc_noisy --corpus "$WORK/r1/corpus.tsv" --probe-argc --gate-arg "$R1_G"
want_out   "rush01: ...and the note counts runs, not cases" \
	'run(s) also wrote to standard error' -- \
	once r1_probe argc_noisy --corpus "$WORK/r1/corpus.tsv" --probe-argc --gate-arg "$R1_G"
# Two lists, two denominators: the last corpus case is n/n, whatever probes
# follow it (it said "CASE n/968" and then "971 validated").
printf '#!/bin/sh\n[ $# -eq 1 ] || { printf "Error\\n"; exit 0; }\ncase "$1" in\n  "%s") printf "error\\n" ;;\n  *) exec "$(dirname "$0")/good.sh" "$@" ;;\nesac\n' \
	"2 1 3 4 3 4 3 1 1 4 2 3 2 4 4 1" > "$WORK/r1/last_wrong.sh"
chmod +x "$WORK/r1/last_wrong.sh"
want_out   "rush01: the corpus's cases are counted to their own total" 'CASE 10/10  argv' -- \
	once r1_probe last_wrong --corpus "$WORK/r1/corpus.tsv" --probe-argc --gate-arg "$R1_G"
want_out   "rush01: ...and the probes to theirs" 'and 3 probe(s)' -- \
	once r1_probe argc --corpus "$WORK/r1/corpus.tsv" --probe-argc --gate-arg "$R1_G"
# --probe-shape: the argument's shape, read at strict (Rush 01's ex00_readings).
want_red   "rush01: --probe-shape catches a reader that splits on blank runs" -- \
	once r1_probe loose --probes-only --probe-shape --gate-arg "$R1_G"
want_out   "rush01: ...naming the probe it failed" 'a tab between two values' -- \
	env DIFF_MAX_ROWS=0 "$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/loose.sh" \
		--probes-only --probe-shape --gate-arg "$R1_G"
want_out   "rush01: ...as this harness's reading, not a sentence of the subject" \
	"under this harness's reading" -- \
	once r1_probe loose --probes-only --probe-shape --gate-arg "$R1_G"
want_red   "rush01: --probe-shape catches a '0' or '+' skipped in front" -- \
	r1_probe atoi --probes-only --probe-shape --gate-arg "$R1_G"
want_green "rush01: a strict reader passes every shape probe" -- \
	r1_probe argc --probes-only --probe-shape --gate-arg "$R1_G"
# A run that did not end its own way (a time limit, a crash) is a block the
# shell writes, not verdict(), and it printed the argument raw: the tab probe's
# tab reached the log as a tab (V175). Through the renderer now, as the judged
# path's, and every failing block ends with the command that runs it again,
# each argument a shell word of its exact bytes. Toys that are the strict
# reader above but for an argument holding a tab: one never ends (deferred,
# with a 1 s limit), one kills itself.
printf '#!/bin/sh\ncase "$1" in *"%s"*) exec sleep 20 ;; esac\nexec "$(dirname "$0")/argc.sh" "$@"\n' \
	"$(printf '\t')" > "$WORK/r1/tab_hang.sh"
printf '#!/bin/sh\ncase "$1" in *"%s"*) kill -SEGV $$ ;; esac\nexec "$(dirname "$0")/argc.sh" "$@"\n' \
	"$(printf '\t')" > "$WORK/r1/tab_crash.sh"
chmod +x "$WORK/r1/tab_hang.sh" "$WORK/r1/tab_crash.sh"
later_red_out "rush01: a probe that hangs shows its argument rendered" \
	'PROBE 4/6  argv: "1\t2 2 2 4 1 2 3 1 2 2 2 4 1 2 3"  -- a tab between two values' -- \
	r1_probe tab_hang --probes-only --probe-shape --gate-arg "$R1_G" --timeout 1
later_red_out "rush01: ...and the hung probe's replay line" \
	"replay:   ./rush01 \"\$(printf -- '1\\0112 2 2 4 1 2 3 1 2 2 2 4 1 2 3')\"" -- \
	r1_probe tab_hang --probes-only --probe-shape --gate-arg "$R1_G" --timeout 1
want_out   "rush01: a probe that crashes shows its argument rendered" \
	'PROBE 4/6  argv: "1\t2 2 2 4 1 2 3 1 2 2 2 4 1 2 3"  -- a tab between two values' -- \
	r1_probe tab_crash --probes-only --probe-shape --gate-arg "$R1_G"
want_out   "rush01: ...and the crashed probe's replay line" \
	"replay:   ./rush01 \"\$(printf -- '1\\0112 2 2 4 1 2 3 1 2 2 2 4 1 2 3')\"" -- \
	r1_probe tab_crash --probes-only --probe-shape --gate-arg "$R1_G"
# Under the blocks, a key to the marks their arguments showed, and none
# where they showed none.
want_out   "rush01: ...and a key to the tab its argument shows" '(byte for byte: \t a tab)' -- \
	r1_probe tab_crash --probes-only --probe-shape --gate-arg "$R1_G"
# So does a block verdict() wrote: a corpus case judged wrong.
want_out   "rush01: a case judged wrong prints its replay line" \
	"replay:   ./rush01 '2 1 3 4 3 4 3 1 1 4 2 3 2 4 4 1'" -- \
	once r1_probe last_wrong --corpus "$WORK/r1/corpus.tsv" --probe-argc --gate-arg "$R1_G"
want_broken_none "rush01: ...and no key, where no argument shows a mark" 'byte for byte' -- \
	once r1_probe last_wrong --corpus "$WORK/r1/corpus.tsv" --probe-argc --gate-arg "$R1_G"
# A runner states no reading of its own and quotes no subject (V41): where a
# grid came out and Error was the answer -- a shape probe, no argument or an
# empty one, two arguments -- the verdict says which question decides and
# leaves the reading to the target's hints, which a call site hands it. A
# program that prints a grid for every argument list but the gate's.
printf '#!/bin/sh\n[ $# -eq 1 ] && [ "$1" = "%s" ] && exec "$(dirname "$0")/good.sh" "$1"\nprintf "1 2 3 4\\n2 3 4 1\\n3 4 1 2\\n4 1 2 3\\n"\n' \
	"$R1_G" > "$WORK/r1/grid.sh"
chmod +x "$WORK/r1/grid.sh"
r1_grid() { env DIFF_MAX_ROWS=0 "$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" \
	--bin "$WORK/r1/grid.sh" --probes-only --probe-shape --probe-argc --gate-arg "$R1_G"; }
want_out   "rush01: a grid where Error was the answer is a false solution" 'FAULT [false-solution]' -- once r1_grid
want_broken_none "rush01: ...whose verdict states no reading of its own" 'single spaces' -- once r1_grid
want_broken_none "rush01: ...nor what goes before a digit" "a '0' or a '+'" -- once r1_grid
want_broken_none "rush01: ...nor quotes the subject's sentence" 'must be considered an error' -- once r1_grid
want_broken_none "rush01: ...in either wording" 'must be treated as an error' -- once r1_grid
r1_grid_whole() {  # all nine blocks are printed, whatever DIFF_MAX_ROWS the caller exported
	_r1gw=$(export DIFF_MAX_ROWS=1 && r1_grid)
	_r1grc=$?
	[ "$_r1grc" -le 1 ] || { printf '%s\n' "$_r1gw"; return "$_r1grc"; }
	_r1gn=$(printf '%s\n' "$_r1gw" | grep -c '^   FAULT \[')
	[ "$_r1gn" -ge 9 ] && return 0
	echo "under DIFF_MAX_ROWS=1 it printed $_r1gn FAULT line(s) of 9"
	return 1
}
want_green "rush01: ...each read in all nine blocks, whatever DIFF_MAX_ROWS is" -- r1_grid_whole
# ...and where nothing came out for two arguments, the no-output verdict says
# why Error was the answer by counting them, never by the subject's sentence
# that the only acceptable input is one (V41's review). A program that prints
# nothing for every argument list but the gate's.
printf '#!/bin/sh\n[ $# -eq 1 ] && [ "$1" = "%s" ] && exec "$(dirname "$0")/good.sh" "$1"\nexit 0\n' \
	"$R1_G" > "$WORK/r1/mute.sh"
chmod +x "$WORK/r1/mute.sh"
r1_mute() { env DIFF_MAX_ROWS=0 "$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" \
	--bin "$WORK/r1/mute.sh" --probes-only --probe-argc --gate-arg "$R1_G"; }
want_out   "rush01: two arguments and no output is a no-output verdict" \
	'one more than the subject' -- once r1_mute
want_broken_none "rush01: ...which quotes no sentence about the acceptable input" \
	'only acceptable input' -- once r1_mute
# ...and replays both arguments, each a word of its own.
want_out   "rush01: ...whose replay line passes both arguments" \
	"replay:   ./rush01 '$R1_G' '$R1_G'" -- once r1_mute
want_broken "rush01: --probe-shape needs the vector to vary" 'none was given' -- \
	r1_probe argc --probes-only --probe-shape
want_broken "rush01: ...and refuses a malformed one, which could catch nothing" \
	'could catch nothing' -- \
	r1_probe argc --probes-only --probe-shape --gate-arg "4 3 2 1 1 2 2 2"
want_broken "rush01: --probes-only with no probe is refused" 'it would check nothing' -- \
	r1_probe argc --probes-only --gate-arg "$R1_G"
# A probe answered with neither Error nor a grid is told why Error was the
# answer IN ITS OWN TERMS. The FAULT line reused the corpus's "this input has
# no solution" for a probe, while the header just above it said the input was
# malformed under a reading. Each program answers the gate vector like
# good.sh, and every other argument list with "hello" (or with nothing).
printf '#!/bin/sh\n[ $# -eq 1 ] && [ "$1" = "%s" ] && exec "$(dirname "$0")/good.sh" "$1"\nprintf "hello\\n"\n' \
	"$R1_G" > "$WORK/r1/hello.sh"
printf '#!/bin/sh\n[ $# -eq 1 ] && [ "$1" = "%s" ] && exec "$(dirname "$0")/good.sh" "$1"\nexit 0\n' \
	"$R1_G" > "$WORK/r1/silent.sh"
chmod +x "$WORK/r1/hello.sh" "$WORK/r1/silent.sh"
want_out   "rush01: a shape probe's wrong error text names the reading" \
	"it printed something else; under this harness's reading, this argument is not the clue string's one shape" -- \
	r1_probe hello --probes-only --probe-shape --gate-arg "$R1_G"
want_broken_none "rush01: ...and never says the input has no solution" 'has no solution' -- \
	env DIFF_MAX_ROWS=0 "$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/hello.sh" \
		--probes-only --probe-shape --probe-argc --gate-arg "$R1_G"
want_out   "rush01: a two-argument probe's names the second argument" \
	"it printed something else; the program was given two arguments, one more than the subject's launch line passes" -- \
	env DIFF_MAX_ROWS=0 "$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/hello.sh" \
		--probes-only --probe-argc --gate-arg "$R1_G"
want_out   "rush01: a probe answered with nothing says why it is an error" \
	"it printed nothing at all; under this harness's reading, this argument is not the clue string's one shape" -- \
	r1_probe silent --probes-only --probe-shape --gate-arg "$R1_G"
want_out   "rush01: ...and an input with no solution keeps its own words" \
	'it printed nothing at all; this input has no solution' -- \
	env DIFF_MAX_ROWS=0 "$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/silent.sh" \
		--corpus "$WORK/r1/corpus.tsv" --label selftest-silent

# Bonus sizes are reported in the board's own terms. A 5x5 line (one solution,
# from the bonus reference's complete arm) ahead of the 4x4 corpus: a program
# that prints something else there is shown a row as wide as the board, not a
# 4x4 one, and one that runs out of time there is told it was slow on a large
# board, not that its search never ends -- while the same timeout on a 4x4
# keeps the old sentence. --timeout 1 keeps the two timeout arms to a second.
R1_FIVE='2 1 2 3 4 3 3 2 2 1 2 1 3 3 4 3 3 2 3 1'
{ printf '%s\t4531251243231543452112435\n' "$R1_FIVE"; cat "$WORK/r1/corpus.tsv"; } \
	> "$WORK/r1/five.tsv"
# Each answers the corpus like good.sh except on one line.
r1_except() {  # r1_except NAME CLUES COMMAND
	printf '#!/bin/sh\ncase "$1" in\n  "%s") %s ;;\n  *) exec "$(dirname "$0")/good.sh" "$@" ;;\nesac\n' \
		"$2" "$3" > "$WORK/r1/$1.sh"
	chmod +x "$WORK/r1/$1.sh"
}
r1_except five_notgrid "$R1_FIVE" "printf 'hello\\n'"
r1_except five_slow "$R1_FIVE" "exec sleep 5"
r1_except slow4 "1 2 2 2 4 1 2 3 1 2 2 2 4 1 2 3" "exec sleep 5"
want_out   "rush01: not-a-grid shows a row as wide as the board" \
	'each line "d d d d d"' -- \
	"$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/five_notgrid.sh" \
		--corpus "$WORK/r1/five.tsv" --max-size 9 --label selftest-five
want_out   "rush01: a TIMEOUT on a large board says so" \
	'ran out of time on a large board' -- \
	"$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/five_slow.sh" \
		--corpus "$WORK/r1/five.tsv" --max-size 9 --timeout 1 --label selftest-five-slow
want_broken_none "rush01: a TIMEOUT on a 4x4 is not blamed on size" \
	'large board' -- \
	once "$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/slow4.sh" \
		--corpus "$WORK/r1/five.tsv" --max-size 9 --timeout 1 --label selftest-slow4
# ...which proves nothing unless a TIMEOUT happened there at all: an arm that
# only asserts an absence passes on a run that never timed out.
want_out   "rush01: ...though it is reported as a TIMEOUT" \
	'TIMEOUT: it did not finish within 1s' -- \
	once "$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/slow4.sh" \
		--corpus "$WORK/r1/five.tsv" --max-size 9 --timeout 1 --label selftest-slow4
# The sweep gives up after RUSH01_MAX_TIMEOUTS runs that did not finish, and
# says why in the board's terms too: slow on a large board is not a hang.
want_out   "rush01: STOPPED on large boards says they were slow" \
	'STOPPED after 1 run(s) that ran out of time on a large board' -- \
	env RUSH01_MAX_TIMEOUTS=1 "$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/five_slow.sh" \
		--corpus "$WORK/r1/five.tsv" --max-size 9 --timeout 1 --label selftest-five-stop
want_out   "rush01: ...and on a 4x4, that it never finished" \
	'STOPPED after 1 run(s) that never finished' -- \
	env RUSH01_MAX_TIMEOUTS=1 "$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/slow4.sh" \
		--corpus "$WORK/r1/five.tsv" --max-size 9 --timeout 1 --label selftest-slow4-stop

# ...and when the sweep did NOT stop (V85), the one 4x4 run past its own
# limit was counted among the cases "judged wrong" ("1 of 10"). It did not
# finish, so it is said apart, red, and never judged (ruling R4).
r1_slow4() { "$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" \
	--bin "$WORK/r1/slow4.sh" --corpus "$WORK/r1/corpus.tsv" --timeout 2 --label selftest-slow4-dnf; }
later_red_out "rush01: a run past its own limit is counted apart" \
	'and 1 did not finish within 2s each' -- r1_slow4
later_red_none "rush01: ...never as judged wrong" '1 of 10 case(s) judged wrong' -- r1_slow4
# ...and its note is indented as the verdict's other lines are (14), not 2.
later_red_out "rush01: ...said in line with the verdict above it" \
	'              An infinite loop, or a program too slow for these inputs.' -- r1_slow4

# A solver that never built is not 438 wrong grids.
cp "$STANDIN_BIN" "$WORK/r1/built_nothing.sh"
want_red   "rush01: a stand-in is red"                         -- once r1_run built_nothing
want_out   "rush01: ...says the code did not build" "$STANDIN_SAYS" -- once r1_run built_nothing
want_broken_none "rush01: ...and grades no grid" 'solvable' -- once r1_run built_nothing
# ...but under a memory checker it is a SKIP, as every memory layer's is
# (tools/runner_lib.sh, RL_STANDIN): the output layer tells this story, and
# NO_SKIP=1 turns the skip red.
want_out   "rush01 --sanitized: a stand-in is a SKIP" 'was never built' -- \
	env -u NO_SKIP "$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --bin "$WORK/r1/built_nothing.sh" \
		--corpus "$WORK/r1/corpus.tsv" --label selftest-standin --sanitized
want_red   "rush01 --sanitized: ...and NO_SKIP=1 turns it red" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --bin "$WORK/r1/built_nothing.sh" \
		--corpus "$WORK/r1/corpus.tsv" --label selftest-standin --sanitized

# ITS HINTS, by the one rule (finding 149). It printed clues.tsv verbatim --
# the maintainers' '#' header included, as hints -- twenty lines deep. Now
# only the hint column, never a '#' line, at most CLUE_MODE of them (3).
{
	printf '# a maintainer note, never a hint\n'
	printf 'first hint\nsecond hint\nthird hint\nfourth hint\nfifth hint\n'
} > "$WORK/r1/clues.tsv"
want_broken_none "rush01: a '#' line of its clues is never a hint" \
	'maintainer note' -- \
	"$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/wrong.sh" \
		--corpus "$WORK/r1/corpus.tsv" --clues "$WORK/r1/clues.tsv" --label selftest-clues
want_out "rush01: ...and at most three hints show, the rest counted" \
	'(2 more -- CLUE_MODE=all shows every one)' -- \
	"$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/wrong.sh" \
		--corpus "$WORK/r1/corpus.tsv" --clues "$WORK/r1/clues.tsv" --label selftest-clues
# A sweep keys its rows in the program's one clues.tsv by the name it passes
# as --case (ruling R7), beside the rows of the program's cases: it shows
# its own, never a case's.
printf 'Which grid did the sweep judge?\tsweep\nWhat did Error answer?\tnoarg\n' > "$WORK/r1/clues_keyed.tsv"
want_out "rush01: --case shows the rows keyed to the sweep" 'Which grid did the sweep judge?' -- \
	once "$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/wrong.sh" \
		--corpus "$WORK/r1/corpus.tsv" --clues "$WORK/r1/clues_keyed.tsv" --case sweep --label selftest-clues
want_broken_none "rush01: ...and none keyed to a case of the program" 'What did Error answer?' -- \
	once "$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/wrong.sh" \
		--corpus "$WORK/r1/corpus.tsv" --clues "$WORK/r1/clues_keyed.tsv" --case sweep --label selftest-clues

# THE BONUS CAP (finding 148). A bonus-size run that runs out of time is
# excused -- slowness on an optional part is not a verdict -- but it used to be
# excused without end: 26 of them at 10s each once took a sweep to 263s of a
# 300s limit with nothing on screen. After RUSH01_MAX_TIMEOUTS (3) of them the
# other bonus sizes are not tried, and the 4x4 cases still are.
{
	for _i in 1 2 3 4 5; do printf '%s\t4531251243231543452112435\n' "$R1_FIVE"; done
	cat "$WORK/r1/corpus.tsv"
} > "$WORK/r1/bonus_many.tsv"
later_status "rush01: slow bonus sizes are excused, but only three" \
	0 '2 bonus-size case(s) not attempted' -- \
	"$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/five_slow.sh" \
		--corpus "$WORK/r1/bonus_many.tsv" --timeout 3 --label selftest-bonus-cap

# AND THE TEST'S OWN LIMIT. A 4x4 case that never ends, with each run's own cap
# (10s) above what the test has left: the sweep stops at the test's budget and
# says which case it was on, instead of Bazel killing it silently.
# It hangs on the THIRD vector, not the first: the case it names was one too
# low (it said "case 2 of 10" for the third, "case 0" for the first), which an
# arm hanging on case 1 and grepping the phrase could not see.
r1_except hang4 "1 2 2 2 4 2 1 3 1 2 2 3 3 1 2 2" "exec sleep 30"
later_red_out "rush01: a sweep past the test's limit stops, naming the case" \
	'too slow on case 3 of 10, the one running when the time ran out' -- \
	$SHORT "$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/hang4.sh" \
		--corpus "$WORK/r1/corpus.tsv" --label selftest-budget
later_red_out "rush01: ...and how many were not tried" \
	'The remaining 7 case(s) were not tried.' -- \
	$SHORT "$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/hang4.sh" \
		--corpus "$WORK/r1/corpus.tsv" --label selftest-budget
# Wrong on the first vector (Error for a solvable one), then out of time on
# the third: the wrong answer is a verdict, and the report says so rather
# than filing it as a busy machine.
printf '#!/bin/sh\ncase "$1" in\n  "%s") exec sleep 30 ;;\n  "%s") printf "Error\\n" ;;\n  *) exec "$(dirname "$0")/good.sh" "$@" ;;\nesac\n' \
	"1 2 2 2 4 2 1 3 1 2 2 3 3 1 2 2" "1 2 2 2 4 1 2 3 1 2 2 2 4 1 2 3" > "$WORK/r1/wrong_hang.sh"
chmod +x "$WORK/r1/wrong_hang.sh"
later_red_out "rush01: ...a wrong answer before it stays a verdict" \
	'The 1 case(s) judged wrong before that are a verdict' -- \
	$SHORT "$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/wrong_hang.sh" \
		--corpus "$WORK/r1/corpus.tsv" --label selftest-budget-wrong
# ...and a run that ran out of its OWN limit before the stop is named as
# that (V84): this sweep counts its own, and the stop said each case before
# it "ended within its own limit". The first vector waits past its 2 s,
# every other case takes 0.4 s, and 28 of them outgrow the test's 9 s.
{
	cat "$WORK/r1/corpus.tsv"
	sed 1d "$WORK/r1/corpus.tsv"
	sed 1d "$WORK/r1/corpus.tsv"
} > "$WORK/r1/corpus28.tsv"
printf '#!/bin/sh\ncase "$1" in\n  "%s") exec sleep 30 ;;\n  *) sleep 0.4; exec "$(dirname "$0")/good.sh" "$@" ;;\nesac\n' \
	"1 2 2 2 4 1 2 3 1 2 2 2 4 1 2 3" > "$WORK/r1/hang_first.sh"
chmod +x "$WORK/r1/hang_first.sh"
later_red_out "rush01: ...and a run past its own limit before it is named" \
	'ran out of their own time limit' -- \
	$SHORT "$SH" "$TOOLS/rush01_check.sh" --quotes "$R1_QUOTES" --stderr-ignored "$R1_WHY" --bin "$WORK/r1/hang_first.sh" \
		--corpus "$WORK/r1/corpus28.tsv" --timeout 2 --label selftest-budget-hung

