#include "ft_point.h"

/* The subject's main, as the subject prints it: the exercise is to write the
 * header this compiles against, and nothing here asks more of it than that. */
void	set_point(t_point *point)
{
	point->x = 42;
	point->y = 21;
}

int	main(void)
{
	t_point	point;

	set_point(&point);
	return (0);
}
