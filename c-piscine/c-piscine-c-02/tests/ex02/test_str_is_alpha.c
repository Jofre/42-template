#include <stdio.h>

int	ft_str_is_alpha(char *str);

static void	test(char *label, char *s)
{
	printf("%s\t%d\n", label, ft_str_is_alpha(s));
}

int	main(void)
{
	test("\"\" (empty -> 1)", "");
	test("\"Hello\" (letters)", "Hello");
	test("\"abcXYZ\" (mixed case)", "abcXYZ");
	test("\"Hello123\" (has digits)", "Hello123");
	test("\"Hello World\" (has space)", "Hello World");
	test("\"@\" (0x40, just before 'A')", "@");
	test("\"[\" (0x5B, just after 'Z')", "[");
	test("\"`\" (0x60, just before 'a')", "`");
	test("\"{\" (0x7B, just after 'z')", "{");
	return (0);
}
