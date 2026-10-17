#include <stddef.h>
#include <stdio.h>
#include <string.h>

/* ft_bzero's fixture: each row zeroes part of a buffer that starts dirty
 * and shows the whole buffer afterwards, so a byte written outside the n
 * asked for shows too. Values are in the table's notation (\x00 is a NUL
 * byte, \xHH any other byte outside printable ASCII). */
void	ft_bzero(void *s, size_t n);

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

/* A 10-byte buffer holding `fill` in every byte (libc's memset prepares
 * it), zeroed from buf + off. */
static void	row(const char *label, unsigned char fill, size_t off, size_t n)
{
	unsigned char	buf[10];

	memset(buf, fill, sizeof(buf));
	ft_bzero(buf + off, n);
	printf("%s\tbuf=", label);
	put_esc(buf, sizeof(buf));
	printf("\n");
}

/* n = 5000 into a block of 5001 that starts as a pattern of capital
 * letters: how many of the 5000 are 0, and whether the byte after them
 * still holds what it held. */
static void	big(void)
{
	static unsigned char	buf[5001];
	size_t					i;
	size_t					zero;

	i = 0;
	while (i < sizeof(buf))
	{
		buf[i] = (unsigned char)('A' + i % 26);
		i++;
	}
	ft_bzero(buf, 5000);
	zero = 0;
	i = 0;
	while (i < 5000)
		zero += (buf[i++] == 0);
	printf("n 5000, a block of 5001 (past 4096)\tzeroed %zu of 5000, byte 5000 %s\n",
		zero, buf[5000] == (unsigned char)('A' + 5000 % 26) ? "kept" : "changed");
}

int	main(void)
{
	row("'X' x 10, n 5", 'X', 0, 5);
	row("'X' x 10, n 0 (nothing to erase)", 'X', 0, 0);
	row("'X' x 10, n 10 (the whole buffer)", 'X', 0, 10);
	row("'X' x 10, n 3, s at buf + 4", 'X', 4, 3);
	row("0xe9 x 10, n 4", 0xe9, 0, 4);
	big();
	return (0);
}
