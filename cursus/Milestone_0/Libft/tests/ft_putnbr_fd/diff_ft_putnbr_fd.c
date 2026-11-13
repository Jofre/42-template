/* Live-differential reader harness for ft_putnbr_fd.
 * Line: <n>\t<hexWritten>, and \t<hexFd1> where the call wrote to fd 1.
 * The int in decimal, then every byte ft_putnbr_fd wrote to the file
 * descriptor it was handed, in order, as hex; and, only when the call also
 * wrote to fd 1, the standard output, a third column: those bytes, as hex.
 *
 * The descriptor is a file under $TEST_TMPDIR, open on 3 or more and read
 * back after each call: not a pipe, as in the string writers' readers, and
 * not fd 1 or 2, where a function writing to the standard output instead
 * would look right. And fd 1 is not this harness's stream while the function
 * runs: it is a second such file, so bytes written there make the third
 * column instead of landing in the middle of a line (C 02 ex12's dup2 swap,
 * as the fixture's). The capture is tools/diffio.h's, "WHAT A FUNCTION
 * WRITES TO A DESCRIPTOR IT IS HANDED". */
#include "diffio.h"

void	ft_putnbr_fd(int n, int fd);

int	main(void)
{
	char			*line;
	size_t			linecap;
	char			*f[2];
	unsigned char	*w;
	size_t			n;
	t_dio_fdcap		c;

	setbuf(stdout, NULL);
	dio_fdcap_open(&c, "diff_ft_putnbr_fd");
	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		dio_split(line, f, 2);
		dio_fd_aside(&c);
		ft_putnbr_fd((int)strtol(f[0], NULL, 10), c.fd);
		w = dio_fd_take(&c, "ft_putnbr_fd", &n);
		printf("%s\t", f[0]);
		dio_puthex(w, n);
		dio_put_stray(c.stray);
		printf("\n");
		free(w);
	}
	free(line);
	dio_fdcap_close(&c);
	return (0);
}
