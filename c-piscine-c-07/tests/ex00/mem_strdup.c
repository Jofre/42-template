/* Memory-safety probe for ft_strdup — run under AddressSanitizer.
 * ft_strdup allocates a fresh buffer and copies `src` including its terminating
 * NUL, so it must read src[0 .. len] (stopping AT the NUL) and its own block
 * must hold len + 1 bytes. Each `src` below is a HEAP string of EXACTLY len + 1
 * bytes (content + NUL, no slack), so a stray read of src[len + 1] — a scan that
 * checks the bound AFTER dereferencing — lands past the block and ASan reports a
 * heap-buffer-overflow. ASan likewise flags the copy if the function's own
 * malloc is one byte short and it terminates past the end. The empty string is a
 * 1-byte block (just the NUL). This is a test input, not an implementation. */
#include <stdlib.h>

char	*ft_strdup(char *src);

static char	*heapstr(char *s)
{
	int		len;
	int		i;
	char	*p;

	len = 0;
	while (s[len])
		len++;
	p = malloc(len + 1);
	i = 0;
	while (i <= len)
	{
		p[i] = s[i];
		i++;
	}
	return (p);
}

int	main(void)
{
	char	*src;
	char	*empty;
	char	*dup;

	src = heapstr("a");
	dup = ft_strdup(src);
	free(dup);
	free(src);
	empty = heapstr("");
	dup = ft_strdup(empty);
	free(dup);
	free(empty);
	return (0);
}
