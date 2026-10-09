#include <stdio.h>
#include <stdlib.h>
#include <string.h>

char	**ft_split(char *str, char *charset);

/* Prints "<label>\t" then every returned token bracketed [tok] with no spaces,
 * on a single line (so tools/diff_output.sh --labeled shows one case per row).
 * An empty array -- the NULL at index 0 -- prints just the label; a NULL
 * RESULT prints "(null)", as C 09 ex02's fixture does, because the two are
 * different answers and used to print the same bytes (finding 080). Cases run
 * trivial -> hardest, so the first failing row is the most fundamental thing
 * to fix. */
static void	test(char *label, char *str, char *charset)
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
	test("no separators single token", "hello", " ");
	test("three words on spaces", "a b c", " ");
	test("leading trailing multiple spaces", "  hello   world 42 ", " ");
	test("charset with several chars", "a,b;c", ",;");
	test("adjacent separators no empty", "a,,;,b", ",;");
	test("empty charset whole string", "hello world", "");
	test("empty string", "", " ");
	test("only separators", "   ", " ");
	test_long();
	return (0);
}
