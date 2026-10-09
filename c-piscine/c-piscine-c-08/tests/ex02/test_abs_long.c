#include "ft_abs.h"
#include <stdio.h>

/* "Create a macro ABS which replaces its argument with its absolute value"
 * names no type, so an argument wider than int is a case the subject leaves
 * open: strict, not basic (finding 087). long long, the type C guarantees at
 * least 64 bits, with values beyond int's range, of both signs and both
 * parities. Its own main, so an argument this header cannot take fails this
 * case alone and never hides the int results. */
int	main(void)
{
	printf("%s\t%lld\n", "ABS(3000000000LL)", (long long)ABS(3000000000LL));
	printf("%s\t%lld\n", "ABS(-3000000000LL)", (long long)ABS(-3000000000LL));
	printf("%s\t%lld\n", "ABS(-3000000001LL)", (long long)ABS(-3000000001LL));
	printf("%s\t%lld\n", "ABS(4000000001LL)", (long long)ABS(4000000001LL));
	return (0);
}
