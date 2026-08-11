#include <stdio.h>
#include <string.h>

void	ft_advanced_sort_string_tab(char **tab, int (*cmp)(char *, char *));

/* libc's strcmp, not a hand-written one. This harness needs SOME lexicographic
 * comparator to pass in, and writing it out here would publish c-03 ex00's
 * answer -- including the (unsigned char) cast, which is the one subtlety that
 * exercise turns on and which its own clues.tsv deliberately declines to state.
 * A test file is not exempt from that: it ships, and it is greppable. Nothing is
 * lost by calling libc, because what this exercise checks is that YOUR function
 * uses the comparator it is handed, not what the comparator does. */
static int	lex_cmp(char *s1, char *s2)
{
	return (strcmp(s1, s2));
}

static int	rev_strcmp(char *s1, char *s2)
{
	return (-lex_cmp(s1, s2));
}

static int	slen(char *s)
{
	int	i;

	i = 0;
	while (s[i])
		i++;
	return (i);
}

/* orders by string length; differs from strcmp order so it proves cmp is used */
static int	cmp_len(char *s1, char *s2)
{
	return (slen(s1) - slen(s2));
}

/* Sorts tab in place with the supplied cmp, then prints "<label>\t" followed by
 * every element bracketed [str] on one line (so tools/diff_output.sh --labeled
 * shows one case per row). An empty table prints just the label and a newline.
 * Cases run trivial -> hardest, so the first failing row is the most
 * fundamental thing to fix. */
static void	test(char *label, char **tab, int (*cmp)(char *, char *))
{
	int	i;

	ft_advanced_sort_string_tab(tab, cmp);
	printf("%s\t", label);
	i = 0;
	while (tab[i])
		printf("[%s]", tab[i++]);
	printf("\n");
}

int	main(void)
{
	char	*empty[] = {NULL};
	char	*single[] = {"solo", NULL};
	char	*pair[] = {"banana", "apple", NULL};
	char	*ascending[] = {"banana", "apple", "cherry", "Apple", NULL};
	char	*dups[] = {"pear", "apple", "pear", NULL};
	char	*reversed[] = {"banana", "apple", "cherry", "Apple", NULL};
	char	*bylen[] = {"zzz", "aa", "m", NULL};

	test("empty table", empty, &lex_cmp);
	test("single element", single, &lex_cmp);
	test("two elements ascending", pair, &lex_cmp);
	test("ascending strcmp", ascending, &lex_cmp);
	test("duplicates preserved", dups, &lex_cmp);
	test("reversed comparator descending", reversed, &rev_strcmp);
	test("order by length not strcmp", bylen, &cmp_len);
	return (0);
}
