/* Memory-safety probe for ft_print_reverse_alphabet — run under AddressSanitizer/UBSan.
 * Same shape as ex01, with the hazard that actually bites here: counting DOWN.
 * A loop that decrements past the first element, or an array filled from the
 * high index without stopping at zero, reads or writes before the buffer start.
 * ASan places a redzone on both sides, so an underflow is reported as readily as
 * an overflow.
 * A correct version stays in bounds and the probe exits 0 (an unimplemented stub
 * also exits 0). This is a test input, not a solution. */
void	ft_print_reverse_alphabet(void);

int	main(void)
{
	ft_print_reverse_alphabet();
	return (0);
}
