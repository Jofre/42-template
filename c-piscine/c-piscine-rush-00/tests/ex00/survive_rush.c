/* Survival layer (<p>_survive) for rush(x, y): the sizes the subject leaves
 * UNDEFINED, and the legal sizes that sit on a counter's ceiling.
 *
 * "Your function must never crash or enter an infinite loop" is a requirement,
 * but what a degenerate size should PRINT is not specified — so for a
 * non-positive size this harness asserts nothing about the bytes. For each case
 * in tests/ex00/edge_cases.tsv it prints exactly:
 *
 *     <label><TAB>survived
 *
 * A crash truncates the table at the offending case, an infinite loop trips the
 * CPU guard in rush_capture.h, and output beyond rc_runaway_limit() — a
 * megabyte for a non-positive size, or eight times the rectangle for a legal one
 * — is reported as RUNAWAY OUTPUT. For a degenerate size that is a real bug, not
 * a style choice: it means the row/column loop never looked at the sign of its
 * bound, so rush(2147483647, 0) would bury the evaluator's terminal.
 *
 * A LEGAL size owes more than coming back: "a rectangle on the screen with a
 * width of x characters and a height of y characters", so y lines of x
 * characters, each ended by a newline -- (x + 1) * y bytes, known from the size
 * alone. Anything else is reported as WRONG SHAPE, with the figures. Nothing
 * here says which characters: that is the value layers' question, and they
 * name the exact cell. It used to be asked of no legal size at all, so a
 * program that printed nothing above 80 columns "survived" 100000x1 (finding
 * 141).
 *
 * THE SHAPE HALF WAITS FOR A DRAWING, as every rigour layer waits for its
 * exercise's own fixture. While rush(3, 3) prints nothing at all -- a variant
 * not written yet, the stub every team starts from -- a legal size is judged
 * on survival alone: _output and _defense already say "nothing is drawn",
 * and seventeen WRONG SHAPE rows here would say it a third time, at basic, to
 * a beginner. Once 3x3 draws anything, every legal size owes its shape. The
 * survival half never waits: a crash or a runaway is one at any stage.
 *
 * The last case is different: it re-runs a normal rectangle after the whole
 * degenerate sweep and checks it still prints what it printed BEFORE the sweep.
 * That catches state that leaks between calls (a static/global counter that a
 * negative size left dirty). */
#include "diffio.h"
#include "rush_capture.h"

/* For a legal size, whether the capture is y lines of exactly x characters
 * and a newline; 1 when it is. */
static int	right_shape(const char *b, size_t len, int x, int y)
{
	size_t	w;
	size_t	i;

	w = (size_t)x + 1;
	if (len != w * (size_t)y)
		return (0);
	for (i = 0; i < len; i++)
		if ((b[i] == '\n') != (i % w == w - 1))
			return (0);
	return (1);
}

static size_t	count_lines(const char *b, size_t len)
{
	size_t	i;
	size_t	n;

	n = 0;
	for (i = 0; i < len; i++)
		if (b[i] == '\n')
			n++;
	if (len > 0 && b[len - 1] != '\n')
		n++;
	return (n);
}

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
	size_t	lines;
	int		draws;
	int		x;
	int		y;

	rc_guard(20, 64UL * 1024 * 1024);
	before = snapshot(3, 3);
	draws = (before && before[0] != '\0');
	while (dio_line(line, sizeof(line)))
	{
		if (line[0] == '#' || line[0] == '\0')
			continue ;
		if (dio_split(line, f, 3) < 3)
			continue ;
		x = atoi(f[1]);
		y = atoi(f[2]);
		buf = rc_run(x, y, &len);
		if (!buf)
			printf("%s\tCAPTURE FAILED\n", f[0]);
		else if (len > rc_runaway_limit(x, y))
			printf("%s\tRUNAWAY OUTPUT (%lu bytes)\n", f[0],
				(unsigned long)len);
		else if (draws && x > 0 && y > 0 && !right_shape(buf, len, x, y))
		{
			lines = count_lines(buf, len);
			printf("%s\tWRONG SHAPE: %lu bytes in %lu line%s, where %d line%s of %d"
				" character%s and a newline make %lu\n", f[0], (unsigned long)len,
				(unsigned long)lines, lines == 1 ? "" : "s", y, y == 1 ? "" : "s", x,
				x == 1 ? "" : "s", (unsigned long)(((size_t)x + 1) * (size_t)y));
		}
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
