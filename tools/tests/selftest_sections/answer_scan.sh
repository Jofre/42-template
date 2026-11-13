# -------------------------------------------------------------- answer_scan
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The scan for an answer copied OUT of the zone, which is how four shell checks,
# a selftest fixture and env-audit.sh came to ship answers in a published
# template: each computed or ran the answer itself. One fixture repo, driven
# through the three verdicts: found, clean, and nothing to look for. The
# "answer" is a made-up payload, not an exercise's.
#
# Each step that builds a fixture repository runs in a subshell whose words
# go to /dev/null, and one that fails says so: as_broke LABEL keeps its name,
# and the arm at the end of this section is red naming each. Unchecked, a
# commit that failed left an arm green over a tree that held nothing to scan.
# Each step's LABEL is its own, and where two steps do the same thing it
# names their repository or their moment too: under one label for two
# steps, that arm said "leak" and either could have failed.
as_broke() { printf '%s\n' "$1" >> "$WORK/as_broke"; }
! st_mine || mkdir -p "$WORK/as/c-piscine/c-piscine-shell-99/generators" \
	"$WORK/as/c-piscine/c-piscine-shell-99/tests/ex00" \
	"$WORK/as/c-piscine/c-piscine-c-99/deliverable/ex00" \
	"$WORK/as/c-piscine/c-piscine-c-99/tests/ex00"
! st_mine || (
	cd "$WORK/as" || exit 1
	git init -q .
	git config user.email selftest@example.invalid
	git config user.name selftest
	printf '#!/bin/sh\n# Create out.\nprintf "%%s\\n" "selftest payload one" > out\n' \
		> c-piscine/c-piscine-shell-99/generators/ex00.sh
	printf 'int\tft_selftest_mix(int a, int b)\n{\n\tif (a > b)\n\t\ta = a - b;\n\telse\n\t\ta = b - a;\n\treturn (a * 3);\n}\n' \
		> c-piscine/c-piscine-c-99/deliverable/ex00/ft_selftest_mix.c
	printf '#!/bin/sh\nwant=$(printf "%%s" "$1")\n' > c-piscine/c-piscine-shell-99/tests/ex00/check.sh
	git add -A && git commit -q -m clean
) > /dev/null 2>&1 || as_broke "as clean"
# as_scan TREE [ARG...] -- the scan run as `bazel run` runs it, over TREE.
as_scan() {
	_as_t=$1
	shift
	env BUILD_WORKSPACE_DIRECTORY="$_as_t" "$SH" "$TOOLS/answer_scan.sh" "$@"
}
want_green "answer_scan: a tree whose answers stay in the zone is clean" -- \
	as_scan "$WORK/as"
# A generator is run once to read what it writes, and it is the tree's own
# code: one that never ends hung the scan, and the template build behind it,
# with nothing naming it. The scan is a test's runner and sets no limit of
# its own (the test's, or the template build's bound on the whole scan,
# stops it), and whatever stops it ends that generator too and names it:
# a TERM to its whole process group (bounded, as timeout sends it), and a
# TERM to the scan alone, which is all a test runner may forward. Deferred,
# as every arm that waits is.
! st_mine || mkdir -p "$WORK/asloop/c-piscine/c-piscine-shell-99/generators" \
	"$WORK/asloop/c-piscine/c-piscine-shell-99/tests/ex00" \
	"$WORK/asloop/c-piscine/c-piscine-c-99/deliverable/ex00"
! st_mine || (
	cd "$WORK/asloop" || exit 1
	git init -q .
	printf '#!/bin/sh\n# Create out, then never end.\nprintf "%%s\\n" "selftest payload loop" > out\necho "$$" > "${ASLOOP_PID:-/dev/null}"\nwhile :; do :; done\n' \
		> c-piscine/c-piscine-shell-99/generators/ex00.sh
	cp "$WORK/as/c-piscine/c-piscine-c-99/deliverable/ex00/ft_selftest_mix.c" c-piscine/c-piscine-c-99/deliverable/ex00/
	cp "$WORK/as/c-piscine/c-piscine-shell-99/tests/ex00/check.sh" c-piscine/c-piscine-shell-99/tests/ex00/
	git add -A
) > /dev/null 2>&1 || as_broke "asloop"
later_status "answer_scan: a generator that never ends is named when the scan is stopped" 124 \
	'stopped while c-piscine/c-piscine-shell-99/generators/ex00.sh ran' -- \
	bounded 3 env BUILD_WORKSPACE_DIRECTORY="$WORK/asloop" "$SH" "$TOOLS/answer_scan.sh"
as_term_alone() {  # TERM to the scan alone, once its generator runs: it must end that generator
	rm -f "$WORK/asloop.pid"
	env ASLOOP_PID="$WORK/asloop.pid" BUILD_WORKSPACE_DIRECTORY="$WORK/asloop" \
		"$SH" "$TOOLS/answer_scan.sh" > "$WORK/asloop.term" 2>&1 &
	_ast=$!
	_asn=0
	while [ ! -s "$WORK/asloop.pid" ] && [ "$_asn" -lt 100 ]; do sleep 0.1; _asn=$((_asn + 1)); done
	kill -TERM "$_ast" 2> /dev/null
	wait "$_ast"
	cat "$WORK/asloop.term"
	_asg=$(cat "$WORK/asloop.pid" 2> /dev/null)
	[ -n "$_asg" ] || { echo "the generator never ran"; return 2; }
	kill -0 "$_asg" 2> /dev/null || return 0
	kill -KILL "$_asg" 2> /dev/null
	echo "the generator ($_asg) outlived the scan"
	return 1
}
later_status "answer_scan: ...and a TERM to the scan alone ends that generator" 0 \
	'stopped while c-piscine/c-piscine-shell-99/generators/ex00.sh ran' -- as_term_alone
# A generator that hangs does so in a child as often as in itself: a command
# waiting on a pipe, a sleep. Ending the generator's own shell left that
# child running after the scan was gone. This one waits on a sleep whose pid
# it writes first.
! st_mine || mkdir -p "$WORK/aschild/c-piscine/c-piscine-shell-99/generators" \
	"$WORK/aschild/c-piscine/c-piscine-shell-99/tests/ex00" \
	"$WORK/aschild/c-piscine/c-piscine-c-99/deliverable/ex00"
! st_mine || (
	cd "$WORK/aschild" || exit 1
	git init -q .
	cp "$WORK/as/c-piscine/c-piscine-c-99/deliverable/ex00/ft_selftest_mix.c" c-piscine/c-piscine-c-99/deliverable/ex00/
	cp "$WORK/as/c-piscine/c-piscine-shell-99/tests/ex00/check.sh" c-piscine/c-piscine-shell-99/tests/ex00/
	printf '%s\n' '#!/bin/sh' '# Create out, then wait on a child that never ends.' \
		'printf "%s\n" "selftest payload child" > out' \
		"sh -c 'echo \"\$\$\" > \"\${ASCHILD_PID:-/dev/null}\"; exec sleep 300'" \
		> c-piscine/c-piscine-shell-99/generators/ex00.sh
	git add -A
) > /dev/null 2>&1 || as_broke "aschild"
as_child_left() {  # TERM to the scan alone, once its generator waits on a child: no child may outlive the scan
	rm -f "$WORK/aschild.pid"
	env ASCHILD_PID="$WORK/aschild.pid" BUILD_WORKSPACE_DIRECTORY="$WORK/aschild" \
		"$SH" "$TOOLS/answer_scan.sh" > "$WORK/aschild.term" 2>&1 &
	_asc=$!
	_asn=0
	while [ ! -s "$WORK/aschild.pid" ] && [ "$_asn" -lt 100 ]; do sleep 0.1; _asn=$((_asn + 1)); done
	kill -TERM "$_asc" 2> /dev/null
	wait "$_asc"
	cat "$WORK/aschild.term"
	_ascp=$(cat "$WORK/aschild.pid" 2> /dev/null)
	[ -n "$_ascp" ] || { echo "the generator's child never ran"; return 2; }
	# Killed, it can stay a zombie until its new parent reaps it.
	_asn=0
	while kill -0 "$_ascp" 2> /dev/null && [ "$_asn" -lt 20 ]; do
		case $(sed 's/.*) //' "/proc/$_ascp/stat" 2> /dev/null) in Z*) return 0 ;; esac
		sleep 0.1
		_asn=$((_asn + 1))
	done
	kill -0 "$_ascp" 2> /dev/null || return 0
	kill -KILL "$_ascp" 2> /dev/null
	echo "the generator's child ($_ascp) outlived the scan"
	return 1
}
later_status "answer_scan: ...and the child that generator waits on" 0 \
	'stopped while c-piscine/c-piscine-shell-99/generators/ex00.sh ran' -- as_child_left
# A brace the C reader must not count: one in a char literal, one in a
# comment over two lines. Counted, it threw the depth off, and no later
# function body of that file was ever compared. Each file's second function
# has its body copied into a test (made-up functions, no exercise's); a third
# file with no such brace keeps the zone from reading as a stubbed one.
! st_mine || mkdir -p "$WORK/asbr/c-piscine/c-piscine-c-99/deliverable/ex00" \
	"$WORK/asbr/c-piscine/c-piscine-c-99/deliverable/ex01" \
	"$WORK/asbr/c-piscine/c-piscine-c-99/deliverable/ex02" \
	"$WORK/asbr/c-piscine/c-piscine-c-99/tests/ex00" "$WORK/asbr/c-piscine/c-piscine-c-99/tests/ex01"
! st_mine || (
	cd "$WORK/asbr/c-piscine/c-piscine-c-99" || exit 1
	printf '%s\n' "int	ft_selftest_brace(char c)" "{" "	if (c == '}')" "		return (1);" \
		"	return (0);" "}" "" "int	ft_selftest_tally(char *s)" "{" "	int	n;" "" "	n = 0;" \
		"	while (*s)" "	{" "		n = n * 7 + *s;" "		s++;" "	}" "	return (n % 13);" "}" \
		> deliverable/ex00/ft_selftest_brace.c
	printf '%s\n' "while (*s)" "n = n * 7 + *s;" "s++;" "return (n % 13);" > tests/ex00/ref_lit.c
	printf '%s\n' "int	ft_selftest_note(int a)" "{" "	/* a } in" "	   a comment */" "	return (a);" "}" "" \
		"int	ft_selftest_fold(int *t, int n)" "{" "	int	i;" "" "	i = 0;" "	while (i < n)" "	{" \
		"		t[i] = t[i] * 5 - i;" "		i += 2;" "	}" "	return (t[0] + 9);" "}" \
		> deliverable/ex01/ft_selftest_note.c
	printf '%s\n' "while (i < n)" "t[i] = t[i] * 5 - i;" "i += 2;" "return (t[0] + 9);" > tests/ex01/ref_cmt.c
	cp "$WORK/as/c-piscine/c-piscine-c-99/deliverable/ex00/ft_selftest_mix.c" deliverable/ex02/
	cd "$WORK/asbr" || exit 1
	git init -q . && git config user.email selftest@example.invalid && git config user.name selftest
	git add -A && git commit -q -m braces
) > /dev/null 2>&1 || as_broke "braces"
want_out "answer_scan: a body after a '}' char literal is still compared" \
	'tests/ex00/ref_lit.c:1: four lines of' -- \
	as_scan "$WORK/asbr"
want_out "answer_scan: ...and after a brace in a comment over two lines" \
	'tests/ex01/ref_cmt.c:1: four lines of' -- \
	as_scan "$WORK/asbr"
# The listing of the files it searches is git's too, and a git that fails
# there left it nothing to read, which it called clean. A stand-in git first
# on PATH fails that one listing (the only call naming TODO.md), and hands
# every other call to git itself. A tree with nothing outside the zone to
# search is no clean one either.
# as_git_failing DIR ARG -- that stand-in, as DIR/git: it fails every call
# naming ARG.
as_git_failing() {
	mkdir -p "$1"
	printf '#!/bin/sh
for a; do
	[ "$a" != %s ] || { echo "fatal: a listing that failed" >&2; exit 128; }
done
exec "%s" "$@"
' \
		"$2" "$(command -v git)" > "$1/git"
	chmod +x "$1/git"
}
! st_mine || as_git_failing "$WORK/asgit" "':(exclude)TODO.md'"
want_broken "answer_scan: a listing of its targets git failed is refused" \
	'git could not list the index' -- \
	env PATH="$WORK/asgit:$PATH" BUILD_WORKSPACE_DIRECTORY="$WORK/as" "$SH" "$TOOLS/answer_scan.sh"
# So are the two listings the names a subject gives come from: the files
# under tests/ (the only call naming ':(exclude)tools/*') and the BUILD files
# whose contracts are read (the only one naming '*/BUILD'). Neither status
# was read, so a failed one left those names unknown, and the scan went on
# to call harness names answers' -- a false hit, never the cause.
! st_mine || as_git_failing "$WORK/asgit_tests" "':(exclude)tools/*'"
want_broken "answer_scan: ...as is a listing of the files under tests/" \
	'git could not list the index' -- \
	env PATH="$WORK/asgit_tests:$PATH" BUILD_WORKSPACE_DIRECTORY="$WORK/as" "$SH" "$TOOLS/answer_scan.sh"
! st_mine || as_git_failing "$WORK/asgit_builds" "'*/BUILD'"
want_broken "answer_scan: ...and a listing of the BUILD files" \
	'git could not list the index' -- \
	env PATH="$WORK/asgit_builds:$PATH" BUILD_WORKSPACE_DIRECTORY="$WORK/as" "$SH" "$TOOLS/answer_scan.sh"
! st_mine || mkdir -p "$WORK/aszero/c-piscine/c-piscine-c-99/deliverable/ex00"
! st_mine || (
	cd "$WORK/aszero" || exit 1
	git init -q . && git config user.email selftest@example.invalid && git config user.name selftest
	printf 'int\tft_selftest_mix(int a, int b)\n{\n\tif (a > b)\n\t\ta = a - b;\n\telse\n\t\ta = b - a;\n\treturn (a * 3);\n}\n' \
		> c-piscine/c-piscine-c-99/deliverable/ex00/ft_selftest_mix.c
	git add -A && git commit -q -m zone-only
) > /dev/null 2>&1 || as_broke "zone-only"
want_broken "answer_scan: ...and so is a tree with no file outside the zone to search" \
	'no file outside the zone' -- \
	as_scan "$WORK/aszero"
! st_mine || ( cd "$WORK/as" && printf '#!/bin/sh\nwant=$(printf %%s\\n "selftest payload one")\n' \
	> c-piscine/c-piscine-shell-99/tests/ex00/check.sh && git commit -qam leak ) > /dev/null 2>&1 || as_broke "as leak"
want_out   "answer_scan: a shell answer inside a check is found" \
	"tests/ex00/check.sh:2: an answer line" -- \
	as_scan "$WORK/as"
! st_mine || ( cd "$WORK/as" && git checkout -q HEAD~1 -- . &&
	printf 'int\tref(int a, int b)\n{\n\tif (a > b)\n\t\ta = a - b;\n\telse\n\t\ta = b - a;\n\treturn (a * 3);\n}\n' \
		> c-piscine/c-piscine-c-99/tests/ex00/ref.c && git add -A && git commit -qm cleak ) > /dev/null 2>&1 || as_broke "cleak"
want_out   "answer_scan: a C body copied into a test is found" \
	"tests/ex00/ref.c:3: four lines" -- \
	as_scan "$WORK/as"
# ...and still found with the answer deleted from the work tree, the delete
# not staged: its text is in the index, and read from there. The scan said
# "tracked in the zone but could not be read" and exited 2, so a maintainer's
# unstaged delete, and every throwaway tree laid over with other answers,
# made the maintainer's test red (review of W7-V29). The generator the same.
! st_mine || rm -f "$WORK/as/c-piscine/c-piscine-c-99/deliverable/ex00/ft_selftest_mix.c"
want_out   "answer_scan: ...with the answer deleted, unstaged, from the index" \
	"tests/ex00/ref.c:3: four lines" -- \
	as_scan "$WORK/as"
want_out   "answer_scan: ...and says where it read it" \
	"ft_selftest_mix.c' is tracked and not in the work tree: its answer is read from the index" -- \
	as_scan "$WORK/as"
! st_mine || ( cd "$WORK/as" && git checkout -q -- c-piscine/c-piscine-c-99/deliverable/ex00/ft_selftest_mix.c &&
	git show HEAD~1:c-piscine/c-piscine-shell-99/tests/ex00/check.sh > "$WORK/as_check.sh" &&
	cp "$WORK/as_check.sh" c-piscine/c-piscine-shell-99/tests/ex00/check.sh &&
	rm -f c-piscine/c-piscine-shell-99/generators/ex00.sh ) > /dev/null 2>&1 || as_broke "as restore"
want_out   "answer_scan: ...a deleted generator's line, from the index" \
	"tests/ex00/check.sh:2: an answer line" -- \
	as_scan "$WORK/as"
! st_mine || ( cd "$WORK/as" && git checkout -q -- . ) > /dev/null 2>&1 || as_broke "as checkout, after as restore"
# ...and never in the maintainer's records, which never leave the private
# repo: TODO.md, HISTORY.md and every file under the folder todo/, at any
# depth, may quote an answer (a lead saying where one leaked). The same line
# in a check script beside them is found.
! st_mine || mkdir -p "$WORK/as3/c-piscine/c-piscine-shell-99/generators" \
	"$WORK/as3/c-piscine/c-piscine-shell-99/tests/ex00" "$WORK/as3/todo/decisions"
_as3_l=todo/decisions
! st_mine || (
	cd "$WORK/as3" || exit 1
	git init -q .
	git config user.email selftest@example.invalid
	git config user.name selftest
	printf '#!/bin/sh\n# Create out.\nprintf "%%s\\n" "selftest payload three" > out\n' \
		> c-piscine/c-piscine-shell-99/generators/ex00.sh
	printf '#!/bin/sh\nwant=$(printf "%%s" "$1")\n' > c-piscine/c-piscine-shell-99/tests/ex00/check.sh
	for _as3_f in TODO.md HISTORY.md "$_as3_l/x.md"; do
		printf '**V1. A leak**\n\n    printf "%%s\\n" "selftest payload three" > out\n' > "$_as3_f"
	done
	git add -A && git commit -q -m records
) > /dev/null 2>&1 || as_broke "records"
want_green "answer_scan: an answer quoted in the records is not reported" -- \
	as_scan "$WORK/as3"
! st_mine || ( cd "$WORK/as3" && printf '#!/bin/sh\nprintf "%%s\\n" "selftest payload three" > out\n' \
	> c-piscine/c-piscine-shell-99/tests/ex00/check.sh && git commit -qam leak ) > /dev/null 2>&1 || as_broke "as3 leak"
want_out   "answer_scan: ...and the same line in a check is" \
	"tests/ex00/check.sh:2: an answer line" -- \
	as_scan "$WORK/as3"
want_broken_none "answer_scan: ...while the records stay quiet" \
	"decisions/x.md" -- as_scan "$WORK/as3"
# ...and a path the index cannot give either is refused with git's own line
# saying why: the scan threw git's stderr away, so a blob missing from the
# object store read as "could not be read" and nothing more. Its own repo,
# staged and not on disk, its blob deleted after the add.
! st_mine || mkdir -p "$WORK/asgone/c-piscine/c-piscine-c-99/deliverable/ex00"
! st_mine || (
	cd "$WORK/asgone" || exit 1
	git init -q .
	printf 'int\tft_selftest_gone(int a)\n{\n\treturn (a * 7 + 3);\n}\n' \
		> c-piscine/c-piscine-c-99/deliverable/ex00/ft_selftest_gone.c
	git add -A
	_asg=$(git rev-parse :c-piscine/c-piscine-c-99/deliverable/ex00/ft_selftest_gone.c)
	rm -f ".git/objects/${_asg%"${_asg#??}"}/${_asg#??}" \
		c-piscine/c-piscine-c-99/deliverable/ex00/ft_selftest_gone.c
) > /dev/null 2>&1 || as_broke "asgone"
want_broken "answer_scan: a blob the index cannot give, with git's reason" \
	'fatal: ' -- as_scan "$WORK/asgone"
# A script turned in from deliverable/ is an answer as a generator is, and
# the scan read none: a line of one copied into a doc printed "OK ... none
# outside the zone", and a tree whose only answer was one had "nothing to
# scan for" (V182). Its own repo; the script and its commands are invented,
# and one of them leaves a mark if anything runs it, which nothing may.
! st_mine || mkdir -p "$WORK/assh/c-piscine/c-piscine-c-99/deliverable/ex00" "$WORK/assh/docs"
! st_mine || (
	cd "$WORK/assh" || exit 1
	git init -q .
	git config user.email selftest@example.invalid
	git config user.name selftest
	printf '#!/bin/sh\n# Bundle the pieces.\nselftest_pack --fold alpha.part beta.part > bundle.out\ntouch "%s"\n' \
		"$WORK/assh.ran" > c-piscine/c-piscine-c-99/deliverable/ex00/selftest_bundle.sh
	printf 'How the pieces are kept.\n' > docs/notes.md
	git add -A && git commit -q -m clean
) > /dev/null 2>&1 || as_broke "assh clean"
want_green "answer_scan: a tree whose only answer is a script scans" -- \
	as_scan "$WORK/assh"
want_green "answer_scan: ...and never runs it" -- test ! -e "$WORK/assh.ran"
! st_mine || ( cd "$WORK/assh" &&
	printf 'int\tft_selftest_fold(int a)\n{\n\tif (a > 9)\n\t\ta = a / 9;\n\telse\n\t\ta = a * 9;\n\treturn (a + 1);\n}\n' \
		> c-piscine/c-piscine-c-99/deliverable/ex00/ft_selftest_fold.c &&
	printf 'Then: selftest_pack  --fold alpha.part beta.part > bundle.out\n' >> docs/notes.md &&
	git add -A && git commit -qm sleak ) > /dev/null 2>&1 || as_broke "sleak"
want_out   "answer_scan: a turn-in script's line in a doc is found" \
	"docs/notes.md:2: an answer line from c-piscine/c-piscine-c-99/deliverable/ex00/selftest_bundle.sh" -- \
	as_scan "$WORK/assh"
# A zone file of a kind no class reads was never looked at: the same script
# turned in with no .sh in its name, or kept as a generator not named
# exNN.sh, and its line in the doc scanned "OK ... none outside the zone"
# (V309). Such a file now stops the run until a class reads its kind, and
# is still never run. A README.md at the root of deliverable/ and a file
# tools/resources.tsv registers are let by, each for its reason there.
! st_mine || ( cd "$WORK/assh" &&
	git mv c-piscine/c-piscine-c-99/deliverable/ex00/selftest_bundle.sh \
		c-piscine/c-piscine-c-99/deliverable/ex00/selftest_bundle &&
	git commit -qm nosh ) > /dev/null 2>&1 || as_broke "nosh"
want_broken "answer_scan: a zone file no class reads stops the scan" \
	"ex00/selftest_bundle' is tracked in the zone, and no class here reads it" -- \
	as_scan "$WORK/assh"
want_green "answer_scan: ...and is never run either" -- test ! -e "$WORK/assh.ran"
! st_mine || ( cd "$WORK/assh" && mkdir -p c-piscine/c-piscine-shell-99/generators &&
	git mv c-piscine/c-piscine-c-99/deliverable/ex00/selftest_bundle \
		c-piscine/c-piscine-shell-99/generators/selftest_helper.sh &&
	git commit -qm gen ) > /dev/null 2>&1 || as_broke "gen"
want_broken "answer_scan: ...nor does a generator not named exNN.sh" \
	"generators/selftest_helper.sh' is tracked in the zone, and no class here reads it" -- \
	as_scan "$WORK/assh"
! st_mine || ( cd "$WORK/assh" && git rm -q c-piscine/c-piscine-shell-99/generators/selftest_helper.sh &&
	mkdir -p tools c-piscine/c-piscine-c-99/tests/ex00 &&
	printf 'A toy project, kept in the zone.\n' > c-piscine/c-piscine-c-99/deliverable/README.md &&
	printf 'selftest_alpha: one\nselftest_beta: two\n' > c-piscine/c-piscine-c-99/deliverable/ex00/toy.dict &&
	cp c-piscine/c-piscine-c-99/deliverable/ex00/toy.dict c-piscine/c-piscine-c-99/tests/ex00/ref.dict &&
	printf 'dict=toy.dict\n' > c-piscine/c-piscine-c-99/tests/ex00/check.sh &&
	printf 'c-piscine/c-piscine-c-99\ttoy.dict\tc-piscine/c-piscine-c-99/deliverable/ex00/toy.dict\tturn-in\n' \
		> tools/resources.tsv &&
	git add -A && git commit -qm issued ) > /dev/null 2>&1 || as_broke "issued"
want_green "answer_scan: ...but a deliverable/README.md and an issued file do" -- \
	as_scan "$WORK/assh"
# And no wider: a README.md below that root, and the same .dict once
# tools/resources.tsv registers another path, are refused. stub_check.sh's
# issued-file list once named *.dict itself, which let any .dict through.
! st_mine || ( cd "$WORK/assh" &&
	git mv c-piscine/c-piscine-c-99/deliverable/README.md \
		c-piscine/c-piscine-c-99/deliverable/ex00/README.md &&
	git commit -qm readme ) > /dev/null 2>&1 || as_broke "readme"
want_broken "answer_scan: ...a README.md below a deliverable/'s root is not" \
	"ex00/README.md' is tracked in the zone, and no class here reads it" -- \
	as_scan "$WORK/assh"
! st_mine || ( cd "$WORK/assh" &&
	git mv c-piscine/c-piscine-c-99/deliverable/ex00/README.md \
		c-piscine/c-piscine-c-99/deliverable/README.md &&
	printf 'c-piscine/c-piscine-c-99\tother.dict\tc-piscine/c-piscine-c-99/deliverable/ex00/other.dict\tturn-in\n' \
		> tools/resources.tsv &&
	git add tools/resources.tsv && git commit -qm unissued ) > /dev/null 2>&1 || as_broke "unissued"
want_broken "answer_scan: ...nor a .dict tools/resources.tsv does not register" \
	"ex00/toy.dict' is tracked in the zone, and no class here reads it" -- \
	as_scan "$WORK/assh"
# Header macros and Makefile lines: the whole answer to C 08's exercises, and to
# Reloaded ex24, is one of those, and the scan used to look at neither. Compared
# with every blank removed, so a re-spaced copy is still one.
! st_mine || (
	cd "$WORK/as" || exit 1
	git rm -q c-piscine/c-piscine-c-99/tests/ex00/ref.c
	printf '#ifndef SELFTEST_H\n# define SELFTEST_H\n# define SELFTEST_MIX(a, b) ((a) * 3 + (b))\n#endif\n' \
		> c-piscine/c-piscine-c-99/deliverable/ex00/selftest.h
	printf 'NAME = selftest\n\nall:\n\tcp selftest.src $(NAME).made\n' \
		> c-piscine/c-piscine-c-99/deliverable/ex00/Makefile
	git add -A && git commit -qm defs
) > /dev/null 2>&1 || as_broke "defs"
want_green "answer_scan: a macro and a Makefile kept in the zone are clean" -- \
	as_scan "$WORK/as"
# (mkdir: the git rm above took the directory with the last file in it.)
! st_mine || ( cd "$WORK/as" && mkdir -p c-piscine/c-piscine-c-99/tests/ex00 &&
	printf '/* #define SELFTEST_MIX(a,b) ((a)*3+(b)) */\n' \
	> c-piscine/c-piscine-c-99/tests/ex00/notes.c && git add -A && git commit -qm hleak ) > /dev/null 2>&1 || as_broke "hleak"
want_out   "answer_scan: a macro re-spaced into a test is found" \
	"tests/ex00/notes.c:1: an answer line" -- \
	as_scan "$WORK/as"
! st_mine || ( cd "$WORK/as" && git rm -q c-piscine/c-piscine-c-99/tests/ex00/notes.c &&
	mkdir -p c-piscine/c-piscine-c-99/tests/ex00 && printf 'the recipe: cp selftest.src $(NAME).made\n' \
		> c-piscine/c-piscine-c-99/tests/ex00/doc.txt && git add -A && git commit -qm mleak ) > /dev/null 2>&1 || as_broke "mleak"
want_out   "answer_scan: a Makefile line in a doc is found" \
	"tests/ex00/doc.txt:1: an answer line" -- \
	as_scan "$WORK/as"
# A complete ed25519 public key anywhere outside the zone: any one passes Shell
# 00 ex03, so it needs no source to match. Assembled at run time, so this file
# never holds a whole one itself.
! st_mine || ( cd "$WORK/as" && git rm -q c-piscine/c-piscine-c-99/tests/ex00/doc.txt &&
	mkdir -p c-piscine/c-piscine-c-99/tests/ex00 &&
	printf 'vector: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI%s selftest\n' \
		"$(printf 'Q%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 \
			22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43)" \
		> c-piscine/c-piscine-c-99/tests/ex00/audit.txt && git add -A && git commit -qm kleak ) > /dev/null 2>&1 || as_broke "kleak"
want_out   "answer_scan: a whole ed25519 public key is found" \
	"tests/ex00/audit.txt:1: a complete ed25519 public key" -- \
	as_scan "$WORK/as"
# The names class: a design leaks without a line of its code, as the rush-00
# comments naming one team's structs and a file the template lacked did. The
# fixture's names are invented. What the arms pin is which ones prose may
# repeat -- what a test, an include guard, the subject contract's files list
# or the program's name (an artifact) gives -- and which it may not. The header's first macro
# holds "/*" in a string: a regex pass took that for a comment and never saw
# the macro after it.
! st_mine || (
	cd "$WORK/as" || exit 1
	git rm -q c-piscine/c-piscine-c-99/tests/ex00/audit.txt
	mkdir -p c-piscine/c-piscine-c-99/tests/ex00
	printf '#ifndef SELFTEST_PAIR_H\n# define SELFTEST_PAIR_H\n# define SELFTEST_ART "/*"\n# define SELFTEST_EDGE 3\n\ntypedef struct s_selftest_pair\n{\n\tint\ta;\n}\tt_selftest_pair;\n\n#endif\n' \
		> c-piscine/c-piscine-c-99/deliverable/ex00/selftest_pair.h
	printf 'static int\tselftest_twice(int n)\n{\n\treturn (n + n);\n}\n\nstatic int\tselftest_tool(int n)\n{\n\treturn (n - 1);\n}\n' \
		> c-piscine/c-piscine-c-99/deliverable/ex00/selftest_util.c
	printf 't_selftest_pair\tg_pair;\n' > c-piscine/c-piscine-c-99/tests/ex00/main.c
	printf 'subject(\n    exercises = {\n        "00": exercise(dir = "ex00/", files = ["ft_selftest_mix.c"]),\n    },\n)\n\nc_make(artifact = "ft_selftest_tool")\n' \
		> c-piscine/c-piscine-c-99/BUILD.bazel
	printf 'Build on t_selftest_pair, guarded by SELFTEST_PAIR_H, in ft_selftest_mix.c, for selftest_tool.\n' \
		> c-piscine/c-piscine-c-99/README.md
	git add -A && git commit -qm names && git tag names
) > /dev/null 2>&1 || as_broke "names"
want_green "answer_scan: names a test, a guard or the contract gives are clean" -- \
	as_scan "$WORK/as"
# `bazel run //tools:answer_scan` starts the script from bazel-bin/tools/, and
# stub_check.sh is not there: the workspace's own copy must be found instead.
# Every other arm runs it from the source tree, which is how that went unseen.
# units.awk, which reads the subject contracts, is found the same way.
! st_mine || mkdir -p "$WORK/asbin" "$WORK/as/tools"
! st_mine || cp "$TOOLS/answer_scan.sh" "$WORK/asbin/answer_scan"
! st_mine || cp "$TOOLS/stub_check.sh" "$WORK/as/tools/stub_check.sh"
! st_mine || cp "$TOOLS/units.awk" "$WORK/as/tools/units.awk"
want_green "answer_scan: run as bazel run does, it finds stub_check" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/as" "$SH" "$WORK/asbin/answer_scan"
! st_mine || rm -rf "$WORK/as/tools"
want_broken "answer_scan: with no stub_check.sh anywhere it refuses" \
	"no stub_check.sh beside this script" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/as" "$SH" "$WORK/asbin/answer_scan"
! st_mine || mkdir -p "$WORK/as/tools"
! st_mine || cp "$TOOLS/stub_check.sh" "$WORK/as/tools/stub_check.sh"
want_broken "answer_scan: ...and with no units.awk anywhere" \
	"no units.awk beside this script" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/as" "$SH" "$WORK/asbin/answer_scan"
! st_mine || rm -rf "$WORK/as/tools"
# --declared is what the template build's last check reads the declared
# names with, and that check has no arms of its own: exactly the declared
# names, nothing else. A BUILD file from before the subject contract named
# them in a c_files() call, which --declared still reads (C_FILES_CALL), for
# a template index from that time.
! st_mine || printf 'c_files(\n    num = "00",\n    required = ["ft_selftest_mix.c"],\n)\n' > "$WORK/as_cfiles.bazel"
want_green "answer_scan --declared: exactly the c_files() names of a BUILD file before the contract" -- \
	"$SH" -c '[ "$("$1" "$2" --declared < "$3")" = ft_selftest_mix.c ]' _ \
	"$SH" "$TOOLS/answer_scan.sh" "$WORK/as_cfiles.bazel"
# ...and a subject() contract's, as tools/units.awk reads it: each unit's
# `files` and `optional`, never a glob's argument; nothing from a files list
# outside subject(); a contract it cannot read refused with its line; and
# BUILD files named on the command line, each read once. Each is named and
# on standard input too, as the template build hands one over, so a copy
# that reads standard input alone is held to the same rows.
! st_mine || mkdir -p "$WORK/asdecl"
! st_mine || cat > "$WORK/asdecl/as_in.bazel" <<'AS_CONTRACT'
subject(
    grader = "moulinette",
    group = False,
    exercises = {
        "00": exercise(page = 1, dir = "ex00/", files = ["toy_in.c"], optional = ["toy_opt.c", "toy_*.c"], allowed = []),
    },
)
AS_CONTRACT
! st_mine || cat > "$WORK/asdecl/as_outside.bazel" <<'AS_CONTRACT'
x(
    data = {"exercises": {"00": exercise(page = 1, dir = "ex00/", files = ["toy_outside.c"], allowed = [])}},
)
AS_CONTRACT
! st_mine || cat > "$WORK/asdecl/as_unread.bazel" <<'AS_CONTRACT'
subject(
    grader = "moulinette",
    group = False,
    exercises = {
        "00": TOY_EXERCISE,
    },
)
AS_CONTRACT
# A list units.awk reads only in part (joined with + to a name it does not
# follow) gives the names it did read, and says it was read in part: a name
# only the unread part gives is not given, and a mention of it outside the
# zone then reads as an answer's with nothing to say why.
! st_mine || cat > "$WORK/asdecl/as_part.bazel" <<'AS_CONTRACT'
TOY_MORE = ["toy_more.c"]

subject(
    grader = "moulinette",
    group = False,
    exercises = {
        "00": exercise(page = 1, dir = "ex00/", files = ["toy_in.c"] + TOY_MORE, allowed = []),
    },
)
AS_CONTRACT
want_green "answer_scan --declared: a contract's files and optional names" -- \
	"$SH" -c '_o=$("$1" "$2" --declared "$3" < "$3") && [ "$_o" = "$(printf "toy_in.c\ntoy_opt.c")" ]' _ \
	"$SH" "$TOOLS/answer_scan.sh" "$WORK/asdecl/as_in.bazel"
want_green "answer_scan --declared: ...never a files list outside subject()" -- \
	"$SH" -c '_o=$("$1" "$2" --declared "$3" < "$3") && [ -z "$_o" ]' _ \
	"$SH" "$TOOLS/answer_scan.sh" "$WORK/asdecl/as_outside.bazel"
want_out "answer_scan --declared: a list read in part says so, naming its unit" \
	"$WORK/asdecl/as_part.bazel: ex00's files is read in part" -- \
	"$SH" -c '"$1" "$2" --declared "$3" < "$3"' _ \
	"$SH" "$TOOLS/answer_scan.sh" "$WORK/asdecl/as_part.bazel"
want_green "answer_scan --declared: ...and gives the names it read, exit 0" -- \
	"$SH" -c '_o=$("$1" "$2" --declared "$3" < "$3" 2> /dev/null) && [ "$_o" = toy_in.c ]' _ \
	"$SH" "$TOOLS/answer_scan.sh" "$WORK/asdecl/as_part.bazel"
want_broken "answer_scan --declared: a contract units.awk cannot read, with its line" \
	"units.awk: $WORK/asdecl/as_unread.bazel:5: " -- \
	"$SH" -c '"$1" "$2" --declared "$3" < "$3"' _ \
	"$SH" "$TOOLS/answer_scan.sh" "$WORK/asdecl/as_unread.bazel"
want_green "answer_scan --declared: ...and every BUILD file it is given" -- \
	"$SH" -c '_o=$("$1" "$2" --declared "$3" "$4" < "$3") &&
		[ "$_o" = "$(printf "toy_in.c\ntoy_opt.c\nft_selftest_mix.c")" ]' _ \
	"$SH" "$TOOLS/answer_scan.sh" "$WORK/asdecl/as_in.bazel" \
	"$WORK/as/c-piscine/c-piscine-c-99/BUILD.bazel"
# A scan over a tree whose one contract units.awk cannot read stops there:
# the names that subject gives are unknown, so any of them would be a hit.
! st_mine || ( cd "$WORK/as" && mkdir -p c-piscine/c-piscine-c-97 &&
	cp "$WORK/asdecl/as_unread.bazel" c-piscine/c-piscine-c-97/BUILD.bazel &&
	git add -A && git commit -qm unread ) > /dev/null 2>&1 || as_broke "unread"
want_broken "answer_scan: a contract it cannot read ends the run" \
	"nothing was scanned" -- \
	as_scan "$WORK/as"
! st_mine || ( cd "$WORK/as" && git rm -q -r c-piscine/c-piscine-c-97 &&
	git commit -qm read ) > /dev/null 2>&1 || as_broke "read"
! st_mine || ( cd "$WORK/as" && printf 'Mind s_selftest_pair.\n' >> c-piscine/c-piscine-c-99/README.md &&
	git commit -qam tag ) > /dev/null 2>&1 || as_broke "tag"
want_out   "answer_scan: a struct tag only the answers use is found" \
	"README.md:2: s_selftest_pair -- a struct, union or enum tag" -- \
	as_scan "$WORK/as"
# --worktree, as the maintainer's test //tools/tests:answer_scan runs it: no
# BUILD_WORKSPACE_DIRECTORY, and $0 a link (the runfiles tree's) to the
# checkout's own tools/answer_scan.sh -- the tree it scans is the one that
# link leads to (TO VERIFY V29). Untracked here, so not scanned itself: the
# steps below add their files by path, never with -A, until it is removed.
! st_mine || mkdir -p "$WORK/as/tools" "$WORK/aslink" "$WORK/asnogit/tools"
! st_mine || cp "$TOOLS/answer_scan.sh" "$TOOLS/stub_check.sh" "$TOOLS/units.awk" "$WORK/as/tools/"
! st_mine || ln -sf "$WORK/as/tools/answer_scan.sh" "$WORK/aslink/answer_scan"
want_out   "answer_scan --worktree: as a test runs it, it scans its own checkout" \
	"README.md:2: s_selftest_pair -- a struct, union or enum tag" -- \
	env -u BUILD_WORKSPACE_DIRECTORY "$SH" "$WORK/aslink/answer_scan" --worktree
! st_mine || cp "$TOOLS/answer_scan.sh" "$WORK/asnogit/tools/"
! st_mine || ln -sf "$WORK/asnogit/tools/answer_scan.sh" "$WORK/aslink/nogit"
# Under the ceiling: a hand run's WORK can sit in Bazel's execroot, whose
# .git is a link to the checkout's, and git found that one.
want_broken "answer_scan --worktree: a link to no git checkout refuses" \
	'is not a git checkout' -- \
	env -u BUILD_WORKSPACE_DIRECTORY GIT_CEILING_DIRECTORIES="$WORK" \
		"$SH" "$WORK/aslink/nogit" --worktree
! st_mine || cp "$TOOLS/answer_scan.sh" "$WORK/aslink/scan.sh"
want_broken "answer_scan --worktree: ...and a copy that is no checkout's file" \
	"not to a checkout's tools/answer_scan.sh" -- \
	env -u BUILD_WORKSPACE_DIRECTORY "$SH" "$WORK/aslink/scan.sh" --worktree
# ...and the refusal carries git's own reason, which is the only line saying
# what to fix where git refuses a checkout another user owns.
want_broken "answer_scan --worktree: ...saying git's reason" \
	'not a git repository' -- \
	env -u BUILD_WORKSPACE_DIRECTORY GIT_CEILING_DIRECTORIES="$WORK" \
		"$SH" "$WORK/aslink/nogit" --worktree
# A zone file stub_check refuses -- an empty one here -- ends the scan with
# stub_check's reason, not with "could not be read" over a file read whole.
! st_mine || ( cd "$WORK/as" && : > c-piscine/c-piscine-c-99/deliverable/ex00/ft_selftest_empty.c &&
	git add c-piscine/c-piscine-c-99/deliverable/ex00/ft_selftest_empty.c &&
	git commit -qm empty ) > /dev/null 2>&1 || as_broke "empty"
# as_untracked_tools -- 0 when the toy repo's index holds nothing under
# tools/, 2 when git cannot say. A helper and not a $(...) in the arm's
# words: those are expanded before want_green looks at its shard, so every
# shard that skips this section ran git in a folder only this one makes,
# and its log carried git's "fatal:" beside a green run.
as_untracked_tools() {
	_ast=$(git -C "$WORK/as" ls-files tools) || return 2
	test -z "$_ast"
}
want_green "answer_scan: the copied tools/ stays out of the toy repo's index" -- \
	as_untracked_tools
want_broken "answer_scan: a zone file stub_check refuses, with its reason" \
	'is empty' -- as_scan "$WORK/as"
! st_mine || ( cd "$WORK/as" && git rm -q c-piscine/c-piscine-c-99/deliverable/ex00/ft_selftest_empty.c &&
	git commit -qm unempty ) > /dev/null 2>&1 || as_broke "unempty"
# An approved header ships as it stands, so the names it defines are no
# answer's. The scan hands stub_check ./<path>, or the absolute path of the
# index's copy when the file is not on disk, and stub_check matched its
# approved paths against that spelling: the header was "an implementation",
# and a README naming its type was a leak. The arms run copies of the two
# scripts side by side (answer_scan.sh finds stub_check.sh beside itself),
# the stub_check one approving a made-up header, as in stub_check's section.
! st_mine || mkdir -p "$WORK/asap/bin" "$WORK/asap/tree/c-piscine/c-piscine-c-98/deliverable/ex00"
! st_mine || printf '%s\n\n#ifndef SC_KEPT_H\n# define SC_KEPT_H\n\ntypedef struct s_sc_kept\n{\n\tint\tn;\n}\tt_sc_kept;\n\n#endif\n' \
	"$SC_H" > "$WORK/asap/tree/c-piscine/c-piscine-c-98/deliverable/ex00/sc_kept.h"
! st_mine || _asak=$("$SH" "$TOOLS/stub_check.sh" --hash \
	"$WORK/asap/tree/c-piscine/c-piscine-c-98/deliverable/ex00/sc_kept.h" | cut -d' ' -f1)
! st_mine || awk -v e="$_asak c-piscine/c-piscine-c-98/deliverable/*/sc_kept.h selftest-fixture" \
	'{ print } /^APPROVED_HEADERS=.$/ { print e }' "$TOOLS/stub_check.sh" > "$WORK/asap/bin/stub_check.sh"
! st_mine || cp "$TOOLS/answer_scan.sh" "$WORK/asap/bin/answer_scan.sh"
! st_mine || cp "$TOOLS/units.awk" "$WORK/asap/bin/units.awk"
! st_mine || (
	cd "$WORK/asap/tree" || exit 1
	git init -q .
	git config user.email selftest@example.invalid
	git config user.name selftest
	printf 'int\tft_sc_mix(int a, int b)\n{\n\tif (a > b)\n\t\ta = a - b;\n\telse\n\t\ta = b - a;\n\treturn (a * 5);\n}\n' \
		> c-piscine/c-piscine-c-98/deliverable/ex00/ft_sc_mix.c
	printf 'Build on t_sc_kept.\n' > README.md
	git add -A && git commit -q -m approved
) > /dev/null 2>&1 || as_broke "approved"
want_green "answer_scan: an approved header's names are no answer's" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/asap/tree" "$SH" "$WORK/asap/bin/answer_scan.sh"
! st_mine || rm -f "$WORK/asap/tree/c-piscine/c-piscine-c-98/deliverable/ex00/sc_kept.h"
want_green "answer_scan: ...nor are they read from the index" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/asap/tree" "$SH" "$WORK/asap/bin/answer_scan.sh"
# ...even with the scan's scratch folder inside the checkout: stub_check
# matches an approval at the file's place in its workspace, and the index's
# copy sits at <scratch>/index/<path> there unless the scan names that copy's
# root as the workspace (V151, V232).
! st_mine || mkdir -p "$WORK/asap/tree/scratch"
want_green "answer_scan: ...with its scratch folder in the checkout" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/asap/tree" TMPDIR="$WORK/asap/tree/scratch" \
	"$SH" "$WORK/asap/bin/answer_scan.sh"
! st_mine || rm -rf "$WORK/as/tools"
! st_mine || ( cd "$WORK/as" && git checkout -q names -- . &&
	printf 'Then selftest_twice.\n' >> c-piscine/c-piscine-c-99/README.md &&
	git commit -qam static ) > /dev/null 2>&1 || as_broke "static"
want_out   "answer_scan: a static helper's name is found" \
	"README.md:2: selftest_twice -- a static function" -- \
	as_scan "$WORK/as"
! st_mine || ( cd "$WORK/as" && git checkout -q names -- . &&
	printf 'SELFTEST_EDGE is the width.\n' >> c-piscine/c-piscine-c-99/README.md &&
	git commit -qam macro ) > /dev/null 2>&1 || as_broke "macro"
want_out   "answer_scan: a macro after a \"/*\" string is found" \
	"README.md:2: SELFTEST_EDGE -- a macro" -- \
	as_scan "$WORK/as"
# A name reserved to the implementation is the C library's, not an answer's:
# an answer that defines _GNU_SOURCE before its includes made every harness
# file that does the same (tools/path_redirect.c) a hit.
! st_mine || ( cd "$WORK/as" && git checkout -q names -- . &&
	{ printf '#define _GNU_SOURCE\n'; cat c-piscine/c-piscine-c-99/deliverable/ex00/selftest_util.c; } \
		> "$WORK/as_util.c" && cp "$WORK/as_util.c" c-piscine/c-piscine-c-99/deliverable/ex00/selftest_util.c &&
	printf 'Built with _GNU_SOURCE defined.\n' >> c-piscine/c-piscine-c-99/README.md &&
	git commit -qam reserved ) > /dev/null 2>&1 || as_broke "reserved"
want_green "answer_scan: a reserved name (_GNU_SOURCE) an answer defines is no hit" -- \
	as_scan "$WORK/as"
! st_mine || ( cd "$WORK/as" && git checkout -q names -- . &&
	printf '# see deliverable/ex00/selftest_util.c\n' >> c-piscine/c-piscine-c-99/BUILD.bazel &&
	git commit -qam file ) > /dev/null 2>&1 || as_broke "file"
want_out   "answer_scan: a file no contract declares is found by name" \
	"BUILD.bazel:8: selftest_util.c -- a file name" -- \
	as_scan "$WORK/as"
# A clue is prose, like the README: it gives no name, so one that repeats a
# helper's is found -- when every word under tests/ counted as given, the leak
# vouched for itself and the scan stayed green.
! st_mine || ( cd "$WORK/as" && git checkout -q names -- . &&
	printf 'ex00\tUse selftest_twice for it.\n' > c-piscine/c-piscine-c-99/tests/ex00/clues.tsv &&
	git add -A && git commit -qm clue ) > /dev/null 2>&1 || as_broke "clue"
want_out   "answer_scan: a helper's name in a clue is found" \
	"tests/ex00/clues.tsv:1: selftest_twice -- a static function" -- \
	as_scan "$WORK/as"
# A Makefile line that is only a path the subject gives is no answer line: a
# grader's file, which the subject contract's `provided` puts in place, is
# named in the BUILD file there (its subject() call, which is where
# tools/units.awk reads it), and a correct Makefile naming it was a hit. The
# negative premise: a path of the Makefile's own, copied into a doc, is still
# one. The Makefile's list is invented, and shaped like no exercise's. (The
# clue arm's file goes first: checking out `names` keeps a file added since.)
! st_mine || ( cd "$WORK/as" && git checkout -q names -- . &&
	git rm -q c-piscine/c-piscine-c-99/tests/ex00/clues.tsv &&
	printf 'OWN = \\\n\tgrader/selftest_mine.c\nGIVEN = \\\n\tgrader/selftest_given.c\n' \
		>> c-piscine/c-piscine-c-99/deliverable/ex00/Makefile &&
	printf 'subject(\n    exercises = {\n        "00": exercise(\n            dir = "ex00/",\n            files = ["ft_selftest_mix.c"],\n            provided = {"tests/ex00/g/selftest_given.c": "grader/selftest_given.c"},\n        ),\n    },\n)\n\nc_make(artifact = "ft_selftest_tool")\n' \
		> c-piscine/c-piscine-c-99/BUILD.bazel &&
	git commit -qam overlay && git tag overlay ) > /dev/null 2>&1 || as_broke "overlay"
want_green "answer_scan: a line of paths the subject gives is no answer" -- \
	as_scan "$WORK/as"
! st_mine || ( cd "$WORK/as" && printf 'Build it from grader/selftest_mine.c.\n' \
	>> c-piscine/c-piscine-c-99/README.md && git commit -qam own ) > /dev/null 2>&1 || as_broke "own"
want_out   "answer_scan: ...while a path of the answer's own still is" \
	"README.md:2: an answer line" -- \
	as_scan "$WORK/as"
# A name `git ls-files` quotes -- a byte above 0x7f, an e with an acute accent
# here -- was listed by that quoted name, which is no file: stub_check called
# it unreadable, awk could not open it, and the answer's definitions were never
# read. A static helper only it names, in a harness file, went unreported,
# "OK ... none outside the zone". Listed with -z, every name is read whole.
! st_mine || ( cd "$WORK/as" && git checkout -q overlay -- . &&
	printf 'static int\tselftest_accent(int n)\n{\n\treturn (n * n + 1);\n}\n' \
		> "c-piscine/c-piscine-c-99/deliverable/ex00/selftest_$(printf '\303\251').c" &&
	printf 'Then selftest_accent.\n' >> c-piscine/c-piscine-c-99/README.md &&
	git add -A && git commit -qm accent ) > /dev/null 2>&1 || as_broke "accent"
want_out   "answer_scan: a helper of a file git quotes the name of is found" \
	"README.md:2: selftest_accent -- a static function" -- \
	as_scan "$WORK/as"
# A file the zone lists and the scan cannot read is one whose answer was never
# looked for, so the run ends there (exit 2) rather than reporting on the rest:
# a stub_check that could not read it, and an awk that could not open it, were
# both passed over. Here a directory stands where the index has the file: a
# file only gone from the disk is read from the index instead (above), so
# it was this arm's fixture until that was so.
! st_mine || rm -f "$WORK/as/c-piscine/c-piscine-c-99/deliverable/ex00/selftest_util.c"
! st_mine || mkdir "$WORK/as/c-piscine/c-piscine-c-99/deliverable/ex00/selftest_util.c"
want_broken "answer_scan: a zone file it cannot read ends the run" \
	"could not be read" -- \
	as_scan "$WORK/as"
! st_mine || rmdir "$WORK/as/c-piscine/c-piscine-c-99/deliverable/ex00/selftest_util.c"
! st_mine || ( cd "$WORK/as" && git checkout -q -- . ) > /dev/null 2>&1 || as_broke "as checkout, after the unreadable zone file"
# A file at the root whose name is shaped like an awk assignment: awk took
# `selftest=notes.txt` for one, read its standard input instead -- the rest of
# the list of files to scan -- and the file and every one after it went
# unscanned. Read by redirection, it is a file like any other.
! st_mine || ( cd "$WORK/as" && git checkout -q overlay -- . &&
	printf 'Then selftest_twice.\n' > selftest=notes.txt &&
	git add -A && git commit -qm assign ) > /dev/null 2>&1 || as_broke "assign"
want_out   "answer_scan: a file named like an awk assignment is read" \
	"selftest=notes.txt:1: selftest_twice -- a static function" -- \
	as_scan "$WORK/as"
# A library's contract writes its files as a pattern (Libft's "ft_*.c") and
# names its functions: the file of a function it names, where the pattern
# takes it, is a name the subject fixes, not the answer's. A harness comment
# naming it was a hit as soon as the student's file stopped being a stub,
# and the push gate refused main. The negative premise: a file the pattern
# takes and no function names is still the answer's own.
! st_mine || ( cd "$WORK/as" && git checkout -q overlay -- . &&
	git rm -q selftest=notes.txt &&
	mkdir -p cursus/selftest-lib/deliverable &&
	printf 'subject(\n    units = {\n        "selftestlib": unit(\n            files = ["Makefile"],\n            optional = ["ft_*.c"],\n            functions = {\n                "ft_selftest_lib": [],\n            },\n        ),\n    },\n)\n\n# ft_selftest_lib.c is turned in at the root.\n' \
		> cursus/selftest-lib/BUILD.bazel &&
	printf 'int\tft_selftest_lib(int n)\n{\n\tif (n < 0)\n\t\tn = -n;\n\treturn (n * 7 + 3);\n}\n' \
		> cursus/selftest-lib/deliverable/ft_selftest_lib.c &&
	printf 'int\tft_selftest_lib_aux(int n)\n{\n\tif (n > 9)\n\t\tn = n %% 9;\n\treturn (n * 5 + 1);\n}\n' \
		> cursus/selftest-lib/deliverable/ft_selftest_aux.c &&
	git add -A && git commit -qm library ) > /dev/null 2>&1 || as_broke "library"
want_green "answer_scan: a library function's file its contract's pattern takes is given" -- \
	as_scan "$WORK/as"
! st_mine || ( cd "$WORK/as" && printf '# and ft_selftest_aux.c beside it.\n' \
	>> cursus/selftest-lib/BUILD.bazel && git commit -qam aux ) > /dev/null 2>&1 || as_broke "library aux"
want_out   "answer_scan: ...while a file the pattern takes and no function names is not" \
	"BUILD.bazel:14: ft_selftest_aux.c -- a file name" -- \
	as_scan "$WORK/as"
! st_mine || mkdir -p "$WORK/as2/c-piscine/c-piscine-c-99/deliverable/ex00"
! st_mine || (
	cd "$WORK/as2" || exit 1
	git init -q .
	printf '%s\n\nint\tft_x(int n)\n{\n\t(void)n;\n\treturn (0);\n}\n' "$SC_H" \
		> c-piscine/c-piscine-c-99/deliverable/ex00/ft_x.c
	git add -A
) > /dev/null 2>&1 || as_broke "as2"
want_broken "answer_scan: a stubbed tree has nothing to scan for" \
	"no answer to look for" -- \
	as_scan "$WORK/as2"
# Every fixture step above that built a repository succeeded (as_broke, at
# the top of this section).
as_unbroken() {
	[ -s "$WORK/as_broke" ] || return 0
	sed 's/^/a fixture step failed: /' "$WORK/as_broke"
	return 1
}
want_green "answer_scan: every fixture step it built succeeded" -- as_unbroken
