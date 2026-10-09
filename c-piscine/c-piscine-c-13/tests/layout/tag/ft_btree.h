/* The NAMES C 13 prints for ft_btree.h's structure (p.3), checked against
 * YOUR ft_btree.h: t_btree is a typedef of struct s_btree, and left and right
 * point to a struct s_btree.
 *
 * Apart from ../ft_btree.h on purpose. A header that lays the fields out as
 * the subject does, under another tag, reads the grader's own nodes right:
 * memory does not see a tag. Only code written against the subject's header
 * by name -- the grader's own tests may be -- tells the two apart, so a
 * difference here is real but not certain, and this file is read by
 * exNN_layout_prototype, at strict (tools/prototype_check.sh --layout-tag).
 * Nothing here is compiled into any program. */
#ifndef LAYOUT_TAG_C13_FT_BTREE_H
# define LAYOUT_TAG_C13_FT_BTREE_H

_Static_assert(__builtin_types_compatible_p(t_btree, struct s_btree),
	"ft_btree.h: t_btree is not a typedef of struct s_btree, as the subject's is");
_Static_assert(__builtin_types_compatible_p(
		__typeof__(((t_btree *)0)->left), struct s_btree *),
	"ft_btree.h: left is not a struct s_btree *, as the subject's is");
_Static_assert(__builtin_types_compatible_p(
		__typeof__(((t_btree *)0)->right), struct s_btree *),
	"ft_btree.h: right is not a struct s_btree *, as the subject's is");

#endif
