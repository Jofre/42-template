#include <stddef.h>
#include <stdio.h>

/* The table for ft_strlen (man 3 strlen, where Libft, p.8 sends you).
 * Prints "<label>\t<length>"; diff_output.sh (--labeled) puts the label in a
 * column of its own. Rows run from the simplest to the hardest, the long one
 * last. */
size_t	ft_strlen(const char *s);

static void	test(const char *label, const char *s)
{
	printf("%s\t%zu\n", label, ft_strlen(s));
}

/* 5000 bytes, none of them 0, then the terminator: the length is 5000 by
 * construction. The bytes cycle through 1..255, so a byte above 0x7f comes
 * up every 255 bytes along the way. */
static void	test_long(void)
{
	static char	s[5001];
	int			i;

	i = 0;
	while (i < 5000)
	{
		s[i] = (char)(1 + i % 255);
		i++;
	}
	s[5000] = '\0';
	test("5000 bytes, every value 1..255 among them", s);
}

int	main(void)
{
	const char	stop[] = {'a', 'b', '\0', 'c', 'd', '\0'};
	const char	high[] = {'c', 'a', 'f', (char)0xc3, (char)0xa9, '\0'};
	const char	ff[] = {(char)0xff, '\0'};
	const char	eighty[] = {(char)0x80, (char)0x80, (char)0x80, '\0'};

	test("\"\" (empty)", "");
	test("\"a\"", "a");
	test("\"Hello\"", "Hello");
	test("spaces and a tab: \"a b<TAB>c\"", "a b\tc");
	test("\"ab\", a NUL, then \"cd\"", stop);
	test("\"caf\" then bytes 0xc3 0xa9 (UTF-8)", high);
	test("one byte 0xff", ff);
	test("three bytes 0x80", eighty);
	test_long();
	return (0);
}
