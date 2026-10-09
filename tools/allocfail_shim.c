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
 * And where the error is not a pointer, a pointer loses what the function
 * actually did: ft_ultimate_range returning 0, or its range size, was reported
 * as "still returned a pointer" (finding 075). So a harness may also say, in
 * words, what the call returned, before it returns:
 *
 *     extern const char	*af_note;
 *     af_note = "returned 0, with *range left NULL";
 *
 * The shim reports it with the result, and the script prints it in place of
 * the pointer wording. One line of text, no newline; read only when the
 * result is not NULL.
 *
 * Keep the input SMALL. The check runs the binary once per allocation the
 * deliverable makes, so a harness that splits a 10,000-word string turns a
 * one-second layer into a sweep that has to be truncated to stay bounded.
 *
 * ---------------------------------------------------------------------------
 * WHAT IT COUNTS, AND WHO JUDGES IT
 *
 * The pointer af_case() returns is never freed here. What the deliverable had
 * already taken when the refusal hit is COUNTED, never judged by this file:
 * with free() wrapped too (-Wl,--wrap=free, which allocfail_check.sh links
 * only for --leaks), every block __wrap_malloc hands out is kept in a small
 * table, and every free() of one of them crosses it off. The report carries
 * how many are still live, and their bytes.
 *
 * The basic layer reads none of it. The subjects say what the function must
 * RETURN when an allocation fails; not one says it must first release the
 * blocks it had already taken, and no memory checker at 42 ever sees an
 * allocation refused. So releasing them is this repo's own rigour, asked at
 * `robust` by a separate exNN_allocfail_leaks target (allocfail_check.sh
 * --leaks), and only where the subject lets the function call free(). Leaks on
 * the SUCCESS path are a real requirement and are graded by valgrind_test.sh.
 *
 * ---------------------------------------------------------------------------
 * PROTOCOL WITH THE SCRIPT
 *
 *   in : AF_ARM=<n> in the environment. n = 0 (or unset/garbage) arms nothing,
 *        which is how the script discovers how many allocations the deliverable
 *        makes in the first place. n > 0 fails the n-th one.
 *   out: one line on stderr, after af_case() returns —
 *            AF_RESULT arm=<n> seen=<count> result=<ptr|null> live=<n> bytes=<b>[ note=<text>]
 *        note is af_note's text, when the harness set it: the rest of the
 *        line, its control bytes turned into blanks.
 *        `seen` is how many allocations the deliverable actually asked for on
 *        THIS run; the script uses it to confirm the injection really fired
 *        (seen >= arm) before drawing any conclusion from the result. `live`
 *        and `bytes` are the blocks it obtained and has not freed, when free()
 *        is wrapped; `live=untracked` when the counter's own table could not
 *        grow (the shim ran out of memory), so a count that would be wrong is
 *        never printed.
 *   exit status: always 0. This program does not judge — if it dies, it died
 *        for the reason under test, so the script can read a non-zero status as
 *        "the deliverable crashed" with no ambiguity about who chose it.
 */
#include <unistd.h>
#include "allocfail_counter.h"

/* Defined by the exercise's harness. See THE HARNESS CONTRACT above. */
void	*af_case(void);

/* What the call returned, in words, where a pointer cannot say it: set by a
 * harness whose subject's error is not a pointer (THE HARNESS CONTRACT). */
const char	*af_note;

int	main(void)
{
	char		line[400];
	char		note[208];
	const char	*arm_env;
	void		*result;
	int			n;
	size_t		i;

	arm_env = getenv("AF_ARM");
	if (arm_env != NULL)
		g_arm = strtoul(arm_env, NULL, 10);
	/* Reset AFTER the environment lookup: getenv/strtoul do not allocate, but
	 * zeroing here rather than at file scope keeps the count unambiguously
	 * "allocations made during af_case()" no matter what start-up code the
	 * platform runs first. */
	g_seen = 0;
	af_reset();
	result = af_case();
	/* Deliberately not freed — see WHAT IT COUNTS, AND WHO JUDGES IT. */
	/* The note, kept to one line: a control byte in it would end the line the
	 * script reads, and cut the report short. It goes last (af_line's EXTRA),
	 * so the script can take the rest of the line as its text. */
	note[0] = '\0';
	if (result != NULL && af_note != NULL && af_note[0] != '\0')
	{
		snprintf(note, sizeof(note), " note=%s", af_note);
		i = 0;
		while (note[i] != '\0')
		{
			if (note[i] >= 0 && note[i] < ' ')
				note[i] = ' ';
			i++;
		}
	}
	/* The LEADING newline (af_line) is not decoration. The deliverable and
	 * the harness share this stream, and a program that wrote to stderr
	 * without a trailing newline would otherwise have this report appended to
	 * its own last line — where the script, which anchors on the start of a
	 * line, would not find it. It would then read "no report" as "the call
	 * never returned" and report a crash that never happened. One byte removes
	 * the whole class. */
	n = af_line(line, sizeof(line), result != NULL ? "ptr" : "null", note);
	if (n > 0)
		write(2, line, (size_t)n);
	return (0);
}
