/* ft_putchar is a deliverable of its own here ("The ft_putchar.c file must
 * contain the ft_putchar function"), so it is tested on its own: this harness
 * links ONLY ft_putchar.c, which also proves the function really lives in that
 * file rather than inside rush0N.c.
 *
 * Cases run trivial -> conceptually hardest: printable ASCII, the invisible
 * ones, then the two bytes that expose a signed/unsigned char confusion (0x00
 * and 0xFF). */
void	ft_putchar(char c);

int	main(void)
{
	ft_putchar('O');
	ft_putchar('K');
	ft_putchar('\n');
	ft_putchar('4');
	ft_putchar('2');
	ft_putchar(' ');
	ft_putchar('-');
	ft_putchar('|');
	ft_putchar('/');
	ft_putchar('\\');
	ft_putchar('~');
	ft_putchar('\t');
	ft_putchar((char)0);
	ft_putchar((char)127);
	ft_putchar((char)128);
	ft_putchar((char)255);
	ft_putchar('\n');
	return (0);
}
