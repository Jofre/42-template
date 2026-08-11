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
# never packaging noise; it means the pin was edited in one place and not the
# other. It is reported loudly whatever its size.
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
# /sgoinfre; nothing else does, and testing for a directory costs nothing.
#
# Usage:
#   bazel run //tools:env_drift [-- --strict] [-- --report]
#
#   --strict   exit 1 on campus-kind drift or ANY fetch drift (for a maintainer)
#   --report   also write a timestamped copy under tools/env-reports/
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
require awk date dirname env grep mkdir tail tr
# conventions: optional python3 -- reads norminette's package metadata, since it
# has no --version flag. Absent, that one row reports "(not importable)" and
# every other row is still compared.

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

PINS="${PINS_OVERRIDE:-tools/pins.tsv}"
[ -r "$PINS" ] || { echo "env_drift.sh: cannot read $PINS" >&2; exit 2; }

# ---------------------------------------------------------------- where am I
ON_CAMPUS=0
WHY="no 42 filesystem markers"
if [ -d /sgoinfre ] || [ -d /goinfre ]; then
	ON_CAMPUS=1
	WHY="/goinfre or /sgoinfre exists"
elif [ -d /nfs/homes ]; then
	ON_CAMPUS=1
	WHY="/nfs/homes exists"
fi

echo "env_drift: comparing this machine against $PINS"
if [ "$ON_CAMPUS" = 1 ]; then
	echo "  machine: CAMPUS ($WHY)"
	echo "  This is the run that counts -- campus-kind pins must match here."
else
	echo "  machine: not a campus box ($WHY)"
	echo "  Campus-kind drift reported below is only meaningful on a 42 machine."
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

# The LAST complete dotted number in a version string. Every upstream here puts
# the real version last -- "Ubuntu clang version 12.0.1-19ubuntu3",
# "gcc-10 (Ubuntu 10.5.0-1ubuntu1~22.04.3) 10.5.0", "valgrind-3.18.1" -- so the
# last one skips the packaging numbers and the distro release that come earlier.
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
	[ "$_wv" = "$_gv" ] && { echo packaging; return; }

	version_present "$_wv" "$_got" && { echo packaging; return; }

	_wmaj=${_wv%%.*}
	_gmaj=${_gv%%.*}
	[ "$_wmaj" = "$_gmaj" ] || { echo major; return; }

	_wrest=${_wv#*.}
	_grest=${_gv#*.}
	_wmin=${_wrest%%.*}
	_gmin=${_grest%%.*}
	[ "$_wmin" = "$_gmin" ] || { echo minor; return; }
	echo patch
}

MATCH=0
DRIFT=0
MISSING=0
RECORDED=0
FETCH_DRIFT=0
DRIFT_LINES=""

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
NL='
'

while IFS='	' read -r tool kind want cmd where herm; do
	case "$tool" in
		'#'* | '') continue ;;
	esac
	herm=${herm:-}

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
	# A version-command of `-` means "recorded here, deliberately not probed".
	# Exactly two rows need it, and for the same reason: bazel and bazelisk
	# cannot be asked their version from inside a `bazel run` without
	# re-entering Bazel and contending for the lock this very command holds.
	# They are still pinned -- //tools:conventions checks that the version this
	# file records is the version .bazelversion, tools/setup.sh and the
	# Dockerfile actually install -- so "not probed" is not "not checked".
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
		# shellcheck disable=SC2086
		got=$($cmd 2>&1 | first_line)
	fi

	# Ask about the binary the version COMMAND runs, not the row's name. They
	# are usually the same, and for one row they are not: glibc is asked with
	# `ldd --version`, because a C library has no executable of its own. Testing
	# the name meant reporting the runtime every deliverable links against as
	# MISSING on a machine that plainly has it -- and a check that cries wolf on
	# a healthy box is one people learn to skim.
	probe=${cmd%% *}
	[ "$probe" != "default-std" ] || probe=${cmd#* }
	# `fetched` rows reach here with got empty ON PURPOSE, which is precisely
	# what the MISSING branch exists to report. Excluded by kind, not by
	# emptiness, so the branch keeps its meaning for every other row.
	if [ "$kind" != "fetched" ] && { [ -z "$got" ] || ! command -v "$probe" > /dev/null 2>&1; }; then
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
				printf '              Same version, different package build. Nothing to do.\n'
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
	if [ -z "$hpath" ]; then
		# NOT a bare `continue`. This is the pin-vs-fetch comparison -- the
		# third of the three this script's header calls non-optional -- and an
		# unset HERMETIC_* means it did not happen. Advising and moving on let
		# the whole comparison disappear one variable at a time while the run
		# still reported no drift and --strict still exited 0.
		FETCH_DRIFT=$((FETCH_DRIFT + 1))
		FETCH_LINES="$FETCH_LINES$NL  $tool: $herm is unset, so the fetched binary was never compared (add it to //tools:env_drift data)"
		printf '              fetched:  NOT COMPARED (%s unset -- add the binary to //tools:env_drift data)\n' "$herm"
		continue
	fi
	if [ ! -x "$hpath" ]; then
		FETCH_DRIFT=$((FETCH_DRIFT + 1))
		FETCH_LINES="$FETCH_LINES$NL  $tool: pinned binary missing at $hpath"
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
		FETCH_DRIFT=$((FETCH_DRIFT + 1))
		printf '              fetched:  UNRUNNABLE (no library dir at %s)\n' "$_bad"
		FETCH_LINES="$FETCH_LINES$NL  $tool: ${herm}_LIBS names '$_bad', which does not exist -- the binary would silently load this machine's libraries instead"
		continue
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
	# shellcheck disable=SC2086
	if [ -n "$hlibs" ]; then
		hgot=$(env RUNFILES_DIR="$RUNFILES_ROOT" \
			LD_LIBRARY_PATH="$hlibs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
			"$hpath" $_hargs 2>&1 | first_line)
	else
		hgot=$(env RUNFILES_DIR="$RUNFILES_ROOT" "$hpath" $_hargs 2>&1 | first_line)
	fi
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
echo "  $MATCH match, $DRIFT drifted, $MISSING missing, $FETCH_DRIFT fetch-drift, $RECORDED recorded"

if [ -n "$DRIFT_LINES" ]; then
	echo ""
	echo "  CAMPUS-KIND DRIFT. These decide whether the suite tests the same"
	echo "  toolchain the grade comes from, so they are the ones worth acting on:"
	printf '%s\n' "$DRIFT_LINES"
	echo ""
	echo "  Re-pin by hand, in both places named above. Deliberately not automatic:"
	echo "  a pin changed by a script is a change to what the suite tests that"
	echo "  nobody decided."
fi

if [ -n "$FETCH_LINES" ]; then
	echo ""
	echo "  FETCH DRIFT — worse than campus drift, and never noise. What Bazel"
	echo "  downloaded is not what pins.tsv claims it downloads, and a fetch is"
	echo "  pinned by sha256, so this cannot be a repackaging: the pin was edited"
	echo "  in one place and not the other. Until it is fixed, pins.tsv describes"
	echo "  a toolchain nothing actually runs:"
	printf '%s\n' "$FETCH_LINES"
fi

if [ "$REPORT" = 1 ]; then
	mkdir -p tools/env-reports
	stamp=$(date -u '+%Y-%m-%dT%H-%M-%SZ' 2>/dev/null || echo unknown)
	host=$(hostname 2>/dev/null | tr -c 'A-Za-z0-9._-' '_' || echo unknown)
	out="tools/env-reports/drift-$host-$stamp.txt"
	{
		echo "env_drift report"
		echo "host:     $host"
		echo "when:     $stamp"
		echo "campus:   $ON_CAMPUS ($WHY)"
		echo "result:   $MATCH match, $DRIFT drifted, $MISSING missing, $FETCH_DRIFT fetch-drift, $RECORDED recorded"
		[ -n "$DRIFT_LINES" ] && printf '%s\n' "$DRIFT_LINES"
		[ -n "$FETCH_LINES" ] && printf '%s\n' "$FETCH_LINES"
	} > "$out"
	echo ""
	echo "  report written to $out"
	echo "  (commit it -- a timestamped history of what each box carried is how"
	echo "   'when did campus move?' stops being guesswork)"
fi

if [ "$STRICT" = 1 ] && { [ -n "$DRIFT_LINES" ] || [ -n "$FETCH_LINES" ]; }; then
	exit 1
fi
exit 0
