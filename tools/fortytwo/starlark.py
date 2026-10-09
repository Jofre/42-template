"""--show_starlark: which macro call in which BUILD file declares each test of a run.

From two query views only, by the owner's decision: `--output=location`, which
prints a BUILD file, a line and a label, and `attr()` membership tests against
the fixed names below, which answer with labels. No attribute value is ever
printed, nor any comment: a call's arguments can name the reference its test
compares with, and BUILD comments are held to no rule yet.
"""

import os
import re
import subprocess

import bazel

# The macros a project's BUILD file calls that declare tests (18 on
# 2026-10-09), and the levels (tools/defs.bzl, _LEVEL_NAMES). A test whose
# macro is none of these would show "?": test_starlark holds every call a
# project's BUILD file makes to this list or to NOT_TESTS, so a new macro is a
# decision, not a gap.
MACROS = (
    "c_function", "c_program", "c_diff", "c_levels", "shell_exercise", "rush_variant",
    "c_mem_check", "c_make", "c_header", "hand_test", "c_cycles", "corpus_memory",
    "c_argv_table", "rush_common", "c_libft", "c_files", "c_reference_cost", "c_issued",
)
LEVELS = ("basic", "strict", "robust", "complete")

LOCATION = re.compile(r"^(?P<path>.+?):(?P<line>\d+):(?P<col>\d+): (?P<kind>\S+) rule (?P<label>//\S+)$")


def has_tag(tag, expr):
    # A list attribute is matched as "[a, b, c]": the tag between a bracket or a
    # blank and a comma or a bracket (Bazel's query docs, attr).
    return 'attr(tags, "[\\[ ]%s[,\\]]", %s)' % (tag, expr)


def expression(patterns, tag_filter):
    """The query set of `bazel test PATTERNS --test_tag_filters=FILTER`."""
    expr = "tests(%s)" % " + ".join(patterns)
    if not tag_filter:
        return expr
    words = [w for w in tag_filter.split(",") if w]
    keep = [w for w in words if not w.startswith("-")]
    drop = [w[1:] for w in words if w.startswith("-")]
    out = " + ".join(has_tag(t, expr) for t in keep) if keep else expr
    if keep and len(keep) > 1:
        out = "(%s)" % out
    for t in drop:
        out = "%s except %s" % (out, has_tag(t, expr))
    return out


def query(exe, ws, env, expr, output="label"):
    r = subprocess.run([exe, "query", expr, "--output=" + output, "--keep_going"],
                       cwd=ws, env=bazel.child_env(env), stdin=subprocess.DEVNULL,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
                       check=False)
    return r.returncode, r.stdout.splitlines(), r.stderr


def locations(lines, ws):
    """{label: (BUILD file from the checkout's root, line)} from --output=location."""
    # The file itself is not resolved: in a tree of links (Bazel's runfiles)
    # that would lead out of the checkout. Its folder may be named either way.
    roots = {os.path.abspath(ws), os.path.realpath(ws)}
    out = {}
    for line in lines:
        m = LOCATION.match(line.strip())
        if not m:
            continue
        path = rel = os.path.abspath(m.group("path"))
        for root in roots:
            if path.startswith(root + os.sep):
                rel = os.path.relpath(path, root)
        out[m.group("label")] = (rel, int(m.group("line")))
    return out


def show(ctx, scope, level):
    patterns, tag_filter = ctx.W.selection(scope, level)
    expr = expression(patterns, tag_filter)
    argv = ["bazel", "query", expr, "--output=location"]
    ctx.show(argv)
    if ctx.args.dry_run:
        ctx.out.say("  and one `attr()` query per macro (%d) and per level (%d), each\n"
                    "  answered with labels." % (len(MACROS), len(LEVELS)))
        return 0
    exe = ctx.bazel()
    rc, lines, err = query(exe, ctx.ws, ctx.env, expr, "location")
    if rc not in (0, 3):  # 3: some patterns failed under --keep_going; the rest is shown
        ctx.out.say(err.rstrip())
        return rc
    where = locations(lines, ctx.ws)
    if not where:
        ctx.out.say("42 test %s, level %s: no test is selected." % (scope.describe(), level))
        return 0
    # A test has one macro and one lowest level, so each loop stops once every
    # test has its answer: most scopes need two or three queries, not 23.
    macro = {}
    for name in MACROS:
        if len(macro) == len(where):
            break
        _, got, _ = query(exe, ctx.ws, ctx.env, 'attr(generator_function, "^%s$", %s)' % (name, expr))
        for label in got:
            macro.setdefault(label.strip(), name)
    lvl = {}
    for name in LEVELS:
        if len(lvl) == len(where):
            break
        _, got, _ = query(exe, ctx.ws, ctx.env, has_tag("lvl_" + name, expr))
        for label in got:
            lvl.setdefault(label.strip(), name)
    manual = set()
    if len(lvl) < len(where):
        _, got, _ = query(exe, ctx.ws, ctx.env, has_tag("manual", expr))
        manual = {l.strip() for l in got}

    ctx.out.say("42 test %s, level %s: %d test(s), each declared by a macro call.\n"
                % (scope.describe(), level, len(where)))
    rows = sorted(where.items(), key=lambda kv: (kv[1][0], kv[1][1], kv[0]))
    width = max(len("%s:%d" % v) for _, v in rows)
    for label, (path, line) in rows:
        pkg = os.path.dirname(path).replace(os.sep, "/")
        name = label.split(":", 1)[1] if label.startswith("//%s:" % pkg) else label
        level_of = lvl.get(label) or ("manual" if label in manual else "-")
        ctx.out.say("  %-*s  %-16s %-9s %s" % (width, "%s:%d" % (path, line),
                                               macro.get(label, "?"), level_of, name))
    ctx.out.say("\n  Each line: the BUILD file and line of the call, the macro it calls\n"
                "  (tools/defs.bzl defines them), the lowest level that runs the test\n"
                "  (docs/reference.md, the ladder), and the test's name. A call's\n"
                "  arguments are left out.")
    return 0
