#include <stdio.h>
#include <stdlib.h>

char	*ft_strdup(char *src);

/* Prints "<label>\t[<copy>]" — the duplicated string rendered on one line.
 * Cases run trivial -> hardest so the first failing row is the most basic.
 * The copy is freed before the row's newline, so a crash in free() leaves
 * this row unfinished and diff_output.sh marks it, not the next one. */
static void	test(char *label, char *src)
{
	char	*d;

	d = ft_strdup(src);
	if (d)
		printf("%s\t[%s]", label, d);
	else
		printf("%s\t(null)", label);
	free(d);
	printf("\n");
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
	printf("%s] src=[%s]", d, buf);
	free(d);
	printf("\n");
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
