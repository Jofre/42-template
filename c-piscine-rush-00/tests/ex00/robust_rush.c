/* Robustness layer for rush(x, y): the sizes the subject leaves UNDEFINED.
 *
 * "Your function must never crash or enter an infinite loop" is a requirement,
 * but what a degenerate size should PRINT is not specified — so this harness
 * asserts nothing about the bytes. For each case in tests/ex00/edge_cases.tsv
 * it prints exactly:
 *
 *     <label><TAB>survived
 *
 * A crash truncates the table at the offending case, an infinite loop trips the
 * CPU guard in rush_capture.h, and output beyond rc_runaway_limit() — a
 * megabyte for a non-positive size, or eight times the rectangle for a legal one
 * — is reported as RUNAWAY OUTPUT. For a degenerate size that is a real bug, not
 * a style choice: it means the row/column loop never looked at the sign of its
 * bound, so rush(2147483647, 0) would bury the evaluator's terminal. The budget
 * for a legal size is loose on purpose: an off-by-one or a trailing space must
 * be reported by the value layers, which say exactly what is wrong, not here.
 *
 * The last case is different: it re-runs a normal rectangle after the whole
 * degenerate sweep and checks it still prints what it printed BEFORE the sweep.
 * That catches state that leaks between calls (a static/global counter that a
 * negative size left dirty). */
#include "diffio.h"
#include "rush_capture.h"

/* Capture rush(x, y) escaped onto one line, or NULL if the plumbing failed. */
static char	*snapshot(int x, int y)
{
	char	*buf;
	char	*esc;
	size_t	len;

	buf = rc_run(x, y, &len);
	if (!buf)
		return (NULL);
	esc = rc_escape(buf, len);
	free(buf);
	return (esc);
}

int	main(void)
{
	char	line[512];
	char	*f[3];
	char	*before;
	char	*after;
	char	*buf;
	size_t	len;

	rc_guard(20, 64UL * 1024 * 1024);
	before = snapshot(3, 3);
	while (dio_line(line, sizeof(line)))
	{
		if (line[0] == '#' || line[0] == '\0')
			continue ;
		if (dio_split(line, f, 3) < 3)
			continue ;
		buf = rc_run(atoi(f[1]), atoi(f[2]), &len);
		if (!buf)
			printf("%s\tCAPTURE FAILED\n", f[0]);
		else if (len > rc_runaway_limit(atoi(f[1]), atoi(f[2])))
			printf("%s\tRUNAWAY OUTPUT (%lu bytes)\n", f[0],
				(unsigned long)len);
		else
			printf("%s\tsurvived\n", f[0]);
		free(buf);
	}
	after = snapshot(3, 3);
	printf("3x3 unchanged by the degenerate calls\t%s\n",
		(before && after && !strcmp(before, after)) ? "YES" : "NO");
	free(before);
	free(after);
	return (0);
}
