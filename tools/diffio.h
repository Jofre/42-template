/* Shared helpers for live-differential reader harnesses (grader-side test infra).
 *
 * A reader harness reads the Rust reference's cases from stdin, decodes the
 * hex-encoded input fields, runs the student's function, and reprints the input
 * fields followed by the student's result — so tools/rust_diff.sh can byte-diff
 * it against the reference. These are test readers, not submissions: they use
 * libc freely and need not be norm-compliant.
 *
 * All helpers are `static inline` so a harness that uses only some of them still
 * compiles clean under -Wall -Wextra -Werror (no -Wunused-function). */
#ifndef DIFFIO_H
#define DIFFIO_H

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

/* The value of one hex digit, 0 for anything that is not one. A table rather
 * than range tests and `c - '0'` arithmetic, for the reason dio_caplen below
 * gives: the arithmetic spelling is the digit-value step of an ft_atoi_base,
 * and this file ships on the template. Same results for every char value
 * the callers pass, and for EOF: anything that is not a hex digit reads 0. */
static inline int	dio_hv(int c)
{
	static const unsigned char	value[256] = {
		['0'] = 0, ['1'] = 1, ['2'] = 2, ['3'] = 3, ['4'] = 4,
		['5'] = 5, ['6'] = 6, ['7'] = 7, ['8'] = 8, ['9'] = 9,
		['a'] = 10, ['b'] = 11, ['c'] = 12, ['d'] = 13, ['e'] = 14,
		['f'] = 15,
		['A'] = 10, ['B'] = 11, ['C'] = 12, ['D'] = 13, ['E'] = 14,
		['F'] = 15,
	};

	return (value[(unsigned char)c]);
}

/* Decode the first `hlen` hex digits of `h` (an even count) into a fresh
 * calloc'd buffer with `pad` extra zero bytes after the decoded content, plus
 * the one that terminates it as a C string. *len = decoded byte count.
 * dio_unhex is the same for a whole string. For an input the function under
 * test reads: a DESTINATION it writes into comes from dio_garbage or dio_dest
 * below, never from the zeroed tail of this one (finding 057). */
static inline unsigned char	*dio_unhexn(const char *h, size_t hlen, size_t *len, size_t pad)
{
	size_t			n;
	size_t			i;
	unsigned char	*b;

	n = hlen / 2;
	b = (unsigned char *)calloc(n + pad + 1, 1);
	i = 0;
	while (i < n)
	{
		b[i] = (unsigned char)((dio_hv(h[2 * i]) << 4) | dio_hv(h[2 * i + 1]));
		i++;
	}
	if (len)
		*len = n;
	return (b);
}

static inline unsigned char	*dio_unhex(const char *h, size_t *len, size_t pad)
{
	return (dio_unhexn(h, strlen(h), len, pad));
}

/* What a harness writes before it gives up on the corpus itself: the runner
 * (tools/rust_diff.sh) reads it and reports a broken harness, exit 2, rather
 * than a verdict on the student's function. */
#define DIO_HARNESS_ERROR "diffio: HARNESS ERROR: "

/* The harness cannot go on with this corpus: say why, and exit 2. */
static inline void	dio_fail(const char *why)
{
	fprintf(stderr, DIO_HARNESS_ERROR "%s\n", why);
	exit(2);
}

/* A destination for a function that writes into memory it is handed: exactly
 * cap bytes, every one 0xff (finding 057). In a zeroed buffer -- calloc,
 * memset 0, an array declared with "" or {0}, a static one -- the byte where a
 * terminator belongs is 0 before the call, so a function that never writes
 * one prints the right string, and neither the diff nor its ASan twin sees it.
 * 0xff is a byte no string function writes by accident, and a harness that
 * prints the buffer in hex shows it as ff. Never a byte more than cap, so a
 * write one past the end lands in an ASan redzone; cap 0 still gives a
 * pointer the function may be handed, since malloc(0) may return NULL.
 * //tools:conventions holds every diff_*.c to this: a zeroed buffer handed to
 * the function under test needs its reason written beside it. */
static inline unsigned char	*dio_garbage(size_t cap)
{
	unsigned char	*b;

	b = (unsigned char *)malloc(cap ? cap : 1);
	if (b == NULL)
		dio_fail("out of memory for a destination buffer");
	memset(b, 0xff, cap);
	return (b);
}

/* dio_garbage(cap) holding a string already: s[0..len) and a terminator, every
 * byte after it 0xff -- the destination of an append, whose free bytes must
 * not supply the terminator the append owes. len must be below cap, which it
 * checks: a case that broke it would have the HARNESS write past its own
 * block, and the ASan twin would blame that write on the student. */
static inline unsigned char	*dio_dest(const unsigned char *s, size_t len,
		size_t cap)
{
	unsigned char	*b;

	if (len >= cap)
		dio_fail("dio_dest: a string of len bytes needs a cap above len, for "
			"its terminator; this case asked for no more room than the string");
	b = dio_garbage(cap);
	memcpy(b, s, len);
	b[len] = '\0';
	return (b);
}

/* Print bytes b[0..n) as lowercase hex, no newline. */
static inline void	dio_puthex(const unsigned char *b, size_t n)
{
	size_t	i;

	i = 0;
	while (i < n)
	{
		printf("%02x", b[i]);
		i++;
	}
}

/* Length of a NUL-terminated region, but never scanning past `cap` bytes
 * (safe for buffers a correct impl may leave unterminated within `cap`).
 * memchr, not a hand-written scan: this file ships on the template, and a
 * length loop here is c-01's ft_strlen with one extra condition. memchr reads
 * at most `cap` bytes and stops at the first match, so the result -- and what
 * a sanitizer sees being read -- is the same. */
static inline size_t	dio_caplen(const unsigned char *b, size_t cap)
{
	const unsigned char	*nul;

	nul = (const unsigned char *)memchr(b, '\0', cap);
	if (nul == NULL)
		return (cap);
	return ((size_t)(nul - b));
}

/* SIZED FROM THE CASE, NEVER A CAPACITY. Every array a harness fills from a
 * corpus line comes from the helpers below, sized by what the line holds:
 * a fixed int tab[64] or char *items[64] overflowed the harness's own stack,
 * or silently dropped what did not fit, the first time a corpus held a case
 * bigger than whoever wrote the harness expected -- and either way the
 * differ blamed the student (finding 041). //tools:conventions refuses a
 * fixed-size array in a diff_*.c that is not one of the two bounded by
 * construction: the line dio_line reads (it exits 2 on a longer one) and the
 * fields dio_split splits it into (never more than it is given room for). */

/* A zeroed heap array of exactly n elements of `size` bytes: exact, so that
 * under ASan (exNN_diff_asan) a step past the end is caught at the edge of
 * the case itself. Never NULL: an empty case gets a valid pointer to nothing.
 * Out of memory is a harness error. free() it. */
static inline void	*dio_alloc(size_t n, size_t size)
{
	void	*p;

	p = calloc(n, size);
	if (p == NULL && n == 0)
		p = calloc(1, size);
	if (p == NULL)
		dio_fail("out of memory for a case");
	return (p);
}

/* ABOVE 4 GiB: WHERE A BLOCK WHOSE ADDRESS IS PRINTED LIVES (finding 048).
 *
 * A harness that checks an address the function printed against the one it
 * passed sees an address cut to 32 bits only if the two differ, and here they
 * do not: the reader programs are linked position-dependent, so the heap
 * starts just after the image, a few MiB into the address space, and every
 * block malloc hands out has an address that fits in 32 bits -- cut, it loses
 * only zeros and prints the real one. C 02 ex12's diff passed 100000 cases
 * with the address narrowed (the mutation run of 2026-10-03).
 *
 * dio_high(BLOCK, N): N bytes of BLOCK, a block from malloc, at an address
 * above 4 GiB -- BLOCK itself when it is there already (an ASan build's
 * allocator puts it far above, and its redzones then still catch a read past
 * the end), else a copy in a mapping of the program's own, which the kernel
 * places near the top of the address space, BLOCK freed. One mapping, reused
 * and grown from call to call: give the result back with dio_high_free(),
 * never free(). A block that cannot be put above 4 GiB is a harness error,
 * never a case that passes. //tools:conventions holds every reader harness
 * that turns a pointer into a number to calling it ("A harness that checks a
 * printed address puts the block above 4 GiB"). */
typedef struct s_dio_high
{
	unsigned char	*map;
	size_t			room;
}	t_dio_high;

static inline t_dio_high	*dio__high(void)
{
	static t_dio_high	h;

	return (&h);
}

static inline unsigned char	*dio_high(unsigned char *block, size_t n)
{
	t_dio_high	*h;
	void		*m;

	if ((uintptr_t)block > (uintptr_t)0xffffffffu)
		return (block);
	h = dio__high();
	if (n > h->room || h->map == NULL)
	{
		if (h->map != NULL)
			munmap(h->map, h->room);
		h->room = n < 4096 ? 4096 : n;
		m = mmap(NULL, h->room, PROT_READ | PROT_WRITE,
				MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
		if (m == MAP_FAILED)
			dio_fail("cannot map memory to put a block above 4 GiB");
		h->map = (unsigned char *)m;
	}
	if ((uintptr_t)h->map <= (uintptr_t)0xffffffffu)
		dio_fail("the block could not be put above 4 GiB, where an address "
			"narrowed to 32 bits differs from the real one: nothing was compared");
	memcpy(h->map, block, n);
	free(block);
	return (h->map);
}

/* Give back what dio_high returned: the mapping stays for the next call, a
 * block that was above 4 GiB already is freed. */
static inline void	dio_high_free(unsigned char *p)
{
	if (p != dio__high()->map)
		free(p);
}

/* How many items a comma-joined list holds: one more than its commas, none
 * when it is empty. */
static inline int	dio_ncsv(const char *s)
{
	int	n;

	if (*s == '\0')
		return (0);
	n = 1;
	while ((s = strchr(s, ',')) != NULL)
	{
		n++;
		s++;
	}
	return (n);
}

/* The comma-joined decimal ints of `s` ("" for none), in a heap array of
 * exactly *n of them (dio_alloc). free() it. */
static inline int	*dio_csv_ints(const char *s, int *n)
{
	int		*tab;
	char	*p;
	int		i;

	*n = dio_ncsv(s);
	tab = (int *)dio_alloc((size_t)*n, sizeof(int));
	p = (char *)s;
	i = 0;
	while (i < *n)
	{
		tab[i++] = (int)strtol(p, &p, 10);
		if (*p == ',')
			p++;
	}
	return (tab);
}

/* The comma-joined hex strings of `s`, exactly `n` of them (n - 1 commas;
 * one empty string is "" with n 1), each decoded to a NUL-terminated string
 * (dio_unhex), in a heap array of n plus a NULL after the last -- the shape
 * of a char ** a subject hands its function. A list that does not hold n is
 * a harness error. dio_free_list() releases it. */
static inline char	**dio_hex_n(const char *s, int n)
{
	char		**items;
	const char	*p;
	const char	*comma;
	size_t		len;
	int			i;

	items = (char **)dio_alloc((size_t)n + 1, sizeof(char *));
	p = s;
	i = 0;
	while (i < n)
	{
		comma = strchr(p, ',');
		if ((comma == NULL) != (i == n - 1))
			dio_fail("a list holds a different number of items than its count");
		len = comma ? (size_t)(comma - p) : strlen(p);
		items[i++] = (char *)dio_unhexn(p, len, NULL, 0);
		p += len + (comma != NULL);
	}
	if (n == 0 && *s != '\0')
		dio_fail("a list holds items where its count says none");
	return (items);
}

/* The same, as many as `s` holds ("" for none): *n = dio_ncsv(s). */
static inline char	**dio_hex_list(const char *s, int *n)
{
	*n = dio_ncsv(s);
	return (dio_hex_n(s, *n));
}

/* Free what dio_hex_list returned: its n strings, then the array. */
static inline void	dio_free_list(char **items, int n)
{
	int	i;

	i = 0;
	while (i < n)
		free(items[i++]);
	free(items);
}

/* WHICH CORPUS CASE A HARNESS DIED ON (finding 051, V46).
 *
 * A harness that dies takes its buffered stdout with it, so the runner can
 * only say the run stopped "at or after" the last answer it received, give or
 * take a few thousand cases. The harness knows exactly: dio_line (and
 * dio_getline) counts the lines it hands out, and when it dies it writes the
 * count -- the corpus line it was on, as a decimal number and a newline --
 * into the file the runner named in DIO_CASE_FILE. tools/rust_diff.sh names
 * one, reads the number back, and shows that line from the corpus.
 *
 * ONLY WHEN ASKED, and never on stderr. The same harnesses are also run by
 * runners with a corpus of their own (diff_output.sh --harness-fixture over
 * Rush 00's case files, whose comment lines the count would include), and
 * timed by the perf and cycles layers. A line on stderr reached those logs
 * too, with a case number nobody could match (the review of V46). With no
 * DIO_CASE_FILE nothing is installed and nothing is written: the count is
 * all the harness keeps, one increment per line.
 *
 * Under ASan the number is written from the sanitizer's death callback,
 * which runs before it aborts. The plain build has none, so it writes it from
 * a signal handler on the first SIGSEGV, SIGBUS, SIGFPE, SIGILL or SIGABRT,
 * on a stack of its own (a recursion that never ends dies by running out of
 * the one it had), with calls a handler may make (open, write, close), then
 * lets the signal end the run as it would have: SA_RESETHAND puts the
 * default action back and the handler raises it again, so the status the
 * runner reads is unchanged. */
#if defined(__SANITIZE_ADDRESS__)
# define DIO_SANITIZED 1
#elif defined(__has_feature)
# if __has_feature(address_sanitizer)
#  define DIO_SANITIZED 1
# endif
#endif

#include <fcntl.h>
#include <unistd.h>

static inline unsigned long	*dio__count(void)
{
	static unsigned long	n;

	return (&n);
}

static inline const char	**dio__case_file(void)
{
	static const char	*path;

	return (&path);
}

/* The count, in decimal, into DIO_CASE_FILE: nothing here but calls a
 * signal handler may make. */
static inline void	dio__say_case(void)
{
	char			buf[24];
	size_t			i;
	unsigned long	n;
	int				fd;
	ssize_t			w;

	n = *dio__count();
	if (n == 0 || *dio__case_file() == NULL)
		return ;
	i = sizeof(buf);
	buf[--i] = '\n';
	do
	{
		buf[--i] = (char)('0' + n % 10);
		n /= 10;
	} while (n > 0);
	fd = open(*dio__case_file(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (fd < 0)
		return ;
	w = write(fd, buf + i, sizeof(buf) - i);
	(void)w;
	close(fd);
}

#ifdef DIO_SANITIZED
# include <sanitizer/common_interface_defs.h>

static inline void	dio__arm(void)
{
	__sanitizer_set_death_callback(dio__say_case);
}
#else
# include <signal.h>

static inline void	dio__on_signal(int sig)
{
	dio__say_case();
	raise(sig);
}

static inline void	dio__arm(void)
{
	static char			alt[1 << 16];
	static const int	sigs[] = {SIGSEGV, SIGBUS, SIGFPE, SIGILL, SIGABRT};
	struct sigaction	sa;
	stack_t				st;
	size_t				i;

	st.ss_sp = alt;
	st.ss_size = sizeof(alt);
	st.ss_flags = 0;
	sigaltstack(&st, NULL);
	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = dio__on_signal;
	sigemptyset(&sa.sa_mask);
	sa.sa_flags = SA_ONSTACK | SA_RESETHAND | SA_NODEFER;
	i = 0;
	while (i < sizeof(sigs) / sizeof(sigs[0]))
		sigaction(sigs[i++], &sa, NULL);
}
#endif

/* One more line handed out. On the first, the runner's DIO_CASE_FILE is
 * read, and the report armed only when it names a file. */
static inline void	dio__track(void)
{
	const char	*path;

	if ((*dio__count())++ > 0)
		return ;
	path = getenv("DIO_CASE_FILE");
	if (path == NULL || path[0] == '\0')
		return ;
	*dio__case_file() = path;
	dio__arm();
}

/* Read one line from stdin into buf (newline stripped). Returns 1, or 0 at EOF.
 *
 * A line longer than `cap` is a HARNESS error, and ends the harness with exit
 * 2. fgets() splits it silently: the first `cap - 1` bytes came back as one
 * case and the rest as the next, each decoded as though it were whole -- so a
 * corpus that grew past a harness's buffer turned into cases nobody wrote,
 * judged against answers for other ones (finding 041). A harness that must
 * take lines of any length reads them with dio_getline instead. */
static inline int	dio_line(char *buf, int cap)
{
	size_t	n;
	int		c;

	if (!fgets(buf, cap, stdin))
		return (0);
	n = strlen(buf);
	if (n > 0 && buf[n - 1] == '\n')
	{
		buf[n - 1] = '\0';
		dio__track();
		return (1);
	}
	if ((int)n + 1 < cap)
	{
		dio__track();
		return (1);
	}
	c = getc(stdin);
	if (c == EOF || c == '\n')
	{
		dio__track();
		return (1);
	}
	fprintf(stderr, DIO_HARNESS_ERROR "a corpus line is longer than this "
		"harness's %d-byte buffer. Read it with dio_getline, which takes "
		"a line of any length.\n", cap);
	exit(2);
}

/* Read one line of ANY length from stdin into *buf (newline stripped), which
 * is grown with realloc as a line needs: start with *buf NULL and *cap 0, and
 * free(*buf) at the end. Returns 1, or 0 at EOF. For the harnesses whose
 * corpus holds one case far larger than the others -- an array of thousands
 * of ints, a string of thousands of words -- where no fixed buffer is big
 * enough for every case a generator may add. Out of memory is a harness
 * error, exit 2. */
static inline int	dio_getline(char **buf, size_t *cap)
{
	size_t	len;
	char	*grown;

	if (*buf == NULL || *cap < 2)
	{
		*cap = 8192;
		*buf = (char *)malloc(*cap);
		if (*buf == NULL)
			goto oom;
	}
	len = 0;
	while (fgets(*buf + len, (int)(*cap - len), stdin))
	{
		len += strlen(*buf + len);
		if (len > 0 && (*buf)[len - 1] == '\n')
		{
			(*buf)[len - 1] = '\0';
			dio__track();
			return (1);
		}
		if (len + 1 < *cap)
		{
			dio__track();
			return (1);
		}
		grown = (char *)realloc(*buf, *cap * 2);
		if (grown == NULL)
			goto oom;
		*buf = grown;
		*cap *= 2;
	}
	if (len == 0)
		return (0);
	dio__track();
	return (1);
oom:
	fprintf(stderr, DIO_HARNESS_ERROR "out of memory for a corpus line\n");
	exit(2);
}

/* How many fields dio_split would find in `line`: one more than its tabs.
 * For sizing the arrays a harness splits a line into, when the corpus decides
 * how many fields a case has. */
static inline int	dio_nfields(const char *line)
{
	int	n;

	n = 1;
	while ((line = strchr(line, '\t')) != NULL)
	{
		n++;
		line++;
	}
	return (n);
}

/* Split `line` in place on tabs into fields[0..maxf); returns field count.
 * Past maxf the rest of the line stays in the last field: a harness reads
 * its inputs from the first fields and leaves the reference's answer, which
 * may hold any number of tabs, in the last one. Where every field is an
 * input -- one per string of an array -- size `fields` with dio_nfields and
 * give it all of them, or use dio_split_all. */
static inline int	dio_split(char *line, char **fields, int maxf)
{
	int		n;
	char	*p;

	n = 0;
	p = line;
	fields[n++] = p;
	while (n < maxf && (p = strchr(p, '\t')))
	{
		*p++ = '\0';
		fields[n++] = p;
	}
	return (n);
}

/* Every field of `line`, split in place on tabs, in a heap array of exactly
 * *n of them (dio_nfields): for a line whose fields are ALL inputs, as many
 * as the case has. free() the array; the fields are the line's own bytes. */
static inline char	**dio_split_all(char *line, int *n)
{
	char	**fields;

	*n = dio_nfields(line);
	fields = (char **)dio_alloc((size_t)*n, sizeof(char *));
	dio_split(line, fields, *n);
	return (fields);
}

#endif
