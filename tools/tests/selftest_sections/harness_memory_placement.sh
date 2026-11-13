# ----------------------------------------------------- harness memory placement
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# Where a differential harness puts what it hands the function decides what a
# wrong answer can be seen to get wrong.
#
# C 02 ex12's harness checks each printed address against the block's. It is
# linked position-dependent, as Bazel's toolchain links it, so a block from
# malloc sat a few MiB into the address space, and an address cut to 32 bits
# printed the real one: 100000 cases passed with the address narrowed (the
# mutation run of 2026-10-03). Built here the same way (-no-pie) over a toy
# that prints nothing but its argument cut to 32 bits, in the row's place: the
# harness must not take that for the block's address, which it shows as the
# row's offset, 0000000000000000. The toy is named apart, and the harness's
# call renamed to it (-D), so nothing outside the zone defines the exercise's
# function.
printf '%s\n' '#include <stdio.h>' '#include <unistd.h>' \
	'void	*toy_addr32(void *addr, unsigned int size)' '{' \
	'	char	row[40];' '	int		n;' '' '	if (size == 0)' '		return (addr);' \
	'	n = snprintf(row, sizeof(row), "%016x: \n", (unsigned int)(unsigned long)addr);' \
	'	write(1, row, (size_t)n);' '	return (addr);' '}' > "$WORK/toy_addr32.c"
! st_mine || toy_cc "$WORK/pm_addr32" -no-pie -I "$TOOLS" -Dft_print_memory=toy_addr32 \
	"$ROOT/c-piscine/c-piscine-c-02/tests/ex12/diff_print_memory.c" "$WORK/toy_addr32.c"
pm_addr32_run() {  # one five-byte block through the harness
	printf '6162636465\t5\n' | "$WORK/pm_addr32"
}
want_out "C 02 ex12 diff harness: a block is replayed" '6162636465	5	' -- pm_addr32_run
want_broken_none "...and an address cut to 32 bits is not the block's" \
	'6162636465	5	0000000000000000: \n	1' -- pm_addr32_run
# A wrong address the function printed is kept, marked with a '!' the
# reference never prints. Kept bare, an address that was the row's offset
# (0000000000000000, then ...0010) was the reference's own record, byte for
# byte: a toy printing the offset where the address goes, built like the one
# above, is not the block's record either.
printf '%s\n' '#include <stdio.h>' '#include <unistd.h>' \
	'void	*toy_offset(void *addr, unsigned int size)' '{' \
	'	char	row[40];' '	int		n;' '' '	if (size == 0)' '		return (addr);' \
	'	n = snprintf(row, sizeof(row), "%016x: \n", 0u);' \
	'	write(1, row, (size_t)n);' '	return (addr);' '}' > "$WORK/toy_offset.c"
! st_mine || toy_cc "$WORK/pm_offset" -no-pie -I "$TOOLS" -Dft_print_memory=toy_offset \
	"$ROOT/c-piscine/c-piscine-c-02/tests/ex12/diff_print_memory.c" "$WORK/toy_offset.c"
pm_offset_run() {  # the same five-byte block
	printf '6162636465\t5\n' | "$WORK/pm_offset"
}
want_out "C 02 ex12 diff harness: an address that is the row's offset is kept, marked" \
	'6162636465	5	!0000000000000000: \n	1' -- pm_offset_run
want_broken_none "...and is not the block's record" \
	'6162636465	5	0000000000000000: \n	1' -- pm_offset_run

# The same harness compiled by the pinned gcc, at -O0 and at -O2, over a toy
# that writes the block it is handed, raw, and nothing else (named apart, the
# call renamed with -D). C leaves the order of a call's arguments open, and
# where the block's length was read in the same call that sets it, gcc-10
# read it first: the previous case's length, or none, so a block reached the
# function cut short, or the harness died at -O0. Three blocks of different
# lengths must each come back whole. gcc compiles it, its assembler offered
# through -B with the libraries the pinned binutils load (--nm-lib's folder);
# the pinned clang links it.
printf '%s\n' '#include <unistd.h>' \
	'void	*toy_raw(void *addr, unsigned int size)' '{' '	ssize_t	w;' '' \
	'	w = write(1, addr, size);' '	(void)w;' '	return (addr);' '}' > "$WORK/toy_raw.c"
mkdir -p "$WORK/pm_gccb"
_pm_as=$(cd "$(dirname "$AS")" && pwd)/${AS##*/}
_pm_aslib=$(cd "$(dirname "$NM_LIB")" && pwd)
printf "#!/bin/sh\nLD_LIBRARY_PATH='%s'\nexport LD_LIBRARY_PATH\nexec '%s' \"\$@\"\n" \
	"$_pm_aslib" "$_pm_as" > "$WORK/pm_gccb/as"
chmod +x "$WORK/pm_gccb/as"
for _o in O0 O2; do
	! st_mine || { toy_cc --cc "$GCC" "$WORK/pm_gcc_$_o.o" -B"$WORK/pm_gccb/" -c -"$_o" \
		-I "$TOOLS" -Dft_print_memory=toy_raw \
		"$ROOT/c-piscine/c-piscine-c-02/tests/ex12/diff_print_memory.c" &&
		toy_cc "$WORK/pm_gcc_$_o" -no-pie "$WORK/pm_gcc_$_o.o" "$WORK/toy_raw.c"; }
done
pm_gcc_run() {  # pm_gcc_run LEVEL -- three blocks, the records on one line
	_pm_out=$(printf '41424344\t4\n4546\t2\n4748494a4b4c4d4e\t8\n' | "$WORK/pm_gcc_$1")
	_pm_rc=$?
	printf '%s|' "$_pm_out" | tr '\n' '|'
	return "$_pm_rc"
}
_pm_whole=$(printf '41424344\t4\tABCD\t1|4546\t2\tEF\t1|4748494a4b4c4d4e\t8\tGHIJKLMN\t1|')
want_out "C 02 ex12 diff harness: built by gcc -O0, each block reaches the function whole" \
	"$_pm_whole" -- pm_gcc_run O0
want_out "...and built by gcc -O2" "$_pm_whole" -- pm_gcc_run O2

# A field a function never writes, in memory it took from malloc. A reader
# harness frees each case's result before the next, so the next block is the
# same one, and glibc hands it back with its second word zeroed: C 13 ex00's
# diff read a node's unwritten `right` as NULL for 400000 cases (the mutation
# run of 2026-10-03). Every program linking //tools:diffio has malloc wrapped
# (tools/dirty_malloc.c), so the block holds no zero. The toy reader
# tools/tests/diffio_probe.c, over an invented three-field record whose maker
# never writes the middle one: built by Bazel through //tools:diffio
# (:diffio_probe), as every c_diff reader is, every case reads it set -- which
# holds the library's source and its -Wl,--wrap=malloc both, where a copy
# compiled here with the flag held neither (the wave 6 review). The same
# reader built bare shows the premise: on this C library the reused block
# reads NULL.
! st_mine || toy_cc "$WORK/trio_bare" -I "$TOOLS" "$TOOLS/tests/diffio_probe.c" \
	"$TOOLS/tests/diffio_probe_toy.c"
trio_run() {  # trio_run BIN -- three cases, each block the last one's
	printf 'x\ny\nz\n' | "$1"
}
want_out "dirty_malloc: premise, a reused block reads an unwritten field NULL" \
	'NULL' -- trio_run "$WORK/trio_bare"
want_broken_none "dirty_malloc: through //tools:diffio, never" 'NULL' -- \
	trio_run "$TOOLS/tests/diffio_probe"
want_out "dirty_malloc: ...and the reader ran" 'SET' -- trio_run "$TOOLS/tests/diffio_probe"
# HOW MUCH it fills: the first 4 KiB of a block and its last bytes, never the
# middle of a big one. Filled whole, a correct answer that asks malloc for a
# megabyte a call paid for every byte of it on every case, and a value diff
# became a timeout (the wave 6 review). The probe's one block of 1 MiB.
want_out "dirty_malloc: a big block's head and tail hold the fill" \
	'head FILLED, middle' -- "$TOOLS/tests/diffio_probe" big
want_out "dirty_malloc: ...its last byte, where a terminator goes" \
	', tail FILLED' -- "$TOOLS/tests/diffio_probe" big
want_out "dirty_malloc: ...and not its middle, which costs a block's size" \
	'middle LEFT,' -- "$TOOLS/tests/diffio_probe" big

# A field the harness cannot decode for want of memory is the harness's
# error (exit 2), never a case the function under test is blamed for.
# dio_unhex wrote through a calloc it never checked: the harness died of
# SIGSEGV, which the runner reports as a crash on that case, and an empty
# field reached the function as NULL. A toy that includes tools/diffio.h,
# its every calloc failing (-Wl,--wrap=calloc), decodes the field it is
# given.
printf '%s\n' '#include "diffio.h"' '' \
	'void	*__wrap_calloc(size_t n, size_t size)' '{' '	(void)n;' '	(void)size;' \
	'	return (NULL);' '}' '' \
	'int	main(int argc, char **argv)' '{' '	size_t			len;' '	unsigned char	*b;' '' \
	'	b = dio_unhex(argc > 1 ? argv[1] : "", &len, 0);' \
	'	puts(b == NULL ? "NULL" : "decoded");' '	return (0);' '}' > "$WORK/toy_nocalloc.c"
! st_mine || toy_cc "$WORK/dio_nocalloc" -I "$TOOLS" "$WORK/toy_nocalloc.c" -Wl,--wrap=calloc
want_broken "diffio: a decoded field calloc cannot give is a harness error" \
	'diffio: HARNESS ERROR' -- "$WORK/dio_nocalloc" 4142
want_broken "...and an empty one, never NULL for the function" \
	'diffio: HARNESS ERROR' -- "$WORK/dio_nocalloc" ''

# Where a writer's bytes go. Libft's fd readers hand the function a file on
# a descriptor of 3 or more and read it back; fd 1 is their own stream, so
# bytes a function also wrote there landed in the middle of their lines,
# before the input column, and the report paired the wrong lines (V217). As
# the fixtures do, fd 1 is a second file during the call, and what it got
# is a third column. Each reader is built here over a toy that writes
# "dbg\n" to fd 1 and nothing to its fd, its call renamed to the toy (-D):
# each line must still begin with the case's input, with 6462670a, those
# four bytes, as its third column.
printf '%s\n' '#include <unistd.h>' \
	'void	toy_fd1_str(char *s, int fd)' '{' '	(void)s;' '	(void)fd;' \
	'	write(1, "dbg\n", 4);' '}' '' \
	'void	toy_fd1_nbr(int n, int fd)' '{' '	(void)n;' '	(void)fd;' \
	'	write(1, "dbg\n", 4);' '}' > "$WORK/toy_fd1.c"
_lfd=$ROOT/cursus/Milestone_0/Libft/tests
if st_mine; then
	for _w in putstr:str putendl:str putnbr:nbr; do
		toy_cc "$WORK/fd1_${_w%%:*}" -I "$TOOLS" -Dft_${_w%%:*}_fd=toy_fd1_${_w#*:} \
			"$_lfd/ft_${_w%%:*}_fd/diff_ft_${_w%%:*}_fd.c" "$WORK/toy_fd1.c"
	done
fi
# fd1_run BIN IN -- two cases of input column IN through the reader: red
# unless both lines begin with IN and a tab, and end in the fd-1 column.
fd1_run() {
	[ -x "$1" ] || { echo "the reader was not built" >&2; return 2; }
	printf '%s\tx\n%s\tx\n' "$2" "$2" | "$1" > "$WORK/fd1.out" 2>&1
	cat "$WORK/fd1.out"
	awk -F'\t' -v want="$2" '
		$1 != want || NF != 3 || $3 != "6462670a" { bad = 1 }
		END { exit (bad || NR != 2) }' "$WORK/fd1.out"
}
want_green "Libft ft_putstr_fd reader: fd 1's bytes get a column" -- \
	fd1_run "$WORK/fd1_putstr" 6869
want_green "Libft ft_putendl_fd reader: ...and ft_putendl_fd's" -- \
	fd1_run "$WORK/fd1_putendl" 6869
want_green "Libft ft_putnbr_fd reader: ...and ft_putnbr_fd's" -- \
	fd1_run "$WORK/fd1_putnbr" 42

# A copy that is the source itself. Libft's ft_strdup reader printed what
# the returned pointer held, then freed it only when it was not the source:
# so an ft_strdup handing s back printed the source's own bytes, which is
# the reference's line, and both diff layers passed it. It prints SAME
# there, which the reference never writes, decided before anything is
# freed. Built over a toy that returns its argument (named apart, the call
# renamed with -D), plain and under ASan, which must see no double free.
printf '%s\n' 'char	*toy_strdup_same(const char *s)' '{' '	return ((char *)s);' '}' \
	> "$WORK/toy_strdup_same.c"
if st_mine; then
	toy_cc "$WORK/strdup_same" -I "$TOOLS" -Dft_strdup=toy_strdup_same \
		"$_lfd/ft_strdup/diff_ft_strdup.c" "$WORK/toy_strdup_same.c"
	toy_cc "$WORK/strdup_same_asan" -g -fsanitize=address -I "$TOOLS" -Dft_strdup=toy_strdup_same \
		"$_lfd/ft_strdup/diff_ft_strdup.c" \
		"$WORK/toy_strdup_same.c"
fi
strdup_same_run() {  # strdup_same_run BIN -- one case, "hi"
	[ -x "$1" ] || { echo "the reader was not built" >&2; return 2; }
	printf '6869\n' | env ASAN_OPTIONS=detect_leaks=0 "$1"
}
want_out "Libft ft_strdup reader: a copy that is the source itself is SAME" \
	"$(printf '6869\tSAME')" -- strdup_same_run "$WORK/strdup_same"
want_out "...and under ASan, which it ends with no double free" \
	"$(printf '6869\tSAME')" -- strdup_same_run "$WORK/strdup_same_asan"

