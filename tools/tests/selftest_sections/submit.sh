# ------------------------------------------------------------------- submit
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The tool that pushes to 42, which had no arm of any kind -- and the defects
# below are all in its REMOTES parser, i.e. in the decision of WHICH module goes
# to WHICH url. Every one of them was reproduced before it was fixed.
#
# Driven with -n (dry-run) and --no-gate over a fixture workspace, so nothing
# runs bazel, nothing touches the deliverable's git (the file list -n prints
# comes from a scratch index), and nothing reaches the network. LOGIN42 and
# EMAIL42 are supplied so the identity check does not short-circuit the parse.
# The real push is driven further down, against a local bare repository.
#
# Two project folders, one at the root and one under a course folder, because a
# module id is a PATH and the nested form is the one the repo actually uses.
# Each has a BUILD.bazel: a row with a live remote must name a project folder.
mkdir -p "$WORK/subm/ws/c-piscine-c-00/deliverable" "$WORK/subm/ws/.vscode" \
	"$WORK/subm/ws/c-piscine/c-piscine-c-00/deliverable"
: > "$WORK/subm/ws/c-piscine-c-00/BUILD.bazel"
: > "$WORK/subm/ws/c-piscine/c-piscine-c-00/BUILD.bazel"
printf '{ "42header.username": "marvin", "42header.email": "marvin@42.fr" }\n' \
	> "$WORK/subm/ws/.vscode/settings.json"
# sb_env [NAME=VALUE...] COMMAND...: COMMAND as every submit.sh run here
# runs it -- marvin's identity, no SUBMIT_GATE (a gated run gates at the
# level its fixture gives, never one exported by whoever runs this), no
# /etc/gitconfig, and git never looking above $WORK -- with the run's own
# NAME=VALUEs after these, which win. The selftest's preamble gives every
# run a HOME and an XDG_CONFIG_HOME of its own.
sb_env() {
	env SUBMIT_GATE= GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$WORK" \
		LOGIN42=marvin EMAIL42=marvin@42.fr "$@"
}

# A copy of the real script with its FIRST table row replaced per fixture.
#
# It used to rewrite the row keyed c-piscine-c-00 with a sed, and when the keys
# changed shape that sed matched nothing: the "fixture" was then a verbatim copy
# of submit.sh, and the arms asserting an ABSENCE ("should-not-run" never
# printed) passed without the row they test ever existing. So the row is found
# by position, whatever its key, and the fixture is checked to contain it.
sb_make() {
	awk -v row="$1" '
		!d && $0 == "REMOTES='"'"'" { print; getline; print row; d = 1; next }
		{ print }' "$TOOLS/submit.sh" > "$WORK/subm/$2.sh"
	if ! grep -qxF -- "$1" "$WORK/subm/$2.sh"; then
		printf '  %-52s %s\n' "submit: fixture '$2' holds its row" \
			"FAIL < (the row was not written; every arm on it is vacuous)"
		FAIL=$((FAIL + 1))
	fi
}
sb_run() {  # sb_run FIXTURE [ARG...]: a dry run of FIXTURE's copy, ungated
	_sbf=$1
	shift
	sb_env BUILD_WORKSPACE_DIRECTORY="$WORK/subm/ws" \
		"$SH" "$WORK/subm/$_sbf.sh" -n --no-gate "$@"
}

# 1. A COMMENTED-OUT ROW MUST NOT BE PUSHED. `for entry in $REMOTES` word-split
#    on IFS, so "# c-piscine-c-00=..." became a bare "#" (which the guard
#    skipped) followed by the entry itself (which it did not). The single
#    gesture a person makes to disable a module was the one that did not work.
sb_make '# c-piscine-c-00=git@example.invalid:should-not-run' cmt
want_broken_none "submit: a commented-out table row is not pushed" \
	"should-not-run" -- sb_run cmt

# 2. AN INLINE COMMENT IS NOT PART OF THE URL. docs/submitting.md shows a row
#    written exactly this way; without the fix the tail became the remote, so
#    the row stopped reading as REPLACE_ME and was treated as live.
sb_make 'c-piscine-c-00=REPLACE_ME   # left as REPLACE_ME -> skipped' ic
want_out "submit: an inline comment leaves the row a REPLACE_ME skip" \
	"SKIP  c-piscine-c-00" -- once sb_run ic
want_broken_none "submit: ... and does not invent modules from its words" \
	"==>  left" -- once sb_run ic

# 3. SPACES AROUND "=" are how a person writes a table row, and produced a
#    module named with a trailing space pointed at a URL with a leading one.
sb_make 'c-piscine-c-00 = git@example.invalid:spaced' sp
want_out "submit: spaces around = still name the module" \
	"==>  c-piscine-c-00 " -- sb_run sp

# 4. A ROW WITH NO "=" is not a table row. ${entry#*=} returns the string
#    UNCHANGED when there is no match, so such a row became a module whose
#    remote was its own name.
sb_make 'c-piscine-c-00-no-equals-here' noeq
want_out "submit: a row with no '=' is reported, not treated as live" \
	"malformed table line" -- sb_run noeq

# 5. A MODULE NAME THAT MATCHES NO ROW must not exit 0. It filtered everything
#    out before any counter moved, so a typo printed the summary and exited 0 --
#    the same output as a submission that worked.
sb_make 'c-piscine-c-00=REPLACE_ME' plain
want_red "submit: a module that is not in the table exits non-zero" -- \
	sb_run plain c-piscine-c-OO
want_green "submit: ... and a real module name still exits 0" -- \
	sb_run plain c-piscine-c-00

# 6. A NESTED MODULE ID IS A MODULE. The guard used to refuse any id holding a
#    '/', so once the projects moved under a course folder every row printed
#    "bad module name", nothing was pushed, and the run exited 0.
sb_make 'c-piscine/c-piscine-c-00=git@example.invalid:nested' nest
want_out "submit: a nested module id is submitted" \
	"==>  c-piscine/c-piscine-c-00 " -- sb_run nest
want_out "submit: ... named by its project name alone" \
	"==>  c-piscine/c-piscine-c-00 " -- sb_run nest c-piscine-c-00
want_out "submit: ... and with tab completion's trailing /" \
	"==>  c-piscine/c-piscine-c-00 " -- sb_run nest c-piscine/c-piscine-c-00/
want_green "submit: ... and named both ways, it is one module" -- \
	sb_env BUILD_WORKSPACE_DIRECTORY="$WORK/subm/ws" \
	"$SH" "$WORK/subm/nest.sh" -n --no-gate c-piscine-c-00 c-piscine/c-piscine-c-00
want_broken "submit: a name that normalises to nothing is refused" \
	"empty module name" -- sb_run nest /
sb_make 'c-piscine/c-piscine-c-00/ = git@example.invalid:tslash' ts
want_out "submit: a table key with a trailing / is the same module" \
	"==>  c-piscine/c-piscine-c-00 " -- sb_run ts

# 7. WHAT THE GUARD STILL REFUSES: an id that climbs out of the repo, or has an
#    empty component. Never submitted, and on a row with a live remote a
#    FAILURE rather than a skip, since the URL says someone meant to push it.
sb_make '../x=git@example.invalid:dotdot' dd
want_broken_none "submit: a '..' id is never submitted" \
	"==>  ../x" -- sb_run dd
want_red "submit: ... and naming it exits non-zero" -- \
	sb_run dd ../x
sb_make 'c-piscine//c-piscine-c-00=git@example.invalid:dslash' ds
want_red "submit: a LIVE row the guard refuses fails the run" -- once sb_run ds
want_out "submit: ... and says why" "FAIL  bad module name" -- once sb_run ds

# 8. A LIVE ROW MUST NAME A PROJECT FOLDER. A typo in a key used to gate on
#    //typo/... (no targets) and push typo/deliverable (absent).
sb_make 'c-piscine-c-77=git@example.invalid:nobuild' nb
want_red "submit: a live row with no project folder fails" -- once sb_run nb
want_out "submit: ... and says which folder is missing" \
	"not a project folder" -- once sb_run nb

# 8b. NO IDENTITY AT ALL stops the run before any parse, and the advice names
#    the command a student types, `42 init`, as 42 doctor, 42 config and
#    setup.sh do. It named the Bazel target, which a student meets only in
#    the scripts' own headers (V187).
mkdir -p "$WORK/sid/ws"
sid_err() {  # its stderr alone, on stdout
	{ env -u LOGIN42 -u EMAIL42 BUILD_WORKSPACE_DIRECTORY="$WORK/sid/ws" \
		"$SH" "$TOOLS/submit.sh" -n --no-gate > /dev/null; } 2>&1
}
want_red "submit: no 42 identity fails the run" -- once sid_err
want_out "submit: ... and says on stderr that 42 init sets it" "Run:  42 init" -- once sid_err

# 9. THE URLS LIVE IN .submit-remotes, not in the tracked table. Same parser,
#    so the same hand-written shapes: a comment, an inline comment, spaces, and
#    a key spelled as the project name alone. A key that names no module is a
#    typo that would silently skip the module meant, and two URLs for one
#    module are a guess about which repository is graded: both fail the run.
#    Driven through the real script, whose table is all REPLACE_ME.
mkdir -p "$WORK/sr/ws/c-piscine/c-piscine-c-00/deliverable/ex00"
: > "$WORK/sr/ws/c-piscine/c-piscine-c-00/BUILD.bazel"
#    The arms below run sr_run directly, not through once, wherever the
#    same command line runs again after .submit-remotes or the workspace is
#    rewritten (a bare sr_run, sr_run Libft): once would replay the first
#    run. The one pair through once, `sr_run c-piscine-c-77 --url ...`, is
#    two arms over one run with nothing written between them.
sr_run() {  # sr_run [ARG...]: a dry run of the real script over the sr workspace, ungated
	sb_env BUILD_WORKSPACE_DIRECTORY="$WORK/sr/ws" \
		"$SH" "$TOOLS/submit.sh" -n --no-gate "$@"
}
printf 'c-piscine/c-piscine-c-00=git@example.invalid:from-file\n' > "$WORK/sr/ws/.submit-remotes"
want_out "submit: .submit-remotes gives a module its URL" \
	"->  git@example.invalid:from-file" -- sr_run
printf '  # c-piscine/c-piscine-c-00=git@example.invalid:should-not-run\n' \
	> "$WORK/sr/ws/.submit-remotes"
want_broken_none "submit: ... a commented-out line in it is not pushed" \
	"should-not-run" -- sr_run
printf 'c-piscine-c-00 = git@example.invalid:by-name   # mine' > "$WORK/sr/ws/.submit-remotes"
want_out "submit: ... a project-name key, spaced, commented, no newline" \
	"->  git@example.invalid:by-name" -- sr_run
printf 'c-piscine-c-O0=git@example.invalid:typo\n' > "$WORK/sr/ws/.submit-remotes"
want_red "submit: ... a key that names no module fails the run" -- sr_run
want_out "submit: ... and is named" "BUT NOT A MODULE: c-piscine-c-O0" -- sr_run
printf 'c-piscine/c-piscine-c-00=git@example.invalid:one\nc-piscine-c-00=git@example.invalid:two\n' \
	> "$WORK/sr/ws/.submit-remotes"
want_red "submit: ... two URLs for one module fail the run" -- sr_run
want_broken_none "submit: ... and neither is used" "==>  c-piscine/c-piscine-c-00" -- sr_run
#    The short name `42` takes everywhere else (c-00) is a key too, by the
#    rule `42` and first_red name a project with. It used to name no module:
#    the module was skipped as having no URL, and the key reported.
printf 'c-00=git@example.invalid:short\n' > "$WORK/sr/ws/.submit-remotes"
want_out "submit: ... a short-name key gives the module its URL" \
	"->  git@example.invalid:short" -- sr_run
want_green "submit: ... and is not reported as naming no module" -- sr_run
#    A Common Core project's short name is its folder's name in lower case,
#    at any depth under cursus/ (cursus/Milestone_0/Libft is libft): a key
#    too, and two keys for it are two URLs. A short name two modules share
#    names neither, and the run says so.
mkdir -p "$WORK/sr/ws/cursus/Milestone_0/Libft/deliverable"
: > "$WORK/sr/ws/cursus/Milestone_0/Libft/BUILD.bazel"
printf 'libft=git@example.invalid:lib\n' > "$WORK/sr/ws/.submit-remotes"
want_green "submit: ... a Common Core short-name key names a module" -- sr_run
want_out "submit: ... and gives it its URL" \
	"==>  cursus/Milestone_0/Libft  ->  git@example.invalid:lib" -- sr_run Libft
printf 'Libft=git@example.invalid:one\nlibft=git@example.invalid:two\n' > "$WORK/sr/ws/.submit-remotes"
want_red "submit: ... and with its folder's name, is two URLs" -- sr_run Libft
want_out "submit: ... said so" "gives it 2 URLs: keep one" -- sr_run Libft
sb_make 'cursus/Milestone_8/LIBFT=REPLACE_ME' snd
printf 'libft=git@example.invalid:amb\n' > "$WORK/sr/ws/.submit-remotes"
want_out "submit: ... a short name two modules share is refused" \
	"libft names more than one module: cursus/Milestone_8/LIBFT cursus/Milestone_0/Libft" -- \
	sb_env BUILD_WORKSPACE_DIRECTORY="$WORK/sr/ws" \
	"$SH" "$WORK/subm/snd.sh" -n --no-gate
rm -rf "$WORK/sr/ws/.submit-remotes" "$WORK/sr/ws/cursus"
#    Reading the keys costs the same per key whatever the table holds. When
#    short names came in, every key read the whole table again, one sed per
#    half-row, and a .submit-remotes with a key for each module made a dry run
#    ten times slower. Counted rather than timed, so a loaded machine cannot
#    fail it: the sed runs one dry run makes with a key for every row of the
#    real table, less those it makes with one key, at most eight per key.
#    That counts sed runs and nothing else. The other half of the slowdown,
#    a $(short_name ...) subshell for each key and row, runs no sed: a
#    stand-in on PATH counts the runs of a program it stands in for, and
#    never a subshell or a program it does not; sr_nofork, below, holds
#    that half.
mkdir -p "$WORK/sr/bin"
printf '#!/bin/sh\necho sed >> "$SR_SEDS"\nexec %s "$@"\n' "$(command -v sed)" > "$WORK/sr/bin/sed"
chmod +x "$WORK/sr/bin/sed"
sed -n "/^REMOTES='\$/,/^'\$/s/^\([^=]*\)=.*/\1/p" "$TOOLS/submit.sh" |
	sed -e '/^REMOTES$/d' -e 's:.*/c-piscine-:c-piscine-:' -e 's/^c-piscine-//' \
		-e 's/$/=git@example.invalid:k/' \
	> "$WORK/sr/every.keys"
sr_seds() {  # sr_seds KEYS-FILE: how many seds one dry run of c-piscine-c-00 runs
	cp "$1" "$WORK/sr/ws/.submit-remotes"
	: > "$WORK/sr/seds"
	sb_env PATH="$WORK/sr/bin:$PATH" SR_SEDS="$WORK/sr/seds" \
		BUILD_WORKSPACE_DIRECTORY="$WORK/sr/ws" \
		"$SH" "$TOOLS/submit.sh" -n --no-gate c-piscine-c-00 > /dev/null 2>&1 || return 1
	grep -c . "$WORK/sr/seds"
}
sr_per_key() {
	printf 'c-00=git@example.invalid:k\n' > "$WORK/sr/one.keys"
	_srn=$(grep -c . "$WORK/sr/every.keys")
	_sr1=$(sr_seds "$WORK/sr/one.keys") && _srall=$(sr_seds "$WORK/sr/every.keys") || return 1
	echo "$_srn keys: $_srall seds; one key: $_sr1"
	[ "$_srn" -gt 10 ] && [ "$((_srall - _sr1))" -le "$((8 * (_srn - 1)))" ]
}
want_green "submit: ... and a key costs the same however long the table" -- sr_per_key
#    The code a key runs once for every row -- key_names, ovr_lookup, and the
#    loop that looks for a key naming two modules -- makes no command
#    substitution, $(...) or `...`: each is a subshell, forked once per key
#    and row. And it runs nothing but shell keywords, assignments, key_names
#    and the builtins it runs now ([, read, continue, printf): a program
#    (expr, grep) forks as surely, and another function of the script's is
#    code this check does not read, so a call to either is reported, and a
#    new one is added to the list on purpose (TO VERIFY V152). Read from the
#    script's text, so it holds those three blocks as written, not what a run
#    costs; mutated copies -- key_names forking for its third comparison,
#    calling a helper for it, or running expr -- show the check tells.
sr_nofork() {  # sr_nofork SCRIPT: SCRIPT's per-key code makes no command substitution
	awk '
		# The line with every quoted string made a Q: what a string holds
		# is no command word.
		function unq(l,   o, i, c, q) {
			o = ""; q = ""
			for (i = 1; i <= length(l); i++) {
				c = substr(l, i, 1)
				if (q == "") {
					if (c == "\\") { o = o substr(l, i, 2); i++ }
					else if (c == "\047" || c == "\"") { q = c; o = o "Q" }
					else o = o c
				} else if (q == "\"" && c == "\\") i++
				else if (c == q) q = ""
			}
			return o
		}
		/^(key_names|ovr_lookup)\(\) \{$/ || /^AMBIGUOUS=0$/ { on = 1; seen++; hd = ""; next }
		on && hd != "" {
			if ($0 ~ ("^\t*" hd "$")) hd = ""
			if (/^OVERRIDES$/) on = 0
			next
		}
		on && /^[ \t]*#/ { next }
		on && (/\$\([^(]/ || /`/) { print FNR ": " $0; bad = 1 }
		on {
			if (match($0, /<<-?[ \t]*[\047"]?[A-Za-z_][A-Za-z0-9_]*/)) {
				hd = substr($0, RSTART, RLENGTH); sub(/^<<-?[ \t]*[\047"]?/, "", hd)
			}
			l = unq($0)
			gsub(/\$\(\([^()]*\)\)/, "N", l)
			gsub(/[0-9]*[<>]&[0-9-]*/, " ", l)
			gsub(/[0-9]*[<>]+[ \t]*[^ \t;&|]*/, " ", l)
			# A case pattern: a ")" with no "(" before it but its own.
			if (match(l, /^[ \t]*\(?[^()]*\)/)) l = substr(l, RLENGTH + 1)
			gsub(/&&|\|\||;;|[;&|]/, "\n", l)
			ns = split(l, seg, "\n")
			for (s = 1; s <= ns; s++) {
				sub(/^[ \t]+/, "", seg[s]); sub(/[ \t]+$/, "", seg[s])
				nw = split(seg[s], w, /[ \t]+/)
				j = 1
				while (j <= nw && w[j] ~ /^(then|do|else|elif|if|while|until|!)$/) j++
				while (j <= nw && w[j] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) j++
				if (j > nw || w[j] ~ /^(case|esac|done|fi|\}|\[|read|continue|printf|key_names)$/) continue
				print FNR ": " $0 "  -- runs " w[j]; bad = 1
			}
		}
		on && (/^\}$/ || /^OVERRIDES$/) { on = 0 }
		END {
			if (seen != 3) { print "found " seen + 0 " of the 3 blocks"; exit 1 }
			exit bad
		}' "$1"
}
want_green "submit: ... and forks no subshell per key and row" -- sr_nofork "$TOOLS/submit.sh"
sed 's/|| \[ "\$1" = "\$3" \]$/|| [ "$1" = "$(printf %s "$3")" ]/' "$TOOLS/submit.sh" > "$WORK/sr/forks.sh"
want_red "submit: ... which a key_names that forks fails" -- sr_nofork "$WORK/sr/forks.sh"
sed 's/|| \[ "\$1" = "\$3" \]$/|| kn_eq "$1" "$3"/' "$TOOLS/submit.sh" > "$WORK/sr/helper.sh"
want_red "submit: ... and one that calls a function of its own fails" -- sr_nofork "$WORK/sr/helper.sh"
sed 's/|| \[ "\$1" = "\$3" \]$/|| expr "x$1" = "x$3" > \/dev\/null/' "$TOOLS/submit.sh" > "$WORK/sr/expr.sh"
want_red "submit: ... and one that runs a program fails" -- sr_nofork "$WORK/sr/expr.sh"
#    A key that names two modules is a guess about which one, so it is
#    refused before anything is pushed. A second row whose folder has the
#    same name as a real module's, under another course folder, makes one.
sb_make 'c-piscine-c-01=REPLACE_ME' amb
mkdir -p "$WORK/subm/ws/c-piscine/c-piscine-c-01"
: > "$WORK/subm/ws/c-piscine/c-piscine-c-01/BUILD.bazel"
printf 'c-01=git@example.invalid:amb\n' > "$WORK/subm/ws/.submit-remotes"
want_red "submit: ... a key that names two modules fails the run" -- once sb_run amb
want_out "submit: ... and says which modules it names" \
	"c-01 names more than one module: c-piscine-c-01 c-piscine/c-piscine-c-01" -- once sb_run amb
want_broken_none "submit: ... and nothing is submitted" "==>  " -- once sb_run amb
#    --url gives the one module named its repository on the command line
#    (`42 submit c-00 URL` passes it), and no line of the file has a say in
#    where that push goes: neither a key naming two modules nor, below, two
#    URLs for the one named. Every other module stays out of the run.
want_out "submit: --url pushes past a key that names two modules" \
	"->  git@example.invalid:given" -- \
	once sb_run amb c-piscine/c-piscine-c-01 --url git@example.invalid:given
want_broken_none "submit: ... and to no URL of the file" "example.invalid:amb" -- \
	once sb_run amb c-piscine/c-piscine-c-01 --url git@example.invalid:given
rm -rf "$WORK/subm/ws/.submit-remotes" "$WORK/subm/ws/c-piscine/c-piscine-c-01"
printf 'c-piscine/c-piscine-c-00=git@example.invalid:one\nc-00=git@example.invalid:two\n' \
	> "$WORK/sr/ws/.submit-remotes"
want_out "submit: --url wins over two URLs for the module" \
	"->  git@example.invalid:given" -- sr_run c-piscine-c-00 --url git@example.invalid:given
want_broken "submit: --url with two modules is refused" "name exactly one module" -- \
	sr_run c-piscine-c-00 c-piscine-c-01 --url git@example.invalid:given
want_broken "submit: --url with no module is refused" "name exactly one module" -- \
	sr_run --url git@example.invalid:given
want_broken "submit: an empty --url is refused" "needs a repository URL" -- \
	sr_run c-piscine-c-00 --url ""
want_broken "submit: a --url holding a blank is refused" "needs a repository URL" -- \
	sr_run c-piscine-c-00 --url "git@example.invalid: x"
want_red "submit: --url for a module not in the table fails" -- \
	once sr_run c-piscine-c-77 --url git@example.invalid:given
want_broken_none "submit: ... and pushes nothing" "==>  " -- \
	once sr_run c-piscine-c-77 --url git@example.invalid:given
#    A NAME HOLDING A GLOB CHARACTER is no module name. The --url check
#    counted the names with globbing off, so a quoted
#    'c-piscine/c-piscine-c-0?' passed as one module; the selection then
#    expanded it in the repo root, with globbing on, into ten project folders,
#    and pushed every one of them to the one URL given, naming none of them
#    as unmatched. A toy workspace of ten such folders, so it has something to
#    expand to.
for _sg in 0 1 2 3 4 5 6 7 8 9; do
	mkdir -p "$WORK/sg/ws/c-piscine/c-piscine-c-0$_sg/deliverable"
	: > "$WORK/sg/ws/c-piscine/c-piscine-c-0$_sg/BUILD.bazel"
done
sg_run() {
	sb_env BUILD_WORKSPACE_DIRECTORY="$WORK/sg/ws" \
		"$SH" "$TOOLS/submit.sh" -n --no-gate "$@"
}
want_broken "submit: --url with a glob for a name is refused" "glob character" -- \
	once sg_run --url git@example.invalid:given 'c-piscine/c-piscine-c-0?'
want_broken_without "submit: ... and selects no module" "==>  " -- \
	once sg_run --url git@example.invalid:given 'c-piscine/c-piscine-c-0?'
want_broken "submit: a glob for a name is refused without --url too" "glob character" -- \
	sg_run 'c-piscine/c-piscine-c-0[0-9]'

#    A '=' in a line's comment alone makes no KEY=URL of it: asked before the
#    comment was cut, `c-piscine-c-00 # note=x` was the module pushed to the
#    "URL" c-piscine-c-00.
printf 'c-piscine-c-00 # note=x\n' > "$WORK/sr/ws/.submit-remotes"
want_broken_none "submit: ... a '=' in a comment alone is no URL" \
	"->  c-piscine-c-00" -- sr_run
want_out "submit: ... and the line is called malformed" \
	'malformed .submit-remotes line (no "=" before any comment)' -- sr_run

# 10. WHAT GETS PUSHED IS WRITTEN DOWN, and -n lists it: the deliverable as it
#     is on disk, ignored files included, build products out. The list comes
#     from the same staging function as the push, so it cannot disagree.
printf 'c-piscine/c-piscine-c-00=git@example.invalid:list\n' > "$WORK/sr/ws/.submit-remotes"
_srd="$WORK/sr/ws/c-piscine/c-piscine-c-00/deliverable"
printf 'int\tg_x;\n' > "$_srd/ex00/ft_x.c"
printf '0: zero\n' > "$_srd/ex00/numbers.dict"
printf 'numbers.dict\n' > "$_srd/ex00/.gitignore"
printf 'obj' > "$_srd/ex00/ft_x.o"
want_out "submit: -n lists a file it would push" "ex00/ft_x.c" -- sr_run
want_out "submit: ... an ignored one too" "ex00/numbers.dict" -- sr_run
want_broken_none "submit: ... but no build product" "ft_x.o" -- sr_run
want_green "submit: ... and the dry run leaves no .git behind" -- test ! -e "$_srd/.git"

# 11. THE PUSH ITSELF, end to end, against a local bare repository -- no arm
#     ever ran it. Submit used to re-initialise history every time, so every
#     re-submit needed -f, and -f on a group repository replaced a teammate's
#     work. Now it builds on the remote's branch: the bare repository refuses
#     any push that is not a fast-forward, a teammate pushes in between, and
#     the re-submit must still go through, on top of their commit.
mkdir -p "$WORK/se/ws/c-piscine/c-piscine-c-00/deliverable/ex00"
: > "$WORK/se/ws/c-piscine/c-piscine-c-00/BUILD.bazel"
git init -q --bare -b master "$WORK/se/remote.git"
git --git-dir="$WORK/se/remote.git" config receive.denyNonFastForwards true
printf 'c-piscine/c-piscine-c-00=%s\n' "$WORK/se/remote.git" > "$WORK/se/ws/.submit-remotes"
_sed="$WORK/se/ws/c-piscine/c-piscine-c-00/deliverable"
printf 'one\n' > "$_sed/ex00/a.txt"
printf 'obj' > "$_sed/ex00/a.o"
# SE_HOOKS, when set, is a hooks directory every git command in the run uses:
# deliverable/.git is rebuilt on each submit, so a hook cannot be put in it,
# and git's environment config is the one way in.
SE_HOOKS=""
se_run() {
	sb_env BUILD_WORKSPACE_DIRECTORY="$WORK/se/ws" \
		${SE_HOOKS:+GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath "GIT_CONFIG_VALUE_0=$SE_HOOKS"} \
		"$SH" "$TOOLS/submit.sh" --no-gate "$@" > "$WORK/se/log" 2>&1
}
se_tree() { git --git-dir="$WORK/se/remote.git" ls-tree -r --name-only master; }
want_green "submit: a first push to an empty remote" -- se_run c-piscine-c-00
want_green "submit: ... pushes the deliverable" -- \
	sh -c '[ "$(git --git-dir="$1" show master:ex00/a.txt)" = one ]' _ "$WORK/se/remote.git"
want_broken_none "submit: ... without its build products" "a.o" -- se_tree
_se_first=$(git --git-dir="$WORK/se/remote.git" rev-parse master 2>/dev/null)
# The teammate: their own clone, their own commit, pushed the ordinary way --
# a file of their own, and their version of one of ours.
git clone -q "$WORK/se/remote.git" "$WORK/se/mate" > /dev/null 2>&1
mkdir -p "$WORK/se/mate/ex00"
printf 'mate\n' > "$WORK/se/mate/ex00/mate.txt"
printf 'mate-a\n' > "$WORK/se/mate/ex00/a.txt"
{
	git -C "$WORK/se/mate" add ex00/mate.txt ex00/a.txt
	git -C "$WORK/se/mate" -c user.name=mate -c user.email=mate@42.fr commit -q -m mate
	git -C "$WORK/se/mate" push -q origin master
} > /dev/null 2>&1
_se_mate=$(git -C "$WORK/se/mate" rev-parse HEAD 2>/dev/null)
want_green "submit: ...the teammate's commit reached the remote" -- \
	git --git-dir="$WORK/se/remote.git" cat-file -e "$_se_mate^{commit}"
printf 'two\n' > "$_sed/ex00/a.txt"
want_green "submit: a re-submit goes through with no -f" -- se_run c-piscine-c-00
want_green "submit: ... on top of the teammate's commit" -- \
	git --git-dir="$WORK/se/remote.git" merge-base --is-ancestor "$_se_mate" master
want_green "submit: ... which is on top of the first" -- \
	git --git-dir="$WORK/se/remote.git" merge-base --is-ancestor "$_se_first" "$_se_mate"
want_green "submit: ... carrying the new deliverable" -- \
	sh -c '[ "$(git --git-dir="$1" show master:ex00/a.txt)" = two ]' _ "$WORK/se/remote.git"
want_green "submit: ... saying what it takes off the tip" -- \
	sh -c 'grep -q "takes them off its tip" "$1" && grep -q "ex00/mate.txt" "$1"' _ "$WORK/se/log"
want_green "submit: ... and whose version of a file it replaces" -- \
	sh -c 'grep -q "was not yours but mate <mate@42.fr>" "$1" &&
		grep -qx " *ex00/a.txt" "$1"' _ "$WORK/se/log"
# The negative premise of that NOTE: a re-submit over your OWN last push
# replaces your own files, which is the point of re-submitting, not news.
printf 'three\n' > "$_sed/ex00/a.txt"
want_green "submit: a re-submit over your own push goes through" -- se_run c-piscine-c-00
want_green "submit: ... and is pushed" -- \
	sh -c '[ "$(git --git-dir="$1" show master:ex00/a.txt)" = three ]' _ "$WORK/se/remote.git"
want_broken_none "submit: ... with no NOTE about someone else's files" \
	"was not yours" -- cat "$WORK/se/log"
# A teammate's push of OTHER files does not make yours theirs. The NOTE named
# every file that differed from the tip whenever the last push was not yours,
# so a file only you ever touched was called "theirs" and "replaced".
{
	git -C "$WORK/se/mate" fetch -q origin
	git -C "$WORK/se/mate" reset -q --hard origin/master
	mkdir -p "$WORK/se/mate/ex01"
	printf 'b\n' > "$WORK/se/mate/ex01/b.txt"
	git -C "$WORK/se/mate" add ex01/b.txt
	git -C "$WORK/se/mate" -c user.name=mate -c user.email=mate@42.fr commit -q -m b
	git -C "$WORK/se/mate" push -q origin master
} > /dev/null 2>&1
printf 'three-b\n' > "$_sed/ex00/a.txt"
want_green "submit: a re-submit after a teammate's push of other files" -- \
	se_run c-piscine-c-00
want_green "submit: ... is pushed" -- \
	sh -c '[ "$(git --git-dir="$1" show master:ex00/a.txt)" = three-b ]' _ "$WORK/se/remote.git"
want_broken_none "submit: ... and does not call your own file theirs" \
	"was not yours" -- cat "$WORK/se/log"
_se_second=$(git --git-dir="$WORK/se/remote.git" rev-parse master 2>/dev/null)
want_green "submit: an unchanged deliverable is not pushed again" -- se_run c-piscine-c-00
want_green "submit: ... so the remote is where it was" -- \
	test "$(git --git-dir="$WORK/se/remote.git" rev-parse master 2>/dev/null)" = "$_se_second"
# An emptied deliverable against a remote that has files: nothing to commit
# an empty tree from, so nothing is pushed and the remote keeps its files.
mv "$_sed/ex00" "$WORK/se/ex00.aside"
want_green "submit: an empty deliverable is not pushed" -- se_run c-piscine-c-00
want_green "submit: ... says so" -- grep -q "nothing to push" "$WORK/se/log"
want_green "submit: ... and the remote is where it was" -- \
	test "$(git --git-dir="$WORK/se/remote.git" rev-parse master 2>/dev/null)" = "$_se_second"
mv "$WORK/se/ex00.aside" "$_sed/ex00"
# A fetch that fails -- the first contact with the remote, which gates every
# submit. Here a path with no repository at it, which git's error words
# classify as neither the network nor the SSH key.
cp "$WORK/se/ws/.submit-remotes" "$WORK/se/remotes.aside"
printf 'c-piscine/c-piscine-c-00=%s\n' "$WORK/se/nowhere.git" > "$WORK/se/ws/.submit-remotes"
want_red "submit: a fetch that fails fails the run" -- se_run c-piscine-c-00
want_green "submit: ... and says the fetch failed" -- \
	grep -q "fetch FAILED for c-piscine/c-piscine-c-00" "$WORK/se/log"
mv "$WORK/se/remotes.aside" "$WORK/se/ws/.submit-remotes"
# The race: a teammate pushes between submit's fetch and its push. The push is
# then refused as not a fast-forward, and what the student reads must be that,
# and "run it again" -- never advice to force it, which is what the old message
# gave for every failure it could not name. The teammate is a post-commit hook
# that moves the remote's branch once.
mkdir -p "$WORK/se/hooks"
cat > "$WORK/se/hooks/post-commit" <<HOOK
#!/bin/sh
[ -e "$WORK/se/raced" ] && exit 0
: > "$WORK/se/raced"
c=\$(git --git-dir="$WORK/se/remote.git" -c user.name=mate -c user.email=mate@42.fr \\
	commit-tree -p master -m race 'master^{tree}') &&
	git --git-dir="$WORK/se/remote.git" update-ref refs/heads/master "\$c"
HOOK
chmod +x "$WORK/se/hooks/post-commit"
printf 'four\n' > "$_sed/ex00/a.txt"
SE_HOOKS="$WORK/se/hooks"
want_red "submit: a push the remote moved past fails" -- se_run c-piscine-c-00
SE_HOOKS=""
want_green "submit: ... says a push came in between" -- \
	grep -q "moved on after the fetch" "$WORK/se/log"
want_broken_none "submit: ... and never suggests forcing" "with -f" -- cat "$WORK/se/log"
_se_race=$(git --git-dir="$WORK/se/remote.git" rev-parse master 2>/dev/null)
want_green "submit: ... and the next submit builds on that push" -- se_run c-piscine-c-00
want_green "submit: ... keeping it in the history" -- \
	git --git-dir="$WORK/se/remote.git" merge-base --is-ancestor "$_se_race" master
want_broken "submit: -f is refused, and says why" "never force-pushes" -- \
	sb_env BUILD_WORKSPACE_DIRECTORY="$WORK/se/ws" \
	"$SH" "$TOOLS/submit.sh" --no-gate -f c-piscine-c-00

# A BUILT PROGRAM in deliverable/ blocks the module (finding 163). The tree the
# tests read is the sources, never a program built from them, so pushing one
# pushes a tree nobody tested. Two shapes: an ELF file under any name (seven
# bytes of ELF header are all the check reads), and a file named like a
# program a c_make() in the BUILD file builds, whatever it holds. Neither is
# pushed, the remote stays where it was, and -n says what it would refuse.
_se_block=$(git --git-dir="$WORK/se/remote.git" rev-parse master 2>/dev/null)
printf 'five\n' > "$_sed/ex00/a.txt"
printf '\177ELF\002\001\001' > "$_sed/ex00/prog"
want_red "submit: an ELF file in deliverable/ blocks the module" -- se_run c-piscine-c-00
want_green "submit: ... saying what to remove, and how" -- \
	sh -c 'grep -q "BLOCKED" "$1" && grep -qx " *ex00/prog" "$1" &&
		grep -q "make fclean" "$1"' _ "$WORK/se/log"
want_green "submit: ... and the remote is where it was" -- \
	test "$(git --git-dir="$WORK/se/remote.git" rev-parse master 2>/dev/null)" = "$_se_block"
rm -f "$_sed/ex00/prog"
# The same under a name git quotes. A plain ls-files C-quotes a name holding
# '"' or '\' -- Shell 01 ex05's turn-in has both -- and the quoted name is no
# file on disk, so it was never looked inside. And a Mach-O program, the
# ELF of a campus Mac: its 64-bit magic as a little-endian file holds it.
printf '\177ELF\002\001\001' > "$_sed/ex00/pr\"o\\g"
want_red "submit: an ELF under a name git quotes blocks it too" -- se_run c-piscine-c-00
want_green "submit: ... named as it is on disk" -- grep -qxF '                ex00/pr"o\g' "$WORK/se/log"
rm -f "$_sed/ex00/pr\"o\\g"
printf '\317\372\355\376\007\000\000\001' > "$_sed/ex00/prog"
want_red "submit: a Mach-O file blocks it" -- se_run c-piscine-c-00
want_green "submit: ... and the remote is where it was" -- \
	test "$(git --git-dir="$WORK/se/remote.git" rev-parse master 2>/dev/null)" = "$_se_block"
rm -f "$_sed/ex00/prog"
printf 'c_make(\n    num = "00",\n    artifact = "selftest-prog",\n)\n' \
	> "$WORK/se/ws/c-piscine/c-piscine-c-00/BUILD.bazel"
printf '#!/bin/sh\n' > "$_sed/ex00/selftest-prog"
want_red "submit: a file named like the module's program blocks it" -- se_run c-piscine-c-00
want_green "submit: ... and names it" -- grep -qx " *ex00/selftest-prog" "$WORK/se/log"
want_red "submit: -n says it would be blocked" -- se_run -n c-piscine-c-00
want_green "submit: ... in those words" -- grep -q "would be BLOCKED" "$WORK/se/log"
rm -f "$_sed/ex00/selftest-prog"
want_green "submit: with it gone, the module is pushed" -- se_run c-piscine-c-00
want_green "submit: ... and the push carries no program" -- \
	sh -c '! git --git-dir="$1" ls-tree -r --name-only master | grep -q prog' _ "$WORK/se/remote.git"
: > "$WORK/se/ws/c-piscine/c-piscine-c-00/BUILD.bazel"
# --url pushes to the repository it names, and the one .submit-remotes names
# is left where it was.
git init -q --bare -b master "$WORK/se/given.git"
_se_kept=$(git --git-dir="$WORK/se/remote.git" rev-parse master 2>/dev/null)
want_green "submit: --url pushes to the repository it names" -- \
	se_run c-piscine-c-00 --url "$WORK/se/given.git"
want_green "submit: ... the deliverable as it is on disk" -- \
	sh -c 'git --git-dir="$1" show master:ex00/a.txt | cmp -s - "$2"' _ \
	"$WORK/se/given.git" "$_sed/ex00/a.txt"
want_green "submit: ... and not to the one .submit-remotes names" -- \
	test "$(git --git-dir="$WORK/se/remote.git" rev-parse master 2>/dev/null)" = "$_se_kept"
# ...and as it is on disk, byte for byte, whatever the owner's global git
# configuration says. A core.autocrlf of true or input (common on WSL and
# Windows), or a core.attributesFile with a text rule, stored a CRLF file the
# layers had tested as LF, so the tree pushed was not the tree tested. The
# global file here is the arm's own (GIT_CONFIG_GLOBAL), each push goes to a
# repository of its own, and the CRLF file is taken away after.
printf 'a\r\nb\r\n' > "$_sed/ex00/crlf.txt"
printf '[core]\n\tautocrlf = true\n' > "$WORK/se/autocrlf.gitconfig"
printf '* text eol=lf\n' > "$WORK/se/text.attributes"
printf '[core]\n\tattributesFile = %s\n' "$WORK/se/text.attributes" > "$WORK/se/attr.gitconfig"
git init -q --bare -b master "$WORK/se/crlf.git"
git init -q --bare -b master "$WORK/se/attr.git"
se_global() {  # se_global GITCONFIG ARG...: se_run with GITCONFIG as the global git file
	_seg=$1; shift
	sb_env BUILD_WORKSPACE_DIRECTORY="$WORK/se/ws" \
		GIT_CONFIG_GLOBAL="$_seg" \
		"$SH" "$TOOLS/submit.sh" --no-gate "$@" > "$WORK/se/log" 2>&1
}
want_green "submit: a global core.autocrlf=true push goes through" -- \
	se_global "$WORK/se/autocrlf.gitconfig" c-piscine-c-00 --url "$WORK/se/crlf.git"
want_green "submit: ... keeping a CRLF file's CRs" -- \
	sh -c 'git --git-dir="$1" show master:ex00/crlf.txt | cmp -s - "$2"' _ \
	"$WORK/se/crlf.git" "$_sed/ex00/crlf.txt"
want_green "submit: a global core.attributesFile push goes through" -- \
	se_global "$WORK/se/attr.gitconfig" c-piscine-c-00 --url "$WORK/se/attr.git"
want_green "submit: ... keeping a CRLF file's CRs too" -- \
	sh -c 'git --git-dir="$1" show master:ex00/crlf.txt | cmp -s - "$2"' _ \
	"$WORK/se/attr.git" "$_sed/ex00/crlf.txt"
rm -f "$_sed/ex00/crlf.txt"

# 11b. THE SERVER'S HOST KEY. ssh ends with "Host key verification failed"
#     for a host known_hosts has no line for, and for one whose key CHANGED,
#     after its "REMOTE HOST IDENTIFICATION HAS CHANGED" banner. Both read as
#     an SSH-key refusal, and the fix for one ran for both: whatever
#     ssh-keyscan received was appended to known_hosts and the fetch tried
#     again, so a key nobody checked was trusted from then on, and every
#     refused key added the line once more. A stand-in git fails each fetch
#     and push with ssh's words ($WORK/hk/says), and stand-ins for ssh-keyscan
#     and ssh-keygen log each call: nothing here reaches a network, and the
#     HOME is the arm's own.
mkdir -p "$WORK/hk/bin" "$WORK/hk/home/.ssh"
_hk_git=$(command -v git)
cat > "$WORK/hk/bin/git" <<'HK_GIT'
#!/bin/sh
sub() {
	while [ $# -gt 0 ]; do
		case $1 in -C | -c) shift 2 ;; -*) shift ;; *) echo "$1"; return ;; esac
	done
}
case $(sub "$@") in
	fetch | push) echo "$(sub "$@")" >> "$HK_LOG"; cat "$HK_SAYS" >&2; exit 128 ;;
esac
exec "$HK_GIT" "$@"
HK_GIT
cat > "$WORK/hk/bin/ssh-keyscan" <<'HK_SCAN'
#!/bin/sh
echo "keyscan $*" >> "$HK_LOG"
for a; do h=$a; done
echo "$h ssh-ed25519 AAAAstand-in-scanned"
HK_SCAN
# ssh-keygen -F HOST -f FILE: 0 with a line for HOST, 1 with none, 255 with
# no FILE, as OpenSSH's does.
cat > "$WORK/hk/bin/ssh-keygen" <<'HK_KEYGEN'
#!/bin/sh
echo "keygen $*" >> "$HK_LOG"
[ "$1" = -F ] && [ "$3" = -f ] || exit 2
[ -e "$4" ] || exit 255
grep -q "^$2 " "$4"
HK_KEYGEN
chmod +x "$WORK/hk/bin/git" "$WORK/hk/bin/ssh-keyscan" "$WORK/hk/bin/ssh-keygen"
_hk_kh="$WORK/hk/home/.ssh/known_hosts"
hk_run() {  # the module pushed to git@host.example.invalid, ssh's words in $WORK/hk/says
	: > "$WORK/hk/log"
	sb_env PATH="$WORK/hk/bin:$PATH" HK_LOG="$WORK/hk/log" HK_SAYS="$WORK/hk/says" \
		HK_GIT="$_hk_git" HOME="$WORK/hk/home" XDG_CONFIG_HOME="$WORK/hk/home/.config" \
		BUILD_WORKSPACE_DIRECTORY="$WORK/se/ws" \
		"$SH" "$TOOLS/submit.sh" --no-gate c-piscine-c-00 \
		--url git@host.example.invalid:x > "$WORK/hk/out" 2>&1
}
hk_count() { grep -c -- "$1" "$2"; }  # hk_count PATTERN FILE: its lines that match
# A public key under a default name, so a refusal read as the student's key
# reaches the retry.
printf 'ssh-ed25519 AAAAstand-in-public marvin@42.fr\n' > "$WORK/hk/home/.ssh/id_ed25519.pub"
printf 'host.example.invalid ssh-ed25519 AAAAstand-in-recorded\n' > "$_hk_kh"
cp "$_hk_kh" "$WORK/hk/kh.before"
printf '%s\n' \
	'@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@' \
	'@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @' \
	'@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@' \
	'IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!' \
	'Offending ED25519 key in /home/you/.ssh/known_hosts:1' \
	'Host key for host.example.invalid has changed and you have requested strict checking.' \
	'Host key verification failed.' \
	'fatal: Could not read from remote repository.' > "$WORK/hk/says"
want_red "submit: a CHANGED host key fails the fetch" -- hk_run
want_green "submit: ... adds nothing to known_hosts" -- cmp -s "$_hk_kh" "$WORK/hk/kh.before"
want_green "submit: ... scans no key" -- test "$(hk_count '^keyscan' "$WORK/hk/log")" = 0
want_green "submit: ... and tries the fetch once" -- test "$(hk_count '^fetch' "$WORK/hk/log")" = 1
want_out "submit: ... saying the host's key changed" "host key is NOT the one" -- \
	cat "$WORK/hk/out"
want_broken_none "submit: ... and not that the student's key is wrong" \
	"SSH-KEY reasons" -- cat "$WORK/hk/out"
printf 'git@host.example.invalid: Permission denied (publickey).\nfatal: Could not read from remote repository.\n' \
	> "$WORK/hk/says"
want_red "submit: a refused key, the host known, fails the fetch" -- hk_run
want_green "submit: ... adds no second line for the host" -- cmp -s "$_hk_kh" "$WORK/hk/kh.before"
want_green "submit: ... scans no key" -- test "$(hk_count '^keyscan' "$WORK/hk/log")" = 0
want_out "submit: ... and shows the public key to register" "AAAAstand-in-public" -- \
	cat "$WORK/hk/out"
rm -f "$_hk_kh"
printf 'Host key verification failed.\nfatal: Could not read from remote repository.\n' \
	> "$WORK/hk/says"
want_red "submit: an unknown host fails the fetch" -- hk_run
want_green "submit: ... and its key is added, once" -- \
	test "$(hk_count '^host\.example\.invalid ' "$_hk_kh")" = 1
want_red "submit: ... refused again, it fails again" -- hk_run
want_green "submit: ... and adds no second copy" -- \
	test "$(hk_count '^host\.example\.invalid ' "$_hk_kh")" = 1

# An unknown --gate-level lists the levels and the layers each adds, read from
# docs/reference.md's layer table -- the one written copy of the ladder -- so
# the fixture's made-up layer is what it prints. With no table, the names alone.
mkdir -p "$WORK/se/ws/docs"
printf '| `norm` | basic | x |\n| `widget` | robust | y |\n' > "$WORK/se/ws/docs/reference.md"
want_broken "submit: an unknown level lists the reference's ladder" 'robust    + widget' -- \
	sb_env BUILD_WORKSPACE_DIRECTORY="$WORK/se/ws" \
	"$SH" "$TOOLS/submit.sh" --gate-level nope
rm -rf "$WORK/se/ws/docs"
want_broken "submit: ... and the level names with no table" 'basic, strict, robust, complete' -- \
	sb_env BUILD_WORKSPACE_DIRECTORY="$WORK/se/ws" \
	"$SH" "$TOOLS/submit.sh" --gate-level nope

# 12. A GATE THAT DOES NOT BUILD. Bazel exits 1 for a build error, and here that
#    is most often the student's own code: a syntax error, a leftover main() or
#    a missing turn-in file. The gate used to call exit 1 "NOT a verdict on
#    your code". A stand-in bazel on PATH replays the stderr FAKE_BAZEL_ERR
#    names with the status FAKE_BAZEL_RC asks for, and the stdout
#    FAKE_BAZEL_OUT names when that is set; `shutdown` succeeds. It
#    writes each command line it is given to FAKE_BAZEL_ARGV, one per line,
#    and the advisory run (the one filtered on -manual) exits with
#    FAKE_BAZEL_ADV_RC when that is set, after the stdout FAKE_BAZEL_ADV_OUT
#    and the stderr FAKE_BAZEL_ADV_ERR name (section 14). The row's remote is
#    example.invalid, and a blocked gate never reaches the push anyway.
#
#    Each fixture puts a line on the stream real Bazel prints it on
#    (measured on 9.2.0, with both streams sent to files as the gate sends
#    them): the build's errors, its INFO lines and each "FAIL: //t (see
#    LOG)" on stderr; the summary, one "//t  FAILED in" line per red test
#    with its log under it, and "Executed N out of M tests", on stdout, as
#    is --test_output=errors' "Test output for" block. So a reader of the
#    gate's output that reads the wrong stream finds nothing here, as it
#    would in a real run.
#
#    build.err is the stderr of a real capture (C 11 ex00, a semicolon dropped
#    from its stub): the compiler line comes early and more than fifteen lines
#    follow it, as they do in a real run, so only the filter that looks for it
#    can quote it -- the old branch printed the last fifteen lines, and an arm
#    over a four-line stderr could not tell the two apart.
mkdir -p "$WORK/subm/bin"
{
	printf '#!/bin/sh\n[ -z "${FAKE_BAZEL_ARGV:-}" ] || printf "argv: %%s\\n" "$*" >> "$FAKE_BAZEL_ARGV"\n'
	printf 'for a; do [ "$a" = shutdown ] && exit 0; done\n'
	printf 'case " $* " in *" --test_tag_filters=-manual "*)\n'
	printf '\t[ -z "${FAKE_BAZEL_ADV_OUT:-}" ] || cat "$FAKE_BAZEL_ADV_OUT"\n'
	printf '\t[ -z "${FAKE_BAZEL_ADV_ERR:-}" ] || cat "$FAKE_BAZEL_ADV_ERR" >&2\n'
	printf '\t[ -z "${FAKE_BAZEL_ADV_RC:-}" ] || exit "$FAKE_BAZEL_ADV_RC" ;;\nesac\n'
	printf '[ -z "${FAKE_BAZEL_OUT:-}" ] || cat "$FAKE_BAZEL_OUT"\n'
	printf 'cat "$FAKE_BAZEL_ERR" >&2\nexit "${FAKE_BAZEL_RC:-1}"\n'
} > "$WORK/subm/bin/bazel"
chmod +x "$WORK/subm/bin/bazel"
{
	printf '%s\n' \
		"INFO: Analyzed 162 targets (0 packages loaded, 0 targets configured)." \
		"ERROR: /home/you/42/c-piscine/c-piscine-c-11/BUILD.bazel:3:11: Compiling c-piscine/c-piscine-c-11/deliverable/ex00/ft_foreach.c failed: (Exit 1): clang.sh failed: error executing CppCompile command (from cc_library rule target //c-piscine/c-piscine-c-11:ft_foreach) tools/cc_toolchain/clang.sh -U_FORTIFY_SOURCE -fstack-protector -Wall -Wthread-safety -Wself-assign -Wno-free-nonheap-object -fcolor-diagnostics -fno-omit-frame-pointer -MD -MF ... (remaining 22 arguments skipped)" \
		"" \
		"Use --sandbox_debug to see verbose messages from the sandbox and retain the sandbox build root for debugging" \
		"c-piscine/c-piscine-c-11/deliverable/ex00/ft_foreach.c:16:3: error: expected expression" \
		"        (void)length;" \
		"         ^" \
		"2 errors generated."
	for _t in ex01_output ex01_diff ex02_output ex02_diff ex03_output ex03_diff \
		ex04_output ex04_diff ex05_output ex05_unknownword_output ex06_output \
		ex06_diff ex07_output ex07_diff; do
		printf 'FAIL: //c-piscine/c-piscine-c-11:%s (Exit 1) (see /tmp/bazelcache/x/execroot/_main/bazel-out/k8-fastbuild/testlogs/c-piscine/c-piscine-c-11/%s/test.log)\n' "$_t" "$_t"
	done
	printf '%s\n' \
		"INFO: Build succeeded for only 153 of 162 top-level targets" \
		"INFO: Found 23 targets and 139 test targets..." \
		"ERROR: Build did NOT complete successfully"
} > "$WORK/subm/build.err"
#    ...and a summary on stdout, one line per FAIL above. This one is
#    modelled, not captured: it is not the stdout of the run build.err comes
#    from, but written from that run's FAIL lines in the layout a real run's
#    summary was measured to have (above). A captured exit-1 summary may
#    hold lines this one does not.
{
	for _t in ex01_output ex01_diff ex02_output ex02_diff ex03_output ex03_diff \
		ex04_output ex04_diff ex05_output ex05_unknownword_output ex06_output \
		ex06_diff ex07_output ex07_diff; do
		printf '//c-piscine/c-piscine-c-11:%-40s FAILED in 0.1s\n' "$_t"
		printf '  /tmp/bazelcache/x/execroot/_main/bazel-out/k8-fastbuild/testlogs/c-piscine/c-piscine-c-11/%s/test.log\n' "$_t"
	done
} > "$WORK/subm/build.out"
#    harness.err is the stderr of the oracle's entry point broken under answers
#    that pass (the capture first_red's harness arm keeps): exit 1 as well, and
#    no line names a file of the student's.
cat > "$WORK/subm/harness.err" <<'SB_HARNESS'
INFO: Analyzed 143 targets (0 packages loaded, 160 targets configured).
ERROR: /home/you/42/oracle/BUILD.bazel:9:12: Compiling Rust bin oracle (24 files) failed: (Exit 1): process_wrapper failed: error executing Rustc command (from rust_binary rule target //oracle:oracle) bazel-out/k8-opt-exec/bin/external/rules_rust+/util/process_wrapper/process_wrapper --subst 'pwd=${pwd}' --subst 'exec_root=${exec_root}' --subst 'output_base=${output_base}' -- ... (remaining 2 arguments skipped)

Use --sandbox_debug to see verbose messages from the sandbox and retain the sandbox build root for debugging
error: this file contains an unclosed delimiter
   --> oracle/src/main.rs:160:14
    |
160 | fn broken( {
    |          - -^
    |          | |
    |          | unclosed delimiter
    |          unclosed delimiter

error: aborting due to 1 previous error

INFO: Build succeeded for only 120 of 143 top-level targets
INFO: Found 26 targets and 117 test targets...
INFO: Elapsed time: 7.903s, Critical Path: 5.78s
INFO: 96 processes: 586 action cache hit, 2 internal, 188 processwrapper-sandbox.
ERROR: Build did NOT complete successfully
SB_HARNESS
sb_make 'c-piscine-c-00=git@example.invalid:gate' gate
sb_gate() {  # sb_gate STATUS FIXTURE: FIXTURE.err on stderr, FIXTURE.out (if any) on stdout
	_sbo=/dev/null
	[ ! -f "$WORK/subm/$2.out" ] || _sbo="$WORK/subm/$2.out"
	sb_env PATH="$WORK/subm/bin:$PATH" FAKE_BAZEL_RC="$1" FAKE_BAZEL_ERR="$WORK/subm/$2.err" \
		FAKE_BAZEL_OUT="$_sbo" FAKE_BAZEL_ARGV="$WORK/subm/argv" \
		BUILD_WORKSPACE_DIRECTORY="$WORK/subm/ws" \
		"$SH" "$WORK/subm/gate.sh" c-piscine-c-00
}
want_out "submit: a gate that does not build says so" \
	"the module does NOT BUILD" -- once sb_gate 1 build
want_out "submit: ... quotes the compiler's own line" \
	"ft_foreach.c:16:3: error: expected expression" -- once sb_gate 1 build
want_broken_none "submit: ... and never calls it no verdict on the code" \
	"NOT a verdict" -- once sb_gate 1 build
want_red "submit: ... and fails the run" -- once sb_gate 1 build
#    link.err: a leftover main() in C 01 ex06 (the error lines of the capture
#    first_red's link arm keeps, written again here: that capture is another
#    section's fixture). The linker names object files only, so what ties it
#    to the student is the exercise target whose link failed.
cat > "$WORK/subm/link.err" <<'SB_LINK'
ERROR: /home/you/42/c-piscine/c-piscine-c-01/BUILD.bazel:49:11: Linking c-piscine/c-piscine-c-01/ex06_bin failed: (Exit 1): clang.sh failed: error executing CppLink command (from cc_binary rule target //c-piscine/c-piscine-c-01:ex06_bin) tools/cc_toolchain/clang.sh @bazel-out/k8-fastbuild/bin/c-piscine/c-piscine-c-01/ex06_bin-0.params
Use --sandbox_debug to see verbose messages from the sandbox and retain the sandbox build root for debugging
external/+deb_archive+binutils_x86_64_linux_gnu/usr/bin/x86_64-linux-gnu-ld.gold: error: bazel-out/k8-fastbuild/bin/c-piscine/c-piscine-c-01/_objs/ft_strlen/ft_strlen.pic.o: multiple definition of 'main'
external/+deb_archive+binutils_x86_64_linux_gnu/usr/bin/x86_64-linux-gnu-ld.gold: bazel-out/k8-fastbuild/bin/c-piscine/c-piscine-c-01/_objs/ex06_bin/test_strlen.pic.o: previous definition here
clang: error: linker command failed with exit code 1 (use -v to see invocation)
SB_LINK
want_out "submit: a leftover main() does not build either" \
	"the module does NOT BUILD" -- sb_gate 1 link
# The negative premise: exit 1 with no line naming a file of the student's is
# a stop, not code that does not build, and it is still not pushed.
want_broken_none "submit: a harness build error is no DOES NOT BUILD" \
	"does NOT BUILD" -- once sb_gate 1 harness
want_out "submit: ... it says the build stopped" \
	"the build STOPPED" -- once sb_gate 1 harness
want_out "submit: ... and quotes the first errors" \
	"error: this file contains an unclosed delimiter" -- once sb_gate 1 harness
want_red "submit: ... and fails the run" -- once sb_gate 1 harness
# A bad command line (2) is still no verdict on the code.
want_out "submit: a gate that could not run is still no verdict" \
	"NOT a verdict" -- sb_gate 2 build
# 13. A GATE STOPPED BY A FILES TEST (3): the rule is the files layer's, and
#    submit only shows its report -- the file that would be pushed and
#    should not be -- from the log the gate's stderr names, instead of
#    leaving it behind a command to run (finding 052).
mkdir -p "$WORK/subm/logs/deliverable_files"
printf '%s\n' 'files_test: c-piscine/c-piscine-c-00/deliverable' '' \
	"  THESE ARE IN NO EXERCISE'S FOLDER. This subject gives each exercise a" \
	'    notes.txt' '' '  RESULT: FAIL — the subject asks for its exercises'"'"' folders and' \
	> "$WORK/subm/logs/deliverable_files/test.log"
printf 'FAIL: //c-piscine-c-00:deliverable_files (Exit 1) (see %s)\n' \
	"$WORK/subm/logs/deliverable_files/test.log" > "$WORK/subm/files.err"
printf '//c-piscine-c-00:deliverable_files  FAILED in 0.1s\n  %s\n\nExecuted 1 out of 1 test: 1 fails locally.\n' \
	"$WORK/subm/logs/deliverable_files/test.log" > "$WORK/subm/files.out"
want_out "submit: a gate stopped by a files test shows its report" \
	"notes.txt" -- once sb_gate 3 files
want_red "submit: ... and fails the run" -- once sb_gate 3 files
want_broken_none "submit: a gate stopped by another test shows none" \
	"RESULT:" -- sb_gate 3 build
# 14. THE GATE RUNS BAZEL AS THE STUDENT TYPES IT (V98), ON A SERVER IT HAS
#    JUST STARTED, AND TRUSTING NO CACHE. It had an output base of its own,
#    for a lock `bazel run` was said to hold on the main one while the program
#    it started runs. Bazel holds none then (a toy, 2026-10-09: a plain `bazel
#    test`, and a `bazel shutdown` too, inside `bazel run` came back at once),
#    and a second base cost a second JVM and a second build of everything. So
#    the gate passes no startup option: no output base, no idle limit. But
#    the server and the caches it now shares are the ones a watch loop
#    leaves. A file saved while a test ran can leave a result, even a compiled
#    program, cached for the file's other contents, and only a `bazel
#    shutdown` followed by --nocache_test_results and --use_action_cache=false
#    healed that (V111). A gate that read such a result would push code its
#    own tests fail. So it shuts the server down once, before its first
#    module, and runs with both flags. The command it prints to re-run is the
#    command it ran.
sb_argv() {  # sb_argv STATUS FIXTURE: the gate's bazel command lines
	: > "$WORK/subm/argv"
	sb_gate "$@" > /dev/null 2>&1
	cat "$WORK/subm/argv"
}
want_out "submit: the gate runs bazel test as a student types it" \
	"argv: test //" -- once sb_argv 3 files
want_broken_none "submit: ... on no output base of its own" "--output_base" -- once sb_argv 3 files
want_broken_none "submit: ... with no idle limit" "--max_idle_secs" -- once sb_argv 3 files
sb_fresh() {  # the server shut down first, and once
	_sbf=$(once sb_argv "$@")
	printf '%s\n' "$_sbf"
	[ "$(printf '%s\n' "$_sbf" | sed -n 1p)" = "argv: shutdown" ] &&
		[ "$(printf '%s\n' "$_sbf" | grep -c '^argv: shutdown$')" = 1 ]
}
want_green "submit: ... on a server it started afresh, once, first" -- sb_fresh 3 files
want_out "submit: ... trusting no cached test result" \
	"--nocache_test_results" -- once sb_argv 3 files
want_out "submit: ... and no cached build" \
	"--use_action_cache=false" -- once sb_argv 3 files
want_out "submit: ... and the command it prints is the one it ran" \
	"--keep_going --nocache_test_results --use_action_cache=false" -- once sb_gate 3 files
want_broken_none "submit: ... and the command it prints names no base" \
	"--output_base" -- once sb_gate 3 files
#    A gate that passes runs the advisory pass, the module's tests above the
#    level, and on a red one prints the command to read it with: the same,
#    over the fixture with a real push (the se workspace and its local remote).
#    The advisory pass's red test is named in its summary, on stdout, as real
#    Bazel prints it, and its FAIL line is on stderr.
mkdir -p "$WORK/subm/logs/ex00_asan"
printf 'FAIL: //c-piscine/c-piscine-c-00:ex00_asan (Exit 1) (see %s)\n' \
	"$WORK/subm/logs/ex00_asan/test.log" > "$WORK/subm/adv.err"
printf '//c-piscine/c-piscine-c-00:ex00_asan  FAILED in 0.1s\n  %s\n\nExecuted 1 out of 1 test: 1 fails locally.\n' \
	"$WORK/subm/logs/ex00_asan/test.log" > "$WORK/subm/adv.out"
se_gated() {
	: > "$WORK/subm/argv"
	sb_env PATH="$WORK/subm/bin:$PATH" FAKE_BAZEL_RC=0 FAKE_BAZEL_ADV_RC=3 \
		FAKE_BAZEL_ADV_OUT="$WORK/subm/adv.out" FAKE_BAZEL_ADV_ERR="$WORK/subm/adv.err" \
		FAKE_BAZEL_ERR=/dev/null FAKE_BAZEL_ARGV="$WORK/subm/argv" \
		BUILD_WORKSPACE_DIRECTORY="$WORK/se/ws" \
		"$SH" "$TOOLS/submit.sh" c-piscine-c-00
}
se_gated_argv() { se_gated > /dev/null 2>&1; cat "$WORK/subm/argv"; }
want_out "submit: the advisory pass runs bazel test as typed too" \
	"argv: test //c-piscine/c-piscine-c-00/... --test_tag_filters=-manual --keep_going" -- se_gated_argv
want_out "submit: ... and prints that command to read it with" \
	"             bazel test //c-piscine/c-piscine-c-00/... --test_tag_filters=-manual --keep_going" -- once se_gated
want_out "submit: ... counting the red test above the gate" \
	'NOTE: 1 test(s) above the' -- once se_gated
want_out "submit: ... and naming it" \
	"             //c-piscine/c-piscine-c-00:ex00_asan" -- once se_gated
#    ...whatever SUBMIT_GATE the shell running this exports: the gate's level
#    is the fixture's, and an exported complete would leave nothing above it.
se_gated_exported() { ( SUBMIT_GATE=complete; export SUBMIT_GATE; se_gated ); }
want_out "submit: ... under an exported SUBMIT_GATE too" \
	'NOTE: 1 test(s) above the' -- se_gated_exported
#    want_out matches a substring, so the arms above hold while a flag is
#    added to what runs and left out of what is printed. The command each
#    prints is, word for word, the command the stand-in bazel was handed.
sb_ran() {  # sb_ran FILTER-WORD: the bazel test line logged with that filter
	sed -n 's/^argv: \(test .*\)$/\1/p' "$WORK/subm/argv" | grep -F -- "--test_tag_filters=$1 "
}
sb_same() {  # sb_same PRINTED RAN: the two, and whether they are one command
	printf 'printed: %s\nran:     %s\n' "$1" "$2"
	[ -n "$2" ] && [ "$1" = "$2" ]
}
sb_blocked_same() {
	: > "$WORK/subm/argv"
	_sbp=$(sb_gate 3 files 2>&1 | sed -n '/BLOCKED: tests are FAILING/{n;s/^ *bazel //p;}')
	sb_same "$_sbp" "$(sb_ran lvl_basic,-manual)"
}
sb_dry_same() {
	: > "$WORK/subm/argv"
	sb_gate 3 files > /dev/null 2>&1
	_sbp=$(sb_env PATH="$WORK/subm/bin:$PATH" FAKE_BAZEL_RC=3 FAKE_BAZEL_ERR=/dev/null \
		BUILD_WORKSPACE_DIRECTORY="$WORK/subm/ws" \
		"$SH" "$WORK/subm/gate.sh" -n c-piscine-c-00 2>&1 |
		sed -n 's/^ *dry-run: would gate on  bazel \(.*\)  (level: .*/\1/p')
	sb_same "$_sbp" "$(sb_ran lvl_basic,-manual)"
}
se_adv_same() {
	_sbp=$(se_gated 2>&1 | sed -n '/Read it with:/{n;s/^ *bazel //p;}')
	sb_same "$_sbp" "$(sb_ran -manual)"
}
want_green "submit: the BLOCKED command is the gate's, word for word" -- sb_blocked_same
want_green "submit: the dry run's gate command is the gate's too" -- sb_dry_same
want_green "submit: the advisory command printed is the one it ran" -- se_adv_same
#    Every status a red test can have is named, not FAILED alone. A pass
#    whose only red was a TIMEOUT (the upper layers' usual one), a NO STATUS
#    or an INCOMPLETE printed "NOTE: 0 test(s) above the gate are red" and
#    named nothing; and a red pass whose summary names no test says so.
se_adv() {  # se_adv SUMMARY: se_gated, the advisory pass's stdout $WORK/subm/adv_SUMMARY.out
	: > "$WORK/subm/argv"
	sb_env PATH="$WORK/subm/bin:$PATH" FAKE_BAZEL_RC=0 FAKE_BAZEL_ADV_RC=3 \
		FAKE_BAZEL_ADV_OUT="$WORK/subm/adv_$1.out" FAKE_BAZEL_ADV_ERR=/dev/null \
		FAKE_BAZEL_ERR=/dev/null FAKE_BAZEL_ARGV="$WORK/subm/argv" \
		BUILD_WORKSPACE_DIRECTORY="$WORK/se/ws" \
		"$SH" "$TOOLS/submit.sh" c-piscine-c-00
}
printf '//c-piscine/c-piscine-c-00:ex00_perf  TIMEOUT in 60.0s\n  %s\n' \
	"$WORK/subm/logs/ex00_perf/test.log" > "$WORK/subm/adv_timeout.out"
printf '//c-piscine/c-piscine-c-00:ex01_asan  NO STATUS\n' > "$WORK/subm/adv_nostatus.out"
printf '//c-piscine/c-piscine-c-00:ex02_cycles  INCOMPLETE\n' > "$WORK/subm/adv_incomplete.out"
printf 'ERROR: Build did NOT complete successfully\n' > "$WORK/subm/adv_none.out"
want_out "submit: an advisory TIMEOUT is named, with its status" \
	"             //c-piscine/c-piscine-c-00:ex00_perf  TIMEOUT" -- se_adv timeout
want_broken_none "submit: ... and never counted as no red" "NOTE: 0 test(s)" -- se_adv timeout
want_out "submit: an advisory NO STATUS is named, with its status" \
	"             //c-piscine/c-piscine-c-00:ex01_asan  NO STATUS" -- se_adv nostatus
want_broken_none "submit: ... and never counted as no red" "NOTE: 0 test(s)" -- se_adv nostatus
want_out "submit: an advisory INCOMPLETE is named, with its status" \
	"             //c-piscine/c-piscine-c-00:ex02_cycles  INCOMPLETE" -- se_adv incomplete
want_broken_none "submit: ... and never counted as no red" "NOTE: 0 test(s)" -- se_adv incomplete
want_out "submit: a red advisory pass naming no test says so" \
	"no line of its summary names one" -- se_adv none
want_broken_none "submit: ... and never counts it as no red" "NOTE: 0 test(s)" -- se_adv none
#    A temporary file submit could not make. run_gate says so by name
#    (GATE_WHY); the advisory pass printed "0 test(s) above the gate are red"
#    for a pass that never ran, the fetch read the shell's error as git's,
#    and the NOTE about a teammate's files was dropped without a word. Each
#    stand-in mktemp is earlier on PATH: the advisory one fails once the
#    stand-in bazel has run (after the gate made its own two files), the
#    fetch one fails every call that names no template (pushed_files' own
#    `mktemp -d` still works), and the teammate one fails only the call of
#    those numbered SE_MKTEMP_FAIL, counting in $WORK/se/mkcount: the fetch's
#    is the first, changed_since's the second, the push's the third.
mkdir -p "$WORK/subm/advbin" "$WORK/se/nomk" "$WORK/se/mknth"
printf '#!/bin/sh\n[ ! -e "%s" ] || exit 1\nexec %s "$@"\n' "$WORK/subm/gated" "$(command -v mktemp)" \
	> "$WORK/subm/advbin/mktemp"
printf '#!/bin/sh\n: > "%s"\nexec "%s" "$@"\n' "$WORK/subm/gated" "$WORK/subm/bin/bazel" \
	> "$WORK/subm/advbin/bazel"
printf '#!/bin/sh\n[ "$#" -gt 0 ] || exit 1\nexec %s "$@"\n' "$(command -v mktemp)" \
	> "$WORK/se/nomk/mktemp"
printf '#!/bin/sh\n[ "$#" -gt 0 ] || {\n\tn=$(($(cat "%s" 2>/dev/null || echo 0) + 1))\n\techo "$n" > "%s"\n\t[ "$n" != "$SE_MKTEMP_FAIL" ] || exit 1\n}\nexec %s "$@"\n' \
	"$WORK/se/mkcount" "$WORK/se/mkcount" "$(command -v mktemp)" > "$WORK/se/mknth/mktemp"
chmod +x "$WORK/subm/advbin/mktemp" "$WORK/subm/advbin/bazel" "$WORK/se/nomk/mktemp" \
	"$WORK/se/mknth/mktemp"
se_adv_nomk() {
	rm -f "$WORK/subm/gated"
	sb_env PATH="$WORK/subm/advbin:$WORK/subm/bin:$PATH" FAKE_BAZEL_RC=0 FAKE_BAZEL_ADV_RC=3 \
		FAKE_BAZEL_ADV_OUT="$WORK/subm/adv.out" FAKE_BAZEL_ADV_ERR=/dev/null \
		FAKE_BAZEL_ERR=/dev/null BUILD_WORKSPACE_DIRECTORY="$WORK/se/ws" \
		"$SH" "$TOOLS/submit.sh" c-piscine-c-00
}
# The words only the advisory NOTE prints: "(mktemp failed)" alone is also
# remote_git's, whose own mktemp the stand-in fails right after (the module
# has a remote), so an arm on it stayed green with the NOTE's branch gone.
want_out "submit: an advisory pass with no temporary file says so" \
	'tests above the "basic" gate were not run' -- se_adv_nomk
want_broken_none "submit: ... and counts no red for a pass never run" "NOTE: 0 test(s)" -- se_adv_nomk
rm -f "$WORK/subm/gated"
se_nomk() {  # se_run's push under --no-gate, the stand-in mktemp DIR earlier on PATH
	_sen=$1; shift
	sb_env PATH="$WORK/se/$_sen:$PATH" BUILD_WORKSPACE_DIRECTORY="$WORK/se/ws" \
		"$SH" "$TOOLS/submit.sh" --no-gate "$@" > "$WORK/se/log" 2>&1
}
printf 'nomk\n' > "$_sed/ex00/a.txt"
want_red "submit: a fetch with no temporary file fails" -- se_nomk nomk c-piscine-c-00
want_out "submit: ... saying mktemp failed" "(mktemp failed)" -- cat "$WORK/se/log"
want_broken_none "submit: ... and not as git's failure" "git's own words are above" -- \
	cat "$WORK/se/log"
git init -q --bare -b master "$WORK/se/cs.git"
printf 'cs-one\n' > "$_sed/ex00/a.txt"
want_green "submit: a first push to a group repository" -- \
	se_run c-piscine-c-00 --url "$WORK/se/cs.git"
{
	git clone -q "$WORK/se/cs.git" "$WORK/se/csmate"
	printf 'cs-mate\n' > "$WORK/se/csmate/ex00/a.txt"
	git -C "$WORK/se/csmate" add ex00/a.txt
	git -C "$WORK/se/csmate" -c user.name=mate -c user.email=mate@42.fr commit -q -m mate
	git -C "$WORK/se/csmate" push -q origin master
} > /dev/null 2>&1
printf 'cs-two\n' > "$_sed/ex00/a.txt"
rm -f "$WORK/se/mkcount"
SE_MKTEMP_FAIL=2
export SE_MKTEMP_FAIL
want_green "submit: a re-submit over a teammate's file, with no temporary file" -- \
	se_nomk mknth c-piscine-c-00 --url "$WORK/se/cs.git"
unset SE_MKTEMP_FAIL
want_green "submit: ... still names their file in the NOTE" -- \
	sh -c 'grep -q "was not yours but mate <mate@42.fr>" "$1" && grep -qx " *ex00/a.txt" "$1"' \
	_ "$WORK/se/log"

# 15. .submit-level IS THE WORKSPACE'S, at its root, and no other. The level
#    was looked up beside the script first ($0/../.submit-level), so a copy of
#    submit.sh in another tree, or one run as `sh submit.sh` from inside
#    tools/, read the level of the folder above it and gated on that. Here a
#    copy whose parent holds `complete` gates a workspace with none: basic.
mkdir -p "$WORK/slv/tools"
cp "$TOOLS/submit.sh" "$WORK/slv/tools/submit.sh"
printf 'complete\n' > "$WORK/slv/.submit-level"
rm -f "$WORK/se/ws/.submit-level"
slv_run() {
	sb_env BUILD_WORKSPACE_DIRECTORY="$WORK/se/ws" \
		"$SH" "$WORK/slv/tools/submit.sh" -n c-piscine-c-00
}
want_out "submit: no .submit-level in the workspace is basic" \
	"--test_tag_filters=lvl_basic,-manual" -- once slv_run
want_broken_none "submit: ... whatever the folder above the script holds" \
	"(level: complete" -- once slv_run
printf 'strict\n' > "$WORK/se/ws/.submit-level"
#    A direct run: once would replay the run above, from before this file.
want_out "submit: ... and the workspace's own file is the one read" \
	"(level: strict" -- slv_run
rm -f "$WORK/se/ws/.submit-level"

# 16. --written-only, AN OPT-IN GATE FOR A PROJECT HALF DONE. The gate runs
#    every test of the module, so one exercise not started yet blocks the
#    exercises that are finished, and the only way past it was --no-gate,
#    which gates nothing. --written-only lets through each exercise that
#    first_red's triage calls not written yet -- the same verdict its report
#    prints -- gates the rest, and names what it let through. The workspace
#    holds first_red and what it reads beside it, since the script runs the
#    workspace's copy. The stand-in bazel above replays one red output as
#    Bazel prints it: the FAIL line on stderr, and the summary, the line that
#    says FAILED, on stdout -- which the gate used to throw away.
# toy_c FILE NAME stub|plus|minus: a toy .c of one function NAME, under its
# 42 header (first_red's section, FR_H): a template stub, or a body written.
# Without the header stub_check refuses the file (exit 2), and first_red's
# triage then called a stub "not written" by another branch than a real
# stub's. Any other kind is refused (exit 2) before FILE is written: a
# file of the header alone, its function missing, let the arms over it
# pass or fail for a reason none of them names.
toy_c() {
	case $3 in
		stub | plus | minus) ;;
		*)
			echo "toy_c: unknown kind '$3' (stub, plus or minus)" >&2
			return 2 ;;
	esac
	{
		printf '%s\n' "$FR_H"
		case $3 in
			stub) printf 'int\t%s(int a)\n{\n\t(void)a;\n\treturn (0);\n}\n' "$2" ;;
			plus) printf 'int\t%s(int a)\n{\n\treturn (a + 1);\n}\n' "$2" ;;
			minus) printf 'int\t%s(int a)\n{\n\treturn (a - 1);\n}\n' "$2" ;;
		esac
	} > "$1"
}
_wo="$WORK/wo/ws"
_wom="$_wo/c-piscine/c-piscine-c-00"
mkdir -p "$_wo/tools" "$_wom/deliverable/ex00" "$_wom/deliverable/ex01"
for _wof in first_red.sh stub_check.sh standin.sh defs_levels.bzl runner_lib.sh units.awk; do
	cp "$TOOLS/$_wof" "$_wo/tools/$_wof"
done
fr_contract "$_wom" 00=ex00/ 01=ex01/
toy_c "$_wom/deliverable/ex00/f.c" f plus
toy_c "$_wom/deliverable/ex01/g.c" g stub
want_green "submit: the --written-only toy's unstarted exercise is a template stub" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$_wom/deliverable/ex01/g.c"
want_broken "submit: toy_c refuses a kind it does not know, by name" \
	"toy_c: unknown kind 'body'" -- toy_c "$WORK/wo/no-such-kind.c" f body
git init -q --bare -b master "$WORK/wo/remote.git"
printf 'c-piscine/c-piscine-c-00=%s\n' "$WORK/wo/remote.git" > "$_wo/.submit-remotes"
mkdir -p "$WORK/wo/logs/ex01_output"
printf 'ex01_output: its test log\n' > "$WORK/wo/logs/ex01_output/test.log"
printf 'FAIL: //c-piscine/c-piscine-c-00:ex01_output (Exit 1) (see %s)\n' \
	"$WORK/wo/logs/ex01_output/test.log" > "$WORK/wo/stub.err"
printf '//c-piscine/c-piscine-c-00:ex00_output  PASSED in 0.1s\n' > "$WORK/wo/stub.out"
printf '//c-piscine/c-piscine-c-00:ex01_output  FAILED in 0.1s\n  %s\n' \
	"$WORK/wo/logs/ex01_output/test.log" >> "$WORK/wo/stub.out"
wo_run() {  # wo_run FIXTURE [OPTION...]: FIXTURE.err and .out; the log is in $WORK/wo/log
	# $WORK/wo/bin comes first on PATH: an arm that needs a stand-in puts it there.
	_woe=$1
	shift
	sb_env PATH="$WORK/wo/bin:$WORK/subm/bin:$PATH" FAKE_BAZEL_RC=3 FAKE_BAZEL_ADV_RC=0 \
		FAKE_BAZEL_ERR="$WORK/wo/$_woe.err" FAKE_BAZEL_OUT="$WORK/wo/$_woe.out" \
		BUILD_WORKSPACE_DIRECTORY="$_wo" \
		"$SH" "$TOOLS/submit.sh" "$@" c-piscine-c-00 > "$WORK/wo/log" 2>&1
}
wo_pushed() { git --git-dir="$WORK/wo/remote.git" rev-parse -q --verify master 2> /dev/null; }
want_red "submit: one exercise not started blocks the module" -- wo_run stub
want_green "submit: ... and nothing is pushed" -- sh -c '! git --git-dir="$1" rev-parse -q --verify master' \
	_ "$WORK/wo/remote.git"
want_out "submit: -n --written-only says what it would let through" \
	"an exercise not written yet does not block" -- \
	sb_env BUILD_WORKSPACE_DIRECTORY="$_wo" \
	"$SH" "$TOOLS/submit.sh" -n --written-only c-piscine-c-00
want_broken "submit: --written-only with --no-gate is refused" \
	"--written-only narrows the gate and --no-gate skips it" -- \
	sb_env BUILD_WORKSPACE_DIRECTORY="$_wo" \
	"$SH" "$TOOLS/submit.sh" --written-only --no-gate c-piscine-c-00
want_green "submit: --written-only pushes it" -- wo_run stub --written-only
want_green "submit: ... the written exercise in the push" -- \
	sh -c 'git --git-dir="$1" ls-tree -r --name-only master | grep -qx ex00/f.c' _ "$WORK/wo/remote.git"
want_out "submit: ... and names the exercise it let through" \
	"not written yet, let through by --written-only: ex01" -- cat "$WORK/wo/log"
want_out "submit: ... again in the summary" \
	"c-piscine/c-piscine-c-00: ex01" -- sh -c 'sed -n "/^----/,\$p" "$1"' _ "$WORK/wo/log"
_wo_tip=$(wo_pushed)
#    What it lets through is first_red's verdict, not a red output: a written
#    exercise whose output is red still blocks, as does a red test of the
#    whole module, and a run that did not complete is not triaged at all.
toy_c "$_wom/deliverable/ex01/g.c" g minus
want_red "submit: --written-only still blocks a written exercise" -- wo_run stub --written-only
want_broken_none "submit: ... and lets nothing through" "let through by" -- cat "$WORK/wo/log"
toy_c "$_wom/deliverable/ex01/g.c" g stub
mkdir -p "$WORK/wo/logs/deliverable_files"
printf '%s\n' 'files_test: c-piscine/c-piscine-c-00/deliverable' '' \
	"  THESE ARE IN NO EXERCISE'S FOLDER." '    notes.txt' '' '  RESULT: FAIL' \
	> "$WORK/wo/logs/deliverable_files/test.log"
{
	cat "$WORK/wo/stub.err"
	printf 'FAIL: //c-piscine/c-piscine-c-00:deliverable_files (Exit 1) (see %s)\n' \
		"$WORK/wo/logs/deliverable_files/test.log"
} > "$WORK/wo/whole.err"
{
	cat "$WORK/wo/stub.out"
	printf '//c-piscine/c-piscine-c-00:deliverable_files  FAILED in 0.1s\n  %s\n' \
		"$WORK/wo/logs/deliverable_files/test.log"
} > "$WORK/wo/whole.out"
want_red "submit: ... and a red test of the whole module" -- wo_run whole --written-only
want_out "submit: ... showing that test's report" "notes.txt" -- cat "$WORK/wo/log"
{
	cat "$WORK/wo/stub.err"
	printf 'ERROR: Build did NOT complete successfully\n'
} > "$WORK/wo/stopped.err"
cp "$WORK/wo/stub.out" "$WORK/wo/stopped.out"
want_red "submit: ... and a run that did not complete" -- wo_run stopped --written-only
want_green "submit: ... none of which pushed anything" -- \
	sh -c '[ "$(git --git-dir="$1" rev-parse master)" = "$2" ]' _ "$WORK/wo/remote.git" "$_wo_tip"
#    A triage that never ran is no verdict on the code. With first_red.sh
#    missing, or stopping before its report (a file it reads is not beside
#    it), or reading nothing red in a red run, the student was told that
#    something they wrote is red: sent to their code for a report that never
#    ran. Blocked still, and saying the report could not be read, with the
#    command that shows it (wo_piped) wherever that command can run.
wo_unread() {  # wo_unread FIXTURE: blocked, and the run says why
	wo_run "$1" --written-only && return 1
	grep -q "the gate's report" "$WORK/wo/log" && grep -q "could not be read" "$WORK/wo/log" &&
		! grep -q "an exercise you have" "$WORK/wo/log"
}
wo_piped() { grep -qF -- "--use_action_cache=false 2>&1 | sh tools/first_red.sh" "$WORK/wo/log"; }
#    With first_red.sh gone, piping the gate into it fails the same way, so
#    the run hands over the plain gate command alone and says what is missing.
#    The plain command is the BLOCKED line's, which every blocked run prints
#    (the gate's arms above pin it): what this branch decides is that no
#    piped one follows it, and that is the arm to hold.
mv "$_wo/tools/first_red.sh" "$WORK/wo/first_red.aside"
want_green "submit: --written-only with no first_red says so" -- wo_unread stub
want_out "submit: ... that it is missing from the checkout" \
	"tools/first_red.sh, which reads that report, is missing" -- cat "$WORK/wo/log"
want_out "submit: ... and how to restore it" "git checkout HEAD -- tools/first_red.sh" -- cat "$WORK/wo/log"
want_broken_none "submit: ... and no pipe into the missing script" "| sh tools/first_red.sh" -- \
	cat "$WORK/wo/log"
want_broken_none "submit: ... nor the shell's error as first_red's" "tools/first_red.sh, which reads it," -- \
	cat "$WORK/wo/log"
mv "$WORK/wo/first_red.aside" "$_wo/tools/first_red.sh"
mv "$_wo/tools/defs_levels.bzl" "$WORK/wo/defs.aside"
want_green "submit: ... nor with first_red stopping before its report" -- wo_unread stub
want_green "submit: ... with the command that shows the report" -- wo_piped
want_out "submit: ... and quotes why it stopped" "defs_levels.bzl is not beside it" -- cat "$WORK/wo/log"
want_out "submit: ... under first_red's own heading" "tools/first_red.sh, which reads it, stopped (exit 2) and said:" -- \
	cat "$WORK/wo/log"
mv "$WORK/wo/defs.aside" "$_wo/tools/defs_levels.bzl"
#    ...and for any other reason it stops: a stand-in first_red.sh that says
#    one line on stderr and exits 2 has that line quoted, and nothing else.
mv "$_wo/tools/first_red.sh" "$WORK/wo/first_red.aside"
printf '#!/bin/sh
echo "first_red.sh: the selftest stand-in stops here" >&2
exit 2
' \
	> "$_wo/tools/first_red.sh"
want_green "submit: ... nor with first_red stopping for another reason" -- wo_unread stub
want_green "submit: ... with the command that shows the report" -- wo_piped
want_out "submit: ... under first_red's own heading" "tools/first_red.sh, which reads it, stopped (exit 2) and said:" -- \
	cat "$WORK/wo/log"
want_green "submit: ... quoting the one line it said" -- \
	grep -qx "              | first_red.sh: the selftest stand-in stops here" "$WORK/wo/log"
want_green "submit: ... and no other line under its heading" -- \
	sh -c '[ "$(grep -c "^              | " "$1")" -eq 1 ]' _ "$WORK/wo/log"
mv "$WORK/wo/first_red.aside" "$_wo/tools/first_red.sh"
: > "$WORK/wo/silent.err"
: > "$WORK/wo/silent.out"
want_green "submit: ... nor with nothing red in a red run's output" -- wo_unread silent
want_green "submit: ... with the command that shows the report" -- wo_piped
#    Only first_red's own words go under that heading. The two cases that
#    are submit's own finding used to be printed there as if first_red had
#    said them; they are said in the run's own words instead.
want_out "submit: ... and says so in its own words" \
	"Bazel said tests failed, but tools/first_red.sh found no" -- cat "$WORK/wo/log"
want_broken_none "submit: ... not as something first_red said" "tools/first_red.sh, which reads it," -- \
	cat "$WORK/wo/log"
#    A temporary file it could not make: a stand-in mktemp, earlier on PATH,
#    that fails once the stand-in bazel has run, which is after the gate
#    made its own two and before the triage makes any.
mkdir -p "$WORK/wo/bin"
printf '#!/bin/sh\n[ ! -e "%s" ] || exit 1\nexec %s "$@"\n' "$WORK/wo/gated" "$(command -v mktemp)" \
	> "$WORK/wo/bin/mktemp"
printf '#!/bin/sh\n: > "%s"\nexec "%s" "$@"\n' "$WORK/wo/gated" "$WORK/subm/bin/bazel" \
	> "$WORK/wo/bin/bazel"
chmod +x "$WORK/wo/bin/mktemp" "$WORK/wo/bin/bazel"
want_green "submit: ... nor with no temporary file to read it into" -- wo_unread stub
want_green "submit: ... with the command that shows the report" -- wo_piped
want_out "submit: ... and says so in its own words" \
	"could not create a temporary file to read it" -- cat "$WORK/wo/log"
want_broken_none "submit: ... not as something first_red said" "tools/first_red.sh, which reads it," -- \
	cat "$WORK/wo/log"
rm -rf "$WORK/wo/bin" "$WORK/wo/gated"
want_green "submit: ... and none of those pushed" -- \
	sh -c '[ "$(git --git-dir="$1" rev-parse master)" = "$2" ]' _ "$WORK/wo/remote.git" "$_wo_tip"
#    The gate's own two temporary files, which hold what Bazel says. With
#    mktemp failing, both names were empty, Bazel's output went to a file the
#    shell could not open, and the gate's status was the shell's redirection
#    error read as Bazel's: "Bazel exited 2" under dash, "the build STOPPED"
#    under bash. The gate could not run, and it says why.
mkdir -p "$WORK/wo/bin"
printf '#!/bin/sh\nexit 1\n' > "$WORK/wo/bin/mktemp"
chmod +x "$WORK/wo/bin/mktemp"
want_red "submit: a gate with no temporary file blocks" -- wo_run stub
want_out "submit: ... as a gate that could not run" \
	"BLOCKED: the gate could not RUN" -- cat "$WORK/wo/log"
want_out "submit: ... saying mktemp failed" \
	"create a temporary file for Bazel's output (mktemp failed)" -- cat "$WORK/wo/log"
want_broken_none "submit: ... not as Bazel's verdict" "Bazel exited" -- cat "$WORK/wo/log"
rm -rf "$WORK/wo/bin"
want_green "submit: ... and nothing is pushed" -- \
	sh -c '[ "$(git --git-dir="$1" rev-parse master)" = "$2" ]' _ "$WORK/wo/remote.git" "$_wo_tip"
#    No bazel on PATH at all. The gate said so, then the could-not-RUN block
#    under it read its status as Bazel's: "Bazel exited 2", glossed as a bad
#    command line, "Bazel's last words" and a bazel command to reproduce it
#    with. The PATH holds the tools submit.sh requires (its own require
#    line) and nothing else, so no bazel of this machine's is found either.
mkdir -p "$WORK/wo/nobz"
for _b in sh "$SH" $(sed -n 's/^require //p' "$TOOLS/submit.sh"); do
	_p=$(command -v "$_b" 2> /dev/null) || continue
	case $_p in /*) ln -sf "$_p" "$WORK/wo/nobz/${_b##*/}" ;; esac
done
wo_nobz() {
	sb_env PATH="$WORK/wo/nobz" BUILD_WORKSPACE_DIRECTORY="$_wo" \
		"$SH" "$TOOLS/submit.sh" c-piscine-c-00 > "$WORK/wo/log" 2>&1
}
want_red "submit: a gate with no bazel on PATH blocks" -- wo_nobz
want_out "submit: ... as a gate that could not run" \
	"BLOCKED: the gate could not RUN" -- cat "$WORK/wo/log"
want_out "submit: ... saying bazel is not on PATH" \
	"bazel is not on PATH, so the gate never ran" -- cat "$WORK/wo/log"
want_broken_none "submit: ... not as Bazel's exit status" "Bazel exited" -- cat "$WORK/wo/log"
want_broken_none "submit: ... nor as Bazel's last words" "last words" -- cat "$WORK/wo/log"
rm -rf "$WORK/wo/nobz"
want_green "submit: ... and nothing is pushed" -- \
	sh -c '[ "$(git --git-dir="$1" rev-parse master)" = "$2" ]' _ "$WORK/wo/remote.git" "$_wo_tip"
#    THE FLOOR. --written-only pushes what is written, and never nothing: with
#    every exercise still a stub it let every red through and pushed the
#    stubs as they were. Now it refuses, before any test runs, and -n says
#    so; without the flag, the blocked gate says nothing is written.
toy_c "$_wom/deliverable/ex00/f.c" f stub
want_red "submit: --written-only with nothing written is refused" -- wo_run stub --written-only
want_out "submit: ... as nothing written to push" \
	"BLOCKED by --written-only -- not pushed: nothing written to push." -- cat "$WORK/wo/log"
want_broken_none "submit: ... before any test runs" "gate: bazel test" -- cat "$WORK/wo/log"
want_out "submit: ... and -n says it would be" \
	"would be BLOCKED by --written-only -- nothing written to push." -- \
	sb_env BUILD_WORKSPACE_DIRECTORY="$_wo" \
	"$SH" "$TOOLS/submit.sh" -n --written-only c-piscine-c-00
want_red "submit: without it, a gate over nothing written blocks" -- wo_run stub
want_out "submit: ... and says nothing is written" \
	"Nothing of it is written yet: every exercise is still the" -- cat "$WORK/wo/log"
want_green "submit: ... none of which pushed anything" -- \
	sh -c '[ "$(git --git-dir="$1" rev-parse master)" = "$2" ]' _ "$WORK/wo/remote.git" "$_wo_tip"
#    A SUBJECT'S MANDATORY PART, where the contract names one (subject()'s
#    `mandatory`, written here over lines, as buildifier spreads a list):
#    --written-only does not push the project while one of it is a stub, and
#    says which before any test runs. Without the flag, the blocked gate says
#    the same; and with only the rest unwritten, it is the warning that
#    --written-only pushes without them.
wo_mandatory() {  # wo_mandatory KEY...: the toy's contract, KEYs its mandatory part
	fr_contract "$_wom" 00=ex00/ 01=ex01/
	{
		sed '$d' "$_wom/BUILD.bazel"
		printf '    mandatory = [\n'
		for _wmk in "$@"; do printf '        "%s",\n' "$_wmk"; done
		printf '    ],\n    mandatory_quote = "Toy, p.1: \\"These are the mandatory exercises.\\"",\n)\n'
	} > "$WORK/wo/BUILD.new" && mv "$WORK/wo/BUILD.new" "$_wom/BUILD.bazel"
}
wo_mandatory 00
toy_c "$_wom/deliverable/ex01/g.c" g minus
want_red "submit: --written-only refuses a mandatory exercise not written" -- wo_run stub --written-only
want_out "submit: ... naming it" "not written yet: ex00" -- cat "$WORK/wo/log"
want_broken_none "submit: ... before any test runs" "gate: bazel test" -- cat "$WORK/wo/log"
want_red "submit: without it, the blocked gate names it too" -- wo_run stub
want_out "submit: ... as mandatory" "A mandatory exercise is not written yet:" -- cat "$WORK/wo/log"
want_green "submit: ... none of which pushed anything" -- \
	sh -c '[ "$(git --git-dir="$1" rev-parse master)" = "$2" ]' _ "$WORK/wo/remote.git" "$_wo_tip"
toy_c "$_wom/deliverable/ex00/f.c" f plus
toy_c "$_wom/deliverable/ex01/g.c" g stub
want_red "submit: the mandatory part written and the rest not blocks" -- wo_run stub
want_out "submit: ... and warns that only the mandatory part is" \
	"Every mandatory exercise is written, and" -- cat "$WORK/wo/log"
want_out "submit: ... naming the rest" "these are not: ex01. To push without them, add" -- cat "$WORK/wo/log"
want_green "submit: ... which --written-only pushes without" -- wo_run stub --written-only
want_out "submit: ... letting it through" \
	"not written yet, let through by --written-only: ex01" -- cat "$WORK/wo/log"
_wo_tip=$(wo_pushed)
#    A floor that could not be read lets nothing through: which exercises are
#    mandatory is not known. A contract first_red cannot read (no subject()
#    in the BUILD file) leaves the triage its verdict, and the push refused.
printf '# the selftest: no contract here\n' > "$_wom/BUILD.bazel"
want_red "submit: --written-only over a floor it cannot read" -- wo_run stub --written-only
want_out "submit: ... lets nothing through" \
	"which exercises this" -- cat "$WORK/wo/log"
want_out "submit: ... quoting first_red" "| first_red.sh: no subject() contract" -- cat "$WORK/wo/log"
want_broken_none "submit: ... not as a let-through" "let through by" -- cat "$WORK/wo/log"
want_green "submit: ... and pushed nothing" -- \
	sh -c '[ "$(git --git-dir="$1" rev-parse master)" = "$2" ]' _ "$WORK/wo/remote.git" "$_wo_tip"
fr_contract "$_wom" 00=ex00/ 01=ex01/
#    A CONTRACT OF NAMED UNITS (units = {...}): what --written-only lets
#    through, and what its floor is read against, are the units
#    tools/units.awk lists for it -- never a name of another shape, and never
#    a function of a library, which goes to 42 with its library -- and the
#    run speaks of them in their kind's words. A stand-in first_red gives
#    each arm the verdicts it picks, over a toy library in a module of its
#    own (cursus/Milestone_9/Toylib, the table's first row, as sb_make
#    writes one).
_wn="$WORK/wn/ws"
_wnm=cursus/Milestone_9/Toylib
mkdir -p "$_wn/tools" "$_wn/$_wnm/deliverable" "$WORK/wn/logs/toy_len_output"
cp "$TOOLS/units.awk" "$_wn/tools/units.awk"
wn_lib() {  # the toy library's contract: libtoy, of toy_len and toy_up, mandatory
	{
		printf 'subject(\n    grader = "both",\n    group = False,\n    units = {\n'
		printf '        "libtoy": unit(page = 1, files = ["Makefile"], allowed = [],\n'
		printf '            functions = {\n                "toy_len": [],\n                "toy_up": [],\n            }),\n'
		printf '    },\n    mandatory = ["libtoy"],\n'
		printf '    mandatory_quote = "Toy, p.1: \\"The library is the mandatory part.\\"",\n)\n'
	} > "$_wn/$_wnm/BUILD.bazel"
}
wn_lib
printf 'x\n' > "$_wn/$_wnm/deliverable/toy_len.c"
cat > "$_wn/tools/first_red.sh" <<'WN_FIRST_RED'
#!/bin/sh
# The selftest's stand-in: --written prints $FAKE_FR_WRITTEN, --triage
# writes $FAKE_FR_TRIAGE as its report.
case "$1" in
	--written) cat "$FAKE_FR_WRITTEN"; exit 0 ;;
	--triage) cat > /dev/null; cp "$FAKE_FR_TRIAGE" "$2"; exit 0 ;;
esac
exit 2
WN_FIRST_RED
sb_make "$_wnm=REPLACE_ME" wn
git init -q --bare -b master "$WORK/wn/remote.git"
printf '%s=%s\n' "$_wnm" "$WORK/wn/remote.git" > "$_wn/.submit-remotes"
printf 'toy_len_output: its test log\n' > "$WORK/wn/logs/toy_len_output/test.log"
printf 'FAIL: //%s:toy_len_output (Exit 1) (see %s)\n' "$_wnm" \
	"$WORK/wn/logs/toy_len_output/test.log" > "$WORK/wn/red.err"
printf '//%s:toy_len_output  FAILED in 0.1s\n' "$_wnm" > "$WORK/wn/red.out"
{
	printf 'ERROR: /x/%s/BUILD.bazel:1:1: Linking %s/toy_len_bin failed: (Exit 1): ' "$_wnm" "$_wnm"
	printf 'clang.sh failed: error executing CppLink command (from cc_binary rule target //%s:toy_len_bin) x\n' "$_wnm"
	printf "ld: error: toy_len.o: multiple definition of 'main'\n"
	printf 'ERROR: Build did NOT complete successfully\n'
} > "$WORK/wn/link.err"
: > "$WORK/wn/link.out"
printf 'written\tlibtoy\tmandatory\n' > "$WORK/wn/w_written"
printf 'stub\tlibtoy\tmandatory\n' > "$WORK/wn/w_stub"
printf 'written\tlibtoy\tmandatory\nstub\ttoy_len\toptional\n' > "$WORK/wn/w_fn"
printf 'written\tlibtoy\toptional\n' > "$WORK/wn/w_part"
printf 'work\t//%s\tlibtoy\n' "$_wnm" > "$WORK/wn/t_lib"
printf 'work\t//%s\ttoy_len\n' "$_wnm" > "$WORK/wn/t_fn"
printf 'work\t//%s\tex00\n' "$_wnm" > "$WORK/wn/t_ex"
wn_run() {  # wn_run RC FIXTURE WRITTEN TRIAGE [OPTION...]; the log is in $WORK/wn/log
	_wnrc=$1 _wnx=$2 _wnw=$3 _wnt=$4
	shift 4
	sb_env PATH="$WORK/subm/bin:$PATH" FAKE_BAZEL_RC="$_wnrc" FAKE_BAZEL_ADV_RC=0 \
		FAKE_BAZEL_ERR="$WORK/wn/$_wnx.err" FAKE_BAZEL_OUT="$WORK/wn/$_wnx.out" \
		FAKE_FR_WRITTEN="$WORK/wn/$_wnw" FAKE_FR_TRIAGE="$WORK/wn/$_wnt" \
		BUILD_WORKSPACE_DIRECTORY="$_wn" \
		"$SH" "$WORK/subm/wn.sh" "$@" Toylib > "$WORK/wn/log" 2>&1
}
wn_pushed() { git --git-dir="$WORK/wn/remote.git" rev-parse -q --verify master 2> /dev/null; }
want_green "submit: --written-only lets a library not written through" -- \
	wn_run 3 red w_written t_lib --written-only
want_out "submit: ... naming it" \
	"not written yet, let through by --written-only: libtoy" -- cat "$WORK/wn/log"
_wn_tip=$(wn_pushed)
want_green "submit: ... and pushes" -- test -n "$_wn_tip"
want_red "submit: ... never a function of it, which is no unit" -- \
	wn_run 3 red w_written t_fn --written-only
want_out "submit: ... blocked as something else red, in its words" \
	"lets through only a library not written" -- cat "$WORK/wn/log"
want_red "submit: ... nor an exNN its contract does not list" -- \
	wn_run 3 red w_written t_ex --written-only
want_broken_none "submit: ... letting nothing through" "let through by" -- cat "$WORK/wn/log"
want_red "submit: --written over a library's function is no floor" -- \
	wn_run 3 red w_fn t_lib --written-only
want_out "submit: ... said so" "which libraries this" -- cat "$WORK/wn/log"
want_out "submit: ... quoting first_red" \
	"tools/first_red.sh --written $_wnm said:" -- cat "$WORK/wn/log"
want_red "submit: ... nor one whose part is not its contract's" -- \
	wn_run 3 red w_part t_lib --written-only
want_out "submit: ... said so" "which libraries this" -- cat "$WORK/wn/log"
want_red "submit: --written-only refuses the library still a stub" -- \
	wn_run 3 red w_stub t_lib --written-only
want_out "submit: ... in the library's words" \
	"The library is still the stub it started as, and" -- cat "$WORK/wn/log"
want_red "submit: without it, the blocked gate says so" -- wn_run 3 red w_stub t_lib
want_out "submit: ... in the library's words" \
	"Nothing of it is written yet: the library is still the" -- cat "$WORK/wn/log"
want_green "submit: -n --written-only over a library" -- \
	wn_run 0 red w_written t_lib -n --written-only
want_out "submit: ... says what it would let through, in its words" \
	"a library not written yet does not block" -- cat "$WORK/wn/log"
want_red "submit: a library's failed link does not build" -- wn_run 1 link w_written t_lib
want_out "submit: ... said as its own" "the module does NOT BUILD" -- cat "$WORK/wn/log"
want_out "submit: ... in the library's words" \
	"Which library does not build, and why:" -- cat "$WORK/wn/log"
want_green "submit: ... none of which pushed anything" -- \
	sh -c '[ "$(git --git-dir="$1" rev-parse master)" = "$2" ]' _ "$WORK/wn/remote.git" "$_wn_tip"
#    The list is units.awk's, read by the script itself: a contract it
#    cannot read lets nothing through, though first_red read it, and the
#    run quotes units.awk.
printf 'subject(\n    grader = "both",\n' > "$_wn/$_wnm/BUILD.bazel"
want_red "submit: --written-only over a contract units.awk refuses" -- \
	wn_run 3 red w_written t_lib --written-only
want_out "submit: ... names units.awk" \
	"tools/units.awk, reading $_wnm/BUILD.bazel, said:" -- cat "$WORK/wn/log"
want_out "submit: ... quoting it" "| units.awk: " -- cat "$WORK/wn/log"
#    A project of one unit is "the project".
printf 'subject(\n    grader = "both",\n    group = False,\n    units = {\n        "tally": unit(page = 1, files = ["Makefile"], allowed = None),\n    },\n)\n' \
	> "$_wn/$_wnm/BUILD.bazel"
printf 'stub\ttally\toptional\n' > "$WORK/wn/w_tally"
want_red "submit: --written-only refuses a project not written" -- \
	wn_run 3 red w_tally t_lib --written-only
want_out "submit: ... in the project's words" \
	"The project is still the stub it started as, and" -- cat "$WORK/wn/log"
#    A contract of exercises is held to its list the same way: an exNN it
#    does not have is never let through, and a --written that leaves one
#    out, names one it lacks, or calls mandatory one it does not, is no
#    floor.
fr_contract "$_wn/$_wnm" 00=ex00/ 01=ex01/
printf 'written\tex00\toptional\nstub\tex01\toptional\n' > "$WORK/wn/x_ok"
printf 'written\tex00\toptional\n' > "$WORK/wn/x_short"
printf 'written\tex00\toptional\nstub\tex05\toptional\n' > "$WORK/wn/x_other"
printf 'written\tex00\tmandatory\nstub\tex01\toptional\n' > "$WORK/wn/x_part"
printf 'work\t//%s\tex01\n' "$_wnm" > "$WORK/wn/tx_01"
printf 'work\t//%s\tex05\n' "$_wnm" > "$WORK/wn/tx_05"
want_red "submit: --written-only never lets through an exNN not listed" -- \
	wn_run 3 red x_ok tx_05 --written-only
want_broken_none "submit: ... letting nothing through" "let through by" -- cat "$WORK/wn/log"
want_red "submit: --written leaving an exercise out is no floor" -- \
	wn_run 3 red x_short tx_01 --written-only
want_out "submit: ... said so" "which exercises this" -- cat "$WORK/wn/log"
want_red "submit: ... nor one naming an exercise not listed" -- \
	wn_run 3 red x_other tx_01 --written-only
want_out "submit: ... said so" "which exercises this" -- cat "$WORK/wn/log"
want_red "submit: ... nor one calling mandatory what is not" -- \
	wn_run 3 red x_part tx_01 --written-only
want_out "submit: ... said so" "which exercises this" -- cat "$WORK/wn/log"
want_green "submit: ... while a true one lets its exercise through" -- \
	wn_run 3 red x_ok tx_01 --written-only
want_out "submit: ... naming it" \
	"not written yet, let through by --written-only: ex01" -- cat "$WORK/wn/log"
#    A PROJECT DIVIDED INTO PARTS AT THE ROOT (several units = {...}, of
#    kind part), whose subject names its mandatory part: each part is told
#    written by its own judge (first_red's THE JUDGE OF A PART), and the
#    floor is read per part. Without --written-only, a project whose
#    mandatory part reads as written and another part not is not pushed,
#    before any test runs: the run names that part and says that
#    --written-only pushes the project without waiting for it, every other
#    test still to pass, and never that a part is written: a judge's
#    "written" is only that the part is not plainly a stub. With it, the
#    gate lets that part's reds
#    through and the whole deliverable goes, as it is on disk, to a local
#    bare repository. The real first_red, stub_check and units.awk read
#    invented toy files; the stand-in bazel replays the gate, green in the
#    arms that hold the block to the floor alone, so no test's verdict is
#    what blocks them.
_wp="$WORK/wp/ws"
_wpm=cursus/Milestone_9/Toyparts
mkdir -p "$_wp/tools" "$_wp/$_wpm/deliverable" "$WORK/wp/logs/bonus_output" "$WORK/wp/logs/base_output"
for _wpf in first_red.sh stub_check.sh standin.sh defs_levels.bzl runner_lib.sh units.awk; do
	cp "$TOOLS/$_wpf" "$_wp/tools/$_wpf"
done
wp_contract() {  # wp_contract files|three|goal: the toy's parts, judged so
	{
		printf 'subject(\n    grader = "both",\n    group = False,\n    units = {\n'
		if [ "$1" = files ]; then
			printf '        "base": unit(page = 1, files = ["toy_count.c", "toy_count.h"], allowed = []),\n'
			printf '        "bonus": unit(page = 2, files = ["toy_count_bonus.c"], allowed = []),\n'
		elif [ "$1" = three ]; then
			printf '        "base": unit(page = 1, files = ["toy_count.c", "toy_count.h"], allowed = []),\n'
			printf '        "bonus": unit(page = 2, files = ["toy_count_bonus.c"], allowed = []),\n'
			printf '        "extra": unit(page = 3, files = ["toy_count_extra.c"], allowed = []),\n'
		else
			printf '        "base": unit(page = 1, files = ["Makefile", "toy_count.c"], allowed = [],\n'
			printf '            goal = "all", goal_quote = "Toy, p.1: \\"Your Makefile has the rule all.\\""),\n'
			printf '        "bonus": unit(page = 2, files = ["Makefile", "toy_count.c"], allowed = [],\n'
			printf '            goal = "bonus", goal_quote = "Toy, p.2: \\"The bonus is built by the rule bonus.\\""),\n'
		fi
		printf '    },\n    mandatory = ["base"],\n'
		printf '    mandatory_quote = "Toy, p.1: \\"The base is the mandatory part.\\"",\n)\n'
	} > "$_wp/$_wpm/BUILD.bazel"
}
wp_contract files
toy_c "$_wp/$_wpm/deliverable/toy_count.c" toy_count plus
{ printf '%s\n' "$FR_H"; printf '#ifndef TOY_COUNT_H\n# define TOY_COUNT_H\n#endif\n'; } \
	> "$_wp/$_wpm/deliverable/toy_count.h"
toy_c "$_wp/$_wpm/deliverable/toy_count_bonus.c" toy_count_bonus stub
sb_make "$_wpm=REPLACE_ME" wp
git init -q --bare -b master "$WORK/wp/remote.git"
printf '%s=%s\n' "$_wpm" "$WORK/wp/remote.git" > "$_wp/.submit-remotes"
printf 'bonus_output: its test log\n' > "$WORK/wp/logs/bonus_output/test.log"
printf 'FAIL: //%s:bonus_output (Exit 1) (see %s)\n' "$_wpm" \
	"$WORK/wp/logs/bonus_output/test.log" > "$WORK/wp/bonus.err"
{
	printf '//%s:base_output  PASSED in 0.1s\n' "$_wpm"
	printf '//%s:bonus_output  FAILED in 0.1s\n  %s\n' "$_wpm" "$WORK/wp/logs/bonus_output/test.log"
} > "$WORK/wp/bonus.out"
printf 'base_output: its test log\n' > "$WORK/wp/logs/base_output/test.log"
printf 'FAIL: //%s:base_output (Exit 1) (see %s)\n' "$_wpm" \
	"$WORK/wp/logs/base_output/test.log" > "$WORK/wp/base.err"
printf '//%s:base_output  FAILED in 0.1s\n  %s\n' "$_wpm" \
	"$WORK/wp/logs/base_output/test.log" > "$WORK/wp/base.out"
: > "$WORK/wp/green.err"
printf '//%s:base_output  PASSED in 0.1s\n//%s:bonus_output  PASSED in 0.1s\n' "$_wpm" "$_wpm" \
	> "$WORK/wp/green.out"
wp_run() {  # wp_run RC FIXTURE [OPTION...]: the gate replays FIXTURE.err and .out; the log is in $WORK/wp/log
	_wprc=$1 _wpx=$2
	shift 2
	sb_env PATH="$WORK/subm/bin:$PATH" FAKE_BAZEL_RC="$_wprc" FAKE_BAZEL_ADV_RC=0 \
		FAKE_BAZEL_ERR="$WORK/wp/$_wpx.err" FAKE_BAZEL_OUT="$WORK/wp/$_wpx.out" \
		BUILD_WORKSPACE_DIRECTORY="$_wp" \
		"$SH" "$WORK/subm/wp.sh" "$@" Toyparts > "$WORK/wp/log" 2>&1
}
wp_none() { ! git --git-dir="$WORK/wp/remote.git" rev-parse -q --verify master > /dev/null 2>&1; }
wp_tree() { git --git-dir="$WORK/wp/remote.git" ls-tree -r --name-only master; }
wp_written() {  # wp_written ROWS: first_red --written prints exactly ROWS
	_wpw=$(cd "$_wp" && sh tools/first_red.sh --written "$_wpm") || return 2
	printf '%s\n' "$_wpw"
	[ "$_wpw" = "$1" ]
}
want_green "submit: a part is read by its own files, not the root's" -- \
	wp_written "$(printf 'written\tbase\tmandatory\nstub\tbonus\toptional')"
want_red "submit: the mandatory part written and the bonus not blocks" -- wp_run 0 green
want_out "submit: ... naming the bonus" \
	"BLOCKED -- not pushed: a part is not written yet: bonus" -- cat "$WORK/wp/log"
want_out "submit: ... saying --written-only pushes it without waiting for that part" \
	"42 submit --written-only pushes the project without waiting" -- cat "$WORK/wp/log"
want_out "submit: ... while every other test still has to pass" \
	"every other test, the mandatory part's included, still has" -- cat "$WORK/wp/log"
want_broken_none "submit: ... and never saying a part is written" "is written" -- cat "$WORK/wp/log"
want_broken_none "submit: ... before any test runs" "gate: bazel test" -- cat "$WORK/wp/log"
want_green "submit: ... and nothing is pushed" -- wp_none
want_red "submit: -n says a part not written would block it" -- wp_run 0 green -n
want_out "submit: ... naming the bonus it would block on" \
	"dry-run: would be BLOCKED -- a part is not written yet: bonus" -- cat "$WORK/wp/log"
want_green "submit: --written-only pushes the mandatory part" -- wp_run 3 bonus --written-only
want_out "submit: ... letting the bonus through" \
	"not written yet, let through by --written-only: bonus" -- cat "$WORK/wp/log"
want_out "submit: ... to the local repository, the written part" "toy_count.c" -- wp_tree
want_out "submit: ... and the bonus as it is on disk" "toy_count_bonus.c" -- wp_tree
_wp_tip=$(git --git-dir="$WORK/wp/remote.git" rev-parse -q --verify master 2> /dev/null)
#    The bonus written and the base not: the mandatory part is below the
#    floor, with --written-only or without it.
toy_c "$_wp/$_wpm/deliverable/toy_count.c" toy_count stub
toy_c "$_wp/$_wpm/deliverable/toy_count_bonus.c" toy_count_bonus plus
want_red "submit: --written-only refuses the mandatory part not written" -- \
	wp_run 3 base --written-only
want_out "submit: ... naming it" "not written yet: base" -- cat "$WORK/wp/log"
want_red "submit: without it, the gate runs and names it" -- wp_run 3 base
want_out "submit: ... as the mandatory part" "A mandatory part is not written yet:" -- cat "$WORK/wp/log"
want_broken_none "submit: ... and never that --written-only pushes it" \
	"42 submit --written-only pushes the project" -- cat "$WORK/wp/log"
toy_c "$_wp/$_wpm/deliverable/toy_count.c" toy_count plus
want_green "submit: both parts written are pushed by default" -- wp_run 0 green
want_broken_none "submit: ... with no part named" "a part is not written yet" -- cat "$WORK/wp/log"
want_green "submit: ... none of the earlier runs having pushed" -- \
	sh -c '[ "$(git --git-dir="$1" rev-parse master^)" = "$2" ]' _ "$WORK/wp/remote.git" "$_wp_tip"
#    Three parts, one of the two optional ones written: the run names the
#    one not written, in the same words.
wp_contract three
toy_c "$_wp/$_wpm/deliverable/toy_count_extra.c" toy_count_extra stub
want_red "submit: one optional part written and another not blocks" -- wp_run 0 green
want_out "submit: ... naming the one not written" \
	"BLOCKED -- not pushed: a part is not written yet: extra" -- cat "$WORK/wp/log"
want_out "submit: ... saying --written-only pushes it without waiting for that one" \
	"42 submit --written-only pushes the project without waiting" -- cat "$WORK/wp/log"
want_broken_none "submit: ... never saying a part is written" "is written" -- cat "$WORK/wp/log"
rm -f "$_wp/$_wpm/deliverable/toy_count_extra.c"
#    A bonus that shares its files with the base is read by the rule of the
#    Makefile that builds it: a written Makefile with no bonus rule is a
#    bonus not written.
wp_contract goal
printf 'all:\n\tcc -c toy_count.c\n' > "$_wp/$_wpm/deliverable/Makefile"
want_red "submit: a Makefile with no bonus rule blocks by default" -- wp_run 0 green
want_out "submit: ... naming the bonus it has no rule for" \
	"BLOCKED -- not pushed: a part is not written yet: bonus" -- cat "$WORK/wp/log"
printf 'bonus: all\n' >> "$_wp/$_wpm/deliverable/Makefile"
want_green "submit: ... and is pushed once it has the rule" -- wp_run 0 green
#    A bonus rule whose recipe echoes and then compiles does more than
#    echo: that bonus is written, so --written-only lets none of its reds
#    through.
printf 'all:\n\tcc -c toy_count.c\nbonus:\n\t@echo bonus && cc -o checker toy_count.c\n' \
	> "$_wp/$_wpm/deliverable/Makefile"
_wp_was=$(git --git-dir="$WORK/wp/remote.git" rev-parse -q --verify master 2> /dev/null)
want_green "first_red: an echo, then && a compiler, is a bonus written" -- \
	wp_written "$(printf 'written\tbase\tmandatory\nwritten\tbonus\toptional')"
want_red "submit: ... so --written-only lets none of its reds through" -- \
	wp_run 3 bonus --written-only
want_out "submit: ... saying a part written is red" "something else is red" -- cat "$WORK/wp/log"
want_green "submit: ... and pushing nothing" -- \
	sh -c '[ "$(git --git-dir="$1" rev-parse master)" = "$2" ]' _ "$WORK/wp/remote.git" "$_wp_was"
#    A Makefile whose rule stub_check cannot tell (any answer but a stub
#    and no such rule) is a part written, whoever asks: here a stand-in for
#    it that answers 2 to every --goal, over a bonus whose rule only echoes.
#    So --written-only lets none of its reds through either.
cp "$_wp/tools/stub_check.sh" "$_wp/tools/stub_check_real.sh"
printf '#!/bin/sh\n[ "${1:-}" = --goal ] && exit 2\nexec sh "$(dirname "$0")/stub_check_real.sh" "$@"\n' \
	> "$_wp/tools/stub_check.sh"
printf 'all:\n\tcc -c toy_count.c\nbonus:\n\t@echo TODO\n' > "$_wp/$_wpm/deliverable/Makefile"
want_green "first_red: a part whose rule stub_check cannot tell is written" -- \
	wp_written "$(printf 'written\tbase\tmandatory\nwritten\tbonus\toptional')"
want_red "submit: ... so --written-only lets none of its reds through" -- \
	wp_run 3 bonus --written-only
want_out "submit: ... saying a part written is red" "something else is red" -- cat "$WORK/wp/log"
want_green "submit: ... and pushing nothing" -- \
	sh -c '[ "$(git --git-dir="$1" rev-parse master)" = "$2" ]' _ "$WORK/wp/remote.git" "$_wp_was"
mv "$_wp/tools/stub_check_real.sh" "$_wp/tools/stub_check.sh"
rm -f "$_wp/$_wpm/deliverable/Makefile"
wp_contract files
#    How each part is read, beyond the floor: a part is written by any file
#    it lists, its optional ones included; the part a bare make builds is
#    read by the rule a bare make runs; a rule that only echoes, or no rule
#    at all, is a part not written, in the report as in the floor.
wp_contract_more() {  # wp_contract_more optional|bare: two more ways a toy is divided
	{
		printf 'subject(\n    grader = "both",\n    group = False,\n    units = {\n'
		if [ "$1" = optional ]; then
			printf '        "base": unit(page = 1, files = ["toy_count.c", "toy_count.h"], allowed = []),\n'
			printf '        "bonus": unit(page = 2, files = ["toy_count_bonus.c"], allowed = [],\n'
			printf '            optional = ["toy_count_more.c"]),\n'
		else
			printf '        "base": unit(page = 1, files = ["Makefile", "toy_count.c"], allowed = []),\n'
			printf '        "bonus": unit(page = 2, files = ["Makefile", "toy_count.c"], allowed = [],\n'
			printf '            goal = "bonus", goal_quote = "Toy, p.2: \\"The bonus is built by the rule bonus.\\""),\n'
		fi
		printf '    },\n    mandatory = ["base"],\n'
		printf '    mandatory_quote = "Toy, p.1: \\"The base is the mandatory part.\\"",\n)\n'
	} > "$_wp/$_wpm/BUILD.bazel"
}
wp_contract_more optional
toy_c "$_wp/$_wpm/deliverable/toy_count.c" toy_count plus
toy_c "$_wp/$_wpm/deliverable/toy_count_bonus.c" toy_count_bonus stub
toy_c "$_wp/$_wpm/deliverable/toy_count_more.c" toy_count_more plus
want_green "first_red: a part is written by a file of its optional list" -- \
	wp_written "$(printf 'written\tbase\tmandatory\nwritten\tbonus\toptional')"
rm -f "$_wp/$_wpm/deliverable/toy_count_more.c" "$_wp/$_wpm/deliverable/toy_count_bonus.c"
wp_contract_more bare
printf 'all: toy_count.o\n\tcc -o toy_count toy_count.o\n\nbonus:\n\techo bonus\n' > "$_wp/$_wpm/deliverable/Makefile"
want_green "first_red: a bare make's part by its rule, an echo by none" -- \
	wp_written "$(printf 'written\tbase\tmandatory\nstub\tbonus\toptional')"
#    A bare make's rule credited by its prerequisite alone, once another
#    rule does more than echo, while what a bare make runs only echoes: the
#    run blocked names the bonus, and says nothing of the base as written.
printf 'all: toy\ntoy: toy_count.c\n\t@echo TODO\nbonus:\n\t@echo TODO\nclean:\n\trm -f toy_count.o\n' \
	> "$_wp/$_wpm/deliverable/Makefile"
want_green "first_red: a bare make's rule credited by its prerequisite alone" -- \
	wp_written "$(printf 'written\tbase\tmandatory\nstub\tbonus\toptional')"
want_red "submit: ... blocks with the bonus not written" -- wp_run 0 green
want_out "submit: ... naming it" \
	"BLOCKED -- not pushed: a part is not written yet: bonus" -- cat "$WORK/wp/log"
want_out "submit: ... saying --written-only pushes it without waiting for it" \
	"42 submit --written-only pushes the project without waiting" -- cat "$WORK/wp/log"
want_broken_none "submit: ... and never that the base is written" "is written" -- cat "$WORK/wp/log"
printf 'all: toy_count.o\n\tcc -o toy_count toy_count.o\n' > "$_wp/$_wpm/deliverable/Makefile"
printf '//%s:bonus_output  FAILED in 0.1s\n' "$_wpm" > "$WORK/wp/norule.log"
want_out "first_red: a red bonus with no rule is not written yet" \
	"$(printf 'work\t//%s\tbonus' "$_wpm")" -- \
	"$SH" -c 'cd "$1" && "$2" tools/first_red.sh --triage "$3/tri_norule.tsv" < "$3/norule.log" > /dev/null && cat "$3/tri_norule.tsv"' \
	_ "$_wp" "$SH" "$WORK/wp"
rm -f "$_wp/$_wpm/deliverable/Makefile"
mkdir -p "$WORK/wpodd"
cp -R "$_wp/tools" "$WORK/wpodd/tools"
printf 'BEGIN { printf "base\\tpart\\tmandatory\\tdeliverable\\todd\\t-\\n"; exit 0 }\n' > "$WORK/wpodd/tools/units.awk"
mkdir -p "$WORK/wpodd/$_wpm"
cp "$_wp/$_wpm/BUILD.bazel" "$WORK/wpodd/$_wpm/BUILD.bazel"
want_broken "first_red: --written refuses a judge it does not know" \
	"the unit base (odd) is read by a judge this does not know" -- \
	"$SH" -c 'cd "$1" && "$2" tools/first_red.sh --written "$3"' _ "$WORK/wpodd" "$SH" "$_wpm"
rm -rf "$WORK/wpodd"
wp_contract files

