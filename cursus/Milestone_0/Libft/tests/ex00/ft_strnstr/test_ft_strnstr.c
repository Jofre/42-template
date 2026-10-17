#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* The table for ft_strnstr (man 3bsd strnstr, where Libft, p.8 sends you).
 * Prints "<label>\t<where>", where is "big+N" for a pointer N bytes into
 * big, "NULL", or "outside big" for any other pointer. len = SIZE_MAX is
 * the largest size_t, whatever its width. */
char	*ft_strnstr(const char *big, const char *little, size_t len);

static void	test(const char *label, const char *big, size_t blen,
		const char *little, size_t len)
{
	char	*p;

	p = ft_strnstr(big, little, len);
	if (p == NULL)
		printf("%s\tNULL\n", label);
	else if (p >= big && p <= big + blen)
		printf("%s\tbig+%zu\n", label, (size_t)(p - big));
	else
		printf("%s\toutside big\n", label);
}

/* big: 4999 bytes of 'a', then '#', then the terminator; little "a#". By
 * construction the only match starts at 4998 and ends at 4999, the last
 * byte of big. */
static void	test_long(const char *label, size_t len)
{
	static char	big[5001];

	memset(big, 'a', 4999);
	big[4999] = '#';
	big[5000] = '\0';
	test(label, big, 5000, "a#", len);
}

int	main(void)
{
	const char	*h = "Hello, 42 world";
	const char	hi[] = {'a', (char)0xe9, '\0'};
	const char	e9[] = {(char)0xe9, '\0'};

	test("\"42\" in \"Hello, 42 world\" (len 15)", h, 15, "42", 15);
	test("\"42\" (len 9: it ends on the last byte searched)", h, 15, "42", 9);
	test("\"42\" (len 8: len cuts it)", h, 15, "42", 8);
	test("\"world\" (len 15)", h, 15, "world", 15);
	test("\"world\" (len 14: len cuts it)", h, 15, "world", 14);
	test("\"\" (len 0)", h, 15, "", 0);
	test("\"\" (len 15)", h, 15, "", 15);
	test("\"o\" (len 4: the first 'o' is byte 4)", h, 15, "o", 4);
	test("\"o\" (len 5)", h, 15, "o", 5);
	test("\"Hello\" (len 0)", h, 15, "Hello", 0);
	test("\"Hello, 42 world!!\" (longer than big, len 100)", h, 15,
		"Hello, 42 world!!", 100);
	test("\"xyz\" (absent, len 15)", h, 15, "xyz", 15);
	test("\"world\" (len SIZE_MAX)", h, 15, "world", SIZE_MAX);
	test("\"c\" in \"abc\" (len 10, past its NUL)", "abc", 3, "c", 10);
	test("\"abcd\" in \"abc\" (len 10)", "abc", 3, "abcd", 10);
	test("\"aaab\" in \"aaaab\" (len 5)", "aaaab", 5, "aaab", 5);
	test("\"Bar\" in \"Foo Bar Baz\" (len 4, the man page's example)",
		"Foo Bar Baz", 11, "Bar", 4);
	test("\"Bar\" in \"Foo Bar Baz\" (len 7)", "Foo Bar Baz", 11, "Bar", 7);
	test("byte 0xe9 in 'a' 0xe9 (len 2)", hi, 2, e9, 2);
	test_long("\"a#\" ending at byte 4999 of 5000 (len 5000)", 5000);
	test_long("\"a#\" ending at byte 4999 of 5000 (len 4999)", 4999);
	return (0);
}
