# **************************************************************************** #
#                                                                              #
#   Makefile (stub) -- the same toy library, one of its sources broken         #
#                                                                              #
#   The recipes only echo: `make -Bn` reads the compile line they print,       #
#   which names both sources and -I inc. toy_right.c does not compile, so      #
#   every member's program is a stand-in saying so, toy_left's too.            #
#                                                                              #
# **************************************************************************** #

NAME = libtoy14.a

$(NAME):
	@echo cc -Wall -Wextra -Werror -I inc -c toy_left.c toy_right.c
	@echo ar -crs $(NAME) toy_left.o toy_right.o

.PHONY:
