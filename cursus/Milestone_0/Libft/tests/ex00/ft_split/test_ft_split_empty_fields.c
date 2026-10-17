#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ex00_ft_split_empty_fields_output: the cases ft_split's box (p.11) leaves
 * open -- an empty s, c == '\0', a delimiter at either end of s or beside
 * another, so a field with no byte in it. This target tests one reading of
 * them, at strict (the BUILD file says why), and its hint says which.
 *
 * Printed as test_ft_split.c prints: how many strings come before the NULL,
 * a colon, each string bracketed -- raw here, every string these inputs
 * should give being printable -- or NULL. The walk is capped by the count
 * each case expects: the entry where the NULL belongs is read, and when it
 * is not NULL the row says "more than N" and that entry is neither printed
 * nor freed. Each string printed is freed, then the array, before the row's
 * newline, so a crash in free() marks its own row. The row past 4096 comes
 * last, checked by construction. */
char	**ft_split(char const *s, char c);

static size_t	count(char **res, size_t want)
{
	size_t	n;

	n = 0;
	while (n <= want && res[n] != NULL)
		n++;
	return (n);
}

static void	release(char **res, size_t n, size_t want)
{
	size_t	i;

	i = 0;
	while (i < n && i < want)
		free(res[i++]);
	free(res);
}

static void	test(const char *label, const char *s, char c, size_t want)
{
	char	**res;
	size_t	n;
	size_t	i;

	res = ft_split(s, c);
	printf("%s\t", label);
	if (res == NULL)
	{
		printf("NULL\n");
		return ;
	}
	n = count(res, want);
	if (n > want)
		printf("more than %zu:", want);
	else
		printf("%zu:", n);
	i = 0;
	while (i < n && i < want)
		printf(" [%s]", res[i++]);
	release(res, n, want);
	printf("\n");
}

/* 5000 words, "w0" to "w4999", each with two commas before it, and two
 * after the last; each string of the result is held to its word. */
static void	test_many_words(void)
{
	char	*s;
	char	**res;
	char	word[16];
	size_t	len;
	size_t	n;
	size_t	i;

	s = malloc(5000 * 7 + 3);
	if (s == NULL)
		exit(1);
	len = 0;
	i = 0;
	while (i < 5000)
	{
		len += (size_t)sprintf(s + len, ",,w%zu", i);
		i++;
	}
	strcpy(s + len, ",,");
	res = ft_split(s, ',');
	printf("5000 words, two commas around each\t");
	if (res == NULL)
		printf("NULL");
	else
	{
		n = count(res, 5000);
		i = 0;
		while (i < n && i < 5000)
		{
			sprintf(word, "w%zu", i);
			if (strcmp(res[i], word) != 0)
				break ;
			i++;
		}
		if (n > 5000)
			printf("more than 5000");
		else if (i < n)
			printf("%zu: string %zu is [%s], not [w%zu]", n, i, res[i], i);
		else if (n < 5000)
			printf("%zu:", n);
		else
			printf("5000: [w0] ... [w4999]");
		release(res, n, 5000);
	}
	free(s);
	printf("\n");
}

int	main(void)
{
	test("\"  hello  world  \", ' '", "  hello  world  ", ' ', 2);
	test("\",a,,b,\", ','", ",a,,b,", ',', 2);
	test("\"a,,b\", ','", "a,,b", ',', 2);
	test("\",a\", ','", ",a", ',', 1);
	test("\"a,\", ','", "a,", ',', 1);
	test("\"\", ' '", "", ' ', 0);
	test("\"   \", ' '", "   ", ' ', 0);
	test("\",\", ','", ",", ',', 0);
	test("\"abc\", NUL", "abc", '\0', 1);
	test("\"\", NUL", "", '\0', 0);
	test("0xe9 0xe9 \"a\" 0xe9, 0xe9", "\xe9\xe9" "a\xe9", '\xe9', 1);
	test_many_words();
	return (0);
}
