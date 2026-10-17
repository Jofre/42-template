/* Live-differential reader harness for ft_strlcpy.
 * Line: <hexSrc>\t<size>\t<hexDstContent>\t<ret>. The source, two hex digits
 * per byte, size in decimal, then what the destination holds after the call
 * up to its first NUL (hex, never past size), and what ft_strlcpy returned,
 * in decimal. The destination is exactly size bytes of 0xff
 * (tools/diffio.h, dio_garbage), so a missing terminator shows as ff bytes
 * and a write past size lands in an ASan redzone in the diff_asan twin. */
#include "diffio.h"

size_t	ft_strlcpy(char *dst, const char *src, size_t size);

int	main(void)
{
	char			*line;
	size_t			linecap;
	char			*f[4];
	unsigned char	*src;
	unsigned char	*dst;
	size_t			size;
	size_t			ret;

	/* A line of any length (tools/diffio.h, dio_getline): the corpus holds
	 * strings past 4 KiB, past what a line buffer holds. */
	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		if (dio_split(line, f, 4) < 2)
			continue ;
		src = dio_unhex(f[0], NULL, 0);
		size = (size_t)strtoull(f[1], NULL, 10);
		dst = dio_garbage(size);
		ret = ft_strlcpy((char *)dst, (const char *)src, size);
		printf("%s\t%s\t", f[0], f[1]);
		dio_puthex(dst, dio_caplen(dst, size));
		printf("\t%zu\n", ret);
		free(src);
		free(dst);
	}
	free(line);
	return (0);
}
