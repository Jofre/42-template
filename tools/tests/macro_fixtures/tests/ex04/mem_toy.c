/* ex04's memory probe: c_mem_check's wiring, beside a stray main.c the
 * contract does not name, which this build must not compile. It calls the
 * toy once; the probe program it is built into (ex04_memprobe) is a harness
 * over the toy's files, so it names ex04_prototype like every other
 * (tools/defs.bzl's _student_bin), and :harnesses lists it. */
int	toy_twice(int n);

int	main(void)
{
	(void)toy_twice(21);
	return (0);
}
