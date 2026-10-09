/* Memory-safety probe for ft_strncat — run under AddressSanitizer.
 * strncat copies AT MOST nb bytes of src, and man strncat says src need not
 * be NUL-terminated when it holds nb or more bytes. The byte at index nb may
 * then not exist, so reading it is out of bounds. `src` below is a 4-byte
 * buffer with NO terminator, passed with nb 4: an implementation that reads
 * src[4] runs one byte past the buffer, and ASan reports it. `dest` is
 * oversized so the only possible fault is that src over-read. With nb 0 the
 * src must not be copied. This is a test input, not a solution. */
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
