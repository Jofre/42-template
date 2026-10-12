"""//tools/tests:fortytwo_test -- every suite of tools/fortytwo/tests, under unittest."""

import os
import sys
import unittest

# A test's scratch files go under TEST_TMPDIR, which Bazel empties, and not in
# the machine's /tmp, the TMPDIR Bazel sets when the shell that ran it set none,
# which tempfile reads (tools/runner_lib.sh, "THE SCRATCH FOLDER"). Set before
# any suite is loaded, so before tempfile looks.
if os.environ.get("TEST_TMPDIR") and os.environ.get("TMPDIR", "/tmp").rstrip("/") in ("", "/tmp"):
    os.environ["TMPDIR"] = os.environ["TEST_TMPDIR"]

here = os.path.join(os.environ.get("TEST_SRCDIR", ""), "_main", "tools", "fortytwo", "tests")
if not os.path.isdir(here):
    here = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "fortytwo", "tests")
sys.path.insert(0, here)
suite = unittest.defaultTestLoader.discover(here, pattern="test_*.py", top_level_dir=here)
result = unittest.TextTestRunner(stream=sys.stdout, verbosity=2).run(suite)
sys.exit(0 if result.wasSuccessful() and result.testsRun > 0 else 1)
