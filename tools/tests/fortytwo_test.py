"""//tools/tests:fortytwo_test -- every suite of tools/fortytwo/tests, under unittest."""

import os
import sys
import unittest

here = os.path.join(os.environ.get("TEST_SRCDIR", ""), "_main", "tools", "fortytwo", "tests")
if not os.path.isdir(here):
    here = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "fortytwo", "tests")
sys.path.insert(0, here)
suite = unittest.defaultTestLoader.discover(here, pattern="test_*.py", top_level_dir=here)
result = unittest.TextTestRunner(stream=sys.stdout, verbosity=2).run(suite)
sys.exit(0 if result.wasSuccessful() and result.testsRun > 0 else 1)
