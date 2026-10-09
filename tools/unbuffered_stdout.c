/* unbuffered_stdout.c — linked into every output fixture the HARNESS owns, so
 * that what a case printed reaches tools/diff_output.sh even if the program
 * dies in a later case. Grader-side test infrastructure, never compiled into a
 * deliverable (same standing as tools/perf_run.c and tools/allocfail_shim.c).
 *
 * WHY. diff_output.sh sends the program's stdout to a file, and the C library
 * fully buffers a stream that is not a terminal: printf's bytes sit in a 4 KiB
 * buffer until it fills or main returns. A fixture runs every case in one
 * process, so when the student's code crashed in case 5, the lines cases 1-4
 * had printed were still in that buffer and died with it. The table then read
 * "(no line)" on every row -- the cases the code gets right included -- and the
 * hints followed the table to the most basic concept the exercise has
 * (findings 064 and 129 of the student-test run). With stdout unbuffered each
 * printf is written as it is called, so the rows before the crash are real
 * results and the first missing line is the case that was running.
 *
 * WHERE, and where NOT. Only binaries whose main() is the harness's: the
 * c_function, c_libft, c_header and rush output fixtures (defs.bzl's
 * _output_fixture_binary, and the two runners that compile a fixture at test
 * time, header_check.sh and ilp32_test.sh, through --harness-src). Never:
 *   - a student's own program (c_program): it is graded as the student wrote
 *     it, buffering included, exactly as the grader will run it;
 *   - a diff, perf, cycles or refcost binary: they measure, and a write per
 *     printf would change what they measure and slow a corpus of 400 000
 *     cases for nothing -- nobody reads their output row by row.
 * //tools:conventions checks both halves: it refuses a cc_binary built from a
 * harness main, and _output_fixture_binary around anything else.
 *
 * ORDER. Unbuffered output lands in program order, so a fixture that mixes
 * printf with the student's write() needs no setbuf() of its own any more; the
 * fixtures that call one keep it (harmless, and it says why beside the call).
 * No expected file changed with this: every fixture that interleaves the two
 * already made stdout unbuffered or flushed it itself, and no output or ilp32
 * target changed status on either answer set when this was first linked.
 *
 * A constructor rather than a line in each main: one place, nothing to forget
 * in the next fixture. cc_library's alwayslink keeps the linker from dropping
 * this object, which nothing references by name.
 *
 * THE MARKER. diff_output.sh --harness-fixture reads a missing row as the case that
 * was running, which is true only of a binary built with this file. So it
 * checks, before it runs one, that the binary carries the string below, and
 * refuses (exit 2) a --harness-fixture binary that does not: the premise is verified
 * where it is relied on, not only linted. The constructor reads the string
 * through a volatile pointer so that neither the compiler nor the linker's
 * section garbage collection can drop it. */
#include <stdio.h>

static const char	g_marker[]
	= "tools/unbuffered_stdout: stdout is unbuffered";

__attribute__((constructor))
static void	harness_unbuffer_stdout(void)
{
	const char *volatile	marker;

	marker = g_marker;
	(void)*marker;
	setvbuf(stdout, NULL, _IONBF, 0);
}
