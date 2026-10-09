#include <stdio.h>

void	ft_putnbr(int nb);

/* Prints "<label>\t" then lets ft_putnbr write the digits, then a newline.
 * setbuf(stdout, NULL) makes printf unbuffered so the labels stay ordered
 * with the bytes ft_putnbr emits via write(). Cases ordered trivial ->
 * conceptually hardest. */
static void	test(char *label, int nb)
{
	printf("%s\t", label);
	ft_putnbr(nb);
	printf("\n");
}

int	main(void)
{
	setbuf(stdout, NULL);
	test("zero", 0);
	test("one digit", 7);
	test("two digits", 42);
	test("ends in zero", 10);
	test("trailing zeros", 100);
	test("big positive", 1000000000);
	test("negative one digit", -7);
	test("negative two digits", -42);
	test("negative trailing zeros", -100);
	test("big negative", -1000000000);
	test("INT_MAX", 2147483647);
	test("INT_MAX - 1", 2147483646);
	test("INT_MIN + 1", -2147483647);
	test("INT_MIN", -2147483648);
	return (0);
}
