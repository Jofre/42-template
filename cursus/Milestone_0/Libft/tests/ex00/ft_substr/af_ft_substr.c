/* Allocation-failure probe for ft_substr. A test input, not a solution.
 *
 * af_case() makes ONE call into the library. The layer runs that same call
 * once per malloc the function reaches, refusing a different one each time,
 * and asks only that the call report the failure -- return NULL, as
 * ft_substr's box says (p.10: "NULL if the allocation fails.") -- instead of
 * using the pointer it did not get. A short input: every allocation is
 * another whole run.
 */
#include <stddef.h>

char	*ft_substr(char const *s, unsigned int start, size_t len);

void	*af_case(void)
{
	return (ft_substr("hello", 1, 3));
}
