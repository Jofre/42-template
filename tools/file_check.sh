#!/bin/sh
# file_check.sh — differential check for a program whose input is FILES.
#
# Runs the student's binary once per case against a corpus //oracle generated,
# writing each case's file contents to a scratch directory first, and reports
# the first differences.
#
# Usage:
#   file_check.sh --bin PATH --oracle PATH --fn NAME
#                 [--seed N] [--count N] [--show N]
#                 [--expect-transform] [--expect-substring TEXT]
#
# WHY THIS EXISTS BESIDE argv_check.sh AND bsq_check.sh. argv_check's case is a
# list of ARGUMENTS; bsq_check's is one map file and a square. c-10's four
# programs need both halves -- flags AND file contents -- and none of the three
# corpora can express another's cases.
#
# ONE EXEC PER CASE, for the reason those two give: a program that takes its
# input as a path cannot be streamed.
#
# THE CORPUS LINE, peeled rather than read into fields:
#
#     <tag>\t<nflags>\t<flag>...\t<nfiles>\t<file>...\t<escaped-expected>
#
# `IFS=$TAB read` cannot parse it: tab is IFS whitespace, so a run of tabs is
# one separator and an EMPTY field vanishes -- and an empty file is the first
# case in this corpus. Both counts are in the line so the peel is exact.
#
# Every field is POSIX-escaped (`\n`, `\t`, `\\`, `\0NNN` octal). dash's
# `printf %b` decodes `\0NNN` and prints `\xHH` back literally, which is why the
# reference emits octal.
#
# THE EXPECTED BYTES NEVER CONTAIN A PATH. Anything that would print the name of
# the file it was given -- ft_tail with two or more files, every error message --
# is excluded from the corpus by the reference, because the path is chosen here
# at run time and a corpus that hardcoded one would be testing this script.
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "file_check.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk cat cmp grep mktemp od rm sed sort uniq wc

BIN=""
ORACLE=""
FN=""
SEED=1
COUNT=120
SHOW=6
EXPECT_TRANSFORM=0
EXPECT_SUBSTRING=""

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "file_check.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--bin) need "$1" "$#"; BIN="$2"; shift 2 ;;
		--oracle) need "$1" "$#"; ORACLE="$2"; shift 2 ;;
		--fn) need "$1" "$#"; FN="$2"; shift 2 ;;
		--seed) need "$1" "$#"; SEED="$2"; shift 2 ;;
		--count) need "$1" "$#"; COUNT="$2"; shift 2 ;;
		--show) need "$1" "$#"; SHOW="$2"; shift 2 ;;
		--expect-transform) EXPECT_TRANSFORM=1; shift ;;
		--expect-substring) need "$1" "$#"; EXPECT_SUBSTRING="$2"; shift 2 ;;
		*) echo "file_check.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$BIN" ] || { echo "file_check.sh: --bin is required" >&2; exit 2; }
[ -n "$ORACLE" ] || { echo "file_check.sh: --oracle is required" >&2; exit 2; }
[ -n "$FN" ] || { echo "file_check.sh: --fn is required" >&2; exit 2; }
[ -x "$BIN" ] || { echo "file_check.sh: not executable: $BIN" >&2; exit 2; }
[ -x "$ORACLE" ] || { echo "file_check.sh: not executable: $ORACLE" >&2; exit 2; }

WORK=$(mktemp -d) || exit 2
trap 'rm -rf "$WORK"' EXIT INT TERM

TAB=$(printf '\t')

# Decode one escaped field STRAIGHT INTO A FILE, never through a variable.
#
# A shell variable cannot hold a NUL byte -- dash drops it silently, bash warns
# and drops it -- so `_d=$(printf '%b.' "$1"); printf '%s' "${_d%.}" > "$2"`
# writes the file with every NUL missing. That is not a small loss here: a file
# containing a NUL is what separates a correct read loop from one that treats
# its buffer as a C string, and it is the single most valuable case in this
# corpus. The first version of this function did exactly that, and a
# deliberately broken `strlen(buf)` program PASSED 60 of 60.
#
# Redirecting printf's output needs no sentinel either: command substitution is
# what strips trailing newlines, and there is none here.
dec_to() {  # dec_to ESCAPED DEST
	printf '%b' "$1" > "$2"
}

"$ORACLE" "$FN" "$SEED" "$COUNT" > "$WORK/corpus.tsv" 2> "$WORK/oracle.err" || {
	echo "file_check: the reference failed to produce a corpus for '$FN'." >&2
	sed -n '1,10p' "$WORK/oracle.err" >&2
	exit 2
}

CASES=$(wc -l < "$WORK/corpus.tsv")

# ---------------------------------------------------------------------------
# FLOORS. Each names a corpus that a program doing none of what the exercise
# asks would pass, so failing one is a broken harness -- exit 2, not 1.
MIN_CASES=${MIN_FILE_CASES:-20}
if [ "$CASES" -lt "$MIN_CASES" ]; then
	echo "file_check: only $CASES cases (floor $MIN_CASES). Refusing to report OK." >&2
	exit 2
fi

# What a hand-written fixture never has. Checked ON THE CORPUS rather than
# assumed from the generator's source, because the generator is the thing this
# is meant to keep honest.
_probe=$(awk -F'\t' '
	{
		nf = $2 + 0
		fi = 3 + nf              # index of <nfiles>
		n  = $(fi) + 0
		for (i = fi + 1; i < fi + 1 + n; i++) {
			if ($i == "") empty = 1
			if ($i ~ /\\0000/) nul = 1
			if (length($i) > 4096) big = 1
		}
		if ($NF != "") nonempty = 1
		if ($NF != $(fi + 1)) transformed = 1
	}
	END { printf "%d %d %d %d %d", empty, nul, big, nonempty, transformed }
' "$WORK/corpus.tsv")
set -- $_probe
[ "$1" = 1 ] || { echo "file_check: no EMPTY file in the corpus. A read loop that never runs would pass." >&2; exit 2; }
[ "$2" = 1 ] || { echo "file_check: no file containing a NUL. A program using str* functions would pass." >&2; exit 2; }
[ "$3" = 1 ] || { echo "file_check: every file is small. A fixed-size buffer read once would pass." >&2; exit 2; }
[ "$4" = 1 ] || { echo "file_check: every expected block is empty. A program that prints nothing would pass." >&2; exit 2; }

# For the arms whose answer is not the file itself: at least one case where the
# expected bytes differ from the first file's. Without it a `ft_hexdump` corpus
# could consist entirely of empty files and be passed by `cat`.
if [ "$EXPECT_TRANSFORM" = 1 ] && [ "$5" != 1 ]; then
	echo "file_check: no case whose output differs from its input, so a program" >&2
	echo "            that copies the file would pass." >&2
	exit 2
fi

# An arm may name one thing its corpus must be able to produce -- hexdump's `*`
# squeeze line is the case in point, since it needs sixteen identical bytes
# twice over and no hand-written fixture reaches it.
if [ -n "$EXPECT_SUBSTRING" ]; then
	if ! grep -qF -- "$EXPECT_SUBSTRING" "$WORK/corpus.tsv"; then
		echo "file_check: no case whose expected output contains '$EXPECT_SUBSTRING'." >&2
		exit 2
	fi
fi

# ---------------------------------------------------------------------------
# THE REPLAY.
FAILED=0
CHECKED=0
: > "$WORK/faults"
: > "$WORK/report"

classify() {  # classify EXPECTED GOT STATUS
	if [ "$3" -ge 128 ]; then echo "crash"; return; fi
	if [ ! -s "$2" ] && [ -s "$1" ]; then echo "no-output"; return; fi
	if [ -s "$2" ] && [ ! -s "$1" ]; then echo "output-when-none-expected"; return; fi
	_we=$(wc -c < "$1"); _ge=$(wc -c < "$2")
	if [ "$_ge" -lt "$_we" ]; then echo "truncated-$((_we - _ge))-bytes"; return; fi
	if [ "$_ge" -gt "$_we" ]; then echo "extra-$((_ge - _we))-bytes"; return; fi
	echo "same-length-different-bytes"
}

while IFS= read -r line; do
	[ -n "$line" ] || continue
	tag=${line%%"$TAB"*}; rest=${line#*"$TAB"}
	nflags=${rest%%"$TAB"*}; rest=${rest#*"$TAB"}

	set --
	_i=0
	while [ "$_i" -lt "$nflags" ]; do
		_f=${rest%%"$TAB"*}; rest=${rest#*"$TAB"}
		_v=$(printf '%b.' "$_f")
		set -- "$@" "${_v%.}"
		_i=$((_i + 1))
	done

	nfiles=${rest%%"$TAB"*}; rest=${rest#*"$TAB"}
	rm -f "$WORK"/f[0-9]*
	_i=0
	while [ "$_i" -lt "$nfiles" ]; do
		_f=${rest%%"$TAB"*}; rest=${rest#*"$TAB"}
		dec_to "$_f" "$WORK/f$_i"
		set -- "$@" "$WORK/f$_i"
		_i=$((_i + 1))
	done
	dec_to "$rest" "$WORK/want"

	# `< /dev/null` on every run. Without it a program that falls back to stdin
	# -- which ft_cat does by design -- consumes the rest of the corpus, the
	# loop ends early, and the layer reports "OK" having checked one case.
	"$BIN" "$@" < /dev/null > "$WORK/got" 2> /dev/null
	st=$?
	CHECKED=$((CHECKED + 1))

	cmp -s "$WORK/want" "$WORK/got" && continue
	FAILED=$((FAILED + 1))
	_fault=$(classify "$WORK/want" "$WORK/got" "$st")
	echo "$_fault" >> "$WORK/faults"

	[ "$FAILED" -le "$SHOW" ] || continue
	{
		printf '\n  case %d  [%s]  %s\n' "$CHECKED" "$tag" "$_fault"
		printf '    flags:    %s\n' "$(printf '%s ' "$@" | sed "s|$WORK/|<file>|g")"
		_i=0
		while [ "$_i" -lt "$nfiles" ]; do
			printf '    file %d:   %s bytes\n' "$_i" "$(wc -c < "$WORK/f$_i")"
			_i=$((_i + 1))
		done
		printf '    expected: %s bytes\n' "$(wc -c < "$WORK/want")"
		printf '    got:      %s bytes\n' "$(wc -c < "$WORK/got")"
		# The first differing BYTE, with its offset, from od rather than from a
		# text diff: these outputs are binary in general, and "line 4 differs"
		# says nothing about a file that has no lines.
		printf '    first difference: %s\n' \
			"$(cmp "$WORK/want" "$WORK/got" 2>&1 | sed -n '1p')"
		printf '    expected around it:\n'
		od -An -c -N 64 "$WORK/want" | sed 's/^/      /' | sed -n '1,3p'
		printf '    got around it:\n'
		od -An -c -N 64 "$WORK/got" | sed 's/^/      /' | sed -n '1,3p'
		[ "$st" -lt 128 ] || printf '    (killed by signal %d)\n' "$((st - 128))"
	} >> "$WORK/report"
done < "$WORK/corpus.tsv"

# The loop must have SEEN the corpus. A program that eats stdin, a corpus whose
# last line has no newline, a `while read` that died on the first case: every
# one of them ends here with fewer cases run than the file holds, and every one
# used to be reported as a pass.
if [ "$CHECKED" -ne "$CASES" ]; then
	echo "file_check: ran $CHECKED of $CASES cases. Refusing to report on a partial replay." >&2
	exit 2
fi

if [ "$FAILED" -eq 0 ]; then
	echo "file_check: PASS — $CHECKED cases, every one byte-identical to the reference."
	exit 0
fi

echo "file_check: FAIL — $FAILED of $CHECKED cases differ from the reference."
cat "$WORK/report"
echo ""
echo "  by kind:"
LC_ALL=C sort "$WORK/faults" | uniq -c | sort -rn | sed 's/^/    /'
echo ""
echo "  A truncation of exactly one buffer's worth is a read loop that runs"
echo "  once; a truncation at the first NUL is a buffer treated as a string."
exit 1
