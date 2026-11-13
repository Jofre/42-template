# make_db.awk -- the readers of make's database (make -p), shared by
# tools/make_test.sh (goal_state) and tools/student_build.sh (Makefile mode),
# which ask make the same question the same way: whether the Makefile has a
# rule G. Each caller keeps its own policy (how make is run, the staging, what
# a refused or untrusted reading becomes); this file only reads. Found beside
# the caller, and staged with it: tools/defs_test.bzl's _test() for a test
# whose runner is make_test.sh, tools/student_build.bzl for the builder.
#
# Usage: READING=... ANCHOR=... PROBE=... awk -v part=read -f make_db.awk DB
#        ERR=FILE awk -v part=remake -v q="'" -f make_db.awk DB.read
#        GOAL=FILE awk -v part=goal -v t=G -f make_db.awk DB.read
#
# part=read   the last database of DB, from the line that names the run's
#             pattern rule (ANCHOR, a prefix) to the line make prints after
#             the files, block by block as make lays it out (see the callers'
#             comment on the reading). READING is the line each reading
#             starts with, PROBE the line make prints before the variable the
#             caller's last makefile sets. Prints the blocks; exit 0 when the
#             last database was read to its end, 1 when it was not, 3 when one
#             strays from make's layout (the caller says why and stops).
# part=remake exit 0 when a makefile ERR names in "Failed to remake makefile
#             'X'." is marked as failed to be updated in the last database of
#             DB.read; 1 otherwise.
# part=goal   G's state in DB.read: exit 0 a rule (a prerequisite or a
#             recipe), 1 none, 3 a name with neither. Writes to GOAL the
#             lines that name G and say where its recipes are (/dev/null when
#             the caller does not need them).
#
# Any other part, exit 2. The inputs come through the environment, so that
# awk reads no backslash escape in them.

BEGIN {
	if (part == "remake") {
		while ((getline l < ENVIRON["ERR"]) > 0) {
			i = index(l, "Failed to remake makefile " q)
			if (i && substr(l, length(l) - 1) == q ".") {
				x = substr(l, i + 27)
				want[substr(x, 1, length(x) - 2)] = 1
			}
		}
	} else if (part == "goal") {
		printf "" > ENVIRON["GOAL"]
	} else if (part != "read") {
		printf "make_db.awk: -v part= is read, remake or goal, not '%s'\n", part > "/dev/stderr"
		bad_part = 1
		exit 2
	}
}

# PART READ
function odd(x,   k) {
	k = 0
	while (k < length(x) && substr(x, length(x) - k, 1) == "\\") k++
	return k % 2
}
function bad() { st = 0; rej = 1 }
part == "read" { L[++n] = $0 }

# PART REMAKE
part == "remake" && /^# Make data base, printed on/ { db++; files = 0; next }
part == "remake" && $0 == "# Files" { files = 1; cur = ""; named = 0; next }
part == "remake" && !files { next }
part == "remake" && /^$/ { cur = ""; named = 0; next }
part == "remake" && /^#  Failed to be updated\.$/ { if (cur != "") unmade[cur] = db; next }
part == "remake" && (/^#/ || named) { next }
part == "remake" { named = 1; for (x in want) if (index($0, x ":") == 1) cur = x }

# PART GOAL
part == "goal" && /^# Make data base, printed on/ { files = 0; found = 0; prereq = 0; recipe = 0; next }
part == "goal" && $0 == "# Files" { files = 1; next }
part == "goal" && !files { next }
part == "goal" && /^$/ { top = 1; nt = 0; cur = 0; next }
part == "goal" && top && $0 == "# Not a target:" { nt = 1; next }
part == "goal" && top {
	top = 0
	if (index($0, t ":") == 1 && !nt) {
		rest = substr($0, length(t) + 2)
		sub(/^:/, "", rest)
		cur = 1; found = 1
		if (rest !~ /^[ \t]*$/) prereq = 1
		print > ENVIRON["GOAL"]
	}
	next
}
part == "goal" && cur && /^#  recipe to execute/ { recipe = 1; print > ENVIRON["GOAL"] }

END {
	if (bad_part) exit 2
	if (part == "read") {
	# st 0 outside the rules, 1 the implicit rules from the anchor on,
	# 2 the files; bs where a block is: 0 before its blank line, 1
	# before its name, 2 after it, 3 in its recipe, whose prefix is P.
		for (i = 1; i <= n && !rej; i++) {
			x = L[i]
			if (st == 0) {
				if (x == ENVIRON["READING"]) {
					got = 0; hs = 0; R = 0
				} else if (x ~ /^# Make data base, printed on/) {
					hdr = x
				} else if (x == "HARNESS_READ_TO_THE_END := yes" && L[i - 1] == ENVIRON["PROBE"]) {
					hs = 1
				} else if (index(x, ENVIRON["ANCHOR"]) == 1) {
					st = 1; bs = 2; h0 = hs; hs = 0; P = "\t"; got = 0
					nb = 0; B[++nb] = hdr; split("", seen); last = ""
				}
				continue
			}
			if (bs == 3) {
				# A line that ends in an odd number of backslashes goes
				# on in the next, whatever that holds.
				if (cont) {
					if (x == "" && L[i + 1] != "" && substr(L[i + 1], 1, 1) != P) { bad(); continue }
					cont = odd(x); continue
				}
				if (x != "" && substr(x, 1, 1) == P) { cont = odd(x); continue }
				if (x != "") { bad(); continue }
				if (st == 1) bs = 0; else { B[++nb] = x; bs = 1; fl = 0 }
				continue
			}
			if (st == 1) {
				if (bs == 2) {
					if (x == "") bs = 0
					else if (index(x, "#  recipe to execute") == 1) { bs = 3; cont = 0 }
					else bad()
				} else if (x == "# Files") {
					st = 2; bs = 0; B[++nb] = x
				} else if (x != "" && x !~ /^# [0-9]+ implicit rules, /) {
					if (x ~ /^#/) bad(); else bs = 2
				}
				continue
			}
			if (bs == 0) { if (x == "") { B[++nb] = x; bs = 1; fl = 0 } else bad(); continue }
			if (bs == 2) {
				if (x == "") { if (nc) { B[++nb] = x; bs = 1; fl = 0 } else bad() }
				else if (index(x, "#  recipe to execute") == 1) { B[++nb] = x; bs = 3; cont = 0 }
				else if (substr(x, 1, 1) == "#") { B[++nb] = x; nc++ }
				else bad()
				continue
			}
			if (x == "# files hash-table stats:") {
				if (!h0) { bad(); continue }
				got = 1; R = nb; for (j = 1; j <= nb; j++) G[j] = B[j]
				st = 0; continue
			}
			if (!fl++ && x ~ /^\.RECIPEPREFIX = .?$/) { P = (length(x) == 16) ? "\t" : substr(x, 17, 1); continue }
			if (x == "# Not a target:") { B[++nb] = x; continue }
			# The variables of a target, each after the line that says
			# where it was set, up to the line of the target itself.
			if (substr(x, 1, 2) == "# " && (k = index(L[i + 1], ": "))) {
				t = substr(L[i + 1], 1, k - 1)
				for (j = i + 2; j <= n; j++) {
					y = L[j]
					if (index(y, t ":") == 1 && substr(y, k + 1) !~ /^ (define [^ ]|[^ ]+ [:+]?= )/) break
				}
				if (j > n) { bad(); continue }
				i = (L[j - 1] == "# Not a target:") ? j - 2 : j - 1
				continue
			}
			# A name: one block a file, or several in a row for a :: one.
			if (x == "" || substr(x, 1, 1) == "#" || !(k = index(x, ":"))) { bad(); continue }
			t = substr(x, 1, k - 1); dc = (substr(x, k + 1, 1) == ":")
			if ((t in seen) && !(seen[t] && dc && last == t)) { bad(); continue }
			seen[t] = dc; last = t
			B[++nb] = x; bs = 2; nc = 0
		}
		if (rej) exit 3
		for (j = 1; j <= R; j++) print G[j]
		exit !got
	} else if (part == "remake") {
		for (x in want) if ((x in unmade) && unmade[x] == db) exit 0; exit 1
	} else {
		if (!found) exit 1; exit ((prereq || recipe) ? 0 : 3)
	}
}
