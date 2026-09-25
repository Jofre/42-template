#include <stdio.h>

char	*ft_strcapitalize(char *str);

/* ft_strcapitalize modifies in place. Prints "<label>\t<result>". */
static void	test(char *label, char *s)
{
	printf("%s\t%s\n", label, ft_strcapitalize(s));
}

int	main(void)
{
	char	empty[] = "";
	char	abc[] = "a b c";
	char	words[] = "hELLo wORLD";
	char	digits[] = "42abc xyz";
	char	mixed[] = "ab42cd ef";
	char	punct[] = "salut, comment tu vas ? 42mots quarante-deux; cinquante+et+un";
	char	punct_en[] = "hi, how are you? 42words forty-two; fifty+and+one";
	char	rp[] = "x";
	char	*ret;

	test("\"\" (empty)", empty);
	test("\"a b c\" (each word capitalized)", abc);
	test("\"hELLo wORLD\" (rest lowercased)", words);
	test("\"42abc xyz\" (word starting with digit)", digits);
	test("\"ab42cd ef\" (digit mid-word)", mixed);
	/* Both language editions of the subject print their own transcript, and an
	 * evaluator types the one they were given. The two are not redundant: the
	 * ES/FR line has a space before its "?" and an accent-free multi-hyphen
	 * word, the EN line puts "?" tight against the word and starts a group with
	 * "42words" -- so each exercises a boundary the other does not. */
	test("subject transcript (es/fr)", punct);
	test("subject transcript (en)", punct_en);
	ret = ft_strcapitalize(rp);
	printf("returns its argument\tret==arg:%d\n", ret == rp);
	return (0);
}
