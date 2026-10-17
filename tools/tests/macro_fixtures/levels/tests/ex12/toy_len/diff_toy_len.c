/* Live-differential reader harness for toy_len, the toy library's member.
 * Line: <n>\t<returned int>. The input as the reference wrote it, then what
 * toy_len returned for it, in decimal. See tools/diffio.h. */
#include "diffio.h"

int	toy_len(int n);

int	main(void)
{
	char	line[256];
	char	*f[2];
	int		n;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		n = (int)strtol(f[0], NULL, 10);
		printf("%s\t%d\n", f[0], toy_len(n));
	}
	return (0);
}
