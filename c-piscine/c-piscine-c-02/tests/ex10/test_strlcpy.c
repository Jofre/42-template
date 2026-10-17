#include <stdio.h>
#include <string.h>

/* The table for ft_strlcpy (man 3bsd strlcpy, where the subject sends you).
 * Prints "<label>\tret=<n> in size: <bytes> | from size: <bytes>":
 *   in size    the destination's first `size` bytes up to the first NUL,
 *              that NUL shown as \x00; "(no NUL)" after them when none of
 *              the `size` bytes is one, and "(none)" when size is 0;
 *   from size  the three bytes at size and after, which the call may not
 *              write: every destination starts filled with 'X'.
 * The bytes between the terminator and size are not shown: the man page
 * says nothing of them. Values are in diff_output.sh's escaped notation
 * (escaped_values): \xHH for a byte outside printable ASCII, \\ for a
 * backslash, \n and \t for a line break and a tab. */
unsigned int	ft_strlcpy(char *dest, char *src, unsigned int size);

static void	put_esc(const unsigned char *p, unsigned int n)
{
	unsigned int	i;

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

/* The first `size` bytes of dest, up to and with the first NUL. */
static void	put_in_size(const unsigned char *dest, unsigned int size)
{
	const unsigned char	*nul;

	if (size == 0)
	{
		printf("(none)");
		return ;
	}
	nul = memchr(dest, '\0', size);
	if (nul != NULL)
		put_esc(dest, (unsigned int)(nul - dest) + 1);
	else
	{
		put_esc(dest, size);
		printf(" (no NUL)");
	}
}

static void	test(char *label, char *src, unsigned int size)
{
	char			dest[64];
	unsigned int	ret;

	memset(dest, 'X', sizeof(dest));
	ret = ft_strlcpy(dest, src, size);
	printf("%s\tret=%u in size: ", label, ret);
	put_in_size((unsigned char *)dest, size);
	printf(" | from size: ");
	put_esc((unsigned char *)dest + size, 3);
	printf("\n");
}

int	main(void)
{
	test("\"\" size 5 (empty src)", "", 5);
	test("\"Hi\" size 50 (fits)", "Hi", 50);
	test("\"Hello\" size 6 (fits exactly)", "Hello", 6);
	test("\"Hello\" size 5 (truncated by 1)", "Hello", 5);
	test("\"Hello\" size 1 (only the \\0)", "Hello", 1);
	test("\"Hello\" size 0 (writes nothing)", "Hello", 0);
	test("\"Hello World\" size 6 (big truncate)", "Hello World", 6);
	return (0);
}
