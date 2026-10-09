# C 08

What this module needs beyond [the general docs](../../docs/testing.md): the
header ex04 and ex05 compile against, and how ex01's and ex02's headers are
normed.

## ft_stock_str.h: the grader's header, kept in `tests/`

ex04 and ex05 say *"The structure will be defined in the ft_stock_str.h file
that we will provide"*. So it is not yours to write, and not a file you turn
in: `deliverable/ex04/` holds `ft_strs_to_tab.c` and nothing else, and
`deliverable/ex05/` holds `ft_show_tab.c`. The `files` layer reports a copy
you leave there.

The harness keeps its copy at **`tests/ft_stock_str.h`**, written from the
structure the subject prints, since 42 does not hand the file over in the
end: it is this repository's reconstruction, not 42's file. Every layer
compiles ex04 and ex05 with `-I tests`, and so must a compile of yours by
hand. Keep your own test `main.c` **outside** `deliverable/`, since everything
in there is turned in; from a scratch directory, with `REPO` the path to this
repository:

```sh
cc -Wall -Wextra -Werror -I REPO/c-piscine/c-piscine-c-08/tests \
    main.c REPO/c-piscine/c-piscine-c-08/deliverable/ex04/ft_strs_to_tab.c
```

The rule for every file directly under a project's `tests/` is in
[docs/reference.md](../../docs/reference.md#layout).

## ex01 and ex02: norminette with `-R CheckDefine`

Both subjects say *"Norminette must be launched with the -R CheckDefine flag.
Moulinette will use it too."* The `norm` layer does, and its log prints the
command that reproduces its verdict. By hand, with the version pinned for
campus, from the repository root:

```sh
bazel run //tools:norminette -- -R CheckDefine \
    "$PWD/c-piscine/c-piscine-c-08/deliverable/ex01/ft_boolean.h"
```

norminette keeps only the last `-R` it is given, so add no other `-R` after
it.
