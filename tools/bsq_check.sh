#!/bin/sh
# bsq_check.sh — differential check for c-piscine-bsq.
#
# Runs the student's ./bsq once per map against a corpus the Rust reference
# generated, and reports the first differences as readable diagnoses.
#
# WHY THIS IS ONE EXEC PER CASE, unlike c_diff.
# c_diff streams a 400k-line corpus through ONE process reading stdin, which is
# what makes that layer cheap. It can do that because its subject is a
# FUNCTION: the harness links the student's code and loops in-process. bsq is a
# PROGRAM -- it has its own main, it takes file paths on argv, and each case is
# therefore a fork+exec. The count stays in the hundreds. That is a property of
# the subject, not a shortcut.
#
# WHY THIS ONE GATES, unlike tools/rush02_check.sh.
# rush-02's subject pins four outputs and no composition rule, so a divergence
# there is evidence rather than a verdict and its targets are `manual`. bsq's
# subject settles the answer completely, including the tie: "the square that is
# closest to the top of the map, then the one that is most to the left". There
# is one correct output per map, so this is a real check and it is allowed to
# be red.
#
# THREE MODES, ONE CORPUS. argv (one map per exec), stdin (the same map on
# stdin with no arguments), multi (K maps in one exec, which is where the blank
# line between outputs is checked). They replay the SAME records on purpose: a
# separate corpus per transport is two corpora that drift, and the weaker one
# is the one nobody notices.
#
# Usage:
#   bsq_check.sh --bin PATH --oracle PATH
#                [--fn NAME] [--seed N] [--count N]
#                [--mode argv|stdin|multi] [--group K] [--show N]
#                [--gate-differ PATH --gate-bin PATH --gate-expected PATH]
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "bsq_check.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk cmp grep mktemp rm sed sort uniq
# conventions: optional timeout -- probed below; without it a map that sends the
# program into an infinite loop is not stopped, so the layer keeps its verdicts
# but loses its hang guard. NO_SKIP=1 refuses rather than degrading quietly.

BIN=""
ORACLE=""
FN="bsq_maps"
SEED=1
COUNT=200
MODE="argv"
GROUP=3
SHOW="${BSQ_MAX_FAILS:-8}"
GATE_DIFFER=""; GATE_BIN=""; GATE_EXPECTED=""

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "bsq_check.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--bin) need "$1" "$#"; BIN="$2"; shift 2 ;;
		--oracle) need "$1" "$#"; ORACLE="$2"; shift 2 ;;
		--fn) need "$1" "$#"; FN="$2"; shift 2 ;;
		--seed) need "$1" "$#"; SEED="$2"; shift 2 ;;
		--count) need "$1" "$#"; COUNT="$2"; shift 2 ;;
		--mode) need "$1" "$#"; MODE="$2"; shift 2 ;;
		--group) need "$1" "$#"; GROUP="$2"; shift 2 ;;
		--show) need "$1" "$#"; SHOW="$2"; shift 2 ;;
		--gate-differ) need "$1" "$#"; GATE_DIFFER="$2"; shift 2 ;;
		--gate-bin) need "$1" "$#"; GATE_BIN="$2"; shift 2 ;;
		--gate-expected) need "$1" "$#"; GATE_EXPECTED="$2"; shift 2 ;;
		*) echo "bsq_check.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$BIN" ] || { echo "bsq_check.sh: --bin is required" >&2; exit 2; }
[ -n "$ORACLE" ] || { echo "bsq_check.sh: --oracle is required" >&2; exit 2; }
case "$MODE" in
	argv|stdin|multi) ;;
	*) echo "bsq_check.sh: --mode must be argv|stdin|multi" >&2; exit 2 ;;
esac

# Absolutise everything before anything changes directory. $(location ...) hands
# us runfiles-root-relative paths and they stop resolving the moment cwd moves.
abspath() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$PWD" "$1" ;; esac; }
BIN=$(abspath "$BIN")
ORACLE=$(abspath "$ORACLE")
[ -n "$GATE_DIFFER" ] && GATE_DIFFER=$(abspath "$GATE_DIFFER")
[ -n "$GATE_BIN" ] && GATE_BIN=$(abspath "$GATE_BIN")
[ -n "$GATE_EXPECTED" ] && GATE_EXPECTED=$(abspath "$GATE_EXPECTED")

[ -x "$BIN" ] || { echo "bsq_check.sh: '$BIN' is not executable" >&2; exit 1; }

# ---------------------------------------------------------------------------
# The correctness gate. While the exercise's own output fixture is red, replaying
# 250 generated maps says the same thing 250 times less usefully. Fails OPEN: no
# gate wired, an unrunnable gate binary or a missing fixture all mean "run
# anyway", because a gate that cannot answer must not be able to silence a
# layer. NO_SKIP=1 forces it open.
if [ "${NO_SKIP:-0}" != "1" ] &&
	[ -n "$GATE_DIFFER" ] && [ -n "$GATE_BIN" ] && [ -n "$GATE_EXPECTED" ] &&
	[ -x "$GATE_BIN" ] && [ -f "$GATE_EXPECTED" ]; then
	if ! sh "$GATE_DIFFER" --bin "$GATE_BIN" --expected "$GATE_EXPECTED" > /dev/null 2>&1; then
		echo "bsq_check: SKIP — this exercise's own output fixture is not passing yet."
		echo ""
		echo "  That fixture is the subject's own example map, with a labelled table"
		echo "  and hints attached. This layer replays $COUNT generated maps and"
		echo "  reports raw divergences — the same failure, told far less usefully."
		echo "  Get the *_output layer green and this one starts checking the maps"
		echo "  you did not think of."
		exit 0
	fi
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

# The hang guard. Nine runners here probe for `timeout` the same way; without it
# a program that never returns burns the whole Bazel timeout with no
# explanation a student can act on.
TMO="${BSQ_TIMEOUT:-10}"
if command -v timeout > /dev/null 2>&1; then
	RUNNER="timeout -s KILL $TMO"
else
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: no 'timeout' command available, so a map that sends the"
		echo "             program into an infinite loop could not be stopped, and"
		echo "             this layer must not report a pass it cannot stand behind."
		exit 1
	}
	echo "bsq_check: NOTE — no 'timeout' command; runs are unguarded against hangs."
	RUNNER=""
fi

CORPUS="$WORK/corpus"
"$ORACLE" "$FN" "$SEED" "$COUNT" > "$CORPUS" 2>/dev/null || {
	echo "bsq_check.sh: the oracle produced no corpus for '$FN'" >&2
	exit 2
}

# ---------------------------------------------------------------------------
# FLOORS. Each one names a wrong program that would otherwise pass, which is the
# only reason a floor is worth having. All of them are exit 2: a corpus that
# cannot fail anything is a broken harness, not a wrong deliverable.
#
# `grep -c` PRINTS 0 and EXITS 1 when nothing matches, so `|| echo 0` would
# append a second zero and the comparison would silently never fire. That was a
# real bug in rush02_check.sh; it is written this way on purpose.
MIN_BSQ_CASES=20
GOT_CASES=$(grep -c . "$CORPUS" 2>/dev/null) || GOT_CASES=0
if [ "$GOT_CASES" -lt "$MIN_BSQ_CASES" ]; then
	echo "bsq_check.sh: the reference emitted $GOT_CASES case(s) for '$FN'," >&2
	echo "              fewer than the $MIN_BSQ_CASES this layer requires." >&2
	echo "              Reporting a HARNESS failure rather than a green run:" >&2
	echo "              a corpus this small proves nothing about the program." >&2
	exit 2
fi

FLOOR=$(awk -F'\t' '
	$1 == "ok"      { ok++;  if ($2 == 0) zero++ }
	$1 ~ /^err:/    { err++ }
	$1 == "ok" && $5 != $6 { differs++ }
	END { printf "%d %d %d %d\n", ok+0, err+0, zero+0, differs+0 }' "$CORPUS")
set -- $FLOOR
N_OK=$1; N_ERR=$2; N_ZERO=$3; N_DIFF=$4

if [ "$MODE" = multi ]; then
	if [ "$N_OK" -lt 1 ] || [ "$N_ERR" -lt 1 ]; then
		echo "bsq_check.sh: --mode multi needs a corpus holding BOTH valid and invalid" >&2
		echo "              maps ($N_OK valid, $N_ERR invalid). Without both, a program" >&2
		echo "              that always prints 'map error' — or never does — passes." >&2
		exit 2
	fi
elif [ "$N_OK" -ge 1 ]; then
	if [ "$N_DIFF" -lt 1 ]; then
		echo "bsq_check.sh: no valid map in this corpus has an answer that differs from" >&2
		echo "              its own input, so 'cat' would pass this layer." >&2
		exit 2
	fi
	if [ "$N_ZERO" -lt 1 ]; then
		echo "bsq_check.sh: no map in this corpus has a biggest square of side 0, so a" >&2
		echo "              program that prints 'map error' whenever it finds nothing" >&2
		echo "              would pass. The corpus must contain an all-obstacle map." >&2
		exit 2
	fi
fi

# ---------------------------------------------------------------------------
# CORPUS SELF-VALIDATION, before a single student run. It cannot check
# MAXIMALITY -- that is //oracle:oracle_check's job, and it is done there
# exhaustively -- but it catches a corrupted or mis-escaped record, which would
# otherwise be reported as the student's fault.
BAD_REC=$(awk -F'\t' '
	NF != 6 { printf "line %d: %d fields, want 6\n", NR, NF; next }
	$1 != "ok" && $1 !~ /^err:/ { printf "line %d: unknown tag %s\n", NR, $1 }
	$1 == "ok" && $2 < 0 { printf "line %d: ok record with side %s\n", NR, $2 }
	$1 ~ /^err:/ && $6 != "map error\\n" { printf "line %d: err record whose expected is not map error\n", NR }
	$1 == "ok" && $2 > 0 && ($3 < 0 || $4 < 0) { printf "line %d: side %s but corner (%s,%s)\n", NR, $2, $3, $4 }
	' "$CORPUS")
if [ -n "$BAD_REC" ]; then
	echo "bsq_check.sh: the corpus itself is malformed — this is a harness fault," >&2
	echo "              not a deliverable fault:" >&2
	printf '%s\n' "$BAD_REC" | sed 's/^/    /' >&2
	exit 2
fi

# ---------------------------------------------------------------------------
TAB=$(printf '\t')
TOTAL=0
BAD=0
SHOWN=0
CATS="$WORK/cats"
: > "$CATS"

say() { printf '%s\n' "$*"; }

# One failing case, diagnosed. Everything here runs ONLY for a failure, so a
# green run pays nothing for it.
report_case() {
	_idx="$1"; _tag="$2"; _side="$3"; _top="$4"; _left="$5"; _rc="$6"
	SHOWN=$((SHOWN + 1))
	# EVERY failure is categorised; only the first --show many are PRINTED. The
	# tally is the part that scales: a hundred failures that are all one fault
	# is one thing to fix, and that is the sentence worth having at the bottom.
	_quiet=0
	[ "$SHOWN" -le "$SHOW" ] || _quiet=1
	[ "$_quiet" -eq 1 ] || say " --------------------------------------------------"
	if [ "$_rc" -gt 128 ]; then
		_sig=$((_rc - 128))
		case "$_sig" in
			4)  _what="SIGILL (illegal instruction)" ;;
			6)  _what="SIGABRT (abort; often a libc heap check)" ;;
			8)  _what="SIGFPE (divide by zero, or INT_MIN / -1)" ;;
			9)  _what="SIGKILL (the hang guard stopped it)" ;;
			11) _what="SIGSEGV (invalid memory access)" ;;
			13) _what="SIGPIPE" ;;
			*)  _what="signal $_sig" ;;
		esac
		echo "crash" >> "$CATS"
		if [ "$_quiet" -eq 0 ]; then
			say " CASE $_idx  [$_tag]  DIED: $_what"
			sed -n '1,6p' "$WORK/err" | sed 's/^/     /'
		fi
		return 0
	fi
	# -v, not trailing VAR=value operands: an operand assignment is processed
	# when awk reaches it while reading input, so it is still unset inside
	# BEGIN -- which is where this whole program lives. That mistake reads as
	# "your output: 0 lines" on every case, which looks like a finding.
	awk -v idx="$_idx" -v tag="$_tag" -v side="$_side" -v top="$_top" -v left="$_left" \
		-v WANT="$WORK/want" -v GOT="$WORK/got" -v CATS="$CATS" -v quiet="$_quiet" \
		-v MAP="$WORK/map" '
		function pad(w,   r) { r = ""; while (length(r) < w) r = r " "; return r }
		BEGIN {
			nw = 0; ng = 0
			while ((getline l < WANT) > 0) { w[++nw] = l }
			while ((getline l < GOT)  > 0) { g[++ng] = l }
			close(WANT); close(GOT)
			# The INPUT body, so the student square can be found as "cells you
			# changed" rather than "cells that differ from the reference". Those
			# are not the same set: a square shifted one column differs from the
			# reference in TWO columns, which is not a square, and reporting that
			# as a mis-shaped square would send someone hunting the wrong bug.
			# Line 1 of the file is the header and is not part of the map.
			nrows = 0
			if (MAP != "") {
				mi = 0
				while ((getline l < MAP) > 0) { mi++; if (mi > 1) mp[++nrows] = l }
				close(MAP)
			}

			# ---- measure, before deciding anything ----
			minw = 1e9; maxw = 0
			for (i = 1; i <= ng; i++) {
				if (length(g[i]) < minw) minw = length(g[i])
				if (length(g[i]) > maxw) maxw = length(g[i])
			}
			if (ng == 0) { minw = 0; maxw = 0 }
			ewid = (nw > 0) ? length(w[1]) : 0

			lim = (nw > ng) ? nw : ng
			dl = 0; dc = 0
			for (i = 1; i <= lim && dl == 0; i++) {
				if (w[i] != g[i]) {
					dl = i
					n = length(w[i]); m = length(g[i]); k = (n > m) ? n : m
					for (j = 1; j <= k; j++)
						if (substr(w[i], j, 1) != substr(g[i], j, 1)) { dc = j; break }
					if (dc == 0) dc = (n < m ? n : m) + 1
				}
			}

			# ---- what KIND of wrong; one category, most specific first ----
			kind = "output"
			wmap = (nw == 1 && w[1] == "map error")
			gmap = (ng >= 1 && g[1] == "map error")
			if (wmap && !gmap)      kind = "map-error-missing"
			else if (!wmap && gmap) kind = "map-error-unexpected"
			else if (nw == ng && minw == ewid && maxw == ewid && dl == 0) kind = "trailing-newline"
			else if (ng != nw || minw != ewid || maxw != ewid) kind = "not-a-map"
			else if (tag == "ok" && nrows == ng) {
				# What the student PAINTED: cells that differ from the input.
				gt = -1; gl = -1; gb = -1; gr = -1; nch = 0; onob = 0
				fullc = (side + 0 > 0) ? substr(w[top + 1], left + 1, 1) : ""
				emptyc = (side + 0 > 0) ? substr(mp[top + 1], left + 1, 1) : ""
				for (i = 1; i <= nrows && i <= ng; i++) {
					n = length(mp[i])
					for (j = 1; j <= n; j++) {
						cm = substr(mp[i], j, 1); cg = substr(g[i], j, 1)
						if (cm == cg) continue
						nch++
						if (cm != emptyc) onob++
						if (gt < 0) gt = i
						if (gl < 0 || j < gl) gl = j
						if (i > gb) gb = i
						if (j > gr) gr = j
					}
				}
				gh = gb - gt + 1; gwid = gr - gl + 1
				if (nch == 0) kind = "no-square"
				else if (onob > 0) kind = "overwrote-obstacle"
				else if (gh != gwid || nch != gh * gwid) kind = "square-shape"
				else if (gh != side + 0) kind = "square-size"
				else kind = "square-position"
				sq_side = gh; sq_top = gt; sq_left = gl
			}
			print kind >> CATS
			close(CATS)
			if (quiet + 0 == 1) exit 0

			# ---- report ----
			printf " CASE %s  [%s]\n", idx, tag
			if (tag == "ok")
				printf "   the biggest square is %sx%s, at line %d column %d (1-based).\n", \
					side, side, top + 1, left + 1
			else if (tag ~ /^err:/)
				printf "   this file is invalid (%s): the only correct output is one \"map error\".\n", \
					substr(tag, 5)
			printf "   your output: %d line(s), widths %d..%d   (expected %d line(s) of %d)\n", \
				ng, minw, maxw, nw, ewid
			if (dl > 0) {
				printf "   first difference: line %d, column %d\n", dl, dc
				lo = 1; hi = length(w[dl]); pre = ""; post = ""
				if (hi > 68) {
					lo = dc - 30; if (lo < 1) lo = 1
					hi = lo + 60
					if (lo > 1) pre = "<"
					post = ">"
				}
				printf "     want | %s%s%s\n", pre, substr(w[dl], lo, hi - lo + 1), post
				printf "     got  | %s%s%s\n", pre, substr(g[dl], lo, hi - lo + 1), post
				printf "            %s%s^\n", (pre == "" ? "" : " "), pad(dc - lo)
			}
			if (sq_side > 0 && kind != "no-square")
				printf "   your square is %dx%d, at line %d column %d.\n", \
					sq_side, sq_side, sq_top, sq_left
			printf "   FAULT [%s]\n", kind
			if (kind == "square-position")
				print "     Right size, wrong place. Where several biggest squares fit, the\n" \
				      "     subject picks the one closest to the TOP first, and only then the\n" \
				      "     one furthest LEFT."
			else if (kind == "square-size")
				print "     A solid square, but not the biggest one that fits."
			else if (kind == "square-shape")
				print "     The cells you filled are not a square."
			else if (kind == "no-square")
				print "     You printed the map back unchanged. There is a square to draw here."
			else if (kind == "map-error-missing")
				print "     This file breaks one of the validity rules the subject lists, so\n" \
				      "     the only output is \"map error\" and a newline."
			else if (kind == "map-error-unexpected")
				print "     This file is valid, so it has an answer. Re-read the validity list\n" \
				      "     and ask which rule you think it breaks."
			else if (kind == "not-a-map")
				print "     The shape of the output is wrong before its contents are. Count the\n" \
				      "     lines you print, and remember the first line of the file is a header\n" \
				      "     rather than a row of the map."
			else if (kind == "overwrote-obstacle")
				print "     One of the cells you filled was an obstacle in the input. The\n" \
				      "     square has to fit in EMPTY cells only."
			else if (kind == "trailing-newline")
				print "     Every line of the map, including the last one, ends with a newline."
		}
	' < /dev/null
}

run_one() {
	# $1 = map path list (one or more), stdin handled by the caller
	if [ "$MODE" = stdin ]; then
		# shellcheck disable=SC2086
		$RUNNER "$BIN" > "$WORK/got" 2> "$WORK/err" < "$1"
	else
		# < /dev/null is load-bearing: the loop's own stdin is the corpus, a
		# child inherits it, and a program that reads stdin when it was handed
		# argv files would eat the remaining cases -- the loop would end after
		# one iteration and this runner would report "OK, 1 case".
		# shellcheck disable=SC2086
		$RUNNER "$BIN" $1 > "$WORK/got" 2> "$WORK/err" < /dev/null
	fi
}

printf 'bsq_check: %s, seed %s, %s case(s), mode %s (one exec each)\n\n' \
	"$FN" "$SEED" "$GOT_CASES" "$MODE"

GN=0
GARGS=""
: > "$WORK/want"

while IFS= read -r line; do
	[ -n "$line" ] || continue
	tag=${line%%"$TAB"*};  rest=${line#*"$TAB"}
	side=${rest%%"$TAB"*}; rest=${rest#*"$TAB"}
	top=${rest%%"$TAB"*};  rest=${rest#*"$TAB"}
	left=${rest%%"$TAB"*}; rest=${rest#*"$TAB"}
	einp=${rest%%"$TAB"*}; eexp=${rest#*"$TAB"}

	TOTAL=$((TOTAL + 1))
	if [ "$MODE" = multi ]; then
		GN=$((GN + 1))
		printf '%b' "$einp" > "$WORK/map.$GN"
		# One blank line BETWEEN outputs: each expected blob already ends in a
		# newline, so a bare newline before every blob but the first is exactly
		# one empty line between them, none before the first, none after the last.
		[ "$GN" -eq 1 ] || printf '\n' >> "$WORK/want"
		printf '%b' "$eexp" >> "$WORK/want"
		GARGS="$GARGS $WORK/map.$GN"
		[ "$GN" -lt "$GROUP" ] && continue
		run_one "$GARGS"
		rc=$?
		if ! cmp -s "$WORK/want" "$WORK/got"; then
			BAD=$((BAD + 1))
			report_case "$TOTAL" "group of $GN" "-1" "-1" "-1" "$rc"
		fi
		GN=0; GARGS=""; : > "$WORK/want"
		continue
	fi

	printf '%b' "$einp" > "$WORK/map"
	printf '%b' "$eexp" > "$WORK/want"
	run_one "$WORK/map"
	rc=$?
	if ! cmp -s "$WORK/want" "$WORK/got"; then
		BAD=$((BAD + 1))
		report_case "$TOTAL" "$tag" "$side" "$top" "$left" "$rc"
	fi
done < "$CORPUS"

# a trailing partial group in multi mode still has to be run
if [ "$MODE" = multi ] && [ "$GN" -gt 0 ]; then
	run_one "$GARGS"
	rc=$?
	if ! cmp -s "$WORK/want" "$WORK/got"; then
		BAD=$((BAD + 1))
		report_case "$TOTAL" "group of $GN" "-1" "-1" "-1" "$rc"
	fi
fi

echo ""
if [ "$BAD" -eq 0 ]; then
	echo "bsq_check: OK — $TOTAL/$TOTAL agree with the reference (fn=$FN, seed=$SEED, mode=$MODE)"
	exit 0
fi
if [ "$SHOWN" -gt "$SHOW" ]; then
	echo "  ... $((SHOWN - SHOW)) further failing case(s) not shown."
	echo "      Raise with --test_env=BSQ_MAX_FAILS=N."
fi
echo "  BY FAULT:"
sort "$CATS" | uniq -c | sort -rn | sed 's/^/    /'
echo ""
echo "bsq_check: FAIL — $((TOTAL - BAD))/$TOTAL agree, $BAD differ."
exit 1
