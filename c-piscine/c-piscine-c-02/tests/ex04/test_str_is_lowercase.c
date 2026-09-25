#include <stdio.h>

int	ft_str_is_lowercase(char *str);

static void	test(char *label, char *s)
{
	printf("%s\t%d\n", label, ft_str_is_lowercase(s));
}

int	main(void)
{
	test("\"\" (empty -> 1)", "");
	test("\"hello\" (lowercase)", "hello");
	test("\"abcxyz\" (lowercase)", "abcxyz");
	test("\"Hello\" (has uppercase)", "Hello");
	test("\"abc1\" (has digit)", "abc1");
	test("\"abc def\" (has space)", "abc def");
	test("\"`\" (0x60, just before 'a')", "`");
	test("\"{\" (0x7B, just after 'z')", "{");
	return (0);
}
