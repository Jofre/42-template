/* Contract header -- the 43 signatures Libft fixes (v19.3), one per
 * function of the library.
 *
 * Part 1 (p.8): "Your version will have the same prototypes and behaviors as
 * the originals, adhering strictly to their definitions in the man page. The
 * only difference will be their names, which must start with the 'ft_'
 * prefix." So each Part 1 line is its man page's SYNOPSIS (man 3 <name>; for
 * strlcpy, strlcat and strnstr, man 3bsd <name>), with ft_ in front and no
 * 'restrict': "it is forbidden to include it in your own prototypes" (p.8).
 * Part 2 (pp.10-13) and Part 3 (pp.14-16): each function's "Prototype" line,
 * as its box prints it.
 *
 * The prototype layer (ex00_prototype) compiles each of your files with this
 * force-included, so the compiler sees the subject's declaration and your
 * definition in the SAME translation unit: a different return type or
 * parameter list is a conflicting-types error, instead of linking silently.
 * libft.h is included for t_list, which p.14 prints for it. */
#ifndef PROTOTYPE_LIBFT_EX00_H
# define PROTOTYPE_LIBFT_EX00_H

# include <stddef.h>
# include "libft.h"

int		ft_isalpha(int c);
int		ft_isdigit(int c);
int		ft_isalnum(int c);
int		ft_isascii(int c);
int		ft_isprint(int c);
int		ft_toupper(int c);
int		ft_tolower(int c);
void	*ft_memset(void *s, int c, size_t n);
void	ft_bzero(void *s, size_t n);
void	*ft_memcpy(void *dest, const void *src, size_t n);
void	*ft_memmove(void *dest, const void *src, size_t n);
void	*ft_memchr(const void *s, int c, size_t n);
int		ft_memcmp(const void *s1, const void *s2, size_t n);
void	*ft_calloc(size_t nmemb, size_t size);
size_t	ft_strlen(const char *s);
size_t	ft_strlcpy(char *dst, const char *src, size_t size);
size_t	ft_strlcat(char *dst, const char *src, size_t size);
char	*ft_strchr(const char *s, int c);
char	*ft_strrchr(const char *s, int c);
int		ft_strncmp(const char *s1, const char *s2, size_t n);
char	*ft_strnstr(const char *big, const char *little, size_t len);
int		ft_atoi(const char *nptr);
char	*ft_strdup(const char *s);
char	*ft_substr(char const *s, unsigned int start, size_t len);
char	*ft_strjoin(char const *s1, char const *s2);
char	*ft_strtrim(char const *s1, char const *set);
char	**ft_split(char const *s, char c);
char	*ft_itoa(int n);
char	*ft_strmapi(char const *s, char (*f)(unsigned int, char));
void	ft_striteri(char *s, void (*f)(unsigned int, char*));
void	ft_putchar_fd(char c, int fd);
void	ft_putstr_fd(char *s, int fd);
void	ft_putendl_fd(char *s, int fd);
void	ft_putnbr_fd(int n, int fd);
t_list	*ft_lstnew(void *content);
void	ft_lstadd_front(t_list **lst, t_list *new);
unsigned int	ft_lstsize(t_list *lst);
t_list	*ft_lstlast(t_list *lst);
void	ft_lstadd_back(t_list **lst, t_list *new);
void	ft_lstdelone(t_list *lst, void (*del)(void *));
void	ft_lstclear(t_list **lst, void (*del)(void *));
void	ft_lstiter(t_list *lst, void (*f)(void *));
t_list	*ft_lstmap(t_list *lst, void *(*f)(void *), void (*del)(void *));

#endif
