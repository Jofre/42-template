#include <stdio.h>
#include <unistd.h>

void	ft_putstr_non_printable(char *str);

/* ft_putstr_non_printable writes with write(); setbuf(NULL) keeps the printf
 * labels ordered with it. Prints "<label>\t<escaped output>". */
static void	test(char *label, char *s)
{
	printf("%s\t", label);
	ft_putstr_non_printable(s);
	printf("\n");
}

int	main(void)
{
	setbuf(stdout, NULL);
	test("\" ~\" (all printable)", " ~");
	test("\"a\\b ~\" (backslash IS printable)", "a\\b ~");
	test("contains newline (0x0a)", "Coucou\ntu vas bien ?");
	/* The EN subject's own transcript, printed verbatim there as
	 * Hello\nHow are you? -> Hello\0aHow are you?. Same shape as the line
	 * above, which is the ES/FR edition's; an evaluator types whichever they
	 * were given, and neither should meet a case the fixture never ran. */
	test("subject transcript (en)", "Hello\nHow are you?");
	test("contains tab (0x09)", "Tab\tEnd");
	test("0x07 and 0xff mixed in", "Coucou\x07tu vas\xff bien ?");
	test("0x7f / DEL", "\x7f");
	test("0x1f then 0x05", "\x1f\x05");
	test("high bytes 0x80, 0xff", "\x80\xff");
	return (0);
}
