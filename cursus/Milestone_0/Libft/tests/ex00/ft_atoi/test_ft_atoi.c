#include <stdio.h>
#include <string.h>

/* The table for ft_atoi (man 3 atoi, where Libft, p.8 sends you: "The
 * behavior is the same as strtol(nptr, NULL, 10)", and man 3 strtol says
 * the string "may begin with an arbitrary amount of white space (as
 * determined by isspace(3)) followed by a single optional '+' or '-' sign").
 * Prints "<label>\t<value>". Every input's value fits in an int: what a
 * number that does not fit gives is not in this table. Rows run from the
 * simplest to the hardest, the long ones last. */
int	ft_atoi(const char *nptr);

static void	test(const char *label, const char *s)
{
	printf("%s\t%d\n", label, ft_atoi(s));
}

/* 5000 copies of `fill`, then `tail`: built here, so the value is known by
 * construction. */
static void	test_long(const char *label, char fill, const char *tail)
{
	static char	s[5010];

	memset(s, fill, 5000);
	memcpy(s + 5000, tail, strlen(tail) + 1);
	test(label, s);
}

int	main(void)
{
	test("\"42\"", "42");
	test("\"0\"", "0");
	test("\"-0\"", "-0");
	test("\"000123\" (leading zeros)", "000123");
	test("\"+42\"", "+42");
	test("\"-42\"", "-42");
	test("space, tab, LF, VT, FF, CR, then \"-123\"", " \t\n\v\f\r-123");
	test("\"   +1\"", "   +1");
	test("\"12-3\" (stops at the minus)", "12-3");
	test("\"  -0042abc\"", "  -0042abc");
	test("\"\" (empty)", "");
	test("\"   \" (only spaces)", "   ");
	test("\"abc\"", "abc");
	test("\"+\" (a sign, no digit)", "+");
	test("\"-\" (a sign, no digit)", "-");
	test("\"+-1\" (two signs)", "+-1");
	test("\"-+1\" (two signs)", "-+1");
	test("\"--1\" (two signs)", "--1");
	test("\"++1\" (two signs)", "++1");
	test("\"- 1\" (a space after the sign)", "- 1");
	test("\"+ 1\" (a space after the sign)", "+ 1");
	test("byte 0x80, space, \"1\"", "\x80 1");
	test("byte 0xa0, then \"42\"", "\xa0" "42");
	test("byte 0x1c, then \"42\"", "\x1c" "42");
	test("\"2147483647\" (INT_MAX)", "2147483647");
	test("\"-2147483648\" (INT_MIN)", "-2147483648");
	test_long("5000 spaces, then \"-7\"", ' ', "-7");
	test_long("5000 '0', then \"42\"", '0', "42");
	return (0);
}
