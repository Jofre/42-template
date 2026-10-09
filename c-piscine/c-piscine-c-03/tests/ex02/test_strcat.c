#include <stdio.h>
#include <string.h>

char	*ft_strcat(char *dest, char *src);

/* Prints "<label>\tret=\"<string returned>\" dest=\"<dest after>\"
 * ret==dest:<1 or 0>": each field names itself, so a red row says which
 * of the three is wrong. */
static void	test(char *label, char *dest, char *src)
{
	char	*ret;

	ret = ft_strcat(dest, src);
	printf("%s\tret=\"%s\" dest=\"%s\" ret==dest:%d\n", label, ret, dest,
		ret == dest);
}

int	main(void)
{
	char	d1[50] = "abc";
	char	d2[50] = "";
	char	d3[50] = "Hello ";
	char	d4[50] = "ab";
	char	d5[50];
	char	d6[50] = "";
	char	d7[50] = "hi";
	char	d8[50] = "ab";

	test("\"abc\" + \"\" (empty src)", d1, "");
	test("\"\" + \"abc\" (empty dest)", d2, "abc");
	test("\"Hello \" + \"World!\"", d3, "World!");
	test("\"ab\" + \"cde\"", d4, "cde");
	memset(d5, 'X', sizeof(d5));
	d5[0] = 'H';
	d5[1] = 'i';
	d5[2] = '\0';
	test("append past old '\\0' (buffer was X-filled)", d5, "ya");
	test("\"\" + \"\" (both empty)", d6, "");
	test("\"hi\" + high-byte src \\xC3\\xA9\\x80", d7, "\xC3\xA9\x80");
	test("long src onto short dest", d8,
		"0123456789012345678901234567890123456789");
	return (0);
}
