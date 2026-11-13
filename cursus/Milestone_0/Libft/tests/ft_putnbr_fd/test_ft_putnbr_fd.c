#include "fd_capture.h"

/* ft_putnbr_fd's fixture: C 04 ex02's fourteen ints, trivial to subtle, each
 * row's value every byte the call wrote to the file descriptor it was handed,
 * in the notation diff_output.sh --escaped-values reads (\\ a backslash, \n a
 * line break, \t a tab, \xHH any other byte outside printable ASCII), so a
 * stray byte shows rather than travels.
 *
 * WHERE THE BYTES GO: tools/fd_capture.h, which hands the call a file of
 * its own and fd 1 another, reads both back and writes the row. */
void	ft_putnbr_fd(int n, int fd);

static void	test(const char *label, int n)
{
	fc_aside();
	ft_putnbr_fd(n, g_fc_fd);
	fc_back();
	fc_show(label);
}

int	main(void)
{
	fc_start();
	test("zero", 0);
	test("one digit", 7);
	test("two digits", 42);
	test("ends in zero", 10);
	test("trailing zeros", 100);
	test("big positive", 1000000000);
	test("negative one digit", -7);
	test("negative two digits", -42);
	test("negative trailing zeros", -100);
	test("big negative", -1000000000);
	test("INT_MAX", 2147483647);
	test("INT_MAX - 1", 2147483646);
	test("INT_MIN + 1", -2147483647);
	test("INT_MIN", -2147483647 - 1);
	fc_stop();
	return (0);
}
