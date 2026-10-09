/* perf_run — run a command and report how long it took and how much memory it
 * peaked at. Grader-side test infrastructure: never compiled into a
 * deliverable, so it uses libc freely and need not be norm-compliant.
 *
 * Why this exists: the performance layer needs wall time AND peak resident set
 * size, and neither is available portably from POSIX sh. GNU `time -v` would
 * give both but is not installed in the devcontainer (and is not guaranteed on
 * the campus box either), while the shell's own `times` reports CPU only and
 * never memory. wait4() hands us both from the kernel for free, so a ~50-line
 * wrapper removes the dependency entirely.
 *
 * Usage:
 *   perf_run [--stdin FILE] [--timeout S [--ceiling C]] -- CMD [ARG...]
 *
 * --timeout S bounds the run by its OWN time: wall time less what it waited
 * on the run queue for a CPU, which a busy machine adds and this gives back
 * (tools/runqueue.h), never past C seconds of wall time (what the test has
 * left; without --ceiling, nothing is given back). A fixed wall clock had
 * perf halve a correct program's sizes on a loaded machine and measure less,
 * or nothing (finding 066).
 *
 * Prints one line to stdout:
 *   ms=<wall-ms> cpums=<cpu-ms> rss=<peak-kilobytes> exit=<how it ended>
 *
 * where <how it ended> is the status the child RETURNED (a number, 0 to 255),
 * "timeout" when its own time (--timeout) ran out and it was killed,
 * "ceiling" when the ceiling's wall clock (--ceiling, what the test has
 * left) ran out first and it was killed, or "sigN" when signal N killed it.
 * Never 128+N: that is also a status a program can return (`return (-1);`
 * is 255), and wait4() already says which it was. "ceiling" is its own word
 * because the two are different reports: a run stopped by the ceiling used
 * less than its limit of its own time, and perf_test.sh said it "did not
 * finish within 25s (PERF_TIMEOUT)" of it (exit_status says the same with
 * its "ceiling Q" line).
 *
 * BOTH clocks, because they answer different questions and only one of them can
 * be trusted to compare two runs. Wall time is what a human waits and is the
 * honest number to show; it also counts every millisecond this process spent
 * descheduled while the rest of the test suite competed for the same cores, so
 * repeating an identical run can hand back numbers that differ several-fold.
 * cpums is the child's own user+system time straight out of the same rusage
 * wait4 already fills in: time somebody else was running is not in it. The
 * performance layer fits its growth exponent on cpums for that reason -- an
 * exponent fitted on wall time is fitted partly on how busy the machine was.
 *
 * The child's own stdout/stderr go to /dev/null: this tool measures, it does
 * not diff. Correctness is the diff layer's job.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <sys/wait.h>
#include <sys/resource.h>
#include <signal.h>
#include <errno.h>
#include "runqueue.h"

/* A measurement has to be bounded: an implementation slow enough to matter
 * is slow enough to hang the layer, and "did not finish" is itself the
 * finding rather than a reason to wait. The alarm says when to look; main
 * decides whether the run's own time is spent (rq_next). */
static volatile sig_atomic_t	g_timed_out = 0;
static volatile sig_atomic_t	g_alarm = 0;
static int						g_ceiling = 0;

static void	on_alarm(int sig)
{
	(void)sig;
	g_alarm = 1;
}

int	main(int argc, char **argv)
{
	const char		*stdin_path = NULL;
	int				timeout_s = 0;
	int				ceiling_s = 0;
	struct sigaction	sa;
	unsigned int	next;
	int				i = 1;
	struct timespec	t0;
	struct timespec	t1;
	pid_t			pid;
	int				status = 0;
	struct rusage	ru;
	long			ms;
	long			cpums;
	double			elapsed;
	double			waited;

	while (i < argc && strcmp(argv[i], "--") != 0)
	{
		if (strcmp(argv[i], "--stdin") == 0 && i + 1 < argc)
		{
			stdin_path = argv[i + 1];
			i += 2;
		}
		else if (strcmp(argv[i], "--timeout") == 0 && i + 1 < argc)
		{
			timeout_s = atoi(argv[i + 1]);
			i += 2;
		}
		else if (strcmp(argv[i], "--ceiling") == 0 && i + 1 < argc)
		{
			ceiling_s = atoi(argv[i + 1]);
			i += 2;
		}
		else
		{
			fprintf(stderr, "perf_run: unknown option: %s\n", argv[i]);
			return (2);
		}
	}
	if (i >= argc || strcmp(argv[i], "--") != 0 || i + 1 >= argc)
	{
		fprintf(stderr, "perf_run: usage: perf_run [--stdin FILE] [--timeout S [--ceiling C]] -- CMD [ARG...]\n");
		return (2);
	}
	i++;
	clock_gettime(CLOCK_MONOTONIC, &t0);
	pid = fork();
	if (pid < 0)
	{
		perror("perf_run: fork");
		return (2);
	}
	if (pid == 0)
	{
		int	devnull = open("/dev/null", O_WRONLY);
		int	in;

		if (stdin_path)
		{
			in = open(stdin_path, O_RDONLY);
			if (in < 0)
			{
				perror("perf_run: open stdin");
				_exit(127);
			}
			dup2(in, 0);
		}
		if (devnull >= 0)
		{
			dup2(devnull, 1);
			dup2(devnull, 2);
		}
		execv(argv[i], &argv[i]);
		perror("perf_run: exec");
		_exit(127);
	}
	if (ceiling_s < timeout_s)
		ceiling_s = timeout_s;
	if (timeout_s > 0)
	{
		/* No SA_RESTART: the alarm has to interrupt wait4 to be looked at. */
		memset(&sa, 0, sizeof(sa));
		sa.sa_handler = on_alarm;
		sigemptyset(&sa.sa_mask);
		sigaction(SIGALRM, &sa, NULL);
		alarm((unsigned int)timeout_s);
	}
	/* wait4 gives us the child's peak RSS alongside its status, which is the
	 * whole reason this wrapper exists rather than a shell one-liner. */
	while (wait4(pid, &status, 0, &ru) < 0)
	{
		if (errno != EINTR)
		{
			perror("perf_run: wait4");
			return (2);
		}
		if (!g_alarm || g_timed_out)
			continue ;
		g_alarm = 0;
		clock_gettime(CLOCK_MONOTONIC, &t1);
		elapsed = (double)(t1.tv_sec - t0.tv_sec)
			+ (double)(t1.tv_nsec - t0.tv_nsec) / 1e9;
		waited = rq_task_waited((long)pid);
		next = rq_next(elapsed, waited, timeout_s, ceiling_s);
		if (next > 0)
			alarm(next);
		else
		{
			/* Which ran out: its own time, or the ceiling first (as
			 * exit_status tells them apart). */
			g_ceiling = (waited >= 0 && elapsed - waited < timeout_s - 0.5);
			g_timed_out = 1;
			kill(pid, SIGKILL);
		}
	}
	alarm(0);
	clock_gettime(CLOCK_MONOTONIC, &t1);
	ms = (t1.tv_sec - t0.tv_sec) * 1000
		+ (t1.tv_nsec - t0.tv_nsec) / 1000000;
	cpums = (ru.ru_utime.tv_sec + ru.ru_stime.tv_sec) * 1000
		+ (ru.ru_utime.tv_usec + ru.ru_stime.tv_usec) / 1000;
	printf("ms=%ld cpums=%ld rss=%ld exit=", ms < 0 ? 0 : ms,
		cpums < 0 ? 0 : cpums, (long)ru.ru_maxrss);
	if (WIFEXITED(status))
		printf("%d\n", WEXITSTATUS(status));
	else if (g_timed_out && WTERMSIG(status) == SIGKILL)
		printf("%s\n", g_ceiling ? "ceiling" : "timeout");
	else
		printf("sig%d\n", WTERMSIG(status));
	return (0);
}
