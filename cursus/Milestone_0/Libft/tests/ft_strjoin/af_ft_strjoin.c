/* Allocation-failure probe for ft_strjoin. A test input, not a solution.
 *
 * af_case() makes ONE call into the library. The layer runs that same call
 * once per malloc the function reaches, refusing a different one each time,
 * and asks only that the call report the failure -- return NULL, as
 * ft_strjoin's box says (p.10: "NULL if the allocation fails.") -- instead
 * of using the pointer it did not get. A short input: every allocation is
 * another whole run.
 */
#include <stddef.h>

char	*ft_strjoin(char const *s1, char const *s2);

void	*af_case(void)
{
	return (ft_strjoin("ab", "cd"));
}
