/* Live-differential reader harness for ft_strlcat.
 * Line: <hexDest>\t<destcap>\t<hexSrc>\t<size>\t<hexResult>\t<returned int>.
 * The destination and the source, two hex digits per byte, the size of the
 * buffer the destination is in, the size argument in decimal, then what the
 * buffer holds after the call up to its first NUL (hex, never past destcap),
 * and what ft_strlcat returned, in decimal.
 *
 * The buffer is filled with 0xff before the destination is copied in and
 * terminated (dio_dest, tools/diffio.h), so every byte past the old
 * terminator is garbage: a result that is not terminated shows up as
 * trailing ff bytes, where a zeroed buffer would have supplied a terminator
 * for it (finding 057). */
#include "diffio.h"

unsigned int	ft_strlcat(char *dest, char *src, unsigned int size);

int	main(void)
{
	char			line[8192];
	char			*f[6];
	size_t			dlen;
	size_t			cap;
	unsigned int	size;
	unsigned char	*draw;
	unsigned char	*buf;
	unsigned char	*src;
	unsigned int	ret;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 6) < 4)
			continue ;
		draw = dio_unhex(f[0], &dlen, 0);
		cap = strtoul(f[1], NULL, 10);
		buf = dio_dest(draw, dlen, cap);
		src = dio_unhex(f[2], NULL, 0);
		size = (unsigned int)strtoul(f[3], NULL, 10);
		ret = ft_strlcat((char *)buf, (char *)src, size);
		printf("%s\t%s\t%s\t%s\t", f[0], f[1], f[2], f[3]);
		dio_puthex(buf, dio_caplen(buf, cap));
		printf("\t%u\n", ret);
		free(draw);
		free(buf);
		free(src);
	}
	return (0);
}
