#include <stdio.h>

char	*ft_strupcase(char *str);

/* ft_strupcase modifies in place, so each case needs its own writable array.
 * Prints "<label>\t<result>". */
static void	test(char *label, char *s)
{
	printf("%s\t%s\n", label, ft_strupcase(s));
}

int	main(void)
{
	char	empty[] = "";
	char	mixed[] = "ABZabz";
	char	sentence[] = "Hello World 123!";
	char	symbols[] = "{|}~`@";
	char	rp[] = "abc";
	char	*ret;

	test("\"\" (empty)", empty);
	test("\"ABZabz\" (only letters change)", mixed);
	test("\"Hello World 123!\" (digits/space kept)", sentence);
	test("\"{|}~`@\" (non-letters unchanged)", symbols);
	ret = ft_strupcase(rp);
	printf("returns its argument\tret==arg:%d\n", ret == rp);
	return (0);
}
