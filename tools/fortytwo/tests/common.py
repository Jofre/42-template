"""What every suite of 42's tests shares: where the checkout is, and how to run 42."""

import contextlib
import io
import os
import sys

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


def run42(argv, cwd=None, environ=None):
    """main.main() in-process: (exit status, stdout, stderr)."""
    import main
    env = dict(environ or {})
    env.setdefault("PATH", os.environ.get("PATH", ""))
    env.setdefault("HOME", os.environ.get("TEST_TMPDIR", "/tmp"))
    env["FT_WS"] = WS
    env["FT_CWD"] = cwd or WS
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        rc = main.main(list(argv), env)
    return rc, out.getvalue(), err.getvalue()
