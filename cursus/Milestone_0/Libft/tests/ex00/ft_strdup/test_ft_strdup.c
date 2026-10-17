#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

/* The table for ft_strdup (man 3 strdup, where Libft, p.8 sends you).
 * Prints "<label>\t<copy>": the returned string up to and with its NUL
 * (shown as \x00), read no further than one byte past the length of s;
 * "(no NUL)" after those bytes when none of them is a NUL, and "NULL" for a
 * NULL result. Every copy is freed with free(3), as the man page says it
 * can be, before its row's newline, so a crash in free() marks its own row.
 * Values are in diff_output.sh's escaped notation (escaped_values):
 * \xHH for a byte outside printable ASCII, \t for a tab, \\ for a
 * backslash. */
char	*ft_strdup(const char *s);

static void	put_esc(const unsigned char *p, size_t n)
{
	size_t	i;

	i = 0;
	while (i < n)
	{
		if (p[i] == '\\')
			printf("\\\\");
		else if (p[i] == '\n')
			printf("\\n");
		else if (p[i] == '\t')
			printf("\\t");
		else if (p[i] < 0x20 || p[i] > 0x7e)
			printf("\\x%02x", p[i]);
		else
			putchar(p[i]);
		i++;
	}
}

/* s holds len bytes and its terminator. */
static void	test(const char *label, const char *s, size_t len)
{
	char	*d;
	char	*nul;

	d = ft_strdup(s);
	printf("%s\t", label);
	if (d == NULL)
		printf("NULL");
	else if (d == s)
		printf("the same pointer as s");
	else
	{
		nul = memchr(d, '\0', len + 1);
		if (nul != NULL)
			put_esc((unsigned char *)d, (size_t)(nul - d) + 1);
		else
		{
			put_esc((unsigned char *)d, len + 1);
			printf(" (no NUL)");
		}
		free(d);
	}
	printf("\n");
}

/* The copy is a block of its own: written into, s does not change. */
static void	test_independent(void)
{
	char	s[] = "modifiable";
	char	*d;

	d = ft_strdup(s);
	printf("a separate copy, written into\t");
	if (d == NULL)
		printf("NULL");
	else if (d == s)
		printf("the same pointer as s");
	else
	{
		d[0] = 'X';
		printf("copy: %.10s, s: %s", d, s);
		free(d);
	}
	printf("\n");
}

/* 5000 bytes cycling through 1..255, then the terminator, by construction;
 * the copy is counted against that pattern, and the byte after the bytes
 * that match is shown. */
static void	test_long(void)
{
	static char	s[5001];
	char		*d;
	size_t		k;

	k = 0;
	while (k < 5000)
	{
		s[k] = (char)(1 + k % 255);
		k++;
	}
	s[5000] = '\0';
	d = ft_strdup(s);
	printf("5000 bytes, every value 1..255 among them\t");
	if (d == NULL || d == s)
	{
		printf("%s\n", d == NULL ? "NULL" : "the same pointer as s");
		return ;
	}
	k = 0;
	while (k < 5000 && d[k] == (char)(1 + k % 255))
		k++;
	printf("%zu bytes of s then ", k);
	put_esc((unsigned char *)d + k, 1);
	free(d);
	printf("\n");
}

int	main(void)
{
	const char	high[] = {'c', 'a', 'f', (char)0xc3, (char)0xa9, (char)0xff,
		'\0'};

	test("\"\" (empty)", "", 0);
	test("\"a\"", "a", 1);
	test("\"42 Barcelona\"", "42 Barcelona", 12);
	test("spaces and a tab kept", "two  gaps\tand a tab", 19);
	test("\"caf\" then bytes 0xc3 0xa9 0xff", high, 6);
	test_independent();
	test_long();
	return (0);
}
