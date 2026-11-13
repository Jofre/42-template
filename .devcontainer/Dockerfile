# GDB, CAMPUS'S VERSION, BUILT FROM GNU'S SOURCE.
#
# The campus box runs GNU gdb 16.3 (a campus box, 2026-11-13, report ce9909df
# on origin/env-audit-42: "GNU gdb (GDB) 16.3", from a package "gdb 16.3-1"
# that is not Ubuntu's), and Ubuntu 22.04 has no gdb past 12.1, so apt cannot
# pin it. This stage builds that release from GNU's tarball, checked against
# GDB_SHA256, and the image below copies in the stripped gdb alone: the
# compilers and -dev packages it needs stay in this stage. A build with GNU's
# defaults prints exactly campus's version line, which is tools/pins.tsv's gdb
# row; //tools:conventions holds GDB_VERSION to that row. Under /usr/local, it
# still reads what Ubuntu's packages give a gdb under /usr: the debug files in
# /usr/lib/debug, and the scripts in /usr/share/gdb/auto-load, libstdc++'s
# pretty-printers among them. It is the image's slowest step (about 2.5
# minutes on 24 cores, longer on fewer), and Docker caches it until
# GDB_VERSION or GDB_SHA256 changes. To re-pin: take the version from a campus
# box's report, download gdb-<version>.tar.xz and its .sig from
# ftp.gnu.org/gnu/gdb, check the signature against GNU's keyring
# (ftp.gnu.org/gnu/gnu-keyring.gpg, with gpgv), compute the tarball's SHA-256
# yourself (GNU publishes none), and edit both ARGs and the row together.
FROM ubuntu:22.04 AS gdb-build
ENV DEBIAN_FRONTEND=noninteractive
ARG GDB_VERSION=16.3
ARG GDB_SHA256=bcfcd095528a987917acf9fff3f1672181694926cc18d609c99d0042c00224c5
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    wget \
    xz-utils \
    libgmp-dev \
    libmpfr-dev \
    libexpat1-dev \
    zlib1g-dev \
    libncurses-dev \
    python3-dev \
    && wget -q -O /tmp/gdb.tar.xz "https://ftp.gnu.org/gnu/gdb/gdb-${GDB_VERSION}.tar.xz" \
    && echo "${GDB_SHA256}  /tmp/gdb.tar.xz" | sha256sum -c - \
    && mkdir -p /tmp/gdb/build \
    && tar -xJf /tmp/gdb.tar.xz -C /tmp/gdb --strip-components=1 \
    && cd /tmp/gdb/build \
    && ../configure --prefix=/usr/local --disable-nls --disable-werror \
        --disable-sim --disable-gprofng --with-system-zlib --with-expat \
        --with-python=/usr/bin/python3 --without-debuginfod \
        --with-separate-debug-dir=/usr/lib/debug \
        '--with-auto-load-dir=$debugdir:$datadir/auto-load:/usr/share/gdb/auto-load' \
        '--with-auto-load-safe-path=$debugdir:$datadir/auto-load:/usr/share/gdb/auto-load' \
    && make -j"$(nproc)" \
    && make install-strip-gdb DESTDIR=/opt/gdb \
    && rm -f /opt/gdb/usr/local/share/man/man1/gdbserver.1

FROM ubuntu:22.04

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Configure environment variables — match the 42 campus box locale (en_US.UTF-8,
# generated below; see tools/env-audit.sh reports).
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# WHICH PACKAGES CARRY A VERSION, and which deliberately do not.
#
# tools/pins.tsv calls itself "the single statement of which tool versions this
# repo expects" and names THIS FILE as a pin site: the only one for gdb and
# lldb-12, beside MODULE.bazel's fetched .debs for gcc-10, clang-12,
# binutils (ar, nm, ...), make and valgrind, and beside
# tools/requirements.txt for norminette's pip install (further down).
# It said so while every package here was installed unversioned, so the audit
# and the image disagreed: pins.tsv recorded clang 12.0.1-19ubuntu3 and the
# image installed whatever jammy served on the day it was built.
#
# So every package pins.tsv names this file as a pin site of is pinned here,
# with the version pins.tsv records (gdb as GDB_VERSION, the release the
# gdb-build stage builds, since Ubuntu has no campus gdb to pin); where
# MODULE.bazel also fetches it,
# at the revision MODULE.bazel fetches (tools/conventions.sh holds the two
# together; g++-10 goes with gcc-10). pins.tsv also records rows it marks NOT
# PINNED, observed only: glibc, perl, and the shell piscine's tools (the note
# below says why those stay unversioned for now). The rest are not pinned, on
# purpose -- an editor's language server, a pager and a manual-page reader
# decide no verdict, and a pin costs a re-pin every time Ubuntu moves it.
#
# WHEN A PIN STOPS RESOLVING. Ubuntu supersedes a package and drops the old
# version from archive.ubuntu.com, and this image stops building with
# "Version '<x>' for '<pkg>' was not found". That failure is the point: the
# alternative is a silent upgrade of the compiler the whole suite is calibrated
# against. Fix it by running `bazel run //tools:env_drift` on a CAMPUS box,
# taking the version it reports, and editing this file, tools/pins.tsv and,
# for a package MODULE.bazel fetches too, its deb_archive URLs and sha256
# together -- which is the same procedure pins.tsv's own header describes.
#
# NOT PINNED, AND WHY IT IS NOT AN OVERSIGHT: the shell piscine's tools --
# bash, openssh-client, file, bc, net-tools, iproute2, findutils, tar, patch
# and git -- feed shell-piscine outputs, and several of the checks run them,
# so a version could in principle move a verdict. The second campus audit
# (report 90da4ff6, 2026-10-13) observed each one's version line, the line
# this image prints too, and tools/pins.tsv holds those lines as campus rows
# (observed, not pinned), so env_drift reports a campus move. What it did not
# record is each package's revision, which an apt pin here needs, and pinning
# to whatever this container happens to carry would record a revision nobody
# measured on the box that matters. tools/env-audit.sh records the revisions
# ("tool packages") from the next audit on; pin them from that report.
#
# Re-enable manual pages installation and install development tools
RUN rm -f /etc/dpkg/dpkg.cfg.d/excludes \
    && apt-get update && apt-get install -y --no-install-recommends \
    # Compile / build / test toolchain. gcc-10 + clang-12 mirror the 42 campus box
    # (its `gcc` is 10.5, its `cc` is clang-12); g++-10 gives gcc-10 its libstdc++ so
    # the gcc-10 Bazel config links. build-essential (gcc-11) and clang(-14) stay for
    # the editor/clangd. The update-alternatives block below repoints cc/gcc/clang.
    build-essential \
    gcc-10=10.5.0-1ubuntu1~22.04.3 \
    g++-10=10.5.0-1ubuntu1~22.04.3 \
    clang-12=1:12.0.1-19ubuntu3 \
    clang \
    # binutils, named explicitly rather than left to build-essential: this is
    # the copy a student gets by typing `nm` or `ar`, at campus's version. No
    # test runs it: pins.tsv's `nm`, `ar` and `ranlib` are the Bazel-fetched
    # ones, which the forbidden-symbol layer and a Makefile's recipes run.
    binutils=2.38-4ubuntu2.12 \
    # clangd: language server for the vscode-clangd / Open VSX extension, so the
    # editor never has to prompt to download it (matches the clang 14 toolchain).
    clangd \
    make=4.3-4.1build1 \
    valgrind=1:3.18.1-1ubuntu2 \
    # The debuggers. Neither is part of the Piscine and no test layer uses them,
    # but a campus box carries gdb AND lldb, and this container is supposed to
    # reproduce a campus box -- so a student following along with either one
    # should not find it missing here. lldb-12 rather than the default lldb, to
    # match the clang-12 the box ships and this image already pins. gdb is
    # campus's 16.3, built in the gdb-build stage at the top and copied in
    # below; these are the libraries it loads (ldd), unpinned like any library.
    lldb-12=1:12.0.1-19ubuntu3 \
    libgmp10 \
    libmpfr6 \
    libexpat1 \
    zlib1g \
    libncursesw6 \
    libtinfo6 \
    libpython3.10 \
    wget \
    ca-certificates \
    locales \
    # norminette (the 42 C style checker) is a pure-Python pip package
    python3 \
    python3-pip \
    # Version control + Vogsphere submission over SSH
    git \
    openssh-client \
    # Manual pages (man 2/3 are genuinely useful while learning C). The
    # pages glibc lacks, strlcpy(3bsd), strlcat(3bsd) and strnstr(3bsd), come
    # in below.
    man-db \
    manpages \
    manpages-dev \
    manpages-posix \
    manpages-posix-dev \
    # Used by the shell-piscine exercises and their tests
    file \
    net-tools \
    iproute2 \
    bc \
    shellcheck \
    # Editors for a terminal-only workflow
    vim \
    nano \
    && apt-get install --reinstall -y \
    coreutils \
    findutils \
    tar \
    patch \
    bash \
    && (rm -f /usr/bin/man || true) \
    && (dpkg-divert --quiet --remove --rename /usr/bin/man || true) \
    && rm -rf /var/lib/apt/lists/*

# gdb, from the gdb-build stage at the top: the binary, its Python modules,
# syscall tables and manual pages, under /usr/local.
COPY --from=gdb-build /opt/gdb/usr/local/ /usr/local/

# THE strlcpy(3bsd), strlcat(3bsd) AND strnstr(3bsd) MANUAL PAGES, AND NOTHING
# ELSE OF libbsd.
#
# C 02 ex10 and C 03 ex05 ask for ft_strlcpy and ft_strlcat, and Libft for
# both and for ft_strnstr; the manual page is where their contract is written
# down. glibc 2.35 has none of the three functions, so on Ubuntu 22.04 their
# pages ship only in libbsd-dev, in section 3bsd -- and `man strlcpy` here
# said "No manual entry" (finding 054).
#
# Installing libbsd-dev would also install <bsd/string.h> and a libbsd to link
# against, and code that includes or links them would build here and not on a
# campus box without them. So the pages are taken out of the package and
# nothing else is: strlcpy's, which documents both strlcpy and strlcat;
# strlcat's, which is a link to it; and strnstr's. `man 3bsd strlcpy` and `man
# 3bsd strnstr` then open, while the header and -lbsd do not exist here.
# Never add libbsd-dev or libbsd0 to the apt list above; //tools:conventions
# refuses it, and asks for the page of every such function a contract turns
# in.
#
# One .deb for every architecture: a manual page is text, the same in the
# amd64 package as in the arm64 one. The version is tools/pins.tsv's
# libbsd-dev row, which //tools:conventions holds this ARG to. Ubuntu keeps
# the file in the archive while 22.04 is supported, and on old-releases after.
ARG LIBBSD_DEV_VERSION=0.11.5-1
ARG LIBBSD_DEV_SHA256=16f20fc8f05bdb68b0db046a4f91dfe664d91409bc4e196b302ab5432bce5022
RUN DEB="libbsd-dev_${LIBBSD_DEV_VERSION}_amd64.deb" \
    && for MIRROR in http://archive.ubuntu.com/ubuntu http://old-releases.ubuntu.com/ubuntu; do \
         wget -q -O /tmp/libbsd-dev.deb "$MIRROR/pool/main/libb/libbsd/$DEB" && break; \
       done \
    && echo "$LIBBSD_DEV_SHA256  /tmp/libbsd-dev.deb" | sha256sum -c - \
    && dpkg-deb --fsys-tarfile /tmp/libbsd-dev.deb \
       | tar -x -C / ./usr/share/man/man3/strlcpy.3bsd.gz ./usr/share/man/man3/strlcat.3bsd.gz \
         ./usr/share/man/man3/strnstr.3bsd.gz \
    && rm -f /tmp/libbsd-dev.deb

# Install Norminette (the 42 coding style checker)
# Pinned, not floating. norminette's version decides which rules exist, so an
# unpinned install means a devcontainer rebuilt next month can start rejecting
# code that passed today -- or accepting code the campus box rejects. 3.3.58 is
# what the campus audit matched. This copy is for running norminette BY HAND in
# the shell; the Bazel norm layer takes its own pinned copy (see MODULE.bazel)
# and never this one. Both are tools/requirements.txt's version, and
# tools/conventions.sh holds the two together: re-pin them as one.
RUN pip3 install --no-cache-dir norminette==3.3.58

# Reading the subjects. Every project's subject is a PDF kept beside it (on a fresh
# clone of the public template, a SUBJECT-PLACEHOLDER.pdf says which one to fetch), and
# this container is terminal-only -- there is no viewer, so without something
# here the one document a student MUST read is the one they cannot open.
#
# pypdf rather than poppler-utils: it is a pure-Python wheel, so it pins to an
# exact version like norminette above instead of following whatever jammy
# currently ships, and it needs no C toolchain of its own.
#
#     python3 -c 'import sys,pypdf; print("\n".join(p.extract_text() for p in pypdf.PdfReader(sys.argv[1]).pages))' c-piscine/c-piscine-bsq/en.subject.pdf
#
# Deliberately NOT in tools/requirements.txt: that file is the hermetic build's
# Python environment, and nothing the harness runs reads a PDF. This is for the
# human at the terminal, so it belongs to the image and not to the build.
RUN pip3 install --no-cache-dir pypdf==6.14.2

# Match the 42 campus toolchain exactly: generate its locale and repoint the
# compiler commands to the versions on the box (cc -> clang-12, gcc -> gcc-10.5,
# clang -> clang-12), so a student compiling by hand gets the campus pair. Bazel
# builds with the clang-12 and gcc-10 it fetches (//tools/cc_toolchain,
# MODULE.bazel), whatever cc is here; the few layers that still take a compiler
# from the box are listed in docs/environment.md.
RUN locale-gen en_US.UTF-8 \
    && update-alternatives --install /usr/bin/cc cc /usr/bin/clang-12 100 \
    && update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 100 \
    && update-alternatives --install /usr/bin/clang clang /usr/bin/clang-12 100 \
    && update-alternatives --set cc /usr/bin/clang-12 \
    && update-alternatives --set gcc /usr/bin/gcc-10 \
    && update-alternatives --set clang /usr/bin/clang-12

# Install Bazelisk (the Bazel launcher) for the build's target architecture.
# BuildKit fills TARGETARCH automatically (amd64 / arm64 — the same names bazelisk
# uses), so the right binary is selected for whatever platform is being built,
# independent of the host OS. Falls back to dpkg if TARGETARCH is ever unset
# (e.g. the legacy non-BuildKit builder).
# A PINNED VERSION AND A CHECKSUM, not `releases/latest`.
#
# tools/setup.sh installs the same launcher and says why in its own words: "a
# checksum is the only thing standing between 'we downloaded a launcher' and
# 'we downloaded and executed whatever that URL served today'". It then pins
# bazelisk v1.29.0 by sha256 -- while this file fetched `releases/latest` with
# no checksum at all, so the same repo installed a verified binary one way and
# an unverified moving target the other, and the two could be different
# versions on the same machine.
#
# The amd64 digest below is byte-identical to setup.sh's BAZELISK_SHA256, which
# is what makes the two agree rather than merely both being pinned;
# //tools:conventions checks that they still do.
#
# One digest per architecture, because the file differs per architecture and a
# single one would mean "verified on amd64, unverified everywhere else". An
# unknown TARGETARCH now stops the build instead of installing something no
# line here vouches for.
ARG TARGETARCH
ARG BAZELISK_VERSION=v1.29.0
ARG BAZELISK_SHA256_AMD64=5a408715e932c0250d28bd84555f12edbf70117de42f9181691c736eacc4a992
ARG BAZELISK_SHA256_ARM64=e20e8b0f4f240091b7a55bf17b9398bd4f40ee70ae0208dff95dd4c445fb4010
RUN ARCH="${TARGETARCH:-$(dpkg --print-architecture)}" \
    && case "$ARCH" in \
         amd64) WANT="$BAZELISK_SHA256_AMD64" ;; \
         arm64) WANT="$BAZELISK_SHA256_ARM64" ;; \
         *) echo "no pinned bazelisk digest for architecture '$ARCH'" >&2; exit 1 ;; \
       esac \
    && wget -O /usr/local/bin/bazel \
        "https://github.com/bazelbuild/bazelisk/releases/download/${BAZELISK_VERSION}/bazelisk-linux-${ARCH}" \
    && echo "$WANT  /usr/local/bin/bazel" | sha256sum -c - \
    && chmod +x /usr/local/bin/bazel

# Install buildifier (the Bazel BUILD/.bzl formatter + linter) so the BazelBuild
# editor extension finds it on PATH instead of prompting for a manual download.
# Same TARGETARCH-aware pattern, same pinning, same reason as bazelisk above.
#
# v8.5.1 is the buildifier inside buildifier_prebuilt 8.5.1.3, the version
# MODULE.bazel already pins -- so the copy on PATH and the copy
# //tools:conventions runs (@buildifier_prebuilt//:buildifier) are the same
# formatter. They were not: this one floated.
ARG BUILDIFIER_VERSION=v8.5.1
ARG BUILDIFIER_SHA256_AMD64=887377fc64d23a850f4d18a077b5db05b19913f4b99b270d193f3c7334b5a9a7
ARG BUILDIFIER_SHA256_ARM64=947bf6700d708026b2057b09bea09abbc3cafc15d9ecea35bb3885c4b09ccd04
RUN ARCH="${TARGETARCH:-$(dpkg --print-architecture)}" \
    && case "$ARCH" in \
         amd64) WANT="$BUILDIFIER_SHA256_AMD64" ;; \
         arm64) WANT="$BUILDIFIER_SHA256_ARM64" ;; \
         *) echo "no pinned buildifier digest for architecture '$ARCH'" >&2; exit 1 ;; \
       esac \
    && wget -O /usr/local/bin/buildifier \
        "https://github.com/bazelbuild/buildtools/releases/download/${BUILDIFIER_VERSION}/buildifier-linux-${ARCH}" \
    && echo "$WANT  /usr/local/bin/buildifier" | sha256sum -c - \
    && chmod +x /usr/local/bin/buildifier

# Create a non-root user with sudo access. The name is parameterised so the
# environment isn't tied to any one editor; UID/GID 1000 matches the typical host
# user for clean bind-mount permissions.
ARG USERNAME=student
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && apt-get update \
    && apt-get install -y sudo \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME \
    && rm -rf /var/lib/apt/lists/*

# Two supplementary groups for the user, created for the purpose and granting
# nothing (they own no file and appear in no sudoers or policy file). Shell 01
# ex01 prints a user's groups joined by commas, and a list of one group has no
# comma in it: with `student` in its own group alone, a print_groups.sh that
# printed the primary group only, or joined names with anything at all, passed
# in the supported environment (finding 025). The check does not rely on
# this -- it asks //oracle for a user in two groups or more, and says it could
# not observe the join where there is none -- but here there is one.
RUN groupadd cohort \
    && groupadd cluster \
    && usermod -a -G cohort,cluster "$USERNAME"

# Default shell to bash for the user.
RUN chsh -s /bin/bash "$USERNAME"

# Run as the non-root user by default, so plain `docker run` behaves the same as
# VS Code / the devcontainer CLI (which honour remoteUser) — no editor required.
USER $USERNAME

# Set working directory inside container
WORKDIR /workspaces
