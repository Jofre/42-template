# ------------------------------------------------------------------ make_test
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# Every arm here runs make_test through mt, which is `once` over it: a run
# that several arms read is made once. The rule steps sleep a second where
# they check re, and this section had grown to twice the runs it needed --
# the red/out/none triples each paid for their own -- which is what took the
# whole file past its timeout on a loaded box.
mt() {  # mt ARGS...: make_test.sh ARGS, once per distinct ARGS
	once "$SH" "$TOOLS/make_test.sh" --nm "$NM" --build-target selftest_build "$@"
}

# The `rm -f` added in 6965462. Bazel's data glob sweeps in whatever a hand-run
# of make left behind in deliverable/ — .gitignore hides those from git, not from
# native.glob — and copies it into the scratch build dir, so without that line a
# build script producing NOTHING reported green off the stale artifact. The
# --script arm is the one worth pinning: it never runs the fclean/re hygiene the
# Makefile arm gets, which is what would otherwise have caught the stale copy.
#
# The fixture is a directory of its own because the runner stages the anchor's
# whole DIRECTORY: anchoring anywhere in $WORK would copy every other fixture in
# this file into the build.
mkdir -p "$WORK/mk"
printf '#!/bin/sh\n:\n' > "$WORK/mk/build_none.sh"
printf '#!/bin/sh\n: > libselftest.a\n' > "$WORK/mk/build_ok.sh"
printf 'stale artifact from an earlier hand-run\n' > "$WORK/mk/libselftest.a"
# Is the pinned make really the one that runs? A --make that is accepted and
# then ignored looks exactly like one that works, and the obvious arm does not
# distinguish them: point it at a directory with no Makefile and BOTH a broken
# make and the box's fail, so the red proves nothing.
#
# So the fixture is a Makefile that genuinely builds. The box's make succeeds on
# it (second arm), and a --make that is not make at all must therefore fail
# (first arm). Only the pair is conclusive. --rules "" because this fixture is
# about which make runs, not about clean/fclean/re, and it has none of them.
mkdir -p "$WORK/mkbin"
printf 'all:\n\t: > libselftest.a\n' > "$WORK/mkbin/Makefile"
want_red "make_test: --make is used, not accepted and ignored" -- \
	mt --make /bin/false --rules "" \
		--anchor "$WORK/mkbin/Makefile" --artifact libselftest.a
want_green "make_test: and the same fixture builds with a real make" -- \
	mt --rules "" --anchor "$WORK/mkbin/Makefile" --artifact libselftest.a

# --rules all. The build runs a bare `make`, which runs the FIRST rule in the
# file, so a Makefile with no `all` passed it whenever that first rule built the
# artifact. The pair: mkbin (whose one rule IS all) stays green once the check
# runs, and a Makefile whose only rule is named after the artifact goes red.
mkdir -p "$WORK/mknoall"
printf 'libselftest.a:\n\t: > libselftest.a\n' > "$WORK/mknoall/Makefile"
want_green "make_test: a Makefile with an all rule passes --rules all" -- \
	mt --rules all --anchor "$WORK/mkbin/Makefile" --artifact libselftest.a
want_red   "make_test: one without it fails, though bare make builds" -- \
	mt --rules all --anchor "$WORK/mknoall/Makefile" --artifact libselftest.a
want_out   "make_test: ...and says the rule is missing" 'your Makefile has no all rule' -- \
	mt --rules all --anchor "$WORK/mknoall/Makefile" --artifact libselftest.a

# What the build printed reaches the log through the one renderer, cut: a
# recipe that clears the screen, or prints without end, wrote its bytes and
# every line of them into the log as they were.
mkdir -p "$WORK/mkloud"
{
	printf 'all:\n'
	printf '\t@printf %s\n' "'\\033[2J\\rsel_cr\\n'"
	printf '\t@awk %s\n' "'BEGIN { for (sel_i = 1; sel_i <= 1000; sel_i++) print sel_i }'"
	printf '\t@: > libselftest.a\n'
} > "$WORK/mkloud/Makefile"
want_broken_none "make_test: a build's raw escape never reaches the log" \
	"$(printf '\033')" -- mt --rules "" --anchor "$WORK/mkloud/Makefile" --artifact libselftest.a
want_out   "make_test: ...it is shown in the renderer's notation" '\x1b[2J\x0dsel_cr' -- \
	mt --rules "" --anchor "$WORK/mkloud/Makefile" --artifact libselftest.a
want_out   "make_test: ...and the build's output is cut, saying so" 'more line(s)' -- \
	mt --rules "" --anchor "$WORK/mkloud/Makefile" --artifact libselftest.a
# make stops at the recipe that failed, so a failed build's error is its
# last line: a long one's excerpt keeps its end as well as its start, and
# the FAIL does not say all of its output is above.
mkdir -p "$WORK/mklong"
{
	printf 'all:\n'
	printf '\t@awk %s\n' "'BEGIN { for (sel_i = 1; sel_i <= 300; sel_i++) print \"sel_echo \" sel_i }'"
	printf '\t@echo sel_the_last_word; exit 1\n'
} > "$WORK/mklong/Makefile"
want_out   "make_test: a long failed build's log ends in its error" 'sel_the_last_word' -- \
	mt --rules "" --anchor "$WORK/mklong/Makefile" --artifact libselftest.a
want_out   "make_test: ...and says the lines between are not above" 'its first and last lines are above' -- \
	mt --rules "" --anchor "$WORK/mklong/Makefile" --artifact libselftest.a

mks() {  # mks DIR/SCRIPT: the --script arm, over the script in $WORK/DIR
	mt --anchor "$WORK/$1" --artifact libselftest.a --script "${1##*/}"
}
want_red   "make_test: a stale artifact is not a build" -- mks mk/build_none.sh
want_green "make_test: a script that really builds passes" -- mks mk/build_ok.sh
# The script arm names the script. Its failure used to say "'make' succeeded"
# and talk of targets and rules, for C 09 ex00, which has no Makefile at all.
want_out   "make_test: a script that built nothing is named" 'sh build_none.sh' -- \
	mks mk/build_none.sh
want_broken_none "make_test: ...and make is not mentioned" "'make'" -- \
	mks mk/build_none.sh

# A Makefile that BUILT NOTHING is not a naming problem. The build used to fall
# through to "check the name your rule gives", or, under --graph, to the flag
# order over an empty listing. Three shapes, each red either way; what is
# pinned is the diagnosis: no rule at all (make's own "No targets"), a first
# rule that is not the one that builds (the default goal, named), and a recipe
# that only echoes -- the stub every Makefile exercise starts from.
# THE SENTENCES a check applies (--quotes), a toy subject's -- no arm quotes a
# real one. --graph is backed by three of them, and the rule arms by the four
# definitions: without those, what clean, fclean and re do is not exNN_build's
# question but exNN_build_rules', at robust ("make_test sentences", below).
MKQ="$WORK/mkquotes"
mkdir -p "$MKQ"
{
	printf 'print\tToy, p.1: "Print every command."\n'
	printf 'unnecessary\tToy, p.1: "Redo nothing that is done."\n'
	printf 'objects\tToy, p.1: "Each object beside its source."\n'
} > "$MKQ/graph.tsv"
{
	printf 'all\tToy, p.2: "all builds the library."\n'
	printf 'clean\tToy, p.2: "clean removes what the build made on the way."\n'
	printf 'fclean\tToy, p.2: "fclean is clean, and the library too."\n'
	printf 're\tToy, p.2: "re is fclean, then all."\n'
} > "$MKQ/rules.tsv"
mkdir -p "$WORK/mknorule" "$WORK/mkfirst" "$WORK/mkecho"
printf '# no rule yet\n' > "$WORK/mknorule/Makefile"
printf 'clean:\n\trm -f libselftest.a\nall:\n\t: > libselftest.a\n' > "$WORK/mkfirst/Makefile"
printf 'all:\n\techo selftest stub\n' > "$WORK/mkecho/Makefile"
mkn() {  # mkn DIR [--graph]: no rule checked, over $WORK/DIR/Makefile
	mt --rules "" ${2:+"$2"} ${2:+--quotes} ${2:+"$MKQ/graph.tsv"} \
		--anchor "$WORK/$1/Makefile" --artifact libselftest.a
}
want_out   "make_test: no rule at all shows make's own words" 'No targets' -- \
	mkn mknorule --graph
want_broken_none "make_test: ...and does not blame the flag order" 'in that order' -- \
	mkn mknorule --graph
want_out   "make_test: a first rule that builds nothing is named" "default goal is 'clean'" -- \
	mkn mkfirst
want_out   "make_test: an echo-only recipe reads as not written yet" 'not written yet' -- \
	mkn mkecho
# The other way `make -n` lists nothing: it read rules and could not follow
# them. That is no stub, and make's own error -- which names what it stopped
# on -- used to go to /dev/null under a message about the flag order.
mkdir -p "$WORK/mkplan"
printf 'all: libselftest.a\nlibselftest.a: absent.txt\n\tcp absent.txt libselftest.a\n' \
	> "$WORK/mkplan/Makefile"
want_out   "make_test: make -n's own error is shown" "No rule to make target 'absent.txt'" -- \
	mkn mkplan --graph
want_broken_none "make_test: ...and it is not called unwritten" 'not written yet' -- \
	mkn mkplan --graph
# The three diagnoses no arm above reaches. No rule at all WITHOUT --graph is
# the build's own "No targets" branch, not make -n's. A --graph plan that runs
# no compile at all is not told about its flags. And the default goal is read
# through a recipe that calls $(MAKE): its sub-make prints its own database,
# with its own default goal, before the top make prints the one that counts.
want_out   "make_test: a bare make with no rule says there is none" 'has no rule yet' -- \
	mkn mknorule
want_out   "make_test: --graph, a plan with no .c in it is named" 'planned no compile command' -- \
	mkn mkecho --graph
mkdir -p "$WORK/mkrec"
printf 'first:\n\t$(MAKE) -f sub.mk\n' > "$WORK/mkrec/Makefile"
printf 'other:\n\t:\n' > "$WORK/mkrec/sub.mk"
want_out   "make_test: a recursive make's default goal is its own" "default goal is 'first'" -- \
	mkn mkrec
want_broken_none "make_test: ...never the sub-make's" "default goal is 'other'" -- \
	mkn mkrec

# THE RULE STEPS, each from a start state of its own. `re` used to run straight
# after `make all` had rebuilt the tree, and was judged by the artifact being
# there, so a Makefile with no re rule passed; make's output was thrown away,
# so a missing rule was blamed on re's order. mkrules writes a Makefile that
# does all four jobs, shaped like no exercise's: cp stands in for every
# compiler and archiver, and each rule spells out its own files. Every red arm
# is that Makefile with one rule changed.
mkrules() {  # mkrules DIR CLEAN-RECIPE RE-RULE [FCLEAN-RECIPE]
	mkdir -p "$WORK/$1"
	printf 'selftest\n' > "$WORK/$1/sel.txt"
	{
		printf 'all: libselftest.a\n'
		printf 'libselftest.a: sel.o\n\tcp sel.o libselftest.a\n'
		printf 'sel.o: sel.txt\n\tcp sel.txt sel.o\n'
		printf 'clean:\n\t%b\n' "$2"
		printf 'fclean:\n\t%b\n' "${4:-rm -f sel.o libselftest.a}"
		printf '%b' "$3"
	} > "$WORK/$1/Makefile"
}
_mkre='re:\n\trm -f sel.o libselftest.a\n\t$(MAKE) all\n'
mkrules mkre_ok 'rm -f sel.o' "$_mkre"
mkrules mkre_none 'rm -f sel.o' ''
mkrules mkre_all 'rm -f sel.o' 're: all\n'
mkrules mkre_clean 'rm -f sel.o' 're:\n\trm -f sel.o\n\t$(MAKE) all\n'
mkrules mkre_keep 'rm -f sel.o' 're:\n\trm -f libselftest.a\n\t$(MAKE) all\n'
mkrules mkre_cleanerr 'rm sel.o' "$_mkre"
# mkr and mkrx name the twins (--build-target) as c_make does, so the arms
# that read a twin's name share these runs instead of making their own.
mkr() {  # mkr DIR [RULES]: with the toy subject's definitions of the rules
	mt --rules "${2-all,clean,fclean,re}" --build-target selftest_build \
		--quotes "$MKQ/rules.tsv" --anchor "$WORK/$1/Makefile" --artifact libselftest.a
}
want_green "make_test: four rules that each do their job pass" -- mkr mkre_ok
want_red   "make_test: no re rule fails, all having just built" -- mkr mkre_none
want_out   "make_test: ...and says so in make's own words" \
	"No rule to make target 're'" -- mkr mkre_none
want_out   "make_test: ...and names the missing rule" 'your Makefile has no re rule' -- \
	mkr mkre_none
want_red   "make_test: an re that only rebuilds fails" -- mkr mkre_all
want_red   "make_test: an re built on clean fails" -- mkr mkre_clean
want_out   "make_test: ...because the old artifact survives it" 'left the old' -- \
	mkr mkre_clean
want_red   "make_test: an re that keeps the objects fails" -- mkr mkre_keep
want_out   "make_test: ...and lists them" 'kept object files' -- mkr mkre_keep
# No subject says what a cleaning rule exits with when there is nothing to
# clean, so that is robust-level rigour. make_test has one target, at basic, so
# it is a WARNING there and the test stays green.
want_green "make_test: clean erroring on a clean tree is not a FAIL" -- \
	mkr mkre_cleanerr
want_out   "make_test: ...but it is named, with the rule" \
	"WARNING — 'make clean' on a tree with nothing to clean" -- mkr mkre_cleanerr
# No subject says an evaluator runs a rule twice, so the warning does not.
want_broken_none "make_test: ...and claims nothing about evaluators" \
	'evaluators' -- mkr mkre_cleanerr

# A rule named in .PHONY and nowhere else: make knows the name, finds nothing
# to do for it, says so and exits 0 -- which read as a re that ran, and was
# blamed on what re did ("left the old ..."). The pair: the same .PHONY line
# over a Makefile whose four rules exist stays green.
mkrules mkre_phony 'rm -f sel.o' '.PHONY: re fclean clean all\n'
mkrules mkre_phonyok 'rm -f sel.o' ".PHONY: re fclean clean all\\n$_mkre"
want_red   "make_test: a re named only in .PHONY fails" -- mkr mkre_phony
want_out   "make_test: ...as a missing rule, not as what re did" \
	'your Makefile has no re rule' -- mkr mkre_phony
want_green "make_test: ...while phony rules that exist pass" -- mkr mkre_phonyok

# An EMPTY rule the Makefile writes is not a missing one. make's database gives
# `clean:`, written with no prerequisite and no recipe, the same entry as a
# clean that .PHONY alone names, so it was called missing over a build that
# leaves nothing for it to remove. It is judged by what it does instead: green
# with nothing to clean, red on the objects it leaves, while a clean named only
# in .PHONY stays a missing rule. mkempty writes the Makefile: CLEAN is the
# clean rule's text (none at all for the .PHONY-only arm), OBJ says whether the
# build leaves an object, and PHONY, when given, is a .PHONY written first in
# place of the one-line .PHONY written last.
# A Makefile line is an answer line to answer_scan wherever else it reads one,
# a stock line included: these fixtures spell their fclean's prerequisite
# through %s, and their .PHONY names in another order, so that no line of this
# file is a whole Makefile line. The Makefiles written are the same.
mkempty() {  # mkempty DIR CLEAN OBJ|NOOBJ [PHONY]
	mkdir -p "$WORK/$1"
	printf 'selftest\n' > "$WORK/$1/sel.txt"
	{
		if [ -n "${4:-}" ]; then printf '%b' "$4"; fi
		printf 'all: libselftest.a\n'
		if [ "$3" = OBJ ]; then
			printf 'libselftest.a: sel.o\n\tcp sel.o libselftest.a\n'
			printf 'sel.o: sel.txt\n\tcp sel.txt sel.o\n'
		else
			printf 'libselftest.a: sel.txt\n\tcp sel.txt libselftest.a\n'
		fi
		printf '%b' "$2"
		printf 'fclean: %s\n\trm -f sel.o libselftest.a\n' clean
		if [ -z "${4:-}" ]; then printf '.PHONY: fclean clean all\n'; fi
	} > "$WORK/$1/Makefile"
}
mkempty mkcl_empty 'clean:\n' NOOBJ
mkempty mkcl_phony '' NOOBJ
mkempty mkcl_emptyobj 'clean:\n' OBJ
mkempty mkcl_emptycont 'clean:\n' NOOBJ '.PHONY: all \\\n\tclean fclean\n'
want_green "make_test: an empty clean, nothing to clean, passes" -- \
	mkr mkcl_empty all,clean,fclean
want_red   "make_test: a clean only in .PHONY still fails" -- \
	mkr mkcl_phony all,clean,fclean
want_out   "make_test: ...as a missing rule" 'your Makefile has no clean rule' -- \
	mkr mkcl_phony all,clean,fclean
want_red   "make_test: an empty clean that leaves objects fails" -- \
	mkr mkcl_emptyobj all,clean,fclean
want_out   "make_test: ...on what it left, not as missing" \
	'left object files behind' -- mkr mkcl_emptyobj all,clean,fclean
want_green "make_test: ...and with .PHONY first, continued" -- \
	mkr mkcl_emptycont all,clean,fclean
# A target-specific variable is no rule: make's database prints `clean: VAR
# = x` above clean's own line, and it read as a clean with a prerequisite,
# so a Makefile whose only clean was that variable passed. `!=` adds a
# second such line (.SHELLSTATUS). The pair: the variable over an empty
# clean the Makefile writes is judged by what that clean does.
mkempty mkcl_tsv 'clean: SEL_V = x\n' NOOBJ
mkempty mkcl_tsvsh 'clean: SEL_V != echo x\n' NOOBJ
mkempty mkcl_tsvempty 'clean: SEL_V = x\nclean:\n' NOOBJ
want_red   "make_test: a clean that is only a target-specific variable fails" -- \
	mkr mkcl_tsv all,clean,fclean
want_out   "make_test: ...as a missing rule" 'your Makefile has no clean rule' -- \
	mkr mkcl_tsv all,clean,fclean
want_out   "make_test: ...and with != too" 'your Makefile has no clean rule' -- \
	mkr mkcl_tsvsh all,clean,fclean
want_green "make_test: ...while that variable over an empty clean passes" -- \
	mkr mkcl_tsvempty all,clean,fclean
# Telling the two apart runs make again, and the step goes on with the
# status `make clean` gave, never the database run's (make -npq .DEFAULT
# exits 2). It used to come back as 2: a WARNING here, and a FAIL in the
# robust twin, over a clean that exited 0.
want_broken_none "make_test: ...and says no status of its own" \
	'exited with status' -- mkr mkcl_empty all,clean,fclean
# A .PHONY the copy cannot rename, in an included makefile, keeps the old
# verdict: a clean named only there is still missing.
mkdir -p "$WORK/mkcl_incphony"
printf 'selftest\n' > "$WORK/mkcl_incphony/sel.txt"
printf '.PHONY: fclean clean all\n' > "$WORK/mkcl_incphony/phony.mk"
{
	printf 'include phony.mk\n'
	printf 'all: libselftest.a\n'
	printf 'libselftest.a: sel.txt\n\tcp sel.txt libselftest.a\n'
	printf 'fclean: %s\n\trm -f libselftest.a\n' clean
} > "$WORK/mkcl_incphony/Makefile"
want_out   "make_test: a clean only in an included .PHONY fails" \
	'your Makefile has no clean rule' -- mkr mkcl_incphony all,clean,fclean
# A recipe line can start with `clean:` too: a continued line is printed
# from the first column of make's database. Read as a target, it gave a
# clean named only in .PHONY a rule -- from an extra target's recipe
# (mkcl_stray_rule, whose block is read first) or from the artifact's
# (mkcl_stray_copy, which only the .PHONY-renamed copy got wrong).
mkstray() {  # mkstray DIR EXTRA-RULE ARTIFACT-RECIPE-END
	mkdir -p "$WORK/$1"
	printf 'selftest\n' > "$WORK/$1/sel.txt"
	{
		printf 'all: libselftest.a\n'
		printf 'libselftest.a: sel.txt\n\tcp sel.txt libselftest.a%b\n' "$3"
		printf '%b' "$2"
		printf 'fclean: %s\n\trm -f libselftest.a\n' clean
		printf '.PHONY: stage fclean clean all\n'
	} > "$WORK/$1/Makefile"
}
mkstray mkcl_stray_rule 'stage:\n\techo "rules:" \\\nclean: objects\n' ''
mkstray mkcl_stray_copy '' '; echo "rules:" \\\nclean: objects'
want_out   "make_test: a recipe line is no clean rule" \
	'your Makefile has no clean rule' -- mkr mkcl_stray_rule all,clean,fclean
want_out   "make_test: ...in the artifact's recipe either" \
	'your Makefile has no clean rule' -- mkr mkcl_stray_copy all,clean,fclean
# The database the rule steps read is the one `make RULE` reads: under
# RULE as the goal make was given, and the last one make printed. A
# Makefile that refuses a goal it does not know printed none for the goal
# the reading named, and a re named only in .PHONY passed as a rule; one
# that remakes an include as it starts printed one before it read the
# include again, and a clean only that first reading had passed as one.
mkdir -p "$WORK/mkre_goals" "$WORK/mkcl_restart"
printf 'selftest\n' > "$WORK/mkre_goals/sel.txt"
printf 'selftest\n' > "$WORK/mkcl_restart/sel.txt"
{
	printf 'SEL_GOALS := all clean fclean re\n'
	printf 'ifneq ($(filter-out $(SEL_GOALS),$(MAKECMDGOALS)),)\n'
	printf '$(error sel: no goal $(MAKECMDGOALS))\nendif\n'
	printf 'all: libselftest.a\n'
	printf 'libselftest.a: sel.o\n\tcp sel.o libselftest.a\n'
	printf 'sel.o: sel.txt\n\tcp sel.txt sel.o\n'
	printf 'clean:\n\trm -f sel.o\n'
	printf 'fclean:\n\trm -f sel.o libselftest.a\n'
	printf '.PHONY: re fclean clean all\n'
} > "$WORK/mkre_goals/Makefile"
# The include is removed as the first reading starts, so make remakes it
# and reads again every time: whether a file make rewrote counts as changed
# is up to the clock's grain, and a rule that remade it each time restarted
# make only most of the time.
{
	printf '.PHONY: fclean clean all\n'
	printf 'all: libselftest.a\n'
	printf 'libselftest.a: sel.txt\n\tcp sel.txt libselftest.a\n'
	printf 'ifeq ($(MAKE_RESTARTS),)\n$(shell rm -f sel_gen.mk)\nclean:\n\t@echo sel cleaning\nendif\n'
	printf -- '-include sel_gen.mk\n'
	printf 'sel_gen.mk:\n\t@echo "SEL_X = 1" > sel_gen.mk\n'
	printf 'fclean: %s\n\trm -f libselftest.a\n' clean
} > "$WORK/mkcl_restart/Makefile"
want_out   "make_test: a re only in .PHONY, under a Makefile that checks its goals" \
	'your Makefile has no re rule' -- mkr mkre_goals
want_out   "make_test: a clean only the first reading of a restarted make has" \
	'your Makefile has no clean rule' -- mkr mkcl_restart all,clean,fclean

# An all that builds the artifact and then exits non-zero did its job: at
# basic that is the run contract's WARNING, and it used to be "did not build"
# over the file it had built. Its re builds the artifact directly, so only
# the bare make and all carry the failing command.
mkdir -p "$WORK/mkallerr"
printf 'selftest\n' > "$WORK/mkallerr/sel.txt"
{
	printf 'all: libselftest.a\n\tfalse\n'
	printf 'libselftest.a: sel.o\n\tcp sel.o libselftest.a\n'
	printf 'sel.o: sel.txt\n\tcp sel.txt sel.o\n'
	printf 'clean:\n\trm -f sel.o\n'
	printf 'fclean:\n\trm -f sel.o libselftest.a\n'
	printf 're:\n\trm -f sel.o libselftest.a\n\t$(MAKE) libselftest.a\n'
} > "$WORK/mkallerr/Makefile"
want_green "make_test: an all that builds, then exits non-zero, passes" -- \
	mkr mkallerr
want_out   "make_test: ...and says it built it and exited non-zero" \
	"'make all' built 'libselftest.a', and exited with status 2" -- mkr mkallerr
# The question under a non-zero exit names a cause only where its premise
# held: a cleaning rule meeting a tree with nothing left to clean. An all that
# fails on a built tree removed nothing, so it is asked for the command that
# stopped it and never about a file that is already gone. The footer that
# sends a student to the robust twin appears only over a warning.
want_out   "make_test: ...and asks which command stopped it" \
	'Which command stopped it? Its own error is in what make printed.' -- \
	mkr mkallerr
want_broken_none "make_test: ...not about a file already gone" 'already gone' -- \
	mkr mkallerr
want_out   "make_test: a clean on nothing to clean is asked that" 'already gone' -- \
	mkr mkre_cleanerr
want_broken_none "make_test: a run with no warning names no twin" 'selftest_build_exit' -- \
	mkr mkre_ok
want_out   "make_test: ...and one with a warning, its _exit twin" '(selftest_build_exit)' -- \
	mkr mkre_cleanerr

# A rule whose effect is wrong fails at basic whatever it exits with, and
# each of these rules also stops on a failing command after doing it wrong
# -- the shape --exit-only below must not judge. mkfc_keep's fclean leaves
# the artifact; mkcl_left's clean leaves the object; mkfc_src's fclean also
# removes the source, so nothing can rebuild; mkre_fail's re removes both and
# stops before building again.
mkrules mkfc_keep 'rm -f sel.o' "$_mkre" 'rm -f sel.o\n\trm libselftest.b'
mkrules mkcl_left 'rm sel.x' "$_mkre"
mkrules mkfc_src 'rm -f sel.o' "$_mkre" 'rm -f sel.o libselftest.a sel.txt'
mkrules mkre_fail 'rm -f sel.o' 're:\n\trm -f sel.o libselftest.a\n\tfalse\n'
want_out   "make_test: an fclean that keeps the artifact fails" \
	"FAIL — 'make fclean' did not remove 'libselftest.a'" -- mkr mkfc_keep
want_out   "make_test: a clean that keeps the object fails" \
	"FAIL — 'make clean' left object files behind" -- mkr mkcl_left
want_out   "make_test: a tree its fclean broke fails the rebuild" \
	"FAIL — 'make' did not rebuild 'libselftest.a' after 'make fclean'" -- mkr mkfc_src
want_out   "make_test: an re that builds nothing fails" \
	"FAIL — 'make re' did not rebuild 'libselftest.a'" -- mkr mkre_fail

# --exit-only, the robust twin (exNN_build_exit): the same runs, judged only
# by how each ended. What a rule DID is exNN_build's, so a rule that did not
# do its job is NOT JUDGED rather than failed, and a Makefile that built
# nothing is a SKIP that NO_SKIP=1 turns red.
mkrx() {  # mkrx DIR [RULES]
	mt --rules "${2-all,clean,fclean,re}" --build-target selftest_build --exit-only \
		--anchor "$WORK/$1/Makefile" --artifact libselftest.a
}
want_green "make_test --exit-only: rules that all exit 0 pass" -- mkrx mkre_ok
# ...and said so from what it judged: a SKIP exits 0 too.
want_out   "make_test --exit-only: ...having judged each run" \
	'run(s) judged here exited 0' -- mkrx mkre_ok
want_red   "make_test --exit-only: clean erroring on a clean tree fails" -- \
	mkrx mkre_cleanerr
want_out   "make_test --exit-only: ...and names the run" \
	"FAIL — 'make clean' on a tree with nothing to clean exited" -- mkrx mkre_cleanerr
want_red   "make_test --exit-only: an all that exits non-zero fails" -- mkrx mkallerr
# An empty clean that exited 0 is judged as exiting 0 (mkcl_empty, above).
want_green "make_test --exit-only: an empty clean exits 0" -- \
	mkrx mkcl_empty all,clean,fclean
want_green "make_test --exit-only: what a rule did is not its business" -- \
	mkrx mkre_clean
want_out   "make_test --exit-only: ...it is not judged" \
	"NOT JUDGED — 'make re': it left the old 'libselftest.a' in place" -- mkrx mkre_clean
# A rule that did nothing ("Nothing to be done") has make's database read
# (rule_is_empty), and make passes -p on to a sub-make that remakes an
# include: one whose output is the include left that database in the tree,
# with the -p of the reading in its MAKEFLAGS. Every later make read it and
# printed a database of its own, so the re that fails below showed that in
# place of its own error. The tree is put back after each reading, as
# goal_state puts it back. Here fclean is clean, which does nothing, so its
# reading comes before every later step; the exit twin goes on past it. The
# include is removed once each make has read it, so make remakes it and
# reads again exactly once, whatever the clock's grain (mkcl_restart).
mkdir -p "$WORK/mkleak"
printf 'selftest\n' > "$WORK/mkleak/sel.txt"
printf 'sel_x:\n\t@:\n' > "$WORK/mkleak/sel_gen.src"
{
	printf 'all: libselftest.a\n'
	printf 'libselftest.a: sel.txt\n\tcp sel.txt libselftest.a\n'
	printf 'clean:\n'
	printf 'fclean: %s\n' clean
	printf 're:\n\trm -f libselftest.a\n\t$(MAKE) all\n\techo sel_re_stops; exit 3\n'
	printf -- '-include sel_gen.mk\n'
	printf 'ifeq ($(MAKE_RESTARTS),)\n$(shell rm -f sel_gen.mk)\nendif\n'
	printf 'sel_gen.mk:\n\t@$(MAKE) -s -f sel_gen.src > sel_gen.mk\n'
	printf '.PHONY: re fclean clean all\n'
} > "$WORK/mkleak/Makefile"
want_out   "make_test --exit-only: a rule run after a reading shows its own words" \
	"re] Error 3" -- mkrx mkleak
want_broken_none "make_test --exit-only: ...and no database a reading left" \
	'# Make data base' -- mkrx mkleak
want_green "make_test --exit-only: nothing built is a SKIP" -- \
	env -u NO_SKIP "$SH" "$TOOLS/make_test.sh" --nm "$NM" --rules "" --exit-only \
		--build-target selftest_build --anchor "$WORK/mkecho/Makefile" --artifact libselftest.a
want_red   "make_test --exit-only: ...that NO_SKIP=1 turns red" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/make_test.sh" --nm "$NM" --rules "" --exit-only \
		--build-target selftest_build --anchor "$WORK/mkecho/Makefile" --artifact libselftest.a
# ...naming the target whose finding it is, as the SKIP does: forced open, a
# stand-down read as this target's own red (c09b M6, 2026-10-03).
want_out   "make_test --exit-only: ...and names the build target" \
	'could judge; selftest_build says why' -- \
	env NO_SKIP=1 "$SH" "$TOOLS/make_test.sh" --nm "$NM" --rules "" --exit-only \
		--build-target selftest_build --anchor "$WORK/mkecho/Makefile" --artifact libselftest.a
# A run that did not do its job is NOT JUDGED here either, rule by rule: a
# rule the Makefile lacks, or an all that built nothing, is exNN_build's
# finding. It used to be judged as a non-zero exit, under the run contract's
# words -- "'make all' built 'libselftest.a', and exited with status 2" over
# make's own "No rule to make target 'all'". mknoall has no all; mkbin has no
# libselftest.a rule; mkre_phony names re in .PHONY and nowhere else; mkallnone's
# all runs a command that fails and builds nothing.
mkdir -p "$WORK/mkallnone"
printf 'selftest\n' > "$WORK/mkallnone/sel.txt"
{
	printf 'libselftest.a: sel.txt\n\tcp sel.txt libselftest.a\n'
	printf 'all:\n\tfalse\n'
} > "$WORK/mkallnone/Makefile"
want_green "make_test --exit-only: a missing all is not judged" -- mkrx mknoall all
want_broken_none "make_test --exit-only: ...nor said to have built" \
	"built 'libselftest.a'" -- mkrx mknoall all
want_out   "make_test --exit-only: ...and is named as not judged" \
	"NOT JUDGED — 'make all': your Makefile has no all rule" -- mkrx mknoall all
want_out   "make_test --exit-only: the verdict counts what it left out" \
	'1 run(s) were not judged' -- mkrx mknoall all
# The twins' names come from c_make (--build-target), not from the exercise
# directory: a turn-in at deliverable/ itself has no exNN to guess from, and
# the messages lost the pointer from one twin to the other.
want_out   "make_test: --build-target names the twin in the messages" \
	'selftest_build says what went wrong' -- mkrx mknoall all
want_broken "make_test: --build-target is required" '--build-target is required' -- \
	"$SH" "$TOOLS/make_test.sh" --nm "$NM" --rules "" --anchor "$WORK/mkecho/Makefile" --artifact libselftest.a
want_broken "make_test: ...and names a _build target" 'which ends in _build' -- \
	"$SH" "$TOOLS/make_test.sh" --nm "$NM" --rules "" --build-target ex00 \
		--anchor "$WORK/mkecho/Makefile" --artifact libselftest.a
want_green "make_test --exit-only: a missing artifact rule, the same" -- \
	mkrx mkbin libselftest.a
want_broken_none "make_test --exit-only: ...nor said to have built" \
	"built 'libselftest.a'" -- mkrx mkbin libselftest.a
want_green "make_test --exit-only: an all that built nothing is not judged" -- \
	mkrx mkallnone all
want_broken_none "make_test --exit-only: ...nor said to have built" \
	"built 'libselftest.a'" -- mkrx mkallnone all
want_out   "make_test --exit-only: a re only in .PHONY is not judged" \
	"NOT JUDGED — 'make re'" -- mkrx mkre_phony
# The effect checks of fclean, clean and re, and the rebuild before each: the
# fixtures above whose rule did its job wrong and then stopped on a failing
# command. Each used to be judged on that status -- and a cleaning rule's
# second run, "on a tree with nothing to clean", asked what rm does "when the
# file it names is already gone", over a tree that still held it. Now each is
# NOT JUDGED, the test passes, and that second run is not made.
want_green "make_test --exit-only: an fclean that keeps the artifact passes" -- \
	mkrx mkfc_keep
want_out   "make_test --exit-only: ...as not judged" \
	"NOT JUDGED — 'make fclean': it did not remove 'libselftest.a' (it exited with status 2)" -- \
	mkrx mkfc_keep
want_broken_none "make_test --exit-only: ...with no tree called empty" \
	'nothing to clean' -- mkrx mkfc_keep
want_broken_none "make_test --exit-only: ...nor a file called gone" \
	'already gone' -- mkrx mkfc_keep
want_green "make_test --exit-only: a clean that keeps the object passes" -- \
	mkrx mkcl_left
want_out   "make_test --exit-only: ...as not judged" \
	"NOT JUDGED — 'make clean': it left object files behind" -- mkrx mkcl_left
want_broken_none "make_test --exit-only: ...with no tree called empty" \
	'nothing to clean' -- mkrx mkcl_left
want_green "make_test --exit-only: a rebuild that makes nothing passes" -- \
	mkrx mkfc_src
want_out   "make_test --exit-only: ...as not judged, the steps after unrun" \
	"every rule check after it did not run" -- mkrx mkfc_src
want_broken_none "make_test --exit-only: ...never as exNN_build's FAIL" \
	"FAIL — 'make' did not rebuild" -- mkrx mkfc_src
want_green "make_test --exit-only: an re that builds nothing passes" -- \
	mkrx mkre_fail
want_out   "make_test --exit-only: ...as not judged" \
	"NOT JUDGED — 'make re': it did not rebuild 'libselftest.a'" -- mkrx mkre_fail

# The artifact's own rule, where a subject lists it (C 09 ex01's "and of
# course libft.a", rush-02's $NAME), checked by name. mkbin builds its
# artifact from all and has no rule of that name. A rule name no step checks
# is refused: it would be listed as mandated and checked by nobody.
want_green "make_test: the artifact's own rule, where it exists" -- \
	mkr mkre_ok all,clean,fclean,re,libselftest.a
want_red   "make_test: ...fails where only all builds it" -- mkr mkbin libselftest.a
want_out   "make_test: ...and names the rule" 'your Makefile has no libselftest.a rule' -- \
	mkr mkbin libselftest.a
want_broken "make_test: a rule no step checks is refused" 'has no check for' -- \
	mt --rules all,bogus --anchor "$WORK/mkbin/Makefile" --artifact libselftest.a

# The near-miss name. rush-02's Makefile really did build `rush02`, and the only
# layer in the whole repo that can notice is this one -- everything else
# compiles the sources itself and never asks what the Makefile called its
# output. Two arms, because the value here is entirely in the DIAGNOSIS: red
# alone was already the behaviour, and red plus "you built ./libself-test.a"
# is what makes it a two-second fix instead of a hunt. Anchored in its own
# directory for the reason given above.
mkdir -p "$WORK/mknear"
printf '#!/bin/sh\n: > libself-test.a\n' > "$WORK/mknear/build_near.sh"
want_red   "make_test: a name differing only in punctuation is still wrong" -- \
	mks mknear/build_near.sh
want_out   "make_test: it names the near miss instead of dumping ls" \
	'libself-test.a' -- mks mknear/build_near.sh

# --symbols, driven the way Bazel drives it: --nm and --nm-lib as the relative
# runfiles paths `$(rootpath)` hands over. Every arm above builds an EMPTY
# artifact and passes no --symbols, so none of them reached the nm call -- which
# runs after the runner's `cd` into its scratch copy, where a relative path no
# longer names anything. Every c_make that lists symbols (C 09, C 10, C 11,
# Rush 02, Reloaded ex24 and ex27) was red on a Makefile that built correctly,
# and nothing noticed because every one of those deliverables was still a stub.
# The object is compiled here and copied by the Makefile, so the fixture needs no
# compiler inside the runner and is shaped like no exercise's Makefile.
mkdir -p "$WORK/mksym" "$WORK/mksym_src"
printf 'int\tselftest_sym(void)\n{\n\treturn (42);\n}\n' > "$WORK/mksym_src/sym.c"
toy_cc "$WORK/mksym/sym.o" -c "$WORK/mksym_src/sym.c"
printf 'all:\n\tcp sym.o libselftest.a\n' > "$WORK/mksym/Makefile"
want_green "make_test: --symbols works with a relative --nm/--nm-lib" -- \
	mt --nm-lib "$NM_LIB" --rules "" \
		--anchor "$WORK/mksym/Makefile" --artifact libselftest.a \
		--symbols selftest_sym
want_red   "make_test: and a symbol the artifact lacks is still missing" -- \
	mt --nm-lib "$NM_LIB" --rules "" \
		--anchor "$WORK/mksym/Makefile" --artifact libselftest.a \
		--symbols selftest_sym,selftest_absent
# --nm-lib may be given more than once, its library in any of its folders, as
# in symbols_test.sh and forbidden_symbols.sh: make_test.sh tested the loaded
# library against every folder joined into one path, and refused this as
# "not under --nm-lib" (V277). The folder that holds it comes second.
want_green "make_test: --symbols finds nm's library in the second --nm-lib" -- \
	mt --nm-lib "$WORK/mksym_src/none" --nm-lib "$NM_LIB" --rules "" \
		--anchor "$WORK/mksym/Makefile" --artifact libselftest.a \
		--symbols selftest_sym
# ...and refuses as the other two runners that read symbols do (runner_lib.sh,
# rl_binutils_pin, which all three call): a --nm-lib folder that is not
# there, and an nm that loads a libbfd from outside --nm-lib -- a copy of the
# fetched one, reached through LD_LIBRARY_PATH from outside, as the symbols
# arms have one: a library from somewhere else on every machine.
mkdir -p "$WORK/mknm_nolib" "$WORK/mknm_elsewhere"
cp -L "${NM_LIB%/*}"/lib*.so* "$WORK/mknm_elsewhere/"
want_broken "make_test: a --nm-lib folder that is not there is refused" \
	"--nm-lib directory '$WORK/mksym_src/gone' does not exist" -- \
	mt --nm-lib "$WORK/mksym_src/gone/libbfd.so" --rules "" \
		--anchor "$WORK/mksym/Makefile" --artifact libselftest.a \
		--symbols selftest_sym
want_broken "make_test: nm loading a libbfd from outside --nm-lib is refused" \
	"the pinned nm loaded '$WORK/mknm_elsewhere/" -- \
	env LD_LIBRARY_PATH="$WORK/mknm_elsewhere" \
	"$SH" "$TOOLS/make_test.sh" --nm "$NM" --build-target selftest_build \
		--nm-lib "$WORK/mknm_nolib/none" --rules "" \
		--anchor "$WORK/mksym/Makefile" --artifact libselftest.a --symbols selftest_sym
# nm's folder is nm's alone: proved under its path and run under it, as in
# the other two runners, and never exported to make and every recipe of the
# Makefile, which ran with the pinned libbfd's folder on their loader's path.
# The recipe writes the path it was run with where the arm can read it.
mkdir -p "$WORK/mkldp"
cp "$WORK/mksym/sym.o" "$WORK/mkldp/sym.o"
printf 'all:
	echo "ldp=$$LD_LIBRARY_PATH" > %s/ldp.txt
	cp sym.o libselftest.a
' \
	"$WORK/mkldp" > "$WORK/mkldp/Makefile"
case "$NM_LIB" in /*) _mkldp_d=${NM_LIB%/*} ;; *) _mkldp_d=$PWD/${NM_LIB%/*} ;; esac
mkldp_run() {  # the path the recipe ran with, after a run that read the symbols
	rm -f "$WORK/mkldp/ldp.txt"
	"$SH" "$TOOLS/make_test.sh" --nm "$NM" --build-target selftest_build \
		--nm-lib "$NM_LIB" --rules "" --anchor "$WORK/mkldp/Makefile" \
		--artifact libselftest.a --symbols selftest_sym > /dev/null 2>&1
	_mkldp_rc=$?
	[ "$_mkldp_rc" -eq 0 ] || { echo "make_test.sh exited $_mkldp_rc"; return 2; }
	[ -f "$WORK/mkldp/ldp.txt" ] || { echo "no recipe wrote its path"; return 2; }
	cat "$WORK/mkldp/ldp.txt"
}
want_broken_none "make_test: a recipe runs without nm's --nm-lib folder on its loader's path" \
	"$_mkldp_d" -- mkldp_run

# AN ARCHIVE WITH NO MEMBER: what `ar rcs lib.a` writes when the list of
# objects after it came out empty, the magic line and nothing else. It used to
# be reported as the first symbol missing, which leaves the student to infer
# that nothing was compiled. The premise is checked both ways: an archive
# holding one object that lacks the symbol is still "missing" and never
# "empty". Both archives are written here, by the format (an 8-byte magic
# line, then each member behind a 60-byte header), so no `ar` is needed.
mkdir -p "$WORK/mkempty" "$WORK/mkone"
printf '!<arch>\n' > "$WORK/mkempty/none.ar"
printf 'all:\n\tcp none.ar libselftest.a\n' > "$WORK/mkempty/Makefile"
_mk_sz=$(wc -c < "$WORK/mksym/sym.o" | tr -d ' ')
{
	printf '!<arch>\n'
	printf '%-16s%-12s%-6s%-6s%-8s%-10s`\n' 'sym.o/' 0 0 0 644 "$_mk_sz"
	cat "$WORK/mksym/sym.o"
	[ $((_mk_sz % 2)) -eq 0 ] || printf '\n'
} > "$WORK/mkone/one.ar"
printf 'all:\n\tcp one.ar libselftest.a\n' > "$WORK/mkone/Makefile"
want_out   "make_test: an archive with no member is said to be empty" \
	"built 'libselftest.a', and it is an empty archive" -- \
	mt --nm-lib "$NM_LIB" --rules "" \
		--anchor "$WORK/mkempty/Makefile" --artifact libselftest.a \
		--symbols selftest_sym
want_red   "make_test: ...and fails" -- \
	mt --nm-lib "$NM_LIB" --rules "" \
		--anchor "$WORK/mkempty/Makefile" --artifact libselftest.a \
		--symbols selftest_sym
want_green "make_test: an archive with a member holding the symbol passes" -- \
	mt --nm-lib "$NM_LIB" --rules "" \
		--anchor "$WORK/mkone/Makefile" --artifact libselftest.a \
		--symbols selftest_sym
want_out   "make_test: ...and one lacking it names the missing symbol" \
	"symbol 'selftest_absent' missing" -- \
	mt --nm-lib "$NM_LIB" --rules "" \
		--anchor "$WORK/mkone/Makefile" --artifact libselftest.a \
		--symbols selftest_absent
want_broken_none "make_test: ...and never calls it empty" 'empty archive' -- \
	mt --nm-lib "$NM_LIB" --rules "" \
		--anchor "$WORK/mkone/Makefile" --artifact libselftest.a \
		--symbols selftest_absent

# --clues: an exercise that is a Makefile alone (Reloaded ex24, C 09 ex01) has
# no other layer to print its hints, and make_test.sh took none, so its
# clues.tsv was shown to nobody. Under a FAIL the hints come last, without
# the maintainer's '#' line; a build that passes shows none. An invented hint.
printf '# a maintainer note, never shown\nWhich toy files does your rule list?\n' \
	> "$WORK/mkempty/clues.tsv"
want_out   "make_test: a FAIL ends with the exercise's hints (--clues)" \
	'   * Which toy files does your rule list?' -- \
	mt --nm-lib "$NM_LIB" --rules "" --clues "$WORK/mkempty/clues.tsv" \
		--anchor "$WORK/mkempty/Makefile" --artifact libselftest.a \
		--symbols selftest_sym
want_broken_none "make_test: ...never the maintainer's note" 'a maintainer note' -- \
	mt --nm-lib "$NM_LIB" --rules "" --clues "$WORK/mkempty/clues.tsv" \
		--anchor "$WORK/mkempty/Makefile" --artifact libselftest.a \
		--symbols selftest_sym
want_broken_none "make_test: ...and a build that passes shows none" 'HINTS' -- \
	mt --nm-lib "$NM_LIB" --rules "" --clues "$WORK/mkempty/clues.tsv" \
		--anchor "$WORK/mkone/Makefile" --artifact libselftest.a \
		--symbols selftest_sym
want_broken "make_test: a --clues file that is not there refuses" \
	"no clues file at" -- \
	mt --nm-lib "$NM_LIB" --rules "" --clues "$WORK/mkempty/nowhere.tsv" \
		--anchor "$WORK/mkone/Makefile" --artifact libselftest.a

# --overlay: the grader's files staged beside a turn-in that is a Makefile alone
# (Piscine Reloaded ex24). The fixture's Makefile succeeds only if the staged
# file is there, so the red arm is the proof the green one needs. A made-up
# token and a made-up library -- nothing shaped like an exercise's Makefile.
mkdir -p "$WORK/mkov" "$WORK/mkov_src"
printf 'all:\n\tcp grader/token.txt libselftest.a\n' > "$WORK/mkov/Makefile"
printf 'selftest token\n' > "$WORK/mkov_src/token.txt"
want_red   "make_test: without the overlay the grader's file is absent" -- \
	mt --rules "" \
		--anchor "$WORK/mkov/Makefile" --artifact libselftest.a
want_green "make_test: --overlay stages the grader's file before make" -- \
	mt --rules "" \
		--anchor "$WORK/mkov/Makefile" --artifact libselftest.a \
		--overlay "$WORK/mkov_src/token.txt" grader/token.txt
want_broken "make_test: an overlay may not land outside the exercise" \
	"must be a relative path" -- \
	mt --rules "" \
		--anchor "$WORK/mkov/Makefile" --artifact libselftest.a \
		--overlay "$WORK/mkov_src/token.txt" ../escape.txt

# A grader-supplied file the student ALSO put in the turn-in is a FAIL, not a
# quiet overwrite: the grader fetches the Makefile alone, so the copy would be
# pushed as an extra file -- one the files layer cannot see in a subdirectory.
mkdir -p "$WORK/mkovc/grader"
cp "$WORK/mkov/Makefile" "$WORK/mkovc/Makefile"
printf 'selftest token\n' > "$WORK/mkovc/grader/token.txt"
want_red   "make_test: a grader file inside the turn-in fails" -- \
	mt --rules "" \
		--anchor "$WORK/mkovc/Makefile" --artifact libselftest.a \
		--overlay "$WORK/mkov_src/token.txt" grader/token.txt
want_out   "make_test: ...and says where the grader's files go" \
	"holds files where the grader's files go" -- \
	mt --rules "" \
		--anchor "$WORK/mkovc/Makefile" --artifact libselftest.a \
		--overlay "$WORK/mkov_src/token.txt" grader/token.txt
# ...and so is ANY file in a directory the grader's files go in, not only one
# at a DEST: C 09 ex01's srcs/ and includes/ are the grader's whole. A file of
# the student's own there used to be staged beside the grader's, unreported.
mkdir -p "$WORK/mkovd/grader"
cp "$WORK/mkov/Makefile" "$WORK/mkovd/Makefile"
printf 'selftest own file\n' > "$WORK/mkovd/grader/own.txt"
want_red   "make_test: a file of one's own in the grader's dir fails" -- \
	mt --rules "" \
		--anchor "$WORK/mkovd/Makefile" --artifact libselftest.a \
		--overlay "$WORK/mkov_src/token.txt" grader/token.txt
want_out   "make_test: ...and names it" 'grader/own.txt' -- \
	mt --rules "" \
		--anchor "$WORK/mkovd/Makefile" --artifact libselftest.a \
		--overlay "$WORK/mkov_src/token.txt" grader/token.txt
# A DEST written ./grader/token.txt is the same file. It made "." the
# grader's top directory, and every file of the turn-in -- the Makefile
# first -- was reported as the grader's. Any other . in a DEST is refused.
want_green "make_test: a ./ DEST is the same file" -- \
	mt --rules "" \
		--anchor "$WORK/mkov/Makefile" --artifact libselftest.a \
		--overlay "$WORK/mkov_src/token.txt" ./grader/token.txt
# The listing is compared WHOLE: the runner that made "." the grader's top
# directory listed './Makefile' and './grader/own.txt', so a needle for one
# name matched the ./ spelling of the other, and an absence of '    Makefile'
# held over a listing that had it. ov_lists EXPECTED -- RUNNER...: 0 when the
# runner failed (1) listing exactly EXPECTED, one indented name per line.
ov_lists() {
	_want=$1; shift 2
	_out=$("$@" 2>&1)
	_rc=$?
	[ "$_rc" -lt 2 ] || return "$_rc"
	[ "$_rc" -eq 1 ] || return 1
	[ "$(printf '%s\n' "$_out" | sed -n 's/^    \([^ ]\)/\1/p')" = "$_want" ]
}
want_green "make_test: ...lists grader/own.txt, and nothing else" -- \
	ov_lists 'grader/own.txt' -- \
	mt --rules "" \
		--anchor "$WORK/mkovd/Makefile" --artifact libselftest.a \
		--overlay "$WORK/mkov_src/token.txt" ./grader/token.txt
want_broken "make_test: a . inside a DEST is refused" 'no . or .. in it' -- \
	mt --rules "" \
		--anchor "$WORK/mkov/Makefile" --artifact libselftest.a \
		--overlay "$WORK/mkov_src/token.txt" grader/./token.txt

# --relink-source norm: the no-relink rule quoted from the Norm, for a subject
# that never states it (Piscine Reloaded). mkbin rewrites its artifact on every
# run, so it relinks. The Norm's sentence comes from the call site's quotes,
# as a subject's does: written into the runner, it was one fact travelling
# two ways, and a toy one stands in for it here.
printf 'relink\tToy Norm, III.9: "Never relink."\n' > "$MKQ/norm.tsv"
want_red   "make_test: --relink fails a Makefile that relinks" -- \
	mt --rules "" --relink --quotes "$MKQ/norm.tsv" \
		--relink-source norm --anchor "$WORK/mkbin/Makefile" --artifact libselftest.a
want_out   "make_test: --relink-source norm cites the Norm" 'the Norm' -- \
	mt --rules "" --relink --quotes "$MKQ/norm.tsv" \
		--relink-source norm --anchor "$WORK/mkbin/Makefile" --artifact libselftest.a
want_out   "make_test: ...in the call site's words" 'Toy Norm, III.9: "Never relink."' -- \
	mt --rules "" --relink --quotes "$MKQ/norm.tsv" \
		--relink-source norm --anchor "$WORK/mkbin/Makefile" --artifact libselftest.a
want_broken "make_test: --relink-source norm with no relink sentence is refused" "'relink' sentence" -- \
	mt --rules "" --relink \
		--relink-source norm --anchor "$WORK/mkbin/Makefile" --artifact libselftest.a

# THE TIME BUDGET (tools/runner_lib.sh). A Makefile is the student's code, and
# make runs it: a rule that never ends -- one that calls itself through
# $(MAKE), a $(shell) waiting for input -- ran until Bazel killed the test with
# nothing in its log. Every run of make, or of the creator script, is now
# bounded by what is left of the test's own limit, and says which run it was.
mkdir -p "$WORK/mkloop" "$WORK/mkloops"
printf 'all:\n\twhile :; do :; done\n' > "$WORK/mkloop/Makefile"
later_red_out "make_test: a Makefile that never ends is stopped, and said" \
	"an infinite loop, or too slow on 'make'" -- \
	$SHORT "$SH" "$TOOLS/make_test.sh" --nm "$NM" --rules "" \
		--build-target selftest_build --anchor "$WORK/mkloop/Makefile" --artifact libselftest.a
# The default goal is asked of make with -pnq, under the same limit; a run of
# it that did not return used to end only the $( ) it ran in, and the report
# went on to name a default goal of ''. This Makefile waits only under -q.
mkdir -p "$WORK/mkq"
printf 'ifneq (,$(findstring q,$(MAKEFLAGS)))\nX := $(shell sleep 30)\nendif\nall:\n\t@echo hi\n' \
	> "$WORK/mkq/Makefile"
want_out   "make_test: a default goal make never names is stopped, and said" \
	"too slow on 'make -pnq'" -- \
	env MAKE_TIMEOUT=1 "$SH" "$TOOLS/make_test.sh" --nm "$NM" --rules "" \
		--build-target selftest_build --anchor "$WORK/mkq/Makefile" --artifact libselftest.a
want_broken_none "make_test: ...and the report ends there" \
	"the default goal is ''" -- \
	env MAKE_TIMEOUT=1 "$SH" "$TOOLS/make_test.sh" --nm "$NM" --rules "" \
		--build-target selftest_build --anchor "$WORK/mkq/Makefile" --artifact libselftest.a
printf '#!/bin/sh\nwhile :; do :; done\n' > "$WORK/mkloops/loop.sh"
later_red_out "make_test: ...and so is a creator script" \
	"too slow on 'sh loop.sh'" -- \
	$SHORT "$SH" "$TOOLS/make_test.sh" --nm "$NM" --script loop.sh \
		--build-target selftest_build --anchor "$WORK/mkloops/loop.sh" --artifact libselftest.a

# A PART BUILT BY A RULE OF ITS OWN (--make-goal G): the build is `make G`.
# Without it a part sharing its Makefile with another was built by a bare
# `make`, so a Makefile with no bonus rule passed whenever the default goal
# made the same artifact (the mtgoal_lib pair), and a correct one failed
# whenever it made another (mtgoal: a bare `make` builds no checker).
for _d in mtgoal mtgoal_lib mtgoal_src mtgoal_warn mtgoal_phony mtgoal_echo; do
	mkdir -p "$WORK/$_d"
done
# The recipes make files with `: >`, as this section's other fixtures do:
# which rule runs is the question, and no compiler of the box's answers it.
printf 'all: sorter\nsorter:\n\t: > sorter\nbonus: checker\nchecker:\n\t: > checker\n.PHONY: all bonus\n' \
	> "$WORK/mtgoal/Makefile"
printf 'all: libtoy.a\nlibtoy.a:\n\t: > libtoy.a\n' > "$WORK/mtgoal_lib/Makefile"
printf 'all:\n\t: > sorter\n' > "$WORK/mtgoal_src/Makefile"
printf 'int main(void) { return (0); }\n' > "$WORK/mtgoal_src/bonus.c"
printf 'all:\n\t: > sorter\nall:\n\t: > sorter\n' > "$WORK/mtgoal_warn/Makefile"
printf 'int main(void) { return (0); }\n' > "$WORK/mtgoal_warn/bonus.c"
printf 'all:\n\t: > sorter\n.PHONY: all bonus\n' > "$WORK/mtgoal_phony/Makefile"
printf 'all:\n\t: > sorter\nbonus:\n\t@echo bonus\n' > "$WORK/mtgoal_echo/Makefile"
printf 'goal\tAn invented subject: "The bonus part is built by a rule of its own."\n' > "$WORK/mtgoal.q"
want_green "make_test: --make-goal builds with that rule" -- \
	mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal/Makefile" --artifact checker --build-target checker_build
want_green "make_test: ...and its exit twin judges that build" -- \
	mt --rules - --exit-only --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal/Makefile" --artifact checker --build-target checker_build
want_green "make_test: a bare make makes libtoy.a without a bonus rule" -- \
	mt --rules - --anchor "$WORK/mtgoal_lib/Makefile" --artifact libtoy.a
want_red "make_test: ...which --make-goal bonus does not take for one" -- \
	mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_lib/Makefile" --artifact libtoy.a --build-target bonus_build
want_out "make_test: ...saying the Makefile has no such rule" \
	'your Makefile has no bonus rule' -- \
	mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_lib/Makefile" --artifact libtoy.a --build-target bonus_build
want_out "make_test: ...quoting the sentence it applies" 'built by a rule of its own' -- \
	mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_lib/Makefile" --artifact libtoy.a --build-target bonus_build
want_out "make_test: ...and its exit twin stands down" 'SKIP — your Makefile has no bonus rule' -- \
	mt --rules - --exit-only --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_lib/Makefile" --artifact libtoy.a --build-target bonus_build
want_out "make_test: a bonus.c make compiles alone is no rule" \
	'your Makefile has no bonus rule' -- \
	mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_src/Makefile" --artifact bonus --build-target bonus_build
want_out "make_test: ...nor under a Makefile make warns about" \
	'your Makefile has no bonus rule' -- \
	mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_warn/Makefile" --artifact bonus --build-target bonus_build
want_out "make_test: ...where its exit twin stands down for that" \
	'SKIP — your Makefile has no bonus rule' -- \
	mt --rules - --exit-only --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_warn/Makefile" --artifact bonus --build-target bonus_build
want_out "make_test: a name in .PHONY alone is no rule" \
	'names bonus and gives it no rule' -- \
	mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_phony/Makefile" --artifact checker --build-target checker_build
want_out "make_test: a rule that only echoes names that rule" \
	"'make bonus' runs your Makefile's bonus rule" -- \
	mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_echo/Makefile" --artifact checker --build-target checker_build
# make reads the first of GNUmakefile, makefile and Makefile there is, and so
# does the reading of its rules: a Makefile with the rule, beside one of the
# other two without it, has none make reads.
for _d in mtgoal_gnu mtgoal_lower; do
	mkdir -p "$WORK/$_d"
	cp "$WORK/mtgoal/Makefile" "$WORK/$_d/Makefile"
done
printf 'all:\n\t: > sorter\n' > "$WORK/mtgoal_gnu/GNUmakefile"
printf 'all:\n\t: > sorter\n' > "$WORK/mtgoal_lower/makefile"
want_out "make_test: a GNUmakefile without the rule is read before the Makefile" \
	'your Makefile has no bonus rule' -- \
	mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_gnu/Makefile" --artifact checker --build-target checker_build
want_out "make_test: ...and so is a makefile" \
	'your Makefile has no bonus rule' -- \
	mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_lower/Makefile" --artifact checker --build-target checker_build
want_broken "make_test: --make-goal takes a rule's name" 'takes a Makefile rule' -- \
	mt --rules - --make-goal -k --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal/Makefile" --artifact checker --build-target checker_build
want_broken "make_test: --make-goal needs its sentence" "the 'goal' sentence" -- \
	mt --rules - --make-goal bonus \
		--anchor "$WORK/mtgoal/Makefile" --artifact checker --build-target checker_build
want_broken "make_test: --make-goal judges no shared rule" 'cannot be combined with: --rules' -- \
	mt --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal/Makefile" --artifact checker --build-target checker_build
want_broken "make_test: ...and no relink" 'cannot be combined with: --relink' -- \
	mt --rules - --relink --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal/Makefile" --artifact checker --build-target checker_build
want_broken "make_test: ...and a goal sentence needs --make-goal" 'no --make-goal for it to back' -- \
	mt --rules - --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal/Makefile" --artifact sorter --build-target sorter_build

# Make's database is read when make read the whole Makefile, and its LAST
# line on stderr is one sign of that: make stops at its first error, so its
# complaint that the goal .DEFAULT has no rule comes last only when nothing
# stopped it before. Each tree below has a bonus.c a built-in rule compiles,
# and no bonus rule. What may come before that complaint and is no error: a
# $(warning) whose text holds ***, a $(shell) that writes *** to stderr, a
# sub-make that fails to remake an optional include. A Makefile that refuses
# a goal it does not know reads as it does under `make bonus`, so .DEFAULT,
# the goal the database is asked for, is not refused. And a $(error) worded
# as make's complaint is not it: make puts its file and line before it, and
# the bonus rule after it is never read. Nor is the same line written by a
# $(shell) before a $(error) that stops make: it is not the last.
for _d in mtgoal_wstars mtgoal_shstars mtgoal_submk/sub mtgoal_gfilt mtgoal_mimic mtgoal_shmimic; do
	mkdir -p "$WORK/$_d"
	cp "$WORK/mtgoal_src/bonus.c" "$WORK/${_d%/sub}/bonus.c"
done
printf '$(warning *** careful)\nall:\n\t: > sorter\n' > "$WORK/mtgoal_wstars/Makefile"
printf 'X := $(shell echo "lib: *** not built" >&2)\nall:\n\t: > sorter\n' \
	> "$WORK/mtgoal_shstars/Makefile"
printf -- '-include gen.mk\nall:\n\t: > sorter\ngen.mk:\n\t$(MAKE) -C sub gen.mk\n' \
	> "$WORK/mtgoal_submk/Makefile"
printf 'other:\n\t@:\n' > "$WORK/mtgoal_submk/sub/Makefile"
printf 'ifneq ($(filter-out all clean fclean re bonus,$(MAKECMDGOALS)),)\n$(error unknown goal: $(MAKECMDGOALS))\nendif\nall:\n\t: > sorter\n' \
	> "$WORK/mtgoal_gfilt/Makefile"
printf 'all:\n\t: > sorter\n$(error No rule to make target '\''.DEFAULT'\'')\nbonus: checker\nchecker:\n\t: > checker\n' \
	> "$WORK/mtgoal_mimic/Makefile"
printf 'X := $(shell echo "make: *** No rule to make target '\''.DEFAULT'\''.  Stop." >&2)\n$(error stopped here)\nbonus: checker\nchecker:\n\t: > checker\n' \
	> "$WORK/mtgoal_shmimic/Makefile"
for _d in mtgoal_wstars mtgoal_shstars mtgoal_submk mtgoal_gfilt; do
	want_out "make_test: no bonus rule, whatever came before the last line ($_d)" \
		'your Makefile has no bonus rule' -- \
		mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
			--anchor "$WORK/$_d/Makefile" --artifact bonus --build-target bonus_build
done
want_broken_none "make_test: a \$(error) worded as make's complaint is not it" \
	'your Makefile has no bonus rule' -- \
	mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_mimic/Makefile" --artifact checker --build-target checker_build
want_out "make_test: ...and make's own words say why it stopped" \
	"*** No rule to make target '.DEFAULT'" -- \
	mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_mimic/Makefile" --artifact checker --build-target checker_build
want_broken_none "make_test: the complaint is make's only when it is the last line" \
	'your Makefile has no bonus rule' -- \
	mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_shmimic/Makefile" --artifact checker --build-target checker_build
# Make's messages are translated, and the complaint is matched in its own
# English words. This box's make has no translation, so the stand-in below is
# the box's make with that complaint said in French, and the lines -w prints
# around a sub-make, and "No targets", which student_build reads. Its
# standard output comes before its standard error. It speaks English only
# under LC_ALL=C with LANGUAGE unset or empty: stricter than gettext, which
# reads no LANGUAGE under the C locale, so that both are held to be cleared.
# xlmake DIR writes it as DIR/make; student_build's section writes its own.
xlmake() {
	mkdir -p "$1"
	{
		echo '#!/bin/sh'
		printf '_m=%s\n' "$(command -v make)"
		cat <<-'XLMAKE'
		if [ "${LC_ALL:-}" = C ] && [ -z "${LANGUAGE:-}" ]; then
			exec "$_m" "$@"
		fi
		_e=$(mktemp) || exit 2
		_o=$(mktemp) || exit 2
		"$_m" "$@" > "$_o" 2> "$_e"
		_r=$?
		sed -e "s/: Entering directory '\(.*\)'\$/ : on entre dans le répertoire « \1 »/" \
			-e "s/: Leaving directory '\(.*\)'\$/ : on quitte le répertoire « \1 »/" "$_o"
		sed -e "s/No rule to make target '\(.*\)'\.  Stop\./Aucune règle pour fabriquer la cible « \1 ».  Arrêt./" \
			-e "s/No targets\.  Stop\./Pas de cible.  Arrêt./" "$_e" >&2
		rm -f "$_e" "$_o"
		exit "$_r"
		XLMAKE
	} > "$1/make"
	chmod +x "$1/make"
}
xlmake "$WORK/xlmake"
want_out "make_test: no bonus rule, read from a make that speaks French" \
	'your Makefile has no bonus rule' -- \
	once env LANGUAGE=fr "$SH" "$TOOLS/make_test.sh" --nm "$NM" --make "$WORK/xlmake/make" \
		--rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_src/Makefile" --artifact bonus --build-target bonus_build
# Nor can stderr alone say make read the whole Makefile: a $(error) whose text
# holds a newline ends in make's complaint, word for word, with the bonus rule
# after it never read (mtgoal_nlmimic). So make reads a makefile of the
# runner's after the student's, and what it sets says the reading got there.
# Then the complaint may come without its "Stop.", under -k from the Makefile
# or from the environment, and after what a $(shell) wrote to stderr with no
# newline; but not after an include make could not make, which -k goes on
# past too, and whose rules the database lacks (mtgoal_kincl). And
# MAKECMDGOALS reaches make as `make bonus` gives it, which a Makefile that
# sets it itself overrides.
for _d in mtgoal_nlmimic mtgoal_kflag mtgoal_shnonl mtgoal_mcgset mtgoal_kincl; do
	mkdir -p "$WORK/$_d"
	cp "$WORK/mtgoal_src/bonus.c" "$WORK/$_d/bonus.c"
done
printf 'define NL\n\n\nendef\nall:\n\t: > sorter\n$(error x$(NL)make: *** No rule to make target '\''.DEFAULT'\'')\nbonus: checker\nchecker:\n\t: > checker\n' \
	> "$WORK/mtgoal_nlmimic/Makefile"
printf 'MAKEFLAGS += -k\nall:\n\t: > sorter\n' > "$WORK/mtgoal_kflag/Makefile"
printf 'all:\n\t: > sorter\nX := $(shell printf '\''no newline after this'\'' >&2)\n' \
	> "$WORK/mtgoal_shnonl/Makefile"
printf 'MAKECMDGOALS := all\nifneq ($(MAKECMDGOALS),all)\n$(error only all)\nendif\nall:\n\t: > sorter\n' \
	> "$WORK/mtgoal_mcgset/Makefile"
printf 'MAKEFLAGS += -k\ninclude gone.mk\nall:\n\t: > sorter\n' > "$WORK/mtgoal_kincl/Makefile"
want_broken_none "make_test: a \$(error) that ends in make's complaint is not it" \
	'your Makefile has no bonus rule' -- \
	mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_nlmimic/Makefile" --artifact checker --build-target checker_build
for _d in mtgoal_kflag mtgoal_shnonl mtgoal_mcgset; do
	want_out "make_test: no bonus rule, read to the end ($_d)" \
		'your Makefile has no bonus rule' -- \
		mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
			--anchor "$WORK/$_d/Makefile" --artifact bonus --build-target bonus_build
done
want_out "make_test: no bonus rule, under a MAKEFLAGS=k from outside" \
	'your Makefile has no bonus rule' -- \
	once env MAKEFLAGS=k "$SH" "$TOOLS/make_test.sh" --nm "$NM" --build-target bonus_build \
		--rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_src/Makefile" --artifact bonus
want_broken_none "make_test: ...but not past an include it could not make" \
	'your Makefile has no bonus rule' -- \
	mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_kincl/Makefile" --artifact bonus --build-target bonus_build
# A makefile make includes and knows how to make is made first, and make then
# starts again and reads everything anew, printing a database each time: the
# last is the one `make bonus` goes on with. There the bonus rule may come
# from the made file alone (mtgoal_rxphony), or take its prerequisite from a
# variable it sets (mtgoal_rxconf); and a reading that stops the second time
# never reaches the runner's makefile, however the first one ended
# (mtgoal_rxmimic). And the makefile make failed to remake is one its own
# database marks so: the same words from a sub-make that a $(shell) runs are
# that sub-make's, not this make's (mtgoal_shsubk).
for _d in mtgoal_rxphony mtgoal_rxconf mtgoal_rxmimic mtgoal_shsubk; do
	mkdir -p "$WORK/$_d"
	cp "$WORK/mtgoal_src/bonus.c" "$WORK/$_d/bonus.c"
done
printf '.PHONY: all bonus\nall:\n\t: > sorter\n-include gen.mk\ngen.mk:\n\tprintf '\''bonus: checker\\nchecker:\\n\\t: > checker\\n'\'' > gen.mk\n' \
	> "$WORK/mtgoal_rxphony/Makefile"
printf -- '-include config.mk\nconfig.mk:\n\tprintf '\''BONUS_NAME := checker\\n'\'' > config.mk\nall:\n\t: > sorter\nbonus: $(BONUS_NAME)\nchecker:\n\t: > checker\n.PHONY: all bonus\n' \
	> "$WORK/mtgoal_rxconf/Makefile"
printf 'define NL\n\n\nendef\nall:\n\t: > sorter\n-include gen.mk\ngen.mk:\n\tprintf '\''ok := 1\\n'\'' > gen.mk\nifdef ok\n$(error x$(NL)make: *** No rule to make target '\''.DEFAULT'\'')\nbonus: checker\nchecker:\n\t: > checker\nendif\n' \
	> "$WORK/mtgoal_rxmimic/Makefile"
printf 'all:\n\t: > sorter\nX := $(shell $(MAKE) -k -f nothere.mk > /dev/null)\n' \
	> "$WORK/mtgoal_shsubk/Makefile"
for _d in mtgoal_rxphony mtgoal_rxconf; do
	want_green "make_test: the rule make reads once it made what it includes ($_d)" -- \
		mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
			--anchor "$WORK/$_d/Makefile" --artifact checker --build-target checker_build
done
want_broken_none "make_test: ...and a second reading that stops is not read to the end" \
	'your Makefile has no bonus rule' -- \
	mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_rxmimic/Makefile" --artifact checker --build-target checker_build
want_out "make_test: no bonus rule, whatever a sub-make failed to remake" \
	'your Makefile has no bonus rule' -- \
	mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_shsubk/Makefile" --artifact bonus --build-target bonus_build
# The database is make's reading of the Makefile with the built-in variables
# `make bonus` reads, and its built-in rules, which set one of them: a rule
# under a conditional on one of those variables is there (mtgoal_ccvar, and
# mtgoal_sfxvar, on the suffixes those rules know). What a variable holds is
# printed in it as it is, and is no line of the database: the body of a
# define, one with a define inside it too, that holds the line the rules are
# listed under (mtgoal_defhdr, mtgoal_defnest), nor a := of one, which prints
# its lines with nothing around them, holding a line that starts as that one
# does or that very line (mtgoal_valhdr, mtgoal_valfiles). And under -k, a
# file dated in the future has make warn after its complaint, at its end
# (mtgoal_skew); .EXTRA_PREREQS gives every rule a prerequisite, the
# runner's own too (mtgoal_extra).
for _d in mtgoal_ccvar mtgoal_sfxvar mtgoal_defhdr mtgoal_defnest mtgoal_valhdr mtgoal_valfiles \
	mtgoal_skew mtgoal_extra; do
	mkdir -p "$WORK/$_d"
	cp "$WORK/mtgoal_src/bonus.c" "$WORK/$_d/bonus.c"
done
printf 'all:\n\t: > sorter\nifneq ($(SUFFIXES),)\nbonus: checker\nchecker:\n\t: > checker\nendif\n' \
	> "$WORK/mtgoal_sfxvar/Makefile"
printf 'all:\n\t: > sorter\nifdef COMPILE.c\nbonus: checker\nchecker:\n\t: > checker\nendif\n' \
	> "$WORK/mtgoal_ccvar/Makefile"
printf 'all:\n\t: > sorter\ndefine TPL\n# Files\nbonus: checker\nendef\n' > "$WORK/mtgoal_defhdr/Makefile"
printf 'all:\n\t: > sorter\ndefine TPL\ndefine IN\nx\nendef\n# Files\nbonus: checker\nendef\n' \
	> "$WORK/mtgoal_defnest/Makefile"
printf 'define TPL\n\n# Files of the bonus\nbonus: checker\nendef\nS := $(TPL)\nall:\n\t: > sorter\n' \
	> "$WORK/mtgoal_valhdr/Makefile"
printf 'define TPL\n\n# Files\nbonus: checker\nendef\nS := $(TPL)\nall:\n\t: > sorter\n' \
	> "$WORK/mtgoal_valfiles/Makefile"
printf 'MAKEFLAGS += -k\nX := $(shell touch -t 209901010000 future.mk)\n-include future.mk\nall:\n\t: > sorter\n' \
	> "$WORK/mtgoal_skew/Makefile"
printf 'all:\n\t: > sorter\n.EXTRA_PREREQS := stamp\nstamp:\n\t: > stamp\n' > "$WORK/mtgoal_extra/Makefile"
want_green "make_test: a rule under a built-in variable is in the database" -- \
	mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_ccvar/Makefile" --artifact checker --build-target checker_build
want_green "make_test: ...and one under the suffixes make knows by itself" -- \
	mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_sfxvar/Makefile" --artifact checker --build-target checker_build
for _d in mtgoal_defhdr mtgoal_defnest mtgoal_valhdr mtgoal_valfiles mtgoal_skew; do
	want_out "make_test: no bonus rule, whatever a value holds or make warns ($_d)" \
		'your Makefile has no bonus rule' -- \
		mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
			--anchor "$WORK/$_d/Makefile" --artifact bonus --build-target bonus_build
done
want_out "make_test: no bonus rule, whatever .EXTRA_PREREQS adds to every rule" \
	'your Makefile has no bonus rule' -- \
	mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_extra/Makefile" --artifact bonus --build-target bonus_build
# The database is read as make prints it, block by block, from the runner's
# rule on. A recipe is read line by line with the lines that continue it,
# whatever they hold: one of a suffix rule, which make lists after the
# runner's rule, under a .RECIPEPREFIX the Makefile sets last (mtgoal_rpfx);
# one that reads as the first line of a database (mtgoal_dbreset); an empty
# one, and a recipe line after it that starts as a rule's name does, under a
# prefix of the Makefile's (mtgoal_pfxjoin). A target's own variable is read
# up to the target's own line (mtgoal_tsvnl), and the rules to their end, not
# the search paths printed after them (mtgoal_vpath). A rule under a prefix
# of the Makefile's follows a line that names that prefix, and is there
# (mtgoal_pfxrule); so is a :: rule whose first block does nothing and whose
# second does (mtgoal_dcfirst). And the Makefile reads the MAKEFLAGS `make
# bonus` reads: one that leaves its bonus rule out when make is asked a
# question (-q) has it (mtgoal_mflags).
for _d in mtgoal_rpfx mtgoal_dbreset mtgoal_pfxjoin mtgoal_tsvnl mtgoal_vpath mtgoal_pfxrule \
	mtgoal_dcfirst mtgoal_mflags; do
	mkdir -p "$WORK/$_d"
	cp "$WORK/mtgoal_src/bonus.c" "$WORK/$_d/bonus.c"
done
printf 'all:\n\t: > sorter\n.SUFFIXES: .q .z\n.q.z:\n\t@echo \\\n# Files\n\tonus: checker\n.RECIPEPREFIX := b\n' \
	> "$WORK/mtgoal_rpfx/Makefile"
printf 'all:\n\t: > sorter\nclean:\n\trm -f sorter \\\n# Make data base, printed on a Monday\n' \
	> "$WORK/mtgoal_dbreset/Makefile"
printf 'all:\n\t: > sorter\n.RECIPEPREFIX := b\njunk:\nbecho \\\n\nbonus: checker\n.RECIPEPREFIX :=\n' \
	> "$WORK/mtgoal_pfxjoin/Makefile"
printf 'define TPL\n\n\nbonus: checker\nendef\nsorter: S := $(TPL)\nall:\n\t: > sorter\n' \
	> "$WORK/mtgoal_tsvnl/Makefile"
printf 'define NL\n\n\nendef\nvpath %%.c x$(NL)$(NL)bonus:checker\nall:\n\t: > sorter\n' \
	> "$WORK/mtgoal_vpath/Makefile"
printf 'all:\n\t: > sorter\n.RECIPEPREFIX := >\nbonus:\n>: > checker\n' > "$WORK/mtgoal_pfxrule/Makefile"
printf 'all:\n\t: > sorter\nbonus::\nbonus::\n\t: > checker\n' > "$WORK/mtgoal_dcfirst/Makefile"
printf 'all:\n\t: > sorter\nifeq ($(findstring q,$(MAKEFLAGS)),)\nbonus:\n\t: > checker\nendif\n' \
	> "$WORK/mtgoal_mflags/Makefile"
for _d in mtgoal_rpfx mtgoal_dbreset mtgoal_pfxjoin mtgoal_tsvnl mtgoal_vpath; do
	want_out "make_test: no bonus rule, however make prints a recipe or a value ($_d)" \
		'your Makefile has no bonus rule' -- \
		mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
			--anchor "$WORK/$_d/Makefile" --artifact bonus --build-target bonus_build
done
for _d in mtgoal_pfxrule mtgoal_dcfirst mtgoal_mflags; do
	want_green "make_test: the bonus rule is there, however make prints it ($_d)" -- \
		mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
			--anchor "$WORK/$_d/Makefile" --artifact checker --build-target checker_build
done
# While make reads the database it remakes the Makefile's includes as under
# `make bonus`, with the sub-makes that do it, which really run (make passes
# neither -n nor -q on to them), so a rule an include holds that a sub-make
# writes is there (mtgoal_subgen); and a Makefile read again after an include
# was remade reads the MAKEFLAGS `make bonus` reads too (mtgoal_mfrx). A
# .RECIPEPREFIX the Makefile sets last does not change how the runner's
# makefile is read, whatever letter its lines start with (mtgoal_pfxh, _pfxo,
# _pfxM), and nor does a value the Makefile gives the runner's own variable
# (mtgoal_hrov).
for _d in mtgoal_subgen mtgoal_mfrx mtgoal_pfxh mtgoal_pfxo mtgoal_pfxM mtgoal_hrov; do
	mkdir -p "$WORK/$_d"
done
for _d in mtgoal_pfxh mtgoal_pfxo mtgoal_pfxM mtgoal_hrov; do
	cp "$WORK/mtgoal_src/bonus.c" "$WORK/$_d/bonus.c"
	printf 'all:\n\t: > sorter\n' > "$WORK/$_d/Makefile"
done
printf 'all:\n\t: > sorter\n-include gen.mk\ngen.mk:\n\t$(MAKE) -f gen.make gen.mk\n' \
	> "$WORK/mtgoal_subgen/Makefile"
printf 'gen.mk:\n\tprintf "bonus:\\n\\t: > checker\\n" > gen.mk\n' > "$WORK/mtgoal_subgen/gen.make"
printf 'all:\n\t: > sorter\n-include gen.mk\ngen.mk:\n\tprintf "x := 1\\n" > gen.mk\nifeq ($(findstring q,$(MAKEFLAGS)),)\nbonus:\n\t: > checker\nendif\n' \
	> "$WORK/mtgoal_mfrx/Makefile"
for _c in h o M; do
	printf '.RECIPEPREFIX := %s\n' "$_c" >> "$WORK/mtgoal_pfx$_c/Makefile"
done
printf 'override HARNESS_READ_TO_THE_END := no\n' >> "$WORK/mtgoal_hrov/Makefile"
for _d in mtgoal_subgen mtgoal_mfrx; do
	want_green "make_test: the bonus rule is there, however make reads the includes ($_d)" -- \
		mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
			--anchor "$WORK/$_d/Makefile" --artifact checker --build-target checker_build
done
for _d in mtgoal_pfxh mtgoal_pfxo mtgoal_pfxM mtgoal_hrov; do
	want_out "make_test: no bonus rule, whatever the Makefile sets last ($_d)" \
		'your Makefile has no bonus rule' -- \
		mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
			--anchor "$WORK/$_d/Makefile" --artifact bonus --build-target bonus_build
done
# make passes -p on to those sub-makes, though, so each prints a database
# too, and one whose output is the include leaves that database in it, which
# make then reads as the Makefile's own lines. A reading that left one in a
# file of the tree is not trusted: the tree is put back as it was staged, its
# includes are made by a make asked for no database, and make is read again,
# so that a rule that database had is not the Makefile's, and a built-in rule
# does not answer for one it lacks (mtgoal_cfgnob); the Makefile's own is
# there where it had another (mtgoal_cfgok). The second reading takes the
# files the first one made or changed as up to date, so an include made each
# time make runs (once: one made again after each restart would have make
# restart for as long as its date moves) is read as the make asked for no
# database made it (mtgoal_cfgforce). And make's complaint may be of a
# prerequisite of .DEFAULT it has no rule for, "Stop." left out under -k
# (mtgoal_defpre, mtgoal_defpok).
for _d in mtgoal_cfgnob mtgoal_cfgok mtgoal_cfgforce mtgoal_defpre mtgoal_defpok; do
	mkdir -p "$WORK/$_d"
done
for _d in mtgoal_cfgnob mtgoal_defpre mtgoal_defpok; do
	cp "$WORK/mtgoal_src/bonus.c" "$WORK/$_d/bonus.c"
done
printf 'all:\n\t: > sorter\ninclude config.mk\nconfig.mk:\n\t$(MAKE) -s --no-print-directory -f tools.make config > $@\n' \
	> "$WORK/mtgoal_cfgnob/Makefile"
printf 'config:\n\t@echo "X = 1"\nbonus:\n\t: > checker\n' > "$WORK/mtgoal_cfgnob/tools.make"
printf 'all:\n\t: > sorter\nbonus: checker\nchecker:\n\t: > checker\ninclude config.mk\nconfig.mk:\n\t$(MAKE) -s --no-print-directory -f tools.make config > $@\n' \
	> "$WORK/mtgoal_cfgok/Makefile"
printf 'all:\n\t: > sorter\nbonus: checker\nchecker:\n\t: > checker\ninclude config.mk\nconfig.mk: $(if $(MAKE_RESTARTS),,FORCE)\n\t$(MAKE) -s --no-print-directory -f tools.make config > $@\nFORCE:\n' \
	> "$WORK/mtgoal_cfgforce/Makefile"
for _d in mtgoal_cfgok mtgoal_cfgforce; do
	printf 'config:\n\t@echo "X = 1"\nchecker:\n\tfalse\n' > "$WORK/$_d/tools.make"
done
printf '.DEFAULT: nothere\nall:\n\t: > sorter\n' > "$WORK/mtgoal_defpre/Makefile"
printf 'MAKEFLAGS += -k\n.DEFAULT: | nothere\nall:\n\t: > sorter\n' > "$WORK/mtgoal_defpok/Makefile"
want_out "make_test: no bonus rule where a sub-make's database had one (mtgoal_cfgnob)" \
	'your Makefile has no bonus rule' -- \
	mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_cfgnob/Makefile" --artifact bonus --build-target bonus_build
for _d in mtgoal_cfgok mtgoal_cfgforce; do
	want_green "make_test: the Makefile's own rule where that database had another ($_d)" -- \
		mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
			--anchor "$WORK/$_d/Makefile" --artifact checker --build-target checker_build
done
for _d in mtgoal_defpre mtgoal_defpok; do
	want_out "make_test: no bonus rule, whatever .DEFAULT needs ($_d)" \
		'your Makefile has no bonus rule' -- \
		mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
			--anchor "$WORK/$_d/Makefile" --artifact bonus --build-target bonus_build
done
# So with no bonus rule, an include made each time make reads the Makefile
# holds no database of make's, and a built-in rule does not answer for the
# rule it lacks (mtgoal_force). A second reading that leaves a database all
# the same stops the runner, which says why (mtgoal_forcelate).
for _d in mtgoal_force mtgoal_forcelate; do
	mkdir -p "$WORK/$_d"
	cp "$WORK/mtgoal_src/bonus.c" "$WORK/$_d/bonus.c"
	printf 'all:\n\t@#nothing\n' > "$WORK/$_d/gen.mk"
done
printf 'all:\n\t: > sorter\n-include config.mk\nconfig.mk: $(if $(MAKE_RESTARTS),,FORCE)\n\t@$(MAKE) --no-print-directory -s -f gen.mk > $@\nFORCE:\n' \
	> "$WORK/mtgoal_force/Makefile"
printf 'all:\n\t: > sorter\n-include a.mk b.mk\na.mk:\n\t@$(MAKE) --no-print-directory -s -f gen.mk > $@\n\t@grep -q "data base" $@ || : > stamp\nb.mk: $(if $(wildcard stamp),$(if $(MAKE_RESTARTS),,FORCE))\n\t@$(MAKE) --no-print-directory -s -f gen.mk > $@\nFORCE:\n' \
	> "$WORK/mtgoal_forcelate/Makefile"
: > "$WORK/mtgoal_forcelate/b.mk"
want_out "make_test: no bonus rule, whatever an include made each time holds (mtgoal_force)" \
	'your Makefile has no bonus rule' -- \
	mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_force/Makefile" --artifact bonus --build-target bonus_build
want_broken "make_test: a database each reading leaves stops it (mtgoal_forcelate)" \
	'each time make reads it' -- \
	mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_forcelate/Makefile" --artifact bonus --build-target bonus_build
# The second reading reads such an include as `make bonus` makes it, rule
# and all. The make between the readings asks for no -q, which a MAKEFLAGS
# the Makefile sets with override would pass on to the sub-make that writes
# the include (mtgoal_ovforce); no make a recipe runs is given the goal the
# readings set in MAKECMDGOALS, as none is under `make bonus`
# (mtgoal_goalsforce); and the second reading remakes no file the first one
# made by the path from the tree or by $(CURDIR)'s (mtgoal_absforce).
for _d in mtgoal_ovforce mtgoal_goalsforce mtgoal_absforce; do
	mkdir -p "$WORK/$_d"
	cp "$WORK/mtgoal_src/bonus.c" "$WORK/$_d/bonus.c"
done
printf 'override MAKEFLAGS += -s\nall:\n\t: > sorter\n-include config.mk\nconfig.mk: $(if $(MAKE_RESTARTS),,FORCE)\n\t@$(MAKE) --no-print-directory -f gen.mk > $@\nFORCE:\n' \
	> "$WORK/mtgoal_ovforce/Makefile"
printf 'all:\n\t@printf "bonus:\\n\\t: > checker\\n"\n' > "$WORK/mtgoal_ovforce/gen.mk"
printf 'all:\n\t: > sorter\n-include config.mk\nconfig.mk: $(if $(MAKE_RESTARTS),,FORCE)\n\t@$(MAKE) --no-print-directory -s -f gen.mk > $@\nFORCE:\n' \
	> "$WORK/mtgoal_goalsforce/Makefile"
printf 'all:\nifeq ($(MAKECMDGOALS),)\n\t@printf "bonus:\\n\\t: > checker\\n"\nelse\n\t@echo "X = 1"\nendif\n' \
	> "$WORK/mtgoal_goalsforce/gen.mk"
printf 'all:\n\t: > sorter\nbonus: checker\nchecker:\n\t: > checker\ninclude $(CURDIR)/config.mk\n$(CURDIR)/config.mk: $(if $(MAKE_RESTARTS),,FORCE)\n\t$(MAKE) -s --no-print-directory -f tools.make config > $@\nFORCE:\n' \
	> "$WORK/mtgoal_absforce/Makefile"
printf 'config:\n\t@echo "X = 1"\nchecker:\n\tfalse\n' > "$WORK/mtgoal_absforce/tools.make"
for _d in mtgoal_ovforce mtgoal_goalsforce mtgoal_absforce; do
	want_green "make_test: the bonus rule is there, as make bonus makes the include ($_d)" -- \
		mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
			--anchor "$WORK/$_d/Makefile" --artifact checker --build-target checker_build
done
# A line that starts a database, in a value make prints among the variables,
# changes nothing of how the database after it is read (mtgoal_hdrval). And a
# database not laid out as make lays one out is never left to `make bonus`,
# which a built-in rule would answer here: one with the line of this run's
# rule in a value, worked out from the folders around the Makefile, stops the
# runner, which says why (mtgoal_fanch).
for _d in mtgoal_hdrval mtgoal_fanch; do
	mkdir -p "$WORK/$_d"
	cp "$WORK/mtgoal_src/bonus.c" "$WORK/$_d/bonus.c"
done
printf 'all:\n\t: > sorter\ndefine TPL\n\n# Make data base, printed on x\nendef\nsorter: S := $(TPL)\n' \
	> "$WORK/mtgoal_hdrval/Makefile"
printf 'all:\n\t: > sorter\ndefine NL\n\n\nendef\nX := $(foreach d,$(wildcard ../*/probe.mk),$(NL)harness-anchor-$(notdir $(patsubst %%/,%%,$(dir $(d))))%%:$(NL))\n' \
	> "$WORK/mtgoal_fanch/Makefile"
want_out "make_test: no bonus rule, whatever a value holds before the rules (mtgoal_hdrval)" \
	'your Makefile has no bonus rule' -- \
	mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_hdrval/Makefile" --artifact bonus --build-target bonus_build
want_broken "make_test: a database not laid out as make lays one out stops it (mtgoal_fanch)" \
	'is not laid out as make lays one out' -- \
	mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_fanch/Makefile" --artifact bonus --build-target bonus_build
# A rule that is there only when make is not asked for a dry run (-n) is
# there under `make bonus` (mtgoal_mfn), and one there only under -n is not
# (mtgoal_mfnot). A rule that is another under -n is the one `make bonus`
# runs (mtgoal_mfboth).
for _d in mtgoal_mfn mtgoal_mfnot mtgoal_mfboth; do
	mkdir -p "$WORK/$_d"
	cp "$WORK/mtgoal_src/bonus.c" "$WORK/$_d/bonus.c"
done
printf 'all:\n\t: > sorter\nifeq ($(findstring n,$(MAKEFLAGS)),)\nbonus:\n\t: > checker\nendif\n' \
	> "$WORK/mtgoal_mfn/Makefile"
printf 'all:\n\t: > sorter\nifneq ($(findstring n,$(MAKEFLAGS)),)\nbonus:\n\t: > checker\nendif\n' \
	> "$WORK/mtgoal_mfnot/Makefile"
printf 'all:\n\t: > sorter\nifeq ($(MAKEFLAGS),)\nbonus:\n\t: > checker\nelse\nbonus:\n\t: > other\nendif\n' \
	> "$WORK/mtgoal_mfboth/Makefile"
want_green "make_test: the bonus rule is the one make reads without a dry run (mtgoal_mfboth)" -- \
	mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_mfboth/Makefile" --artifact checker --build-target checker_build
want_green "make_test: the bonus rule make reads without a dry run is there (mtgoal_mfn)" -- \
	mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_mfn/Makefile" --artifact checker --build-target checker_build
want_out "make_test: no bonus rule, whatever a dry run would read (mtgoal_mfnot)" \
	'your Makefile has no bonus rule' -- \
	mt --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
		--anchor "$WORK/mtgoal_mfnot/Makefile" --artifact bonus --build-target bonus_build
# The runner's makefile is named from the folder make runs in, so a space, a
# # or a $ in the path of the scratch folders is no part of the name make
# reads, nor of the rule it is read from.
for _c in ' ' '#' '$'; do
	mkdir -p "$WORK/mttmp/tmp${_c}dir"
	want_out "make_test: no bonus rule, under a TMPDIR that holds a '$_c'" \
		'your Makefile has no bonus rule' -- \
		once env TMPDIR="$WORK/mttmp/tmp${_c}dir" "$SH" "$TOOLS/make_test.sh" --nm "$NM" \
			--build-target bonus_build --rules - --make-goal bonus --quotes "$WORK/mtgoal.q" \
			--anchor "$WORK/mtgoal_src/Makefile" --artifact bonus
done


# make's database is read by tools/make_db.awk, staged beside the runner. A
# reader that fails -- an exit that is none of its answers, awk's own error
# -- says nothing of the Makefile, so it stops the runner (exit 2), and so
# does a reader that is not there. Each arm runs a copy of the runner whose
# make_db.awk is broken on purpose, or gone.
for _d in mtdb_bad mtdb_none; do
	mkdir -p "$WORK/$_d"
	cp "$TOOLS/make_test.sh" "$TOOLS/runner_lib.sh" "$WORK/$_d/"
	[ ! -f "$TOOLS/exit_status" ] || cp "$TOOLS/exit_status" "$WORK/$_d/"
done
printf 'BEGIN { exit 9 }\n' > "$WORK/mtdb_bad/make_db.awk"
mtdb() {  # mtdb DIR: DIR's copy of make_test.sh, --make-goal bonus over mtgoal
	"$SH" "$WORK/$1/make_test.sh" --nm "$NM" --build-target checker_build --rules - \
		--make-goal bonus --quotes "$WORK/mtgoal.q" --anchor "$WORK/mtgoal/Makefile" \
		--artifact checker
}
want_broken "make_test: a make_db.awk that fails stops it" \
	"could not read make's database of the Makefile (awk exited 9)" -- mtdb mtdb_bad
want_broken "make_test: ...and so does one not staged" \
	'tools/make_db.awk is not staged beside' -- mtdb mtdb_none
