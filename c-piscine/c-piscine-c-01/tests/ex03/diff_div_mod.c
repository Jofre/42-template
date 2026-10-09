/* Live-differential reader harness for ft_div_mod.
 * Line: <a>\t<b>\t<div>\t<mod>. Reads a and b, calls ft_div_mod, and reprints
 * <a>\t<b>\t<div>\t<mod>, where a result the function never stored through
 * its pointer reads "untouched". Inputs never trigger C UB (b != 0, never
 * INT_MIN/-1). See tools/diffio.h.
 *
 * UNTOUCHED, and why each case runs twice. The two ints start at a preset,
 * and one that still holds it was never written: they used to start at 0, a
 * value many cases expect, so a function that skipped the store there
 * matched the reference. But any int can be a quotient, so no one preset is
 * safe: each case runs once from PRESET_A and once from PRESET_B, and only
 * a result that kept its preset BOTH times is untouched. A function that
 * stores its result stores the same one both times, whatever it is. */
#include "diffio.h"

void	ft_div_mod(int a, int b, int *div, int *mod);

#define PRESET_A 1592614637
#define PRESET_B (-1592614637)

/* A result from the two runs: "untouched" when each kept its run's preset. */
static void	show(int first, int second)
{
	if (first == PRESET_A && second == PRESET_B)
		printf("untouched");
	else
		printf("%d", first);
}

int	main(void)
{
	char	line[8192];
	char	*f[4];
	int		a;
	int		b;
	int		d;
	int		m;
	int		d2;
	int		m2;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 4) < 2)
			continue ;
		a = (int)strtol(f[0], NULL, 10);
		b = (int)strtol(f[1], NULL, 10);
		d = PRESET_A;
		m = PRESET_A;
		ft_div_mod(a, b, &d, &m);
		d2 = PRESET_B;
		m2 = PRESET_B;
		ft_div_mod(a, b, &d2, &m2);
		printf("%s\t%s\t", f[0], f[1]);
		show(d, d2);
		printf("\t");
		show(m, m2);
		printf("\n");
	}
	return (0);
}
