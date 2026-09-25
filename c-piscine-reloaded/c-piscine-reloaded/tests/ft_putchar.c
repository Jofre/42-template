/*
 * The GRADER's ft_putchar. Piscine Reloaded's subject: "If ft_putchar() is an
 * authorized function, we will compile your code with our ft_putchar.c".
 * So an exercise that may call ft_putchar declares it in its own .c file --
 *
 *     void	ft_putchar(char c);
 *
 * -- and never defines it: this file is compiled in by the harness, as the
 * Moulinette compiles in its own. A definition of your own is a second one,
 * which does not link at the Moulinette; turned in as its own ft_putchar.c it
 * is also an extra file, which the subject fails ("You cannot leave any
 * additional file").
 *
 * It is written with stdio, which no Piscine exercise authorises, ON PURPOSE:
 * this file ships in the public template, and the obvious one-line version is
 * the answer to the Piscine's very first exercise (AGENTS.md §0: answers are
 * never written anywhere). fflush after every character keeps it in step with
 * anything else writing to fd 1, exactly as an unbuffered write() would.
 *
 * WEAK, unlike the Moulinette's, and that is the one place this file departs
 * from it on purpose. With a strong symbol, a student's second definition
 * would be a link error -- in Bazel a BUILD error, which stops every other
 * test in the run, the thing this repo never lets a student's code do. Weak,
 * theirs silently wins the link, the build completes, and the exercise's
 * forbidden layer names the mistake: "your code DEFINES a function the grader
 * supplies".
 *
 * To compile an exercise by hand, keep your test main OUT of deliverable/ --
 * anything in there is part of what you turn in -- and name this file on the
 * command line. From a scratch directory, with REPO the path to this repo:
 *     cc -Wall -Wextra -Werror main.c \
 *         REPO/c-piscine-reloaded/c-piscine-reloaded/deliverable/ex06/ft_print_alphabet.c \
 *         REPO/c-piscine-reloaded/c-piscine-reloaded/tests/ft_putchar.c
 */
#include <stdio.h>

__attribute__((weak)) void	ft_putchar(char c)
{
	fputc(c, stdout);
	fflush(stdout);
}
