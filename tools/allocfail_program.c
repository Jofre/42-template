/* allocfail_program.c — the allocation-failure shim for a PROGRAM: the
 * student's own main() runs, and ONE of its malloc() calls is refused.
 * Grader-side test infrastructure, never compiled into a deliverable (same
 * standing as allocfail_shim.c, whose header explains the mechanism).
 *
 * WHY A SECOND SHIM. allocfail_shim.c provides main() and calls one function,
 * so a program -- which brings its own main() -- could never be linked with it
 * (finding 150: BSQ, the rushes and C 10's ex02/ex03 had no way in, and every
 * Common Core project is a program). This file has no main(): c_program links
 * it beside the student's sources, with -Wl,--wrap=malloc and -Wl,--wrap=free,
 * into exNN_bin_allocfail, built by the same student_binary rule as every
 * other program -- a Makefile project from its own `make -Bn`.
 *
 * PROTOCOL WITH THE SCRIPT (allocfail_check.sh --bin):
 *
 *   in : AF_ARM=<n> in the environment, as for the function shim; AF_REPORT=
 *        <path>, the file the report is written to.
 *   out: when the program ends by returning from main() or calling exit(),
 *        one line in AF_REPORT -- the function shim's AF_RESULT line, with
 *        result=exit (a program returns no pointer): how many allocations it
 *        asked for, and how many blocks it still held -- and wrapped=<0|1>.
 *        A program killed by a signal writes nothing, and the script reads
 *        the signal instead.
 *
 * The count starts in a constructor, before main(): the student's code is
 * the only caller of the wrapped malloc, so nothing before it is counted.
 *
 * wrapped=1 is the constructor's own proof that the link took the wraps: its
 * malloc(1), made before anything is armed, is counted only if this binary's
 * references to malloc reach __wrap_malloc. Without it, a program that asked
 * for no memory and a link that lost -Wl,--wrap=malloc would read the same --
 * "nothing to refuse" -- and the second would stay green forever.
 */
#define AF_WRAP_FREE
#include <fcntl.h>
#include <unistd.h>
#include "allocfail_counter.h"

static void	af_start(void) __attribute__((constructor));
static void	af_report(void) __attribute__((destructor));

static int	g_wrapped;

static void	af_start(void)
{
	const char	*arm_env;
	void		*probe;

	g_arm = 0;
	g_seen = 0;
	probe = malloc(1);
	g_wrapped = (g_seen == 1 && g_live == 1);
	free(probe);
	g_wrapped = g_wrapped && g_live == 0;
	arm_env = getenv("AF_ARM");
	if (arm_env != NULL)
		g_arm = strtoul(arm_env, NULL, 10);
	g_seen = 0;
	af_reset();
}

/* Runs after main() returns, or inside exit(): what the program still holds
 * then is what it left behind. open/write rather than stdio: the program's
 * own streams may be closed, and a FILE of ours would be one more block. */
static void	af_report(void)
{
	char		line[200];
	const char	*path;
	int			fd;
	int			n;

	path = getenv("AF_REPORT");
	if (path == NULL || *path == '\0')
		return ;
	n = af_line(line, sizeof(line), "exit",
			g_wrapped ? " wrapped=1" : " wrapped=0");
	fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (fd < 0)
		return ;
	if (n > 0)
		(void)!write(fd, line, (size_t)n);
	close(fd);
}
