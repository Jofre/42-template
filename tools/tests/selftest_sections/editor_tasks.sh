# --------------------------------------------------------------- editor tasks
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# .vscode/tasks.json's default task, Run Test Task, runs the :basic suite of
# the module the open file is in, from the file's folder relative to the
# workspace (the editor's ${relativeFileDirname}). Its command is read out of
# the real file here -- the "-c" script of the default task, unescaped from
# JSON -- and run in a toy checkout with a bazel on PATH that prints what it
# was asked. It used to take the first two parts of the folder as the module,
# and a grouped project, cursus/<group>/<project>, got "Open a file of the
# module" from every folder of its own: the module is the nearest folder
# whose BUILD.bazel calls c_levels(, which is what declares :basic.
VT="$WORK/vt"
mkdir -p "$VT/bin" "$VT/ws/c-piscine/c-piscine-c-00/deliverable/ex00" \
	"$VT/ws/c-piscine/c-piscine-c-00/tests/ex00" \
	"$VT/ws/c-piscine-reloaded/c-piscine-reloaded/generators" \
	"$VT/ws/cursus/g/p/deliverable/src" "$VT/ws/cursus/g/p/tests/ex00" \
	"$VT/ws/tools"
printf '#!/bin/sh\necho "bazel $*"\n' > "$VT/bin/bazel"
chmod +x "$VT/bin/bazel"
for _vt_m in c-piscine/c-piscine-c-00 c-piscine-reloaded/c-piscine-reloaded cursus/g/p; do
	printf 'subject(\n)\n\nc_levels(\n    name = "levels",\n)\n' > "$VT/ws/$_vt_m/BUILD.bazel"
done
# A package inside a module, and a workspace root and a folder above it that
# declare no module of their own -- above the workspace is never a module,
# whatever BUILD.bazel it holds. So the folder above, and one beside the
# workspace, both call c_levels( here: a folder outside is refused by the
# task's guard and not because its BUILD.bazel is missing, each of '..' and
# '../*' by its own arm below.
printf 'filegroup(\n    name = "cases",\n)\n' > "$VT/ws/cursus/g/p/tests/BUILD.bazel"
printf 'filegroup(\n    name = "conventions_srcs",\n)\n' > "$VT/ws/BUILD.bazel"
printf 'c_levels(\n)\n' > "$VT/BUILD.bazel"
mkdir -p "$VT/elsewhere"
printf 'c_levels(\n)\n' > "$VT/elsewhere/BUILD.bazel"
awk '
	/^[[:blank:]]*\{[[:blank:]]*$/ { depth++; if (depth == 2) { def = 0; scr = ""; next_is = 0 } }
	depth == 2 && next_is { scr = $0; next_is = 0 }
	depth == 2 && /^[[:blank:]]*"-c",[[:blank:]]*$/ { next_is = 1 }
	/"isDefault"[[:blank:]]*:[[:blank:]]*true/ { def = 1 }
	/^[[:blank:]]*\}[[:blank:]]*,?[[:blank:]]*$/ {
		if (depth == 2 && def && scr != "") found = scr
		depth--
	}
	END {
		if (found == "") exit 1
		sub(/^[[:blank:]]*"/, "", found)
		sub(/",?[[:blank:]]*$/, "", found)
		out = ""
		for (i = 1; i <= length(found); i++) {
			c = substr(found, i, 1)
			if (c == "\\") { i++; c = substr(found, i, 1); if (c == "n") c = "\n"; else if (c == "t") c = "\t" }
			out = out c
		}
		print out
	}' "$TOOLS/../.vscode/tasks.json" > "$VT/script" 2> /dev/null || : > "$VT/script"
# The task runs under a time limit (bounded): a guard that lets a folder
# through whose dirname is itself -- '.', with its alternative cut -- loops
# for ever, and that is an exit 124 its arm names, not a shard's timeout. A
# grep on PATH before the real one writes down each file the task reads, so
# an arm can say a folder was refused before any BUILD.bazel was read: ''
# with its alternative cut is still refused, once the walk has read
# /BUILD.bazel and dirname has made it '.'. The real grep is found here, by
# an absolute path, before PATH changes: a stand-in that ran itself would
# look like a hang.
_vt_grep=$(command -v grep)
case $_vt_grep in
	/*)
		printf '#!/bin/sh\nfor _a; do :; done\nprintf "%%s\\n" "$_a" >> "%s"\nexec "%s" "$@"\n' \
			"$VT/probed" "$_vt_grep" > "$VT/bin/grep"
		chmod +x "$VT/bin/grep" ;;
	*) rm -f "$VT/bin/grep" ;;
esac
# vt_run's own faults, a fixture it could not build, exit 3: 2 is the task's
# refusal, which want_broken_without takes as it is, so an arm asking that
# nothing was read passed with no task run at all. Every want_* fails a 3.
vt_run() {  # vt_run FOLDER -- the default task, from FOLDER of the toy workspace
	[ -s "$VT/script" ] || { echo "vt_run: no default task with an sh -c script" >&2; return 3; }
	[ -x "$VT/bin/grep" ] || { echo "vt_run: grep is not an absolute path on PATH ($_vt_grep)" >&2; return 3; }
	: > "$VT/probed"
	( cd "$VT/ws" && PATH="$VT/bin:$PATH" && export PATH && bounded 20 "$SH" -c "$(cat "$VT/script")" sh "$1" )
	_vt_rc=$?
	awk '!seen[$0]++ { print "vt_run: the task read " $0 }' "$VT/probed"
	return "$_vt_rc"
}
vt_fault() (  # vt_fault -- each of vt_run's own faults, in a fixture of its own
	VT="$WORK/vt-none"
	mkdir -p "$VT/bin"
	: > "$VT/script"
	vt_run ''
	[ "$?" -eq 3 ] || return 1
	echo 'exit 0' > "$VT/script"
	vt_run ''
	[ "$?" -eq 3 ]
)
want_green "editor task: vt_run's own fixture fault is never a refusal" -- vt_fault
want_out "editor task: a grouped project runs its own :basic" \
	"bazel test //cursus/g/p:basic --test_output=errors" -- vt_run cursus/g/p/deliverable/src
want_out "editor task: ...from any folder of it, a package's too" \
	"bazel test //cursus/g/p:basic " -- vt_run cursus/g/p/tests/ex00
want_out "editor task: ...and from the module's own folder" \
	"bazel test //cursus/g/p:basic " -- vt_run cursus/g/p
want_out "editor task: a Piscine module runs its :basic" \
	"bazel test //c-piscine/c-piscine-c-00:basic " -- vt_run c-piscine/c-piscine-c-00/deliverable/ex00
want_out "editor task: ...and its tests' folder too" \
	"bazel test //c-piscine/c-piscine-c-00:basic " -- vt_run c-piscine/c-piscine-c-00/tests/ex00
want_out "editor task: ...and Reloaded's generators" \
	"bazel test //c-piscine-reloaded/c-piscine-reloaded:basic " -- \
	vt_run c-piscine-reloaded/c-piscine-reloaded/generators
want_broken "editor task: a folder in no module is refused" \
	"Open a file of the module" -- vt_run tools
want_broken "editor task: ...after reading the BUILD.bazel of each folder up" \
	"vt_run: the task read tools/BUILD.bazel" -- vt_run tools
want_broken "editor task: ...the group's folder, which is none" \
	"Open a file of the module" -- vt_run cursus/g
want_broken "editor task: ...the workspace's root" \
	"Open a file of the module" -- vt_run .
want_broken "editor task: ...a folder outside the workspace" \
	"Open a file of the module" -- vt_run ../elsewhere
want_broken "editor task: ...the folder just above it" \
	"Open a file of the module" -- vt_run ..
# An empty folder: the editor gives '.' for the workspace's root, never '',
# so this alternative is a guard against an editor that would. Without it the
# task reads /BUILD.bazel first, and then refuses as it should.
want_broken "editor task: ...an empty one" \
	"Open a file of the module" -- vt_run ''
want_broken_without "editor task: ...before reading any BUILD.bazel" \
	"vt_run: the task read" -- vt_run ''
# An absolute folder, even a module's: "//" before it is no label, and
# without the guard the walk up from one in no module never ends -- the
# parent of / is /. The arm points into a real module, so a missing guard
# makes it run bazel and go red rather than hang.
want_broken "editor task: ...and an absolute one, a module's too" \
	"Open a file of the module" -- vt_run "$VT/ws/cursus/g/p/deliverable/src"

