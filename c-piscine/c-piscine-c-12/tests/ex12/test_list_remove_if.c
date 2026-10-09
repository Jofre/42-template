#include "ft_list.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void	ft_list_remove_if(t_list **begin_list, void *data_ref,
			int (*cmp)(), void (*free_fct)(void *));

/* Prints "<label>\t<value>" so tools/diff_output.sh (run with --labeled) can
 * show each row in its own column. Per case: what survived, one row per node;
 * how many times free_fct was called; what it was given; and, once at the
 * end, whether cmp was always called the way the subject writes it.
 *
 * Every element's data is its own strdup'd string, registered in g_data. The
 * free_fct handed to the function RECORDS what it is given and frees nothing,
 * so a call on the wrong pointer is a row of the table rather than a crash;
 * the harness frees every string itself once the case is over. The nodes the
 * function removes are its own to free, with the free the subject allows. */
static char	*g_data[8];
static int	g_gone[8];
static int	g_n;
static int	g_calls;
static int	g_stray;
static int	g_twice;
static void	*g_ref;
static int	g_swapped;

/* The comparator handed to the function. It compares the strings with libc
 * strcmp, which a test is free to use, and notes a call whose arguments are
 * not the subject's (*cmp)(list_ptr->data, data_ref): the reference the test
 * passed second, and one of the list's data first. The comparison it returns
 * is the same either way round, so a swapped call changes only that row. */
static int	cmp_str(void *a, void *b)
{
	int	i;
	int	known;

	known = 0;
	i = 0;
	while (i < g_n)
		if (g_data[i++] == a)
			known = 1;
	if (b != g_ref || !known)
		g_swapped = 1;
	return (strcmp((char *)a, (char *)b));
}

static void	record_free(void *p)
{
	int	i;

	g_calls++;
	i = 0;
	while (i < g_n && g_data[i] != p)
		i++;
	if (i == g_n)
		g_stray++;
	else if (g_gone[i]++)
		g_twice++;
}

/* The list the function is handed, built by construction: n nodes, node i
 * holding its own strdup'd copy of arr[i] and linked to node i + 1 by index;
 * calloc leaves the last node's next NULL. Every node and every string is its
 * own heap block, because the function releases the elements it removes one
 * at a time, so none of them may share a block. */
static t_list	*build(char **arr, int n)
{
	t_list	*node[8];
	int		i;

	g_n = n;
	g_calls = 0;
	g_stray = 0;
	g_twice = 0;
	i = 0;
	while (i < n)
	{
		node[i] = calloc(1, sizeof(t_list));
		g_data[i] = strdup(arr[i]);
		g_gone[i] = 0;
		node[i]->data = g_data[i];
		i++;
	}
	i = 0;
	while (i + 1 < n)
	{
		node[i]->next = node[i + 1];
		i++;
	}
	if (n == 0)
		return (NULL);
	return (node[0]);
}

/* Print what survived, one row per node, reading at most `cap` nodes -- the
 * list's length before the call, plus one -- and recording each node reached;
 * then free the survivors' nodes from that record. A list still going after
 * `cap` nodes can only be looping back on itself, and gets a row saying so
 * instead of an endless run; its repeated node is freed at its first slot
 * only, so that mistake stays a readable wrong answer instead of turning into
 * a double-free crash. */
static void	show_nodes(char *label, t_list *l, int cap)
{
	t_list	*seen[9];
	int		k;
	int		i;
	int		j;

	if (!l)
		printf("%s: nodes left\tnone\n", label);
	k = 0;
	while (l && k < cap)
	{
		printf("%s: node %d\t%s\n", label, k + 1, (char *)l->data);
		seen[k++] = l;
		l = l->next;
	}
	if (l)
		printf("%s: the list ends\tno, still going after %d nodes\n",
			label, cap);
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

/* What free_fct was given, against the elements that had to go: the ones
 * whose string equals the target, counted from the case's own data. Compared
 * as a set -- the order of the calls is the function's business. */
static void	show_frees(char *label, char **arr, char *target)
{
	int	i;
	int	want;
	int	missed;
	int	survivor;

	want = 0;
	missed = 0;
	survivor = 0;
	i = 0;
	while (i < g_n)
	{
		if (strcmp(arr[i], target) == 0)
			want++;
		if (strcmp(arr[i], target) == 0 && !g_gone[i])
			missed++;
		if (strcmp(arr[i], target) != 0 && g_gone[i])
			survivor++;
		i++;
	}
	printf("%s: free_fct calls\t%d\n", label, g_calls);
	if (g_stray)
		printf("%s: free_fct was given\ta pointer that is no element's data\n",
			label);
	else if (survivor)
		printf("%s: free_fct was given\ta surviving element's data\n", label);
	else if (g_twice)
		printf("%s: free_fct was given\tthe same data twice\n", label);
	else if (missed)
		printf("%s: free_fct was given\tnot every removed element's data\n",
			label);
	else if (want == 0)
		printf("%s: free_fct was given\tnothing, as nothing was removed\n",
			label);
	else
		printf("%s: free_fct was given\teach removed element's data, once\n",
			label);
	i = 0;
	while (i < g_n)
		free(g_data[i++]);
}

static void	run(char **arr, int n, char *target, char *label)
{
	t_list	*begin;

	begin = build(arr, n);
	g_ref = target;
	ft_list_remove_if(&begin, target, &cmp_str, &record_free);
	show_nodes(label, begin, n + 1);
	show_frees(label, arr, target);
}

int	main(void)
{
	char	*a[] = {"keep", "del", "keep2", "del"};
	char	*b[] = {"del", "a", "b"};
	char	*c[] = {"a", "b", "del"};
	char	*d[] = {"a", "del", "del", "b", "del"};
	char	*e[] = {"z", "z", "z"};
	char	*f[] = {"a", "b"};
	char	target[4];

	strcpy(target, "del");
	run(a, 4, target, "interleaved");
	run(b, 3, target, "remove head");
	run(c, 3, target, "remove tail");
	run(d, 5, target, "consecutive");
	strcpy(target, "z");
	run(e, 3, target, "remove all");
	strcpy(target, "q");
	run(f, 2, target, "no match");
	if (g_swapped)
		printf("cmp called as (*cmp)(list_ptr->data, data_ref)\tno, swapped\n");
	else
		printf("cmp called as (*cmp)(list_ptr->data, data_ref)\tyes\n");
	return (0);
}
