/* Not a test, and not a solution.
 *
 * This file exists only so the `forbidden` layer has an object file to look at.
 * ft_abs.h's answer is a macro, and a macro leaves no trace in a header -- there
 * is no .o to inspect until something expands it. So this translation unit
 * expands ABS exactly once and calls nothing else: every undefined symbol in the
 * resulting object therefore came out of the macro body.
 *
 * The harness's own test_abs.c cannot serve here. It calls printf itself, so its
 * undefined symbols are a mix of the macro's and its own, and the one thing this
 * layer is looking for would be indistinguishable from the noise around it.
 *
 * What it catches: `# define ABS(n) (abs(n))` produces `U abs`, and c-08's
 * subject says "Allowed functions: None". Without this, that header passes every
 * layer the exercise has -- right output, clean Norm, correct file -- and is a
 * flat KO at the Moulinette.
 */

#include "ft_abs.h"

int	probe_abs(int nbr);

int	probe_abs(int nbr)
{
	return (ABS(nbr));
}
