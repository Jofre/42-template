#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

/* ft_putnbr_fd's fixture: C 04 ex02's fourteen ints, trivial to subtle, each
 * row's value every byte the call wrote to the file descriptor it was handed,
 * in the notation diff_output.sh --escaped-values reads (\\ a backslash, \n a
 * line break, \t a tab, \xHH any other byte outside printable ASCII), so a
 * stray byte shows rather than travels.
 *
 * WHERE THE BYTES GO. A file under $TEST_TMPDIR, open on a descriptor of 3 or
 * more, read back after each call and emptied for the next. Not fd 1 or 2: a
 * function that writes to the standard output instead of its fd would then
 * look right. And fd 1 is not the table's stream while the function runs: it
 * is a second file, read back with the first, so bytes written there show in
 * their own row, after a note, instead of in the middle of the table (C 02
 * ex12's dup2 swap). */
void	ft_putnbr_fd(int n, int fd);

static int	g_fd = -1;
static int	g_stray = -1;
static int	g_saved = -1;

/* A file of our own on a descriptor of 3 or more, unlinked at once so nothing
 * is left behind. */
static int	open_file(const char *what)
{
	const char	*dir;
	char		path[4096];
	int			fd;
	int			hi;

	dir = getenv("TEST_TMPDIR");
	if (dir == NULL || *dir == '\0')
		dir = "/tmp";
	snprintf(path, sizeof(path), "%s/ft_putnbr_fd_%s_XXXXXX", dir, what);
	fd = mkstemp(path);
	if (fd < 0)
	{
		perror("test_ft_putnbr_fd: mkstemp");
		exit(2);
	}
	unlink(path);
	if (fd >= 3)
		return (fd);
	hi = fcntl(fd, F_DUPFD, 3);
	close(fd);
	if (hi < 3)
	{
		perror("test_ft_putnbr_fd: fcntl");
		exit(2);
	}
	return (hi);
}

/* Around each call, fd 1 is the stray file, and the table's own stream is
 * back on fd 1 before anything is printed. */
static void	aside(void)
{
	fflush(stdout);
	if (dup2(g_stray, 1) != 1)
		exit(2);
}

static void	back(void)
{
	if (dup2(g_saved, 1) != 1)
		exit(2);
}

static void	put_escaped(const unsigned char *b, size_t n)
{
	size_t	i;

	i = 0;
	while (i < n)
	{
		if (b[i] == '\\')
			printf("\\\\");
		else if (b[i] == '\n')
			printf("\\n");
		else if (b[i] == '\t')
			printf("\\t");
		else if (b[i] < 0x20 || b[i] > 0x7e)
			printf("\\x%02x", b[i]);
		else
			putchar(b[i]);
		i++;
	}
}

/* Every byte in the file fd holds, NULL when it is empty; *n its count. */
static unsigned char	*slurp(int fd, size_t *n)
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
static void	show(const char *label)
{
	unsigned char	*b;
	size_t			n;
	unsigned char	*s;
	size_t			sn;
	int				closed;

	closed = (fcntl(g_fd, F_GETFD) < 0);
	b = NULL;
	n = 0;
	if (!closed)
		b = slurp(g_fd, &n);
	s = slurp(g_stray, &sn);
	printf("%s\t", label);
	put_escaped(b, n);
	if (sn > 0)
	{
		printf("%s[fd 1, the standard output, got %zu byte%s: ",
			n > 0 ? " " : "", sn, sn == 1 ? "" : "s");
		put_escaped(s, sn > 32 ? 32 : sn);
		printf("%s]", sn > 32 ? "..." : "");
	}
	if (closed)
		printf("%s[fd %d, the descriptor handed in, was closed by the call]",
			n + sn > 0 ? " " : "", g_fd);
	printf("\n");
	free(b);
	free(s);
	if (closed)
		g_fd = open_file("capture");
}

static void	test(const char *label, int n)
{
	aside();
	ft_putnbr_fd(n, g_fd);
	back();
	show(label);
}

int	main(void)
{
	setbuf(stdout, NULL);
	g_fd = open_file("capture");
	g_stray = open_file("stray");
	g_saved = dup(1);
	if (g_saved < 0)
		exit(2);
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
	close(g_fd);
	close(g_stray);
	close(g_saved);
	return (0);
}
