# units.awk -- the units of a project, read from the subject() call its
# BUILD.bazel opens with (tools/subject.bzl), outside Bazel.
#
# Usage: awk -f tools/units.awk MODDIR/BUILD.bazel
#        awk -v rows=files -f tools/units.awk MODDIR/BUILD.bazel
#        awk -v rows=goals -f tools/units.awk MODDIR/BUILD.bazel
#
# One row per unit, TAB-separated, in the order the contract writes them:
#
#   NAME    KIND      REQ        FOLDER            JUDGE    LIB
#   ex00    exercise  mandatory  deliverable/ex00  folder   -
#   libtoy  library   mandatory  deliverable       folder   -
#   toy_up  function  -          deliverable       defines  libtoy
#   base    part      mandatory  deliverable       files    -
#   bonus   part      optional   deliverable       goal     -
#
#   NAME    exNN for an entry "NN": exercise(...) of `exercises`; the key
#           itself for an entry "<name>": unit(...) of `units`; a
#           function's own name for a key of a unit's `functions =
#           {...}`, whose rows follow the unit's directly, in the order its
#           dict writes them.
#   KIND    exercise for an entry of `exercises`. For an entry of `units`:
#           library where it has functions, project where it has none (the
#           project's only unit), part where the contract has several units
#           (none of which has functions). function for a function.
#   REQ     mandatory where the contract's `mandatory` names the entry,
#           optional where it names another, and - where the contract has no
#           mandatory list. Always - on a function row.
#   FOLDER  the turn-in folder, as tools/defs.bzl's turnin_dir() computes
#           it: deliverable/exNN for an exercise, deliverable for every unit
#           (a unit turns in at the root). A function row repeats its
#           library's.
#   JUDGE   how the unit is told written from a stub: folder, every file of
#           its folder (stub_check --file); defines, the one body that
#           defines it (stub_check --defines); and for a part, files, the
#           files it lists (its rows=files rows), each of them its own, or
#           goal, the rule of its Makefile that builds it (its rows=goals
#           row; with none, it is the part a bare make builds).
#   LIB     the library a function row belongs to, by its name; - otherwise.
#
# With rows=files it prints instead the strings of each entry's file
# lists, one row each, in the order written: "NAME<TAB>LIST<TAB>STRING",
# LIST being files, optional or provided (for provided, the dict's values:
# where the grader's files go). Only a plain string standing alone in a
# list (dict) literal is read; a value holding anything else -- a name, a
# call joined to a list with +, a string with a backslash or built with +
# or %, a comprehension -- has one row with an empty STRING besides the
# strings it does read: a list read in part says so. None is no row.
#
# With rows=goals it prints "NAME<TAB>GOAL" for each unit whose unit() names
# a goal, in the order written, and nothing for an exercise or a unit with
# none.
#
# Exit 0 when the rows are printed (none for an empty `exercises`); 1, saying
# nothing, when the file holds no line that starts `subject(`; 2, with
# "units.awk: FILE:LINE: ..." on stderr and nothing on stdout, when the call
# holds something this cannot read as written.
#
# WHY ONE READER. The macros read the contract as JSON, inside Bazel. Four
# scripts read it as text, outside it -- tools/first_red.sh on a log,
# tools/fortytwo/workspace.py before Bazel has run, tools/conventions.sh and
# tools/answer_scan.sh over the tree -- and each had its own reading: two
# digits in one, any number in another, a key cut at the first # in a
# third. Each was held to the macros only where a test happened to look.
# This is the one reading now, and //tools/tests:units_parity holds its
# rows byte for byte to each package's :units, which subject() writes from
# the contract the macros read (every module, and every toy package), and
# its rows=files rows to the lists of the package's subject.json.
#
# HOW IT READS. From the first line that starts `subject(` to the ) that
# closes that call, one token at a time, across lines: a string ("..." or
# '...', a backslash escaping the character after it, and the triple-quoted
# forms over several lines), a name, a number, or one character of
# punctuation. A # outside a string starts a comment that runs to the end of
# its line. So a key in a comment is no key, a # or a } inside a string ends
# nothing (dir = "a#b"), and an entry spread over lines reads as one on a
# line.
#
# FAILING CLOSED. Only the arguments it reads are read strictly: subject()'s
# `exercises`, `units` and `mandatory`, each exercise()'s `dir`, and each
# unit()'s `functions`, `goal` (a plain string or None) and `strict` (None
# or not). Where `units` has several, each one's `files` and `optional` are
# read strictly too, because they say how it is told written: a list of
# plain strings written out, files never None.
# Every other value -- a quote, a list built with +, a name bound above --
# is skipped to its closing bracket, unread (rows=files reads three of them,
# as above). What it reads has to be written out the way every project
# writes it: a dict literal of "NN": exercise(...) entries, keyword arguments
# only, dir a plain string, functions a dict literal with a plain
# string per key, mandatory None or a list of plain strings, each an
# exercise, once. Anything else -- a comprehension, a key that is a name, a
# dict merged with |, an escape in a key -- exits 2 naming the line, rather
# than printing a reading that might be wrong: a unit misread is a written
# exercise called "not written yet", or a stub pushed as written. Starlark
# would accept some of those forms; write the entry as the others are.
#
# NAMED UNITS are refused here as tools/subject.bzl refuses them, so that a
# reader with no Bazel running (42) never lists a contract the macros will
# not load: exactly one of `exercises` and `units`; a unit name that is not
# [a-z][a-z0-9_]*, or begins ex and a digit; a name given twice, to a unit
# or a function; a name that, followed by _, begins another (the prefix
# rule: no reader could tell whose a target is); a unit with a dir; a goal
# that is no rule name, or on a unit that lists no Makefile, or on the
# project's only unit. Where there are several units (parts), what
# tools/subject.bzl's _parts() refuses: a part with functions or a strict,
# with files None or no file at all, two parts with one goal, a goal on a
# part whose files are its own, a part that may share its files and lists
# no Makefile, and two such parts with no goal. A
# part's files are its own (JUDGE files) when every name every part lists
# is a plain file name -- no *, no empty or . segment -- and no other part
# lists one of its names; otherwise it may share them (JUDGE goal).
#
# EXERCISES are refused here as subject.bzl refuses them too: an exercise
# turns in at the folder its key names, dir = "exNN/", the subject's
# "Turn-in directory: exNN/" line, so dir = None or another folder is
# refused; and it turns in no library, so `functions` is refused. A subject
# with no such line, or a library, is a contract of units.
#
# One refusal is subject.bzl's alone: a name the
# harness reserves (a level, a layer, a target every module has). That
# list is tools/defs.bzl's, held to its own tables, and a contract that
# takes one of them does not load.
#
# POSIX awk only: the image's awk is mawk 1.3.4, which has no interval
# expressions ({n} in a regex) and no gawk extensions, and the selftest runs
# this under it. Every caller runs it under LC_ALL=C, so a byte is a
# character whatever the awk.

# A token, in four arrays: its kind (s a string, n a name, d a number, p one
# character of punctuation), its text (a string's without its quotes), the
# line it starts on, and whether a string holds a backslash. A string with
# one is never read as a key, a dir or a function: what it means is
# Starlark's to decode, and a reading of it here could part from that.
function tok(kind, text, line, esc) {
	nt++
	tk[nt] = kind
	tv[nt] = text
	tl[nt] = line
	te[nt] = esc
}

function fail(line, msg) {
	printf "units.awk: %s:%d: %s\n", FILENAME, line, msg > "/dev/stderr"
	bad = 1
	exit 2
}

# One line of the call, into tokens. A string open at the end of a line is
# carried to the next only when triple-quoted; any other is an error, as it
# is in Starlark. Stops at the ) that closes the call (depth back at 0).
function scan(s,   i, L, c, j, q3) {
	L = length(s)
	i = 1
	# A triple-quoted string carried over a line break: what it holds is
	# no plain string (its line breaks are not kept here).
	if (instr != "") sesc = 1
	while (i <= L) {
		if (instr != "") {
			# Inside a triple-quoted string carried from an earlier line.
			c = substr(s, i, 1)
			if (c == "\\") {
				sbuf = sbuf c substr(s, i + 1, 1); sesc = 1; i += 2
				continue
			}
			if (substr(s, i, 3) == instr) {
				tok("s", sbuf, sline, sesc)
				instr = ""; i += 3
				continue
			}
			sbuf = sbuf c; i++
			continue
		}
		c = substr(s, i, 1)
		if (c == " " || c == "\t" || c == "\r") { i++; continue }
		if (c == "#") return
		if (c == "\"" || c == "'") {
			q3 = c c c
			if (substr(s, i, 3) == q3) {
				instr = q3; sbuf = ""; sesc = 0; sline = FNR; i += 3
				continue
			}
			sbuf = ""; sesc = 0
			for (j = i + 1; j <= L; j++) {
				if (substr(s, j, 1) == "\\") {
					sbuf = sbuf substr(s, j, 2); sesc = 1; j++
					continue
				}
				if (substr(s, j, 1) == c) break
				sbuf = sbuf substr(s, j, 1)
			}
			if (j > L) fail(FNR, "a string that does not end on its line")
			tok("s", sbuf, FNR, sesc)
			i = j + 1
			continue
		}
		if (c ~ /[A-Za-z_]/) {
			# A name; and r"..." is a raw string, read as a string.
			for (j = i + 1; j <= L && substr(s, j, 1) ~ /[A-Za-z0-9_]/; j++)
				;
			if (j <= L && substr(s, j, 1) ~ /["']/ && substr(s, i, j - i) ~ /^[rRbB]+$/) {
				i = j
				continue
			}
			tok("n", substr(s, i, j - i), FNR, 0)
			i = j
			continue
		}
		if (c ~ /[0-9]/) {
			for (j = i + 1; j <= L && substr(s, j, 1) ~ /[A-Za-z0-9_.]/; j++)
				;
			tok("d", substr(s, i, j - i), FNR, 0)
			i = j
			continue
		}
		tok("p", c, FNR, 0)
		if (c == "(" || c == "[" || c == "{") depth++
		else if (c == ")" || c == "]" || c == "}") {
			depth--
			if (depth == 0) { closed = 1; return }
		}
		i++
	}
}

# The token at the cursor is punctuation C, which is consumed; else fail
# with WHAT, naming the line.
function expect(c, what) {
	if (tk[at] != "p" || tv[at] != c) fail(tl[at], what)
	at++
}

# A value that is not read, skipped to the , or closing bracket that ends
# it at its own depth (neither is consumed). Whatever it holds -- calls,
# lists, quotes, names, + -- is no unit.
function skip(   d) {
	d = 0
	while (at <= nt) {
		if (tk[at] == "p") {
			if (tv[at] == "(" || tv[at] == "[" || tv[at] == "{") d++
			else if (tv[at] == ")" || tv[at] == "]" || tv[at] == "}") {
				if (d == 0) return
				d--
			} else if (tv[at] == "," && d == 0) return
		}
		at++
	}
}


# rows=files: a value whose strings are file names -- files and optional,
# lists; provided, a dict whose VALUES are where the grader puts its files.
# A string is a row only where it stands alone as an element of the list
# literal (a value of the dict literal): after its [ , or :, and before its
# , or closing bracket. Lists joined with + are each read so. Anything else
# in the value -- a name or a call (rush_owed(...), a dict bound to a name
# above), a string with a backslash, or joined to another with + or %, a
# comprehension, a bracket inside the literal, a parenthesis -- is an
# operand not read, and gives the value one row with no STRING, which
# every reader then knows it has not seen. Stops, as skip() does, at the ,
# or bracket that ends the value.
function lits(n, k,   d, open1, lit, odd, part, b, a) {
	d = 0
	open1 = (k == "provided") ? "{" : "["
	if (tk[at] == "n" && tv[at] == "None") { unone[n, k] = 1; at++; return }
	while (at <= nt) {
		odd = 0
		if (tk[at] == "p" && (tv[at] == "(" || tv[at] == "[" || tv[at] == "{")) {
			d++
			if (d == 1) lit = (tv[at] == open1)
			if (!lit || d > 1) odd = 1
		} else if (tk[at] == "p" && (tv[at] == ")" || tv[at] == "]" || tv[at] == "}")) {
			if (d == 0) return
			d--
		} else if (tk[at] == "p" && tv[at] == "," && d == 0) return
		else if (d == 0) {
			# Between two operands, only the + that joins them.
			if (!(tk[at] == "p" && tv[at] == "+")) odd = 1
		} else if (!lit || d > 1) {
			# Inside a bracket that is no literal of the list, or one
			# inside the literal: already said, at its opening bracket.
		} else if (tk[at] == "p" && (tv[at] == "," || (k == "provided" && tv[at] == ":"))) {
			# The literal's own punctuation.
		} else if (tk[at] == "s") {
			b = (tk[at - 1] == "p") ? tv[at - 1] : ""
			a = (tk[at + 1] == "p") ? tv[at + 1] : ""
			if (k == "provided" && (b == "{" || b == ",") && a == ":") {
				# A key: where the harness keeps the file, no row.
			} else if (((k != "provided" && (b == "[" || b == ",")) || \
			    (k == "provided" && b == ":")) && (a == "," || a == (k == "provided" ? "}" : "]")) && !te[at])
			{
				frow(n, k, tv[at])
				nul[n, k]++
				ul[n, k, nul[n, k]] = tv[at]
			} else
				odd = 1
		} else
			odd = 1
		if (odd && !part) {
			part = 1
			uodd[n, k] = 1
			frow(n, k, "")
		}
		at++
	}
}

function frow(n, k, v) {
	nfr++
	frn[nfr] = n
	frk[nfr] = k
	frv[nfr] = v
}

# After a value: a , (consumed) or the closing C (left for the caller).
# Anything else follows the value in an expression: exercises = {...} | X.
function after(c, what) {
	if (tk[at] == "p" && tv[at] == ",") { at++; return }
	if (tk[at] == "p" && tv[at] == c) return
	fail(tl[at], what)
}

# A plain string at the cursor, consumed, for a key, a dir, a function or a
# mandatory entry; else fail with WHAT.
function plain(what,   v) {
	if (tk[at] != "s" || te[at]) fail(tl[at], what)
	v = tv[at]
	at++
	return v
}

# exercise(...): its keyword arguments, `dir` read, `functions` refused, the
# rest skipped. Its folder is kept under N.
function exercise(n, line,   k, f, hasdir) {
	expect("(", "\"" n "\" is not written as exercise(...)")
	hasdir = 0
	while (!(tk[at] == "p" && tv[at] == ")")) {
		if (tk[at] != "n" || !(tk[at + 1] == "p" && tv[at + 1] == "="))
			fail(tl[at], "exercise \"" n "\" has an argument that is not name = value")
		k = tv[at]
		at += 2
		if (k == "dir") {
			if (tk[at] == "n" && tv[at] == "None")
				fail(tl[at], "exercise \"" n "\" has dir = None: an exercise turns in at ex" n "/, the folder its subject's \"Turn-in directory\" line names; a subject with no such line turns in at the root of deliverable/, which is a unit (units = {...})")
			f = plain("exercise \"" n "\"'s dir is not a plain string")
			if (f != "ex" n "/")
				fail(tl[at - 1], "exercise \"" n "\" turns in at \"" f "\": an exercise turns in at ex" n "/, the folder its key names (\"Turn-in directory: ex" n "/\")")
			sub(/\/+$/, "", f)
			folder[n] = "deliverable/" f
			hasdir = 1
		} else if (k == "functions")
			fail(tl[at], "exercise \"" n "\" has functions = {...}: an exercise turns in no library; a library is a unit, units = {\"<library>\": unit(..., functions = {...})}")
		else if (rows == "files" && (k == "files" || k == "optional" || k == "provided"))
			lits(n, k)
		else
			skip()
		after(")", "exercise \"" n "\"'s " k " is not one value")
	}
	at++
	if (!hasdir) fail(line, "exercise \"" n "\" has no dir = ...")
}

# functions = {"name": [...], ...}: the keys, in order; the values skipped.
# WHO names the unit in a message: unit "libtoy". A unit's functions are
# units of their own, so each name is held to the rules of a unit name
# (named()).
function functions(n, who,   f) {
	expect("{", who "'s functions is not a {...} written out")
	while (!(tk[at] == "p" && tv[at] == "}")) {
		f = plain(who "'s functions has a key that is not a plain string")
		if ((n SUBSEP f) in hasfn) fail(tl[at - 1], who " lists " f " twice")
		named(f, tl[at - 1], who "'s function \"" f "\"", "a function of " who)
		hasfn[n, f] = 1
		nfn[n]++
		fn[n, nfn[n]] = f
		expect(":", who "'s functions has a key with no value")
		skip()
		after("}", who "'s function " f " is not one value")
	}
	at++
}

# A name of a unit or a function, read at LINE, as WHAT ("units has the key
# \"x\"", or unit "x"'s function "f"), to be AS (the unit "x", a function of
# unit "x"): the grammar every reader types it in, never an exercise's
# shape, never a name already taken. Kept, in order, for the prefix rule.
function named(f, line, what, as) {
	if (f !~ /^[a-z][a-z0-9_]*$/)
		fail(line, what " is not a unit name: a lowercase letter, then lowercase letters, digits or _")
	if (f ~ /^ex[0-9]/)
		fail(line, what " is shaped like an exercise's name: ex and a digit begin only an exercise's")
	if (f in nameas)
		fail(line, "\"" f "\" names both " nameas[f] " and " as ": each unit and each function has a name of its own")
	nameas[f] = as
	nnames++
	names[nnames] = f
	nline[f] = line
}

# exercises = {"NN": exercise(...), ...}, in order.
function exercises(   n, line) {
	expect("{", "exercises is not a {...} written out")
	while (!(tk[at] == "p" && tv[at] == "}")) {
		line = tl[at]
		n = plain("exercises has a key that is not a plain string")
		if (n !~ /^[0-9][0-9]$/) fail(line, "exercises has the key \"" n "\", not a two-digit number")
		if (n in folder) fail(line, "exercises has the key \"" n "\" twice")
		expect(":", "exercises has a key with no value")
		if (tk[at] != "n" || tv[at] != "exercise") fail(tl[at], "\"" n "\" is not written as exercise(...)")
		at++
		exercise(n, line)
		nex++
		ex[nex] = n
		after("}", "exercise \"" n "\" is not one value")
	}
	at++
}

# unit(...): its keyword arguments, `functions` and `goal` read, the rest
# skipped. A unit turns in at the root of deliverable/, so a dir is refused,
# whatever its value.
function unit(n, line,   k, who) {
	who = "unit \"" n "\""
	expect("(", "\"" n "\" is not written as unit(...)")
	while (!(tk[at] == "p" && tv[at] == ")")) {
		if (tk[at] != "n" || !(tk[at + 1] == "p" && tv[at + 1] == "="))
			fail(tl[at], who " has an argument that is not name = value")
		k = tv[at]
		at += 2
		if (k == "dir")
			fail(tl[at - 2], who " has a dir = ...: a unit turns in at the root of deliverable/, and takes none")
		else if (k == "goal") {
			# None is no goal; a goal is a rule name, a plain string.
			if (tk[at] == "n" && tv[at] == "None") at++
			else {
				goalline[n] = tl[at - 2]
				goal[n] = plain(who "'s goal is neither a plain string nor None")
				if (goal[n] !~ /^[A-Za-z0-9_][A-Za-z0-9_.-]*$/)
					fail(goalline[n], who "'s goal \"" goal[n] "\" is no Makefile rule name, like \"bonus\"")
			}
		} else if (k == "strict") {
			if (tk[at] == "n" && tv[at] == "None") at++
			else { strictline[n] = tl[at - 2]; skip() }
		} else if (k == "functions")
			functions(n, who)
		else if (k == "files" || k == "optional" || (rows == "files" && k == "provided")) {
			if (k == "files") hasfiles[n] = 1
			lits(n, k)
		} else
			skip()
		after(")", who "'s " k " is not one value")
	}
	at++
}

# units = {"<name>": unit(...), ...}, in order. Several are parts (parts()).
function units(   n, line) {
	expect("{", "units is not a {...} written out")
	while (!(tk[at] == "p" && tv[at] == "}")) {
		line = tl[at]
		n = plain("units has a key that is not a plain string")
		if (n in folder) fail(line, "units has the key \"" n "\" twice")
		named(n, line, "units has the key \"" n "\", which", "the unit \"" n "\"")
		unitline[n] = line
		expect(":", "units has a key with no value")
		if (tk[at] != "n" || tv[at] != "unit") fail(tl[at], "\"" n "\" is not written as unit(...)")
		at++
		unit(n, line)
		folder[n] = "deliverable"
		nex++
		ex[nex] = n
		after("}", "unit \"" n "\" is not one value")
	}
	at++
}

# Whether unit N lists the name F in its files or optional, as written.
function lists(n, f,   k, i) {
	for (k = 1; k <= 2; k++)
		for (i = 1; i <= nul[n, lk[k]]; i++)
			if (ul[n, lk[k], i] == f) return 1
	return 0
}

# A plain file name: no *, no empty or . segment (subject.bzl's
# _is_plain_name). Only plain names can show two parts list different files.
function plainname(f) {
	return index(f, "*") == 0 && f !~ /(^|\/)\.?(\/|$)/
}

# Whether part N may share a file with another part: one of its names is
# no plain name, or another part's is, or another part lists one of its.
function shares(n,   i, j, k, o, y) {
	for (k = 1; k <= 2; k++)
		for (i = 1; i <= nul[n, lk[k]]; i++)
			if (!plainname(ul[n, lk[k], i])) return 1
	for (j = 1; j <= nex; j++) {
		o = ex[j]
		if (o == n) continue
		for (k = 1; k <= 2; k++)
			for (i = 1; i <= nul[o, lk[k]]; i++) {
				y = ul[o, lk[k], i]
				if (!plainname(y) || lists(n, y)) return 1
			}
	}
	return 0
}

# Several units: each a part, its JUDGE derived (files or goal), as
# subject.bzl's _parts() derives it, and refused where it refuses.
function parts(   i, n, k, bare, goalof) {
	lk[1] = "files"
	lk[2] = "optional"
	for (i = 1; i <= nex; i++) {
		n = ex[i]
		if (nfn[n]) fail(unitline[n], "unit \"" n "\" has functions, and the project has other units: a library is a project's only unit")
		if (n in strictline) fail(strictline[n], "unit \"" n "\" has a strict = ...: a file no part lists is judged once for the whole root, under subject()'s strict")
		if (!hasfiles[n] || ((n, "files") in unone)) fail(unitline[n], "unit \"" n "\" has no files: each of several parts lists its files")
		for (k = 1; k <= 2; k++)
			if ((n, lk[k]) in uodd) fail(unitline[n], "unit \"" n "\"'s " lk[k] " is not a list of plain strings written out: with several units, it says how the part is told written")
		if (!nul[n, "files"] && !nul[n, "optional"]) fail(unitline[n], "unit \"" n "\" lists no file, and it is one of several parts")
		if (n in goal) {
			if (!lists(n, "Makefile")) fail(goalline[n], "unit \"" n "\" has a goal, and lists no Makefile")
			if (goal[n] in goalof) fail(goalline[n], "units \"" goalof[goal[n]] "\" and \"" n "\" both have goal = \"" goal[n] "\"")
			goalof[goal[n]] = n
		}
	}
	for (i = 1; i <= nex; i++) {
		n = ex[i]
		if (!shares(n)) {
			if (n in goal) fail(goalline[n], "unit \"" n "\" has a goal, and its files are its own: a goal names the rule that builds a part sharing its files with another, and a part whose files are its own is told written by them")
			judge[n] = "files"
			continue
		}
		judge[n] = "goal"
		if (!lists(n, "Makefile")) fail(unitline[n], "unit \"" n "\" may share its files with another part, and lists no Makefile, whose rule would say it is written")
		if (!(n in goal)) {
			if (bare != "") fail(unitline[n], "units \"" bare "\" and \"" n "\" may share their files, and neither has a goal: a bare make builds one part")
			bare = n
		}
	}
}

# mandatory = None, or ["NN", ...].
function mandatory(   n, cnt) {
	if (tk[at] == "n" && tv[at] == "None") { at++; return }
	expect("[", "mandatory is neither a [...] written out nor None")
	hasmand = 1
	while (!(tk[at] == "p" && tv[at] == "]")) {
		n = plain("mandatory has an entry that is not a plain string")
		if (n in mand) fail(tl[at - 1], "mandatory names \"" n "\" twice")
		mline[n] = tl[at - 1]
		mand[n] = 1
		cnt++
		after("]", "mandatory's entry \"" n "\" is not one value")
	}
	# Starlark refuses an empty list too: name the mandatory part, or None.
	if (!cnt) fail(tl[at], "mandatory = [] names no exercise: name the subject's mandatory part, or leave it out")
	at++
}

# rows= names what is printed; any other word would print unit rows to a
# reader expecting file rows.
BEGIN {
	if (rows != "" && rows != "files" && rows != "goals") {
		printf "units.awk: rows=%s: the rows it prints are units (no rows=), files (rows=files) or goals (rows=goals)\n", rows > "/dev/stderr"
		bad = 1
		exit 2
	}
}

!started && /^subject\(/ {
	started = 1
	depth = 0
	scan($0)
	next
}
started && !closed {
	scan($0)
	next
}
# A second call is a second contract: no reader can say which one the
# macros read (Starlark refuses it, `subject` declared twice).
closed && /^subject\(/ { fail(FNR, "a second subject( call") }

END {
	if (bad) exit 2
	if (!started) exit 1
	if (instr != "") fail(sline, "a triple-quoted string that never ends")
	if (!closed) fail(FNR, "the subject( call never closes")
	# subject ( keyword arguments... )
	at = 3
	while (!(tk[at] == "p" && tv[at] == ")")) {
		if (tk[at] != "n" || !(tk[at + 1] == "p" && tv[at + 1] == "="))
			fail(tl[at], "subject() has an argument that is not name = value")
		k = tv[at]
		if (k in given) fail(tl[at], "subject() is given " k " twice")
		if ((k == "exercises" && ("units" in given)) || (k == "units" && ("exercises" in given)))
			fail(tl[at], "subject() has both exercises = {...} and units = {...}: a project is divided one way")
		given[k] = 1
		at += 2
		if (k == "exercises") exercises()
		else if (k == "units") { isunits = 1; units() }
		else if (k == "mandatory") mandatory()
		else skip()
		after(")", "subject()'s " k " is not one value")
	}
	if (!("exercises" in given) && !("units" in given))
		fail(tl[1], "subject() has neither exercises = {...} nor units = {...}")
	if (isunits) {
		# The prefix rule, over every name in the order written: the
		# later of the two is the line named.
		for (i = 1; i <= nnames; i++)
			for (j = 1; j <= nnames; j++)
				if (i != j && index(names[j], names[i] "_") == 1)
					fail(nline[names[i < j ? j : i]], "\"" names[i] "\" followed by _ begins \"" names[j] "\": no reader could tell whose a target named " names[j] "_... is")
		if (nex == 1) {
			for (n in goalline)
				fail(goalline[n], "unit \"" n "\" has a goal: a goal is the Makefile rule that builds one part of several, and \"" n "\" is the project's only unit")
		} else if (nex > 1)
			parts()
	}
	for (n in mand)
		if (!(n in folder)) {
			if (isunits && (n in nameas))
				fail(mline[n], "mandatory names \"" n "\", " nameas[n] ": it names the library, whose functions are judged with it")
			fail(mline[n], "mandatory names \"" n "\", which is no " (isunits ? "unit" : "exercise") " of this contract")
		}
	pre = isunits ? "" : "ex"
	if (rows == "goals") {
		for (i = 1; i <= nex; i++)
			if (ex[i] in goal) printf "%s\t%s\n", ex[i], goal[ex[i]]
		exit 0
	}
	if (rows == "files") {
		for (i = 1; i <= nfr; i++)
			printf "%s%s\t%s\t%s\n", pre, frn[i], frk[i], frv[i]
		exit 0
	}
	for (i = 1; i <= nex; i++) {
		n = ex[i]
		printf "%s%s\t%s\t%s\t%s\t%s\t-\n", pre, n, (!isunits ? "exercise" : (nex > 1 ? "part" : (nfn[n] ? "library" : "project"))), (!hasmand ? "-" : ((n in mand) ? "mandatory" : "optional")), folder[n], ((n in judge) ? judge[n] : "folder")
		for (j = 1; j <= nfn[n]; j++)
			printf "%s\tfunction\t-\t%s\tdefines\t%s%s\n", fn[n, j], folder[n], pre, n
	}
	exit 0
}
