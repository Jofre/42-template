#!/bin/sh
# selftest_costs.sh -- does selftest_costs.tsv still say what selftest.sh's
# sections cost? Read off a run's shard logs, and the table rebuilt from them.
#
# WHY. selftest.sh deals its sections to shards by the seconds this table
# gives them, and its two refusals (a section over three quarters of a
# shard's mean, a shard over 15% above it) read the same rows (selftest.sh,
# "SHARD WEIGHTS"). So a listed section that grows keeps its old row, the deal
# goes on calling the shards even, and no refusal can see it: on 2026-10-17
# the deal printed every shard at 398.5s while the logs of the same tree had
# them at 1.17-1.19x their mean on arms alone, :selftest_bash 797s of its 900
# (TO VERIFY V285). Each shard's log prints every section's seconds
# ("[section NAME: Ns, its arms]"); this reads them back.
#
# THE TABLE'S SCALE. A loaded run takes longer for every section, so a
# section's seconds are compared on the table's scale: divided by how much
# slower than the table the run's typical section ran -- the median, over its
# sections with a row of a second or more, of measured seconds over row. A
# median, not a total, so the one section that grew does not make every other
# one look shrunk. A run is one target's shards: the logs of one folder, as
# Bazel writes them (bazel-testlogs/tools/tests/selftest/shard_N_of_8/
# test.log); a name that heads several sections sums them, as the deal does.
#
# Usage:
#   selftest_costs.sh [--check | --rebuild | --write] [--table FILE]
#                     [--ratio R] [--floor S] [LOG...]
#
#   --check    (the default) say what has drifted: a section whose seconds on
#              the table's scale are over R times its row or under 1/R of it
#              (R is 2), when either is S seconds or more (S is 5); a section
#              the table does not list; and the deal's two refusals, applied
#              to each run's measured seconds -- a shard over 15% above its
#              run's mean, a section over three quarters of it.
#   --rebuild  print the table again, each measured section's row its mean
#              seconds on the table's scale: the header, the order, the
#              blocks the template build strips kept; a row with no
#              measurement kept, and a section with no row added at the end,
#              each said on stderr.
#   --write    --rebuild, into the table itself.
#   --table    the table (selftest_costs.tsv beside this script by default)
#   LOG        a shard's test.log. Under `bazel run` with none named, the
#              last run's: bazel-testlogs/tools/tests/selftest{,_bash}/.
#
#   bazel test //tools/tests:selftest //tools/tests:selftest_bash --nocache_test_results
#   bazel run //tools/tests:selftest_costs              (what drifted)
#   bazel run //tools/tests:selftest_costs -- --write   (measure the table again)
#
# Exit 0: nothing drifted (--check), or the table was printed or written. 1:
# something drifted, each named. 2: nothing was read (no log, a log with no
# section line, a table that is not section<TAB>seconds).
set -u

require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "selftest_costs.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk cat dirname mktemp mv rm

need() { [ "$2" -ge 2 ] || { echo "selftest_costs.sh: $1 needs a value" >&2; exit 2; }; }

MODE="check"
TABLE=""
RATIO=2
FLOOR=5
while [ $# -gt 0 ]; do
	case "$1" in
		--check) MODE="check"; shift ;;
		--rebuild) MODE="rebuild"; shift ;;
		--write) MODE="write"; shift ;;
		--table) need "$1" "$#"; TABLE=$2; shift 2 ;;
		--ratio) need "$1" "$#"; RATIO=$2; shift 2 ;;
		--floor) need "$1" "$#"; FLOOR=$2; shift 2 ;;
		--) shift; break ;;
		-*) echo "selftest_costs.sh: unknown option: $1" >&2; exit 2 ;;
		*) break ;;
	esac
done
case $RATIO in
	*[!0-9.]* | "" | .) echo "selftest_costs.sh: --ratio takes a number above 1" >&2; exit 2 ;;
esac
case $FLOOR in
	*[!0-9.]* | "" | .) echo "selftest_costs.sh: --floor takes a number of seconds" >&2; exit 2 ;;
esac
awk -v r="$RATIO" 'BEGIN { exit !(r + 0 > 1) }' ||
	{ echo "selftest_costs.sh: --ratio takes a number above 1" >&2; exit 2; }

# Where the table and the logs are: named, or the workspace's under `bazel
# run`, or the table beside this script.
WS=${BUILD_WORKSPACE_DIRECTORY:-}
if [ -z "$TABLE" ]; then
	if [ -n "$WS" ]; then
		TABLE=$WS/tools/tests/selftest_costs.tsv
	else
		case $0 in */*) TABLE=${0%/*}/selftest_costs.tsv ;; *) TABLE=selftest_costs.tsv ;; esac
	fi
fi
[ -f "$TABLE" ] || { echo "selftest_costs.sh: no table at $TABLE" >&2; exit 2; }
if [ $# -eq 0 ] && [ -n "$WS" ]; then
	for _l in "$WS"/bazel-testlogs/tools/tests/selftest/shard_*/test.log \
		"$WS"/bazel-testlogs/tools/tests/selftest_bash/shard_*/test.log; do
		[ -f "$_l" ] && set -- "$@" "$_l"
	done
	[ $# -gt 0 ] || {
		echo "selftest_costs.sh: no shard logs under $WS/bazel-testlogs/tools/tests/:" >&2
		echo "  run bazel test //tools/tests:selftest //tools/tests:selftest_bash first" >&2
		exit 2
	}
fi
[ $# -gt 0 ] || { echo "selftest_costs.sh: name the shard logs to read (LOG...)" >&2; exit 2; }
for _l in "$@"; do
	[ -f "$_l" ] || { echo "selftest_costs.sh: no log at $_l" >&2; exit 2; }
done

OUT=$(mktemp) || { echo "selftest_costs.sh: mktemp failed" >&2; exit 2; }
trap 'rm -f "$OUT"' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

# A run is a log's folder, or the folder above it when that one is Bazel's
# shard_N_of_M: each log goes in as RUN<TAB>PATH on the first lines of stdin.
for _l in "$@"; do
	_d=$(dirname "$_l")
	case ${_d##*/} in shard_*_of_*) _d=$(dirname "$_d") ;; esac
	printf '%s\t%s\n' "$_d" "$_l"
done | awk -F'\t' -v table="$TABLE" -v mode="$MODE" -v r="$RATIO" -v floor="$FLOOR" '
	function bad(msg) { printf "selftest_costs.sh: %s\n", msg > "/dev/stderr"; failed = 2; exit 2 }
	function median(a, n,   i, j, t) {
		for (i = 2; i <= n; i++)
			for (j = i; j > 1 && a[j - 1] > a[j]; j--) { t = a[j]; a[j] = a[j - 1]; a[j - 1] = t }
		return n % 2 ? a[(n + 1) / 2] : (a[n / 2] + a[n / 2 + 1]) / 2
	}
	BEGIN {
		while ((got = (getline row < table)) > 0) {
			tl[++nt] = row
			if (row ~ /^#/ || row ~ /^[ \t]*$/) continue
			if (split(row, f, "\t") != 2 || f[2] !~ /^[0-9]+(\.[0-9]+)?$/)
				bad(table ":" nt " is not a row of section<TAB>seconds")
			cost[f[1]] = f[2] + 0
			rowat[f[1]] = nt
		}
		if (got < 0) bad("cannot read " table)
	}
	{
		g = $1; lg = $2
		if (!(g in gn)) runs[++nr] = g
		gn[g]++
		lines = 0
		while ((got = (getline l < lg)) > 0) {
			if (l !~ /^  \[section .*: [0-9]+\.[0-9][0-9]s, its arms\]$/) continue
			sub(/^  \[section /, "", l)
			sub(/s, its arms\]$/, "", l)
			match(l, /: [0-9]+\.[0-9][0-9]$/)
			nm = substr(l, 1, RSTART - 1)
			if (nm !~ /^[ -~]+$/) bad(lg ": a section line whose name is not printable ASCII")
			s = substr(l, RSTART + 2) + 0
			if (!((g, nm) in m)) { ns[g]++; sec[g, ns[g]] = nm }
			m[g, nm] += s
			tot[lg] += s
			shards[g, gn[g]] = lg
			lines++
		}
		close(lg)
		if (got < 0) bad("cannot read " lg)
		if (!lines) bad(lg " has no \"[section NAME: Ns, its arms]\" line: is it a shard log of //tools/tests:selftest?")
	}
	END {
		if (failed) exit 2
		# Each run, on the table s scale, by its median section.
		for (i = 1; i <= nr; i++) {
			g = runs[i]; k = 0
			for (j = 1; j <= ns[g]; j++) {
				nm = sec[g, j]
				if ((nm in cost) && cost[nm] >= 1) q[++k] = m[g, nm] / cost[nm]
			}
			slow[g] = k ? median(q, k) : 1
			if (slow[g] <= 0) slow[g] = 1
			for (j = 1; j <= ns[g]; j++) {
				nm = sec[g, j]
				if (!(nm in seen)) { seen[nm] = 1; order[++no] = nm }
				sum[nm] += m[g, nm] / slow[g]
				cnt[nm]++
			}
		}
		for (i = 1; i <= no; i++) { nm = order[i]; at[nm] = sum[nm] / cnt[nm] }
		if (mode != "check") {
			for (i = 1; i <= nt; i++) {
				row = tl[i]
				if (row ~ /^#/ || row ~ /^[ \t]*$/) { print row; continue }
				split(row, f, "\t")
				if (f[1] in at) printf "%s\t%.1f\n", f[1], (at[f[1]] < 0.1 ? 0.1 : at[f[1]])
				else {
					print row
					printf "selftest_costs.sh: \"%s\" is in no log read, so its row is kept\n", f[1] > "/dev/stderr"
				}
			}
			for (i = 1; i <= no; i++) {
				nm = order[i]
				if (nm in cost) continue
				printf "%s\t%.1f\n", nm, (at[nm] < 0.1 ? 0.1 : at[nm])
				printf "selftest_costs.sh: \"%s\" had no row, and is added at the end: move it into its block if selftest.sh has its section in one the template build strips\n", nm > "/dev/stderr"
			}
			exit 0
		}
		said = 0
		for (i = 1; i <= no; i++) {
			nm = order[i]
			if (!(nm in cost)) {
				out[++said] = sprintf("  \"%s\": no row; it took %.1fs on the table\047s scale", nm, at[nm])
				continue
			}
			c = cost[nm]
			if (c < floor && at[nm] < floor) continue
			if (c > 0 && at[nm] <= c * r && at[nm] * r >= c) continue
			out[++said] = sprintf("  \"%s\": its row says %.1fs; it took %.1fs on the table\047s scale (%.2fx)", nm, c, at[nm], (c > 0 ? at[nm] / c : 0))
		}
		# The deal s two refusals, on what each run measured.
		for (i = 1; i <= nr; i++) {
			g = runs[i]
			if (gn[g] < 2) continue
			all = 0; most = ""
			for (j = 1; j <= gn[g]; j++) {
				lg = shards[g, j]
				all += tot[lg]
				if (most == "" || tot[lg] > tot[most]) most = lg
			}
			mean = all / gn[g]
			if (tot[most] > mean * 1.15)
				out[++said] = sprintf("  %s: the shards are uneven: %s took %.1fs of arms, %.0f%% above their mean %.1fs (the deal refuses 15%%)", g, substr(most, length(g) + 2), tot[most], (tot[most] / mean - 1) * 100, mean)
			for (j = 1; j <= ns[g]; j++) {
				nm = sec[g, j]
				if (m[g, nm] > mean * 3 / 4)
					out[++said] = sprintf("  %s: \"%s\" took %.1fs, over three quarters of its shards\047 mean %.1fs", g, nm, m[g, nm], mean)
			}
		}
		miss = 0
		for (nm in cost) if (!(nm in at)) miss++
		if (miss)
			printf "selftest_costs.sh: %d row(s) are in no log read (a shard log missing, or only some named)\n", miss > "/dev/stderr"
		if (!said) {
			printf "selftest_costs.sh: the table still says what its sections cost (%d section(s) in %d run(s), within %sx of their rows)\n", no, nr, r
			exit 0
		}
		printf "selftest_costs.sh: the table no longer says what these sections cost (%d section(s) in %d run(s)):\n", no, nr
		for (i = 1; i <= said; i++) print out[i]
		printf "  The deal reads only the table, so it cannot see this. Measure it again:\n"
		printf "  bazel run //tools/tests:selftest_costs -- --write, after a run of both\n"
		printf "  selftest targets on a quiet machine, and look at the diff.\n"
		exit 1
	}' > "$OUT"
rc=$?
case $rc in
	0 | 1) ;;
	*) exit 2 ;;
esac
if [ "$MODE" = write ]; then
	_new=$(mktemp "$TABLE.XXXXXX") || { echo "selftest_costs.sh: cannot write beside $TABLE" >&2; exit 2; }
	cat "$OUT" > "$_new" && mv "$_new" "$TABLE" || { rm -f "$_new"; exit 2; }
	echo "selftest_costs.sh: wrote $TABLE"
	exit 0
fi
cat "$OUT"
exit "$rc"
