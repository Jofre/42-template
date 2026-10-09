#include <stdio.h>

int	ft_strcmp(char *s1, char *s2);

/* The SIGN of a comparison result, as a word. The subject sends you to
 * `man strcmp`, whose RETURN VALUE promises a sign; whether the exact int is
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
 * show each case in its own column. What the sign should be is
 * `man strcmp`'s to say. */
static void	test(char *label, char *s1, char *s2)
{
	printf("%s\t%s\n", label, sign(ft_strcmp(s1, s2)));
}

int	main(void)
{
	char	hi1[] = {(char)0x80, 0};
	char	hi2[] = {(char)0x01, 0};
	char	hi3[] = {'A', (char)0x80, 0};
	char	hi4[] = {'A', (char)0x7f, 0};
	char	hi5[] = {(char)0xff, 0};
	char	hi6[] = {'a', 0};

	test("\"Hello\" vs \"Hello\"", "Hello", "Hello");
	test("\"Hello\" vs \"Hella\"", "Hello", "Hella");
	test("\"Hello\" vs \"Helloo\"", "Hello", "Helloo");
	test("\"Helloo\" vs \"Hello\"", "Helloo", "Hello");
	test("\"\" vs \"\"", "", "");
	test("\"\" vs \"a\"", "", "a");
	test("\"a\" vs \"\"", "a", "");
	test("\"abc\" vs \"abd\"", "abc", "abd");
	test("\"abz\" vs \"abc\"", "abz", "abc");
	test("{0x80} vs {0x01}", hi1, hi2);
	test("{0x01} vs {0x80}", hi2, hi1);
	test("{A,0x80} vs {A,0x7f}", hi3, hi4);
	test("{0x80} vs {0xff}", hi1, hi5);
	test("{0xff} vs {a}", hi5, hi6);
	return (0);
}
