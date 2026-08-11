#include <stdio.h>
#include <string.h>

char	*ft_strncat(char *dest, char *src, unsigned int nb);

/* Prints "<label>\t<result>|<dest>|<ret==dest>". */
static void	test(char *label, char *dest, char *src, unsigned int nb)
{
	char	*ret;

	ret = ft_strncat(dest, src, nb);
	printf("%s\t%s|%s|%d\n", label, ret, dest, ret == dest);
}

int	main(void)
{
	char	d1[50] = "abc";
	char	d2[50] = "Hello ";
	char	d3[50] = "Hello ";
	char	d4[50] = "Hello ";
	char	d5[50];
	char	d6[50] = "Hello ";
	char	d7[50] = "";
	char	d8[50] = "Hello ";

	test("\"abc\" + \"\" (nb=5, empty src)", d1, "", 5);
	test("\"Hello \" + \"World!\" (nb=0)", d2, "World!", 0);
	test("\"Hello \" + \"World!\" (nb=3, truncated)", d3, "World!", 3);
	test("\"Hello \" + \"World!\" (nb=100, all fits)", d4, "World!", 100);
	memset(d5, 'X', sizeof(d5));
	d5[0] = 'H';
	d5[1] = 'i';
	d5[2] = '\0';
	test("append nb=3 past old '\\0' (X-filled)", d5, "World", 3);
	test("\"Hello \" + \"World!\" (nb=6, nb==strlen)", d6, "World!", 6);
	test("\"\" + \"abc\" (nb=3, empty dest)", d7, "abc", 3);
	test("\"Hello \" + \"Hi\" (nb=100, short src)", d8, "Hi", 100);
	return (0);
}
