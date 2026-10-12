#include <unistd.h>

void	ft_putstr(char *str);

/* A string of 5000 bytes, "abc...z" over and over: past every capacity a
 * function is usually given room for (16, 64, 256, 1024, 4096; finding 041),
 * so a string passed through room of a fixed size comes out cut. The subject
 * bounds no string, so every reading agrees on this case. */
static void	put_long(void)
{
	static char	s[5001];
	int			i;

	i = 0;
	while (i < 5000)
	{
		s[i] = 'a' + i % 26;
		i++;
	}
	s[i] = '\0';
	ft_putstr(s);
	write(1, "\n", 1);
}

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
	put_long();
	ft_putstr("caf\xC3\xA9");
	write(1, "\n", 1);
	ft_putstr("\xff");
	write(1, "\n", 1);
	return (0);
}
