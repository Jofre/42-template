#include <ctype.h>
#include <stdio.h>

int	ft_count_if(char **tab, int (*f)(char *));

/* Predicate: 1 when the first character is an uppercase letter, else 0. */
static int	first_is_upper(char *s)
{
	if (isupper((unsigned char)s[0]))
		return (1);
	return (0);
}

/* Prints "<label>\t<value>" so tools/diff_output.sh (run with --labeled) can
 * show each case in its own column. Cases go from trivial to hardest, so the
 * first failing row is the most fundamental thing to fix. */
static void	test(char *label, char **tab)
{
	printf("%s\t%d\n", label, ft_count_if(tab, &first_is_upper));
}

int	main(void)
{
	char	*empty[] = {NULL};
	char	*none[] = {"a", "b", "c", NULL};
	char	*all[] = {"A", "B", "C", NULL};
	char	*some[] = {"Apple", "banana", "Cherry", "Date", "egg", NULL};
	char	*stops[] = {"A", "B", NULL, "C", "D", NULL};

	test("empty array counts nothing", empty);
	test("no element matches", none);
	test("every element matches", all);
	test("some match some do not", some);
	test("the first NULL ends the array", stops);
	return (0);
}
