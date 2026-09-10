extends RefCounted

# Fixture for test/unit/test_coverage_addon.gd. Not a test (no test_ prefix) and
# never instrumented by the pre-run hook (res://test/* is excluded), so the test
# can instrument it itself and inspect which lines the addon chose.
#
# The trailing comment on FIRST opens a "(" that the following comment-only line
# closes. The vendored instrumenter used to count the opener but skip the
# comment-only line, leaving its block count stuck above zero so that nothing
# after this enum was instrumented.

enum Mode {
	FIRST,  ## widen the block (manual resize or a
	## file-double) closes the bracket the line above opened
	SECOND,
}


func after_poison() -> int:
	var total := 0
	for step in range(3):
		total += step
	return total


func string_bracket() -> String:
	var opener := "("
	return opener + ")"
