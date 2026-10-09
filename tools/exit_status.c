/* exit_status — run a program, and say how it ended: it returned a status, a
 * signal killed it, or its time ran out. Grader-side test infrastructure, never
 * compiled into a deliverable (same standing as tools/perf_run.c), so it uses
 * libc freely.
 *
 * WHY. A shell reports a program killed by signal N as the status 128+N, which
 * is also a status a program can return: `return (-1);` from main is 255, the
 * number a death by "signal 127" would give. The runners read every status
 * above 128 as a crash, so a student's program that returned -1 on an error
 * input -- a status no level judges, by the Run contract -- was reported as
 * "died on signal 127" and failed the basic output test. Once the process is
 * gone the shell has nothing else to go on; waitpid() does: WIFEXITED and
 * WIFSIGNALED are two different answers, and this hands the caller the one the
 * kernel gave. asan_run.sh's "126 and 127 are indistinguishable" had the same
 * cause, and exec failing is a third answer here.
 *
 * WHY THE TIME LIMIT IS HERE TOO. The runners used to put `timeout -s KILL N`
 * in front of this helper. That kills the whole process group, this helper
 * included, so a run that timed out left no report, and the shell running it
 * saw its child die of SIGKILL -- which dash and bash announce with a line of
 * their own, "Killed", written into whatever the run's stderr was redirected
 * to: the student's stderr file, or the compared stream itself. Here the child
 * gets a process group of its own, the alarm kills that group, and this
 * helper RETURNS: the report says "timeout", and no shell announces anything.
 *
 * AND A SIGNAL SENT TO THE TEST REACHES THE PROGRAM. Bazel stops a test that
 * runs out of time with SIGTERM. A shell runs its trap only once its
 * foreground command returns, so a runner waiting on a program that never
 * ends used to wait until Bazel's SIGKILL. SIGTERM, SIGINT or SIGHUP here
 * kills the child's group at once, reports "stopped" and returns, so the
 * runner's own trap runs. A group of its own also means a kill aimed at the
 * test's group misses the program, so the child asks the kernel for SIGKILL
 * when this helper dies (PR_SET_PDEATHSIG): a program that never ends is not
 * left running when the helper is killed outright. What that program started
 * itself is covered by a CPU-time limit, SECONDS plus a margin, which it and
 * its children inherit: one that spins forever after an orphaning is stopped
 * by the kernel. A run that finishes inside its wall-clock limit never nears
 * it, since a single thread cannot use more CPU than time.
 *
 * A LIMIT IS THE RUN'S OWN TIME (finding 066). SECONDS is wall time less the
 * time the run waited on the run queue for a CPU, which a busy machine adds
 * and this gives back (tools/runqueue.h says how it is read, and why): a
 * correct program on a machine running two suites at once is not stopped for
 * the queue it stood in, and one that sleeps or blocks forever waits on no
 * queue and is stopped on the wall clock. One that spins forever queues as a
 * correct one does and is given that back too, so on a busy machine it is
 * stopped later in wall time, after SECONDS of its own (runqueue.h). Never
 * past --ceiling CEIL seconds of wall time, the most the test has left;
 * without it, no time is given back.
 *
 * Usage:
 *   exit_status [--timeout SECONDS [--ceiling CEIL]] REPORT PROG [ARG...]
 *
 * Runs PROG with this process's stdin, stdout and stderr, in a process group of
 * its own, waits for it, and writes one line to REPORT:
 *   exit N      it returned N from main, or called exit(N)
 *   signal N    signal N killed it (25, SIGXFSZ, is `ulimit -f` stopping it)
 *   noexec E    it could not be started at all (E is why): exec failed, or
 *               the dynamic loader stopped it before main (E is then the
 *               loader's own message; see THE LOADER IS NOT THE PROGRAM)
 *   timeout S   SECONDS of its own time passed (S is SECONDS), or the
 *               ceiling did first (S is CEIL), and its group was killed; a
 *               second line, "queued Q", says Q seconds of waiting for a CPU
 *               were given back, and "ceiling Q" that the ceiling stopped it
 *               with that much given back
 *   stopped N   this helper received signal N and killed the group
 * then exits with the status a shell would have reported for the first three
 * (N, 128+N, 127/126), 124 for a timeout and 128+N for a stop -- always by
 * RETURNING, so a caller that reads only $? still sees what it always saw and
 * no shell prints a "Killed" line. No report at all means this helper itself
 * was stopped from outside (a SIGKILL); a stale one is removed first.
 *
 * THE LOADER IS NOT THE PROGRAM. exec succeeding does not mean the program
 * ran. A dynamically linked binary is started by ld.so, which then loads its
 * shared libraries; when one is missing, lacks a symbol or lacks a version,
 * the loader prints why and exits -- 127, or 1 for a missing version -- and
 * main is never reached (a symbol bound lazily fails at its first call
 * instead: the binary is as broken). waitpid() reports that as a plain exit,
 * the same as a program returning 127. asan_run.sh, whose whole verdict is
 * how the run ended, called it "memory-clean (exit 127)" (review of wave 3's
 * output tables; reproduced with a binary whose .so was deleted). So when the run
 * returned non-zero and its stderr is a regular file -- every runner that
 * keeps stderr sends it to one -- the lines it wrote there are read back,
 * and a line in glibc's loader format is reported as noexec:
 *     PROG: error while loading shared libraries: ...
 *     PROG: symbol lookup error: ...
 *     PROG: LIB: version `V' not found (required by ...)
 * PROG is this program's argv[0], which the loader names itself by, so a
 * message about some other binary the program ran is not one. musl's loader
 * words it differently; no binary the harness runs is linked dynamically
 * against musl (the ilp32 rebuilds are static), so it is not read. Where stderr
 * is not a regular file (a pipe, /dev/null) or /proc cannot reopen it, a
 * loader failure reads as the exit it gives, as before.
 */
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include "runqueue.h"

static pid_t					g_child = -1;
static volatile sig_atomic_t	g_timed_out = 0;
static volatile sig_atomic_t	g_stop_sig = 0;

static volatile sig_atomic_t	g_alarm = 0;

/* The alarm only says the time to look has come: whether the run is out of
 * its own time is read in main (rq_next), where reading /proc is safe. */
static void	on_alarm(int sig)
{
	(void)sig;
	g_alarm = 1;
}

static void	on_stop(int sig)
{
	g_stop_sig = sig;
	if (g_child > 0)
		kill(-g_child, SIGKILL);
}

static int	report2(const char *path, const char *kind, const char *what,
		const char *more)
{
	FILE	*f;

	f = fopen(path, "w");
	if (!f)
	{
		fprintf(stderr, "exit_status: cannot write '%s': %s\n", path, strerror(errno));
		return (-1);
	}
	fprintf(f, "%s %s\n", kind, what);
	if (more)
		fprintf(f, "%s\n", more);
	return (fclose(f) == 0 ? 0 : -1);
}

static int	report(const char *path, const char *kind, const char *what)
{
	return (report2(path, kind, what, NULL));
}

static void	catch(int sig, void (*fn)(int))
{
	struct sigaction	sa;

	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = fn;
	sigemptyset(&sa.sa_mask);
	sigaction(sig, &sa, NULL);
}

/* Where this run's stderr starts in its file, or -1 when it is not a regular
 * file this can read back. Taken before the fork: the program shares the
 * offset. With O_APPEND every write lands at the end, whatever the offset
 * says, so the end is where the program's first byte will go. */
static off_t	stderr_start(void)
{
	struct stat	st;
	int			flags;

	if (fstat(2, &st) != 0 || !S_ISREG(st.st_mode))
		return (-1);
	flags = fcntl(2, F_GETFL);
	if (flags == -1)
		return (-1);
	if (flags & O_APPEND)
		return (st.st_size);
	return (lseek(2, 0, SEEK_CUR));
}

/* Where WORD first occurs in the LEN bytes at S, or -1. */
static long	find(const char *s, size_t len, const char *word)
{
	size_t	wlen;
	size_t	i;

	wlen = strlen(word);
	i = 0;
	while (i + wlen <= len)
	{
		if (memcmp(s + i, word, wlen) == 0)
			return ((long)i);
		i++;
	}
	return (-1);
}

/* Is LINE (LEN bytes, not NUL-terminated) the loader saying PROG never
 * started? Its message is "PROG: " and then one of three forms. Returns what
 * follows "PROG: ", or NULL. */
static const char	*loader_says(const char *line, size_t len, const char *prog)
{
	size_t		plen;
	const char	*rest;
	size_t		rlen;
	long		v;

	plen = strlen(prog);
	if (len < plen + 2 || memcmp(line, prog, plen) != 0
		|| line[plen] != ':' || line[plen + 1] != ' ')
		return (NULL);
	rest = line + plen + 2;
	rlen = len - plen - 2;
	if (find(rest, rlen, "error while loading shared libraries: ") == 0
		|| find(rest, rlen, "symbol lookup error: ") == 0)
		return (rest);
	v = find(rest, rlen, "version `");
	if (v >= 0 && find(rest + v, rlen - (size_t)v, "' not found (required by ") > 0)
		return (rest);
	return (NULL);
}

/* After a non-zero exit: did the loader stop PROG before main? Reads what the
 * run wrote to stderr from START, and copies the loader's line, without
 * "PROG: ", into WHY. */
static int	loader_failed(off_t start, const char *prog, char *why, size_t size)
{
	char		buf[4096];
	int			fd;
	ssize_t		n;
	char		*line;
	char		*end;
	const char	*said;
	size_t		len;

	fd = open("/proc/self/fd/2", O_RDONLY);
	if (fd < 0)
		return (0);
	n = pread(fd, buf, sizeof(buf), start);
	close(fd);
	if (n <= 0)
		return (0);
	line = buf;
	while (line < buf + n)
	{
		end = memchr(line, '\n', (size_t)(buf + n - line));
		if (!end)
			end = buf + n;
		said = loader_says(line, (size_t)(end - line), prog);
		if (said)
		{
			len = (size_t)(end - said);
			if (len >= size)
				len = size - 1;
			memcpy(why, said, len);
			why[len] = '\0';
			return (1);
		}
		line = end + 1;
	}
	return (0);
}

int	main(int argc, char **argv)
{
	int		fds[2];
	pid_t	pid;
	pid_t	me;
	int		status;
	int		err;
	ssize_t	n;
	char	num[16];
	int				timeout_s;
	int				ceiling_s;
	double			started;
	double			waited;
	unsigned int	next;
	char			more[64];
	int				a;
	struct rlimit	lim;
	off_t			errat;
	char			why[512];

	timeout_s = 0;
	ceiling_s = 0;
	a = 1;
	while (argc - a > 2 && (strcmp(argv[a], "--timeout") == 0
			|| strcmp(argv[a], "--ceiling") == 0))
	{
		if (strcmp(argv[a], "--timeout") == 0)
			timeout_s = atoi(argv[a + 1]);
		else
			ceiling_s = atoi(argv[a + 1]);
		a += 2;
	}
	if (argc - a < 2)
	{
		fprintf(stderr, "exit_status: usage: exit_status [--timeout S [--ceiling C]] REPORT PROG [ARG...]\n");
		return (2);
	}
	if (ceiling_s < timeout_s)
		ceiling_s = timeout_s;
	if (unlink(argv[a]) != 0 && errno != ENOENT)
	{
		fprintf(stderr, "exit_status: cannot clear '%s': %s\n", argv[a], strerror(errno));
		return (2);
	}
	errat = stderr_start();
	/* A close-on-exec pipe: a successful exec closes the child's end with
	 * nothing written, and a failed one writes errno down it. */
	if (pipe(fds) != 0 || fcntl(fds[1], F_SETFD, FD_CLOEXEC) != 0)
	{
		perror("exit_status: pipe");
		return (2);
	}
	/* Before the fork, so a signal between fork and exec already finds the
	 * handler; the child restores the defaults before it execs. */
	catch(SIGTERM, on_stop);
	catch(SIGINT, on_stop);
	catch(SIGHUP, on_stop);
	me = getpid();
	pid = fork();
	if (pid < 0)
	{
		perror("exit_status: fork");
		return (2);
	}
	if (pid == 0)
	{
		signal(SIGTERM, SIG_DFL);
		signal(SIGINT, SIG_DFL);
		signal(SIGHUP, SIG_DFL);
		setpgid(0, 0);
		/* Checked after asking: a parent that died before the request would
		 * never send it. */
		if (prctl(PR_SET_PDEATHSIG, SIGKILL) != 0 || getppid() != me)
			_exit(127);
		if (timeout_s > 0)
		{
			lim.rlim_cur = (rlim_t)timeout_s + 10;
			lim.rlim_max = (rlim_t)timeout_s + 15;
			setrlimit(RLIMIT_CPU, &lim);
		}
		close(fds[0]);
		execvp(argv[a + 1], &argv[a + 1]);
		err = errno;
		if (write(fds[1], &err, sizeof(err)) < 0)
			_exit(127);
		_exit(err == ENOENT ? 127 : 126);
	}
	/* Both sides set the group, so neither the alarm nor a stop can land
	 * between the fork and the child's own setpgid and miss it. */
	setpgid(pid, pid);
	g_child = pid;
	if (g_stop_sig)
		kill(-pid, SIGKILL);
	close(fds[1]);
	do
		n = read(fds[0], &err, sizeof(err));
	while (n < 0 && errno == EINTR);
	close(fds[0]);
	started = rq_now();
	waited = 0;
	if (timeout_s > 0 && n != (ssize_t)sizeof(err))
	{
		catch(SIGALRM, on_alarm);
		alarm((unsigned int)timeout_s);
	}
	while (waitpid(pid, &status, 0) < 0)
	{
		if (errno != EINTR)
		{
			perror("exit_status: waitpid");
			return (2);
		}
		if (!g_alarm || g_timed_out)
			continue ;
		g_alarm = 0;
		/* Its own time, the queue's given back, up to the ceiling. */
		waited = rq_group_waited(pid);
		next = rq_next(rq_now() - started, waited, timeout_s, ceiling_s);
		if (next > 0)
			alarm(next);
		else
		{
			g_timed_out = 1;
			kill(-pid, SIGKILL);
		}
	}
	alarm(0);
	if (n == (ssize_t)sizeof(err))
	{
		/* ENOENT for a file that is there is about the interpreter its #!
		 * line names (a CRLF line ending makes that "/bin/sh\r"), or an
		 * ELF's loader: "No such file or directory" alone sends a reader
		 * looking for the wrong file. */
		if (err == ENOENT && strchr(argv[a + 1], '/') && access(argv[a + 1], F_OK) == 0)
			snprintf(why, sizeof(why), "%s: not the file, which is there, but the "
				"interpreter its #! line names (or an ELF binary's loader)",
				strerror(err));
		else
			snprintf(why, sizeof(why), "%s", strerror(err));
		if (report(argv[a], "noexec", why) != 0)
			return (2);
		return (err == ENOENT ? 127 : 126);
	}
	if (g_stop_sig && WIFSIGNALED(status))
	{
		snprintf(num, sizeof(num), "%d", (int)g_stop_sig);
		if (report(argv[a], "stopped", num) != 0)
			return (2);
		return (128 + g_stop_sig);
	}
	if (g_timed_out && WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL)
	{
		/* Which ran out: its own time, or the ceiling first. */
		more[0] = '\0';
		if (waited >= 0 && rq_now() - started - waited < timeout_s - 0.5)
		{
			snprintf(num, sizeof(num), "%d", ceiling_s);
			snprintf(more, sizeof(more), "ceiling %d", (int)(waited + 0.5));
		}
		else
		{
			snprintf(num, sizeof(num), "%d", timeout_s);
			if (waited >= 1)
				snprintf(more, sizeof(more), "queued %d", (int)(waited + 0.5));
		}
		if (report2(argv[a], "timeout", num, more[0] ? more : NULL) != 0)
			return (2);
		return (124);
	}
	if (WIFSIGNALED(status))
	{
		snprintf(num, sizeof(num), "%d", WTERMSIG(status));
		if (report(argv[a], "signal", num) != 0)
			return (2);
		return (128 + WTERMSIG(status));
	}
	if (WEXITSTATUS(status) != 0 && errat >= 0
		&& loader_failed(errat, argv[a + 1], why, sizeof(why)))
	{
		if (report(argv[a], "noexec", why) != 0)
			return (2);
		return (WEXITSTATUS(status));
	}
	snprintf(num, sizeof(num), "%d", WEXITSTATUS(status));
	if (report(argv[a], "exit", num) != 0)
		return (2);
	return (WEXITSTATUS(status));
}
