/* A toy reader harness: what the knobs of the macro that names it hand
 * their runner, nothing else -- no test built from it is ever run.
 * Line: <decimal n>\t<toy_twice(n)>. See tools/diffio.h. */
#include "diffio.h"

int	toy_twice(int n);

int	main(void)
{
	char	line[64];

	while (dio_line(line, sizeof(line)))
		printf("%s\t%d\n", line, toy_twice(atoi(line)));
	return (0);
}
