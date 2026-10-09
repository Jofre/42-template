"""A function the GRADER brings, compiled from Rust, for C code to link.

WHY THIS EXISTS. Two subjects say the grader compiles a function of its own
in with every exercise after the first: C 12 "From exercise 01 onward, we'll
use our ft_create_elem", and C 13 the same of btree_create_node. The harness
used to link the student's own ex00 instead, so a bug in ex00 read as an
unexplained failure in a correct ex04, and a header whose structure differed
from the subject's was invisible, because both sides of every test were built
from it (findings 136 and 132). The grader's copy is built from the subject's
structure; so is this one.

WHY RUST, AND NOT A C FILE UNDER tests/. A C implementation of the
constructor anywhere outside deliverable/ is ex00's answer outside the zone
(AGENTS.md section 0), and tools/answer_scan.sh would rightly flag it. The
reference implementations of this repo live in //oracle, in Rust, where a
student can read but not paste them (AGENTS.md section 2, "The oracle is a
legitimate door"). So the grader's constructor is a small `#![no_std]` crate
under oracle/grader/, exporting a C function (`#[no_mangle] extern "C"`) over
`#[repr(C)]` structures laid out as the subject prints them, allocating with
the C library's malloc so that the student's code and the tests can free what
it returns.

TWO ARCHIVES FROM ONE SOURCE, with the same flags:

  lib<name>.a       x86_64, for every 64-bit program: the CcInfo this target
                    provides, which a student_binary links after the
                    student's archive (tools/student_build.bzl), and the
                    default output, for a runner that compiles at test time
                    and takes it with --lib.
  lib<name>_i686.a  i686, for the ilp32 layer, which links it with the pinned
                    zig at -target x86-linux-musl. Reached through the
                    `<name>_i686` filegroup grader_library() declares.

Both are compiled by the rustc of the rules_rust toolchain that builds
//oracle. The x86_64 one uses that toolchain's own standard library; the i686
one needs `core` built for i686, which is Rust's rust-std component for
i686-unknown-linux-musl, fetched by MODULE.bazel against a sha256 at the SAME
version as the toolchain (a `core` from another rustc does not load:
//tools:conventions holds the two versions together).

WHAT IT DOES NOT NEED. No std, no unwinding (-Cpanic=abort), no allocator of
its own: the archive's only undefined symbol is malloc, which resolves to the
C library's -- or, in an ASan build, to the sanitizer's interceptor, so the
nodes it returns are tracked like any other allocation, and valgrind sees
them the same way. The archive is not instrumented itself; it touches nothing
but the block it just allocated. Nothing in it is weak: a student who defines
the function anyway gets theirs linked (an archive member is pulled only for
a symbol still undefined), and the forbidden and symbols layers tell them the
grader brings it.

The contract names the library, per exercise, in `linked` (tools/subject.bzl),
and the macros in tools/defs.bzl read it from there. Three checks hold that
together: the contract's analysis refuses a label that is no grader_library(),
or one whose `exports` lack the function (GraderLibInfo); //tools:conventions
holds `exports` to the crate's #[no_mangle] functions; and a macro that would
build a program without the library fails while loading (defs.bzl's
_TAKES_LINKED).
"""

load("@rules_cc//cc:find_cc_toolchain.bzl", "CC_TOOLCHAIN_ATTRS", "find_cc_toolchain", "use_cc_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

# The target the i686 archive is built for. musl, as the ilp32 layer's zig
# links (-target x86-linux-musl); the archive uses nothing of either libc but
# malloc, so the choice only has to agree on the object format.
_I686 = "i686-unknown-linux-musl"

# Flags both archives are built with, so that they are the same code at two
# widths: optimised (the call is one malloc and two stores, and -O0 would leave
# calls into core's checks), no unwinding, one codegen unit (one object file,
# the same on every build). And no warning: one is a red build on the author's
# machine rather than noise in a student's first run, as for //oracle
# (//tools:conventions holds both to -Dwarnings).
_FLAGS = [
    "--edition=2021",
    "--crate-type=staticlib",
    "-Copt-level=2",
    "-Cpanic=abort",
    "-Ccodegen-units=1",
    "-Cdebuginfo=0",
    "-Dwarnings",
]

def _sysroot_of(files, triple):
    """The directory above lib/rustlib/<triple>/lib, from one of its files."""
    marker = "/lib/rustlib/%s/lib/" % triple
    for f in files:
        i = f.path.find(marker)
        if i >= 0:
            return f.path[:i]
    fail("no file under lib/rustlib/%s/lib/ in the i686 standard library" % triple)

def _rustc(ctx, tc, out, triple, sysroot, inputs):
    args = ctx.actions.args()
    args.add_all(_FLAGS)
    args.add("--crate-name", ctx.label.name)
    if triple:
        args.add("--target", triple)
    args.add("--sysroot", sysroot)
    args.add("-o", out)
    args.add(ctx.file.src)
    ctx.actions.run(
        executable = tc.rustc,
        arguments = [args],
        inputs = depset([ctx.file.src], transitive = inputs),
        outputs = [out],
        mnemonic = "GraderRustc",
        progress_message = "Compiling the grader's %s (%s)" % (
            ctx.label.name,
            triple or tc.target_triple.str,
        ),
    )

def _impl(ctx):
    tc = ctx.toolchains["@rules_rust//rust:toolchain_type"]
    a64 = ctx.actions.declare_file("lib%s.a" % ctx.label.name)
    a32 = ctx.actions.declare_file("lib%s_i686.a" % ctx.label.name)

    # The toolchain's own sysroot, as rules_rust passes it to every rustc it
    # runs.
    _rustc(ctx, tc, a64, None, tc.sysroot, [tc.all_files])
    std32 = ctx.files._i686_std
    _rustc(
        ctx,
        tc,
        a32,
        _I686,
        _sysroot_of(std32, _I686),
        [depset(std32), tc.rustc_lib, depset([tc.rustc])],
    )

    cc_toolchain = find_cc_toolchain(ctx)
    fc = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )
    lib = cc_common.create_library_to_link(
        actions = ctx.actions,
        feature_configuration = fc,
        cc_toolchain = cc_toolchain,
        static_library = a64,
    )
    linking = cc_common.create_linking_context(
        linker_inputs = depset([cc_common.create_linker_input(
            owner = ctx.label,
            libraries = depset([lib]),
        )]),
    )
    return [
        DefaultInfo(files = depset([a64])),
        CcInfo(linking_context = linking),
        OutputGroupInfo(i686 = depset([a32])),
        GraderLibInfo(names = sorted(ctx.attr.exports)),
    ]

GraderLibInfo = provider(
    doc = "What a grader_library() is: the functions it exports, for the subject contract's check of `linked` (tools/subject.bzl's linked_problem()).",
    fields = {
        "names": "The C functions the crate exports, as grader_library()'s `exports` lists them.",
    },
)

_grader_library = rule(
    implementation = _impl,
    doc = "A grader's function from a #![no_std] Rust crate, as an x86_64 and an i686 archive.",
    attrs = dict(CC_TOOLCHAIN_ATTRS, **{
        "src": attr.label(
            allow_single_file = [".rs"],
            mandatory = True,
            doc = "The crate root: one file, no dependencies.",
        ),
        "exports": attr.string_list(
            mandatory = True,
            allow_empty = False,
            doc = "The C functions the crate exports (//tools:conventions holds the list to the crate's #[no_mangle] ones).",
        ),
        "_i686_std": attr.label(
            default = "@rust_std_i686_musl//:rlibs",
            doc = "core and compiler_builtins for i686 (each .rlib and its .rmeta), from the pinned rust-std.",
        ),
    }),
    toolchains = ["@rules_rust//rust:toolchain_type"] + use_cc_toolchain(),
    fragments = ["cpp"],
)

def grader_library(name, src, exports, visibility = None):
    """A function the grader brings: :<name> (x86_64) and :<name>_i686 (i686).

    Args:
        name: the library, as an exercise's `linked` names it in the subject
            contract ("//oracle:c12_grader"). The i686 archive is always
            `<name>_i686` beside it: the ilp32 layer derives the label.
        src: the crate root, a #![no_std] Rust file exporting the function
            with #[no_mangle] extern "C" and nothing else of use to a student.
        exports: the functions it exports, by their C names: ["ft_create_elem"].
            The subject contract checks every function its `linked` takes from
            this library is one of them, while it is analysed (tools/subject.bzl's
            linked_problem()); //tools:conventions checks they are the crate's
            #[no_mangle] functions, all of them and no other. Written down
            because analysis cannot read the crate.
        visibility: as for any rule; the modules that link it need to see it.
    """
    _grader_library(
        name = name,
        src = src,
        exports = exports,
        visibility = visibility,
    )
    native.filegroup(
        name = name + "_i686",
        srcs = [":" + name],
        output_group = "i686",
        visibility = visibility,
    )
