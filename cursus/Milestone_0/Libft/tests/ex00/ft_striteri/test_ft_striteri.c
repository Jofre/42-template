#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* The fixture of ex00_ft_striteri_output: one labelled row per case, the
 * string after the call printed between quotes in diff_output.sh's notation
 * (\\ a backslash, \n, \t, \xHH any other byte outside printable ASCII),
 * then the calls f received, in the order it received them, each as
 * index@address=character: the index, where the address points as s+offset
 * (or "elsewhere"), and the byte found there before f changed it. Every s is
 * a writable buffer of the harness's own; each f below is the harness's and
 * logs its calls, and none writes a '\0'. The row past 4096 bytes comes
 * last, checked by construction: its f is told which call it should be
 * next. */
void	ft_striteri(char *s, void (*f)(unsigned int, char*));

#define LOG_MAX 16

static unsigned int		g_index[LOG_MAX];
static long				g_offset[LOG_MAX];
static unsigned char	g_char[LOG_MAX];
static size_t			g_calls;
static char				*g_base;
static size_t			g_len;

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

/* Logs a call; reads the byte only where p is inside s, terminator
 * included. */
static void	logged(unsigned int i, char *p)
{
	long	off;

	off = -1;
	if (p >= g_base && p <= g_base + g_len)
		off = (long)(p - g_base);
	if (g_calls < LOG_MAX)
	{
		g_index[g_calls] = i;
		g_offset[g_calls] = off;
		g_char[g_calls] = off < 0 ? 0 : (unsigned char)*p;
	}
	g_calls++;
}

/* Moves the byte up by its index. */
static void	plus_index(unsigned int i, char *p)
{
	logged(i, p);
	if (p >= g_base && p < g_base + g_len)
		*p = (char)(*p + i);
}

/* Writes nothing. */
static void	look(unsigned int i, char *p)
{
	logged(i, p);
}

static void	test(const char *label, const char *text,
		void (*f)(unsigned int, char*))
{
	char	*s;
	size_t	k;

	g_len = strlen(text);
	s = malloc(g_len + 1);
	if (s == NULL)
		exit(1);
	memcpy(s, text, g_len + 1);
	g_base = s;
	g_calls = 0;
	ft_striteri(s, f);
	printf("%s\t\"", label);
	k = 0;
	while (k < g_len && s[k])
		put_esc_char((unsigned char)s[k++]);
	printf("\"");
	if (g_calls == 0)
		printf(", no call");
	else
		printf(", calls");
	k = 0;
	while (k < g_calls && k < LOG_MAX)
	{
		if (g_offset[k] < 0)
			printf(" %u@elsewhere", g_index[k]);
		else
		{
			printf(" %u@s+%ld=", g_index[k], g_offset[k]);
			put_esc_char(g_char[k]);
		}
		k++;
	}
	if (g_calls > LOG_MAX)
		printf(" ... %zu calls", g_calls);
	printf("\n");
	free(s);
}

static size_t	g_next;
static int		g_wrong;

/* For the long row: notes a call that is not the next index, or not handed
 * that index's address; turns the letter upper case. */
static void	upper_in_order(unsigned int i, char *p)
{
	if (i != g_next || i >= 5000 || p != g_base + i)
		g_wrong = 1;
	else
		*p = (char)(*p - 32);
	g_next++;
}

/* s: 5000 bytes of 'a'..'z' over and over. */
static void	test_long(void)
{
	char	*s;
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
	g_base = s;
	g_next = 0;
	g_wrong = 0;
	ft_striteri(s, upper_in_order);
	i = 0;
	while (i < 5000 && s[i] == (char)('A' + i % 26))
		i++;
	printf("5000 letters, upper case\t");
	if (i < 5000)
		printf("byte %zu is not upper case", i);
	else
		printf("5000 upper-case letters");
	if (g_wrong)
		printf(", a call out of order or handed the wrong address");
	printf(", %zu calls\n", g_next);
	free(s);
}

int	main(void)
{
	test("\"aaaa\", *p + i", "aaaa", plus_index);
	test("\"abc\", *p + i", "abc", plus_index);
	test("\"\", *p + i", "", plus_index);
	test("\"a<TAB>b<LF>\", nothing", "a\tb\n", look);
	test("0xe9 0xf0 0x80, *p + i", "\xe9\xf0\x80", plus_index);
	test_long();
	return (0);
}
