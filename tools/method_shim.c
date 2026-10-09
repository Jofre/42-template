/*
 * method_shim.c -- the method layer's recorder (tools/method_check.sh).
 *
 * The method layer asks one question a subject puts in words and no output
 * can show: does a function of the turned-in file call itself while it is
 * still running? tools/method_check.sh compiles the student's sources, and
 * only those, with -finstrument-functions, which has the compiler call
 * __cyg_profile_func_enter() as each of their functions starts and
 * __cyg_profile_func_exit() as it returns. This file is those two functions,
 * compiled WITHOUT the flag, beside the exercise's own test program (also
 * without it), so every call they see is one of the student's functions
 * starting or returning.
 *
 * What it records is a stack of the functions running right now. A function
 * that starts while it is already on that stack has been RE-ENTERED: it
 * called itself, or called a function that called it back. That is the one
 * fact both readings need -- the recursive ones ("Create a recursive
 * function", "Recursion is required") are read as "some function of the file
 * is re-entered", the iterative ones as "none ever is" -- so the moment it
 * happens the run is over: this writes "reentered" and ends the process, and
 * a recursive search that would print for seconds is judged at its first
 * call into itself. A run that ends with nothing re-entered writes "done".
 * Either line carries how many function starts were seen and how deep the
 * stack went, so the runner's verdict says what it is built on.
 *
 * Without re-entry the stack holds distinct functions only, so it is never
 * deeper than the file has functions; METHOD_DEPTH is far past any Piscine
 * file, and a run that passes it says so instead of guessing.
 *
 * It writes to the file METHOD_REPORT names, with write(2) and nothing that
 * buffers, and calls no function that is itself instrumented. It never prints
 * to the program's own output.
 *
 * ONE LINE PER PROCESS, APPENDED. A test program that forks has a recorder in
 * each process (the child's starts as a copy of its parent's), and each
 * writes its own line: the child's "reentered" must survive its parent's
 * "done", which a report opened with O_TRUNC overwrote. One write(2) of a
 * short line to a file opened with O_APPEND lands whole, so lines from
 * several processes never interleave; tools/method_check.sh reads them all,
 * and a "reentered" in any one is decisive.
 */
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>

#define METHOD_DEPTH 4096

static void				*g_running[METHOD_DEPTH];
static unsigned long	g_depth;
static unsigned long	g_deepest;
static unsigned long	g_starts;
static int				g_overflow;

__attribute__((no_instrument_function))
static void	method_num(char *buf, unsigned long *at, unsigned long n)
{
	char			digits[24];
	unsigned long	k;

	k = 0;
	if (n == 0)
		digits[k++] = '0';
	while (n > 0)
	{
		digits[k++] = (char)('0' + n % 10);
		n /= 10;
	}
	while (k > 0)
		buf[(*at)++] = digits[--k];
}

__attribute__((no_instrument_function))
static void	method_word(char *buf, unsigned long *at, const char *w)
{
	while (*w)
		buf[(*at)++] = *w++;
}

/* "WHAT STARTS DEEPEST\n" appended to METHOD_REPORT, once per process. */
__attribute__((no_instrument_function))
static void	method_report(const char *what)
{
	static int		said;
	const char		*path;
	char			line[128];
	unsigned long	at;
	int				fd;

	if (said)
		return ;
	said = 1;
	path = getenv("METHOD_REPORT");
	if (path == NULL)
		return ;
	at = 0;
	method_word(line, &at, what);
	line[at++] = ' ';
	method_num(line, &at, g_starts);
	line[at++] = ' ';
	method_num(line, &at, g_deepest);
	line[at++] = '\n';
	fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
	if (fd < 0)
		return ;
	if (write(fd, line, at) < 0)
		at = 0;
	close(fd);
}

__attribute__((no_instrument_function))
void	__cyg_profile_func_enter(void *fn, void *site)
{
	unsigned long	i;

	(void)site;
	g_starts++;
	i = 0;
	while (i < g_depth && i < METHOD_DEPTH)
	{
		if (g_running[i] == fn)
		{
			if (g_depth + 1 > g_deepest)
				g_deepest = g_depth + 1;
			method_report("reentered");
			_exit(0);
		}
		i++;
	}
	if (g_depth < METHOD_DEPTH)
		g_running[g_depth] = fn;
	else
		g_overflow = 1;
	g_depth++;
	if (g_depth > g_deepest)
		g_deepest = g_depth;
}

__attribute__((no_instrument_function))
void	__cyg_profile_func_exit(void *fn, void *site)
{
	(void)fn;
	(void)site;
	if (g_depth > 0)
		g_depth--;
}

/* The run ended by itself with nothing re-entered. */
__attribute__((destructor, no_instrument_function))
static void	method_done(void)
{
	method_report(g_overflow ? "overflow" : "done");
}
