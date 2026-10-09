/* allocfail_counter.h — the allocation counter both allocation-failure shims
 * link: tools/allocfail_shim.c (a function, called once by its own main) and
 * tools/allocfail_program.c (a program, which owns main). Grader-side test
 * infrastructure, never compiled into a deliverable; included by exactly ONE
 * file of each binary, so its definitions are not static.
 *
 * Written once because the two shims must refuse and count the same way: a
 * second copy is how the function layer and the program layer would come to
 * disagree about what "allocation #3" means. tools/allocfail_shim.c explains
 * the mechanism (why -Wl,--wrap=malloc, why only the deliverable's own calls
 * are seen) and the protocol; this file is only the counter.
 */
#ifndef ALLOCFAIL_COUNTER_H
# define ALLOCFAIL_COUNTER_H

# include <stdio.h>
# include <stdlib.h>

extern void	*__real_malloc(size_t size);
void		*__wrap_malloc(size_t size);

/* Which allocation to fail (1-based; 0 = none), and how many have been asked
 * for so far. Single-threaded by construction — the deliverables are — so
 * plain globals are enough and an atomic would only obscure the mechanism. */
static unsigned long	g_arm;
static unsigned long	g_seen;

/* The blocks the deliverable holds: every pointer __wrap_malloc handed out,
 * and its size, until free() crosses it off -- an open-addressing table keyed
 * by the pointer, which doubles when it is half full, so a count is exact
 * however many blocks a program keeps (a Common Core program keeps thousands).
 * It used to be a fixed 4096 slots, past which the count was marked untracked
 * for good: a program that once held 4097 blocks and freed every one was
 * reported as holding an unknown number. Untracked now means one thing only:
 * the table could not grow, because the shim's OWN memory ran out.
 *
 * The table's memory comes from calloc() and goes back through the real
 * free(): neither is wrapped, so the table is never counted as the
 * deliverable's, and it never asks the counter for room while counting.
 * Without --wrap=free nothing is ever crossed off, and the script does not
 * read the count. */
#ifdef AF_WRAP_FREE

extern void	__real_free(void *ptr);
void		__wrap_free(void *ptr);
# define AF_RELEASE __real_free
#else
# define AF_RELEASE free
#endif

static void				**g_ptr;
static size_t			*g_size;
static unsigned long	g_cap;
static unsigned long	g_live;
static unsigned long	g_bytes;
static int				g_untracked;

/* The slot a pointer starts its search at. Blocks are 16-byte aligned, so the
 * low bits say nothing; a multiplicative hash spreads the rest. */
static unsigned long	af_slot(const void *p)
{
	unsigned long long	h;

	h = (unsigned long long)(size_t)p >> 4;
	h *= 0x9E3779B97F4A7C15ULL;
	return ((unsigned long)(h >> 24) & (g_cap - 1));
}

static void	af_put(void *p, size_t size)
{
	unsigned long	i;

	i = af_slot(p);
	while (g_ptr[i] != NULL)
		i = (i + 1) & (g_cap - 1);
	g_ptr[i] = p;
	g_size[i] = size;
}

/* Doubles the table (or starts it). 0 when the shim's own memory ran out,
 * with the old table left as it was. */
static int	af_grow(void)
{
	void			**old_ptr;
	size_t			*old_size;
	unsigned long	old_cap;
	unsigned long	i;

	old_ptr = g_ptr;
	old_size = g_size;
	old_cap = g_cap;
	g_cap = old_cap != 0 ? old_cap * 2 : 1024;
	g_ptr = calloc(g_cap, sizeof(*g_ptr));
	g_size = calloc(g_cap, sizeof(*g_size));
	if (g_ptr == NULL || g_size == NULL)
	{
		AF_RELEASE(g_ptr);
		AF_RELEASE(g_size);
		g_ptr = old_ptr;
		g_size = old_size;
		g_cap = old_cap;
		return (0);
	}
	i = 0;
	while (i < old_cap)
	{
		if (old_ptr[i] != NULL)
			af_put(old_ptr[i], old_size[i]);
		i++;
	}
	AF_RELEASE(old_ptr);
	AF_RELEASE(old_size);
	return (1);
}

static void	af_track(void *p, size_t size)
{
	if (g_untracked)
		return ;
	if ((g_live + 1) * 2 > g_cap && !af_grow())
	{
		g_untracked = 1;
		return ;
	}
	af_put(p, size);
	g_live++;
	g_bytes += size;
}

/* Forgets every block: the count starts again from here. */
static void	af_reset(void)
{
	unsigned long	i;

	i = 0;
	while (i < g_cap)
		g_ptr[i++] = NULL;
	g_live = 0;
	g_bytes = 0;
	g_untracked = 0;
}

/* The refusal itself. Note what is NOT here: no size threshold, no random
 * failure, no "fail every Nth", and no stickiness — the refusal does not stay
 * on once it has fired. Exactly one allocation fails per run, chosen by the
 * caller, so when something goes wrong the run that produced it names the
 * single decision point responsible. A shim that failed allocations randomly
 * would find the same bugs and be unable to say where.
 *
 * One consequence worth knowing, because it changes how a finding reads: an
 * implementation that RETRIES a refused allocation gets a real block on its
 * second attempt and finishes normally, so it never shows up as a hang. It
 * shows up as "was refused, asked again, returned a pointer" — which is the
 * honest description of what the code did, and a more useful one than a
 * timeout, since a timeout says only that something never came back. The
 * script compares `seen` against the armed index to tell the two apart. */
void	*__wrap_malloc(size_t size)
{
	void	*p;

	g_seen++;
	if (g_arm != 0 && g_seen == g_arm)
		return (NULL);
	p = __real_malloc(size);
	if (p != NULL)
		af_track(p, size);
	return (p);
}

/* A free() of a block the table holds crosses it off. Any other pointer --
 * one the harness allocated, NULL, or one this file never saw -- goes to the
 * real free() untouched, so wrapping free changes what is COUNTED and nothing
 * the program does. Compiled only with AF_WRAP_FREE, because __real_free
 * exists only when the link has -Wl,--wrap=free: allocfail_check.sh sets both
 * for a function's --leaks sweep, so its basic sweep links exactly as it
 * always has, and allocfail_program.c defines it for every program (c_program
 * links that binary with both wraps). */
#ifdef AF_WRAP_FREE

/* Crosses P off when the table holds it; any other pointer is left alone.
 * The slots after it that hashed at or before its slot move back into the
 * gap, so a search never stops early at a hole (no tombstones). */
static void	af_untrack(void *p)
{
	unsigned long	i;
	unsigned long	j;
	unsigned long	k;

	if (p == NULL || g_cap == 0)
		return ;
	i = af_slot(p);
	while (g_ptr[i] != NULL && g_ptr[i] != p)
		i = (i + 1) & (g_cap - 1);
	if (g_ptr[i] == NULL)
		return ;
	g_live--;
	g_bytes -= g_size[i];
	g_ptr[i] = NULL;
	j = i;
	while (1)
	{
		j = (j + 1) & (g_cap - 1);
		if (g_ptr[j] == NULL)
			break ;
		k = af_slot(g_ptr[j]);
		if (i <= j ? (i < k && k <= j) : (i < k || k <= j))
			continue ;
		g_ptr[i] = g_ptr[j];
		g_size[i] = g_size[j];
		g_ptr[j] = NULL;
		i = j;
	}
}

void	__wrap_free(void *ptr)
{
	af_untrack(ptr);
	__real_free(ptr);
}
#endif

/* af_line -- the report line, into LINE (CAP bytes): AF_RESULT arm=<n>
 * seen=<count> result=<RESULT> live=<n> bytes=<b><EXTRA>, with a leading
 * newline (see allocfail_shim.c's main for why). Returns how many bytes to
 * write, never more than the buffer holds. */
static int	af_line(char *line, size_t cap, const char *result, const char *extra)
{
	char			live[48];
	int				n;

	if (g_untracked)
		snprintf(live, sizeof(live), "untracked bytes=0");
	else
		snprintf(live, sizeof(live), "%lu bytes=%lu", g_live, g_bytes);
	n = snprintf(line, cap,
			"\nAF_RESULT arm=%lu seen=%lu result=%s live=%s%s\n",
			g_arm, g_seen, result, live, extra);
	/* snprintf returns the length it WOULD have written, which is not the
	 * same as the length it did. The fixed text plus four 20-digit counters
	 * cannot reach 200, and allocfail_shim.c's EXTRA (a harness's note, cut
	 * to 207 bytes) cannot take its 400 past it, so this cannot trigger
	 * today; it is here because handing an over-long count to write() would
	 * read past the buffer, and a tool that reads out of bounds while grading
	 * memory safety is not a tool anyone should have to think twice about.
	 * The line is ended even then, so the script still finds it. */
	if (n > (int)cap - 1)
	{
		n = (int)cap - 1;
		line[n - 1] = '\n';
	}
	return (n);
}

#endif
