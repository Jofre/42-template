/* Allocation-failure probe for ft_split. A test input, not a solution.
 *
 * af_case() makes ONE call into the library. The layer runs that same call
 * once per malloc the function reaches, refusing a different one each time,
 * and asks only that the call report the failure -- return NULL, as
 * ft_split's box says (p.11: "NULL if any allocation fails.") -- instead of
 * using the pointer it did not get. Three words: an array and a string per
 * word, so a refusal can land after some of them were obtained, which is
 * what ex00_ft_split_allocfail_leaks reads.
 */
#include <stddef.h>

char	**ft_split(char const *s, char c);

void	*af_case(void)
{
	return (ft_split("ab cd ef", ' '));
}
