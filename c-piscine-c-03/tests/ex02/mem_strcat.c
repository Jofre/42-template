/* Memory-safety probe for ft_strcat — run under AddressSanitizer.
 * strcat appends src onto the end of dest, overwriting dest's terminator and
 * re-terminating: a correct impl writes exactly strlen(dest)+strlen(src)+1
 * bytes into dest. Each dest below is a HEAP buffer sized to that EXACT final
 * length (prefilled content plus its terminator, no interior NUL), so any
 * off-by-one in the copy or in the final '\0' write lands one byte past the
 * buffer — an ASan heap-buffer-overflow. src is an exact-size, terminated heap
 * buffer so an over-read of src is caught too. The empty case (dest "" + src
 * "") and the length-1 case are covered. This is a test input, not a solution. */
#include <stdlib.h>

char	*ft_strcat(char *dest, char *src);

int	main(void)
{
	char	*d1;
	char	*s1;
	char	*d2;
	char	*s2;
	char	*d3;
	char	*s3;

	d1 = malloc(5);
	s1 = malloc(3);
	d1[0] = 'a';
	d1[1] = 'b';
	d1[2] = '\0';
	s1[0] = 'c';
	s1[1] = 'd';
	s1[2] = '\0';
	ft_strcat(d1, s1);
	d2 = malloc(1);
	s2 = malloc(1);
	d2[0] = '\0';
	s2[0] = '\0';
	ft_strcat(d2, s2);
	d3 = malloc(2);
	s3 = malloc(2);
	d3[0] = '\0';
	s3[0] = 'x';
	s3[1] = '\0';
	ft_strcat(d3, s3);
	free(d1);
	free(s1);
	free(d2);
	free(s2);
	free(d3);
	free(s3);
	return (0);
}
