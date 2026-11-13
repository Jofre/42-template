#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ft_calloc's fixture. A block row asks for nmemb x size bytes and says
 * whether every one of them is 0; the block it gets back is likely the one
 * the row has just filled with 0xa5 and freed, so a block left as malloc
 * hands it over shows. A zero row asks with nmemb or size 0, which the
 * subject settles (p.8: "calloc() returns a unique pointer value that can
 * be successfully passed to free()"), and says whether the pointer is NULL;
 * a row of its own then frees each of those pointers once. An overflow row
 * asks for more than a size_t can count. Every size comes from SIZE_MAX, so
 * the rows mean the same on a 32-bit build. Every row frees what it got
 * BEFORE it prints, so a crash in free() is marked on the row whose block
 * it was. */
void	*ft_calloc(size_t nmemb, size_t size);

/* Leave a freed block of `total` bytes, every one 0xa5, for the next
 * allocation of that size to find. */
static void	dirty(size_t total)
{
	unsigned char	*m;

	m = malloc(total);
	if (m == NULL)
		return ;
	memset(m, 0xa5, total);
	free(m);
}

static void	block(const char *label, size_t nmemb, size_t size)
{
	unsigned char	*p;
	size_t			i;
	size_t			total;
	size_t			nonzero;

	total = nmemb * size;
	dirty(total);
	p = ft_calloc(nmemb, size);
	if (p == NULL)
	{
		printf("%s\tNULL\n", label);
		return ;
	}
	nonzero = 0;
	i = 0;
	while (i < total)
		nonzero += (p[i++] != 0);
	free(p);
	if (nonzero == 0)
		printf("%s\t%zu bytes, every one 0\n", label, total);
	else
		printf("%s\t%zu bytes, NOT all 0\n", label, total);
}

static void	*zero(const char *label, size_t nmemb, size_t size)
{
	void	*p;

	p = ft_calloc(nmemb, size);
	printf("%s\t%s\n", label, p ? "a pointer, not NULL" : "NULL");
	return (p);
}

/* nmemb * size is more than SIZE_MAX: nothing to look at but the pointer. */
static void	overflow(const char *label, size_t nmemb, size_t size)
{
	void	*p;
	int		got;

	p = ft_calloc(nmemb, size);
	got = (p != NULL);
	free(p);
	printf("%s\t%s\n", label, got ? "a pointer, not NULL" : "NULL");
}

int	main(void)
{
	void	*z[3];
	size_t	half;

	block("3 x 4", 3, 4);
	block("1 x 7", 1, 7);
	z[0] = zero("0 x 5 (nmemb 0)", 0, 5);
	z[1] = zero("5 x 0 (size 0)", 5, 0);
	z[2] = zero("0 x 0", 0, 0);
	printf("0 x 5, 5 x 0 and 0 x 0: three different pointers\t%s\n",
		(z[0] && z[1] && z[2] && z[0] != z[1] && z[0] != z[2]
			&& z[1] != z[2]) ? "yes" : "no");
	/* Each pointer once: a value handed back twice is freed only the first
	 * time, so the row above has already said so and nothing here crashes on
	 * it. */
	free(z[0]);
	if (z[1] != z[0])
		free(z[1]);
	if (z[2] != z[0] && z[2] != z[1])
		free(z[2]);
	printf("0 x 5, 5 x 0 and 0 x 0: each passed to free()\tdone\n");
	half = (size_t)1 << (sizeof(size_t) * 4);
	overflow("(SIZE_MAX / 2 + 2) x 2 (more than SIZE_MAX)",
		SIZE_MAX / 2 + 2, 2);
	overflow("SIZE_MAX x SIZE_MAX", SIZE_MAX, SIZE_MAX);
	overflow("h x h, h = 2^(half the bits of size_t), so h x h = SIZE_MAX + 1",
		half, half);
	block("1 x 5000 (past 4096)", 1, 5000);
	block("5000 x 1 (past 4096)", 5000, 1);
	block("4097 x 3 (past 4096)", 4097, 3);
	return (0);
}
