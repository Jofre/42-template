/*
 * A decoy, for the subject's last line: "Watch out for wildcards!". The
 * grader's srcs/ may hold files your Makefile was never told about, and the
 * subject names the five it compiles: "These files will be: ft_putchar.c,
 * ft_swap.c, ft_putstr.c, ft_strlen.c, ft_strcmp.c." A Makefile that lists
 * those five never touches this file; one that globs srcs/ compiles it -- and
 * this is what it gets.
 */
#error "your Makefile compiled srcs/ft_not_listed.c: name the five sources the subject lists (Watch out for wildcards!)"
