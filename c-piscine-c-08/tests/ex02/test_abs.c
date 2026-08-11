#include "ft_abs.h"
#include <stdio.h>

/* ABS is a macro, so each case is inlined with its own label. The "expr arg"
 * cases pass an expression (2 - 5) to expose missing parentheses AROUND THE
 * ARGUMENT. The "outer" cases embed ABS(...) inside a larger expression
 * (2 * ABS(-3)) to expose a body missing its OUTER wrapping parentheses, which
 * would then bind by precedence and produce the wrong value. */
int	main(void)
{
	printf("%s\t%d\n", "ABS(0)", ABS(0));
	printf("%s\t%d\n", "ABS(5)", ABS(5));
	printf("%s\t%d\n", "ABS(-5)", ABS(-5));
	printf("%s\t%d\n", "ABS(1)", ABS(1));
	printf("%s\t%d\n", "ABS(-1)", ABS(-1));
	printf("%s\t%d\n", "ABS(2147483647)", ABS(2147483647));
	printf("%s\t%d\n", "ABS(-2147483647)", ABS(-2147483647));
	printf("%s\t%d\n", "ABS(2 - 5) expr arg", ABS(2 - 5));
	printf("%s\t%d\n", "ABS(0 - 8) expr arg", ABS(0 - 8));
	printf("%s\t%d\n", "ABS(10 - 3) expr arg", ABS(10 - 3));
	printf("%s\t%d\n", "2 * ABS(-3) outer", 2 * ABS(-3));
	printf("%s\t%d\n", "10 - ABS(-4) outer", 10 - ABS(-4));
	printf("%s\t%d\n", "1 + ABS(-6) outer", 1 + ABS(-6));
	return (0);
}
