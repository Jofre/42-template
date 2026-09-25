/* Memory-safety probe for rush(x, y) — compiled with the student's rush0N.c and
 * ft_putchar.c under ASan + UBSan and RUN (tools/asan_check.sh).
 *
 * rush() owns no caller buffer, so nothing here can diff a value: what this
 * catches is the class of bug output-diffing cannot see — a fixed internal
 * buffer ("char line[100];") written past its end for a wide rectangle, an
 * index that goes negative, a signed-overflow in x * y, a read of an
 * uninitialised cell that happens to hold the right character today. Output is
 * sent to /dev/null; the sanitizer is the assertion.
 *
 * The sweep is deliberately wider than the buffer sizes students reach for
 * (80, 100, 128, 256, 1024) so an unchecked internal buffer is actually
 * overrun here rather than at the evaluation. */
#include "rush_capture.h"

static const int	g_degenerate[] = {
	0, -1, -2, -7, -42, -1000, -2147483647 - 1, 2147483647
};

static const int	g_ceilings[] = {
	63, 64, 65, 79, 80, 81, 99, 100, 101, 127, 128, 129, 255, 256, 257,
	511, 512, 513, 1023, 1024, 1025, 2047, 2048, 2049, 4095, 4096, 4097
};

int	main(void)
{
	int	x;
	int	y;
	int	i;
	int	k;

	rc_guard(60, 16UL * 1024 * 1024);
	/* every small rectangle, exhaustively */
	x = 1;
	while (x <= 40)
	{
		y = 1;
		while (y <= 40)
			rc_run_discard(x, y++);
		x++;
	}
	/* every buffer/counter ceiling and its neighbours, wide and tall: this is
	 * where "char line[80];" is actually overrun. Same list as the CEILINGS in
	 * oracle/src/rush00.rs, so a failure here and a divergence there name the
	 * same sizes. */
	i = 0;
	while (i < (int)(sizeof(g_ceilings) / sizeof(g_ceilings[0])))
	{
		k = 1;
		while (k <= 3)
		{
			rc_run_discard(g_ceilings[i], k);
			rc_run_discard(k, g_ceilings[i]);
			k++;
		}
		i++;
	}
	/* a few big-but-sane rectangles */
	rc_run_discard(123, 42);
	rc_run_discard(300, 300);
	rc_run_discard(1024, 4);
	rc_run_discard(4, 1024);
	rc_run_discard(32768, 1);
	rc_run_discard(1, 32768);
	rc_run_discard(65536, 1);
	rc_run_discard(1, 65536);
	/* every degenerate dimension, alone and paired with a normal one. A huge
	 * dimension only ever appears next to a non-positive one: rush(INT_MAX, 42)
	 * is 90 billion legitimate characters, not a bug worth waiting for. */
	i = 0;
	while (i < (int)(sizeof(g_degenerate) / sizeof(g_degenerate[0])))
	{
		k = 0;
		while (k < (int)(sizeof(g_degenerate) / sizeof(g_degenerate[0])))
		{
			if (g_degenerate[i] <= 0 || g_degenerate[k] <= 0)
				rc_run_discard(g_degenerate[i], g_degenerate[k]);
			k++;
		}
		rc_run_discard(g_degenerate[i], 0);
		rc_run_discard(0, g_degenerate[i]);
		if (g_degenerate[i] <= 0)
		{
			rc_run_discard(g_degenerate[i], 5);
			rc_run_discard(5, g_degenerate[i]);
			rc_run_discard(g_degenerate[i], 42);
			rc_run_discard(42, g_degenerate[i]);
		}
		i++;
	}
	/* and back to normal afterwards, twice, to shake out leaked state */
	rc_run_discard(5, 3);
	rc_run_discard(5, 3);
	printf("mem probe: OK\n");
	return (0);
}
