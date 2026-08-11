/* Memory-safety probe for ft_count_if — run under AddressSanitizer.
 * ft_count_if reads tab[0..length-1] (each a char *), applies the predicate f
 * and must never read tab[length]. tab below is a heap block of EXACTLY length
 * char * slots, so a correct scan touches only 0..length-1 while a read at index
 * length is out of bounds and ASan aborts. length 0 must not dereference tab.
 * This is a test input, not an implementation. */
#include <stdlib.h>

int	ft_count_if(char **tab, int length, int (*f)(char *));

/* Predicate: truthy when the string starts with an uppercase letter. */
static int	first_is_upper(char *s)
{
	if (s[0] >= 'A' && s[0] <= 'Z')
		return (1);
	return (0);
}

/* Builds an exact-sized heap array of string pointers and scans it. */
static void	run(int length)
{
	char		**tab;
	int			i;
	static char	*words[] = {"Apple", "berry", "Cherry", "date"};

	tab = malloc(sizeof(char *) * length);
	i = 0;
	while (i < length)
	{
		tab[i] = words[i];
		i++;
	}
	ft_count_if(tab, length, &first_is_upper);
	free(tab);
}

int	main(void)
{
	run(0);
	run(1);
	run(4);
	return (0);
}
