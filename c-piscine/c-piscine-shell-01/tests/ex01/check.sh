#!/bin/sh
# ex01 — print_groups.sh prints the groups of the user in $FT_USER, comma-separated,
# with no trailing newline. User-agnostic: we drive it with the CURRENT user, so
# this works whatever the container user is named (and on a real 42 machine).
#
# WHERE THE EXPECTED VALUE COMES FROM. A user's groups live in the machine's user
# database (/etc/group here, LDAP on a campus box), so no fixture can fix them in
# advance. This check used to compute them with the very pipeline the exercise
# asks for, which put the answer in a file the public template ships. The
# reference is now //oracle's `shell01_groups`: the same glibc lookups `id`
# makes, in Rust, so no shell pipeline in the template computes the expected
# list. The comparison stays a plain pass/fail and never prints the list.
#
# WHY A SECOND USER IS DRIVEN BELOW. Every assertion here used to run with
# FT_USER set to $(id -un) — the current user, which is exactly the value the
# tools involved default to when they are given no user at all. That made this
# fixture blind to the one thing the exercise is about: a deliverable that never
# references $FT_USER, and simply prints the groups of whoever is running it,
# passed 5/5. A fixture whose value equals the code's implicit default cannot
# observe whether the code read anything — which generalises well past shell, and
# is worth stating plainly for anyone extending this suite.
#
# The remedy is the subject's own second worked example: it shows FT_USER=daemon,
# a user that exists unprivileged on any Debian/Ubuntu 42 box, precisely to make
# the point that the variable is an INPUT. We do not hardcode the group list the
# subject prints for it — /etc/group differs per machine, and a worked example's
# output is not ours to write down in clear anyway (see ex08's header for the
# same rule) — we ask the oracle for it too, and we only assert it if such a user
# exists AND its group list actually differs from the current user's. Both
# guards keep this from red-ing a correct deliverable on a machine that
# happens not to have one.
#
# AND WHY ONE OF THE USERS NEEDS TWO GROUPS. A list of one group has no comma
# in it, so on a machine where every user tried is in one group -- the dev
# container was, until its image put `student` in two more -- a program that
# printed the primary group alone, or joined names with anything at all,
# passed (finding 025). So the second user is one in two groups or more where
# the machine has one: //oracle's shell01_multigroup names the first such user
# in the user database, ahead of the fixed candidates below. Whether the join
# was seen is a fact about the users, read from the oracle's lists before the
# program runs; where it was not, the check says so with ck_skipped, which
# NO_SKIP=1 turns red: nothing checked the comma.
# shellcheck source=../../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

D=${1:-print_groups.sh}
printf "  CHECK: %s\n" "$D"

ck_require "print_groups.sh exists" test -f "$D"
# The subject's example runs it as ./print_groups.sh, so its execute bit is required
# (docs/reference.md, "Run contract").
ck_executable "$D"
# The subject: shell exercises must be executable with /bin/sh.
ck_sh_parses "$D"

u=$(id -un)
ORACLE=${ORACLE:?this check needs //oracle: declare the exercise with oracle = True}

# One run, two views: the raw bytes (with any trailing newline) and the
# shell-stripped form of them.
raw=$(mktemp)
ck_run "$raw" env FT_USER="$u" sh "$D"
out=$(cat "$raw")

# 1) It must actually print something.
ck "prints non-empty output" test -n "$out"

# 2) No trailing newline, on output that exists: a comparison of lengths passed
#    on no output at all, which has no trailing newline because it has nothing.
ck_no_final_newline "no trailing newline" "$raw"

# 3) Group names are joined by commas only — never spaces. Seen only in output
#    that exists: printing nothing is not joining with commas.
ck "no spaces in the output (comma-joined, not space-joined)" \
	sh -c '[ -n "$1" ] && case "$1" in *" "*) exit 1;; *) exit 0;; esac' _ "$out"

# 4) The names printed must be exactly this user's groups, in the order `id`
#    gives them. The reference is the oracle's; a plain pass/fail, never printed.
want=$("$ORACLE" shell01_groups "$u")
ck "lists exactly the user's groups, by name, in order" test "$out" = "$want"

# 5) $FT_USER is actually READ. Drive a DIFFERENT user and require the output to
#    follow. Candidates are the first user in two groups or more the user
#    database has, then the standard unprivileged system accounts every
#    Debian/Ubuntu box ships (the subject names `daemon` itself). A candidate
#    whose list is the current user's is skipped, being just as blind as $u;
#    of the rest, the first in two groups or more is taken, else the first.
#    The walk of the user database is asked only when the current user is in
#    one group: a campus box may enumerate a directory service behind it, and
#    a list with a comma in it has already been seen above.
alt=""
altwant=""
multi=""
case "$want" in
	*,*) ;;
	*) multi=$("$ORACLE" shell01_multigroup "$u" 2>/dev/null) ;;
esac
for cand in $multi daemon bin sys nobody mail games; do
	[ "$cand" = "$u" ] && continue
	# An unknown user makes the oracle print nothing (and exit 1).
	cw=$("$ORACLE" shell01_groups "$cand" 2>/dev/null)
	[ -n "$cw" ] || continue
	[ "$cw" = "$want" ] && continue
	if [ -z "$alt" ]; then
		alt=$cand
		altwant=$cw
	fi
	case "$cw" in
		*,*)
			alt=$cand
			altwant=$cw
			break
			;;
	esac
done

if [ -n "$alt" ]; then
	ck_run "$raw" env FT_USER="$alt" sh "$D"
	altout=$(cat "$raw")
	ck "reads \$FT_USER: a different user yields THAT user's groups (tried '$alt')" \
		test "$altout" = "$altwant"
else
	# Not a failure: on a host with no second account we simply cannot observe
	# this property. Say so out loud — a check that quietly stops checking is
	# how a hole like this one gets built in the first place. ck_skipped rather
	# than a bare printf, so it reaches the RESULT line and NO_SKIP=1 can force
	# it; the candidate list above is read from the host's user database, so
	# this is keyed off the host and not off anything the deliverable printed.
	ck_skipped "no second local user with a distinct group list — cannot observe that \$FT_USER is read"
fi

# 6) The comma join was seen only if one of the lists compared above holds two
#    groups. Read from the oracle's lists, never from what the program printed.
case "$want,$altwant" in
	*,*,*) ;;
	*)
		ck_skipped "cannot observe the comma join: every user tried has one group on this machine (${u}${alt:+, $alt}), so a list of one group was all there was to print"
		;;
esac

rm -f "$raw" "$raw.err"
ck_report
