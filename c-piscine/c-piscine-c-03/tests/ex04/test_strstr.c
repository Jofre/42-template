#include <stdio.h>

char	*ft_strstr(char *str, char *to_find);

/* Prints "<label>\t<offset>:<match..>" or "<label>\tNULL". */
static void	test(char *label, char *str, char *to_find)
{
	char	*p;

	p = ft_strstr(str, to_find);
	if (p)
		printf("%s\t%ld:%s\n", label, (long)(p - str), p);
	else
		printf("%s\tNULL\n", label);
}

int	main(void)
{
	test("find \"Hello\" at start", "Hello World!", "Hello");
	test("find \"World\" in middle", "Hello World!", "World");
	test("find \"!\" at end", "Hello World!", "!");
	test("find \"o W\" (spans a space)", "Hello World!", "o W");
	test("empty needle", "Hello World!", "");
	test("case-sensitive miss \"world\"", "Hello World!", "world");
	test("not present \"xyz\"", "Hello", "xyz");
	test("needle longer than haystack", "abc", "abcd");
	test("whole string equals needle", "abc", "abc");
	test("overlap \"ab\" in \"aab\"", "aab", "ab");
	test("overlap \"aa\" in \"aaa\"", "aaa", "aa");
	test("late match \"abcd\" in \"abcabcd\"", "abcabcd", "abcd");
	test("empty haystack empty needle", "", "");
	test("empty haystack needle \"a\"", "", "a");
	test("first of two \"ab\" in \"abab\"", "abab", "ab");
	test("first \"X\" in \"..X..X\"", "..X..X", "X");
	test("restart \"aab\" in \"aaab\"", "aaab", "aab");
	test("needle past remaining \"abcd\"", "abcabca", "abcd");
	test("needle past remaining \"ab\" in \"xa\"", "xa", "ab");
	return (0);
}
