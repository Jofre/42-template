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
# makes, in Rust, which a curious student may read and cannot paste (AGENTS.md
# §0 and §2). The comparison stays a plain pass/fail and never prints the list.
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
# exists AND its group list actually differs from the current user's. Both guards keep this from red-ing a correct deliverable on
# a machine that happens not to have one.
# shellcheck source=../../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

D=${1:-print_groups.sh}
printf "  CHECK: %s\n" "$D"

ck "print_groups.sh exists" test -f "$D"

u=$(id -un)

# Capture raw bytes (with any trailing newline) and the shell-stripped form.
raw=$(mktemp)
FT_USER="$u" sh "$D" > "$raw" 2>/dev/null
out=$(FT_USER="$u" sh "$D" 2>/dev/null)

# 1) It must actually print something.
ck "prints non-empty output" test -n "$out"

# 2) No trailing newline: raw byte count equals the stripped length
#    (a trailing newline would make raw one byte longer).
raw_len=$(wc -c < "$raw" | tr -d ' ')
out_len=$(printf '%s' "$out" | wc -c | tr -d ' ')
ck "no trailing newline" test "$raw_len" = "$out_len"

# 3) Group names are joined by commas only — never spaces.
ck "no spaces in the output (comma-joined, not space-joined)" \
	sh -c 'case "$1" in *" "*) exit 1;; *) exit 0;; esac' _ "$out"

# 4) The names printed must be exactly this user's groups, in the order `id`
#    gives them. The reference is the oracle's; a plain pass/fail, never printed.
ORACLE=${ORACLE:?this check needs //oracle: declare the exercise with oracle = True}
want=$("$ORACLE" shell01_groups "$u")
ck "lists exactly the user's groups, by name, in order" test "$out" = "$want"

# 5) $FT_USER is actually READ. Drive a DIFFERENT user and require the output to
#    follow. Candidates are the standard unprivileged system accounts every
#    Debian/Ubuntu box ships (the subject names `daemon` itself); we take the
#    first that exists and whose group list differs from the current user's,
#    because a candidate with an identical list would be just as blind as $u.
alt=""
altwant=""
for cand in daemon bin sys nobody mail games; do
	[ "$cand" = "$u" ] && continue
	# An unknown user makes the oracle print nothing (and exit 1).
	cw=$("$ORACLE" shell01_groups "$cand" 2>/dev/null)
	[ -n "$cw" ] || continue
	[ "$cw" = "$want" ] && continue
	alt=$cand
	altwant=$cw
	break
done

if [ -n "$alt" ]; then
	altout=$(FT_USER="$alt" sh "$D" 2>/dev/null)
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

rm -f "$raw"
ck_report
