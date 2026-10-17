#!/bin/sh
# env_drift.sh — has anything drifted from what tools/pins.tsv expects?
#
# THREE THINGS ARE COMPARED, not two.
#
#   the PIN       what tools/pins.tsv says we expect.
#   the BOX       what this machine carries. On a campus machine this is what
#                 the Moulinette will use, so it is the comparison the grade
#                 depends on.
#   the FETCH     what Bazel actually downloaded, for the tools we no longer
#                 take from the box at all.
#
# The third one was missing for as long as every layer ran the box's binary, and
# it stops being optional the moment one does not. A pin and a fetch that
# disagree means the suite is testing something nobody wrote down -- the same
# false-green shape as everywhere else in this repo, one level up: pins.tsv
# would read 2.38 while the checks ran something else entirely, and nothing
# anywhere would say so. A fetch is pinned by sha256, so a difference here is
# never packaging noise: a version that differs means the pin was edited in
# one place and not the other, and a line without the pin's words means the
# row is handed another tool's binary (V327). It is reported loudly whatever
# its size. A comparison that could not run (a variable //tools:env_drift
# does not set, a path that is no executable) is NOT COMPARED: a fault of
# that target's data, never a pin edit (V326).
#
# WHY DIFFERENCES ARE GRADED RATHER THAN MATCHED.
# The expected value used to be a SUBSTRING, so `clang version 12.` swallowed
# 12.0.0 and 12.0.1 alike. That was the right instinct -- Ubuntu re-packages
# without changing the compiler, and failing on `-19ubuntu3` is noise -- applied
# the wrong way, because "do not fail on it" became "cannot see it". Now the
# full observed string is recorded and the DIFFERENCE is graded:
#
#   major differs        loud. A different compiler; expect different warnings.
#   minor/patch differs  report and re-audit. Campus moved.
#   only the suffix      note it and carry on. Same compiler, new packaging.
#                        Not drift, and --strict ignores it -- but a campus
#                        pin is campus's EXACT string (the owner's ruling,
#                        2026-10-14), so on a campus box it still prints the
#                        re-pin edit, in the drift line's own form.
#
# WHY IT WARNS RATHER THAN FAILS.
# A student sitting at a campus machine that has been upgraded has done nothing
# wrong and can do nothing about it. Failing their build would punish them for
# 42's package update. So drift is reported loudly and exits 0 by default;
# --strict turns it into an error for the one place that should care, a
# maintainer deciding whether to re-pin.
#
# WHY IT DOES NOT RE-PIN ITSELF.
# Changing a pin changes what the whole suite tests. Done automatically it is a
# change nobody made, reviewed, or noticed -- and if campus ever ships a compiler
# that accepts something the Moulinette rejects, auto-repinning would quietly
# teach the suite to accept it too. It prints the exact edit instead.
#
# WHY CAMPUS IS DETECTED OFFLINE.
# Reachability of Vogsphere would work but is the wrong instrument: it needs the
# network, it is slow, it fails on a campus box that is merely offline, and a
# build should not depend on a remote host answering. 42 boxes carry /goinfre and
# /sgoinfre; nothing else does, and testing for a directory costs nothing. The
# test itself is tools/drives.sh's, the one setup.sh and tools/bazel use, so
# the three cannot disagree about which machine this is; C_PISCINE_CAMPUS=0|1
# overrides it (the selftest drives both banners with it).
#
# WHO THE ADVICE IS FOR (finding 005). Campus-kind drift is counted, and fails
# --strict, on every machine; the "worth acting on, re-pin by hand" prose is
# printed only on a campus box, because that is the only box whose tools the
# grade comes from. Off campus the same rows mean your machine differs from
# campus, which is nothing for you to do: the pins describe campus, not your
# machine.
#
# AND WHERE THIS CHECKOUT'S STATE IS. On a campus box it also says when the
# Bazel state of this checkout sits in the quota'd $HOME or under a path with
# no login in it (finding 001), read back from the output base this very
# `bazel run` uses rather than predicted.
#
# A FETCHED TOOL THAT DOES NOT START is a finding of its own, UNRUNNABLE,
# and never fetch drift. Each one is started the way its layers start it
# (its libraries on the loader's path, valgrind with $VALGRIND_LIB, and a
# compiler asked to compile an empty file), and a non-zero status or a
# loader's error is not a version: graded as one, a loader error naming
# libbfd-2.38-system.so read as "ok", since 2.38 is the pin, and a valgrind
# that could not start its tool read as a pin edited in one place (V243).
# The cause is the machine (a library it lacks, a system newer than the
# one the fetched tools were built for), and the dev container is the fix.
# A tool of this BOX that does not start is DID NOT START, by the same two
# signs, and counts with the missing (V328).
#
# Usage:
#   bazel run //tools:env_drift [-- --strict] [-- --report]
#
#   --strict   exit 1 on campus-kind drift, ANY fetch drift, or a fetched
#              tool that does not start (for a maintainer)
#   --report   also write a timestamped copy under tools/env-reports/
#
# The summary line ("N match, ..., N unrunnable, N recorded") is read by
# `42 doctor` (tools/fortytwo/doctor.py), which turns an unrunnable count
# above 0 into a blocker and a missing line into "env_drift did not
# finish". It reads the line rather than the exit status, which `bazel run`
# shares with Bazel's own: 1 is also a build that failed, and 2, this
# script's refusal below, is also Bazel refusing an option; the status only
# picks that BLOCK's wording. Reword it in both.
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "env_drift.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk date dirname env grep mkdir readlink sed sort tail tr
# conventions: optional python3 -- reads norminette's package metadata, since it
# has no --version flag. Absent, that one row reports "(not importable)" and
# every other row is still compared.
# conventions: optional uname -- the machine's name for --report's file, when
# neither C_PISCINE_HOST nor /proc gives one; without it the name is "unknown".

STRICT=0
REPORT=0
PINS_OVERRIDE=""
while [ $# -gt 0 ]; do
	case "$1" in
		--strict) STRICT=1; shift ;;
		--report) REPORT=1; shift ;;
		# --pins exists so the GRADING can be tested. It is comparison logic
		# with no test of its own otherwise, and comparison logic that quietly
		# stops comparing is this repo's signature failure -- two versions of
		# the extractor here got a wrong answer for a bare "3.3.58" before any
		# of it ran against a fixture. //tools/tests:selftest drives it.
		--pins)
			[ "$#" -ge 2 ] || { echo "env_drift.sh: --pins needs a value" >&2; exit 2; }
			PINS_OVERRIDE="$2"; shift 2 ;;
		*) echo "env_drift.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

# Bazel hands the fetched binaries over as runfiles-relative paths, and the cd
# below would strand every one of them -- silently, since a binary that cannot
# be found reads exactly like a tool nobody pinned. Remembering where we started
# is what lets the resolution happen later, in the loop, for ANY variable a
# pins.tsv row names rather than for a hardcoded list of three.
ORIG_PWD=$PWD

# THE RUNFILES ROOT, which is not $PWD: `bazel run` starts an sh_binary inside
# <target>.runfiles/_main, one level BELOW the root that rootpaths like
# `../clang_12_ubuntu+/usr/bin/clang-12` are written against. Bazel leaves
# RUNFILES_DIR unset here (measured), and a fetched tool that is a LAUNCHER
# rather than a binary needs it: buildifier's wrapper looks its real executable
# up in that tree and, invoked by absolute path from a script that is not its
# own, reported "Unable to locate buildifier runfile" -- which grade() then read
# as a version string and called major drift. An inherited value wins, for a
# caller that knows better than this arithmetic.
RUNFILES_ROOT="${RUNFILES_DIR:-${ORIG_PWD%/*}}"

abs_path() {
	[ -n "$1" ] || return 0
	case "$1" in
		/*) printf '%s' "$1" ;;
		*) printf '%s/%s' "$ORIG_PWD" "$1" ;;
	esac
}

# The convention is <VAR>_LIBS beside <VAR>, holding a colon-separated list of
# the LIBRARY FILES a fetched binary needs; their directories are what goes on
# the loader's path. A fetched binary run without them loads the BOX's copies,
# and this comparison then reports on a toolchain other than the pinned one --
# the check failing in precisely the way it exists to catch, which is why the
# directories are verified below rather than assumed.
#
# Files rather than directories because the caller is Bazel, which expands a
# label to a file and has no dirname -- and because deriving a directory by
# appending /.. to a file silently produces a path that cannot be used and
# cannot be noticed. That exact mistake shipped here for one commit.
abs_libdir_list() {
	[ -n "$1" ] || return 0
	_out=""
	_ifs=$IFS
	IFS=:
	for _p in $1; do
		_out="${_out:+$_out:}$(dirname "$(abs_path "$_p")")"
	done
	IFS=$_ifs
	printf '%s' "$_out"
}
PINS_OVERRIDE=$(abs_path "$PINS_OVERRIDE")

WS="${BUILD_WORKSPACE_DIRECTORY:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$WS" || { echo "env_drift.sh: cannot enter '$WS'" >&2; exit 2; }

# tools/drives.sh: which machine this is, and whether a Bazel root is per-user.
# From the workspace, as setup.sh, prime.sh, env-audit and the wrapper read it,
# and never from beside $0. That is true of a hand run only: under `bazel run`,
# $0 is bazel-bin's symlink to this file and nothing sits beside it, so this
# exited 2 on every machine while the selftest, which runs it from tools/,
# stayed green. //tools/tests:selftest now runs it the way `bazel run` does.
if [ -r "$WS/tools/drives.sh" ]; then
	# shellcheck source=tools/drives.sh
	. "$WS/tools/drives.sh"
else
	echo "env_drift.sh: cannot read $WS/tools/drives.sh, which says which machine this is" >&2
	exit 2
fi

PINS="${PINS_OVERRIDE:-tools/pins.tsv}"
[ -r "$PINS" ] || { echo "env_drift.sh: cannot read $PINS" >&2; exit 2; }

# ---------------------------------------------------------------- where am I
drives_campus
ON_CAMPUS=$DRIVES_CAMPUS
WHY=$DRIVES_CAMPUS_WHY

echo "env_drift: comparing this machine against $PINS"
if [ "$ON_CAMPUS" = 1 ]; then
	echo "  machine: CAMPUS ($WHY)"
	echo "  This is the run that counts -- campus-kind pins must match here."
else
	echo "  machine: not a campus box ($WHY)"
	echo "  Rows marked campus compare this machine with campus. The pins describe"
	echo "  campus, not this machine, so a difference here is nothing to fix on it."
fi
echo ""

# norminette prints a locale banner before anything else, so its version comes
# from the package metadata rather than a --version flag it does not really have.
norminette_version() {
	python3 -c 'import importlib.metadata as m; print(m.version("norminette"))' 2>/dev/null ||
		echo "(norminette not importable)"
}

# What language standard does a compiler assume when nobody says?
#
# This is not a version, and it is the thing that actually decides whether five
# of c-12's contracts accept correct code: under gnu17 an empty parameter list
# means "unspecified", under C23 it means "(void)". The suite pins -std=gnu17
# explicitly, but the MOULINETTE compiles with no -std at all -- so what matters
# here is the box's default, and it has to keep matching what we pin.
#
# Reported as "<__STDC_VERSION__> <gnu|strict>", which is the whole answer in
# two words: 201710L gnu.
default_std() {
	[ -n "$1" ] || { echo "(no compiler)"; return; }
	command -v "$1" > /dev/null 2>&1 || { echo "(not installed)"; return; }
	"$1" -dM -E -x c /dev/null 2>/dev/null | awk '
		/__STDC_VERSION__/ { v = $3 }
		/__STRICT_ANSI__/  { a = 1 }
		END { printf "%s %s", (v == "" ? "(none)" : v), (a ? "strict" : "gnu") }'
}

# The LAST complete dotted number in a version string. Most upstreams here put
# the real version last -- "Ubuntu clang version 12.0.1-19ubuntu3",
# "gcc-10 (Ubuntu 10.5.0-1ubuntu1~22.04.3) 10.5.0", "valgrind-3.18.1" -- so the
# last one skips the packaging numbers and the distro release that come earlier.
# Not all: ssh's and ip's lines end in a library's version, which is why
# grade() also compares first_version_of's.
#
# Whole tokens, not a greedy regex over the line. A greedy `.*` before the
# capture matches from the LAST position it can, which inside "3.3.58" means
# starting after the first dot and returning "3.58" -- a version that is not
# there, silently, and only for the pins written as a bare number.
# THE FIRST LINE WITH CONTENT, not literally line 1.
#
# `head -n 1` was right for every tool here until perl, whose --version prints a
# BLANK line first and the version on the second. The row then compared the
# empty string against the pin and reported the tool MISSING on a machine where
# it was installed and working -- a false negative in the one check whose job is
# to notice a difference. Nothing else would have said so: the cycles layers use
# perl through callgrind_annotate and were green throughout.
# ...and shellcheck went one step further: its --version prints a BANNER first
# ("ShellCheck - shell script analysis tool") and "version: 0.10.0" on the line
# after. That line has content, so "the first line with content" pinned the
# banner -- a string that is identical in every release, i.e. a pin that can
# never report drift.
#
# So: the first line that carries a dotted version, and the first line with
# content only if no line does. That is the same correction perl forced, made
# general instead of made once.
first_line() {
	awk '
		!seen && NF { seen = 1; fallback = $0 }
		/[0-9]+\.[0-9]+/ { print; found = 1; exit }
		END { if (!found) print fallback }
	'
}

version_of() {
	printf '%s' "$1" | grep -oE '[0-9]+(\.[0-9]+)+' | tail -n 1
}

# The FIRST version number: the tool's own, on every line pins.tsv records
# that has one (the cc-std rows' "201710L gnu" has none).
# Some lines end in another program's -- `ip -V` in libbpf's, `ssh -V` in
# OpenSSL's -- so the last number alone graded iproute2 moving a whole major
# release under the same libbpf as a repackaging.
first_version_of() {
	printf '%s' "$1" | grep -oE '[0-9]+(\.[0-9]+)+' | sed -n 1p
}

# Does the pinned version appear ANYWHERE in the observed string as a version in
# its own right? This is the rule for a tool that reports several: `norminette
# --version` prints its own version, Python's and the kernel's on one line, so
# "the last one" reads the kernel's and would grade a perfectly correct 3.3.58
# as a different major release.
version_present() {
	printf '%s' "$2" | grep -oE '[0-9]+(\.[0-9]+)+' | grep -qxF "$1"
}

# ok | packaging | patch | minor | major, comparing two full version strings.
# Anything with no recognisable number in it grades as `major`: unknown is not
# the same as equal, and treating it as equal is how a version comparison stops
# comparing.
grade() {
	_want="$1"
	_got="$2"
	[ "$_want" = "$_got" ] && { echo ok; return; }

	_wv=$(version_of "$_want")
	_gv=$(version_of "$_got")
	[ -n "$_wv" ] && [ -n "$_gv" ] || { echo major; return; }

	# The tool's own number moved: drift, whatever the last number says.
	# Unless the box's line carries it elsewhere, which is the case
	# version_present exists for.
	_wf=$(first_version_of "$_want")
	_gf=$(first_version_of "$_got")
	if [ "$_wf" != "$_gf" ] && ! version_present "$_wf" "$_got"; then
		version_step "$_wf" "$_gf"
		return
	fi

	[ "$_wv" = "$_gv" ] && { echo packaging; return; }

	version_present "$_wv" "$_got" && { echo packaging; return; }

	version_step "$_wv" "$_gv"
}

# The pin's words before its first version, its trailing blanks cut:
# "GNU nm (GNU Binutils for Ubuntu)" of the nm pin, nothing of a bare
# "0.13.0". A fetched binary's line has to hold them (V327): graded on its
# numbers alone, another tool that exits 0 with the pinned number in its
# line -- objdump handed to the nm row, both 2.38 -- read "ok". Anywhere in
# the line, never at its start: gcc names itself by the name it was run as,
# so the fetched gcc-10's line starts "x86_64-linux-gnu-gcc-10 (Ubuntu".
# The same rule makes a rootpath through a "gcc" link read as another tool.
pin_banner() {
	printf '%s\n' "$1" | awk '
		match($0, /[0-9]+(\.[0-9]+)+/) { s = substr($0, 1, RSTART - 1) }
		{ sub(/[ \t]+$/, "", s); print s; exit }'
}

# major | minor | patch: how far apart two version numbers are.
version_step() {
	_wmaj=${1%%.*}
	_gmaj=${2%%.*}
	[ "$_wmaj" = "$_gmaj" ] || { echo major; return; }

	_wrest=${1#*.}
	_grest=${2#*.}
	_wmin=${_wrest%%.*}
	_gmin=${_grest%%.*}
	[ "$_wmin" = "$_gmin" ] || { echo minor; return; }
	echo patch
}

# fetched_run LIBDIRS VALGRIND_LIB BINARY ARGS... -- a fetched binary, as its
# layers run it: LIBDIRS first on the loader's path, $VALGRIND_LIB set, and
# RUNFILES_DIR (see RUNFILES_ROOT). An empty one is left as it is.
fetched_run() {
	_fr_libs=$1
	_fr_vg=$2
	shift 2
	if [ -n "$_fr_libs" ] && [ -n "$_fr_vg" ]; then
		env RUNFILES_DIR="$RUNFILES_ROOT" VALGRIND_LIB="$_fr_vg" \
			LD_LIBRARY_PATH="$_fr_libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "$@"
	elif [ -n "$_fr_libs" ]; then
		env RUNFILES_DIR="$RUNFILES_ROOT" \
			LD_LIBRARY_PATH="$_fr_libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "$@"
	elif [ -n "$_fr_vg" ]; then
		env RUNFILES_DIR="$RUNFILES_ROOT" VALGRIND_LIB="$_fr_vg" "$@"
	else
		env RUNFILES_DIR="$RUNFILES_ROOT" "$@"
	fi
}

# What a program that did not start says, whatever its status: the loader's
# missing library, and valgrind's missing tool.
START_FAILURE='error while loading shared libraries|failed to start tool'
start_failure() {
	printf '%s\n' "$1" | grep -qE "$START_FAILURE"
}

MATCH=0
DRIFT=0
MISSING=0
RECORDED=0
FETCH_DRIFT=0
UNRUNNABLE=0
UNRUN_LINES=""
DRIFT_LINES=""
REPIN_LINES=""

# IS THE FETCH HALF APPLICABLE AT ALL?
#
# The HERMETIC_* variables are set by //tools:env_drift's `data`, so under
# `bazel run` they are all present and outside it none of them are. Those two
# situations need opposite answers: one unset variable among many is a pinned
# binary that stopped being compared, which is drift; ALL of them unset is a
# hand-run of the script, where there is nothing to compare and saying "drift"
# would be crying wolf on every standalone invocation.
_herm_set=0
# Column 6 is "the variable holding the fetched path", whatever it is called --
# not necessarily HERMETIC_*. Matching on that prefix made this probe blind to
# any other naming, which is precisely what the selftest fixtures use.
for _h in $(awk -F'\t' 'NF >= 6 && $6 != "" { print $6 }' "$PINS" 2>/dev/null); do
	eval "_hv=\${$_h:-}"
	[ -z "$_hv" ] || _herm_set=1
done
FETCH_LINES=""
WIRING_LINES=""
NL='
'

while IFS='	' read -r tool kind want cmd where herm; do
	case "$tool" in
		'#'* | '') continue ;;
	esac
	herm=${herm:-}
	nostart=""

	# KIND `fetched`: the box is not consulted, because nothing here uses its
	# copy. shellcheck, zig and buildifier are downloaded by Bazel against a
	# sha256 and every layer runs THAT binary -- so an apt-installed 0.8.0
	# sitting beside our pinned 0.10.0 is not drift, it is irrelevant.
	# (A comment line may not START with the word shellcheck: shellcheck reads
	# that as one of its own directives and fails to parse the file.)
	# Reporting it as drift would put a permanent false red in front of the one
	# check whose whole value is that a red means something.
	#
	# The comparison that IS meaningful for these rows is pin-vs-fetch, which
	# the fetch half below already performs.
	#
	# A version-command of `-` means "recorded here, deliberately not probed":
	# a row nothing on this machine can be asked about from here (pins.tsv's
	# header names each one and why -- bazel and bazelisk cannot be asked
	# without re-entering Bazel and contending for the lock this very command
	# holds). They are still pinned -- //tools:conventions checks that the
	# version this file records is the version the file in `pinned-in`
	# actually installs -- so "not probed" is not "not checked".
	if [ "$kind" = "fetched" ]; then
		printf '  %-11s %-7s not taken from this box\n' "$tool" "$kind"
		got=""
	elif [ "$cmd" = "-" ]; then
		RECORDED=$((RECORDED + 1))
		printf '  %-11s %-7s recorded %s (not probed: %s)\n' "$tool" "$kind" "$want" "$where"
		continue
	elif [ "$cmd" = "norminette-version" ]; then
		got=$(norminette_version)
	elif [ "${cmd% *}" = "default-std" ]; then
		got=$(default_std "${cmd#* }")
	else
		# The output and the status APART, as the fetch half keeps them:
		# piped into first_line, the status was first_line's, and a box tool
		# that could not start was graded on its error, "ok (repackaged)"
		# for a loader error naming libbfd-2.38, the pin's number (V328).
		# One that is installed and exits non-zero, or says what a program
		# that did not start says, DID NOT START: counted with the missing,
		# since this box cannot run it either, and never graded. An absent
		# one is still MISSING, below.
		# shellcheck disable=SC2086
		bout=$($cmd 2>&1)
		brc=$?
		got=$(printf '%s\n' "$bout" | first_line)
		if { [ "$brc" -ne 0 ] || start_failure "$bout"; } &&
			command -v "${cmd%% *}" > /dev/null 2>&1; then
			nostart=$(printf '%s\n' "$bout" | grep -m 1 -E "$START_FAILURE")
			[ -n "$nostart" ] || nostart=$got
			[ -n "$nostart" ] || nostart="(it printed nothing)"
			nostart="exit $brc: $nostart"
			got=""
		fi
	fi

	# Ask about the binary the version COMMAND runs, not the row's name. They
	# are usually the same, and for one row they are not: glibc is asked with
	# `ldd --version`, because a C library has no executable of its own. Testing
	# the name meant reporting the runtime every deliverable links against as
	# MISSING on a machine that plainly has it -- and a check that cries wolf on
	# a healthy box is one people learn to skim.
	probe=${cmd%% *}
	[ "$probe" != "default-std" ] || probe=${cmd#* }
	if [ -n "$nostart" ]; then
		MISSING=$((MISSING + 1))
		printf '  %-11s %-7s DID NOT START (%s)\n' "$tool" "$kind" "$nostart"
		# --strict fails on it as on an absent campus tool, without the
		# re-pin edit: the machine is at fault, not the pin.
		if [ "$kind" = "campus" ]; then
			DRIFT_LINES="$DRIFT_LINES$NL  $tool (did not start): expected $want; this box's $probe did not start ($nostart)"
		fi
	fi
	# `fetched` rows reach here with got empty ON PURPOSE, which is precisely
	# what the MISSING branch exists to report. Excluded by kind, not by
	# emptiness, so the branch keeps its meaning for every other row.
	if [ -z "$nostart" ] && [ "$kind" != "fetched" ] && { [ -z "$got" ] || ! command -v "$probe" > /dev/null 2>&1; }; then
		if [ "$cmd" != "norminette-version" ]; then
			MISSING=$((MISSING + 1))
			printf '  %-11s %-7s MISSING   (expected %s)\n' "$tool" "$kind" "$want"
			# A campus tool that is ABSENT is campus drift, and --strict is
			# documented as "exit 1 on campus-kind drift". It counted into
			# MISSING and into neither list, and the two lists are the only
			# thing --strict looks at -- so a box carrying none of the pinned
			# tools printed a wall of MISSING and exited 0. The one kind of
			# machine the flag exists to reject was the one it accepted.
			#
			# Only campus-kind, deliberately: a tool absent on someone else's
			# laptop is ordinary, and a check that cries wolf there is one
			# people learn to skim.
			if [ "$kind" = "campus" ]; then
				DRIFT_LINES="$DRIFT_LINES$NL  $tool (missing): expected $want, not installed   (edit $where and tools/pins.tsv)"
			fi
			got=""
		fi
	fi

	if [ -n "$got" ]; then
		verdict=$(grade "$want" "$got")
		case "$verdict" in
			ok)
				MATCH=$((MATCH + 1))
				printf '  %-11s %-7s ok\n' "$tool" "$kind"
				;;
			packaging)
				MATCH=$((MATCH + 1))
				printf '  %-11s %-7s ok (repackaged)\n' "$tool" "$kind"
				printf '              pinned:   %s\n' "$want"
				printf '              this box: %s\n' "$got"
				if [ "$kind" = "campus" ] && [ "$ON_CAMPUS" = 1 ]; then
					printf '              Same version, different package build: not drift, but the\n'
					printf '              pin is campus'"'"'s exact string: re-pin it in %s and tools/pins.tsv\n' "$where"
					REPIN_LINES="$REPIN_LINES$NL  $tool (repackaged): $want  ->  $got   (edit $where and tools/pins.tsv)"
				else
					printf '              Same version, different package build. Nothing to do.\n'
				fi
				;;
			*)
				DRIFT=$((DRIFT + 1))
				printf '  %-11s %-7s DRIFT (%s)\n' "$tool" "$kind" "$verdict"
				printf '              pinned:   %s\n' "$want"
				printf '              this box: %s\n' "$got"
				printf '              pinned in %s\n' "$where"
				if [ "$kind" = "campus" ]; then
					DRIFT_LINES="$DRIFT_LINES$NL  $tool ($verdict): $want  ->  $got   (edit $where and tools/pins.tsv)"
				fi
				;;
		esac
	fi

	# ------------------------------------------------ and what did we FETCH?
	[ -n "$herm" ] || continue
	eval "hpath=\$(abs_path \"\${$herm:-}\")"
	if [ -z "$hpath" ] && [ "$_herm_set" -eq 0 ]; then
		# Hand-run, outside Bazel: nothing was fetched, so there is nothing to
		# compare and this is not a finding.
		continue
	fi
	# NOT a bare `continue` for these two. This is the pin-vs-fetch
	# comparison -- the third of the three this script's header calls
	# non-optional -- and an unset HERMETIC_* means it did not happen.
	# Advising and moving on let the whole comparison disappear one variable
	# at a time while the run still reported no drift and --strict still
	# exited 0. Counted as fetch drift, and listed apart from it: each is a
	# fault of //tools:env_drift's wiring, never "the pin was edited in one
	# place", which the FETCH DRIFT banner says (V326).
	if [ -z "$hpath" ]; then
		FETCH_DRIFT=$((FETCH_DRIFT + 1))
		WIRING_LINES="$WIRING_LINES$NL  $tool: $herm is unset, so the fetched binary was never compared (add it to //tools:env_drift data)"
		printf '              fetched:  NOT COMPARED (%s unset -- add the binary to //tools:env_drift data)\n' "$herm"
		continue
	fi
	if [ ! -x "$hpath" ]; then
		FETCH_DRIFT=$((FETCH_DRIFT + 1))
		WIRING_LINES="$WIRING_LINES$NL  $tool: $herm names $hpath, which is not an executable (fix //tools:env_drift's data, and run it with bazel run)"
		printf '              fetched:  MISSING at %s\n' "$hpath"
		continue
	fi
	eval "hlibs=\$(abs_libdir_list \"\${${herm}_LIBS:-}\")"
	_bad=""
	if [ -n "$hlibs" ]; then
		_ifs=$IFS
		IFS=:
		for _d in $hlibs; do
			[ -d "$_d" ] || _bad="$_d"
		done
		IFS=$_ifs
	fi
	if [ -n "$_bad" ]; then
		UNRUNNABLE=$((UNRUNNABLE + 1))
		printf '              fetched:  UNRUNNABLE (no library dir at %s)\n' "$_bad"
		UNRUN_LINES="$UNRUN_LINES$NL  $tool: ${herm}_LIBS names '$_bad', which does not exist -- the binary would silently load this machine's libraries instead (fix //tools:env_drift's data)"
		continue
	fi
	# <VAR>_TOOLS: a FILE inside valgrind's tool directory, as the layers'
	# --valgrind-tools. Its directory is $VALGRIND_LIB, without which
	# valgrind.bin starts the BOX's memcheck from /usr/libexec/valgrind, or
	# none ("failed to start tool"): --version starts the tool too, so the
	# version reported without it was never the fetched tree's alone.
	# readlink -f and dirname, as valgrind_test.sh derives it.
	eval "htools=\${${herm}_TOOLS:-}"
	hvglib=""
	if [ -n "$htools" ]; then
		htools=$(abs_path "$htools")
		hvglib=$(readlink -f "$htools" 2> /dev/null) || hvglib=""
		[ -n "$hvglib" ] || hvglib=$htools
		hvglib=$(dirname "$hvglib")
		if [ ! -f "$htools" ]; then
			UNRUNNABLE=$((UNRUNNABLE + 1))
			printf '              fetched:  UNRUNNABLE (no tool file at %s)\n' "$htools"
			UNRUN_LINES="$UNRUN_LINES$NL  $tool: ${herm}_TOOLS names '$htools', which does not exist (fix //tools:env_drift's data)"
			continue
		fi
	fi
	# The row's OWN flags, not a hardcoded --version. `zig --version` is an
	# error -- the subcommand is `zig version` -- so a hardcoded flag reports
	# the pinned zig as unversioned and grades a correct fetch as major drift.
	# Rows whose command is not "<tool> <flags>" (norminette-version) keep
	# --version, which is what they were already getting.
	_hargs=${cmd#* }
	[ "$_hargs" != "$cmd" ] || _hargs=--version
	# RUNFILES_ROOT: see its definition. Harmless for the fetched tools that are
	# real executables, and the difference between a verdict and a error message
	# graded as one for the ones that are launchers.
	#
	# The output and the status APART: piped into first_line, the status was
	# first_line's, and a binary the loader could not start (exit 127) was
	# graded on its error message (V243).
	# shellcheck disable=SC2086
	hout=$(fetched_run "$hlibs" "$hvglib" "$hpath" $_hargs 2>&1)
	hrc=$?
	hgot=$(printf '%s\n' "$hout" | first_line)
	# <VAR>_COMPILE: the words a compiler is also run with, a compile of an
	# empty C file. --version runs the driver alone, and a compile starts
	# what the driver hands it to (gcc's cc1, with libraries of its own):
	# a driver can answer --version on a machine where every compile fails.
	eval "hcomp=\${${herm}_COMPILE:-}"
	if [ "$hrc" -eq 0 ] && [ -n "$hcomp" ] && ! start_failure "$hout"; then
		# shellcheck disable=SC2086
		hout=$(fetched_run "$hlibs" "$hvglib" "$hpath" $hcomp 2>&1)
		hrc=$?
		[ "$hrc" -ne 0 ] || hcomp=""
	else
		hcomp=""
	fi
	if [ "$hrc" -ne 0 ] || start_failure "$hout"; then
		hwhy=$(printf '%s\n' "$hout" | grep -m 1 -E "$START_FAILURE")
		[ -n "$hwhy" ] || hwhy=$(printf '%s\n' "$hout" | first_line)
		[ -n "$hwhy" ] || hwhy="(it printed nothing)"
		hhow="${hcomp:+$hcomp, }exit $hrc"
		UNRUNNABLE=$((UNRUNNABLE + 1))
		printf '              fetched:  UNRUNNABLE (%s: %s)\n' "$hhow" "$hwhy"
		UNRUN_LINES="$UNRUN_LINES$NL  $tool ($hhow): $hwhy"
		continue
	fi
	hbanner=$(pin_banner "$want")
	case "$hgot" in
		*"$hbanner"*) ;;
		*)
			FETCH_DRIFT=$((FETCH_DRIFT + 1))
			printf '              fetched:  DRIFT (another tool)\n'
			printf '                        pinned:  %s\n' "$want"
			printf '                        fetched: %s\n' "$hgot"
			FETCH_LINES="$FETCH_LINES$NL  $tool (another tool): pins.tsv says '$want', and the fetched binary's line '$hgot' lacks the pin's words '$hbanner' (which file does //tools:env_drift's data give $herm?)"
			continue
			;;
	esac
	hverdict=$(grade "$want" "$hgot")
	# packaging counts as ok here too: the fetch is pinned by sha256, so the
	# only question this comparison answers is whether the binary reports the
	# version pins.tsv claims, and a version command that also prints its
	# interpreter and libc is not drift.
	if [ "$hverdict" = "ok" ] || [ "$hverdict" = "packaging" ]; then
		# A `fetched` row has no box half, so this IS its verdict and it has to
		# count as one -- otherwise the summary's "N match" silently stops
		# covering three of the tools that decide verdicts.
		[ "$kind" != "fetched" ] || MATCH=$((MATCH + 1))
		printf '              fetched:  ok (%s)\n' "$hgot"
	else
		FETCH_DRIFT=$((FETCH_DRIFT + 1))
		printf '              fetched:  DRIFT (%s)\n' "$hverdict"
		printf '                        pinned:  %s\n' "$want"
		printf '                        fetched: %s\n' "$hgot"
		FETCH_LINES="$FETCH_LINES$NL  $tool ($hverdict): pins.tsv says '$want', the fetched binary says '$hgot'"
	fi
done < "$PINS"

echo ""

# ---------------------------------------------------------------------------
# THE C++ TOOLCHAIN BAZEL CACHED, which is a different question from every row
# above and the one that actually broke a campus box.
#
# `cc_binary` builds with the pinned //tools/cc_toolchain by default
# (MODULE.bazel). The toolchain rules_cc AUTO-DETECTS from the box is reached
# only by --config=gcc (.bazelrc), and it survives in output bases cached before
# the pin. Where it exists, auto-detection ran ONCE, writes absolute paths into
# external/..._local_config_cc/BUILD as `tool_paths = {"ar": "...", ...}`, and
# caches them for the life of the output base. It does not re-run because PATH
# changed.
#
# So: a student with Homebrew on PATH gets `~/.linuxbrew/bin/ar` recorded. They
# later uninstall Homebrew -- which this repo actively recommends, because that
# same brew shadows the pinned binutils -- and every link then dies with
#
#     execvp(/home/<user>/.linuxbrew/bin/ar): No such file or directory
#
# That happened. Nothing above could have caught it: pins.tsv's `ar` row
# compares the pin against the box's `ar`, which is fine and present; what is
# broken is the third thing, the path a cached toolchain still points at.
#
# Read-only and best-effort: no `bazel` is run (this script must work on a box
# where nothing is set up), and anything unreadable is silently skipped. The
# output bases are globbed from the root Bazel actually uses for this checkout:
# the one this `bazel run` is in, read back from the working directory, else
# the one tools/drives.sh predicts, the wrapper's rules included, creating
# nothing. It read .bazelrc.local alone, in its own `=`-only sed, so a checkout
# on the wrapper's default root -- the usual case now -- was never checked.
STALE_TOOLS=""
if _our=$(drives_run_base "$ORIG_PWD" "$0"); then
	_our=${_our%/*}
else
	_our=$(drives_predicted_root "$WS")
fi
if [ -n "$_our" ] && [ -d "$_our" ]; then
	for _cc in "$_our"/*/external/*local_config_cc/BUILD; do
		[ -f "$_cc" ] || continue
		# tool_paths is one line of "name": "/abs/path" pairs. Pull out every
		# absolute path and test it; a relative one is Bazel's own wrapper and
		# is not ours to judge.
		for _tp in $(sed -n 's/.*tool_paths = {\(.*\)}.*/\1/p' "$_cc" |
				tr ',' '\n' | sed -n 's/.*"\(\/[^"]*\)".*/\1/p' | sort -u); do
			[ -x "$_tp" ] && continue
			STALE_TOOLS="$STALE_TOOLS$NL  $_tp   (recorded in ${_cc%/BUILD})"
		done
	done
fi

# `42 doctor` reads this line: see the header before rewording it.
SUMMARY="$MATCH match, $DRIFT drifted, $MISSING missing, $FETCH_DRIFT fetch-drift, $UNRUNNABLE unrunnable, $RECORDED recorded"
echo "  $SUMMARY"

if [ -n "$STALE_TOOLS" ]; then
	echo ""
	echo "  STALE C++ TOOLCHAIN — a cached tool path no longer exists. Every"
	echo "  link will fail with \"execvp(...): No such file or directory\" until"
	echo "  this is invalidated. Bazel auto-detects these ONCE per output base"
	echo "  and does not re-run because PATH changed:"
	printf '%s\n' "$STALE_TOOLS"
	echo ""
	echo "  Fix, cheapest first -- the repository cache is a SIBLING of the"
	echo "  output base and survives both, so neither re-downloads anything."
	echo "  Re-detect just this:"
	echo ""
	echo "      rm -rf <recorded-dir> <recorded-dir>.marker"
	echo ""
	echo "  or start clean:"
	echo ""
	echo "      bazel clean --expunge"
	echo ""
	echo "  The usual cause is a tool that WAS on PATH when the toolchain was"
	echo "  detected and is not now -- uninstalling Homebrew is the common one."
fi

# The prose is for whoever can act on it: on campus, the difference is between
# the pins and the machines the grade comes from, and it goes to whoever keeps
# the pins. Off campus it is between your machine and campus, and the pins
# describe campus, not your machine -- one line, and nothing to do. The count
# above and --strict are the same on both.
if [ "$ON_CAMPUS" = 1 ] && { [ -n "$DRIFT_LINES" ] || [ -n "$REPIN_LINES" ]; }; then
	if [ -n "$DRIFT_LINES" ]; then
		echo ""
		echo "  CAMPUS-KIND DRIFT. These decide whether the suite tests the same"
		echo "  toolchain the grade comes from, so they are the ones worth acting on:"
		printf '%s\n' "$DRIFT_LINES"
	fi
	if [ -n "$REPIN_LINES" ]; then
		echo ""
		echo "  CAMPUS-KIND REPACKAGING. The same version in a different package build:"
		echo "  not drift, and --strict ignores it, but each campus pin is campus's"
		echo "  exact string, so these are re-pinned too:"
		printf '%s\n' "$REPIN_LINES"
	fi
	echo ""
	# A did-not-start line names no pin to edit: the box is at fault.
	case "$DRIFT_LINES$REPIN_LINES" in
	*"(edit "*)
		echo "  Nothing for you to fix: whoever keeps the pins re-pins by hand, in both"
		echo "  places named above -- deliberately not automatic, since a pin changed by"
		echo "  a script is a change to what the suite tests that nobody decided. So"
		echo "  that they hear of it, record this machine with"
		;;
	*)
		echo "  No pin is wrong here: a tool this box has would not start, which is"
		echo "  the machine's fault, not the pins'. So that whoever keeps the pins"
		echo "  hears of it, record this machine with"
		;;
	esac
	echo "      sh tools/env-audit.sh"
	echo "  and send them the report it writes under tools/env-reports/. In a clone"
	echo "  of the public template that is an environment issue, opened from"
	echo "      https://github.com/Jofre/42-template/issues/new/choose"
	echo "  (--push reaches only your own origin). Issues there are public and the"
	echo "  report names you: replace your login and this machine's name everywhere"
	echo "  in it, and rename it (its file name is the machine's), before you attach it."
elif [ -n "$DRIFT_LINES" ]; then
	echo ""
	echo "  Campus-kind rows differ from the pins on this machine, which is not a"
	echo "  campus box: nothing to do here (the pins describe campus)."
fi

# Where this checkout's Bazel state is, on a campus box. The output base this
# `bazel run` uses when started by one, else the root Bazel would use here.
# Asked only on campus: off it there is nothing to warn about.
if [ "$ON_CAMPUS" = 1 ]; then
	_warn=$(drives_root_warning "$(drives_state_of "$WS" "$ORIG_PWD" "$0")" "$WS")
	if [ -n "$_warn" ]; then
		echo ""
		printf '%s\n' "$_warn" | sed 's/^/  /'
	fi
fi

if [ -n "$FETCH_LINES" ]; then
	echo ""
	echo "  FETCH DRIFT — worse than campus drift, and never noise. What Bazel"
	echo "  downloaded is not what pins.tsv claims it downloads, and a fetch is"
	echo "  pinned by sha256, so this cannot be a repackaging. Two versions on a"
	echo "  line mean the pin was edited in one place and not the other; a line"
	echo "  that says \"another tool\" means //tools:env_drift's data hands the row"
	echo "  another binary, or the pin's words were edited. Until it is fixed,"
	echo "  pins.tsv describes a toolchain nothing actually runs:"
	printf '%s\n' "$FETCH_LINES"
fi

if [ -n "$WIRING_LINES" ]; then
	echo ""
	echo "  NOT COMPARED — the fetched binary of these rows was never compared"
	echo "  with its pin, so nothing says the checks run what pins.tsv describes."
	echo "  The pins are not at fault: each line is a fault in //tools:env_drift's"
	echo "  data, or a run of this script that did not come from that target:"
	printf '%s\n' "$WIRING_LINES"
fi

if [ -n "$UNRUN_LINES" ]; then
	echo ""
	echo "  UNRUNNABLE — a fetched tool did not start on this machine, so it was"
	echo "  compared with nothing, and every check that runs it fails here too."
	echo "  The pins are not at fault: most fetched tools are Ubuntu 22.04 builds"
	echo "  that load some shared libraries from this machine, so the usual cause"
	echo "  is a library it lacks, or a system newer than 22.04. The dev container"
	echo "  gives them the system they were built for (docs/environment.md). A"
	echo "  line that names //tools:env_drift's data is a fault in that target:"
	printf '%s\n' "$UNRUN_LINES"
fi

if [ "$REPORT" = 1 ]; then
	mkdir -p tools/env-reports
	stamp=$(date -u '+%Y-%m-%dT%H-%M-%SZ' 2>/dev/null || echo unknown)
	# The machine's name, as tools/prime_trace.sh reads it: C_PISCINE_HOST,
	# the kernel's, then uname's, and anything that is not letters, digits,
	# dots and dashes -- or nothing -- is "unknown". It was `hostname | tr`,
	# which turned hostname's newline into a "_" in every file name, left
	# the name empty where hostname was missing (the status was tr's), and
	# called a command require does not declare (V258).
	host="${C_PISCINE_HOST:-}"
	if [ -z "$host" ] && [ -r /proc/sys/kernel/hostname ]; then
		read -r host < /proc/sys/kernel/hostname || host=""
	fi
	if [ -z "$host" ] && command -v uname > /dev/null 2>&1; then
		host=$(uname -n 2> /dev/null) || host=""
	fi
	case "$host" in
		'' | .* | *[!A-Za-z0-9._-]*) host=unknown ;;
	esac
	out="tools/env-reports/drift-$host-$stamp.txt"
	{
		echo "env_drift report"
		echo "host:     $host"
		echo "when:     $stamp"
		echo "campus:   $ON_CAMPUS ($WHY)"
		echo "result:   $SUMMARY"
		[ -n "$DRIFT_LINES" ] && printf '%s\n' "$DRIFT_LINES"
		[ -n "$REPIN_LINES" ] && printf '%s\n' "$REPIN_LINES"
		[ -n "$FETCH_LINES" ] && printf '%s\n' "$FETCH_LINES"
		[ -n "$WIRING_LINES" ] && printf '%s\n' "$WIRING_LINES"
		[ -n "$UNRUN_LINES" ] && printf '%s\n' "$UNRUN_LINES"
	} > "$out"
	echo ""
	echo "  report written to $out"
	echo "  (commit it -- a timestamped history of what each box carried is how"
	echo "   'when did campus move?' stops being guesswork)"
fi

if [ "$STRICT" = 1 ] && { [ -n "$DRIFT_LINES" ] || [ -n "$FETCH_LINES" ] ||
	[ -n "$WIRING_LINES" ] || [ -n "$UNRUN_LINES" ]; }; then
	exit 1
fi
exit 0
