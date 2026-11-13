# ------------------------------------------------------ 42's entry and installer
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# tools/42.sh hands over to python3 -I -B and the checkout's main.py, or, with
# no python3 new enough, prints the Bazel command 42 would have run; and
# tools/fortytwo/install.sh writes the `42` shim that finds the checkout around
# the folder it is typed in. A toy checkout (MODULE.bazel and the two scripts)
# and a stand-in python3 that prints what it was given: nothing here runs 42's
# Python, which //tools/tests:fortytwo_test covers. "Outside any checkout" is
# /, because the folders above $WORK can be an execroot, which holds this
# repository's MODULE.bazel and tools/42.sh.
FT42="$WORK/ft42"
mkdir -p "$FT42/bin" "$FT42/ws/tools/fortytwo" "$FT42/ws/a/b" "$FT42/other/tools" \
	"$FT42/other/x" "$FT42/it's ws/tools/fortytwo" "$FT42/mine/.local/bin"
for _d in "$FT42/ws" "$FT42/other" "$FT42/it's ws"; do
	: > "$_d/MODULE.bazel"
	cp "$TOOLS/42.sh" "$_d/tools/42.sh"
done
cp "$TOOLS/fortytwo/install.sh" "$FT42/ws/tools/fortytwo/install.sh"
cp "$TOOLS/fortytwo/install.sh" "$FT42/it's ws/tools/fortytwo/install.sh"
cat > "$FT42/bin/python3" <<'FT42_PY'
#!/bin/sh
# A stand-in python3. A version check against a floor of 3.1x passes unless
# FT42_OLD is set, and any other check fails, so a check that no longer
# compares the version (or names an older floor) turns every arm red.
case "$1" in
	-c) case "$2" in
		*"sys.exit(sys.version_info < (3, 1"[0-9]"))"*) [ -z "${FT42_OLD:-}" ] ;;
		*) exit 3 ;;
	esac ;;
	--version) echo "Python 3.8.10" ;;
	*) echo "python3 $*"; echo "FT_WS=$FT_WS"; echo "FT_CWD=$FT_CWD" ;;
esac
FT42_PY
chmod +x "$FT42/bin/python3"
printf '#!/bin/sh\necho mine\n' > "$FT42/mine/.local/bin/42"
# ft42_in DIR CMD... -- CMD in DIR, with the stand-in python3 first on PATH
# and none of `bazel run`'s variables, which 42.sh would take over $0's folder.
ft42_in() {
	(cd "$1" && shift && unset BUILD_WORKSPACE_DIRECTORY BUILD_WORKING_DIRECTORY &&
		PATH="$FT42/bin:$PATH" "$@")
}
want_out "42.sh: hands over to python3 -I -B and the checkout's main.py" \
	"python3 -I -B $FT42/ws/tools/fortytwo/main.py test ex03" -- \
	ft42_in "$FT42/ws/a/b" $SH "$FT42/ws/tools/42.sh" test ex03
want_out "42.sh: ...and passes the folder it was typed in" \
	"FT_CWD=$FT42/ws/a/b" -- ft42_in "$FT42/ws/a/b" $SH "$FT42/ws/tools/42.sh"
want_broken "42.sh: an old python3 is refused, and named" \
	"this machine has Python 3.8.10" -- \
	ft42_in "$FT42/ws" env FT42_OLD=1 $SH "$FT42/ws/tools/42.sh"
want_broken "42.sh: ...with the Bazel command that does without it" \
	"--test_tag_filters=lvl_basic,-manual 2>&1 | sh tools/first_red.sh" -- \
	ft42_in "$FT42/ws" env FT42_OLD=1 $SH "$FT42/ws/tools/42.sh"
want_out "install.sh: writes the shim" \
	"42: installed $FT42/home/.local/bin/42" -- \
	env HOME="$FT42/home" $SH "$FT42/ws/tools/fortytwo/install.sh"
want_green "install.sh: ...marked as its own" -- \
	grep -qF "# 42 shim, written by tools/fortytwo/install.sh" "$FT42/home/.local/bin/42"
want_out "shim: runs the checkout around the folder it is typed in" \
	"FT_WS=$FT42/other" -- ft42_in "$FT42/other/x" "$FT42/home/.local/bin/42" help
want_out "shim: ...and outside any, the checkout that installed it" \
	"FT_WS=$FT42/ws" -- ft42_in / "$FT42/home/.local/bin/42" help
want_green "install.sh: run again, it rewrites the shim and nothing else" -- \
	sh -c 'HOME="$1" '"$SH"' "$2" > /dev/null && [ "$(ls -A "$1/.local/bin")" = 42 ]' \
	_ "$FT42/home" "$FT42/ws/tools/fortytwo/install.sh"
want_out "install.sh: a 42 it did not write is left alone" \
	"is not 42's shim -- left alone" -- \
	env HOME="$FT42/mine" $SH "$FT42/ws/tools/fortytwo/install.sh"
want_green "install.sh: ...untouched" -- \
	sh -c '[ "$(cat "$1")" = "$(printf "#!/bin/sh\necho mine")" ]' _ "$FT42/mine/.local/bin/42"
env HOME="$FT42/q" $SH "$FT42/it's ws/tools/fortytwo/install.sh" > /dev/null 2>&1
want_out "shim: a checkout with a quote in its path falls back intact" \
	"FT_WS=$FT42/it's ws" -- ft42_in / "$FT42/q/.local/bin/42"

# Run by a relative path, as the README says to, under an exported CDPATH:
# cd looks `tools/..` up through it, and prints the folder it found, so a
# lookup of the checkout that does not empty CDPATH captured two lines (and,
# through an entry holding a tools/ of its own, another checkout).
want_out "42.sh: an exported CDPATH=. leaves one checkout path" \
	"python3 -I -B $FT42/ws/tools/fortytwo/main.py help" -- \
	ft42_in "$FT42/ws" env CDPATH=. $SH tools/42.sh help
want_out "42.sh: ...and one naming another checkout is not followed" \
	"python3 -I -B $FT42/ws/tools/fortytwo/main.py help" -- \
	ft42_in "$FT42/ws" env CDPATH="$FT42/other" $SH tools/42.sh help
want_out "install.sh: an exported CDPATH=. still installs the shim" \
	"42: installed $FT42/cdhome/.local/bin/42" -- \
	ft42_in "$FT42/ws" env HOME="$FT42/cdhome" CDPATH=. $SH tools/fortytwo/install.sh
