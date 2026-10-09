#include <stdio.h>

int	ft_strncmp(char *s1, char *s2, unsigned int n);

/* The SIGN of a comparison result, as a word. The subject sends you to
 * `man strncmp`, whose RETURN VALUE promises a sign; whether the exact int is
 * graded as well is not settled, so this basic table compares the sign only
 * and the strict diff layer compares the int itself. */
static const char	*sign(int v)
{
	if (v < 0)
		return ("negative");
	if (v > 0)
		return ("positive");
	return ("zero");
}

/* Prints "<label>\t<sign>" so tools/diff_output.sh (run with --labeled) can
 * show each case in its own column. What the sign should be, and how n
 * limits the comparison, is `man strncmp`'s to say. */
static void	test(char *label, char *s1, char *s2, unsigned int n)
{
	printf("%s\t%s\n", label, sign(ft_strncmp(s1, s2, n)));
}

int	main(void)
{
	char	hi1[] = {(char)0x80, 0};
	char	hi2[] = {(char)0x01, 0};

	test("\"abc\" vs \"xyz\" (n=0)", "abc", "xyz", 0);
	test("\"Hello\" vs \"Hello\" (n=0)", "Hello", "Hello", 0);
	test("\"Hello\" vs \"Hello\" (n=5)", "Hello", "Hello", 5);
	test("\"abc\" vs \"abc\" (n=10)", "abc", "abc", 10);
	test("\"Hello\" vs \"Hella\" (n=3, diff is after n)", "Hello", "Hella", 3);
	test("\"abc\" vs \"abd\" (n=10)", "abc", "abd", 10);
	test("\"xyz\" vs \"abc\" (n=3)", "xyz", "abc", 3);
	test("\"Hello\" vs \"Hella\" (n=5)", "Hello", "Hella", 5);
	test("\"Hello\" vs \"Helloo\" (n=5, equal prefix)", "Hello", "Helloo", 5);
	test("\"Hello\" vs \"Helloo\" (n=6, s1 ends first)", "Hello", "Helloo", 6);
	test("\"abc\" vs \"ab\" (n=10, s2 ends first)", "abc", "ab", 10);
	test("{0x80} vs {0x01} (n=1)", hi1, hi2, 1);
	test("{0x01} vs {0x80} (n=1)", hi2, hi1, 1);
	test("\"\" vs \"\" (n=1)", "", "", 1);
	test("\"\" vs \"abc\" (n=3)", "", "abc", 3);
	test("\"abc\" vs \"\" (n=3)", "abc", "", 3);
	test("\"abXee\" vs \"abYee\" (n=3, diff at n-1)", "abXee", "abYee", 3);
	return (0);
}
