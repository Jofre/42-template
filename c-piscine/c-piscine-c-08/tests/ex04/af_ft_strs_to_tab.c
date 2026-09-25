/* Allocation-failure probe for ft_strs_to_tab. A test input, not a solution.
 *
 * af_case() makes ONE call into the deliverable with a fixed, small input. The
 * layer then runs this same call once per malloc the function reaches, refusing
 * a different one each time, and asks only that the call report the error
 * instead of using the pointer it did not get.
 *
 * The input is deliberately tiny. Every extra string is another allocation and
 * therefore another whole run of the program, and two strings are already
 * enough to reach both shapes that matter: the array itself, and a per-element
 * allocation inside the loop.
 *
 * This exercise is the one place in the repo where the subject states the
 * requirement in its own words — "It should return a NULL pointer if an error
 * occurs" — which is why it is the one exercise with this layer. See
 * tools/allocfail_check.sh on why it must not be switched on wholesale.
 */

#include "ft_stock_str.h"

struct s_stock_str	*ft_strs_to_tab(int ac, char **av);

void	*af_case(void)
{
	static char	*av[2] = {"42", "ok"};

	return (ft_strs_to_tab(2, av));
}
