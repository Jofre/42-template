/* Shared helpers for live-differential reader harnesses (grader-side test infra).
 *
 * A reader harness reads the Rust reference's cases from stdin, decodes the
 * hex-encoded input fields, runs the student's function, and reprints the input
 * fields followed by the student's result — so tools/rust_diff.sh can byte-diff
 * it against the reference. These are test readers, not submissions: they use
 * libc freely and need not be norm-compliant.
 *
 * All helpers are `static inline` so a harness that uses only some of them still
 * compiles clean under -Wall -Wextra -Werror (no -Wunused-function). */
#ifndef DIFFIO_H
#define DIFFIO_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static inline int	dio_hv(int c)
{
	if (c >= '0' && c <= '9')
		return (c - '0');
	if (c >= 'a' && c <= 'f')
		return (c - 'a' + 10);
	if (c >= 'A' && c <= 'F')
		return (c - 'A' + 10);
	return (0);
}

/* Decode even-length hex string `h` into a fresh calloc'd buffer with `pad`
 * extra zero bytes after the decoded content (so it can double as a NUL-
 * terminated C string, or as a sized dest buffer). *len = decoded byte count. */
static inline unsigned char	*dio_unhex(const char *h, size_t *len, size_t pad)
{
	size_t			n;
	size_t			i;
	unsigned char	*b;

	n = strlen(h) / 2;
	b = (unsigned char *)calloc(n + pad + 1, 1);
	i = 0;
	while (i < n)
	{
		b[i] = (unsigned char)((dio_hv(h[2 * i]) << 4) | dio_hv(h[2 * i + 1]));
		i++;
	}
	if (len)
		*len = n;
	return (b);
}

/* Print bytes b[0..n) as lowercase hex, no newline. */
static inline void	dio_puthex(const unsigned char *b, size_t n)
{
	size_t	i;

	i = 0;
	while (i < n)
	{
		printf("%02x", b[i]);
		i++;
	}
}

/* Length of a NUL-terminated region, but never scanning past `cap` bytes
 * (safe for buffers a correct impl may leave unterminated within `cap`). */
static inline size_t	dio_caplen(const unsigned char *b, size_t cap)
{
	size_t	i;

	i = 0;
	while (i < cap && b[i] != '\0')
		i++;
	return (i);
}

/* Read one line from stdin into buf (newline stripped). Returns 1, or 0 at EOF. */
static inline int	dio_line(char *buf, int cap)
{
	if (!fgets(buf, cap, stdin))
		return (0);
	buf[strcspn(buf, "\n")] = '\0';
	return (1);
}

/* Split `line` in place on tabs into fields[0..maxf); returns field count. */
static inline int	dio_split(char *line, char **fields, int maxf)
{
	int		n;
	char	*p;

	n = 0;
	p = line;
	fields[n++] = p;
	while (n < maxf && (p = strchr(p, '\t')))
	{
		*p++ = '\0';
		fields[n++] = p;
	}
	return (n);
}

#endif
