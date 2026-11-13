/* WHAT A FUNCTION WRITES TO A DESCRIPTOR IT IS HANDED, for an output
 * fixture (Libft's ft_put*_fd tables), written once.
 *
 * The bytes go to a file under $TEST_TMPDIR, open on a descriptor of 3 or
 * more, read back after each call and emptied for the next. Not a pipe: a
 * long row would fill one and block. Not fd 1 or 2: a function that writes
 * to the standard output instead of its fd would then look right. And fd 1
 * is not the table's stream while the function runs: it is a second file,
 * read back with the first, so bytes written there show in their own row,
 * after a note, instead of in the middle of the table (C 02 ex12's dup2
 * swap). The four fixtures kept a copy each of the code below.
 *
 *     fc_start();                      once: the files, fd 1 kept aside
 *     fc_aside();                      fd 1 is the stray file from here
 *     ft_put..._fd(..., g_fc_fd);
 *     fc_back();                       fd 1 is the table's again
 *     fc_show("<label>");              the row, then both files emptied
 *     fc_stop();                       once, after the last row
 *
 * The rows are in the notation diff_output.sh --escaped-values reads,
 * written by tools/notation.h, so a fixture that includes this header says
 * escaped_values = True. Linked as part of //tools:notation, a library of
 * headers alone: no dirty_malloc, no --wrap=malloc, so the memcheck layers
 * may run what includes it.
 *
 * Not tools/diffio.h's capture (dio_fdcap_open), which a reader harness
 * uses, on purpose: a reader reads each call's bytes by offset and empties
 * the file only past 1 MiB, shows every stray byte, stops the run with exit
 * 1 when the call closed its descriptor, and fails through dio_fail, whose
 * prefix rust_diff.sh looks for. A fixture empties both files after every
 * row, shows the first 32 stray bytes, opens a new file in place of a
 * closed descriptor and goes on, and fails with perror and exit 2. And
 * diffio.h is //tools:diffio's, which links dirty_malloc, while these
 * fixtures run under memcheck. Both kinds of program are refused a
 * mkstemp( or an F_DUPFD of their own (//tools:conventions).
 *
 * Every function is static inline, so a fixture that calls only some of
 * them still builds under -Wall -Wextra -Werror. */
#ifndef FD_CAPTURE_H
# define FD_CAPTURE_H

# include <fcntl.h>
# include <stdio.h>
# include <stdlib.h>
# include <sys/stat.h>
# include <unistd.h>
# include "notation.h"

/* The descriptor the function is handed, the file fd 1 is during a call,
 * and the table's own standard output, kept aside. */
static int	g_fc_fd = -1;
static int	g_fc_stray = -1;
static int	g_fc_saved = -1;

/* A file of our own on a descriptor of 3 or more, unlinked at once so
 * nothing is left behind. `tag` names it while it has a name. */
static inline int	fc_open(const char *tag)
{
	const char	*dir;
	char		path[4096];
	int			fd;
	int			hi;

	dir = getenv("TEST_TMPDIR");
	if (dir == NULL || *dir == '\0')
		dir = "/tmp";
	snprintf(path, sizeof(path), "%s/fd_capture_%s_XXXXXX", dir, tag);
	fd = mkstemp(path);
	if (fd < 0)
	{
		perror("fd_capture: mkstemp");
		exit(2);
	}
	unlink(path);
	if (fd >= 3)
		return (fd);
	hi = fcntl(fd, F_DUPFD, 3);
	close(fd);
	if (hi < 3)
	{
		perror("fd_capture: fcntl");
		exit(2);
	}
	return (hi);
}

/* Before the first row: the table's stream unbuffered, the two files, and
 * fd 1 kept aside, opened in that order. */
static inline void	fc_start(void)
{
	setbuf(stdout, NULL);
	g_fc_fd = fc_open("capture");
	g_fc_stray = fc_open("stray");
	g_fc_saved = dup(1);
	if (g_fc_saved < 0)
		exit(2);
}

/* After the last row. */
static inline void	fc_stop(void)
{
	close(g_fc_fd);
	close(g_fc_stray);
	close(g_fc_saved);
}

/* Around each call, fd 1 is the stray file, and the table's own stream is
 * back on fd 1 before anything is printed. */
static inline void	fc_aside(void)
{
	fflush(stdout);
	if (dup2(g_fc_stray, 1) != 1)
		exit(2);
}

static inline void	fc_back(void)
{
	if (dup2(g_fc_saved, 1) != 1)
		exit(2);
}

/* Every byte in the file fd holds, NULL when it is empty; *n its count.
 * The file is emptied for the next row. */
static inline unsigned char	*fc_slurp(int fd, size_t *n)
{
	struct stat		st;
	unsigned char	*b;
	ssize_t			got;

	*n = 0;
	if (fstat(fd, &st) != 0)
		exit(2);
	if (st.st_size == 0)
		return (NULL);
	b = malloc((size_t)st.st_size);
	if (b == NULL)
		exit(2);
	got = pread(fd, b, (size_t)st.st_size, 0);
	if (got > 0)
		*n = (size_t)got;
	if (ftruncate(fd, 0) != 0 || lseek(fd, 0, SEEK_SET) != 0)
		exit(2);
	return (b);
}

/* The row: what the file holds now, then the file emptied for the next. Two
 * mistakes get a note of their own after the bytes, so the row is red and
 * still readable: bytes that went to fd 1 (the first 32 shown), and a
 * descriptor the call closed, after which a new file takes its place. */
static inline void	fc_show(const char *label)
{
	unsigned char	*b;
	size_t			n;
	unsigned char	*s;
	size_t			sn;
	int				closed;

	closed = (fcntl(g_fc_fd, F_GETFD) < 0);
	b = NULL;
	n = 0;
	if (!closed)
		b = fc_slurp(g_fc_fd, &n);
	s = fc_slurp(g_fc_stray, &sn);
	printf("%s\t", label);
	nt_put(b, n);
	if (sn > 0)
	{
		printf("%s[fd 1, the standard output, got %zu byte%s: ",
			n > 0 ? " " : "", sn, sn == 1 ? "" : "s");
		nt_put(s, sn > 32 ? 32 : sn);
		printf("%s]", sn > 32 ? "..." : "");
	}
	if (closed)
		printf("%s[fd %d, the descriptor handed in, was closed by the call]",
			n + sn > 0 ? " " : "", g_fc_fd);
	printf("\n");
	free(b);
	free(s);
	if (closed)
		g_fc_fd = fc_open("capture");
}

#endif
