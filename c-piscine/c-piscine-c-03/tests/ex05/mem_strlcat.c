/* Memory-safety probe for ft_strlcat — run under AddressSanitizer.
 * `dest` below is a 4-byte buffer with NO terminator, passed with size 4. The
 * probe checks one thing only: ft_strlcat never reads dest[4], the byte past
 * `size` (man strlcat: it looks at no more than size bytes of dest). The second
 * call, size 0, must not run off the end of d2 either. What either call returns
 * is not checked here -- the output layer pins that. This is a test input, not a
 * solution. */
unsigned int	ft_strlcat(char *dest, char *src, unsigned int size);

int	main(void)
{
	char					dest[4] = {'A', 'B', 'C', 'D'};
	char					d2[2] = {'Z', 'Z'};
	volatile unsigned int	r1;
	volatile unsigned int	r2;

	r1 = ft_strlcat(dest, "XY", 4);
	r2 = ft_strlcat(d2, "q", 0);
	(void)r1;
	(void)r2;
	return (0);
}
