/* argv_guard_main.c — the entry point of a GUARDED argv replay: the student's
 * main() runs on an argv the sanitizer can see the edges of. Grader-side test
 * infrastructure, never compiled into a deliverable.
 *
 * WHY. The kernel lays argv and its strings out on the initial stack, one
 * after another, in memory AddressSanitizer does not poison. A program that
 * reads one byte past an argument's terminator reads the next argument, and
 * one that reads argv[argc + 1] reads the environment: both come back with
 * bytes, and the sanitizer replay of the same invocations saw nothing
 * (finding 071). Here every argument is copied into a heap block of exactly
 * its size, terminator included, and argv into one of exactly argc + 1
 * pointers, so either read lands in a redzone and is a heap-buffer-overflow
 * report naming the line.
 *
 * HOW. c_argv_table links the student's sources, untouched, beside this file
 * under ASan with -Wl,--wrap=main: the C runtime's call to main() reaches
 * __wrap_main below, which calls theirs as __real_main. Their main() keeps its
 * name, and with it what C gives main alone -- reaching its closing brace
 * returns 0. Renaming it (-Dmain=...) took that away: a main() with no return
 * statement, which the grader's build compiles, became a function that ends
 * without returning a value, and -Werror refused the guarded build of a
 * correct program. Leak detection is off for every sanitizer runner here
 * (tools/runner_lib.sh, rl_sanitizers), so the copies are not freed: the
 * student may have swapped or replaced argv's entries, and freeing what they
 * now hold would be a test of this file, not of theirs.
 */
#include <stdlib.h>
#include <string.h>

int	__real_main(int argc, char **argv);
int	__wrap_main(int argc, char **argv);

int	__wrap_main(int argc, char **argv)
{
	char	**guarded;
	size_t	n;
	int		i;

	guarded = malloc(sizeof(char *) * ((size_t)argc + 1));
	if (guarded == NULL)
		return (125);
	i = 0;
	while (i < argc)
	{
		n = strlen(argv[i]) + 1;
		guarded[i] = malloc(n);
		if (guarded[i] == NULL)
			return (125);
		memcpy(guarded[i], argv[i], n);
		i++;
	}
	guarded[argc] = NULL;
	return (__real_main(argc, guarded));
}
