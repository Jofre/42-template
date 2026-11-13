"""The user file's grammar, case by case: what 42 reads from each file, or the line it refuses.

Each case is (label, the file's bytes, what 42 reads). What it reads is a dict
{name: value}, every value the string 42 hands its reader, or Refused(line,
words the message holds). test_userconfig.py holds userconfig.parse to every
case. //tools/tests:userconfig_oracle_test holds every dict to the two real
YAML readers: PyYAML (YAML 1.1) and ruamel.yaml (YAML 1.2) must read that file
as that mapping, a decimal value as the number it spells. So a case here is
never 42's opinion alone.

A label that starts with "hole:" is one the design review found the first
prototype getting wrong (2026-10-23): it read a file that a real YAML reader
reads differently or not at all, or refused one both read alike. The holes
in its writer are test_userconfig.py's Edit cases.
"""


class Refused:
    def __init__(self, line, words):
        self.line, self.words = line, words

    def __repr__(self):
        return "Refused(%r, %r)" % (self.line, self.words)


NAMES = ("login", "email", "level", "remote.c-05", "remote.cursus/Milestone_0/Libft",
         "bazel.cpus", "bazel.idle_secs", "machine.root")

CASES = [
    # What reads as nothing.
    ("empty", b"", {}),
    ("comments only", b"# a\n# b\n", {}),
    ("blank lines", b"\n\n   \n", {}),
    ("an indented comment", b"   # c\n", {}),
    ("the header 42 writes",
     b"# Settings 42 reads in every checkout of yours on this machine. A checkout's\n"
     b"# own value wins over these: `42 config list` shows which one is in use.\n", {}),
    ("a document start alone", b"---\n", {}),

    # Entries.
    ("one entry", b"level: strict\n", {"level": "strict"}),
    ("no final newline", b"level: strict", {"level": "strict"}),
    ("several, blank lines between", b"\nlogin: jdoe\n\nlevel: strict\n\n", {"login": "jdoe", "level": "strict"}),
    ("more blanks after the colon", b"level:    strict\n", {"level": "strict"}),
    ("trailing blanks", b"level: strict   \n", {"level": "strict"}),
    ("a trailing comment", b"level: strict # mine\n", {"level": "strict"}),
    ("an empty trailing comment", b"level: strict #\n", {"level": "strict"}),
    ("hole: a tab inside a full-line comment", b"# a\tb\n", {}),
    ("a trailing comment with a tab in it", b"level: strict # a\tb\n", {"level": "strict"}),
    ("a document start first", b"---\nlevel: strict\n", {"level": "strict"}),
    ("a document start after comments", b"# c\n---\nlevel: strict\n", {"level": "strict"}),
    ("a document start with trailing blanks", b"---   \nlevel: strict\n", {"level": "strict"}),
    ("a BOM at the start", b"\xef\xbb\xbflevel: strict\n", {"level": "strict"}),
    ("CRLF lines", b"login: jdoe\r\nlevel: strict\r\n", {"login": "jdoe", "level": "strict"}),
    ("a CRLF line with a trailing comment", b"level: strict # mine\r\n", {"level": "strict"}),
    ("CRLF and LF mixed", b"login: jdoe\r\nlevel: strict\n", {"login": "jdoe", "level": "strict"}),
    ("a CR at the very end", b"level: strict\r", {"level": "strict"}),
    ("every name 42 has today", b"".join(b"%s: x\n" % n.encode() for n in NAMES), {n: "x" for n in NAMES}),
    ("names with _ / . -", b"a_b: x\na/b: x\nA: x\na.b.c-d: x\n", {"a_b": "x", "a/b": "x", "A": "x", "a.b.c-d": "x"}),
    # YAML reads a name as a key only when its colon is at most 1024
    # characters from where the name starts (YAML 1.2, 7.4.2).
    ("a name of 1024 characters", b"a" * 1024 + b": x\n", {"a" * 1024: "x"}),

    # Plain values.
    ("an scp-style URL", b"remote.c-05: git@git.example.com:you/c-05.git\n",
     {"remote.c-05": "git@git.example.com:you/c-05.git"}),
    ("an ssh URL", b"r: ssh://git@host.example.com:2222/you/c-05.git\n", {"r": "ssh://git@host.example.com:2222/you/c-05.git"}),
    ("an https URL", b"r: https://example.com/a/b\n", {"r": "https://example.com/a/b"}),
    ("a file URL", b"r: file:///srv/git/c-05.git\n", {"r": "file:///srv/git/c-05.git"}),
    ("an absolute path", b"r: /srv/git/c-05.git\n", {"r": "/srv/git/c-05.git"}),
    ("a slash alone", b"r: /\n", {"r": "/"}),
    ("an email", b"email: jdoe@student.42.fr\n", {"email": "jdoe@student.42.fr"}),
    ("a colon inside", b"a: b:c\n", {"a": "b:c"}),
    ("an equals sign and a plus inside", b"a: b=c+d\n", {"a": "b=c+d"}),
    ("one letter", b"a: x\n", {"a": "x"}),
    ("a decimal", b"bazel.idle_secs: 600\n", {"bazel.idle_secs": "600"}),
    ("zero", b"a: 0\n", {"a": "0"}),
    ("a big decimal", b"a: 123456789012345678901234567890\n", {"a": "123456789012345678901234567890"}),

    # Quoted values.
    ("a quoted no", b'a: "no"\n', {"a": "no"}),
    ("a quoted 0755", b'a: "0755"\n', {"a": "0755"}),
    ("a quoted 12:30", b'a: "12:30"\n', {"a": "12:30"}),
    ("a quoted date", b'a: "2026-10-23"\n', {"a": "2026-10-23"}),
    ("blanks inside quotes", b'a: " x y "\n', {"a": " x y "}),
    ("a # inside quotes", b'a: "x # y"\n', {"a": "x # y"}),
    ("an empty string", b'a: ""\n', {"a": ""}),
    ("every escape JSON has", b'a: "\\"\\\\\\/\\b\\f\\n\\r\\t\\u00e9"\n', {"a": '"\\/\b\f\n\r\t\u00e9'}),
    ("a \\u0000", b'a: "\\u0000"\n', {"a": "\0"}),
    ("raw UTF-8 inside quotes", "a: \"\u00e9\u4e2d\U0001f600\"\n".encode(), {"a": "\u00e9\u4e2d\U0001f600"}),
    ("a quoted value and a comment", b'a: "x" # c\n', {"a": "x"}),
    ("a single-quoted no", b"a: 'no'\n", {"a": "no"}),
    ("a doubled single quote", b"a: 'it''s'\n", {"a": "it's"}),
    ("an empty single-quoted string", b"a: ''\n", {"a": ""}),
    ("a # inside single quotes", b"a: 'x # y'\n", {"a": "x # y"}),
    ("a backslash in single quotes is a backslash", b"a: 'x\\ny'\n", {"a": "x\\ny"}),
    ("raw UTF-8 in a comment", "# \u00e9\u4e2d\U0001f600\n".encode(), {}),

    # What YAML reads as something else.
    ("no", b"a: no\n", Refused(1, "true or false")),
    ("NO", b"a: NO\n", Refused(1, "true or false")),
    ("yes", b"a: yes\n", Refused(1, "true or false")),
    ("on", b"a: on\n", Refused(1, "true or false")),
    ("Off", b"a: Off\n", Refused(1, "true or false")),
    ("true", b"a: true\n", Refused(1, "true or false")),
    ("False", b"a: False\n", Refused(1, "true or false")),
    ("y", b"a: y\n", Refused(1, "true or false")),
    ("n", b"a: n\n", Refused(1, "true or false")),
    ("null", b"a: null\n", Refused(1, "null")),
    ("~", b"a: ~\n", Refused(1, "symbol")),
    ("0755", b"a: 0755\n", Refused(1, "number")),
    ("012", b"a: 012\n", Refused(1, "number")),
    ("1_0", b"a: 1_0\n", Refused(1, "number")),
    ("12:30", b"a: 12:30\n", Refused(1, "number")),
    ("a date", b"a: 2026-10-23\n", Refused(1, "date")),
    ("1e3", b"a: 1e3\n", Refused(1, "number")),
    ("1.5", b"a: 1.5\n", Refused(1, "number")),
    (".inf", b"a: .inf\n", Refused(1, "number")),
    ("-1", b"a: -1\n", Refused(1, "number")),
    ("+1", b"a: +1\n", Refused(1, "number")),
    ("0x1f", b"a: 0x1f\n", Refused(1, "number")),
    ("a name that is a bool", b"on: x\n", Refused(1, "the name on")),
    ("a name that is null", b"null: x\n", Refused(1, "the name null")),
    ("a name that is y", b"y: x\n", Refused(1, "the name y")),

    # Shapes outside the subset.
    ("no value", b"a:\n", Refused(1, "no value")),
    ("only a comment for a value", b"a: # c\n", Refused(1, "no value")),
    ("a nested map", b"a:\n  b: c\n", Refused(1, "no value")),
    ("an indented entry", b"  a: x\n", Refused(1, "indented")),
    ("a list", b"- a\n", Refused(1, "not `name: value`")),
    ("no blank after the colon", b"a:x\n", Refused(1, "a blank goes after")),
    ("a blank inside a plain value", b"a: x y\n", Refused(1, "double quotes")),
    ("a comma in a plain value", b"a: x,y\n", Refused(1, "double quotes")),
    ("a # with no blank before it", b"a: x#c\n", Refused(1, "double quotes")),
    ("text after the quotes", b'a: "x" y\n', Refused(1, "double quotes")),
    ("a comment glued to the quotes", b'a: "x"#c\n', Refused(1, "double quotes")),
    ("an unterminated quote", b'a: "x\n', Refused(1, "double quotes")),
    ("a value ending in a colon", b"a: x:\n", Refused(1, "double quotes")),
    ("a value with ': ' inside", b"a: b: c\n", Refused(1, "double quotes")),
    ("an anchor", b"a: &x b\n", Refused(1, "symbol")),
    ("an alias", b"a: *x\n", Refused(1, "symbol")),
    ("a tag", b"a: !t b\n", Refused(1, "symbol")),
    ("a block scalar", b"a: |\n  x\n", Refused(1, "symbol")),
    ("a flow list", b"a: [1]\n", Refused(1, "symbol")),
    ("a flow map", b"a: {b: c}\n", Refused(1, "symbol")),
    ("a reserved @", b"a: @x\n", Refused(1, "symbol")),
    ("a directive", b"%YAML 1.2\n---\na: x\n", Refused(1, "not `name: value`")),
    ("a complex key", b"? a\n: b\n", Refused(1, "not `name: value`")),
    ("a quoted name", b'"a": x\n', Refused(1, "not `name: value`")),
    ("a name with a blank", b"a b: x\n", Refused(1, "not `name: value`")),
    ("a name starting with a digit", b"1a: x\n", Refused(1, "not `name: value`")),
    ("a document end", b"a: x\n...\n", Refused(2, "may only start the file")),
    ("a document start after an entry", b"a: x\n---\nb: y\n", Refused(2, "may only start the file")),
    ("two document starts", b"---\n---\na: x\n", Refused(2, "may only start the file")),
    ("a name set twice", b"a: x\nb: w\na: z\n", Refused(3, "set twice, here and on line 1")),
    ("a name of 1025 characters", b"a" * 1025 + b": x\n", Refused(1, "1025 characters")),

    # Characters.
    ("a tab as the blank after the colon", b"a:\tx\n", Refused(1, "a tab")),
    ("a tab before a name", b"\ta: x\n", Refused(1, "a tab")),
    ("a tab before a trailing comment", b"a: x\t# c\n", Refused(1, "a tab")),
    ("a tab before a full-line comment", b"\t# c\n", Refused(1, "a tab")),
    ("a raw tab inside quotes", b'a: "x\ty"\n', Refused(1, "a tab")),
    ("hole: a NEL in a comment", b"a: x # c\xc2\x85b: y\n", Refused(1, "U+0085")),
    ("hole: a NEL in a full-line comment", b"# c\xc2\x85b: y\n", Refused(1, "U+0085")),
    ("hole: a U+2028 in a comment", b"# c\xe2\x80\xa8b: y\n", Refused(1, "U+2028")),
    ("hole: a U+2029 in a comment", b"a: x # c\xe2\x80\xa9\n", Refused(1, "U+2029")),
    ("hole: a control character in a comment", b"# c\x01\na: x\n", Refused(1, "U+0001")),
    ("hole: an ESC in a comment", b"# c\x1b[0m\na: x\n", Refused(1, "U+001B")),
    ("hole: a DEL in a comment", b"# c\x7f\na: x\n", Refused(1, "U+007F")),
    ("a C1 control in a comment", b"# c\xc2\x9b\n", Refused(1, "U+009B")),
    ("a BOM in the middle", b"a: x\n\xef\xbb\xbfb: y\n", Refused(2, "U+FEFF")),
    ("a NEL inside quotes", b'a: "x\xc2\x85y"\n', Refused(1, "U+0085")),
    ("a NEL inside single quotes", b"a: 'x\xc2\x85y'\n", Refused(1, "U+0085")),
    ("a U+FFFE inside quotes", b'a: "x\xef\xbf\xbe"\n', Refused(1, "U+FFFE")),
    ("a CR inside a line", b"a: x\rb: y\n", Refused(1, "carriage return")),
    ("a byte that is no UTF-8", b"a: x\nb: \xff\n", Refused(2, "UTF-8")),
    ("a \\x escape", b'a: "\\x41"\n', Refused(1, "an escape")),
    ("a \\a escape", b'a: "\\a"\n', Refused(1, "an escape")),
    ("a \\e escape", b'a: "\\e"\n', Refused(1, "an escape")),
    ("a \\N escape", b'a: "\\N"\n', Refused(1, "an escape")),
    ("a \\U escape", b'a: "\\U0001F600"\n', Refused(1, "an escape")),
    ("a \\ before a blank", b'a: "\\ "\n', Refused(1, "an escape")),
    ("half a character", b'a: "\\ud83d"\n', Refused(1, "half of a character")),
]
