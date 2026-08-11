#!/bin/sh
# Run a binary and compare its captured output against an expected file,
# rendering a legible per-line PASS/FAIL table (not a raw diff).
#
# The table shows EVERY line — passing and failing, in order — because for a
# student who did not write the test, the passing rows document what the
# function is supposed to do. Columns: CASE | EXPECTED | GOT | STATUS.
#
# Usage:
#   diff_output.sh --bin PATH --expected PATH [options] [-- PROG ARGS...]
#
# Options:
#   --stream stdout|stderr   which stream to compare (default: stdout)
#   --stdin PATH             feed this file to the program's stdin
#   --sanitize               normalise a leading 16-hex-digit address column to
#                            its offset from the first row of its block, so that
#                            an ASLR-randomised value can still be compared for
#                            width, letter case and the +16 step (for
#                            ft_print_memory / hexdump-style output). See the
#                            long comment at the normalisation step itself.
#   --labeled                each output/expected line is "CASE<TAB>VALUE"; the
#                            CASE is shown in its own column. Without this, the
#                            CASE column is just the 1-based line number.
#   --clues PATH             a clues.tsv of pedagogic hints (concept groups). When
#                            a test fails, fired hints are shown below the table.
#   --exit CODE              also assert the program exits with CODE
#   --                       everything after is passed verbatim to the binary
#
# Exit status: 0 if output (and exit code, if checked) match, 1 otherwise.
#
# clues.tsv format (tab-separated, one concept group per line; '#'/blank ignored):
#   <hint text><TAB><member CASE label><TAB><member CASE label>...
# A group's hint fires when ANY of its member cases fails. A line with no member
# labels fires on any failure. Hints are shown most-fundamental first; the count
# shown is capped (default 3) and overridable with the CLUE_MODE env var
# (an integer, or "all"), forwarded by Bazel via --test_env=CLUE_MODE=all.

set -u

# The external commands this runner takes from PATH, declared and probed at
# startup. This is the one place the reasoning is written down; every other
# runner carries the same helper and points here.
#
# WHY DECLARE THEM. The failure without this is silent. `grep -q ... && ...`
# with no grep on the machine does not error -- it reads exactly like "no
# match", so the branch is skipped and a real finding is reported under the
# wrong headline, or not at all. asan_run.sh is the worked example: its
# sanitizer-signature probe is a grep, and without one a genuine ASan report
# would be announced as "died on signal 6".
#
# WHY EXIT 2, NEVER 1. 1 means the thing under test is wrong. 2 means the check
# never ran and a human should look. //tools/tests:selftest's want_red insists
# on exit 1 for exactly this reason, so the two can never be confused.
#
# WHY NOT PIN THEM. The same answer /bin/sh got: the question is whether the
# USAGE is portable, not whether the binary is ours. shellcheck's SC3xxx family
# refuses a bashism statically, //tools/tests:selftest_bash replays every arm
# under a second shell, and //tools:conventions recomputes the list below from
# what the script actually calls, so it cannot go stale. Pinning coreutils would
# buy a guarantee those three already give.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "diff_output.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk cmp head mktemp mv rm sed tail tr wc

BIN=""
EXPECTED=""
STREAM="stdout"
STDIN_FILE=""
SANITIZE=0
LABELED=0
CLUES_FILE=""
EXPECT_EXIT=""

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "diff_output.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--bin) need "$1" "$#"; BIN="$2"; shift 2 ;;
		--expected) need "$1" "$#"; EXPECTED="$2"; shift 2 ;;
		--stream) need "$1" "$#"; STREAM="$2"; shift 2 ;;
		--stdin) need "$1" "$#"; STDIN_FILE="$2"; shift 2 ;;
		--sanitize) SANITIZE=1; shift ;;
		--labeled) LABELED=1; shift ;;
		--clues) need "$1" "$#"; CLUES_FILE="$2"; shift 2 ;;
		--exit) need "$1" "$#"; EXPECT_EXIT="$2"; shift 2 ;;
		--) shift; break ;;
		*) echo "diff_output.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

if [ -z "$BIN" ] || [ -z "$EXPECTED" ]; then
	echo "diff_output.sh: --bin and --expected are required" >&2
	exit 2
fi

ACTUAL=$(mktemp)
# The stream we are NOT comparing used to go to /dev/null. Keep it: when
# something goes wrong it usually says why (a sanitizer report, a glibc
# "free(): invalid next size", the program's own error message), and throwing it
# away made every failure harder to read than it needed to be.
OTHER=$(mktemp)
# This is the most-invoked runner in the repo -- 21 macro sites, and every
# per-case output test in every module goes through it -- and its two temp files
# were removed by three hand-written `rm -f` on the exit paths somebody thought
# of. A trap covers the ones nobody did: the awk-driven exits below, and the
# signal Bazel sends a test that runs out of time.
trap 'rm -f "$ACTUAL" "$OTHER"' EXIT INT TERM

# Runaway guard. This runs code nobody has verified: a loop that never
# terminates its condition writes at page-cache speed for the WHOLE Bazel
# timeout — gigabytes into the test tmpdir — and an infinite loop that prints
# nothing burns a core for 60s before Bazel gives up with no explanation the
# student can act on. run_check.sh has carried this pattern for the rush all
# along; every other runner executed student code bare.
#
# `ulimit -f` bounds the output at the source: the kernel kills the writer with
# SIGXFSZ (exit 153) the moment it goes past the budget, so nothing can fill the
# disk. It counts 512-byte blocks. The budget scales off the expected output —
# 32x it, floor 4 MiB — so it is far above any legitimate result and far below
# "fills the container".
EXP_BYTES=$(wc -c < "$EXPECTED" 2>/dev/null || echo 0)
CAP=$(( EXP_BYTES * 32 ))
[ "$CAP" -lt 4194304 ] && CAP=4194304
BLOCKS=$(( CAP / 512 + 2 ))

# An inner timeout, well under Bazel's, so an infinite loop is reported as one
# instead of surfacing as an opaque Bazel timeout. Every test using this runner
# finishes in well under a second.
TMO="${DIFF_TIMEOUT:-30}"
if command -v timeout >/dev/null 2>&1; then
	RUNNER="timeout -s KILL $TMO"
else
	RUNNER=""
fi

(
	ulimit -f "$BLOCKS" 2>/dev/null
	if [ -n "$STDIN_FILE" ]; then
		if [ "$STREAM" = "stderr" ]; then
			$RUNNER "$BIN" "$@" < "$STDIN_FILE" 2> "$ACTUAL" > "$OTHER"
		else
			$RUNNER "$BIN" "$@" < "$STDIN_FILE" > "$ACTUAL" 2> "$OTHER"
		fi
	else
		if [ "$STREAM" = "stderr" ]; then
			$RUNNER "$BIN" "$@" 2> "$ACTUAL" > "$OTHER"
		else
			$RUNNER "$BIN" "$@" > "$ACTUAL" 2> "$OTHER"
		fi
	fi
)
RC=$?

if [ "$RC" -eq 153 ]; then
	echo " --------------------------------------------------"
	echo " RUNAWAY OUTPUT: the program kept printing past a $CAP-byte budget and"
	echo "                 was stopped. Expected output here is $EXP_BYTES bytes."
	echo "                 A loop whose exit condition is never reached prints"
	echo "                 forever; nothing about the output below was checked."
	exit 1
fi
if [ "$RC" -eq 137 ] || [ "$RC" -eq 124 ]; then
	echo " --------------------------------------------------"
	echo " TIMEOUT: the program did not finish within ${TMO}s (infinite loop?)."
	echo "          Every case in this layer should complete almost instantly."
	exit 1
fi

if [ "$SANITIZE" -eq 1 ]; then
	# The address column of a hex dump cannot be compared literally: ASLR moves
	# the stack on every run, so the SAME CORRECT program prints a different
	# number each time. This step used to rewrite the column to sixteen zeros,
	# which threw away everything about it except its width — and then a program
	# that never touched the pointer at all was byte-perfect green. Three
	# implementations were built against c-02 ex12's real harness to confirm it:
	# one printing the same address on every row, one printing sixteen literal
	# zeros with no pointer arithmetic anywhere, and one printing the right value
	# in UPPERCASE hex; all three passed. The committed fixture even DISPLAYED
	# the zeros, so it documented the second of those as the expected answer.
	#
	# What stays deterministic once the base address is unknowable is the STEP:
	# consecutive rows of one dump are 16 bytes apart, always. So each address is
	# rewritten to its offset from the first row of the block it belongs to, a
	# new block starting wherever an address is not the previous one plus 16, or
	# wherever a non-address line interrupts the dump. A correct dump therefore
	# normalises to the ladder 0000000000000000 / 0000000000000010 /
	# 0000000000000020 …, restarting at zero for each separate buffer, whatever
	# ASLR did with the real pointers. That ladder is what lands in the EXPECTED
	# column of the table, so the +16 rule is something the student can READ
	# rather than something hidden inside this runner.
	#
	# Three properties are compared this way, and one is deliberately not:
	#   WIDTH — only an exactly-16-hex-digit field followed by ':' is rewritten
	#           at all, so a narrower or wider column keeps its raw random
	#           address and can never match a fixture. (This much already worked.)
	#   CASE  — "(UPPERCASE)" is appended when the field contains A-F. The test is
	#           ONE-SIDED on purpose: a lowercase program cannot produce A-F, so
	#           this can never redden a correct one, while an uppercase program is
	#           missed only if not one of its addresses contains a letter — which
	#           no stack address on this platform manages.
	#   STEP  — the +16 ladder above.
	#   VALUE — NOT checked, and not checkABLE from out here: the true pointer is
	#           unknowable to a test that only reads stdout. A program printing
	#           row_index * 16 into a 16-digit field still passes. That residual
	#           is the price of tolerating ASLR; closing it would need the harness
	#           itself to publish the addresses it handed in.
	#
	# Block boundaries are the one assumption here. Two SEPARATE buffers that
	# happen to sit exactly 16 bytes apart would merge into a single block and
	# shift the offsets the fixture expects, reddening a CORRECT program — and
	# nothing in a hex dump can tell that apart from one longer dump, since the
	# bytes are identical either way. So the argument has to come from the
	# harness, not from the output. c-02 ex12 is this runner's only --sanitize user
	# (tools/shell_test.sh has a --sanitize flag of its own, still carrying the old
	# zeros sed, but nothing passes it — if a shell exercise ever does, it reopens
	# exactly the hole described at the top of this comment and needs the same fix);
	# ex12 makes four dumps, so there are only two adjacent pairs to account for
	# (the third pair is separated by a line of plain text):
	#   str -> full  cannot merge — "ret==str:1" is printed between them, and any
	#                non-address line closes the block outright.
	#   full -> part cannot merge — `full` is char[17] ("0123456789ABCDEF" plus
	#                its NUL) and only its first 16 bytes are dumped, so full+16
	#                is a byte that BELONGS to full. No distinct object can start
	#                there. This one holds by construction, on any target.
	#   part -> np   is the single arithmetically possible merge: it needs `np` to
	#                land exactly 12 bytes past the end of char part[4]. Measured
	#                over gcc and clang at -O0/-O1/-O2/-O3/-Os: np sits at part+4
	#                under gcc, part-5 under clang -O0..-O3 and part+7 under
	#                clang -Os. Never part+16. (Note this is NOT "every buffer
	#                sits below the previous one" — under gcc np is ABOVE part.
	#                Only the exact +16 coincidence matters.)
	# The ilp32 layer replays this same fixture from a zig -m32 build, where the
	# first two pairs still hold by construction but the third has not been
	# re-measured. If a toolchain ever does merge that pair, the symptom is one
	# FAIL row on a correct program — and the NOTE printed above the table is what
	# makes that readable instead of mysterious.
	#
	# awk, not sed, because none of this is expressible without state; and awk's
	# `print` always terminates its line, so a program whose output does NOT end
	# in a newline would silently gain one here and the byte-exact guard further
	# down — which exists to catch exactly that — would stop seeing it. So probe
	# the last byte first and hand the answer to awk, whose END rule puts the file
	# back the way it came in.
	#
	# The probe pipes through `tr -d` rather than relying on `$(...)`: command
	# substitution strips trailing NEWLINES, which is the test we want, but the
	# shell also drops NUL bytes from the result, so output ending in a literal
	# NUL read as "ends in a newline" and gained one. `tr -d '\n' | wc -c` is 0
	# only for a real newline. Student output that ends in a NUL is far-fetched,
	# but the old sed preserved it exactly and this step must not quietly differ.
	EOL=1
	LASTB=$(tail -c 1 "$ACTUAL" | tr -d '\n' | wc -c)
	[ -s "$ACTUAL" ] && [ "$LASTB" -ne 0 ] && EOL=0
	awk -v eol="$EOL" '
	function ishex16(s,   i) {
		if (length(s) != 16) return 0
		for (i = 1; i <= 16; i++)
			if (index("0123456789abcdef", tolower(substr(s, i, 1))) == 0)
				return 0
		return 1
	}
	# s + 0x10, one digit at a time on the STRING. awk has no integer type, and a
	# 16-hex-digit address does not survive a pass through a double.
	function plus16(s,   i, d, out) {
		out = s
		i = 15
		while (i >= 1) {
			d = index("0123456789abcdef", substr(out, i, 1))
			out = substr(out, 1, i - 1) substr("0123456789abcdef", d % 16 + 1, 1) \
				substr(out, i + 1)
			if (d < 16) return out
			i--
		}
		return out
	}
	# One line of lookahead, so END can decide how to terminate the last one.
	function emit(s) { if (NR > 1) printf "%s\n", held; held = s }
	{
		field = substr($0, 1, 16)
		if (substr($0, 17, 1) == ":" && ishex16(field)) {
			low = tolower(field)
			if (open && low == want)
				off += 16
			else
				off = 0
			want = plus16(low)
			open = 1
			mark = (field ~ /[A-F]/) ? "(UPPERCASE)" : ""
			emit(sprintf("%016x%s:%s", off, mark, substr($0, 18)))
		} else {
			open = 0
			emit($0)
		}
	}
	END { if (NR > 0) printf "%s%s", held, (eol ? "\n" : "") }
	' "$ACTUAL" > "$ACTUAL.s" && mv "$ACTUAL.s" "$ACTUAL"
fi

# A student who did not write this runner has no way to know their address column
# was rewritten before the comparison, and the table would otherwise show them an
# EXPECTED value ("0000000000000010") that no correct program ever prints. Left
# unexplained that is worse than unhelpful: the obvious way to make the table go
# green is to print the numbers it is showing you, which is precisely the wrong
# answer. So say what was rewritten AND say not to chase it, above the table, in
# the terms the exercise is about.
if [ "$SANITIZE" -eq 1 ]; then
	echo " NOTE: the OS randomises where your memory lives (ASLR), so the address"
	echo "       column below is NOT compared literally — neither column shows the"
	echo "       real value. Both are normalised: every address is replaced by its"
	echo "       distance, in 16 hex digits, from the first row of its block, and a"
	echo "       new block starts wherever an address is not the previous one plus"
	echo "       16. A correct dump therefore reads 0000000000000000 / ...0010 /"
	echo "       ...0020 and restarts at zero for each buffer it is given. Compared:"
	echo "       the column's width, its letter case ('(UPPERCASE)' is appended when"
	echo "       it holds A-F) and the +16 step. Not compared: the address itself —"
	echo "       so do NOT print the numbers you see here. Print the real address of"
	echo "       each line's first byte, as the subject asks; only the SHAPE of that"
	echo "       column can be checked from outside your program."
fi

# Render the table and decide pass/fail. EXPECTED is read first (FNR==NR).
awk -v labeled="$LABELED" -v cluefile="$CLUES_FILE" -v cluemode="${CLUE_MODE:-}" \
	-v maxrows="${DIFF_MAX_ROWS:-40}" '
function pad(s, w,   r) { r = s; while (length(r) < w) r = r " "; return r }
function dash(w,    r)  { r = ""; while (length(r) < w) r = r "-"; return r }
function show_hints(   line, nf, f, j, fire, nfired, nall, limit, shown, k, gated) {
	nfired = 0
	nall = 0
	while ((getline line < cluefile) > 0) {
		if (line ~ /^[ \t]*#/ || line ~ /^[ \t]*$/) continue
		nf = split(line, f, "\t")
		nall++
		aclue[nall] = f[1]
		fire = 0
		if (nf <= 1) fire = 1
		else { for (j = 2; j <= nf; j++) if (f[j] in failed) { fire = 1; break } }
		# Remember WHICH KIND fired. A row with no member labels fires on any
		# failure, and that changes what an honest "there are more" line can
		# promise -- see below.
		if (fire) { nfired++; fclue[nfired] = f[1]; fcatch[nfired] = (nf <= 1) }
	}
	close(cluefile)
	if (nall == 0) return
	limit = 3
	if (cluemode == "all") limit = nall
	else if (cluemode ~ /^[0-9]+$/ && (cluemode + 0) > 0) limit = cluemode + 0

	# NOTHING KEYED TO THIS CASE. 83 cases across 31 exercises are named by no
	# clue row, in files that also have no catch-all -- and this used to return
	# in silence, so failing exactly one of them printed no HINTS block at all.
	# The uncovered ones are mostly the boundaries (INT_MIN, "", "returns
	# dest"), which is where a beginner is most stuck and least able to tell an
	# absent hint from an absent idea. The hints this exercise does have are
	# shown instead, said plainly to be unmatched so nobody chases the wrong one.
	if (nfired == 0) {
		shown = (nall < limit) ? nall : limit
		print " " dash(50)
		print " HINTS (none matches this case -- showing what this exercise has):"
		for (k = 1; k <= shown; k++) print "   * " aclue[k]
		if (nall > shown)
			printf "   (%d more -- CLUE_MODE=all shows every one)\n", nall - shown
		return
	}
	shown = (nfired < limit) ? nfired : limit
	print " " dash(50)
	print " HINTS:"
	for (k = 1; k <= shown; k++) print "   * " fclue[k]
	if (nfired > shown) {
		# "Unlock them by passing more cases" is only true of a CASE-KEYED row:
		# fixing an earlier case stops its hint firing, which lets a later one
		# rise into the cap. A row with no labels fires on ANY failure, so it
		# never stops until everything passes -- at which point there is no
		# HINTS block at all. Three clue files are entirely such rows, and
		# their rows 4..10 were therefore unreachable while this line promised
		# a way to reach them. Say which mechanism actually applies.
		gated = 0
		for (k = shown + 1; k <= nfired; k++) if (!fcatch[k]) gated = 1
		if (gated)
			printf "   (%d more hidden hint%s -- unlock %s by passing more cases, or CLUE_MODE=all)\n", \
				nfired - shown, (nfired - shown == 1 ? "" : "s"), \
				(nfired - shown == 1 ? "it" : "them")
		else
			printf "   (%d more hidden hint%s -- CLUE_MODE=all shows %s; passing cases will not, %s fire%s on any failure)\n", \
				nfired - shown, (nfired - shown == 1 ? "" : "s"), \
				(nfired - shown == 1 ? "it" : "them"), \
				(nfired - shown == 1 ? "it" : "they"), \
				(nfired - shown == 1 ? "s" : "")
	}
}
FNR == NR { want[FNR] = $0; ne = FNR; next }
          { got[FNR] = $0; ng = FNR }
END {
	n = (ne > ng) ? ne : ng
	hC = "CASE"; hE = "EXPECTED"; hG = "GOT"
	wC = length(hC); wE = length(hE); wG = length(hG)
	fails = 0
	for (i = 1; i <= n; i++) {
		ehas = (i <= ne); ghas = (i <= ng)
		eline = ehas ? want[i] : ""; gline = ghas ? got[i] : ""
		eval = eline; gval = gline; cse = "line " i
		if (labeled == "1") {
			p = index(eline, "\t")
			if (p > 0) { ecase = substr(eline, 1, p - 1); eval = substr(eline, p + 1) }
			else       { ecase = "" }
			q = index(gline, "\t")
			if (q > 0) { gcase = substr(gline, 1, q - 1); gval = substr(gline, q + 1) }
			else       { gcase = "" }
			if (ehas && ecase != "")      cse = ecase
			else if (ghas && gcase != "") cse = gcase
		}
		evald = ehas ? eval : "(no line)"
		gvald = ghas ? gval : "(no line)"
		ok = (ehas && ghas && eline == gline)
		C[i] = cse; E[i] = evald; G[i] = gvald; OKf[i] = ok
		if (!ok) { fails++; failed[cse] = 1 }
		if (length(cse) > wC)   wC = length(cse)
		if (length(evald) > wE) wE = length(evald)
		if (length(gvald) > wG) wG = length(gvald)
	}
	printf " %s | %s | %s | %s\n", pad(hC, wC), pad(hE, wE), pad(hG, wG), "STATUS"
	printf " %s-+-%s-+-%s-+-%s\n", dash(wC), dash(wE), dash(wG), dash(6)
	# Row cap. The table prints one row per line of output, and some cases have
	# thousands: the c-10 ex02 case `ccarry` compares 40000 bytes of tail, which rendered
	# 1092 lines and 77 KB into the test log on every failure. Both c-10
	# deliverables are stubs, so a student starting that exercise met a 77 KB wall
	# of "(no line)" before they had written anything at all — and the first failing row
	# already told them everything the other thousand rows repeated.
	#
	# Failing rows are shown FIRST and in full up to the cap, because those are
	# the ones being read; passing rows fill whatever budget is left, since they
	# are context rather than news. Both keep their original order, so the table
	# still reads as the output does. With no truncation the layout is unchanged,
	# which is why every other table in the suite looks exactly as it did before.
	shown = 0
	for (pass = 0; pass <= 1; pass++) {
		for (i = 1; i <= n; i++) {
			if (OKf[i] != pass) continue
			if (maxrows > 0 && shown >= maxrows) continue
			st = OKf[i] ? "PASS" : "FAIL <"
			printf " %s | %s | %s | %s\n", pad(C[i], wC), pad(E[i], wE), pad(G[i], wG), st
			shown++
			seen[i] = 1
		}
	}
	if (shown < n) {
		hidf = 0
		for (i = 1; i <= n; i++) if (!seen[i] && !OKf[i]) hidf++
		printf " ... %d more row(s) not shown (%d of them failing).", n - shown, hidf
		printf "  Raise with DIFF_MAX_ROWS.\n"
	}
	printf " %s-+-%s-+-%s-+-%s\n", dash(wC), dash(wE), dash(wG), dash(6)
	if (fails) printf " RESULT: FAIL  (%d/%d passed, %d failed)\n", n - fails, n, fails
	else       printf " RESULT: PASS  (%d/%d passed)\n", n, n
	if (fails > 0 && cluefile != "") show_hints()
	exit (fails ? 1 : 0)
}
' "$EXPECTED" "$ACTUAL"
DRC=$?

# Byte-exact guard: the per-line table above cannot see a missing/extra FINAL
# newline (both "x\n" and "x" read as the single line "x"), but the Moulinette
# compares stdout byte-for-byte and KOs on it. If the lines matched yet the bytes
# differ, it can only be the final terminator — surface it instead of a false PASS.
if [ "$DRC" -eq 0 ] && ! cmp -s "$EXPECTED" "$ACTUAL"; then
	printf '  --------------------------------------------------\n'
	printf '  BYTE CHECK: FAIL -- output matches line-by-line but differs at the byte\n'
	printf '              level (a missing or extra final newline). Moulinette compares bytes.\n'
	DRC=1
fi

# A program KILLED BY A SIGNAL is never correct, however good its output looks.
# The shell reports 128+signal, so anything above 128 died rather than returned.
# Without this a function could print byte-perfect output and then segfault on
# the way out — stack smashing, a double free, a bad write past a buffer — and
# this layer said PASS. The Moulinette does not, and neither should we. Checked
# BEFORE the table's verdict, because a crash outranks a byte comparison.
if [ "$RC" -gt 128 ]; then
	SIG=$((RC - 128))
	case "$SIG" in
		4)  NAME="SIGILL (illegal instruction)" ;;
		6)  NAME="SIGABRT (abort: assertion, stack smashing, or a glibc heap error)" ;;
		8)  NAME="SIGFPE (arithmetic error, e.g. division or modulo by zero, or INT_MIN / -1)" ;;
		11) NAME="SIGSEGV (invalid memory access)" ;;
		13) NAME="SIGPIPE (wrote to a closed pipe)" ;;
		*)  NAME="signal $SIG" ;;
	esac
	echo " --------------------------------------------------"
	echo " CRASH: the program died on $NAME."
	echo "        Output up to that point may still match, which is why the table"
	echo "        above can look fine. It is not: a crash is a failure regardless."
	if [ -s "$OTHER" ]; then
		echo " ----- the program's other stream said -----"
		sed 's/^/   /' "$OTHER" | head -20
	fi
	DRC=1
fi

# Show the discarded stream when something failed — it is usually the
# explanation (sanitizer report, libc diagnostic, the program's own message).
if [ "$DRC" -ne 0 ] && [ "$RC" -le 128 ] && [ -s "$OTHER" ]; then
	echo " ----- also written to $([ "$STREAM" = "stderr" ] && echo stdout || echo stderr) -----"
	sed 's/^/   /' "$OTHER" | head -10
fi

if [ -n "$EXPECT_EXIT" ] && [ "$RC" != "$EXPECT_EXIT" ]; then
	echo "diff_output.sh: exit code $RC, expected $EXPECT_EXIT" >&2
	exit 1
fi
exit $DRC
