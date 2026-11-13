/* The escaped-value notation, written once for every output fixture.
 *
 * tools/diff_output.sh --escaped-values (its HARNESS-ESCAPED VALUES) reads a
 * value a test program wrote as: \\ a backslash, \n a line break, \t a tab,
 * \xHH in lowercase hex any other byte outside printable ASCII, every other
 * byte as it is. A fixture whose value holds a byte that cannot travel raw
 * writes it so, and its c_function says escaped_values = True. Each one used
 * to carry its own writer of it, and some wrote only part of it: C 03 ex05's
 * printed dest raw in one place and never doubled a backslash in another,
 * so a raw backslash and an n read as a line-break mark.
 *
 * Both halves of the rule are libc's, as rush_capture.h's are: isprint() is
 * exactly 0x20..0x7e in the "C" locale, the one these programs run in (none
 * calls setlocale), and the hex form is printf's "%02x".
 *
 * Linked as //tools:notation, a library of headers alone (this one and
 * fd_capture.h, which writes its rows in it), by every output fixture
 * (tools/defs_test.bzl, _output_fixture_binary), and staged
 * beside every fixture a runner compiles itself (ilp32_test.sh,
 * method_check.sh, header_check.sh, ref_compare.sh). It links nothing: no
 * dirty_malloc, no --wrap=malloc, so the memcheck layers may run what
 * includes it.
 * //tools:conventions counts an include of it, or a call of nt_*, as a
 * program writing escapes, which its c_function must then declare.
 *
 * Every function is static inline, so a fixture that calls only some of
 * them still builds under -Wall -Wextra -Werror. */
#ifndef NOTATION_H
# define NOTATION_H

# include <ctype.h>
# include <stdio.h>
# include <stdlib.h>

/* One byte, c read as an unsigned char. */
static inline void	nt_putc(int c)
{
	unsigned char	b;

	b = (unsigned char)c;
	if (b == '\\')
		printf("\\\\");
	else if (b == '\n')
		printf("\\n");
	else if (b == '\t')
		printf("\\t");
	else if (isprint(b))
		putchar(b);
	else
		printf("\\x%02x", b);
}

/* The n bytes at b, NULs included. */
static inline void	nt_put(const void *b, size_t n)
{
	const unsigned char	*p;
	size_t				i;

	p = (const unsigned char *)b;
	i = 0;
	while (i < n)
		nt_putc(p[i++]);
}

/* The bytes of s up to its terminator. */
static inline void	nt_puts(const char *s)
{
	while (*s != '\0')
		nt_putc(*s++);
}

/* A returned string as a cell: NULL, or the string between quotes. Then it
 * is freed, before the row's newline the caller prints, so a crash in
 * free() marks this row and not the next. */
static inline void	nt_cell(char *r_to_free)
{
	if (r_to_free == NULL)
		printf("NULL");
	else
	{
		printf("\"");
		nt_puts(r_to_free);
		printf("\"");
	}
	free(r_to_free);
}

#endif
