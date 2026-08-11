/* Memory-safety probe for ft_print_comb — run under AddressSanitizer/UBSan.
 * ft_print_comb prints every strictly ascending digit triple, filling a fixed
 * internal buffer per combination ("abc" plus its separator). There is no n/size
 * parameter to bound, so an undersized buffer or an off-by-one on its last index
 * is the only memory hazard — and this single call walks every triple from 012
 * to 789, so the probe exercises the widest and the narrowest output the
 * function ever builds.
 * A correct version stays in bounds and the probe exits 0 (an unimplemented stub
 * also exits 0). This is a test input, not a solution. */
void	ft_print_comb(void);

int	main(void)
{
	ft_print_comb();
	return (0);
}
