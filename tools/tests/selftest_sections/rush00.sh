# ------------------------------------------------------------------ rush00
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# Rush 00's two harnesses that JUDGE rather than print a value: survive_rush.c,
# which owes every legal size its rectangle's shape once rush(3, 3) draws
# anything, and test_defense.c, which compares rush(123, 42) with the
# reference's picture and prints one verdict row (finding 141). Neither has a
# runner of its own -- diff_output.sh only compares the rows they print -- and
# every tree the suite runs them on passes them: the stubs, the owner's
# answers, the student answers. So nothing showed that either could go red: a
# `draws` stuck at 0, or a right_shape() that always said yes, would let every
# legal size "survive" with the whole suite green.
#
# These arms build both harnesses from the files the module ships, as its
# targets do, against three bodies of rush() that no variant draws:
#
#   empty   the stub, printing nothing. survive.txt verbatim: the shape check
#           waits for a drawing. The defense row says "nothing at all".
#   xnl     "x" and a newline for every size: WRONG SHAPE on every legal size,
#           and the defense row names row 1, column 1.
#   narrow  the shape alone -- y lines of x '#' and a newline, a character no
#           variant draws -- up to 200 columns, and nothing wider: WRONG SHAPE
#           on the legal sizes wider than 200 and on no other.
#
# The sizes are the module's own (tests/ex00/edge_cases.tsv), so a ceiling
# added there is asked here too. The defense harness takes its picture on
# stdin, so its arms hand it invented pictures of '#', never the reference's.
# Each harness is built on first use, by the arm that needs it: a section's
# plain code runs in every shard (SHARDS, above).
R0="$ROOT/c-piscine/c-piscine-rush-00/tests/ex00"
mkdir -p "$WORK/r0"
cat > "$WORK/r0/empty.c" <<'R0_EMPTY'
void	rush(int x, int y)
{
	(void)x;
	(void)y;
}
R0_EMPTY
cat > "$WORK/r0/xnl.c" <<'R0_XNL'
#include <unistd.h>

void	rush(int x, int y)
{
	(void)x;
	(void)y;
	write(1, "x\n", 2);
}
R0_XNL
cat > "$WORK/r0/narrow.c" <<'R0_NARROW'
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

void	rush(int x, int y)
{
	char	*b;
	size_t	w;
	size_t	r;

	if (x <= 0 || y <= 0 || x > 200)
		return ;
	w = (size_t)x + 1;
	b = malloc(w * (size_t)y);
	if (!b)
		return ;
	for (r = 0; r < (size_t)y; r++)
	{
		memset(b + r * w, '#', (size_t)x);
		b[r * w + w - 1] = '\n';
	}
	write(1, b, w * (size_t)y);
	free(b);
}
R0_NARROW
# Pictures for the defense harness: rectangles of '#' (one with an 'x' at row
# 2, column 3), and one that is none (rows of two widths).
awk 'BEGIN { for (i = 0; i < 4; i++) print "######" }' > "$WORK/r0/pic6x4"
awk 'BEGIN { s = ""; for (i = 0; i < 300; i++) s = s "#"; print s; print s }' > "$WORK/r0/pic300x2"
printf '######\n##x###\n######\n######\n' > "$WORK/r0/pic6x4x"
printf '###\n##\n' > "$WORK/r0/ragged"

r0_build() {  # r0_build HARNESS BODY -- build tests/ex00/HARNESS.c over BODY once
	[ -x "$WORK/r0/$1.$2" ] && return 0
	toy_cc "$WORK/r0/$1.$2" -I "$R0" -I "$TOOLS" "$R0/$1.c" "$WORK/r0/$2.c" || return 2
}
r0_survive_run() {  # r0_survive_run BODY -- the survival harness's rows, as its target reads them
	r0_build survive_rush "$1" || return 2
	"$WORK/r0/survive_rush.$1" < "$R0/edge_cases.tsv" || return 2
}
r0_survive_is_expected() {  # r0_survive_is_expected BODY -- 0 when its rows are survive.txt's
	r0_survive_run "$1" > "$WORK/r0/survive.$1.out" || return 2
	cmp -s "$R0/survive.txt" "$WORK/r0/survive.$1.out"
}
# r0_shape BODY WIDTH -- 0 when the legal sizes wider than WIDTH are WRONG
# SHAPE, every other size survived, and the 3x3 is unchanged; 1 when not; 2
# when no legal size is that wide, which would ask nothing.
r0_shape() {
	r0_survive_run "$1" > "$WORK/r0/shape.$1.out" || return 2
	awk -F'\t' -v w="$2" '
		NR == FNR {
			if ($0 ~ /^#/ || NF < 3) next
			n++
			lab[n] = $1
			bad[n] = ($2 + 0 > 0 && $3 + 0 > 0 && $2 + 0 > w + 0)
			shaped += bad[n]
			next
		}
		{ got[++m] = $0 }
		END {
			if (!shaped) exit 2
			if (m != n + 1) exit 1
			for (i = 1; i <= n; i++) {
				if (bad[i] && index(got[i], lab[i] "\tWRONG SHAPE: ") != 1) exit 1
				if (!bad[i] && got[i] != lab[i] "\tsurvived") exit 1
			}
			if (got[m] != "3x3 unchanged by the degenerate calls\tYES") exit 1
		}' "$R0/edge_cases.tsv" "$WORK/r0/shape.$1.out"
}
r0_defense() {  # r0_defense BODY PICTURE -- the defense harness's row for PICTURE
	r0_build test_defense "$1" || return 2
	"$WORK/r0/test_defense.$1" < "$WORK/r0/$2" || return 2
}

want_green "rush00 survive: printing nothing gets survive.txt" -- \
	r0_survive_is_expected empty
want_green "rush00 survive: 'x' is WRONG SHAPE at every legal size" -- \
	r0_shape xnl 0
want_red   "rush00 survive: ...so it does not get survive.txt" -- \
	r0_survive_is_expected xnl
want_out   "rush00 survive: ...and its row gives the figures" \
	"WRONG SHAPE: 2 bytes in 1 line, where 128 lines of 1 character and a newline make 256" -- \
	r0_survive_run xnl
want_green "rush00 survive: nothing past 200 wide: WRONG SHAPE there only" -- \
	r0_shape narrow 200
want_red   "rush00 survive: ...so it does not get survive.txt either" -- \
	r0_survive_is_expected narrow
want_out   "rush00 defense: printing nothing is 'nothing at all'" \
	"nothing at all, where 4 rows of 6 make 28 bytes" -- r0_defense empty pic6x4
want_out   "rush00 defense: 'x' is told where it first differs" \
	"2 bytes in 1 line, where 4 rows of 6 make 28; first difference at row 1, column 1" -- \
	r0_defense xnl pic6x4
want_out   "rush00 defense: the picture itself is the reference's" \
	"the reference's picture, all 28 bytes" -- r0_defense narrow pic6x4
want_out   "rush00 defense: ...and one byte off is found where it is" \
	"first difference at row 2, column 3: yours" -- r0_defense narrow pic6x4x
want_out   "rush00 defense: ...and nothing past 200 columns is nothing" \
	"nothing at all, where 2 rows of 300 make 602 bytes" -- r0_defense narrow pic300x2
want_out   "rush00 defense: no rectangle on stdin is the harness's" \
	"BROKEN FIXTURE" -- r0_defense empty ragged

