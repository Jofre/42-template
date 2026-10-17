#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* The table for ft_strncmp (man 3 strncmp, where Libft, p.8 sends you).
 * Prints "<label>\t<sign>": negative, zero or positive. man 3 strncmp's
 * RETURN VALUE promises a sign, so the sign is what is compared, here and in
 * the diff layer. n = SIZE_MAX is the largest size_t, whatever its width. */
int	ft_strncmp(const char *s1, const char *s2, size_t n);

static const char	*sign(int v)
{
	if (v < 0)
		return ("negative");
	if (v > 0)
		return ("positive");
	return ("zero");
}

static void	test(const char *label, const char *s1, const char *s2, size_t n)
{
	printf("%s\t%s\n", label, sign(ft_strncmp(s1, s2, n)));
}

/* Two 5000-byte strings of 'a'..'z' over and over, equal but for their last
 * byte, which is 'y' in s1 and 'z' in s2: by construction they first differ
 * at index 4999, where s1's byte is the smaller. */
static void	test_long(const char *label, size_t n)
{
	static char	s1[5001];
	static char	s2[5001];
	int			i;

	i = 0;
	while (i < 5000)
	{
		s1[i] = (char)('a' + i % 26);
		i++;
	}
	memcpy(s2, s1, 5000);
	s1[4999] = 'y';
	s2[4999] = 'z';
	s1[5000] = '\0';
	s2[5000] = '\0';
	test(label, s1, s2, n);
}

int	main(void)
{
	const char	x80[] = {(char)0x80, '\0'};
	const char	x01[] = {(char)0x01, '\0'};
	const char	xff[] = {(char)0xff, '\0'};
	const char	nul_x[] = {'a', 'b', '\0', 'x', '\0'};
	const char	nul_y[] = {'a', 'b', '\0', 'y', '\0'};

	test("\"abc\" vs \"xyz\" (n=0)", "abc", "xyz", 0);
	test("\"Hello\" vs \"Hello\" (n=5)", "Hello", "Hello", 5);
	test("\"abc\" vs \"abc\" (n=10)", "abc", "abc", 10);
	test("\"Hello\" vs \"Hella\" (n=4, they differ after n)", "Hello", "Hella", 4);
	test("\"abc\" vs \"abd\" (n=10)", "abc", "abd", 10);
	test("\"xyz\" vs \"abc\" (n=3)", "xyz", "abc", 3);
	test("\"Hello\" vs \"Hella\" (n=5)", "Hello", "Hella", 5);
	test("\"Hello\" vs \"Helloo\" (n=5, equal prefix)", "Hello", "Helloo", 5);
	test("\"Hello\" vs \"Helloo\" (n=6, s1 ends first)", "Hello", "Helloo", 6);
	test("\"abc\" vs \"ab\" (n=10, s2 ends first)", "abc", "ab", 10);
	test("\"\" vs \"\" (n=1)", "", "", 1);
	test("\"\" vs \"abc\" (n=3)", "", "abc", 3);
	test("\"abc\" vs \"\" (n=3)", "abc", "", 3);
	test("\"abXee\" vs \"abYee\" (n=3, they differ at n-1)", "abXee", "abYee", 3);
	test("\"ab\", NUL, \"x\" vs \"ab\", NUL, \"y\" (n=4)", nul_x, nul_y, 4);
	test("\"abc\" vs \"abd\" (n=SIZE_MAX)", "abc", "abd", SIZE_MAX);
	test("\"abc\" vs \"abc\" (n=SIZE_MAX)", "abc", "abc", SIZE_MAX);
	test("\"abd\" vs \"abc\" (n=2147483648)", "abd", "abc", (size_t)2147483648u);
	test("byte 0x80 vs byte 0x01 (n=1)", x80, x01, 1);
	test("byte 0x01 vs byte 0x80 (n=1)", x01, x80, 1);
	test("byte 0xff vs \"a\" (n=5)", xff, "a", 5);
	test_long("5000 bytes, differ at 4999 (n=5000)", 5000);
	test_long("5000 bytes, differ at 4999 (n=4999)", 4999);
	test_long("5000 bytes, differ at 4999 (n=SIZE_MAX)", SIZE_MAX);
	return (0);
}
