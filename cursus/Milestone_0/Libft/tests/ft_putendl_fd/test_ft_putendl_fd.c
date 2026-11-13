#include <stdlib.h>
#include <string.h>
#include "fd_capture.h"

/* ft_putendl_fd's fixture: one labeled row per call, its value every byte the
 * call wrote to the file descriptor it was handed, in the notation
 * diff_output.sh --escaped-values reads (\\ a backslash, \n a line break, \t
 * a tab, \xHH any other byte outside printable ASCII).
 *
 * WHERE THE BYTES GO: tools/fd_capture.h, which hands the call a file of
 * its own and fd 1 another, reads both back and writes the row.
 *
 * The two rows past 4096 bytes (finding 041) are built by construction and
 * come last. */
void	ft_putendl_fd(char *s, int fd);

static void	test(const char *label, const char *s)
{
	char	*copy;
	size_t	len;

	len = strlen(s);
	copy = malloc(len + 1);
	if (copy == NULL)
		exit(2);
	memcpy(copy, s, len + 1);
	fc_aside();
	ft_putendl_fd(copy, g_fc_fd);
	fc_back();
	fc_show(label);
	free(copy);
}

/* n bytes, first + i % 26 for byte i, then the terminator. */
static void	test_long(const char *label, size_t n, char first)
{
	char	*s;
	size_t	i;

	s = malloc(n + 1);
	if (s == NULL)
		exit(2);
	i = 0;
	while (i < n)
	{
		s[i] = (char)(first + i % 26);
		i++;
	}
	s[n] = '\0';
	fc_aside();
	ft_putendl_fd(s, g_fc_fd);
	fc_back();
	fc_show(label);
	free(s);
}

int	main(void)
{
	char	every[256];
	int		i;

	fc_start();
	test("\"Hello\"", "Hello");
	test("\"\" (the empty string)", "");
	test("a tab and a line break inside", "a\tb\nc");
	test("a line break alone", "\n");
	test("UTF-8 text, then a lone 0xff", "caf\xc3\xa9\xff");
	i = 0;
	while (i < 255)
	{
		every[i] = (char)(i + 1);
		i++;
	}
	every[255] = '\0';
	test("every byte from 0x01 to 0xff, in order", every);
	test_long("5000 bytes", 5000, 'a');
	test_long("70000 bytes", 70000, 'A');
	fc_stop();
	return (0);
}
