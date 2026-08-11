#!/bin/sh
# ex05 — "Can you create it?": the deliverable is a single file whose name is full
# of shell metacharacters (matched here via the *MaRV* glob so the literal special
# name is never typed into this student-readable check). The file must:
#   - have permissions -rw---xr-- (614),
#   - contain EXACTLY the two bytes "42" — no trailing newline, no extra bytes.
#
# The Moulinette compares the file byte-for-byte, so a stray trailing newline (the
# classic "42\n" KO) is a real failure. The previous check read the content with a
# $(cat ...) command substitution, which SILENTLY STRIPS a trailing newline — that
# assertion's "no trailing newline" claim was therefore blind, and the newline was
# only caught incidentally by the size check. We now assert the terminator directly
# on the RAW bytes and confirm the content with a byte-for-byte compare against a
# controlled fixture we create ourselves. "42", the size (2) and the mode (614) are
# SPEC constants from the subject, not the answer (the answer is the tricky filename).
# shellcheck source=../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

dir=${1:-.}
cd "$dir" 2>/dev/null || { printf 'cannot enter %s\n' "$dir"; exit 1; }

printf "  CHECK: %s\n" "$dir"

f=$(ls -1d -- *MaRV* 2>/dev/null | head -1)

# A file matching the special name pattern exists.
ck "a file matching *MaRV* exists" test -n "$f"

if [ -n "$f" ]; then
	perms=$(ls -l -- "$f" | cut -c1-10)
	size=$(wc -c < "$f" | tr -d ' ')
	content=$(cat -- "$f")

	# Raw bytes of the file, so the exact terminator can be asserted (a $(cat)
	# capture is blind to a trailing newline and would hide the "42\n" KO).
	raw=$(mktemp)
	cat -- "$f" > "$raw"

	# Controlled fixture holding the exact required 2 bytes "42" (a spec constant),
	# for a byte-for-byte compare that also catches any stray trailing/extra byte.
	want=$(mktemp)
	printf '42' > "$want"

	# SPEC values from the subject: perms -rw---xr-- (614), size 2, content "42".
	ck_eq "permissions are -rw---xr-- (614)" "$perms" "-rw---xr--"
	ck_eq "file is exactly 2 bytes"          "$size"  "2"
	ck_eq "content is 42 (shell-stripped view)" "$content" "42"

	# TIGHTENING (to the ex01 standard): assert the terminator on the RAW bytes and
	# confirm the content is byte-for-byte exact against the controlled fixture.
	ck_no_final_newline "no trailing newline: file ends exactly at its last byte" "$raw"
	ck "content is byte-for-byte exactly the 2 bytes 42 (no extra/trailing bytes)" \
		cmp -s "$raw" "$want"

	rm -f "$raw" "$want"
else
	ck "permissions are -rw---xr-- (614)" false
	ck "file is exactly 2 bytes"          false
	ck "content is 42 (shell-stripped view)" false
	ck "no trailing newline: file ends exactly at its last byte" false
	ck "content is byte-for-byte exactly the 2 bytes 42 (no extra/trailing bytes)" false
fi

ck_report
