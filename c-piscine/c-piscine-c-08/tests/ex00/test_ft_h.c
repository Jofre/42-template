#include "ft.h"

int	main(void)
{
	int	a;
	int	b;

	a = 1;
	b = 2;
	// All five calls rely on prototypes coming from ft.h. With an incomplete
	// header the implicit declarations make -Werror fail (red until written).
	ft_putchar('x');
	ft_swap(&a, &b);
	ft_putstr("hello");
	ft_strlen("hello");
	ft_strcmp("a", "b");
	return (0);
}

// Trivial definitions placed AFTER main so prototypes must come from ft.h.
void	ft_putchar(char c)
{
	(void)c;
}

void	ft_swap(int *a, int *b)
{
	(void)a;
	(void)b;
}

void	ft_putstr(char *str)
{
	(void)str;
}

int	ft_strlen(char *str)
{
	(void)str;
	return (0);
}

int	ft_strcmp(char *s1, char *s2)
{
	(void)s1;
	(void)s2;
	return (0);
}
