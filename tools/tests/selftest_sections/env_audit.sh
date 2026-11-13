# ------------------------------------------------------------------ env-audit
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The campus report, which decisions wait on (D7: gathered, not guessed).
# Until now no arm ran it at all. It runs in a sandbox repository, where it
# writes its report and nothing else, with two facts set the way a campus box
# would set them: a timezone off UTC, given as a POSIX TZ string (no zone
# database needed), and a manual path holding strlcpy's page in section 3bsd
# (and strnstr's, Libft's), beside one holding none -- the two answers the
# report must tell apart. Where this machine has no `man` at all, both say
# "(no page)", which is then the true report.
# conventions: optional man -- only to know which answer the report owes
mkdir -p "$WORK/ea/tools" "$WORK/ea/home" "$WORK/ea/man/man3" "$WORK/ea/noman"
cp "$TOOLS/env-audit.sh" "$TOOLS/drives.sh" "$TOOLS/prime_trace.sh" "$WORK/ea/tools/"
# Two prime traces (tools/prime_trace.sh): one that finished, and one with no
# END from an earlier boot -- the shape a freeze leaves. And one with no END
# from ANOTHER machine, which $HOME may have brought here: it may be running
# there still, so this machine's boot says nothing about it.
ea_dir() {  # ea_dir HOST -- where the library puts HOST's traces
	env HOME="$WORK/ea/home" XDG_STATE_HOME="$WORK/ea/state" C_PISCINE_HOST="$1" \
		"$SH" -c '. "$1" && printf "%s" "$TRACE_DIR"' sh "$TOOLS/prime_trace.sh"
}
_eat=$(ea_dir ea-this-host)
_eao=$(ea_dir ea-other-host)
mkdir -p "$_eat" "$_eao"
# Its pressure figures are a box's whose cpu `full` line is always 0 (the
# system-wide one is), while `some` climbs: the summary keeps both.
printf '42-piscine prime trace 1\nmode background\nboot ea-earlier-boot\nS up=10 memavail=900 swapfree=50 pswpin=0 pswpout=0 pgmajfault=0 bazel_rss=7:100 psi_cpu=some:10.00/full:0.00\nS up=15 memavail=300 swapfree=40 pswpin=5 pswpout=500 pgmajfault=10 bazel_rss=7:2500 psi_cpu=some:90.00/full:0.00\n' \
	> "$_eat/trace-000001"
printf '42-piscine prime trace 1\nmode foreground\nboot ea-this-boot\nS up=1 memavail=800\nEND rc=0\n' \
	> "$_eat/trace-000002"
printf '42-piscine prime trace 1\nmode background\nboot ea-other-boot\nS up=4 memavail=600\n' \
	> "$_eao/trace-000007"
printf 'norminette\tcampus\t9.9.9\tnorminette-version\ttools/requirements.txt\n' > "$WORK/ea/tools/pins.tsv"
printf '.TH STRLCPY 3bsd\n.SH NAME\nstrlcpy, strlcat \\- a toy page\n' > "$WORK/ea/man/man3/strlcpy.3bsd"
ln -s strlcpy.3bsd "$WORK/ea/man/man3/strlcat.3bsd"
printf '.TH STRNSTR 3bsd\n.SH NAME\nstrnstr \\- a toy page\n' > "$WORK/ea/man/man3/strnstr.3bsd"
git init -q "$WORK/ea"
# The scratch folder too is the sandbox's, and absent: the report tails the
# prime.log it finds there and runs du over its caches, and on a box with a
# /goinfre of its own that was the box's real log and real caches, up to 30 s
# of du each on the disk this audit exists to watch. The drives a scratch is
# chosen from are named absent as well, and du gets 1 s. An arm hands it a
# /goinfre of its own through EA_ST_GOINFRE, and drops the scratch with an
# empty EA_ST_SCRATCH: an exported C_PISCINE_GOINFRE is overridden by env's
# own, and the stand-in below once never reached the script that way.
# Neither comes from the shell that started this file.
unset EA_ST_GOINFRE EA_ST_SCRATCH
ea_run() {  # ea_run MANPATH -- the report, as the script prints it
	( cd "$WORK/ea" && env HOME="$WORK/ea/home" BUILD_WORKSPACE_DIRECTORY="$WORK/ea" \
		XDG_STATE_HOME="$WORK/ea/state" C_PISCINE_BOOT_ID=ea-this-boot \
		C_PISCINE_SCRATCH="${EA_ST_SCRATCH-$WORK/ea/plain-scratch}" \
		C_PISCINE_GOINFRE="${EA_ST_GOINFRE:-$WORK/ea/no-goinfre}" \
		C_PISCINE_SGOINFRE="$WORK/ea/no-sgoinfre" C_PISCINE_LEGACY_ROOT="$WORK/ea/no-legacy" \
		EA_DU_SECONDS=1 C_PISCINE_HOST=ea-this-host TZ=XYZ-14 MANPATH="$1" \
		"$SH" tools/env-audit.sh )
}
# The second report runs as on a box that has a /goinfre with a prime.log in
# it: a stand-in for /goinfre (EA_ST_GOINFRE), holding the user's folder,
# which drives_user names from USER. The third, the control, drops the
# scratch too, so the stand-in is where the scratch is chosen and its
# prime.log is read: it proves the second report's stand-in arrived.
mkdir -p "$WORK/ea/host-goinfre/ea-host-user"
printf 'ea host: a prime.log the sandbox must not read\n' \
	> "$WORK/ea/host-goinfre/ea-host-user/prime.log"
if st_mine; then
	ea_run "$WORK/ea/man" > "$WORK/ea.page" 2>&1
	( EA_ST_GOINFRE="$WORK/ea/host-goinfre"; USER=ea-host-user
	  export EA_ST_GOINFRE USER
	  ea_run "$WORK/ea/noman" ) > "$WORK/ea.nopage" 2>&1
	( EA_ST_GOINFRE="$WORK/ea/host-goinfre"; EA_ST_SCRATCH=""; USER=ea-host-user
	  export EA_ST_GOINFRE EA_ST_SCRATCH USER
	  ea_run "$WORK/ea/noman" ) > "$WORK/ea.control" 2>&1
fi
want_out "env-audit: its scratch folder is the sandbox's" \
	"$(printf '%-22s %s' scratch: "$WORK/ea/plain-scratch")" -- cat "$WORK/ea.nopage"
want_broken_none "env-audit: ...never a /goinfre of the box's" \
	'ea host: a prime.log' -- cat "$WORK/ea.nopage"
want_out "env-audit: the stand-in /goinfre reaches the script (control)" \
	'ea host: a prime.log' -- cat "$WORK/ea.control"
# strlcat's page is a link to strlcpy's. man-db answers with the link's
# target (measured: .../strlcpy.3bsd), another man may name the link
# itself, so its arm asks for a page of this toy path, either one, and
# never "(no page)": the prefix alone also matched a lookup that failed.
_ea_page="$WORK/ea/man/man3/strlcpy.3bsd"
_ea_cat="$WORK/ea/man/man3/strlc"
_ea_nstr="$WORK/ea/man/man3/strnstr.3bsd"
command -v man > /dev/null 2>&1 || { _ea_page="(no page)"; _ea_cat="(no page)"; _ea_nstr="(no page)"; }
want_out "env-audit: strlcpy's page in section 3bsd, where it is" \
	"man -w 3bsd strlcpy:   $_ea_page" -- cat "$WORK/ea.page"
want_out "env-audit: ...and strlcat's, a link to it" \
	"man -w 3bsd strlcat:   $_ea_cat" -- cat "$WORK/ea.page"
want_out "env-audit: ...said absent where it is not" \
	'man -w 3bsd strlcpy:   (no page)' -- cat "$WORK/ea.nopage"
want_out "env-audit: ...and strnstr's, Libft's, where it is" \
	"man -w 3bsd strnstr:   $_ea_nstr" -- cat "$WORK/ea.page"
want_out "env-audit: the UTC offset, beside the zone" \
	'UTC offset:            +1400' -- cat "$WORK/ea.page"
want_out "env-audit: ...the drives Bazel's state can use" \
	'setup.sh would choose:' -- cat "$WORK/ea.page"
want_out "env-audit: ...the memory limits" '### Memory limits' -- cat "$WORK/ea.page"
want_out "env-audit: ...how the box behaves under memory pressure" \
	'### Memory pressure and I/O' -- cat "$WORK/ea.page"
want_out "env-audit: ...a prime trace that stopped with the machine" \
	'trace-000001:          did not finish, and the machine restarted since' -- cat "$WORK/ea.page"
want_out "env-audit: ...one that finished" \
	'trace-000002:          finished (rc=0)' -- cat "$WORK/ea.page"
want_out "env-audit: ...another machine's traces, under its name" \
	"$(printf '%-22s %s' machine: ea-other-host)" -- cat "$WORK/ea.page"
want_out "env-audit: ...whose unfinished one this boot cannot judge" \
	'trace-000007:          no END, from another machine' -- cat "$WORK/ea.page"
want_out "env-audit: ...the lowest memory a trace saw" \
	'lowest MemAvailable 300 kB' -- cat "$WORK/ea.page"
want_out "env-audit: ...its swap rate" '100 out' -- cat "$WORK/ea.page"
# The packages behind the shell tools' version lines, which pins.tsv's
# observed rows need to become apt pins. The label only: what dpkg-query
# names is the host's, and a check does not depend on the host.
want_out "env-audit: ...the shell tools' packages, by name" \
	'tool packages:' -- cat "$WORK/ea.page"
want_out "env-audit: ...a Bazel server's peak memory" \
	'peak RSS of Bazel server 7: 2500 kB' -- cat "$WORK/ea.page"
want_out "env-audit: ...whether python3's curses imports" 'python3 curses:' -- cat "$WORK/ea.page"
# The tools the dev container installs unpinned for the shell exercises, which
# wait on a campus observation before they can be pinned: a line each, whether
# or not this machine has the tool (it then says "(not installed)").
for _ea_tool in bc file netstat ip; do
	want_out "env-audit: ...a version line for $_ea_tool" \
		"$(printf '%-22s' "$_ea_tool:")" -- cat "$WORK/ea.page"
done
# And the text tools every runner takes from the box, unpinned
# (tools/pins.tsv, THE BOX'S TEXT TOOLS): which file the awk on PATH
# resolves to, as this machine resolves it, then a line each for awk's,
# sed's, grep's and coreutils' versions and one for their packages.
_ea_awk=$(command -v awk)
want_out "env-audit: ...the file awk resolves to" \
	"$(printf '%-22s %s -> %s' awk: "$_ea_awk" "$(readlink -f "$_ea_awk")")" -- cat "$WORK/ea.page"
for _ea_tool in 'awk version' sed grep coreutils 'text tool packages'; do
	want_out "env-audit: ...a line for $_ea_tool" \
		"$(printf '%-22s' "$_ea_tool:")" -- cat "$WORK/ea.page"
done
# And the two download tools, which nothing installs or pins: a line each
# says which of them the box has, the question the report is asked about them.
for _ea_tool in curl wget; do
	want_out "env-audit: ...a version line for $_ea_tool" \
		"$(printf '%-22s' "$_ea_tool:")" -- cat "$WORK/ea.page"
done
want_out "env-audit: ...and it wrote its report in the checkout" \
	"report written to: $WORK/ea/tools/env-reports/" -- cat "$WORK/ea.page"
# The machine's name is the one prime_trace.sh gives it (C_PISCINE_HOST
# first), the name its traces are kept under: the report's file, its host
# row and its machine row all say it. The audit had a rule of its own, which
# ignored the knob, so one report named the box two ways.
want_green "env-audit: ...named for the machine, by prime_trace.sh's rule" -- \
	test -f "$WORK/ea/tools/env-reports/ea-this-host.txt"
want_out "env-audit: ...whose host row is its traces' machine" \
	"$(printf '%-22s %s' host: ea-this-host)" -- cat "$WORK/ea.page"
# A row that is no version banner keeps every line: a quota(1) that finds a
# quota prints a banner, a column header, then the figures, and a row cut
# at two lines kept the headers and dropped every number. A stand-in quota
# first on PATH says so for a toy filesystem.
mkdir -p "$WORK/ea/rows-bin"
{
	printf '#!/bin/sh\n'
	printf 'echo "Disk quotas for user ea (uid 7):"\n'
	printf 'echo "     Filesystem   space   quota   limit   grace   files   quota   limit   grace"\n'
	printf 'echo "       /dev/ea1   1234M  5000M  6000M              42       0       0"\n'
} > "$WORK/ea/rows-bin/quota"
chmod +x "$WORK/ea/rows-bin/quota"
# The same run stands in for three more of the box's facts. A cgroup v1
# box: no 0:: line, its memory controller's limit in a tree of its own
# (EA_CGROUP_ROOT), which the v1 row read from the host's /sys/fs/cgroup
# instead. A /bin/sh that is not dash, with dash installed too: the sh row
# gave it dash's package version. And a python3 that does not answer: the
# inotify row ran it anyway and kept whatever came back, the shell's own
# "not found" and a line number of the script on a box with none.
mkdir -p "$WORK/ea/cgv1/memory"
printf '271828182\n' > "$WORK/ea/cgv1/memory/memory.limit_in_bytes"
printf '5:memory:/ea.slice\n1:name=systemd:/ea.slice\n' > "$WORK/ea/cgv1.self"
_ea_rl=$(command -v readlink)
_ea_dq=$(command -v dpkg-query || :)
{
	printf '#!/bin/sh\n'
	printf 'case "$*" in "-f /bin/sh") echo /usr/bin/ea-bash; exit 0 ;; esac\n'
	printf 'exec %s "$@"\n' "$_ea_rl"
} > "$WORK/ea/rows-bin/readlink"
{
	printf '#!/bin/sh\n'
	printf 'case "$*" in *" dash") printf " 0.5.99-ea"; exit 0 ;; esac\n'
	if [ -n "$_ea_dq" ]; then printf 'exec %s "$@"\n' "$_ea_dq"; else printf 'exit 1\n'; fi
} > "$WORK/ea/rows-bin/dpkg-query"
printf '#!/bin/sh\nexit 127\n' > "$WORK/ea/rows-bin/python3"
chmod +x "$WORK/ea/rows-bin/readlink" "$WORK/ea/rows-bin/dpkg-query" "$WORK/ea/rows-bin/python3"
! st_mine || ( PATH="$WORK/ea/rows-bin:$PATH" EA_CGROUP_ROOT="$WORK/ea/cgv1" \
	EA_CGROUP_SELF="$WORK/ea/cgv1.self"; export PATH EA_CGROUP_ROOT EA_CGROUP_SELF
	ea_run "$WORK/ea/noman" ) > "$WORK/ea.rows" 2>&1
want_out "env-audit: a quota's figures, below its two headers" \
	'/dev/ea1   1234M' -- cat "$WORK/ea.rows"
want_out "env-audit: a cgroup v1 limit, from the tree it is given" \
	"$(printf '%-22s %s' 'cgroup (v1) memory limit:' '271828182 bytes')" -- cat "$WORK/ea.rows"
want_green "env-audit: a /bin/sh that is not dash, by its name and never dash's version" -- \
	grep -qxF "$(printf '%-22s %s' 'sh (/bin/sh):' ea-bash)" "$WORK/ea.rows"
want_out "env-audit: the inotify row, with no python3 to ask" \
	"$(printf '%-22s %s' 'inotify under $HOME:' '(python3 MISSING)')" -- cat "$WORK/ea.rows"
# With no scratch folder (a TMPDIR that is gone, a /tmp that is full) every
# probe writing to it failed, and its row read as a fact about the box; it
# says so and stops instead.
! st_mine || ( TMPDIR="$WORK/ea/no-tmpdir"; export TMPDIR; ea_run "$WORK/ea/noman" ) \
	> "$WORK/ea.notmp" 2>&1
ea_notmp() { cat "$WORK/ea.notmp"; }
want_out "env-audit: a scratch folder it cannot make is said" \
	'env-audit.sh: could not make a scratch folder' -- ea_notmp
want_broken_none "env-audit: ...with no probe row read as the box's" \
	'NOT supported' -- ea_notmp
# A checkout without tools/drives.sh, a user with no name: USER unset, and
# a stand-in id that knows uid 4242 and no name for it (a container run as
# --user 4242 with no passwd line). Every per-user path still ends in the
# uid, never in the shared folder itself: the disk row of the stand-in
# /goinfre's user folder (C_PISCINE_GOINFRE, as tools/drives.sh reads it),
# and the scratch.
mkdir -p "$WORK/ea-nn/tools" "$WORK/ea-nn/bin" "$WORK/ea-nn/goinfre/4242"
cp "$TOOLS/env-audit.sh" "$TOOLS/prime_trace.sh" "$WORK/ea-nn/tools/"
git init -q "$WORK/ea-nn"
printf '#!/bin/sh\ncase "$*" in\n\t-u) echo 4242 ;;\n\t*) echo "id: cannot find name for user ID 4242" >&2; exit 1 ;;\nesac\n' \
	> "$WORK/ea-nn/bin/id"
chmod +x "$WORK/ea-nn/bin/id"
! st_mine || ( cd "$WORK/ea-nn" && env -u USER -u C_PISCINE_SCRATCH \
	PATH="$WORK/ea-nn/bin:$PATH" HOME="$WORK/ea/home" BUILD_WORKSPACE_DIRECTORY="$WORK/ea-nn" \
	XDG_STATE_HOME="$WORK/ea/state" C_PISCINE_BOOT_ID=ea-this-boot \
	C_PISCINE_GOINFRE="$WORK/ea-nn/goinfre" EA_DU_SECONDS=1 C_PISCINE_HOST=ea-this-host \
	TZ=XYZ-14 MANPATH="$WORK/ea/noman" "$SH" tools/env-audit.sh ) > "$WORK/ea.noname" 2>&1
want_out "env-audit: no drives.sh, no user name: the user folder's disk, by uid" \
	"disk of $WORK/ea-nn/goinfre/4242:" -- cat "$WORK/ea.noname"
want_broken_none "env-audit: ...never the shared folder's, as the user's" \
	"disk of $WORK/ea-nn/goinfre/:" -- cat "$WORK/ea.noname"
want_out "env-audit: ...and the scratch, by uid" \
	"$(printf '%-22s %s' scratch: /tmp/4242)" -- cat "$WORK/ea.noname"
# A drive's PERSISTENCE line (tools/drives.sh, drives_describe) says what
# the filesystem's type can tell, and no more. A type that is neither
# RAM-backed nor network was printed as a "local disk": campus's home
# folder, xfs on a device of its own that may be a volume attached at
# login, read as one in the first campus report. The type comes from a
# toy df, so the arm is the same on every machine.
ea_describe() {  # ea_describe FSTYPE -- drives_describe, where df says FSTYPE
	"$SH" -c '
		_ea_fs=$2
		df() {
			case " $* " in
				*" -T "*) printf "%s\n" "Filesystem Type 1024-blocks Used Available Capacity Mounted on" \
					"/dev/toy $_ea_fs 2048 1024 1024 50% /toy" ;;
				*) printf "%s\n" "Filesystem 1024-blocks Used Available Capacity Mounted on" \
					"/dev/toy 2048 1024 1024 50% /toy" ;;
			esac
		}
		. "$1" && drives_describe "$3"' sh "$TOOLS/drives.sh" "$1" "$WORK/ea"
}
want_broken_none "env-audit: a drive neither RAM nor network is no 'local disk'" \
	'local disk' -- ea_describe xfs
want_out "env-audit: ...it is not a network filesystem by type" \
	'persistence: not a network filesystem by type' -- ea_describe xfs
want_out "env-audit: ...a tmpfs is RAM-backed" \
	'persistence: RAM-backed, gone at reboot' -- ea_describe tmpfs
want_out "env-audit: ...an nfs4 is a network filesystem" \
	'persistence: network filesystem, shared between machines' -- ea_describe nfs4
# A FUSE type was a network filesystem whatever its subtype, local ones too:
# fuse-overlayfs, which rootless containers use, keeps its files on a disk of
# this machine's. Only the subtypes that reach another machine by design are
# network ones; any other FUSE type says the type cannot tell. fuseblk is
# FUSE over a block device of this machine's (ntfs-3g), so it stays where a
# disk's type puts it.
want_broken_none "env-audit: a FUSE drive is no network one by its type alone" \
	'persistence: network filesystem' -- ea_describe fuse.fuse-overlayfs
want_out "env-audit: ...it may be local or network, it says" \
	'may be local or network' -- ea_describe fuse.fuse-overlayfs
want_out "env-audit: ...an sshfs is a network filesystem" \
	'persistence: network filesystem, shared between machines' -- ea_describe fuse.sshfs
# GlusterFS has no client in the kernel and CephFS has one in FUSE too, so
# both reach another machine by design under a fuse.* type: the arm that
# named ceph and gluster* missed their FUSE mounts once every fuse.* stopped
# being a network one.
want_out "env-audit: ...a GlusterFS FUSE mount is a network filesystem" \
	'persistence: network filesystem, shared between machines' -- ea_describe fuse.glusterfs
want_out "env-audit: ...and a ceph-fuse one too" \
	'persistence: network filesystem, shared between machines' -- ea_describe fuse.ceph-fuse
want_out "env-audit: ...and a fuseblk is not one by type" \
	'persistence: not a network filesystem by type' -- ea_describe fuseblk

# THE PROBES THAT UNDER-RECORDED on the first campus box (V248, V255, V263).
# Each is asked of a fake of its own, never of this machine: a grep over the
# report above passes on a box that has every tool and the plainest disks,
# and says nothing about the box that lacks one or stacks them.
#
# A tool the box lacks reads one fixed word. cap() used to print the shell's
# own error for it, which differs between dash and bash and carries a line
# number of cap's, so two reports of boxes lacking the same tool differed.
sed -n '/^cap(){/,/^}/p' "$TOOLS/env-audit.sh" > "$WORK/ea-cap.sh"
want_out "env-audit: a tool the box lacks reads (not installed)" \
	"$(printf '%-22s %s' probe: '(not installed)')" -- \
	"$SH" -c '. "$1"; cap probe ea-no-such-tool-x --version' sh "$WORK/ea-cap.sh"
want_broken_none "env-audit: ...never the shell's error for it" 'not found' -- \
	"$SH" -c '. "$1"; cap probe ea-no-such-tool-x --version' sh "$WORK/ea-cap.sh"
want_out "env-audit: ...and one that ran and printed nothing, (not available)" \
	"$(printf '%-22s %s' probe: '(not available)')" -- \
	"$SH" -c '. "$1"; cap probe true' sh "$WORK/ea-cap.sh"
# The reader for the rows that are not version banners keeps every line, up
# to a limit it says it reached.
sed -n '/^capall(){/,/^}/p' "$TOOLS/env-audit.sh" > "$WORK/ea-capall.sh"
want_out "env-audit: a long row says how many lines it cut" \
	'aaaa|bbbb (1 more line)' -- \
	"$SH" -c '. "$1"; EA_ROW_MAX=10 capall probe printf "aaaa\nbbbb\ncccc\n"' sh "$WORK/ea-capall.sh"

# The fakes. A toy tool under a usr/bin of its own, which answers --version
# the way dash does (an error, status 2); a dpkg that knows files only by
# their /bin spelling, as on a merged-/usr box, and prints dpkg-divert's
# lines first when asked to, and one file only past its links; a dpkg-query
# naming every package installed but patch, which it knows of and the box
# does not carry; a tool on PATH shadowing a system copy that is a link to a
# package's file, as update-alternatives makes; a pyenv shim beside the file
# pyenv selects; a df that puts every folder on a
# device-mapper volume and reports no inode count (as an NFS server does),
# with a findmnt and a sysfs under it whose disk has a scheduler of its own; a
# cgroup tree whose limits are set on an ancestor; a silent quota; a locale of
# three lines; a launcher, a docker and a clang-12 of the box's.
_eaf="$WORK/ea/fake/bin"
mkdir -p "$_eaf" "$WORK/ea/fake/root/usr/bin" "$WORK/ea/fake/dev/mapper" \
	"$WORK/ea/pyenv/shims" "$WORK/ea/pyenv/versions/9.9/bin"
printf '#!/bin/sh\necho "ea-toy: 0: Illegal option --" >&2\nexit 2\n' \
	> "$WORK/ea/fake/root/usr/bin/ea-toy"
printf '%s\n' '#!/bin/sh' '[ "$1" = -S ] || exit 2' 'case "$2" in' \
	'*/usr/bin/*) echo "dpkg-query: no path found matching pattern $2" >&2; exit 1 ;;' \
	'*/bin/ea-toy)' \
	'	[ -z "${EA_DPKG_DIVERT:-}" ] || printf "diversion by ea-other from: %s\ndiversion by ea-other to: %s.real\n" "$2" "$2"' \
	'	printf "ea-toy-pkg: %s\n" "$2" ;;' \
	'*/usr/lib/ea-alt/ea-alt) printf "ea-alt-pkg: %s\n" "$2" ;;' \
	'*) exit 1 ;;' 'esac' > "$_eaf/dpkg"
printf '%s\n' '#!/bin/sh' 'f=""' 'for a; do' '	case "$a" in' \
	'	-f=*) f=${a#-f=} ;;' '	-*) ;;' \
	'	patch) case "$f" in *Status*) echo "un |patch=" ;; *Package*) echo "patch=" ;; esac ;;' \
	'	*) case "$f" in *Status*) printf "ii |%s=1.0-ea\n" "$a" ;;' \
	'		*Package*) printf "%s=1.0-ea\n" "$a" ;; *) printf "1.0-ea" ;; esac ;;' \
	'	esac' 'done' > "$_eaf/dpkg-query"
_easr="$WORK/ea/fake/sysroot"
mkdir -p "$_easr/usr/bin" "$_easr/usr/lib/ea-alt"
printf '#!/bin/sh\necho "ea-alt 2.0"\n' > "$_easr/usr/lib/ea-alt/ea-alt"
ln -s ../lib/ea-alt/ea-alt "$_easr/usr/bin/ea-alt"
printf '#!/bin/sh\necho "ea-alt 1.0"\n' > "$_eaf/ea-alt"
chmod +x "$_easr/usr/lib/ea-alt/ea-alt"
printf '#!/bin/sh\necho "norminette 9.9.9"\n' > "$WORK/ea/pyenv/shims/norminette"
printf '#!/ea/pyenv/python9.9\n' > "$WORK/ea/pyenv/versions/9.9/bin/norminette"
printf '#!/bin/sh\n[ "$1" = which ] && [ -x "%s/$2" ] && { printf "%%s\\n" "%s/$2"; exit 0; }\nexit 1\n' \
	"$WORK/ea/pyenv/versions/9.9/bin" "$WORK/ea/pyenv/versions/9.9/bin" > "$_eaf/pyenv"
ln -s ../dm-0 "$WORK/ea/fake/dev/mapper/ea--vg-ea--lv"
printf '%s\n' '#!/bin/sh' 't=0; i=0' \
	'for a; do case "$a" in -T | -PT) t=1 ;; -i) i=1 ;; esac; done' \
	'echo "Filesystem 1024-blocks Used Available Capacity Mounted on"' \
	'if [ "$i" = 1 ]; then echo "ea-dev 0 0 0 - /"' \
	"elif [ \"\$t\" = 1 ]; then echo \"$WORK/ea/fake/dev/mapper/ea--vg-ea--lv ea-df-fs 1048576 524288 524288 50% /\"" \
	"else echo \"$WORK/ea/fake/dev/mapper/ea--vg-ea--lv 1048576 524288 524288 50% /\"; fi" > "$_eaf/df"
printf '#!/bin/sh\necho ea-findmnt-fs\n' > "$_eaf/findmnt"
_eas="$WORK/ea/sys"
mkdir -p "$_eas/class/block" "$_eas/devices/block/sdz/queue" "$_eas/devices/block/sdz/sdz3" \
	"$_eas/devices/virtual/block/dm-0/queue" "$_eas/devices/virtual/block/dm-0/slaves"
echo none > "$_eas/devices/virtual/block/dm-0/queue/scheduler"
echo 1 > "$_eas/devices/virtual/block/dm-0/queue/rotational"
echo '[mq-deadline] none' > "$_eas/devices/block/sdz/queue/scheduler"
echo 1 > "$_eas/devices/block/sdz/queue/rotational"
ln -s ../../../../block/sdz/sdz3 "$_eas/devices/virtual/block/dm-0/slaves/sdz3"
ln -s ../../devices/virtual/block/dm-0 "$_eas/class/block/dm-0"
ln -s ../../devices/block/sdz "$_eas/class/block/sdz"
ln -s ../../devices/block/sdz/sdz3 "$_eas/class/block/sdz3"
_eacg="$WORK/ea/cg"
mkdir -p "$_eacg/user.slice/user-7.slice/ea.scope"
for _ea_l in user.slice:max:max:max user.slice/user-7.slice:3141592653:max:777 \
	user.slice/user-7.slice/ea.scope:max:max:900; do
	_ea_d=${_ea_l%%:*}; _ea_v=${_ea_l#*:}
	echo "${_ea_v%%:*}" > "$_eacg/$_ea_d/memory.max"; _ea_v=${_ea_v#*:}
	echo "${_ea_v%%:*}" > "$_eacg/$_ea_d/memory.high"
	echo "${_ea_v#*:}" > "$_eacg/$_ea_d/pids.max"
done
echo '0::/user.slice/user-7.slice/ea.scope' > "$WORK/ea/cg.self"
printf '#!/bin/sh\nexit 0\n' > "$_eaf/quota"
printf '#!/bin/sh\n[ "$1" = -a ] && { echo C; exit 0; }\nprintf "LANG=ea\\nLANGUAGE=\\nLC_EA_THIRD=ea\\n"\n' > "$_eaf/locale"
printf '#!/bin/sh\necho "ea launcher"\n' > "$_eaf/bazelisk"
printf '#!/bin/sh\necho "ea other launcher"\n' > "$_eaf/bazel"
printf '#!/bin/sh\necho "ea docker"\n' > "$_eaf/docker"
printf '%s\n' '#!/bin/sh' 'case " $* " in' \
	'*" -v "*) echo "Selected GCC installation: /ea/gcc/x86_64-ea/12" >&2 ;;' \
	'*) echo "ea clang version 12.0.1" ;;' 'esac' > "$_eaf/clang-12"
chmod +x "$_eaf"/* "$WORK/ea/fake/root/usr/bin/ea-toy" "$WORK/ea/pyenv/shims/norminette" \
	"$WORK/ea/pyenv/versions/9.9/bin/norminette"
# setup.sh's pin of the launcher, read from setup.sh and never retyped: here
# a toy setup.sh whose pin is the fake bazelisk's bytes, so one launcher
# matches it and the other does not.
printf 'BAZELISK_VERSION=v0.0-ea\nBAZELISK_SHA256=%s\n' \
	"$(sha256sum "$_eaf/bazelisk" | cut -d' ' -f1)" > "$WORK/ea/tools/setup.sh"
# The prime's own log and caches, where the scratch puts them.
mkdir -p "$WORK/ea/scratch/bazel-disk" "$WORK/ea/scratch/bazel/cache/repos"
printf 'ea prime: the first line\nea prime: the last line\n' > "$WORK/ea/scratch/prime.log"
printf 'startup --output_user_root=%s\n' "$WORK/ea/scratch/bazel" > "$WORK/ea/.bazelrc.local"

# pin() alone, over the fakes.
sed -n '/^vline() {/,/^}/p; /^ea_ver() {/,/^}/p; /^ea_pkg() {/,/^}/p; /^ea_real() {/,/^}/p; /^pin() {/,/^}/p' \
	"$TOOLS/env-audit.sh" > "$WORK/ea-pin.sh"
ea_pin() {  # ea_pin CMD [VAR=VALUE] -- what pin() records for CMD among the fakes
	env ${2:+"$2"} PATH="$_eaf:$WORK/ea/fake/root/usr/bin:$WORK/ea/pyenv/shims:$PATH" \
		"$SH" -c '. "$1"; pin "$2"' sh "$WORK/ea-pin.sh" "$1"
}
want_out "env-audit: a merged-/usr tool's package, by its /bin name" \
	'pkg    ea-toy-pkg 1.0-ea' -- ea_pin ea-toy
want_out "env-audit: ...past dpkg-divert's lines" \
	'pkg    ea-toy-pkg 1.0-ea' -- ea_pin ea-toy EA_DPKG_DIVERT=1
want_out "env-audit: an error for --version is no version" \
	"$(printf '%-22s %s' ea-toy: '(no --version)')" -- ea_pin ea-toy
want_out "env-audit: a pyenv shim's pin is the file pyenv selects" \
	"path   $WORK/ea/pyenv/versions/9.9/bin/norminette" -- ea_pin norminette
want_out "env-audit: a system copy a tool on PATH shadows" \
	"SHADOWED: system copy at $_easr/usr/bin/ea-alt" -- ea_pin ea-alt EA_SYS_ROOT="$_easr"
want_out "env-audit: ...its package, found past its links" \
	"$(printf '%-22s     pkg     %s' '' ea-alt-pkg)" -- ea_pin ea-alt EA_SYS_ROOT="$_easr"

# The whole report, over the fakes.
if st_mine; then
	( cd "$WORK/ea" && env HOME="$WORK/ea/home" BUILD_WORKSPACE_DIRECTORY="$WORK/ea" \
		XDG_STATE_HOME="$WORK/ea/state" C_PISCINE_BOOT_ID=ea-this-boot \
		C_PISCINE_HOST=ea-this-host TZ=XYZ-14 MANPATH="$WORK/ea/noman" \
		PATH="$_eaf:$WORK/ea/pyenv/shims:$PATH" C_PISCINE_SYSFS="$_eas" \
		EA_CGROUP_ROOT="$_eacg" EA_CGROUP_SELF="$WORK/ea/cg.self" \
		C_PISCINE_SCRATCH="$WORK/ea/scratch" "$SH" tools/env-audit.sh ) \
		> "$WORK/ea.fake" 2>&1
fi
want_out "env-audit: the disk under a device-mapper volume, and its scheduler" \
	"$(printf '%-22s %s' '  under it, sdz3:' 'scheduler [mq-deadline] none, rotational 1')" -- cat "$WORK/ea.fake"
want_out "env-audit: ...the filesystem's type as findmnt names it" \
	"$WORK/ea/fake/dev/mapper/ea--vg-ea--lv (ea-findmnt-fs): scheduler none" -- cat "$WORK/ea.fake"
want_out "env-audit: ...a filesystem that reports no inode count, said so" \
	'inodes not reported by the filesystem' -- cat "$WORK/ea.fake"
want_out "env-audit: the smallest memory.max on the cgroup path, and where" \
	"$(printf '%-22s %s' '  lowest memory.max:' '3141592653 (the smallest, set by /user.slice/user-7.slice)')" \
	-- cat "$WORK/ea.fake"
want_out "env-audit: ...and pids.max" \
	"$(printf '%-22s %s' '  lowest pids.max:' '777 (the smallest, set by /user.slice/user-7.slice)')" \
	-- cat "$WORK/ea.fake"
want_out "env-audit: every line of a row that is not a banner" \
	'LANG=ea|LANGUAGE=|LC_EA_THIRD=ea' -- cat "$WORK/ea.fake"
# Green before the guard too: it guards that a present, silent tool is not
# called absent by it.
want_out "env-audit: a quota that ran and printed nothing" \
	"$(printf '%-22s %s' quota: '(not available)')" -- cat "$WORK/ea.fake"
want_out "env-audit: the norminette a pyenv shim runs" \
	"$WORK/ea/pyenv/shims/norminette -> $WORK/ea/pyenv/versions/9.9/bin/norminette" -- cat "$WORK/ea.fake"
want_out "env-audit: ...and that file's interpreter, not the shim's" \
	"$(printf '%-22s %s' interpreter: '#!/ea/pyenv/python9.9')" -- cat "$WORK/ea.fake"
want_out "env-audit: the launcher that matches setup.sh's bazelisk" \
	"matches setup.sh's BAZELISK_SHA256 (v0.0-ea)" -- cat "$WORK/ea.fake"
want_out "env-audit: ...and one that does not" \
	"not setup.sh's bazelisk (v0.0-ea)" -- cat "$WORK/ea.fake"
want_out "env-audit: whether docker is on PATH" \
	"$(printf '%-22s %s' docker: "$_eaf/docker")" -- cat "$WORK/ea.fake"
want_out "env-audit: ...and podman" "$(printf '%-22s' podman:)" -- cat "$WORK/ea.fake"
want_out "env-audit: the prime's own log, its tail" \
	'    ea prime: the last line' -- cat "$WORK/ea.fake"
want_out "env-audit: ...the disk cache's size" \
	"$(printf '%-22s %s' 'disk cache:' "$WORK/ea/scratch/bazel-disk")" -- cat "$WORK/ea.fake"
want_out "env-audit: ...the repository cache's" \
	"$(printf '%-22s %s' 'repository cache:' "$WORK/ea/scratch/bazel/cache/repos")" -- cat "$WORK/ea.fake"
# du is stopped at its bound, and says so: a du that would take 5 s, given 1.
sed -n '/^ea_du() {/,/^}/p' "$TOOLS/env-audit.sh" > "$WORK/ea-du.sh"
mkdir -p "$WORK/ea/slowdu" "$WORK/ea/dutmp"
printf '#!/bin/sh\nsleep 5\nprintf "9G\\t%%s\\n" "$2"\n' > "$WORK/ea/slowdu/du"
chmod +x "$WORK/ea/slowdu/du"
want_out "env-audit: ...a du past its bound, stopped and said so" \
	"$WORK/ea/scratch: (still counting after 1 s, stopped)" -- \
	env PATH="$WORK/ea/slowdu:$PATH" WORK="$WORK/ea/dutmp" EA_DU_SECONDS=1 \
		"$SH" -c '. "$1"; ea_du "$2"' sh "$WORK/ea-du.sh" "$WORK/ea/scratch"
# A du done before its bound ends the watchdog's sleep too: killing the
# watchdog alone left its sleep running out the whole bound, two a report.
# A stand-in sleep first on PATH writes down its pid and becomes the real
# one; once ea_du returns, that pid must be gone (and is ended if not). A
# stand-in du beside it returns only once that sleep has started (or after
# 5 s): a real du on an empty folder was often done before the watchdog
# had started its sleep, and the arm then had nothing to look at.
mkdir -p "$WORK/ea/dusleep"
printf '#!/bin/sh
echo "$$" > "%s"
exec "%s" "$@"
' "$WORK/ea/dusleep.pid" "$(command -v sleep)" \
	> "$WORK/ea/dusleep/sleep"
printf '#!/bin/sh
n=0
while [ ! -s "%s" ] && [ "$n" -lt 100 ]; do n=$((n + 1)); "%s" 0.05; done
printf "1K\\t%%s\\n" "$2"
' "$WORK/ea/dusleep.pid" "$(command -v sleep)" \
	> "$WORK/ea/dusleep/du"
chmod +x "$WORK/ea/dusleep/sleep" "$WORK/ea/dusleep/du"
ea_du_sleep() {
	rm -f "$WORK/ea/dusleep.pid"
	env PATH="$WORK/ea/dusleep:$PATH" WORK="$WORK/ea/dutmp" EA_DU_SECONDS=30 \
		"$SH" -c '. "$1"; ea_du "$2"' sh "$WORK/ea-du.sh" "$WORK/ea/scratch" > /dev/null 2>&1
	_eas_p=$(cat "$WORK/ea/dusleep.pid" 2> /dev/null)
	[ -n "$_eas_p" ] || { echo "the watchdog started no sleep"; return 2; }
	kill -0 "$_eas_p" 2> /dev/null || return 0
	kill "$_eas_p" 2> /dev/null
	echo "the watchdog's sleep ($_eas_p) outlived ea_du"
	return 1
}
want_green "env-audit: ...and one done early leaves no sleep running" -- ea_du_sleep
# A du done at once never waits out the bound. Under dash a signal that
# reaches a process forked a moment before, while it still carries its
# parent's trap, is lost: the watchdog's kill of a sleep it had just started
# went nowhere, and ea_du waited the whole bound behind that sleep, in two
# or three runs in a hundred. So 150 run at once, du a function done at
# once, and each must be back within 5 s of an 8 s bound. A watchdog that
# signals nothing ends by itself within a second of du.
ea_du_race() (
	_ear=$WORK/ea/durace
	rm -rf "$_ear"
	mkdir -p "$_ear" || return 2
	_i=0
	while [ "$_i" -lt 150 ]; do
		_i=$((_i + 1))
		mkdir "$_ear/$_i" || return 2
		{ env WORK="$_ear/$_i" EA_DU_SECONDS=8 "$SH" -c \
			'du() { printf "1K\t%s\n" "$2"; }; . "$1"; ea_du "$2"' \
			sh "$WORK/ea-du.sh" "$WORK/ea/scratch" > /dev/null 2>&1
		  : > "$_ear/$_i/back"; } > /dev/null 2>&1 &
	done
	_t=0
	while [ "$_t" -lt 100 ]; do
		set -- "$_ear"/*/back
		[ -e "$1" ] && [ "$#" -eq 150 ] && break
		sleep 0.05
		_t=$((_t + 1))
	done
	set -- "$_ear"/*/back
	[ -e "$1" ] || set --
	_eal=$((150 - $#))
	wait
	[ "$_eal" -eq 0 ] && return 0
	echo "$_eal of 150 ea_du calls on a du done at once were not back after 5 s"
	return 1
)
want_green "env-audit: ...nor one done at once, waiting out the bound" -- ea_du_race
want_out "env-audit: the GCC installation clang-12 selects" \
	'/ea/gcc/x86_64-ea/12' -- cat "$WORK/ea.fake"
want_out "env-audit: dash and zsh among the tool packages" \
	'dash=1.0-ea zsh=1.0-ea' -- cat "$WORK/ea.fake"
want_out "env-audit: ...and one dpkg knows the box lacks, said so" \
	'tar=1.0-ea patch=(not installed) git=1.0-ea' -- cat "$WORK/ea.fake"
# On the plain report: ld and as, which tools/pins.tsv pins, recorded.
want_green "env-audit: ld in the pin data" -- grep -q '^ld: ' "$WORK/ea.page"
want_green "env-audit: ...and as" -- grep -q '^as: ' "$WORK/ea.page"
# A prime trace's pressure, some and full apart: the cpu's full line is
# always 0, and printed as 0.00, not as nothing.
want_out "env-audit: a trace's cpu pressure, some and full" \
	'peak psi_cpu (avg10): some 90.00, full 0.00' -- cat "$WORK/ea.page"

