/* A toy rush harness: what rush_variant's knobs hand their runner,
 * nothing else -- no test built from it is ever run.
 * It calls rush once and reads nothing: no line, no stdin. */
void	rush(int x, int y);

int	main(void)
{
	rush(1, 1);
	return (0);
}
