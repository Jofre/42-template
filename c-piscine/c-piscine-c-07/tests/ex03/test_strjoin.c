#include <stdio.h>
#include <stdlib.h>

char	*ft_strjoin(int size, char **strs, char *sep);

/* Prints "<label>\t[<value>]" so tools/diff_output.sh (run with --labeled)
 * shows each case in its own column. The whole joined string is one line.
 * A NULL result prints "(null)" so a missing allocation is visible. Cases are
 * ordered trivial -> hardest, so the first failing row is the most basic fix. */
static void	test(char *label, int size, char **strs, char *sep)
{
	char	*res;

	res = ft_strjoin(size, strs, sep);
	if (res)
		printf("%s\t[%s]\n", label, res);
	else
		printf("%s\t(null)\n", label);
	free(res);
}

int	main(void)
{
	char	*strs[] = {"Hello", "World", "42"};
	char	*two[] = {"ab", "cd"};
	char	*withempty[] = {"", "x", ""};

	test("single element, sep unused", 1, strs, "-");
	test("two strings, dash separator", 2, two, "-");
	test("three strings, comma-space separator", 3, strs, ", ");
	test("empty separator joins two", 2, strs, "");
	test("empty separator joins ab cd", 2, two, "");
	test("empty elements with separator", 3, withempty, "-");
	test("size 0 empty string", 0, strs, "-");
	return (0);
}
