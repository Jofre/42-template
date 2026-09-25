#include <unistd.h>

void	*ft_print_memory(void *addr, unsigned int size);

int	main(void)
{
	char			str[] = "Bonjour les aminches\t\n\tc\a est fou\ttout\tce qu on peut faire avec\t\n\tprint_memory\n\n\n\tlol.lol. \0";
	char			full[] = "0123456789ABCDEF";
	char			part[] = "abc";
	unsigned char	np[5];
	void			*ret;

	ret = ft_print_memory(str, sizeof(str) - 1);
	if (ret == (void *)str)
		write(1, "ret==str:1\n", 11);
	else
		write(1, "ret==str:0\n", 11);
	ft_print_memory(full, 16);
	ft_print_memory(part, 3);
	np[0] = 0;
	np[1] = 1;
	np[2] = 127;
	np[3] = 128;
	np[4] = 255;
	ft_print_memory(np, 5);
	write(1, "SIZE0:[", 7);
	ft_print_memory(full, 0);
	write(1, "]\n", 2);
	return (0);
}
