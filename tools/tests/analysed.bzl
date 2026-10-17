"""A target that depends on others only so that each one is analysed.

For a package of fixtures whose targets are tagged manual, as every test the
macros emit under tools/tests/macro_fixtures is: `bazel build //...` and
`bazel test //...` skip a manual target, so a toy that named a label no
package declares, or that a macro change left unable to analyse, stayed
green everywhere until someone ran the package's hand command (V139).
Depending on a target analyses it -- every label it names must resolve, and
the macro's rule must accept what it was given -- and builds nothing of it:
this rule's output is empty and asks for no file of its deps. A source file
missing from the package itself is not seen: Bazel only looks for one when
an action reads it, and nothing here runs one.
"""

def _analysed_impl(_ctx):
    return [DefaultInfo()]

analysed = rule(
    implementation = _analysed_impl,
    doc = "Analyses `deps`, and builds nothing of them. Set testonly = True where a dep is a test.",
    attrs = {
        "deps": attr.label_list(doc = "The targets to analyse: tests, binaries and suites alike."),
    },
)
