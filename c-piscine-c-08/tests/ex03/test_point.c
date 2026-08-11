#include "ft_point.h"

void	set_point(t_point *point)
{
	point->x = 42;
	point->y = 21;
}

int	main(void)
{
	t_point	point;
	int		*px;
	int		*py;

	set_point(&point);
	/* The subject requires int fields x and y. Binding their addresses to int*
	   fails under -Werror if a header declares them with any other type. */
	px = &point.x;
	py = &point.y;
	(void)px;
	(void)py;
	return (0);
}
