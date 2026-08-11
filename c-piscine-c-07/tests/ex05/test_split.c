#include <stdio.h>
#include <stdlib.h>

char	**ft_split(char *str, char *charset);

/* Prints "<label>\t" then every returned token bracketed [tok] with no spaces,
 * on a single line (so tools/diff_output.sh --labeled shows one case per row).
 * An empty result prints just the label and a newline. Cases run trivial ->
 * hardest, so the first failing row is the most fundamental thing to fix. */
static void	test(char *label, char *str, char *charset)
{
	char	**res;
	int		i;

	res = ft_split(str, charset);
	printf("%s\t", label);
	if (res)
	{
		i = 0;
		while (res[i])
		{
			printf("[%s]", res[i]);
			free(res[i]);
			i++;
		}
		free(res);
	}
	printf("\n");
}

int	main(void)
{
	test("no separators single token", "hello", " ");
	test("three words on spaces", "a b c", " ");
	test("leading trailing multiple spaces", "  hello   world 42 ", " ");
	test("charset with several chars", "a,b;c", ",;");
	test("adjacent separators no empty", "a,,;,b", ",;");
	test("empty charset whole string", "hello world", "");
	test("empty string", "", " ");
	test("only separators", "   ", " ");
	return (0);
}
