#include "ft_list.h"
#include <stdio.h>
#include <stdlib.h>

static char	*dup_str(char *s)
{
	int		i;
	char	*r;

	i = 0;
	while (s[i])
		i++;
	r = malloc((i + 1) * sizeof(char));
	i = 0;
	while (s[i])
	{
		r[i] = s[i];
		i++;
	}
	r[i] = '\0';
	return (r);
}

static void	del(void *data)
{
	printf("free %s\n", (char *)data);
	free(data);
}

static t_list	*new_node(char *s, t_list *next)
{
	t_list	*n;

	n = malloc(sizeof(t_list));
	n->data = dup_str(s);
	n->next = next;
	return (n);
}

int	main(void)
{
	t_list	*begin;

	ft_list_clear(NULL, &del);
	begin = new_node("solo", NULL);
	ft_list_clear(begin, &del);
	begin = new_node("x", NULL);
	begin = new_node("x", begin);
	begin = new_node("x", begin);
	ft_list_clear(begin, &del);
	return (0);
}
