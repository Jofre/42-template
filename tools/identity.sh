#!/bin/sh
# identity.sh -- the one writer of your 42 identity: the "42header.username"
# and "42header.email" keys of .vscode/settings.json, which the kube.42header
# VS Code extension, tools/gen_header.sh and tools/submit.sh read, and this
# checkout's local git identity. tools/init.sh and `42 config set login|email`
# both write through it, so the two cannot write the file two ways.
#
# Usage, run from anywhere (the checkout is BUILD_WORKSPACE_DIRECTORY, else the
# folder above this file), KIND being login or email, each named once at most:
#   sh tools/identity.sh check KIND VALUE [KIND VALUE]   all that set does but
#                                                        write: can each VALUE
#                                                        be stored, in the file
#                                                        as it is now?
#   sh tools/identity.sh set KIND VALUE [KIND VALUE]     check them, then store
#                                                        them, all or none
#
# Exit 0 when they are stored (or would be, for check). 1 when a value is
# refused, or a write failed (and what it had changed was put back, or it
# says how to). 3 when the values are fine and nothing was written:
# .vscode/settings.json cannot take them as it is now (a shape this script
# does not rewrite, a file it cannot read), or its new contents could not be
# prepared. 2 for a call it does not take, or a tool missing from PATH. 128
# and a signal's number when that signal (HUP, INT, TERM) stopped it, after
# it put back what it had changed. Why is on stderr.
#
# All or none, because tools/init.sh sets both kinds in one call: it set the
# new login, then could not set the email (a file shape the rewrite refuses,
# a git config behind a stale lock), and left the new login beside the old
# email. So each value is checked against the file before anything is
# written; the git identity is set before the file, so that a git config
# that fails has changed nothing; and a write that fails after that, or a
# signal that stops it anywhere, puts back what was set before it, and says
# what it could not put back, never "nothing was changed".
#
# A value goes in between the quotes of a JSON string, and on the "By:" line
# of every 42 header, so it is refused when it could not be stored as it was
# typed: a `"` ends the string early, a `\` starts an escape, and a blank
# lands in every header. A login is letters, digits, '.', '_' and '-'; an
# email is a name, one '@', and a domain with a dot in it, none of them
# holding a blank, a '"' or a '\'. tools/init.sh used to write `a"b` as it
# came, and left a settings.json no JSON reader could open.

set -u
# Bytes, in every locale. Under UTF-8, grep's and sed's '.' stops at a byte
# that is no UTF-8 and [[:space:]] takes every Unicode blank, so a file with
# a Latin-1 comment was refused here, for a reason it did not have, and
# rewritten under C.
LC_ALL=C
export LC_ALL

# The external commands this script takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says nothing was
# checked rather than that a value was refused.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "identity.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk cat cmp dirname git grep head mkdir mktemp od rm sed tr

WS="${BUILD_WORKSPACE_DIRECTORY:-$(cd "$(dirname "$0")/.." && pwd)}"
SETTINGS="$WS/.vscode/settings.json"

usage() {
	echo "usage: sh tools/identity.sh check|set login|email VALUE [login|email VALUE]" >&2
	exit 2
}
[ $# -eq 3 ] || [ $# -eq 5 ] || usage
ACTION=$1
shift
case "$ACTION" in
	check | set) ;;
	*) usage ;;
esac
# The pairs in the order given: KIND1 VALUE1, and KIND2 VALUE2 when there are two.
KIND1=$1 VALUE1=$2 KIND2='' VALUE2=''
[ $# -eq 4 ] && { KIND2=$3; VALUE2=$4; }
for _k in "$KIND1" ${KIND2:+"$KIND2"}; do
	case "$_k" in
		login | email) ;;
		*) usage ;;
	esac
done
[ "$KIND1" != "$KIND2" ] || usage

# check_value KIND VALUE: exit status 0 when VALUE is a KIND this file stores.
check_value() {
	case "$2" in
		"")
			echo "identity.sh: your 42 $1 cannot be empty." >&2
			return 1 ;;
		*[!A-Za-z0-9._@+-]*)
			echo "identity.sh: '$2' holds a character a 42 $1 does not have." >&2
			echo "  A login is letters, digits, '.', '_' and '-'; an email adds one '@'" >&2
			echo "  (and '+'). A blank, a '\"' or a '\\' could not be stored as typed." >&2
			return 1 ;;
	esac
	if [ "$1" = login ]; then
		case "$2" in
			*[@+]*)
				echo "identity.sh: '$2' looks like an email; your 42 login is the name" >&2
				echo "  before the '@' (jdoe, not jdoe@student.42campus.fr)." >&2
				return 1 ;;
		esac
		return 0
	fi
	case "$2" in
		*@*@*) ;;
		?*@?*.?*) return 0 ;;
	esac
	echo "identity.sh: '$2' does not look like an email address (name@domain.tld)." >&2
	return 1
}

check_value "$KIND1" "$VALUE1" || exit 1
[ -z "$KIND2" ] || check_value "$KIND2" "$VALUE2" || exit 1

# pair KIND VALUE: the names one value is written under. The member whole,
# the key alone as grep reads it, and the git key.
pair() {
	case "$1" in
		login) KEY=username GIT_KEY=user.name ;;
		email) KEY=email GIT_KEY=user.email ;;
	esac
	VALUE=$2
	MEMBER="\"42header.$KEY\": \"$VALUE\""
	TAG="\"42header\\.$KEY\""
}

# drop: remove this run's temporary files.
drop() {
	for _f in "${tmp1:-}" "${tmp2:-}" "${orig:-}"; do
		[ -z "$_f" ] || rm -f "$_f"
	done
}

# sq TEXT: TEXT for between single quotes, each ' in it as '\''.
sq() { printf '%s' "$1" | sed "s/'/'\\\\''/g"; }

# What this run has changed, for give_up to put back. GIT1 and GIT2 are the
# git keys set, each with HAD (1 when it had a value) and OLD (that value),
# noted before git runs. WRITING is 1 once settings.json is being written,
# and $orig holds what it held (none when there was no file). What cannot be
# put back joins NOTES, and the command that would put it back joins CMDS.
GIT1='' GIT2='' WRITING=0 orig='' tmp1='' tmp2='' NOTES='' CMDS=''

# put_back GIT_KEY HAD OLD: that key as it was, unless it is so already (a
# git that failed may have written nothing).
put_back() {
	_now=$(git -C "$WS" config --local --get "$1")
	_rc=$?
	if [ "$2" = 1 ]; then
		[ "$_rc" = 0 ] && [ "$_now" = "$3" ] && return 0
		git -C "$WS" config --local "$1" "$3" && return 0
		CMDS="$CMDS
    git -C '$(sq "$WS")' config --local $1 '$(sq "$3")'"
	else
		[ "$_rc" = 1 ] && return 0
		git -C "$WS" config --local --unset "$1" && return 0
		CMDS="$CMDS
    git -C '$(sq "$WS")' config --local --unset $1"
	fi
}

# give_up WHY STATUS: put back what this run changed, say what it could not,
# and exit STATUS. A second signal waits until it is done.
give_up() {
	trap '' HUP INT TERM
	[ -z "$GIT2" ] || put_back "$GIT2" "$HAD2" "$OLD2"
	[ -z "$GIT1" ] || put_back "$GIT1" "$HAD1" "$OLD1"
	if [ "$WRITING" = 0 ]; then
		:
	elif [ -n "$orig" ]; then
		# `>` empties the file first, so a write that failed part-way
		# left it cut short.
		if ! cmp -s "$orig" "$SETTINGS" && ! cat "$orig" > "$SETTINGS"; then
			NOTES="$NOTES
  .vscode/settings.json may now be cut short. What it held is in
  $orig."
			CMDS="$CMDS
    cat '$(sq "$orig")' > '$(sq "$SETTINGS")'"
			orig=''
		fi
	elif [ ! -L "$SETTINGS" ]; then
		rm -f "$SETTINGS"
	elif [ -e "$SETTINGS" ]; then
		# A link to a file that was not there yet: the link is the
		# person's, and stays, and the file it now leads to is this run's.
		NOTES="$NOTES
  .vscode/settings.json is a link, and this run made the file it leads to,
  which may be cut short."
	fi
	drop
	if [ -z "$NOTES$CMDS" ]; then
		printf 'identity.sh: %s, so nothing was changed.\n' "$1" >&2
	else
		printf 'identity.sh: %s.\n  Not all it had changed could be put back.%s\n' "$1" "$NOTES" >&2
		[ -z "$CMDS" ] ||
			printf '  Once it can be (is the disk full?), put it back with:%s\n' "$CMDS" >&2
	fi
	exit "$2"
}

# hand_edit WHY...: the file is in a shape this script does not rewrite.
# Nothing is written, and the member is spelled out for the person to put in.
hand_edit() {
	drop
	echo "identity.sh: .vscode/settings.json was left as it was: it" >&2
	for _l in "$@"; do echo "  $_l" >&2; done
	echo "  Set this member in it by hand:  $MEMBER" >&2
	exit 3
}

# count FILE ERE: N, the number of FILE's lines that match ('' counts them
# all, the last one too when no newline ends it). grep says 2 when it cannot
# read the file, which must never read as "no line matches": that is how a
# settings.json this script could not read was once written over with the
# one key, every other setting in it gone.
count() {
	N=$(grep -c -E -- "$2" "$1")
	[ $? -le 1 ] || { echo "identity.sh: could not read $1." >&2; drop; exit 3; }
}

if [ -e "$SETTINGS" ] && { [ ! -f "$SETTINGS" ] || [ ! -r "$SETTINGS" ]; }; then
	echo "identity.sh: cannot read .vscode/settings.json, so it was left as it was." >&2
	exit 3
fi

# rewrite IN OUT: OUT is IN (which may not exist) with the current pair's
# member set. Three shapes are rewritten, and no other. VS Code's
# settings.json allows comments and spreads its members over lines in many
# ways, and a rewrite that guessed at one it did not know reported success
# while the key stayed as it was, or left a file no JSON reader could open:
#   - no file, or an empty object: the member alone;
#   - the key on one line of its own with a plain string value, and a //
#     comment after it at most, and nowhere else: that value replaced;
#   - no key yet, and the object's '{' alone on the file's first line that is
#     neither blank nor a // comment, a // comment after it at most: the
#     member put right after it, with a comma when a member follows (one line
#     opening with '"'), and none when only comments do.
# The value holds no '&', '\' or '|' (check_value), the three characters the
# sed replacement below would read as its own: nothing to escape.
rewrite() {
	if [ -f "$1" ]; then count "$1" '[^[:space:]{}]'; else N=0; fi
	if [ "$N" = 0 ]; then
		printf '{\n  %s\n}\n' "$MEMBER" > "$2"
		return
	fi
	count "$1" "$TAG"
	if [ "$N" != 0 ]; then
		_tags=$N
		count "$1" '^[[:space:]]*'"$TAG"'[[:space:]]*:[[:space:]]*"[^"\]*"[[:space:]]*,?[[:space:]]*(//.*)?$'
		# A // comment holding the key counts: tools/submit.sh and
		# tools/gen_header.sh read the first line that holds it.
		[ "$_tags" = 1 ] ||
			hand_edit "holds \"42header.$KEY\" on more than one line (a // comment" \
				"line counts: 42 submit and the file headers read the first one)."
		[ "$N" = 1 ] ||
			hand_edit "holds \"42header.$KEY\" on a line that is not that member alone, with a" \
				"string value and at most a // comment after it."
		sed "s|^\([[:space:]]*\"42header\.$KEY\"[[:space:]]*:[[:space:]]*\"\)[^\"]*\"|\1$VALUE\"|" \
			"$1" > "$2"
		return
	fi
	_first=$(grep -v -E '^[[:space:]]*(//.*)?$' "$1" | head -n 1 | tr -d ' \t\r')
	case "$_first" in
		"{" | "{//"*) ;;
		*)
			# Saved by an editor that marks UTF-8 with one, the '{'
			# looks alone on its line and is not: say what is there.
			[ "$(head -c 3 "$1" | od -An -tx1 | tr -d ' \n')" = efbbbf ] &&
				hand_edit "starts with a byte-order mark (save it as UTF-8 without one)."
			hand_edit "does not open with its '{' alone on a line (blank and // comment" \
				"lines before it, and a // comment after it, are fine)." ;;
	esac
	count "$1" '^[[:space:]]*"'
	if [ "$N" != 0 ]; then
		_ins="  $MEMBER,"
	else
		count "$1" '^[[:space:]]*([{}][[:space:]]*)?(//.*)?[[:space:]]*$'
		_bare=$N
		count "$1" ''
		[ "$_bare" = "$N" ] || hand_edit "holds a line that is neither a member nor a // comment."
		_ins="  $MEMBER"
	fi
	awk -v ins="$_ins" '!done && /^[ \t]*[{][ \t\r]*(\/\/.*)?$/ { print; print ins; done = 1; next } { print }' \
		"$1" > "$2"
}

# not_prepared: a rewrite that failed for a reason of its own (no space for
# the temporary file, a tool that stopped).
not_prepared() {
	echo "identity.sh: could not prepare the new .vscode/settings.json; it was left as it was." >&2
	drop
	exit 3
}

# read_back KIND VALUE: NEW holds that value the way tools/submit.sh and
# tools/gen_header.sh read it: the first line holding the key, and its value
# between the quotes. A rewrite that did not leave exactly that is not put
# in place, whatever went wrong.
read_back() {
	pair "$1" "$2"
	count "$NEW" "$TAG"
	_got=$(sed -n "s/.*\"42header.$KEY\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$NEW" | head -n 1)
	[ "$N" = 1 ] && [ "$_got" = "$VALUE" ] || hand_edit "could not be rewritten safely."
}

# From the first temporary file on, a signal puts back what was done.
trap 'give_up "stopped by a signal" 129' HUP
trap 'give_up "stopped by a signal" 130' INT
trap 'give_up "stopped by a signal" 143' TERM
tmp1=$(mktemp) || exit 3
pair "$KIND1" "$VALUE1"
rewrite "$SETTINGS" "$tmp1" || not_prepared
NEW=$tmp1
if [ -n "$KIND2" ]; then
	tmp2=$(mktemp) || not_prepared
	pair "$KIND2" "$VALUE2"
	rewrite "$tmp1" "$tmp2" || not_prepared
	NEW=$tmp2
fi
read_back "$KIND1" "$VALUE1"
[ -z "$KIND2" ] || read_back "$KIND2" "$VALUE2"
[ "$ACTION" = set ] || { drop; exit 0; }

# What is there now, to put back if a later step fails: the file's bytes
# ($orig, none when there is no file yet), and each git key's value.
mkdir -p "$WS/.vscode" || { drop; exit 1; }
if [ -f "$SETTINGS" ]; then
	orig=$(mktemp) && cat "$SETTINGS" > "$orig" ||
		{ echo "identity.sh: could not copy .vscode/settings.json aside; nothing was changed." >&2; drop; exit 1; }
fi

# This checkout's local git identity, first: a git config that fails here
# has changed nothing. Your global ~/.gitconfig is left untouched, and
# outside a git work tree there is none to set.
git_set() {  # git_set N KIND VALUE
	pair "$2" "$3"
	_old=$(git -C "$WS" config --local --get "$GIT_KEY")
	case $? in
		0) _had=1 ;;
		1) _had=0 ;;
		*) give_up "could not read this checkout's git $GIT_KEY" 1 ;;
	esac
	# Noted before git runs: a signal that stops it once it has written
	# still has the key put back.
	if [ "$1" = 1 ]; then
		GIT1=$GIT_KEY HAD1=$_had OLD1=$_old
	else
		GIT2=$GIT_KEY HAD2=$_had OLD2=$_old
	fi
	git -C "$WS" config --local "$GIT_KEY" "$VALUE" ||
		give_up "could not set this checkout's git $GIT_KEY" 1
}
if git -C "$WS" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
	git_set 1 "$KIND1" "$VALUE1"
	[ -z "$KIND2" ] || git_set 2 "$KIND2" "$VALUE2"
fi

# Into the file, not moved over it: a mktemp file is 0600, and mv would leave
# settings.json with that mode. Rewriting in place keeps mode and owner.
WRITING=1
cat "$NEW" > "$SETTINGS" || give_up "could not write .vscode/settings.json" 1
trap - HUP INT TERM
drop
exit 0
