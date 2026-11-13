#!/bin/sh
# Tests for the TEST HARNESS (tag "selftest").
#
# Every false green found in this harness had the same shape: a layer reported OK
# having checked nothing. rust_diff.sh said "OK (0 cases)" on an empty corpus;
# asan_check.sh exited 0 when clang-12 was missing; forbidden_symbols.sh passed
# with an empty symbol list when nm failed; diff_output.sh passed a program that
# printed the right bytes and then segfaulted. Each was found by reading the
# script and asking "can this exit 0 while broken?" — which is exactly the
# question a test can ask automatically, and none existed.
#
# So: known-bad inputs, each of which MUST make its layer red, and known-good
# inputs which must stay green. A runner that stops detecting its bug will fail
# here instead of silently passing every exercise in the repo.
#
# Usage: selftest.sh --anchor PATH-TO-ANY-TOOLS-SCRIPT --norminette PATH
#            --nm PATH --nm-lib PATH --shellcheck PATH --clang PATH
#            [--clang-lib PATH]... --gcc PATH --symbolizer PATH
#            --symbolizer-lib PATH --ld PATH --ld-lib PATH --objdump PATH
#            --as PATH --ar PATH --ranlib PATH --python PATH
#            --valgrind PATH --valgrind-callgrind-tools PATH
# Every one but the bracketed is required (exit 2 without it), and
# //tools/tests:selftest's args hand them all over (tools/tests/BUILD.bazel).
# The valgrind pair too: the cycles runners require the pin, and without it
# every cycles arm exits 2 on the wiring, a FAIL that checked nothing.
#
# The anchor is a file rather than a directory because Bazel's $(rootpath) on a
# filegroup member resolves to the FILE; appending /.. to it yields
# "diff_output.sh/..", which is not a directory. dirname is the honest way to
# get there — and getting this wrong made every check in here go red at once,
# which is how it was found.
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "selftest.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk cat chmod cmp cp cut date dirname env find git grep head id ln ls make mkdir mktemp mv od readlink rm rmdir sed sha256sum sleep sort tail tar tr wc

# A test's scratch files go under TEST_TMPDIR, which Bazel empties, and not
# in the machine's /tmp, the TMPDIR Bazel sets when the shell that ran it set
# none (tools/runner_lib.sh, "THE SCRATCH FOLDER").
case ${TMPDIR:-/tmp} in /tmp | /tmp/) [ -z "${TEST_TMPDIR:-}" ] || export TMPDIR="$TEST_TMPDIR" ;; esac

# SHARDS. Bazel runs this file as several processes at once (shard_count in
# tools/tests/BUILD.bazel says why), each with TEST_TOTAL_SHARDS and its own
# TEST_SHARD_INDEX, and each shard runs the ARMS of its own sections only. A
# section is what runs from one `# ---- name` line to the next; every section
# of one name goes to the same shard. Each section is a file of its own, in
# selftest_sections/ beside this one, which opens with its `# ---- name`
# line; this file sources them in order, below its preamble ("THE
# SECTIONS"), and a shard reads them as one text (st_assemble).
#
# SHARD WEIGHTS. Sections are dealt by what they cost, heaviest first, each
# to the shard with the least so far. Dealt in turn instead, one shard held
# the conventions section -- 450 of the file's 750 seconds of arms, a run
# of conventions.sh per arm -- and ran 500s while the others ran 150
# (finding 066). Dealt by counted lines after that (1 an arm, 20 a run of
# conventions.sh), the shards were even in count and not in time: a run of
# conventions.sh takes about 1.4s over a toy tree and 12s or more over the
# cv tree, and on an idle machine the slowest shard took 590s of its 900
# while the fastest took 342 (V138, V208). So the cost is MEASURED:
# selftest_costs.tsv, beside this file, holds each section's seconds of
# arms, read off the "[section ...]" lines every shard's log prints (its
# header says how). A section it does not list is weighed by its count,
# scaled to seconds by what the listed sections cost a counted unit, and
# named on stderr so its row gets measured. The deal is refused (exit 2)
# when a row names a section this file does not have, or sits in a
# block the template build strips while its section does not, or the other
# way round (the template's copy would name a section its file lacks); when
# a section costs more than three quarters of a shard's mean, since one
# section is one shard's however it is dealt -- split it into sections of
# their own names, as conventions is, or let arms that ask about one tree
# read one run of it, as cv5's do; and when the most loaded shard
# carries more than 15% over the mean. A section added, split or made
# slower is measured again: the deal reads only the table, so it cannot see
# a listed section that grew, and selftest_costs.sh, beside this file, reads
# a run's shard logs back against it (TO VERIFY V285).
# `TEST_TOTAL_SHARDS=8 SELFTEST_DEAL=print sh
# tools/tests/selftest.sh` prints the deal and runs no arm; a test run
# refuses it, since every shard would pass having run nothing.
#
# Everything that is not an arm runs in every shard: the fixtures, the
# variables, the helpers a section defines -- the sections were written in
# order, and a later one builds on what an earlier one set up. What a shard
# skips is the want_* arms of the other shards' sections, which is where the
# time goes (each runs a runner, most of them compile or start an
# interpreter). The few checks written out by hand, outside want_*, run too,
# but a section that is not this shard's prints nothing and counts nothing
# (_st_section). So an arm may rely on anything above it except what an ARM
# of another section did: a later section that needs a file an arm made
# would find it missing in every shard that skipped that arm -- make the
# file in plain code instead. The strict helpers make such a slip visible:
# a runner handed a missing file exits 2, which want_red, want_green,
# want_out and want_broken_none all read as a failure.
#
# The shard's copy of this file -- the whole program, its sections' files
# put in place of the lines that source them (st_assemble), with a
# _st_section line after every section line -- is written and run in its
# place (exec); no arm knows about shards. A
# hand run has no shard variables and runs every arm, as does
# `bazel run --test_sharding_strategy=disabled`. A shard that got no section
# fails (exit 2): a count above the number of sections, or a filter that
# stopped recognising the section lines, would otherwise pass having checked
# nothing.
#
# st_assemble FILE -- FILE as one text: each line that sources a section's
# file (`. "$ST_PARTS/NAME.sh"`, under THE SECTIONS) replaced by that file,
# from the selftest_sections folder beside FILE. A file it names that is
# missing or empty is refused (exit 2): its section would be dealt nowhere,
# and its arms run by no shard. A FILE that sources none, the toy of "the
# shard deal", is itself.
st_assemble() {
	awk -v d="$(dirname "$1")/selftest_sections" '
		/^\. "\$ST_PARTS\/[^"\/]+\.sh"$/ {
			f = $0
			sub(/^\. "\$ST_PARTS\//, "", f)
			sub(/"$/, "", f)
			n = 0
			while ((got = (getline l < (d "/" f))) > 0) { print l; n++ }
			close(d "/" f)
			if (got < 0 || n == 0) {
				printf "selftest: no section file %s/%s (THE SECTIONS)\n", d, f > "/dev/stderr"
				bad = 1
				exit 2
			}
			next
		}
		{ print }
		END { if (bad) exit 2 }' "$1"
}
if [ "${TEST_TOTAL_SHARDS:-1}" -gt 1 ] && [ -z "${SELFTEST_SHARD:-}" ]; then
	# SELFTEST_DEAL prints the deal and runs no arm, so a test run handed
	# it (`--test_env=SELFTEST_DEAL=1`) would pass every shard having
	# checked nothing: Bazel's own variables say it is one, and it refuses.
	if [ -n "${SELFTEST_DEAL:-}" ] &&
		{ [ -n "${TEST_SHARD_STATUS_FILE:-}" ] || [ -n "${XML_OUTPUT_FILE:-}" ]; }; then
		echo "selftest: SELFTEST_DEAL prints the deal and runs no arm, so a test run refuses it (SHARD WEIGHTS)" >&2
		exit 2
	fi
	[ -z "${TEST_SHARD_STATUS_FILE:-}" ] || : > "$TEST_SHARD_STATUS_FILE"
	_costs=$(dirname "$0")/selftest_costs.tsv
	if [ ! -f "$_costs" ]; then
		echo "selftest: no table of section costs at $_costs (SHARD WEIGHTS)" >&2
		exit 2
	fi
	_whole=$(mktemp) || { echo "selftest: mktemp failed" >&2; exit 2; }
	st_assemble "$0" > "$_whole" || { rm -f "$_whole"; exit 2; }
	_shard_file=$(mktemp) || { echo "selftest: mktemp failed" >&2; rm -f "$_whole"; exit 2; }
	awk -v n="$TEST_TOTAL_SHARDS" -v k="${TEST_SHARD_INDEX:-0}" \
		-v costs="$_costs" -v show="${SELFTEST_DEAL:-}" '
		# The template build strips a block between these two comment lines;
		# the bracket keeps this file from spelling the word that build
		# refuses to publish.
		function priv_start(l) { return l ~ /^[ \t]*#[ \t]*PRIVATE-[O]NLY BLOCK/ }
		function priv_end(l) { return l ~ /^[ \t]*#[ \t]*END PRIVATE-[O]NLY[ \t]*$/ }
		function refuse(msg) { printf "selftest: %s (SHARD WEIGHTS)\n", msg > "/dev/stderr"; refused = 1 }
		# The table: "section<TAB>seconds" a row, and # lines are notes.
		BEGIN {
			while ((got = (getline row < costs)) > 0) {
				rn++
				if (priv_start(row)) tp = 1
				if (priv_end(row)) tp = 0
				if (row ~ /^#/ || row ~ /^[ \t]*$/) continue
				if (split(row, f, "\t") != 2 || f[2] !~ /^[0-9]+(\.[0-9]+)?$/) {
					refuse(costs ":" rn " is not a row of section<TAB>seconds")
					exit 5
				}
				if (f[1] in cost) {
					refuse(costs ":" rn " lists section \"" f[1] "\" a second time")
					exit 5
				}
				cost[f[1]] = f[2] + 0
				listed[++nl] = f[1]
				at[f[1]] = rn
				tpriv[f[1]] = tp
			}
			if (got < 0) { refuse("cannot read " costs); exit 5 }
		}
		# First pass: each section, and its count -- 1 an arm, 20 a run of
		# conventions.sh, which walks a whole fixture tree -- for a section
		# the table does not list (SHARD WEIGHTS, above).
		NR == FNR {
			if ($0 ~ /^# =+ the tally$/) done = 1
			if (done) next
			if (priv_start($0)) fp = 1
			if (priv_end($0)) fp = 0
			if ($0 ~ /^# -----+ /) {
				cur = $0
				sub(/^# -+ /, "", cur)
				if (!(cur in w)) { order[++ns] = cur; w[cur] = 0; fpriv[cur] = fp }
				next
			}
			if (cur == "") next
			if ($0 ~ /^[ \t]*want_[a-z_]+ /) w[cur] += 1
			# A run: a call of conv, convk or convlb where a command
			# starts (or a $CONV, the string they replaced, in a file not
			# yet moved).
			if ($0 ~ /\$CONV|(^|[;&|(!{]|--|(^|[^A-Za-z0-9_])(then|do|else))[[:blank:]]*conv(k|lb)?([[:blank:]>;&|)]|$)/) w[cur] += 20
			next
		}
		FNR == 1 {
			for (i = 1; i <= nl; i++) {
				nm = listed[i]
				if (!(nm in w))
					refuse(costs ":" at[nm] " names section \"" nm "\", which this file does not have")
				else if (fpriv[nm] && !tpriv[nm])
					refuse(costs ":" at[nm] ": section \"" nm "\" sits in a block the template build strips, and its row does not")
				else if (!fpriv[nm] && tpriv[nm])
					refuse(costs ":" at[nm] ": section \"" nm "\" sits in no block the template build strips, and its row does")
			}
			if (refused) exit 5
			# Seconds for each section: its row, or its count at what a
			# counted unit of the listed sections costs.
			for (i = 1; i <= ns; i++)
				if (order[i] in cost) { secs += cost[order[i]]; units += w[order[i]] }
			per = units > 0 ? secs / units : 0.2
			for (i = 1; i <= ns; i++) {
				nm = order[i]
				if (nm in cost) c[nm] = cost[nm]
				else {
					c[nm] = w[nm] * per
					unlisted = unlisted (nmiss++ ? ", " : "") "\"" nm "\""
				}
			}
			if (nmiss)
				printf "selftest: %d section(s) not in %s, weighed by their count: %s (SHARD WEIGHTS)\n", nmiss, costs, unlisted > "/dev/stderr"
			# Heaviest first, each to the lightest shard so far; ties go
			# in the order the sections appear, so every shard deals alike.
			# The hundredth of a second each spreads sections that cost
			# nothing.
			for (i = 1; i <= ns; i++) left[i] = 1
			for (j = 1; j <= ns; j++) {
				b = 0
				for (i = 1; i <= ns; i++)
					if (left[i] && (b == 0 || c[order[i]] > c[order[b]])) b = i
				left[b] = 0
				m = 0
				for (t = 1; t < n; t++) if (load[t] < load[m]) m = t
				shard[order[b]] = m
				load[m] += c[order[b]] + 0.01
				dealt[m] = dealt[m] (dealt[m] == "" ? "" : " | ") order[b]
			}
			for (t = 0; t < n; t++) { all += load[t]; if (load[t] > load[most]) most = t }
			mean = all / n
			if (show)
				for (t = 0; t < n; t++)
					printf "shard %d of %d: %.1fs  %s\n", t + 1, n, load[t], dealt[t]
			# A section goes to one shard whole, so one near the mean
			# leaves nothing to even it out with; and a deal far over the
			# mean is the timeout this is here to prevent.
			for (i = 1; n > 1 && i <= ns; i++)
				if (c[order[i]] > mean * 3 / 4)
					refuse(sprintf("section \"%s\" costs %.1fs, over three quarters of a shard\047s mean %.1fs: split it into sections of their own names, or let arms that ask about one tree read one run of it", order[i], c[order[i]], mean))
			if (n > 1 && load[most] > mean * 1.15)
				refuse(sprintf("the shards are uneven: shard %d carries %.1fs, over 15%% above the mean %.1fs", most + 1, load[most], mean))
			if (refused) exit 5
			if (show) { shown = 1; exit 6 }
		}
		/^# =+ the tally$/ { print "_st_section end"; tally = 1 }
		{ print }
		!tally && /^# -----+ / {
			name = $0
			sub(/^# -+ /, "", name)
			q = name
			gsub(/\047/, "\047\\\047\047", q)
			if (shard[name] == k) { kept++; print "_st_section keep \047" q "\047" }
			else print "_st_section skip \047" q "\047"
		}
		END { if (refused) exit 5; if (shown) exit 6; if (!tally) exit 4; if (!kept) exit 3 }' "$_whole" "$_whole" > "$_shard_file"
	_st_rc=$?
	rm -f "$_whole"
	case $_st_rc in
		0) ;;
		3)
			echo "selftest: shard ${TEST_SHARD_INDEX:-0} of $TEST_TOTAL_SHARDS got no section," >&2
			echo "          so nothing would be checked" >&2
			rm -f "$_shard_file"
			exit 2 ;;
		5)
			# The deal printed, then refused (SELFTEST_DEAL): it says where.
			[ -z "${SELFTEST_DEAL:-}" ] || cat "$_shard_file"
			rm -f "$_shard_file"
			exit 2 ;;
		6)
			cat "$_shard_file"
			rm -f "$_shard_file"
			exit 0 ;;
		4)
			# Without it the last section's _st_section never ends, and a
			# skipped last section would swallow the tally.
			echo "selftest: no '# ===== the tally' line above the tally" >&2
			rm -f "$_shard_file"
			exit 2 ;;
		*)
			echo "selftest: could not write this shard's copy of $0" >&2
			rm -f "$_shard_file"
			exit 2 ;;
	esac
	SELFTEST_SHARD="${TEST_SHARD_INDEX:-0}" SELFTEST_SHARD_FILE="$_shard_file" \
		SELFTEST_SELF="$0" exec sh "$_shard_file" "$@"
fi
# The copy removes itself: the shell reads it through a descriptor it holds.
[ -z "${SELFTEST_SHARD_FILE:-}" ] || rm -f "$SELFTEST_SHARD_FILE"
# This file, which a shard's copy is not ("the shard deal" reads its header).
ST_SELF=${SELFTEST_SELF:-$0}
# The folder of this file's sections (THE SECTIONS), by its absolute path:
# a hand run names this file relative to wherever it was started.
ST_PARTS=$(CDPATH='' cd "$(dirname "$ST_SELF")" && pwd)/selftest_sections

# _st_section keep|skip|end -- the line the shard's copy has after every
# section line (and before the tally). A skipped section runs its plain code
# with stdout on /dev/null (the real one kept on descriptor 9, which nothing
# else here uses), and whatever its hand-written checks counted is put back
# at the next section line: they are the arms of another shard.
#
# Each section's time is printed when the next one starts, so a shard's log
# says where its time went: the arms of a section it keeps, and the plain code
# of one it skips, which every shard runs. The first are what
# selftest_costs.tsv is measured from (SHARD WEIGHTS).
_st_mine=1
# st_mine -- whether this shard runs the arms of the section it is in: where
# a section's plain code makes something only its own arms read -- one run of
# conventions.sh, seconds long, read by forty arms -- it is made under this,
# not in every shard. A file another section's arms read too stays plain
# code, made in every shard, and says so where it is written (diff_output's
# exp.txt, forbidden_symbols' emitted.c, symbols' leaky.c).
st_mine() { [ "$_st_mine" = 1 ]; }
_st_name=""
_st_t0=""
_st_now() {  # sets _st_t, centiseconds since boot ("" without /proc)
	_st_t=""
	read -r _st_up _st_idle < /proc/uptime 2> /dev/null || return 0
	# /proc/uptime is seconds with two decimals, and a machine up a while
	# has no leading zero to be read as octal.
	case "$_st_up" in
		[1-9]*.[0-9][0-9]) _st_t=${_st_up%%.*}${_st_up#*.} ;;
	esac
}
_st_section() {
	_st_now
	if [ -n "$_st_name" ] && [ -n "$_st_t" ] && [ -n "$_st_t0" ]; then
		_st_cs=$((_st_t - _st_t0))
		if [ "$_st_mine" = 1 ]; then
			printf '  [section %s: %d.%02ds, its arms]\n' "$_st_name" $((_st_cs / 100)) $((_st_cs % 100))
		else
			printf '  [section %s: %d.%02ds, plain code only]\n' "$_st_name" $((_st_cs / 100)) $((_st_cs % 100)) >&9
		fi
	fi
	_st_name=${2:-}
	_st_t0=$_st_t
	if [ "$_st_mine" = 0 ]; then
		PASS=$_st_pass
		FAIL=$_st_fail
		exec 1>&9 9>&-
	fi
	_st_mine=1
	[ "$1" = skip ] || return 0
	_st_mine=0
	_st_pass=$PASS
	_st_fail=$FAIL
	exec 9>&1 1>/dev/null
}

VALGRIND=""
VGCGTOOLS=""
ANCHOR=""
NORMINETTE=""
NM=""
NM_LIB=""
SHELLCHECK=""
CLANG=""
CLANG_LIBS=""
CLANG_LIB_FILES=""
GCC=""
SYMBOLIZER=""
SYMBOLIZER_LIB=""
LD=""
LD_LIB=""
OBJDUMP=""
AS=""
AR=""
RANLIB=""
PYTHON=""

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "selftest.sh: $1 needs a value" >&2; exit 2; }; }

# shellcheck disable=SC2034 # --valgrind and --valgrind-callgrind-tools are read by the sections (THE SECTIONS)
while [ $# -gt 0 ]; do
	case "$1" in
		--valgrind) need "$1" "$#"; VALGRIND="$2"; shift 2 ;;
		--valgrind-callgrind-tools) need "$1" "$#"; VGCGTOOLS="$2"; shift 2 ;;
		--anchor) need "$1" "$#"; ANCHOR="$2"; shift 2 ;;
		# Not derivable from the anchor: norminette is a py_binary, so it lands
		# somewhere else in runfiles rather than beside the shell runners.
		--norminette) need "$1" "$#"; NORMINETTE="$2"; shift 2 ;;
		# symbols_test.sh and forbidden_symbols.sh take a SUPPLIED nm with no
		# PATH fallback, so the selftest has to hand them one like Bazel does.
		--nm) need "$1" "$#"; NM="$2"; shift 2 ;;
		# And the library that nm loads, for the same reason Bazel passes it:
		# binutils ships frontends, so a pinned nm with no path to the fetched
		# libbfd loads the box's and stops being pinned. So every arm that
		# hands a runner --nm hands it --nm-lib too, as every BUILD caller
		# does (//tools:conventions holds them to it, TO VERIFY V210).
		--nm-lib) need "$1" "$#"; NM_LIB="$2"; shift 2 ;;
		# Same reason, for shell_test.sh's norm mode and conventions.sh.
		--shellcheck) need "$1" "$#"; SHELLCHECK="$2"; shift 2 ;;
		# The pinned clang and its libraries, for the runners that read what
		# only clang can say (prototype_check.sh --names: its AST dump).
		--clang) need "$1" "$#"; CLANG="$2"; shift 2 ;;
		--clang-lib)
			need "$1" "$#"
			CLANG_LIBS="$CLANG_LIBS --cc-lib $2"
			CLANG_LIB_FILES="${CLANG_LIB_FILES:+$CLANG_LIB_FILES
}$2"
			shift 2 ;;
		# The pinned gcc, for the one runner mode only gcc can answer: the
		# method layer's --fixed-array, which reads gcc's own size warnings.
		--gcc) need "$1" "$#"; GCC="$2"; shift 2 ;;
		# The pinned llvm-symbolizer and a library beside the libLLVM it
		# loads, handed to the sanitizer runners as Bazel hands them over.
		--symbolizer) need "$1" "$#"; SYMBOLIZER="$2"; shift 2 ;;
		--symbolizer-lib) need "$1" "$#"; SYMBOLIZER_LIB="$2"; shift 2 ;;
		# The pinned ld.bfd and a library beside the libbfd it loads, for
		# the runners that link what they compile (tools/runner_lib.sh,
		# rl_ld_pin), handed over as defs_toolchain.bzl hands them (_pinned_ld_args).
		--ld) need "$1" "$#"; LD="$2"; shift 2 ;;
		--ld-lib) need "$1" "$#"; LD_LIB="$2"; shift 2 ;;
		# The pinned objdump, for forbidden_symbols.sh --function, which
		# takes one with no PATH fallback; its libraries are --nm-lib's.
		--objdump) need "$1" "$#"; OBJDUMP="$2"; shift 2 ;;
		# The pinned assembler, for compile_check.sh's --cc-progs arms; its
		# libraries are --nm-lib's too.
		--as) need "$1" "$#"; AS="$2"; shift 2 ;;
		# The pinned ar and ranlib, for make_test.sh's pinned arms: a
		# recipe that names either runs these (TO VERIFY V60). Their
		# libraries are --ld-lib's.
		--ar) need "$1" "$#"; AR="$2"; shift 2 ;;
		--ranlib) need "$1" "$#"; RANLIB="$2"; shift 2 ;;
		# The fetched python3, for env_drift's arms: //tools:env_drift hands
		# its launcher this interpreter, never the box's (ENV_DRIFT_PYTHON).
		--python) need "$1" "$#"; PYTHON="$2"; shift 2 ;;
		*) echo "selftest.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done
# st_required FLAG VALUE... -- exit 2, naming the first FLAG whose VALUE is
# empty: each flag in Usage, above, that is not bracketed.
st_required() {
	while [ "$#" -ge 2 ]; do
		[ -n "$2" ] || { echo "selftest.sh: $1 is required" >&2; exit 2; }
		shift 2
	done
}
st_required --anchor "$ANCHOR"
[ -f "$ANCHOR" ] || { echo "selftest.sh: anchor $ANCHOR does not exist" >&2; exit 2; }
st_required --norminette "$NORMINETTE" --nm "$NM" --nm-lib "$NM_LIB" \
	--shellcheck "$SHELLCHECK" --clang "$CLANG" --gcc "$GCC" \
	--symbolizer "$SYMBOLIZER" --symbolizer-lib "$SYMBOLIZER_LIB" --ld "$LD" \
	--ld-lib "$LD_LIB" --objdump "$OBJDUMP" --as "$AS" --ar "$AR" \
	--ranlib "$RANLIB" --python "$PYTHON" --valgrind "$VALGRIND" \
	--valgrind-callgrind-tools "$VGCGTOOLS"
TOOLS=$(dirname "$ANCHOR")
# The checkout a `bazel run` names. Under `bazel test` neither is set; a hand
# run from the script `bazel run --script_path` writes inherits the real
# checkout's, and every script here that takes its checkout from it -- setup.sh,
# which writes .bazelrc.local -- then worked on that checkout and not on the
# arm's sandbox (V92). An arm that wants one passes its own.
unset BUILD_WORKSPACE_DIRECTORY BUILD_WORKING_DIRECTORY
# And where git's repository is and which configuration it takes. A hand run
# from a `git rebase -x` or `git -c` shell inherits GIT_DIR, GIT_WORK_TREE and
# GIT_CONFIG_PARAMETERS, and every fixture below that runs git without a
# sandbox of its own then worked in THAT repository: its `git init` made
# nothing here, its commits took the checkout's uncommitted work, its
# `git config` rewrote the checkout's identity, and answer_scan's
# `git checkout -q HEAD~1 -- .` threw away its uncommitted edits (V331).
# Two env-audit-commit runs are handed some on purpose, in subshells of
# their own; //tools:conventions holds this line to the list it keeps.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
unset GIT_CONFIG_GLOBAL GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
# And the knobs a user turns whose default the arms test. A SUBMIT_GATE
# exported as submit.sh's own advice says changed the level every gated
# submit arm ran at, and a CLUE_MODE=all -- docs/bazel.md's re-run, or a
# shell's export -- shows every clue row, so the arms asking that a case's
# own row is among the three shown passed wherever it was. An arm that tests
# a knob passes its own with env, as diff_output's CLUE_MODE arms do. And
# GIT_CONFIG_SYSTEM, a file git reads in /etc/gitconfig's place
# (GIT_CONFIG_NOSYSTEM, below, turns both off).
unset SUBMIT_GATE CLUE_MODE GIT_CONFIG_SYSTEM
# And ILP32_CC (docs/reference.md's knob): the 32-bit compiler ilp32_test.sh
# tries first, by its path, where no fixture PATH can hide it. Exported by a
# hand run, the arm on a missing compiler was red on another branch (a long
# of 8 bytes) and the arm on its SKIP green on another SKIP. An arm that
# wants one sets it. //tools:conventions holds this unset and the knobs'
# above (under bazel test none is exported, so no arm would miss them).
unset ILP32_CC

WORK=$(mktemp -d) || { echo "selftest.sh: cannot create a scratch directory" >&2; exit 2; }
# The system rc tools/drives.sh reads first is one of this file's, and absent,
# never the machine's /etc/bazel.bazelrc: a root set there reached every arm
# that asks where Bazel's state goes (V334). An arm that wants one names its
# own.
C_PISCINE_SYSTEM_BAZELRC="$WORK/no-system-bazelrc"
export C_PISCINE_SYSTEM_BAZELRC
# And the user's files are none of this run's: an empty HOME of its own,
# beside WORK and not in it (every section shares it, where a tree in WORK
# is one section's fixture), its XDG_CONFIG_HOME inside it, and no
# /etc/gitconfig. Bazel's HOME is the test's
# scratch folder already, but /etc/gitconfig was read under it too, and a
# hand run read the user's ~/.gitconfig and their 42 config file: an
# init.defaultBranch=main left the teammate fixture's push on no branch, a
# commit.gpgsign or a core.hooksPath failed the fixtures' commits without a
# word, an excludesFile kept the records out of answer_scan's toy repository
# (its arm on them then passed with nothing to scan), and a level in the 42
# file reached every gated submit arm. An arm that needs a HOME of its own
# still passes one. //tools:conventions holds these lines to the git rule's.
ST_HOME=$(mktemp -d) && mkdir "$ST_HOME/.config" ||
	{ rm -rf "$WORK" "$ST_HOME"; echo "selftest.sh: cannot create a scratch HOME" >&2; exit 2; }
HOME=$ST_HOME
XDG_CONFIG_HOME="$HOME/.config"
GIT_CONFIG_NOSYSTEM=1
export HOME XDG_CONFIG_HOME GIT_CONFIG_NOSYSTEM
trap 'rm -rf "$WORK" "$ST_HOME"' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

PASS=0
FAIL=0

# THE ARM HELPERS are tools/tests/selftest_lib.sh's, one copy for this file
# and selftest_slow.sh: the want_* and later_* helpers that judge an arm,
# _st_said, which shows what a failed arm's command said, cv_saved and its
# kin, which read a saved run of the conventions check with its status,
# with_kind, st_oracle, and the two steps below, st_shell_guard and
# st_pin_cc. Its header says what it reads; ST_NAME is the name a refusal
# of this file's own opens with.
ST_NAME=selftest
# shellcheck source=tools/tests/selftest_lib.sh
. "$TOOLS/tests/selftest_lib.sh"

# A test's own time limit, made short: the runners take their budget from
# TEST_TIMEOUT (tools/runner_lib.sh), less a margin -- one second here -- so an
# arm about a program that never ends is over in ten seconds, not three
# hundred. Ten rather than four because these arms are deferred and run beside
# everything else: the runner's own setup has to fit well inside the budget on
# a loaded machine, or the arm reports "no time left to start" instead.
# shellcheck disable=SC2034 # read by the sections (THE SECTIONS), not here
SHORT="env TEST_TIMEOUT=10 RL_MARGIN=1"

# bounded SECS COMMAND... -- for an arm whose failure is a HANG. A hang here
# would stop this whole file at Bazel's timeout, and a TIMEOUT names no arm.
# `timeout` ends the command's whole process group, which matters: a loop in a
# command substitution runs in a child that killing the shell alone leaves
# behind. It exits 124 then, which every want_* reports as a harness error.
# conventions: optional timeout -- without it a bounded arm runs unbounded: it
# still passes on a fixed runner, and a hung one hangs the target as before.
bounded() {
	_bs=$1
	shift
	if command -v timeout > /dev/null 2>&1; then
		timeout "$_bs" "$@"
	else
		"$@"
	fi
}

# once COMMAND...: run COMMAND the first time it is asked for, keeping what it
# printed and its exit status, and replay both every time after. For a runner
# whose one run is slow and read by several arms -- a make_test run with an re
# step sleeps a full second, and a pair of arms used to pay it twice, a
# red/out/none triple three times. The replay is the whole output and the real
# status, so want_red, want_green, want_out and want_broken_none take it as
# they are, and a runner that refused (exit 2) still fails every one of them.
#
# The key is the command line itself, so two arms share a run only when they
# ran the same thing. What it cannot see is a fixture rewritten between them:
# a file a command reads must not change after its first run. Nor does it see
# the environment: a variable exported around the call, or read by a
# function's body, leaves the key as it was, so a run that differs only by
# its environment says so on its command line (`once env X=1 ...`) or does
# not go through once. It holds no lock either: a command a later_* arm runs
# in the background never goes through it, since two first runs of one key
# write one file. And the replay comes back on stdout, stderr merged into it
# as every want_* helper merges it, so a function that pipes it reads both.
once() {
	_ok=$(printf '%s\n' "$@" | sha256sum | cut -c1-32)
	if [ ! -f "$WORK/once/$_ok.rc" ]; then
		mkdir -p "$WORK/once"
		"$@" > "$WORK/once/$_ok.out" 2>&1
		echo "$?" > "$WORK/once/$_ok.rc"
	fi
	cat "$WORK/once/$_ok.out"
	return "$(cat "$WORK/once/$_ok.rc")"
}

# WHICH SHELL INTERPRETS THE RUNNERS: SELFTEST_SH's, `sh` by default, and a
# SKIP where it is not installed (st_shell_guard says why). Every arm below
# launches a runner through "$SH", and //tools/tests:selftest_bash replays
# this file under bash.
st_shell_guard

# THE COMPILER EVERY FIXTURE HERE IS BUILT WITH: the pinned clang-12, linking
# with the pinned ld.bfd, proven by the runners' own helpers and made one
# command, $CC, or exit 2 (st_pin_cc says why).
st_pin_cc "$CLANG" "$CLANG_LIB_FILES"
# And the compiler the runners take when a hand run names none (their
# *_CC defaults, `cc`): an arm that drives one without --cc gets this one.
HEADER_CC=$CC PROTOTYPE_CC=$CC FORBIDDEN_CC=$CC SYMBOLS_CC=$CC
export HEADER_CC PROTOTYPE_CC FORBIDDEN_CC SYMBOLS_CC

# THE PINNED BUILD, as tools/defs_toolchain.bzl hands it to every runner that
# compiles and links at test time (_pinned_build_args): the fetched clang-12
# with the libraries it loads and a file of its own tree, and the fetched
# ld.bfd with its library. asan_check.sh, allocfail_check.sh (with --src),
# cycles_check.sh and ref_compare.sh (with --harness) refuse to build without
# them, and method_check.sh --expect takes the linker half (LD_PIN). One word
# list each, split where it is used, as $CLANG_LIBS is.
BUILD_PIN="--cc $CLANG $CLANG_LIBS --cc-under $CLANG --ld $LD --ld-lib $LD_LIB"
# And the tools a Makefile's recipes run, as defs_toolchain.bzl hands them to
# make_test.sh (_pinned_make_args, TO VERIFY V60): the pinned build, gcc-10,
# and binutils' as, ar and ranlib.
# shellcheck disable=SC2034 # read by the sections (THE SECTIONS), not here
MK_PIN="$BUILD_PIN --gcc $GCC --as $AS --ar $AR --ranlib $RANLIB"
# shellcheck disable=SC2034 # read by the sections (THE SECTIONS), not here
LD_PIN="--ld $LD --ld-lib $LD_LIB"

# THE BUILD STAND-IN every runner below that runs a built program is handed.
# When a student's code does not build, tools/student_build.sh writes a script
# in the program's place that prints the compiler's words and exits
# STANDIN_STATUS (tools/standin.sh), so the build never fails and each test
# fails on its own. Every runner that runs a program has an arm next to its
# others saying a stand-in is a build failure -- red, in the compiler's words,
# never a verdict on a program that does not exist. Written here, once, by the
# builder itself rather than by hand, so an arm fails if either side's wording
# drifts.
mkdir -p "$WORK/standin"
printf 'int\tbroken(void)\n{\n\treturn (0)\n}\n' > "$WORK/standin/broken.c"
printf 'int\tmain(void)\n{\n\treturn (0);\n}\n' > "$WORK/standin/main.c"
"$SH" "$TOOLS/student_build.sh" --cc "$CC" --out "$WORK/standin/prog" --label selftest \
	--harness "$WORK/standin/main.c" --src "$WORK/standin/broken.c" > /dev/null 2>&1 &&
	[ -f "$WORK/standin/prog" ] || {
	echo "selftest: tools/student_build.sh wrote no stand-in for a syntax error" >&2
	exit 2
}
# shellcheck disable=SC2034 # read by the sections (THE SECTIONS), not here
STANDIN_BIN="$WORK/standin/prog"
# And its sibling: the stand-in for a build that had NOTHING to compile (no
# .c file here), which is what an exercise nobody has started looks like.
"$SH" "$TOOLS/student_build.sh" --cc "$CC" --out "$WORK/standin/empty" --label selftest \
	--dir "$WORK/standin/nowhere" --no-archive > /dev/null 2>&1 &&
	[ -f "$WORK/standin/empty" ] || {
	echo "selftest: tools/student_build.sh wrote no stand-in for an empty directory" >&2
	exit 2
}
# What every arm below looks for: the runner's own sentence, and the file the
# compiler named, which only the stand-in's text can have brought.
# shellcheck disable=SC2034 # read by the sections (THE SECTIONS), not here
STANDIN_SAYS='your code did not build'
# shellcheck disable=SC2034 # read by the sections (THE SECTIONS), not here
STANDIN_FILE='standin/broken.c:'

# THE SANITIZER PROBE. Whether this box can BUILD an instrumented binary at
# all is a property of the toolchain, not of a layer under test, so it is
# asked once, here, before the first section: the sanitized arms of
# rust_diff, asan_run, argv_table, rush02 and argv_check read SAN, and
# rust_diff comes first. A box that cannot build one drops every arm that
# needs one, each section saying so with a skip line (st_skipped); under
# NO_SKIP=1 it refuses here instead, exit 2, and this is that refusal's one
# home, as a run that must leave nothing unchecked cannot pass where those
# arms have nothing to run. A toy that does not build on a box that can is
# no skip: each section builds its own with toy_cc, a FAIL in the compiler's
# words. (asan_check's arms need no probe: the runner takes the pinned
# clang-12 and ld.bfd, BUILD_PIN, and proves them itself.) asan_run's first
# arm runs the probe's program.
printf '#include <stdio.h>\nint main(void){char b[8];int i=0;while(i<12){b[i]=(char)i;i++;}printf("%%d\\n",b[0]);return 0;}\n' > "$WORK/oob.c"
# conventions: a probe -- its failure says what the box lacks, and NO_SKIP=1 refuses it below
if "$CC" -g -fsanitize=address,undefined -fno-sanitize-recover=all -fuse-ld=bfd \
		-o "$WORK/oob" "$WORK/oob.c" > /dev/null 2>&1; then
	# shellcheck disable=SC2034 # read by the sections (THE SECTIONS), not here
	SAN=1
else
	# shellcheck disable=SC2034 # read by the sections (THE SECTIONS), not here
	SAN=0
	st_no_skip "no sanitizer build is possible here, so the asan arms" \
		"did not run and the asan layers are unproven."
fi

printf 'selftest: does each layer still detect what it exists to detect?\n\n'

# ============================================================ THE SECTIONS
# Every section, one file each in tools/tests/selftest_sections/, sourced in
# the order they were written: a later one builds on what an earlier one set
# up (SHARDS, above). Each opens with its `# ---- name` line, which
# selftest_costs.tsv and the shard deal know it by. A hand run sources them
# here; a shard runs one text with each line below replaced by its file
# (st_assemble), so the two run the same program. A new section is a file
# there and a line here, in the place its arms need; a block the template
# build strips is spelt here, around the lines of the files that do not
# ship, which the template build's list of private files names.
. "$ST_PARTS/diff_output.sh"
. "$ST_PARTS/progname.sh"
. "$ST_PARTS/rust_diff.sh"
. "$ST_PARTS/forbidden_symbols.sh"
. "$ST_PARTS/symbols.sh"
. "$ST_PARTS/forbidden_functions.sh"
. "$ST_PARTS/forbidden_globals.sh"
. "$ST_PARTS/asan_run.sh"
. "$ST_PARTS/asan_check.sh"
. "$ST_PARTS/files_test.sh"
. "$ST_PARTS/argv_table.sh"
. "$ST_PARTS/units_awk.sh"
. "$ST_PARTS/first_red.sh"
. "$ST_PARTS/units_parity.sh"
. "$ST_PARTS/macro_fixtures_test.sh"
. "$ST_PARTS/header_check.sh"
. "$ST_PARTS/prototype_check.sh"
. "$ST_PARTS/prototype_check_no_restrict.sh"
. "$ST_PARTS/header_norm.sh"
. "$ST_PARTS/method_check.sh"
. "$ST_PARTS/lists_of_words.sh"
. "$ST_PARTS/make_test.sh"
. "$ST_PARTS/make_test_sentences.sh"
. "$ST_PARTS/make_test_archiver.sh"
. "$ST_PARTS/generate.sh"
. "$ST_PARTS/cycles_check.sh"
. "$ST_PARTS/ref_compare.sh"
. "$ST_PARTS/oracle_check.sh"
. "$ST_PARTS/model_check.sh"
. "$ST_PARTS/env_drift.sh"
. "$ST_PARTS/env_audit.sh"
. "$ST_PARTS/compile_check_1.sh"
. "$ST_PARTS/env_audit_commit.sh"
. "$ST_PARTS/student_build.sh"
. "$ST_PARTS/shell_check_1.sh"
. "$ST_PARTS/shell_test.sh"
. "$ST_PARTS/shell_check_2.sh"
. "$ST_PARTS/out_parameter_presets.sh"
. "$ST_PARTS/callback_arguments.sh"
. "$ST_PARTS/the_hint_that_fits.sh"
. "$ST_PARTS/harness_memory_placement.sh"
. "$ST_PARTS/compile_check_2.sh"
. "$ST_PARTS/run_check.sh"
. "$ST_PARTS/norminette.sh"
. "$ST_PARTS/gen_header_reset_headers_init.sh"
. "$ST_PARTS/ilp32.sh"
. "$ST_PARTS/require.sh"
. "$ST_PARTS/a_flag_with_no_value.sh"
. "$ST_PARTS/conventions.sh"
. "$ST_PARTS/conventions_a_units_projects_pages_by.sh"
. "$ST_PARTS/conventions_the_contracts_table_of_keys.sh"
. "$ST_PARTS/conventions_a_runners_word_for_its_unit.sh"
. "$ST_PARTS/conventions_dump_harnesses_fixtures.sh"
. "$ST_PARTS/conventions_corpus_runners_module.sh"
. "$ST_PARTS/conventions_how_a_run_ended_python_flags.sh"
. "$ST_PARTS/conventions_the_registry_of_issued_files.sh"
. "$ST_PARTS/conventions_registry_consumers_cr_bytes.sh"
. "$ST_PARTS/conventions_a_built_program_kept_out_of.sh"
. "$ST_PARTS/conventions_bazel_run_first_red_hints.sh"
. "$ST_PARTS/conventions_clue_labels_program_cases.sh"
. "$ST_PARTS/conventions_wider_types_named_methods.sh"
. "$ST_PARTS/conventions_legends_zeroed_buffers.sh"
. "$ST_PARTS/conventions_check_scripts.sh"
. "$ST_PARTS/conventions_every_pinned_binary_compared.sh"
. "$ST_PARTS/conventions_the_images_own_tools_by_hand.sh"
. "$ST_PARTS/conventions_a_projects_own_page_docs.sh"
. "$ST_PARTS/conventions_every_hint_file_is_read.sh"
. "$ST_PARTS/conventions_a_units_own_tests_folder.sh"
. "$ST_PARTS/conventions_the_maintainers_records_todo.sh"
. "$ST_PARTS/conventions_a_reading_named_in_a_hint.sh"
. "$ST_PARTS/conventions_42s_command_registry.sh"
. "$ST_PARTS/conventions_a_tests_scratch_files.sh"
. "$ST_PARTS/conventions_a_librarys_function_folders.sh"
. "$ST_PARTS/conventions_an_awk_element_tested_by.sh"
. "$ST_PARTS/conventions_a_selftest_read_whole.sh"
. "$ST_PARTS/42s_entry_and_installer.sh"
. "$ST_PARTS/postcreate.sh"
. "$ST_PARTS/editor_tasks.sh"
. "$ST_PARTS/allocfail.sh"
. "$ST_PARTS/stub_check.sh"
. "$ST_PARTS/placeholder_pdf.sh"
. "$ST_PARTS/exam_guide.sh"
. "$ST_PARTS/answer_scan.sh"
. "$ST_PARTS/setup.sh"
. "$ST_PARTS/tools_bazel.sh"
. "$ST_PARTS/prime.sh"
. "$ST_PARTS/rush00.sh"
. "$ST_PARTS/rush01.sh"
. "$ST_PARTS/rush02.sh"
. "$ST_PARTS/submit.sh"
. "$ST_PARTS/bsq.sh"
. "$ST_PARTS/oracle_fixtures.sh"
. "$ST_PARTS/reference_cases.sh"
. "$ST_PARTS/issued_test.sh"
. "$ST_PARTS/readme_check.sh"
. "$ST_PARTS/argv_check.sh"
. "$ST_PARTS/file_check.sh"
. "$ST_PARTS/probe_under.sh"
. "$ST_PARTS/the_compiler_pin.sh"
. "$ST_PARTS/the_borrowed_libraries.sh"
. "$ST_PARTS/the_nm_pin.sh"
. "$ST_PARTS/the_shard_deal.sh"
. "$ST_PARTS/the_test_locale.sh"
# ============================================================== the tally
# The deferred arms, which waited while everything above ran. A shard started
# only those of its own sections (later_status and later_term skip the others,
# as want_* does), so each is judged once, in the shard that owns it.
if [ "$LATER_N" -gt 0 ]; then
	printf '\n  -- arms that had to wait (started beside their runners above) --\n'
	later_collect
fi

# Every shard runs this (see SHARDS above), and says which shard it was.
printf '\n  %d checks passed, %d failed%s\n' "$PASS" "$FAIL" \
	"${SELFTEST_SHARD:+ (shard $((SELFTEST_SHARD + 1)) of ${TEST_TOTAL_SHARDS:-1})}"
[ "$FAIL" -eq 0 ] || {
	printf '\n  A runner stopped detecting the thing it exists to detect. That is\n'
	printf '  worse than a red exercise: every test using it now reports OK\n'
	printf '  without checking. Fix the runner before trusting any suite result.\n'
	exit 1
}
exit 0
