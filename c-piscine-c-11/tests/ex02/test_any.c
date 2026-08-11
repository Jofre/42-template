#include <stdio.h>

int	ft_any(char **tab, int (*f)(char *));

/* Predicate: truthy (returns 1) when the word starts with an uppercase letter. */
static int	first_is_upper(char *s)
{
	if (s[0] >= 'A' && s[0] <= 'Z')
		return (1);
	return (0);
}

/* Predicate returning a truthy value that is NOT 1 (100) on a match, to check
 * that ft_any normalises its answer rather than echoing or summing what f gives. */
static int	upper_weight(char *s)
{
	if (s[0] >= 'A' && s[0] <= 'Z')
		return (100);
	return (0);
}

/* Prints "<label>\t<value>" so tools/diff_output.sh (run with --labeled) can
 * show each case in its own column. Cases are ordered trivial -> hardest, so
 * the first failing row is the most fundamental thing to fix. */
static void	test(char *label, char **tab, int (*f)(char *))
{
	printf("%s\t%d\n", label, ft_any(tab, f));
}

int	main(void)
{
	char	*empty[] = {NULL};
	char	*one_no[] = {"apple", NULL};
	char	*one_yes[] = {"Apple", NULL};
	char	*no_upper[] = {"apple", "banana", "cherry", NULL};
	char	*first_match[] = {"Zebra", "apple", "cherry", NULL};
	char	*last_match[] = {"apple", "banana", "Cherry", NULL};
	char	*has_upper[] = {"apple", "Banana", "cherry", NULL};
	char	*all_match[] = {"Apple", "Banana", "Cherry", NULL};

	test("empty table", empty, &first_is_upper);
	test("single no match", one_no, &first_is_upper);
	test("single match", one_yes, &first_is_upper);
	test("none of several match", no_upper, &first_is_upper);
	test("match at first position", first_match, &first_is_upper);
	test("match only at last", last_match, &first_is_upper);
	test("match in the middle", has_upper, &first_is_upper);
	test("every element matches", all_match, &first_is_upper);
	test("truthy is 100 normalise", all_match, &upper_weight);
	return (0);
}
