/* Live-differential reader harness for ft_print_memory.
 * Line: <hexBlock>\t<size>\t<escapedRender>. Rebuilds the block from hex, calls
 * ft_print_memory on it, and reprints what it wrote as ONE field: the address
 * column replaced by the row's offset, backslash doubled, newline as \n.
 *
 * WHY THE OUTPUT IS CAPTURED. This function writes with write() straight to fd
 * 1 and returns nothing, so there is no value to compare -- the bytes it emits
 * ARE the answer. fd 1 is therefore pointed at a pipe for the duration of the
 * call and read back afterwards. The corpus keeps blocks small (under 70
 * bytes), which is far inside a pipe's buffer, so the write cannot block
 * waiting for a reader that has not started yet.
 *
 * WHY THE ADDRESS IS REWRITTEN. The subject prints the real address of the
 * area, which no reference can predict and which changes between runs. Both
 * sides normalise it the same way -- row 0 is 0, row 1 is 0x10 -- which is the
 * same thing the output layer's `sanitize` does to this exercise's fixture. */
#include "diffio.h"
#include <unistd.h>

void	ft_print_memory(void *addr, unsigned int size);

static int	unhex_digit(char c)
{
	if (c >= '0' && c <= '9')
		return (c - '0');
	if (c >= 'a' && c <= 'f')
		return (c - 'a' + 10);
	if (c >= 'A' && c <= 'F')
		return (c - 'A' + 10);
	return (-1);
}

static int	unhex(const char *s, unsigned char *out)
{
	int	n;
	int	hi;
	int	lo;

	n = 0;
	while (s[0] && s[1])
	{
		hi = unhex_digit(s[0]);
		lo = unhex_digit(s[1]);
		if (hi < 0 || lo < 0)
			break ;
		out[n++] = (unsigned char)((hi << 4) | lo);
		s += 2;
	}
	return (n);
}

/* Print one captured line with its address column replaced by `row`, then the
 * rest verbatim. A row is "<16 hex>: <rest>"; anything shorter than that is
 * passed through untouched rather than mangled, so a malformed line from the
 * deliverable still reaches the report as what it was. */
/* `row` is 64-bit, and that is not cosmetic: an address column is sixteen hex
 * digits, so rendering it means shifting right by up to 60. Shifting a 32-bit
 * value that far is undefined, and on x86 the count wraps modulo 32 -- which
 * printed a stray digit halfway along every second row and would have shown up
 * as the student diverging on an address they had written correctly. */
static void	put_row(const char *p, int len, unsigned long long row)
{
	int		i;
	char	digits[] = "0123456789abcdef";

	if (len < 18 || p[16] != ':' || p[17] != ' ')
	{
		i = 0;
		while (i < len)
			putchar(p[i++]);
		return ;
	}
	i = 16;
	while (i-- > 0)
		putchar(digits[(row >> (i * 4)) & 0xf]);
	i = 16;
	while (i < len)
	{
		if (p[i] == '\\')
			printf("\\\\");
		else
			putchar(p[i]);
		i++;
	}
}

static void	put_escaped(const char *buf, int len)
{
	int					start;
	int					i;
	unsigned long long	row;

	start = 0;
	i = 0;
	row = 0;
	while (i < len)
	{
		if (buf[i] == '\n')
		{
			put_row(buf + start, i - start, row);
			printf("\\n");
			row += 16;
			start = i + 1;
		}
		i++;
	}
	if (start < len)
		put_row(buf + start, len - start, row);
}

int	main(void)
{
	char			line[8192];
	char			*f[3];
	unsigned char	block[4096];
	char			cap[65536];
	int				n;
	int				got;
	int				fds[2];
	int				saved;
	unsigned int	size;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		n = unhex(f[0], block);
		(void)n;
		size = (unsigned int)strtoul(f[1], NULL, 10);
		fflush(stdout);
		if (pipe(fds) != 0)
			return (1);
		saved = dup(1);
		dup2(fds[1], 1);
		close(fds[1]);
		ft_print_memory(block, size);
		fflush(stdout);
		dup2(saved, 1);
		close(saved);
		got = (int)read(fds[0], cap, sizeof(cap));
		close(fds[0]);
		if (got < 0)
			got = 0;
		printf("%s\t%s\t", f[0], f[1]);
		put_escaped(cap, got);
		printf("\n");
	}
	return (0);
}
