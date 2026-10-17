/* The structure Libft prints for libft.h (p.14: "add the following structure
 * declaration to your libft.h file"), checked against YOUR libft.h: content
 * first, a void *, then next -- the reverse of the C Piscine's C 12 t_list,
 * whose next comes first.
 *
 * The prototype layer force-includes your libft.h and then this file, while
 * compiling your files (tools/prototype_check.sh --layout). Libft has no
 * grader's function that builds nodes for yours, and a test compiled against
 * your own libft.h builds them on your layout. But code compiled against the
 * structure the subject prints -- a test written from the subject, or a later
 * project's -- reads a t_list whose fields differ in type, size, order or
 * number wrong, however right your functions are. That is why this check
 * runs at strict, not basic. Each check below names the field it is about.
 *
 * What the subject prints and memory does not see -- the tag, struct s_list,
 * and next's type as a struct s_list * -- is checked apart, in
 * tag/libft.h, and only at strict.
 *
 * This is the subject's typedef, under a tag of its own so it cannot collide
 * with yours; nothing here is compiled into any program. */
#ifndef LAYOUT_LIBFT_LIBFT_H
# define LAYOUT_LIBFT_LIBFT_H

# include <stddef.h>

struct	s_list_as_libft_prints_it
{
	void								*content;
	struct s_list_as_libft_prints_it	*next;
};

_Static_assert(__builtin_types_compatible_p(
		__typeof__(((t_list *)0)->content), void *),
	"libft.h: content is not a void *, as the subject's is");
_Static_assert(sizeof(((t_list *)0)->next)
	== sizeof(((struct s_list_as_libft_prints_it *)0)->next),
	"libft.h: next is not the size of a pointer, as the subject's is");
_Static_assert(offsetof(t_list, content)
	== offsetof(struct s_list_as_libft_prints_it, content),
	"libft.h: content is not where the subject puts it (the first field)");
_Static_assert(offsetof(t_list, next)
	== offsetof(struct s_list_as_libft_prints_it, next),
	"libft.h: next is not where the subject puts it (after content)");
_Static_assert(sizeof(t_list)
	== sizeof(struct s_list_as_libft_prints_it),
	"libft.h: t_list is not the size of the subject's: a field more or less");

#endif
