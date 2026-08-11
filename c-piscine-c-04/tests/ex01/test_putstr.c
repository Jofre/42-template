#include <unistd.h>

void	ft_putstr(char *str);

int	main(void)
{
	ft_putstr("Hello");
	write(1, "\n", 1);
	ft_putstr("");
	write(1, "\n", 1);
	ft_putstr("Hello, world!");
	write(1, "\n", 1);
	ft_putstr("42");
	write(1, "\n", 1);
	ft_putstr("0");
	write(1, "\n", 1);
	ft_putstr("  leading and trailing  ");
	write(1, "\n", 1);
	ft_putstr("tab\tand\ttabs");
	write(1, "\n", 1);
	return (0);
}
