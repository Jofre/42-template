#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ex00_ft_substr_start_past_end_output: a start past the end of s, a case
 * ft_substr's box (p.10) does not mention. This target tests one reading of
 * it, at strict (the BUILD file says why), and its hint says which.
 *
 * Each row prints the result between quotes, raw (every input here keeps the
 * answer printable), or NULL, and frees it before the row's newline, so a
 * crash in free() marks its own row. The row past 4096 bytes comes last. */
char	*ft_substr(char const *s, unsigned int start, size_t len);

static void	test(const char *label, const char *s, unsigned int start,
		size_t len)
{
	char	*r;

	r = ft_substr(s, start, len);
	printf("%s\t", label);
	if (r == NULL)
		printf("NULL");
	else
		printf("\"%s\"", r);
	free(r);
	printf("\n");
}

int	main(void)
{
	char	*s;
	size_t	i;

	test("\"Hello, 42!\", 11, 5", "Hello, 42!", 11, 5);
	test("\"Hello, 42!\", 11, 0", "Hello, 42!", 11, 0);
	test("\"Hello, 42!\", 100, 3", "Hello, 42!", 100, 3);
	test("\"Hello, 42!\", UINT_MAX, SIZE_MAX", "Hello, 42!", UINT_MAX,
		SIZE_MAX);
	test("\"\", 1, 0", "", 1, 0);
	test("\"\", 1, 5", "", 1, 5);
	test("0xe9 't' 0xe9, 4, 1", "\xe9t\xe9", 4, 1);
	s = malloc(5001);
	if (s == NULL)
		return (1);
	i = 0;
	while (i < 5000)
	{
		s[i] = (char)('a' + i % 26);
		i++;
	}
	s[5000] = '\0';
	test("5000-byte s, 5001, 10", s, 5001, 10);
	free(s);
	return (0);
}
