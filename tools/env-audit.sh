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
# AND THE FACTS THE HARNESS'S OWN DEFAULTS DEPEND ON (TODO.md D7: gathered,
# not guessed). Where Bazel's state can go -- every drive a student can use,
# with its space, owner, mode and what can be said about persistence, and what
# tools/drives.sh (setup.sh's and tools/bazel's choice) decides on this box;
# the norminette on PATH, which a student runs by hand and which may not be the
# pinned one; the memory limits a build runs under (ulimit, cgroup); whether
# libbsd is installed and strlcpy's manual page resolves (on Ubuntu 22.04 the
# page ships only with libbsd-dev); the clock, timezone and UTC offset, which
# the 42 header stamps and the modification-time exercises read; and what the
# machine does under load -- swap, the dirty-page limits, the disk schedulers,
# the kernel's out-of-memory and hung-task lines -- with the traces every
# prime writes (tools/prime_trace.sh), for the campus box that froze while it
# primed.
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
# student types, and the study guide tells them to try both.
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

h "Drives, for tools/drives.sh"
# Where Bazel's state -- 8.9 GB for a full run -- can go on this box, which is
# a decision (tools/drives.sh: /goinfre/$USER, then the cache dir in $HOME, then
# /tmp/$USER) made from these facts rather than from a guess. Deliberately NOT
# /sgoinfre as a candidate: that is network-attached, and a shared drive used
# as a build cache is both more closely watched and the wrong tool -- if a
# shared cache is ever wanted, it should be a real remote cache (buildbarn or
# similar), not a filesystem several machines write to at once. Owner's call,
# 2026-08-09. It is still described, so the call can be revisited from facts.
#
# PERSISTENCE is what can be detected: RAM-backed, network, or local disk.
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
    # shellcheck source=drives.sh
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
        if drives_default_root; then
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
_cg=$(sed -n 's/^0::\(.*\)/\1/p' /proc/self/cgroup 2>/dev/null | head -n 1)
if [ -n "$_cg" ] && [ -r "/sys/fs/cgroup$_cg/memory.max" ]; then
    kv "cgroup (v2)" "$_cg"
    for _f in memory.max memory.high memory.swap.max pids.max cpu.max; do
        [ -r "/sys/fs/cgroup$_cg/$_f" ] && kv "  $_f" "$(cat "/sys/fs/cgroup$_cg/$_f" 2>/dev/null)"
    done
elif [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
    kv "cgroup (v1) memory limit" "$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null) bytes"
else
    kv "cgroup memory limit" "(no cgroup memory controller visible)"
fi
cap "systemd user slice" sh -c 'systemctl show "user-$(id -u).slice" -p MemoryMax -p MemoryHigh -p TasksMax 2>/dev/null'

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
for _d in "$HOME" /goinfre "/goinfre/$(id -un 2>/dev/null)" /tmp; do
    [ -d "$_d" ] || continue
    _dev=$(df -P "$_d" 2>/dev/null | awk 'NR == 2 { print $1 }')
    _fst=$(stat -f -c %T "$_d" 2>/dev/null)
    _blk=$(readlink -f "$_dev" 2>/dev/null)
    _blk=${_blk##*/}
    _q=""
    if [ -n "$_blk" ] && [ -r "/sys/class/block/$_blk/queue/scheduler" ]; then
        _q="/sys/class/block/$_blk/queue"
    elif [ -n "$_blk" ] && [ -r "/sys/class/block/$_blk/../queue/scheduler" ]; then
        _q="/sys/class/block/$_blk/../queue"
    fi
    if [ -n "$_q" ]; then
        kv "disk of $_d" "$_dev ($_fst): scheduler $(cat "$_q/scheduler" 2>/dev/null), rotational $(cat "$_q/rotational" 2>/dev/null)"
    else
        kv "disk of $_d" "${_dev:-(unknown)} (${_fst:-unknown type}): no local scheduler"
    fi
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
# their manual page, and on the Ubuntu campus runs that page comes from
# libbsd-dev, in section 3bsd, not from glibc (which has the functions only
# from 2.38). The dev image carries the page alone (.devcontainer/Dockerfile),
# and docs/environment.md names a fallback for a box with none; whether
# campus has it is what decides that text. The header and the library are
# recorded too: code that includes or links them builds wherever they are.
cap "libbsd packages" sh -c 'dpkg-query -W -f="\${Package} \${Version} \${Status}\n" libbsd0 libbsd-dev 2>/dev/null'
kv "<bsd/string.h>"   "$([ -r /usr/include/bsd/string.h ] && echo present || echo absent)"
cap "libbsd.so"       sh -c 'ldconfig -p 2>/dev/null | grep "libbsd\.so" | head -n 2'
cap "pkg-config libbsd" pkg-config --modversion libbsd
kv "man"              "$(command -v man 2>/dev/null || echo '(not on PATH)')"
for _pg in strlcpy strlcat "3bsd strlcpy" "3bsd strlcat"; do
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
cap "timedatectl"   sh -c 'timedatectl show -p Timezone -p NTPSynchronized -p LocalRTC 2>/dev/null'

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
_nm=$(command -v norminette 2>/dev/null)
if [ -n "$_nm" ]; then
    kv "path"            "$_nm -> $(readlink -f "$_nm" 2>/dev/null)"
    kv "norminette -v"   "$(norminette --version 2>&1 | vline)"
    kv "interpreter"     "$(head -n 1 "$(readlink -f "$_nm" 2>/dev/null || printf '%s' "$_nm")" 2>/dev/null | cut -c1-80)"
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
        # none and goes on.
        _lp=$("$_sh" -lic 'case ":$PATH:" in *":$HOME/.local/bin:"*) echo yes;; *) echo no;; esac' \
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
# per machine: $HOME follows a student between machines on campus, and the
# traces with it. This machine's five newest come first, in full, each after
# a summary; another machine's after it, each summarised, and in full when it
# did not finish -- a freeze there is evidence read from here too. A trace of
# this machine that "stopped with the machine" has no END and names a boot
# before this one: the shape a freeze leaves, and the one that keeps the
# login prime from starting again. Another machine's boots are not this
# one's to judge, so one of its traces with no END is said to be only that.
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
            for (k in f) if (k ~ /^psi_/) {
                x = f[k]; sub(/.*full:/, "", x); sub(/\/.*/, "", x)
                if (x + 0 > psi[k] + 0) psi[k] = x
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
            for (k in psi) printf "  peak %s full (avg10): %s\n", k, psi[k]
            for (p in rss) printf "  peak RSS of Bazel server %s: %d kB\n", p, rss[p]
        }' "$1"
    [ "$_tfull" = 0 ] || sed 's/^/    /' "$1"
}
if [ -r "$ROOT/tools/prime_trace.sh" ]; then
    # shellcheck source=prime_trace.sh
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
