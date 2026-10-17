#include <stddef.h>
#include <stdio.h>
#include <string.h>

/* The table for ft_strlcpy (man 3bsd strlcpy, where Libft, p.8 sends you).
 * Prints "<label>\tret=<n> in size: <bytes> | from size: <bytes>":
 *   in size    the destination's first `size` bytes up to the first NUL,
 *              that NUL shown as \x00; "(no NUL)" after them when none of
 *              the `size` bytes is one, and "(none)" when size is 0;
 *   from size  the three bytes at size and after, which the call may not
 *              write: every destination starts filled with 'X'.
 * The bytes between the terminator and size are not shown: the man page
 * says nothing of them. Values are in diff_output.sh's escaped notation
 * (escaped_values): \xHH for a byte outside printable ASCII, \\ for a
 * backslash. */
size_t	ft_strlcpy(char *dst, const char *src, size_t size);

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

/* The first `size` bytes of dst, up to and with the first NUL. */
static void	put_in_size(const unsigned char *dst, size_t size)
{
	const unsigned char	*nul;

	if (size == 0)
	{
		printf("(none)");
		return ;
	}
	nul = memchr(dst, '\0', size);
	if (nul != NULL)
		put_esc(dst, (size_t)(nul - dst) + 1);
	else
	{
		put_esc(dst, size);
		printf(" (no NUL)");
	}
}

static void	test(const char *label, const char *src, size_t size)
{
	char	dst[64];
	size_t	ret;

	memset(dst, 'X', sizeof(dst));
	ret = ft_strlcpy(dst, src, size);
	printf("%s\tret=%zu in size: ", label, ret);
	put_in_size((unsigned char *)dst, size);
	printf(" | from size: ");
	put_esc((unsigned char *)dst + size, 3);
	printf("\n");
}

/* A 5000-byte src, 'a'..'z' over and over, into a 4100-byte destination with
 * size 4097: how much of the copy matches src is counted against the
 * pattern src was built from, and the byte after the match is shown. */
static void	test_long(void)
{
	static char	src[5001];
	static char	dst[4100];
	size_t		ret;
	size_t		k;

	k = 0;
	while (k < 5000)
	{
		src[k] = (char)('a' + k % 26);
		k++;
	}
	src[5000] = '\0';
	memset(dst, 'X', sizeof(dst));
	ret = ft_strlcpy(dst, src, 4097);
	k = 0;
	while (k < 4097 && dst[k] == (char)('a' + k % 26))
		k++;
	printf("5000-byte src, size 4097\tret=%zu in size: %zu bytes of src then ",
		ret, k);
	if (k < 4097)
		put_esc((unsigned char *)dst + k, 1);
	else
		printf("(no NUL)");
	printf(" | from size: ");
	put_esc((unsigned char *)dst + 4097, 3);
	printf("\n");
}

int	main(void)
{
	const char	hi[] = {(char)0xe9, 't', (char)0xe9, '\0'};

	test("\"\" size 5 (empty src)", "", 5);
	test("\"Hi\" size 50 (fits)", "Hi", 50);
	test("\"Hello\" size 6 (fits exactly)", "Hello", 6);
	test("\"Hello\" size 5 (one byte short)", "Hello", 5);
	test("\"Hello\" size 1 (room for the NUL alone)", "Hello", 1);
	test("\"Hello\" size 0 (no room at all)", "Hello", 0);
	test("\"Hello World\" size 6 (cut short)", "Hello World", 6);
	test("bytes 0xe9 't' 0xe9, size 10 (fits)", hi, 10);
	test("bytes 0xe9 't' 0xe9, size 3 (cut short)", hi, 3);
	test_long();
	return (0);
}
