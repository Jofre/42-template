#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

/* 5000 words, "w0" to "w4999", each followed by one to three of ",; " in
 * turn, and the result checked against those words by construction, then
 * shown as ONE line: the words, abridged, or the first one that differs. The
 * subject bounds neither the string nor the number of words, so every
 * reading agrees on this case, and it is past every capacity an array of
 * words is usually given (16, 64, 256, 1024, 4096): a function that counts
 * into a fixed-size array of its own gets it wrong here, or dies
 * (finding 041). */
static void	test_long(void)
{
	static char	str[64000];
	static char	*charset = ",; ";
	char		**res;
	char		word[16];
	int			len;
	int			i;
	int			k;

	len = 0;
	i = 0;
	while (i < 5000)
	{
		len += sprintf(str + len, "w%d", i);
		k = 0;
		while (k < 1 + i % 3)
		{
			str[len++] = charset[(i + k) % 3];
			k++;
		}
		i++;
	}
	str[len] = '\0';
	res = ft_split(str, charset);
	printf("5000 words\t");
	i = 0;
	while (res && i < 5000 && res[i])
	{
		sprintf(word, "w%d", i);
		if (strcmp(res[i], word) != 0)
			break ;
		i++;
	}
	if (!res)
		printf("(null)\n");
	else if (i == 5000 && !res[i])
		printf("[w0][w1] ... [w4999]\n");
	else if (i == 5000)
		printf("more than 5000 words\n");
	else if (!res[i])
		printf("only %d words\n", i);
	else
		printf("word %d is [%s], not [w%d]\n", i, res[i], i);
	k = 0;
	while (res && res[k])
		free(res[k++]);
	free(res);
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
	test_long();
	return (0);
}
