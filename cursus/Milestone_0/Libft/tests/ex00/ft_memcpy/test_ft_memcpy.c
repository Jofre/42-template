#include <stddef.h>
#include <stdio.h>
#include <string.h>

/* ft_memcpy's fixture: each row copies into a buffer of 'X' and shows the
 * whole buffer afterwards, so a byte written outside the n asked for shows
 * too, with what the call returned ("dest" for the pointer it was handed).
 * Source and destination never overlap: man memcpy says they "must not".
 * Values are in the table's notation (\x00 is a NUL byte, \xHH any other
 * byte outside printable ASCII). */
void	*ft_memcpy(void *dest, const void *src, size_t n);

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

static const char	*who(void *ret, void *dest)
{
	if (ret == dest)
		return ("dest");
	if (ret == NULL)
		return ("NULL");
	return ("another pointer");
}

/* A 10-byte buffer of 'X' (libc's memset prepares it), copied into from
 * buf + off. */
static void	row(const char *label, size_t off, const char *src, size_t n)
{
	unsigned char	buf[10];
	void			*ret;

	memset(buf, 'X', sizeof(buf));
	ret = ft_memcpy(buf + off, src, n);
	printf("%s\tret=%s buf=", label, who(ret, buf + off));
	put_esc(buf, sizeof(buf));
	printf("\n");
}

/* 5000 bytes, every value 0..255 among them (NULs and bytes of 0x80 or
 * more included), into a block of 5001 whose every byte starts one more
 * than the source byte at its index, so no byte of it holds what it must
 * before the call: how many of the 5000 arrived, and whether the byte after
 * them still holds what it held. */
static void	big(void)
{
	static unsigned char	src[5000];
	static unsigned char	dst[5001];
	size_t					i;
	size_t					same;
	void					*ret;

	i = 0;
	while (i < sizeof(dst))
	{
		if (i < sizeof(src))
			src[i] = (unsigned char)(i * 7 + 3);
		dst[i] = (unsigned char)(i * 7 + 4);
		i++;
	}
	ret = ft_memcpy(dst, src, 5000);
	same = 0;
	i = 0;
	while (i < 5000)
	{
		same += (dst[i] == (unsigned char)(i * 7 + 3));
		i++;
	}
	printf("5000 bytes into a block of 5001 (past 4096)\tret=%s copied %zu of 5000, byte 5000 %s\n",
		who(ret, dst), same, dst[5000] == (unsigned char)(5000 * 7 + 4)
		? "kept" : "changed");
}

int	main(void)
{
	row("\"Hello\", n 5", 0, "Hello", 5);
	row("\"Hello\", n 0 (nothing to copy)", 0, "Hello", 0);
	row("\"abcdefgh\", n 3", 0, "abcdefgh", 3);
	row("\"xyz\", n 3, dest at buf + 4", 4, "xyz", 3);
	row("\"a\\0b\", n 3 (a NUL inside)", 0, "a\0b", 3);
	row("\"\\0\\0\\0\", n 3", 0, "\0\0\0", 3);
	row("bytes 0x80 0xff 0xe9 0x00 0x7f, n 5", 0, "\x80\xff\xe9\0\x7f", 5);
	big();
	return (0);
}
