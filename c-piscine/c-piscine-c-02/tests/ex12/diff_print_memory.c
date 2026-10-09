/* Live-differential reader harness for ft_print_memory.
 * Line: <hexBlock>\t<size>\t<escapedRender>\t<returned addr>. The block, two
 * hex digits per byte, the size in decimal, then what ft_print_memory wrote
 * as ONE field -- each row's address as its offset from the block when it is
 * the row's real address, backslash doubled, newline as \n -- and 1 or 0 for
 * "returned the addr it was given".
 *
 * WHY THE OUTPUT IS CAPTURED. This function writes with write() straight to fd
 * 1, and the bytes it emits are most of the answer. fd 1 is therefore pointed
 * at a scratch FILE for the duration of the call and read back afterwards,
 * whole, into a buffer sized from what was written. It was a pipe read once
 * into 64 KiB: a block whose dump passed a pipe's buffer would have blocked
 * the write forever, a reader that had not started yet, and the hang been
 * blamed on the student -- the corpus only kept clear of it by keeping every
 * block under 70 bytes (tools/diffio.h, "SIZED FROM THE CASE").
 *
 * WHY THE ADDRESS IS REWRITTEN, AND ONLY WHEN IT IS RIGHT. The subject prints
 * the real address of each row, which no reference can predict and which
 * changes between runs. But this harness knows the address it passed, so it
 * checks each row's against it -- sixteen lowercase hex digits of block + row
 * -- and prints the row's offset in its place only when they match, which is
 * what the reference prints. A wrong address (narrowed to 32 bits, the
 * block's instead of the row's, uppercase) is kept as the function printed
 * it, and the record diverges (finding 048). The output layer checks the same
 * against the addresses its fixture publishes (diff_output.sh --sanitize).
 *
 * WHERE THE BLOCK LIVES: ABOVE 4 GiB, OR A NARROWED ADDRESS IS RIGHT. This
 * program is linked as a position-dependent executable, and its heap starts
 * just after the image, a few MiB into the address space: a block malloc
 * hands out there has an address that fits in 32 bits, so an address cut to
 * 32 bits loses only zeros and prints the row's real address. Every case of
 * the corpus passed with the address narrowed, while the comment above said
 * the record would diverge (the mutation run of 2026-10-03). So the block is
 * moved above 4 GiB before the call, by tools/diffio.h's dio_high, which
 * every reader harness checking a printed address uses: a block that still
 * sits below is a harness error, never a case that passes, and an ASan
 * build's block stays where its allocator put it, far above already, so its
 * redzones still catch a read past the end.
 *
 * THE RETURN. "It should return addr." (C 02 p.21), for every size, the empty
 * dump included (finding 050). */
#include "diffio.h"
#include <stdint.h>
#include <unistd.h>

void	*ft_print_memory(void *addr, unsigned int size);

/* Print one captured line with its address column replaced by `row` when it
 * is the row's real address, block + row, then the rest verbatim. A row is
 * "<16 hex>: <rest>"; anything shorter than that is passed through untouched
 * rather than mangled, so a malformed line from the deliverable still reaches
 * the report as what it was. libc's snprintf writes the address it must be,
 * sixteen zero-padded lowercase hex digits, into a buffer of exactly that
 * (dio_alloc: no array of fixed size here, tools/diffio.h); unsigned long long
 * because that is the type %016llx expects, and at least as wide as a
 * pointer. */
static void	put_row(const char *p, int len, const unsigned char *block,
		unsigned long long row)
{
	int		i;
	char	*want;

	if (len < 18 || p[16] != ':' || p[17] != ' ')
	{
		i = 0;
		while (i < len)
			putchar(p[i++]);
		return ;
	}
	want = (char *)dio_alloc(17, 1);
	snprintf(want, 17, "%016llx",
		(unsigned long long)((uintptr_t)block + row));
	if (memcmp(p, want, 16) == 0)
		printf("%016llx", row);
	else
		printf("%.16s", p);
	free(want);
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

static void	put_escaped(const char *buf, int len, const unsigned char *block)
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
			put_row(buf + start, i - start, block, row);
			printf("\\n");
			row += 16;
			start = i + 1;
		}
		i++;
	}
	if (start < len)
		put_row(buf + start, len - start, block, row);
}

/* Everything written to `fd` since it was emptied, in a heap buffer of
 * exactly that many bytes (and a NUL); *len is the count. */
static char	*slurp(int fd, long *len)
{
	char	*buf;
	long	got;
	ssize_t	r;

	*len = (long)lseek(fd, 0, SEEK_END);
	if (*len < 0 || lseek(fd, 0, SEEK_SET) != 0)
		dio_fail("cannot read back the captured output");
	buf = (char *)dio_alloc((size_t)*len + 1, 1);
	got = 0;
	while (got < *len)
	{
		r = read(fd, buf + got, (size_t)(*len - got));
		if (r <= 0)
			dio_fail("cannot read back the captured output");
		got += r;
	}
	return (buf);
}

int	main(void)
{
	char			*line;
	size_t			linecap;
	char			*f[3];
	unsigned char	*block;
	size_t			len;
	char			*cap;
	long			got;
	FILE			*out;
	int				saved;
	unsigned int	size;
	void			*ret;

	out = tmpfile();
	if (out == NULL)
		dio_fail("cannot create a scratch file to capture the output in");
	/* A line of any length (tools/diffio.h, dio_getline): the corpus holds
	 * blocks past 4 KiB, whose dump is far longer than a line buffer. */
	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		block = dio_high(dio_unhex(f[0], &len, 0), len + 1);
		size = (unsigned int)strtoul(f[1], NULL, 10);
		if (size > len)
			dio_fail("a case asks for more bytes than its block holds");
		fflush(stdout);
		if (ftruncate(fileno(out), 0) != 0 || lseek(fileno(out), 0, SEEK_SET) != 0)
			dio_fail("cannot empty the scratch file");
		saved = dup(1);
		dup2(fileno(out), 1);
		ret = ft_print_memory(block, size);
		fflush(stdout);
		dup2(saved, 1);
		close(saved);
		cap = slurp(fileno(out), &got);
		printf("%s\t%s\t", f[0], f[1]);
		put_escaped(cap, (int)got, block);
		printf("\t%d\n", ret == (void *)block);
		free(cap);
		dio_high_free(block);
	}
	fclose(out);
	free(line);
	return (0);
}
