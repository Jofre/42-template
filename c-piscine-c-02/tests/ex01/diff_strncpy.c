/* Live-differential reader harness for ft_strncpy.
 * Line: <hexSrc>\t<n>\t<hexDest(n bytes)>\t1. Runs strncpy into an n-byte dest
 * prefilled with 0xff, reprints ALL n bytes (padding NULs included), then a
 * trailing 1/0 for "returned dest". */
#include "diffio.h"

char			*ft_strncpy(char *dest, char *src, unsigned int n);

int	main(void)
{
	char			line[8192];
	char			*f[3];
	unsigned char	*src;
	unsigned char	*dest;
	unsigned int	n;
	char			*ret;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		src = dio_unhex(f[0], NULL, 0);
		n = (unsigned int)strtoul(f[1], NULL, 10);
		/* EXACTLY the window the function is given, never one more. With
		 * malloc(n + 1) a write to dest[n] -- the classic mistake in
		 * this exercise, terminating a buffer the subject says must not
		 * be terminated -- landed INSIDE the allocation, so the ASan twin
		 * of this harness could not see it and the diff could not either
		 * (the extra byte is never printed). Sized to fit, one step past
		 * the end is a redzone. The `? : 1` keeps a valid pointer when
		 * n is 0, since malloc(0) may return NULL. */
		dest = (unsigned char *)malloc(n ? n : 1);
		memset(dest, 0xff, n);
		ret = ft_strncpy((char *)dest, (char *)src, n);
		printf("%s\t%s\t", f[0], f[1]);
		dio_puthex(dest, n);
		printf("\t%d\n", ret == (char *)dest);
		free(src);
		free(dest);
	}
	return (0);
}
