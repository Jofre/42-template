/* The parameter NAMES Libft prints, for the functions whose box prints them:
 * each "Prototype" line of Part 2 (pp.10-13) and Part 3 (pp.14-16), as
 * printed -- "Prototype char *ft_substr(char const *s, unsigned int start,
 * size_t len);" (p.10), and so on -- with each box's "Parameters" naming them
 * again. Nothing of Part 1, whose prototypes are the man pages' (p.8) and
 * whose names the subject does not print.
 *
 * Read by tools/prototype_check.sh --names (ex00_prototype_names, strict).
 * That a box's names bind your definition is this harness's reading: a name
 * changes nothing a program does, and only an evaluator reading the code can
 * mark it. The types are prototype.h's, at basic. A names contract includes
 * nothing, so size_t and t_list are declared here only so that this file
 * compiles alone. */
#ifndef PROTOTYPE_NAMES_LIBFT_EX00_H
# define PROTOTYPE_NAMES_LIBFT_EX00_H

typedef __SIZE_TYPE__	size_t;
typedef struct s_list	t_list;

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
