#!/bin/sh
# rush02_check.sh — differential check for c-piscine-rush-02.
#
# Runs the student's ./rush-02 once per number against a corpus the Rust
# reference generated, and reports the first differences, one block each.
#
# EVERY BYTE OF A SHOWN CASE IS SHOWN. The report was a fixed-width table,
# cutting the number at 24 characters and both strings at 34 without a mark --
# in the runner that exists for long numbers -- and a generated dictionary was
# overwritten by the next case and deleted on exit, so a failing case could be
# neither read nor replayed (finding 158). Now the number is whole, EXPECTED
# and GOT go through tools/runner_lib.sh's rl_vis (\xHH for a byte that is not
# printable, \n for a line break), the first differing character is named,
# and a failing case's generated dictionary is kept in test.outputs, with the
# command that replays it.
#
# WHY THIS IS ONE EXEC PER CASE, unlike every other differential layer here.
# c_diff streams a 400k-line corpus through ONE process reading stdin, which is
# what makes that layer cheap. rush-02 is a program that takes its number on the
# command line, so each case is a fork+exec: the count has to stay in the
# hundreds, not the hundreds of thousands. That is a property of the subject,
# not a shortcut.
#
# WHY A WHOLE-OUTPUT COMPARISON NEVER GATES.
# The subject pins four outputs and no composition rule. `forty two` and `one
# hundred thousand` fix the separator and the group/scale shape; they do not
# settle whether 101 reads "one hundred one" or "one hundred and one", nor
# whether a leading group of one is spelled out. Bonus 1 then legalises "-", ","
# and "and" outright. So a disagreement here is EVIDENCE, not a verdict: it may
# mean a bug, or it may mean the team answered a question the subject left open.
# The targets that compare whole outputs are tagged `manual` for that reason --
# run them when you want them, and read their output as a second opinion
# rather than a grade.
#
# WHAT GATES: --settled. Some differences no reading explains, and the
# subject states each in words (finding 160: they were in the manual targets
# only, so every suite a student runs stayed green on a program that refused
# every number past unsigned int, or printed English of its own):
#   * "Error" for a number of the corpus. Every one is a valid and positive
#     integer, and "Error" is the subject's answer to one that is not.
#   * "Dict Error" where the reference spelled the number. The corpus gives
#     such a case a dictionary holding every key of the reference
#     dictionary, which spell every number up to 42 digits under every
#     reading: none needs a key the reference set lacks.
#   * Output that is not the dictionary's values with separators between
#     them ("The values inside it must be used to print the result"). The
#     separators are a space and bonus 1's "-", "," and "and", so every
#     reading of the composition passes this; English typed into the
#     program does not, against a dictionary whose values are random.
#   * Nothing at all, and a run that does not end by itself.
#   * The two shapes the named cases at basic hold as every reading spells
#     them (BUILD.bazel, "what the subject states in words"): a number below
#     100 with a key of its own -- a teen, a ten, a unit -- is that key's
#     value alone, and a round number in the "<group> <scale>" shape of the
#     subject's "one hundred thousand", the group one key other than one, is
#     the group's value and the scale's. Every such key is one the
#     reference dictionary (--dict) holds: a key a dictionary adds, such as
#     45 beside 40 and 5, is one whose use the subject leaves open. They used to pass here as "a
#     reading the subject leaves open" while ex00_teen_output failed the same
#     spelling at basic (the mutation run of 2026-10-03: "three hundred ten
#     eight" and "seven million thousand" passed this target).
# Any other difference -- "and", a leading "one", another decomposition, a
# spelling of a number past the dictionary that combines scale words -- is
# shown as information and passes: composition is not judged here. THE CORPUS CONTRACT this rests on
# (oracle/src/rush02.rs): every number is a valid and positive integer, and
# a case that expects words names a dictionary with every reference key
# (rush02_words uses --dict, ref.dict; rush02_dicts drops a key only where it
# expects "Dict Error").
#
# WHAT IS COMPARED is the whole of standard output, byte for byte: the
# reference's words and the newline every subject transcript shows after them
# (`| cat -e` ends each in `$`). It was read through $( ), which drops every
# trailing newline, so a program that printed none, or two, agreed. Standard
# error is compared only where the call holds it empty (--stderr-empty, below);
# otherwise a case that wrote to it is counted and the first one shown, pass or
# fail (finding 156). --settled judges the words, not the bytes: see WHAT
# GATES above.
#
# UNDER A MEMORY CHECKER (finding 113): --sanitized replays every case on the
# ASan build and --valgrind a sample under memcheck, judging memory and how
# each run ended and never the words (tools/runner_lib.sh, "A CORPUS UNDER A
# MEMORY CHECKER"); --symbolizer PATH --symbolizer-lib FILE, with --sanitized,
# name each frame of a report's stack (rl_sanitizers). That asserts what every reading agrees on -- p.7 itself
# asks for heap memory to be freed -- so those targets are not `manual`.
#
# Usage:
#   rush02_check.sh --bin PATH --dict PATH --oracle PATH
#                   [--fn NAME] [--seed N] [--count N] [--show N] [--settled]
#                   [--sanitized | --valgrind PATH --valgrind-tools FILE
#                    [--sample N] [--rule FILE]]
#                   [--gate-differ PATH --gate-bin PATH --gate-expected PATH
#                    --gate-number N]
#                   (--stderr-empty | --stderr-ignored REASON)
#
#   --show N       how many failing cases to print (default DIFF_MAX_ROWS, 40;
#                  0 prints all); every one is kept in test.outputs either way
#   --stderr-empty            a case also fails when the program writes
#                             anything to standard error, its words right or not
#                             (under --settled too: a FAILS line says so)
#   --stderr-ignored REASON   standard error is not judged: it is shown beside
#                             a case that differed, and the OK line says why
#
# ONE OF THE TWO IS REQUIRED (exit 2 without it, or with both): what standard
# error is held to is the call site's decision, by the Run contract. This
# runner threw it away on every run, which decided it by default
# (tools/runner_lib.sh, STANDARD ERROR, A CHOICE AT EVERY CALL; review of
# WP-50). tools/defs.bzl refuses such a call while loading (_RUNNER_CHOICES).
# Under --sanitized or --valgrind neither is given: standard error carries the
# checker's report there, and no output is judged.
#
# The gate (tools/runner_lib.sh's rl_gate): while `BIN DICT N`, the
# subject's own example, does not print the --gate-expected file, the run
# says SKIP and passes. A gated target is one that judges (--settled); the
# manual ones run whatever their author asked them to.
#
# Env: RUSH02_TIMEOUT  seconds one number may take (default 10), capped by what
#                      is left of the test's own limit (tools/runner_lib.sh).
#                      After three that run out of their own time the sweep
#                      stops and says how many it did not try.
#      DIFF_MAX_ROWS   the default of --show (tools/runner_lib.sh, rl_rows)
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "rush02_check.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk cat cmp grep mktemp rm tr

# The shared runner helpers: the time budget, signal traps and how a run ended
# (tools/runner_lib.sh, which says why each is written once).
RL_NAME=rush02_check
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "rush02_check.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"
# The harness's own programs this runner starts by path, outside rl_run on
# purpose: //tools:conventions holds every other one to rl_run.
# conventions: harness tool ORACLE -- the Rust reference (//oracle), which writes the corpus

BIN=""
DICT=""
ORACLE=""
FN="rush02_words"
SEED=1
COUNT=200
SHOW=""
SETTLED=0
GATE_DIFFER=""; GATE_BIN=""; GATE_EXPECTED=""; GATE_NUMBER=""
# Each case's own cap: one number, one dictionary, milliseconds for a program
# that stops. The test's time limit caps it too.
CASE_TMO="${RUSH02_TIMEOUT:-10}"
STDERR_EMPTY=0
STDERR_WHY=""

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "rush02_check.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--bin) need "$1" "$#"; BIN="$2"; shift 2 ;;
		--dict) need "$1" "$#"; DICT="$2"; shift 2 ;;
		--oracle) need "$1" "$#"; ORACLE="$2"; shift 2 ;;
		--fn) need "$1" "$#"; FN="$2"; shift 2 ;;
		--seed) need "$1" "$#"; SEED="$2"; shift 2 ;;
		--count) need "$1" "$#"; COUNT="$2"; shift 2 ;;
		--show) need "$1" "$#"; SHOW="$2"; shift 2 ;;
		--stderr-empty) STDERR_EMPTY=1; shift ;;
		--stderr-ignored) need "$1" "$#"; STDERR_WHY="$2"; shift 2 ;;
		--settled) SETTLED=1; shift ;;
		--gate-differ) need "$1" "$#"; GATE_DIFFER="$2"; shift 2 ;;
		--gate-bin) need "$1" "$#"; GATE_BIN="$2"; shift 2 ;;
		--gate-expected) need "$1" "$#"; GATE_EXPECTED="$2"; shift 2 ;;
		--gate-number) need "$1" "$#"; GATE_NUMBER="$2"; shift 2 ;;
		--sanitized | --valgrind | --valgrind-tools | --sample | --rule | --symbolizer | --symbolizer-lib)
			rl_mem_opt "$@"; shift "$RL_MEM_SHIFT" ;;
		*) echo "rush02_check.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

for v in BIN DICT ORACLE; do
	eval "x=\$$v"
	[ -n "$x" ] || { echo "rush02_check.sh: --$(echo $v | tr 'A-Z' 'a-z') is required" >&2; exit 2; }
done
rl_stderr_choice
rl_rows "$SHOW"
rl_mem_ready
if [ "$SETTLED" = 1 ] && [ -n "$RL_MEM" ]; then
	echo "rush02_check.sh: --settled and --$RL_MEM are two targets, not one: each" >&2
	echo "  judges the same runs its own way." >&2
	exit 2
fi

# Absolutise everything before anything changes directory. $(location ...) hands
# us runfiles-root-relative paths, and they stop resolving the moment cwd moves
# -- the trap make_test.sh documents where it makes --nm and --make absolute,
# for the same reason.
abspath() {
	case "$1" in
		/*) echo "$1" ;;
		*) echo "$PWD/$1" ;;
	esac
}
BIN=$(abspath "$BIN")
DICT=$(abspath "$DICT")
ORACLE=$(abspath "$ORACLE")
[ -z "$GATE_DIFFER" ] || [ -n "$GATE_NUMBER" ] ||
	{ echo "rush02_check.sh: --gate-differ needs --gate-number, the number the gate converts" >&2; exit 2; }
[ -z "$GATE_DIFFER" ] || GATE_DIFFER=$(abspath "$GATE_DIFFER")
[ -z "$GATE_BIN" ] || GATE_BIN=$(abspath "$GATE_BIN")
[ -z "$GATE_EXPECTED" ] || GATE_EXPECTED=$(abspath "$GATE_EXPECTED")

[ -x "$BIN" ] || { echo "rush02_check.sh: '$BIN' is not executable" >&2; exit 1; }
[ -r "$DICT" ] || { echo "rush02_check.sh: cannot read dictionary '$DICT'" >&2; exit 1; }

# The subject's own example first: while it is red, this layer waits.
[ -z "$GATE_DIFFER" ] ||
	rl_gate rush02_check "$GATE_DIFFER" "$GATE_BIN" "$GATE_EXPECTED" "$DICT" "$GATE_NUMBER"

# A PROGRAM THAT DID NOT BUILD is a stand-in script that says why (see
# tools/standin.sh). Checked after the gate, as every gated runner does: a
# red gate has already skipped this layer. Graded as a program, its "output" is empty and its exit
# status arbitrary, and the report would be a table of wrong answers under
# this exercise's hints, none of which is about a build. Say what the build
# said instead, whole, and fail.
case "$0" in */*) _sl_dir=${0%/*} ;; *) _sl_dir=. ;; esac
for _sl in "$_sl_dir/standin.sh" \
	"${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/standin.sh"; do
	[ -f "$_sl" ] && break
done
[ -f "$_sl" ] || { echo "rush02_check.sh: cannot find tools/standin.sh beside it or in the runfiles" >&2; exit 2; }
# shellcheck source=tools/standin.sh
. "$_sl"
standin_check rush02_check "$BIN" "$RL_STANDIN" "the program"

CORPUS=$(mktemp)
# Installed here rather than beside TMPD forty lines down, which is where it
# used to be: three exit paths sit between the two, and each of them leaked the
# corpus. TMPD and GOTF are empty until then and `rm -f ""` is a no-op, so one
# trap covers all three -- and it exits on a signal (rl_traps), because Bazel
# kills a slow test and a trap that only cleans up resumes the script.
TMPD=""
GOTF=""
WANTF=""
ERRF=""
BLOCK=""
rl_traps 'rm -f "$CORPUS" "$TMPD" "$GOTF" "$WANTF" "$ERRF" "$BLOCK"'

"$ORACLE" "$FN" "$SEED" "$COUNT" > "$CORPUS" 2>/dev/null || {
	echo "rush02_check.sh: the oracle produced no corpus for '$FN'" >&2
	exit 1
}

# An oracle that exits 0 having printed NOTHING is not a pass, and until this
# guard existed it was: the loop below never ran, TOTAL stayed 0, and the report
# read "OK -- 0/0 agree with the reference" while nothing at all had been
# compared. That is the same false green tools/rust_diff.sh grew MIN_DIFF_CASES
# to stop, in the only check this module has.
#
# The floor is deliberately not 1. A corpus of a handful of cases would satisfy
# a literal emptiness test while still saying nothing about a converter, and the
# caller asks for --count 200 by default, so anything two orders below that
# means the reference is broken rather than terse.
MIN_RUSH02_CASES=20
# `|| echo 0` here would be a bug, and was one: grep -c PRINTS 0 and EXITS 1
# when nothing matches, so the fallback appended a second zero, the test became
# `[ "0\n0" -lt 20 ]`, sh called it a bad number, and the guard silently never
# fired -- a guard against a false green, failing the same way.
GOT_CASES=$(grep -c . "$CORPUS" 2>/dev/null) || GOT_CASES=0
if [ "$GOT_CASES" -lt "$MIN_RUSH02_CASES" ]; then
	echo "rush02_check.sh: the reference emitted $GOT_CASES case(s) for '$FN'," >&2
	echo "                 fewer than the $MIN_RUSH02_CASES this layer requires." >&2
	echo "                 Reporting a HARNESS failure rather than '0/0 agree':" >&2
	echo "                 a corpus this small proves nothing about the program." >&2
	exit 2
fi

TOTAL=0
BAD=0
OPEN=0
# GOT_CASES, not `wc -l`: a final line with no newline is invisible to wc, and
# this number is the one the replay is asserted against at the bottom. A header
# announcing 25 over a run that compared 1 is exactly the shape this file's own
# MIN_RUSH02_CASES guard exists to refuse.
case "$RL_MEM" in
	sanitized) echo "rush02_check: $FN, seed $SEED, $GOT_CASES cases (one exec each, under ASan/UBSan)" ;;
	"valgrind") echo "rush02_check: $FN, seed $SEED, $RL_MEM_SAMPLE of $GOT_CASES cases under memcheck" ;;
	*) echo "rush02_check: $FN, seed $SEED, $GOT_CASES cases (one exec each)" ;;
esac
[ "$SETTLED" = 0 ] ||
	echo "  judging only what every reading of the subject agrees on (--settled)"

# The dictionary as a reader finds it: its path in the workspace, not in this
# test's runfiles tree.
DICT_SHOWN=${DICT#"${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/"}

# show_case N NUMBER DICT -- one failing case, whole, as a block on stdout:
# the number, both outputs byte-exact (tools/runner_lib.sh's rl_vis: \n is a
# line break, \xHH a byte that is not printable), where they part, and how to
# run it again. DICT is the generated dictionary, or empty when the case used
# --dict. The outputs are $WANTF and $GOTF.
show_case() {
	echo ""
	printf '  case %s of %s\n' "$1" "$GOT_CASES"
	printf '    number:   %s\n' "$(printf '%s' "$2" | rl_vis arg)"
	printf '    expected: %s\n' "$(rl_vis arg < "$WANTF")"
	if [ "$ended" = 1 ]; then
		printf '    got:      (it %s)\n' "$RL_WHY"
		[ ! -s "$GOTF" ] || printf '              having printed: %s\n' "$(rl_vis arg < "$GOTF")"
	elif cmp -s "$WANTF" "$GOTF"; then
		printf '    got:      the same words, byte for byte\n'
	elif [ "$SETTLED" = 1 ]; then
		# Where they part is not what --settled judges: its FAILS line
		# says what is.
		printf '    got:      %s\n' "$(rl_vis arg < "$GOTF")"
	else
		printf '    got:      %s\n' "$(rl_vis arg < "$GOTF")"
		# Where they part: the first byte that differs, counted from 1, and a
		# ^ under it in the lines above. Those show escapes (\x01, \n), so
		# the ^ goes where the rendering of the bytes before it ends, not at
		# the byte count, which would drift one column per escape.
		_at=$(rl_first_diff "$WANTF" "$GOTF")
		printf '              %s first difference: byte %s\n' "$(rl_caret "$WANTF" "$_at")" "$_at"
	fi
	# What it wrote to stderr: the fault itself under --stderr-empty, and
	# otherwise often the explanation of the difference above.
	if [ -s "$ERRF" ]; then
		if rl_stderr_noisy "$ERRF"; then
			printf '    it wrote to standard error, where this input should get nothing:\n'
		else
			printf '    it also wrote to standard error:\n'
		fi
		rl_excerpt "$ERRF" 3 "stderr-case-$1.txt" "      "
	fi
	show_replay "$@"
}

# show_replay N NUMBER DICT -- how to run case N again: its dictionary, kept
# when the case generated one, and the command line.
show_replay() {
	if [ -n "$3" ]; then
		if rl_save "$3" "case-$1.dict"; then
			printf '    dictionary: generated for this case, kept as %s\n' "$RL_SAVED"
			# The number as a shell word that gives back its exact bytes
			# (rl_shword): rl_vis's rendering above is for reading, and a
			# replay built from it ran another input.
			printf '    replay:   ./rush-02 case-%s.dict %s\n' "$1" "$(printf '%s' "$2" | rl_shword)"
		else
			printf '    dictionary: generated for this case (a run under bazel test keeps it)\n'
		fi
	else
		# The fixed dictionary is kept beside the generated ones, so this
		# line too runs from test.outputs/, where the docs say every replay
		# line does (docs/testing.md); its workspace path, named from there,
		# reached nothing. Outside bazel test there is nowhere to keep it.
		if rl_save "$DICT" "${DICT##*/}"; then
			printf '    replay:   ./rush-02 %s %s\n' "${DICT##*/}" "$(printf '%s' "$2" | rl_shword)"
		else
			printf '    replay:   ./rush-02 %s %s\n' "$DICT_SHOWN" "$(printf '%s' "$2" | rl_shword)"
		fi
	fi
}

# dict_cover DICT OUTPUT -- nothing when OUTPUT is DICT's values with
# separators between them (a space, "-", ",", "and"; at its end too), else
# the 1-based byte from which no value covers it. The dictionary is read by
# the subject's grammar: digits, spaces, a colon, spaces, the value, trimmed
# of the spaces at its ends. Every split is tried (a value may hold spaces,
# and one may begin another), so a correct output is never refused for a
# value that happens to be a prefix of the next.
dict_cover() {
	G="$2" LC_ALL=C awk '
		match($0, /^[0-9]+ *:/) {
			v = substr($0, RLENGTH + 1)
			sub(/^ +/, "", v); sub(/ +$/, "", v)
			if (v != "" && !(v in seen)) { seen[v] = 1; vals[++nv] = v }
		}
		END {
			s = ENVIRON["G"]; n = length(s)
			# at[p]: 1 the start, where a value must come; 2 a value ends
			# at p, and a separator must; 3 a separator ends at p, and
			# either may. Every step goes forward, so p is settled when
			# reached, and 3 is kept over 2: it allows all 2 does.
			at[0] = 1; far = 0
			for (p = 0; p <= n; p++) {
				if (!(p in at)) continue
				far = p
				if (p == n && at[p] != 1) exit
				if (at[p] != 2)
					for (i = 1; i <= nv; i++)
						if (substr(s, p + 1, length(vals[i])) == vals[i] && at[p + length(vals[i])] != 3)
							at[p + length(vals[i])] = 2
				if (at[p] != 1) {
					c = substr(s, p + 1, 1)
					if (c == " " || c == "," || c == "-") at[p + 1] = 3
					if (substr(s, p + 1, 3) == "and") at[p + 3] = 3
				}
			}
			print far + 1
		}' "$1"
}

# settled_shape DICT REFDICT NUMBER -- the words every reading spells NUMBER
# with, where it has one of the two shapes WHAT GATES names, by DICT's values:
# below 100 with a key of its own, its value; a group of one or two digits,
# other than 1, that is a key, followed by a multiple of three zeros that,
# after a 1, is a key too, the two values with a space. Every key it uses is
# one REFDICT (--dict, the reference dictionary) holds as well: those are the
# keys the named cases at basic hold, and a dictionary may add others -- "45"
# beside 40 and 5 -- whose use the subject leaves open, and the reference
# composes without (oracle/src/rush02.rs, compose_with). Settling one here
# failed the reference's own composition (the wave 6 review). Nothing for any
# other number, or one whose keys DICT lacks. Each dictionary is read as
# dict_cover reads it.
settled_shape() {
	N="$3" LC_ALL=C awk '
		# The two files by their order, not their names: the corpus
		# that uses --dict itself hands the same path twice.
		FNR == 1 { file++ }
		match($0, /^[0-9]+ *:/) {
			k = substr($0, 1, RLENGTH - 1)
			sub(/ +$/, "", k)
			if (file == 2) { held[k] = 1; next }
			v = substr($0, RLENGTH + 1)
			sub(/^ +/, "", v); sub(/ +$/, "", v)
			if (v != "" && !(k in val)) val[k] = v
		}
		END {
			n = ENVIRON["N"]
			if (n !~ /^[1-9][0-9]*$/ && n != "0") exit
			if (length(n) <= 2) {
				if ((n in val) && (n in held)) print val[n]
				exit
			}
			# A group of one or two digits, then zeros a multiple of
			# three long: at most one split of the length fits.
			if (n !~ /^[1-9][0-9]?0+$/) exit
			if ((length(n) - 1) % 3 == 0 && substr(n, 2) ~ /^0+$/) lead = substr(n, 1, 1)
			else if ((length(n) - 2) % 3 == 0) lead = substr(n, 1, 2)
			else exit
			if (lead == "1") exit
			scale = "1" substr(n, length(lead) + 1)
			if ((lead in val) && (scale in val) && (lead in held) && (scale in held))
				print val[lead] " " val[scale]
		}' "$1" "$2"
}

# settled_why DICT EXPECTED GOT NUMBER -- why GOT breaks a rule every reading
# agrees on (see WHAT GATES), or nothing when the difference is one the
# subject leaves open. $ended says whether the run ended by itself. Under
# --stderr-empty, a run that wrote to standard error breaks the call site's
# rule whatever its words (rl_stderr_noisy), and says so when its words are
# not already the reason.
settled_why() {
	_sw=$(settled_words "$@")
	if [ -z "$_sw" ] && rl_stderr_noisy "$ERRF"; then
		_sw="it wrote to standard error, which this check holds empty (--stderr-empty)"
	fi
	[ -z "$_sw" ] || echo "$_sw"
}

# settled_words DICT EXPECTED GOT NUMBER -- settled_why's verdict on the words alone.
settled_words() {
	if [ "$ended" = 1 ]; then
		echo "a run ends by itself under every reading, and this one did not"
		return
	fi
	case $3 in
		"")
			echo "it printed nothing: a valid number has its words, or Dict Error"
			return ;;
		Error)
			echo "Error is for a number that is not a valid and positive integer, and this one is"
			return ;;
		"Dict Error")
			[ "$2" = "Dict Error" ] ||
				echo "this dictionary has every key of the reference dictionary, and they spell this number"
			return ;;
	esac
	# The two shapes every reading spells alike (WHAT GATES): word for word.
	_shape=$(settled_shape "$1" "$DICT" "$4")
	if [ -n "$_shape" ] && [ "$3" != "$_shape" ]; then
		echo "every reading spells this number with its own keys' values, and only those:" \
			"$(printf '%s' "$_shape" | rl_vis arg) (a number below 100 with a key of its own" \
			"is that key's value alone; a round <group> <scale> is the two)"
		return
	fi
	_from=$(dict_cover "$1" "$3")
	[ -z "$_from" ] ||
		echo "from byte $_from on, none of it is this dictionary's values, which must be used to print the result"
}

# Two corpus shapes, told apart per line by the field count:
#   2 fields  <number>\t<expected>                  -- uses --dict, fixed
#   3 fields  <escaped-dict>\t<number>\t<expected>  -- a generated dictionary
# The escape is rush00's; only \n, \t and \\ can actually occur here, because
# the generator emits printable values only, and printf %b handles those three.
TMPD=$(mktemp)
GOTF=$(mktemp)
WANTF=$(mktemp)
ERRF=$(mktemp)
BLOCK=$(mktemp)
# No second trap here. `trap` REPLACES the handler rather than adding to it, so
# re-arming it at this point would silently drop the INT and TERM the one above
# installs -- and it is the same command either way, because these files were
# declared empty up there for exactly this reason.

# show_mem_case N NUMBER DICT -- a case rl_mem_run marks to show under the
# memory checker, one that went wrong or did not finish: the number, how to
# run it again, and what the checker said. Never the words: they are not
# what a memory checker judges.
show_mem_case() {
	echo ""
	printf '  case %s of %s  [%s]\n' "$1" "$GOT_CASES" "$RL_MEM_KIND"
	printf '    number:   %s\n' "$(printf '%s' "$2" | rl_vis arg)"
	show_replay "$@"
	rl_mem_report
}
DONE=0

# The output goes to a FILE, capped by `ulimit -f` (set once, now that the
# corpus is written): a program printing without end is stopped by SIGXFSZ at
# 1 MiB. Captured with $( ) instead, it grew in this shell's memory until the
# timeout. A correct answer is one line of words.
ulimit -f 2048 2> /dev/null || true

while IFS='	' read -r f1 f2 f3; do
	[ -n "$f1" ] || continue
	if [ -n "$f3" ]; then
		printf '%b' "$f1" > "$TMPD"
		use_dict="$TMPD"; num="$f2"; want="$f3"; gen_dict="$TMPD"
	else
		use_dict="$DICT"; num="$f1"; want="$f2"; gen_dict=""
	fi
	TOTAL=$((TOTAL + 1))
	if [ -n "$RL_MEM" ]; then
		# Under a memory checker: the case runs when it is in the sample,
		# and only memory and how it ended are judged.
		rl_mem_pick "$TOTAL" "$GOT_CASES" || continue
		rl_sweep_next "$CASE_TMO" || { TOTAL=$((TOTAL - 1)); break; }
		DONE=$((DONE + 1))
		rl_mem_run --what "case $TOTAL of $GOT_CASES" -- "$use_dict" "$num"
		if [ "$RL_MEM_BAD" = 1 ]; then
			show_mem_case "$TOTAL" "$num" "$gen_dict" > "$BLOCK"
			rl_block "$BLOCK"
		fi
		[ -z "$RL_STOP" ] || break
		continue
	fi
	DONE=$((DONE + 1))
	# < /dev/null, and it is not defensive tidiness: this loop reads the corpus
	# on the shell's own stdin, so a deliverable that reads stdin EATS THE
	# REMAINING CASES. The runner then compared one case, announced the total it
	# had been given, and printed "OK — 1/1 agree". The three sibling runners
	# each carry this line with a comment saying it was added after exactly that
	# bug (argv_check.sh, file_check.sh, rush01_check.sh).
	rl_sweep_next "$CASE_TMO" || { TOTAL=$((TOTAL - 1)); break; }
	rl_run "$BIN" "$use_dict" "$num" > "$GOTF" 2> "$ERRF" < /dev/null
	st=$?
	rl_sweep_ran "$st"
	rl_stderr "$ERRF" "case $TOTAL"
	# The expected bytes: the reference's words and the newline after them.
	printf '%s\n' "$want" > "$WANTF"
	# A CRASH IS NOT AN ANSWER. The status was discarded here, so a program that
	# printed the right words and then died on a signal counted as agreement --
	# the same hole the three siblings closed. How it ended is rl_classify's
	# (tools/exit_status's waitpid()): a return of any number, 128 and 255
	# included, is a return; a signal, the time limit or the output budget is
	# not.
	case "$RL_CAUSE" in
		ok | "exit") ended=0 ;;
		noexec)
			echo "rush02_check.sh: the program $RL_WHY" >&2
			exit 2 ;;
		*) ended=1 ;;
	esac
	if cmp -s "$WANTF" "$GOTF" && [ "$ended" = 0 ] && ! rl_stderr_noisy "$ERRF"; then
		:
	elif [ "$SETTLED" = 0 ]; then
		BAD=$((BAD + 1))
		show_case "$TOTAL" "$num" "$gen_dict" > "$BLOCK"
		rl_block "$BLOCK"
	else
		# The words, as settled_why reads them: what was printed, less the
		# newline(s) after it, which no rule of WHAT GATES is about.
		got=$(cat "$GOTF")
		_why=$(settled_why "$use_dict" "$want" "$got" "$num")
		if [ -n "$_why" ]; then
			BAD=$((BAD + 1))
			{
				show_case "$TOTAL" "$num" "$gen_dict"
				printf '    FAILS:    %s\n' "$_why"
			} > "$BLOCK"
			rl_block "$BLOCK"
		else
			# A composition this target does not judge: a few are
			# shown, as what they are, and none fails. Not "a reading
			# the subject leaves open": the subject leaves composition
			# open, and this target does not ask whether a given
			# spelling is a reading of it at all.
			OPEN=$((OPEN + 1))
			if [ "$OPEN" -le 3 ]; then
				show_case "$TOTAL" "$num" "$gen_dict"
				printf '    passes:   another composition of the number, which this target does not judge\n'
			fi
		fi
	fi
	[ -z "$RL_STOP" ] || break
done < "$CORPUS"

# THE LOOP MUST HAVE SEEN THE WHOLE CORPUS. A program that eats stdin, a corpus
# whose last line has no newline, a `while read` that died on the first case:
# every one of them ends here with fewer cases run than the file holds, and
# every one of them used to be reported as a pass over the cases that did run.
# Exit 2 -- nothing can be concluded from a partial replay, which is a harness
# fault rather than a finding about the deliverable.
if [ -z "$RL_STOP" ] && [ "$TOTAL" -ne "$GOT_CASES" ]; then
	echo "rush02_check.sh: ran $TOTAL of $GOT_CASES cases. Refusing to report" >&2
	echo "                 on a partial replay." >&2
	exit 2
fi

rl_tally
if [ -n "$RL_MEM" ]; then
	if [ -n "$RL_STOP" ]; then
		echo ""
		rl_mem_count "$GOT_CASES"
		rl_mem_stopped "$DONE"
		exit 1
	fi
	rl_mem_tally "$DONE" "$GOT_CASES"
	_mt=$?
	# The number is an argument: what the sanitizer saw of it.
	rl_mem_argv_note 0
	exit "$_mt"
fi
echo ""
if [ -n "$RL_STOP" ]; then
	# The cases judged wrong before the sweep stopped, not counting the one
	# the time ran out in (counted in $BAD, but cut short, not wrong): a verdict,
	# which keeps the report from reading as "ran out of time" alone. Nor any
	# that ran out of its own limit (RL_HANGS, in $BAD too): not judged
	# (ruling R4), and rl_sweep_stopped names them apart (V84).
	_wrong=$((BAD - RL_HANGS))
	[ "$RL_STOP" != budget ] || _wrong=$((_wrong - 1))
	rl_sweep_stopped "$TOTAL" "$GOT_CASES" "$_wrong"
	exit 1
fi
if [ "$SETTLED" = 1 ]; then
	[ "$OPEN" -le 3 ] || echo "  ... $((OPEN - 3)) more difference(s) in composition, not judged here, not shown."
	if [ "$BAD" -eq 0 ]; then
		echo "  RESULT: OK — none of $TOTAL cases breaks a rule every reading of the subject"
		echo "  agrees on; $OPEN differ from the reference's own composition, which this"
		echo "  target does not judge: they are information."
		rl_stderr_rule
		rl_stderr_note
		exit 0
	fi
	echo "  RESULT: $BAD of $TOTAL cases break a rule every reading of the subject agrees on"
	echo "  (each one's FAILS line says which). Composition is not judged here: \"and\","
	echo "  a leading \"one\" or another split of the number pass; what fails is Error for"
	echo "  a valid number, Dict Error from a dictionary that can spell it, words that"
	echo "  are not the dictionary's values, a number with a key of its own below 100 or"
	echo "  a round <group> <scale> spelled other than by those keys, nothing at all, or"
	echo "  a run that never ends."
	rl_stderr_note
	exit 1
fi
if [ "$BAD" -eq 0 ]; then
	echo "  RESULT: OK — $TOTAL/$TOTAL agree with the reference."
	rl_stderr_rule
	rl_stderr_note
	exit 0
fi
echo "  RESULT: $((TOTAL - BAD))/$TOTAL agree, $BAD differ."
rl_stderr_note
echo ""
echo "  Read this before changing anything. A difference here is one of two"
echo "  things:"
echo "    * a real bug — the usual case, especially if small numbers differ; or"
echo "    * a reading: where the subject leaves how a number is worded open, the"
echo "      reference took one reading, and yours may be another."
echo "  Compare the SHAPE of the differences: if every case differs the same way,"
echo "  that is a convention, not a bug."
# The marks are named from the lines the report showed (rl_shown_legend),
# with \n read as the newline that ends a line: a legend written once named
# a backslash and \xHH under words that held neither.
echo "  The reference prints a newline after the words (\`| cat -e\` marks it"
echo "  with \$)."
rl_shown_legend '^    (number|expected|got): +|^ +having printed: ' "  " 1
exit 1
