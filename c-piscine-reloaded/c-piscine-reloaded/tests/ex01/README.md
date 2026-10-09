# ex01's tests are Shell 00 ex00's

This exercise asks what Shell 00 ex00 asks, in its own words. So it
has no tests of its own: the output it is compared with (expected.txt)
and its hints (clues.tsv) are in

    c-piscine/c-piscine-shell-00/tests/ex00/

and they run for both projects, so a fix made there reaches both. The link
is `twin_of` on this exercise's `shell_exercise` call in ../../BUILD.bazel.
Any other file put in this folder fails ex01_twin, since nothing would
read it, and //tools:conventions checks that this README names the folder
that call does.
