extends GutTest

## Guards the local deviations in the vendored coverage addon
## (addons/coverage/Coverage.gd): brackets inside a trailing comment or a string
## literal must not be counted as code blocks, because an unbalanced one left
## every later line of the file uninstrumented and the file reporting zero
## coverable lines.

const Coverage = preload("res://addons/coverage/Coverage.gd")
const COVERAGE_SCRIPT_PATH := "res://addons/coverage/Coverage.gd"
const FIXTURE_PATH := "res://test/fixtures/coverage_trailing_comment_bracket.gd"

var _collector = null


func after_each() -> void:
	if _collector != null:
		_collector.revert()
		_collector = null


func _instrument_fixture():
	_collector = Coverage.ScriptCoverageCollector.new(COVERAGE_SCRIPT_PATH, FIXTURE_PATH)
	return _collector


## 0-based index of the first fixture line containing `needle`, matching the
## indices the addon stores in coverage_lines.
func _line_index(collector, needle: String) -> int:
	var lines: PackedStringArray = collector.source_code.split("\n")
	for i in lines.size():
		if needle in lines[i]:
			return i
	fail_test("fixture has no line containing %s" % needle)
	return -1


func test_lines_after_an_unbalanced_trailing_comment_are_instrumented() -> void:
	var collector = _instrument_fixture()
	for needle in ["var total := 0", "total += step", "return total"]:
		assert_has(
			collector.coverage_lines,
			_line_index(collector, needle),
			"line %s is instrumented despite the earlier trailing-comment bracket" % needle
		)


func test_brackets_inside_string_literals_do_not_open_a_block() -> void:
	var collector = _instrument_fixture()
	assert_has(
		collector.coverage_lines,
		_line_index(collector, "return opener"),
		"the line after a lone \"(\" string literal is instrumented"
	)


func test_strip_trailing_comment_keeps_code_and_blanks_strings() -> void:
	var collector = _instrument_fixture()
	assert_eq(collector._strip_trailing_comment("x = f(a)  # opens ("), "x = f(a)  ")
	assert_eq(collector._strip_trailing_comment('x = "#(" # ('), 'x = "__" ')
	assert_eq(collector._strip_trailing_comment("y = [1, 2]"), "y = [1, 2]")
