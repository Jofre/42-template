/* The toy's memory probe: c_mem_check's wiring, nothing else. It calls the
 * toy once; the probe program it is built into (ex00_memprobe) is a harness
 * over the toy's files, so it names ex00_prototype like every other
 * (tools/defs.bzl's _student_bin), and :harnesses lists it. */
int	toy_twice(int n);

int	main(void)
{
	(void)toy_twice(21);
	return (0);
}
