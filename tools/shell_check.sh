# shellcheck shell=sh
# (sourced library, never executed, so it has no shebang -- this directive
#  tells shellcheck the dialect without implying the file is a program.)
# shell_check.sh — tiny library sourced by c-piscine shell check scripts so a
# failing exercise shows a per-PROPERTY checklist instead of one opaque exit code.
# The shell_test.sh runner exports SHELL_CHECK_LIB pointing here; a check.sh does:
#
#     . "${SHELL_CHECK_LIB:?}"
#     ck     "produces foo.tar"        test -f foo.tar          # PASS if cmd exits 0
#     ck_eq  "member size (bytes)"     "$got" "40"              # compares; shows want/got
#     ck_report                                                  # prints RESULT, exits 0/1
#
# Show SPEC values (sizes, permissions, names from the subject) freely — they are
# requirements, not the solution. Do NOT pass a value that would reveal the answer
# itself (e.g. an expected computed output): use plain `ck` (pass/fail) for those.

_CK_N=0
_CK_FAIL=0
_CK_REPORTED=0

# A check.sh that forgets its final ck_report prints [FAIL] lines to the log and
# then exits with whatever its LAST command happened to return -- usually 0. The
# log says FAIL, Bazel says PASSED, and nothing reconciles them. All 17 live
# check scripts do call ck_report, so this is latent rather than broken; adding
# the eighteenth is all it would take, and the cost of noticing late is a
# student's Moulinette result.
#
# shell_test.sh runs the check script with `sh "$CHECK"`, a separate shell, so
# this trap belongs to the check script alone and cannot touch the runner.
#
# It never turns a red into a green: a non-zero status is passed through
# untouched, and only an unreported exit 0 is converted. The trap returns rather
# than exiting on the normal path, which leaves ck_report's own status intact.
_ck_exit_guard() {
	_ck_rc=$?
	if [ "$_CK_REPORTED" = 1 ]; then
		return
	fi
	printf '  ------------------------------\n'
	printf '  BROKEN CHECK SCRIPT: it ended without calling ck_report.\n'
	printf '  %d check(s) ran and %d failed, but the exit status came from\n' \
		"$_CK_N" "$_CK_FAIL"
	printf '  whatever command happened to run last, not from them. Without\n'
	printf '  ck_report this test can print [FAIL] and still be reported as\n'
	printf '  passing. Add ck_report as the final line of the check script.\n'
	if [ "$_ck_rc" -ne 0 ]; then
		exit "$_ck_rc"
	fi
	exit 1
}
trap _ck_exit_guard EXIT

# ck_skip "<why>" -> the exercise cannot be checked HERE, and says so.
#
# One exercise needs it: shell-00 ex07's answer is derived from a resource 42
# issues and this repo does not redistribute, so on a fresh clone there is
# nothing to check against. That is not a pass and not a failure of the
# student's work -- and the difference has to survive, because a skip that
# looks like a pass is the defect class this whole repo is built against.
#
# NO_SKIP=1 turns it into a failure, the same lever every other gated layer
# here answers to, so the forced sweep can still tell "quiet because clean"
# from "quiet because it never ran". It reports and exits, so the guard above
# is satisfied.
ck_skip() {
	_CK_REPORTED=1
	printf '  ------------------------------
'
	printf '  SKIP: %s
' "$1"
	if [ "${NO_SKIP:-0}" = "1" ]; then
		printf '  NO_SKIP=1 is set, so this counts as a failure: nothing was checked.
'
		exit 1
	fi
	printf '  RESULT: SKIPPED (nothing was checked)
'
	exit 0
}

# ck "<requirement>" cmd...  -> PASS when the command succeeds (exit 0).
ck() {
	_lbl=$1
	shift
	_CK_N=$((_CK_N + 1))
	if "$@" >/dev/null 2>&1; then
		printf '  [PASS] %s\n' "$_lbl"
	else
		printf '  [FAIL] %s\n' "$_lbl"
		_CK_FAIL=$((_CK_FAIL + 1))
	fi
}

# ck_eq "<requirement>" "<got>" "<want>"  -> compares two strings; shows both on fail.
ck_eq() {
	_CK_N=$((_CK_N + 1))
	if [ "$2" = "$3" ]; then
		printf '  [PASS] %s\n' "$1"
	else
		printf '  [FAIL] %s (want %s, got %s)\n' "$1" "$3" "${2:-<empty>}"
		_CK_FAIL=$((_CK_FAIL + 1))
	fi
}

# Trailing-newline assertions. The Moulinette compares stdout byte-for-byte, so a
# stray (or missing) final newline is a real KO the shell-stripping `$(...)` capture
# is blind to. Capture the deliverable's RAW output to a file first, e.g.:
#     raw=$(mktemp); sh "$D" > "$raw" 2>/dev/null
# then assert the required terminator. Whether a final newline is required is a SPEC
# property (from the subject's example), not the answer, so this reveals nothing.
_ck_lastbyte() { [ -s "$1" ] && tail -c1 "$1" | od -An -tx1 | tr -d ' \n'; }

# ck_no_final_newline "<requirement>" <file>  -> PASS if <file> is non-empty and its
# last byte is NOT a newline (output ends exactly at its last visible char).
ck_no_final_newline() {
	_CK_N=$((_CK_N + 1))
	if [ -s "$2" ] && [ "$(_ck_lastbyte "$2")" != "0a" ]; then
		printf '  [PASS] %s\n' "$1"
	else
		printf '  [FAIL] %s\n' "$1"
		_CK_FAIL=$((_CK_FAIL + 1))
	fi
}

# ck_final_newline "<requirement>" <file>  -> PASS if <file> is non-empty and ends
# with a newline (the normal terminator for line-oriented output).
ck_final_newline() {
	_CK_N=$((_CK_N + 1))
	if [ "$(_ck_lastbyte "$2")" = "0a" ]; then
		printf '  [PASS] %s\n' "$1"
	else
		printf '  [FAIL] %s\n' "$1"
		_CK_FAIL=$((_CK_FAIL + 1))
	fi
}

# ck_report  -> print the summary line and exit (0 if all checks passed, else 1).
ck_report() {
	_CK_REPORTED=1
	printf '  ------------------------------\n'
	if [ "$_CK_FAIL" -eq 0 ]; then
		printf '  RESULT: PASS  (%d/%d checks)\n' "$_CK_N" "$_CK_N"
		exit 0
	fi
	printf '  RESULT: FAIL  (%d/%d checks passed)\n' "$((_CK_N - _CK_FAIL))" "$_CK_N"
	exit 1
}
