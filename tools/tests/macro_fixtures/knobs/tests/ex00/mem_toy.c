/* The toy's memory probe: c_mem_check's srcs, hdrs and prototype
 * overrides, nothing else. It calls the toy once. */
int	toy_twice(int n);

int	main(void)
{
	(void)toy_twice(21);
	return (0);
}
