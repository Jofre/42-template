/* Allocation-failure probe for ft_strmapi. A test input, not a solution.
 *
 * af_case() makes ONE call into the library. The layer runs that same call
 * once per malloc the function reaches, refusing a different one each time,
 * and asks only that the call report the failure -- return NULL, as
 * ft_strmapi's box says (p.12: "Returns NULL if the allocation fails.") --
 * instead of using the pointer it did not get. The f is the harness's own
 * and gives back the byte it is handed.
 */
#include <stddef.h>

char	*ft_strmapi(char const *s, char (*f)(unsigned int, char));

static char	same(unsigned int i, char c)
{
	(void)i;
	return (c);
}

void	*af_case(void)
{
	return (ft_strmapi("abc", same));
}
