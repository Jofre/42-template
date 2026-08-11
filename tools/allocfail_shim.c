/* allocfail_shim.c — the mechanism behind tools/allocfail_check.sh: it makes
 * ONE of the deliverable's own malloc() calls fail on purpose, and reports what
 * came back. Grader-side test infrastructure — never compiled into a
 * deliverable, so it uses libc freely and need not be norm-compliant (same
 * standing as tools/perf_run.c).
 *
 * ---------------------------------------------------------------------------
 * WHY THIS EXISTS
 *
 * Every malloc exercise's subject carries a sentence of the shape "it should
 * return a NULL pointer if an error occurs". Until this layer, nothing in the
 * suite had ever made that sentence true or false: the diff layers compare
 * output, valgrind observes the success path, ASan observes the success path,
 * ilp32 rebuilds the success path for 32-bit. malloc simply never refused, on
 * any exercise, in any layer. So a function that stores malloc's answer into a
 * pointer and dereferences it without ever looking at it was byte-identical,
 * leak-identical and sanitizer-identical to one that checks — the error path
 * was not merely unverified, it had never been EXECUTED.
 *
 * An error path nobody has run is an error path nobody has got right. That is
 * the whole thesis of this file: not that checking malloc is stylish, but that
 * the branch is dead code until something makes the allocator say no.
 *
 * ---------------------------------------------------------------------------
 * HOW THE INJECTION WORKS, AND WHY IT LANDS ONLY ON THE DELIVERABLE
 *
 * `ld -Wl,--wrap=malloc` rewrites every *undefined* reference to `malloc` in
 * the object files on the link line into a reference to `__wrap_malloc`, and
 * binds `__real_malloc` to the genuine one. Two properties matter here, and
 * both are the reason this approach was chosen over LD_PRELOAD:
 *
 *   1. It only touches references that are RESOLVED AT THIS LINK. Allocations
 *      made *inside* libc — printf's stdout buffer, the dynamic loader's
 *      bookkeeping, strdup's copy — are internal calls within libc.so and are
 *      never routed through us. That is not a limitation, it is the scoping:
 *      the counter can only ever see allocations the student's own code asked
 *      for, so injection #3 means the deliverable's third malloc and not "the
 *      third malloc that happened on this machine". With LD_PRELOAD, failing
 *      "the third allocation" could mean failing setlocale's, which would red a
 *      correct student for a fault in the C library.
 *
 *   2. It is a LINK-TIME decision, so the deliverable's source is compiled
 *      exactly as every other layer compiles it. Nothing is #defined over the
 *      student's malloc; the code under test is the code they wrote.
 *
 * The harness is deliberately kept out of the count too. allocfail_check.sh
 * compiles the harness translation unit — and only that one — with
 * `-Dmalloc=__real_malloc`, so any allocation the TEST code makes to set up its
 * inputs goes straight to the real allocator: uncounted, and never injected.
 * Without that, a harness that builds a heap string before calling the function
 * would shift every injection index by one and would eventually take the
 * injected NULL itself — a crash in the test scaffolding, reported as a student
 * failure. The scoping is what makes injection #N mean something a student can
 * act on.
 *
 * ---------------------------------------------------------------------------
 * THE HARNESS CONTRACT — one function, no header
 *
 * This file provides main(). The exercise's harness provides:
 *
 *     void	*af_case(void);
 *
 * af_case() performs ONE call into the deliverable with a fixed, small input,
 * and returns:
 *
 *     the pointer the deliverable produced   — it reported success
 *     NULL                                   — it reported the error
 *
 * "Returns NULL" is spelled as an actual pointer rather than a status code so
 * that the common case is written without ceremony (`return (ft_strdup("x"))`),
 * and so exercises whose subject signals the error some other way can still say
 * so honestly: ft_ultimate_range reports -1 and fills nothing, and its harness
 * writes `return (n == -1 ? NULL : range)`. The harness is the only place that
 * knows what its own subject calls "an error", which is exactly where that
 * knowledge belongs.
 *
 * Keep the input SMALL. The check runs the binary once per allocation the
 * deliverable makes, so a harness that splits a 10,000-word string turns a
 * one-second layer into a sweep that has to be truncated to stay bounded.
 *
 * ---------------------------------------------------------------------------
 * WHAT THIS DELIBERATELY DOES NOT CHECK
 *
 * The pointer af_case() returns is never freed here, and nothing in this file
 * or in allocfail_check.sh looks at what was leaked when an injected failure
 * hit halfway through a multi-block allocation.
 *
 * That is a considered omission, not an oversight. The subjects say what the
 * function must RETURN when an allocation fails; not one of them says it must
 * first release the blocks it had already taken. Failing a student for a
 * partial-allocation leak on the error path would invent a requirement the
 * exercise does not carry, and inventing requirements is how a test suite
 * teaches students to write code for the suite instead of for the subject.
 * Leaks on the SUCCESS path are a real requirement and are graded — by
 * valgrind_test.sh, which is the layer that owns that question.
 *
 * ---------------------------------------------------------------------------
 * PROTOCOL WITH THE SCRIPT
 *
 *   in : AF_ARM=<n> in the environment. n = 0 (or unset/garbage) arms nothing,
 *        which is how the script discovers how many allocations the deliverable
 *        makes in the first place. n > 0 fails the n-th one.
 *   out: one line on stderr, after af_case() returns —
 *            AF_RESULT arm=<n> seen=<count> result=<ptr|null>
 *        `seen` is how many allocations the deliverable actually asked for on
 *        THIS run; the script uses it to confirm the injection really fired
 *        (seen >= arm) before drawing any conclusion from the result.
 *   exit status: always 0. This program does not judge — if it dies, it died
 *        for the reason under test, so the script can read a non-zero status as
 *        "the deliverable crashed" with no ambiguity about who chose it.
 */
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>

extern void	*__real_malloc(size_t size);
void		*__wrap_malloc(size_t size);

/* Defined by the exercise's harness. See THE HARNESS CONTRACT above. */
void		*af_case(void);

/* Which allocation to fail (1-based; 0 = none), and how many have been asked
 * for so far. Single-threaded by construction — the deliverables are — so
 * plain globals are enough and an atomic would only obscure the mechanism. */
static unsigned long	g_arm;
static unsigned long	g_seen;

/* The refusal itself. Note what is NOT here: no size threshold, no random
 * failure, no "fail every Nth", and no stickiness — the refusal does not stay
 * on once it has fired. Exactly one allocation fails per run, chosen by the
 * caller, so when something goes wrong the run that produced it names the
 * single decision point responsible. A shim that failed allocations randomly
 * would find the same bugs and be unable to say where.
 *
 * One consequence worth knowing, because it changes how a finding reads: an
 * implementation that RETRIES a refused allocation gets a real block on its
 * second attempt and finishes normally, so it never shows up as a hang. It
 * shows up as "was refused, asked again, returned a pointer" — which is the
 * honest description of what the code did, and a more useful one than a
 * timeout, since a timeout says only that something never came back. The
 * script compares `seen` against the armed index to tell the two apart. */
void	*__wrap_malloc(size_t size)
{
	g_seen++;
	if (g_arm != 0 && g_seen == g_arm)
		return (NULL);
	return (__real_malloc(size));
}

int	main(void)
{
	char		line[160];
	const char	*arm_env;
	void		*result;
	int		n;

	arm_env = getenv("AF_ARM");
	if (arm_env != NULL)
		g_arm = strtoul(arm_env, NULL, 10);
	/* Reset AFTER the environment lookup: getenv/strtoul do not allocate, but
	 * zeroing here rather than at file scope keeps the count unambiguously
	 * "allocations made during af_case()" no matter what start-up code the
	 * platform runs first. */
	g_seen = 0;
	result = af_case();
	/* Deliberately not freed — see WHAT THIS DELIBERATELY DOES NOT CHECK. */
	/* The LEADING newline is not decoration. The deliverable and the harness
	 * share this stream, and a program that wrote to stderr without a trailing
	 * newline would otherwise have this report appended to its own last line —
	 * where the script, which anchors on the start of a line, would not find
	 * it. It would then read "no report" as "the call never returned" and
	 * report a crash that never happened. One byte removes the whole class. */
	n = snprintf(line, sizeof(line), "\nAF_RESULT arm=%lu seen=%lu result=%s\n",
			g_arm, g_seen, result != NULL ? "ptr" : "null");
	/* snprintf returns the length it WOULD have written, which is not the same
	 * as the length it did. The fixed text plus two 20-digit counters cannot
	 * reach 160, so this cannot trigger today; it is here because handing an
	 * over-long count to write() would read past the buffer, and a tool that
	 * reads out of bounds while grading memory safety is not a tool anyone
	 * should have to think twice about. */
	if (n > (int)sizeof(line) - 1)
		n = (int)sizeof(line) - 1;
	if (n > 0)
		write(2, line, (size_t)n);
	return (0);
}
