#include <stddef.h>
#include <stdio.h>
#include <string.h>

/* ft_memmove's fixture: most rows move bytes inside ONE buffer, "123456789"
 * followed by an 'X', where src and dest overlap, and show the whole buffer
 * afterwards with what the call returned ("dest" for the pointer it was
 * handed). Values are in the table's notation (\x00 is a NUL byte, \xHH any
 * other byte outside printable ASCII). */
void	*ft_memmove(void *dest, const void *src, size_t n);

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

/* The 10-byte buffer "123456789X" (no NUL), or `init` when one is given,
 * which libc's memcpy puts in place: n bytes moved from buf + s to buf + d. */
static void	row(const char *label, const char *init, size_t d, size_t s,
	size_t n)
{
	unsigned char	buf[10];
	void			*ret;

	memcpy(buf, init ? init : "123456789X", sizeof(buf));
	ret = ft_memmove(buf + d, buf + s, n);
	printf("%s\tret=%s buf=", label, who(ret, buf + d));
	put_esc(buf, sizeof(buf));
	printf("\n");
}

/* Two separate buffers: "Hello" into 'X' x 10 (libc's memset prepares
 * it). */
static void	apart(void)
{
	unsigned char	buf[10];
	void			*ret;

	memset(buf, 'X', sizeof(buf));
	ret = ft_memmove(buf, "Hello", 5);
	printf("\"Hello\" into another buffer, n 5\tret=%s buf=", who(ret, buf));
	put_esc(buf, sizeof(buf));
	printf("\n");
}

/* A block of 5002 bytes, byte i holding (i * 7 + 3) % 256 -- no two
 * neighbours equal, NULs and bytes of 0x80 or more among them -- and 5000
 * of them moved one place up (dest = src + 1) or one place down (src =
 * dest + 1). Counts the bytes that hold what they must, by construction:
 * after a move up, byte i + 1 holds what byte i held; after a move down,
 * byte i holds what byte i + 1 held. The bytes outside the 5000 written
 * must keep what they held. */
static void	big(int up)
{
	static unsigned char	buf[5002];
	size_t					i;
	size_t					same;
	int						kept;
	void					*ret;

	i = 0;
	while (i < sizeof(buf))
	{
		buf[i] = (unsigned char)(i * 7 + 3);
		i++;
	}
	if (up)
		ret = ft_memmove(buf + 1, buf, 5000);
	else
		ret = ft_memmove(buf, buf + 1, 5000);
	same = 0;
	i = 0;
	while (i < 5000)
	{
		if (up)
			same += (buf[i + 1] == (unsigned char)(i * 7 + 3));
		else
			same += (buf[i] == (unsigned char)((i + 1) * 7 + 3));
		i++;
	}
	if (up)
		kept = (buf[0] == 3 && buf[5001] == (unsigned char)(5001 * 7 + 3));
	else
		kept = (buf[5000] == (unsigned char)(5000 * 7 + 3)
				&& buf[5001] == (unsigned char)(5001 * 7 + 3));
	printf("%s\tret=%s moved %zu of 5000, the rest %s\n", up
		? "5000 bytes one place up, overlapping (past 4096)"
		: "5000 bytes one place down, overlapping (past 4096)",
		who(ret, up ? buf + 1 : buf), same, kept ? "kept" : "changed");
}

int	main(void)
{
	apart();
	row("dest = buf + 2, src = buf, n 5", NULL, 2, 0, 5);
	row("dest = buf, src = buf + 2, n 5", NULL, 0, 2, 5);
	row("dest = src = buf + 1, n 5", NULL, 1, 1, 5);
	row("dest = buf + 2, src = buf, n 0", NULL, 2, 0, 0);
	row("dest = buf + 1, src = buf, n 8", NULL, 1, 0, 8);
	row("dest = buf, src = buf + 1, n 8", NULL, 0, 1, 8);
	row("'a' 0x00 0xe9 0xff 0x00 'b', dest = buf + 2, src = buf, n 4",
		"a\0\xe9\xff\0bXXXX", 2, 0, 4);
	row("'a' 0x00 0xe9 0xff 0x00 'b', dest = buf, src = buf + 2, n 4",
		"a\0\xe9\xff\0bXXXX", 0, 2, 4);
	big(1);
	big(0);
	return (0);
}
