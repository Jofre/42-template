/* Live-differential reader harness for ft_putendl_fd.
 * Line: <hexS>\t<hexWritten>, and \t<hexFd1> where the call wrote to fd 1.
 * s as hex, then every byte ft_putendl_fd wrote to the file descriptor it was
 * handed, in order, as hex: s, then the newline the description asks for;
 * and, only when the call also wrote to fd 1, the standard output, a third
 * column: those bytes, as hex.
 *
 * The descriptor is a file under $TEST_TMPDIR, open on 3 or more and read
 * back after each call: not a pipe, which the 70000-byte case would fill and
 * block on, and not fd 1 or 2, where a function writing to the standard
 * output instead would look right. s is a block of exactly its length plus
 * the terminator, so the ASan twin sees a read past it. And fd 1 is not this
 * harness's stream while the function runs: it is a second such file, so
 * bytes written there make the third column instead of landing in the
 * middle of a line (C 02 ex12's dup2 swap, as the fixture's). See
 * tools/diffio.h. */
#include "diffio.h"
#include <fcntl.h>
#include <unistd.h>

void	ft_putendl_fd(char *s, int fd);

static int	capture_open(void)
{
	const char	*dir;
	/* conventions: bounded -- snprintf'd with its size from $TEST_TMPDIR, never from a case */
	char		path[4096];
	int			fd;
	int			hi;

	dir = getenv("TEST_TMPDIR");
	if (dir == NULL || *dir == '\0')
		dir = "/tmp";
	snprintf(path, sizeof(path), "%s/diff_ft_putendl_fd_XXXXXX", dir);
	fd = mkstemp(path);
	if (fd < 0)
		dio_fail("cannot create the capture file under $TEST_TMPDIR");
	unlink(path);
	if (fd >= 3)
		return (fd);
	hi = fcntl(fd, F_DUPFD, 3);
	close(fd);
	if (hi < 3)
		dio_fail("cannot move the capture file to a descriptor of 3 or more");
	return (hi);
}

/* What the call wrote to fd 1, as the line's third column, then emptied for
 * the next: no column at all when it wrote nothing there. stray and fd 1
 * share one file offset (dup2), so the offset is how much was written. */
static void	put_stray(int stray)
{
	off_t			n;
	unsigned char	*b;

	n = lseek(stray, 0, SEEK_CUR);
	if (n <= 0)
		return ;
	b = (unsigned char *)malloc((size_t)n);
	if (b == NULL || pread(stray, b, (size_t)n, 0) != n)
		dio_fail("cannot read back what the call wrote to fd 1");
	printf("\t");
	dio_puthex(b, (size_t)n);
	free(b);
	if (ftruncate(stray, 0) != 0 || lseek(stray, 0, SEEK_SET) != 0)
		dio_fail("cannot empty the file fd 1 is during a call");
}

int	main(void)
{
	char			*line;
	size_t			linecap;
	char			*f[2];
	unsigned char	*s;
	unsigned char	*w;
	int				fd;
	int				stray;
	int				saved;
	off_t			start;
	off_t			end;

	setbuf(stdout, NULL);
	fd = capture_open();
	stray = capture_open();
	saved = fcntl(1, F_DUPFD, 3);
	if (saved < 3)
		dio_fail("cannot keep the standard output on a descriptor of 3 or more");
	start = 0;
	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		s = dio_unhex(f[0], NULL, 0);
		if (dup2(stray, 1) != 1)
			dio_fail("cannot make fd 1 a file of its own for the call");
		ft_putendl_fd((char *)s, fd);
		if (dup2(saved, 1) != 1)
			dio_fail("cannot put the standard output back after the call");
		/* A descriptor the call closed is the function's doing, not the
		 * harness's: said as such, and the run ends there. */
		if (fcntl(fd, F_GETFD) < 0)
		{
			fprintf(stderr, "diff_ft_putendl_fd: after the call, fd %d, the descriptor "
				"ft_putendl_fd was handed, was no longer open: the call closed it\n", fd);
			exit(1);
		}
		/* What this call wrote: from where the file stood before it to where
		 * it stands now. Emptied only past 1 MiB, to spend two system calls
		 * a case and not four. */
		end = lseek(fd, 0, SEEK_CUR);
		if (end < start)
			end = start;
		w = (unsigned char *)malloc((size_t)(end - start) + 1);
		if (w == NULL || pread(fd, w, (size_t)(end - start), start) != end - start)
			dio_fail("cannot read the capture file back");
		printf("%s\t", f[0]);
		dio_puthex(w, (size_t)(end - start));
		put_stray(stray);
		printf("\n");
		free(w);
		free(s);
		start = end;
		if (start > (1 << 20))
		{
			if (ftruncate(fd, 0) != 0 || lseek(fd, 0, SEEK_SET) != 0)
				dio_fail("cannot empty the capture file");
			start = 0;
		}
	}
	free(line);
	close(fd);
	close(stray);
	close(saved);
	return (0);
}
