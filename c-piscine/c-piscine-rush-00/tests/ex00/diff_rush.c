/* Live-differential reader harness for rush(x, y). Reference line:
 *   <x>\t<y>\t<escaped-rectangle>
 * We reprint "<x>\t<y>\t" followed by the student's own rectangle, escaped with
 * the same rules (rush_capture.h / oracle/src/rush00.rs), so tools/rust_diff.sh
 * can byte-diff the two files. A mismatch therefore reports the exact size that
 * diverged, with both rectangles on one line each.
 *
 * The same binary is built a second time under ASan+UBSan and replayed over the
 * degenerate-size corpus in --crash-only mode, where the values are ignored and
 * only survival counts. */
#include "diffio.h"
#include "rush_capture.h"

/* The corpus carries a whole rectangle per line (up to ~20 KiB escaped), so the
 * line buffer is generous and static rather than on the stack. */
static char	g_line[1 << 18];

int	main(void)
{
	char	*f[3];
	char	*buf;
	char	*esc;
	size_t	len;
	int		x;
	int		y;

	rc_guard(45, 64UL * 1024 * 1024);
	while (dio_line(g_line, (int)sizeof(g_line)))
	{
		if (dio_split(g_line, f, 3) < 2)
			continue ;
		x = (int)strtol(f[0], NULL, 10);
		y = (int)strtol(f[1], NULL, 10);
		buf = rc_run(x, y, &len);
		if (!buf)
		{
			printf("%d\t%d\tCAPTURE FAILED\n", x, y);
			continue ;
		}
		if (len > rc_runaway_limit(x, y))
		{
			printf("%d\t%d\tRUNAWAY OUTPUT (%lu bytes)\n", x, y,
				(unsigned long)len);
			free(buf);
			continue ;
		}
		esc = rc_escape(buf, len);
		printf("%d\t%d\t%s\n", x, y, esc ? esc : "ESCAPE FAILED");
		free(esc);
		free(buf);
	}
	return (0);
}
