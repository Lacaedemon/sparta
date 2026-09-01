## Strict review verdict payload verification before auto-merge under mwc

**Never merge a PR without inspecting the full review comment payload for a clean/approved verdict.**

### 1. `review / claude-review` Exit Status vs. Actual Review Verdict
The GitHub Actions workflow job `review / claude-review` (and `require-review`) returns an exit code of `0` (`pass`) as long as the review workflow executed without an infrastructure crash, *even when the review verdict is explicitly "Needs more work"*.
Therefore:
- A `pass` status reported by `gh pr checks` is **not** evidence of an approved code review.
- Under `mwc`, you must always inspect the actual review comment body via `gh api repos/<owner>/<repo>/issues/<PR>/comments` or `gh pr view <PR> --comments`.
- Any review verdict other than **Clean / Approved** (or any outstanding review findings) strictly blocks merging.

### 2. Demo Skip Manifest Schema
When authoring a `"skip": true` manifest for documentation-only or headless changes (`demos/demo.<slug>.json`):
- The explanation field MUST be named `"reason"`, NOT `"skip_reason"`.
- CI (`.github/workflows/demo-video.yml`) specifically parses `.reason // .caption // <generic fallback>`. If named `"skip_reason"`, the authored reason is ignored and CI falls back to a generic placeholder.

### 3. File Path Verification in Documentation
Never reference speculative or imagined test scripts (`test/unit/test_unit_order_mode.gd`) or input manifests (`demos/inputs/stance-*.json`) in architectural design documents. Always verify exact file paths against the codebase before publishing design docs.
