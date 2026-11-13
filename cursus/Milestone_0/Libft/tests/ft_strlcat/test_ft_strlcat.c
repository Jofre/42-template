#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include "notation.h"

/* The table for ft_strlcat (man 3bsd strlcat, where Libft, p.8 sends you).
 * Prints "<label>\tret=<n> dst: <bytes> | from size: <bytes>":
 *   dst        the buffer up to its first NUL, that NUL shown as \x00
 *              ("(no NUL)" when the whole buffer holds none);
 *   from size  the three bytes at index size and after, which the call may
 *              not write.
 * Every buffer is filled with 'X' before dst's own string and terminator
 * are put in it, so no byte past dst's terminator is a NUL the call did not
 * write. Values are in diff_output.sh's escaped notation (escaped_values):
 * \xHH for a byte outside printable ASCII, \\ for a backslash. */
size_t	ft_strlcat(char *dst, const char *src, size_t size);

/* buf[0..cap) filled with 'X', then dst's dlen bytes and a terminator. */
static void	setup(char *buf, size_t cap, const char *dst, size_t dlen)
{
	memset(buf, 'X', cap);
	memcpy(buf, dst, dlen);
	buf[dlen] = '\0';
}

static void	test(const char *label, const char *dst, size_t dlen,
		const char *src, size_t size)
{
	char	buf[64];
	size_t	ret;
	char	*nul;

	setup(buf, sizeof(buf), dst, dlen);
	ret = ft_strlcat(buf, src, size);
	printf("%s\tret=%zu dst: ", label, ret);
	nul = memchr(buf, '\0', sizeof(buf));
	if (nul != NULL)
		nt_put(buf, (size_t)(nul - buf) + 1);
	else
	{
		nt_put(buf, sizeof(buf));
		printf(" (no NUL)");
	}
	printf(" | from size: ");
	nt_put(buf + size, 3);
	printf("\n");
}

/* Capacity: dst is dlen bytes of 'A'..'Z' over and over, src slen bytes of
 * 'a'..'z', both by construction, in a 9104-byte buffer. What the buffer
 * holds after the call is counted against those two patterns: how many of
 * dst's bytes are still there, how many of src's follow them, and the byte
 * after that. */
static void	test_long(const char *label, size_t dlen, size_t slen,
		size_t size)
{
	static char	buf[9104];
	static char	src[5001];
	size_t		ret;
	size_t		k1;
	size_t		k2;

	memset(buf, 'X', sizeof(buf));
	k1 = 0;
	while (k1 < dlen)
	{
		buf[k1] = (char)('A' + k1 % 26);
		k1++;
	}
	buf[dlen] = '\0';
	k2 = 0;
	while (k2 < slen)
	{
		src[k2] = (char)('a' + k2 % 26);
		k2++;
	}
	src[slen] = '\0';
	ret = ft_strlcat(buf, src, size);
	k1 = 0;
	while (k1 < dlen && buf[k1] == (char)('A' + k1 % 26))
		k1++;
	printf("%s\tret=%zu dst: %zu bytes of dst, ", label, ret, k1);
	k2 = 0;
	while (k1 == dlen && k2 < slen && dlen + k2 < sizeof(buf)
		&& buf[dlen + k2] == (char)('a' + k2 % 26))
		k2++;
	printf("%zu of src, then ", k2);
	if (k1 + k2 < sizeof(buf))
		nt_put(buf + k1 + k2, 1);
	else
		printf("(end of buffer)");
	printf(" | from size: ");
	nt_put(buf + size, 3);
	printf("\n");
}

int	main(void)
{
	const char	hi[] = {(char)0xe9, 't', (char)0xe9, '\0'};
	const char	hidst[] = {(char)0xe9, (char)0xe9, '\0'};

	test("empty src (size 50)", "Hello ", 6, "", 50);
	test("into empty dst (size 10)", "", 0, "Hi", 10);
	test("fits fully (size 50)", "Hello ", 6, "World!", 50);
	test("cut short (size 10)", "Hello ", 6, "World!", 10);
	test("size 0", "Hello ", 6, "World!", 0);
	test("size 1", "Hello ", 6, "World!", 1);
	test("size < dst length (2)", "Hello ", 6, "World!", 2);
	test("size == dst length (6)", "Hello ", 6, "World!", 6);
	test("size == dst length + 1 (7)", "Hello ", 6, "World!", 7);
	test("size == dst length + 2 (8)", "Hello ", 6, "World!", 8);
	test("cut short into empty dst (size 4)", "", 0, "World!", 4);
	test("both empty (size 50)", "", 0, "", 50);
	test("src bytes 0xe9 't' 0xe9 (size 50)", "Hello ", 6, hi, 50);
	test("dst bytes 0xe9 0xe9, src \"ab\" (size 4)", hidst, 2, "ab", 4);
	test_long("dst 5000 bytes, src \"abc\" (size 4097)", 5000, 3, 4097);
	test_long("dst 4100 + src 5000 bytes (size 9101, fits)", 4100, 5000, 9101);
	test_long("dst 4100 + src 5000 bytes (size 6000, cut short)", 4100, 5000,
		6000);
	return (0);
}
