/* Memory-safety probe for ft_print_comb2 — run under AddressSanitizer.
 * ft_print_comb2 takes no arguments and is handed no buffer. There is no n/size
 * parameter to bound, so the only memory hazard is internal: whatever storage
 * the function keeps of its own while it prints a pair, it must not WRITE past
 * the end of it. ASan instruments stack buffers with redzones, so this single
 * call — which walks every pair from 00 01 up to 98 99 — makes any such stray
 * write a reported stack-buffer-overflow. A correct version stays in bounds and the probe exits 0
 * (an unimplemented stub also exits 0). This is a test input, not a solution. */
void	ft_print_comb2(void);

int	main(void)
{
	ft_print_comb2();
	return (0);
}
