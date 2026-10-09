#include <stdio.h>

unsigned int	ft_strlcat(char *dest, char *src, unsigned int size);

/* Prints "<label>\tret=<return value> dest=\"<dest after>\"": each field
 * names itself, so a red row says which of the two is wrong. */
static void	test(char *label, char *dest, char *src, unsigned int size)
{
	unsigned int	ret;

	ret = ft_strlcat(dest, src, size);
	printf("%s\tret=%u dest=\"%s\"\n", label, ret, dest);
}

/* Shows the first n bytes of a buffer, each NUL as "\x00" (the notation of
 * diff_output.sh's escaped values: its call says escaped_values = True), so
 * where the terminator went -- and what lies past it -- is visible. Bounded
 * by n, so a result left unterminated is never read past its array. */
static void	show(char *d, int n)
{
	int	i;

	i = 0;
	while (i < n)
	{
		if (d[i] == '\0')
			printf("\\x00");
		else
			printf("%c", d[i]);
		i++;
	}
	printf("\n");
}

/* The same call on a buffer filled with 'X' past "Hi" and its terminator
 * (finding 057). In the zero-initialised buffers above, the byte where a
 * terminator belongs is already 0 whether or not ft_strlcat writes one; here
 * a missing one shows as an X after the text. showlen shows up to the
 * terminator and, past it, only bytes at or beyond size: man strlcat bounds
 * what may be written by size, and says nothing of the bytes between the
 * terminator and size, so they are not shown. */
static void	test_x(char *label, char *src, unsigned int size, int showlen)
{
	char			dest[50];
	unsigned int	ret;
	int				i;

	i = 0;
	while (i < 50)
		dest[i++] = 'X';
	dest[0] = 'H';
	dest[1] = 'i';
	dest[2] = '\0';
	ret = ft_strlcat(dest, src, size);
	printf("%s\tret=%u buf=", label, ret);
	show(dest, showlen);
}

/* The same call, dest shown in the notation of diff_output.sh's escaped
 * values, for a src holding bytes above 0x7f (finding 039): a byte of src
 * read as a signed char is negative there, and a length counted while the
 * byte is above 0 stops at it. The text is right either way when the copy
 * runs to the terminator; the return value is what shows the count. */
static void	test_hi(char *label, char *dest, char *src, unsigned int size)
{
	unsigned int	ret;
	int				i;

	ret = ft_strlcat(dest, src, size);
	printf("%s\tret=%u dest=\"", label, ret);
	i = 0;
	while (dest[i] != '\0')
	{
		if ((unsigned char)dest[i] < 0x20 || (unsigned char)dest[i] > 0x7e)
			printf("\\x%02x", (unsigned char)dest[i]);
		else
			printf("%c", dest[i]);
		i++;
	}
	printf("\"\n");
}

int	main(void)
{
	char	d1[50] = "Hello ";
	char	d2[50] = "Hello ";
	char	d3[50] = "";
	char	d4[50] = "Hello ";
	char	d5[50] = "Hello ";
	char	d6[50] = "Hello ";
	char	d7[50] = "Hello ";
	char	d8[50] = "Hello ";
	char	d9[50] = "Hello ";
	char	d10[50] = "Hello ";
	char	d11[50] = "";
	char	d12[50] = "";
	char	d13[50] = "Hello ";

	test("empty src (size 50)", d1, "", 50);
	test("into empty dest (size 10)", d3, "Hi", 10);
	test("fits fully (size 50)", d4, "World!", 50);
	test("truncated (size 10)", d2, "World!", 10);
	test("size 0", d5, "World!", 0);
	test("size 1", d6, "World!", 1);
	test("size == dest length (6)", d7, "World!", 6);
	test("size < dest length (3)", d8, "World!", 3);
	test("size == dest len + 1 (7)", d9, "World!", 7);
	test("size == dest len + 2 (8)", d10, "World!", 8);
	test("trunc into empty dest (size 4)", d11, "World!", 4);
	test("both empty (size 50)", d12, "", 50);
	test_hi("bytes above 0x7f in src (size 50)", d13, "\xe9t\xe9", 50);
	test_x("X-filled buffer, truncated (size 5)", "World", 5, 8);
	test_x("X-filled buffer, fits (size 20)", "World", 20, 8);
	return (0);
}
