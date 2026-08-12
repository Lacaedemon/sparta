extends GutTest
## The validate gate's compile sweep (tools/ci/compile_all_scripts.gd): the walker that
## finds every .gd, and the per-script compile check both its verdicts rest on. The
## end-to-end gate behavior (inject a parse error -> `check.sh validate` fails) is proven
## at the shell level in the PR that added it; these pin the helpers' contracts.

const Sweep = preload("res://tools/ci/compile_all_scripts.gd")


func test_gd_paths_finds_scripts_across_the_tree() -> void:
	var paths: Array = Sweep.gd_paths("res://")
	assert_true(paths.has("res://scripts/Unit.gd"), "gameplay scripts are swept")
	assert_true(paths.has("res://tools/ci/compile_all_scripts.gd"), "the sweep sweeps itself")
	assert_true(paths.has("res://test/unit/test_compile_all_scripts.gd"),
			"test scripts are swept too (a broken test silently drops from GUT's run)")
	var sorted := paths.duplicate()
	sorted.sort()
	assert_eq(paths, sorted, "stable, sorted report order")


func test_gd_paths_skips_hidden_directories() -> void:
	for path in Sweep.gd_paths("res://"):
		assert_false(".godot" in String(path), "the editor cache holds no source: %s" % path)


func test_compiles_accepts_a_known_good_script() -> void:
	assert_true(Sweep.compiles("res://scripts/Unit.gd"), "a healthy script compiles")


# The negative case — compiles() rejecting a parse-broken script — deliberately does NOT
# live here: loading a broken script makes the engine print the very parse-error markers
# check.sh's test gate greps logs for, so an in-suite fixture would fail the gate even
# with the assertion passing. The sweep script self-tests that contract at the start of
# every run instead (see compile_all_scripts.gd's _initialize), where only its exit code
# is judged.
