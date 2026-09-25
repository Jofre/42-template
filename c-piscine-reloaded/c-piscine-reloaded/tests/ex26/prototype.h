/* Contract header -- the signature the subject specifies for this exercise.
 *
 * Piscine Reloaded's ft_count_if is NOT the Piscine's: there is no length, and
 * the array ends at its first NULL ("The array will be delimited by 0"). The
 * prototype layer compiles your deliverable with this force-included, so a
 * leftover third parameter is a conflicting-types error rather than a program
 * that links and reads garbage. */
#ifndef PROTOTYPE_C_PISCINE_RELOADED_EX26_H
# define PROTOTYPE_C_PISCINE_RELOADED_EX26_H

int		ft_count_if(char **tab, int (*f)(char *));

#endif
