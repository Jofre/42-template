/* Live-differential reader harness for ft_strcapitalize.
 * Line: <hexStr>\t<hexResult>\t1. Case transform is in place and length-
 * preserving (never introduces a NUL), so all original bytes are reprinted as
 * hex, then a trailing 1/0 for "returned the str pointer it was given". */
#include "diffio.h"

char	*ft_strcapitalize(char *str);

int	main(void)
{
	char			line[8192];
	char			*f[2];
	unsigned char	*s;
	size_t			slen;
	char			*ret;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		s = dio_unhex(f[0], &slen, 0);
		ret = ft_strcapitalize((char *)s);
		printf("%s\t", f[0]);
		dio_puthex(s, slen);
		printf("\t%d\n", ret == (char *)s);
		free(s);
	}
	return (0);
}
