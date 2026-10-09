#include <stdio.h>

int	toy_twice(int n);
int	toy_base(int n);

/* ex15's reading (c_function's `readings`): another harness over the same
 * unit, built like the fixture's program, the grader's toy_base linked in. */
int	main(void)
{
	printf("%d %d\n", toy_twice(1), toy_base(1));
	return (0);
}
