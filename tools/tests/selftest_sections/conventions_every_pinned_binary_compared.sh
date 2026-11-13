# ---------------------------- conventions: every pinned binary, compared
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# A binary the macros pin is one env_drift compares: every "@repo//:path"
# label a tools/*.bzl writes, in any shape. cvpin pins four: one held (its
# env_drift variable names a pins.tsv row), one as an attribute's default in
# another .bzl, one through Label(); the last two have no row, and the rule
# read one line shape of tools/defs.bzl alone, so neither was reported. The
# fourth (toyrowless) has its env_drift variable and no pins.tsv row, where
# the row alone decides: env_drift would print its rootpath and compare it
# with nothing. cvpin2
# has a row for env_drift and a defs.bzl that writes no pin: a search that
# reads nothing is reported as the search's fault, never a green.
mkdir -p "$WORK/cvpin/tools" "$WORK/cvpin2/tools"
for _t in cvpin cvpin2; do
	mkdir -p "$WORK/$_t/c-piscine/c-piscine-c-87"
	: > "$WORK/$_t/c-piscine/c-piscine-c-87/BUILD.bazel"
	cv_submit "c-piscine/c-piscine-c-87" > "$WORK/$_t/tools/submit.sh"
	printf 'toybin\tfetched\t1\ttoybin --version\tMODULE.bazel\tHERMETIC_TOYBIN\n' > "$WORK/$_t/tools/pins.tsv"
	printf 'sh_binary(\n    name = "env_drift",\n    env = {\n        "HERMETIC_TOYBIN": "$(rootpath @toy_repo//:usr/bin/toybin)",\n    },\n)\n' \
		> "$WORK/$_t/tools/BUILD.bazel"
done
{
	printf '_TOYBIN = "@toy_repo//:usr/bin/toybin"\n'
	printf '_TOYLABEL = Label("@toy_repo//:usr/bin/toylabel")\n'
} > "$WORK/cvpin/tools/defs.bzl"
printf 'toy = rule(attrs = {"_x": attr.label(\n    default = "@toy_repo//:usr/bin/toyother",\n)})\n' \
	> "$WORK/cvpin/tools/student_build.bzl"
printf '_TOY = "a pin written some other way"\n' > "$WORK/cvpin2/tools/defs.bzl"
printf '_TOYROWLESS = "@toy_repo//:usr/bin/toyrowless"\n' >> "$WORK/cvpin/tools/defs.bzl"
# And what env_drift starts each binary with (V243): @toy_lib's library and
# @toy_vg's tool directory are handed to the layers, so toylibbin, started
# with no _LIBS, and toyvg, with no _TOOLS, are reported; toylibok has its
# _LIBS, and toybin's repository hands over nothing.
{
	printf '_TOYLIB = "@toy_lib//:usr/lib/libtoy.so.1"\n'
	printf '_TOYLIBBIN = "@toy_lib//:usr/bin/toylibbin"\n'
	printf '_TOYLIBOK = "@toy_lib//:usr/bin/toylibok"\n'
	printf '_TOYVGTOOL = "@toy_vg//:usr/libexec/toy/tool-amd64"\n'
	printf '_TOYVG = "@toy_vg//:usr/bin/toyvg"\n'
} >> "$WORK/cvpin/tools/defs.bzl"
for _t in toylibbin toylibok toyvg; do
	printf '%s\tfetched\t1\t%s --version\tMODULE.bazel\tHERMETIC_%s\n' "$_t" "$_t" \
		"$(printf '%s' "$_t" | tr '[:lower:]' '[:upper:]')" >> "$WORK/cvpin/tools/pins.tsv"
done
{
	printf 'sh_binary(\n    name = "env_drift",\n    env = {\n'
	printf '        "HERMETIC_TOYBIN": "$(rootpath @toy_repo//:usr/bin/toybin)",\n'
	printf '        "HERMETIC_TOYROWLESS": "$(rootpath @toy_repo//:usr/bin/toyrowless)",\n'
	printf '        "HERMETIC_TOYLIBBIN": "$(rootpath @toy_lib//:usr/bin/toylibbin)",\n'
	printf '        "HERMETIC_TOYLIBOK": "$(rootpath @toy_lib//:usr/bin/toylibok)",\n'
	printf '        "HERMETIC_TOYLIBOK_LIBS": "$(rootpath @toy_lib//:usr/lib/libtoy.so.1)",\n'
	printf '        "HERMETIC_TOYVG": "$(rootpath @toy_vg//:usr/bin/toyvg)",\n'
	printf '    },\n)\n'
} > "$WORK/cvpin/tools/BUILD.bazel"
if st_mine; then
	env BUILD_WORKSPACE_DIRECTORY="$WORK/cvpin" "$SH" "$TOOLS/conventions.sh" > "$WORK/cvpin.out" 2>&1
	env BUILD_WORKSPACE_DIRECTORY="$WORK/cvpin2" "$SH" "$TOOLS/conventions.sh" > "$WORK/cvpin2.out" 2>&1
fi
cvpin_rule() { cvi_rule "$2" "$1"; }  # cvpin_rule HEADLINE TOY
want_out "conventions: a pin no pins.tsv row compares, as an attribute's default" \
	'@toy_repo//:usr/bin/toyother (no variable of //tools:env_drift is set to it)' -- \
	cvpin_rule 'is one env_drift never compares' cvpin
want_out "conventions: ...and one written through Label()" \
	'@toy_repo//:usr/bin/toylabel (no variable' -- cvpin_rule 'is one env_drift never compares' cvpin
want_out "conventions: ...and one env_drift sets a variable to, with no row" \
	'@toy_repo//:usr/bin/toyrowless (HERMETIC_TOYROWLESS names no row of tools/pins.tsv)' -- \
	cvpin_rule 'is one env_drift never compares' cvpin
want_broken_none "conventions: ...never one its row compares" \
	'toybin' -- cvpin_rule 'is one env_drift never compares' cvpin
want_broken_none "conventions: ...and a search that read pins is no search's fault" \
	'FAIL' -- cvpin_rule 'no label a tools/*.bzl pins was read' cvpin
want_out "conventions: a search for pins that reads none is reported" \
	'tools/pins.tsv has rows for env_drift' -- cvpin_rule 'no label a tools/*.bzl pins was read' cvpin2
want_out "conventions: env_drift starting a binary without its libraries" \
	'HERMETIC_TOYLIBBIN (a binary of @toy_lib, and no HERMETIC_TOYLIBBIN_LIBS)' -- \
	cvpin_rule 'without what its layers hand it' cvpin
want_out "conventions: ...or a valgrind without its tool directory" \
	'HERMETIC_TOYVG (a binary of @toy_vg, and no HERMETIC_TOYVG_TOOLS)' -- \
	cvpin_rule 'without what its layers hand it' cvpin
want_broken_none "conventions: ...never one started with them" \
	'TOYLIBOK' -- cvpin_rule 'without what its layers hand it' cvpin
want_broken_none "conventions: ...nor one whose repository hands over none" \
	'HERMETIC_TOYBIN ' -- cvpin_rule 'without what its layers hand it' cvpin

