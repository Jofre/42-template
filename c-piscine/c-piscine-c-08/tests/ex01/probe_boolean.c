/* Not a test, and not a solution. See tests/ex02/probe_abs.c for why this shape
 * exists: a macro leaves no object file to inspect until something expands it,
 * so the `forbidden` layer needs a translation unit that expands EVEN once and
 * calls nothing else of its own.
 *
 * EVEN's surface for this is narrower than ABS's -- there is less in the C
 * library to reach for -- but the layer costs nothing to run and the subject's
 * "Allowed functions: None" applies to this exercise word for word.
 */

#include "ft_boolean.h"

int	probe_even(int nbr);

int	probe_even(int nbr)
{
	return ((EVEN(nbr)) ? 1 : 0);
}
