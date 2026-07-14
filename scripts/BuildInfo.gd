class_name BuildInfo
## Build/version stamp read by Replay.gd when saving, so a saved replay records which
## commit produced it -- lets a player told to load an old replay recognize when their
## build might be incompatible, instead of just guessing from an unexplained desync.
##
## COMMIT_SHA is overwritten with the real commit by .github/workflows/release.yml right
## before --export-release, so an exported binary bakes in the SHA it was actually built
## from. That overwrite is never committed back -- every other run (editor, godot-ci.yml's
## tests, a plain local `godot` invocation) sees this checked-in fallback untouched.
const COMMIT_SHA := "dev"


## Best-effort "does the live checkout have uncommitted changes" signal, for local dev runs
## only. Returns "" on any failure (no git binary, no .git directory, or a shipped build
## that has neither) so an exported build's Replay.save() just omits this field instead of
## erroring -- never used to gate anything, purely informational context for a human
## diagnosing a replay mismatch.
static func git_dirty_status() -> String:
	var output: Array = []
	var exit_code := OS.execute("git", ["status", "--porcelain"], output, true)
	if exit_code != 0:
		return ""
	return "\n".join(output)
