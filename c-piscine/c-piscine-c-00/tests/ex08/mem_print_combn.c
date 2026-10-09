/* Memory-safety probe for ft_print_combn — run under AddressSanitizer.
 * ft_print_combn(n) is handed no buffer, so whatever storage it uses to hold
 * its n digits is its own -- and the widest n it accepts must not write past
 * that storage. An off-by-one there only shows at the largest n, which is why
 * the probe drives n up to 9 (valid range 1..9); ASan's redzones catch the
 * overflow. It also passes 0, 10 and a negative — values the subject rules out
 * ("0 < n < 10") and therefore says nothing about. This probe does not care
 * what they PRINT; the output layer deliberately does not pin that (see
 * tests/ex08/test_print_combn.c). What it requires is the property that applies
 * whatever the code decides to do with them: it must not read or write outside
 * its own storage. A correct version
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
