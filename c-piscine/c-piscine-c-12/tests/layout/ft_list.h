/* The structure C 12 prints for ft_list.h (p.5: "For the following exercises,
 * you have to use the following structure"), checked against YOUR ft_list.h.
 *
 * The prototype layer force-includes your ft_list.h and then this file, while
 * compiling your exercise's file (tools/prototype_check.sh --layout). The
 * grader builds its own nodes on the subject's structure -- "From exercise 01
 * onward, we'll use our ft_create_elem" -- so a t_list whose fields differ in
 * type, size, order or number reads the grader's nodes wrong, however right
 * the function is. Each check below names the field it is about.
 *
 * What the subject prints and memory does not see -- the tag, struct s_list,
 * and next's type as a struct s_list * -- is checked apart, in
 * tag/ft_list.h, and only at strict.
 *
 * This is the subject's typedef, under a tag of its own so it cannot collide
 * with yours; nothing here is compiled into any program. */
#ifndef LAYOUT_C12_FT_LIST_H
# define LAYOUT_C12_FT_LIST_H

# include <stddef.h>

struct	s_list_as_the_subject_prints_it
{
	struct s_list_as_the_subject_prints_it	*next;
	void									*data;
};

_Static_assert(sizeof(((t_list *)0)->next)
	== sizeof(((struct s_list_as_the_subject_prints_it *)0)->next),
	"ft_list.h: next is not the size of a pointer, as the subject's is");
_Static_assert(__builtin_types_compatible_p(
		__typeof__(((t_list *)0)->data), void *),
	"ft_list.h: data is not a void *, as the subject's is");
_Static_assert(offsetof(t_list, next)
	== offsetof(struct s_list_as_the_subject_prints_it, next),
	"ft_list.h: next is not where the subject puts it (the first field)");
_Static_assert(offsetof(t_list, data)
	== offsetof(struct s_list_as_the_subject_prints_it, data),
	"ft_list.h: data is not where the subject puts it (after next)");
_Static_assert(sizeof(t_list)
	== sizeof(struct s_list_as_the_subject_prints_it),
	"ft_list.h: t_list is not the size of the subject's: a field more or less");

#endif
