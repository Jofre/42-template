#include <stddef.h>
#include <stdio.h>

/* ft_memset's fixture: each row fills part of a buffer that starts dirty
 * and shows the whole buffer afterwards, so a byte written outside the n
 * asked for shows too, with what the call returned ("s" for the pointer it
 * was handed). Only c in 0..255: the man page's "the constant byte c"
 * settles nothing else, and a c outside it is a target of its own. Values
 * are in the table's notation (\xHH for a byte outside printable ASCII). */
void	*ft_memset(void *s, int c, size_t n);

static void	put_esc(const unsigned char *b, size_t n)
{
	size_t	i;

	i = 0;
	while (i < n)
	{
		if (b[i] == '\\')
			printf("\\\\");
		else if (b[i] == '\n')
			printf("\\n");
		else if (b[i] == '\t')
			printf("\\t");
		else if (b[i] < 0x20 || b[i] > 0x7e)
			printf("\\x%02x", b[i]);
		else
			putchar(b[i]);
		i++;
	}
}

static const char	*who(void *ret, void *s)
{
	if (ret == s)
		return ("s");
	if (ret == NULL)
		return ("NULL");
	return ("another pointer");
}

/* A 12-byte buffer of 'X', filled from buf + off. */
static void	row(const char *label, size_t off, int c, size_t n)
{
	unsigned char	buf[12] = {'X', 'X', 'X', 'X', 'X', 'X',
		'X', 'X', 'X', 'X', 'X', 'X'};
	void			*ret;

	ret = ft_memset(buf + off, c, n);
	printf("%s\tret=%s buf=", label, who(ret, buf + off));
	put_esc(buf, sizeof(buf));
	printf("\n");
}

/* n = 5000 into a block of 5001 that starts as a pattern of capital
 * letters: how many of the 5000 hold c, and whether the byte after them
 * still holds what it held. */
static void	big(void)
{
	static unsigned char	buf[5001];
	size_t					i;
	size_t					set;
	void					*ret;

	i = 0;
	while (i < sizeof(buf))
	{
		buf[i] = (unsigned char)('A' + i % 26);
		i++;
	}
	ret = ft_memset(buf, 'z', 5000);
	set = 0;
	i = 0;
	while (i < 5000)
		set += (buf[i++] == 'z');
	printf("'z', n 5000, a block of 5001 (past 4096)\tret=%s set %zu of 5000, byte 5000 %s\n",
		who(ret, buf), set, buf[5000] == (unsigned char)('A' + 5000 % 26)
		? "kept" : "changed");
}

int	main(void)
{
	row("'a', n 5", 0, 'a', 5);
	row("'a', n 0 (nothing to fill)", 0, 'a', 0);
	row("'a', n 12 (the whole buffer)", 0, 'a', 12);
	row("'*', n 3, s at buf + 4", 4, '*', 3);
	row("0, n 3 (the NUL byte)", 0, 0, 3);
	row("128 (0x80), n 4", 0, 128, 4);
	row("233 (0xe9), n 4", 0, 233, 4);
	row("255 (0xff), n 12", 0, 255, 12);
	big();
	return (0);
}
