/* Live-differential reader harness for ft_putstr_non_printable.
 * Line: <hexStr>\t<escaped-output>. The function writes to fd 1 directly; we
 * flush the leading "<hexStr>\t" first so its bytes precede the function's, then
 * emit the trailing newline. The escaped output is all-printable (0x20..=0x7e),
 * so it carries no TAB/NL and rides raw as the final field. */
#include "diffio.h"

void	ft_putstr_non_printable(char *str);

int	main(void)
{
	char			line[8192];
	char			*f[2];
	unsigned char	*s;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		s = dio_unhex(f[0], NULL, 0);
		printf("%s\t", f[0]);
		fflush(stdout);
		ft_putstr_non_printable((char *)s);
		fflush(stdout);
		printf("\n");
		fflush(stdout);
		free(s);
	}
	return (0);
}
