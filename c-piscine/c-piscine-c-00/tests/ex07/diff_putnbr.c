/* Live-differential reader harness for ft_putnbr. Reads reference cases
 *   <decimal-int>\t<reference decimal text>
 * from stdin and reprints <decimal-int>\t<student output>. The function writes
 * its digits straight to fd 1, so stdout is flushed around the call to keep the
 * echoed input, the function's bytes, and the newline in order. See tools/diffio.h. */
#include "diffio.h"
#include <unistd.h>

void	ft_putnbr(int nb);

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
		ft_putnbr(atoi(f[0]));
		fflush(stdout);
		printf("\n");
	}
	return (0);
}
