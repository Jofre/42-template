#include <stdio.h>

char	*ft_strncpy(char *dest, char *src, unsigned int n);

static void	fill(char *b, int n)
{
	int	i;

	i = 0;
	while (i < n)
	{
		b[i] = 'X';
		i++;
	}
}

/* Shows a buffer, NULs included, in the notation that diff_output.sh
 * --escaped-values reads (tools/diff_output.sh, HARNESS-ESCAPED VALUES).
 * A NUL is "\x00", so the padding and the terminator are visible; a
 * backslash is "\\" and a line break "\n", so neither is read as a mark
 * or as the end of the row. Any other byte is printed as it is: the
 * table shows a byte outside printable ASCII as \xHH itself. */
static void	show(char *d, int n)
{
	int	i;

	i = 0;
	while (i < n)
	{
		if (d[i] == '\0')
			printf("\\x00");
		else if (d[i] == '\\')
			printf("\\\\");
		else if (d[i] == '\n')
			printf("\\n");
		else
			printf("%c", d[i]);
		i++;
	}
	printf("\n");
}

static void	test(char *label, char *src, unsigned int n, int showlen)
{
	char	dest[50];

	fill(dest, 50);
	ft_strncpy(dest, src, n);
	printf("%s\t", label);
	show(dest, showlen);
}

int	main(void)
{
	char	dest[50];
	char	*ret;

	test("n=0 (copies nothing)", "Hello", 0, 5);
	test("empty src, n=4 (pads with \\0)", "", 4, 6);
	test("n>len: \"Hello\",10 (pads rest \\0)", "Hello", 10, 15);
	test("n==len: \"Hello\",5 (NO terminator!)", "Hello", 5, 8);
	test("n<len: \"Hello\",3 (NO terminator!)", "Hello", 3, 8);
	fill(dest, 50);
	ret = ft_strncpy(dest, "Hello", 5);
	printf("returns dest\tret==dest:%d\n", ret == dest);
	return (0);
}
