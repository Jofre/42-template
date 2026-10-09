/* Live-differential reader harness for ft_strs_to_tab.
 *
 * Line: <n>\t<hex-av-0>...\t<hex-av-n-1>\t<rendering>
 *
 * Decodes the n hex fields into a real char *av[], calls ft_strs_to_tab(n, av),
 * then reprints the input fields and its own rendering of the returned array.
 * The reference emits the identical rendering, so a correct ft_strs_to_tab
 * makes the two streams byte-identical. See tools/diffio.h.
 *
 * WHY A RENDERING RATHER THAN THE ARRAY. tools/rust_diff.sh reports BY LINE --
 * "it died at or after case N", "feed one of these to your harness on its own"
 * -- so a case that spans lines makes every one of those messages wrong. One
 * case, one line.
 *
 * The rendering is `size/alias/hex-of-copy` per entry, joined with `,`, then
 * `;term=1`. Each part is a property the subject states:
 *
 *   size   "size being the length of the string". The student computes this,
 *          which is why the corpus is full of bytes >= 0x80: a length scan
 *          that treats any byte comparing as negative as the end of the string
 *          stops at the first of them, because a plain char is signed here.
 *   alias  "str being the string" -- the pointer handed in, not a copy of it.
 *          `a` when tab[i].str == av[i], `-` otherwise.
 *   copy   compared by BYTES, over `size` of them.
 *   term   "the returned array should be ... its last element's str set to 0".
 *
 * A NULL return renders as the single word NULL, so a deliverable that gives up
 * diverges on its first case instead of segfaulting this harness.
 *
 * THE COPY IS PRINTED OVER THE STUDENT'S OWN size, not over strlen(copy). If
 * the two disagree the size field already differs and the case is red either
 * way -- but reading strlen(copy) of a copy that was never terminated would
 * walk off the block and take the harness down with it, turning a wrong answer
 * into a crash report. dio_caplen bounds it.
 */
#include "diffio.h"
#include "ft_stock_str.h"

struct s_stock_str	*ft_strs_to_tab(int ac, char **av);

/* Every array here is sized from the line itself, and the line is read whole
 * however long it is (dio_getline). The corpus holds cases of hundreds of
 * strings, past every capacity a student might pick (finding 041). A fixed
 * MAXF of 64 here folded every field past the 64th into one, so such a case
 * read as malformed and printed nothing: a divergence no function could
 * avoid. And av is an exact-size heap block, so under ASan (ex04_diff_asan)
 * reading av[ac] is caught at its edge. */
int	main(void)
{
	char				*line;
	size_t				cap;
	char				**f;
	char				**av;
	unsigned char		**raw;
	struct s_stock_str	*tab;
	int					nf;
	int					n;
	int					i;

	line = NULL;
	cap = 0;
	while (dio_getline(&line, &cap))
	{
		nf = dio_nfields(line);
		f = (char **)malloc(sizeof(char *) * (size_t)nf);
		if (f == NULL)
			return (2);
		nf = dio_split(line, f, nf);
		n = atoi(f[0]);
		if (nf < 2 || n < 0 || n + 2 > nf)
		{
			free(f);
			continue ;
		}
		av = (char **)malloc(sizeof(char *) * (size_t)n);
		raw = (unsigned char **)malloc(sizeof(unsigned char *) * (size_t)(n + 1));
		if ((av == NULL && n > 0) || raw == NULL)
			return (2);
		i = 0;
		while (i < n)
		{
			raw[i] = dio_unhex(f[i + 1], NULL, 1);
			av[i] = (char *)raw[i];
			i++;
		}
		printf("%s", f[0]);
		i = 0;
		while (i < n)
		{
			printf("\t%s", f[i + 1]);
			i++;
		}
		printf("\t");
		tab = ft_strs_to_tab(n, av);
		if (!tab)
			printf("NULL");
		else
		{
			i = 0;
			while (i < n)
			{
				if (i)
					printf(",");
				printf("%d/%c/", tab[i].size,
					tab[i].str == av[i] ? 'a' : '-');
				if (tab[i].copy && tab[i].size >= 0)
					dio_puthex((unsigned char *)tab[i].copy,
						dio_caplen((unsigned char *)tab[i].copy,
							(size_t)tab[i].size));
				i++;
			}
			printf(";term=%d", tab[n].str == 0);
			/* What the function handed back is released here, as its caller
			 * must: each copy, then the array (the test_ fixture frees them the
			 * same way). Left allocated, every case's copies stayed live for
			 * the whole run, and the perf layer, which replays this harness,
			 * told every correct answer that something allocated per case was
			 * never released (finding 095). A copy that is the string handed
			 * in is not the function's to give, and is not freed twice. */
			i = 0;
			while (i < n)
			{
				if (tab[i].copy != av[i] && tab[i].copy != tab[i].str)
					free(tab[i].copy);
				i++;
			}
			free(tab);
		}
		printf("\n");
		i = 0;
		while (i < n)
		{
			free(raw[i]);
			i++;
		}
		free(raw);
		free(av);
		free(f);
	}
	free(line);
	return (0);
}
