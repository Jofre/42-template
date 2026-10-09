/* The signature the Rush 00 subject fixes for every variant (p.8, "Function
 * requirements"): "The function must be prototyped as follows:
 * void rush(int x, int y);" and "It must take two integer arguments, named x
 * and y." Force-included while each rush0N.c is compiled
 * (tools/prototype_check.sh): a definition of another type is a conflicting-
 * types error, which <p>_prototype reports at basic. The parameter NAMES are
 * the subject's too, and <p>_prototype_names holds the definition to the
 * names below, at strict: no behaviour depends on them, and only an evaluator
 * reading the code can mark them. */
#ifndef PROTOTYPE_C_PISCINE_RUSH_00_EX00_H
# define PROTOTYPE_C_PISCINE_RUSH_00_EX00_H

void	rush(int x, int y);

#endif
