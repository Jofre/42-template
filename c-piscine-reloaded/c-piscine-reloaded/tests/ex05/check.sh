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
# shellcheck source=../../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

dir=${1:-.}
cd "$dir" 2>/dev/null || { printf 'cannot enter %s\n' "$dir"; exit 1; }

printf "  CHECK: %s\n" "$dir"

f=$(ls -1d -- *MaRV* 2>/dev/null | head -1)

# A file matching the special name pattern exists.
ck "a file matching *MaRV* exists" test -n "$f"

# THE NAME ITSELF. The glob only FINDS the file; the Moulinette looks it up by
# the exact name the subject gives, so a file called anything else that merely
# contains MaRV was a KO this check passed. The name is stored as a digest and
# compared pass/fail with nothing echoed: typed out here it would show how it
# has to be quoted, and that is the whole exercise.
#
# PROVENANCE: the SHA-256 (and, for a box without sha256sum, the cksum sum) of
# the 18 bytes the subject prints as the name, cross-checked against the name a
# working turn-in actually creates. sha256sum is coreutils and on the campus box;
# cksum is the fallback rather than skipping, as in Shell 01 ex08.
if command -v sha256sum >/dev/null 2>&1; then
	digest() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }
	NAME_DIGEST="bcb7c2b8fd139077bf1c2864eec2bda41939fe3057afa9ff92e2041ccaac4703"
else
	# cksum prints "<sum> <bytes>"; the length is not published here either.
	digest() { printf '%s' "$1" | cksum | cut -d' ' -f1; }
	NAME_DIGEST="15740168"
fi

if [ -n "$f" ]; then
	ck "its name is exactly the one the subject gives, byte for byte" \
		test "$(digest "$f")" = "$NAME_DIGEST"

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

	# TIGHTENING (to Shell 01 ex01's standard): assert the terminator on the RAW bytes and
	# confirm the content is byte-for-byte exact against the controlled fixture.
	ck_no_final_newline "no trailing newline: file ends exactly at its last byte" "$raw"
	ck "content is byte-for-byte exactly the 2 bytes 42 (no extra/trailing bytes)" \
		cmp -s "$raw" "$want"

	rm -f "$raw" "$want"

	# NOTHING ELSE IN THE TURN-IN, which every other exercise in both shell
	# modules gets from its exNN_files layer. This one has no such layer, and
	# cannot: that layer needs the deliverable's NAME written into BUILD.bazel,
	# and here the name IS the answer. So the property is asserted where the
	# name is already reached through a glob and never typed.
	#
	# Subject p.3: "You must not leave any additional files in your directory
	# other than those specified in the assignment." Counted rather than named,
	# for the same reason: the count is the requirement, the name is the answer.
	# Dotfiles included -- a half-run cleanup leaves those too, and //tools:submit
	# pushes them with `git add -A --force`.
	left=0
	for e in * .[!.]* ..?*; do
		[ -e "$e" ] || [ -L "$e" ] || continue
		left=$((left + 1))
	done
	ck_eq "the directory holds this one file and nothing else" "$left" "1"
else
	ck "its name is exactly the one the subject gives, byte for byte" false
	ck "permissions are -rw---xr-- (614)" false
	ck "file is exactly 2 bytes"          false
	ck "content is 42 (shell-stripped view)" false
	ck "no trailing newline: file ends exactly at its last byte" false
	ck "content is byte-for-byte exactly the 2 bytes 42 (no extra/trailing bytes)" false
	ck "the directory holds this one file and nothing else" false
fi

ck_report
