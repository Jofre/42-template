# ex03's tests are Shell 01 ex02's

This exercise asks what Shell 01 ex02 asks, in its own words. So it
has no tests of its own: its check, its hints (clues.tsv) and any reading
checked at strict are in

    c-piscine/c-piscine-shell-01/tests/ex02/

and they run for both projects, so a fix made there reaches both. The link
is `twin_of` on this exercise's `shell_exercise` call in ../../BUILD.bazel.
Any other file put in this folder fails ex03_twin, since nothing would
read it, and //tools:conventions checks that this README names the folder
that call does.
