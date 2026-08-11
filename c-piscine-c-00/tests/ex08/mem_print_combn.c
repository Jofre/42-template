/* Memory-safety probe for ft_print_combn — run under AddressSanitizer.
 * ft_print_combn(n) owns no external buffer: it builds a fixed internal buffer
 * and recurses to depth n (valid range 1..9), writing one digit per level. There
 * is no caller-supplied buffer to bound, so the memory hazard is an off-by-one or
 * undersized internal buffer written during the DEEPEST recursion. ASan's stack
 * redzones catch that. We drive n up to the maximum depth 9, plus 0, 10 and a
 * negative — values the subject rules out ("0 < n < 10") and therefore says
 * nothing about. This probe does not care what they PRINT; the output layer
 * deliberately does not pin that (see tests/ex08/test_print_combn.c). What it
 * requires is the property that applies whatever the code decides to do with
 * them: it must not read or write outside its own buffer. A correct version
 * stays in bounds and the probe exits 0 (an unimplemented stub also exits 0).
 * This is a test input, not a solution. */
void	ft_print_combn(int n);

int	main(void)
{
	ft_print_combn(0);
	ft_print_combn(1);
	ft_print_combn(2);
	ft_print_combn(9);
	ft_print_combn(10);
	ft_print_combn(-3);
	return (0);
}
