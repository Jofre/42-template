#include <stdint.h>
#include <stdio.h>
#include <string.h>

char	*ft_strncat(char *dest, char *src, unsigned int nb);

/* Prints "<label>\tret=<what was returned> dest=\"<dest after>\"
 * ret==dest:<1 or 0>": each field names itself, so a red row says which
 * of the three is wrong. Every dest below is 50 bytes, and nothing is read
 * past it: dest is shown up to its 50th byte, and ret, when it points into
 * dest, up to the same end, so a result left unterminated (the X-filled
 * row) shows what the array holds and no more. A ret anywhere else is not
 * read: the row says what it is (NULL, src, or a pointer outside dest). */
static void	test(char *label, char *dest, char *src, unsigned int nb)
{
	char		*ret;
	uintptr_t	k;

	ret = ft_strncat(dest, src, nb);
	k = (uintptr_t)ret - (uintptr_t)dest;
	printf("%s\tret=", label);
	if (ret == NULL)
		printf("NULL");
	else if (k < 50)
		printf("\"%.*s\"", (int)(50 - k), ret);
	else if (ret == src)
		printf("src");
	else
		printf("(a pointer outside dest)");
	printf(" dest=\"%.*s\" ret==dest:%d\n", 50, dest, ret == dest);
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
