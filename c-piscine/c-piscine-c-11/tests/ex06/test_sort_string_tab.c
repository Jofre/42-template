#include <stdio.h>

void	ft_sort_string_tab(char **tab);

/* Sorts tab in place, then prints "<label>\t[s0][s1]..." so
 * tools/diff_output.sh (run with --labeled) can show each case in its own
 * column. Every sorted string lands on the same labeled line, bracketed.
 * Cases are ordered trivial -> hardest, so the first failing row is the most
 * fundamental thing to fix. */
static void	test(char *label, char **tab)
{
	int	i;

	ft_sort_string_tab(tab);
	printf("%s\t", label);
	i = 0;
	while (tab[i])
	{
		printf("[%s]", tab[i]);
		i++;
	}
	printf("\n");
}

int	main(void)
{
	char	*empty[] = {NULL};
	char	*single[] = {"solo", NULL};
	char	*sorted[] = {"a", "b", "c", NULL};
	char	*reverse[] = {"cherry", "banana", "apple", NULL};
	char	*dups[] = {"pear", "apple", "pear", "apple", NULL};
	char	*mixed[] = {"banana", "apple", "cherry", "Apple", NULL};
	char	*prefix[] = {"apricot", "apple", "apply", NULL};
	char	*substr[] = {"band", "banana", "ban", NULL};
	char	*tail[] = {"abcd", "abce", "abca", NULL};

	test("empty table", empty);
	test("single element", single);
	test("already sorted", sorted);
	test("reverse sorted", reverse);
	test("duplicates preserved", dups);
	test("uppercase before lowercase", mixed);
	test("shared prefix differ mid-string", prefix);
	test("one string is a prefix of another", substr);
	test("differ only at last byte", tail);
	return (0);
}
