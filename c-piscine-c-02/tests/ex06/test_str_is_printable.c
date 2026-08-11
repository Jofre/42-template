#include <stdio.h>

int	ft_str_is_printable(char *str);

static void	test(char *label, char *s)
{
	printf("%s\t%d\n", label, ft_str_is_printable(s));
}

int	main(void)
{
	test("\"\" (empty -> 1)", "");
	test("\" ~\" (space..tilde edges)", " ~");
	test("\"Hello ~!\" (printable)", "Hello ~!");
	test("contains newline", "Hello\nWorld");
	test("contains tab", "ok\there");
	test("0x1F (just below space)", "\x1f");
	test("0x7F / DEL (just above '~')", "\x7f");
	test("0x80 (high byte, > 127)", "\x80");
	test("0xFF (high byte, > 127)", "\xff");
	return (0);
}
