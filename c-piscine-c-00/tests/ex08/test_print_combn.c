/* Drives ft_print_combn across the domain the subject defines and NOTHING else.
 *
 * The subject says, word for word: "The value of n will be such that:
 * 0 < n < 10." So n is 1..9, and what the function does with 0, 10 or -3 is not
 * specified — which means this layer is not entitled to an opinion about it. It
 * used to pin byte-exact empty output for all three, and a perfectly reasonable
 * implementation that fills n slots prints "0123456789" for n = 10. That was a
 * red test, at the BEGINNER gate, for code that is correct everywhere the
 * subject reaches.
 *
 * Those three values are still driven — in tests/ex08/mem_print_combn.c, under
 * AddressSanitizer, where the requirement is the one that really does apply to
 * them: whatever it decides to print, it must not read or write out of bounds.
 * That is a liveness property, not an output contract, and it belongs there.
 *
 * ALL NINE values the subject defines are driven. It used to be four -- both
 * ends of the recursion (n = 1, shallowest; n = 9, deepest) and two interiors
 * (2 and 4, the widest output) -- and c-piscine-c-00/BUILD.bazel named the
 * remedy for the other five in the same breath as declining a fuzz layer for
 * them: "the cheap and correct answer is five more calls in that harness, not a
 * fuzz layer". These are those five calls.
 *
 * The expected bytes come from //oracle's `c00_print_combn` arm, which emits
 * exactly these nine lines and whose own check() compares each against an
 * independent odometer enumeration and against C(10, n). Before the five were
 * added, that arm was required to reproduce the four already committed here
 * BYTE FOR BYTE -- which it does, and which is what makes the other five
 * trustworthy rather than merely plausible.
 */

#include <unistd.h>

void	ft_print_combn(int n);

int	main(void)
{
	int	n;

	n = 1;
	while (n < 10)
	{
		ft_print_combn(n);
		write(1, "\n", 1);
		n++;
	}
	return (0);
}
