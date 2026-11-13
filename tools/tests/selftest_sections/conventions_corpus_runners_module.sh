# --------------- conventions: corpus runners, module programs, crash statuses
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# A CORPUS RUNNER THAT CANNOT REPLAY UNDER A MEMORY CHECKER (finding 113), and
# _CORPUS_RUNNERS held to the runners: one that takes --bin and --oracle and
# sweeps must take the memory options and be listed, and a listed one must
# exist and take them. The probes are moved out of the way after.
{
	cat "$WORK/cv_defs.bak"
	printf '\n_CORPUS_RUNNERS = [\n    "//tools:probe_corpus_mem.sh",\n    "//tools:probe_corpus_gone.sh",\n]\n'
} > "$WORK/cv/tools/defs.bzl"
_cr_opts='while [ $# -gt 0 ]; do\n\tcase "$1" in\n\t\t--bin) BIN="$2"; shift 2 ;;\n\t\t--oracle) O="$2"; shift 2 ;;\n%s\t\t*) exit 2 ;;\n\tesac\ndone\n'
_cr_mem='\t\t--sanitized) rl_mem_opt "$@"; shift "$RL_MEM_SHIFT" ;;\n'
for _cr in plain mem unlisted; do
	{
		printf '#!/bin/sh\nset -u\n. "$RL_LIB"\n'
		# shellcheck disable=SC2059 # the format is the option loop, kept in one place
		if [ "$_cr" = plain ]; then printf "$_cr_opts" ''; else printf "$_cr_opts" "$_cr_mem"; fi
		printf 'rl_sweep_next 5 || exit 1\n'
		[ "$_cr" = plain ] || printf 'rl_mem_run -- "$O"\n'
	} > "$WORK/cv/tools/probe_corpus_$_cr.sh"
done
# The four arms ask about one tree, so they read one run of it.
! st_mine || conv > "$WORK/cv.corpus" 2>&1
want_out "conventions: a corpus runner without the memory options is reported" \
	'probe_corpus_plain.sh replays a generated corpus and cannot replay it under a memory checker' -- \
	cv_saved "$WORK/cv.corpus"
want_out "conventions: ...and one _CORPUS_RUNNERS does not list" \
	'probe_corpus_unlisted.sh replays a corpus, and tools/defs_test.bzl' -- \
	cv_saved "$WORK/cv.corpus"
want_out "conventions: ...and a listed runner that is gone" \
	'_CORPUS_RUNNERS names tools/probe_corpus_gone.sh, which does not exist' -- \
	cv_saved "$WORK/cv.corpus"
want_broken_none "conventions: ...but a listed one with them is not" \
	'probe_corpus_mem.sh replays' -- \
	cv_saved "$WORK/cv.corpus"
rm -f "$WORK/cv/tools/probe_corpus_plain.sh" "$WORK/cv/tools/probe_corpus_mem.sh" \
	"$WORK/cv/tools/probe_corpus_unlisted.sh" "$WORK/cv.corpus"
# A CORPUS RUNNER'S GATE IS rl_gate: BSQ's and Rush 01's ran the differ
# themselves, and BSQ's handed the program no map, so its corpora SKIPped on
# every correct program. A listed runner that runs the variable --gate-differ
# sets is reported, and so is one that takes the option and never calls
# rl_gate; the one that hands the differ to rl_gate is not, nor one that
# calls it behind `if !`. A differ run behind a keyword is run by hand all
# the same: `if sh "$GD" ...` (kw), in a runner that calls rl_gate too.
{
	cat "$WORK/cv_defs.bak"
	printf '\n_CORPUS_RUNNERS = [\n    "//tools:probe_gate_hand.sh",\n    "//tools:probe_gate_lib.sh",\n'
	printf '    "//tools:probe_gate_if.sh",\n    "//tools:probe_gate_kw.sh",\n]\n'
} > "$WORK/cv/tools/defs.bzl"
for _cr in hand lib if kw; do
	{
		printf '#!/bin/sh\nset -u\n. "$RL_LIB"\nGD=""\n'
		printf 'while [ $# -gt 0 ]; do\n\tcase "$1" in\n\t\t--bin) BIN="$2"; shift 2 ;;\n'
		printf '\t\t--oracle) O="$2"; shift 2 ;;\n\t\t--gate-differ) GD="$2"; shift 2 ;;\n'
		printf '\t\t--sanitized) rl_mem_opt "$@"; shift "$RL_MEM_SHIFT" ;;\n'
		printf '\t\t*) exit 2 ;;\n\tesac\ndone\n'
		if [ "$_cr" = hand ]; then
			printf 'sh "$GD" --bin "$BIN" --expected x > /dev/null || exit 0\n'
		elif [ "$_cr" = if ]; then
			printf 'if ! rl_gate probe "$GD" "$BIN" x m; then :; fi\n'
		elif [ "$_cr" = kw ]; then
			printf 'if sh "$GD" --bin "$BIN" --expected x; then :; fi\nrl_gate probe "$GD" "$BIN" x m\n'
		else
			printf 'rl_gate probe "$GD" "$BIN" x m\n'
		fi
		printf 'rl_sweep_next 5 || exit 1\nrl_mem_run -- "$O"\n'
	} > "$WORK/cv/tools/probe_gate_$_cr.sh"
done
! st_mine || conv > "$WORK/cv.gate" 2>&1
want_out "conventions: a corpus runner that runs its gate itself is reported" \
	'tools/probe_gate_hand.sh runs its gate itself' -- cv_saved "$WORK/cv.gate"
want_out "conventions: ...and for never calling rl_gate" \
	'tools/probe_gate_hand.sh takes --gate-differ and never calls rl_gate' -- cv_saved "$WORK/cv.gate"
want_broken_none "conventions: ...but one that hands it to rl_gate is not" \
	'probe_gate_lib.sh runs its gate itself' -- cv_saved "$WORK/cv.gate"
want_broken_none "conventions: ...nor said never to call it" \
	'probe_gate_lib.sh takes --gate-differ' -- cv_saved "$WORK/cv.gate"
want_broken_none "conventions: ...nor one that calls it behind if !" \
	'probe_gate_if.sh takes --gate-differ' -- cv_saved "$WORK/cv.gate"
want_out "conventions: ...while a differ run behind if is run by hand" \
	'tools/probe_gate_kw.sh runs its gate itself' -- cv_saved "$WORK/cv.gate"
rm -f "$WORK/cv/tools/probe_gate_hand.sh" "$WORK/cv/tools/probe_gate_lib.sh" \
	"$WORK/cv/tools/probe_gate_if.sh" "$WORK/cv/tools/probe_gate_kw.sh" "$WORK/cv.gate"
cp "$WORK/cv_defs.bak" "$WORK/cv/tools/defs.bzl"
# ...AND EVERY OTHER RUNNER'S: the rule read _CORPUS_RUNNERS alone, so
# rust_diff, ref_compare, cycles_check and allocfail_check kept copies of
# their own, which drifted (a NO_SKIP line missing, perf_test's skipping on a
# gate that could not run). One no list names, running its differ itself, is
# reported, and so is allocfail_check, which the rule once let keep its copy.
# The two runners whose copy stays are named in the rule with why, and held
# to skipping on exit 1 alone. Each of the rule's two reports has a probe of
# its own: perf_test's never tests `-ge 2` and tests `-ne 0` (line 13),
# `-gt 0` (14) and `!= 0` (15), so each is reported by number, and the
# missing test too; valgrind_test's tests `-ge 2` first and skips on
# `-eq 1`, and is not reported at all.
printf '#!/bin/sh\nset -u\n. "$RL_LIB"\nGD=""\nwhile [ $# -gt 0 ]; do\n\tcase "$1" in\n\t\t--gate-differ) GD="$2"; shift 2 ;;\n\t\t*) exit 2 ;;\n\tesac\ndone\nsh "$GD" --bin x --expected x > /dev/null || exit 0\n' \
	> "$WORK/cv/tools/probe_gate_other.sh"
for _cr in perf_test:any allocfail_check:none valgrind_test:ge; do
	printf '#!/bin/sh\nset -u\n. "$RL_LIB"\nGD=""\nwhile [ $# -gt 0 ]; do\n\tcase "$1" in\n\t\t--gate-differ) GD="$2"; shift 2 ;;\n\t\t*) exit 2 ;;\n\tesac\ndone\nsh "$GD" --bin x --expected x > /dev/null\n_gate_rc=$?\n' \
		> "$WORK/cv/tools/${_cr%%:*}.sh"
	case "${_cr#*:}" in
		any)
			for _op in -ne -gt '!='; do
				printf 'if [ "$_gate_rc" %s 0 ]; then exit 0; fi\n' "$_op" >> "$WORK/cv/tools/${_cr%%:*}.sh"
			done ;;
		none)
			printf 'if [ "$_gate_rc" -eq 1 ]; then exit 0; fi\n' >> "$WORK/cv/tools/${_cr%%:*}.sh" ;;
		ge)
			printf 'if [ "$_gate_rc" -ge 2 ]; then :; elif [ "$_gate_rc" -eq 1 ]; then exit 0; fi\n' \
				>> "$WORK/cv/tools/${_cr%%:*}.sh" ;;
	esac
done
! st_mine || conv > "$WORK/cv.gate" 2>&1
want_out "conventions: a runner no list names that runs its gate itself is reported" \
	'tools/probe_gate_other.sh runs its gate itself' -- cv_saved "$WORK/cv.gate"
want_out "conventions: ...and a runner keeping its own copy that skips on any failure" \
	'tools/perf_test.sh keeps its own gate and skips on a status other than 1' -- \
	cv_saved "$WORK/cv.gate"
want_out "conventions: ...its test of -ne 0 by its line" '    tools/perf_test.sh:13' -- \
	cv_saved "$WORK/cv.gate"
want_out "conventions: ...its test of -gt 0" '    tools/perf_test.sh:14' -- \
	cv_saved "$WORK/cv.gate"
want_out "conventions: ...its test of != 0" '    tools/perf_test.sh:15' -- \
	cv_saved "$WORK/cv.gate"
want_out "conventions: ...and that it never tests -ge 2" \
	'tools/perf_test.sh: no test of "$_gate_rc" -ge 2' -- cv_saved "$WORK/cv.gate"
want_out "conventions: ...while allocfail_check, off the list, runs its gate itself" \
	'tools/allocfail_check.sh runs its gate itself' -- cv_saved "$WORK/cv.gate"
want_broken_none "conventions: ...but not one that skips on 1 alone" \
	'tools/valgrind_test.sh keeps its own gate' -- cv_saved "$WORK/cv.gate"
want_broken_none "conventions: ...nor reported for running it itself" \
	'tools/valgrind_test.sh runs its gate itself' -- cv_saved "$WORK/cv.gate"
rm -f "$WORK/cv/tools/probe_gate_other.sh" "$WORK/cv/tools/perf_test.sh" \
	"$WORK/cv/tools/allocfail_check.sh" "$WORK/cv/tools/valgrind_test.sh" "$WORK/cv.gate"
# A module builds no test program of its own: a cc_binary from a tests/ file in
# a module BUILD is reported, and so is --harness-fixture there.
cp "$WORK/cv/c-piscine/c-piscine-c-98/BUILD.bazel" "$WORK/cv_c98.bak"
printf 'cc_binary(\n    name = "x",\n    srcs = ["tests/ex00/x.c"],\n)\n' \
	>> "$WORK/cv/c-piscine/c-piscine-c-98/BUILD.bazel"
want_out "conventions: a module's cc_binary from a tests/ file is reported" \
	'c-98/BUILD.bazel builds its own binary from a tests/ file' -- \
	conv
cp "$WORK/cv_c98.bak" "$WORK/cv/c-piscine/c-piscine-c-98/BUILD.bazel"
want_broken_none "conventions: ...and without one nothing is" \
	'builds its own binary from a tests/ file' -- \
	conv
# A runner that reads a crash from a status above 128 -- which is also what
# `return (-1);` gives -- is reported, whatever its name: the debt list that
# once exempted nine runners by name (bsq_check.sh among them) is gone. The
# rule reads tools/*.sh and not tools/tests/, which is why the probes are
# written under $WORK/cv/tools/ and why this file may hold the pattern
# itself.
printf '#!/bin/sh\nset -u\nrc=0\nif [ "$rc" -gt 128 ]; then :; fi\n' \
	> "$WORK/cv/tools/probe_guess.sh"
cp "$WORK/cv/tools/probe_guess.sh" "$WORK/cv/tools/bsq_check.sh"
! st_mine || conv > "$WORK/cv.crash" 2>&1
want_out "conventions: a runner guessing a crash from its status is reported" \
	'probe_guess.sh reads how a program ended from its status' -- \
	cv_saved "$WORK/cv.crash"
want_out "conventions: ...under a name once on the debt list too" \
	'bsq_check.sh reads how a program ended from its status' -- \
	cv_saved "$WORK/cv.crash"
rm -f "$WORK/cv/tools/probe_guess.sh" "$WORK/cv/tools/bsq_check.sh" "$WORK/cv.crash"
