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
# AND THE FACTS THE HARNESS'S OWN DEFAULTS DEPEND ON (D7: gathered,
# not guessed). Where Bazel's state can go -- every drive a student can use,
# with its space, owner, mode and what can be said about persistence, and what
# tools/drives.sh (setup.sh's and tools/bazel's choice) decides on this box;
# how big the Bazel caches already there are, and which Bazel launcher
# answers; the norminette on PATH, which a student runs by hand and which may
# not be the pinned one; which GCC installation clang-12 takes its headers
# and libgcc from; whether docker or podman is there; the memory limits a
# build runs under (ulimit, cgroup); whether libbsd is installed and
# strlcpy's manual page resolves (on Ubuntu 22.04 the page ships only with
# libbsd-dev); the clock, timezone and UTC offset, which the 42 header stamps
# and the modification-time exercises read; and what the machine does under
# load -- swap, the dirty-page limits, the disk schedulers, the kernel's
# out-of-memory and hung-task lines -- with the traces every prime writes
# (tools/prime_trace.sh) and the last prime's log, for the campus box that
# froze while it primed.
#
# It audits the machine, never an exercise. An earlier version ran three
# exercises' answers here to watch them work; that put answers in a file the
# public template ships, and it measured the answer as much as the machine.
#
# SAFETY: read-only w.r.t. your account. It never reads ~/.ssh, never prints a
# private key, and does all work inside a fresh `mktemp -d` that is removed on
# exit. It captures tool *versions* and *behaviors* only — no secrets.
#
# USAGE (from the repo root, on a 42 machine that has this repo cloned). Write
# and print the report only:
#   sh tools/env-audit.sh
# Also commit the report on a local branch env-audit-42, on top of origin's
# (then `git push origin env-audit-42` sends it):
#   sh tools/env-audit.sh --commit
# Commit it and push it to origin's env-audit-42 instead (--push alone does
# the same; a local env-audit-42 an earlier --commit left goes along):
#   sh tools/env-audit.sh --commit --push
# Neither switches branch: your branch, its staged files and your files stay
# as they were, and the report stays where it was written. Both need a git
# identity (git config user.name and user.email) and an origin that answers;
# without them they stop with exit 1 and say why, the report written anyway.
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
# --commit and --push are the exception: each exits 1 when it did not do what
# it says, because a report that silently stayed behind is one nobody reads.
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
            sed -n '3,/^# ====/p' "$0" | sed '$d'; exit 0 ;;
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
trap 'rm -rf "$WORK"' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

# ---- tiny helpers -----------------------------------------------------------
h()  { printf '\n### %s\n' "$1"; }                         # section header
kv() { printf '%-22s %s\n' "$1:" "$2"; }                   # key: value
# cap "label" cmd... -- a version banner: cmd's first two lines, joined by |.
# A cmd the box lacks reads "(not installed)", one that ran and printed
# nothing "(not available)". The shell's own "not found" was the row before:
# dash and bash word it differently, and it carried a line number of this
# script's, so two boxes lacking the same tool reported it differently.
# Commands run through `sh -c` or `cat` always pass the first test, and say
# "(not available)" when they find nothing.
cap(){
    _lbl="$1"; shift
    if ! command -v "$1" > /dev/null 2>&1; then
        printf '%-22s %s\n' "$_lbl:" "(not installed)"
        return 0
    fi
    _out=$("$@" 2>&1)
    if [ -n "$_out" ]; then
        printf '%-22s %s\n' "$_lbl:" "$(printf '%s' "$_out" | head -n 2 | tr '\n' '|')"
    else
        printf '%-22s %s\n' "$_lbl:" "(not available)"
    fi
}
# capall "label" cmd... -- cap for a row that is not a banner (a list, or a
# set of properties): every line, joined by |, up to EA_ROW_MAX bytes (1000),
# then how many lines it left out. cap's two lines lost what such a row was
# for: the 2026-10-13 report has two of /etc/shells' lines and two of the
# three properties timedatectl was asked for.
capall(){
    _lbl="$1"; shift
    if ! command -v "$1" > /dev/null 2>&1; then
        printf '%-22s %s\n' "$_lbl:" "(not installed)"
        return 0
    fi
    _out=$("$@" 2>&1)
    if [ -n "$_out" ]; then
        printf '%-22s %s\n' "$_lbl:" "$(printf '%s\n' "$_out" | awk -v max="${EA_ROW_MAX:-1000}" '
            cut || (NR > 1 && length(row) + 1 + length($0) > max + 0) { cut++; next }
            { row = (NR > 1 ? row "|" : "") $0 }
            END { printf "%s", row; if (cut) printf " (%d more line%s)", cut, (cut == 1 ? "" : "s") }')"
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

# ea_ver PROG -- PROG's version, as vline reads its --version. A PROG that
# fails and prints no dotted number has none to give: dash answers
# "dash: 0: Illegal option --" with status 2, and that error was recorded as
# its version. vline itself is left as env_drift's first_line reads.
ea_ver() {
    _evo=$("$1" --version 2>&1)
    _evr=$?
    if [ "$_evr" != 0 ] && ! printf '%s\n' "$_evo" | grep -q '[0-9][0-9]*\.[0-9]'; then
        printf '%s\n' "(no --version)"
        return 0
    fi
    printf '%s\n' "$_evo" | vline
}

# ea_pkg FILE -- the package dpkg says FILE came from, or nothing. On a
# merged-/usr box (/bin a link to usr/bin) readlink -f says /usr/bin/dash and
# dpkg knows the file as /bin/dash, so the /bin or /sbin spelling is asked
# too: the 2026-10-13 report read "not from a package" for sh, bash, dash and
# zsh. dpkg-divert's "diversion by P from: FILE" lines come first for a
# diverted file and name no owner.
ea_pkg() {
    for _epf in "$1" "$(printf '%s\n' "$1" | sed -n 's#/usr/\(s\{0,1\}bin/[^/]*\)$#/\1#p')"; do
        [ -n "$_epf" ] || continue
        _epk=$(dpkg -S "$_epf" 2>/dev/null | grep -v '^diversion ' | cut -d: -f1 | head -n 1)
        if [ -n "$_epk" ]; then
            printf '%s\n' "$_epk"
            return 0
        fi
    done
}

# ea_real CMD PATH -- the file PATH runs as CMD: readlink -f, and past a pyenv
# shim (a bash script that runs whichever version pyenv selects) to the file
# `pyenv which` names. Without that the report described the shim: its
# sha256, "#!/usr/bin/env bash" as norminette's interpreter, and a path that
# pointed at itself.
ea_real() {
    _erp=""
    case "$2" in
        */shims/*)
            command -v pyenv > /dev/null 2>&1 && _erp=$(pyenv which "$1" 2>/dev/null) ;;
    esac
    [ -n "$_erp" ] || _erp=$2
    readlink -f "$_erp" 2>/dev/null || printf '%s\n' "$_erp"
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
    _real=$(ea_real "$_cmd" "$_p")
    _ver=$(ea_ver "$_cmd")
    [ -n "$_ver" ] || _ver="(no --version)"
    _sha=$(sha256sum "$_real" 2>/dev/null | cut -d" " -f1)
    [ -n "$_sha" ] || _sha="(unreadable)"
    _pkg=$(ea_pkg "$_real")
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
    #
    # EA_SYS_ROOT stands in for / here, so a fake system copy can be found.
    for _sys in "${EA_SYS_ROOT:-}/usr/bin/$_cmd" "${EA_SYS_ROOT:-}/bin/$_cmd"; do
        [ -x "$_sys" ] || continue
        # Compare RESOLVED paths. On a merged-/usr system /bin is a symlink to
        # /usr/bin, so a string compare reported /bin/gdb as "shadowing"
        # /usr/bin/gdb -- the same file, announced as a conflict.
        _sysreal=$(readlink -f "$_sys" 2>/dev/null || printf '%s' "$_sys")
        [ "$_sysreal" = "$_real" ] && continue
        _sver=$(ea_ver "$_sys")
        # By its own path, then by the file it resolves to: a copy that
        # update-alternatives manages (cc) is a package's file only at the
        # end of its links.
        _spkg=$(ea_pkg "$_sys")
        [ -n "$_spkg" ] || _spkg=$(ea_pkg "$_sysreal")
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
capall "locale" locale
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
# perl, gdb, lldb-12, ld and as are here because tools/pins.tsv pins them, and
# a pin nothing captures is a pin nobody can re-check: env_drift would report
# drift on a box whose actual version this report never recorded. Plain `lldb`
# beside lldb-12 for the same reason clang sits beside clang-12: it is the name
# a student types, and the study guide tells them to try both.
for _t in cc clang clang-12 gcc gcc-10 make diff ar nm objdump ld as norminette \
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
capall "/etc/shells" cat /etc/shells

h "Drives, for tools/drives.sh"
# Where a full run's Bazel state (DRIVES_FULL_GB) can go on this box, which is
# a decision (tools/drives.sh: /goinfre/$USER, then the cache dir in $HOME, then
# /tmp/$USER) made from these facts rather than from a guess. Deliberately NOT
# /sgoinfre as a candidate: that is network-attached, and a shared drive used
# as a build cache is both more closely watched and the wrong tool -- if a
# shared cache is ever wanted, it should be a real remote cache (buildbarn or
# similar), not a filesystem several machines write to at once. Owner's call,
# 2026-08-09. It is still described, so the call can be revisited from facts.
#
# PERSISTENCE is what can be detected: RAM-backed, network, FUSE (served by a
# program, which may keep its files here or on another machine), or not a
# network filesystem by type (a local disk, or a volume attached at login: the
# type cannot tell them apart).
# Whether a campus cleans /goinfre at logout is its policy, which no file on
# the box records -- write it down beside the report if you know it.
#
# INODES matter as much as bytes here, and that is not obvious: Bazel keys its
# output base on the workspace path, so every clone and worktree is a full tree
# of small files. Eight of them exhausted a 16.7-million-inode filesystem on the
# development box while 122 GB was still free, and the build failed with "no
# space left on device" -- a true message about the wrong resource.
#
# Nothing here writes: the choice below is PREDICTED (DRIVES_DRY), from the
# modes of what exists, so the account is left as it was found.
if [ -r "$ROOT/tools/drives.sh" ]; then
    # shellcheck source=tools/drives.sh
    . "$ROOT/tools/drives.sh"
    _au_user=$(drives_user)
    for _d in /goinfre "/goinfre/$_au_user" /sgoinfre "$HOME" "${XDG_CACHE_HOME:-$HOME/.cache}" /tmp "/tmp/$_au_user"; do
        drives_describe "$_d" | sed "1s|^|$_d: |; 2,\$s|^|$(printf '%s: ' "$_d" | sed 's/./ /g')|"
    done
    drives_campus
    kv "campus box" "$DRIVES_CAMPUS ($DRIVES_CAMPUS_WHY)"
    (
        unset C_PISCINE_SCRATCH
        DRIVES_DRY=1
        export DRIVES_DRY
        if drives_choose; then
            kv "setup.sh would choose" "$DRIVES_SCRATCH  ($DRIVES_WHY)"
        else
            kv "setup.sh would choose" "nothing: $DRIVES_WHY"
        fi
        if drives_default_root "$ROOT"; then
            kv "tools/bazel's root" "$DRIVES_ROOT  (with no .bazelrc.local; $DRIVES_ROOT_WHY)"
        else
            kv "tools/bazel's root" "none: $DRIVES_ROOT_WHY"
        fi
        _au_rc=$(drives_rc_root "$ROOT")
        [ -n "$_au_rc" ] || _au_rc="(none, so the default above applies)"
        kv "this checkout's rc root" "$_au_rc"
    )
else
    kv "tools/drives.sh" "(not in this checkout -- the choice cannot be reported)"
    for _d in /goinfre /sgoinfre "$HOME" /tmp; do
        [ -d "$_d" ] || continue
        kv "df -h $_d" "$(df -h "$_d" 2>/dev/null | awk 'NR==2 {print $2" total, "$4" free ("$5" used)"}')"
        kv "df -i $_d" "$(df -i "$_d" 2>/dev/null | awk 'NR==2 {print $2" inodes, "$4" free ("$5" used)"}')"
    done
fi
# "(not available)" here is a quota that ran and reported nothing for this
# account, "(not installed)" a box without quota(1).
cap "quota" quota -s

h "Memory limits"
# What a build runs under. The Bazel server settles around 1.4 GB, and a campus
# box was measured at 8 GB of RAM with about 2.5 GB free at idle; a cap from
# ulimit or a cgroup lowers that further, and shows up as a killed server or an
# OOM rather than as a message naming the limit.
kv "MemTotal"     "$(awk '/^MemTotal:/ {print $2" kB"}' /proc/meminfo 2>/dev/null)"
kv "MemAvailable" "$(awk '/^MemAvailable:/ {print $2" kB"}' /proc/meminfo 2>/dev/null)"
kv "SwapTotal"    "$(awk '/^SwapTotal:/ {print $2" kB"}' /proc/meminfo 2>/dev/null)"
kv "nproc"        "$(nproc 2>/dev/null || echo '(nproc not available)')"
# Asked of /bin/sh in a string: POSIX defines only `ulimit -f`, and which of
# the others a shell knows is part of what is being recorded.
for _u in v m d s n; do
    kv "ulimit -$_u" "$(sh -c "ulimit -$_u" 2>/dev/null || echo '(not supported by /bin/sh)')"
done
# Processes: -u in bash and zsh, -p in dash.
kv "ulimit processes" "$(sh -c 'ulimit -u' 2>/dev/null || sh -c 'ulimit -p' 2>/dev/null || echo '(not supported by /bin/sh)')"
# cgroup v2 first: one path, named in /proc/self/cgroup as 0::/<path>.
# EA_CGROUP_ROOT and EA_CGROUP_SELF stand in for /sys/fs/cgroup and
# /proc/self/cgroup, so a fake tree can be walked.
_cgr=${EA_CGROUP_ROOT:-/sys/fs/cgroup}
_cg=$(sed -n 's/^0::\(.*\)/\1/p' "${EA_CGROUP_SELF:-/proc/self/cgroup}" 2>/dev/null | head -n 1)
# ea_cg_min FILE -- the smallest limit FILE sets on the path from the leaf up
# to the root, and the cgroup that sets it. In cgroup v2 every limit on the
# path applies, and the leaf (a terminal's scope, on campus) seldom sets one.
ea_cg_min() {
    _ecp=$_cg
    _ecm=""
    _eca=""
    while :; do
        _ecv=$(cat "$_cgr$_ecp/$1" 2>/dev/null)
        case "$_ecv" in
            '' | max) ;;
            *[!0-9]*) ;;
            *)
                if [ -z "$_ecm" ] || [ "$_ecv" -lt "$_ecm" ]; then
                    _ecm=$_ecv
                    _eca=${_ecp:-/}
                fi ;;
        esac
        if [ -z "$_ecp" ] || [ "$_ecp" = / ]; then
            break
        fi
        _ecp=${_ecp%/*}
    done
    if [ -n "$_ecm" ]; then
        printf '%s\n' "$_ecm (the smallest, set by $_eca)"
    else
        printf '%s\n' "max (no cgroup on the path sets one)"
    fi
}
if [ -n "$_cg" ] && [ -r "$_cgr$_cg/memory.max" ]; then
    kv "cgroup (v2)" "$_cg"
    for _f in memory.max memory.high memory.swap.max pids.max cpu.max; do
        [ -r "$_cgr$_cg/$_f" ] && kv "  $_f" "$(cat "$_cgr$_cg/$_f" 2>/dev/null)"
    done
    for _f in memory.max memory.high pids.max; do
        kv "  lowest $_f" "$(ea_cg_min "$_f")"
    done
elif [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
    kv "cgroup (v1) memory limit" "$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null) bytes"
else
    kv "cgroup memory limit" "(no cgroup memory controller visible)"
fi
capall "systemd user slice" sh -c 'systemctl show "user-$(id -u).slice" -p MemoryMax -p MemoryHigh -p TasksMax 2>/dev/null'

h "Memory pressure and I/O"
# What decides how a box behaves when a build asks for more than it has, which
# is the question a frozen campus box left open: whether it swaps and how
# eagerly, how much written data it lets pile up before writers are made to
# wait, which scheduler the disks behind the build's folders run, and what the
# kernel said about memory and stuck tasks. The pressure figures (PSI) are what
# the prime traces sample, where the kernel has them.
cap "/proc/swaps" cat /proc/swaps
for _vm in swappiness dirty_ratio dirty_background_ratio dirty_bytes dirty_background_bytes vfs_cache_pressure; do
    kv "vm.$_vm" "$(cat "/proc/sys/vm/$_vm" 2>/dev/null || echo '(not readable)')"
done
if [ -r /proc/pressure/memory ]; then
    kv "pressure (PSI)" "available"
    for _r in memory io cpu; do
        cap "  $_r" cat "/proc/pressure/$_r"
    done
else
    kv "pressure (PSI)" "(absent: a kernel without it, or booted with psi=0)"
fi
# The disk behind each folder a build writes to. A network filesystem has no
# local scheduler, and says so by its type.
#
# A volume of LVM, md or dm-crypt is a device-mapper node, whose own
# scheduler is "none": the one that queues the I/O is the disk's under it,
# found through slaves/ (the first campus report had only the node's, on
# /goinfre and /tmp). The type comes from findmnt, then df -T: stat -f calls
# ext4 "ext2/ext3". C_PISCINE_SYSFS stands in for /sys, so a fake can be read.
_sysfs=${C_PISCINE_SYSFS:-/sys}
ea_queue() {  # ea_queue NAME -- NAME's queue folder (a partition's is its disk's)
    if [ -r "$_sysfs/class/block/$1/queue/scheduler" ]; then
        printf '%s\n' "$_sysfs/class/block/$1/queue"
    elif [ -r "$_sysfs/class/block/$1/../queue/scheduler" ]; then
        printf '%s\n' "$_sysfs/class/block/$1/../queue"
    fi
}
ea_leaves() {  # ea_leaves NAME -- the bottom devices of NAME's slaves/, or NAME
    _elt=$1
    _elo=""
    _eln=0
    while [ -n "$_elt" ] && [ "$_eln" -lt 64 ]; do
        _eln=$((_eln + 1))
        _elb=${_elt%% *}
        case "$_elt" in *" "*) _elt=${_elt#* } ;; *) _elt="" ;; esac
        _els=""
        for _elx in "$_sysfs/class/block/$_elb/slaves/"*; do
            [ -e "$_elx" ] || [ -L "$_elx" ] || continue
            _els="$_els${_els:+ }${_elx##*/}"
        done
        if [ -n "$_els" ]; then
            _elt="$_elt${_elt:+ }$_els"
        else
            _elo="$_elo${_elo:+ }$_elb"
        fi
    done
    printf '%s\n' "$_elo"
}
for _d in "$HOME" /goinfre "/goinfre/$(id -un 2>/dev/null)" /tmp; do
    [ -d "$_d" ] || continue
    _dev=$(df -P "$_d" 2>/dev/null | awk 'NR == 2 { print $1 }')
    _fst=$(findmnt -n -o FSTYPE --target "$_d" 2>/dev/null | head -n 1)
    [ -n "$_fst" ] || _fst=$(df -PT "$_d" 2>/dev/null | awk 'NR == 2 { print $2 }')
    [ -n "$_fst" ] || _fst=$(stat -f -c %T "$_d" 2>/dev/null)
    _blk=$(readlink -f "$_dev" 2>/dev/null)
    _blk=${_blk##*/}
    _q=""
    [ -z "$_blk" ] || _q=$(ea_queue "$_blk")
    if [ -n "$_q" ]; then
        kv "disk of $_d" "$_dev ($_fst): scheduler $(cat "$_q/scheduler" 2>/dev/null), rotational $(cat "$_q/rotational" 2>/dev/null)"
    else
        kv "disk of $_d" "${_dev:-(unknown)} (${_fst:-unknown type}): no local scheduler"
    fi
    [ -n "$_blk" ] || continue
    for _lf in $(ea_leaves "$_blk"); do
        [ "$_lf" != "$_blk" ] || continue
        _lq=$(ea_queue "$_lf")
        if [ -n "$_lq" ]; then
            kv "  under it, $_lf" "scheduler $(cat "$_lq/scheduler" 2>/dev/null), rotational $(cat "$_lq/rotational" 2>/dev/null)"
        else
            kv "  under it, $_lf" "(no scheduler readable)"
        fi
    done
done
_bt=$(awk '$1 == "btime" { print $2 }' /proc/stat 2>/dev/null)
kv "booted" "$(date -d "@$_bt" 2>/dev/null || echo "${_bt:-(unknown)}")"
kv "boot id" "$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo '(not readable)')"
# The kernel's own lines about memory and stuck tasks: this boot's, and the
# previous boot's, which a box that froze and was reset only has in its
# journal. Many accounts may read neither, and that is recorded too.
_kpat='out of memory|oom-kill|oom_reaper|killed process|hung_task|blocked for more than|page allocation failure'
_kl=$(dmesg 2>/dev/null) && kv "this boot, kernel" "readable" || kv "this boot, kernel" "(dmesg not readable by this account)"
printf '%s\n' "$_kl" | grep -iE "$_kpat" | tail -n 20 | sed 's/^/    /'
_kp=$(journalctl -k -b -1 --no-pager 2>/dev/null) && [ -n "$_kp" ] &&
    kv "previous boot, kernel" "readable" ||
    kv "previous boot, kernel" "(no journal of it this account can read)"
printf '%s\n' "$_kp" | grep -iE "$_kpat" | tail -n 20 | sed 's/^/    /'

h "libbsd, and strlcpy's manual page"
# strlcpy (C 02 ex10) and strlcat (C 03 ex05) are exercises whose contract is
# their manual page, as strnstr's is for one of Libft's functions, and on
# the Ubuntu campus runs those pages come from libbsd-dev, in section 3bsd,
# not from glibc (which has strlcpy and strlcat only from 2.38, and no
# strnstr). The dev image carries the pages alone (.devcontainer/Dockerfile),
# and docs/environment.md names a fallback for a box with none. The one
# campus report so far (2026-10-13) had libbsd-dev 0.11.5-1, the header, the
# library and the 3bsd pages; there a bare `man strlcpy` or `man strlcat`
# opened avr-libc's avr_string(3avr) instead, and a bare `man strnstr` the
# 3bsd page. Whether every campus box has them is what further reports say.
# The header and the library are recorded too: code that includes or links
# them builds wherever they are.
cap "libbsd packages" sh -c 'dpkg-query -W -f="\${Package} \${Version} \${Status}\n" libbsd0 libbsd-dev 2>/dev/null'
kv "<bsd/string.h>"   "$([ -r /usr/include/bsd/string.h ] && echo present || echo absent)"
cap "libbsd.so"       sh -c 'ldconfig -p 2>/dev/null | grep "libbsd\.so" | head -n 2'
cap "pkg-config libbsd" pkg-config --modversion libbsd
kv "man"              "$(command -v man 2>/dev/null || echo '(not on PATH)')"
for _pg in strlcpy strlcat strnstr "3bsd strlcpy" "3bsd strlcat" "3bsd strnstr"; do
    # shellcheck disable=SC2086 # the section and the name are two words
    _pw=$(man -w $_pg 2>/dev/null | head -n 1)
    kv "man -w $_pg" "${_pw:-(no page)}"
done

h "Clock and timezone"
# The 42 header stamps local time, and shell-00's modification-time exercises
# read file times: a box whose clock or zone is off from campus's makes both
# look wrong for reasons no check can see.
kv "date"           "$(date 2>/dev/null)"
kv "date -u"        "$(date -u 2>/dev/null)"
# The offset alone, which the line above gives only as a zone's abbreviation:
# a test run with no TZ in its environment reads time in this zone, and off
# campus the suite mostly runs in UTC, so a campus offset is worth knowing.
kv "UTC offset"     "$(date +%z 2>/dev/null)"
kv "TZ"             "${TZ:-unset}"
kv "/etc/timezone"  "$(cat /etc/timezone 2>/dev/null || echo '(absent)')"
kv "/etc/localtime" "$(readlink -f /etc/localtime 2>/dev/null || echo '(absent)')"
capall "timedatectl" sh -c 'timedatectl show -p Timezone -p NTPSynchronized -p LocalRTC 2>/dev/null'

h "Users, groups and interfaces, as the Shell 01 checks read them"
# What the machine lets three Shell 01 checks observe, as counts: no login and
# no group name is recorded. ex01 prints a user's groups joined by commas, and
# a list of one group has no comma, so its check needs a user in two groups or
# more to see the join (the dev image gives `student` two supplementary
# groups; this says what a campus login has). ex07's check runs on a fixture
# of its own and last on this machine's /etc/passwd, and whether the test
# locale is installed decides whether the two readings of its order can be
# told apart. ex04 prints the machine's MAC addresses, which the interfaces
# decide.
#
# Each is read without the exercises' own tools: the groups from what the
# kernel holds for this process (its gid and supplementary list), never from
# id's list, and /etc/passwd by its size alone, never field by field. A
# command that walks the logins or lists a user's groups is a piece of those
# exercises' answers, and this file ships in the template.
kv "this login's groups" "$(awk '/^Gid:/ { g = $2 } /^Groups:/ { for (i = 2; i <= NF; i++) if ($i != g) n++ } END { print n + 1 }' /proc/self/status 2>/dev/null)"
kv "/etc/passwd lines" "$(wc -l < /etc/passwd 2>/dev/null | tr -d ' ')"
kv "en_US.UTF-8 installed" "$(locale -a 2>/dev/null | grep -qix 'en_US\.utf-*8' && echo yes || echo NO)"
kv "network interfaces" "$(ls /sys/class/net 2>/dev/null | wc -l | tr -d ' ') under /sys/class/net"

h "norminette on PATH"
# The one a student runs by hand. The suite never uses it -- it runs the pinned
# one (tools/pins.tsv, row norminette) -- and a different version can mean
# different rules, which is exactly the disagreement a student cannot explain
# ("green in the suite, red on my prompt"). So both its --version and the
# version of the Python package behind it are recorded, with where it lives.
# Under pyenv the command is a shim, so the file is the one `pyenv which`
# names (ea_real).
_nm=$(command -v norminette 2>/dev/null)
if [ -n "$_nm" ]; then
    _nmr=$(ea_real norminette "$_nm")
    kv "path"            "$_nm -> $_nmr"
    kv "norminette -v"   "$(norminette --version 2>&1 | vline)"
    kv "interpreter"     "$(head -n 1 "$_nmr" 2>/dev/null | cut -c1-80)"
    kv "package version" "$(python3 -c 'import importlib.metadata as m; print(m.version("norminette"))' 2>/dev/null || echo '(not importable by python3)')"
    cap "pip show" sh -c 'python3 -m pip show norminette 2>/dev/null | grep -E "^(Version|Location):"'
else
    kv "norminette"      "(not on PATH)"
fi
kv "pinned (pins.tsv)" "$(awk -F'\t' '$1 == "norminette" { print $3 }' "$ROOT/tools/pins.tsv" 2>/dev/null)"

h "Tool versions"
# dash/POSIX sh has no --version; report the /bin/sh implementation (+ pkg version if any)
kv  "sh (/bin/sh)"  "$(readlink -f /bin/sh 2>/dev/null | sed 's#.*/##')$(dpkg-query -W -f=' ${Version}' dash 2>/dev/null)"
cap "bash"       bash --version
cap "ssh"        ssh -V
# ssh-keygen has no --help; list supported key algorithms instead (ed25519 matters for ex03)
capall "ssh key algos" ssh -Q key
cap "file"       file --version
# bash, ssh, file, bc, net-tools (netstat), iproute2 (ip), find, tar, patch
# and git are the tools the dev container installs UNPINNED for the shell
# exercises (.devcontainer/Dockerfile, "NOT PINNED", says why). tools/pins.tsv
# holds each line they print as a campus row, from the 2026-10-13 report;
# "tool packages" below records the revisions.
cap "bc"         bc --version
cap "netstat"    netstat --version
cap "ip"         ip -V
cap "find"       find --version
cap "tar"        tar --version
cap "patch"      patch --version
cap "diff"       diff --version
# The packages behind those lines, by name, on one line. pins.tsv's rows for
# them are observed, not pinned, and an apt pin in .devcontainer/Dockerfile
# needs the package's revision, which a version line does not carry. libssl3
# and libbpf0 too: ssh's and ip's lines end in their versions. By name,
# because on a merged-/usr box `dpkg -S` finds nothing at the /usr/bin path of
# a file the package lists under /bin: the 2026-10-13 report reads "not from a
# package" for bash, dash and zsh. pin() now asks dpkg the /bin spelling too
# (ea_pkg); dash and zsh are named here as well, so their revisions sit
# beside the others' on one line. One dpkg knows of but the box does not
# carry (zsh, in the dev container) reads "=(not installed)", never a bare
# "zsh=" that looks cut off.
kv  "tool packages" "$(dpkg-query -W -f='${db:Status-Abbrev}|${Package}=${Version}\n' bash openssh-client libssl3 \
    file bc net-tools iproute2 libbpf0 findutils tar patch git dash zsh 2>/dev/null |
    awk -F'|' 'substr($1, 2, 1) == "i" { print $2; next } { sub(/=.*/, "", $2); print $2 "=(not installed)" }' |
    tr '\n' ' ' | sed 's/ $//')"
# Whether this box can fetch a file from the command line, and with which:
# curl, wget, both or neither. Nothing in the suite runs either, so their
# lines are not pins. They answer a question about the box, for any step
# meant to run on one: which download tool it can count on.
cap "curl"       curl --version
cap "wget"       wget --version
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
# Which GCC installation clang-12 takes its headers, crt files and libgcc
# from: the newest it finds, which need not be gcc-10's. Its driver names it
# on an empty compile.
if command -v clang-12 > /dev/null 2>&1; then
    _gi=$(clang-12 -v -E -x c /dev/null -o /dev/null 2>&1 | sed -n 's/^Selected GCC installation: //p' | head -n 1)
    kv "clang-12's GCC" "${_gi:-(clang-12 names none)}"
else
    kv "clang-12's GCC" "(no clang-12)"
fi
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
h "Bazel launcher"
# Which launcher answers here, and whether its bytes are the bazelisk
# tools/setup.sh installs: its BAZELISK_SHA256, read from setup.sh itself.
# Neither is run: `bazelisk version` starts a Bazel server, after downloading
# Bazel on a box where nothing is set up yet.
_bzv=$(sed -n 's/^BAZELISK_VERSION=\([^[:space:]]*\).*/\1/p' "$ROOT/tools/setup.sh" 2>/dev/null | head -n 1)
_bzs=$(sed -n 's/^BAZELISK_SHA256=\([0-9a-f]*\).*/\1/p' "$ROOT/tools/setup.sh" 2>/dev/null | head -n 1)
if [ -n "$_bzs" ]; then
    kv "setup.sh's bazelisk" "$_bzv $_bzs"
else
    kv "setup.sh's bazelisk" "(no BAZELISK_SHA256 in this checkout's tools/setup.sh)"
fi
for _b in bazel bazelisk; do
    _bp=$(command -v "$_b" 2>/dev/null)
    if [ -z "$_bp" ]; then
        kv "$_b" "(not on PATH)"
        continue
    fi
    _br=$(readlink -f "$_bp" 2>/dev/null || printf '%s' "$_bp")
    kv "$_b" "$_bp -> $_br"
    _bh=$(sha256sum "$_br" 2>/dev/null | cut -d' ' -f1)
    if [ -z "$_bh" ]; then
        kv "  sha256" "(unreadable)"
    elif [ -z "$_bzs" ]; then
        kv "  sha256" "$_bh"
    elif [ "$_bh" = "$_bzs" ]; then
        kv "  sha256" "$_bh, matches setup.sh's BAZELISK_SHA256 ($_bzv)"
    else
        kv "  sha256" "$_bh, not setup.sh's bazelisk ($_bzv)"
    fi
done

# -----------------------------------------------------------------------------
h "Prime log and Bazel caches"
# The prime's own log, which the next prime overwrites, and how big the caches
# it fills were: a prime into warm caches and one into cold ones are different
# measurements. The scratch folder is tools/drives.sh's drives_scratch, the
# lookup tools/prime.sh makes, predicted, never made; without drives.sh,
# prime.sh's own fallback. du gets 30 s a folder, because a cache of many
# small files on a spinning disk can take minutes and this audit has to finish.
_rcr=""
command -v drives_rc_root > /dev/null 2>&1 && _rcr=$(drives_rc_root "$ROOT")
if command -v drives_scratch > /dev/null 2>&1; then
    _scr=$(DRIVES_DRY=1; export DRIVES_DRY; drives_scratch "$ROOT")
else
    case "${C_PISCINE_SCRATCH:-}" in
        /*) _scr=$C_PISCINE_SCRATCH ;;
        *) _scr="/tmp/${USER:-$(id -un 2>/dev/null)}" ;;
    esac
fi
# The repository cache is Bazel's default, under the output user root.
_ubr=$_rcr
if [ -z "$_ubr" ] && command -v drives_default_root > /dev/null 2>&1; then
    _ubr=$(DRIVES_DRY=1; export DRIVES_DRY; drives_default_root "$ROOT" && printf '%s' "$DRIVES_ROOT")
fi
kv "scratch" "$_scr"
if [ -r "$_scr/prime.log" ]; then
    kv "prime log" "$_scr/prime.log, its last 20 lines:"
    tail -n 20 "$_scr/prime.log" 2>/dev/null | sed 's/^/    /'
else
    kv "prime log" "(none at $_scr/prime.log)"
fi
# ea_du DIR -- "DIR: its size", given EA_DU_SECONDS (30). The bound is this
# script's own, by a watchdog that stops du: a test runner never bounds a run
# itself (tools/runner_lib.sh's rl_tmo knows the test's limit), but this is
# no runner and runs under no test's limit: it is run by hand on a box, and
# du runs no student code.
ea_du() {
    if [ ! -d "$1" ]; then
        printf '%s\n' "$1: (absent)"
        return 0
    fi
    rm -f "$WORK/du.out"
    du -sh "$1" > "$WORK/du.out" 2>/dev/null &
    _edp=$!
    ( sleep "${EA_DU_SECONDS:-30}"; kill "$_edp" 2>/dev/null && : > "$WORK/du.stopped" ) \
        > /dev/null 2>&1 &
    _edw=$!
    wait "$_edp" 2>/dev/null
    kill "$_edw" 2>/dev/null
    wait "$_edw" 2>/dev/null
    if [ -e "$WORK/du.stopped" ]; then
        rm -f "$WORK/du.stopped"
        printf '%s\n' "$1: (still counting after ${EA_DU_SECONDS:-30} s, stopped)"
        return 0
    fi
    _edu=$(cut -f1 "$WORK/du.out" 2>/dev/null | head -n 1)
    printf '%s\n' "$1: ${_edu:-(du said nothing)}"
}
kv "disk cache" "$(ea_du "$_scr/bazel-disk")"
if [ -n "$_ubr" ]; then
    kv "repository cache" "$(ea_du "$_ubr/cache/repos")"
else
    kv "repository cache" "(no output user root to find it under)"
fi

# -----------------------------------------------------------------------------
h "Containers"
# Whether docker or podman is on PATH, never run: whether a box could run
# the dev container at all is a fact about the box.
for _c in docker podman; do
    kv "$_c" "$(command -v "$_c" 2>/dev/null || echo '(not on PATH)')"
done

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


# -----------------------------------------------------------------------------
h "42 -- the front-end command"
# What tools/42.sh leans on, gathered rather than assumed: the python3 it runs
# on (its floor is 3.10, Ubuntu 22.04's), tmux for `42 watch --tmux`, whether a
# new terminal's PATH reaches ~/.local/bin, where tools/fortytwo/install.sh
# writes the `42` shim, and whether an edit under $HOME raises an inotify
# event: 42 watch polls with stat, because on some filesystems none arrives.
# The PATH rows start a login shell, which runs your startup files exactly as a
# new terminal does; only its yes or no is kept, never what the files hold.
kv "python3" "$(python3 -I -c 'import sys; print(sys.version.split()[0])' 2>/dev/null || echo MISSING)"
# curses is what a full-screen front end draws with; a Python built without it
# imports nothing.
kv "python3 curses" "$(python3 -I -c 'import curses; print("imports")' 2>/dev/null || echo 'does NOT import')"
kv "tmux" "$(tmux -V 2>/dev/null || echo MISSING)"
kv "zellij" "$(zellij --version 2>/dev/null || echo MISSING)"
# screen -v exits 1 even when it answers, so its output is what is read.
_scr=$(screen -v 2>/dev/null | head -n 1)
kv "screen" "${_scr:-MISSING}"
kv "TERM" "${TERM:-unset}"
# How many folders one account may watch for changes: a watcher over the
# whole checkout needs one per folder.
kv "inotify max_user_watches" "$(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || echo '(not readable)')"
kv "inotify max_user_instances" "$(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || echo '(not readable)')"
for _sh in zsh bash; do
    if command -v "$_sh" >/dev/null 2>&1; then
        # Its input is /dev/null, so a startup file that asks for a key gets
        # none and goes on. NO_C_PISCINE_PRIME, because a new interactive
        # shell runs the block tools/setup.sh writes into the startup files,
        # and that block starts a prime in the background: the memory and
        # trace sections below would then measure a prime the audit started.
        _lp=$(NO_C_PISCINE_PRIME=1 "$_sh" -lic 'case ":$PATH:" in *":$HOME/.local/bin:"*) echo yes;; *) echo no;; esac' \
            </dev/null 2>/dev/null | tail -n 1)
        kv "$_sh login: ~/.local/bin on PATH" "${_lp:-(no answer)}"
    else
        kv "$_sh login: ~/.local/bin on PATH" "($_sh MISSING)"
    fi
done
# The event is looked for in a folder of this script's own under $HOME, made
# and removed here; the edit is a file written in it.
cat > "$WORK/inotify.py" <<'PY'
import ctypes, os, select, sys
d = sys.argv[1]
libc = ctypes.CDLL(None, use_errno=True)
fd = libc.inotify_init1(os.O_NONBLOCK)
if fd < 0:
    print("inotify_init1 failed")
    sys.exit()
libc.inotify_add_watch(fd, d.encode(), 0x2 | 0x8 | 0x100 | 0x80)  # MODIFY CLOSE_WRITE CREATE MOVED_TO
with open(os.path.join(d, "f.c"), "w") as f:
    f.write("x")
r, _, _ = select.select([fd], [], [], 2.0)
print("events arrive" if r else "NO EVENTS within 2 s (a watcher must poll)")
PY
_hw=$(mktemp -d "$HOME/.42audit.XXXXXX" 2>/dev/null) || _hw=""
if [ -n "$_hw" ]; then
    trap 'rm -rf "$WORK" "$_hw"' EXIT
    kv "inotify under \$HOME" "$(python3 -I "$WORK/inotify.py" "$_hw" 2>&1 | tail -n 1)"
    rm -rf "$_hw"
    trap 'rm -rf "$WORK"' EXIT
else
    kv "inotify under \$HOME" "(could not make a folder under \$HOME)"
fi

h "Prime traces"
# What the machine did while it primed, sampled by the prime itself
# (tools/prime_trace.sh says why and what each field is), kept in one folder
# per machine: $HOME may follow a student between machines on campus (not
# confirmed yet), and the traces with it. This machine's five newest come
# first, in full, each after a summary; another machine's after it, each
# summarised, and in full when it did not finish -- a freeze there is evidence
# read from here too. A trace of this machine that "stopped with the machine"
# has no END and names a boot before this one: the shape a freeze leaves, and
# the one that keeps the login prime from starting again. Another machine's
# boots are not this one's to judge, so one of its traces with no END is said
# to be only that.
ea_trace() {  # ea_trace FILE MINE -- one trace; in full if MINE, or unfinished
    _tfull=1
    if grep -q '^END ' "$1"; then
        _ts="finished ($(sed -n 's/^END //p' "$1" | tail -n 1))"
        _tfull=$2
    elif [ "$2" = 0 ]; then
        _ts="no END, from another machine: still running there, or stopped with it"
    elif trace_froze "$1"; then
        _ts="did not finish, and the machine restarted since: it stopped with the machine"
    else
        _ts="no END yet: a prime of this boot, still running"
    fi
    printf '\n'
    kv "${1##*/}" "$_ts"
    awk '
        function rate(name,   d) {
            if (!(name in prev) || prev[name] == "" || f[name] == "" || f["up"] <= pu) return
            d = (f[name] - prev[name]) / (f["up"] - pu)
            if (d > peak[name]) peak[name] = d
        }
        /^S / {
            split("", f)
            for (i = 2; i <= NF; i++) {
                k = $i; sub(/=.*/, "", k)
                v = $i; sub(/^[^=]*=/, "", v)
                f[k] = v
            }
            n++
            if (n == 1) first = f["up"]
            last = f["up"]
            if (f["memavail"] != "" && (minm == "" || f["memavail"] + 0 < minm)) minm = f["memavail"] + 0
            if (f["swapfree"] != "" && (mins == "" || f["swapfree"] + 0 < mins)) mins = f["swapfree"] + 0
            if (n > 1) { rate("pswpin"); rate("pswpout"); rate("pgmajfault") }
            prev["pswpin"] = f["pswpin"]; prev["pswpout"] = f["pswpout"]; prev["pgmajfault"] = f["pgmajfault"]
            pu = f["up"]
            # Each field is some:X[/full:Y], and the two are kept apart: the
            # system-wide cpu full line is always 0, and keeping full alone
            # printed an empty cpu peak while some reached 96.99 on campus.
            # The first value seen starts each peak, so a 0 prints as 0.00.
            for (k in f) if (k ~ /^psi_/) {
                np = split(f[k], parts, "/")
                for (j = 1; j <= np; j++) {
                    if (split(parts[j], pk, ":") != 2) continue
                    pkey = k " " pk[1]
                    if (!(pkey in psi) || pk[2] + 0 > psi[pkey] + 0) psi[pkey] = pk[2]
                    psin[k] = 1
                }
            }
            m = split(f["bazel_rss"], a, ",")
            for (i = 1; i <= m; i++) {
                split(a[i], pr, ":")
                if (pr[2] + 0 > rss[pr[1]] + 0) rss[pr[1]] = pr[2]
            }
        }
        END {
            printf "  %d samples over %d s\n", n, last - first
            printf "  lowest MemAvailable %s kB, lowest SwapFree %s kB\n", minm, mins
            printf "  peak per second: %.0f pages swapped in, %.0f out, %.0f major faults\n", peak["pswpin"], peak["pswpout"], peak["pgmajfault"]
            for (k in psin) {
                line = "  peak " k " (avg10):"
                if ((k " some") in psi) line = line " some " psi[k " some"]
                if ((k " full") in psi) line = line (((k " some") in psi) ? "," : "") " full " psi[k " full"]
                print line
            }
            for (p in rss) printf "  peak RSS of Bazel server %s: %d kB\n", p, rss[p]
        }' "$1"
    [ "$_tfull" = 0 ] || sed 's/^/    /' "$1"
}
if [ -r "$ROOT/tools/prime_trace.sh" ]; then
    # shellcheck source=tools/prime_trace.sh
    . "$ROOT/tools/prime_trace.sh"
    kv "folder" "$TRACE_ROOT"
    kv "this boot" "${BOOT_ID:-unknown}"
    _tn=0
    printf '\n'
    kv "machine" "$TRACE_HOST (this one)"
    for _tf in "$TRACE_DIR"/trace-[0-9]*; do
        [ -f "$_tf" ] || continue
        _tn=$((_tn + 1))
        ea_trace "$_tf" 1
    done
    for _td in "$TRACE_ROOT"/*; do
        [ -d "$_td" ] && [ "$_td" != "$TRACE_DIR" ] || continue
        printf '\n'
        kv "machine" "${_td##*/}"
        for _tf in "$_td"/trace-[0-9]*; do
            [ -f "$_tf" ] || continue
            _tn=$((_tn + 1))
            ea_trace "$_tf" 0
        done
    done
    [ "$_tn" -gt 0 ] || kv "traces" "(none: no prime has written one on this account)"
else
    kv "tools/prime_trace.sh" "(not in this checkout -- no trace can be read)"
fi

printf '\n=== end of report ===\n'
} > "$REPORT" 2>&1

# ---- show it ----------------------------------------------------------------
cat "$REPORT"
echo
echo ">>> report written to: $REPORT"

# ---- optional commit / push -------------------------------------------------
# The report goes on branch env-audit-42, one file per box, on top of what
# origin's branch already holds, so reports ACCUMULATE. It is built WITHOUT A
# CHECKOUT: a scratch index starts from that branch's files (or from none, for
# a branch origin does not have yet), takes the report, and becomes a commit
# whose parent is the branch's last one. Nothing of yours is touched. A
# checkout is what failed before: the report the run had just written blocked
# the switch on a box whose report was already on origin, and a commit that
# failed for want of an identity still let the push go out without it.
#
# NEVER A FORCE PUSH, and never a branch rebuilt from your own. An earlier
# version rebuilt the branch from wherever you were when its fetch failed; the
# push was then rejected, and the obvious response ("--force-with-lease, it is
# only a report branch") DESTROYED every report pushed from another machine.
# So the branch is only ever extended, a fetch that fails stops the run, and
# so does every other step that cannot do what it says: exit 1, with git's
# own words and what was left undone.
ea_stop() {  # ea_stop LINE... -- say why, and stop with exit 1
    for _l in "$@"; do
        echo "    !! $_l"
    done
    echo "    The report is not on $BR; it stays at $REPORT"
    exit 1
}
ea_said() {  # ea_said FILE -- what git said, indented under the run's own lines
    [ -s "$1" ] && sed 's/^/       git: /' "$1"
    return 0
}
# ea_tip -- origin's last commit on $BR in _tip, "" when origin has no such
# branch. `ls-remote --exit-code` is what tells the two apart: 2 is "no such
# branch", and anything else is a failure to reach or read origin, which must
# never be taken for an empty branch.
ea_tip() {
    git -C "$ROOT" ls-remote --exit-code origin "refs/heads/$BR" > "$WORK/ls" 2> "$WORK/git.err"
    _rc=$?
    case $_rc in
        0) _tip=$(awk 'NR == 1 { print $1 }' "$WORK/ls") ;;
        2) _tip="" ;;
        *)
            ea_said "$WORK/git.err"
            ea_stop "origin did not answer (git ls-remote exit $_rc), so what its $BR" \
                "holds is unknown and nothing was committed or pushed. Run this" \
                "again once git fetch works from this checkout."
            ;;
    esac
    [ -z "$_tip" ] && return 0
    if ! git -C "$ROOT" fetch -q origin "refs/heads/$BR" 2> "$WORK/git.err" ||
        ! git -C "$ROOT" cat-file -e "$_tip^{commit}" 2>> "$WORK/git.err"; then
        ea_said "$WORK/git.err"
        ea_stop "origin's $BR could not be fetched; nothing was committed or pushed."
    fi
}
# ea_build BASE -- the commit that adds the report on top of BASE ("" for a
# first commit) in _new. Returns 1 when BASE holds this very report already.
ea_build() {
    rm -f "$IDX"
    if [ -n "$1" ]; then
        GIT_INDEX_FILE=$IDX git -C "$ROOT" read-tree "$1" 2> "$WORK/git.err" || return 2
    fi
    _blob=$(git -C "$ROOT" hash-object -w -- "$REPORT" 2> "$WORK/git.err") || return 2
    GIT_INDEX_FILE=$IDX git -C "$ROOT" update-index --add \
        --cacheinfo "100644,$_blob,$REL" 2> "$WORK/git.err" || return 2
    _tree=$(GIT_INDEX_FILE=$IDX git -C "$ROOT" write-tree 2> "$WORK/git.err") || return 2
    if [ -n "$1" ] && [ "$_tree" = "$(git -C "$ROOT" rev-parse "$1^{tree}" 2>/dev/null)" ]; then
        return 1
    fi
    # shellcheck disable=SC2086 # ${1:+-p "$1"} is the two words -p BASE, or none
    _new=$(git -C "$ROOT" commit-tree "$_tree" ${1:+-p "$1"} \
        -m "chore(env-audit): $HOST @ $STAMP" 2> "$WORK/git.err") || return 2
}
# ea_build_or_stop -- ea_build on $_base, stopping on a failure. When the base
# holds this very report already, there is nothing to commit; but a --push
# whose base is a local commit origin lacks still has that commit to send.
ea_build_or_stop() {
    ea_build "$_base"
    case $? in
        0) return 0 ;;
        1)
            if [ "$DO_PUSH" = 1 ] && [ "$_base" != "$_tip" ]; then
                _new=$_base
                return 0
            fi
            echo "    $BR already holds this report; nothing to commit."
            exit 0
            ;;
        *) ea_said "$WORK/git.err"; ea_stop "git could not build the commit." ;;
    esac
}
# ea_base -- the commit the report goes on top of, in _base, and a line saying
# which. Origin's branch is only ever extended, so the base is origin's last
# commit, or the local branch when that already holds origin's last commit,
# as an earlier --commit leaves it: --push then sends that commit along, and
# a later --commit finds the local branch behind origin's, never beside it.
# A local branch that has commits of its own and also lacks some of origin's
# is never built on: --push leaves it as it is, and --commit stops.
ea_base() {
    _base=$_tip
    if [ -n "$_old" ] && [ "$_old" != "$_tip" ]; then
        if [ -z "$_tip" ] || git -C "$ROOT" merge-base --is-ancestor "$_tip" "$_old" 2>/dev/null; then
            _base=$_old
        elif ! git -C "$ROOT" merge-base --is-ancestor "$_old" "$_tip" 2>/dev/null; then
            if [ "$DO_PUSH" = 0 ]; then
                ea_stop "your local $BR and origin's have each a commit the other lacks," \
                    "so neither can go on top of the other. Unless you made them" \
                    "yourself, the commits only the local one has are earlier reports" \
                    "from this checkout, which this run's report replaces. Delete it" \
                    "(git branch -D $BR), then run this again."
            fi
            echo "    your local $BR and origin's have each a commit the other lacks:"
            echo "    the local one is left as it is, and only this report goes to origin."
        fi
    fi
    _along=""
    [ "$DO_PUSH" = 1 ] && _along="; its commits go to origin with this one"
    if [ -z "$_base" ]; then
        echo "    origin has no $BR yet: this commit starts it"
    elif [ "$_base" = "$_tip" ]; then
        echo "    on top of origin's $BR (the reports on it are kept)"
    elif [ -z "$_tip" ]; then
        echo "    on top of your local $BR (origin has no $BR yet$_along)"
    else
        echo "    on top of your local $BR, which holds origin's and adds to it$_along"
    fi
}
if [ "$DO_COMMIT" = 1 ]; then
    echo
    BR="env-audit-42"
    REL="tools/env-reports/$HOST.txt"
    IDX="$(cd "$WORK" && pwd)/index"
    echo ">>> committing the report on branch '$BR' (no checkout: your own branch is not touched)"

    # Who the commit is by. With no user.name or user.email set, git either
    # makes one up from the login and the host name, or gives up: better
    # known before anything is built, and a made-up one shows here.
    for _v in GIT_AUTHOR_IDENT GIT_COMMITTER_IDENT; do
        if ! _id=$(git -C "$ROOT" var "$_v" 2> "$WORK/git.err"); then
            ea_said "$WORK/git.err"
            ea_stop "git has no identity to commit the report under. Set one, then" \
                "run this again:" \
                "   git config user.name \"<your login>\"" \
                "   git config user.email \"<your 42 address>\""
        fi
        # The ident ends with the time and its zone, which say nothing here.
        _id=$(printf '%s' "$_id" | sed 's/ [0-9][0-9]* [-+][0-9][0-9]*$//')
        case $_v in
            GIT_AUTHOR_IDENT) _author=$_id; echo "    as: $_id" ;;
            *) [ "$_id" = "$_author" ] || echo "    committed by: $_id" ;;
        esac
    done

    # --commit alone moves the local branch, and never one a work tree has
    # checked out: its files and index would be left behind the branch, and
    # the next commit there would take the report back out.
    if [ "$DO_PUSH" = 0 ] &&
        git -C "$ROOT" worktree list --porcelain 2>/dev/null | grep -qxF "branch refs/heads/$BR"; then
        ea_stop "$BR is the branch checked out in a work tree here (git worktree list" \
            "says which), and moving it would leave that tree's files behind." \
            "Switch that tree to another branch, or run with --push, which" \
            "leaves local branches alone."
    fi

    ea_tip
    _old=$(git -C "$ROOT" rev-parse -q --verify "refs/heads/$BR")
    ea_base

    if [ "$DO_PUSH" = 1 ]; then
        # Local branches are left alone: the commit goes straight to origin.
        # A rejection is another box pushing between the fetch and the push,
        # so the report is built once more on what origin then holds.
        _try=1
        while :; do
            ea_build_or_stop
            if git -C "$ROOT" push origin "$_new:refs/heads/$BR" 2> "$WORK/push.err"; then
                ea_said "$WORK/push.err"
                echo "    pushed to origin's $BR (commit $(git -C "$ROOT" rev-parse --short "$_new"))."
                exit 0
            fi
            ea_said "$WORK/push.err"
            _was=$_tip
            ea_tip
            if [ "$_try" = 1 ] && [ "$_tip" != "$_was" ]; then
                echo "    origin's $BR moved while this ran (another box?); once more on top of it"
                _try=2
                ea_base
                continue
            fi
            ea_stop "the push failed (git's words above), and origin's $BR is as it" \
                "was. Run this again once git push works from this checkout."
        done
    fi

    # --commit alone: the commit goes on the local branch (ea_base chose
    # where), for a later `git push origin $BR`.
    ea_build_or_stop
    if ! git -C "$ROOT" update-ref -m "env-audit: $HOST @ $STAMP" \
        "refs/heads/$BR" "$_new" "$_old" 2> "$WORK/git.err"; then
        ea_said "$WORK/git.err"
        ea_stop "the local branch $BR could not be moved to the new commit."
    fi
    echo "    committed on the local branch $BR (commit $(git -C "$ROOT" rev-parse --short "$_new"))."
    echo "    Not pushed: git push origin $BR sends it. If origin refuses it,"
    echo "    run this again with --push, which builds on what origin holds."
fi
