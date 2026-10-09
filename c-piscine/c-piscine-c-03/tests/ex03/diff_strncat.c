/* Live-differential reader harness for ft_strncat.
 * Line: <hexDest>\t<destcap>\t<hexSrc>\t<n>\t<hexResult>\t<returned dest>.
 * The destination and the source, two hex digits per byte, the size of the
 * buffer the destination is in, n in decimal, then what the buffer holds after
 * the call up to its first NUL (hex, never past destcap), and 1 or 0 for
 * "returned the dest pointer it was given".
 *
 * The buffer is filled with 0xff before the destination is copied in and
 * terminated (dio_dest, tools/diffio.h), so every byte past the old
 * terminator is garbage: an append that does not write its own terminator
 * shows up as trailing ff bytes, where a zeroed buffer would have supplied
 * one for it (finding 057). */
#include "diffio.h"

char	*ft_strncat(char *dest, char *src, unsigned int nb);

int	main(void)
{
	char			line[8192];
	char			*f[5];
	size_t			dlen;
	size_t			cap;
	unsigned char	*draw;
	unsigned char	*buf;
	unsigned char	*src;
	unsigned int	n;
	char			*ret;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 5) < 4)
			continue ;
		draw = dio_unhex(f[0], &dlen, 0);
		cap = strtoul(f[1], NULL, 10);
		buf = dio_dest(draw, dlen, cap);
		src = dio_unhex(f[2], NULL, 0);
		n = (unsigned int)strtoul(f[3], NULL, 10);
		ret = ft_strncat((char *)buf, (char *)src, n);
		printf("%s\t%s\t%s\t%s\t", f[0], f[1], f[2], f[3]);
		dio_puthex(buf, dio_caplen(buf, cap));
		printf("\t%d\n", ret == (char *)buf);
		free(draw);
		free(buf);
		free(src);
	}
	return (0);
}
