/* The toy's allocation-failure probe: c_function's allocfail wiring, and
 * allocfail_level's raise, nothing else. One call into the toy. */
int	toy_twice(int n);

void	*af_case(void)
{
	return ((void *)(long)toy_twice(21));
}
