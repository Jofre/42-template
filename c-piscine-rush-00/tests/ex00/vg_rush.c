/* Valgrind probe for rush(x, y) — the student's rush0N.c + ft_putchar.c built
 * normally and run under memcheck (tools/valgrind_test.sh).
 *
 * This is NOT a duplicate of the ASan probe: the two catch different bugs, and
 * each is blind to the other's.
 *   - memcheck sees a write() whose buffer holds UNINITIALISED bytes ("Syscall
 *     param write(buf) points to uninitialised byte(s)") — a row assembled in
 *     an array that was only partly filled. The bytes may well look right on
 *     this machine today, so no diff can catch it. ASan has no uninitialised-
 *     memory detector at all.
 *   - ASan sees a write PAST the end of that array, which memcheck does not
 *     instrument on the stack.
 *
 * Small sweep on purpose: memcheck costs 20-50x, and the sizes that matter for
 * uninitialised bytes are the ordinary ones. Output goes to /dev/null. */
#include "rush_capture.h"

int	main(void)
{
	int	x;
	int	y;

	rc_guard(50, 8UL * 1024 * 1024);
	x = 1;
	while (x <= 20)
	{
		y = 1;
		while (y <= 20)
			rc_run_discard(x, y++);
		x++;
	}
	rc_run_discard(80, 3);
	rc_run_discard(3, 80);
	rc_run_discard(123, 42);
	rc_run_discard(0, 0);
	rc_run_discard(-1, 5);
	rc_run_discard(5, -1);
	rc_run_discard(5, 3);
	return (0);
}
