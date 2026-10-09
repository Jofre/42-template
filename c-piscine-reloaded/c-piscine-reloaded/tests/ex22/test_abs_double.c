#include "ft_abs.h"
#include <stdio.h>

/* The same open case with a floating-point argument (finding 087): strict.
 * Negative fractional values, never -0.0, whose printed sign is not what this
 * case is about. Its own main, for the reason test_abs_long.c gives. */
int	main(void)
{
	printf("%s\t%.2f\n", "ABS(-2.5)", (double)ABS(-2.5));
	printf("%s\t%.2f\n", "ABS(2.25)", (double)ABS(2.25));
	printf("%s\t%.2f\n", "ABS(-0.75)", (double)ABS(-0.75));
	return (0);
}
