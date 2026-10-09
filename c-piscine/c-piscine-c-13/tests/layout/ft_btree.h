/* The structure C 13 prints for ft_btree.h (p.3: "For the following
 * exercises, we'll use the following structure"), checked against YOUR
 * ft_btree.h.
 *
 * The prototype layer force-includes your ft_btree.h and then this file,
 * while compiling your exercise's file (tools/prototype_check.sh --layout).
 * The grader builds its own nodes on the subject's structure -- "From
 * exercise 01 onward, we'll use our btree_create_node" -- so a t_btree whose
 * fields differ in type, size, order or number reads the grader's nodes
 * wrong, however right the function is. Each check below names the field it
 * is about.
 *
 * What the subject prints and memory does not see -- the tag, struct
 * s_btree, and left's and right's type as a struct s_btree * -- is checked
 * apart, in tag/ft_btree.h, and only at strict.
 *
 * This is the subject's typedef, under a tag of its own so it cannot collide
 * with yours; nothing here is compiled into any program. */
#ifndef LAYOUT_C13_FT_BTREE_H
# define LAYOUT_C13_FT_BTREE_H

# include <stddef.h>

struct	s_btree_as_the_subject_prints_it
{
	struct s_btree_as_the_subject_prints_it	*left;
	struct s_btree_as_the_subject_prints_it	*right;
	void									*item;
};

_Static_assert(sizeof(((t_btree *)0)->left)
	== sizeof(((struct s_btree_as_the_subject_prints_it *)0)->left),
	"ft_btree.h: left is not the size of a pointer, as the subject's is");
_Static_assert(sizeof(((t_btree *)0)->right)
	== sizeof(((struct s_btree_as_the_subject_prints_it *)0)->right),
	"ft_btree.h: right is not the size of a pointer, as the subject's is");
_Static_assert(__builtin_types_compatible_p(
		__typeof__(((t_btree *)0)->item), void *),
	"ft_btree.h: item is not a void *, as the subject's is");
_Static_assert(offsetof(t_btree, left)
	== offsetof(struct s_btree_as_the_subject_prints_it, left),
	"ft_btree.h: left is not where the subject puts it (the first field)");
_Static_assert(offsetof(t_btree, right)
	== offsetof(struct s_btree_as_the_subject_prints_it, right),
	"ft_btree.h: right is not where the subject puts it (after left)");
_Static_assert(offsetof(t_btree, item)
	== offsetof(struct s_btree_as_the_subject_prints_it, item),
	"ft_btree.h: item is not where the subject puts it (after right)");
_Static_assert(sizeof(t_btree)
	== sizeof(struct s_btree_as_the_subject_prints_it),
	"ft_btree.h: t_btree is not the size of the subject's: a field more or less");

#endif
