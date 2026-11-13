"""What every suite of 42's tests shares: where the checkout is, and how to run 42."""

import atexit
import contextlib
import io
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURES = os.path.join(HERE, "fixtures")


def checkout():
    """The tree the tests read: FT_TEST_WS, else Bazel's runfiles, else the checkout around this file.

    Under `bazel test` the runfiles hold every project's BUILD.bazel and tests
    (//tools/tests:fortytwo_test's data), never a turn-in file; run by hand,
    it is a real checkout.
    """
    if os.environ.get("FT_TEST_WS"):
        return os.environ["FT_TEST_WS"]
    if os.environ.get("TEST_SRCDIR"):
        return os.path.join(os.environ["TEST_SRCDIR"], "_main")
    return os.path.dirname(os.path.dirname(os.path.dirname(HERE)))


WS = checkout()
sys.path.insert(0, os.path.join(WS, "tools", "fortytwo"))


def tool_text(name):
    """A file of the checkout's tools/, as text, for a toy checkout that runs it: tools/units.awk, which
    42 reads every contract with (workspace.read_units)."""
    with open(os.path.join(WS, "tools", name), encoding="utf-8") as f:
        return f.read()


_HOME = []


def own_home():
    """A HOME for a run given none: Bazel's TEST_TMPDIR, else a folder of this run's own,
    never a shared /tmp, where anyone may leave a .config/42/config.yaml."""
    if os.environ.get("TEST_TMPDIR"):
        return os.environ["TEST_TMPDIR"]
    if not _HOME:
        _HOME.append(tempfile.mkdtemp(prefix="run42-home-"))
        atexit.register(shutil.rmtree, _HOME[0], True)
    return _HOME[0]


def run42(argv, cwd=None, environ=None, ws=None):
    """main.main() in-process, in the checkout or ws: (exit status, stdout, stderr)."""
    import main
    env = dict(environ or {})
    env.setdefault("PATH", os.environ.get("PATH", ""))
    env.setdefault("HOME", own_home())
    # The user file is under that HOME, never under the XDG_CONFIG_HOME of
    # whoever runs the tests: env is built from environ alone.
    env.setdefault("XDG_CONFIG_HOME", os.path.join(env["HOME"], ".config"))
    env["FT_WS"] = ws or WS
    env["FT_CWD"] = cwd or ws or WS
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        rc = main.main(list(argv), env)
    return rc, out.getvalue(), err.getvalue()
