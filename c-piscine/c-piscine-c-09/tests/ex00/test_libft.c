#include <stdio.h>
#include <limits.h>

/* Prototypes of the libft functions under test (ex00 ships no header). */
void	ft_putchar(char c);
void	ft_swap(int *a, int *b);
void	ft_putstr(char *str);
int		ft_strlen(char *str);
int		ft_strcmp(char *s1, char *s2);

/* The utf8_ and hi_ strlen lines, and putstr_hi, hold bytes >= 0x80: a scan
 * that treats a byte a plain char holds as negative as the end of the string
 * stops early on them. Each module is its own repository, graded on its own
 * files, so this one covers them at basic too. */
static void	test_strlen(void)
{
	printf("strlen:\n");
	printf("  empty=%d\n", ft_strlen(""));
	printf("  one=%d\n", ft_strlen("a"));
	printf("  hello=%d\n", ft_strlen("hello"));
	printf("  spaced=%d\n", ft_strlen("a b c 42!"));
	printf("  utf8_cafe=%d\n", ft_strlen("caf\xC3\xA9"));
	printf("  hi_ff=%d\n", ft_strlen("\xff"));
}

/* The SIGN of a comparison result, as a word. The subject sends you to
 * `man strcmp`, whose RETURN VALUE promises a sign; whether the exact int is
 * graded as well is not settled, so this basic table compares the sign only
 * and the strict diff layer compares the int itself. */
static const char	*sign(int v)
{
	if (v < 0)
		return ("negative");
	if (v > 0)
		return ("positive");
	return ("zero");
}

/* These cases print the SIGN of what ft_strcmp returns, as a word (see sign()
 * above). The hi_* cases use bytes >= 0x80: whether a char is read as signed
 * or unsigned flips the sign of the answer for those bytes. Which reading is
 * right is in `man strcmp`. */
static void	test_strcmp(void)
{
	printf("strcmp:\n");
	printf("  eq=%s\n", sign(ft_strcmp("abc", "abc")));
	printf("  lt=%s\n", sign(ft_strcmp("abc", "abd")));
	printf("  gt=%s\n", sign(ft_strcmp("abd", "abc")));
	printf("  prefix_short=%s\n", sign(ft_strcmp("abc", "abcd")));
	printf("  prefix_long=%s\n", sign(ft_strcmp("abcd", "abc")));
	printf("  both_empty=%s\n", sign(ft_strcmp("", "")));
	printf("  empty_vs_a=%s\n", sign(ft_strcmp("", "a")));
	printf("  a_vs_empty=%s\n", sign(ft_strcmp("a", "")));
	printf("  hi_80_vs_01=%s\n", sign(ft_strcmp("\x80", "\x01")));
	printf("  hi_ff_vs_a=%s\n", sign(ft_strcmp("\xff", "a")));
	printf("  hi_A80_vs_A7f=%s\n", sign(ft_strcmp("A\x80", "A\x7f")));
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
	printf("putstr_hi:[");
	ft_putstr("caf\xC3\xA9");
	ft_putstr("\xff");
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
