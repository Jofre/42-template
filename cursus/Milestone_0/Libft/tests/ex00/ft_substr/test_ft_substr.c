#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* The fixture of ex00_ft_substr_output: one labelled row per case, the
 * substring printed between quotes in diff_output.sh's notation (\\ a
 * backslash, \n, \t, \xHH any other byte outside printable ASCII), or NULL.
 * Every start here is at most strlen(s): what a start past the end gives is
 * test_ft_substr_start_past_end.c's. Each result is freed, as a caller of a
 * function that allocates must, before its row's newline, so a crash in
 * free() marks its own row. Cases run from the plainest to the longest;
 * the two past 4096 bytes come last, checked against the string they were
 * cut from, by construction. */
char	*ft_substr(char const *s, unsigned int start, size_t len);

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

static void	test(const char *label, const char *s, unsigned int start,
		size_t len)
{
	char	*r;

	r = ft_substr(s, start, len);
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

/* s is n bytes of 'a'..'z' over and over; the substring at start, len, is
 * held to the bytes of s it was cut from: its length, then the first byte
 * that differs. */
static void	test_long(const char *label, size_t n, unsigned int start,
		size_t len, size_t want)
{
	char	*s;
	char	*r;
	size_t	got;
	size_t	i;

	s = malloc(n + 1);
	if (s == NULL)
		return ;
	i = 0;
	while (i < n)
	{
		s[i] = (char)('a' + i % 26);
		i++;
	}
	s[n] = '\0';
	r = ft_substr(s, start, len);
	printf("%s\t", label);
	if (r == NULL)
		printf("NULL");
	else
	{
		got = strlen(r);
		i = 0;
		while (i < got && i < want && r[i] == s[start + i])
			i++;
		if (got != want)
			printf("%zu bytes", got);
		else if (i < want)
			printf("%zu bytes, byte %zu differs", got, i);
		else
			printf("%zu bytes, s[%u..%zu]", got, start, start + want - 1);
	}
	free(r);
	free(s);
	printf("\n");
}

int	main(void)
{
	test("\"Hello, 42!\", 0, 5", "Hello, 42!", 0, 5);
	test("\"Hello, 42!\", 7, 2", "Hello, 42!", 7, 2);
	test("\"Hello, 42!\", 9, 1", "Hello, 42!", 9, 1);
	test("\"Hello, 42!\", 0, 0", "Hello, 42!", 0, 0);
	test("\"Hello, 42!\", 7, 100", "Hello, 42!", 7, 100);
	test("\"Hello, 42!\", 10, 5", "Hello, 42!", 10, 5);
	test("\"Hello, 42!\", 10, 0", "Hello, 42!", 10, 0);
	test("\"\", 0, 5", "", 0, 5);
	test("\"Hello, 42!\", 0, SIZE_MAX", "Hello, 42!", 0, SIZE_MAX);
	test("\"Hello, 42!\", 7, SIZE_MAX", "Hello, 42!", 7, SIZE_MAX);
	test("\"Hello, 42!\", 3, UINT_MAX", "Hello, 42!", 3, (size_t)UINT_MAX);
	test("\"a<TAB>b<LF>c\", 1, 3", "a\tb\nc", 1, 3);
	test("0xe9 't' 0xe9, 1, 1", "\xe9t\xe9", 1, 1);
	test("0xe9 't' 0xe9, 0, 2", "\xe9t\xe9", 0, 2);
	test("0xe9 't' 0xe9, 2, SIZE_MAX", "\xe9t\xe9", 2, SIZE_MAX);
	test("0x80 0xff 0x7f, 1, 2", "\x80\xff\x7f", 1, 2);
	test_long("5000-byte s, 100, 4097", 5000, 100, 4097, 4097);
	test_long("5000-byte s, 4500, SIZE_MAX", 5000, 4500, SIZE_MAX, 500);
	return (0);
}
