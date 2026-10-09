"""42 -- one command over this repo's Bazel harness. Started by tools/42.sh.

Every command runs a Bazel target, or Bazel itself; tools/fortytwo/commands.tsv
says which, and `42 help` is printed from it. 42 adds no check of its own:
what a run reports is first_red.sh's and the tests' own logs.
"""

import os
import sys

# python3 -I (tools/42.sh) leaves the script's own folder off sys.path; the
# modules beside this file are the only ones it adds.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import argparse  # noqa: E402
import shutil  # noqa: E402
import textwrap  # noqa: E402
import time  # noqa: E402

import bazel  # noqa: E402
import report  # noqa: E402
import taint  # noqa: E402
import workspace  # noqa: E402
from workspace import LEVELS, UsageError, Workspace, resolve_level  # noqa: E402

VERSION = "1"


# ---------------------------------------------------------------------------
# The registry

def load_registry(ws):
    rows = []
    path = os.path.join(ws, "tools", "fortytwo", "commands.tsv")
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            cols = line.split("\t")
            if len(cols) != 5:
                raise RuntimeError("%s:%d: %d columns, not 5" % (path, n, len(cols)))
            rows.append(dict(zip(("command", "usage", "runs", "audience", "text"), cols)))
    return rows


# ---------------------------------------------------------------------------
# Output

class Out:
    def __init__(self, plain=False):
        self.tty = sys.stderr.isatty() and not plain
        self._ticking = False

    def say(self, text=""):
        self.clear_tick()
        print(text, flush=True)

    def err(self, text):
        self.clear_tick()
        print(text, file=sys.stderr, flush=True)

    def tick(self, text):
        if self.tty:
            sys.stderr.write("\r\033[K" + text)
            sys.stderr.flush()
            self._ticking = True

    def clear_tick(self):
        if self._ticking:
            sys.stderr.write("\r\033[K")
            sys.stderr.flush()
            self._ticking = False


class Ctx:
    def __init__(self, ws, cwd, environ, args):
        self.ws = ws
        self.cwd = cwd
        self.env = environ
        self.args = args
        self.W = Workspace(ws, cwd)
        self.out = Out(getattr(args, "plain", False))

    def show(self, argv, pipe=False):
        """--show_bazel and --dry-run: the command, as a student would type it."""
        if self.args.show_bazel or self.args.dry_run:
            line = bazel.shell_line(argv)
            if pipe:
                line += " 2>&1 | sh tools/first_red.sh"
            self.out.say("$ " + line)

    def show_line(self, line):
        """--show_bazel and --dry-run: a shell line that is not one Bazel command."""
        if self.args.show_bazel or self.args.dry_run:
            self.out.say("$ " + line)

    def bazel(self):
        return bazel.executable(self.env)


# ---------------------------------------------------------------------------
# help

def here_line(ctx):
    """Where you are, and what `42 test` would run from here. No Bazel call."""
    try:
        scope = ctx.W.scope_of_path(ctx.cwd)
        level, source = resolve_level(None, ctx.env, ctx.ws)
    except (UsageError, OSError, RuntimeError) as e:
        return "  here: %s" % e
    where = "default" if source == "default" else "from " + source
    if scope.project is None:
        if ctx.W.rel(ctx.cwd) is None:
            return "  here: outside this checkout (%s)." % ctx.ws
        return ("  here: no project (the repo root). `42 test` needs one: run it in a\n"
                "  project's folder, or name it (42 test c-05).")
    return "  here: %s, level %s (%s).\n  `42 test` runs these tests; `42 test --level L` another level." % (
        scope.describe(), level, where)


def print_help(ctx, every=False, command=None):
    rows = load_registry(ctx.ws)
    if command:
        row = next((r for r in rows if r["command"] == command), None)
        if row is None:
            raise UsageError("no command %r. `42 help` lists them." % command)
        ctx.out.say("42 %s %s\n\n  %s\n  Runs: %s" % (command, row["usage"], row["text"], row["runs"]))
        if command in ("test", "watch", "clues"):
            ctx.out.say(WORDS_HELP % {"projects": wrap(ctx.W.project_list(), 16),
                                      "layers": wrap(" ".join(ctx.W.layers()), 16)})
        if command == "test":
            ctx.out.say(TEST_FLAGS_HELP % {"levels": " ".join(LEVELS)})
        return 0
    ctx.out.say("42 -- run this repo's tests the way you think about them.\n")
    ctx.out.say(here_line(ctx) + "\n")
    audiences = ("student", "maintainer") if every else ("student",)
    for aud in audiences:
        if aud == "maintainer":
            ctx.out.say("\n  for maintainers:")
        for r in rows:
            if r["audience"] != aud or r["command"] == "-":
                continue
            ctx.out.say(("  42 %s %s" % (r["command"], r["usage"])).rstrip())
            ctx.out.say("        " + r["text"])
    ctx.out.say(
        "\n  Levels: %s. Yours comes from --level, then\n"
        "  SUBMIT_GATE, then the .submit-level file, else basic.\n"
        "  Every command takes --show_bazel, which prints the Bazel command it\n"
        "  runs, and --dry-run, which prints it and runs nothing; docs/bazel.md\n"
        "  takes those commands apart.\n"
        "  More: 42 help <command>%s, and docs/testing.md.\n"
        "  Stuck? The peer next to you, the subject and `man` come first." % (
            ", ".join(LEVELS), "" if every else ", 42 help --all"))
    return 0


def wrap(words, indent, width=80):
    """Words on lines of at most `width`, every line after the first indented."""
    return textwrap.fill(words, width - indent, break_on_hyphens=False).replace("\n", "\n" + " " * indent)


WORDS_HELP = """
  The words, in any order, each optional:
    a project   %(projects)s
                (or its folder, c-piscine/c-piscine-c-05, or any path inside it)
    exNN        one exercise of that project
    a layer     %(layers)s
                (norminette is norm): that layer alone, whatever its level
    //label     a Bazel label or pattern, run as it is
  With no project word, the folder you are in decides: an exercise's folder
  under deliverable/ or tests/ is that exercise, anywhere else in a project is
  the whole project."""

TEST_FLAGS_HELP = """
  Its flags:
    --level L   that level instead of yours (%(levels)s)
    --fresh     every test again, even one whose result Bazel has cached
    --all       in what is still red, one line per exercise"""


# ---------------------------------------------------------------------------
# test

def scope_project(ctx, scope):
    """The project a scope runs in: its own, or the one a //label points into."""
    if scope.project is None and scope.label:
        return ctx.W.scope_of_path(os.path.join(ctx.ws, scope.label[2:].split(":")[0].split("/...")[0])).project
    return scope.project


def scope_files(ctx, scope):
    """The turn-in files a run of this scope reads, for its before/after snapshot."""
    project = scope_project(ctx, scope)
    if project is None:
        return []
    return taint.watched_files(project, scope.ex)


BUSY = ("  Bazel is busy with another command in this checkout (another\n"
        "  terminal, or 42 watch). Waiting for it to finish...")


def while_busy(out, attempt, limit=120):
    """attempt() until it is not LOCK_HELD, for up to `limit` seconds. Returns its last code."""
    waited = 0
    while True:
        rc = attempt()
        if rc != bazel.LOCK_HELD or waited >= limit:
            return rc
        if waited == 0:
            out.say(BUSY)
        time.sleep(2)
        waited += 2


def changed_files(ws, paths, when):
    """'This file changed WHEN:' and the files, one to a line: a path can be as wide as the screen."""
    return "  %s changed %s:%s" % ("This file" if len(paths) == 1 else "These files", when,
                                   "".join("\n      " + os.path.relpath(p, ws) for p in sorted(paths)))


def repair_notice(ws, paths, project, first):
    """What 42 says before it repairs a run an edit raced (TODO.md V111): a taint has a project."""
    then = ("runs %s again without the cache, then the rest" % ", ".join(first) if first
            else "runs these tests again, without the cache")
    return "%s\n  %s" % (changed_files(ws, paths, "while an earlier run was going"), wrap(
        "so what Bazel built from %s, and the results it kept, may be for other contents. "
        "42 deletes what Bazel built for %s and %s." % (
            "it" if len(paths) == 1 else "them", project.short, then), 2))


def raced_notice(ws, paths):
    """What 42 says when a file changed while the tests ran."""
    return "%s\n  %s" % (changed_files(ws, paths, "while the tests ran"), wrap(
        "so this result may be for the old contents, or a mix. Run it again; 42 will not "
        "trust the cache for it.", 2))


class Run:
    """One `bazel test` of a scope: the repair a taint asks for, the run, its snapshots, its report.

    stop(), when given (42 watch), is asked twice a second while Bazel runs;
    True cancels the run with one SIGINT, and the run is reported as stopped,
    not as a result.
    """

    def __init__(self, ctx, scope, level, source, extra=(), all_lines=False, label="test"):
        self.ctx, self.scope, self.level, self.source = ctx, scope, level, source
        self.all_lines, self.label = all_lines, label
        self.extra = list(extra)
        self.cancelled = False
        self.project = scope_project(ctx, scope)
        self.files = scope_files(ctx, scope)
        self.store = taint.Taint(ctx.ws, ctx.env)
        # Stats first: a save between the two is then seen as one during the run.
        self.before_stats = taint.stats(self.files)
        self.before = taint.snapshot(self.files)
        self.tainted = self.store.hits(self.before)
        # In a whole project, the exercises of the
        # tainted files run again without the cache first, and the project
        # then runs with it; anywhere smaller, the run itself goes uncached.
        self.first = []
        if self.tainted and not (scope.ex or scope.layer or scope.label):
            exs = {ctx.W.scope_of_path(p).ex for p in self.tainted}
            if None not in exs:
                self.first = sorted(exs)
        if self.tainted and not self.first and "--nocache_test_results" not in self.extra:
            self.extra.append("--nocache_test_results")

    def argv_first(self, ex):
        patterns, filt = self.ctx.W.selection(workspace.Scope(self.project, ex), self.level)
        return bazel.test_argv(patterns, filt, ["--nocache_test_results"])

    def shown(self):
        patterns, filt = self.ctx.W.selection(self.scope, self.level)
        return bazel.test_argv(patterns, filt, self.extra)

    def say_header(self):
        s, where = self.scope, ("default" if self.source == "default" else "from " + self.source)
        self.ctx.out.say("42 %s: %s, level %s (%s)" % (self.label, s.describe(), self.level, where)
                         if not s.layer and not s.label else "42 %s: %s" % (self.label, s.describe()))

    def go(self, stop=None):
        ctx, out = self.ctx, self.ctx.out
        self.say_header()
        if self.tainted and self.project:
            # TODO.md V111: a program built while its file changed can be
            # the other contents' program, and only building it again fixes that.
            ctx.show_line("rm -rf \"$(bazel info execution_root)\"/bazel-out/*/bin/" + self.project.rel)
        for ex in self.first:
            ctx.show(self.argv_first(ex))
        ctx.show(self.shown(), pipe=True)
        if ctx.args.dry_run:
            return 0
        exe = ctx.bazel()
        if self.tainted:
            out.say(repair_notice(ctx.ws, self.tainted, self.project, self.first))
        cold = report.coldness(ctx.ws, ctx.env)
        if cold:
            out.say("  " + report.PHASE[cold].replace("\n", "\n  "))
        if self.tainted and self.project:
            rc = while_busy(out, lambda: bazel.drop_outputs(exe, ctx.ws, [self.project.rel], ctx.env))
            if rc != bazel.OK:
                return report_run(ctx, self.scope, self.level, rc, None, None, None, self.all_lines)

        rundir = bazel.run_dir(ctx.env)
        try:
            out_path = os.path.join(rundir, "bazel.out")
            bep_path = os.path.join(rundir, "bep.json")
            next_path = os.path.join(rundir, "next.tsv")
            rcs = []
            for ex in self.first:
                argv = bazel.with_startup([exe] + self.argv_first(ex)[1:]) + ["--build_tests_only"]
                rc = self._bazel(argv, os.path.join(rundir, "first.out"), stop, ex + " again, without the cache")
                rcs.append(rc)
                if rc not in (bazel.OK, bazel.TESTS_FAILED, bazel.BUILD_FAILED):
                    break
            else:
                argv = bazel.with_startup([exe] + self.shown()[1:]) + bazel.plumbing(bep_path, bazel.new_invocation())
                rc = self._bazel(argv, out_path, stop, "running")
                rcs.append(rc)
            out.clear_tick()
            files = scope_files(ctx, self.scope)
            after_stats = taint.stats(files)
            moved = taint.raced(self.before, self.before_stats, taint.snapshot(files), after_stats)
            if moved and rc != bazel.LOCK_HELD:
                for p, digests in moved.items():
                    for d in digests:
                        self.store.add(p, d)
                if not self.cancelled:
                    out.say(raced_notice(ctx.ws, sorted(moved)))
            elif self.tainted and all(r in (bazel.OK, bazel.TESTS_FAILED) for r in rcs):
                # Rebuilt and re-run on a still file: these contents are vouched
                # for now. Other tainted contents of the same files stay tainted.
                for p in self.tainted:
                    self.store.discharge(p, self.before.get(p))
            self.store.save()
            if self.cancelled:
                return rc
            if len(rcs) <= len(self.first):  # a first run stopped short: nothing more ran
                return report_run(ctx, self.scope, self.level, rc, os.path.join(rundir, "first.out"),
                                  None, next_path, self.all_lines)
            return report_run(ctx, self.scope, self.level, rc, out_path, bep_path, next_path, self.all_lines)
        finally:
            shutil.rmtree(rundir, ignore_errors=True)

    def _bazel(self, argv, out_path, stop, doing):
        out = self.ctx.out

        def check():
            if stop is not None and not self.cancelled and stop():
                self.cancelled = True
            return self.cancelled

        def attempt():
            child = bazel.Child(argv, self.ctx.ws, out_path, self.ctx.env)
            return bazel.run_foreground(child, tick=lambda t, stopping: out.tick(
                "  %s... %ds%s" % ("stopping" if stopping else doing, t,
                                   "" if stopping else "  (Ctrl-C stops it)")), cancel_when=check,
                stuck=lambda: out.say("  Bazel has not stopped 10 s after it was asked to. 42 waits for\n"
                                      "  it, and never kills it."))
        return while_busy(out, attempt)


def run_tests(ctx, scope, level, source, extra=(), all_lines=False, label="test"):
    """One `42 test`. Returns Bazel's exit code."""
    return Run(ctx, scope, level, source, extra, all_lines, label).go()


def report_run(ctx, scope, level, rc, out_path, bep_path, next_path, all_lines):
    out = ctx.out
    if rc == bazel.LOCK_HELD:
        out.say("  Still busy after two minutes. Run it again once the other command\n"
                "  has finished, or stop that one.")
        return rc
    if out_path is None:
        out.say("  Bazel could not say where it keeps what it built (`bazel info` exit %d).\n"
                "  `42 doctor` checks this machine." % rc)
        return rc
    if rc == bazel.NO_TESTS:
        what = ("no %s test" % scope.layer) if scope.layer else ("no test at level %s" % level)
        out.say("\n  Nothing to run: %s has %s." % (scope.describe(), what))
        return rc
    if rc == bazel.USAGE:
        with open(out_path, encoding="utf-8", errors="replace") as f:
            lines = [l.rstrip() for l in f if l.strip()]
        errors = [l for l in lines if l.startswith("ERROR")] or lines
        out.say("\n  Bazel refused the command:\n    " + "\n    ".join(errors[-5:] or ["(it printed nothing)"]))
        return rc
    text, _ = report.first_red(ctx.ws, out_path, next_path, all_lines)
    out.say(text.rstrip("\n"))
    bep = bazel.read_bep(bep_path)
    if rc in (bazel.TESTS_FAILED, bazel.BUILD_FAILED):
        show_next_log(ctx, scope, bep, next_path)
        state = taint.state_dir(ctx.ws, ctx.env)
        if report.nudge_due(state):
            out.say("\n  " + report.NUDGE)
    elif rc == bazel.OK and scope.project and not scope.ex and not scope.layer:
        out.say("\n  Every test of %s passes at %s. `42 submit` pushes it; its gate runs\n"
                "  these same tests first." % (scope.project.short, level))
    return rc


def show_next_log(ctx, scope, bep, next_path):
    nxt = report.read_next(next_path)
    if nxt is None:
        return
    label = report.pick_label(nxt, bep)
    path = report.log_path(ctx.ws, label, bep) if label else None
    if not path:
        return
    lines, more = report.log_body(path)
    out = ctx.out
    out.say("\n  THE LOG OF %s\n" % label)
    out.say("\n".join(lines))
    if more:
        out.say("\n  ... %d more line(s): %s" % (more, path))
    if any("more hidden hint" in l or "CLUE_MODE=all" in l for l in lines):
        bucket, module, ex, _ = nxt
        words = [report_words(ctx, module), ex] if ex.startswith("ex") else [label]
        out.say("\n  more hints: 42 clues %s" % " ".join(w for w in words if w))


def report_words(ctx, module_label):
    p = ctx.W.project_named(module_label)
    return p.short if p else module_label


def cmd_test(ctx):
    a = ctx.args
    scope = ctx.W.resolve(a.words)
    if scope.project is None and not scope.label:
        raise UsageError(root_message(ctx, "test"))
    level, source = resolve_level(a.level, ctx.env, ctx.ws)
    if a.show_starlark:
        import starlark
        return starlark.show(ctx, scope, level)
    extra = ["--nocache_test_results"] if a.fresh else []
    return run_tests(ctx, scope, level, source, extra, all_lines=a.all)


def root_message(ctx, cmd):
    return ("42 %s needs a project, and you are not in one. Run it in a project's\n"
            "folder, or name one:\n  42 %s c-05\n  42 %s c-05 ex03\nThe projects: %s" % (
                cmd, cmd, cmd, ctx.W.project_list()))


# ---------------------------------------------------------------------------
# clues

def cmd_clues(ctx):
    a = ctx.args
    words = list(a.words)
    hints = "all"
    if words and (words[-1] == "all" or words[-1].isdigit()):
        hints = words.pop()
    scope = ctx.W.resolve(words)
    if scope.project is None and not scope.label:
        raise UsageError(root_message(ctx, "clues"))
    level, source = resolve_level(a.level, ctx.env, ctx.ws)
    patterns, filt = ctx.W.selection(scope, level)
    out = ctx.out
    if ctx.args.dry_run:
        ctx.show(bazel.test_argv(patterns, filt))
        ctx.show(bazel.test_argv(["<the labels that failed>"], None, ["--test_env=CLUE_MODE=" + hints]))
        return 0
    exe = ctx.bazel()
    rundir = bazel.run_dir(ctx.env)
    try:
        # What failed: the same selection as `42 test`, so a cached run costs
        # nothing. Then only those labels again, with the hints asked for: a
        # --test_env change re-runs every test of its invocation, so the
        # passing ones are left out of it.
        bep_path = os.path.join(rundir, "bep1.json")
        argv = bazel.with_startup([exe] + bazel.test_argv(patterns, filt)[1:]) + bazel.plumbing(bep_path, bazel.new_invocation())
        ctx.show(bazel.test_argv(patterns, filt))
        rc = bazel.run_foreground(bazel.Child(argv, ctx.ws, os.path.join(rundir, "out1"), ctx.env),
                                  tick=lambda t, s: out.tick("  finding what failed... %ds" % t))
        out.clear_tick()
        failed = bazel.read_bep(bep_path).failed()
        if rc == bazel.OK or not failed:
            out.say("Nothing failed in %s at %s: no hint to show." % (scope.describe(), level))
            return rc
        bep2 = os.path.join(rundir, "bep2.json")
        shown = bazel.test_argv(failed, None, ["--test_env=CLUE_MODE=" + hints])
        ctx.show(shown)
        argv = bazel.with_startup([exe] + shown[1:]) + bazel.plumbing(bep2, bazel.new_invocation())
        rc = bazel.run_foreground(bazel.Child(argv, ctx.ws, os.path.join(rundir, "out2"), ctx.env),
                                  tick=lambda t, s: out.tick("  running %d test(s) again with %s hints... %ds" % (len(failed), hints, t)))
        out.clear_tick()
        bep = bazel.read_bep(bep2)
        for label in failed:
            path = report.log_path(ctx.ws, label, bep)
            block = hint_block(path) if path else []
            out.say("\n  %s" % label)
            out.say("\n".join(block) if block else "   (this test prints no hints)")
        return rc
    finally:
        shutil.rmtree(rundir, ignore_errors=True)


def hint_block(path):
    """The HINTS block of a test.log, verbatim, up to the rule that closes it."""
    lines, _ = report.log_body(path, cap=10 ** 6)
    out = []
    for l in lines:
        if out and set(l.strip()) == {"-"}:
            break
        if out or l.strip() == "HINTS:":
            out.append(l)
    return out


# ---------------------------------------------------------------------------
# watch

def cmd_watch(ctx):
    import watch
    a = ctx.args
    scope = ctx.W.resolve(a.words)
    if scope.project is None and not scope.label:
        raise UsageError(root_message(ctx, "watch"))
    level, source = resolve_level(a.level, ctx.env, ctx.ws)
    if a.tmux:
        return watch.in_tmux(ctx, scope, level)
    if a.dry_run:  # the command each run would be, once; the loop would wait for a save
        return Run(ctx, scope, level, source, label="watch").go()
    return watch.Watch(ctx.out, scope.describe(), lambda: scope_files(ctx, scope),
                       lambda: Run(ctx, scope, level, source, label="watch"), keys=watch.Keys()).loop()


# ---------------------------------------------------------------------------
# The commands that run one target: exec'd, so the terminal, Ctrl-C and the
# exit status are exactly those of the command --show_bazel prints.

def run_target(ctx, label, args=(), command="run"):
    argv = ["bazel", command, label]
    if args:
        argv += ["--"] + list(args)
    ctx.show(argv)
    if ctx.args.dry_run:
        return 0
    argv[0] = ctx.bazel()
    bazel.exec_foreground(argv, ctx.ws, ctx.env)


def here_project(ctx, words, cmd):
    """The one project named by words, else the current folder's, else None."""
    scope = ctx.W.resolve(words)
    if scope.layer or scope.label:
        raise UsageError("42 %s takes a project, not %s." % (cmd, scope.layer or scope.label))
    return scope


def cmd_submit(ctx):
    a = ctx.args
    args = []
    if a.all:
        if a.projects:
            raise UsageError("--all or project names, not both.")
    else:
        projects = []
        for w in a.projects or [None]:
            scope = here_project(ctx, [w] if w else [], "submit")
            if scope.project is None:
                raise UsageError(
                    "42 submit pushes the project you are in, and you are not in one.\n"
                    "Name the projects (42 submit c-05 c-06), or push every one with a\n"
                    "remote set: 42 submit --all")
            if scope.project.rel not in projects:
                projects.append(scope.project.rel)
        args += projects
    if a.level:
        if a.level not in LEVELS:
            raise UsageError("--level %s is not a level: %s." % (a.level, ", ".join(LEVELS)))
        args += ["--gate-level", a.level]
    if a.n:
        args.append("-n")
    args += a.rest
    return run_target(ctx, "//tools:submit", args)


def cmd_norm(ctx):
    a = ctx.args
    if not a.files:
        # The harness's verdict, which gives each file the -R its norm test
        # gives it; a bare norminette over a header can say otherwise.
        level, source = resolve_level(None, ctx.env, ctx.ws)
        scope = ctx.W.resolve(["norm"])
        if scope.project is None:
            raise UsageError(root_message(ctx, "norm"))
        return run_tests(ctx, scope, level, source, label="norm")
    files = []
    for f in a.files:
        p = os.path.abspath(os.path.join(ctx.cwd, f))
        if not os.path.exists(p):
            raise UsageError("%s: no such file." % f)
        files.append(p)
    return run_target(ctx, "//tools:norminette", a.rest + files)


def cmd_generate(ctx):
    a = ctx.args
    scope = here_project(ctx, [a.project] if a.project else [], "generate")
    if scope.project is None:
        return run_target(ctx, "//tools:generate")
    if not scope.project.has_generators():
        gens = " ".join(p.short for p in ctx.W.projects() if p.has_generators())
        raise UsageError("%s has no generators: its deliverables are the files you write. "
                         "The projects with generators: %s." % (scope.project.short, gens))
    return run_target(ctx, scope.project.label + ":generate")


def cmd_header(ctx):
    a = ctx.args
    if a.reset:
        # It edits files in place, so with no folder named it re-stamps the
        # folder you are in, and at the repo root it asks: every file of every
        # project is --all, said on purpose.
        args = (["-n"] if a.n else []) + (["-k"] if a.k else [])
        if a.all:
            if a.targets:
                raise UsageError("--all or folders, not both.")
        elif a.targets:
            args += checkout_paths(ctx, a.targets)
        elif ctx.W.scope_of_path(ctx.cwd).project:
            args += checkout_paths(ctx, ["."])
        else:
            raise UsageError("42 header --reset re-stamps the headers of the folder you are in,\n"
                             "and you are in no project. Name one (42 header --reset c-05), or\n"
                             "re-stamp every project's files: 42 header --reset --all")
        return run_target(ctx, "//tools:reset_headers", args)
    if len(a.targets) != 1 or a.n or a.k or a.all:
        raise UsageError("42 header FILE prints the header for one file; "
                         "42 header --reset [where] re-stamps the ones you have.")
    return run_target(ctx, "//tools:gen_header", [a.targets[0]])


def cmd_init(ctx):
    a = ctx.args
    args = []
    if a.login:
        args += ["--login", a.login]
    if a.email:
        args += ["--email", a.email]
    return run_target(ctx, "//tools:init", args)


def cmd_stop(ctx):
    root = report.state_root(ctx.ws, ctx.env)
    base = report.output_base(ctx.ws, root)
    pid = report.server_alive(base)
    argv = ["bazel", "shutdown"]
    ctx.show(argv)
    if ctx.args.dry_run:
        return 0
    if not pid:
        ctx.out.say("No Bazel server is running for this checkout.")
        return 0
    try:
        with open("/proc/%d/status" % pid, encoding="utf-8") as f:
            rss = next((l.split()[1] for l in f if l.startswith("VmRSS:")), None)
        if rss:
            ctx.out.say("Stopping this checkout's Bazel server (%d MB). The next run starts it again." % (int(rss) // 1024))
    except OSError:
        pass
    argv[0] = ctx.bazel()
    bazel.exec_foreground(argv, ctx.ws, ctx.env)


def cmd_doctor(ctx):
    import doctor
    return doctor.run(ctx)


def cmd_selftest(ctx):
    labels = ["//tools/tests:fortytwo_test"] + (["//tools/..."] if ctx.args.harness else [])
    argv = ["bazel", "test"] + labels
    ctx.show(argv)
    if ctx.args.dry_run:
        return 0
    argv[0] = ctx.bazel()
    bazel.exec_foreground(argv, ctx.ws, ctx.env)


def cmd_conventions(ctx):
    return run_target(ctx, "//tools:conventions")


def checkout_paths(ctx, words):
    """Each word as a path from the checkout root: a file or folder, or a project's name."""
    out = []
    for w in words:
        path = os.path.join(ctx.cwd, w)
        if os.path.exists(path):
            rel = ctx.W.rel(path)
            if rel is None:
                raise UsageError("%s is outside this checkout." % w)
            out.append(rel)
            continue
        p = ctx.W.project_named(w)
        if p is None:
            raise UsageError("%s is neither a file nor a project." % w)
        out.append(p.rel)
    return out


def cmd_stubcheck(ctx):
    a = ctx.args
    if a.file:
        return run_target(ctx, "//tools:stub_check", ["--file", os.path.abspath(os.path.join(ctx.cwd, a.file))])
    words = a.where
    if not words:
        here = ctx.W.scope_of_path(ctx.cwd)
        words = [here.project.path] if here.project else []
    return run_target(ctx, "//tools:stub_check", checkout_paths(ctx, words))


# ---------------------------------------------------------------------------
# Arguments

class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise UsageError("%s. `42 help %s` says how to call it." % (message, self.prog.split()[-1]))

    def parse_args(self, args=None, namespace=None):
        # A flag no command takes is reported by the top parser, whose prog is
        # "42", and `42 help 42` is no command: name the command it came with.
        ns, extra = self.parse_known_args(args, namespace)
        if extra:
            topic = getattr(ns, "command", None)
            raise UsageError("unrecognized arguments: %s. `42 help%s` says how to call it."
                             % (" ".join(extra), " " + topic if topic else ""))
        return ns


def parser():
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--show_bazel", action="store_true")
    common.add_argument("--dry-run", "--dry_run", dest="dry_run", action="store_true")
    common.add_argument("--plain", action="store_true")

    top = Parser(prog="42", add_help=False)
    sub = top.add_subparsers(dest="command", parser_class=Parser)

    def add(name, **kw):
        return sub.add_parser(name, parents=[common], add_help=False, **kw)

    h = add("help")
    h.add_argument("topic", nargs="?")
    h.add_argument("--all", action="store_true")

    for name in ("test", "watch", "clues"):
        p = add(name)
        p.add_argument("words", nargs="*")
        p.add_argument("--level")
        if name == "test":
            p.add_argument("--fresh", action="store_true")
            p.add_argument("--all", action="store_true")
            p.add_argument("--show_starlark", action="store_true")
        if name == "watch":
            p.add_argument("--tmux", action="store_true")

    p = add("submit")
    p.add_argument("projects", nargs="*")
    p.add_argument("--all", action="store_true")
    p.add_argument("--level")
    p.add_argument("-n", action="store_true")

    p = add("norm")
    p.add_argument("files", nargs="*")

    p = add("generate")
    p.add_argument("project", nargs="?")

    p = add("header")
    p.add_argument("targets", nargs="*")
    p.add_argument("--reset", action="store_true")
    p.add_argument("--all", action="store_true")
    p.add_argument("-n", action="store_true")
    p.add_argument("-k", action="store_true")

    p = add("init")
    p.add_argument("--login")
    p.add_argument("--email")

    p = add("doctor")
    p.add_argument("--drift", action="store_true")
    p.add_argument("--report", action="store_true")

    add("stop")
    p = add("selftest")
    p.add_argument("--harness", action="store_true")
    add("conventions")
    p = add("stubcheck")
    p.add_argument("where", nargs="*")
    p.add_argument("--file")
    return top


COMMANDS = {
    "test": cmd_test, "watch": cmd_watch, "clues": cmd_clues, "submit": cmd_submit,
    "norm": cmd_norm, "generate": cmd_generate, "header": cmd_header, "init": cmd_init,
    "doctor": cmd_doctor, "stop": cmd_stop, "selftest": cmd_selftest,
    "conventions": cmd_conventions, "stubcheck": cmd_stubcheck,
}

# The commands whose words after `--` go to the tool they run, untouched.
PASSTHROUGH = ("submit", "norm")


def main(argv=None, environ=None):
    environ = dict(os.environ if environ is None else environ)
    argv = list(sys.argv[1:] if argv is None else argv)
    ws = environ.get("FT_WS") or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    cwd = environ.get("FT_CWD") or os.getcwd()
    rest = []
    if argv and argv[0] in PASSTHROUGH and "--" in argv:
        i = argv.index("--")
        argv, rest = argv[:i], argv[i + 1:]
    if argv and argv[0] in ("--version", "version"):
        print("42 %s (%s)" % (VERSION, ws))
        return 0
    if not argv or argv[0] in ("-h", "--help"):
        argv = ["help"] + argv[1:]
    elif len(argv) > 1 and argv[0] != "help" and ("-h" in argv[1:] or "--help" in argv[1:]):
        argv = ["help", argv[0]]
    try:
        args = parser().parse_args(argv)
        args.rest = rest
        ctx = Ctx(ws, cwd, environ, args)
        if args.command == "help":
            return print_help(ctx, every=args.all, command=args.topic)
        if args.command is None:
            raise UsageError("no command. `42 help` lists them.")
        return COMMANDS[args.command](ctx) or 0
    except UsageError as e:
        print("42: %s" % e, file=sys.stderr)
        return 2
    except bazel.NoBazel as e:
        print("42: %s" % e, file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("", file=sys.stderr)
        return 8
    except BrokenPipeError:
        # `42 help | head`: the reader left; say nothing more to it.
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        return 0


if __name__ == "__main__":
    sys.exit(main())
