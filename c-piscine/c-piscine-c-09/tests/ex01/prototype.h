/* Contract header -- the signature the subject specifies for this
 * exercise, lifted from the harness that every other layer already relies on.
 *
 * The prototype layer compiles your deliverable with this force-included, so
 * the compiler sees the subject's declaration and your definition in the SAME
 * translation unit. A mismatched return type or parameter list is then a
 * conflicting-types error instead of silently linking (C has no name mangling,
 * so a wrong signature links fine and simply misbehaves).
 *
 * ex01 turns in the same five functions as ex00 under a different build system,
 * so the contract is identical; only the layout of the sources changes.
 *
 * Hand-written from the subject's contract; the harness in this exercise's
 * tests/ directory is the cross-check that it is right. */
#ifndef PROTOTYPE_C_PISCINE_C_09_EX01_H
# define PROTOTYPE_C_PISCINE_C_09_EX01_H

int		ft_strcmp(char *s1, char *s2);
int		ft_strlen(char *str);
void	ft_putchar(char c);
void	ft_putstr(char *str);
void	ft_swap(int *a, int *b);

#endif
