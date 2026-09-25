#!/bin/sh
# Deliverable file-set check (tag "files").
#
# The Moulinette looks at WHICH FILES you turned in before it looks at what they
# do: a required file that is missing is an instant KO, and some projects also
# object to files nobody asked for. No other layer here can see that — a missing
# file is currently a Bazel *analysis* error (a wall of text about a label that
# does not exist, not a test result), and an extra file is invisible entirely,
# yet it still gets pushed to Vogsphere by //tools:submit.
#
# The two halves are deliberately NOT treated alike:
#
#   MISSING a required file  -> FAIL. The subject names its files exactly; there
#                               is no argument to be had.
#   An EXTRA file            -> WARNING, and the test still passes. Rushes are
#                               reviewed by a human, not auto-graded, and an
#                               extra file is often defensible (the Norm bans
#                               declaring a struct in a .c, so a rush that wants
#                               one needs a header the subject never mentions).
#                               You just have to be ready to justify it at the
#                               evaluation — which is what the warning is for.
#                               Pass --strict where a subject really does forbid
#                               extras.
#
# The actual file list is supplied by the caller (Bazel's glob sees the real
# directory at analysis time; a test sandbox would only ever see files that were
# already declared, which is exactly the blind spot this closes).
#
# Usage:
#   files_test.sh --label NAME [--required NAME]... [--optional NAME]...
#                 [--actual PATH]... [--strict]
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "files_test.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require basename

LABEL=""
STRICT=0
REQ=""
OPT=""
ACT=""

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "files_test.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--label) need "$1" "$#"; LABEL="$2"; shift 2 ;;
		--required) need "$1" "$#"; REQ="$REQ $2"; shift 2 ;;
		--optional) need "$1" "$#"; OPT="$OPT $2"; shift 2 ;;
		--actual) need "$1" "$#"; ACT="$ACT $(basename "$2")"; shift 2 ;;
		--strict) STRICT=1; shift ;;
		*) echo "files_test.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

has() {
	for _x in $2; do
		[ "$_x" = "$1" ] && return 0
	done
	return 1
}

echo "files_test: ${LABEL:-deliverable}"
echo ""
printf '  %-28s %s\n' "REQUIRED BY THE SUBJECT" "STATUS"
printf '  %-28s %s\n' "----------------------------" "----------"

MISSING=0
for f in $REQ; do
	if has "$f" "$ACT"; then
		printf '  %-28s %s\n' "$f" "present"
	else
		printf '  %-28s %s\n' "$f" "MISSING <"
		MISSING=$((MISSING + 1))
	fi
done

EXTRA=""
for f in $ACT; do
	has "$f" "$REQ" && continue
	has "$f" "$OPT" && continue
	EXTRA="$EXTRA $f"
done

if [ -n "$EXTRA" ]; then
	echo ""
	echo "  FILES THE SUBJECT DID NOT ASK FOR:"
	for f in $EXTRA; do
		printf '    %s\n' "$f"
	done
fi

echo ""
if [ "$MISSING" -gt 0 ]; then
	echo "  RESULT: FAIL — $MISSING required file(s) missing."
	echo "  The subject names the files it wants, exactly. A file that is not"
	echo "  there cannot be graded, whatever the rest of the module does."
	exit 1
fi

if [ -n "$EXTRA" ]; then
	if [ "$STRICT" -eq 1 ]; then
		echo "  RESULT: FAIL — this subject does not allow extra files."
		exit 1
	fi
	echo "  RESULT: PASS (with a warning)"
	echo "  Every required file is there. The extra one(s) above are not a"
	echo "  failure — this project is reviewed by a person, and an extra file is"
	echo "  often justifiable. Be ready to say WHY it exists at the evaluation,"
	echo "  and remember //tools:submit pushes it too."
	exit 0
fi

echo "  RESULT: PASS — exactly the files the subject asks for."
exit 0
