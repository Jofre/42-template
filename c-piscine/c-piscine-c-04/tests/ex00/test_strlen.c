#include <stdio.h>

int	ft_strlen(char *str);

/* Prints "<label>\t<length>"; tools/diff_output.sh (--labeled) puts <label> in
 * its own column. Cases ordered trivial -> conceptually harder. */
static void	test(char *label, char *s)
{
	printf("%s\t%d\n", label, ft_strlen(s));
}

/* A string of 5000 bytes, "abc...z" over and over: past every capacity a
 * function is usually given room for (16, 64, 256, 1024, 4096; finding 041),
 * so a length counted through room of a fixed size gets it wrong. The
 * subject bounds no string, so every reading agrees on this case. */
static void	test_long(void)
{
	static char	s[5001];
	int			i;

	i = 0;
	while (i < 5000)
	{
		s[i] = 'a' + i % 26;
		i++;
	}
	s[i] = '\0';
	test("long (5000 chars)", s);
}

int	main(void)
{
	test("\"\" (empty)", "");
	test("\"a\" (one char)", "a");
	test("\"Hello\"", "Hello");
	test("\"0\" (the digit zero)", "0");
	test("\"1234567890\"", "1234567890");
	test("\" \" (single space)", " ");
	test("\"a b c\" (spaces count)", "a b c");
	test("\"  leading and trailing  \"", "  leading and trailing  ");
	test("embedded tabs \"x\\ty\\tz\"", "x\ty\tz");
	test("long (40 chars)", "0123456789012345678901234567890123456789");
	test_long();
	test("UTF-8 word \"caf\" + bytes 0xc3 0xa9 (above 0x7f)", "caf\xC3\xA9");
	test("lone byte 0xff", "\xff");
	return (0);
}
