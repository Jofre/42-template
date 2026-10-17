#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* The fixture of ex00_ft_strjoin_output: one labelled row per case, the new
 * string printed between quotes in diff_output.sh's notation (\\ a
 * backslash, \n, \t, \xHH any other byte outside printable ASCII), or NULL.
 * Each result is freed before its row's newline, so a crash in free() marks
 * its own row. The row past 4096 bytes comes last, held to the two
 * strings it was joined from, by construction, and so are they: neither may
 * change. */
char	*ft_strjoin(char const *s1, char const *s2);

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

static void	test(const char *label, const char *s1, const char *s2)
{
	char	*r;

	r = ft_strjoin(s1, s2);
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

static char	*filled(size_t n, char first)
{
	char	*s;
	size_t	i;

	s = malloc(n + 1);
	if (s == NULL)
		exit(1);
	i = 0;
	while (i < n)
	{
		s[i] = (char)(first + i % 26);
		i++;
	}
	s[n] = '\0';
	return (s);
}

/* Whether s still holds the n bytes filled() wrote. */
static int	intact(const char *s, size_t n, char first)
{
	size_t	i;

	i = 0;
	while (i < n && s[i] == (char)(first + i % 26))
		i++;
	return (i == n && s[n] == '\0');
}

/* s1 is 4100 bytes of 'a'..'z' over and over, s2 5000 of 'A'..'Z': the
 * result is held to s1 then s2, its length first, then the first byte that
 * differs; and each input to the bytes it was built with. */
static void	test_long(void)
{
	char	*s1;
	char	*s2;
	char	*r;
	size_t	got;
	size_t	i;

	s1 = filled(4100, 'a');
	s2 = filled(5000, 'A');
	r = ft_strjoin(s1, s2);
	printf("4100-byte s1, 5000-byte s2\t");
	if (r == NULL)
		printf("NULL");
	else
	{
		got = strlen(r);
		i = 0;
		while (i < got && i < 9100
			&& r[i] == (i < 4100 ? s1[i] : s2[i - 4100]))
			i++;
		printf("%zu bytes", got);
		if (got == 9100 && i == 9100)
			printf(", s1 then s2");
		else if (i < got)
			printf(", byte %zu differs", i);
	}
	if (!intact(s1, 4100, 'a') || !intact(s2, 5000, 'A'))
		printf(", an input changed");
	free(r);
	free(s1);
	free(s2);
	printf("\n");
}

int	main(void)
{
	test("\"Hello, \", \"42\"", "Hello, ", "42");
	test("\"abc\", \"def\"", "abc", "def");
	test("\"\", \"\"", "", "");
	test("\"\", \"b\"", "", "b");
	test("\"a\", \"\"", "a", "");
	test("\"a<TAB>b\", \"c<LF>d\"", "a\tb", "c\nd");
	test("0xe9, 0xff", "\xe9", "\xff");
	test("0x80 0x7f, 0xff 0x01", "\x80\x7f", "\xff\x01");
	test_long();
	return (0);
}
