"""Fetch a Debian/Ubuntu .deb and extract its payload, using only Bazel.

WHY THIS EXISTS. The hermeticity rule here is that no check may depend on a tool
the host happens to carry -- a campus machine is not ours to configure, and a
check whose answer depends on which box you sat at is not a check. For the
compiler-adjacent tools that meant finding an upstream to pin, and the obvious
one (the official LLVM release tarball) costs ~400 MB and ships 12.0.0 where the
campus box runs Ubuntu's 12.0.1 build.

Ubuntu's own .deb is the better answer on both counts -- 2.2 MB for binutils, and
the EXACT build the Moulinette uses -- and the reason it was not the first answer
is that it looked impossible without adding tools:

  * a .deb is an `ar` archive containing data.tar.<compression>;
  * jammy compresses that inner tar with zstd;
  * and nothing in this repo or its devcontainer reads zstd. Checked: no `zstd`
    binary, `tar --zstd` fails with "Cannot exec", and Python 3.10 has neither
    `compression.zstd` (3.14+) nor `zstandard`.

It turns out Bazel does it alone. `ctx.extract` handles both layers -- `ar` for
the .deb, then zstd for the payload -- so this needs no zstd, no `ar`, and not
even the zig that ships with the ilp32 layer. Two calls and a BUILD file.

WHAT IT DOES NOT DO. It does not resolve dependencies. A .deb that needs shared
libraries from another package will extract fine and then fail to run, so this
suits self-contained binaries (binutils' nm, ar, objdump) and not, say, clang,
which wants libclang-cpp and libLLVM alongside it. Pinning clang this way means
fetching each of those packages explicitly and setting an rpath -- possible, and
a bigger job than this rule.

PIN BY sha256, ALWAYS. Ubuntu's pool moves: a package can be superseded and
withdrawn, and an unpinned URL would then either 404 or, worse, serve different
bytes. The checksum is what makes "the version the campus box runs" a fact
rather than a hope, and `tools/pins.tsv` is where the expected version lives.
"""

def _deb_archive_impl(ctx):
    # Several packages, one tree. A self-contained binary needs one .deb; a
    # compiler does not. clang is the driver alone -- 100 KB of it -- and it
    # finds libclang-cpp, libLLVM and its own resource headers beside it, so
    # extracting each package into a repository of its own would produce four
    # trees none of which can run. Laying them over each other reproduces the
    # layout the package maintainer designed, which is also the layout clang
    # computes its resource directory from (bin/../lib/clang/<version>).
    #
    # Keyed by checksum, so a mirror list belongs to exactly one payload and a
    # copy-pasted URL cannot silently inherit another package's pin.
    i = 0
    for sha256, urls in ctx.attr.debs.items():
        i += 1
        deb = "pkg%d.deb" % i
        ctx.download(url = urls, sha256 = sha256, output = deb)

        # Two layers. The first gives control.tar.*, data.tar.* and
        # debian-binary; the second unpacks the payload into usr/... where the
        # BUILD file expects it. Bazel picks the decompressor from the
        # extension, which is why this works for zstd without anything
        # installed.
        ctx.extract(deb)

        found = ""
        for name in ["data.tar.zst", "data.tar.xz", "data.tar.gz", "data.tar.bz2"]:
            if ctx.path(name).exists:
                ctx.extract(name)
                found = name
                break
        if not found:
            fail(("deb_archive(%s): no data.tar.* inside %s. Either the " +
                  "download is not a .deb, or Debian has started using a " +
                  "compression this rule does not list.") % (ctx.attr.name, urls[0]))

        # Leave nothing but the payload: the archive members are large, they
        # would sit in the repository cache twice over, and -- since every
        # package extracts into the SAME directory -- a leftover data.tar.zst
        # would be picked up again by the next package's search and unpacked a
        # second time.
        ctx.delete(deb)
        ctx.delete(found)
        for junk in ["control.tar.zst", "control.tar.xz", "control.tar.gz", "debian-binary"]:
            ctx.delete(junk)

    ctx.file("BUILD.bazel", ctx.attr.build_file_content, executable = False)

deb_archive = repository_rule(
    implementation = _deb_archive_impl,
    doc = "Download one or more .debs, lay their payloads over each other, and " +
          "put a BUILD file on top.",
    attrs = {
        "debs": attr.string_list_dict(
            mandatory = True,
            doc = "sha256 -> mirrors for the .deb with that checksum. The " +
                  "checksum is the key rather than a parallel list because a " +
                  "pin that can drift out of step with its URL is not a pin; " +
                  "and Ubuntu's pool prunes superseded versions, so more than " +
                  "one mirror is worth having. Packages are extracted in " +
                  "iteration order into a single tree.",
        ),
        "build_file_content": attr.string(
            mandatory = True,
            doc = "BUILD file laid over the extracted tree. Paths are as they " +
                  "appear in the package, e.g. usr/bin/x86_64-linux-gnu-nm.",
        ),
    },
)
