#include <stdio.h>

int	ft_str_is_uppercase(char *str);

static void	test(char *label, char *s)
{
	printf("%s\t%d\n", label, ft_str_is_uppercase(s));
}

int	main(void)
{
	test("\"\" (empty -> 1)", "");
	test("\"HELLO\" (uppercase)", "HELLO");
	test("\"ABCXYZ\" (uppercase)", "ABCXYZ");
	test("\"Hello\" (has lowercase)", "Hello");
	test("\"ABC1\" (has digit)", "ABC1");
	test("\"ABC DEF\" (has space)", "ABC DEF");
	test("\"@\" (0x40, just before 'A')", "@");
	test("\"[\" (0x5B, just after 'Z')", "[");
	return (0);
}
