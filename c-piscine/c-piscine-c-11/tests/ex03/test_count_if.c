#include <stdio.h>
#include <ctype.h>

int	ft_count_if(char **tab, int length, int (*f)(char *));

/* Predicate: truthy (1) when the first character is an uppercase letter. */
static int	first_is_upper(char *s)
{
	if (isupper((unsigned char)s[0]))
		return (1);
	return (0);
}

/* Predicate returning a truthy value that is NOT 1 (100) on a match, so a
 * correct count adds one per match instead of summing the returned values. */
static int	upper_weight(char *s)
{
	if (isupper((unsigned char)s[0]))
		return (100);
	return (0);
}

/* A predicate that also RECORDS which element of g_tab it was handed, by
 * pointer identity, in call order: "This function will be applied following
 * the array's order" (ex03), which a pure predicate cannot see. */
static char	**g_tab;
static int	g_len;
static int	g_log[8];
static int	g_logged;

static int	record_upper(char *s)
{
	int	i;

	i = 0;
	while (i < g_len && g_tab[i] != s)
		i++;
	if (i == g_len)
		i = -1;
	if (g_logged < 8)
		g_log[g_logged] = i;
	g_logged++;
	return (first_is_upper(s));
}

/* Prints the index in the array of each element f was handed, in call order:
 * 0 1 2 ... by construction when the calls follow the array's order. A
 * pointer that is no element of the array is -1. */
static void	test_order(char *label, char **tab, int length)
{
	int	i;

	g_tab = tab;
	g_len = length;
	g_logged = 0;
	ft_count_if(tab, length, &record_upper);
	printf("%s\t", label);
	i = 0;
	while (i < g_logged && i < 8)
	{
		printf("%s%d", i ? " " : "", g_log[i]);
		i++;
	}
	if (g_logged == 0)
		printf("f was never called");
	printf("\n");
}

/* Prints "<label>\t<value>" so tools/diff_output.sh (run with --labeled) can
 * show each case in its own column. Cases are ordered trivial -> hardest, so
 * the first failing row is the most fundamental thing to fix. The test passes
 * the predicate to apply as a function pointer. */
static void	test(char *label, char **tab, int length, int (*f)(char *))
{
	printf("%s\t%d\n", label, ft_count_if(tab, length, f));
}

int	main(void)
{
	char	*tab[] = {"Apple", "banana", "Cherry", "Date", "egg"};
	char	*none[] = {"a", "b", "c"};
	char	*all[] = {"A", "B", "C"};
	char	*bounded[] = {"A", "B", "C", "D", NULL};

	test("length 0 counts nothing", tab, 0, &first_is_upper);
	test("no element matches", none, 3, &first_is_upper);
	test("every element matches", all, 3, &first_is_upper);
	test("some match some do not", tab, 5, &first_is_upper);
	test("match returns 100 not 1", tab, 5, &upper_weight);
	test("length bounds the scan", bounded, 2, &first_is_upper);
	test_order("elements handed to f, by index", tab, 5);
	return (0);
}
