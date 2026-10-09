/* The NAMES C 12 prints for ft_list.h's structure (p.5), checked against
 * YOUR ft_list.h: t_list is a typedef of struct s_list, and next points to a
 * struct s_list.
 *
 * Apart from ../ft_list.h on purpose. A header that lays the fields out as
 * the subject does, under another tag, reads the grader's own nodes right:
 * memory does not see a tag. Only code written against the subject's header
 * by name -- the grader's own tests may be -- tells the two apart, so a
 * difference here is real but not certain, and this file is read by
 * exNN_layout_prototype, at strict (tools/prototype_check.sh --layout-tag).
 * Nothing here is compiled into any program. */
#ifndef LAYOUT_TAG_C12_FT_LIST_H
# define LAYOUT_TAG_C12_FT_LIST_H

_Static_assert(__builtin_types_compatible_p(t_list, struct s_list),
	"ft_list.h: t_list is not a typedef of struct s_list, as the subject's is");
_Static_assert(__builtin_types_compatible_p(
		__typeof__(((t_list *)0)->next), struct s_list *),
	"ft_list.h: next is not a struct s_list *, as the subject's is");

#endif
