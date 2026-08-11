/* Allocation-failure probe for ft_strdup. A test input, not a solution.
 *
 * af_case() makes ONE call into the deliverable. The layer runs that same call
 * once per malloc the function reaches, refusing a different one each time, and
 * asks only that the call report the failure instead of using the pointer it
 * did not get.
 *
 * WHERE THE REQUIREMENT COMES FROM, since it is not in the subject's own words.
 * The subject says "Reproduce the behavior of the function strdup (man strdup)"
 * -- so the contract is the man page's, and that page states the return: NULL,
 * with errno set, when insufficient memory was available. c-08 ex04 is the one
 * exercise that spells the same rule out in the subject text; here it arrives
 * by the reference the subject makes instead.
 *
 * That is a weaker hook than a sentence in the subject, and this layer is gated
 * accordingly: allocfail sits at level 3 (robust), so it never meets a beginner
 * at the gate they see first. It is switched on here because ignoring malloc's
 * answer is not a style question -- the next line dereferences it.
 *
 * A short input on purpose. Every allocation is another whole run of the
 * program, and one is all this function should need.
 */

char	*ft_strdup(char *src);

void	*af_case(void)
{
	return (ft_strdup("42"));
}
