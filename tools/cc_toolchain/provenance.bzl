"""toolchain_provenance_test: prove the C++ toolchain Bazel RESOLVES is the pinned one.

This is a rule and not a script. A check that asks
which file got exec'd first proves nothing: a two-line wrapper that execs the
box's clang passes it, and so does a pinned driver that loads the box's
libclang-cpp. So this resolves the toolchain the way every cc_binary does --
through toolchain resolution, in this build's configuration -- and hands the
test the compiler and archiver THAT toolchain names, with its files as
runfiles. The test then asks the loader what actually ran.

If registration ever stops winning, the toolchain resolved here is the
auto-detected one, its compiler is /usr/lib/llvm-12/bin/clang, and the first
assertion fails by name.

THE LINKS ARE THE TOOLCHAIN'S TOO. The test is handed the flags that
toolchain gives a program's link (link_flags, and every feature an
executable's link turns on), read here through cc_common as
tools/student_build.bzl reads them for every binary a layer runs, never
written out, and its link checks pass no -B or -fuse-ld of their own. They
did: a link_flags without -Btools/cc_toolchain/, or back on
-fuse-ld=/usr/bin/ld.gold, sent every link to the box's linkers while this
test still said OK.
"""

load("@rules_cc//cc:action_names.bzl", "ACTION_NAMES")
load("@rules_cc//cc:find_cc_toolchain.bzl", "CC_TOOLCHAIN_ATTRS", "find_cc_toolchain", "use_cc_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")

def _impl(ctx):
    cc = find_cc_toolchain(ctx)
    fc = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )
    link_flags = cc_common.get_memory_inefficient_command_line(
        feature_configuration = fc,
        action_name = ACTION_NAMES.cpp_link_executable,
        variables = cc_common.create_link_variables(
            cc_toolchain = cc,
            feature_configuration = fc,
            is_using_linker = True,
            is_linking_dynamic_library = False,
        ),
    )
    script = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._runner,
        output = script,
        substitutions = {
            "@AR@": cc.ar_executable,
            "@COMPILER@": cc.compiler_executable,
            # One a line, inside a quoted here-document of the script: read
            # as written, so none is quoted here. No flag holds a newline.
            "@LINK_FLAGS@": "\n".join(link_flags),
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
