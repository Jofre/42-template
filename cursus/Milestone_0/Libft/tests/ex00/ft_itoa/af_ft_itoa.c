/* Allocation-failure probe for ft_itoa. A test input, not a solution.
 *
 * af_case() makes ONE call into the library. The layer runs that same call
 * once per malloc the function reaches, refusing a different one each time,
 * and asks only that the call report the failure -- return NULL, as
 * ft_itoa's box says (p.11: "NULL if the allocation fails.") -- instead of
 * using the pointer it did not get.
 */
#include <stddef.h>

char	*ft_itoa(int n);

void	*af_case(void)
{
	return (ft_itoa(-42));
}
