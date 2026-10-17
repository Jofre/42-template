/* Allocation-failure probe for ft_calloc. A test input, not a solution.
 *
 * af_case() makes ONE call into the deliverable. The layer runs that same
 * call once per malloc the function reaches, refusing a different one each
 * time, and asks only that the call report the failure instead of using the
 * pointer it did not get.
 *
 * WHERE THE REQUIREMENT COMES FROM: Part 1 asks for "the same prototypes and
 * behaviors as the originals, adhering strictly to their definitions in the
 * man page" (Libft, p.8), and man 3 calloc's RETURN VALUE says "On error,
 * these functions return NULL." A cited contract, so the layer sits at
 * basic, as C 07's strdup does on the same kind of hook.
 *
 * A short request on purpose: one allocation is all this function needs.
 */
#include <stddef.h>

void	*ft_calloc(size_t nmemb, size_t size);

void	*af_case(void)
{
	return (ft_calloc(3, 4));
}
