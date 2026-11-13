#include <stddef.h>
#include <stdio.h>
#include <string.h>

/* The table for ft_strrchr (man 3 strrchr, where Libft, p.8 sends you).
 * Prints "<label>\t<where>", where is "s+N" for a pointer N bytes into the
 * string passed, "NULL", or "outside s" for any other pointer. Every c here
 * is a byte value, 0..255: what a c outside that range means is not in this
 * table. */
char	*ft_strrchr(const char *s, int c);

static void	test(const char *label, const char *s, size_t len, int c)
{
	char	*p;

	p = ft_strrchr(s, c);
	if (p == NULL)
		printf("%s\tNULL\n", label);
	else if (p >= s && p <= s + len)
		printf("%s\ts+%zu\n", label, (size_t)(p - s));
	else
		printf("%s\toutside s\n", label);
}

/* 5000 bytes of 'a' with a '#' at the positions given (-1: none), then the
 * terminator: where each '#' and the terminator are is known by
 * construction. */
static void	test_long(const char *label, int at1, int at2, int c)
{
	static char	s[5001];

	memset(s, 'a', 5000);
	s[5000] = '\0';
	if (at1 >= 0)
		s[at1] = '#';
	if (at2 >= 0)
		s[at2] = '#';
	test(label, s, 5000, c);
}

int	main(void)
{
	const char	*h = "Hello, 42!";
	const char	hi[] = {'a', (char)0xe9, 'b', (char)0xe9, '\0'};
	const char	hiz[] = {(char)0xe9, 'z', '\0'};
	const char	x80[] = {(char)0x80, (char)0x80, '\0'};

	test("'H' in \"Hello, 42!\" (first byte)", h, 10, 'H');
	test("'l' in \"Hello, 42!\" (two of them)", h, 10, 'l');
	test("'!' in \"Hello, 42!\" (last byte)", h, 10, '!');
	test("'z' in \"Hello, 42!\" (absent)", h, 10, 'z');
	test("NUL (c = 0) in \"Hello, 42!\"", h, 10, '\0');
	test("'a' in \"\"", "", 0, 'a');
	test("NUL (c = 0) in \"\"", "", 0, '\0');
	test("c = 233 in 'a' 0xe9 'b' 0xe9", hi, 4, 233);
	test("'z' in 0xe9 'z'", hiz, 2, 'z');
	test("c = 128 in 0x80 0x80", x80, 2, 128);
	test_long("'#' in 5000 bytes, '#' at 0 and 4999", 0, 4999, '#');
	test_long("'#' in 5000 bytes, '#' only at 0", 0, -1, '#');
	test_long("NUL (c = 0) in 5000 bytes", -1, -1, '\0');
	return (0);
}
