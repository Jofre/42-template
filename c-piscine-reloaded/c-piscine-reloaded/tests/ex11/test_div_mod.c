#include <stdio.h>
#include <limits.h>

void	ft_div_mod(int a, int b, int *div, int *mod);

/* The two ints start at a value no row's quotient or remainder is, and one
 * still holding it prints as "untouched": a function that never stores
 * through a pointer is seen on every row. They used to start at 0, which
 * three rows expect, so on those rows nothing showed whether the function
 * wrote them (finding 076's class: an out-parameter preset to the value a
 * row checks). */
#define UNTOUCHED 1592614637

static void	show(int v)
{
	if (v == UNTOUCHED)
		printf("untouched");
	else
		printf("%d", v);
}

/* Prints "<label>\tdiv: <quotient>, mod: <remainder>", the two values the
 * function stored through its pointers. */
static void	test(char *label, int a, int b)
{
	int	d;
	int	m;

	d = UNTOUCHED;
	m = UNTOUCHED;
	ft_div_mod(a, b, &d, &m);
	printf("%s\tdiv: ", label);
	show(d);
	printf(", mod: ");
	show(m);
	printf("\n");
}

int	main(void)
{
	test("13 / 5", 13, 5);
	test("7 / 1", 7, 1);
	test("0 / 5", 0, 5);
	test("-13 / 5 (neg dividend)", -13, 5);
	test("13 / -5 (neg divisor)", 13, -5);
	test("-13 / -5 (both neg)", -13, -5);
	test("-7 / 2", -7, 2);
	test("INT_MIN / 2", INT_MIN, 2);
	test("INT_MAX / 7", INT_MAX, 7);
	return (0);
}
