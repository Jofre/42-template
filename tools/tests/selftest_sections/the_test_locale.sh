# ------------------------------------------------------------ the test locale
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# st_locale (tools/tests/selftest_locale.sh, called above with $SH), over toy
# shells, so each branch is asked on any machine: one that warns of its
# locale unless LC_ALL is C runs the replay under C, and says which locale it
# lacked; one quiet either way, and one whose warning C does not stop, are
# left as they were. Its proof on bash itself is a run of :selftest_bash with
# the locale hidden from it, --test_env=LOCPATH=<an empty folder> (V338).
mkdir -p "$WORK/loc"
printf '#!/bin/sh\n[ "${LC_ALL:-}" = C ] || echo "toysh: warning: setlocale: LC_ALL: cannot change locale" >&2\n' \
	> "$WORK/loc/warns"
printf '#!/bin/sh\n:\n' > "$WORK/loc/quiet"
printf '#!/bin/sh\necho "toysh: warning: something else" >&2\n' > "$WORK/loc/other"
chmod +x "$WORK/loc/warns" "$WORK/loc/quiet" "$WORK/loc/other"
loc_try() {  # loc_try SHELL: st_locale over SHELL, handed xx_XX.UTF-8, and then LC_ALL
	(
		LC_ALL=xx_XX.UTF-8
		export LC_ALL
		# shellcheck source=tools/tests/selftest_locale.sh
		. "$TOOLS/tests/selftest_locale.sh"
		st_locale "$1"
		echo "then LC_ALL=[$LC_ALL]"
	)
}
want_out "the test locale: a shell that warns of it replays under C" \
	"then LC_ALL=[C]" -- loc_try "$WORK/loc/warns"
want_out "the test locale: ...saying which locale is missing" \
	"selftest: xx_XX.UTF-8 is not installed" -- loc_try "$WORK/loc/warns"
want_out "the test locale: ...a quiet shell is left as it was" \
	"then LC_ALL=[xx_XX.UTF-8]" -- loc_try "$WORK/loc/quiet"
want_broken_none "the test locale: ...and says nothing" \
	"is not installed" -- loc_try "$WORK/loc/quiet"
want_out "the test locale: ...and so is one whose warning C does not stop" \
	"then LC_ALL=[xx_XX.UTF-8]" -- loc_try "$WORK/loc/other"

