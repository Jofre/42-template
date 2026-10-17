#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* The fixture of ex00_ft_strtrim_output: one labelled row per case, the
 * trimmed string printed between quotes in diff_output.sh's notation (\\ a
 * backslash, \n, \t, \xHH any other byte outside printable ASCII), or NULL.
 * Each result is freed before its row's newline, so a crash in free() marks
 * its own row. The two rows past 4096 bytes come last, built so
 * the answer is known by construction: a long s1 whose middle is the
 * answer, and a long set. */
char	*ft_strtrim(char const *s1, char const *set);

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

static void	show(const char *label, char *r)
{
	printf("%s\t", label);
	if (r == NULL)
		printf("NULL");
	else
	{
		printf("\"");
		put_esc(r);
		printf("\"");
	}
	free(r);
	printf("\n");
}

static void	test(const char *label, const char *s1, const char *set)
{
	show(label, ft_strtrim(s1, set));
}

/* s1: 4100 blanks, 5000 bytes of 'a'..'z' over and over, 4100 blanks; set
 * " ". The result is held to the middle: its length, then the first byte
 * that differs. */
static void	test_long_s1(void)
{
	char	*s1;
	char	*r;
	size_t	i;
	size_t	got;

	s1 = malloc(13201);
	if (s1 == NULL)
		exit(1);
	memset(s1, ' ', 13200);
	i = 0;
	while (i < 5000)
	{
		s1[4100 + i] = (char)('a' + i % 26);
		i++;
	}
	s1[13200] = '\0';
	r = ft_strtrim(s1, " ");
	printf("4100 blanks, 5000 letters, 4100 blanks; \" \"\t");
	if (r == NULL)
		printf("NULL");
	else
	{
		got = strlen(r);
		i = 0;
		while (i < got && i < 5000 && r[i] == s1[4100 + i])
			i++;
		if (got == 5000 && i == 5000)
			printf("5000 bytes, the letters");
		else if (i < got)
			printf("%zu bytes, byte %zu differs", got, i);
		else
			printf("%zu bytes", got);
	}
	free(r);
	free(s1);
	printf("\n");
}

/* set: 4999 '#' and one '*', its last byte; s1 "**hi**". */
static void	test_long_set(void)
{
	char	*set;

	set = malloc(5001);
	if (set == NULL)
		exit(1);
	memset(set, '#', 4999);
	set[4999] = '*';
	set[5000] = '\0';
	show("\"**hi**\", 4999 '#' then '*'", ft_strtrim("**hi**", set));
	free(set);
}

int	main(void)
{
	test("\"  hello  \", \" \"", "  hello  ", " ");
	test("\"xxhixx\", \"x\"", "xxhixx", "x");
	test("\"abcHELLOcba\", \"abc\"", "abcHELLOcba", "abc");
	test("\"--+hi+-\", \"+-+\"", "--+hi+-", "+-+");
	test("\"xxhi\", \"x\"", "xxhi", "x");
	test("\"hixx\", \"x\"", "hixx", "x");
	test("\"a b\", \" \"", "a b", " ");
	test("\"x y x\", \"x\"", "x y x", "x");
	test("\"hello\", \"\"", "hello", "");
	test("\"hello\", \"xyz\"", "hello", "xyz");
	test("\"\", \"abc\"", "", "abc");
	test("\"\", \"\"", "", "");
	test("\"aaaa\", \"a\"", "aaaa", "a");
	test("\"<TAB><LF> hi <LF><TAB>\", \"<TAB><LF> \"", "\t\n hi \n\t",
		"\t\n ");
	test("0xe9 0xe9 \"hi\" 0xe9, 0xe9", "\xe9\xe9hi\xe9", "\xe9");
	test("0xff \"a\" 0x80 \"b\" 0xff, 0xff", "\xff" "a\x80" "b\xff", "\xff");
	test_long_s1();
	test_long_set();
	return (0);
}
