# userconfig_line.awk -- the line of your user file that sets NAME, for a script.
#
#     LC_ALL=C awk -v name=level -f tools/userconfig_line.awk FILE
#
# prints that line's number and exits 0, or exits 1 when no line sets it.
#
# Your user file ($XDG_CONFIG_HOME/42/config.yaml, else ~/.config/42/config.yaml)
# is 42's to read: tools/fortytwo/userconfig.py, which refuses what it does not
# understand. A script gets a value from it as a flag, from 42. This finds the
# line and reads nothing in it, so that a script run without that flag can
# stop instead of acting on a default the file says otherwise.
# tools/fortytwo/tests/test_config.py holds it to 42's reader, file by file.
#
# Every line 42 reads starts with its name and a colon, so a line that starts
# with a name and a colon sets that name and no other. In any other line (one
# 42 refuses: indented, quoted, a list item, a flow mapping, a tag or anchor,
# a blank before the colon) NAME is set when it appears as a word followed by
# a colon or by nothing, past blanks, quotes and closing brackets: whoever
# wrote it may have meant that name, and 42 itself stops on such a file. A
# comment or blank line sets nothing, and a leading --- is no part of a line.
#
# YAML also breaks a line at a lone CR, NEL, LS and PS, where awk sees none,
# so each piece between them is read as a line of its own; the number printed
# is the line's, counted at newlines, as 42 counts them. A byte order mark
# before the first line is no part of it.

BEGIN {
	q = sprintf("%c", 39)
	word = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./-"
	after = " \t\"" q "}]"
}

# s with every from in it turned into a carriage return.
function breaks(s, from,	i, out) {
	out = ""
	while ((i = index(s, from)) > 0) {
		out = out substr(s, 1, i - 1) "\r"
		s = substr(s, i + length(from))
	}
	return out s
}

# Whether s holds name as a word followed by a colon, or by nothing, past the
# characters in after.
function mentions(s,	at, i, j) {
	at = 0
	while ((i = index(substr(s, at + 1), name)) > 0) {
		i += at
		at = i
		if (i > 1 && index(word, substr(s, i - 1, 1)))
			continue
		j = i + length(name)
		while (j <= length(s) && index(after, substr(s, j, 1)))
			j++
		if (j > length(s) || substr(s, j, 1) == ":")
			return 1
	}
	return 0
}

# Whether the piece s of a line sets name.
function sets(s) {
	if (substr(s, 1, 3) == "---" && (length(s) == 3 || index(" \t", substr(s, 4, 1))))
		s = substr(s, 4)
	if (s ~ /^[ \t]*(#|$)/)
		return 0
	if (s ~ /^[A-Za-z][A-Za-z0-9_.\/-]*:/)
		return substr(s, 1, index(s, ":") - 1) == name
	return mentions(s)
}

FNR == 1 && substr($0, 1, 3) == "\357\273\277" {
	$0 = substr($0, 4)
}

{
	line = breaks(breaks(breaks($0, "\302\205"), "\342\200\250"), "\342\200\251")
	n = split(line, piece, "\r")
	for (p = 1; p <= n; p++)
		if (sets(piece[p])) {
			print FNR
			found = 1
			exit
		}
}

END {
	exit !found
}
