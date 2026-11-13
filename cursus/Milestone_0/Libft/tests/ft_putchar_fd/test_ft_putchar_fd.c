#include "fd_capture.h"

/* ft_putchar_fd's fixture: one labeled row per case, its value every byte the
 * case wrote to the file descriptor it was handed, in the notation
 * diff_output.sh --escaped-values reads (\\ a backslash, \n a line break, \t
 * a tab, \xHH any other byte outside printable ASCII).
 *
 * WHERE THE BYTES GO: tools/fd_capture.h, which hands the call a file of
 * its own and fd 1 another, reads both back and writes the row.
 *
 * The last row calls it once for each of the 256 values a char holds, in
 * order: every input the function has, which is why it has no differential
 * layer. */
void	ft_putchar_fd(char c, int fd);

static void	test(const char *label, char c)
{
	fc_aside();
	ft_putchar_fd(c, g_fc_fd);
	fc_back();
	fc_show(label);
}

int	main(void)
{
	int	i;

	fc_start();
	test("'a'", 'a');
	test("'Z'", 'Z');
	test("a backslash", '\\');
	test("a line break", '\n');
	test("a NUL byte", '\0');
	test("0x7f", (char)0x7f);
	test("0x80", (char)0x80);
	test("0xff", (char)0xff);
	i = 0;
	fc_aside();
	while (i < 256)
	{
		ft_putchar_fd((char)i, g_fc_fd);
		i++;
	}
	fc_back();
	fc_show("all 256 values, 0x00 to 0xff, one call each");
	fc_stop();
	return (0);
}
