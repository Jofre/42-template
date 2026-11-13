"""env_drift.py -- has anything drifted from what tools/pins.tsv expects?

The logic of //tools:env_drift. tools/env_drift.sh, the target's script,
starts it on the Python Bazel fetched, never on a python3 from PATH: this
has to run, and say what it found, on a machine that has none (the owner's
decision of 2026-10-31).

THREE THINGS ARE COMPARED, not two.

  the PIN       what tools/pins.tsv says we expect.
  the BOX       what this machine carries. On a campus machine this is what
                the grade's own tools are, so it is the comparison the grade
                depends on.
  the FETCH     what Bazel actually downloaded, for the tools we no longer
                take from the box at all.

The third one was missing for as long as every layer ran the box's binary,
and it stops being optional the moment one does not. A pin and a fetch that
disagree means the suite is testing something nobody wrote down -- the same
false-green shape as everywhere else in this repo, one level up: pins.tsv
would read 2.38 while the checks ran something else entirely, and nothing
anywhere would say so. A fetch is pinned by sha256, so a difference here is
never packaging noise: a version that differs means the pin was edited in
one place and not the other, and a line without the pin's words means the
row is handed another tool's binary (V327). It is reported loudly whatever
its size. A comparison that could not run (a variable //tools:env_drift
does not set, a path that is no executable) is NOT COMPARED: a fault of
that target's data, never a pin edit (V326).

WHY DIFFERENCES ARE GRADED RATHER THAN MATCHED.
The expected value used to be a SUBSTRING, so `clang version 12.` swallowed
12.0.0 and 12.0.1 alike. That was the right instinct -- Ubuntu re-packages
without changing the compiler, and failing on `-19ubuntu3` is noise --
applied the wrong way, because "do not fail on it" became "cannot see it".
Now the full observed string is recorded and the DIFFERENCE is graded:

  major differs        loud. A different compiler; expect different warnings.
  minor/patch differs  report and re-audit. Campus moved.
  only the suffix      note it and carry on. Same compiler, new packaging.
                       Not drift, and --strict ignores it -- but a campus
                       pin is campus's EXACT string (the owner's ruling,
                       2026-10-14), so on a campus box it still prints the
                       re-pin edit, in the drift line's own form.

WHY IT WARNS RATHER THAN FAILS.
A student sitting at a campus machine that has been upgraded has done
nothing wrong and can do nothing about it. Failing their build would punish
them for 42's package update. So drift is reported loudly and exits 0 by
default; --strict turns it into an error for the one place that should care,
a maintainer deciding whether to re-pin.

WHY IT DOES NOT RE-PIN ITSELF.
Changing a pin changes what the whole suite tests. Done automatically it is
a change nobody made, reviewed, or noticed -- and if campus ever ships a
compiler that accepts something the grade rejects, auto-repinning would
quietly teach the suite to accept it too. It prints the exact edit instead.

WHY CAMPUS IS DETECTED OFFLINE.
Reachability of Vogsphere would work but is the wrong instrument: it needs
the network, it is slow, it fails on a campus box that is merely offline,
and a build should not depend on a remote host answering. 42 boxes carry
/goinfre and /sgoinfre; nothing else does, and testing for a directory costs
nothing. The test itself is tools/drives.sh's, the one setup.sh and
tools/bazel use, run here by /bin/sh as they run it, so the three cannot
disagree about which machine this is; C_PISCINE_CAMPUS=0|1 overrides it (the
selftest drives both banners with it).

WHO THE ADVICE IS FOR (finding 005). Campus-kind drift is counted, and fails
--strict, on every machine; the "worth acting on, re-pin by hand" prose is
printed only on a campus box, because that is the only box whose tools the
grade comes from. Off campus the same rows mean your machine differs from
campus, which is nothing for you to do: the pins describe campus, not your
machine.

AND WHERE THIS CHECKOUT'S STATE IS. On a campus box it also says when the
Bazel state of this checkout sits in the quota'd $HOME or under a path with
no login in it (finding 001), read back from the output base this very
`bazel run` uses rather than predicted.

A FETCHED TOOL THAT DOES NOT START is a finding of its own, UNRUNNABLE, and
never fetch drift. Each one is started the way its layers start it (its
libraries on the loader's path, valgrind with $VALGRIND_LIB, and a compiler
asked to compile an empty file), and a non-zero status or a loader's error
is not a version: graded as one, a loader error naming libbfd-2.38-system.so
read as "ok", since 2.38 is the pin, and a valgrind that could not start its
tool read as a pin edited in one place (V243). The cause is the machine (a
library it lacks, a system newer than the one the fetched tools were built
for), and the dev container is the fix. A tool of this BOX that does not
start is DID NOT START, by the same two signs, and counts with the missing
(V328).

WHAT IS STILL SHELL, AND WHY. The machine is asked its questions as it was
asked them before the port: a pins.tsv version command is a /bin/sh command
line (word splitting, `echo` and `printf` as the shell's own, a script with
no #! run by the shell), and so are `command -v`, the compiler a
default-std row asks and the norminette probe; tools/drives.sh is sourced by
/bin/sh. Everything that reads what they print, grades it and says so is
here, in Python, and //tools/tests:env_drift_test tests it.

Usage (through the launcher):
  bazel run //tools:env_drift [-- [--strict] [--report]]

  --strict   exit 1 on campus-kind drift, ANY fetch drift, or a fetched
             tool that does not start (for a maintainer)
  --report   also write a timestamped copy under tools/env-reports/, and
             exit 2 when it cannot be written

The summary line ("N match, ..., N unrunnable, N recorded") is read by
`42 doctor` (tools/fortytwo/doctor.py), which turns an unrunnable count
above 0 into a blocker and a missing line into "env_drift did not finish".
It reads the line rather than the exit status, which `bazel run` shares with
Bazel's own: 1 is also a build that failed, and 2, this script's refusal
below, is also Bazel refusing an option; the status only picks that BLOCK's
wording. Reword it in both.

The launcher hands over, before the options, three words of its own: its
$0, its $PWD (the directory `bazel run` started it in) and its LC_CTYPE as
"=<value>", or nothing when it had none (see restore_locale).
"""

import glob
import locale
import os
import re
import signal
import subprocess
import sys
import time

# Every message is the launcher's: it is the program that was run.
PROG = "env_drift.sh"

# The shell every probe of the machine runs in, as the script's #! named it.
SH = "/bin/sh"

# A dotted version number, as `grep -oE '[0-9]+(\.[0-9]+)+'` reads one.
VERSION = re.compile(r"[0-9]+(?:\.[0-9]+)+")
# A line that carries one.
DOTTED = re.compile(r"[0-9]+\.[0-9]+")

# What a program that did not start says, whatever its status: the loader's
# missing library, and valgrind's missing tool.
START_FAILURE = re.compile(r"error while loading shared libraries|failed to start tool")

# The shell's field separators when IFS is unset: what an unquoted word of a
# version command or a _COMPILE variable is split on.
IFS_SPLIT = re.compile(r"[ \t\n]+")

# A variable name sh can expand.
NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")

# The report's file name: letters, digits, dots and dashes, not leading dot.
HOST_OK = re.compile(r"[A-Za-z0-9._-]+\Z")

# norminette prints a locale banner before anything else, so its version
# comes from the package metadata rather than a --version flag it does not
# really have. Asked of the python3 on PATH, which is the box's, and its
# status kept apart from its output, as a box tool's is: a python3 that is
# absent, or holds no norminette (NORMINETTE_ABSENT), is a norminette
# MISSING, and one that exits otherwise did not start. It printed
# "(norminette not importable)" instead, which was graded as a version:
# DRIFT (major), and on campus a re-pin to that text.
NORMINETTE_ABSENT = 3
NORMINETTE_PROBE = ("python3 -c 'import importlib.metadata as m, sys\n"
                    "try:\n"
                    "    v = m.version(\"norminette\")\n"
                    "except m.PackageNotFoundError:\n"
                    "    sys.exit(%d)\n"
                    "print(v)'" % NORMINETTE_ABSENT)


# ------------------------------------------------------------ bytes in and out
#
# The shell this replaces moved bytes, never text: a tool that prints a byte
# that is no UTF-8 printed it back the same. The launcher starts Python in
# UTF-8 mode, so the environment and argv arrive decoded with surrogateescape,
# and everything a probe prints is decoded the same way here and encoded back
# on the way out: the bytes come out as they went in.

def decode(b):
    return b.decode("utf-8", "surrogateescape")


def encode(s):
    return s.encode("utf-8", "surrogateescape")


def out(s):
    sys.stdout.buffer.write(encode(s))


def err(s):
    sys.stdout.buffer.flush()
    sys.stderr.buffer.write(encode(s))
    sys.stderr.buffer.flush()


def subst(b):
    """What sh's $(...) keeps of output b: NUL bytes dropped, trailing newlines cut."""
    return decode(b.replace(b"\0", b"")).rstrip("\n")


def status(rc):
    """A child's status as sh's $? reads it: 128+N for a signal."""
    return 128 - rc if rc < 0 else rc


def run(argv, stderr=None):
    """argv's output and its status; stderr to this run's own by default.

    Its input is /dev/null: a probe is asked a question and never reads
    one. (Under the shell version they read the rest of pins.tsv, which a
    tool that read its input would have eaten.)
    """
    sys.stdout.buffer.flush()
    try:
        p = subprocess.run(argv, stdin=subprocess.DEVNULL,
                           stdout=subprocess.PIPE, stderr=stderr)
    except OSError:
        # Only when the program itself cannot be started: sh says "not
        # found" and sets 127, which is what a caller here tells apart.
        return b"", 127
    return p.stdout, status(p.returncode)


def sh(script, *args):
    """/bin/sh -c SCRIPT with ARGS as $1...: its output and status."""
    return run([SH, "-c", script, "sh"] + list(args))


# What sh says itself of a child that a signal killed ("Segmentation
# fault") goes into the output when the command's own stderr is sent there
# and sh runs it last, by exec. Kept in a $(...) assignment instead, as the
# shell version kept it, the shell's word goes to this run's stderr and the
# program's own to the output: "exit 139: (it printed nothing)", and the
# message on the terminal.
CAPTURED = 'o=$(%s 2>&1); s=$?; printf "%%s" "$o"; exit $s'


def command_v(name):
    """sh's `command -v NAME`, which finds its builtins as well as PATH's."""
    return sh('command -v "$1" > /dev/null 2>&1', name)[1] == 0


# ------------------------------------------------------- the shell's own rules

def pad(s, width):
    """printf's %-Ns: padded to N bytes, as dash and bash count them."""
    return s + " " * max(0, width - len(encode(s)))


def first_word(cmd):
    """${cmd%% *}"""
    i = cmd.find(" ")
    return cmd if i < 0 else cmd[:i]


def after_first_word(cmd):
    """${cmd#* }: cmd itself when it has no space."""
    i = cmd.find(" ")
    return cmd if i < 0 else cmd[i + 1:]


def before_last_word(cmd):
    """${cmd% *}: cmd itself when it has no space."""
    i = cmd.rfind(" ")
    return cmd if i < 0 else cmd[:i]


def words(s):
    """An unquoted $s split into words as sh splits it, IFS unset.

    No pathname expansion: no version command or _COMPILE variable has a
    pattern character in it.
    """
    return [w for w in IFS_SPLIT.split(s) if w]


def colon_fields(s):
    """An unquoted $s split with IFS=: -- an empty field kept, a last one not."""
    if s == "":
        return []
    f = s.split(":")
    if f[-1] == "":
        f.pop()
    return f


def dirname(p):
    """dirname(1)'s answer for p."""
    if p == "":
        return "."
    s = p.rstrip("/")
    if s == "":
        return "/"
    i = s.rfind("/")
    if i < 0:
        return "."
    s = s[:i].rstrip("/")
    return s if s else "/"


def logical(base, path):
    """The $PWD sh's `cd path` makes from base: . and .. read as words."""
    full = path if path.startswith("/") else base + "/" + path
    parts = []
    for c in full.split("/"):
        if c in ("", "."):
            continue
        if c == "..":
            if parts:
                parts.pop()
            continue
        parts.append(c)
    return "/" + "/".join(parts)


def sh_read(line, n):
    """`IFS=<tab> read -r v1 ... vn` of one line.

    A tab is IFS whitespace: a run of them is one separator, and those at
    either end are cut. The last variable takes the rest of the line.
    """
    s = line.lstrip("\t")
    vals = []
    for _ in range(n - 1):
        i = s.find("\t")
        if i < 0:
            vals.append(s)
            s = ""
        else:
            vals.append(s[:i])
            s = s[i:].lstrip("\t")
    vals.append(s.rstrip("\t"))
    return vals


def read_lines(text):
    """The lines `while read` reads: a last one with no newline is not one."""
    return text.split("\n")[:-1]


def awk_records(text):
    """The records awk reads: a last one with no newline is one."""
    r = text.split("\n")
    if r[-1] == "":
        r.pop()
    return r


def lines_of(text):
    """The lines of `printf '%s\\n' "$text"`."""
    return text.split("\n")


def env(name):
    """${name:-}, for a name pins.tsv or a row's companion names."""
    if not NAME.match(name):
        return ""
    return os.environ.get(name, "")


# --------------------------------------------------------- reading the answers

def first_line(text):
    """THE FIRST LINE WITH A VERSION, and the first with content if none has.

    `head -n 1` was right for every tool here until perl, whose --version
    prints a BLANK line first and the version on the second. The row then
    compared the empty string against the pin and reported the tool MISSING
    on a machine where it was installed and working -- a false negative in
    the one check whose job is to notice a difference. Nothing else would
    have said so: the cycles layers used perl then, through
    callgrind_annotate, and were green throughout.
    ...and shellcheck went one step further: its --version prints a BANNER
    first ("ShellCheck - shell script analysis tool") and "version: 0.10.0"
    on the line after. That line has content, so "the first line with
    content" pinned the banner -- a string that is identical in every
    release, i.e. a pin that can never report drift.

    So: the first line that carries a dotted version, and the first line
    with content only if no line does. That is the same correction perl
    forced, made general instead of made once. tools/env-audit.sh applies
    the same rule, so a pin and a capture always agree.
    """
    fallback = None
    for line in lines_of(text):
        if fallback is None and line.strip(" \t") != "":
            fallback = line
        if DOTTED.search(line):
            return line
    return fallback if fallback is not None else ""


def versions(s):
    """Every version number in s, whole tokens, left to right.

    Whole tokens, not a greedy regex over the line. A greedy `.*` before the
    capture matches from the LAST position it can, which inside "3.3.58"
    means starting after the first dot and returning "3.58" -- a version
    that is not there, silently, and only for the pins written as a bare
    number.
    """
    return VERSION.findall(s)


def version_of(s):
    """The LAST version number in s.

    Most upstreams here put the real version last -- "Ubuntu clang version
    12.0.1-19ubuntu3", "gcc-10 (Ubuntu 10.5.0-1ubuntu1~22.04.3) 10.5.0",
    "valgrind-3.18.1" -- so the last one skips the packaging numbers and the
    distro release that come earlier. Not all: ssh's and ip's lines end in a
    library's version, which is why grade() also compares first_version_of's.
    """
    v = versions(s)
    return v[-1] if v else ""


def first_version_of(s):
    """The FIRST version number: the tool's own, on every line pins.tsv records
    that has one (the cc-std rows' "201710L gnu" has none).

    Some lines end in another program's -- `ip -V` in libbpf's, `ssh -V` in
    OpenSSL's -- so the last number alone graded iproute2 moving a whole
    major release under the same libbpf as a repackaging.
    """
    v = versions(s)
    return v[0] if v else ""


def version_present(want, s):
    """Does want appear ANYWHERE in s as a version in its own right?

    The rule for a tool that reports several: `norminette --version` prints
    its own version, Python's and the kernel's on one line, so "the last
    one" reads the kernel's and would grade a perfectly correct 3.3.58 as a
    different major release.
    """
    return want in versions(s)


def version_step(want, got):
    """major | minor | patch: how far apart two version numbers are."""
    if want.split(".", 1)[0] != got.split(".", 1)[0]:
        return "major"
    wrest = after(want, ".")
    grest = after(got, ".")
    if wrest.split(".", 1)[0] != grest.split(".", 1)[0]:
        return "minor"
    return "patch"


def after(s, c):
    """${s#*c}: s itself when it has no c."""
    i = s.find(c)
    return s if i < 0 else s[i + 1:]


def grade(want, got):
    """ok | packaging | patch | minor | major, comparing two full version strings.

    Anything with no recognisable number in it grades as `major`: unknown is
    not the same as equal, and treating it as equal is how a version
    comparison stops comparing.
    """
    if want == got:
        return "ok"
    wv = version_of(want)
    gv = version_of(got)
    if not wv or not gv:
        return "major"
    # The tool's own number moved: drift, whatever the last number says.
    # Unless the box's line carries it elsewhere, which is the case
    # version_present exists for.
    wf = first_version_of(want)
    gf = first_version_of(got)
    if wf != gf and not version_present(wf, got):
        return version_step(wf, gf)
    if wv == gv:
        return "packaging"
    if version_present(wv, got):
        return "packaging"
    return version_step(wv, gv)


def pin_banner(want):
    """The pin's words before its first version, its trailing blanks cut.

    "GNU nm (GNU Binutils for Ubuntu)" of the nm pin, nothing of a bare
    "0.13.0". A fetched binary's line has to hold them (V327): graded on its
    numbers alone, another tool that exits 0 with the pinned number in its
    line -- objdump handed to the nm row, both 2.38 -- read "ok". Anywhere
    in the line, never at its start: gcc names itself by the name it was run
    as, so the fetched gcc-10's line starts "x86_64-linux-gnu-gcc-10
    (Ubuntu". The same rule makes a rootpath through a "gcc" link read as
    another tool.
    """
    line = lines_of(want)[0]
    m = VERSION.search(line)
    return line[:m.start()].rstrip(" \t") if m else ""


def start_failure(text):
    return START_FAILURE.search(text) is not None


def start_failure_line(text):
    """The first line saying what a program that did not start says, or ""."""
    for line in lines_of(text):
        if START_FAILURE.search(line):
            return line
    return ""


def default_std_answer(text):
    """"<__STDC_VERSION__> <gnu|strict>" of a compiler's -dM -E output."""
    v = ""
    strict = False
    for line in awk_records(text):
        if "__STDC_VERSION__" in line:
            f = IFS_SPLIT.split(line.strip(" \t"))
            v = f[2] if len(f) > 2 else ""
        if "__STRICT_ANSI__" in line:
            strict = True
    return "%s %s" % (v if v else "(none)", "strict" if strict else "gnu")


def tool_paths(build_text):
    """Every absolute path in a local_config_cc BUILD file's tool_paths.

    tool_paths is "name": "/abs/path" pairs, written by rules_cc one pair a
    line, the `}` on the last: read from its `{` to its first `}`, whatever
    lines that spans. Read a line at a time, as it once was, a real file gave
    no path at all, and a vanished one was never named. A relative path is
    Bazel's own wrapper and is not ours to judge.
    """
    m = re.search(r"tool_paths = \{(.*?)\}", build_text, re.S)
    if not m:
        return []
    paths = []
    for piece in m.group(1).split(","):
        p = re.match(r'.*"(/[^"]*)".*', piece, re.S)
        if p:
            paths.append(p.group(1))
    return paths


def collated(items):
    """`sort -u`: each once, in this locale's collation."""
    try:
        locale.setlocale(locale.LC_COLLATE, "")
        key = locale.strxfrm
    except (locale.Error, ValueError):
        key = None
    return sorted(set(items), key=key)


def host_name():
    """The machine's name, as tools/prime_trace.sh reads it.

    C_PISCINE_HOST, the kernel's, then uname's, and anything that is not
    letters, digits, dots and dashes -- or nothing -- is "unknown". It was
    `hostname | tr`, which turned hostname's newline into a "_" in every file
    name, left the name empty where hostname was missing (the status was
    tr's), and called a command the script did not declare (V258).
    """
    host = os.environ.get("C_PISCINE_HOST", "")
    if not host and os.access("/proc/sys/kernel/hostname", os.R_OK):
        try:
            with open("/proc/sys/kernel/hostname", "rb") as f:
                data = decode(f.read())
        except OSError:
            data = ""
        # `read -r host` stops at the first newline, cuts the blanks at
        # either end, and fails, emptying it here, on a file without one.
        host = data.split("\n", 1)[0].strip(" \t") if "\n" in data else ""
    if not host and command_v("uname"):
        o, rc = sh("uname -n 2> /dev/null")
        host = subst(o) if rc == 0 else ""
    if host.startswith(".") or not HOST_OK.match(host):
        host = "unknown"
    return host


# ------------------------------------------------------------- the run itself

class Drift:
    """One run: what it read, what it counted, and the lines it keeps for later."""

    def __init__(self, self_path, start_pwd, args):
        self.self_path = self_path
        # Bazel hands the fetched binaries over as runfiles-relative paths,
        # and the chdir below would strand every one of them -- silently,
        # since a binary that cannot be found reads exactly like a tool
        # nobody pinned. Remembering where we started is what lets the
        # resolution happen later, in the loop, for ANY variable a pins.tsv
        # row names rather than for a hardcoded list of three.
        self.orig_pwd = start_pwd
        # THE RUNFILES ROOT, which is not $PWD: `bazel run` starts the
        # launcher inside <target>.runfiles/_main, one level BELOW the root
        # that rootpaths like `../clang_12_ubuntu+/usr/bin/clang-12` are
        # written against. Bazel leaves RUNFILES_DIR unset here (measured),
        # and a fetched tool that is a LAUNCHER rather than a binary needs
        # it: buildifier's wrapper looks its real executable up in that tree
        # and, invoked by absolute path from a script that is not its own,
        # reported "Unable to locate buildifier runfile" -- which grade()
        # then read as a version string and called major drift. An inherited
        # value wins, for a caller that knows better than this arithmetic.
        i = start_pwd.rfind("/")
        self.runfiles_root = os.environ.get("RUNFILES_DIR", "") or (start_pwd[:i] if i >= 0 else start_pwd)
        self.strict = False
        self.report = False
        self.pins_override = ""
        self.args = args
        self.match = self.drift = self.missing = self.recorded = 0
        self.fetch_drift = self.unrunnable = 0
        self.unrun_lines = self.drift_lines = self.repin_lines = ""
        self.fetch_lines = self.wiring_lines = ""

    def refuse(self, msg):
        err("%s: %s\n" % (PROG, msg))
        sys.exit(2)

    def abs_path(self, p):
        if not p:
            return ""
        return p if p.startswith("/") else "%s/%s" % (self.orig_pwd, p)

    def abs_libdir_list(self, files):
        """The directories of a <VAR>_LIBS list of library FILES, colon-joined.

        The convention is <VAR>_LIBS beside <VAR>, holding a colon-separated
        list of the LIBRARY FILES a fetched binary needs; their directories
        are what goes on the loader's path. A fetched binary run without
        them loads the BOX's copies, and this comparison then reports on a
        toolchain other than the pinned one -- the check failing in
        precisely the way it exists to catch, which is why the directories
        are verified below rather than assumed.

        Files rather than directories because the caller is Bazel, which
        expands a label to a file and has no dirname -- and because deriving
        a directory by appending /.. to a file silently produces a path that
        cannot be used and cannot be noticed. That exact mistake shipped
        here for one commit.
        """
        if not files:
            return ""
        return ":".join(dirname(self.abs_path(p)) for p in colon_fields(files))

    def parse(self):
        a = self.args
        i = 0
        while i < len(a):
            if a[i] == "--strict":
                self.strict = True
                i += 1
            elif a[i] == "--report":
                self.report = True
                i += 1
            # --pins exists so the GRADING can be tested. It is comparison
            # logic with no test of its own otherwise, and comparison logic
            # that quietly stops comparing is this repo's signature failure
            # -- two versions of the extractor here got a wrong answer for a
            # bare "3.3.58" before any of it ran against a fixture.
            # //tools/tests:selftest drives it.
            elif a[i] == "--pins":
                if len(a) - i < 2:
                    self.refuse("--pins needs a value")
                self.pins_override = a[i + 1]
                i += 2
            else:
                self.refuse("unknown option: %s" % a[i])

    def drives(self, script, *args):
        """SCRIPT run by /bin/sh with tools/drives.sh sourced, in the workspace.

        Sourced as setup.sh, prime.sh, env-audit and the wrapper source it,
        from the workspace and never from beside the launcher: under `bazel
        run` nothing sits beside it. $1 is the workspace, the rest of ARGS
        follow it; its errors reach this run's stderr.

        A status other than 0 is a refusal: the check cannot say which
        machine this is. Only the output was kept, and a drives.sh that
        stopped on an unset variable read as an off-campus box with no
        reason, the campus advice and the quota warning gone (the shell
        version sourced it under set -u, and stopped there).
        """
        sys.stdout.buffer.flush()
        p = subprocess.run([SH, "-c", 'set -u\n. "$1/tools/drives.sh"\n' + script, "sh", self.ws] + list(args),
                           stdout=subprocess.PIPE)
        if p.returncode != 0:
            self.refuse("%s/tools/drives.sh failed (exit %d, its error above), so which machine this is "
                        "is not known" % (self.ws, status(p.returncode)))
        return decode(p.stdout)

    def fetched_run(self, libs, vglib, binary, argv):
        """A fetched binary, as its layers run it.

        LIBDIRS first on the loader's path, $VALGRIND_LIB set, and
        RUNFILES_DIR (see runfiles_root). An empty one is left as it is.
        Through env(1) and sh, as the shell ran it.
        """
        cmd = ["env", "RUNFILES_DIR=" + self.runfiles_root]
        if vglib:
            cmd.append("VALGRIND_LIB=" + vglib)
        if libs:
            old = os.environ.get("LD_LIBRARY_PATH", "")
            cmd.append("LD_LIBRARY_PATH=" + libs + (":" + old if old else ""))
        # A function whose env(1) is one branch of an if, as the shell
        # version's was: where sh says what killed it depends on that.
        o, rc = sh('f() { if :; then "$@"; fi; }; ' + CAPTURED % 'f "$@"',
                   *(cmd + [binary] + argv))
        return subst(o), rc

    def main(self):
        # The external commands this takes from PATH. Exit 2, never 1,
        # because this says the check never ran rather than that the machine
        # is wrong.
        for t in ("env",):
            if not command_v(t):
                err("%s: required command '%s' is not on PATH\n" % (PROG, t))
                sys.exit(2)
        self.parse()
        self.pins_override = self.abs_path(self.pins_override)

        bwd = os.environ.get("BUILD_WORKSPACE_DIRECTORY", "")
        self.ws = bwd or logical(self.orig_pwd, dirname(self.self_path) + "/..")
        try:
            os.chdir(self.ws)
        except OSError:
            self.refuse("cannot enter '%s'" % self.ws)
        # What `cd` leaves the children it starts: sh exports both.
        os.environ["OLDPWD"] = self.orig_pwd
        os.environ["PWD"] = logical(self.orig_pwd, self.ws)

        # tools/drives.sh: which machine this is, and whether a Bazel root
        # is per-user. From the workspace, as setup.sh, prime.sh, env-audit
        # and the wrapper read it, and never from beside the launcher: under
        # `bazel run` its $0 is bazel-bin's symlink and nothing sits beside
        # it, so the shell version exited 2 on every machine while the
        # selftest, which ran it from tools/, stayed green.
        # //tools/tests:selftest runs it the way `bazel run` does.
        if not os.access(self.ws + "/tools/drives.sh", os.R_OK):
            self.refuse("cannot read %s/tools/drives.sh, which says which machine this is" % self.ws)

        pins = self.pins_override or "tools/pins.tsv"
        if not os.access(pins, os.R_OK):
            self.refuse("cannot read %s" % pins)
        try:
            with open(pins, "rb") as f:
                text = decode(f.read())
        except OSError:
            self.refuse("cannot read %s" % pins)

        # ------------------------------------------------------- where am I
        campus = self.drives('drives_campus\nprintf "%s\\n%s" "$DRIVES_CAMPUS" "$DRIVES_CAMPUS_WHY"\n')
        self.on_campus, _, self.why = campus.partition("\n")
        # Anything else would read as "not a campus box" below.
        if self.on_campus not in ("0", "1"):
            self.refuse("%s/tools/drives.sh says DRIVES_CAMPUS='%s', which is neither 0 nor 1, so "
                        "which machine this is is not known" % (self.ws, self.on_campus))

        out("env_drift: comparing this machine against %s\n" % pins)
        if self.on_campus == "1":
            out("  machine: CAMPUS (%s)\n" % self.why)
            out("  This is the run that counts -- campus-kind pins must match here.\n")
        else:
            out("  machine: not a campus box (%s)\n" % self.why)
            out("  Rows marked campus compare this machine with campus. The pins describe\n")
            out("  campus, not this machine, so a difference here is nothing to fix on it.\n")
        out("\n")

        # IS THE FETCH HALF APPLICABLE AT ALL?
        #
        # The HERMETIC_* variables are set by //tools:env_drift's `env`, so
        # under `bazel run` they are all present and outside it none of them
        # are. Those two situations need opposite answers: one unset variable
        # among many is a pinned binary that stopped being compared, which is
        # drift; ALL of them unset is a run outside that target, where there
        # is nothing to compare and saying "drift" would be crying wolf on
        # every standalone invocation.
        #
        # Column 6 is "the variable holding the fetched path", whatever it is
        # called -- not necessarily HERMETIC_*. Matching on that prefix made
        # this probe blind to any other naming, which is precisely what the
        # selftest fixtures use.
        self.herm_set = False
        for rec in awk_records(text):
            f = rec.split("\t")
            if len(f) >= 6 and f[5] != "":
                for h in words(f[5]):
                    if env(h):
                        self.herm_set = True

        for line in read_lines(text):
            self.row(*sh_read(line, 6))

        out("\n")
        self.finish()

    def row(self, tool, kind, want, cmd, where, herm):
        if tool.startswith("#") or tool == "":
            return
        nostart = ""
        # A version-command of `-` means "recorded here, deliberately not
        # probed": a row nothing on this machine can be asked about from here
        # (pins.tsv's header names each one and why -- bazel and bazelisk
        # cannot be asked without re-entering Bazel and contending for the
        # lock this very command holds). They are still pinned --
        # //tools:conventions checks that the version this file records is
        # the version the file in `pinned-in` actually installs -- so "not
        # probed" is not "not checked". Whatever the row's kind, so it comes
        # first: rust-std-i686 is a fetched `-` row, and tested after the
        # kind it printed "not taken from this box" and was counted nowhere.
        if cmd == "-":
            self.recorded += 1
            out("  %s %s recorded %s (not probed: %s)\n" % (pad(tool, 11), pad(kind, 7), want, where))
            return
        # KIND `fetched`: the box is not consulted, because nothing here
        # uses its copy. shellcheck, zig and buildifier are downloaded by
        # Bazel against a sha256 and every layer runs THAT binary -- so an
        # apt-installed 0.8.0 sitting beside our pinned 0.10.0 is not drift,
        # it is irrelevant. Reporting it as drift would put a permanent false
        # red in front of the one check whose whole value is that a red means
        # something. The comparison that IS meaningful for these rows is
        # pin-vs-fetch, which the fetch half below already performs.
        #
        # One with no fetched-as column (rustc) names no fetched binary
        # either, so nothing here compares it: it is recorded, as a `-` row
        # is, and counted with them, so that the summary line accounts for
        # every row.
        if kind == "fetched":
            if not herm:
                self.recorded += 1
                out("  %s %s recorded %s (not probed: no fetched-as column; %s)\n" % (
                    pad(tool, 11), pad(kind, 7), want, where))
                return
            out("  %s %s not taken from this box\n" % (pad(tool, 11), pad(kind, 7)))
            got = ""
        elif cmd == "norminette-version":
            # As a box tool below: the output and the status apart. An
            # absent python3, or one that holds no norminette, leaves got
            # empty for the MISSING branch.
            no, nrc = sh(CAPTURED % NORMINETTE_PROBE)
            nout = subst(no)
            got = first_line(nout)
            if nrc == NORMINETTE_ABSENT or not command_v("python3"):
                got = ""
            elif nrc != 0 or start_failure(nout):
                nostart = "exit %d: %s" % (nrc, start_failure_line(nout) or got or "(it printed nothing)")
                got = ""
        elif before_last_word(cmd) == "default-std":
            got = self.default_std(after_first_word(cmd))
        else:
            # The output and the status APART, as the fetch half keeps them:
            # piped into first_line, the status was first_line's, and a box
            # tool that could not start was graded on its error, "ok
            # (repackaged)" for a loader error naming libbfd-2.38, the pin's
            # number (V328). One that is installed and exits non-zero, or
            # says what a program that did not start says, DID NOT START:
            # counted with the missing, since this box cannot run it either,
            # and never graded. An absent one is still MISSING, below.
            bo, brc = sh(CAPTURED % "$1", cmd)
            bout = subst(bo)
            got = first_line(bout)
            if (brc != 0 or start_failure(bout)) and command_v(first_word(cmd)):
                nostart = start_failure_line(bout) or got or "(it printed nothing)"
                nostart = "exit %d: %s" % (brc, nostart)
                got = ""

        # Ask about the binary the version COMMAND runs, not the row's name.
        # They are usually the same, and for one row they are not: glibc is
        # asked with `ldd --version`, because a C library has no executable
        # of its own. Testing the name meant reporting the runtime every
        # deliverable links against as MISSING on a machine that plainly has
        # it -- and a check that cries wolf on a healthy box is one people
        # learn to skim.
        # And norminette, a package and no binary, about the python3 it is
        # asked of.
        probe = first_word(cmd)
        if probe == "default-std":
            probe = after_first_word(cmd)
        elif cmd == "norminette-version":
            probe = "python3"
        if nostart:
            self.missing += 1
            out("  %s %s DID NOT START (%s)\n" % (pad(tool, 11), pad(kind, 7), nostart))
            # --strict fails on it as on an absent campus tool, without the
            # re-pin edit: the machine is at fault, not the pin.
            if kind == "campus":
                self.drift_lines += "\n  %s (did not start): expected %s; this box's %s did not start (%s)" % (
                    tool, want, probe, nostart)
        # `fetched` rows reach here with got empty ON PURPOSE, which is
        # precisely what the MISSING branch exists to report. Excluded by
        # kind, not by emptiness, so the branch keeps its meaning for every
        # other row.
        if (not nostart and kind != "fetched"
                and (got == "" or not command_v(probe))):
            self.missing += 1
            out("  %s %s MISSING   (expected %s)\n" % (pad(tool, 11), pad(kind, 7), want))
            # A campus tool that is ABSENT is campus drift, and --strict is
            # documented as "exit 1 on campus-kind drift". It counted into
            # MISSING and into neither list, and the two lists are the only
            # thing --strict looks at -- so a box carrying none of the pinned
            # tools printed a wall of MISSING and exited 0. The one kind of
            # machine the flag exists to reject was the one it accepted.
            #
            # Only campus-kind, deliberately: a tool absent on someone else's
            # laptop is ordinary, and a check that cries wolf there is one
            # people learn to skim.
            if kind == "campus":
                self.drift_lines += "\n  %s (missing): expected %s, not installed   (edit %s and tools/pins.tsv)" % (
                    tool, want, where)
            got = ""

        if got:
            self.grade_box(tool, kind, want, got, where)

        self.fetch(tool, kind, want, cmd, herm)

    def default_std(self, cc):
        """What language standard does a compiler assume when nobody says?

        This is not a version, and it is the thing that actually decides
        whether five of c-12's contracts accept correct code: under gnu17 an
        empty parameter list means "unspecified", under C23 it means
        "(void)". The suite pins -std=gnu17 explicitly, but the grade's own
        compile passes no -std at all -- so what matters here is the box's
        default, and it has to keep matching what we pin.

        Reported as "<__STDC_VERSION__> <gnu|strict>", which is the whole
        answer in two words: 201710L gnu.
        """
        if not cc:
            return "(no compiler)"
        if not command_v(cc):
            return "(not installed)"
        o, _ = sh('"$1" -dM -E -x c /dev/null 2>/dev/null', cc)
        return default_std_answer(decode(o))

    def grade_box(self, tool, kind, want, got, where):
        verdict = grade(want, got)
        head = "  %s %s" % (pad(tool, 11), pad(kind, 7))
        if verdict == "ok":
            self.match += 1
            out(head + " ok\n")
        elif verdict == "packaging":
            self.match += 1
            out(head + " ok (repackaged)\n")
            out("              pinned:   %s\n" % want)
            out("              this box: %s\n" % got)
            if kind == "campus" and self.on_campus == "1":
                out("              Same version, different package build: not drift, but the\n")
                out("              pin is campus's exact string: re-pin it in %s and tools/pins.tsv\n" % where)
                self.repin_lines += "\n  %s (repackaged): %s  ->  %s   (edit %s and tools/pins.tsv)" % (
                    tool, want, got, where)
            else:
                out("              Same version, different package build. Nothing to do.\n")
        else:
            self.drift += 1
            out(head + " DRIFT (%s)\n" % verdict)
            out("              pinned:   %s\n" % want)
            out("              this box: %s\n" % got)
            out("              pinned in %s\n" % where)
            if kind == "campus":
                self.drift_lines += "\n  %s (%s): %s  ->  %s   (edit %s and tools/pins.tsv)" % (
                    tool, verdict, want, got, where)

    # ---------------------------------------------- and what did we FETCH?
    def fetch(self, tool, kind, want, cmd, herm):
        if not herm:
            return
        hpath = self.abs_path(env(herm))
        if not hpath and not self.herm_set:
            # Outside //tools:env_drift: nothing was fetched, so there is
            # nothing to compare and this is not a finding.
            return
        # NOT a bare return for these two. This is the pin-vs-fetch
        # comparison -- the third of the three this file's header calls
        # non-optional -- and an unset HERMETIC_* means it did not happen.
        # Advising and moving on let the whole comparison disappear one
        # variable at a time while the run still reported no drift and
        # --strict still exited 0. Counted as fetch drift, and listed apart
        # from it: each is a fault of //tools:env_drift's wiring, never "the
        # pin was edited in one place", which the FETCH DRIFT banner says
        # (V326).
        if not hpath:
            self.fetch_drift += 1
            self.wiring_lines += ("\n  %s: %s is unset, so the fetched binary was never compared "
                                  "(add it to //tools:env_drift data)" % (tool, herm))
            out("              fetched:  NOT COMPARED (%s unset -- add the binary to //tools:env_drift data)\n" % herm)
            return
        if not os.access(hpath, os.X_OK):
            self.fetch_drift += 1
            self.wiring_lines += ("\n  %s: %s names %s, which is not an executable "
                                  "(fix //tools:env_drift's data, and run it with bazel run)" % (tool, herm, hpath))
            out("              fetched:  MISSING at %s\n" % hpath)
            return
        hlibs = self.abs_libdir_list(env(herm + "_LIBS"))
        bad = ""
        for d in colon_fields(hlibs):
            if not os.path.isdir(d):
                bad = d
        if bad:
            self.unrunnable += 1
            out("              fetched:  UNRUNNABLE (no library dir at %s)\n" % bad)
            self.unrun_lines += ("\n  %s: %s_LIBS names '%s', which does not exist -- the binary would "
                                 "silently load this machine's libraries instead (fix //tools:env_drift's data)"
                                 % (tool, herm, bad))
            return
        # <VAR>_TOOLS: a FILE inside valgrind's tool directory, as the
        # layers' --valgrind-tools. Its directory is $VALGRIND_LIB, without
        # which valgrind.bin starts the BOX's memcheck from
        # /usr/libexec/valgrind, or none ("failed to start tool"): --version
        # starts the tool too, so the version reported without it was never
        # the fetched tree's alone. Its links resolved, as valgrind_test.sh
        # derives it.
        htools = env(herm + "_TOOLS")
        hvglib = ""
        if htools:
            htools = self.abs_path(htools)
            hvglib = dirname(os.path.realpath(htools))
            if not os.path.isfile(htools):
                self.unrunnable += 1
                out("              fetched:  UNRUNNABLE (no tool file at %s)\n" % htools)
                self.unrun_lines += ("\n  %s: %s_TOOLS names '%s', which does not exist "
                                     "(fix //tools:env_drift's data)" % (tool, herm, htools))
                return
        # The row's OWN flags, not a hardcoded --version. `zig --version` is
        # an error -- the subcommand is `zig version` -- so a hardcoded flag
        # reports the pinned zig as unversioned and grades a correct fetch as
        # major drift. Rows whose command is not "<tool> <flags>"
        # (norminette-version) keep --version, which is what they were
        # already getting.
        hargs = after_first_word(cmd)
        if hargs == cmd:
            hargs = "--version"
        # The output and the status APART: piped into first_line, the status
        # was first_line's, and a binary the loader could not start (exit
        # 127) was graded on its error message (V243).
        hout, hrc = self.fetched_run(hlibs, hvglib, hpath, words(hargs))
        hgot = first_line(hout)
        # <VAR>_COMPILE: the words a compiler is also run with, a compile of
        # an empty C file. --version runs the driver alone, and a compile
        # starts what the driver hands it to (gcc's cc1, with libraries of
        # its own): a driver can answer --version on a machine where every
        # compile fails.
        hcomp = env(herm + "_COMPILE")
        if hrc == 0 and hcomp and not start_failure(hout):
            hout, hrc = self.fetched_run(hlibs, hvglib, hpath, words(hcomp))
            if hrc == 0:
                hcomp = ""
        else:
            hcomp = ""
        if hrc != 0 or start_failure(hout):
            hwhy = start_failure_line(hout) or first_line(hout) or "(it printed nothing)"
            hhow = (hcomp + ", " if hcomp else "") + "exit %d" % hrc
            self.unrunnable += 1
            out("              fetched:  UNRUNNABLE (%s: %s)\n" % (hhow, hwhy))
            self.unrun_lines += "\n  %s (%s): %s" % (tool, hhow, hwhy)
            return
        hbanner = pin_banner(want)
        if hbanner not in hgot:
            self.fetch_drift += 1
            out("              fetched:  DRIFT (another tool)\n")
            out("                        pinned:  %s\n" % want)
            out("                        fetched: %s\n" % hgot)
            self.fetch_lines += ("\n  %s (another tool): pins.tsv says '%s', and the fetched binary's line "
                                 "'%s' lacks the pin's words '%s' (which file does //tools:env_drift's data "
                                 "give %s?)" % (tool, want, hgot, hbanner, herm))
            return
        hverdict = grade(want, hgot)
        # packaging counts as ok here too: the fetch is pinned by sha256, so
        # the only question this comparison answers is whether the binary
        # reports the version pins.tsv claims, and a version command that
        # also prints its interpreter and libc is not drift.
        if hverdict in ("ok", "packaging"):
            # A `fetched` row has no box half, so this IS its verdict and it
            # has to count as one -- otherwise the summary's "N match"
            # silently stops covering three of the tools that decide
            # verdicts.
            if kind == "fetched":
                self.match += 1
            out("              fetched:  ok (%s)\n" % hgot)
        else:
            self.fetch_drift += 1
            out("              fetched:  DRIFT (%s)\n" % hverdict)
            out("                        pinned:  %s\n" % want)
            out("                        fetched: %s\n" % hgot)
            self.fetch_lines += "\n  %s (%s): pins.tsv says '%s', the fetched binary says '%s'" % (
                tool, hverdict, want, hgot)

    def stale_toolchain(self, root):
        """THE C++ TOOLCHAIN BAZEL CACHED, which no row above can see.

        `cc_binary` builds with the pinned //tools/cc_toolchain by default
        (MODULE.bazel). The toolchain rules_cc AUTO-DETECTS from the box is
        reached only by --config=gcc (.bazelrc), and it survives in output
        bases cached before the pin. Where it exists, auto-detection ran
        ONCE, writes absolute paths into external/..._local_config_cc/BUILD
        as `tool_paths = {"ar": "...", ...}`, and caches them for the life
        of the output base. It does not re-run because PATH changed.

        So: a student with Homebrew on PATH gets `~/.linuxbrew/bin/ar`
        recorded. They later uninstall Homebrew -- which this repo actively
        recommends, because that same brew shadows the pinned binutils --
        and every link then dies with

            execvp(/home/<user>/.linuxbrew/bin/ar): No such file or directory

        That happened. Nothing above could have caught it: pins.tsv's `ar`
        row compares the pin against the box's `ar`, which is fine and
        present; what is broken is the third thing, the path a cached
        toolchain still points at.

        Read-only and best-effort: no `bazel` is run (this must work on a
        box where nothing is set up), and anything unreadable is silently
        skipped. The output bases are globbed from the root Bazel actually
        uses for this checkout: the one this `bazel run` is in, read back
        from the working directory, else the one tools/drives.sh predicts,
        the wrapper's rules included, creating nothing.
        """
        stale = ""
        if not root or not os.path.isdir(root):
            return stale
        for cc in sorted(glob.glob(glob.escape(root) + "/*/external/*local_config_cc/BUILD")):
            if not os.path.isfile(cc):
                continue
            try:
                with open(cc, "rb") as f:
                    text = decode(f.read())
            except OSError:
                continue
            for tp in collated(tool_paths(text)):
                if os.access(tp, os.X_OK):
                    continue
                stale += "\n  %s   (recorded in %s)" % (tp, cc[:-len("/BUILD")])
        return stale

    def finish(self):
        # Where this checkout's Bazel state is: the output base this `bazel
        # run` uses when started by one (the root above it), else the root
        # Bazel would use here, predicted -- and on a campus box the warning
        # for it. Asked of tools/drives.sh in one go.
        ends = self.drives(
            'if _our=$(drives_run_base "$2" "$3"); then\n'
            '\t_our=${_our%/*}\n'
            'else\n'
            '\t_our=$(drives_predicted_root "$1")\n'
            'fi\n'
            'printf "%s\\0" "$_our"\n'
            'if [ "$4" = 1 ]; then\n'
            '\t_warn=$(drives_root_warning "$(drives_state_of "$1" "$2" "$3")" "$1")\n'
            '\tprintf "%s" "$_warn"\n'
            'fi\n',
            self.orig_pwd, self.self_path, self.on_campus)
        our, _, warn = ends.partition("\0")
        stale = self.stale_toolchain(our)

        # `42 doctor` reads this line: see the header before rewording it.
        summary = "%d match, %d drifted, %d missing, %d fetch-drift, %d unrunnable, %d recorded" % (
            self.match, self.drift, self.missing, self.fetch_drift, self.unrunnable, self.recorded)
        out("  %s\n" % summary)

        if stale:
            out("\n")
            out("  STALE C++ TOOLCHAIN — a cached tool path no longer exists. Every\n")
            out("  link will fail with \"execvp(...): No such file or directory\" until\n")
            out("  this is invalidated. Bazel auto-detects these ONCE per output base\n")
            out("  and does not re-run because PATH changed:\n")
            out(stale + "\n")
            out("\n")
            out("  Fix, cheapest first -- the repository cache is a SIBLING of the\n")
            out("  output base and survives both, so neither re-downloads anything.\n")
            out("  Re-detect just this:\n")
            out("\n")
            out("      rm -rf <recorded-dir> <recorded-dir>.marker\n")
            out("\n")
            out("  or start clean:\n")
            out("\n")
            out("      bazel clean --expunge\n")
            out("\n")
            out("  The usual cause is a tool that WAS on PATH when the toolchain was\n")
            out("  detected and is not now -- uninstalling Homebrew is the common one.\n")

        # The prose is for whoever can act on it: on campus, the difference
        # is between the pins and the machines the grade comes from, and it
        # goes to whoever keeps the pins. Off campus it is between your
        # machine and campus, and the pins describe campus, not your machine
        # -- one line, and nothing to do. The count above and --strict are
        # the same on both.
        if self.on_campus == "1" and (self.drift_lines or self.repin_lines):
            if self.drift_lines:
                out("\n")
                out("  CAMPUS-KIND DRIFT. These decide whether the suite tests the same\n")
                out("  toolchain the grade comes from, so they are the ones worth acting on:\n")
                out(self.drift_lines + "\n")
            if self.repin_lines:
                out("\n")
                out("  CAMPUS-KIND REPACKAGING. The same version in a different package build:\n")
                out("  not drift, and --strict ignores it, but each campus pin is campus's\n")
                out("  exact string, so these are re-pinned too:\n")
                out(self.repin_lines + "\n")
            out("\n")
            # A did-not-start line names no pin to edit: the box is at fault.
            if "(edit " in self.drift_lines + self.repin_lines:
                out("  Nothing for you to fix: whoever keeps the pins re-pins by hand, in both\n")
                out("  places named above -- deliberately not automatic, since a pin changed by\n")
                out("  a script is a change to what the suite tests that nobody decided. So\n")
                out("  that they hear of it, record this machine with\n")
            else:
                out("  No pin is wrong here: a tool this box has would not start, which is\n")
                out("  the machine's fault, not the pins'. So that whoever keeps the pins\n")
                out("  hears of it, record this machine with\n")
            out("      sh tools/env-audit.sh\n")
            out("  and send them the report it writes under tools/env-reports/. In a clone\n")
            out("  of the public template that is an environment issue, opened from\n")
            out("      https://github.com/Jofre/42-template/issues/new/choose\n")
            out("  (--push reaches only your own origin). Issues there are public and the\n")
            out("  report names you: replace your login and this machine's name everywhere\n")
            out("  in it, and rename it (its file name is the machine's), before you attach it.\n")
        elif self.drift_lines:
            out("\n")
            out("  Campus-kind rows differ from the pins on this machine, which is not a\n")
            out("  campus box: nothing to do here (the pins describe campus).\n")

        # Where this checkout's Bazel state is, on a campus box. Asked only
        # on campus: off it there is nothing to warn about.
        if self.on_campus == "1" and warn:
            out("\n")
            for line in lines_of(warn):
                out("  %s\n" % line)

        if self.fetch_lines:
            out("\n")
            out("  FETCH DRIFT — worse than campus drift, and never noise. What Bazel\n")
            out("  downloaded is not what pins.tsv claims it downloads, and a fetch is\n")
            out("  pinned by sha256, so this cannot be a repackaging. Two versions on a\n")
            out("  line mean the pin was edited in one place and not the other; a line\n")
            out("  that says \"another tool\" means //tools:env_drift's data hands the row\n")
            out("  another binary, or the pin's words were edited. Until it is fixed,\n")
            out("  pins.tsv describes a toolchain nothing actually runs:\n")
            out(self.fetch_lines + "\n")

        if self.wiring_lines:
            out("\n")
            out("  NOT COMPARED — the fetched binary of these rows was never compared\n")
            out("  with its pin, so nothing says the checks run what pins.tsv describes.\n")
            out("  The pins are not at fault: each line is a fault in //tools:env_drift's\n")
            out("  data, or a run of this script that did not come from that target:\n")
            out(self.wiring_lines + "\n")

        if self.unrun_lines:
            out("\n")
            out("  UNRUNNABLE — a fetched tool did not start on this machine, so it was\n")
            out("  compared with nothing, and every check that runs it fails here too.\n")
            out("  The pins are not at fault: most fetched tools are Ubuntu 22.04 builds\n")
            out("  that load some shared libraries from this machine, so the usual cause\n")
            out("  is a library it lacks, or a system newer than 22.04. The dev container\n")
            out("  gives them the system they were built for (docs/environment.md). A\n")
            out("  line that names //tools:env_drift's data is a fault in that target:\n")
            out(self.unrun_lines + "\n")

        # A report asked for and not written is exit 2: what was asked for
        # did not happen, whatever the comparison found.
        if self.report and not self.write_report(summary):
            sys.stdout.buffer.flush()
            sys.exit(2)

        sys.stdout.buffer.flush()
        if self.strict and (self.drift_lines or self.fetch_lines or self.wiring_lines or self.unrun_lines):
            sys.exit(1)
        sys.exit(0)

    def write_report(self, summary):
        """The report under tools/env-reports/; whether it was written.

        It printed "report written to" and "commit it" after failing to
        create the folder or the file, and exited 0.
        """
        try:
            os.makedirs("tools/env-reports", exist_ok=True)
        except OSError as e:
            err("%s: report NOT written: cannot create directory 'tools/env-reports': %s\n" % (PROG, e.strerror))
            return False
        stamp = time.strftime("%Y-%m-%dT%H-%M-%SZ", time.gmtime())
        host = host_name()
        name = "tools/env-reports/drift-%s-%s.txt" % (host, stamp)
        body = ("env_drift report\n"
                "host:     %s\n"
                "when:     %s\n"
                "campus:   %s (%s)\n"
                "result:   %s\n" % (host, stamp, self.on_campus, self.why, summary))
        for lines in (self.drift_lines, self.repin_lines, self.fetch_lines, self.wiring_lines, self.unrun_lines):
            if lines:
                body += lines + "\n"
        try:
            with open(name, "wb") as f:
                f.write(encode(body))
        except OSError as e:
            err("%s: report NOT written: cannot create %s: %s\n" % (PROG, name, e.strerror))
            return False
        out("\n")
        out("  report written to %s\n" % name)
        out("  (commit it -- a timestamped history of what each box carried is how\n")
        out("   'when did campus move?' stops being guesswork)\n")
        return True


def restore_locale(state):
    """The caller's LC_CTYPE, back in the environment every probe inherits.

    Python started in the C locale "coerces" it: it sets LC_CTYPE=C.UTF-8 in
    its own environment, and -I cannot turn that off. Every tool this asks
    would then answer in a locale its caller never chose. The launcher says
    what it was: "=<value>", or "" for none.
    """
    if state.startswith("="):
        os.environ["LC_CTYPE"] = state[1:]
    else:
        os.environ.pop("LC_CTYPE", None)


def main(argv):
    # A reader that stops reading (`| head`) ends this as it ended the
    # shell, and so does ^C: by the signal, with no traceback.
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    if len(argv) < 4:
        err("%s: env_drift.py is started by tools/env_drift.sh, never by hand: "
            "bazel run //tools:env_drift\n" % PROG)
        return 2
    restore_locale(argv[3])
    Drift(argv[1], argv[2], argv[4:]).main()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
