# shellcheck shell=sh
# (sourced library, never executed, so it has no shebang -- this directive
#  tells shellcheck the dialect without implying the file is a program.)
# shell_check.sh — tiny library sourced by c-piscine shell check scripts so a
# failing exercise shows a per-PROPERTY checklist instead of one opaque exit code.
# The shell_test.sh runner exports SHELL_CHECK_LIB pointing here; a check.sh does:
#
#     . "${SHELL_CHECK_LIB:?}"
#     ck_require "foo.sh exists"       test -f "$D"             # else stop: nothing to check
#     ck_sh_parses "$D"                                         # /bin/sh can read it (sh -n)
#     ck_run "$raw" sh "$D"                                     # the ONE way to run a turn-in
#     ck     "prints something"        test -s "$raw"           # PASS if cmd exits 0
#     ck_eq  "member size (bytes)"     "$got" "40"              # compares; shows want/got
#     ck_report                                                  # prints RESULT, exits 0/1
#
# A turn-in is never run any other way than through ck_run: it keeps the
# script's stderr and exit status and shows them when they say something, and
# it runs a script with /bin/sh, as the shell subjects require. A check that
# runs `sh "$D" 2>/dev/null` itself throws away the one line that explains a
# failure (//tools:conventions refuses it).
#
# Show SPEC values (sizes, permissions, names from the subject) freely — they are
# requirements, not the solution. Do NOT pass a value that would reveal the answer
# itself (e.g. an expected computed output): use plain `ck` (pass/fail) for those.

_CK_N=0
_CK_FAIL=0
_CK_SKIP=0
_CK_REPORTED=0

# A check.sh that forgets its final ck_report prints [FAIL] lines to the log and
# then exits with whatever its LAST command happened to return -- usually 0. The
# log says FAIL, Bazel says PASSED, and nothing reconciles them. All 17 live
# check scripts do call ck_report, so this is latent rather than broken; adding
# the eighteenth is all it would take, and the cost of noticing late is a
# student's Moulinette result.
#
# shell_test.sh runs the check script with `sh "$CHECK"`, a separate shell, so
# this trap belongs to the check script alone and cannot touch the runner.
#
# It never turns a red into a green: a non-zero status is passed through
# untouched, and only an unreported exit 0 is converted. The trap returns rather
# than exiting on the normal path, which leaves ck_report's own status intact.
_ck_exit_guard() {
	_ck_rc=$?
	if [ "$_CK_REPORTED" = 1 ]; then
		return
	fi
	printf '  ------------------------------\n'
	printf '  BROKEN CHECK SCRIPT: it ended without calling ck_report.\n'
	printf '  %d check(s) ran and %d failed, but the exit status came from\n' \
		"$_CK_N" "$_CK_FAIL"
	printf '  whatever command happened to run last, not from them. Without\n'
	printf '  ck_report this test can print [FAIL] and still be reported as\n'
	printf '  passing. Add ck_report as the final line of the check script.\n'
	if [ "$_ck_rc" -ne 0 ]; then
		exit "$_ck_rc"
	fi
	exit 1
}
trap _ck_exit_guard EXIT

# ck_skip "<why>" -> the exercise cannot be checked HERE, and says so.
#
# One exercise needs it: shell-00 ex07's answer is derived from a resource 42
# issues and this repo does not redistribute, so on a fresh clone there is
# nothing to check against. That is not a pass and not a failure of the
# student's work -- and the difference has to survive, because a skip that
# looks like a pass is the defect class this whole repo is built against.
#
# NO_SKIP=1 turns it into a failure, the same lever every other gated layer
# here answers to, so the forced sweep can still tell "quiet because clean"
# from "quiet because it never ran". It reports and exits, so the guard above
# is satisfied.
ck_skip() {
	_CK_REPORTED=1
	printf '  ------------------------------
'
	printf '  SKIP: %s
' "$1"
	if [ "${NO_SKIP:-0}" = "1" ]; then
		printf '  NO_SKIP=1 is set, so this counts as a failure: nothing was checked.
'
		exit 1
	fi
	printf '  RESULT: SKIPPED (nothing was checked)
'
	exit 0
}

# ck_broken "<why>" -> nothing can be judged, and the fault is the harness's:
# a reference that disagrees with the subject's own example, a fixture that
# is not there. Exit 2, the code every runner here keeps for "the check never
# ran", never 1, which would blame the turn-in. It reports and exits, so the
# guard above is satisfied, and NO_SKIP changes nothing: this is not a skip.
ck_broken() {
	_CK_REPORTED=1
	printf '  ------------------------------\n'
	printf '  BROKEN HARNESS: %s\n' "$1"
	printf '  RESULT: nothing was judged (exit 2: the harness failed, not the turn-in)\n'
	exit 2
}

# ck_skipped "<why>" -> ONE property cannot be observed on this machine, while
# the rest of the script can still grade everything else.
#
# ck_skip above abandons the whole exercise; this is its per-property sibling,
# and the difference that matters is not which one you reach for but that the
# skip SURVIVES INTO THE RESULT LINE. Both check scripts that had one printed
# `[SKIP] ...` and then reported `RESULT: PASS (7/7 checks)` -- a total counting
# only what ran -- so a reader, and every log scraper, saw an unqualified pass
# over a property nobody had checked. That is this repo's worst defect class
# wearing the word SKIP.
#
# The host is the only legitimate thing to key one off. shell-01 ex07 keyed its
# skip off the DELIVERABLE's own output, which let a broken program switch its
# own tests off: one emitting three tokens for every range skipped both
# assertions and scored 7/7. Ask whether the MACHINE can show the property, and
# ask it before the program is consulted.
#
# NO_SKIP=1 turns it into a failure, the lever every other gate here answers to,
# so the forced sweep can still tell "quiet because clean" from "quiet because
# it never ran". It counts as a failed check rather than exiting, so a script
# with several skips reports all of them in one run.
ck_skipped() {
	_CK_SKIP=$((_CK_SKIP + 1))
	printf '  [SKIP] %s\n' "$1"
	if [ "${NO_SKIP:-0}" = "1" ]; then
		printf '  [FAIL] NO_SKIP=1 is set, so the skip above is a failure: nothing checked it.\n'
		_CK_N=$((_CK_N + 1))
		_CK_FAIL=$((_CK_FAIL + 1))
	fi
}

# ck "<requirement>" cmd...  -> PASS when the command succeeds (exit 0).
ck() {
	_lbl=$1
	shift
	_CK_N=$((_CK_N + 1))
	if "$@" >/dev/null 2>&1; then
		printf '  [PASS] %s\n' "$_lbl"
	else
		printf '  [FAIL] %s\n' "$_lbl"
		_CK_FAIL=$((_CK_FAIL + 1))
	fi
}

# ck_eq "<requirement>" "<got>" "<want>"  -> compares two strings; shows both on fail.
#
# Both are shown through runner_lib.sh's rl_vis arg (THE ONE BYTE RENDERER),
# each in brackets: \xHH for a byte outside printable ASCII, \t, \n, the
# backslash doubled, a $ as \x24, and the brackets make a blank at either end
# visible. Printed raw, "42 file " against "42 file" or a captured carriage
# return read as two identical values beside a FAIL (finding 042's class).
ck_eq() {
	_CK_N=$((_CK_N + 1))
	if [ "$2" = "$3" ]; then
		printf '  [PASS] %s\n' "$1"
	else
		printf '  [FAIL] %s (want [%s], got [%s])\n' "$1" "$(_ck_vis "$3")" "$(_ck_vis "$2")"
		_CK_FAIL=$((_CK_FAIL + 1))
	fi
}

# ck_require "<requirement>" cmd...  -> like ck, but a FAIL ends the checklist:
# every other check needs this one, so none of them runs.
#
# It exists for the turn-in itself. A check script used to go on after
# `ck "x.sh exists" test -f "$D"` failed, and every check that asserts an
# absence -- "no spaces in the output", "ignores the look-alike", "does not
# list the tracked file" -- passed on the output of a file that was not there.
# A stub scored four PASS lines out of seven, for properties of nothing. So
# the first check of every check script is this one (//tools:conventions
# refuses any other), and its failure is the only line printed.
#
# The RESULT line says why nothing else ran, from what the check found: a
# command whose last argument names nothing on disk is a file that does not
# exist; anything else is reported as the requirement that did not hold.
ck_require() {
	_ck_l=$1
	shift
	_CK_N=$((_CK_N + 1))
	if "$@" > /dev/null 2>&1; then
		printf '  [PASS] %s\n' "$_ck_l"
		return 0
	fi
	_CK_FAIL=$((_CK_FAIL + 1))
	_CK_REPORTED=1
	printf '  [FAIL] %s\n' "$_ck_l"
	_ck_last=""
	for _ck_last do :; done
	printf '  ------------------------------\n'
	if [ -e "$_ck_last" ] || [ -L "$_ck_last" ]; then
		printf '  RESULT: FAIL  (the check above failed; nothing else was checked)\n'
	else
		printf '  RESULT: FAIL  (the file does not exist; nothing else was checked)\n'
	fi
	exit 1
}

# The shell a turn-in script runs under. All three shell subjects say it in
# their general rules -- shell exercises must be executable with /bin/sh -- so
# a script is run as `/bin/sh FILE`: never through its #! line, never with
# bash, and never with whichever `sh` PATH finds first, which would let the
# line ck_run prints name a shell it did not use. A box with no /bin/sh has
# no shell the subjects accept, and the run says so ("not found", status 127).
_CK_SH=/bin/sh
_CK_SHOWN=0
_CK_LAST=""
_CK_RUNS=0

# _ck_word WORD -> WORD the way it would be typed back at a prompt: bare when
# nothing in it is special to the shell, single-quoted otherwise -- and, when it
# holds a byte outside printable ASCII, as runner_lib.sh's rl_shword writes it
# ("$(printf '\ooo')"), which gives the same bytes back and keeps the line
# printable: a control byte inside quotes reached the terminal as it was.
_ck_word() {
	case "$1" in
		*[![:print:]]*)
			if [ -n "$_CK_RL" ]; then
				printf '%s' "$1" | sh -c '. "$1"; rl_shword' shell_check.sh "$_CK_RL"
				return
			fi
			printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
			;;
		"" | *[!A-Za-z0-9_./:,+=@%-]*)
			printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
			;;
		*) printf '%s' "$1" ;;
	esac
}

# _ck_excerpt FILE NAME -> FILE's first five lines under the run it belongs
# to, each path the check passed shown by its name alone (a sandbox path is
# noise to the reader), through runner_lib.sh's rl_excerpt: the one byte
# renderer (a control byte as \xHH, a CRLF line ending as a line ending --
# ssh-keygen writes them), a line longer than RL_EXCERPT_WIDTH cut with a
# marker, and, when anything was left out, a line saying how much and where the
# whole text is kept (test.outputs/NAME). This used to be a copy of its own
# that showed a control byte as '?', cut a line at 160 bytes, and saved
# nothing, so shell_test.sh re-derived its limits to keep the text it dropped.
#
# rl_excerpt runs in a shell of its own: this library is sourced by check
# scripts, whose EXIT trap is the guard above, and runner_lib.sh sets traps
# of its own when it is sourced.
_CK_RL=""
for _ck_l in "${SHELL_CHECK_LIB:+${SHELL_CHECK_LIB%/*}/runner_lib.sh}" \
	"${TEST_SRCDIR:+$TEST_SRCDIR/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh}"; do
	if [ -n "$_ck_l" ] && [ -f "$_ck_l" ]; then
		# Absolute: a check script may cd before it reports a run.
		_CK_RL=$(cd "${_ck_l%/*}" && pwd)/${_ck_l##*/}
		break
	fi
done
# _ck_vis VALUE -> VALUE as rl_vis arg renders it (THE ONE BYTE RENDERER), for
# ck_eq; in a shell of its own, for the reason _ck_excerpt gives below.
_ck_vis() {
	if [ -z "$_CK_RL" ]; then
		echo "shell_check.sh: tools/runner_lib.sh is not beside it or in this test's data," >&2
		echo "                so the values ck_eq compared could not be shown." >&2
		_CK_REPORTED=1
		exit 2
	fi
	printf '%s' "$1" | sh -c '. "$1"; rl_vis arg' shell_check.sh "$_CK_RL"
}
_ck_excerpt() {
	if [ -z "$_CK_RL" ]; then
		echo "shell_check.sh: tools/runner_lib.sh is not beside it or in this test's data," >&2
		echo "                so what the run wrote could not be shown." >&2
		# A harness error, not a check script that forgot ck_report.
		_CK_REPORTED=1
		exit 2
	fi
	CK_SUBS=$_ck_subs LC_ALL=C awk '
		BEGIN {
			n = split(ENVIRON["CK_SUBS"], s, "\n")
			for (i = 1; i <= n; i++) {
				t = index(s[i], "\t")
				if (t) { from[i] = substr(s[i], 1, t - 1); to[i] = substr(s[i], t + 1) }
			}
		}
		{
			line = $0
			for (i = 1; i <= n; i++) {
				if (from[i] == "") continue
				out = ""
				while ((p = index(line, from[i])) > 0) {
					out = out substr(line, 1, p - 1) to[i]
					line = substr(line, p + length(from[i]))
				}
				line = out line
			}
			print line
		}' "$1" > "$1.shown"
	sh -c '. "$1"; shift; rl_excerpt "$@"' shell_check.sh "$_CK_RL" \
		"$1.shown" 5 "$2" "         "
	rm -f "$1.shown"
}

# ck_run [-C DIR] [--no-redirect] OUTFILE cmd...  -> run the turn-in, the one
# way every check does. stdout goes to OUTFILE byte for byte, stderr to
# OUTFILE.err (also in $CK_ERR), and the exit status to $CK_RC. -C runs it
# from DIR. Where the exercise declares a redirect (see ck_redirected), the
# run reads the fixture when it opens the redirected path; --no-redirect runs
# it on the machine's own file instead. How it ended
# goes to $CK_HOW, the line tools/exit_status wrote ("exit 3", "signal 11",
# "noexec WHY"; empty when the helper was itself stopped from outside), for a
# caller that judges the ending: shell_test.sh's diff --run reads it with
# runner_lib.sh's rl_classify, as every runner reads the runs it makes.
#
# The run's stdin is /dev/null, never the check's. No shell subject hands a
# turn-in input on stdin, and a check that runs it inside a `while read`
# loop over a list of cases (Shell 01 ex08's) would otherwise hand it the
# rest of that list: a program that reads its stdin, for whatever reason,
# swallowed the cases after the first, and the check reported PASS over
# pairs it never ran.
#
# Nothing is judged here: a run registers no check. What it adds is the one
# thing a checklist of properties cannot say, which is what the run itself
# printed on the side. When the status is not 0 or anything reached stderr, a
# short block goes out ABOVE the checks that judge this run: the command, as
# it could be typed back (env assignments first, every path the check passed
# shown by its name), its exit status, and the first lines of its stderr. The
# checks used to send stderr to /dev/null, so a script dash could not run --
# "Bad substitution", "Unterminated quoted string" -- showed only its content
# failures and a hint about something else, while the one line that explained
# them was thrown away.
#
# A word `sh` in command position runs $_CK_SH, /bin/sh, and the first block
# says so: a script that works in a terminal through its #! line (bash) and
# fails here needs to know which shell was used. That block says "as the
# subject requires", which holds for the three shell subjects here (each says
# shell exercises must be executable with /bin/sh), and //tools:conventions
# asks a check that runs `sh` for ck_sh_parses too. A project whose subject
# names another shell, or none, runs its script with that shell's name
# instead, and gets neither claim. A repeat of the same status and stderr is
# one line, so a check that runs the script four times does not print the
# same error four times.
#
# A status alone is never a failure here. Where a subject names one, the check
# compares $CK_RC itself; where it names none, the run contract
# (docs/reference.md) does not grade it at basic.
# How the run ended is read from waitpid(), through tools/exit_status, never
# guessed from $?: a shell reports a death by signal N as 128+N, which is also
# what `exit 255` returns, and the run contract grades a plain return nowhere
# at basic. The helper sits beside this library in a test's runfiles
# (defs.bzl's _test() puts it in every test's data); without it, how a run
# ended cannot be told, so its absence stops the check as a harness error.
_CK_WAITER=""
for _ck_w in "${SHELL_CHECK_LIB:+${SHELL_CHECK_LIB%/*}/exit_status}" \
	"${TEST_SRCDIR:+$TEST_SRCDIR/${TEST_WORKSPACE:-_main}/tools/exit_status}"; do
	if [ -n "$_ck_w" ] && [ -x "$_ck_w" ]; then
		# Absolute: ck_run -C runs the command from another directory.
		_CK_WAITER=$(cd "${_ck_w%/*}" && pwd)/${_ck_w##*/}
		break
	fi
done

ck_run() {
	if [ -z "$_CK_WAITER" ]; then
		echo "shell_check.sh: tools/exit_status is not in this test's data, so how the" >&2
		echo "                run ended could not be told from what it returned." >&2
		# A harness error, not a check script that forgot ck_report.
		_CK_REPORTED=1
		exit 2
	fi
	_ck_cd=""
	_ck_redir=1
	while :; do
		case "${1:-}" in
			-C)
				_ck_cd=$2
				shift 2
				;;
			--no-redirect)
				_ck_redir=0
				shift
				;;
			*) break ;;
		esac
	done
	_ck_out=$1
	shift
	CK_ERR="$_ck_out.err"
	_CK_RUNS=$((_CK_RUNS + 1))
	_ck_shown=""
	_ck_subs=""
	_ck_bysh=0
	# The words before the command: `env`, its flags, and NAME=value
	# assignments. `ck_run OUT FT_X=1 sh "$D"`, the shell's own idiom, arrives
	# here as words, and exec would run FT_X=1 as a program -- status 127,
	# "not found", shown as the student's run. So assignments go to env
	# whether or not the check wrote it, and env is shown, flags and all,
	# whenever a flag follows it.
	_ck_st=start
	_ck_env=0
	_ck_eflags=""
	_ck_new=1
	for _ck_a do
		if [ "$_ck_new" = 1 ]; then
			set --
			_ck_new=0
		fi
		case "$_ck_st" in
			start)
				_ck_st=assign
				if [ "$_ck_a" = env ]; then
					_ck_env=1
					_ck_st=flags
					set -- env
					continue
				fi
				;;
			flagval)
				_ck_st=flags
				_ck_eflags="$_ck_eflags $(_ck_word "$_ck_a")"
				set -- "$@" "$_ck_a"
				continue
				;;
			flags)
				case "$_ck_a" in
					-u | -C | -S) _ck_st=flagval ;;
					--) _ck_st=assign ;;
					-*) ;;
					*) _ck_st=assign ;;
				esac
				if [ "$_ck_st" != assign ] || [ "$_ck_a" = -- ]; then
					_ck_eflags="$_ck_eflags $(_ck_word "$_ck_a")"
					set -- "$@" "$_ck_a"
					continue
				fi
				;;
		esac
		if [ "$_ck_st" = assign ]; then
			case "${_ck_a%%=*}" in
				"$_ck_a" | "" | [!A-Za-z_]* | *[!A-Za-z0-9_]*) ;;
				*)
					if [ "$_ck_env" = 0 ]; then
						_ck_env=1
						set -- env
					fi
					_ck_shown="$_ck_shown ${_ck_a%%=*}=$(_ck_word "${_ck_a#*=}")"
					set -- "$@" "$_ck_a"
					continue
					;;
			esac
			_ck_st=args
			if [ "$_ck_a" = sh ] || [ "$_ck_a" = /bin/sh ]; then
				_ck_bysh=1
				_ck_shown="$_ck_shown sh"
				set -- "$@" "$_CK_SH"
				continue
			fi
		fi
		case "$_ck_a" in
			*/*)
				if [ -e "$_ck_a" ]; then
					_ck_b=${_ck_a%/}
					_ck_b=${_ck_b##*/}
					_ck_shown="$_ck_shown $(_ck_word "$_ck_b")"
					_ck_subs="$_ck_subs$_ck_a	$_ck_b
"
					set -- "$@" "$_ck_a"
					continue
				fi
				;;
		esac
		_ck_shown="$_ck_shown $(_ck_word "$_ck_a")"
		set -- "$@" "$_ck_a"
	done
	_ck_shown=${_ck_shown# }
	[ -z "$_ck_eflags" ] || _ck_shown="env$_ck_eflags${_ck_shown:+ $_ck_shown}"
	# The redirect, loaded into the run and into nothing else: the library's
	# name goes on the command line the helper execs, never into the check's
	# own environment, so the check's grep and the oracle read the real file.
	# It is not part of the command as shown, which is the student's; the
	# block below says it on a line of its own.
	_ck_via=""
	if [ "$_ck_redir" = 1 ] && ck_redirected; then
		set -- env "LD_PRELOAD=$CK_REDIRECT_LIB" "$@"
		_ck_via="$CK_REDIRECT_FROM was ${CK_REDIRECT_NAME:-$CK_REDIRECT_TO}"
	fi
	# Absolute: with -C the helper writes it from DIR.
	case "$_ck_out" in
		/*) _ck_how="$_ck_out.how" ;;
		*) _ck_how="$PWD/$_ck_out.how" ;;
	esac
	rm -f "$_ck_how"
	(
		if [ -n "$_ck_cd" ]; then
			cd "$_ck_cd" || exit 125
		fi
		exec "$_CK_WAITER" "$_ck_how" "$@"
	) < /dev/null > "$_ck_out" 2> "$CK_ERR"
	CK_RC=$?
	_ck_ended=""
	_ck_n=""
	CK_HOW=""
	if [ -f "$_ck_how" ]; then
		read -r _ck_ended _ck_n < "$_ck_how"
		rm -f "$_ck_how"
		# shellcheck disable=SC2034 # CK_HOW is the caller's to read.
		[ -z "$_ck_ended" ] || CK_HOW="$_ck_ended $_ck_n"
	fi
	if [ "$CK_RC" -eq 0 ] && [ ! -s "$CK_ERR" ]; then
		return 0
	fi
	_ck_key="$CK_RC:$(head -n 20 "$CK_ERR" | cut -c1-300)"
	if [ "$_ck_key" = "$_CK_LAST" ]; then
		printf '  ran: %s  (the same exit status and stderr as above)\n' "$_ck_shown"
		return 0
	fi
	_CK_LAST=$_ck_key
	if [ "$_ck_bysh" = 1 ] && [ "$_CK_SHOWN" = 0 ]; then
		printf '  ran: %s  (/bin/sh, as the subject requires; not through its #! line)\n' \
			"$_ck_shown"
	else
		printf '  ran: %s\n' "$_ck_shown"
	fi
	_CK_SHOWN=1
	[ -z "$_ck_via" ] || printf '       (%s)\n' "$_ck_via"
	case "$_ck_ended" in
		exit) printf '       exit status %d\n' "$_ck_n" ;;
		signal) printf '       killed by signal %d\n' "$_ck_n" ;;
		noexec) printf '       could not be started: %s\n' "$_ck_n" ;;
		*) printf '       stopped from outside before it ended (status %d)\n' "$CK_RC" ;;
	esac
	if [ -s "$CK_ERR" ]; then
		printf '       stderr:\n'
		_ck_excerpt "$CK_ERR" "run-$_CK_RUNS-stderr.txt"
	else
		printf '       stderr: nothing\n'
	fi
	return 0
}

# ck_redirected  -> whether this check's runs read a fixture in place of a
# path the turn-in opens, and so whether ck_run applies it.
#
# An exercise whose program reads a fixed path -- Shell 01 ex07's
# /etc/passwd -- can declare `redirect` on its shell_exercise call. Its runner
# (shell_test.sh) then proves the redirect works on this machine, by reading
# the path through it, and only then exports CK_REDIRECT_LIB (the preload
# library, tools/path_redirect.c), CK_REDIRECT_FROM (the path),
# CK_REDIRECT_TO (the fixture) and CK_REDIRECT_NAME (the fixture as the
# repository names it). Where the proof failed it exports CK_REDIRECT_BROKEN,
# which says why, and a check says so with ck_skipped for each property only
# the fixture can show: this machine's file is all the run can read.
ck_redirected() {
	[ -n "${CK_REDIRECT_LIB:-}" ] && [ -n "${CK_REDIRECT_FROM:-}" ] &&
		[ -n "${CK_REDIRECT_TO:-}" ]
}

# ck_detail LINE...  -> each LINE under the check line above it, indented as
# everything the library prints under a check is, through _ck_excerpt (the
# one renderer and the one cut, runner_lib.sh's rl_excerpt): a control byte
# as \xHH, a line longer than RL_EXCERPT_WIDTH cut with a marker, five lines
# at most and a count of the rest. For what a failure has to name -- the
# student's own line it refused, the input that was used -- and never for an
# expected value, which is the answer.
#
# What had to be cut is kept whole, where a Bazel test keeps its outputs
# (bazel-testlogs/<package>/<target>/test.outputs/check-detail-N.txt), and the
# last line says where: an input too long for the log is still one a student
# has to be able to paste back. Run by hand there is no such place, and it says
# so rather than naming a path that does not exist. This was a cut and a copy
# of its own (160 bytes, its own "(in full: ...)" line) until _ck_excerpt went
# through rl_excerpt, which cuts, counts and keeps for every excerpt alike.
_CK_DETAILS=0
ck_detail() {
	_ck_subs=""
	_ck_d=$(mktemp) || return 0
	printf '%s\n' "$@" > "$_ck_d"
	_CK_DETAILS=$((_CK_DETAILS + 1))
	_ck_excerpt "$_ck_d" "check-detail-$_CK_DETAILS.txt"
	rm -f "$_ck_d"
}

# ck_quote WORD  -> WORD as it would be typed back at a prompt: bare when
# nothing in it is special to the shell, single-quoted otherwise. For a
# replay line under a failure (ck_detail), so an input full of quotes and
# backslashes can be pasted and run as it was.
ck_quote() {
	_ck_word "$1"
}

# ck_sh_parses <file>  -> PASS when /bin/sh can parse <file> (sh -n), with the
# shell's own message under the line when it cannot.
#
# For every shell turn-in that is a script or a command line: the shell
# subjects all require shell exercises to be executable with /bin/sh, and a
# file it cannot parse is not. Its own check rather than something read off a
# run, because dash runs a script line by line: one that prints the right
# names and then dies on an unclosed `if` scored 9/9 while its every run ended
# in "Syntax error". A construct only bash knows at RUN time -- ${v//a/b} --
# parses fine, and is ck_run's stderr block to show.
ck_sh_parses() {
	_CK_N=$((_CK_N + 1))
	_ck_n=${1##*/}
	if [ ! -f "$1" ]; then
		printf '  [FAIL] %s parses under /bin/sh (no file to read)\n' "$_ck_n"
		_CK_FAIL=$((_CK_FAIL + 1))
		return 0
	fi
	_ck_msg=$("$_CK_SH" -n "$1" 2>&1)
	if [ $? -eq 0 ]; then
		printf '  [PASS] %s parses under /bin/sh (sh -n)\n' "$_ck_n"
		return 0
	fi
	_CK_FAIL=$((_CK_FAIL + 1))
	printf '  [FAIL] %s parses under /bin/sh (sh -n)\n' "$_ck_n"
	_ck_subs="$1	$_ck_n
"
	_ck_pf=$(mktemp) || { echo "shell_check.sh: cannot create a scratch file" >&2; exit 2; }
	printf '%s\n' "$_ck_msg" > "$_ck_pf"
	_ck_excerpt "$_ck_pf" "parse-$_CK_N-stderr.txt"
	rm -f "$_ck_pf"
	printf '         hint: sh -n %s shows the same. Is that line POSIX sh, or something only bash accepts (man dash)?\n' "$_ck_n"
}

# Trailing-newline assertions. The Moulinette compares stdout byte-for-byte, so a
# stray (or missing) final newline is a real KO the shell-stripping `$(...)` capture
# is blind to. Capture the deliverable's RAW output to a file with ck_run first:
#     raw=$(mktemp); ck_run "$raw" sh "$D"; out=$(cat "$raw")
# then assert the required terminator on "$raw", and anything line-based on
# "$out" -- one run, two views of it. Whether a final newline is required is a
# SPEC property (from the subject's example), not the answer, so this reveals
# nothing.
_ck_lastbyte() { [ -s "$1" ] && tail -c1 "$1" | od -An -tx1 | tr -d ' \n'; }

# ck_no_final_newline "<requirement>" <file>  -> PASS if <file> is non-empty and its
# last byte is NOT a newline (output ends exactly at its last visible char).
ck_no_final_newline() {
	_CK_N=$((_CK_N + 1))
	if [ -s "$2" ] && [ "$(_ck_lastbyte "$2")" != "0a" ]; then
		printf '  [PASS] %s\n' "$1"
	else
		printf '  [FAIL] %s\n' "$1"
		_CK_FAIL=$((_CK_FAIL + 1))
	fi
}

# ck_final_newline "<requirement>" <file>  -> PASS if <file> is non-empty and ends
# with a newline (the normal terminator for line-oriented output).
ck_final_newline() {
	_CK_N=$((_CK_N + 1))
	if [ "$(_ck_lastbyte "$2")" = "0a" ]; then
		printf '  [PASS] %s\n' "$1"
	else
		printf '  [FAIL] %s\n' "$1"
		_CK_FAIL=$((_CK_FAIL + 1))
	fi
}

# ck_executable <file>  -> PASS when <file>'s owner execute bit is set, which
# running it as ./<name> needs.
#
# The rule it serves is written once, in docs/reference.md's run contract: the
# bit is required only where the subject's own example runs the file directly,
# as ./<name>. An example that runs it through bash, or none at all, asks for
# nothing that needs the bit, so no check there may demand it.
# Shell 00 ex05 and ex06 did, at basic, for two scripts their subject runs with
# `bash git_commit.sh`, while every script Shell 01 runs as ./name went
# unchecked.
#
# What it reads is the copy the TEST built, by running the generator in its own
# scratch dir -- never a checked-in file. Bazel keys a cached result on file
# CONTENT, so a mode-only change to a file on disk re-runs nothing: a check that
# read deliverable/'s mode would keep reporting the old one. The generator's
# text is part of the key, and the mode it gives the file follows from that
# text, which is also what //tools:generate and //tools:submit turn in.
#
# The hint is inline, under the line that failed, because the exercise's clue
# printed at the end is about the exercise, not about permissions. A file that
# is not there gets no hint: the line above it already says so, and advice
# about chmod would send the student after the wrong problem.
ck_executable() {
	_CK_N=$((_CK_N + 1))
	_ck_n=${1##*/}
	if [ ! -f "$1" ]; then
		printf '  [FAIL] %s has its execute bit set, so ./%s runs (no file to check)\n' \
			"$_ck_n" "$_ck_n"
		_CK_FAIL=$((_CK_FAIL + 1))
		return 0
	fi
	_ck_x=$(ls -lLd -- "$1" 2>/dev/null | cut -c4)
	case "$_ck_x" in
		x | s)
			printf '  [PASS] %s has its execute bit set, so ./%s runs\n' "$_ck_n" "$_ck_n"
			;;
		*)
			printf '  [FAIL] %s has its execute bit set, so ./%s runs\n' "$_ck_n" "$_ck_n"
			printf '         hint: the subject runs ./%s, which needs the x that ls -l shows; set it in the generator (man chmod)\n' "$_ck_n"
			_CK_FAIL=$((_CK_FAIL + 1))
			;;
	esac
}

# sh_operators <file>  -> the operators in <file> that join one command to the
# next, one per line, read the way the shell reads them: ';', '&&', '||', '|',
# '&', and 'newline' for a second command on a line of its own.
#
# Quoted text, a backslash-escaped character, a comment and a backslash-newline
# continuation are never operators. That is the whole reason this exists rather
# than a grep over the file: `printf '%s\n' a \; b` hands printf a ';' as an
# argument, and joins nothing. The '>' before an '&' or a '|' makes it part of a
# redirection (2>&1, >|), not an operator. A '#' starts a comment only where a
# word could start, so the one inside '#x#' or a\#b is text.
#
# A ';' or '&' counts only once another command follows it: `cmd;` and `cmd &`
# end a single command and join it to nothing. '&&', '||' and '|' cannot end a
# file, so they are reported where they stand.
sh_operators() {
	awk '
	function word() {
		if (pendop != "") print pendop
		else if (pend) print "newline"
		pendop = ""
		pend = 0
		cmd = 1
		inword = 1
	}
	function op(o) {
		if (o == ";" || o == "&") {
			if (cmd) pendop = o
		} else
			print o
		pend = 0
		cmd = 0
		inword = 0
		prev = o
	}
	{
		line = $0 "\n"
		n = length(line)
		for (i = 1; i <= n; i++) {
			c = substr(line, i, 1)
			if (st == "comment") {
				if (c != "\n") continue
				st = ""
			}
			if (st == "single") {
				if (c == "\047") st = ""
				continue
			}
			if (st == "double") {
				if (c == "\\") i++
				else if (c == "\"") st = ""
				continue
			}
			if (c == "\\") {
				if (substr(line, i + 1, 1) != "\n") word()
				i++
				prev = "x"
				continue
			}
			if (c == " " || c == "\t") { inword = 0; prev = c; continue }
			if (c == "\n") {
				if (cmd) pend = 1
				cmd = 0
				inword = 0
				prev = c
				continue
			}
			if (c == "#" && !inword) { st = "comment"; continue }
			if (c == ";") { op(";"); continue }
			if (c == "&" && prev != ">" && prev != "<") {
				if (substr(line, i + 1, 1) == "&") { i++; op("&&") } else op("&")
				continue
			}
			if (c == "|" && prev != ">") {
				if (substr(line, i + 1, 1) == "|") { i++; op("||") } else op("|")
				continue
			}
			word()
			if (c == "\047") st = "single"
			else if (c == "\"") st = "double"
			prev = c
		}
	}' "$1"
}

# ck_no_operator "<requirement>" <file> <op>...  -> PASS when <file> joins no two
# commands with any of the named operators (see sh_operators); a failure names
# the ones it found. A file that is not there is a FAIL: a property nobody could
# observe is not one that held.
ck_no_operator() {
	_ck_l=$1
	_ck_f=$2
	shift 2
	_CK_N=$((_CK_N + 1))
	if [ ! -f "$_ck_f" ]; then
		printf '  [FAIL] %s (no file to read)\n' "$_ck_l"
		_CK_FAIL=$((_CK_FAIL + 1))
		return 0
	fi
	_ck_hit=""
	for _ck_o in $(sh_operators "$_ck_f" | sort -u); do
		for _ck_w in "$@"; do
			[ "$_ck_o" = "$_ck_w" ] || continue
			case "$_ck_o" in
				newline) _ck_hit="$_ck_hit, a second command line" ;;
				*) _ck_hit="$_ck_hit, '$_ck_o'" ;;
			esac
		done
	done
	if [ -z "$_ck_hit" ]; then
		printf '  [PASS] %s\n' "$_ck_l"
	else
		printf '  [FAIL] %s (found %s)\n' "$_ck_l" "${_ck_hit#, }"
		_CK_FAIL=$((_CK_FAIL + 1))
	fi
}

# ck_listed_at "<item>" "<YYYY-MM-DD HH:MM>" <MM-DD> <HH:MM>
#   -> the timestamp an `ls -l` in the subject gives <item>, checked against the
#   date and time `tar -tvf` prints for it. Two properties: the date is <MM-DD>
#   of ANY year, and the time is <HH:MM> -- unless ls -l would show the year in
#   that column instead, which it does for a date more than six months old or in
#   the future. The Shell 00 subjects allow exactly that: "A year will be
#   accepted instead of the time in the file's timestamp." The year itself is
#   never judged: the subject prints none, and pinning one fails a correct
#   archive the following January.
#
# A stamp that is not a date at all is ONE failure, and nothing else. It used to
# be read as the year 0, which is more than six months ago, so every member
# missing from an archive scored a FAIL for its date and then a PASS saying
# "time not graded (ls -l shows the year for this date)" -- a pass about a date
# that did not exist, telling the student their timestamp was old. An empty
# archive earned seven of them. So the stamp is read before anything is judged:
# nothing at all means the member was not found, and anything that is not a
# real YYYY-MM-DD HH:MM is shown as it came, since the member IS there and a
# "not in the archive" would send the student after the wrong problem.
_ck_stamp_ok() {  # _ck_stamp_ok "YYYY-MM-DD HH:MM" -> 0 when it is one
	case "$1" in
		[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\ [0-9][0-9]:[0-9][0-9]) ;;
		*) return 1 ;;
	esac
	_ck_x=${1#*-}
	case "${_ck_x%%-*}" in 0[1-9] | 1[0-2]) ;; *) return 1 ;; esac
	_ck_x=${1#*-*-}
	case "${_ck_x%% *}" in 0[1-9] | [12][0-9] | 3[01]) ;; *) return 1 ;; esac
	_ck_x=${1#* }
	case "${_ck_x%%:*}" in [01][0-9] | 2[0-3]) ;; *) return 1 ;; esac
	case "${_ck_x#*:}" in [0-5][0-9]) ;; *) return 1 ;; esac
	return 0
}
ck_listed_at() {
	if ! _ck_stamp_ok "$2"; then
		_CK_N=$((_CK_N + 1))
		_CK_FAIL=$((_CK_FAIL + 1))
		if [ -z "$(printf '%s' "$2" | tr -d ' \t')" ]; then
			printf '  [FAIL] %s: no date to read -- is it in the archive under that name?\n' "$1"
		else
			printf "  [FAIL] %s: no date to read in tar's listing: got '%s', not YYYY-MM-DD HH:MM\n" \
				"$1" "$2"
		fi
		return 0
	fi
	_ck_d=${2% *}
	_ck_t=${2#* }
	ck_eq "$1: dated $3 (month-day, any year)" "${_ck_d#*-}" "$3"
	# Leading zeros are stripped because shell arithmetic reads 08 and 09 as
	# broken octal -- and a year such as 0999 the same way.
	_ck_y=${_ck_d%%-*}
	_ck_y=${_ck_y#"${_ck_y%%[!0]*}"}
	_ck_m=${3%-*}
	_ck_nm=$(date +%m)
	# Months from the listed date to now.
	_ck_age=$(( ($(date +%Y) * 12 + ${_ck_nm#0}) - (${_ck_y:-0} * 12 + ${_ck_m#0}) ))
	if [ "$_ck_age" -ge 6 ] || [ "$_ck_age" -lt 0 ]; then
		ck "$1: time not graded (ls -l shows the year for this date)" true
	else
		ck_eq "$1: listed at $4" "$_ck_t" "$4"
	fi
}

# ck_wording KEY  -> sets CK_WORDING to the subject's own words for KEY, as the
# exercise's shell_exercise call quotes them (its `wording`, which reaches
# here as $SHELL_CHECK_WORDING_<KEY>).
#
# One check script serves two projects when one repeats the other's exercise
# (twin_of), and the two subjects can word the same sentence differently:
# Shell 01 ex02 says "all files ending with .sh", Piscine Reloaded ex03 "all
# file names that end with ".sh"". A check that names the sentence it reads
# quotes the one this student's subject says, never the other project's. A
# call that does not give the words is a wiring error (exit 2), never a
# check that quotes nothing.
ck_wording() {
	CK_WORDING=""
	case "${1:-}" in
		"" | [!A-Za-z_]* | *[!A-Za-z0-9_]*)
			_CK_REPORTED=1
			printf '  BROKEN CHECK SCRIPT: ck_wording takes a key, a name made of\n'
			printf '  letters, digits and _, got "%s".\n' "${1:-}"
			exit 2 ;;
	esac
	eval "CK_WORDING=\${SHELL_CHECK_WORDING_$1:-}"
	if [ -z "$CK_WORDING" ]; then
		_CK_REPORTED=1
		printf '  BROKEN CHECK SCRIPT: it quotes the subject'"'"'s words for "%s", and\n' "$1"
		printf '  this exercise'"'"'s shell_exercise call gives none: add\n'
		printf '  wording = {"%s": "<the sentence, as the subject says it>"}\n' "$1"
		printf '  to it (tools/defs.bzl).\n'
		exit 2
	fi
}

# ck_stable "<requirement>" <file>  -> PASS when a second run of the generator,
# in another empty directory, under an empty HOME and TMPDIR of its own,
# wrote <file> byte for byte the same.
#
# A shell exercise's turn-in is written by its generator, and the generator
# runs again on every generate and every submit. So where the subject fixes
# the turn-in byte for byte, one that comes out different each time is never
# the file that was tested. shell_test.sh makes
# the second run when the exercise's shell_exercise call says stable = True,
# and names its directory in $SHELL_CHECK_RERUN; <file> is looked for there
# under the same name. Without that directory nothing can be compared, which
# is a wiring error (exit 2), never a pass. The failure says the two runs
# differ, and not what to do about it.
_CK_STABLE=0
ck_stable() {
	_CK_STABLE=1
	if [ -z "${SHELL_CHECK_RERUN:-}" ] || [ ! -d "$SHELL_CHECK_RERUN" ]; then
		_CK_REPORTED=1
		printf '  BROKEN CHECK SCRIPT: ck_stable needs a second run of the generator,\n'
		printf '  and there is none: give this exercise'"'"'s shell_exercise call\n'
		printf '  stable = True (tools/defs.bzl), which makes it.\n'
		exit 2
	fi
	_CK_N=$((_CK_N + 1))
	_ck_b=${2##*/}
	if [ ! -f "$SHELL_CHECK_RERUN/$_ck_b" ]; then
		printf '  [FAIL] %s (the second run wrote no %s)\n' "$1" "$_ck_b"
		_CK_FAIL=$((_CK_FAIL + 1))
	elif cmp -s "$2" "$SHELL_CHECK_RERUN/$_ck_b"; then
		printf '  [PASS] %s\n' "$1"
	else
		printf '  [FAIL] %s (two runs of the generator wrote two different %s)\n' "$1" "$_ck_b"
		_CK_FAIL=$((_CK_FAIL + 1))
	fi
}

# ck_report  -> print the summary line and exit (0 if all checks passed, else 1).
#
# The skip count rides on the same line rather than being left above it: a
# result that says PASS and nothing else is read as "everything held", and a
# `[SKIP]` twenty lines earlier does not travel with it. See ck_skipped.
ck_report() {
	_CK_REPORTED=1
	_ck_note=""
	[ "$_CK_SKIP" -eq 0 ] || _ck_note=", $_CK_SKIP skipped"
	printf '  ------------------------------\n'
	# NOTHING REGISTERED IS NOT A PASS. This branched on _CK_FAIL alone, so a
	# check script that reached here having called no ck at all printed
	# "RESULT: PASS (0/0 checks)" and exited 0 -- a green bought by an empty
	# loop, a `for` over a glob that matched nothing, or an early `return` in a
	# helper. Every sibling runner in this repo has the same floor for the same
	# reason (rust_diff.sh's MIN_DIFF_CASES, bsq_check.sh, rush02_check.sh,
	# argv_check.sh, file_check.sh); this library backs all 17 check scripts and
	# had none.
	#
	# Exit 2, not 1: nothing was checked, so this says the harness is broken
	# rather than that the exercise is wrong -- the same code every runner here
	# reserves for that. A script that deliberately checks nothing has ck_skip
	# and ck_skipped to say so, and both are counted below, so this cannot fire
	# on a skip that was declared.
	# A second run was made for this check to compare (stable = True), and
	# it compared nothing: the exercise's stability went unchecked while its
	# call says it is. Wiring, like the case below, so exit 2 -- but only on
	# a checklist that would otherwise pass. One that already failed, and
	# reached here early, before its ck_stable line, is red as it stands:
	# calling it broken would hide the FAIL lines above.
	if [ -n "${SHELL_CHECK_RERUN:-}" ] && [ "$_CK_STABLE" = 0 ] && [ "$_CK_FAIL" -eq 0 ]; then
		printf '  BROKEN CHECK SCRIPT: its shell_exercise call says stable = True, and\n'
		printf '  it never calls ck_stable, so the second run of the generator was\n'
		printf '  compared with nothing. Call ck_stable on the turn-in.\n'
		exit 2
	fi
	if [ "$_CK_N" -eq 0 ] && [ "$_CK_SKIP" -eq 0 ]; then
		printf '  BROKEN CHECK SCRIPT: it registered no checks at all.\n'
		printf '  ck_report was reached with nothing to report, which is not a\n'
		printf '  pass -- it is a script that checked nothing and would have said\n'
		printf '  PASS (0/0). If there is genuinely nothing to check here, say so\n'
		printf '  with ck_skip (whole exercise) or ck_skipped (one property).\n'
		exit 2
	fi
	if [ "$_CK_FAIL" -eq 0 ]; then
		printf '  RESULT: PASS  (%d/%d checks%s)\n' "$_CK_N" "$_CK_N" "$_ck_note"
		exit 0
	fi
	printf '  RESULT: FAIL  (%d/%d checks passed%s)\n' \
		"$((_CK_N - _CK_FAIL))" "$_CK_N" "$_ck_note"
	exit 1
}
