"""//tools/tests:fortytwo_test -- every suite of tools/fortytwo/tests, under unittest."""

import gc
import os
import sys
import unittest
import warnings

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

# A file, pipe or folder a test leaves for the garbage collector is reported
# as a ResourceWarning, which CPython ignores unless asked: without this
# guard such a leak in 42 or in its tests passes unseen under Bazel (V191).
# "error" turns one raised in a test into that test's error. One raised in a
# finalizer (a __del__, a weakref callback) cannot reach the test, and goes
# to sys.unraisablehook instead, which records it here; after the run, a
# last collection flushes the rest, and any recorded fails the suite. The
# runner gets no `warnings`, so it keeps this filter rather than its own.
warnings.simplefilter("error", ResourceWarning)
unraisable = []
original_hook = sys.unraisablehook


def record(info):
    unraisable.append("%s: %s: %s" % (info.err_msg or "Exception ignored in", info.object,
                                      info.exc_value if info.exc_value is not None else info.exc_type))
    original_hook(info)


sys.unraisablehook = record
suite = unittest.defaultTestLoader.discover(here, pattern="test_*.py", top_level_dir=here)
result = unittest.TextTestRunner(stream=sys.stdout, verbosity=2).run(suite)
gc.collect()
if unraisable:
    print("\nFAIL: %d warning(s) or error(s) raised where no test could catch them, in a "
          "finalizer (a __del__ or a weakref callback). A ResourceWarning means something the "
          "tests ran left a file, a pipe or a folder for the garbage collector to close or "
          "remove: find what opens it and close it (a `with`, an addCleanup, or the object's "
          "own close() or cleanup()). Any other error is a finalizer that failed. The test "
          "running when it was collected is not always the one that made it." % len(unraisable))
    for line in unraisable:
        print("  " + line)
sys.exit(0 if result.wasSuccessful() and result.testsRun > 0 and not unraisable else 1)
