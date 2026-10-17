/* Live-differential reader harness for ft_striteri.
 * Line: <hexS>\t<hexAfter>\t<calls>. The string, two hex digits per byte,
 * then what it holds after the call, up to its NUL, as hex, then 1 when f
 * was called exactly once for each index of s, in index order, with the
 * address s + i, and never for the terminator, else 0. See tools/diffio.h.
 *
 * f is the harness's own, the fixed function the reference applies too: it
 * stores f(i, c) = ((c + i) mod 255) + 1 through the address, c read as an
 * unsigned char, and only where the address is one of s's bytes. It never
 * stores 0, so s keeps its length. s is a block of its own, exactly its
 * bytes and its terminator. */
#include "diffio.h"

void	ft_striteri(char *s, void (*f)(unsigned int, char*));

static unsigned char	*g_s;
static size_t			g_len;
static size_t			g_next;
static int				g_ok;

static void	fixed_f(unsigned int i, char *p)
{
	unsigned char	c;

	if (i != g_next || i >= g_len || (unsigned char *)p != g_s + i)
		g_ok = 0;
	g_next++;
	if ((unsigned char *)p < g_s || (unsigned char *)p >= g_s + g_len)
		return ;
	c = (unsigned char)*p;
	*p = (char)(((unsigned long)c + i) % 255 + 1);
}

int	main(void)
{
	char	*line;
	size_t	linecap;
	char	*f[2];

	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		g_s = dio_unhex(f[0], &g_len, 0);
		g_next = 0;
		g_ok = 1;
		ft_striteri((char *)g_s, fixed_f);
		printf("%s\t", f[0]);
		dio_puthex(g_s, dio_caplen(g_s, g_len));
		printf("\t%d\n", g_ok && g_next == g_len);
		free(g_s);
	}
	free(line);
	return (0);
}
