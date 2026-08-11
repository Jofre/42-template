/* Memory-safety probe for ft_strlcat — run under AddressSanitizer.
 * strlcat must cap its scan of dest at `size` (like strnlen), never reading past
 * the buffer when dest has no NUL within `size`. `dest` below is a 4-byte buffer
 * with NO terminator; a correct strlcat scans at most `size` bytes, finds no NUL,
 * appends nothing and returns size + strlen(src) = 6 — never touching dest[4].
 * With size 0 it must not read dest at all. This is a test input, not a solution. */
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
