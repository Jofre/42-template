/* An INVENTED structure, t_toy, as a subject would print it for toy.h: the
 * layout half of what c_function reads from tests/layout/ (tools/defs.bzl,
 * _layouts). ex16's grader links a function of its own (`linked`), so this is
 * read by ex16_prototype at basic; ex17's does not, so by ex17's
 * exNN_layout_prototype twin at strict. The toys' toy.h is a stub, so both
 * are red by design: what is proven is the wiring (layers.expected). */
#ifndef LAYOUT_TOY_H
# define LAYOUT_TOY_H

# include <stddef.h>

struct	s_toy_as_the_subject_prints_it
{
	struct s_toy_as_the_subject_prints_it	*next;
	int										n;
};

_Static_assert(offsetof(t_toy, n)
	== offsetof(struct s_toy_as_the_subject_prints_it, n),
	"toy.h: n is not where the subject puts it (after next)");
_Static_assert(sizeof(t_toy) == sizeof(struct s_toy_as_the_subject_prints_it),
	"toy.h: t_toy is not the size of the subject's");

#endif
