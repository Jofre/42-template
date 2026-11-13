#include <stddef.h>
#include <stdio.h>

/* ft_memcmp's fixture: each row compares two blocks and shows the SIGN of
 * the result (negative, zero or positive), which is all man memcmp says
 * about it: "an integer less than, equal to, or greater than zero". */
int	ft_memcmp(const void *s1, const void *s2, size_t n);

static void	row(const char *label, const void *a, const void *b, size_t n)
{
	int	r;

	r = ft_memcmp(a, b, n);
	if (r < 0)
		printf("%s\tnegative\n", label);
	else if (r > 0)
		printf("%s\tpositive\n", label);
	else
		printf("%s\tzero\n", label);
}

/* Two blocks of 5000 bytes holding the same pattern, NULs and bytes of 0x80
 * or more among them; then the last byte of the first one made 0xe9 and of
 * the second 0x10. */
static void	big(void)
{
	static unsigned char	a[5000];
	static unsigned char	b[5000];
	size_t					i;

	i = 0;
	while (i < sizeof(a))
	{
		a[i] = (unsigned char)(i * 7 + 3);
		b[i] = (unsigned char)(i * 7 + 3);
		i++;
	}
	row("5000 equal bytes, n 5000 (past 4096)", a, b, 5000);
	a[4999] = 0xe9;
	b[4999] = 0x10;
	row("5000 bytes, the last 0xe9 vs 0x10, n 5000 (past 4096)", a, b, 5000);
}

int	main(void)
{
	row("\"abc\" vs \"abc\", n 3", "abc", "abc", 3);
	row("\"abc\" vs \"abd\", n 3", "abc", "abd", 3);
	row("\"abd\" vs \"abc\", n 3", "abd", "abc", 3);
	row("\"abc\" vs \"abd\", n 2", "abc", "abd", 2);
	row("\"a\" vs \"b\", n 0", "a", "b", 0);
	row("\"a\\0b\" vs \"a\\0c\", n 3", "a\0b", "a\0c", 3);
	row("byte 0x80 vs byte 0x01, n 1", "\x80", "\x01", 1);
	row("byte 0x01 vs byte 0xff, n 1", "\x01", "\xff", 1);
	row("byte 0xff vs a NUL byte, n 1", "\xff", "\0", 1);
	big();
	return (0);
}
