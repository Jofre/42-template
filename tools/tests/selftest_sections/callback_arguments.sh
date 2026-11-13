# --------------------------------------------------------- callback arguments
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# What a fixture hands a callback, and what it checks the callback is handed.
#
# C 13 ex05's comparator answered on its two arguments' keys alone, and only
# whether that was 0 mattered: a search that handed cmpf a node instead of
# its item, or data_ref twice, read keys from whatever it got. The subject
# fixes no ORDER for cmpf's arguments (WP-46: either passes), but every
# reading hands it data_ref and a node's item. Built here over a toy that
# hands cmpf the node, the fixture's last row must count those calls. The toy
# is named apart and the fixture's call renamed to it (-D); the header is the
# structure the subject prints, nothing more: the fixture declares its call
# itself.
mkdir -p "$WORK/c13cb"
printf '%s\n' '#ifndef FT_BTREE_H' '# define FT_BTREE_H' \
	'typedef struct s_btree' '{' '	struct s_btree	*left;' '	struct s_btree	*right;' \
	'	void			*item;' '}	t_btree;' '#endif' > "$WORK/c13cb/ft_btree.h"
printf '%s\n' '#include "ft_btree.h"' \
	'void	*btree_search_item(t_btree *root, void *data_ref, int (*cmpf)(void *, void *))' '{' \
	'	if (root != (void *)0 && cmpf(root, data_ref) == 0)' '		return (root->item);' \
	'	return ((void *)0);' '}' > "$WORK/c13cb/toy_node.c"
toy_cc "$WORK/c13cb/fixture" -I "$WORK/c13cb" -Dbtree_search_item=toy_search \
	"$ROOT/c-piscine/c-piscine-c-13/tests/ex05/test_btree_search_item.c" \
	"$WORK/c13cb/toy_node.c"
want_out "C 13 ex05 fixture: it counts what cmpf is handed" \
	'calls handing it anything else: ' -- "$WORK/c13cb/fixture"
want_broken_none "...and a node handed for its item is counted" \
	'calls handing it anything else: 0' -- "$WORK/c13cb/fixture"

