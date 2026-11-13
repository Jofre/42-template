# ------------------------------------------------------------------ units.awk
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# tools/units.awk is the one reader of a subject() contract's text outside
# Bazel. Each refusal is exit 2 with its FILE:LINE and no row; each readable
# shape gives its exact rows.
mkdir -p "$WORK/ua"
# Absolute, before the cd into $WORK/ua that lets each fixture be named as
# units.awk names it back (FILE is its argument, verbatim).
UA_TOOLS=$(cd "$TOOLS" && pwd)
# ua_fix NAME LINE... -- the fixture $WORK/ua/NAME.bzl, one argument a line.
ua_fix() { _uaf=$1; shift; printf '%s\n' "$@" > "$WORK/ua/$_uaf.bzl"; }
UA1='subject('
UA2='    grader = "moulinette",'
UA3='    group = False,'
UA0='        "00": exercise(page = 1, dir = "ex00/", files = [], allowed = None),'
# What it refuses.
ua_fix unterminated "$UA1" "$UA2" '    group = "x,' ')'
ua_fix triple "$UA1" "$UA2" '    mandatory_quote = """never' 'ends' ')'
ua_fix noclose "$UA1" "$UA2" "$UA3" '    exercises = {' "$UA0" '    },'
ua_fix second "$UA1" "$UA2" "$UA3" '    exercises = {' "$UA0" '    },' ')' 'subject(' ')'
ua_fix positional "$UA1" '    "moulinette",' "$UA3" '    exercises = {},' ')'
ua_fix kwargs "$UA1" "$UA2" "$UA3" '    exercises = {' '        "00": exercise(dir = "ex00/", **TOY),' '    },' ')'
ua_fix merged "$UA1" "$UA2" "$UA3" '    exercises = {' "$UA0" '    } | MORE,' ')'
ua_fix onedigit "$UA1" "$UA2" "$UA3" '    exercises = {' '        "1": exercise(page = 1, dir = "ex01/", files = [], allowed = None),' '    },' ')'
ua_fix notnum "$UA1" "$UA2" "$UA3" '    exercises = {' '        "0a": exercise(page = 1, dir = "ex0a/", files = [], allowed = None),' '    },' ')'
ua_fix namekey "$UA1" "$UA2" "$UA3" '    exercises = {' '        N: exercise(page = 1, dir = "ex00/", files = [], allowed = None),' '    },' ')'
ua_fix esckey "$UA1" "$UA2" "$UA3" '    exercises = {' '        "0\x30": exercise(page = 1, dir = "ex00/", files = [], allowed = None),' '    },' ')'
ua_fix comprehension "$UA1" "$UA2" "$UA3" '    exercises = {n: exercise(page = 1, dir = "ex%s/" % n, files = [], allowed = None) for n in ["00"]},' ')'
ua_fix dupkey "$UA1" "$UA2" "$UA3" '    exercises = {' "$UA0" "$UA0" '    },' ')'
ua_fix other "$UA1" "$UA2" "$UA3" '    exercises = {' '        "00": other(page = 1, dir = "ex00/"),' '    },' ')'
ua_fix nodir "$UA1" "$UA2" "$UA3" '    exercises = {' '        "00": exercise(page = 1, files = [], allowed = None),' '    },' ')'
ua_fix dirname "$UA1" "$UA2" "$UA3" '    exercises = {' '        "00": exercise(page = 1, dir = D, files = [], allowed = None),' '    },' ')'
ua_fix exnone "$UA1" "$UA2" "$UA3" '    exercises = {' '        "00": exercise(page = 1, dir = None, files = [], allowed = None),' '    },' ')'
ua_fix notkey "$UA1" "$UA2" "$UA3" '    exercises = {' '        "03": exercise(page = 1, dir = "ex04/", files = [], allowed = None),' '    },' ')'
ua_fix slashes "$UA1" "$UA2" "$UA3" '    exercises = {' '        "00": exercise(page = 1, dir = "ex00//", files = [], allowed = None),' '    },' ')'
ua_fix hashdir "$UA1" "$UA2" "$UA3" '    exercises = {' '        "00": exercise(page = 1, dir = "a#b/", files = [], allowed = None),  # "01": exercise(' '    },' ')'
ua_fix exfn "$UA1" "$UA2" "$UA3" '    exercises = {' '        "00": exercise(page = 1, dir = "ex00/", files = [], allowed = None,' \
	'            functions = {"toy_a": []}),' '    },' ')'
ua_fix exfnnone "$UA1" "$UA2" "$UA3" '    exercises = {' '        "00": exercise(page = 1, dir = "ex00/", files = [], allowed = None,' \
	'            functions = None),' '    },' ')'
ua_fix fnname "$UA1" "$UA2" "$UA3" '    units = {' '        "libtoy": unit(page = 1, files = [], allowed = None, functions = F),' '    },' ')'
ua_fix dupfn "$UA1" "$UA2" "$UA3" '    units = {' '        "libtoy": unit(page = 1, files = [], allowed = None, functions = {' '            "toy_a": [],' '            "toy_a": [],' '        }),' '    },' ')'
ua_fix mandname "$UA1" "$UA2" "$UA3" '    exercises = {' "$UA0" '    },' '    mandatory = M,' ')'
ua_fix mandmissing "$UA1" "$UA2" "$UA3" '    exercises = {' "$UA0" '    },' '    mandatory = ["07"],' ')'
ua_fix mandempty "$UA1" "$UA2" "$UA3" '    exercises = {' "$UA0" '    },' '    mandatory = [],' ')'
ua_fix noexercises "$UA1" "$UA2" "$UA3" ')'
ua_fix dupkwarg "$UA1" "$UA2" "$UA2" '    exercises = {},' ')'
# What it reads.
ua_fix hashkey "$UA1" "$UA2" "$UA3" '    exercises = {' '        "00": exercise(page = 1, dir = "ex00/", files = ["a#b.c"], allowed = None),  # "01": exercise(' '    },' ')'
ua_fix bracefn "$UA1" "$UA2" "$UA3" '    units = {' '        "libtoy": unit(page = 1, files = [], allowed = None, functions = {"toy_a": ["x}y"], "toy_b": []}),' '    },' ')'
ua_fix tripleok "$UA1" '    grader = """moulinette,' '    still the string""",' "$UA3" '    exercises = {' "$UA0" '    },' ')'
ua_fix single "$UA1" "$UA2" "$UA3" '    exercises = {' "        '00': exercise(page = 1, dir = 'ex00/', files = [], allowed = None)," '    },' ')'
ua_fix raw "$UA1" "$UA2" "$UA3" '    exercises = {' '        "00": exercise(page = 1, dir = r"ex00/", files = [], allowed = None),' '    },' ')'
ua_fix mandfirst "$UA1" "$UA2" "$UA3" '    mandatory = ["01"],' '    exercises = {' "$UA0" '        "01": exercise(page = 2, dir = "ex01/", files = [], allowed = None),' '    },' ')'
ua_fix empty "$UA1" "$UA2" "$UA3" '    exercises = {},' ')'
ua_fix oneline 'subject(grader = "defense", group = True, exercises = {})'
ua_fix nosubject 'x(' '    name = "subject(",' ')'
ua_fix files "$UA1" '    exercises = {' '        "00": exercise(dir = "ex00/", files = ["a.c", "b\\c.c"] + EXTRA, optional = None, provided = {"x.c": "srcs/x.c"}),' '    },' ')'
# Named units: subject(units = {"<name>": unit(...)}).
UN1='        "tally": unit(page = 1, files = ["Makefile"], allowed = None),'
UNL='        "libtoy": unit(page = 1, files = ["Makefile"], allowed = [], functions = {'
ua_fix nboth "$UA1" "$UA2" "$UA3" '    exercises = {' "$UA0" '    },' '    units = {' "$UN1" '    },' ')'
ua_fix ndir "$UA1" "$UA2" "$UA3" '    units = {' '        "tally": unit(page = 1, dir = None, files = [], allowed = None),' '    },' ')'
ua_fix nupper "$UA1" "$UA2" "$UA3" '    units = {' '        "Tally": unit(page = 1, files = [], allowed = None),' '    },' ')'
ua_fix nex "$UA1" "$UA2" "$UA3" '    units = {' '        "ex1_tally": unit(page = 1, files = [], allowed = None),' '    },' ')'
ua_fix ndupkey "$UA1" "$UA2" "$UA3" '    units = {' "$UN1" "$UN1" '    },' ')'
ua_fix nsecond "$UA1" "$UA2" "$UA3" '    units = {' "$UN1" '        "bonus": unit(page = 2, files = ["Makefile"], allowed = None),' '    },' ')'
ua_fix nother "$UA1" "$UA2" "$UA3" '    units = {' '        "tally": exercise(page = 1, dir = "ex00/", files = [], allowed = None),' '    },' ')'
ua_fix nkwargs "$UA1" "$UA2" "$UA3" '    units = {' '        "tally": unit(page = 1, **TOY),' '    },' ')'
ua_fix ngoal "$UA1" "$UA2" "$UA3" '    units = {' '        "tally": unit(page = 1, files = ["Makefile"], allowed = None,' '            goal = "bonus", goal_quote = "Toy, p.1: \"make bonus\""),' '    },' ')'
ua_fix nfnname "$UA1" "$UA2" "$UA3" '    units = {' "$UNL" '            "Toy_len": [],' '        }),' '    },' ')'
ua_fix nfnsame "$UA1" "$UA2" "$UA3" '    units = {' "$UNL" '            "toy_len": [],' '            "libtoy": [],' '        }),' '    },' ')'
ua_fix nprefix "$UA1" "$UA2" "$UA3" '    units = {' "$UNL" '            "toy_len_max": [],' '            "toy_up": [],' '            "toy_len": [],' '        }),' '    },' ')'
ua_fix nprefixlib "$UA1" "$UA2" "$UA3" '    units = {' '        "toy": unit(page = 1, files = [], allowed = [], functions = {' '            "toy_up": [],' '        }),' '    },' ')'
ua_fix nmandfn "$UA1" "$UA2" "$UA3" '    units = {' "$UNL" '            "toy_len": [],' '        }),' '    },' '    mandatory = ["toy_len"],' ')'
ua_fix nmandmissing "$UA1" "$UA2" "$UA3" '    units = {' "$UN1" '    },' '    mandatory = ["bonus"],' ')'
ua_fix nlib "$UA1" "$UA2" "$UA3" '    units = {' "$UNL" '            "toy_up": [],' '            "toy_len": [],' '        }),' '    },' '    mandatory = ["libtoy"],' ')'
ua_fix nprog "$UA1" "$UA2" "$UA3" '    units = {' '        "tally": unit(page = 1, files = ["Makefile"], allowed = None, goal = None),' '    },' ')'
ua_fix nfiles "$UA1" '    units = {' '        "tally": unit(files = ["Makefile"], optional = ["**/*.c"], provided = {"tests/x.h": "x.h"}),' '    },' ')'
# Several units at the root: parts.
UPB='        "base": unit(page = 1, files = ["toy_read.c", "toy_read.h"], allowed = ["read"]),'
UPN='        "bonus": unit(page = 2, files = ["toy_read_bonus.c", "toy_read_bonus.h"], allowed = ["read"]),'
UPS='        "sorter": unit(page = 1, files = ["Makefile"], optional = ["**/*.c", "**/*.h"], allowed = ["write"]),'
UPC='        "checker": unit(page = 2, files = ["Makefile"], optional = ["**/*.c", "**/*.h"], allowed = ["write"], goal = "bonus", goal_quote = Q),'
UPM='    mandatory = ["base"],'
ua_fix pfiles "$UA1" "$UA2" "$UA3" '    units = {' "$UPB" "$UPN" '    },' "$UPM" ')'
ua_fix pprog "$UA1" "$UA2" "$UA3" '    units = {' "$UPS" "$UPC" '    },' '    mandatory = ["sorter"],' ')'
ua_fix psame "$UA1" "$UA2" "$UA3" '    units = {' \
	'        "base": unit(page = 1, files = ["Makefile", "toy_fmt.c", "toy_fmt.h"], allowed = ["write"]),' \
	'        "bonus": unit(page = 2, files = ["Makefile", "toy_fmt.c", "toy_fmt.h"], allowed = ["write"],' \
	'            goal = "bonus", goal_quote = Q),' '    },' "$UPM" ')'
ua_fix plib "$UA1" "$UA2" "$UA3" '    units = {' "$UNL" '            "toy_len": [],' '        }),' "$UN1" '    },' ')'
ua_fix pstrict "$UA1" "$UA2" "$UA3" '    units = {' "$UPB" '        "bonus": unit(page = 2, files = ["b.c"], allowed = [], strict = False),' '    },' ')'
ua_fix pnofiles "$UA1" "$UA2" "$UA3" '    units = {' "$UPB" '        "bonus": unit(page = 2, files = None, allowed = []),' '    },' ')'
ua_fix pnofile "$UA1" "$UA2" "$UA3" '    units = {' "$UPB" '        "bonus": unit(page = 2, files = [], allowed = []),' '    },' ')'
ua_fix pfname "$UA1" "$UA2" "$UA3" '    units = {' "$UPB" '        "bonus": unit(page = 2, files = BONUS, allowed = []),' '    },' ')'
ua_fix pgoalname "$UA1" "$UA2" "$UA3" '    units = {' "$UPS" '        "checker": unit(page = 2, files = ["Makefile"], allowed = [], goal = G, goal_quote = Q),' '    },' ')'
ua_fix pgoalshape "$UA1" "$UA2" "$UA3" '    units = {' "$UPS" '        "checker": unit(page = 2, files = ["Makefile"], allowed = [], goal = "-x", goal_quote = Q),' '    },' ')'
ua_fix pgoalnomk "$UA1" "$UA2" "$UA3" '    units = {' "$UPB" '        "bonus": unit(page = 2, files = ["b.c"], allowed = [], goal = "bonus", goal_quote = Q),' '    },' ')'
ua_fix ponegoal "$UA1" "$UA2" "$UA3" '    units = {' \
	'        "sorter": unit(page = 1, files = ["Makefile"], allowed = [], goal = "bonus", goal_quote = Q),' "$UPC" '    },' ')'
ua_fix pnomk "$UA1" "$UA2" "$UA3" '    units = {' \
	'        "base": unit(page = 1, files = ["toy_fmt.c"], allowed = []),' \
	'        "bonus": unit(page = 2, files = ["toy_fmt.c"], allowed = []),' '    },' ')'
ua_fix pbare "$UA1" "$UA2" "$UA3" '    units = {' "$UPS" \
	'        "checker": unit(page = 2, files = ["Makefile"], allowed = []),' '    },' ')'
ua_fix ppattern "$UA1" "$UA2" "$UA3" '    units = {' \
	'        "base": unit(page = 1, files = ["a.c"], optional = ["*_extra.c"], allowed = []),' \
	'        "bonus": unit(page = 2, files = ["b.c"], allowed = []),' '    },' ')'
ua_fix psibpattern "$UA1" "$UA2" "$UA3" '    units = {' \
	'        "base": unit(page = 1, files = ["a.c"], allowed = []),' \
	'        "bonus": unit(page = 2, files = ["b.c"], optional = ["**/*.h"], allowed = []),' '    },' ')'
ua_fix pdot "$UA1" "$UA2" "$UA3" '    units = {' \
	'        "base": unit(page = 1, files = ["srcs/./a.c"], allowed = []),' \
	'        "bonus": unit(page = 2, files = ["srcs/a.c"], allowed = []),' '    },' ')'
ua_fix pgoalown "$UA1" "$UA2" "$UA3" '    units = {' "$UPB" \
	'        "bonus": unit(page = 2, files = ["Makefile", "b.c"], allowed = [], goal = "bonus", goal_quote = Q),' '    },' ')'
# ua_ffix NAME VALUE... -- an exercise whose files (or provided) is VALUE,
# a shape Starlark accepts that rows=files reads only in part.
ua_ffix() { _uaff=$1; shift; ua_fix "$_uaff" "$UA1" '    exercises = {' "        \"00\": exercise(dir = \"ex00/\", $*)," '    },' ')'; }
ua_ffix fname 'files = ["a.c", B]'
ua_ffix fconcat 'files = ["a.c", "ft_" + "b.c"]'
ua_ffix fformat 'files = ["ft_%s.c" % "a"]'
ua_ffix fcompr 'files = ["ft_%s.c" % n for n in ["a", "b"]]'
ua_ffix fnested 'files = ["a.c", ["b.c"]]'
ua_ffix fcall 'files = ["a.c"] + owed("b.c", "c.c", "d.c")'
ua_ffix fparen 'files = [], provided = {"x.c": ("srcs/" + "x.c"), "y.c": "srcs/y.c"}'
# ua_run NAME [AWK-OPTION...] -- units.awk on NAME.bzl, run from $WORK/ua:
# its rows, its words on stderr, its status. Rows beside a refusal are no
# refusal (it prints them only once all is read): 3, which every arm reads
# as a failure.
ua_run() {
	_uan=$1
	shift
	(cd "$WORK/ua" && env LC_ALL=C awk "$@" -f "$UA_TOOLS/units.awk" "$_uan.bzl") > "$WORK/ua/$_uan.rows"
	_uarc=$?
	if [ "$_uarc" -ne 0 ] && [ -s "$WORK/ua/$_uan.rows" ]; then
		echo "units.awk exited $_uarc, and printed rows too"
		return 3
	fi
	cat "$WORK/ua/$_uan.rows"
	return "$_uarc"
}
# ua_rows NAME [AWK-OPTION...] -- the same, its rows on one line as
# "<ROW | ROW>", so one pattern holds every row, in order, and no more:
# "<>" is no row at all.
ua_rows() {
	ua_run "$@" > "$WORK/ua/joined"
	_uarc=$?
	awk '{ o = o (NR > 1 ? " | " : "") $0 } END { printf "<%s>\n", o }' "$WORK/ua/joined"
	return "$_uarc"
}
# ua_said NAME -- what it said on stderr alone, as "said <...>", and its status.
ua_said() {
	(cd "$WORK/ua" && env LC_ALL=C awk -f "$UA_TOOLS/units.awk" "$1.bzl") > /dev/null 2> "$WORK/ua/said"
	_uarc=$?
	printf 'said <%s>\n' "$(cat "$WORK/ua/said")"
	return "$_uarc"
}
want_broken "units.awk: a string open at the end of its line" \
	'units.awk: unterminated.bzl:3: a string that does not end on its line' -- ua_run unterminated
want_broken "units.awk: a triple-quoted string that never ends" \
	'units.awk: triple.bzl:3: a triple-quoted string that never ends' -- ua_run triple
want_broken "units.awk: a call that never closes" \
	'units.awk: noclose.bzl:6: the subject( call never closes' -- ua_run noclose
want_broken "units.awk: a second subject( call" \
	'units.awk: second.bzl:8: a second subject( call' -- ua_run second
want_broken "units.awk: a positional argument to subject()" \
	'units.awk: positional.bzl:2: subject() has an argument that is not name = value' -- ua_run positional
want_broken "units.awk: **kwargs in an exercise()" \
	'units.awk: kwargs.bzl:5: exercise "00" has an argument that is not name = value' -- ua_run kwargs
want_broken "units.awk: exercises merged with |" \
	"units.awk: merged.bzl:6: subject()'s exercises is not one value" -- ua_run merged
want_broken "units.awk: a key of one digit" \
	'units.awk: onedigit.bzl:5: exercises has the key "1", not a two-digit number' -- ua_run onedigit
want_broken "units.awk: a key that is no number" \
	'units.awk: notnum.bzl:5: exercises has the key "0a", not a two-digit number' -- ua_run notnum
want_broken "units.awk: a key that is a name" \
	'units.awk: namekey.bzl:5: exercises has a key that is not a plain string' -- ua_run namekey
want_broken "units.awk: a key with an escape in it" \
	'units.awk: esckey.bzl:5: exercises has a key that is not a plain string' -- ua_run esckey
want_broken "units.awk: exercises written as a comprehension" \
	'units.awk: comprehension.bzl:4: exercises has a key that is not a plain string' -- ua_run comprehension
want_broken "units.awk: a key given twice" \
	'units.awk: dupkey.bzl:6: exercises has the key "00" twice' -- ua_run dupkey
want_broken "units.awk: an entry that is no exercise(...)" \
	'units.awk: other.bzl:5: "00" is not written as exercise(...)' -- ua_run other
want_broken "units.awk: an exercise with no dir" \
	'units.awk: nodir.bzl:5: exercise "00" has no dir = ...' -- ua_run nodir
want_broken "units.awk: a dir that is a name" \
	"units.awk: dirname.bzl:5: exercise \"00\"'s dir is not a plain string" -- ua_run dirname
# An exercise turns in at the folder its key names, and turns in no library.
want_broken "units.awk: an exercise with dir = None" \
	'units.awk: exnone.bzl:5: exercise "00" has dir = None: an exercise turns in at ex00/' -- ua_run exnone
want_broken "units.awk: an exercise turned in at another's folder" \
	'units.awk: notkey.bzl:5: exercise "03" turns in at "ex04/": an exercise turns in at ex03/' -- ua_run notkey
want_broken "units.awk: ...its dir read before a slash is dropped" \
	'units.awk: slashes.bzl:5: exercise "00" turns in at "ex00//"' -- ua_run slashes
want_broken "units.awk: ...and a # in it read as part of the string" \
	'units.awk: hashdir.bzl:5: exercise "00" turns in at "a#b/"' -- ua_run hashdir
want_broken "units.awk: an exercise with functions, at their line" \
	'units.awk: exfn.bzl:6: exercise "00" has functions = {...}: an exercise turns in no library' -- ua_run exfn
want_broken "units.awk: ...functions = None too, as subject() refuses it" \
	'units.awk: exfnnone.bzl:6: exercise "00" has functions = {...}: an exercise turns in no library' -- ua_run exfnnone
want_broken "units.awk: functions that are a name" \
	"units.awk: fnname.bzl:5: unit \"libtoy\"'s functions is not a {...} written out" -- ua_run fnname
want_broken "units.awk: a function listed twice" \
	'units.awk: dupfn.bzl:7: unit "libtoy" lists toy_a twice' -- ua_run dupfn
want_broken "units.awk: mandatory that is a name" \
	'units.awk: mandname.bzl:7: mandatory is neither a [...] written out nor None' -- ua_run mandname
want_broken "units.awk: mandatory naming no exercise" \
	'units.awk: mandmissing.bzl:7: mandatory names "07", which is no exercise of this contract' -- ua_run mandmissing
want_broken "units.awk: mandatory = []" \
	'units.awk: mandempty.bzl:7: mandatory = [] names no exercise' -- ua_run mandempty
want_broken "units.awk: a subject() with neither map" \
	'units.awk: noexercises.bzl:1: subject() has neither exercises = {...} nor units = {...}' -- ua_run noexercises
want_broken "units.awk: an argument given twice" \
	'units.awk: dupkwarg.bzl:3: subject() is given grader twice' -- ua_run dupkwarg
want_broken "units.awk: rows= names no kind of row it prints" \
	'units.awk: rows=units: the rows it prints are units (no rows=), files (rows=files) or goals (rows=goals)' -- \
	ua_run empty -v rows=units
want_out "units.awk: a # inside a string ends nothing" \
	"$(printf '<ex00\tfiles\ta#b.c>')" -- ua_rows hashkey -v rows=files
want_broken_none "units.awk: ...and a key in a comment is no key" 'ex01' -- ua_run hashkey
want_out "units.awk: a library's functions follow it in order" \
	"$(printf '<libtoy\tlibrary\t-\tdeliverable\tfolder\t- | toy_a\tfunction\t-\tdeliverable\tdefines\tlibtoy | toy_b\tfunction\t-\tdeliverable\tdefines\tlibtoy>')" -- \
	ua_rows bracefn
want_out "units.awk: a triple-quoted string over lines" \
	"$(printf '<ex00\texercise\t-\tdeliverable/ex00\tfolder\t->')" -- ua_rows tripleok
want_out "units.awk: a contract in single quotes" \
	"$(printf '<ex00\texercise\t-\tdeliverable/ex00\tfolder\t->')" -- ua_rows single
want_out "units.awk: a raw string" \
	"$(printf '<ex00\texercise\t-\tdeliverable/ex00\tfolder\t->')" -- ua_rows raw
want_out "units.awk: mandatory before exercises, each REQ" \
	"$(printf '<ex00\texercise\toptional\tdeliverable/ex00\tfolder\t- | ex01\texercise\tmandatory\tdeliverable/ex01\tfolder\t->')" -- \
	ua_rows mandfirst
want_green "units.awk: exercises = {} is read" -- ua_run empty
want_out "units.awk: ...as no row" '<>' -- ua_rows empty
want_green "units.awk: a call on one line is read" -- ua_run oneline
want_out "units.awk: ...as no row either" '<>' -- ua_rows oneline
want_red "units.awk: a file with no subject( is exit 1" -- ua_run nosubject
want_out "units.awk: ...said nothing" 'said <>' -- ua_said nosubject
want_out "units.awk: rows=files, what it cannot read is empty" \
	"$(printf '<ex00\tfiles\ta.c | ex00\tfiles\t | ex00\tprovided\tsrcs/x.c>')" -- \
	ua_rows files -v rows=files
# Each a list read in part: the strings that stand alone, and one empty row,
# never a piece of an expression printed as a whole file name.
want_out "units.awk: rows=files, a name inside the list" \
	"$(printf '<ex00\tfiles\ta.c | ex00\tfiles\t>')" -- ua_rows fname -v rows=files
want_out "units.awk: rows=files, a string joined with + inside the list" \
	"$(printf '<ex00\tfiles\ta.c | ex00\tfiles\t>')" -- ua_rows fconcat -v rows=files
want_out "units.awk: rows=files, a string formatted with %" \
	"$(printf '<ex00\tfiles\t>')" -- ua_rows fformat -v rows=files
want_out "units.awk: rows=files, a comprehension" \
	"$(printf '<ex00\tfiles\t>')" -- ua_rows fcompr -v rows=files
want_out "units.awk: rows=files, a list inside the list" \
	"$(printf '<ex00\tfiles\ta.c | ex00\tfiles\t>')" -- ua_rows fnested -v rows=files
want_out "units.awk: rows=files, a call's arguments are no files" \
	"$(printf '<ex00\tfiles\ta.c | ex00\tfiles\t>')" -- ua_rows fcall -v rows=files
want_out "units.awk: rows=files, a provided value in parentheses" \
	"$(printf '<ex00\tprovided\t | ex00\tprovided\tsrcs/y.c>')" -- ua_rows fparen -v rows=files
want_broken "units.awk: both exercises and units" \
	'units.awk: nboth.bzl:7: subject() has both exercises = {...} and units = {...}' -- ua_run nboth
want_broken "units.awk: a unit with a dir, None too" \
	'units.awk: ndir.bzl:5: unit "tally" has a dir = ...' -- ua_run ndir
want_broken "units.awk: a unit name with a capital" \
	'units.awk: nupper.bzl:5: units has the key "Tally", which is not a unit name' -- ua_run nupper
want_broken "units.awk: a unit name shaped like an exercise's" \
	'units.awk: nex.bzl:5: units has the key "ex1_tally", which is shaped like an exercise'"'"'s name' -- ua_run nex
want_broken "units.awk: a unit given twice" \
	'units.awk: ndupkey.bzl:6: units has the key "tally" twice' -- ua_run ndupkey
want_broken "units.awk: two units, neither with a goal" \
	'units.awk: nsecond.bzl:6: units "tally" and "bonus" may share their files, and neither has a goal' -- ua_run nsecond
want_broken "units.awk: a unit that is no unit(...)" \
	'units.awk: nother.bzl:5: "tally" is not written as unit(...)' -- ua_run nother
want_broken "units.awk: **kwargs in a unit()" \
	'units.awk: nkwargs.bzl:5: unit "tally" has an argument that is not name = value' -- ua_run nkwargs
want_broken "units.awk: a goal on the only unit" \
	'units.awk: ngoal.bzl:6: unit "tally" has a goal' -- ua_run ngoal
want_broken "units.awk: a function name that is no unit name" \
	"units.awk: nfnname.bzl:6: unit \"libtoy\"'s function \"Toy_len\" is not a unit name" -- ua_run nfnname
want_broken "units.awk: a function named as its library" \
	'units.awk: nfnsame.bzl:7: "libtoy" names both the unit "libtoy" and a function of unit "libtoy"' -- ua_run nfnsame
want_broken "units.awk: the prefix rule, two functions" \
	'units.awk: nprefix.bzl:8: "toy_len" followed by _ begins "toy_len_max"' -- ua_run nprefix
want_broken "units.awk: the prefix rule, a library and its function" \
	'units.awk: nprefixlib.bzl:6: "toy" followed by _ begins "toy_up"' -- ua_run nprefixlib
want_broken "units.awk: mandatory naming a function" \
	'units.awk: nmandfn.bzl:9: mandatory names "toy_len", a function of unit "libtoy"' -- ua_run nmandfn
want_broken "units.awk: mandatory naming no unit" \
	'units.awk: nmandmissing.bzl:7: mandatory names "bonus", which is no unit of this contract' -- ua_run nmandmissing
want_out "units.awk: a library and its functions, by name" \
	"$(printf '<libtoy\tlibrary\tmandatory\tdeliverable\tfolder\t- | toy_up\tfunction\t-\tdeliverable\tdefines\tlibtoy | toy_len\tfunction\t-\tdeliverable\tdefines\tlibtoy>')" -- \
	ua_rows nlib
want_out "units.awk: a project's only unit, goal = None read" \
	"$(printf '<tally\tproject\t-\tdeliverable\tfolder\t->')" -- ua_rows nprog
want_out "units.awk: rows=files names a unit as it is named" \
	"$(printf '<tally\tfiles\tMakefile | tally\toptional\t**/*.c | tally\tprovided\tx.h>')" -- \
	ua_rows nfiles -v rows=files
want_out "units.awk: parts with files of their own" \
	"$(printf '<base\tpart\tmandatory\tdeliverable\tfiles\t- | bonus\tpart\toptional\tdeliverable\tfiles\t->')" -- ua_rows pfiles
want_out "units.awk: two programs, one Makefile, a goal" \
	"$(printf '<sorter\tpart\tmandatory\tdeliverable\tgoal\t- | checker\tpart\toptional\tdeliverable\tgoal\t->')" -- ua_rows pprog
want_out "units.awk: a bonus in the same files" \
	"$(printf '<base\tpart\tmandatory\tdeliverable\tgoal\t- | bonus\tpart\toptional\tdeliverable\tgoal\t->')" -- ua_rows psame
want_out "units.awk: rows=goals names each goal, in order" \
	"$(printf '<checker\tbonus>')" -- ua_rows pprog -v rows=goals
want_out "units.awk: ...and none where no unit has one" '<>' -- ua_rows pfiles -v rows=goals
want_out "units.awk: ...nor for exercises" '<>' -- ua_rows mandfirst -v rows=goals
want_out "units.awk: rows=files reads a part's lists" \
	"$(printf '<sorter\tfiles\tMakefile | sorter\toptional\t**/*.c | sorter\toptional\t**/*.h | checker\tfiles\tMakefile | checker\toptional\t**/*.c | checker\toptional\t**/*.h>')" -- \
	ua_rows pprog -v rows=files
want_broken "units.awk: a library among parts" \
	'units.awk: plib.bzl:5: unit "libtoy" has functions, and the project has other units' -- ua_run plib
want_broken "units.awk: a part with a strict" \
	'units.awk: pstrict.bzl:6: unit "bonus" has a strict = ...' -- ua_run pstrict
want_broken "units.awk: a part with files = None" \
	'units.awk: pnofiles.bzl:6: unit "bonus" has no files' -- ua_run pnofiles
want_broken "units.awk: a part that lists no file" \
	'units.awk: pnofile.bzl:6: unit "bonus" lists no file' -- ua_run pnofile
want_broken "units.awk: a part's files not written out" \
	"units.awk: pfname.bzl:6: unit \"bonus\"'s files is not a list of plain strings written out" -- ua_run pfname
want_broken "units.awk: a goal that is a name" \
	"units.awk: pgoalname.bzl:6: unit \"checker\"'s goal is neither a plain string nor None" -- ua_run pgoalname
want_broken "units.awk: a goal that is no rule name" \
	"units.awk: pgoalshape.bzl:6: unit \"checker\"'s goal \"-x\" is no Makefile rule name" -- ua_run pgoalshape
want_broken "units.awk: a goal and no Makefile" \
	'units.awk: pgoalnomk.bzl:6: unit "bonus" has a goal, and lists no Makefile' -- ua_run pgoalnomk
want_broken "units.awk: two parts with one goal" \
	'units.awk: ponegoal.bzl:6: units "sorter" and "checker" both have goal = "bonus"' -- ua_run ponegoal
want_broken "units.awk: parts that share a name and no Makefile" \
	'units.awk: pnomk.bzl:5: unit "base" may share its files with another part, and lists no Makefile' -- ua_run pnomk
want_broken "units.awk: two parts a bare make would build" \
	'units.awk: pbare.bzl:6: units "sorter" and "checker" may share their files, and neither has a goal' -- ua_run pbare
want_broken "units.awk: a part's own pattern shares" \
	'units.awk: ppattern.bzl:5: unit "base" may share its files with another part' -- ua_run ppattern
want_broken "units.awk: another part's pattern shares" \
	'units.awk: psibpattern.bzl:5: unit "base" may share its files with another part' -- ua_run psibpattern
want_broken "units.awk: a . segment is no plain name" \
	'units.awk: pdot.bzl:5: unit "base" may share its files with another part' -- ua_run pdot
want_broken "units.awk: a goal on a part whose files are its own" \
	'units.awk: pgoalown.bzl:6: unit "bonus" has a goal, and its files are its own' -- ua_run pgoalown

