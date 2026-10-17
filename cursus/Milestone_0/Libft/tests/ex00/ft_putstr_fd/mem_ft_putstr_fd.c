/* Memory-safety probe for ft_putstr_fd -- run under AddressSanitizer and
 * memcheck. Each s is a HEAP block of exactly its length plus the
 * terminator, with nothing valid after it, so a read one byte past the
 * terminator lands in a redzone: the read that still writes the right bytes,
 * which no diff of the output can see. The empty string is a 1-byte block
 * holding the terminator alone; the longest one is past 4096 bytes. The
 * bytes go to a file under $TEST_TMPDIR, never read back: this probe judges
 * memory only, and a stub, which reads nothing, passes it. This is a test
 * input, not code. */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

void	ft_putstr_fd(char *s, int fd);

static void	probe(const char *text, size_t len, int fd)
{
	char	*s;

	s = malloc(len + 1);
	if (s == NULL)
		exit(2);
	memcpy(s, text, len);
	s[len] = '\0';
	ft_putstr_fd(s, fd);
	free(s);
}

int	main(void)
{
	const char	*dir;
	char		path[4096];
	char		*big;
	int			fd;

	dir = getenv("TEST_TMPDIR");
	if (dir == NULL || *dir == '\0')
		dir = "/tmp";
	snprintf(path, sizeof(path), "%s/mem_ft_putstr_fd_XXXXXX", dir);
	fd = mkstemp(path);
	if (fd < 0)
		return (2);
	unlink(path);
	probe("", 0, fd);
	probe("a", 1, fd);
	probe("Hello", 5, fd);
	probe("caf\xc3\xa9\xff", 6, fd);
	big = malloc(5000);
	if (big == NULL)
		return (2);
	memset(big, 'x', 5000);
	probe(big, 5000, fd);
	free(big);
	close(fd);
	return (0);
}
