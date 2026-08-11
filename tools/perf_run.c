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
 *   perf_run [--stdin FILE] -- CMD [ARG...]
 *
 * Prints one line to stdout:
 *   ms=<wall-ms> cpums=<cpu-ms> rss=<peak-kilobytes> exit=<child-exit-status>
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

/* The child, so the alarm handler can kill it. A measurement has to be bounded:
 * an implementation slow enough to matter is slow enough to hang the layer, and
 * "did not finish" is itself the finding rather than a reason to wait. */
static pid_t	g_child = -1;

static void	on_alarm(int sig)
{
	(void)sig;
	if (g_child > 0)
		kill(g_child, SIGKILL);
}

int	main(int argc, char **argv)
{
	const char		*stdin_path = NULL;
	int				timeout_s = 0;
	int				i = 1;
	struct timespec	t0;
	struct timespec	t1;
	pid_t			pid;
	int				status = 0;
	struct rusage	ru;
	long			ms;
	long			cpums;

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
		else
		{
			fprintf(stderr, "perf_run: unknown option: %s\n", argv[i]);
			return (2);
		}
	}
	if (i >= argc || strcmp(argv[i], "--") != 0 || i + 1 >= argc)
	{
		fprintf(stderr, "perf_run: usage: perf_run [--stdin FILE] [--timeout S] -- CMD [ARG...]\n");
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
	g_child = pid;
	if (timeout_s > 0)
	{
		signal(SIGALRM, on_alarm);
		alarm((unsigned int)timeout_s);
	}
	/* wait4 gives us the child's peak RSS alongside its status, which is the
	 * whole reason this wrapper exists rather than a shell one-liner. */
	if (wait4(pid, &status, 0, &ru) < 0)
	{
		perror("perf_run: wait4");
		return (2);
	}
	clock_gettime(CLOCK_MONOTONIC, &t1);
	ms = (t1.tv_sec - t0.tv_sec) * 1000
		+ (t1.tv_nsec - t0.tv_nsec) / 1000000;
	cpums = (ru.ru_utime.tv_sec + ru.ru_stime.tv_sec) * 1000
		+ (ru.ru_utime.tv_usec + ru.ru_stime.tv_usec) / 1000;
	printf("ms=%ld cpums=%ld rss=%ld exit=%d\n", ms < 0 ? 0 : ms,
		cpums < 0 ? 0 : cpums, (long)ru.ru_maxrss,
		WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status));
	return (0);
}
