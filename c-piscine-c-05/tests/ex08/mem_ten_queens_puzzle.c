/* Memory-safety probe for ft_ten_queens_puzzle — run under AddressSanitizer/UBSan.
 *
 * The function takes no arguments and owns no external buffer, so every memory
 * hazard it has is internal, and there are two worth a redzone:
 *
 *   - the board itself. Whatever holds one column index per row is sized by a
 *     count the implementation chose, and the classic slip is writing the row
 *     AFTER the last one — a loop bound that runs to the row count inclusive, or
 *     an initialisation that steps one place too far. That write lands one
 *     element past the end of a stack array.
 *   - the line buffer. Emitting a solution means assembling one row of digits
 *     plus its newline; sizing that by the digit count and then writing the
 *     newline as well is an off-by-one that produces byte-perfect output,
 *     because the stray byte is overwritten by the next line before anyone
 *     reads it.
 *
 * Neither is visible to any other layer: the output layer compares bytes that
 * are correct, and a zero-input function has no c_diff and therefore no
 * sanitizer twin (tools/defs.bzl builds one but tags it manual). ASan brackets
 * every stack buffer with redzones, so this single call reports either.
 *
 * The call is exhaustive by nature — it walks the whole search tree and emits
 * all 724 solutions — so the probe needs no arguments to reach the interesting
 * states. A correct version stays in bounds and the probe exits 0 (an
 * unimplemented stub also exits 0). This is a test input, not a solution. */
int	ft_ten_queens_puzzle(void);

int	main(void)
{
	ft_ten_queens_puzzle();
	return (0);
}
