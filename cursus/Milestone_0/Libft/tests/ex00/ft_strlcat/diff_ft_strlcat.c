/* Live-differential reader harness for ft_strlcat.
 * Line: <hexDst>\t<cap>\t<hexSrc>\t<size>\t<hexResult>\t<ret>. The
 * destination's string and the source, two hex digits per byte, the size of
 * the buffer the destination is in (cap) and the size argument, in decimal,
 * then what the buffer holds after the call up to its first NUL (hex, never
 * past cap), and what ft_strlcat returned, in decimal.
 *
 * The buffer is exactly cap bytes of 0xff with the destination's string and
 * its terminator copied in (tools/diffio.h, dio_dest), so every byte past
 * the old terminator is garbage: a result left unterminated shows up as
 * trailing ff bytes, and a write past cap lands in an ASan redzone in the
 * diff_asan twin. */
#include "diffio.h"

size_t	ft_strlcat(char *dst, const char *src, size_t size);

int	main(void)
{
	char			*line;
	size_t			linecap;
	char			*f[6];
	size_t			dlen;
	size_t			cap;
	size_t			size;
	unsigned char	*draw;
	unsigned char	*buf;
	unsigned char	*src;
	size_t			ret;

	/* A line of any length (tools/diffio.h, dio_getline): the corpus holds
	 * strings past 4 KiB, past what a line buffer holds. */
	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		if (dio_split(line, f, 6) < 4)
			continue ;
		draw = dio_unhex(f[0], &dlen, 0);
		cap = (size_t)strtoull(f[1], NULL, 10);
		buf = dio_dest(draw, dlen, cap);
		src = dio_unhex(f[2], NULL, 0);
		size = (size_t)strtoull(f[3], NULL, 10);
		ret = ft_strlcat((char *)buf, (const char *)src, size);
		printf("%s\t%s\t%s\t%s\t", f[0], f[1], f[2], f[3]);
		dio_puthex(buf, dio_caplen(buf, cap));
		printf("\t%zu\n", ret);
		free(draw);
		free(buf);
		free(src);
	}
	free(line);
	return (0);
}
