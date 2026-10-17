/* The toy's allocation-failure probe for the member toy_cat: c_function's
 * allocfail and allocfail_leaks wiring on a member, nothing else. One call
 * into the toy. */
char	*toy_cat(char *s);

void	*af_case(void)
{
	return (toy_cat("toy"));
}
