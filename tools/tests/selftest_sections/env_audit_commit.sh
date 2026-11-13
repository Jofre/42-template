# ---------------------------------------------------------- env-audit-commit
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# env-audit.sh --commit and --push, which put the campus report on branch
# env-audit-42, and the audit's login-shell probes. No arm ran either. The
# commit step failed quietly three ways (V247): with no git identity it said
# "pushed" and left the report staged on the branch it started from; a second
# run from a box whose report was on origin could not switch branch, and
# exited 0; and a fetch that failed rebuilt the branch from wherever the run
# started, then advised the force push that deletes every other box's
# report. And the PATH probe starts an interactive login shell, which runs
# the block setup.sh writes into the profiles, and that block starts a prime
# the audit then measures as the machine's (V254).
#
# Each case gets a checkout of its own with a bare origin beside it, so no
# arm reaches a real remote, and git reads no configuration of this
# machine's: HOME, XDG_CONFIG_HOME and the system file are the sandbox's, and
# what a shell started from git hands down (GIT_DIR, GIT_WORK_TREE,
# GIT_CONFIG_PARAMETERS: `git rebase -x` and `git -c` export them) is
# dropped, so a hand run of this file cannot commit or push in the
# repository it was started from. Two runs below are handed those on
# purpose, and arms check they changed nothing. A case with an identity gets
# one through GIT_CONFIG_COUNT; the case without one also turns off git's
# guess from the host name, which on a machine whose name has a domain makes
# one up.
EAC="$WORK/eac"
mkdir -p "$EAC/home" "$EAC/ws/tools"
# Every run below has setup.sh's profile block, taken from setup.sh itself so
# a change to it reaches this fixture, in .profile, .bashrc and .zshrc. Its
# checkout is $EAC/ws, whose tools/prime.sh is a stand-in that only leaves a
# mark: a probe that started a prime leaves it.
cat > "$EAC/ws/tools/prime.sh" <<'EOF'
#!/bin/sh
printf 'prime.sh %s\n' "$*" >> "$HOME/prime-started"
EOF
chmod +x "$EAC/ws/tools/prime.sh"
(
	# shellcheck disable=SC2034 # both are read by block(), defined by the eval
	WS="$EAC/ws" SCRATCH="$EAC/scratch"
	eval "$(sed -n -e '/^MARK_BEGIN=/p' -e '/^MARK_END=/p' \
		-e '/^block() {$/,/^}$/p' "$TOOLS/setup.sh")"
	for _rc in .profile .bashrc .zshrc; do
		block > "$EAC/home/$_rc"
	done
) > /dev/null 2>&1
eac_env() {  # eac_env NAME COMMAND... -- in case NAME's checkout, on the sandbox's configuration only
	_eb=$1
	shift
	( cd "$EAC/$_eb/repo" && env -u EMAIL -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL \
		-u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL -u GIT_CONFIG_GLOBAL \
		-u GIT_CONFIG_SYSTEM -u GIT_CONFIG_COUNT -u GIT_CONFIG_PARAMETERS \
		-u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_OBJECT_DIRECTORY \
		-u GIT_COMMON_DIR -u NO_C_PISCINE_PRIME GIT_CEILING_DIRECTORIES="$WORK" \
		HOME="$EAC/home" XDG_CONFIG_HOME="$EAC/home/.config" \
		XDG_STATE_HOME="$EAC/state" GIT_CONFIG_NOSYSTEM=1 \
		C_PISCINE_BOOT_ID=eac-boot C_PISCINE_HOST=eac-host "$@" )
}
eac_git() {  # eac_git NAME GIT-ARGS... -- git in NAME's checkout, as eac
	_eg=$1
	shift
	eac_env "$_eg" git -c user.name=eac -c user.email=eac@example.invalid "$@"
}
eac_box() {  # eac_box NAME -- a checkout holding the audit's three files, and its bare origin
	mkdir -p "$EAC/$1/repo/tools"
	cp "$TOOLS/env-audit.sh" "$TOOLS/drives.sh" "$TOOLS/prime_trace.sh" "$EAC/$1/repo/tools/"
	eac_env "$1" git init -q --bare "$EAC/$1/origin.git"
	eac_git "$1" init -q .
	eac_git "$1" symbolic-ref HEAD refs/heads/main
	eac_git "$1" add tools
	eac_git "$1" commit -q -m seed
	eac_git "$1" remote add origin "$EAC/$1/origin.git"
	eac_git "$1" push -q origin main
}
eac_audit() {  # eac_audit NAME TAG who|nobody FLAGS... -- one run: TAG.out, TAG.rc
	_eb=$1
	_et=$2
	_ew=$3
	shift 3
	if [ "$_ew" = who ]; then
		eac_env "$_eb" GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=user.name \
			GIT_CONFIG_VALUE_0=eac GIT_CONFIG_KEY_1=user.email \
			GIT_CONFIG_VALUE_1=eac@example.invalid \
			"$SH" tools/env-audit.sh "$@" > "$EAC/$_et.out" 2>&1
	else
		eac_env "$_eb" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.useConfigOnly \
			GIT_CONFIG_VALUE_0=true \
			"$SH" tools/env-audit.sh "$@" > "$EAC/$_et.out" 2>&1
	fi
	echo "$?" > "$EAC/$_et.rc"
}
# What a run said after its report, which is the host's and could hold any
# word. The paths it names hold the sandbox's (the scratch folder under $EAC,
# the report named after C_PISCINE_HOST's eac-host), so they are blanked
# before an arm reads the text.
eac_said() {
	awk -v eac="$EAC" '
		/^>>> report written to:/ { on = 1 }
		!on { next }
		{
			out = ""
			while ((i = index($0, eac)) > 0) {
				out = out substr($0, 1, i - 1) "<EAC>"
				$0 = substr($0, i + length(eac))
			}
			$0 = out $0
			gsub(/env-reports\/[^ ]*\.txt/, "env-reports/<host>.txt")
			print
		}' "$EAC/$1.out"
}
eac_rc() { return "$(cat "$EAC/$1.rc")"; }
# The branch a run started from: what is staged there, and whether HEAD is
# still on it.
eac_start() {
	_es=$(eac_git "$1" diff --cached --name-only)
	printf 'staged: %s, HEAD %s\n' "${_es:-(none)}" "$(eac_git "$1" symbolic-ref -q HEAD)"
}
# How many commits on a branch brought a report.
eac_reports() {
	printf 'reports: %s\n' "$(git --git-dir="$2" log --format=%H "$3" -- tools/env-reports 2>/dev/null | wc -l | tr -d ' ')"
}
# eac_seed NAME -- another box's report, alone in a commit of its own, pushed
# to NAME's origin as its env-audit-42; the commit is kept in NAME/seed.
eac_seed() {
	_ebl=$(printf 'another box\n' | eac_git "$1" hash-object -w --stdin) &&
		eac_env "$1" env GIT_INDEX_FILE="$EAC/$1/seed.index" git update-index --add \
			--cacheinfo "100644,$_ebl,tools/env-reports/another-box.txt" &&
		_et=$(eac_env "$1" env GIT_INDEX_FILE="$EAC/$1/seed.index" git write-tree) &&
		_ec=$(eac_git "$1" commit-tree -m 'another box' "$_et") &&
		eac_git "$1" push -q origin "$_ec:refs/heads/env-audit-42" &&
		echo "$_ec" > "$EAC/$1/seed"
}
# eac_gained NAME -- what origin's env-audit-42 gained on top of NAME/seed:
# whether it still holds that commit, how many commits it added, whether the
# files they changed are only the report the last run left in the checkout,
# and whether origin holds that report as the run wrote it.
eac_gained() {
	_eo="$EAC/$1/origin.git"
	_es=$(cat "$EAC/$1/seed" 2>/dev/null)
	_er=$(cd "$EAC/$1/repo" && ls tools/env-reports/*.txt 2>/dev/null)
	_ek=no
	git --git-dir="$_eo" merge-base --is-ancestor "$_es" refs/heads/env-audit-42 2>/dev/null && _ek=yes
	_en=$(git --git-dir="$_eo" rev-list --count "$_es..refs/heads/env-audit-42" 2>/dev/null)
	_ef=$(git --git-dir="$_eo" diff-tree --name-only -r "$_es" refs/heads/env-audit-42 2>/dev/null)
	_eh=$(git --git-dir="$_eo" rev-parse -q --verify "refs/heads/env-audit-42:$_er" 2>/dev/null)
	_ew=$(eac_git "$1" hash-object -- "$_er" 2>/dev/null)
	[ -n "$_er" ] && [ "$_ef" = "$_er" ] && _ef="this report only"
	[ -n "$_eh" ] && [ "$_eh" = "$_ew" ] && _eh="as written"
	printf 'kept: %s, commits: %s, files: %s, report: %s\n' "$_ek" "${_en:-?}" "$_ef" "$_eh"
}
if st_mine; then
	# The run with no identity is handed one the way `git -c` hands it to a
	# shell it starts: eac_env must drop it, or this case has an identity.
	eac_box noid > /dev/null 2>&1
	(
		# The quotes are git's own format for it, read by git, never by a shell.
		# shellcheck disable=SC2089
		GIT_CONFIG_PARAMETERS="'user.name=decoy' 'user.email=decoy@example.invalid'"
		# shellcheck disable=SC2090
		export GIT_CONFIG_PARAMETERS
		eac_audit noid noid nobody --push
	)
	# The second run from one box is handed GIT_DIR and GIT_WORK_TREE naming
	# another repository, a decoy with an origin of its own, as a hand run
	# from a `git rebase -x` shell would be: it must work in its own checkout
	# and leave the decoy alone.
	eac_box twice > /dev/null 2>&1
	eac_box decoy > /dev/null 2>&1
	eac_audit twice twice1 who --push
	(
		GIT_DIR="$EAC/decoy/repo/.git" GIT_WORK_TREE="$EAC/decoy/repo"
		export GIT_DIR GIT_WORK_TREE
		eac_audit twice twice2 who --push
	)
	# Origin's branch already holds another box's report, and the checkout's
	# fetch address is wrong while its push address is right: the fetch
	# fails, and a push would get through.
	eac_box nofetch > /dev/null 2>&1
	(
		_b=$(printf 'another box\n' | eac_git nofetch hash-object -w --stdin) &&
		eac_env nofetch env GIT_INDEX_FILE="$EAC/nofetch/index" git update-index --add \
			--cacheinfo "100644,$_b,tools/env-reports/another-box.txt" &&
		_t=$(eac_env nofetch env GIT_INDEX_FILE="$EAC/nofetch/index" git write-tree) &&
		_c=$(eac_git nofetch commit-tree -m 'another box' "$_t") &&
		eac_git nofetch push -q origin "$_c:refs/heads/env-audit-42" &&
		echo "$_c" > "$EAC/nofetch/seed" &&
		eac_git nofetch config remote.origin.pushurl "$EAC/nofetch/origin.git" &&
		eac_git nofetch config remote.origin.url "$EAC/nofetch/nowhere.git"
	) > /dev/null 2>&1
	eac_audit nofetch nofetch who --push
	# Another box pushes between this one's fetch and its push: a pre-push
	# hook moves origin's branch on, once. The push is then rejected, and
	# the run builds on what origin holds now and pushes again.
	eac_box race > /dev/null 2>&1
	(
		_b=$(printf 'another box\n' | eac_git race hash-object -w --stdin) &&
		eac_env race env GIT_INDEX_FILE="$EAC/race/index" git update-index --add \
			--cacheinfo "100644,$_b,tools/env-reports/another-box.txt" &&
		_t=$(eac_env race env GIT_INDEX_FILE="$EAC/race/index" git write-tree) &&
		_c=$(eac_git race commit-tree -m 'another box' "$_t") &&
		eac_git race push -q origin "$_c:refs/heads/env-audit-42" &&
		_m=$(eac_git race commit-tree -m 'another box, meanwhile' -p "$_c" "$_t") &&
		eac_git race push -q origin "$_m:refs/heads/meanwhile" &&
		echo "$_m" > "$EAC/race/meanwhile" &&
		printf '#!/bin/sh\n[ -e "%s" ] && exit 0\n: > "%s"\nexec git --git-dir="%s" update-ref refs/heads/env-audit-42 %s %s\n' \
			"$EAC/race/moved" "$EAC/race/moved" "$EAC/race/origin.git" "$_m" "$_c" \
			> "$EAC/race/repo/.git/hooks/pre-push" &&
		chmod +x "$EAC/race/repo/.git/hooks/pre-push"
	) > /dev/null 2>&1
	eac_audit race race who --push
	# --commit alone puts the report on a local branch and pushes nothing;
	# run again while that branch is checked out, it must not move the
	# branch under the checkout's files.
	eac_box local > /dev/null 2>&1
	eac_audit local local1 who --commit
	eac_git local rev-parse -q --verify refs/heads/env-audit-42 > "$EAC/local.tip1" 2>&1
	eac_reports local "$EAC/local/repo/.git" refs/heads/env-audit-42 > "$EAC/local.reports1"
	eac_git local worktree add -q "$EAC/local/wt" env-audit-42 > /dev/null 2>&1
	eac_audit local local2 who --commit
	eac_git local rev-parse -q --verify refs/heads/env-audit-42 > "$EAC/local.tip2" 2>&1
	eac_git local ls-remote origin > "$EAC/local.remote2" 2>&1
	# Then the sequence the closing lines lead to: --push after that
	# --commit, and --commit once more. The local branch is a commit origin
	# has never had; neither run may leave it beside origin's. The --push
	# runs while the branch is still checked out, which is where --commit's
	# refusal sends the user, and must leave it where it was: a branch moved
	# under a checkout leaves that checkout's files describing another
	# commit. diverge3's arm holds the case with no checkout, which git lets
	# more commands move.
	eac_audit local local3 who --push
	eac_git local rev-parse -q --verify refs/heads/env-audit-42 > "$EAC/local.tip3" 2>&1
	eac_git local worktree remove --force "$EAC/local/wt" > /dev/null 2>&1
	eac_audit local local4 who --commit
	# A local branch and origin's that have each a commit the other lacks:
	# after a --commit, another box's report reaches origin's branch first.
	# --commit then has nowhere to put the report and stops, leaving the
	# local branch as it is; --push leaves it too, and sends only this run's
	# report, on top of origin's.
	eac_box diverge > /dev/null 2>&1
	eac_audit diverge diverge1 who --commit
	eac_seed diverge > /dev/null 2>&1
	eac_git diverge rev-parse -q --verify refs/heads/env-audit-42 > "$EAC/diverge.tip1" 2>&1
	eac_audit diverge diverge2 who --commit
	eac_git diverge rev-parse -q --verify refs/heads/env-audit-42 > "$EAC/diverge.tip2" 2>&1
	eac_audit diverge diverge3 who --push
	eac_git diverge rev-parse -q --verify refs/heads/env-audit-42 > "$EAC/diverge.tip3" 2>&1
	# A --push whose local branch already holds, on top of origin's, the
	# very report this run writes: there is nothing to build, and the local
	# commit is what goes to origin. A report holds the time it was made, so
	# no earlier run can write the same one; a stand-in git on PATH commits
	# it, once, when the run first asks origin for its branch (after the
	# report is written), and hands every call to git itself.
	eac_box same > /dev/null 2>&1
	eac_seed same > /dev/null 2>&1
	mkdir -p "$EAC/same/shim"
	_eg_real=$(command -v git)
	cat > "$EAC/same/shim/git" <<EOF
#!/bin/sh
case " \$* " in
	*" ls-remote "*)
		if [ ! -e "$EAC/same/made" ]; then
			r=\$(cd "$EAC/same/repo" && ls tools/env-reports/*.txt) &&
				b=\$("$_eg_real" -C "$EAC/same/repo" hash-object -w -- "\$r") &&
				GIT_INDEX_FILE="$EAC/same/made.index" "$_eg_real" -C "$EAC/same/repo" \\
					read-tree "$(cat "$EAC/same/seed" 2>/dev/null)" &&
				GIT_INDEX_FILE="$EAC/same/made.index" "$_eg_real" -C "$EAC/same/repo" \\
					update-index --add --cacheinfo "100644,\$b,\$r" &&
				t=\$(GIT_INDEX_FILE="$EAC/same/made.index" "$_eg_real" -C "$EAC/same/repo" write-tree) &&
				c=\$("$_eg_real" -C "$EAC/same/repo" commit-tree -m 'this report' \\
					-p "$(cat "$EAC/same/seed" 2>/dev/null)" "\$t") &&
				"$_eg_real" -C "$EAC/same/repo" update-ref refs/heads/env-audit-42 "\$c" &&
				echo "\$c" > "$EAC/same/made"
		fi ;;
esac
exec "$_eg_real" "\$@"
EOF
	chmod +x "$EAC/same/shim/git"
	(
		PATH="$EAC/same/shim:$PATH"
		export PATH
		eac_audit same same who --push
	)
fi
want_out "env-audit-commit: the profiles hold setup.sh's block" \
	'/tools/prime.sh" --background' -- cat "$EAC/home/.profile"
want_red "env-audit-commit: --push with no git identity exits 1" -- eac_rc noid
want_out "env-audit-commit: ...naming what to set" 'git config user.email' -- eac_said noid
want_out "env-audit-commit: ...staging nothing on the branch it left" \
	'staged: (none), HEAD refs/heads/main' -- eac_start noid
want_broken_none "env-audit-commit: ...and pushing no branch without it" \
	'env-audit-42' -- eac_git noid ls-remote origin
want_broken_none "env-audit-commit: ...nor using one git -c handed it" \
	'decoy' -- eac_said noid
want_green "env-audit-commit: a first --push from a box" -- eac_rc twice1
want_green "env-audit-commit: ...and a second from the same box" -- eac_rc twice2
want_out "env-audit-commit: ...leave both reports on origin" \
	'reports: 2' -- eac_reports twice "$EAC/twice/origin.git" refs/heads/env-audit-42
want_out "env-audit-commit: ...staging nothing on the branch they left" \
	'staged: (none), HEAD refs/heads/main' -- eac_start twice
# The decoy's branches and its origin's, and its tools folder.
eac_decoy() {
	git --git-dir="$EAC/decoy/repo/.git" for-each-ref --format='%(refname)'
	git --git-dir="$EAC/decoy/origin.git" for-each-ref --format='%(refname)'
	ls "$EAC/decoy/repo/tools"
}
want_broken_none "env-audit-commit: a run handed GIT_DIR pushes no report there" \
	'env-audit-42' -- eac_decoy
want_broken_none "env-audit-commit: ...nor writes one in its tree" \
	'env-reports' -- eac_decoy
want_red "env-audit-commit: a fetch that fails exits 1" -- eac_rc nofetch
want_out "env-audit-commit: ...saying origin did not answer" \
	'origin did not answer' -- eac_said nofetch
want_broken_none "env-audit-commit: ...advising no force push" '--force' -- eac_said nofetch
want_green "env-audit-commit: ...and origin keeps the report it had" -- \
	git --git-dir="$EAC/nofetch/origin.git" merge-base --is-ancestor \
	"$(cat "$EAC/nofetch/seed" 2>/dev/null)" refs/heads/env-audit-42
want_green "env-audit-commit: a push that lost a race to another box" -- eac_rc race
want_green "env-audit-commit: ...keeps that box's commit" -- \
	git --git-dir="$EAC/race/origin.git" merge-base --is-ancestor \
	"$(cat "$EAC/race/meanwhile" 2>/dev/null)" refs/heads/env-audit-42
want_out "env-audit-commit: ...and adds its own report on top" \
	'reports: 2' -- eac_reports race "$EAC/race/origin.git" refs/heads/env-audit-42
want_green "env-audit-commit: --commit alone" -- eac_rc local1
want_out "env-audit-commit: ...commits the report on a local branch" \
	'reports: 1' -- cat "$EAC/local.reports1"
want_broken_none "env-audit-commit: ...and pushes nothing" \
	'env-audit-42' -- cat "$EAC/local.remote2"
want_red "env-audit-commit: --commit with the branch checked out exits 1" -- eac_rc local2
want_green "env-audit-commit: ...and leaves the branch where it was" -- \
	cmp -s "$EAC/local.tip1" "$EAC/local.tip2"
want_green "env-audit-commit: --push after a --commit" -- eac_rc local3
want_green "env-audit-commit: ...leaving the branch checked out where it was" -- \
	cmp -s "$EAC/local.tip1" "$EAC/local.tip3"
want_out "env-audit-commit: ...takes the --commit's report along" \
	'reports: 2' -- eac_reports local "$EAC/local/origin.git" refs/heads/env-audit-42
want_green "env-audit-commit: ...and a --commit after it" -- eac_rc local4
want_out "env-audit-commit: ...builds on origin's, keeping all three" \
	'reports: 3' -- eac_reports local "$EAC/local/repo/.git" refs/heads/env-audit-42
want_red "env-audit-commit: --commit beside origin's branch exits 1" -- eac_rc diverge2
want_green "env-audit-commit: ...leaving the local branch where it was" -- \
	cmp -s "$EAC/diverge.tip1" "$EAC/diverge.tip2"
want_out "env-audit-commit: ...advising to delete it" \
	'(git branch -D env-audit-42)' -- eac_said diverge2
want_broken_none "env-audit-commit: ...and advising no push" 'git push' -- eac_said diverge2
want_green "env-audit-commit: --push beside origin's branch" -- eac_rc diverge3
want_green "env-audit-commit: ...leaves the local branch where it was" -- \
	cmp -s "$EAC/diverge.tip1" "$EAC/diverge.tip3"
want_out "env-audit-commit: ...and adds one commit to origin's, holding only this report" \
	'kept: yes, commits: 1, files: this report only, report: as written' -- eac_gained diverge
# eac_same -- where the run that found its report already committed left
# origin's branch and the local one, against the commit the stand-in made.
eac_same() {
	_em=$(cat "$EAC/same/made" 2>/dev/null)
	_eo=$(git --git-dir="$EAC/same/origin.git" rev-parse -q --verify refs/heads/env-audit-42)
	_el=$(eac_git same rev-parse -q --verify refs/heads/env-audit-42)
	[ -n "$_em" ] || { echo "the stand-in made no commit"; return 0; }
	if [ "$_eo" = "$_em" ]; then echo "origin: that commit"; else echo "origin: another"; fi
	if [ "$_el" = "$_em" ]; then echo "local: that commit"; else echo "local: another"; fi
}
want_green "env-audit-commit: --push from a local branch already holding this report" -- eac_rc same
want_out "env-audit-commit: ...builds on that branch" \
	"on top of your local env-audit-42, which holds origin's" -- eac_said same
want_out "env-audit-commit: ...and sends its commit as it is" \
	'origin: that commit' -- eac_same
want_out "env-audit-commit: ...leaving the local branch on that commit" \
	'local: that commit' -- eac_same
# Run by its path from inside another repository, --push works in the
# checkout the script is in, never the one it was started from: it took
# that one from the folder's git, and wrote, committed and pushed its report
# there. "elsewhere" is a repository of its own, with an origin, no tools/.
if st_mine; then
	eac_box home42 > /dev/null 2>&1
	mkdir -p "$EAC/elsewhere/repo"
	{
		eac_env elsewhere git init -q --bare "$EAC/elsewhere/origin.git" &&
			eac_git elsewhere init -q . &&
			eac_git elsewhere symbolic-ref HEAD refs/heads/main &&
			printf 'mine\n' > "$EAC/elsewhere/repo/README" &&
			eac_git elsewhere add README && eac_git elsewhere commit -q -m mine &&
			eac_git elsewhere remote add origin "$EAC/elsewhere/origin.git" &&
			eac_git elsewhere push -q origin main
	} > /dev/null 2>&1
	eac_env elsewhere GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=user.name \
		GIT_CONFIG_VALUE_0=eac GIT_CONFIG_KEY_1=user.email \
		GIT_CONFIG_VALUE_1=eac@example.invalid \
		"$SH" "$EAC/home42/repo/tools/env-audit.sh" --push > "$EAC/elsewhere.out" 2>&1
fi
want_red "env-audit-commit: run by its path from another repository, it pushes nothing there" -- \
	git --git-dir="$EAC/elsewhere/origin.git" rev-parse -q --verify refs/heads/env-audit-42
want_red "env-audit-commit: ...commits nothing there" -- \
	git --git-dir="$EAC/elsewhere/repo/.git" rev-parse -q --verify refs/heads/env-audit-42
want_red "env-audit-commit: ...nor writes a report there" -- \
	test -e "$EAC/elsewhere/repo/tools/env-reports"
want_green "env-audit-commit: ...and pushes it from its own checkout" -- \
	git --git-dir="$EAC/home42/origin.git" rev-parse -q --verify refs/heads/env-audit-42
# Last, after every run above: none of them started a prime (V254). The
# probe's own answer is not asked: the block puts ~/.local/bin on PATH, and
# what the row says depends on which shells this machine has.
eac_mark() { cat "$EAC/home/prime-started" 2>/dev/null; return 0; }
want_broken_none "env-audit-commit: its login-shell probes start no prime" \
	'prime.sh' -- eac_mark

