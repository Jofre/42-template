# ex00's tests are Shell 00 ex02's

This exercise asks what Shell 00 ex02 asks, in its own words, and its archive
is exo.tar where Shell 00's is exo2.tar: the check reads that name from this
exercise's call. So it has no tests of its own: its check, its hints
(clues.tsv) and its reading checked at strict are in

    c-piscine/c-piscine-shell-00/tests/ex02/

and they run for both projects, so a fix made there reaches both. The link
is `twin_of` on this exercise's `shell_exercise` call in ../../BUILD.bazel.
Any other file put in this folder fails ex00_twin, since nothing would
read it, and //tools:conventions checks that this README names the folder
that call does.
