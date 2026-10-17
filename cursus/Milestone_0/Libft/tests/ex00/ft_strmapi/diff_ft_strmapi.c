/* Live-differential reader harness for ft_strmapi.
 * Line: <hexS>\t<hexResult>\t<calls>. The string, two hex digits per byte,
 * then what the returned string holds up to its NUL, as hex -- or NULL when
 * ft_strmapi returned NULL -- then 1 when f was called exactly once for each
 * index of s, in index order, with s[i], and never for the terminator, else
 * 0. See tools/diffio.h.
 *
 * f is the harness's own, the fixed function the reference applies too:
 * f(i, c) = ((c + i) mod 255) + 1, c read as an unsigned char. It never
 * gives 0, so no result ends early, and a wrong index or byte handed to it
 * shows in the result as well as in the last field. The result is freed. */
#include "diffio.h"

char	*ft_strmapi(char const *s, char (*f)(unsigned int, char));

static const unsigned char	*g_s;
static size_t				g_len;
static size_t				g_next;
static int					g_ok;

static char	fixed_f(unsigned int i, char c)
{
	if (i != g_next || i >= g_len || (unsigned char)c != g_s[i])
		g_ok = 0;
	g_next++;
	return ((char)(((unsigned long)(unsigned char)c + i) % 255 + 1));
}

int	main(void)
{
	char			*line;
	size_t			linecap;
	char			*f[2];
	unsigned char	*s;
	char			*res;

	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		s = dio_unhex(f[0], &g_len, 0);
		g_s = s;
		g_next = 0;
		g_ok = 1;
		res = ft_strmapi((char *)s, fixed_f);
		printf("%s\t", f[0]);
		if (res == NULL)
			printf("NULL");
		else
			dio_puthex((unsigned char *)res, strlen(res));
		printf("\t%d\n", g_ok && g_next == g_len);
		free(res);
		free(s);
	}
	free(line);
	return (0);
}
