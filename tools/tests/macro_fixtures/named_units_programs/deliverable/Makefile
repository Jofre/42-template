# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    Makefile                                           :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: marvin <marvin@42.fr>                      +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/10/24 00:00:00 by marvin            #+#    #+#              #
#    Updated: 2026/10/24 00:00:00 by marvin           ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

NAME = sorter

all: $(NAME)

$(NAME):
	@echo cc -Wall -Wextra -Werror -o $(NAME) toy_sort.c toy_order.c

bonus:
	@echo cc -Wall -Wextra -Werror -o checker toy_check.c toy_order.c

clean:
	@echo rm -f

fclean: clean
	@echo rm -f $(NAME) checker

re: fclean all

.PHONY: all bonus clean fclean re
