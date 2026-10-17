#include <stdio.h>

int	toy_twice(int n);

/* ex15's second reading: a labeled row whose value holds bytes that cannot
 * travel raw (a NUL, a byte above 0x7f), written in the notation the table
 * renders bytes in, as its case says ("escaped_values"). The stub's 0 is the
 * first byte. */
int	main(void)
{
	unsigned char	buf[3];
	int				i;

	buf[0] = (unsigned char)toy_twice(1);
	buf[1] = 0xff;
	buf[2] = 'X';
	printf("bytes\t");
	i = 0;
	while (i < 3)
	{
		if (buf[i] >= 32 && buf[i] < 127 && buf[i] != '\\')
			printf("%c", buf[i]);
		else
			printf("\\x%02x", buf[i]);
		i++;
	}
	printf("\n");
	return (0);
}
