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
# repo expects" and names THIS FILE as the pin site for cc, ar, gdb and lldb-12.
# It said so while every package here was installed unversioned, so the audit
# and the image disagreed: pins.tsv recorded clang 12.0.1-19ubuntu3 and the
# image installed whatever jammy served on the day it was built.
#
# So every package whose version pins.tsv records is pinned here, with the
# version pins.tsv records. The rest are not, on purpose -- an editor's
# language server, a pager and a manual-page reader decide no verdict, and a
# pin costs a re-pin every time Ubuntu moves it.
#
# WHEN A PIN STOPS RESOLVING. Ubuntu supersedes a package and drops the old
# version from archive.ubuntu.com, and this image stops building with
# "Version '<x>' for '<pkg>' was not found". That failure is the point: the
# alternative is a silent upgrade of the compiler the whole suite is calibrated
# against. Fix it by running `bazel run //tools:env_drift` on a CAMPUS box,
# taking the version it reports, and editing this file and tools/pins.tsv
# together -- which is the same procedure pins.tsv's own header describes.
#
# NOT PINNED, AND WHY IT IS NOT AN OVERSIGHT: bc, file, net-tools and iproute2
# feed shell-piscine outputs, so a version could in principle move a verdict.
# There is no CAMPUS observation of any of them -- the audit that produced
# pins.tsv did not capture them -- and pinning them to whatever this container
# happens to carry would record a number nobody measured on the box that
# matters. Recorded in TODO.md for the next campus audit instead.
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
    # binutils, named explicitly rather than left to build-essential: pins.tsv
    # pins `ar` and `nm` here, and a version this file never mentions is not a
    # pin. (The nm the forbidden-symbol layer runs is Bazel-fetched; this copy
    # is the one a student gets by typing `nm`.)
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
    # match the clang-12 the box ships and this image already pins.
    gdb=12.1-0ubuntu1~22.04.2 \
    lldb-12=1:12.0.1-19ubuntu3 \
    wget \
    ca-certificates \
    locales \
    # norminette (the 42 C style checker) is a pure-Python pip package
    python3 \
    python3-pip \
    # Version control + Vogsphere submission over SSH
    git \
    openssh-client \
    # Manual pages (man 2/3 are genuinely useful while learning C)
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

# Install Norminette (the 42 coding style checker)
# Pinned, not floating. norminette's version decides which rules exist, so an
# unpinned install means a devcontainer rebuilt next month can start rejecting
# code that passed today -- or accepting code the campus box rejects. 3.3.58 is
# what the campus audit matched. This copy is for running norminette BY HAND in
# the shell; the Bazel norm layer takes its own pinned copy (see MODULE.bazel)
# and never this one.
RUN pip3 install --no-cache-dir norminette==3.3.58

# Reading the subjects. Every module's subject is a PDF committed beside it, and
# this container is terminal-only -- there is no viewer, so without something
# here the one document a student MUST read is the one they cannot open.
#
# pypdf rather than poppler-utils: it is a pure-Python wheel, so it pins to an
# exact version like norminette above instead of following whatever jammy
# currently ships, and it needs no C toolchain of its own.
#
#     python3 -c 'import sys,pypdf; print("\n".join(p.extract_text() for p in pypdf.PdfReader(sys.argv[1]).pages))' c-piscine-bsq/en.subject.pdf
#
# Deliberately NOT in tools/requirements.txt: that file is the hermetic build's
# Python environment, and nothing the harness runs reads a PDF. This is for the
# human at the terminal, so it belongs to the image and not to the build.
RUN pip3 install --no-cache-dir pypdf==6.14.2

# Match the 42 campus toolchain exactly: generate its locale and repoint the
# compiler commands to the versions on the box (cc -> clang-12, gcc -> gcc-10.5,
# clang -> clang-12). Bazel is additionally pinned to clang-12 via /.bazelrc, and
# the per-exercise *_compile_gcc tests invoke gcc-10 directly.
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
# MODULE.bazel already pins -- so the copy on PATH and the copy `bazel run
# //:buildifier` uses are the same formatter. They were not: this one floated.
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

# Default shell to bash for the user.
RUN chsh -s /bin/bash "$USERNAME"

# Run as the non-root user by default, so plain `docker run` behaves the same as
# VS Code / the devcontainer CLI (which honour remoteUser) — no editor required.
USER $USERNAME

# Set working directory inside container
WORKDIR /workspaces
