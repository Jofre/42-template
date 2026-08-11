/* Curated pedagogic layer for rush(x, y).
 *
 * Reads the case list from stdin (tests/ex00/cases.tsv, one "<label>\t<x>\t<y>"
 * per line) and prints one line per case:
 *
 *     <label><TAB><the rectangle the student printed, escaped onto one line>
 *
 * tools/diff_output.sh --labeled renders that as a CASE | EXPECTED | GOT table
 * against expected_rush0N.txt, so a failing case names itself ("1x1 single
 * cell") instead of being line 37 of a wall of text. Because one case is always
 * exactly one line, a wrong row count breaks only its own row of the table.
 *
 * The case list and the expected files are generated together, by
 * tests/ex00/regen.sh, out of one source of truth: `const FIXED` in
 * oracle/src/rush00.rs. Neither is hand-edited. */
#include "diffio.h"
#include "rush_capture.h"

int	main(void)
{
	char	line[512];
	char	*f[3];

	/* 20 CPU seconds and a 4 MiB output cap: an infinite loop or a runaway
	 * writer dies here instead of hanging the suite (see rush_capture.h). */
	rc_guard(20, 4UL * 1024 * 1024);
	while (dio_line(line, sizeof(line)))
	{
		if (line[0] == '#' || line[0] == '\0')
			continue ;
		if (dio_split(line, f, 3) < 3)
			continue ;
		rc_print_escaped(f[0], atoi(f[1]), atoi(f[2]));
	}
	return (0);
}
