/* Memory-safety probe for ft_print_alphabet — run under AddressSanitizer/UBSan.
 * It takes no arguments and owns no external buffer, so the only memory hazard
 * is an internal one: an implementation that assembles the 26 letters into a
 * fixed array before emitting them can size that array by the count it MEANT to
 * write rather than the count it writes. ASan puts a redzone after every stack
 * buffer, so one byte past the end is reported here — and nowhere else in this
 * module, since a zero-input function has no c_diff and therefore no sanitizer
 * twin (see the long note in BUILD.bazel).
 * A correct version stays in bounds and the probe exits 0 (an unimplemented stub
 * also exits 0). This is a test input, not a solution. */
void	ft_print_alphabet(void);

int	main(void)
{
	ft_print_alphabet();
	return (0);
}
