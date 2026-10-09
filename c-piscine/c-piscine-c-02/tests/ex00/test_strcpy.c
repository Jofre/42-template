#include <stdio.h>
#include <string.h>

char	*ft_strcpy(char *dest, char *src);

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

/* Copies src into a fresh X-filled buffer. Prints "<label>\t[<dest>]
 * ret==dest:<x> after_nul:<c>" — after_nul is the byte just past the copied
 * terminator and must still be 'X' (proof you didn't write past the end). */
static void	test(char *label, char *src)
{
	char	dest[50];
	char	*ret;

	fill(dest, 50);
	ret = ft_strcpy(dest, src);
	printf("%s\t[%s] ret==dest:%d after_nul:%c\n",
		label, dest, ret == dest, dest[strlen(src) + 1]);
}

int	main(void)
{
	test("\"\" (empty)", "");
	test("\"A\" (single char)", "A");
	test("\"Hello World!\"", "Hello World!");
	return (0);
}
