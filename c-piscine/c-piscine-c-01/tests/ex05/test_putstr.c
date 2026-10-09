#include <unistd.h>

void	ft_putstr(char *str);

int	main(void)
{
	ft_putstr("Hello World!");
	write(1, "\n", 1);
	ft_putstr("");
	write(1, "\n", 1);
	ft_putstr("42 Barcelona");
	write(1, "\n", 1);
	ft_putstr("  tabs\tand spaces  ");
	write(1, "\n", 1);
	ft_putstr("x");
	write(1, "\n", 1);
	return (0);
}
