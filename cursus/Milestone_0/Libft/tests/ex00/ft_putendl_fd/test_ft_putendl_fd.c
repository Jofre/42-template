#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

/* ft_putendl_fd's fixture: one labeled row per call, its value every byte the
 * call wrote to the file descriptor it was handed, in the notation
 * diff_output.sh --escaped-values reads (\\ a backslash, \n a line break, \t
 * a tab, \xHH any other byte outside printable ASCII).
 *
 * WHERE THE BYTES GO. A file under $TEST_TMPDIR, open on a descriptor of 3 or
 * more, read back after each call and emptied for the next. Not a pipe: a
 * long row would fill one and block. Not fd 1 or 2: a function that writes to
 * the standard output instead of its fd would then look right. And fd 1 is
 * not the table's stream while the function runs: it is a second file, read
 * back with the first, so bytes written there show in their own row, after a
 * note, instead of in the middle of the table (C 02 ex12's dup2 swap).
 *
 * The two rows past 4096 bytes (finding 041) are built by construction and
 * come last. */
void	ft_putendl_fd(char *s, int fd);

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
	snprintf(path, sizeof(path), "%s/ft_putendl_fd_%s_XXXXXX", dir, what);
	fd = mkstemp(path);
	if (fd < 0)
	{
		perror("test_ft_putendl_fd: mkstemp");
		exit(2);
	}
	unlink(path);
	if (fd >= 3)
		return (fd);
	hi = fcntl(fd, F_DUPFD, 3);
	close(fd);
	if (hi < 3)
	{
		perror("test_ft_putendl_fd: fcntl");
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

static void	test(const char *label, const char *s)
{
	char	*copy;
	size_t	len;

	len = strlen(s);
	copy = malloc(len + 1);
	if (copy == NULL)
		exit(2);
	memcpy(copy, s, len + 1);
	aside();
	ft_putendl_fd(copy, g_fd);
	back();
	show(label);
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
	aside();
	ft_putendl_fd(s, g_fd);
	back();
	show(label);
	free(s);
}

int	main(void)
{
	char	every[256];
	int		i;

	setbuf(stdout, NULL);
	g_fd = open_file("capture");
	g_stray = open_file("stray");
	g_saved = dup(1);
	if (g_saved < 0)
		exit(2);
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
	close(g_fd);
	close(g_stray);
	close(g_saved);
	return (0);
}
