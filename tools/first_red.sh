#!/bin/sh
# first_red.sh — turn a wall of red into one next objective.
#
# Usage:
#   bazel test //... 2>&1 | sh tools/first_red.sh           # what to do next
#   bazel test //... 2>&1 | sh tools/first_red.sh --all     # ... and everything
#
# Two zoom levels, because "what do I do next" and "how much is left" are
# different questions and the second one is what makes a wall of red feel
# hopeless. The default answers the first and ends with a module-sized picture
# of the second. --all expands that to one line per exercise -- still one line,
# never the two-or-three Bazel prints, because at a hundred failures the log
# paths are noise and the exercise is the unit you actually think in.
#
# THE PROBLEM. A whole-repo run reports every unwritten exercise at once — on a
# fresh clone that is over two hundred red targets, and on a half-finished one
# it is still a hundred. All of it is true and none of it is an instruction.
# "What do I do next?" is not answerable by reading it.
#
# WHY NOT JUST RUN THE TESTS IN ORDER. Because Bazel will not. It schedules
# tests in parallel and promises no order, and it does not deliver one even when
# told to serialise: measured on c-10, three runs of
#
#     bazel test //c-piscine-c-10/... --local_test_jobs=1 --notest_keep_going
#
# stopped on ex00_build, then ex02_ccarry_output, then ex01_two_output. Same
# command, same tree, three answers. So the run stays parallel and fast, and the
# ORDER is applied to the report, where it is deterministic and free.
#
# (Two things worth knowing before reaching for -k: a failing TEST never stops a
# run, because --test_keep_going defaults to true. -k governs BUILD errors,
# which this repo deliberately has none of — a build action that cannot do its
# job still produces its output and exits 1 rather than take its module down.
# So `bazel test //...` and `bazel test //... -k` should always agree here, and
# if they ever disagree that difference is itself the bug report.)
#
# THE ORDER, and why it is not just alphabetical. The reds are not all the same
# kind, and the harness already knows the difference:
#
#   A FRESH STUB passes norm, compile, files, forbidden and prototype, and fails
#   output. That is the whole design of the level ladder.
#
# So a red in one of those five USUALLY means you wrote something that breaks a
# rule the Moulinette scores zero for. Usually, not always — and the exception
# is why this script asks rather than assumes.
#
# c-08's deliverable IS a header. A stubbed header defines nothing, so the
# subject's own main() cannot compile against it, and `compile` is red on an
# exercise nobody has started. An earlier version of this script called that
# "something you wrote breaks a rule" on a fresh clone, which is precisely the
# beginner-sends-hunting-a-bug-that-is-not-there failure this repo rates second
# worst.
#
# So for any exercise in that bucket it asks tools/stub_check.sh whether the
# deliverable is still a stub — the tool whose entire job is that question. A
# stub cannot have broken a rule; it demotes to ordinary work.
#
# Three buckets, one objective, and the rest counted rather than listed.
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "first_red.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk dirname mktemp rm sed sort

MODE=summary
while [ $# -gt 0 ]; do
	case "$1" in
		--all) MODE=all; shift ;;
		*) echo "first_red.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

# stub_check.sh is found NEXT TO THIS SCRIPT, not relative to the working
# directory. A runner that only works when you happen to be standing in the
# repo root is a runner that fails the first time it is called from anywhere
# else -- and this one is meant to be piped into from wherever you ran bazel.
STUB_CHECK="$(dirname "$0")/stub_check.sh"

# GREEN ON A STUB. Keep in step with the same claim in docs/reference.md and
# with _LAYER_LEVEL in tools/defs.bzl; //tools:conventions fails if the layer
# names here stop being layers.
STUB_GREEN='norm compile_clang compile_gcc files forbidden prototype'

FAILED=$(sed -n 's|^\(//[A-Za-z0-9_/.-]*:[A-Za-z0-9_.-]*\) *FAILED.*|\1|p' | sort -u)

if [ -z "$FAILED" ]; then
	echo "first_red: nothing failed."
	exit 0
fi

WORK=$(mktemp) || exit 2
trap 'rm -f "$WORK" "$WORK.2"' EXIT INT TERM

# Pass 1: classify every failing target and aggregate per exercise.
printf '%s\n' "$FAILED" | awk -F'\t' -v stub_green="$STUB_GREEN" '
	BEGIN {
		n = split(stub_green, g, " ")
		for (i = 1; i <= n; i++) ko[g[i]] = 1
	}
	{
		split($0, p, ":")
		mod = p[1]; tgt = p[2]
		ex = tgt; sub(/_.*/, "", ex)
		if (ex !~ /^ex[0-9]+$/) ex = "-"
		layer = tgt; sub(/^ex[0-9]+_/, "", layer)

		# c_program cases and rush variants put a case name between the
		# exercise and the layer (ex00_blob_output, ex00_rush03_diff), so the
		# layer is the TAIL. Walk suffixes until one is a layer we know.
		probe = layer; kind = ""
		while (probe != "") {
			if (probe in ko)         { kind = "ko";   break }
			if (probe == "output")   { kind = "work"; break }
			if (probe == "build")    { kind = "work"; break }
			if (probe == "progname") { kind = "work"; break }
			if (!sub(/^[^_]*_/, "", probe)) break
		}
		if (kind == "") { kind = "rigour"; probe = layer }

		key = mod "\t" ex
		if (!(key in seen)) { seen[key] = 1; order[++nk] = key }
		if (kind == "ko" && !(key SUBSEP probe in kseen)) {
			kseen[key, probe] = 1
			kowhat[key] = kowhat[key] (kowhat[key] ? ", " : "") probe
		}
		if (kind == "rigour" && !(key SUBSEP probe in rseen)) {
			rseen[key, probe] = 1
			rigwhat[key] = rigwhat[key] (rigwhat[key] ? ", " : "") probe
		}
		if (kind == "work") work[key] = 1
		if (!(key SUBSEP probe in lseen)) { lseen[key, probe] = 1; lorder[key] = lorder[key] " " probe }
		lcount[key, probe]++
		ntgt[key]++
		total++
	}
	END {
		for (i = 1; i <= nk; i++) {
			k = order[i]
			kind = kowhat[k] ? "ko" : (work[k] ? "work" : "rigour")
			# A dash, never empty: tab is IFS-whitespace, so `read` collapses
			# consecutive tabs and an empty column silently shifts every field
			# after it. Cost an hour once; costs one character to prevent.
			what = kowhat[k] ? kowhat[k] : (rigwhat[k] ? rigwhat[k] : "-")
			# The layer multiset, compressed: five red output cases read as
			# "output x5", not as five lines. The count is what tells you
			# whether an exercise is one bad case or entirely unwritten.
			layers = ""
			m = split(lorder[k], ls, " ")
			for (j = 1; j <= m; j++) {
				if (ls[j] == "") continue
				c = lcount[k, ls[j]]
				layers = layers (layers ? " " : "") ls[j] (c > 1 ? " x" c : "")
			}
			printf "%s\t%s\t%s\t%d\t%s\n", kind, k, what, ntgt[k], layers
		}
		printf "TOTAL\t%d\t%d\t-\t0\t-\n", total, nk
	}' > "$WORK"

# Pass 2: nothing is called the student's fault until stub_check says the
# deliverable is written. A stub cannot have broken a rule -- c-08's header
# exercises fail `compile` while untouched, because a header that defines
# nothing cannot compile the subject's own main. Demote those to ordinary work.
#
# If the deliverable directory is not there to inspect (the shell modules
# generate theirs), demote as well. Erring toward "not written yet" costs a
# student nothing; erring the other way sends them hunting a bug they did not
# write, which is the failure this whole script exists to avoid.
: > "$WORK.2"
while IFS="$(printf '\t')" read -r kind mod ex what count layers; do
	if [ "$kind" = "ko" ]; then
		dir="$(printf '%s' "$mod" | sed 's|^//||')/deliverable/$ex"
		written=0
		if [ -d "$dir" ]; then
			for f in "$dir"/*; do
				[ -f "$f" ] || continue
				sh "$STUB_CHECK" --file "$f" > /dev/null 2>&1 || written=1
			done
		fi
		[ "$written" -eq 1 ] || kind="work"
	fi
	printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$kind" "$mod" "$ex" "$what" "$count" "$layers" >> "$WORK.2"
done < "$WORK"

# Pass 3: render. One objective, then a module-sized picture of what is left --
# and with --all, one line per exercise. Never one line per TARGET: at a hundred
# failures the log paths are noise, and "ex00 output x5 build" says more in a
# line than six targets do in twelve.
awk -F'\t' -v mode="$MODE" '
	$1 == "TOTAL" { total = $2; nex = $3; next }
	{
		kind[++r] = $1; mod[r] = $2; ex[r] = $3; what[r] = $4
		cnt[r] = $5; lay[r] = $6
		if (!(mod[r] in mseen)) { mseen[mod[r]] = 1; morder[++nm] = mod[r] }
		mred[mod[r]] += $5
		mex[mod[r]]++
		if ($1 == "ko")     mko[mod[r]] = 1
		if ($1 == "work")   mwork[mod[r]] = 1
		if ($1 == "rigour") mrig[mod[r]] = 1
		if (mfirst[mod[r]] == "") mfirst[mod[r]] = $3
		mlast[mod[r]] = $3
		if ($1 == "ko")     { koM[++nko] = $2; koE[nko] = $3; koW[nko] = $4 }
		if ($1 == "work")   { wM[++nw] = $2; wE[nw] = $3 }
		if ($1 == "rigour") { rM[++nr] = $2; rE[nr] = $3; rW[nr] = $4 }
	}
	END {
		printf "\nfirst_red: %d red target(s), %d exercise(s), %d module(s).\n", total, nex, nm

		if (nko) {
			printf "\n  FIX FIRST — these are written, and they break a rule the Moulinette\n"
			printf "  scores zero for. A stub does not fail them.\n\n"
			for (i = 1; i <= nko; i++) {
				printf "      %s %s — %s\n", koM[i], koE[i], koW[i]
				printf "      bazel test %s:%s\n\n", koM[i], koE[i]
			}
		}

		if (nw) {
			printf "\n  YOUR NEXT EXERCISE\n\n"
			printf "      %s %s\n", wM[1], wE[1]
			printf "      bazel test %s:%s\n\n", wM[1], wE[1]
			printf "      Its output layer is red, which is what an unwritten exercise looks\n"
			printf "      like. Write it until that goes green, then run the module again.\n"
		}

		if (nr) {
			printf "\n\n  ALSO RED — these produce the right output; a rigour layer above the\n"
			printf "  Moulinette disagrees. Worth reading, not urgent.\n\n"
			for (i = 1; i <= nr; i++)
				printf "      %s %s — %s\n", rM[i], rE[i], rW[i]
		}

		# The scale, one line per module. This is the part that stops a wall of
		# red reading as hopeless: seven lines say what three hundred did.
		printf "\n\n  EVERYTHING STILL RED\n\n"
		printf "      %-22s %5s  %-14s %s\n", "MODULE", "RED", "EXERCISES", "STATE"
		for (i = 1; i <= nm; i++) {
			m = morder[i]
			span = (mfirst[m] == mlast[m]) ? mfirst[m] : mfirst[m] "-" mlast[m]
			state = mko[m] ? "written; breaking a rule" \
			      : (mwork[m] ? "not written yet" : "written; rigour only")
			short = m; sub(/^\/\/c-piscine-/, "", short)
			printf "      %-22s %5d  %-14s %s\n", short, mred[m], span, state
		}

		if (mode == "all") {
			printf "\n\n  EVERY EXERCISE, one line each\n"
			lastm = ""
			for (i = 1; i <= r; i++) {
				if (mod[i] != lastm) {
					short = mod[i]; sub(/^\/\/c-piscine-/, "", short)
					printf "\n      %s\n", short
					lastm = mod[i]
				}
				printf "        %-6s %2d  %s\n", ex[i], cnt[i], lay[i]
			}
		} else {
			printf "\n      Add --all for one line per exercise.\n"
		}
		printf "\n"
	}' "$WORK.2"
