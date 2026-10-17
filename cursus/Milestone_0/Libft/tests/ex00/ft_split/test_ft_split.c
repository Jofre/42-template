#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* The fixture of ex00_ft_split_output: one labelled row per case, printed as
 * how many strings the array holds before its NULL, a colon, then each string
 * bracketed, [like][this], in diff_output.sh's notation (\\ a backslash, \n,
 * \t, \xHH any other byte outside printable ASCII) -- or NULL for a NULL
 * array. Only the cases every reading of the box (p.11) agrees on are here:
 * s is not empty, c is not '\0', and no delimiter sits at either end of s or
 * beside another, so every field is a word. What the others give is
 * test_ft_split_empty_fields.c's.
 *
 * The walk is capped by the count each case expects: the entry where the
 * NULL belongs is read, and when it is not NULL the row says "more than N"
 * and that entry is neither printed nor freed -- a wrong answer may never
 * have set it. Each string printed is freed, then the array, as the box says
 * the caller releases it, before the row's newline, so a crash in free()
 * marks its own row. The two rows past 4096 come last, checked by
 * construction. */
char	**ft_split(char const *s, char c);

static void	put_esc(const char *s)
{
	const unsigned char	*p;

	p = (const unsigned char *)s;
	while (*p)
	{
		if (*p == '\\')
			printf("\\\\");
		else if (*p == '\n')
			printf("\\n");
		else if (*p == '\t')
			printf("\\t");
		else if (*p < 0x20 || *p > 0x7e)
			printf("\\x%02x", *p);
		else
			putchar(*p);
		p++;
	}
}

/* How many entries of res come before its NULL, reading at most want + 1:
 * want + 1 means "more than want". Only the first want of them are ever
 * printed or freed. */
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
	{
		printf(" [");
		put_esc(res[i]);
		printf("]");
		i++;
	}
	release(res, n, want);
	printf("\n");
}

/* 5000 words, "w0" to "w4999", one space between two of them; each string
 * of the result is held to its word. */
static void	test_many_words(void)
{
	char	*s;
	char	**res;
	char	word[16];
	size_t	len;
	size_t	n;
	size_t	i;

	s = malloc(5000 * 6 + 1);
	if (s == NULL)
		exit(1);
	len = 0;
	i = 0;
	while (i < 5000)
	{
		len += (size_t)sprintf(s + len, i ? " w%zu" : "w%zu", i);
		i++;
	}
	res = ft_split(s, ' ');
	printf("5000 words, one space between two\t");
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
			printf("%zu: string %zu is not w%zu", n, i, i);
		else if (n < 5000)
			printf("%zu:", n);
		else
			printf("5000: [w0] ... [w4999]");
		release(res, n, 5000);
	}
	free(s);
	printf("\n");
}

/* One word of 5000 bytes, 'a'..'z' over and over, and no delimiter in it. */
static void	test_long_word(void)
{
	char	*s;
	char	**res;
	size_t	n;
	size_t	i;

	s = malloc(5001);
	if (s == NULL)
		exit(1);
	i = 0;
	while (i < 5000)
	{
		s[i] = (char)('a' + i % 26);
		i++;
	}
	s[5000] = '\0';
	res = ft_split(s, ' ');
	printf("one 5000-byte word, ' '\t");
	if (res == NULL)
		printf("NULL");
	else
	{
		n = count(res, 1);
		if (n > 1)
			printf("more than 1");
		else if (n == 0)
			printf("0:");
		else if (strcmp(res[0], s) != 0)
			printf("1: [%zu bytes, not the word]", strlen(res[0]));
		else
			printf("1: [the 5000-byte word]");
		release(res, n, 1);
	}
	free(s);
	printf("\n");
}

int	main(void)
{
	test("\"hello\", ' '", "hello", ' ', 1);
	test("\"a b\", ' '", "a b", ' ', 2);
	test("\"a b c\", ' '", "a b c", ' ', 3);
	test("\"hello world 42\", ' '", "hello world 42", ' ', 3);
	test("\"a,b\", ','", "a,b", ',', 2);
	test("\"abc\", 'x'", "abc", 'x', 1);
	test("\"x\", 'y'", "x", 'y', 1);
	test("\"one<TAB>two\", '<TAB>'", "one\ttwo", '\t', 2);
	test("\"a b,c d\", ','", "a b,c d", ',', 2);
	test("\"a\" 0xe9 \"b\", 0xe9", "a\xe9" "b", '\xe9', 2);
	test("0xe9 ' ' 0xff, ' '", "\xe9 \xff", ' ', 2);
	test("\"a\" 0xff \"b\" 0xff \"c\", 0xff", "a\xff" "b\xff" "c", '\xff', 3);
	test_many_words();
	test_long_word();
	return (0);
}
