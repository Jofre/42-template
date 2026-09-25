"""toolchain_provenance_test: prove the C++ toolchain Bazel RESOLVES is the pinned one.

§21 in TODO.md records why this is a rule and not a script. A check that asks
which file got exec'd first proves nothing: a two-line wrapper that execs the
box's clang passes it, and so does a pinned driver that loads the box's
libclang-cpp. So this resolves the toolchain the way every cc_binary does --
through toolchain resolution, in this build's configuration -- and hands the
test the compiler and archiver THAT toolchain names, with its files as
runfiles. The test then asks the loader what actually ran.

If registration ever stops winning, the toolchain resolved here is the
auto-detected one, its compiler is /usr/lib/llvm-12/bin/clang, and the first
assertion fails by name.
"""

load("@rules_cc//cc:find_cc_toolchain.bzl", "CC_TOOLCHAIN_ATTRS", "find_cc_toolchain", "use_cc_toolchain")

def _impl(ctx):
    cc = find_cc_toolchain(ctx)
    script = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._runner,
        output = script,
        substitutions = {
            "@AR@": cc.ar_executable,
            "@COMPILER@": cc.compiler_executable,
        },
        is_executable = True,
    )
    return [DefaultInfo(
        executable = script,
        runfiles = ctx.runfiles(transitive_files = cc.all_files),
    )]

toolchain_provenance_test = rule(
    implementation = _impl,
    doc = "Asserts, via the loader, that the resolved C++ toolchain runs the pinned tools.",
    attrs = dict(
        CC_TOOLCHAIN_ATTRS,
        _runner = attr.label(
            default = ":provenance_test.sh",
            allow_single_file = True,
        ),
    ),
    fragments = ["cpp"],
    test = True,
    toolchains = use_cc_toolchain(),
)
