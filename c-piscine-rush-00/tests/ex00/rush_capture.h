/* Shared capture helpers for the rush00 harnesses (grader-side test infra).
 *
 * rush() prints straight to fd 1 and returns nothing, so a harness cannot
 * inspect it the way it would inspect a return value: it has to READ what the
 * student wrote. Every harness here therefore redirects fd 1 to a temporary
 * file, calls rush(x, y), restores fd 1, and reads the bytes back.
 *
 * The captured rectangle is then ESCAPED onto a single line (see rc_escape)
 * with exactly the rules oracle/src/rush00.rs uses, so one case is always one
 * line of output. That is what keeps the PASS/FAIL table aligned: a student who
 * prints four rows instead of three shifts nothing — only their own case fails.
 * It also makes trailing spaces and the final newline VISIBLE in the table,
 * which is precisely where this exercise goes wrong.
 *
 * Two guards protect the machine from a buggy submission: RLIMIT_CPU turns an
 * infinite loop into a prompt death instead of a test-suite hang, and
 * RLIMIT_FSIZE stops a runaway writer from filling the disk. Both are set by
 * rc_guard(), which every harness calls first.
 *
 * These are test readers, not submissions: they use libc freely and need not be
 * norm-compliant. All helpers are `static inline`, so a harness that uses only
 * some of them still compiles clean under -Wall -Wextra -Werror. */
#ifndef RUSH_CAPTURE_H
#define RUSH_CAPTURE_H

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <unistd.h>

/* The student's deliverable. */
void	rush(int x, int y);
void	ft_putchar(char c);

/* Fallback runaway budget, used for the sizes the subject leaves undefined:
 * there is no rectangle to size the output against, so 1 MiB stands in. */
#define RC_RUNAWAY (1024UL * 1024UL)

/* How much output one call may produce before it stops being a rectangle and
 * starts being an unbounded loop.
 *
 * For a LEGAL size the budget is deliberately generous — eight bytes per cell
 * plus eight per row — so that every plausible bug (an extra wall, a trailing
 * space, one row too many, a doubled character) still comes back as a rectangle
 * and is judged, precisely, by the value layers. Only a loop that does not
 * terminate on its own trips this. Being stingy here would report the most
 * common bug in the exercise, one trailing space per row, as a "runaway", which
 * is a flatly wrong diagnosis.
 *
 * For a NON-POSITIVE size there is nothing to scale against, so RC_RUNAWAY
 * applies: printing a megabyte for rush(0, 5) really does mean a loop bound
 * never looked at its sign. */
static inline size_t	rc_runaway_limit(int x, int y)
{
	size_t	cells;

	if (x <= 0 || y <= 0)
		return (RC_RUNAWAY);
	cells = (size_t)x * (size_t)y;
	return (cells * 8 + (size_t)y * 8 + 4096);
}

/* Cap CPU seconds and per-file bytes for the whole harness, and make stdout
 * unbuffered so that if a guard does fire, everything printed BEFORE it has
 * already reached the test runner — the table then shows exactly which case
 * killed the run instead of losing the evidence in a buffer. */
static inline void	rc_guard(unsigned long cpu_secs, unsigned long max_file)
{
	struct rlimit	r;

	r.rlim_cur = (rlim_t)cpu_secs;
	r.rlim_max = (rlim_t)cpu_secs;
	setrlimit(RLIMIT_CPU, &r);
	r.rlim_cur = (rlim_t)max_file;
	r.rlim_max = (rlim_t)max_file;
	setrlimit(RLIMIT_FSIZE, &r);
	setbuf(stdout, NULL);
}

/* Run rush(x, y) with fd 1 redirected to a temp file and return the captured
 * bytes in a fresh malloc'd, NUL-terminated buffer (*len = byte count, which is
 * authoritative: the bytes may contain NULs). NULL means the capture plumbing
 * itself failed, never that the student printed nothing. */
static inline char	*rc_run(int x, int y, size_t *len)
{
	FILE	*tmp;
	int		fd;
	int		saved;
	off_t	n;
	char	*buf;
	size_t	got;
	ssize_t	r;

	*len = 0;
	tmp = tmpfile();
	if (!tmp)
		return (NULL);
	fd = fileno(tmp);
	fflush(stdout);
	saved = dup(STDOUT_FILENO);
	if (saved < 0 || dup2(fd, STDOUT_FILENO) < 0)
	{
		if (saved >= 0)
			close(saved);
		fclose(tmp);
		return (NULL);
	}
	rush(x, y);
	fflush(stdout);
	dup2(saved, STDOUT_FILENO);
	close(saved);
	n = lseek(fd, 0, SEEK_END);
	if (n < 0 || lseek(fd, 0, SEEK_SET) < 0)
	{
		fclose(tmp);
		return (NULL);
	}
	buf = (char *)malloc((size_t)n + 1);
	if (!buf)
	{
		fclose(tmp);
		return (NULL);
	}
	got = 0;
	while (got < (size_t)n)
	{
		r = read(fd, buf + got, (size_t)n - got);
		if (r <= 0)
			break ;
		got += (size_t)r;
	}
	buf[got] = '\0';
	fclose(tmp);
	*len = got;
	return (buf);
}

/* Run rush(x, y) with fd 1 pointed at /dev/null: no capture, no allocation, no
 * disk. Used by the sanitizer probe, where thousands of cases run and only
 * memory safety is under test. Returns 0, or -1 if the plumbing failed. */
static inline int	rc_run_discard(int x, int y)
{
	int	null;
	int	saved;

	null = open("/dev/null", O_WRONLY);
	if (null < 0)
		return (-1);
	fflush(stdout);
	saved = dup(STDOUT_FILENO);
	if (saved < 0 || dup2(null, STDOUT_FILENO) < 0)
	{
		if (saved >= 0)
			close(saved);
		close(null);
		return (-1);
	}
	rush(x, y);
	fflush(stdout);
	dup2(saved, STDOUT_FILENO);
	close(saved);
	close(null);
	return (0);
}

/* One-line escape of captured bytes, byte-identical to oracle/src/rush00.rs:
 *   '\\' -> "\\\\",  '\n' -> "\\n",  0x20..0x7e raw,  anything else -> "\xHH".
 * Escaping the backslash is not optional: variant 1 draws corners with one.
 * Returns a fresh malloc'd string. */
static inline char	*rc_escape(const char *b, size_t n)
{
	static const char	*hex = "0123456789abcdef";
	unsigned char		c;
	char				*out;
	size_t				i;
	size_t				k;

	out = (char *)malloc(n * 4 + 1);
	if (!out)
		return (NULL);
	i = 0;
	k = 0;
	while (i < n)
	{
		c = (unsigned char)b[i++];
		if (c == '\\')
		{
			out[k++] = '\\';
			out[k++] = '\\';
		}
		else if (c == '\n')
		{
			out[k++] = '\\';
			out[k++] = 'n';
		}
		else if (c >= 0x20 && c <= 0x7e)
			out[k++] = (char)c;
		else
		{
			out[k++] = '\\';
			out[k++] = 'x';
			out[k++] = hex[c >> 4];
			out[k++] = hex[c & 0xf];
		}
	}
	out[k] = '\0';
	return (out);
}

/* Print "<label><TAB><escaped rectangle>" for one case — the labeled-table form
 * consumed by tools/diff_output.sh --labeled. A capture failure or a runaway is
 * reported in the value column so the table still has exactly one line here. */
static inline void	rc_print_escaped(const char *label, int x, int y)
{
	char	*buf;
	char	*esc;
	size_t	len;

	buf = rc_run(x, y, &len);
	if (!buf)
	{
		printf("%s\tCAPTURE FAILED\n", label);
		return ;
	}
	if (len > rc_runaway_limit(x, y))
	{
		printf("%s\tRUNAWAY OUTPUT (%lu bytes)\n", label, (unsigned long)len);
		free(buf);
		return ;
	}
	esc = rc_escape(buf, len);
	printf("%s\t%s\n", label, esc ? esc : "ESCAPE FAILED");
	free(esc);
	free(buf);
}

#endif
