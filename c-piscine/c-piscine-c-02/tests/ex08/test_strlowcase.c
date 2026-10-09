#include <stdio.h>

char	*ft_strlowcase(char *str);

/* ft_strlowcase modifies in place. Prints "<label>\t<result>". */
static void	test(char *label, char *s)
{
	printf("%s\t%s\n", label, ft_strlowcase(s));
}

int	main(void)
{
	char	empty[] = "";
	char	mixed[] = "abzABZ";
	char	sentence[] = "Hello World 123!";
	char	symbols[] = "@[\\]^_`";
	char	rp[] = "ABC";
	char	*ret;

	test("\"\" (empty)", empty);
	test("\"abzABZ\" (only letters change)", mixed);
	test("\"Hello World 123!\" (digits/space kept)", sentence);
	test("\"@[\\]^_`\" (non-letters unchanged)", symbols);
	ret = ft_strlowcase(rp);
	printf("returns its argument\tret==arg:%d\n", ret == rp);
	return (0);
}
