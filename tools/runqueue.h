/* runqueue.h — how long a run has waited for a CPU, for the two helpers that
 * bound a run of student code by time (tools/exit_status.c, tools/perf_run.c).
 * Grader-side test infrastructure, never compiled into a deliverable.
 *
 * WHY (finding 066). A per-run limit -- argv_check's 5s a case, Rush 00's
 * survive cases, perf's 25s a size -- was a wall clock. On a machine running
 * two suites at once (load 60 on 24 cores) a correct program spent most of
 * that clock waiting for a CPU, not running: the same 3.3s of work took 11.2s
 * with three busy loops sharing its core, 8.4s of it on the run queue. So the
 * limit failed correct work, or measured nothing, depending on what else the
 * machine was doing -- a verdict that depends on which computer you sat at.
 *
 * THE RUN'S OWN TIME is what a limit bounds now: the wall time it took, less
 * the time it was runnable and waiting for a CPU, which the kernel counts
 * per task in /proc/PID/schedstat (its second field, in nanoseconds). A busy
 * machine adds queue time and the limit gives it back. Never past the run's
 * CEILING, a wall clock of its own (what is left of the test's limit), so a
 * test still ends before Bazel's.
 *
 * What that does to a run that never ends depends on how it never ends. One
 * that sleeps or blocks waits on no queue, and is stopped on the wall clock,
 * busy machine or not. One that SPINS is runnable, so it stands in the queue
 * as a correct program does and is given that time back too: it is stopped
 * after its limit of its own CPU time, which on a machine with three busy
 * loops on its core took three times the limit in wall time (a 2s limit,
 * 6s), up to the ceiling. So on a loaded machine a test whose cases all loop
 * spends about load times its per-case limit on each, and its later cases
 * meet the ceiling -- what is left of the test -- before their own limit:
 * each is still stopped, and says the time it was given back.
 *
 * Where /proc/PID/schedstat cannot be read (a kernel built without it, no
 * /proc), nothing is given back: the limit is the wall clock, as before.
 * The process group's members are read, and the longest wait counts: a shell
 * check runs the turn-in as children of a shell that itself mostly waits, and
 * the members of a pipeline wait side by side, so a sum would count one wait
 * twice. A member that already ended took its wait with it.
 */
#ifndef RUNQUEUE_H
# define RUNQUEUE_H

# include <dirent.h>
# include <stdio.h>
# include <stdlib.h>
# include <sys/types.h>
# include <time.h>

/* Seconds on a monotonic clock. */
static inline double	rq_now(void)
{
	struct timespec	ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ((double)ts.tv_sec + (double)ts.tv_nsec / 1e9);
}

/* The seconds task PID has spent runnable and waiting for a CPU, or -1. */
static inline double	rq_task_waited(long pid)
{
	char				path[64];
	FILE				*f;
	unsigned long long	run;
	unsigned long long	wait;
	int					got;

	snprintf(path, sizeof(path), "/proc/%ld/schedstat", pid);
	f = fopen(path, "r");
	if (!f)
		return (-1);
	got = fscanf(f, "%llu %llu", &run, &wait);
	fclose(f);
	if (got != 2)
		return (-1);
	return ((double)wait / 1e9);
}

/* The process group PGRP's longest wait for a CPU, in seconds; -1 when the
 * leader's cannot be read. */
static inline double	rq_group_waited(pid_t pgrp)
{
	double			most;
	double			w;
	DIR				*d;
	struct dirent	*e;
	char			path[64];
	char			buf[512];
	FILE			*f;
	char			*close_paren;
	long			pid;
	long			grp;

	most = rq_task_waited((long)pgrp);
	if (most < 0)
		return (-1);
	d = opendir("/proc");
	if (!d)
		return (most);
	while ((e = readdir(d)) != NULL)
	{
		pid = strtol(e->d_name, NULL, 10);
		if (pid <= 0 || pid == (long)pgrp)
			continue ;
		snprintf(path, sizeof(path), "/proc/%ld/stat", pid);
		f = fopen(path, "r");
		if (!f)
			continue ;
		if (!fgets(buf, sizeof(buf), f))
			buf[0] = '\0';
		fclose(f);
		/* pid (comm) state ppid pgrp ...: comm may hold anything but the
		 * last ')' ends it. */
		close_paren = strrchr(buf, ')');
		if (!close_paren || sscanf(close_paren + 1, " %*c %*d %ld", &grp) != 1
			|| grp != (long)pgrp)
			continue ;
		w = rq_task_waited(pid);
		if (w > most)
			most = w;
	}
	closedir(d);
	return (most);
}

/* How many seconds to wait before looking again, for a run that has taken
 * ELAPSED seconds of wall time and WAITED of them on the run queue, under
 * an own-time LIMIT and a wall CEILING; 0 when it is to be stopped now: its
 * own time is spent, the ceiling is reached, or WAITED is unknown (-1, the
 * wall clock alone). */
static inline unsigned int	rq_next(double elapsed, double waited, int limit,
		int ceiling)
{
	double	left;
	double	to_ceiling;

	if (waited < 0)
		return (0);
	left = (double)limit - (elapsed - waited);
	to_ceiling = (double)ceiling - elapsed;
	if (left < 0.5 || to_ceiling < 0.5)
		return (0);
	if (left > to_ceiling)
		left = to_ceiling;
	return ((unsigned int)(left + 0.999));
}

#endif
