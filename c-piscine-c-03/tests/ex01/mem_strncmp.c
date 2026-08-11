/* Memory-safety probe for ft_strncmp — run under AddressSanitizer.
 * strncmp compares at most n bytes and must work on buffers that are NOT
 * NUL-terminated (fixed-size memory comparison), never dereferencing index n.
 * Each buffer below is sized EXACTLY n with no terminator and equal content, so
 * a correct strncmp reads only indices 0..n-1 and returns 0 — while a version
 * whose bound check comes AFTER the dereference reads index n (out of bounds),
 * which ASan flags. This is a test input, not an implementation. */
int	ft_strncmp(char *s1, char *s2, unsigned int n);

int	main(void)
{
	char			a[3] = {'a', 'b', 'c'};
	char			b[3] = {'a', 'b', 'c'};
	char			c[2] = {'x', 'y'};
	char			d[2] = {'x', 'y'};
	volatile int	r1;
	volatile int	r2;

	r1 = ft_strncmp(a, b, 3);
	r2 = ft_strncmp(c, d, 2);
	(void)r1;
	(void)r2;
	return (0);
}
