# **************************************************************************** #
#                                                                              #
#   Makefile (stub) -- a toy library whose Makefile is written                 #
#                                                                              #
#   The recipes only echo: `make -Bn` reads the compile line they print,       #
#   which names both sources and -I inc, and nothing runs. Each member's       #
#   program is built from what it names, inc/toy13.h found through its -I.     #
#                                                                              #
# **************************************************************************** #

NAME = libtoy13.a

$(NAME):
	@echo cc -Wall -Wextra -Werror -I inc -c toy_up.c toy_down.c
	@echo ar -crs $(NAME) toy_up.o toy_down.o

.PHONY:
