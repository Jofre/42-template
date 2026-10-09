/* The names of the INVENTED t_toy (../toy.h): its tag. Read by the
 * exNN_layout_prototype twin of ex16 and of ex17, at strict, with
 * --layout-tag. */
#ifndef LAYOUT_TAG_TOY_H
# define LAYOUT_TAG_TOY_H

_Static_assert(__builtin_types_compatible_p(t_toy, struct s_toy),
	"toy.h: t_toy is not a typedef of struct s_toy, as the subject's is");

#endif
