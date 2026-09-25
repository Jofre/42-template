/* Contract header -- the signature the subject specifies for this
 * exercise, lifted from the harness that every other layer already relies on.
 *
 * The prototype layer compiles your deliverable with this force-included, so
 * the compiler sees the subject's declaration and your definition in the SAME
 * translation unit. A mismatched return type or parameter list is then a
 * conflicting-types error instead of silently linking (C has no name mangling,
 * so a wrong signature links fine and simply misbehaves).
 *
 * Hand-written from the subject's contract; the harness in this exercise's
 * tests/ directory is the cross-check that it is right. */
#ifndef PROTOTYPE_C_PISCINE_C_12_EX16_H
# define PROTOTYPE_C_PISCINE_C_12_EX16_H

# include "ft_list.h"
void	ft_sorted_list_insert(t_list **begin_list, void *data, int (*cmp)());

#endif
