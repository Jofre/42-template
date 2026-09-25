#!/bin/sh
# ex07 — r_dwssap.sh: a multi-stage /etc/passwd text pipeline.
#
# HOST-COUPLED: the deliverable reads the hardcoded /etc/passwd, whose contents
# vary per machine. We therefore CANNOT build a controlled fixture for it (that
# would need root) nor recompute an authoritative reference without re-implementing
# the exercise. So we assert SPEC PROPERTIES only — and crucially the TERMINATOR.
#
# The subject's Example Output ends "...revressta_.$>" — the "$>" prompt is glued
# directly onto the final ".", i.e. there is NO trailing newline. That exact
# terminator is what the Moulinette byte-compares; a lenient $(...) capture strips
# it and is blind to a stray "\n" (the exact class of KO that hid here before).
# Whether a final newline is present is a spec fact from the example, not the
# answer, so these assertions reveal nothing.
#
# ...BUT "we cannot control the input" DOES NOT MEAN "only format is testable",
# which is what the paragraph above used to conclude. The subject's fifth bullet —
# "keep only logins between FT_LINE1 and FT_LINE2 (INCLUSIVE)" — is a property of
# the program relative to ITSELF, and it can be pinned without any reference
# implementation and without touching /etc/passwd. That matters, because the only
# range this check used to drive was 1..3 — a window anchored at the very first
# line, which is the one place where several different readings of "between
# FT_LINE1 and FT_LINE2, inclusive" happen to agree. A very common student form
# misreads the two bounds, is wrong for almost every other range, and at 1..3 it
# emitted the identical three tokens and scored 7/7. So the one piece of
# arithmetic this step is made of went entirely unmeasured. (Stated as behaviour,
# not as a command line: this file is student-readable and does not hand over
# pipelines.)
#
# WHY THE SLICE PROPERTY BELOW IS LEGITIMATE, and not an accident of this host:
# the subject fixes the ORDER of the steps ("Follow the steps in the exact order
# given!"), and the sort is bullet FOUR while the range selection is bullet FIVE.
# The window is therefore taken from an ALREADY-SORTED list, which is exactly what
# makes "the answer for L1..L2 is the L1..L2 slice of the answer for the whole
# range" a requirement rather than a coincidence. If the two steps were reversed,
# a correct program could sort a subset into positions the full list never has,
# and this assertion would be wrong to make. It is the step order that earns it.
#
# The block at the bottom fixes that self-consistently: ask the deliverable for a
# range wider than any /etc/passwd to learn the full ordered list N, then ask for
# a narrow range and require the answer to be exactly that slice of N. Two runs
# of the student's own program, compared against each other — no fixture, no
# root, and nothing host-specific asserted. Cutting the slice out of N is itself
# the exercise's fifth step, so it is not done in shell here: //oracle's
# `shell01_line_range` does it, in Rust (AGENTS.md §2 — readable, not pasteable
# into a shell script). It is handed the student's own full list and nothing
# else, so it is not a reference implementation of the exercise; it only cuts
# lines out of whatever it is given. A second CONCRETE range
# was the alternative and would also have caught this bug; the slice form is
# preferred because it costs the same to write, states the actual requirement
# instead of a number that happens to differ, and keeps working unchanged on a
# machine whose /etc/passwd looks nothing like this one.
# shellcheck source=../../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

D=${1:-r_dwssap.sh}
printf "  CHECK: %s\n" "$D"

ck "r_dwssap.sh exists"      test -f "$D"
ck "r_dwssap.sh is readable" test -r "$D"

# Capture RAW bytes (trailing newline preserved) AND the shell-stripped form.
raw=$(mktemp)
FT_LINE1=1 FT_LINE2=3 sh "$D" > "$raw" 2>/dev/null
out=$(FT_LINE1=1 FT_LINE2=3 sh "$D" 2>/dev/null)

ck "produces output (needs a populated /etc/passwd)" test -n "$out"

# TERMINATOR — the KO class: output must end exactly at its final "." with no
# trailing newline (subject example: "...revressta_.$>").
ck_no_final_newline "ends exactly at the final '.' — no trailing newline" "$raw"

# Structure — subject: "Join them in a single line". Exactly one line, no embedded
# newlines. (The format regex below uses grep -q, which would pass on a multi-line
# output as long as one line matched, so this is an independent, stricter check.)
ck "output is a single line (no embedded newlines)" \
   sh -c 'test "$(printf "%s" "$1" | wc -l | tr -d " ")" -eq 0' _ "$out"

# Subject: "End the output with a '.'".
ck "output ends with a period" \
   sh -c 'case "$1" in *.) exit 0;; *) exit 1;; esac' _ "$out"

# Subject: "separated by ', '". Format is a ", "-joined token list ending in a period.
ck "output is a ', '-joined list ending in a period" \
   sh -c 'printf "%s\n" "$1" | grep -qE "^([A-Za-z0-9_.-]+, )*[A-Za-z0-9_.-]+\.\$"' _ "$out"

# --- INCLUSIVE RANGE (see the header for why 1..3 alone could not see this) ---
#
# tokens(): turn one run's output into one login per line, so two runs can be
# compared entry by entry. Drop the final '.', cut at every ',' (a login name
# never contains one), and drop the one space the ", " separator leaves at the
# front of each piece. Written with the shell's own parameter expansion and no
# external tool, so it behaves the same under whatever /bin/sh the campus box
# ships -- and so it shows nothing about which tools build the list.
tokens() {
	_rest=${1%.}
	[ -n "$_rest" ] || return 0
	while :; do
		_tok=${_rest%%,*}
		printf '%s\n' "${_tok# }"
		case "$_rest" in
			*,*) _rest=${_rest#*,} ;;
			*) break ;;
		esac
	done
}

ORACLE=${ORACLE:?this check needs //oracle: declare the exercise with oracle = True}

# Full ordered list: a range wider than any plausible /etc/passwd. Both a correct
# and a buggy program agree here (each simply runs out of lines), which is what
# makes it a safe way to learn N without a reference implementation.
allout=$(FT_LINE1=1 FT_LINE2=999 sh "$D" 2>/dev/null)
alltok=$(tokens "$allout")

# Pick a window that is NOT anchored at line 1 — anchoring at 1 is exactly the
# degenerate case that hid the bug — and that fits inside the list we just saw.
L1=2
L2=4

# WHETHER THE WINDOW IS OBSERVABLE IS A FACT ABOUT THE HOST, so the host is what
# gets asked. This guard used to count the tokens the DELIVERABLE printed for the
# full range, which handed a broken program the power to switch its own tests
# off: one emitting three tokens for every range fell short of the window, both
# assertions below were skipped, and the runner printed RESULT: PASS (7/7).
# A guard a failing program can satisfy by failing is not a guard.
#
# /etc/passwd is where the logins come from — the header above already says the
# deliverable reads it — so its line count is how many logins EXIST to be
# windowed, whatever the program does with them. Counting lines is not the
# exercise: the exercise is the ordering and the join, and this reveals neither.
#
# grep -c rather than wc -l: a final line with no newline is invisible to wc.
# The empty fallback is not decoration either — grep -c PRINTS 0 and EXITS 1
# when nothing matches, so a `|| echo 0` would append a second zero and the
# comparison would die on a bad number.
hostn=$(grep -c . /etc/passwd 2> /dev/null)
[ -n "$hostn" ] || hostn=0

if [ "$hostn" -ge "$L2" ]; then
	midout=$(FT_LINE1="$L1" FT_LINE2="$L2" sh "$D" 2>/dev/null)
	midtok=$(tokens "$midout")

	# Count first: it gives the clearest failure message. "inclusive" means the
	# window holds L2 - L1 + 1 entries; showing that number reveals nothing about
	# /etc/passwd and nothing about how to select the window — it is the spec.
	ck_eq "range $L1..$L2 keeps exactly (${L2} - ${L1} + 1) logins" \
		"$(printf '%s\n' "$midtok" | wc -l | tr -d ' ')" "$((L2 - L1 + 1))"

	# Then the stronger property: the window is that exact slice of the full list,
	# cut by the oracle (see the header). Plain pass/fail — the values are the
	# program's own output, not ours to echo.
	ck "range $L1..$L2 is exactly entries $L1 through $L2 of the full list" \
		test "$midtok" = "$(printf '%s\n' "$alltok" | "$ORACLE" shell01_line_range "$L1" "$L2")"
else
	# Fewer logins than the window needs: nothing to observe, and asserting
	# anyway would red a CORRECT deliverable. ck_skipped rather than a bare
	# printf, so the skip reaches the RESULT line instead of leaving a bare
	# PASS behind it, and so NO_SKIP=1 can force it like every other gate.
	ck_skipped "/etc/passwd holds only $hostn login line(s) — too few to probe a $L1..$L2 window"
fi

rm -f "$raw"
ck_report
