"""Entry point for the hermetic norminette.

The pip package ships a console script (`norminette` ->
`norminette.__main__:main`), but a console script is generated at install time
against the installing interpreter -- exactly the host dependency this build is
removing. Calling the module's main() directly gives the same behaviour through
Bazel's own Python toolchain, with the version pinned in tools/requirements.txt.

Kept deliberately tiny: it must add no behaviour of its own, because the norm
layer's verdict has to be the one the Moulinette would give.
"""

import sys

from norminette.__main__ import main

if __name__ == "__main__":
    sys.exit(main())
