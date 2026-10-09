#include <stdio.h>

int	toy_twice(int n);
int	toy_base(int n);

/* toy_base is the grader's (the contract's `linked`): it links only where the
 * macros hand the library over. */
int	main(void)
{
	printf("%d\n", toy_twice(21));
	printf("%d\n", toy_base(21));
	return (0);
}
