/* Allocation-failure probe for ft_lstnew. A test input, not a solution.
 *
 * af_case() makes ONE call into the library: the layer runs it once per
 * malloc the call reaches, refusing a different one each time, and asks that
 * the call return NULL instead of using the pointer it did not get. Why that
 * is asked, at robust and not basic, is the sentence its BUILD call hands the
 * report (allocfail_rule). */
#include "libft.h"

t_list	*ft_lstnew(void *content);

void	*af_case(void)
{
	static int	x = 42;

	return (ft_lstnew(&x));
}
