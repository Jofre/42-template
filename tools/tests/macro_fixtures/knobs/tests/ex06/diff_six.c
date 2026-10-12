/* A toy reader harness over a unit student_lib() declares: it prints what
 * the toy returns, whatever it reads, so its program says one thing -- that
 * it was built: toy_six.c includes toy_six.h, which only the unit's include
 * directory reaches.
 * Line: <toy_six(21)>. See tools/diffio.h. */
#include "diffio.h"

int	toy_six(int n);

int	main(void)
{
	printf("%d\n", toy_six(21));
	return (0);
}
