/* Macro hygiene for EVEN — held at the STRICT level, not basic, and the reason
 * is worth reading before moving it.
 *
 * The subject's own main passes EVEN nothing but an int parameter:
 *
 *     t_bool ft_is_even(int nbr) { return ((EVEN(nbr)) ? TRUE : FALSE); }
 *
 * Inside a macro body, a bare `nbr` is already a single token, so a definition
 * that forgets to wrap its argument in parentheses still behaves perfectly
 * there. It only breaks when the argument is an EXPRESSION — `EVEN(1 + 1)`
 * expands to something like `1 + 1 % 2`, and operator precedence quietly turns
 * "is this even" into "1 plus (1 mod 2)". The answer flips, and nothing in the
 * subject's example would ever have shown you.
 *
 * That is a genuine and famous C lesson, and it is most of what an exercise
 * about #define is for. It is also strictly more than this subject requires. So
 * it is checked, but it does not fail anyone at the beginner gate:
 *
 *     bazel test //c-piscine-c-08:basic    subject fidelity — this is not in it
 *     bazel test //c-piscine-c-08:strict   this too
 *
 * The three arguments below are chosen so a missing pair of parentheses cannot
 * pass by luck: 1 + 1 and 3 - 1 are even and would each report odd, while 2 + 3
 * is odd and would report even.
 */

#include "ft_boolean.h"
#include <stdio.h>

static void	report(t_bool res, char *label)
{
	if (res == TRUE)
		printf("%s even\n", label);
	else
		printf("%s odd\n", label);
}

int	main(void)
{
	report((EVEN(1 + 1)) ? TRUE : FALSE, "1 + 1");
	report((EVEN(3 - 1)) ? TRUE : FALSE, "3 - 1");
	report((EVEN(2 + 3)) ? TRUE : FALSE, "2 + 3");
	return (0);
}
