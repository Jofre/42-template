"""docs/bazel.md: each `42 … --dry-run` it shows prints the Bazel lines it shows.

The page teaches what each command runs by showing it, as a terminal would:

    ~/42/c-piscine/c-piscine-c-00/deliverable/ex01$ 42 test --dry-run
    $ bazel test //c-piscine/c-piscine-c-00:ex01 --test_tag_filters=lvl_basic,-manual 2>&1 | sh tools/first_red.sh

The prompt names the folder, under the checkout (~/42 on the page). Each such
42 is run here from that folder, and the `$ ` lines it prints must be the
`$ ` lines the page shows under it, in order. The line naming the scope and
level that 42 prints first is not shown on the page, and not compared: it
says where the level came from, which differs between checkouts.
"""

import os
import re
import shlex
import unittest

from common import WS
from test_main import Case

PROMPT = re.compile(r"^~/42(/[^$ ]*)?\$ 42( .*)?$")
FEWEST = 10  # the page shows more; fewer means the format moved under this test


def transcripts(text):
    """[(line number, folder, argv, [shown $ lines])] for every prompt in a fenced block."""
    out, inb, cur = [], False, None
    for n, line in enumerate(text.splitlines(), 1):
        line = line.lstrip()  # a block inside a list item is indented
        if line.startswith("```"):
            inb, cur = not inb, None
            continue
        if not inb:
            continue
        m = PROMPT.match(line)
        if m:
            cur = (n, (m.group(1) or "").lstrip("/"), shlex.split(m.group(2) or ""), [])
            out.append(cur)
        elif cur is not None and line.startswith("$ "):
            cur[3].append(line[2:])
        else:
            cur = None
    return out


class Page(Case):
    def problems(self, text, name):
        found = []
        for n, folder, argv, shown in transcripts(text):
            where = "%s:%d" % (name, n)
            if "--dry-run" not in argv:
                found.append("%s: `42 %s` has no --dry-run, and this test runs it" % (where, " ".join(argv)))
                continue
            # Env sets SUBMIT_GATE=basic: the default, whatever .submit-level says here.
            rc, out, err = self.run42(argv, os.path.join(WS, folder))
            got = [l[2:] for l in out.splitlines() if l.startswith("$ ")]
            if rc != 0:
                found.append("%s: `42 %s` exited %d: %s" % (where, " ".join(argv), rc, err.strip()))
            elif got != shown:
                found.append("%s: `42 %s` prints\n  %s\nand the page shows\n  %s"
                             % (where, " ".join(argv), "\n  ".join(got), "\n  ".join(shown)))
        return found

    def test_the_page_shows_what_42_prints(self):
        path = os.path.join(WS, "docs", "bazel.md")
        with open(path) as f:
            text = f.read()
        self.assertGreaterEqual(len(transcripts(text)), FEWEST)
        self.assertEqual(self.problems(text, "docs/bazel.md"), [])

    def test_a_stale_line_is_found(self):
        page = ("```\n~/42/c-piscine/c-piscine-c-05$ 42 test --dry-run\n"
                "$ bazel test //c-piscine/c-piscine-c-05/... --test_tag_filters=lvl_strict,-manual"
                " 2>&1 | sh tools/first_red.sh\n```\n")
        found = self.problems(page, "page")
        self.assertEqual(len(found), 1)
        self.assertIn("lvl_basic", found[0])

    def test_a_line_shown_without_dry_run_is_refused(self):
        found = self.problems("```\n~/42$ 42 stop\n$ bazel shutdown\n```\n", "page")
        self.assertEqual(len(found), 1)
        self.assertIn("no --dry-run", found[0])

    def test_a_prompt_outside_a_block_is_prose(self):
        self.assertEqual(transcripts("~/42$ 42 stop --dry-run\n$ bazel shutdown\n"), [])

    def test_a_block_inside_a_list_item_is_read(self):
        found = transcripts("- one:\n\n  ```\n  ~/42$ 42 stop --dry-run\n  $ bazel shutdown\n  ```\n")
        self.assertEqual(found, [(4, "", ["stop", "--dry-run"], ["bazel shutdown"])])


if __name__ == "__main__":
    unittest.main()
