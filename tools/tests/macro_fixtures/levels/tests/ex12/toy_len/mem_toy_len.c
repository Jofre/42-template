/* The toy library's memory probe: a member's c_mem_check wiring, nothing
 * else. It calls toy_len once; the probe program it is built into
 * (ex12_toy_len_memprobe) links the library's unit through the turn-in's
 * Makefile, and names the library's ex12_prototype. */
int	toy_len(int n);

int	main(void)
{
	(void)toy_len(21);
	return (0);
}
