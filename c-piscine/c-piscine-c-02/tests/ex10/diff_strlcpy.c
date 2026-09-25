/* Live-differential reader harness for ft_strlcpy.
 * Line: <hexSrc>\t<size>\t<hexDestContent>\t<ret>. Copies into a size-byte dest
 * prefilled with 0xff (so a missing terminator is caught), then reprints the
 * dest C-string content (hex, bounded by size) and the return value. */
#include "diffio.h"

unsigned int	ft_strlcpy(char *dest, char *src, unsigned int size);

int	main(void)
{
	char			line[8192];
	char			*f[4];
	unsigned char	*src;
	unsigned char	*dest;
	unsigned int	size;
	unsigned int	ret;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 4) < 2)
			continue ;
		src = dio_unhex(f[0], NULL, 0);
		size = (unsigned int)strtoul(f[1], NULL, 10);
		/* EXACTLY the window the function is given, never one more. With
		 * malloc(size + 1) a write to dest[size] -- the classic mistake in
		 * this exercise, terminating a buffer the subject says must not
		 * be terminated -- landed INSIDE the allocation, so the ASan twin
		 * of this harness could not see it and the diff could not either
		 * (the extra byte is never printed). Sized to fit, one step past
		 * the end is a redzone. The `? : 1` keeps a valid pointer when
		 * size is 0, since malloc(0) may return NULL. */
		dest = (unsigned char *)malloc(size ? size : 1);
		memset(dest, 0xff, size);
		ret = ft_strlcpy((char *)dest, (char *)src, size);
		printf("%s\t%s\t", f[0], f[1]);
		dio_puthex(dest, dio_caplen(dest, size));
		printf("\t%u\n", ret);
		free(src);
		free(dest);
	}
	return (0);
}
