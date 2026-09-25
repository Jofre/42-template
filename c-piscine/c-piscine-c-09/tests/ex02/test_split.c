#include <stdio.h>
#include <stdlib.h>

char	**ft_split(char *str, char *charset);

/* Prints "<label>\t[tok][tok]..." (each token bracketed on one line), or
 * "<label>\t(null)". */
static void	run(char *label, char *str, char *charset)
{
	char	**res;
	int		i;

	res = ft_split(str, charset);
	printf("%s\t", label);
	if (!res)
	{
		printf("(null)\n");
		return ;
	}
	i = 0;
	while (res[i])
	{
		printf("[%s]", res[i]);
		free(res[i]);
		i++;
	}
	free(res);
	printf("\n");
}

/* Feeds a WRITABLE copy and appends "input=[...]" to prove the input string was
 * not modified (the subject forbids modifying it). All on one labeled line.
 * libc's snprintf makes the copy: this is the grader's side, not an exercise. */
static void	run_nomod(char *label, char *literal, char *charset)
{
	char	buf[256];
	char	**res;
	int		i;

	snprintf(buf, sizeof(buf), "%s", literal);
	res = ft_split(buf, charset);
	printf("%s\t", label);
	i = 0;
	while (res && res[i])
	{
		printf("[%s]", res[i]);
		free(res[i]);
		i++;
	}
	free(res);
	printf(" input=[%s]\n", buf);
}

int	main(void)
{
	run("single space sep", "hello world 42", " ");
	run("single-char word", "x", " ");
	run("no separator present", "no-separators-here", " ");
	run("empty charset -> one token", "singleton", "");
	run("runs of separators", "  multiple   spaces  ", " ");
	run("leading separator", ",leading", ",");
	run("trailing separator", "trailing,", ",");
	run("multiple separators", "a,b,c;d;e", ",;");
	run("adjacent different seps", "a,;b", ",;");
	run("tab + space separators", "split\tby\ttabs and spaces", " \t");
	run("empty string -> empty", "", " ");
	run("only separators -> empty", "   ", " ");
	run("all (mixed) seps -> empty", " ,; ,;", " ,;");
	run_nomod("input unchanged (spaces)", "keep me intact", " ");
	run_nomod("input unchanged (commas)", "a,b,c", ",");
	return (0);
}
