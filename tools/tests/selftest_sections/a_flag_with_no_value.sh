# ------------------------------------------------------- a flag with no value
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# `--src` at the end of the command line reads $2 under `set -u`, and until the
# guard reached every arm that was a RAW SHELL ERROR whose status depended on
# the shell: dash exits 2 ("2: parameter not set"), bash exits 1 ("$2: unbound
# variable"). Both were measured on this tree before the fix.
#
# That 1 is the problem, and it is worse under :selftest_bash than anywhere
# else: want_red above treats exit 1 as "the runner detected the thing it exists
# to detect", so on bash a runner that had merely FALLEN OVER on its own
# argument list was scored as a correct red. The one target written to catch
# shell divergence was the one blind to it.
#
# Both halves are asserted -- status 2 AND a message naming the flag -- because
# a refusal nobody can act on is only half of one. These arms run under both
# shells, which is the whole point.
for _spec in symbols_test:--src compile_check:--src ilp32_test:--clues \
	asan_check:--hdr prototype_check:--src files_test:--required \
	header_check:--main shell_test:--env valgrind_test:--gate-stdin \
	rush01_check:--oracle-fn argv_check:--valgrind file_check:--stderr-ignored; do
	_r=${_spec%%:*}
	_flag=${_spec#*:}
	want_broken "need: $_r refuses $_flag with no value, naming it" \
		"$_flag needs a value" -- \
		"$SH" "$TOOLS/$_r.sh" "$_flag"
done

