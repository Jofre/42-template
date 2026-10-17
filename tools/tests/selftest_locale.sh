# shellcheck shell=sh
# (sourced by selftest.sh and selftest_slow.sh, never executed -- this
#  directive tells shellcheck the dialect without implying a program.)
#
# selftest_locale.sh -- WHEN THE TEST LOCALE IS NOT INSTALLED.
#
# .bazelrc hands every test LC_ALL=en_US.UTF-8, and a machine without that
# locale is one the repo supports (docs/environment.md): every program there
# falls back to C. bash does too, but says so on stderr, when it starts and
# again after each command it runs with an LC_ALL=... prefix: "warning:
# setlocale: LC_ALL: cannot change locale". dash says nothing. Under the bash
# twins that line landed in what the arms read -- a runner's own text, the
# excerpt under a FAIL, a stderr that must stay empty -- and a dozen arms went
# red on such a machine with every runner right (TO VERIFY V338).
#
# So the shell that interprets the runners is asked once, before any arm:
# when it warns on a plain run and is quiet under LC_ALL=C, the locale it was
# handed is missing, and the replay runs under LC_ALL=C -- what every program
# on that machine runs under anyway -- saying so in one line. A shell quiet
# either way is left as it was, and so is one C does not quiet: that warning
# is not the locale's.
#
# st_locale SHELL: the probe, and the fallback. ST_TEST_LOCALE keeps the
# name of the locale the run was handed, for the words that name it
# ("... is not installed"), which LC_ALL says no longer once it is C.
st_locale() {
	ST_TEST_LOCALE=${LC_ALL:-${LANG:-}}
	[ -n "$("$1" -c 'LC_ALL=C true' 2>&1 < /dev/null)" ] || return 0
	[ -z "$(env LC_ALL=C "$1" -c 'LC_ALL=C true' 2>&1 < /dev/null)" ] || return 0
	LC_ALL=C
	export LC_ALL
	echo "selftest: ${ST_TEST_LOCALE:-the test locale} is not installed, and $1 warns of it on every run: replayed under LC_ALL=C, which every program here falls back to."
}
