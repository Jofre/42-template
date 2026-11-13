# -------------------------------------------------------- macro_fixtures_test
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# //tools/tests:macro_fixtures_test holds what the macros emitted for the
# fixture packages to the .expected files beside them, and every contract
# check's message to contract_problems.expected. Its own arms run on the
# real packages, where every listing agrees; these run it on toy inputs
# written here, where each listing is wrong in one way, as units parity's
# section runs its runner. The programs the real run builds are not here,
# so each of their checks fails: the arms read the lines about the
# listings alone.
MF=$(CDPATH='' cd "$(dirname "$ST_SELF")" && pwd)/macro_fixtures_test.sh
mkdir -p "$WORK/mf/empty"
printf '%s\n' '# 1 tests, 0 red; measured by hand' > "$WORK/mf/BUILD.bazel"
printf 'ex00_output diff_output.sh\n' > "$WORK/mf/layers.txt"
: > "$WORK/mf/empty/layers.txt"
printf 'x\n' > "$WORK/mf/one.txt"
# The contract cases: a listed twice and b left out, so the two counts
# agree; a.b, whose dot a pattern reads as any byte, listed after axb,
# whose line that pattern finds first.
printf '%s\n' 'a: missing turnin' 'b: allowed list is empty' 'axb: wrong' 'a.b: right' \
	> "$WORK/mf/problems.txt"
printf '%s\n' '# case<TAB>words' "$(printf 'a\tmissing turnin')" "$(printf 'a\tmissing turnin')" \
	"$(printf 'axb\twrong')" "$(printf 'a.b\tright')" > "$WORK/mf/problems.expected"
# A harness listing and a knobs listing that differ from their .expected.
printf 'ex00_bin prototype_test=ex00_prototype\n' > "$WORK/mf/harnesses.txt"
printf 'ex00_bin UNTAGGED\n' > "$WORK/mf/harnesses.expected"
printf 'knob target asked holds\n' > "$WORK/mf/knobs.txt"
printf 'knob target asked other\n' > "$WORK/mf/knobs.expected"
# mf_with PROBLEMS EXPECTED [OPTION...] -- the runner over the toys above,
# every option but --lines given, the contract cases PROBLEMS held to
# EXPECTED, then OPTIONs: the top package, whose listing agrees with
# itself, and ./empty, whose listing and .expected are empty.
mf_with() {
	_mf_p=$1; _mf_e=$2; shift 2
	"$SH" "$MF" --dir "$WORK/mf" --diff-output "$TOOLS/diff_output.sh" \
		--ex14-files-names "$WORK/mf/one.txt" \
		--contract-problems "$_mf_p" --contract-expected "$_mf_e" \
		--toy "$WORK/mf" "$WORK/mf/layers.txt" "$WORK/mf/layers.txt" \
		--toy "$WORK/mf/empty" "$WORK/mf/empty/layers.txt" "$WORK/mf/empty/layers.txt" \
		--harnesses "$WORK/mf/harnesses.txt" --expected-harnesses "$WORK/mf/harnesses.expected" \
		--shell-tags "$WORK/mf/one.txt" --redirect-args "$WORK/mf/one.txt" \
		--argvguard-builds "$WORK/mf/one.txt" \
		--knobs "$WORK/mf/knobs.txt" --expected-knobs "$WORK/mf/knobs.expected" "$@"
}
# mf_bare [OPTION...] -- mf_with over the contract toys above.
mf_bare() {
	mf_with "$WORK/mf/problems.txt" "$WORK/mf/problems.expected" "$@"
}
# mf_run [OPTION...] -- mf_bare, with --lines.
mf_run() {
	mf_bare --lines "$WORK/mf/one.txt" x "$@"
}
want_out   "macro_fixtures_test: an empty listing of tests is refused" \
	'its listing is empty' -- once mf_run
want_broken_none "macro_fixtures_test: ...never passed as 0 tests" \
	'(0 tests)' -- once mf_run
want_out   "macro_fixtures_test: a contract case left out is named" \
	'not listed: b;' -- once mf_run
want_out   "macro_fixtures_test: ...and one listed twice" \
	'listed twice: a' -- once mf_run
want_broken_none "macro_fixtures_test: a case name's dot matches only itself" \
	'it says: wrong' -- once mf_run
# A contract listing with no case in it compares nothing, and is never ok.
# With :contract_problems empty, the compare once read contract_problems.expected
# as the cases emitted, and named its rows' text as cases left out of it.
: > "$WORK/mf/no_case.txt"
printf '# case<TAB>words\n' > "$WORK/mf/no_case.expected"
printf 'a\tfoo: bar\n' > "$WORK/mf/foo.expected"
want_out   "macro_fixtures_test: no contract case on either side is refused" \
	'its listing is empty: :contract_problems printed no case' -- \
	mf_with "$WORK/mf/no_case.txt" "$WORK/mf/no_case.expected" --lines "$WORK/mf/one.txt" x
want_broken_none "macro_fixtures_test: ...and .expected's rows are never read as cases" \
	'not listed: a' -- \
	mf_with "$WORK/mf/no_case.txt" "$WORK/mf/foo.expected" --lines "$WORK/mf/one.txt" x
want_out   "macro_fixtures_test: an .expected with no case is refused" \
	'its listing is empty: contract_problems.expected has no case' -- \
	mf_with "$WORK/mf/problems.txt" "$WORK/mf/no_case.expected" --lines "$WORK/mf/one.txt" x
want_out   "macro_fixtures_test: the harnesses' recipe writes the file with cat" \
	'harnesses.expected   (cat, not cp' -- once mf_run
want_out   "macro_fixtures_test: ...and so does the knobs'" \
	'knobs.expected   (cat, not cp' -- once mf_run
# Every option is required, --lines among them, and a run without one is
# refused before it checks anything: --lines was left out of the guard,
# and a run without it printed the rows above its check and then stopped.
# Here ex14's row, which comes before it, has a name list that passes.
printf 'srcs/toy.c\n' > "$WORK/mf/ex14.txt"
want_broken_without "macro_fixtures_test: a run without --lines is refused before any row" \
	' ok' -- mf_bare --ex14-files-names "$WORK/mf/ex14.txt"
# What a program printed is shown through the one renderer. The toy
# package ./prog holds one program, ex00_bin, a link to cat: an ELF that
# prints its stdin, here a tab and a carriage return.
mkdir -p "$WORK/mf/prog"
cp "$WORK/mf/BUILD.bazel" "$WORK/mf/prog/"
ln -s "$(command -v cat)" "$WORK/mf/prog/ex00_bin"
printf 'a\tb\r' > "$WORK/mf/tab_cr.txt"
mf_prog() {  # mf_run over ./prog, the toy's output on its stdin
	mf_run --dir "$WORK/mf/prog" < "$WORK/mf/tab_cr.txt"
}
want_out   "macro_fixtures_test: a program's output is shown through the renderer" \
	"it printed 'a\\tb\\x0d', not '0'" -- mf_prog
# ...and so is what the output runner said about an escaped reading. These
# rows quote its log, written in the renderer's notation already, so only a
# runner gone wrong puts a raw byte there: two stand-ins for it, beside a
# copy of the real standin.sh, print a tab and a carriage return. Each passes its own
# fixture by no means (exit 3), and fails the wrong row with a backslash
# doubled (fake_bytes) or under a legend that names one (fake_legend).
for _d in fake_bytes fake_legend; do
	mkdir -p "$WORK/mf/$_d"
	# A copy, never a link: $TOOLS is relative under Bazel, and a link
	# to it from the scratch folder leads nowhere.
	cp "$TOOLS/standin.sh" "$WORK/mf/$_d/standin.sh"
	cat > "$WORK/mf/$_d/diff_output.sh" <<'FAKE_EOF'
case "$*" in *esc_wrong.txt*) ;; *) printf 'a\tb\r\n'; exit 3 ;; esac
case "$0" in
	*/fake_bytes/*) printf '\\\\x00\tb\r\n' ;;
	*) printf 'x00 one backslash\tb\r\n' ;;
esac
exit 1
FAKE_EOF
done
want_out   "macro_fixtures_test: an escaped reading's log is shown through the renderer" \
	'exit 3: a\tb\x0d$' -- once mf_run --diff-output "$WORK/mf/fake_bytes/diff_output.sh"
want_out   "macro_fixtures_test: ...and so is its wrong row" \
	'\\\\x00\tb\x0d$' -- once mf_run --diff-output "$WORK/mf/fake_bytes/diff_output.sh"
want_out   "macro_fixtures_test: ...and its legend" \
	'the legend: x00 one backslash\tb\x0d$' -- mf_run --diff-output "$WORK/mf/fake_legend/diff_output.sh"
