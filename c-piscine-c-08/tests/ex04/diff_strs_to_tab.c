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
 *          which is why the corpus is full of bytes >= 0x80: a length loop
 *          written `while (str[i] > 0)` stops at the first of them, because a
 *          plain char is signed.
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

#define MAXF 64

struct s_stock_str	*ft_strs_to_tab(int ac, char **av);

int	main(void)
{
	char				line[65536];
	char				*f[MAXF];
	char				*av[MAXF];
	unsigned char		*raw[MAXF];
	struct s_stock_str	*tab;
	int					nf;
	int					n;
	int					i;

	while (dio_line(line, sizeof(line)))
	{
		nf = dio_split(line, f, MAXF);
		if (nf < 2)
			continue ;
		n = atoi(f[0]);
		if (n < 0 || n + 2 > nf)
			continue ;
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
		}
		printf("\n");
		i = 0;
		while (i < n)
		{
			free(raw[i]);
			i++;
		}
	}
	return (0);
}
