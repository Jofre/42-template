# -------------------------------- conventions: the contract's table of keys
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# docs/reference.md's table of the subject contract is held to the keys a
# BUILD file can write: tools/subject.bzl's _UNIT_KEYS and the arguments of
# tools/defs.bzl's subject(), but name. cvkt holds the three files as the
# repository writes them, each cut to what the rule reads: the table has a
# row for every key in cvkt, one key too few and one too many in cvkt2,
# whose first column also has a cell with no key in backquotes; in cvkt3 a
# key tuple is split over two lines and in cvkt4 the table has gone, which
# the rule says rather than passing. A key may hold a digit (cvkt5's
# `goal2`, which has no row), and a tuple holding a name it cannot read
# (cvkt6's _NEEDS) is said, not read as the keys around it.
# cvkt_doc HEADING UNITS GOAL: the toy's docs/reference.md, its table's
# `units` and `goal` rows' first cells given.
cvkt_doc() {
	printf '%s\n' "$1" '' '| field | from the subject | what reads it |' '|---|---|---|'
	for _c in '`grader`' '`group`' '`exercises`' "$2" '`mandatory`, `mandatory_quote`' \
		'`memory_graded`' '`strict`' '`page`' '`dir`' '`files`' '`optional`' \
		'`provided`' '`linked`' '`functions`' "$3" '`allowed`, `variables`'; do
		printf '| %s | x | y |\n' "$_c"
	done
	printf '%s\n' '' '## Next'
}
mkdir -p "$WORK/cvkt/tools" "$WORK/cvkt/docs" "$WORK/cvkt/c-piscine/c-piscine-c-78"
cv_submit "c-piscine/c-piscine-c-78" > "$WORK/cvkt/tools/submit.sh"
: > "$WORK/cvkt/c-piscine/c-piscine-c-78/BUILD.bazel"
printf '%s\n' \
	'_KEYS = ("page", "dir", "files", "optional", "provided", "linked", "allowed", "variables", "strict", "functions")' \
	'_UNIT_KEYS = _KEYS + ("goal", "goal_quote")' > "$WORK/cvkt/tools/subject.bzl"
printf '%s\n' \
	'def subject(grader, group, exercises = None, units = None, strict = True, mandatory = None, mandatory_quote = None, memory_graded = None, name = "subject"):' \
	> "$WORK/cvkt/tools/defs.bzl"
cvkt_doc '### The subject contract' '`units`' '`goal`, `goal_quote`' > "$WORK/cvkt/docs/reference.md"
for _t in cvkt2 cvkt3 cvkt4 cvkt5 cvkt6; do
	mkdir -p "$WORK/$_t"
	cp -R "$WORK/cvkt/." "$WORK/$_t/"
done
printf '%s\n' \
	'_KEYS = ("page", "dir", "files", "optional", "provided", "linked", "allowed", "variables", "strict", "functions")' \
	'_UNIT_KEYS = _KEYS + ("goal", "goal_quote", "goal2")' > "$WORK/cvkt5/tools/subject.bzl"
printf '%s\n' \
	'_KEYS = ("page", "dir", "files", "optional", "provided", "linked", "allowed", "variables", "strict", "functions")' \
	'_UNIT_KEYS = _KEYS + ("goal", "goal_quote", _NEEDS)' > "$WORK/cvkt6/tools/subject.bzl"
cvkt_doc '### The subject contract' 'units' '`goal`, `goal_quote`, `target`' > "$WORK/cvkt2/docs/reference.md"
printf '%s\n' \
	'_KEYS = (' \
	'    "page", "dir", "files", "optional", "provided", "linked", "allowed", "variables", "strict", "functions")' \
	'_UNIT_KEYS = _KEYS + ("goal", "goal_quote")' > "$WORK/cvkt3/tools/subject.bzl"
cvkt_doc '### The contract' '`units`' '`goal`, `goal_quote`' > "$WORK/cvkt4/docs/reference.md"
if st_mine; then
	for _t in cvkt cvkt2 cvkt3 cvkt4 cvkt5 cvkt6; do
		env BUILD_WORKSPACE_DIRECTORY="$WORK/$_t" "$SH" "$TOOLS/conventions.sh" > "$WORK/$_t.out" 2>&1
	done
fi
want_broken_none "conventions: a contract table with a row for every key is quiet" \
	'FAIL' -- cvi_rule cvkt 'table of the subject contract'
want_out "conventions: ...a key with no row is reported" \
	'    units' -- cvi_rule cvkt2 'has no row for a key the contract takes'
want_out "conventions: ...a row for a key the contract does not take" \
	'    target' -- cvi_rule cvkt2 'has a row for a key the contract does not take'
want_out "conventions: ...a first cell with no key in backquotes" \
	'| units |' -- cvi_rule cvkt2 'names no key this rule can read'
want_out "conventions: ...a key tuple it cannot read is said, not passed" \
	'tools/subject.bzl: a line' -- cvi_rule cvkt3 "cannot be held to the contract's keys"
want_out "conventions: ...and so is a table that is not there" \
	'docs/reference.md: a table under' -- cvi_rule cvkt4 "cannot be held to the contract's keys"
want_out "conventions: ...a key holding a digit is a key" \
	'    goal2' -- cvi_rule cvkt5 'has no row for a key the contract takes'
want_out "conventions: ...and a tuple holding a name, not a key, is said" \
	'tools/subject.bzl: a line' -- cvi_rule cvkt6 "cannot be held to the contract's keys"
rm -rf "$WORK/cvkt" "$WORK/cvkt2" "$WORK/cvkt3" "$WORK/cvkt4" "$WORK/cvkt5" "$WORK/cvkt6" \
	"$WORK/cvkt.out" "$WORK/cvkt2.out" "$WORK/cvkt3.out" "$WORK/cvkt4.out" "$WORK/cvkt5.out" \
	"$WORK/cvkt6.out"

