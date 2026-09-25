#include <stdio.h>
#include <stdlib.h>

int	ft_ultimate_range(int **range, int min, int max);

/* Prints "<label>\t<value>" so tools/diff_output.sh (run with --labeled) can
 * show each case in its own column. The result arrives TWO ways: the return
 * value is the size, and the int** out-parameter receives the array pointer.
 * We render both: size=<n> ptr=<set|NULL> then the array on one line as [a][b].
 * Cases are ordered trivial -> hardest, so the first failing row is the most
 * fundamental thing to fix. */
static void	test(char *label, int min, int max)
{
	int	*range;
	int	size;
	int	i;

	range = NULL;
	size = ft_ultimate_range(&range, min, max);
	printf("%s\tsize=%d ptr=%s", label, size, range ? "set" : "NULL");
	i = 0;
	/* `range &&` is the whole point of this line. The likeliest mistake in this
	 * exercise is returning a positive size while leaving *range NULL -- a
	 * forgotten assignment, or a refused malloc reported only in the return
	 * value. Without the guard this loop dereferences NULL one statement after
	 * printing "ptr=NULL", so the commonest student bug arrives as a SEGV that
	 * takes the level-1 output layer down with a signal instead of as the row
	 * "size=6 ptr=NULL", which says exactly what went wrong. */
	while (range && i < size)
	{
		printf(" [%d]", range[i]);
		i++;
	}
	printf("\n");
	free(range);
}

int	main(void)
{
	test("single element 7..8", 7, 8);
	test("small positives 1..5", 1, 5);
	test("negatives only -5..-3", -5, -3);
	test("crosses zero -2..3", -2, 3);
	test("min equals max 5..5", 5, 5);
	test("min greater than max 10..3", 10, 3);
	return (0);
}
