#include <stdio.h>

unsigned int	ft_strlcat(char *dest, char *src, unsigned int size);

/* Prints "<label>\t<return value>|<dest after>". */
static void	test(char *label, char *dest, char *src, unsigned int size)
{
	unsigned int	ret;

	ret = ft_strlcat(dest, src, size);
	printf("%s\t%u|%s\n", label, ret, dest);
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
	return (0);
}
