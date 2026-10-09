/* The subject's defense case, drawn in full (tests <p>_defense).
 *
 * "Your main function will be modified during the defense to check whether you
 * have handled all required cases. Here is an example of a test that will be
 * performed: rush(123, 42);" -- so the defense runs it, and a wrong picture
 * there is a KO whatever else passed. The output table keeps its cases small
 * enough to read (200 cells at most, oracle/src/rush00.rs's FIXED), so this is
 * the one larger size compared in full at basic (finding 141).
 *
 * It reads the REFERENCE's picture on stdin -- tests/ex00/defense_rush0N.txt,
 * written by `oracle rush00_fixtures` and held to it by ex00_oracle_fixtures --
 * takes x and y from it (y lines, each of x characters and a newline), calls
 * rush(x, y), and prints ONE row of the labelled table, never the 5208 bytes:
 *
 *     <label><TAB>the reference's picture, all N bytes
 *
 * when the two are the same bytes, and otherwise
 *
 *     <label><TAB>N bytes in L line(s), where Y rows of X make M; first
 *                 difference at row R, column C: yours "...", the
 *                 reference's "..."
 *
 * ("nothing at all, where Y rows of X make M bytes" when it printed nothing,
 * which is where every team starts: an untouched stub),
 *
 * -- the figures the size makes, (x + 1) * y bytes, and a dozen bytes of each
 * side around the first byte that differs, escaped as every rush table escapes
 * (rush_capture.h). Nothing here knows how the picture is drawn: every byte it
 * compares against is the reference's.
 *
 * Grader-side test infrastructure, not a submission: libc freely, no Norm. */
#include "rush_capture.h"

/* All of stdin, NUL-terminated, in a fresh buffer; NULL if it could not be
 * read. The picture is a few kilobytes. */
static char	*slurp(size_t *len)
{
	char	*buf;
	char	*grown;
	size_t	cap;
	size_t	got;

	cap = 8192;
	*len = 0;
	buf = (char *)malloc(cap);
	if (!buf)
		return (NULL);
	while ((got = fread(buf + *len, 1, cap - *len - 1, stdin)) > 0)
	{
		*len += got;
		if (cap - *len - 1 == 0)
		{
			cap *= 2;
			grown = (char *)realloc(buf, cap);
			if (!grown)
			{
				free(buf);
				return (NULL);
			}
			buf = grown;
		}
	}
	buf[*len] = '\0';
	return (buf);
}

/* The reference's picture is y lines of x characters, each ended by a newline.
 * Sets *x and *y; 0 when it is not that shape (a broken fixture, never the
 * student's doing). */
static int	shape_of(const char *p, size_t n, int *x, int *y)
{
	size_t	i;
	size_t	start;

	*x = 0;
	*y = 0;
	start = 0;
	if (n == 0 || p[n - 1] != '\n')
		return (0);
	for (i = 0; i < n; i++)
	{
		if (p[i] != '\n')
			continue ;
		if (i == start || (*y > 0 && (int)(i - start) != *x))
			return (0);
		*x = (int)(i - start);
		(*y)++;
		start = i + 1;
	}
	return (1);
}

static size_t	count_lines(const char *p, size_t n)
{
	size_t	i;
	size_t	lines;

	lines = 0;
	for (i = 0; i < n; i++)
		if (p[i] == '\n')
			lines++;
	if (n > 0 && p[n - 1] != '\n')
		lines++;
	return (lines);
}

/* Up to `before` bytes ahead of `off` and `after` from it, escaped. */
static char	*window(const char *p, size_t n, size_t off, size_t before, size_t after)
{
	size_t	start;
	size_t	end;

	start = off > before ? off - before : 0;
	end = off + after < n ? off + after : n;
	if (start > end)
		start = end;
	return (rc_escape(p + start, end - start));
}

int	main(void)
{
	/* conventions: bounded -- snprintf'd with its size from two ints */
	char	label[96];
	char	*want;
	char	*got;
	char	*yours;
	char	*theirs;
	size_t	wlen;
	size_t	len;
	size_t	off;
	size_t	row;
	size_t	col;
	size_t	lines;
	size_t	i;
	int		x;
	int		y;

	rc_guard(20, 64UL * 1024 * 1024);
	want = slurp(&wlen);
	if (!want || !shape_of(want, wlen, &x, &y))
	{
		printf("the subject's defense case\tBROKEN FIXTURE: the reference's picture on stdin"
			" is not a rectangle (a harness problem, not yours)\n");
		free(want);
		return (0);
	}
	snprintf(label, sizeof(label), "rush(%d, %d), the subject's defense case", x, y);
	got = rc_run(x, y, &len);
	if (!got)
		printf("%s\tCAPTURE FAILED\n", label);
	else if (len > rc_runaway_limit(x, y))
		printf("%s\tRUNAWAY OUTPUT (%lu bytes)\n", label, (unsigned long)len);
	else if (len == wlen && memcmp(got, want, wlen) == 0)
		printf("%s\tthe reference's picture, all %lu bytes\n", label, (unsigned long)wlen);
	else if (len == 0)
		printf("%s\tnothing at all, where %d rows of %d make %lu bytes\n", label, y, x,
			(unsigned long)wlen);
	else
	{
		off = 0;
		while (off < len && off < wlen && got[off] == want[off])
			off++;
		/* Where the reference's picture is at that byte: its row, and the
		 * column in that row (x + 1 is the newline's place). Past its end,
		 * the program printed more than the whole picture. */
		row = 1;
		col = 1;
		for (i = 0; i < off && i < wlen; i++)
		{
			col++;
			if (want[i] == '\n')
			{
				row++;
				col = 1;
			}
		}
		lines = count_lines(got, len);
		yours = window(got, len, off, 6, 6);
		theirs = window(want, wlen, off, 6, 6);
		if (off >= wlen)
			printf("%s\t%lu bytes in %lu line%s, where %d rows of %d make %lu: the whole"
				" picture, then more after its last row: \"%s\"\n", label, (unsigned long)len,
				(unsigned long)lines, lines == 1 ? "" : "s", y, x, (unsigned long)wlen,
				yours ? yours : "?");
		else
			printf("%s\t%lu bytes in %lu line%s, where %d rows of %d make %lu; first difference"
				" at row %lu, column %lu: yours \"%s\", the reference's \"%s\"\n", label,
				(unsigned long)len, (unsigned long)lines, lines == 1 ? "" : "s", y, x,
				(unsigned long)wlen, (unsigned long)row, (unsigned long)col,
				yours ? yours : "?", theirs ? theirs : "?");
		free(yours);
		free(theirs);
	}
	free(got);
	free(want);
	return (0);
}
