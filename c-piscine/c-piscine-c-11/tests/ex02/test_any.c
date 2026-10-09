#include <stdio.h>
#include <ctype.h>

int	ft_any(char **tab, int (*f)(char *));

/* Predicate: truthy (returns 1) when the word starts with an uppercase letter. */
static int	first_is_upper(char *s)
{
	if (isupper((unsigned char)s[0]))
		return (1);
	return (0);
}

/* Predicate returning a truthy value that is NOT 1 (100) on a match, to check
 * that ft_any normalises its answer rather than echoing or summing what f gives. */
static int	upper_weight(char *s)
{
	if (isupper((unsigned char)s[0]))
		return (100);
	return (0);
}

/* A predicate that also RECORDS which element of g_tab it was handed, by
 * pointer identity, in call order: "This function will be applied following
 * the array's order" (ex02), which a pure predicate cannot see. */
static char	**g_tab;
static int	g_log[8];
static int	g_logged;

static int	record_upper(char *s)
{
	int	i;

	i = 0;
	while (g_tab[i] != NULL && g_tab[i] != s)
		i++;
	if (g_tab[i] == NULL)
		i = -1;
	if (g_logged < 8)
		g_log[g_logged] = i;
	g_logged++;
	return (first_is_upper(s));
}

/* Whether the calls followed the array's order: the recorded indices are 0,
 * 1, 2, ... from the first call on, however many there were. ft_any may stop
 * at the first element f answers yes to, or look at them all -- the subject
 * says neither -- so only the order is judged, never the count. */
static void	test_order(char *label, char **tab)
{
	int	i;

	g_tab = tab;
	g_logged = 0;
	ft_any(tab, &record_upper);
	i = 0;
	while (i < g_logged && i < 8 && g_log[i] == i)
		i++;
	if (g_logged == 0)
		printf("%s\tf was never called\n", label);
	else if (i == g_logged)
		printf("%s\tyes\n", label);
	else
		printf("%s\tno\n", label);
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
	test_order("calls follow the array's order", last_match);
	return (0);
}
