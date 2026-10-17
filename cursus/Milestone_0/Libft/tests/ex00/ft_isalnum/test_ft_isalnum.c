#include <stdio.h>

/* ft_isalnum over EVERY value it is defined for. Its man page (man 3 isalnum)
 * says c "must have the value of an unsigned char or EOF", so the domain is
 * EOF and 0..255, 257 values, and all of them are here: there is no corpus
 * to fuzz (no c_diff, SMALL-INPUT-SPACE in BUILD.bazel).
 *
 * One row per range of codes, the ranges cut where a class of man ascii
 * starts or ends. A row prints one result per code, in order: the digit 0
 * or 1, or, for any other int, the int itself in brackets ("[1024]"). p.8
 * names the two values a classification function returns, so a code that
 * gives a third shows as itself rather than as a "true".
 *
 * Declares only the prototype it calls (tests/ex00/prototype.h has all). */
int		ft_isalnum(int c);

static void	row(const char *label, int lo, int hi)
{
	int	c;
	int	r;

	printf("%s\t", label);
	c = lo;
	while (c <= hi)
	{
		r = ft_isalnum(c);
		if (r == 0 || r == 1)
			printf("%d", r);
		else
			printf("[%d]", r);
		c++;
	}
	printf("\n");
}

int	main(void)
{
	row("EOF", EOF, EOF);
	row("0x00..0x1f (control codes)", 0x00, 0x1f);
	row("0x20..0x2f ' '..'/'", 0x20, 0x2f);
	row("0x30..0x39 '0'..'9'", 0x30, 0x39);
	row("0x3a..0x40 ':'..'@'", 0x3a, 0x40);
	row("0x41..0x5a 'A'..'Z'", 0x41, 0x5a);
	row("0x5b..0x60 '['..'`'", 0x5b, 0x60);
	row("0x61..0x7a 'a'..'z'", 0x61, 0x7a);
	row("0x7b..0x7e '{'..'~'", 0x7b, 0x7e);
	row("0x7f (DEL)", 0x7f, 0x7f);
	row("0x80..0xbf", 0x80, 0xbf);
	row("0xc0..0xdf", 0xc0, 0xdf);
	row("0xe0..0xfe", 0xe0, 0xfe);
	row("0xff", 0xff, 0xff);
	return (0);
}
