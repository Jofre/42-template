#include <stdio.h>
#include <string.h>

int	ft_count_if(char **tab, int (*f)(char *));

/* THE READING THIS HARNESS TAKES, AT STRICT (ex26_returns_one_output). The
 * subject counts "the elements of the array that return 1, passed to the
 * function f"; C 11 ex03 counted those that do not return 0. The basic table
 * (test_count_if.c) passes a predicate that returns only 0 or 1, where the
 * two sentences agree. This one's predicate also returns 2, and the count it
 * expects is the literal one: only a return of exactly 1 counts, as the
 * README says (finding 203).
 *
 * The predicate answers by the word itself: "one" -> 1, "two" -> 2, and
 * anything else -> 0. The table below holds three "one", two "two" and one
 * "zero", so a count of the elements that return 1 is 3, a count of those
 * that do not return 0 would be 5, and a sum of the returns 7: three
 * different numbers, by construction. */
static int	one_two_or_zero(char *s)
{
	if (strcmp(s, "one") == 0)
		return (1);
	if (strcmp(s, "two") == 0)
		return (2);
	return (0);
}

int	main(void)
{
	char	*mixed[] = {"one", "two", "zero", "one", "two", "one", NULL};

	printf("f returns 1, 2 or 0\t%d\n", ft_count_if(mixed, &one_two_or_zero));
	return (0);
}
