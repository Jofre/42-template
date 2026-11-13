# ---------------------------------------------------------------- placeholder_pdf
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The PDF the public template ships where each 42 subject was. Nothing opens it
# in the suite, so the arms check what a PDF reader is strict about and a person
# would never notice until a viewer refused the file: the byte offset of every
# object in the cross-reference table, of the table itself in startxref, and the
# stream's /Length. The script MEASURES those from the file as it writes it, so
# these arms are what would catch a change that started computing them instead.
# The page carries the project's row of tools/subjects.tsv, and each URL on it
# is a link annotation of its own: one object more per link, so the offsets are
# checked over however many objects the table says there are.
mkdir -p "$WORK/pp"
_pp_sha=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
_pp_page=https://projects.intra.42.fr/projects/c-piscine-c-05
_pp_pdf=https://cdn.intra.42.fr/pdf/pdf/1/en.subject.pdf
"$SH" "$TOOLS/placeholder_pdf.sh" "$WORK/pp/p.pdf" c-piscine-c-05 7.1 "$_pp_sha" \
	"$_pp_page" "$_pp_pdf" > /dev/null 2>&1
pp_offsets() {
	awk '
		{ line[NR] = $0; at[NR] = off; off += length($0) + 1 }
		/^[0-9]+ 0 obj$/ { split($0, a, " "); obj[a[1]] = at[NR] }
		/^<< \/Length [0-9]+ >>$/ { split($0, a, " "); len = a[3] }
		$0 == "stream" { s0 = off }
		$0 == "endstream" { s1 = at[NR] - 1 }
		$0 == "xref" { xat = at[NR]; xl = NR }
		$0 == "startxref" { sx = NR + 1 }
		/^<< \/Size [0-9]+ / { split($0, a, " "); size = a[3] }
		END {
			if (line[1] != "%PDF-1.4" || line[NR] != "%%EOF") exit 1
			if (xl == 0 || line[sx] + 0 != xat) exit 1
			if (len + 0 != s1 - s0) exit 1
			split(line[xl + 1], h, " ")
			n = h[2] + 0
			if (n < 6 || n != size + 0) exit 1
			for (i = 1; i < n; i++) {
				split(line[xl + 2 + i], f, " ")
				if (!(i in obj) || f[1] + 0 != obj[i]) exit 1
			}
			if ((n in obj)) exit 1
		}' "$1"
}
# What a reader would open: how many lines offer a direct download, then the
# URI of every link annotation in object order, and END after the last, so an
# arm's text names them all and nothing after.
pp_links() {
	printf 'DL=%s LINKS=' "$(grep -c 'to download directly' "$1")"
	sed -n 's|.*/A << /S /URI /URI (\([^)]*\)) >>.*|\1|p' "$1" | tr '\n' ','
	printf 'END\n'
}
want_green "placeholder_pdf: every offset points where it claims" -- \
	pp_offsets "$WORK/pp/p.pdf"
want_green "placeholder_pdf: ... and it names the project" -- \
	grep -q "Project: c-piscine-c-05" "$WORK/pp/p.pdf"
want_green "placeholder_pdf: ... the version and the whole SHA-256" -- \
	"$SH" -c 'grep -q "(This harness was built from version 7.1 of the English subject,) Tj" "$1" &&
		grep -q "($2) Tj" "$1"' _ "$WORK/pp/p.pdf" "$_pp_sha"
want_green "placeholder_pdf: ... each URL on a line of its own" -- \
	"$SH" -c 'grep -q "($2) Tj" "$1" && grep -q "($3) Tj" "$1"' _ "$WORK/pp/p.pdf" "$_pp_page" "$_pp_pdf"
want_out "placeholder_pdf: ... and each a link to that URL, and no other link" \
	"DL=1 LINKS=$_pp_page,$_pp_pdf,END" -- pp_links "$WORK/pp/p.pdf"
# A row with no direct link (a group project, a revised subject): the page
# says nothing of one, and links the project page alone.
"$SH" "$TOOLS/placeholder_pdf.sh" "$WORK/pp/n.pdf" c-piscine-bsq 9.2 "$_pp_sha" \
	https://projects.intra.42.fr/projects/c-piscine-bsq - > /dev/null 2>&1
want_green "placeholder_pdf: with no direct link, the offsets still hold" -- \
	pp_offsets "$WORK/pp/n.pdf"
want_out "placeholder_pdf: ... offers no download, and links the project page alone" \
	"DL=0 LINKS=https://projects.intra.42.fr/projects/c-piscine-bsq,END" -- pp_links "$WORK/pp/n.pdf"
want_broken "placeholder_pdf: a name a PDF string cannot hold is refused" \
	"project name must be" -- \
	"$SH" "$TOOLS/placeholder_pdf.sh" "$WORK/pp/x.pdf" 'a(b)' 7 "$_pp_sha" "$_pp_page" -
want_broken "placeholder_pdf: ... and so is a SHA-256 that is not 64 hex digits" \
	"sha256 must be" -- \
	"$SH" "$TOOLS/placeholder_pdf.sh" "$WORK/pp/x.pdf" c-piscine-c-05 7 abc "$_pp_page" -
want_broken "placeholder_pdf: ... and a URL holding a character the page cannot print" \
	"cannot print" -- \
	"$SH" "$TOOLS/placeholder_pdf.sh" "$WORK/pp/x.pdf" c-piscine-c-05 7 "$_pp_sha" "$_pp_page" 'https://x/(y)'
want_broken "placeholder_pdf: ... and a row short of its fields" \
	"usage" -- \
	"$SH" "$TOOLS/placeholder_pdf.sh" "$WORK/pp/x.pdf" c-piscine-c-05
# The optional per-project text (shell-00's resources.tar.gz and where it goes):
# lines added to the stream must move every offset after it, and it is held to
# the page's own rule about ( ) and \.
"$SH" "$TOOLS/placeholder_pdf.sh" "$WORK/pp/e.pdf" c-piscine-shell-00 5.1 "$_pp_sha" \
	"$_pp_page" "$_pp_pdf" \
	"$(printf 'ex07 also needs resources.tar.gz.\n|\nSave it next to BUILD.bazel.')" \
	> /dev/null 2>&1
want_green "placeholder_pdf: extra text keeps every offset right" -- \
	pp_offsets "$WORK/pp/e.pdf"
want_green "placeholder_pdf: ... and is on the page" -- \
	grep -q "(Save it next to BUILD.bazel.) Tj" "$WORK/pp/e.pdf"
want_broken "placeholder_pdf: extra text a PDF string cannot hold is refused" \
	"cannot hold" -- \
	"$SH" "$TOOLS/placeholder_pdf.sh" "$WORK/pp/y.pdf" c-piscine-shell-00 5.1 "$_pp_sha" \
	"$_pp_page" - 'see (this)'
want_broken "placeholder_pdf: ... and so is text outside printable ASCII" \
	"printable ASCII" -- \
	"$SH" "$TOOLS/placeholder_pdf.sh" "$WORK/pp/z.pdf" c-piscine-shell-00 5.1 "$_pp_sha" \
	"$_pp_page" - "$(printf 'caf\303\251')"

# tools/subjects.sh, the one reader of the registry those rows come from. A
# toy checkout: one project folder with a subject of known bytes, and one
# without (the template's shape, where only the rows are checked).
mkdir -p "$WORK/sj/tools" "$WORK/sj/c/p1" "$WORK/sj/c/p2"
printf 'not 42 subject bytes\n' > "$WORK/sj/c/p1/en.subject.pdf"
_sj_h=$(sha256sum "$WORK/sj/c/p1/en.subject.pdf" | cut -d' ' -f1)
sj_rows() {
	{
		printf '# a comment, skipped\n'
		printf 'c/p1\t3.1\t%s\thttps://projects.intra.42.fr/projects/p1\thttps://cdn.intra.42.fr/pdf/pdf/9/en.subject.pdf\t2026-11-01\n' "$1"
		printf 'c/p2\t2\t%s\thttps://projects.intra.42.fr/projects/p2\t-\t2026-11-01\n' "$_sj_h"
	} > "$WORK/sj/tools/subjects.tsv"
}
# Absolute: $TOOLS is runfiles-relative, and the reader runs from the toy.
_sj_script="$(cd "$TOOLS" && pwd)/subjects.sh"
sj() { "$SH" -c 'cd "$1" && shift && "$@"' _ "$WORK/sj" "$SH" "$_sj_script" "$@"; }
sj_rows "$_sj_h"
want_green "subjects: a registry whose rows hold passes check" -- sj check
want_out "subjects: get prints a project's row, its first column dropped" \
	"3.1	$_sj_h	https://projects.intra.42.fr/projects/p1	https://cdn.intra.42.fr/pdf/pdf/9/en.subject.pdf	2026-11-01" -- \
	sj get c/p1
want_out "subjects: ... and says so for a project with no row" \
	"c/p3 has no row" -- sj get c/p3
want_out "subjects: --subjects reports a row whose project has no subject to check" \
	"has a row for c/p2, which has no en.subject.pdf" -- sj check --subjects
sj_rows "$_pp_sha"
want_out "subjects: ...and a subject whose bytes are not its row's" \
	"c/p1/en.subject.pdf is not the subject" -- sj check --subjects
# Without --subjects no subject is opened: in a clone of the template an
# en.subject.pdf is the student's own download, of whatever version.
want_green "subjects: plain check opens no subject, whatever its bytes" -- sj check
want_broken "subjects: and an option it does not know is a usage error" \
	"usage" -- sj check --nope
sj_rows "$_sj_h"
printf 'c/p2\t2\tnope\thttp://x\t-\t2026-11-01\textra\n' >> "$WORK/sj/tools/subjects.tsv"
want_out "subjects: a row of the wrong width is reported" \
	"has 7 columns, not 6" -- sj check
sj_rows "$_sj_h"
printf 'c/p3\t2\tnope\thttp://x\t-\t2026-11-01\n' >> "$WORK/sj/tools/subjects.tsv"
want_out "subjects: ... a bad SHA-256" "c/p3: sha256 \"nope\"" -- sj check
want_out "subjects: ... and a page that is not the intranet's" "c/p3: page \"http://x\"" -- sj check
sj_rows "$_sj_h"
printf 'c/p2\t2\t%s\thttps://projects.intra.42.fr/projects/p2\t-\t2026-11-01\n' "$_sj_h" >> "$WORK/sj/tools/subjects.tsv"
want_out "subjects: a project with two rows is reported" \
	"c/p2 has a second row" -- sj check
sj_rows "$_sj_h"
printf 'c/p4\t2\t%s\thttps://projects.intra.42.fr/projects/p4\t-\t2026-11-01\n' "$_sj_h" >> "$WORK/sj/tools/subjects.tsv"
want_out "subjects: a row for a folder this checkout lacks is reported" \
	"c/p4 is not a folder of this checkout" -- sj check
rm -f "$WORK/sj/tools/subjects.tsv"
want_out "subjects: and a missing registry" "tools/subjects.tsv is missing" -- sj check
