/* diffio_probe.c -- a toy reader harness, linked as every c_diff reader is:
 * through //tools:diffio (//tools/tests:diffio_probe). The selftest runs it
 * to hold that library to what its malloc is for (tools/dirty_malloc.c): a
 * field a function never writes, in a block the function took from malloc,
 * does not read as zero. A check on a hand-compiled copy could not see the
 * library lose its source or its -Wl,--wrap=malloc; this one is built by the
 * rule that builds the readers. The record and its maker (diffio_probe_toy.c,
 * a file of its own so the compiler cannot see the field go unwritten) are
 * invented: no exercise has them.
 *
 * Each line read: one record made, its middle field printed SET or NULL, and
 * the record freed, so the next line's block is this one's. With the argument
 * "big": one block of 1 MiB, and whether its first byte, the byte at its
 * middle and its last byte hold the fill (FILLED) or not (LEFT) -- the fill
 * stops short of the middle of a big block, so a program pays for what it
 * uses and not for what it allocates (tools/dirty_malloc.c, HOW MUCH). */
#include "diffio.h"

typedef struct s_trio
{
	void	*a;
	void	*b;
	void	*c;
}	t_trio;

t_trio	*toy_trio_new(void *c);

static const char	*filled(unsigned char byte)
{
	return (byte == 0xa5 ? "FILLED" : "LEFT");
}

static int	big(void)
{
	unsigned char	*p;
	size_t			n;

	n = (size_t)1 << 20;
	p = (unsigned char *)malloc(n);
	if (p == NULL)
		dio_fail("cannot allocate the big block");
	printf("head %s, middle %s, tail %s\n", filled(p[0]), filled(p[n / 2]),
		filled(p[n - 1]));
	free(p);
	return (0);
}

int	main(int argc, char **argv)
{
	char	*line;
	size_t	cap;
	t_trio	*t;

	if (argc == 2 && strcmp(argv[1], "big") == 0)
		return (big());
	line = NULL;
	cap = 0;
	while (dio_getline(&line, &cap))
	{
		t = toy_trio_new(line);
		if (t == NULL)
			dio_fail("the toy could not allocate its record");
		printf("%s\n", t->b != NULL ? "SET" : "NULL");
		free(t);
	}
	free(line);
	return (0);
}
