/* Live-differential reader harness for ft_list_push_strs.
 * Line: <strs>\t<result>. strs = the strings, each as lowercase hex,
 * comma-joined, none of them empty; read into the char ** the subject hands
 * the function (dio_hex_list: the strings, then a NULL after the last), and
 * the function is called once with their number as size. Reprints <strs>\t,
 * then the resulting list's data, head first, each node's string as hex,
 * comma-separated. See tools/diffio.h. */
#include "ft_list.h"
#include "diffio.h"

t_list	*ft_list_push_strs(int size, char **strs);

/* Serialise the list's strings as hex csv, reading at most `cap` nodes: the
 * case's size plus one, so a list one node too long still prints whole. A
 * list still going after that -- longer than size can explain, or looping
 * back on itself -- gets a marker instead of an endless walk, and a node whose
 * data is NULL a marker instead of a crash in strlen. Each node read is
 * recorded in `seen`, and the count returned, so the caller can free them
 * without walking the list a second time. */
static int	ser_hex(t_list *l, int cap, t_list **seen)
{
	int	k;

	k = 0;
	while (l && k < cap)
	{
		if (k > 0)
			printf(",");
		if (l->data == NULL)
			printf("(a node whose data is NULL)");
		else
			dio_puthex((unsigned char *)l->data, strlen((char *)l->data));
		seen[k++] = l;
		l = l->next;
	}
	if (l)
		printf(",...(list still going after %d nodes)", cap);
	printf("\n");
	return (k);
}

/* Free the nodes ser_hex recorded, after each case: the nodes only, since
 * their data points at the strings the harness owns and frees with
 * dio_free_list. A node is recorded twice only when the list loops back on
 * itself; it is freed at its first slot only, so that mistake stays a
 * readable wrong answer instead of turning into a double-free crash. */
static void	free_seen(t_list **seen, int k)
{
	int	i;
	int	j;

	i = 0;
	while (i < k)
	{
		j = 0;
		while (j < i && seen[j] != seen[i])
			j++;
		if (j == i)
			free(seen[i]);
		i++;
	}
}

int	main(void)
{
	char	*line;
	size_t	cap;
	char	*f[2];
	char	**strs;
	int		n;
	t_list	*begin;
	t_list	**seen;

	/* A line of any length (tools/diffio.h): the corpus holds lists of
	 * hundreds and thousands of strings. */
	line = NULL;
	cap = 0;
	while (dio_getline(&line, &cap))
	{
		dio_split(line, f, 2);
		strs = dio_hex_list(f[0], &n);
		seen = (t_list **)dio_alloc((size_t)(n + 1), sizeof(t_list *));
		begin = ft_list_push_strs(n, strs);
		printf("%s\t", f[0]);
		free_seen(seen, ser_hex(begin, n + 1, seen));
		free(seen);
		dio_free_list(strs, n);
	}
	free(line);
	return (0);
}
