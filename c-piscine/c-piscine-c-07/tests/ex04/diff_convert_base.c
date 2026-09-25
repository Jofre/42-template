/* Live-differential reader harness for ft_convert_base.
 * Line: <hexNbr>\t<hexBaseFrom>\t<hexBaseTo>. Prints the converted string as hex
 * (or NULL for an invalid base / NULL result). See tools/diffio.h. */
#include "diffio.h"

char	*ft_convert_base(char *nbr, char *base_from, char *base_to);

int	main(void)
{
	char			line[8192];
	char			*f[4];
	unsigned char	*nbr;
	unsigned char	*from;
	unsigned char	*to;
	char			*res;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 4) < 3)
			continue ;
		nbr = dio_unhex(f[0], NULL, 0);
		from = dio_unhex(f[1], NULL, 0);
		to = dio_unhex(f[2], NULL, 0);
		res = ft_convert_base((char *)nbr, (char *)from, (char *)to);
		printf("%s\t%s\t%s\t", f[0], f[1], f[2]);
		if (!res)
			printf("NULL");
		else
			dio_puthex((unsigned char *)res, strlen(res));
		printf("\n");
		free(nbr);
		free(from);
		free(to);
		free(res);
	}
	return (0);
}
