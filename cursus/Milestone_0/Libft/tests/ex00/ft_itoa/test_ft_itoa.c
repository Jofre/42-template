#include <limits.h>
#include <stdio.h>
#include <stdlib.h>

/* The fixture of ex00_ft_itoa_output: one labelled row per int, the string
 * ft_itoa returned printed between quotes, or NULL; each result is freed
 * before its row's newline, so a crash in free() marks its own row.
 * Every case is a value an int holds, so every reading of the box (p.11)
 * agrees on its answer: 0, one and two digits on each side of 0 (7, -7,
 * 42, -42), the edges at 10 and 100 on the positive side only (9 and 10, 99
 * and 100), -1 and -100, 10^9 and -10^9, and the two ends of the type. */
char	*ft_itoa(int n);

static void	test(const char *label, int n)
{
	char	*r;

	r = ft_itoa(n);
	printf("%s\t", label);
	if (r == NULL)
		printf("NULL");
	else
		printf("\"%s\"", r);
	free(r);
	printf("\n");
}

int	main(void)
{
	test("0", 0);
	test("7", 7);
	test("-7", -7);
	test("9", 9);
	test("10", 10);
	test("42", 42);
	test("-42", -42);
	test("99", 99);
	test("100", 100);
	test("-100", -100);
	test("-1", -1);
	test("1000000000", 1000000000);
	test("-1000000000", -1000000000);
	test("INT_MAX - 1", INT_MAX - 1);
	test("INT_MAX", INT_MAX);
	test("INT_MIN + 1", INT_MIN + 1);
	test("INT_MIN", INT_MIN);
	return (0);
}
