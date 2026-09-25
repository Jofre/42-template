#!/bin/sh
# =============================================================================
# env-audit.sh — capture the 42-machine environment for comparison with the
# devcontainer / Bazel test environment.
#
# WHY: a shell exercise can pass locally (Bazel) and still be KO on delivery.
# That signature ("green locally, red on the Moulinette") is usually environment
# drift: different OpenSSH, libmagic (`file`), findutils, /bin/sh,
# locale, or umask on the real 42 machines. This script records those, and
# PROBES the tool behaviours the shell checks lean on -- ssh-keygen's key types
# and fingerprint format, which find predicates exist, whether `file` honours a
# custom magic file -- with neutral inputs of its own.
#
# It audits the machine, never an exercise. An earlier version ran three
# exercises' answers here to watch them work; that put answers in a file the
# public template ships, and it measured the answer as much as the machine.
#
# SAFETY: read-only w.r.t. your account. It never reads ~/.ssh, never prints a
# private key, and does all work inside a fresh `mktemp -d` that is removed on
# exit. It captures tool *versions* and *behaviors* only — no secrets.
#
# USAGE (from the repo root, on a 42 machine that has this repo cloned):
#   sh tools/env-audit.sh                 # write + print the report only
#   sh tools/env-audit.sh --commit        # also commit the report file
#   sh tools/env-audit.sh --commit --push # also push it on branch env-audit-42
#
# A BARE SCRIPT FIRST, and a Bazel target second. `bazel run //tools:env_audit`
# works and takes the same flags after `--`, but the plain `sh` form is the one
# that matters: this runs on a machine where nothing is set up yet -- that is the
# whole point of it -- and requiring Bazel to ask "what does this box have?"
# would mean installing something before you could find out what was installed.
# It needs a shell and git, nothing else.
#
# (Do not confuse it with //tools:env_drift, which is the other half: this one
# CAPTURES what a machine has, env_drift COMPARES a machine against
# tools/pins.tsv. Audit on the campus box, drift anywhere.)
#
# The report lands in tools/env-reports/<hostname>.txt. With --push you can then,
# back in the devcontainer, run:  git fetch origin env-audit-42
# =============================================================================

# conventions: no-require -- this script PROBES the host, so a missing tool is a
# FINDING to record, not a reason to refuse to run. Every other script in tools/
# declares its PATH commands and exits 2 when one is absent (see
# diff_output.sh); here that would invert the purpose: the one machine whose
# toolchain most needs capturing is the unusual one, and this is the script sent
# to capture it. It reports what it found and what it did not, and exits 0.
#
# `set -u` is left off for the same reason -- it walks a long list of optional
# probes and an absent one must read as absent, not as an abort.

DO_COMMIT=0
DO_PUSH=0
for a in "$@"; do
    case "$a" in
        --commit) DO_COMMIT=1 ;;
        --push)   DO_COMMIT=1; DO_PUSH=1 ;;
        -h|--help)
            sed -n '2,26p' "$0"; exit 0 ;;
        *) echo "unknown option: $a (try --help)" >&2; exit 2 ;;
    esac
done

# ---- locate repo root & report path -----------------------------------------
# Under `bazel run` the cwd is the runfiles tree, not the workspace, so git would
# either find nothing or find the wrong repository. Every run target in this repo
# handles that the same way; this one has to as well now that it is one.
if [ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]; then
    cd "$BUILD_WORKSPACE_DIRECTORY" || {
        echo "env-audit.sh: cannot enter '$BUILD_WORKSPACE_DIRECTORY'" >&2
        exit 1
    }
fi
ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$ROOT" ]; then
    echo "Not inside a git repository — run this from the cloned 42 repo." >&2
    exit 1
fi
HOST=$(hostname 2>/dev/null || uname -n 2>/dev/null || echo unknown)
HOST=$(printf '%s' "$HOST" | tr -c 'A-Za-z0-9._-' '_')
STAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unknown-time)
REPORT_DIR="$ROOT/tools/env-reports"
REPORT="$REPORT_DIR/$HOST.txt"
mkdir -p "$REPORT_DIR"

# ---- scratch space (auto-cleaned) -------------------------------------------
WORK=$(mktemp -d 2>/dev/null || mktemp -d -t envaudit)
trap 'rm -rf "$WORK"' EXIT INT TERM

# ---- tiny helpers -----------------------------------------------------------
h()  { printf '\n### %s\n' "$1"; }                         # section header
kv() { printf '%-22s %s\n' "$1:" "$2"; }                   # key: value
cap(){ # cap "label" cmd... — run cmd, show first line(s) or (not available)
    _lbl="$1"; shift
    _out=$("$@" 2>&1)
    if [ -n "$_out" ]; then
        printf '%-22s %s\n' "$_lbl:" "$(printf '%s' "$_out" | head -n 2 | tr '\n' '|')"
    else
        printf '%-22s %s\n' "$_lbl:" "(not available)"
    fi
}
# vline — the line of a --version output that carries the version: the first
# with a dotted number, else the first with any content. Not `head -n 1`: perl
# prints a BLANK line first, so a pinned tool was recorded as "(no --version)".
# The same rule as first_line() in env_drift.sh, so both read the same string.
vline() {
    awk '
        !seen && NF { seen = 1; fallback = $0 }
        /[0-9]+\.[0-9]+/ { print; found = 1; exit }
        END { if (!found) print fallback }
    '
}

# pin() — everything needed to write a hermetic Bazel pin for one tool.
#
# The repo is moving to fetching every tool through Bazel rather than trusting
# whatever the host happens to carry, because a campus machine is not ours to
# configure: different boxes carry different shells and tool versions, and a
# check whose answer depends on which one you sat at is not a check. But the
# pins have to MATCH campus, not merely be fixed -- the Moulinette compiles with
# the campus cc, so a hermetic toolchain that differs from it would test the
# wrong thing.
#
# So this records, per tool: the resolved path, the version string, the sha256
# of the actual binary, and the distro package that provided it. That is exactly
# what a MODULE.bazel pin needs, gathered from a real campus box rather than
# assumed. Run this there and the pins can be written from the report.
pin() {
    _cmd="$1"
    _p=$(command -v "$_cmd" 2>/dev/null)
    if [ -z "$_p" ]; then
        printf '%-22s %s\n' "$_cmd:" "(not on PATH)"
        return
    fi
    _real=$(readlink -f "$_p" 2>/dev/null || printf '%s' "$_p")
    _ver=$("$_cmd" --version 2>&1 | vline)
    [ -n "$_ver" ] || _ver="(no --version)"
    _sha=$(sha256sum "$_real" 2>/dev/null | cut -d" " -f1)
    [ -n "$_sha" ] || _sha="(unreadable)"
    _pkg=$(dpkg -S "$_real" 2>/dev/null | cut -d: -f1 | head -n 1)
    if [ -n "$_pkg" ]; then
        _pkgv=$(dpkg-query -W -f='${Version}' "$_pkg" 2>/dev/null)
        _pkg="$_pkg $_pkgv"
    else
        _pkg="(not from a package)"
    fi
    printf '%-22s %s\n' "$_cmd:" "$_ver"
    printf '%-22s   path   %s\n' "" "$_real"
    printf '%-22s   sha256 %s\n' "" "$_sha"
    printf '%-22s   pkg    %s\n' "" "$_pkg"

    # WHAT PATH RESOLVES TO IS NOT WHAT IS INSTALLED, and conflating the two
    # made this report actively misleading once. The 2026-08-09 audit showed
    # nm, ar and objdump coming from ~/.linuxbrew ("not from a package"), which
    # reads as "campus has no binutils" -- and that reading is wrong, because a
    # Homebrew directory earlier on PATH shadows the system copy rather than
    # replacing it. The two cases are indistinguishable from `command -v` alone,
    # and they mean opposite things for a pin: the Moulinette does not see a
    # student's PATH, so what matters is the SYSTEM tool.
    #
    # ar in particular cannot be missing -- c-09 and c-10 turn in a Makefile
    # that must build a library, so a campus box without ar could not grade its
    # own subject.
    for _sys in /usr/bin/"$_cmd" /bin/"$_cmd"; do
        [ -x "$_sys" ] || continue
        # Compare RESOLVED paths. On a merged-/usr system /bin is a symlink to
        # /usr/bin, so a string compare reported /bin/gdb as "shadowing"
        # /usr/bin/gdb -- the same file, announced as a conflict.
        _sysreal=$(readlink -f "$_sys" 2>/dev/null || printf '%s' "$_sys")
        [ "$_sysreal" = "$_real" ] && continue
        _sver=$("$_sys" --version 2>&1 | vline)
        _spkg=$(dpkg -S "$_sys" 2>/dev/null | cut -d: -f1 | head -n 1)
        [ -n "$_spkg" ] || _spkg="(not from a package)"
        printf '%-22s   SHADOWED: system copy at %s\n' "" "$_sys"
        printf '%-22s     version %s\n' "" "${_sver:-(no --version)}"
        printf '%-22s     pkg     %s\n' "" "$_spkg"
        break
    done
}

# =============================================================================
# Everything below is written to $REPORT (and echoed at the end).
# =============================================================================
{
printf '=============================================================\n'
printf ' 42 ENVIRONMENT AUDIT\n'
printf '=============================================================\n'
kv "host"        "$HOST"
kv "generated"   "$STAMP"
kv "repo HEAD"   "$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null) ($(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null))"

h "System"
kv "uname -a"    "$(uname -a 2>/dev/null)"
kv "os-release"  "$( . /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown}" )"
kv "locale LANG" "${LANG:-unset}"
cap "locale" locale
kv "umask"       "$(umask)"
kv "\$SHELL"     "${SHELL:-unset}"
kv "/bin/sh ->"  "$(ls -l /bin/sh 2>/dev/null | sed 's/.*-> //') $( (readlink -f /bin/sh) 2>/dev/null )"
kv "PATH"        "$PATH"

h "Hermetic pin data"
# One block per tool the harness runs. Everything here is what a MODULE.bazel
# pin needs; see pin() above for why it is gathered rather than assumed.
#
# Ordered by how much a mismatch costs. cc/clang/gcc first: the Moulinette
# compiles with the campus cc, so those pins decide whether the suite tests the
# same compiler the grade comes from. make next -- c-09, c-10 and rush-02 test
# the STUDENT'S Makefile, so make is part of what is being graded -- then diff,
# whose unified output two runners hand straight to a student (progname_test.sh
# and shell_test.sh; the C output and diff LAYERS do their own comparison and
# never shell out to it). Then the binutils the symbols and
# forbidden layers shell out to, then norminette, then valgrind and the perl its
# callgrind_annotate runs on, then the shell every runner is interpreted by.
# perl, gdb and lldb-12 are here because tools/pins.tsv pins them, and a pin
# nothing captures is a pin nobody can re-check: env_drift would report drift on
# a box whose actual version this report never recorded. Plain `lldb` beside
# lldb-12 for the same reason clang sits beside clang-12: it is the name a
# student types, and the exam guide says campus answers to it.
for _t in cc clang clang-12 gcc gcc-10 make diff ar nm objdump norminette \
          valgrind perl gdb lldb-12 lldb sh bash dash zsh; do
    pin "$_t"
done

h "Shells actually installed"
# tools/setup.sh writes its PATH and cache variables into a shell profile, and it
# can only write the RIGHT one if we know what the box carries. Until this ran on
# a campus machine that was a guess: the list above probes sh/bash/dash because
# those are what the RUNNERS need, which is a different question from what a
# student's login shell is. /etc/shells is the box's own answer.
for _s in bash zsh fish tcsh csh ksh mksh dash ash; do
    _p=$(command -v "$_s" 2>/dev/null) && kv "shell $_s" "$_p"
done
kv "login shell (passwd)" "$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7)"
cap "/etc/shells" cat /etc/shells

h "Storage, for tools/setup.sh"
# setup.sh puts Bazel's state in /goinfre/$USER when /goinfre exists, and needs to
# know it can. Deliberately NOT /sgoinfre: that is network-attached, and a shared
# drive used as a build cache is both more closely watched and the wrong tool --
# if a shared cache is ever wanted, it should be a real remote cache (buildbarn or
# similar), not a filesystem several machines write to at once. Owner's call,
# 2026-08-09.
#
# INODES matter as much as bytes here, and that is not obvious: Bazel keys its
# output base on the workspace path, so every clone and worktree is a full tree
# of small files. Eight of them exhausted a 16.7-million-inode filesystem on the
# development box while 122 GB was still free, and the build failed with "no
# space left on device" -- a true message about the wrong resource.
for _d in /goinfre /sgoinfre "$HOME" /tmp; do
    [ -d "$_d" ] || continue
    kv "df -h $_d" "$(df -h "$_d" 2>/dev/null | awk 'NR==2 {print $2" total, "$4" free ("$5" used)"}')"
    kv "df -i $_d" "$(df -i "$_d" 2>/dev/null | awk 'NR==2 {print $2" inodes, "$4" free ("$5" used)"}')"
done
cap "quota" quota -s

h "Tool versions"
# dash/POSIX sh has no --version; report the /bin/sh implementation (+ pkg version if any)
kv  "sh (/bin/sh)"  "$(readlink -f /bin/sh 2>/dev/null | sed 's#.*/##')$(dpkg-query -W -f=' ${Version}' dash 2>/dev/null)"
cap "bash"       bash --version
cap "ssh"        ssh -V
# ssh-keygen has no --help; list supported key algorithms instead (ed25519 matters for ex03)
cap "ssh key algos" ssh -Q key
cap "file"       file --version
cap "find"       find --version
cap "tar"        tar --version
cap "patch"      patch --version
cap "diff"       diff --version
# The C library, which no earlier audit captured -- and it is the one thing here
# that is not a tool but the RUNTIME every deliverable links against. Only eight
# libc symbols are authorised across the whole Piscine and their behaviour is
# fixed by POSIX, so this is not expected to matter; capturing it is how "campus
# moved to a new Ubuntu" stops being invisible.
cap "glibc"      ldd --version
# The language standard each compiler assumes when nobody says. Not a version,
# and the thing that decides whether five of c-12's contracts accept correct
# code: under gnu17 an empty parameter list means "unspecified", under C23 it
# means "(void)". The suite pins -std=gnu17; the Moulinette passes no -std at
# all, so what is captured here is what the grade is actually compiled under.
cap "cc default std"    sh -c 'cc -dM -E -x c /dev/null 2>/dev/null | grep -E "__STDC_VERSION__|__STRICT_ANSI__"'
cap "gcc-10 default std" sh -c 'gcc-10 -dM -E -x c /dev/null 2>/dev/null | grep -E "__STDC_VERSION__|__STRICT_ANSI__"'
cap "git"        git --version
cap "gcc"        gcc --version
cap "cc"         cc --version
cap "make"       make --version
# GNU and BSD find accept different predicates and word some of their output
# differently, and the shell checks run students' find commands -- so which
# one this box has is recorded, and the predicate matrix below says the rest.
if find --version >/dev/null 2>&1; then
    kv "find flavor" "GNU findutils"
else
    kv "find flavor" "non-GNU (BSD/busybox?) — predicates and actions may differ"
fi

# -----------------------------------------------------------------------------
h "ssh-keygen — key types and fingerprint format"
# Which key types this OpenSSH offers, and how it prints a fingerprint: the
# shell-00 ex03 check reads the type and the bit count out of `ssh-keygen -l`,
# and that output is what changes between OpenSSH versions. Its SHAPE --
# "<bits> <hash> <comment> (<TYPE>)" -- is the same for every key type, so the
# probe below reads a fixed public test vector of a DIFFERENT type from the one
# ex03 asks for (ECDSA P-384; its private half was never kept): it records how
# this OpenSSH prints a fingerprint without shipping anything ex03 would accept.
# Nothing here generates a key.
kv "ed25519 offered" "$(ssh -Q key 2>/dev/null | grep -qx ssh-ed25519 && echo yes || echo NO)"
printf '%s\n' 'ecdsa-sha2-nistp384 AAAAE2VjZHNhLXNoYTItbmlzdHAzODQAAAAIbmlzdHAzODQAAABhBJprqWvILLKF/BrlGXOebgugSDwE62UX7QcYL0U/VnThzSyUodCAKPfPoC3otJV/EQiuR8RYA7gTC6NQX/qgpRI2+UHQhjheaviA4xgkQSWO0zsRgdUZJfBkfacaI5xa+g== test-vector' \
    > "$WORK/vector.pub"
info=$(ssh-keygen -l -f "$WORK/vector.pub" 2>/dev/null)
kv "ssh-keygen -l on the vector" "${info:-(failed)}"
kv "  type, read as the check reads it" "$(printf '%s' "$info" | sed -n 's/.*(\([^)]*\)).*/\1/p')   (vector's own: ECDSA)"
kv "  bits, read as the check reads it" "$(printf '%s' "$info" | awk '{print $1}')   (vector's own: 384)"

# -----------------------------------------------------------------------------
h "find — which predicates exist"
# A capability matrix, run against a scratch directory with a name that matches
# nothing, so no predicate here ever acts on a file. GNU and BSD find differ in
# what they accept; the flavor is recorded under "Tool versions" above. The
# list is a broad sample of find's predicates, POSIX ones and extensions alike,
# and no exercise's command.
mkdir -p "$WORK/findprobe" && : > "$WORK/findprobe/keep"
for _p in "-maxdepth 1" "-mindepth 1" "-empty" "-newer $WORK/findprobe/keep" \
          "-print0" "-regex x" "-iname x" "-path x" "-size -1k" "-perm -u+r" \
          "-links 1" "-mmin -5"; do
    # shellcheck disable=SC2086
    if find "$WORK/findprobe" -name no-such-name-42 $_p >/dev/null 2>&1; then
        kv "  $(printf '%s' "$_p" | sed "s#$WORK/findprobe/keep#FILE#")" "supported"
    else
        kv "  $(printf '%s' "$_p" | sed "s#$WORK/findprobe/keep#FILE#")" "NOT supported"
    fi
done
kv "  scratch file survived" "$([ -f "$WORK/findprobe/keep" ] && echo yes || echo NO)"

# -----------------------------------------------------------------------------
h "file / libmagic — a custom magic file"
# Whether `file -m` loads a magic file of your own and matches with it: the
# shell-00 ex09 check runs the turn-in exactly that way. The entry below is a
# neutral one of this script's, deliberately unlike anything an exercise asks
# for: a number test on the file's first four bytes (read big-endian, they
# spell "AUDI").
printf '0\tbelong\t0x41554449\taudit probe data\n' > "$WORK/probe.magic"
printf 'AUDIT-PROBE and some bytes\n' > "$WORK/probe.sample"
kv "file -m, custom magic" "$(file -b -m "$WORK/probe.magic" "$WORK/probe.sample" 2>&1 | head -n1)   (want: audit probe data)"
kv "file -C, compile it" "$( (cd "$WORK" && file -C -m probe.magic) >/dev/null 2>&1 && echo ok || echo FAILED)"

# -----------------------------------------------------------------------------
h "Running a file that is not executable"
# A file written with `>` gets the umask's mode, usually without +x, and whether
# `./file` then runs is a property of the machine, not of the file's contents.
printf 'true\n' > "$WORK/plain"
kv "mode of a file written by > (umask $(umask))" "$(ls -l "$WORK/plain" | awk '{print $1}')"
( cd "$WORK" && ./plain ) >/dev/null 2>"$WORK/.xerr"
kv "./plain rc" "$?  stderr: $(head -n1 "$WORK/.xerr" 2>/dev/null)"

printf '\n=== end of report ===\n'
} > "$REPORT" 2>&1

# ---- show it ----------------------------------------------------------------
cat "$REPORT"
echo
echo ">>> report written to: $REPORT"

# ---- optional commit / push -------------------------------------------------
if [ "$DO_COMMIT" = 1 ]; then
    echo
    ORIG_BRANCH=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)
    BR="env-audit-42"
    echo ">>> committing report on branch '$BR' (was on '$ORIG_BRANCH')"

    # BUILD ON THE REMOTE BRANCH IF THERE IS ONE. `checkout -B` alone recreates
    # the branch from wherever you are, which diverges from origin -- so the
    # push is rejected, and the obvious response ("--force-with-lease, it is
    # only a report branch") DESTROYS every report already pushed from another
    # machine. That happened on the second run: the new commit's parent was
    # main, not the previous report, and only the same machine regenerating the
    # same filename hid it.
    #
    # Starting from origin/$BR instead makes reports ACCUMULATE, which is the
    # point of a branch collecting one file per box, and a plain push then
    # works because history is linear again.
    git -C "$ROOT" fetch origin "$BR" >/dev/null 2>&1 && HAVE_REMOTE=1 || HAVE_REMOTE=0
    if [ "$HAVE_REMOTE" = 1 ]; then
        echo "    building on origin/$BR (existing reports are kept)"
        _co="git -C $ROOT checkout -B $BR FETCH_HEAD"
    else
        echo "    no origin/$BR yet -- starting it here"
        _co="git -C $ROOT checkout -B $BR"
    fi
    if $_co >/dev/null 2>&1; then
        git -C "$ROOT" add -- "$REPORT"          # explicit path only, never -A
        git -C "$ROOT" commit -m "chore(env-audit): $HOST @ $STAMP" >/dev/null 2>&1 \
            && echo "    committed." || echo "    nothing to commit (report unchanged)."
        if [ "$DO_PUSH" = 1 ]; then
            if git -C "$ROOT" push -u origin "$BR" 2>&1; then
                echo "    pushed to origin/$BR."
            else
                echo "    !! push failed. Run manually:"
                echo "       git push -u origin $BR      # add --force-with-lease if it diverged"
            fi
        else
            echo "    (skipped push; re-run with --push, or: git push -u origin $BR)"
        fi
        # return the user to where they started
        [ -n "$ORIG_BRANCH" ] && [ "$ORIG_BRANCH" != "HEAD" ] && git -C "$ROOT" checkout "$ORIG_BRANCH" >/dev/null 2>&1
    else
        echo "    !! could not switch to branch $BR; leaving report uncommitted at $REPORT"
    fi
fi
