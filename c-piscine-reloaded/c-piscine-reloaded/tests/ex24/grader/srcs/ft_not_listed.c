/*
 * A decoy. The grader's srcs/ may hold files your Makefile was never told
 * about, and the Norm says: "All source files needed to compile your project
 * must be explicitly named in your Makefile. Eg: no *.c, no *.o". A Makefile
 * that lists its five sources never touches this file; one that globs srcs/
 * compiles it -- and this is what it gets.
 */
#error "your Makefile compiled srcs/ft_not_listed.c: name each source explicitly (the Norm forbids *.c in a Makefile)"
