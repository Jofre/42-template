/* Memory-safety probe for ft_print_comb2 — run under AddressSanitizer.
 * ft_print_comb2 takes no arguments and owns no external buffer: for every pair
 * it prints it fills a fixed internal buffer of 5 bytes ("NN NN"). There is no
 * n/size parameter to bound, so the only memory hazard is an off-by-one or an
 * undersized WRITE past that internal buffer's last index. ASan instruments
 * stack buffers with redzones, so this single call — which walks every pair from
 * 00 01 up to 98 99 — makes any stray write past the buffer a reported
 * stack-buffer-overflow. A correct version stays in bounds and the probe exits 0
 * (an unimplemented stub also exits 0). This is a test input, not a solution. */
void	ft_print_comb2(void);

int	main(void)
{
	ft_print_comb2();
	return (0);
}
