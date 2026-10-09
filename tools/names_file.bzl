"""A text file of names, one per line, with no label behind any of them.

For a layer that reads the NAMES of the turn-in's files and never their
contents: c_files. Handing it each file as `$(location f)` made the file's
name part of a label and of an argument list, and a name those cannot carry
broke the layer -- a parenthesis ends $(location ...) early and fails the
analysis of every target that names the file; a blank is split in two by
sh_test's argument tokenising, so "ft_putchar copy.c" was reported as
"ft_putchar" and "copy.c". Written here as plain strings, every name arrives
whole, and the files layer can report it by its real name.
"""

def _names_file_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".txt")
    ctx.actions.write(out, "".join([n + "\n" for n in ctx.attr.names]))
    return [DefaultInfo(files = depset([out]), runfiles = ctx.runfiles([out]))]

names_file = rule(
    implementation = _names_file_impl,
    doc = "Writes `names`, one per line, to <name>.txt.",
    attrs = {
        "names": attr.string_list(doc = "The names, in order. None may hold a newline."),
    },
)
