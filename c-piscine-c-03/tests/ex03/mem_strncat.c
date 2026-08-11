/* Memory-safety probe for ft_strncat — run under AddressSanitizer.
 * strncat copies AT MOST nb bytes of src; per the contract src need not be
 * NUL-terminated when it holds nb or more bytes, so a correct strncat reads
 * only src[0..nb-1] and must test j < nb BEFORE dereferencing src[j]. `src`
 * below is a 4-byte buffer with NO terminator: a correct impl reads src[0..3]
 * and stops, while a bound-check-after-deref loop reads src[4], one past the
 * buffer. `dest` is oversized so the only possible fault is that src over-read.
 * With nb 0 the src must not be copied. This is a test input, not a solution. */
char	*ft_strncat(char *dest, char *src, unsigned int nb);

int	main(void)
{
	char	dest[8] = "ab";
	char	d2[4] = "xy";
	char	src[4] = {'p', 'q', 'r', 's'};
	char	s2[1] = {'z'};

	ft_strncat(dest, src, 4);
	ft_strncat(d2, s2, 0);
	return (0);
}
