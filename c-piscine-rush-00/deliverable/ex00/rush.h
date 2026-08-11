/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   rush.h                                             :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: marvin <marvin@42.fr>                      +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2026/08/05 01:35:10 by marvin            #+#    #+#             */
/*   Updated: 2026/08/05 01:35:10 by marvin           ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

#ifndef RUSH_H
# define RUSH_H

/*
** Only ft_putchar is shared between files. Keep each rush0N.c's helpers static
** and declare them locally, so every one of those files exports rush() and
** nothing else -- the symbols layer checks exactly that.
*/
void	ft_putchar(char c);

#endif
