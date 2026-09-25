/* Live-differential reader harness for ft_strdup.
 * Line: <hexSrc>. Duplicates src and prints the copy's content as hex (or NULL).
 * See tools/diffio.h. */
#include "diffio.h"

char	*ft_strdup(char *src);

int	main(void)
{
	char			line[8192];
	char			*f[2];
	unsigned char	*src;
	char			*res;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		src = dio_unhex(f[0], NULL, 0);
		res = ft_strdup((char *)src);
		printf("%s\t", f[0]);
		if (!res)
			printf("NULL");
		else
			dio_puthex((unsigned char *)res, strlen(res));
		printf("\n");
		free(src);
		free(res);
	}
	return (0);
}
