/* Allocation-failure probe for ft_ultimate_range. A test input, not a solution.
 *
 * af_case() makes ONE call into the deliverable. The layer runs that same call
 * once per malloc the function reaches, refusing a different one each time, and
 * asks only that the call report the failure instead of pretending it succeeded.
 *
 * WHERE THE REQUIREMENT COMES FROM, in this subject's own words. p.10 states
 * TWO error channels as two separate bullets:
 *
 *     "The size of range should be returned (or -1 on error)."
 *     "If the value of min is greater or equal to max's value, range will
 *      point to NULL and it should return 0."
 *
 * The logical condition owns the 0. So the only error left that can produce the
 * -1 the first bullet names is a failed allocation -- and nothing else in this
 * suite has ever made one fail, on any exercise, in any layer. Until this file
 * existed that branch was not weakly tested: it was dead code.
 *
 * That makes this a STRONGER hook than ex00's, which reaches its contract
 * through `man strdup`. Here the sentence is in the exercise's own subject.
 *
 * THE RETURN VALUE, and why the sentinel is not decoration. The shim reads
 * "NULL" as "the deliverable reported the error", so this harness has to
 * translate this subject's error signal into that. -1 is the report. Anything
 * else is not -- and the interesting wrong answer, returning 0 with *range left
 * NULL, would hand the shim a NULL of its own and be read as a correct report.
 * The sentinel is what keeps those two apart.
 *
 * The range is small on purpose: every allocation is another whole run of the
 * program, and this function should need exactly one.
 *
 * WHAT IT RETURNED, in words (the shim's af_note). The sentinel keeps the two
 * apart, and loses the value: the report used to say this function "still
 * returned a pointer" when it had returned 0 (finding 075). So the harness
 * says what the call returned -- the number, and whether *range was set --
 * and the report prints that instead.
 */
#include <stdio.h>

/* Non-NULL, and never dereferenced: it means only "the call returned, and what
 * it returned was not the -1 this subject asks for". */
static int	g_not_reported;
static char	g_note[96];

extern const char	*af_note;

int	ft_ultimate_range(int **range, int min, int max);

void	*af_case(void)
{
	int	*range;
	int	n;

	range = (void *)0;
	n = ft_ultimate_range(&range, 0, 4);
	if (n == -1)
		return ((void *)0);
	snprintf(g_note, sizeof(g_note), "returned %d, not -1, with *range %s", n,
		range ? "set" : "left NULL");
	af_note = g_note;
	if (range)
		return (range);
	return (&g_not_reported);
}
