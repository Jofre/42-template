/* Allocation-failure probe for ft_strdup. A test input, not a solution.
 *
 * af_case() makes ONE call into the library. The layer runs that same call
 * once per malloc the function reaches, refusing a different one each time,
 * and asks only that the call report the failure, as man 3 strdup says,
 * instead of using the pointer it did not get.
 *
 * WHERE THE REQUIREMENT COMES FROM: Libft, p.8 asks for "the same
 * prototypes and behaviors as the originals, adhering strictly to their
 * definitions in the man page", and man 3 strdup's RETURN VALUE says it
 * "returns NULL if insufficient memory was available". The BUILD call
 * quotes both.
 *
 * A short input on purpose: every allocation is another whole run of the
 * program, and one is all this function should need. */
#include <stddef.h>

char	*ft_strdup(const char *s);

void	*af_case(void)
{
	return (ft_strdup("42"));
}
