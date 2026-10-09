#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

void	*ft_print_memory(void *addr, unsigned int size);

/* Before each dump, the address this test passes, as a line of its own:
 * "@addr " and sixteen lowercase hex digits. tools/diff_output.sh --sanitize
 * reads it and takes it out of the output, and it checks every row of the dump
 * that follows against it -- the first row's address is this one, each next
 * row's sixteen more -- which is the one thing about that column a test that
 * only reads stdout could not know (finding 048).
 *
 * Every block it dumps is a local array of main, on the stack, which sits
 * near the top of the address space: an address cut to 32 bits is not the
 * real one there. (The ilp32 layer's -m32 build has 32-bit pointers, with
 * nothing to cut.)
 * conventions: above 4 GiB -- its blocks are main's local arrays, on the stack */
static void	publish(void *addr)
{
	char	line[32];
	int		n;

	n = snprintf(line, sizeof(line), "@addr %016llx\n",
			(unsigned long long)(uintptr_t)addr);
	write(1, line, n);
}

static void	dump(void *addr, unsigned int size)
{
	publish(addr);
	ft_print_memory(addr, size);
}

/* Whether the function returned the addr it was given: "It should return
 * addr." -- for the empty dump too (finding 050). */
static void	put_flag(void *ret, void *addr)
{
	if (ret == addr)
		write(1, "1\n", 2);
	else
		write(1, "0\n", 2);
}

int	main(void)
{
	char			str[] = "Bonjour les aminches\t\n\tc\a est fou\ttout\tce qu on peut faire avec\t\n\tprint_memory\n\n\n\tlol.lol. \0";
	char			full[] = "0123456789ABCDEF";
	char			part[] = "abc";
	unsigned char	np[5];
	void			*ret;

	publish(str);
	ret = ft_print_memory(str, sizeof(str) - 1);
	write(1, "ret==str:", 9);
	put_flag(ret, str);
	dump(full, 16);
	dump(part, 3);
	np[0] = 0;
	np[1] = 1;
	np[2] = 127;
	np[3] = 128;
	np[4] = 255;
	dump(np, 5);
	write(1, "SIZE0:[", 7);
	ret = ft_print_memory(full, 0);
	write(1, "] ret==addr:", 12);
	put_flag(ret, full);
	return (0);
}
