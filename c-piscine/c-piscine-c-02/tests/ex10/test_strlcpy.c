#include <stdio.h>

unsigned int	ft_strlcpy(char *dest, char *src, unsigned int size);

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

/* Shows a buffer, printing each NUL as "\0" so termination is visible. */
static void	show(char *d, int n)
{
	int	i;

	i = 0;
	while (i < n)
	{
		if (d[i] == '\0')
			printf("\\0");
		else
			printf("%c", d[i]);
		i++;
	}
	printf("\n");
}

static void	test(char *label, char *src, unsigned int size, int showlen)
{
	char			dest[50];
	unsigned int	ret;

	fill(dest, 50);
	ret = ft_strlcpy(dest, src, size);
	printf("%s\tret=%u buf=", label, ret);
	show(dest, showlen);
}

int	main(void)
{
	test("\"\" size 5 (empty src)", "", 5, 4);
	test("\"Hi\" size 50 (fits)", "Hi", 50, 6);
	test("\"Hello\" size 6 (fits exactly)", "Hello", 6, 8);
	test("\"Hello\" size 5 (truncated by 1)", "Hello", 5, 8);
	test("\"Hello\" size 1 (only the \\0)", "Hello", 1, 6);
	test("\"Hello\" size 0 (writes nothing)", "Hello", 0, 6);
	test("\"Hello World\" size 6 (big truncate)", "Hello World", 6, 10);
	return (0);
}
