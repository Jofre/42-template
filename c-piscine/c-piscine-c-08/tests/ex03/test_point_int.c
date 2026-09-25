#include <stdio.h>
#include "ft_point.h"

/* STRICTER THAN THE SUBJECT, which is why this case sits at level 3: the
 * subject's main only needs fields that can hold 42 and 21, and a header with
 * any such type passes the Moulinette's compile. This case asks WHICH type
 * they are. _Generic names a type at compile time without failing on the
 * others, so a header with other field types still compiles here, and only
 * this case's output says so. */
int	main(void)
{
	t_point	point;

	point.x = 42;
	point.y = 21;
	printf("x\t%s\n", _Generic(point.x, int: "int", default: "not int"));
	printf("y\t%s\n", _Generic(point.y, int: "int", default: "not int"));
	return (0);
}
