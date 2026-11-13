"""//tools/tests:userconfig_oracle_test -- the user file's grammar, held to two real YAML readers.

userconfig.py reads and writes a subset of YAML itself, because 42 runs with
nothing installed. Its promise is that every file it accepts reads the same to
any YAML reader. So that promise is checked here against two real ones, which
Bazel fetches pinned (tools/requirements.txt) and 42 itself never imports:

  PyYAML       YAML 1.1, both its pure-Python loader and, where the wheel
               carries it, the libyaml one (CSafeLoader);
  ruamel.yaml  YAML 1.2, its pure-Python loader.

Every file 42 accepts must read, under each, as exactly the mapping 42 reads:
the same names, each value that string, or a decimal read as the number it
spells. The files are the corpus (userconfig_corpus.CASES, whose expectations
are checked here too), everything userconfig.render writes, every file
userconfig.edit writes, and a seeded fuzz of files built from the shapes YAML
reads differently. A file 42 refuses is never a failure here: refusing is
always safe. A run says how many files it checked of each kind.
"""

import os
import random
import re
import sys

# Nothing here writes a file, but whatever does later writes under TEST_TMPDIR,
# which Bazel empties, and not in the machine's /tmp (fortytwo_test.py says why).
if os.environ.get("TEST_TMPDIR") and os.environ.get("TMPDIR", "/tmp").rstrip("/") in ("", "/tmp"):
    os.environ["TMPDIR"] = os.environ["TEST_TMPDIR"]

here =os.path.join(os.environ.get("TEST_SRCDIR", ""), "_main", "tools", "fortytwo")
if not os.path.isdir(here):
    here = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "fortytwo")
sys.path[:0] = [here, os.path.join(here, "tests")]

import yaml  # noqa: E402
from ruamel.yaml import YAML  # noqa: E402
import ruamel.yaml  # noqa: E402

import userconfig  # noqa: E402
from userconfig_corpus import CASES, NAMES, Refused  # noqa: E402

FUZZ = int(os.environ.get("USERCONFIG_FUZZ", "30000"))

ruamel_safe = YAML(typ="safe", pure=True)
READERS = [("PyYAML %s SafeLoader" % yaml.__version__, lambda d: yaml.load(d, Loader=yaml.SafeLoader)),
           ("ruamel.yaml %s safe" % ruamel.yaml.__version__, ruamel_safe.load)]
if getattr(yaml, "CSafeLoader", None):
    READERS.append(("PyYAML %s CSafeLoader (libyaml)" % yaml.__version__,
                    lambda d: yaml.load(d, Loader=yaml.CSafeLoader)))
else:
    print("userconfig_oracle: this PyYAML has no libyaml loader here, so libyaml was not asked")

failures = []


def same(theirs, ours):
    """Whether a reader's result is the mapping 42 read."""
    if theirs is None:
        theirs = {}
    if type(theirs) is not dict or set(theirs) != set(ours):
        return False
    for k, v in ours.items():
        t = theirs[k]
        if type(t) is str and t == v:
            continue
        if type(t) is int and re.fullmatch(userconfig.DECIMAL, v) and str(t) == v:
            continue
        return False
    return True


def ours(data):
    try:
        return {k: v for k, (v, _) in userconfig.parse(data).items()}
    except userconfig.Bad:
        return None


def check(kind, data, want=None):
    """Every reader reads data as 42 does; want, when given, is what 42 must read. 1 if 42 accepts it."""
    got = ours(data)
    if want is not None and got != want:
        failures.append("%s: 42 reads %r as %r, not %r" % (kind, data, got, want))
        return 0
    if got is None:
        return 0
    for name, load in READERS:
        try:
            theirs = load(data)
        except Exception as e:  # any refusal of theirs is a disagreement: 42 read it
            theirs = "%s: %s" % (type(e).__name__, str(e).splitlines()[0] if str(e) else "")
        if not same(theirs, got):
            failures.append("%s: %r: 42 reads %r, %s reads %r" % (kind, data, got, name, theirs))
    return 1


# Values as 42 would be handed them, each awkward to some YAML.
VALUES = ["strict", "complete", "no", "NO", "y", "n", "~", "null", "", " ", "0", "600", "0755", "012", "1_0",
          "12:30", "1:2:3", "2026-10-23", "1e3", ".inf", ".NaN", "-1", "+1", "0x1f", "0b1", "0o7", "1.5",
          "a b", "a #b", "a#b", "#a", "a:", "a: b", "a,b", "[a]", "{a: b}", "&a", "*a", "!a", "|", ">", "@a",
          "%a", "`a`", "?a", "-", "- a", "'", '"', "\\", "\\n", "\t", "\n", "\r", "\r\n", "\x00", "\x07",
          "\x7f", "\x85", "\x9b", "\u2028", "\u2029", "\ufeff", "\ufffe", "\uffff", "\u00e9", "\u4e2d",
          "\U0001f600", "git@git.example.com:you/c-05.git", "ssh://h:22/x", "https://e.com/a?b=c&d",
          "/abs", "/", "a/", "a=b", "=", "<<", "jdoe@student.42.fr", "C:\\x", "line1\nline2", "--", "---",
          "...", "a  b", " a", "a ", "yes", "On", "TRUE", "False", "Null", "NULL", "x" * 300]
# The pieces fuzzed files are made of: names, what follows them, and lines of every other kind.
NAME_BITS = ["a", "b", "level", "remote.c-05", "remote.cursus/Milestone_0/Libft", "bazel.idle_secs", "A",
             "a_b", "on", "y", "no", "null", "1a", "a b", '"a"', "'a'", "", "-a", "a:", "?", "a.b."]
SEPS = [": ", ":", ":  ", ":\t", " : ", ":\u00a0", ": \t"]
TAILS = ["", " ", "   ", " # c", "#c", " #", "  # c d", " # \tc", "\t# c", " # \x85x", " # \u2028",
         " # \x01", " # \x7f", " # \u00e9", " # #", " # :", " # 'x'"]
ODD = ["\t", "\x85", "\u2028", "\u2029", "\ufeff", "\x7f", "\x01", "\x1b", "\u00e9", "\U0001f600", "\ufffe",
       "\\", '"', "'", "#", ":", " ", "-", "?", "&", "*", "!", "|", ">", "%", "@", "`", "{", "}", "[", "]",
       ",", "\r", "\u00a0", "0", "1", "a", "z", "/", "."]
ENDS = ["\n", "\n", "\n", "\r\n", "\r", ""]


def value_token(rng):
    v = rng.choice(VALUES)
    r = rng.random()
    if r < 0.35:
        return v  # raw, as someone might type it
    if r < 0.6:
        try:
            return userconfig.render(v)
        except userconfig.Bad:
            return v
    if r < 0.75:
        return "'%s'" % v.replace("'", rng.choice(["''", "'"]))
    if r < 0.9:
        esc = ["\\\"", "\\\\", "\\/", "\\b", "\\f", "\\n", "\\r", "\\t", "\\u00e9", "\\ud83d", "\\x41",
               "\\a", "\\e", "\\N", "\\ ", "\\0", "\\L", "\\P", "\\_", "\\U0001F600"]
        return '"%s"' % "".join(rng.choice(esc + ["x", " ", "#", "'", "\u00e9", "\t"]) for _ in range(rng.randint(0, 4)))
    return "".join(rng.choice(ODD) for _ in range(rng.randint(1, 5)))


def fuzz_line(rng):
    r = rng.random()
    if r < 0.6:
        return rng.choice(NAME_BITS) + rng.choice(SEPS) + value_token(rng) + rng.choice(TAILS)
    if r < 0.7:
        return " " * rng.randint(0, 3) + "#" + "".join(rng.choice(ODD) for _ in range(rng.randint(0, 4)))
    if r < 0.78:
        return rng.choice(["", " ", "  "])
    if r < 0.84:
        return rng.choice(["---", "--- ", "...", "%YAML 1.2", "- a", "? a", ": b"])
    if r < 0.9:
        return " " * rng.randint(1, 3) + rng.choice(NAME_BITS) + ": " + value_token(rng)
    return "".join(rng.choice(ODD) for _ in range(rng.randint(1, 6)))


def fuzz_file(rng):
    lines = [fuzz_line(rng) for _ in range(rng.randint(0, 5))]
    text = "".join(line + rng.choice(ENDS[:5]) for line in lines[:-1])
    if lines:
        text += lines[-1] + rng.choice(ENDS)
    data = text.encode("utf-8", "surrogatepass")
    if rng.random() < 0.05:
        data = userconfig.BOM + data
    if rng.random() < 0.02:
        data += b"\xff"
    return data


def main():
    counts = {}
    corpus = 0
    for label, data, want in CASES:
        if isinstance(want, Refused):
            continue
        corpus += check("corpus %r" % label, data, want)
    counts["corpus files"] = corpus

    rendered = 0
    for v in VALUES + ["%s%s" % (a, b) for a in ODD for b in ("x", "")]:
        try:
            token = userconfig.render(v)
        except userconfig.Bad:
            continue
        rendered += check("render %r" % v, ("k: %s\n" % token).encode("utf-8"), {"k": v})
    counts["rendered values"] = rendered

    rng = random.Random(int(os.environ.get("USERCONFIG_SEED", "4242")))
    accepted = edited = 0
    for i in range(FUZZ):
        data = fuzz_file(rng)
        if check("fuzz #%d" % i, data):
            accepted += 1
            # And what 42 would write over it: a change, an addition, a removal.
            names = list(userconfig.parse(data))
            for name, value in ((rng.choice(names) if names else "level", rng.choice(VALUES)),
                                (rng.choice(NAMES), rng.choice(VALUES)),
                                (rng.choice(names) if names else "zz", None)):
                try:
                    new = userconfig.edit(data, name, value)
                except userconfig.Bad:
                    continue
                edited += check("edit #%d %s=%r" % (i, name, value), new)
    counts["fuzzed files"] = FUZZ
    counts["of them accepted"] = accepted
    counts["edited files"] = edited

    readers = ", ".join(n for n, _ in READERS)
    if failures:
        print("userconfig_oracle: FAIL, %d disagreement(s) with %s" % (len(failures), readers))
        for f in failures[:40]:
            print("  " + f)
        if len(failures) > 40:
            print("  ... and %d more" % (len(failures) - 40))
        return 1
    if not accepted or not corpus or not rendered or not edited:
        print("userconfig_oracle: FAIL, a kind of file was never checked: %r" % counts)
        return 1
    print("userconfig_oracle: OK (%s) against %s" % (", ".join("%d %s" % (n, k) for k, n in counts.items()), readers))
    return 0


if __name__ == "__main__":
    sys.exit(main())
