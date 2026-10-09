"""Build a program from a student's files, in an action that never fails on them.

Every binary a layer runs that holds a student's code is one of these: the
harness linked with a function, a program exercise, its ASan twin, a Makefile
project. They used to be cc_binary and cc_library targets, and then a syntax
error, a warning under -Werror, a leftover main() or a missing file was a Bazel
BUILD error -- FAILED TO BUILD with no log, and before --keep_going the end of
the whole run. tools/student_build.sh does the compile instead and, when the
student's code does not build, writes a stand-in program that prints why (see
tools/standin.sh). So every test that runs it fails on its own, with the
compiler's words in its log.

WHAT STAYS EXACTLY AS A cc_binary HAD IT. The compile, archive and link command
lines are the ones the C++ toolchain Bazel resolved would have run -- read from
it here through cc_common, never written out -- so the pinned clang and linker
(//tools/cc_toolchain), every flag it adds (-fstack-protector, -fPIC,
-U_FORTIFY_SOURCE, relro, -Wl,-S in fastbuild ...) and --config=gcc all carry
over by construction. The caller's copts and linkopts go where a cc_binary puts
them. A function exercise's sources are archived and linked after the harness,
as a cc_library's were, so the linker takes a file only when something calls
into it. The one thing that changed on purpose: an ASan twin compiles every
unit it links under the sanitizer, where it used to link another exercise's
library uninstrumented.

Two rules:

  student_unit    an exercise's files as a unit other binaries link: its
                  sources, its headers and the include directories its own
                  compile used. What `fn` names in c_function, and what a
                  rush variant's unit lists in `deps` for the ft_putchar.c of
                  the same turn-in -- never another exercise's files. It
                  builds nothing, so it cannot fail.
  student_binary  the program: harness sources + units + loose sources, built by
                  tools/student_build.sh. A `deps` entry can also be a
                  cc_library of the harness's own (//tools:diffio): its headers
                  and include directories reach every compile and its
                  libraries the link, as a cc_binary's deps would.

Use them through tools/defs.bzl (_student_bin, _student_lib, student_lib),
which routes every binary built from deliverable sources here and filters every
path through _zone(). //tools:conventions refuses a cc_binary or cc_library in
defs.bzl or in a module's BUILD file.
"""

load("@rules_cc//cc:action_names.bzl", "ACTION_NAMES")
load("@rules_cc//cc:find_cc_toolchain.bzl", "CC_TOOLCHAIN_ATTRS", "find_cc_toolchain", "use_cc_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

StudentUnitInfo = provider(
    doc = "An exercise's files, as another binary links them.",
    fields = {
        "srcs": "depset of the .c files, in link order",
        "hdrs": "depset of the headers to stage",
        "includes": "list of package-relative include directories, as (package, dir) pairs, in order",
    },
)

def _dedup(xs):
    out = []
    for x in xs:
        if x not in out:
            out.append(x)
    return out

def _unit_impl(ctx):
    srcs = [f for f in ctx.files.srcs if f.extension == "c"]
    hdrs = [f for f in ctx.files.srcs + ctx.files.hdrs if f.extension != "c"]
    includes = [(ctx.label.package, d) for d in ctx.attr.includes]
    trans_srcs = []
    trans_hdrs = []
    for d in ctx.attr.deps:
        u = d[StudentUnitInfo]
        trans_srcs.append(u.srcs)
        trans_hdrs.append(u.hdrs)
        includes += u.includes
    return [
        DefaultInfo(files = depset(ctx.files.srcs + ctx.files.hdrs)),
        StudentUnitInfo(
            srcs = depset(srcs, transitive = trans_srcs, order = "preorder"),
            hdrs = depset(hdrs, transitive = trans_hdrs, order = "preorder"),
            includes = _dedup(includes),
        ),
    ]

student_unit = rule(
    implementation = _unit_impl,
    doc = "An exercise's files as a unit a student_binary links. Builds nothing.",
    attrs = {
        "srcs": attr.label_list(allow_files = True, doc = "Sources (and headers) of the unit."),
        "hdrs": attr.label_list(allow_files = True, doc = "Headers to stage."),
        "includes": attr.string_list(doc = "Package-relative include directories, in order."),
        "deps": attr.label_list(providers = [StudentUnitInfo], doc = "Units this one calls into."),
    },
)

def _include_dirs(ctx, pairs):
    """Each (package, dir) as the two -I directories a cc_library gave.

    The source directory, and its mirror under bazel-out, as `includes` did.
    """
    out = []
    for pkg, d in pairs:
        if not d or d == ".":
            rel = pkg
        elif pkg:
            rel = pkg + "/" + d
        else:
            rel = d
        rel = rel or "."
        out.append(rel)
        out.append(ctx.bin_dir.path + ("/" + rel if rel != "." else ""))
    return out

def _binary_impl(ctx):
    cc_toolchain = find_cc_toolchain(ctx)
    fc = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )
    pkg = ctx.label.package

    # What gets compiled, and with which include path. The -I list is in the
    # order a cc_binary's was: the binary's own `includes`, then each dep in
    # the order given -- a unit's own directories first, then those of the
    # units it calls; a harness library's (//tools:diffio) where it stands.
    lib = [f for f in ctx.files.srcs if f.extension == "c"]
    headers = [f for f in ctx.files.srcs + ctx.files.harness + ctx.files.hdrs if f.extension != "c"]
    includes = _include_dirs(ctx, [(pkg, d) for d in ctx.attr.includes])
    quote_includes = [".", ctx.bin_dir.path]
    system_includes = []
    unit_srcs = []
    trans_headers = []
    cc_link_args = []
    cc_link_inputs = []
    for d in ctx.attr.deps:
        if StudentUnitInfo in d:
            u = d[StudentUnitInfo]
            unit_srcs.append(u.srcs)
            trans_headers.append(u.hdrs)
            includes += _include_dirs(ctx, u.includes)
        elif CcInfo in d:
            cctx = d[CcInfo].compilation_context
            trans_headers.append(cctx.headers)
            includes += cctx.includes.to_list()
            quote_includes += cctx.quote_includes.to_list()
            system_includes += cctx.system_includes.to_list()
            for li in d[CcInfo].linking_context.linker_inputs.to_list():
                for l2l in li.libraries:
                    a = l2l.pic_static_library or l2l.static_library
                    if not a:
                        continue
                    cc_link_inputs.append(a)
                    if l2l.alwayslink:
                        cc_link_args += ["-Wl,--whole-archive", a.path, "-Wl,--no-whole-archive"]
                    else:
                        cc_link_args.append(a.path)
                cc_link_args += li.user_link_flags
        else:
            fail("%s: deps entry %s is neither a student_unit nor a cc_library" % (ctx.label, d.label))
    lib = depset(lib, transitive = unit_srcs, order = "preorder").to_list()
    headers = depset(headers, transitive = trans_headers).to_list()
    harness = [f for f in ctx.files.harness if f.extension == "c"]
    includes = _dedup(includes)

    # The toolchain's own command lines, with placeholders the script fills in
    # per file: see its header.
    cvars = cc_common.create_compile_variables(
        cc_toolchain = cc_toolchain,
        feature_configuration = fc,
        source_file = "@SRC@",
        output_file = "@OBJ@",
        user_compile_flags = ctx.attr.copts,
        include_directories = depset(includes),
        quote_include_directories = depset(_dedup(quote_includes)),
        system_include_directories = depset(_dedup(system_includes)),
        use_pic = True,
    )
    compile_argv = cc_common.get_memory_inefficient_command_line(
        feature_configuration = fc,
        action_name = ACTION_NAMES.c_compile,
        variables = cvars,
    )
    compiler = cc_common.get_tool_for_action(
        feature_configuration = fc,
        action_name = ACTION_NAMES.c_compile,
    )
    compile_env = cc_common.get_environment_variables(
        feature_configuration = fc,
        action_name = ACTION_NAMES.c_compile,
        variables = cvars,
    )

    # @OBJS@ as the first user link flag: that is where a cc_binary's objects
    # and libraries sit -- after the toolchain's link flags, before the
    # caller's linkopts and the toolchain's libraries (-lstdc++, -lm).
    lvars = cc_common.create_link_variables(
        cc_toolchain = cc_toolchain,
        feature_configuration = fc,
        output_file = "@OUT@",
        user_link_flags = ["@OBJS@"] + cc_link_args + ctx.attr.linkopts,
        is_using_linker = True,
        is_linking_dynamic_library = False,
        # A cc_binary built in fastbuild is linked with -Wl,-S (--strip's
        # default, "sometimes"); keep that, so nothing a layer reads changes --
        # except for a sanitizer's twin (keep_debug), whose report is read
        # for the file and line each frame names, and -S takes those away.
        must_keep_debug = ctx.attr.keep_debug or ctx.var["COMPILATION_MODE"] != "fastbuild",
    )
    link_argv = cc_common.get_memory_inefficient_command_line(
        feature_configuration = fc,
        action_name = ACTION_NAMES.cpp_link_executable,
        variables = lvars,
    )
    linker = cc_common.get_tool_for_action(
        feature_configuration = fc,
        action_name = ACTION_NAMES.cpp_link_executable,
    )
    link_env = cc_common.get_environment_variables(
        feature_configuration = fc,
        action_name = ACTION_NAMES.cpp_link_executable,
        variables = lvars,
    )

    avars = cc_common.create_link_variables(
        cc_toolchain = cc_toolchain,
        feature_configuration = fc,
        output_file = "@LIB@",
        is_using_linker = False,
        is_linking_dynamic_library = False,
    )
    ar_argv = cc_common.get_memory_inefficient_command_line(
        feature_configuration = fc,
        action_name = ACTION_NAMES.cpp_link_static_library,
        variables = avars,
    )
    archiver = cc_common.get_tool_for_action(
        feature_configuration = fc,
        action_name = ACTION_NAMES.cpp_link_static_library,
    )

    out = ctx.actions.declare_file(ctx.label.name)
    outputs = [out]
    args = ctx.actions.args()
    args.add("--out", out)
    if ctx.outputs.includes_out:
        # The -I directories the Makefile's recipes pass, one per line, for
        # the layers that compile the same files outside this action (the
        # compile and forbidden layers): one reading of `make -Bn`, not two.
        args.add("--includes-out", ctx.outputs.includes_out)
        outputs.append(ctx.outputs.includes_out)
    if ctx.outputs.sources_out:
        # The .c files the recipes compile, one per line, from the Makefile's
        # directory, for the files layer ("unknown" when make could not plan).
        args.add("--sources-out", ctx.outputs.sources_out)
        outputs.append(ctx.outputs.sources_out)
    args.add("--label", "//%s:%s" % (pkg, ctx.label.name))
    if ctx.attr.dir:
        args.add("--dir", pkg + "/" + ctx.attr.dir if pkg else ctx.attr.dir)
    args.add("--cc", compiler)
    args.add_all(compile_argv, before_each = "--cflag")
    args.add("--ld", linker)
    args.add_all(link_argv, before_each = "--lflag")
    args.add("--ar", archiver)
    args.add_all(ar_argv, before_each = "--arflag")
    args.add_all(harness, before_each = "--harness")
    if not ctx.attr.archive:
        args.add("--no-archive")
    inputs = [ctx.file._script, ctx.file._standin] + lib + harness + headers + cc_link_inputs
    if ctx.attr.makefile:
        args.add("--makefile", ctx.file.makefile)
        args.add("--make", ctx.executable._make)
        inputs += [ctx.file.makefile] + ctx.files.make_data + [ctx.executable._make]
    elif ctx.attr.missing_makefile:
        # Not a declared input: the file is not there. The script writes a
        # stand-in saying so.
        args.add("--makefile", pkg + "/" + ctx.attr.missing_makefile if pkg else ctx.attr.missing_makefile)
        args.add("--make", ctx.executable._make)
        inputs.append(ctx.executable._make)
    else:
        args.add_all(lib, before_each = "--src")
    if ctx.attr.makefile or ctx.attr.missing_makefile:
        # What to build while there is no Makefile, or while it compiles
        # nothing (student_build.sh, UNTIL THE MAKEFILE IS WRITTEN).
        args.add_all(lib, before_each = "--fallback-src")

    env = dict(compile_env)
    env.update(link_env)
    ctx.actions.run_shell(
        command = 'exec sh "$@"',
        arguments = [ctx.file._script.path, args],
        inputs = depset(inputs, transitive = [cc_toolchain.all_files]),
        outputs = outputs,
        env = env,
        # PATH for the script's own tools (sed, cp, mkdir ...), as every other
        # action here gets it; `env` above adds the toolchain's variables.
        use_default_shell_env = True,
        mnemonic = "StudentBuild",
        progress_message = "Building %{label} from the student's files",
    )
    return [DefaultInfo(files = depset([out]), executable = out)]

student_binary = rule(
    implementation = _binary_impl,
    doc = "A program built from a student's files; a stand-in when they do not build.",
    executable = True,
    attrs = dict(CC_TOOLCHAIN_ATTRS, **{
        "srcs": attr.label_list(
            allow_files = True,
            doc = "The student's sources (and any the grader supplies), plus headers to stage.",
        ),
        "harness": attr.label_list(
            allow_files = True,
            doc = "The test's own sources (a main()), always linked, plus headers to stage.",
        ),
        "hdrs": attr.label_list(allow_files = True, doc = "Headers to stage."),
        "deps": attr.label_list(
            doc = "student_unit targets, whose sources join the library, or cc_library " +
                  "targets of the harness's own, whose headers and libraries join the build.",
        ),
        "includes": attr.string_list(doc = "Package-relative include directories, first on the path."),
        "copts": attr.string_list(doc = "Compile flags, after the toolchain's."),
        "linkopts": attr.string_list(doc = "Link flags, after the objects."),
        "keep_debug": attr.bool(
            default = False,
            doc = "Link without stripping debug info, whatever the compilation mode: " +
                  "a sanitizer's twin, whose report names file:line.",
        ),
        "archive": attr.bool(
            default = True,
            doc = "Link the student's sources through an archive (a function exercise), " +
                  "or directly (a program exercise).",
        ),
        "dir": attr.string(
            doc = "Package-relative directory the student's own sources live in, for the " +
                  "'none of your files' message. Empty: no such check.",
        ),
        "makefile": attr.label(
            allow_single_file = True,
            doc = "Take the student's sources from `make -Bn` on this Makefile.",
        ),
        "missing_makefile": attr.string(
            doc = "The package-relative path the Makefile should be at, when it is not there.",
        ),
        "make_data": attr.label_list(allow_files = True, doc = "The files staged beside the Makefile."),
        "includes_out": attr.output(
            doc = "Where to write the -I directories the Makefile passes, one per line, " +
                  "workspace-relative (empty when there is no Makefile or it passes none).",
        ),
        "sources_out": attr.output(
            doc = "Where to write the .c files the Makefile's recipes compile, one per line, " +
                  "relative to its directory: 'unknown' when make could not plan the build " +
                  "or there is no Makefile, empty when it compiles none.",
        ),
        "_script": attr.label(default = "//tools:student_build.sh", allow_single_file = True),
        "_standin": attr.label(default = "//tools:standin.sh", allow_single_file = True),
        "_make": attr.label(
            default = "@make_ubuntu//:usr/bin/make",
            allow_single_file = True,
            executable = True,
            cfg = "exec",
        ),
    }),
    toolchains = use_cc_toolchain(),
    fragments = ["cpp"],
)
