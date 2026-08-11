/* Memory-safety probe for ft_print_numbers — run under AddressSanitizer/UBSan.
 * Ten digits, no arguments, no external buffer. The hazard is the same
 * internal-array off-by-one as ex01, on a smaller scale: any stray write past a
 * fixed stack buffer is a reported stack-buffer-overflow.
 * A correct version stays in bounds and the probe exits 0 (an unimplemented stub
 * also exits 0). This is a test input, not a solution. */
void	ft_print_numbers(void);

int	main(void)
{
	ft_print_numbers();
	return (0);
}
