#include "ft_stock_str.h"

void	ft_show_tab(struct s_stock_str *par);

int	main(void)
{
	t_stock_str	tab[5];

	tab[0].str = "zero";
	tab[0].size = 4;
	tab[0].copy = "ZERO";
	tab[1].str = "forty-two";
	tab[1].size = 9;
	tab[1].copy = "FORTY-TWO";
	/* Empty-string element (size 0): a NULL terminator must be a NULL pointer,
	   not an empty string. An impl that stops on *str == 0 would truncate here
	   and never print the element that follows. size 0 also catches a putnbr
	   that prints nothing for zero. */
	tab[2].str = "";
	tab[2].size = 0;
	tab[2].copy = "";
	/* Multi-digit, non-palindromic size (12) catches a digit-reversing putnbr
	   (would print "21"). copy differs from str so printing str twice is caught. */
	tab[3].str = "0123456789ab";
	tab[3].size = 12;
	tab[3].copy = "CHANGED-COPY";
	tab[4].str = 0;
	tab[4].size = 0;
	tab[4].copy = 0;
	ft_show_tab(tab);
	return (0);
}
