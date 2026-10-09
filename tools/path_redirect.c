/* path_redirect — a preload library: a program that opens one fixed path
 * reads a fixture in its place. Grader-side test infrastructure, never
 * compiled into a deliverable (same standing as tools/exit_status.c), so it
 * uses libc freely.
 *
 * WHY. Shell 01 ex07 reads /etc/passwd, a path its subject fixes, and what a
 * machine keeps there decides which of the exercise's steps a test can see.
 * A laptop's file has no comment line, so "Remove comments" was never
 * exercised; its logins are plain lowercase words, so the two readings of
 * "reverse alphabetical order" (bytes, or the locale's collation) printed the
 * same list; and one with few users was too short for the subject's own
 * 7..15 window. The file cannot be replaced -- that needs root, and a mount
 * namespace is refused inside the dev container -- so the program is handed
 * the fixture when it asks for the path, and every step is seen on every
 * machine (finding 026, TODO.md §23).
 *
 * HOW. Loaded into the student's run through LD_PRELOAD, by shell_check.sh's
 * ck_run, only when the exercise's BUILD call declares a redirect (defs.bzl's
 * shell_exercise, `redirect`). Every call that opens a file by name --
 * open, open64, openat, openat64, their _FORTIFY_SOURCE forms, fopen,
 * fopen64 and freopen -- is taken here first: a name that is exactly
 * $CK_REDIRECT_FROM becomes $CK_REDIRECT_TO, and the real call does the rest.
 * Any other name, and every call when either variable is unset, goes through
 * untouched. That covers any program that opens the file by that name, and
 * the shell's own `<`, because each of them opens the file itself.
 *
 * WHAT IT CANNOT REACH, which is why tools/shell_test.sh probes it before the
 * check runs and the check says so when it did not take: a program that
 * asks the C library for users (NSS) rather than opening the file, where a
 * preloaded symbol is never called; a name spelled another way than the
 * redirected path; and a statically linked program, which no preload
 * reaches.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>

typedef int (*t_open)(const char *, int, ...);
typedef int (*t_openat)(int, const char *, int, ...);
typedef int (*t_open2)(const char *, int);
typedef int (*t_openat2)(int, const char *, int);
typedef FILE *(*t_fopen)(const char *, const char *);
typedef FILE *(*t_freopen)(const char *, const char *, FILE *);

/* The name the real call is given: the fixture's for the redirected path,
 * the caller's own for any other. */
static const char *target(const char *path)
{
	const char *from = getenv("CK_REDIRECT_FROM");
	const char *to = getenv("CK_REDIRECT_TO");

	if (path != NULL && from != NULL && to != NULL && from[0] != '\0'
		&& strcmp(path, from) == 0)
		return to;
	return path;
}

/* The next definition of `name` after this library's: libc's. */
static void *next(const char *name)
{
	return dlsym(RTLD_NEXT, name);
}

/* The mode argument, which open and openat read only when they create: the
 * test glibc's own wrappers make (__OPEN_NEEDS_MODE). O_TMPFILE holds
 * O_DIRECTORY's bit, so `flags & O_TMPFILE` alone would read an argument
 * that a plain open of a directory never passed. */
static mode_t mode_arg(int flags, va_list ap)
{
	if ((flags & O_CREAT) != 0 || (flags & O_TMPFILE) == O_TMPFILE)
		return (mode_t)va_arg(ap, int);
	return 0;
}

int open(const char *path, int flags, ...)
{
	static t_open real;
	va_list ap;
	mode_t mode;

	if (real == NULL)
		real = (t_open)next("open");
	va_start(ap, flags);
	mode = mode_arg(flags, ap);
	va_end(ap);
	return real(target(path), flags, mode);
}

int open64(const char *path, int flags, ...)
{
	static t_open real;
	va_list ap;
	mode_t mode;

	if (real == NULL)
		real = (t_open)next("open64");
	va_start(ap, flags);
	mode = mode_arg(flags, ap);
	va_end(ap);
	return real(target(path), flags, mode);
}

int openat(int dir, const char *path, int flags, ...)
{
	static t_openat real;
	va_list ap;
	mode_t mode;

	if (real == NULL)
		real = (t_openat)next("openat");
	va_start(ap, flags);
	mode = mode_arg(flags, ap);
	va_end(ap);
	return real(dir, target(path), flags, mode);
}

int openat64(int dir, const char *path, int flags, ...)
{
	static t_openat real;
	va_list ap;
	mode_t mode;

	if (real == NULL)
		real = (t_openat)next("openat64");
	va_start(ap, flags);
	mode = mode_arg(flags, ap);
	va_end(ap);
	return real(dir, target(path), flags, mode);
}

/* What a program built with _FORTIFY_SOURCE calls for an open() whose flags
 * the compiler could not see. */
int __open_2(const char *path, int flags)
{
	static t_open2 real;

	if (real == NULL)
		real = (t_open2)next("__open_2");
	return real(target(path), flags);
}

int __open64_2(const char *path, int flags)
{
	static t_open2 real;

	if (real == NULL)
		real = (t_open2)next("__open64_2");
	return real(target(path), flags);
}

int __openat_2(int dir, const char *path, int flags)
{
	static t_openat2 real;

	if (real == NULL)
		real = (t_openat2)next("__openat_2");
	return real(dir, target(path), flags);
}

int __openat64_2(int dir, const char *path, int flags)
{
	static t_openat2 real;

	if (real == NULL)
		real = (t_openat2)next("__openat64_2");
	return real(dir, target(path), flags);
}

/* stdio opens through libc's internal open, which no preload reaches, so
 * fopen is taken by name too. */
FILE *fopen(const char *path, const char *mode)
{
	static t_fopen real;

	if (real == NULL)
		real = (t_fopen)next("fopen");
	return real(target(path), mode);
}

FILE *fopen64(const char *path, const char *mode)
{
	static t_fopen real;

	if (real == NULL)
		real = (t_fopen)next("fopen64");
	return real(target(path), mode);
}

FILE *freopen(const char *path, const char *mode, FILE *stream)
{
	static t_freopen real;

	if (real == NULL)
		real = (t_freopen)next("freopen");
	return real(target(path), mode, stream);
}
