#include "ft_boolean.h"
#include <stdio.h>
#include <limits.h>

// No local ft_putstr, on purpose: writing one out here would publish c-01
// ex05's answer in a file that ships, and this test has no use for it -- it
// needs to emit EVEN_MSG/ODD_MSG, not to demonstrate how. fputs does that.
// (test_ft_h.c one directory over defines its ft_* symbols as empty stubs for
// the same reason: a test harness is not exempt from the no-answers rule.)

t_bool	ft_is_even(int nbr)
{
	return ((EVEN(nbr)) ? TRUE : FALSE);
}

/* Exercise the EVEN macro across signs/boundaries via the same TRUE/FALSE */
/* contract the subject relies on. This output is argv-independent, so it is */
/* identical for the "even" and "odd" cases. */
static void	check(int n)
{
	if (ft_is_even(n) == TRUE)
		printf("%d even\n", n);
	else
		printf("%d odd\n", n);
}

/* EVEN applied to an EXPRESSION is checked in test_boolean_expr.c, at the */
/* strict level rather than this one. The subject's own main only ever passes */
/* EVEN an int parameter, so requiring more than that here would fail a header */
/* that is correct against everything the subject asks for -- at the gate a */
/* beginner meets first. */

int	main(int argc, char **argv)
{
	(void)argv;
	check(0);
	check(1);
	check(2);
	check(-1);
	check(-2);
	check(-3);
	check(7);
	check(42);
	check(INT_MAX);
	check(INT_MIN);
	fflush(stdout);
	if (ft_is_even(argc - 1) == TRUE)
		fputs(EVEN_MSG, stdout);
	else
		fputs(ODD_MSG, stdout);
	return (SUCCESS);
}
