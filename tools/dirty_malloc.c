/* dirty_malloc.c — in the programs the differential layers run, every block
 * malloc() hands out starts holding 0xa5, never a zero (HOW MUCH, below). Linked
 * by //tools:diffio, the reader harnesses' library, with -Wl,--wrap=malloc.
 * Grader-side test infrastructure, never compiled into a deliverable (same
 * standing as tools/allocfail_shim.c).
 *
 * WHY. A block malloc returns holds whatever was there, and a reader harness
 * that runs 400000 cases in one process gets one of two things: fresh heap,
 * which the kernel zeroed, or a block freed a case earlier, which glibc hands
 * back with ITS bookkeeping zeroed -- the free-list key it keeps in the second
 * word is cleared on the way out. Either way the bytes a function forgot to
 * write read as zeros: a node whose `right` was never set read NULL, as the
 * reference's does, and C 13 ex00's diff passed 400000 cases over a
 * btree_create_node that never wrote it (the mutation run of 2026-10-03, c13a
 * M3). The same holds for any field, count or terminator a function leaves
 * unwritten in memory it allocated: a zero is the value most of them should
 * hold. Filled with 0xa5, an unwritten pointer is not NULL, an unwritten
 * count is not 0, and a string with no terminator runs on.
 *
 * WHY --wrap AND NOT A DEFINITION OF malloc. `ld --wrap=malloc` rewrites the
 * references to malloc in the objects on this link line -- the student's code
 * and the harness's -- and nothing inside the C library (tools/allocfail_shim.c
 * says why that scoping matters). The block still comes from the real
 * allocator, so an ASan build keeps its redzones (its allocator fills a block
 * with a byte of its own anyway), and calloc, which dio_unhex and dio_alloc
 * use, still returns zeros, as a harness that asked for them expects. A
 * harness that takes a block from malloc writes every byte it reads, as it
 * must already: dio_garbage fills its own.
 *
 * HOW MUCH. The first 4 KiB of a block and its last 64 bytes, and all of a
 * block no bigger than that. A fill of the whole block made the layers pay for
 * every byte a program allocates rather than every byte it uses: a correct
 * answer that asks malloc for a megabyte a call, over 400000 cases, would have
 * spent its time in memset and been reported as a timeout (the wave 6
 * review). ASan caps its own fill at 4096 bytes (max_malloc_fill_size) for
 * the same reason. What is left unfilled is the middle of a big block; a
 * record's fields sit in its first 4 KiB, and a string's terminator, or the
 * last field of a block sized to a count, in its last bytes.
 *
 * NEVER UNDER MEMCHECK. memcheck tracks which bytes were written, and the fill
 * writes them: a byte the student's code never set reads as defined there, and
 * an uninitialised read goes unseen. So no valgrind layer runs a program
 * linking //tools:diffio -- they run the exercise's own _bin, or a _vgbin --
 * and c_levels()' audit refuses one that does (tools/defs.bzl,
 * _diffio_memcheck_problems).
 *
 * WHERE. Every program linking //tools:diffio: the c_diff and c_perf readers
 * (plain and ASan) and Rush 00's judging harnesses. It changes no value a
 * correct program computes; it changes what an unwritten byte reads as. */
#include <stddef.h>
#include <string.h>

#define DIRTY_HEAD 4096
#define DIRTY_TAIL 64

void	*__real_malloc(size_t size);
void	*__wrap_malloc(size_t size);

void	*__wrap_malloc(size_t size)
{
	unsigned char	*p;

	p = __real_malloc(size);
	if (p == NULL)
		return (NULL);
	if (size <= DIRTY_HEAD + DIRTY_TAIL)
		memset(p, 0xa5, size);
	else
	{
		memset(p, 0xa5, DIRTY_HEAD);
		memset(p + size - DIRTY_TAIL, 0xa5, DIRTY_TAIL);
	}
	return (p);
}
