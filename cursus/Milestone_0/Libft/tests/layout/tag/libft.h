/* The NAMES Libft prints for libft.h's structure (p.14), checked against
 * YOUR libft.h: t_list is a typedef of struct s_list, and next points to a
 * struct s_list.
 *
 * Apart from ../libft.h on purpose. A header that lays the fields out as the
 * subject does, under another tag, reads nodes built on the subject's
 * structure right: memory does not see a tag. Only code written against the
 * subject's header by name tells the two apart, so a difference here is real
 * but not certain, and this file is read by ex00_layout_prototype, at strict
 * (tools/prototype_check.sh --layout-tag). Nothing here is compiled into any
 * program. */
#ifndef LAYOUT_TAG_LIBFT_LIBFT_H
# define LAYOUT_TAG_LIBFT_LIBFT_H

_Static_assert(__builtin_types_compatible_p(t_list, struct s_list),
	"libft.h: t_list is not a typedef of struct s_list, as the subject's is");
_Static_assert(__builtin_types_compatible_p(
		__typeof__(((t_list *)0)->next), struct s_list *),
	"libft.h: next is not a struct s_list *, as the subject's is");

#endif
