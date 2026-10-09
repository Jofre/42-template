/* Live-differential reader harness for ft_is_negative.
 * Line: <n>\t<what it wrote>. The int in decimal, then the byte the function
 * wrote to fd 1 for it (the reference's column is 'N' or 'P').
 *
 * The function writes its char straight to fd 1, so stdout is flushed around
 * the call to keep the echoed input, the function's byte, and the newline in
 * order. See tools/diffio.h. */
#include "diffio.h"
#include <unistd.h>

void	ft_is_negative(int n);

int	main(void)
{
	char	line[64];
	char	*f[2];

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		printf("%s\t", f[0]);
		fflush(stdout);
		ft_is_negative(atoi(f[0]));
		fflush(stdout);
		printf("\n");
	}
	return (0);
}
