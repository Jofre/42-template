#include <stdio.h>
#include <stdlib.h>

char	*ft_strdup(char *src);

/* Prints "<label>\t[<copy>]" — the duplicated string rendered on one line.
 * Cases run trivial -> hardest so the first failing row is the most basic. */
static void	test(char *label, char *src)
{
	char	*d;

	d = ft_strdup(src);
	if (d)
		printf("%s\t[%s]\n", label, d);
	else
		printf("%s\t(null)\n", label);
	free(d);
}

/* Proof the copy is independent: report whether it is a NEW buffer (not the
 * same pointer as src), then mutate the copy and show src is untouched — all on
 * ONE labeled line. */
static void	test_independent(char *label)
{
	char	buf[] = "modifiable";
	char	*d;

	d = ft_strdup(buf);
	if (!d)
	{
		printf("%s\t(null)\n", label);
		return ;
	}
	printf("%s\tnew_buffer:%d copy=[", label, d != buf);
	d[0] = 'X';
	printf("%s] src=[%s]\n", d, buf);
	free(d);
}

int	main(void)
{
	test("\"\" (empty)", "");
	test("\"a\" (single char)", "a");
	test("\"42 Barcelona\"", "42 Barcelona");
	test("whitespace copied verbatim", "with  multiple   spaces");
	test_independent("deep copy independent");
	return (0);
}
