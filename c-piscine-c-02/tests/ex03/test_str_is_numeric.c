#include <stdio.h>

int	ft_str_is_numeric(char *str);

static void	test(char *label, char *s)
{
	printf("%s\t%d\n", label, ft_str_is_numeric(s));
}

int	main(void)
{
	test("\"\" (empty -> 1)", "");
	test("\"12345\" (digits)", "12345");
	test("\"0987654321\" (digits)", "0987654321");
	test("\"123a45\" (has a letter)", "123a45");
	test("\"12 34\" (has space)", "12 34");
	test("\"-5\" (has a sign)", "-5");
	test("\"/\" (0x2F, just before '0')", "/");
	test("\":\" (0x3A, just after '9')", ":");
	return (0);
}
