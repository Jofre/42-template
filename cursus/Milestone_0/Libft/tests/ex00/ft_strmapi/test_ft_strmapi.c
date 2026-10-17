#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* The fixture of ex00_ft_strmapi_output: one labelled row per case, the new
 * string printed between quotes in diff_output.sh's notation (\\ a
 * backslash, \n, \t, \xHH any other byte outside printable ASCII), or NULL,
 * then the calls f received, in the order it received them, each as
 * index:character. Each f below is the harness's own and logs its calls;
 * each result is freed before its row's newline, so a crash in free() marks
 * its own row. The row past 4096 bytes comes last, checked by
 * construction: its f is told which call it should be next. */
char	*ft_strmapi(char const *s, char (*f)(unsigned int, char));

#define LOG_MAX 16

static unsigned int		g_index[LOG_MAX];
static unsigned char	g_char[LOG_MAX];
static size_t			g_calls;

static void	put_esc_char(unsigned char c)
{
	if (c == '\\')
		printf("\\\\");
	else if (c == '\n')
		printf("\\n");
	else if (c == '\t')
		printf("\\t");
	else if (c < 0x20 || c > 0x7e)
		printf("\\x%02x", c);
	else
		putchar(c);
}

static void	logged(unsigned int i, char c)
{
	if (g_calls < LOG_MAX)
	{
		g_index[g_calls] = i;
		g_char[g_calls] = (unsigned char)c;
	}
	g_calls++;
}

/* Each byte moved up by its index. */
static char	plus_index(unsigned int i, char c)
{
	logged(i, c);
	return ((char)(c + i));
}

/* 0xe0 plus the index, whatever the byte. */
static char	high_by_index(unsigned int i, char c)
{
	logged(i, c);
	return ((char)(0xe0 + i));
}

/* The byte it is handed, unchanged. */
static char	same(unsigned int i, char c)
{
	logged(i, c);
	return (c);
}

static void	test(const char *label, const char *s,
		char (*f)(unsigned int, char))
{
	char	*r;
	size_t	k;

	g_calls = 0;
	r = ft_strmapi(s, f);
	printf("%s\t", label);
	if (r == NULL)
		printf("NULL");
	else
	{
		printf("\"");
		k = 0;
		while (r[k])
			put_esc_char((unsigned char)r[k++]);
		printf("\"");
	}
	if (g_calls == 0)
		printf(", no call");
	else
		printf(", calls");
	k = 0;
	while (k < g_calls && k < LOG_MAX)
	{
		printf(" %u:", g_index[k]);
		put_esc_char(g_char[k]);
		k++;
	}
	if (g_calls > LOG_MAX)
		printf(" ... %zu calls", g_calls);
	free(r);
	printf("\n");
}

static const char	*g_long;
static size_t		g_next;
static int			g_wrong;

/* For the long row: notes a call that is not the next index, or not handed
 * that index's byte; gives back the byte's upper-case letter. */
static char	upper_in_order(unsigned int i, char c)
{
	if (i != g_next || i >= 5000 || c != g_long[i])
		g_wrong = 1;
	g_next++;
	return ((char)(c - 32));
}

/* s: 5000 bytes of 'a'..'z' over and over. */
static void	test_long(void)
{
	char	*s;
	char	*r;
	size_t	i;
	size_t	got;

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
	g_long = s;
	g_next = 0;
	g_wrong = 0;
	r = ft_strmapi(s, upper_in_order);
	printf("5000 letters, upper case\t");
	if (r == NULL)
		printf("NULL");
	else
	{
		got = strlen(r);
		i = 0;
		while (i < got && i < 5000 && r[i] == (char)('A' + i % 26))
			i++;
		printf("%zu bytes", got);
		if (i < got)
			printf(", byte %zu differs", i);
	}
	if (g_wrong)
		printf(", a call out of order or handed the wrong byte");
	printf(", %zu calls", g_next);
	free(r);
	free(s);
	printf("\n");
}

int	main(void)
{
	test("\"aaaa\", c + i", "aaaa", plus_index);
	test("\"abc\", c + i", "abc", plus_index);
	test("\"\", c + i", "", plus_index);
	test("\"abc\", 0xe0 + i", "abc", high_by_index);
	test("\"a<TAB>b<LF>\", c", "a\tb\n", same);
	test("0xe9 0xff 0x80, c", "\xe9\xff\x80", same);
	test_long();
	return (0);
}
