#include <stdio.h>
#include <limits.h>

/* Prototypes of the libft functions under test (ex00 ships no header). */
void	ft_putchar(char c);
void	ft_swap(int *a, int *b);
void	ft_putstr(char *str);
int		ft_strlen(char *str);
int		ft_strcmp(char *s1, char *s2);

static void	test_strlen(void)
{
	printf("strlen:\n");
	printf("  empty=%d\n", ft_strlen(""));
	printf("  one=%d\n", ft_strlen("a"));
	printf("  hello=%d\n", ft_strlen("hello"));
	printf("  spaced=%d\n", ft_strlen("a b c 42!"));
}

/* strcmp must return the EXACT (unsigned char)s1[k] - (unsigned char)s2[k] at
 * the first differing index k (0 when equal), not merely a sign. The hi_* cases
 * feed bytes >= 0x80 to catch a signed-char implementation, which would yield a
 * negative result (e.g. -129) where the contract requires a positive one. */
static void	test_strcmp(void)
{
	printf("strcmp:\n");
	printf("  eq=%d\n", ft_strcmp("abc", "abc"));
	printf("  lt=%d\n", ft_strcmp("abc", "abd"));
	printf("  gt=%d\n", ft_strcmp("abd", "abc"));
	printf("  prefix_short=%d\n", ft_strcmp("abc", "abcd"));
	printf("  prefix_long=%d\n", ft_strcmp("abcd", "abc"));
	printf("  both_empty=%d\n", ft_strcmp("", ""));
	printf("  empty_vs_a=%d\n", ft_strcmp("", "a"));
	printf("  a_vs_empty=%d\n", ft_strcmp("a", ""));
	printf("  hi_80_vs_01=%d\n", ft_strcmp("\x80", "\x01"));
	printf("  hi_ff_vs_a=%d\n", ft_strcmp("\xff", "a"));
	printf("  hi_A80_vs_A7f=%d\n", ft_strcmp("A\x80", "A\x7f"));
}

static void	test_swap(void)
{
	int	a;
	int	b;
	int	x;

	printf("swap:\n");
	a = 3;
	b = 7;
	ft_swap(&a, &b);
	printf("  basic a=%d b=%d\n", a, b);
	a = -5;
	b = 10;
	ft_swap(&a, &b);
	printf("  signed a=%d b=%d\n", a, b);
	a = INT_MIN;
	b = INT_MAX;
	ft_swap(&a, &b);
	printf("  extreme a=%d b=%d\n", a, b);
	x = 42;
	ft_swap(&x, &x);
	printf("  alias x=%d\n", x);
}

static void	test_putchar(void)
{
	printf("putchar:[");
	ft_putchar('A');
	ft_putchar('4');
	ft_putchar('2');
	printf("]\n");
}

static void	test_putstr(void)
{
	printf("putstr:[");
	ft_putstr("hello");
	ft_putstr("");
	ft_putstr("42");
	printf("]\n");
}

int	main(void)
{
	/* Unbuffer stdout so printf labels and write()-based output interleave in
	 * source order rather than at flush time. */
	setbuf(stdout, NULL);
	test_strlen();
	test_strcmp();
	test_swap();
	test_putchar();
	test_putstr();
	return (0);
}
