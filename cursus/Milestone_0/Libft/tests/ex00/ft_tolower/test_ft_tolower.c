#include <stdio.h>

/* ft_tolower over EVERY value it is defined for. Its man page (man 3 tolower)
 * says "If c is neither an unsigned char value nor EOF, the behavior of
 * these functions is undefined.", so the domain is EOF and 0..255, 257
 * values, and all of them are here: there is no corpus to fuzz (no c_diff,
 * SMALL-INPUT-SPACE in BUILD.bazel).
 *
 * One row per range of codes, the ranges cut where a class of man ascii
 * starts or ends. A row prints one result per code, in order. A result that
 * is a byte (0..255) is shown as that byte, in the notation diff_output.sh
 * reads (escaped_values in BUILD.bazel): a backslash is "\\", a tab "\t", a
 * line break "\n", any other byte outside printable ASCII "\xHH". Any other
 * int, EOF included, is shown as itself in brackets ("[-1]").
 *
 * Declares only the prototype it calls (tests/ex00/prototype.h has all). */
int		ft_tolower(int c);

static void	show(int r)
{
	if (r < 0 || r > 255)
		printf("[%d]", r);
	else if (r == '\\')
		printf("\\\\");
	else if (r == '\t')
		printf("\\t");
	else if (r == '\n')
		printf("\\n");
	else if (r < 0x20 || r > 0x7e)
		printf("\\x%02x", r);
	else
		printf("%c", r);
}

static void	row(const char *label, int lo, int hi)
{
	int	c;

	printf("%s\t", label);
	c = lo;
	while (c <= hi)
	{
		show(ft_tolower(c));
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
