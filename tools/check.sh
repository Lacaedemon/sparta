#!/usr/bin/env bash
# tools/check.sh — run Sparta's CI checks locally, before you push.
#
# This mirrors the gating checks in .github/workflows/ so you can reproduce a CI
# pass (or failure) on your own machine without waiting on the runners:
#
#   validate  Godot import — loads the whole project (autoloads, class_name
#             globals, cross-script references) and fails on any script/parse
#             error. Mirrors .github/workflows/godot-ci.yml.
#   test      GUT unit suite, run headlessly. Mirrors godot-ci.yml.
#   chars     Curly quotes and en/em dashes in the website docs (*.qmd, *.R) —
#             the Quarto source is kept plain-ASCII. Mirrors
#             .github/workflows/check-non-standard-chars.yml.
#   comments  Issue/PR-number citations (#123) in GDScript comments — CLAUDE.md's
#             "no issue-number references" rule (TODO(#N):/FIXME(#N): excepted).
#             Scoped to this diff's own added lines, not a whole-tree grep, so
#             pre-existing citations elsewhere in the repo don't fail every
#             future run. Mirrors .github/workflows/check-comment-citations.yml.
#   units     Units-convention lint (docs/units-convention.md): no runtime
#             metric->world conversions outside the allowed boundaries, no new
#             bare wu literals documented by metric comments. Diff-scoped to
#             added lines like `comments`, sharing its base resolution. Mirrors
#             the units step in check-comment-citations.yml.
#   coverage  GUT suite instrumented for line coverage; writes coverage/lcov.info.
#             Mirrors .github/workflows/test-coverage.yml. Slower than `test` and
#             non-gating, so not in the default set (run it explicitly or via "all").
#   patch_coverage
#             Local approximation of Codecov's codecov/patch check: what fraction
#             of THIS diff's added scripts/*.gd lines are covered. Fails when
#             that fraction is below the effective target (auto: the project-wide
#             total, like codecov/patch's own `target: auto`; override with
#             SPARTA_CHECK_PATCH_COVERAGE_TARGET). Regenerates
#             coverage/lcov.info fresh (runs `coverage` as a dependency), so it's
#             slow — not in the default set. Run it before pushing a scripts/
#             change rather than discovering a codecov/patch failure after a
#             ~15-20 min CI round trip.
#   links     Markdown link-check with lychee, if it's installed. Mirrors
#             .github/workflows/check-links.yml. Needs network; not in the
#             default set (run it explicitly or via "all").
#   demo_defects
#             Deterministic defect scan of THIS diff's changed demos/inputs/*.json
#             scripts: a FULL state dump per script run through DemoDefects (the
#             formation defect metrics plus the script's own declared `expect`
#             assertions -- see demos/README.md). Drives a real headless battle
#             per changed script, so not in the default set. Mirrors the demo
#             workflow's defect-scan step.
#
# Usage:
#   tools/check.sh                 # default set: validate, test, chars, comments, units
#   tools/check.sh test chars      # only the named checks, in the given order
#   tools/check.sh all             # every check (links included if lychee is present)
#   tools/check.sh -l | --list     # list the available checks
#   tools/check.sh -h | --help     # this help
#
# Environment:
#   GODOT_BIN    Godot 4.7 binary (default: godot). On macOS, e.g.
#                /Applications/Godot.app/Contents/MacOS/Godot
#   GUT_VERSION  GUT release vendored into addons/gut when it's missing
#                (default: v9.7.0). Keep in sync with godot-ci.yml and
#                test/README.md.
#   SPARTA_CHECK_VALIDATE_TIMEOUT / SPARTA_CHECK_TEST_TIMEOUT /
#   SPARTA_CHECK_COVERAGE_TIMEOUT
#                Per-check hard timeouts in seconds for the Godot runs (defaults
#                900 / 1800 / 2700). Generous hang-detectors, not perf gates: a
#                run that hits one was never going to finish, and killing it
#                stops an orphaned Godot process from piling up on the machine.
#   SPARTA_GODOT_PREFLIGHT_LIMIT
#                Warn when more than this many Godot processes are already
#                running before the checks start (default 5) — the early signal
#                of an orphan leak building up.
#   SPARTA_CHECK_COMMENTS_BASE
#                Commit-ish the `comments` and `units` checks diff HEAD against to find
#                *new* lines to scan (default: tries origin/main, then main; CI
#                sets this per-event — see check-comment-citations.yml). When no
#                base can be resolved, the check skips rather than scanning the
#                whole tree.
#   SPARTA_CHECK_PATCH_COVERAGE_BASE
#                Same, for the `patch_coverage` check's diff base (default:
#                tries origin/main, then main).
#   SPARTA_CHECK_PATCH_COVERAGE_TARGET
#                Fixed pass/fail threshold (percent, e.g. 90) for the
#                `patch_coverage` check. Default: unset, which mirrors
#                codecov/patch's `target: auto` — the project-wide line
#                coverage computed from the regenerated coverage/lcov.info.
#
# Exit status is non-zero if any selected check fails, so it drops straight into
# a pre-push hook or a `&&` chain.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
GODOT_BIN="${GODOT_BIN:-godot}"
# Keep in sync with .github/workflows/godot-ci.yml and test/README.md.
GUT_VERSION="${GUT_VERSION:-v9.7.0}"

# Hard per-check budgets (seconds) for the Godot invocations, so a hung run is
# killed instead of surviving as an orphaned process. See the header for the
# rationale; override via the SPARTA_CHECK_*_TIMEOUT variables above.
VALIDATE_TIMEOUT="${SPARTA_CHECK_VALIDATE_TIMEOUT:-900}"
TEST_TIMEOUT="${SPARTA_CHECK_TEST_TIMEOUT:-1800}"
COVERAGE_TIMEOUT="${SPARTA_CHECK_COVERAGE_TIMEOUT:-2700}"

# shellcheck source=lib/run-bounded.sh
. "$SCRIPT_DIR/lib/run-bounded.sh"

DEFAULT_CHECKS=(validate test chars comments units)
ALL_CHECKS=(validate test chars comments units coverage patch_coverage links demo_defects)

# --- pretty output ---------------------------------------------------------
# Colour only when stdout is a terminal and NO_COLOR isn't set. Per the NO_COLOR
# spec, any value (including empty) disables colour, so test for presence, not
# emptiness.
if [ -t 1 ] && [ -z "${NO_COLOR+x}" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
fi

section() { printf '\n%s== %s ==%s\n' "$C_BOLD$C_BLUE" "$1" "$C_RESET"; }
info()    { printf '%s\n' "$1"; }
warn()    { printf '%s%s%s\n' "$C_YELLOW" "$1" "$C_RESET"; }
err()     { printf '%s%s%s\n' "$C_RED" "$1" "$C_RESET" >&2; }

# Per-check results, kept in parallel indexed arrays (not an associative array,
# so this stays compatible with the Bash 3.2 that ships on macOS).
RESULT_NAMES=()
RESULT_STATUSES=()

# set_result <name> <status> — record/overwrite a check's status.
set_result() {
  local name="$1" status="$2" i
  if [ ${#RESULT_NAMES[@]} -gt 0 ]; then
    for i in "${!RESULT_NAMES[@]}"; do
      if [ "${RESULT_NAMES[$i]}" = "$name" ]; then
        RESULT_STATUSES[$i]="$status"
        return
      fi
    done
  fi
  RESULT_NAMES+=("$name")
  RESULT_STATUSES+=("$status")
}

# get_result <name> — print a check's status (empty string if unset).
get_result() {
  local name="$1" i
  if [ ${#RESULT_NAMES[@]} -gt 0 ]; then
    for i in "${!RESULT_NAMES[@]}"; do
      if [ "${RESULT_NAMES[$i]}" = "$name" ]; then
        printf '%s' "${RESULT_STATUSES[$i]}"
        return
      fi
    done
  fi
}

# --- helpers ---------------------------------------------------------------

usage() { sed -n '2,/^set /{/^set /d;s/^# \{0,1\}//;p}' "$0"; }

list_checks() {
  info "Available checks:"
  info "  validate   Godot import / script-validation (godot-ci.yml)"
  info "  test       GUT unit suite (godot-ci.yml)"
  info "  chars      non-standard characters in docs (check-non-standard-chars.yml)"
  info "  comments   issue/PR-number citations in NEW GDScript comment lines (check-comment-citations.yml)"
  info "  units      units-convention lint on NEW GDScript lines (docs/units-convention.md)"
  info "  coverage   instrumented GUT suite -> coverage/lcov.info (test-coverage.yml)"
  info "  patch_coverage  local codecov/patch gate for this diff's scripts/*.gd changes (fails below the effective target)"
  info "  links      Markdown link-check via lychee (check-links.yml)"
  info "  demo_defects  deterministic defect scan of this diff's changed demo input scripts (demo-video.yml)"
  info ""
  info "Default (no args): ${DEFAULT_CHECKS[*]}"
  info "all              : ${ALL_CHECKS[*]}"
}

have() { command -v "$1" >/dev/null 2>&1; }

require_godot() {
  if ! have "$GODOT_BIN"; then
    err "Godot binary '$GODOT_BIN' not found. Install Godot 4.7 (Standard) or set GODOT_BIN."
    err "See README.md ('Running Godot headlessly') for the download snippet."
    return 1
  fi
}

# Vendor GUT into addons/gut if it isn't already there — the same way CI and the
# session-start hook do it (GUT is intentionally not committed). The test files
# extend GutTest, so it must be present before 'validate' imports the project.
ensure_gut() {
  if [ -d "$PROJECT_ROOT/addons/gut" ]; then
    return 0
  fi
  info "Vendoring GUT $GUT_VERSION (not committed; cloned on demand)..."
  # A private temp dir (not a fixed path) so two overlapping runs — e.g. a manual
  # run while an editor task does the same — don't clobber each other's clone.
  local gut_tmp; gut_tmp="$(mktemp -d)"
  if ! git clone --depth 1 --branch "$GUT_VERSION" \
      https://github.com/bitwes/Gut.git "$gut_tmp" >/dev/null 2>&1; then
    err "Failed to clone GUT $GUT_VERSION."
    rm -rf "$gut_tmp"
    return 1
  fi
  # Install atomically: copy into a staging dir on the same filesystem, then
  # rename it into place. A crash mid-copy then leaves only the staging dir, not a
  # half-populated addons/gut that the early-return check above would treat as a
  # valid install on the next run.
  mkdir -p "$PROJECT_ROOT/addons"
  local staging="$PROJECT_ROOT/addons/.gut-staging.$$"
  rm -rf "$staging"
  if ! cp -r "$gut_tmp/addons/gut" "$staging"; then
    err "Failed to install GUT into addons/gut."
    rm -rf "$gut_tmp" "$staging"
    return 1
  fi
  rm -rf "$gut_tmp"
  # A concurrent run may have installed GUT between the early-return check above
  # and now; if so, use theirs and drop our staging copy. This also sidesteps
  # POSIX `mv`'s "move into an existing directory" behaviour, which would
  # otherwise deposit the staging dir *inside* a valid addons/gut.
  if [ -d "$PROJECT_ROOT/addons/gut" ]; then
    rm -rf "$staging"
    return 0
  fi
  if ! mv "$staging" "$PROJECT_ROOT/addons/gut"; then
    err "Failed to move GUT into addons/gut."
    rm -rf "$staging"
    return 1
  fi
}

# Pre-flight: warn when Godot processes have already piled up — the early
# signal of an orphan leak building up (hung headless runs whose calling shell
# died), and the likely explanation for slow or flaky local runs. Warn-only:
# concurrent sessions legitimately run a few Godot processes, so this never
# fails the checks. Sweep with tools/kill-orphan-godot.ps1 / .sh (see there).
preflight_godot_count() {
  local limit="${SPARTA_GODOT_PREFLIGHT_LIMIT:-5}" count=""
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      # MSYS ps can't see native Windows processes; tasklist can. The bracketed
      # pattern keeps grep from matching its own command line.
      count="$(tasklist 2>/dev/null | grep -ci '[g]odot')"
      ;;
    *)
      count="$(ps -eo args= 2>/dev/null | grep -ci '[g]odot')"
      ;;
  esac
  # Unparseable count (no ps/tasklist, unexpected output): skip silently — the
  # pre-flight is best-effort and must never block the checks themselves.
  case "$count" in ''|*[!0-9]*) return 0 ;; esac
  if [ "$count" -gt "$limit" ]; then
    warn "Pre-flight: $count Godot processes are already running (warn limit: $limit)."
    warn "That's the early sign of an orphan leak (hung runs whose shell died) and can starve this run."
    warn "Sweep with tools/kill-orphan-godot.ps1 (Windows) or tools/kill-orphan-godot.sh — dry-run by default."
  fi
}

# --- checks ----------------------------------------------------------------
# Each returns 0 on pass, non-zero on fail.

# has_script_errors <log> — true (and echoes the offending lines to stderr) when
# the log contains a Godot script/parse/compile error marker. Godot doesn't
# reliably turn these into a non-zero process exit code, and GUT's own -gexit
# exit code is no better: a test script that fails to parse is reported via a
# plain print() in test_collector.gd, not through the totals/errors counters
# -gexit derives its exit code from, so the script is silently dropped from the
# run (its tests never counted) while the suite still reports success. Godot
# does print these markers to the log regardless of which command hit them, so
# every check that runs Godot against project or test scripts greps for them.
has_script_errors() {
  local log="$1"
  grep -E "SCRIPT ERROR|Failed to load script|Parse Error|Compile Error" "$log" >&2
}

check_validate() {
  require_godot || return 1
  ensure_gut || return 1
  local log; log="$(mktemp)"
  # `--import` loads the project in full and reports compile/import errors, but
  # Godot doesn't reliably exit non-zero on script errors — so, like CI, we fail
  # on any error marker in the log. A timeout is the one exit status that IS
  # meaningful here: a killed run leaves a truncated log with no error markers,
  # which the grep below would wrongly read as a pass.
  local rc=0
  ( cd "$PROJECT_ROOT" && run_bounded "$VALIDATE_TIMEOUT" \
      "$GODOT_BIN" --headless --import --verbose ) >"$log" 2>&1 || rc=$?
  if run_bounded_timed_out "$rc"; then
    err "Godot import timed out after ${VALIDATE_TIMEOUT}s and was killed (no orphan left behind)."
    rm -f "$log"
    return 1
  fi
  # Send the matched error lines to stderr so all of this check's error output
  # (these plus the err() message below) stays on one stream.
  if has_script_errors "$log"; then
    err "Godot reported script/resource errors during import (see above)."
    rm -f "$log"
    return 1
  fi
  rm -f "$log"
  info "Project imported with no script/parse errors."
  # The import pass compiles only what the imported resources reach, so a parse error
  # in a script nothing references at import time (a tools/ helper, a scene-swapped
  # runner's dependency) sails past it and only surfaces at runtime. Sweep-load every
  # .gd to force full compilation; the sweep exits non-zero on any failure (and prints
  # which scripts broke).
  rc=0
  ( cd "$PROJECT_ROOT" && run_bounded "$VALIDATE_TIMEOUT" \
      "$GODOT_BIN" --headless -s tools/ci/compile_all_scripts.gd ) 2>&1 || rc=$?
  if run_bounded_timed_out "$rc"; then
    err "Script compile sweep timed out after ${VALIDATE_TIMEOUT}s and was killed (no orphan left behind)."
    return 1
  fi
  if [ "$rc" -ne 0 ]; then
    err "One or more scripts failed to compile (see the compile-sweep lines above)."
    return 1
  fi
}

check_test() {
  require_godot || return 1
  ensure_gut || return 1
  # If `coverage` (or `patch_coverage`, which internally calls check_coverage)
  # already ran THIS SAME invocation and the GUT suite itself came back clean,
  # reuse that instead of paying for a second full run -- check_coverage's run is
  # a strict superset of what `test` checks (same suite, same pass/fail
  # semantics, plus the identical has_script_errors guard). `main()` reorders the
  # requested checks so a coverage-shaped one runs before `test` whenever both
  # are requested, so this reliably fires instead of racing check ordering.
  #
  # Tracked via the internal `_suite_health` key, NOT `coverage`'s or
  # `patch_coverage`'s own overall pass/fail -- those can fail for reasons that
  # have nothing to do with the suite itself: `patch_coverage` fails when its
  # coverage PERCENTAGE is below target even on a perfectly clean suite run
  # (its main, intended failure mode -- not a corner case), and `coverage` fails
  # if the lcov.info report write itself glitches after a clean run. Either
  # would wrongly report `test` as failed too if this checked their overall
  # result directly. See check_coverage's own set_result calls for where
  # `_suite_health` actually gets recorded. An empty result (neither coverage
  # nor patch_coverage's internal run reached this invocation) falls through to
  # the real run below.
  case "$(get_result _suite_health)" in
    fail)
      err "The coverage-instrumented suite already failed earlier in this run -- not re-running test."
      return 1
      ;;
    pass)
      info "coverage (or patch_coverage) already ran the full suite this invocation -- skipping the redundant plain run."
      return 0
      ;;
  esac
  # gut_cmdln runs the suite without enabling the editor plugin; -gexit makes it
  # exit non-zero if any test fails or errors -- but NOT if a test script fails
  # to parse (see has_script_errors above). Tee the output so the run still
  # streams live, and fail on the same script/parse-error markers
  # check_validate already fails on.
  local log; log="$(mktemp)"
  local rc=0
  ( cd "$PROJECT_ROOT" && run_bounded "$TEST_TIMEOUT" \
      "$GODOT_BIN" --headless -s addons/gut/gut_cmdln.gd \
      -gdir=res://test -ginclude_subdirs -gexit ) 2>&1 | tee "$log"
  rc="${PIPESTATUS[0]}"
  if run_bounded_timed_out "$rc"; then
    err "GUT suite timed out after ${TEST_TIMEOUT}s and was killed (no orphan left behind)."
    rm -f "$log"
    return 1
  fi
  if [ "$rc" -ne 0 ]; then
    rm -f "$log"
    return "$rc"
  fi
  # A clean exit code alone doesn't prove every test script actually ran --
  # confirm none of them failed to parse/load.
  if has_script_errors "$log"; then
    err "GUT reported script/parse errors during the run (see above) -- at least one"
    err "test script failed to load and its tests were silently skipped, even though"
    err "the suite reported success. Fix the broken script; a passing run must load"
    err "every test script."
    rm -f "$log"
    return 1
  fi
  rm -f "$log"
  return 0
}

check_coverage() {
  require_godot || return 1
  ensure_gut || return 1
  # Same run as `test`, plus the GUT pre/post hooks that instrument res://scripts
  # and write an lcov report. Mirrors .github/workflows/test-coverage.yml. Not in
  # the default set — instrumentation is slower and coverage never gates. The
  # report lands at coverage/lcov.info (git-ignored); see test/README.md.
  #
  # Tee to a log and check has_script_errors, exactly like check_test does: this
  # run is meant to be a strict superset of `test` (see check_test's own
  # short-circuit, which skips a redundant plain run when this one already passed
  # this invocation) -- it has to catch everything `test` would, not just run the
  # same suite with looser scrutiny.
  local log; log="$(mktemp)"
  local rc=0
  ( cd "$PROJECT_ROOT" && COVERAGE_LCOV_FILE=res://coverage/lcov.info \
      run_bounded "$COVERAGE_TIMEOUT" \
      "$GODOT_BIN" --headless -s addons/gut/gut_cmdln.gd \
      -gdir=res://test -ginclude_subdirs -gexit \
      -gpre_run_script=res://test/pre_run_hook.gd \
      -gpost_run_script=res://test/post_run_hook.gd ) 2>&1 | tee "$log"
  rc="${PIPESTATUS[0]}"
  if run_bounded_timed_out "$rc"; then
    err "Coverage run timed out after ${COVERAGE_TIMEOUT}s and was killed (no orphan left behind)."
    rm -f "$log"
    set_result _suite_health fail
    return 1
  fi
  if [ "$rc" -ne 0 ]; then
    rm -f "$log"
    set_result _suite_health fail
    return "$rc"
  fi
  if has_script_errors "$log"; then
    err "GUT reported script/parse errors during the coverage run (see above) -- at least"
    err "one test script failed to load and its tests were silently skipped, even though"
    err "the suite reported success. Fix the broken script; a passing run must load"
    err "every test script."
    rm -f "$log"
    set_result _suite_health fail
    return 1
  fi
  rm -f "$log"
  # The GUT run itself is clean at this point -- record that under its own key,
  # distinct from this function's overall pass/fail below (which also depends on
  # the lcov write succeeding -- a report-writing glitch there doesn't mean any
  # test failed, so it must not be conflated with suite health; check_test's own
  # short-circuit reads _suite_health specifically to avoid exactly that).
  set_result _suite_health pass
  # The post-run hook reports a failed lcov write with push_error(), which does
  # not make Godot exit non-zero, so a clean exit above doesn't prove the report
  # was written. Confirm the file exists before claiming success.
  if [ ! -s "$PROJECT_ROOT/coverage/lcov.info" ]; then
    err "coverage/lcov.info was not written — see the post_run_hook output above."
    return 1
  fi
  info "Coverage report written to coverage/lcov.info"
}

# resolve_patch_coverage_base — same shape as resolve_comments_base (see there
# for the "why" of each fallback step), kept as its own function/env var rather
# than shared: the two checks diff against a base for unrelated reasons (new
# comment lines vs. newly-added executable lines) and a caller may reasonably
# want to point them at different refs.
resolve_patch_coverage_base() {
  local candidate
  for candidate in "${SPARTA_CHECK_PATCH_COVERAGE_BASE:-}" "origin/main" "main"; do
    [ -n "$candidate" ] || continue
    case "$candidate" in
      0000000000000000000000000000000000000000) continue ;;
    esac
    if ( cd "$PROJECT_ROOT" && git rev-parse --verify --quiet "${candidate}^{commit}" >/dev/null 2>&1 ); then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

check_patch_coverage() {
  # Codecov's codecov/patch check, computed locally: what fraction of the lines
  # THIS diff adds under scripts/ (recursively -- campaign/ and any other
  # subdirectory included, same as Godot's coverage instrumentation, which
  # walks the whole tree) are covered by the GUT suite. FAILS when that
  # fraction lands below the effective target, mirroring how the codecov/patch
  # status check itself judges a PR: its default `target: auto` compares patch
  # coverage against the project-wide total, approximated here from the
  # regenerated report's own LH:/LF: records (Codecov uses the PR base's
  # total; the local report is HEAD's -- the closest number available without
  # a second instrumented run, differing only by this diff's own effect on
  # the total). SPARTA_CHECK_PATCH_COVERAGE_TARGET overrides the auto target
  # with a fixed percentage. Not in the default set only because it inherits
  # `coverage`'s ~15-20 min runtime. Run it explicitly, or via `all`, before
  # pushing a scripts/ change.
  #
  # The diff/base checks below run BEFORE the expensive coverage regeneration
  # (not after, as an earlier version of this check did) so a diff with no
  # scripts/ changes -- or no resolvable base -- skips instantly instead of
  # always paying the ~15-20 min instrumented run first only to then discover
  # there was nothing to check.
  local base
  if ! base="$(resolve_patch_coverage_base)"; then
    warn "No base ref to diff against -- skipping patch coverage."
    warn "Set SPARTA_CHECK_PATCH_COVERAGE_BASE, or fetch full history (git fetch --unshallow)."
    set_result patch_coverage skip
    return 0
  fi

  local merge_base head
  merge_base="$(cd "$PROJECT_ROOT" && git merge-base HEAD "$base" 2>/dev/null)"
  head="$(cd "$PROJECT_ROOT" && git rev-parse HEAD 2>/dev/null)"
  if [ -z "$merge_base" ]; then
    warn "No common history with '$base' -- skipping patch coverage."
    set_result patch_coverage skip
    return 0
  fi
  if [ "$merge_base" = "$head" ]; then
    info "HEAD is '$base' (or an ancestor of it) -- no new commits to check."
    return 0
  fi

  local diff
  # ':(glob)scripts/**/*.gd': a bare non-magic pathspec like 'scripts/*.gd'
  # (no ':(glob)' prefix) ALREADY matches every subdirectory too -- this is
  # NOT the same rule as the ':(glob)' magic word (which DOES set
  # FNM_PATHNAME, so '*' does NOT cross '/' without an explicit '**'). Per
  # gitglossary(7)'s own "pathspec" definition (the non-magic case, distinct
  # from its separate "glob" magic-word entry): "the rest of the pathspec is
  # a pattern for the remainder of the pathname. Paths ... will be matched
  # ... using fnmatch(3); in particular, '*' and '?' can match directory
  # separators", with the example "Documentation/*.jpg will match ...
  # including Documentation/chapter_1/figure_1.jpg". Also verified directly
  # against a real scripts/campaign/*.gd-touching commit in this repo's own
  # history (a 3-way `git diff --stat` comparison: no-pathspec, bare
  # 'scripts/*.gd', and ':(glob)scripts/*.gd' -- the first two match
  # identically; the third matches nothing). The explicit ':(glob)' + '**'
  # form here produces the identical match set to the bare form; it's kept
  # only because it states the "recurse into every subdirectory" intent
  # explicitly for a reader who doesn't already know this non-magic-pathspec
  # quirk, not because the simpler form was ever wrong.
  diff="$(cd "$PROJECT_ROOT" && git diff --no-color -U0 "$merge_base" HEAD -- ':(glob)scripts/**/*.gd')"
  if [ -z "$diff" ]; then
    info "No scripts/**/*.gd changes in this diff."
    return 0
  fi

  # Only regenerate coverage/lcov.info if `coverage` hasn't already RUN
  # earlier in THIS SAME invocation (e.g. `tools/check.sh all`, or
  # `tools/check.sh coverage patch_coverage`) -- avoids running the ~15-20 min
  # instrumented suite twice for one invocation. A standalone `patch_coverage`
  # run (the common case: checking one diff before pushing) still always
  # regenerates, since there's no earlier run in this invocation to trust, and
  # a stale report from a previous diff would silently answer the wrong
  # question.
  #
  # Three cases, not two: an EMPTY result (not attempted this invocation) is
  # the only one that should trigger a fresh run here. "pass" reuses the
  # report already on disk. "fail" means `coverage` already ran and failed
  # this same invocation -- re-running it would just pay the full ~15-20 min
  # cost again to fail the same way, so fail fast instead.
  case "$(get_result coverage)" in
    pass) ;;
    fail) err "coverage already failed earlier in this run -- not regenerating."; return 1 ;;
    *)    check_coverage || return 1 ;;
  esac

  # added_lines: "file:line" for every line this diff ADDS under scripts/ (same
  # "+++ b/<path>" / "@@ ... +<start> @@" tracking check_comments uses, minus
  # its comment-citation filter -- every added line is a candidate here, not
  # just comment ones).
  local added_lines
  added_lines="$(printf '%s\n' "$diff" | awk '
      /^\+\+\+ / { file = substr($0, 7); next }
      /^@@ /     { match($0, /\+[0-9]+/); line = substr($0, RSTART + 1, RLENGTH - 1) + 0; next }
      /^\+/      { print file ":" line; line++; next }
      { next }
    ')"
  if [ -z "$added_lines" ]; then
    info "No added lines in this diff's scripts/*.gd files (deletions only)."
    return 0
  fi

  local lcov="$PROJECT_ROOT/coverage/lcov.info"
  # Cross-reference added_lines against the lcov DA records: a line present in
  # lcov is "coverable" (Godot's coverage tool instrumented it); coverable-and-
  # hit counts as covered. A line absent from lcov entirely (a comment, a blank
  # line, a declaration the instrumenter skips) is excluded from the
  # denominator -- matching how Codecov itself treats non-executable lines, so
  # this number is directly comparable to the codecov/patch check on GitHub.
  local report
  report="$(awk -v added="$added_lines" '
      BEGIN {
        # arr[file, line] (comma-subscript), not arr[file][line] -- the latter is
        # a GNU-awk-only true-nested-array extension; the comma form (which awk
        # folds into one string key via SUBSEP) is POSIX and works on the BSD/mawk
        # awk macOS ships, matching the no-GNU-extras portability target the rest
        # of this file targets (see tools/README.md).
        n = split(added, rows, "\n")
        for (i = 1; i <= n; i++) {
          split(rows[i], parts, ":")
          is_added[parts[1], parts[2]] = 1
        }
      }
      /^SF:/ { file = substr($0, 4); next }
      /^DA:/ {
        split(substr($0, 4), parts, ",")
        ln = parts[1]; count = parts[2]
        if ((file, ln) in is_added) {
          coverable[file]++
          total_coverable++
          if (count + 0 > 0) {
            hit[file]++
            total_hit++
          } else {
            missing[file] = missing[file] (missing[file] == "" ? "" : ",") ln
          }
        }
        next
      }
      END {
        for (f in coverable) {
          printf "%-55s %6d/%-6d  missing: %s\n", f, hit[f]+0, coverable[f], missing[f]
        }
        if (total_coverable == 0) {
          print "NO_COVERABLE_LINES"
        } else {
          printf "TOTAL %d/%d %.2f\n", total_hit, total_coverable, (100.0 * total_hit / total_coverable)
        }
      }
    ' "$lcov")"

  if printf '%s' "$report" | grep -q '^NO_COVERABLE_LINES$'; then
    info "This diff's added lines are all outside what Godot's coverage tool instruments"
    info "(comments, blank lines, declarations) -- nothing to report."
    return 0
  fi

  printf '%s\n' "$report" | grep -v '^TOTAL '
  local total_line pct fraction
  total_line="$(printf '%s\n' "$report" | grep '^TOTAL ')"
  pct="$(printf '%s' "$total_line" | awk '{print $NF}')"
  fraction="$(printf '%s' "$total_line" | awk '{print $2}')"

  # Effective target, mirroring codecov/patch's default `target: auto` (see
  # the header comment): the project-wide line coverage from the report just
  # regenerated, unless SPARTA_CHECK_PATCH_COVERAGE_TARGET pins a fixed one.
  local target target_src
  if [ -n "${SPARTA_CHECK_PATCH_COVERAGE_TARGET:-}" ]; then
    case "$SPARTA_CHECK_PATCH_COVERAGE_TARGET" in
      *[!0-9.]*|'') err "SPARTA_CHECK_PATCH_COVERAGE_TARGET must be a bare percentage number, got '${SPARTA_CHECK_PATCH_COVERAGE_TARGET}'."; return 1 ;;
    esac
    target="$SPARTA_CHECK_PATCH_COVERAGE_TARGET"
    target_src="SPARTA_CHECK_PATCH_COVERAGE_TARGET"
  else
    target="$(awk -F: '/^LH:/ { h += $2 } /^LF:/ { f += $2 } END { if (f > 0) printf "%.2f", 100.0 * h / f }' "$lcov")"
    target_src="auto: project-wide total from coverage/lcov.info"
  fi
  if [ -z "$target" ]; then
    info ""
    info "Patch coverage: ${fraction} = ${pct}%"
    warn "Could not compute an auto target (no LH:/LF: records in $lcov) -- not gating."
    return 0
  fi

  info ""
  info "Patch coverage: ${fraction} = ${pct}%  (target: ${target}% -- ${target_src})"
  info "(Codecov's codecov/patch check computes the same metric server-side against this PR's base;"
  info "this is a local approximation -- see tools/README.md.)"
  if ! awk -v p="$pct" -v t="$target" 'BEGIN { exit !(p + 0 >= t + 0) }'; then
    err "Patch coverage ${pct}% is below the target ${target}% -- codecov/patch would fail this diff."
    err "Cover the missing lines listed above, or see tools/README.md ('Checking patch coverage"
    err "before you push') for the structurally-hard-to-cover escape hatch."
    return 1
  fi
}

check_chars() {
  # Flag curly quotes and en/em dashes in the Quarto docs, which are kept
  # plain-ASCII so pandoc's smart typography renders them. The flagged characters
  # are U+2018/2019 (' '), U+201C/201D (" "), U+2013/2014 (en/em dash).
  #
  # Matching is done with `grep -F` over the literal UTF-8 byte sequences (built
  # via printf's octal escapes) rather than `grep -P '\x{...}'`: -P is a GNU
  # extension absent from the BSD grep that ships on macOS, whereas fixed-string
  # byte matching is portable and needs no special locale.
  local lsq rsq ldq rdq endash emdash
  lsq="$(printf '\342\200\230')"; rsq="$(printf '\342\200\231')"
  ldq="$(printf '\342\200\234')"; rdq="$(printf '\342\200\235')"
  endash="$(printf '\342\200\223')"; emdash="$(printf '\342\200\224')"

  # Collect the tracked docs null-delimited (handles spaces/newlines) and skip
  # cleanly when there are none — avoids relying on GNU xargs' -r and stops grep
  # from blocking on stdin if the file list is empty.
  local files=()
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(cd "$PROJECT_ROOT" && git ls-files -z '*.qmd' '*.R')
  if [ ${#files[@]} -eq 0 ]; then
    info "No docs to check."
    return 0
  fi

  local out
  out="$(cd "$PROJECT_ROOT" && grep -nF \
      -e "$lsq" -e "$rsq" -e "$ldq" -e "$rdq" -e "$endash" -e "$emdash" \
      "${files[@]}" 2>/dev/null)"
  if [ -n "$out" ]; then
    err "Non-standard characters found (use straight quotes and ASCII '-'):"
    printf '%s\n' "$out" >&2
    return 1
  fi
  info "Docs are free of curly quotes / en-em dashes."
}

# resolve_comments_base — print the first candidate commit-ish that both (a) is
# non-empty and not git's all-zero "no such commit" sentinel (the value a push
# event's `before` takes on a brand-new branch), and (b) actually resolves in
# this checkout, or fail if none do. Candidates, in order: an explicit
# SPARTA_CHECK_COMMENTS_BASE override (CI sets this per-event -- see
# check-comment-citations.yml), then origin/main, then a local main branch --
# the same "best available" fallback a developer's own checkout would have.
resolve_comments_base() {
  local candidate
  for candidate in "${SPARTA_CHECK_COMMENTS_BASE:-}" "origin/main" "main"; do
    [ -n "$candidate" ] || continue
    case "$candidate" in
      0000000000000000000000000000000000000000) continue ;;
    esac
    if ( cd "$PROJECT_ROOT" && git rev-parse --verify --quiet "${candidate}^{commit}" >/dev/null 2>&1 ); then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

check_comments() {
  # Flag NEW issue/PR-number citations (#123) introduced by ADDED lines in this
  # diff's GDScript comments -- CLAUDE.md's "Comments: no issue-number
  # references" rule under "Code conventions". Scoped to the diff against a base
  # ref, not a whole-tree grep of every tracked *.gd file: a repo-wide scan fails
  # on every pre-existing citation -- including ones that predate this check
  # itself -- in files this change never touched, which would fail forever
  # rather than catching only what's actually new. TODO(#N):/FIXME(#N): are
  # explicitly allowed by that rule (they link outstanding work, not explain the
  # code).
  #
  # Matching is intentionally narrow, same as before rescoping: a citation is a
  # '#' immediately followed by 2-4 digits and a word boundary -- misses
  # single-digit hashes (rank/slot markers like "#5") and never fires on a hex
  # colour literal (Color("#3355ff") has letters; a purely-numeric 6/8-digit one
  # like "#000000" fails the word-boundary check, since more digits immediately
  # follow the 4-digit match attempt).
  local base
  if ! base="$(resolve_comments_base)"; then
    warn "No base ref to diff against (shallow checkout, no 'main'/'origin/main',"
    warn "or a brand-new branch with no shared history) -- skipping the"
    warn "comment-citation check rather than scanning the whole tree."
    warn "Set SPARTA_CHECK_COMMENTS_BASE, or fetch full history (git fetch --unshallow)."
    set_result comments skip
    return 0
  fi

  local merge_base head
  merge_base="$(cd "$PROJECT_ROOT" && git merge-base HEAD "$base" 2>/dev/null)"
  head="$(cd "$PROJECT_ROOT" && git rev-parse HEAD 2>/dev/null)"
  if [ -z "$merge_base" ]; then
    warn "No common history with '$base' -- skipping the comment-citation check."
    set_result comments skip
    return 0
  fi
  if [ "$merge_base" = "$head" ]; then
    info "HEAD is '$base' (or an ancestor of it) -- no new commits to check."
    return 0
  fi

  local diff
  diff="$(cd "$PROJECT_ROOT" && git diff --no-color -U0 "$merge_base" HEAD -- '*.gd')"
  if [ -z "$diff" ]; then
    info "No GDScript changes in this diff."
    return 0
  fi

  # Turn the unified diff into "file:line:content" rows for each ADDED line
  # only (tracking the current file from "+++ b/<path>" headers and the
  # current line number from "@@ ... +<start>,<count> @@" hunk headers), so the
  # citation regex below only ever sees lines this diff actually introduces.
  local out
  out="$(printf '%s\n' "$diff" | awk '
      /^\+\+\+ / { file = substr($0, 7); next }
      /^@@ /     { match($0, /\+[0-9]+/); line = substr($0, RSTART + 1, RLENGTH - 1) + 0; next }
      /^\+/      { print file ":" line ":" substr($0, 2); line++; next }
      { next }
    ' | grep -E '#[0-9]{2,4}\b' | grep -vE '(TODO|FIXME)\(#[0-9]+\):')"

  if [ -n "$out" ]; then
    err "Issue/PR-number citations found in new/changed GDScript comment lines"
    err "(CLAUDE.md: explain the change on its own terms, not by pointing at a"
    err "tracker link -- only TODO(#N):/FIXME(#N): are allowed):"
    printf '%s\n' "$out" >&2
    return 1
  fi
  info "No new issue/PR-number citations found in this diff's GDScript comments."
}

check_units() {
  # Units-convention lint (docs/units-convention.md): sim geometry is authored
  # in metres and stored in world units, converted ONLY inside const
  # initializers or the few allowlisted boundary files. Diff-scoped like
  # check_comments -- fires only on lines this change ADDS, never legacy code,
  # so a repo-wide backlog cannot fail it. Reuses the same base resolution (and
  # SPARTA_CHECK_COMMENTS_BASE override) so local and CI agree.
  #
  # Three rules on added *.gd lines:
  #  1. FAIL  -- multiplying by WU_PER_M / WORLD_UNITS_PER_METER anywhere but a
  #     const initializer, outside the allowlisted boundary files: a stray
  #     runtime conversion is either a hot-loop cost or a unit-mixing bug.
  #  2. FAIL  -- the legacy "bare wu literal + metric comment" style
  #     (e.g. `= 9.0  # 0.45 m`): promote the comment to a metric expression
  #     (`0.45 * WorldScaleRef.WU_PER_M`) or mark the value `# tuned in wu`.
  #  3. WARN  -- a new length/speed-named const with a bare literal and neither
  #     a WU_PER_M expression nor a `# tuned in wu` marker. Warning-level only:
  #     the name heuristic has false positives, so it nudges review rather than
  #     gating.
  local base
  if ! base="$(resolve_comments_base)"; then
    warn "No base ref to diff against -- skipping the units-convention check."
    warn "Set SPARTA_CHECK_COMMENTS_BASE, or fetch full history."
    set_result units skip
    return 0
  fi

  local merge_base head
  merge_base="$(cd "$PROJECT_ROOT" && git merge-base HEAD "$base" 2>/dev/null)"
  head="$(cd "$PROJECT_ROOT" && git rev-parse HEAD 2>/dev/null)"
  if [ -z "$merge_base" ]; then
    warn "No common history with '$base' -- skipping the units-convention check."
    set_result units skip
    return 0
  fi
  if [ "$merge_base" = "$head" ]; then
    info "HEAD is '$base' (or an ancestor of it) -- no new commits to check."
    return 0
  fi

  local diff
  diff="$(cd "$PROJECT_ROOT" && git diff --no-color -U0 "$merge_base" HEAD -- "*.gd")"
  if [ -z "$diff" ]; then
    info "No GDScript changes in this diff."
    return 0
  fi

  # "file:line:content" rows for ADDED lines only (same awk as check_comments).
  local added
  added="$(printf '%s\n' "$diff" | awk '
      /^\+\+\+ / { file = substr($0, 7); next }
      /^@@ /     { match($0, /\+[0-9]+/); line = substr($0, RSTART + 1, RLENGTH - 1) + 0; next }
      /^\+/      { print file ":" line ":" substr($0, 2); line++; next }
      { next }
    ')"

  # Boundary files where runtime use of the scale constant is the whole point.
  # (Battle.gd is allowlisted file-level for its spawn/loadout conversion; the
  # lint pins boundary topology, review pins placement within the file.)
  local allow='^(scripts/(WorldScale|Battle|DistanceLegend)\.gd|test/)'

  # The stray-conversion rule must judge CODE, not prose: a trailing comment
  # that merely mentions the constant ("do not scale by * WU_PER_M") is a
  # legitimate -- even encouraged -- thing to write. Strip everything from the
  # first '#' in the content portion before matching. (A '#' inside a GDScript
  # string literal would be over-stripped; sim code doesn't hit that in
  # practice, and over-stripping only makes the rule more lenient.)
  local code_only
  code_only="$(printf '%s\n' "$added" | sed 's/#.*$//')"

  local stray
  stray="$(printf '%s\n' "$code_only" \
    | grep -E '\*\s*(WorldScaleRef\.WU_PER_M|WorldScale\.WU_PER_M|WU_PER_M|WORLD_UNITS_PER_METER)\b|(WU_PER_M|WORLD_UNITS_PER_METER)\s*\*' \
    | grep -vE "$allow" \
    | grep -vE '^[^:]+:[0-9]+:\s*const\s')"
  if [ -n "$stray" ]; then
    err "Runtime metric->world conversion outside the allowed boundaries"
    err "(docs/units-convention.md: conversions live in const initializers, or in"
    err "WorldScale.gd / Battle.gd loadout spawn / DistanceLegend.gd / test/):"
    printf '%s\n' "$stray" >&2
    return 1
  fi

  # Tightly anchored to the documented legacy style (`9.0  # 0.45 m`): the
  # comment must consist of exactly a metric figure and end there, so prose
  # that merely mentions a metric quantity ("spans the 80 m x 50 m field")
  # next to an unrelated float never gates the build.
  local legacy
  legacy="$(printf '%s\n' "$added" \
    | grep -E ':?=\s*-?[0-9]+\.[0-9]+\s*#\s*~?[0-9][0-9.]*\s*m(/s2?)?\s*$' \
    | grep -vE 'WU_PER_M|WORLD_UNITS_PER_METER|# tuned in wu')"
  if [ -n "$legacy" ]; then
    err "Bare world-unit literal documented by a metric comment (the pre-migration"
    err "style). Promote the comment to the value: <metres> * WorldScaleRef.WU_PER_M"
    err "-- or mark a deliberately unit-tuned knob with '# tuned in wu':"
    printf '%s\n' "$legacy" >&2
    return 1
  fi

  local nudge
  nudge="$(printf '%s\n' "$added" \
    | grep -E 'const\s+[A-Z0-9_]*(_RADIUS|_RANGE|_DIST|_DISTANCE|_SPACING|_SPEED)[A-Z0-9_]*(\s*:\s*float)?\s*:?=\s*-?[0-9]' \
    | grep -vE 'WU_PER_M|WORLD_UNITS_PER_METER|# tuned in wu')"
  if [ -n "$nudge" ]; then
    warn "New length/speed-named const(s) with a bare literal -- consider authoring"
    warn "in metres (<metres> * WorldScaleRef.WU_PER_M) or marking '# tuned in wu'"
    warn "(review nudge only, not a failure):"
    printf '%s\n' "$nudge" >&2
  fi
  info "No units-convention violations in this diff's added GDScript lines."
}


check_links() {
  if ! have lychee; then
    warn "lychee not installed — skipping link check."
    warn "Install it from https://github.com/lycheeverse/lychee, then re-run."
    set_result links skip
    return 0
  fi
  # Null-delimited so filenames with spaces survive into lychee's argv. Note this
  # is a bare lychee run; the CI workflow delegates to d-morrison/gha's reusable
  # check-links.yml, which may carry its own ignore-list/timeout config, so a
  # local pass here doesn't guarantee an identical CI result.
  local files=()
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(cd "$PROJECT_ROOT" && git ls-files -z '*.md')
  if [ ${#files[@]} -eq 0 ]; then
    info "No Markdown files to check."
    return 0
  fi
  ( cd "$PROJECT_ROOT" && lychee --no-progress "${files[@]}" )
}

# --- driver ----------------------------------------------------------------

check_demo_defects() {
  # Deterministic demo defect scan: every scripted-input demo this change adds or
  # edits gets a FULL state dump and a DemoDefects verdict pass -- the formation
  # defect metrics plus the script's own declared expectations, exit-code gated
  # (see tools/demo/analyze_transcript.gd). Diff-scoped like check_units, so
  # legacy demos never fail it. Each changed script drives a real headless
  # battle, so budget a few seconds to a minute apiece.
  require_godot || return 1
  if ! have jq; then
    warn "jq not found -- skipping the demo defect scan."
    set_result demo_defects skip
    return 0
  fi
  local base
  if ! base="$(resolve_comments_base)"; then
    warn "No base ref to diff against -- skipping the demo defect scan."
    warn "Set SPARTA_CHECK_COMMENTS_BASE, or fetch full history."
    set_result demo_defects skip
    return 0
  fi
  local changed
  changed="$(cd "$PROJECT_ROOT" && git diff --no-color --name-only "$base" HEAD -- ':(glob)demos/inputs/*.json')"
  if [ -z "$changed" ]; then
    info "No changed demo input scripts -- nothing to scan."
    set_result demo_defects skip
    return 0
  fi
  local failed=0 script ticks dir rc
  while IFS= read -r script; do
    [ -f "$PROJECT_ROOT/$script" ] || continue   # deleted in this diff
    # The scan's tick set is the script's own: its `state` defaults plus every
    # declared expectation tick (ranges contribute both ends), matching what a
    # dump run arms. A script declaring neither gets a generic early-to-mid
    # sampling so the scan still sees the battle develop.
    ticks="$(jq -r '((.state // []) + ([.expect // [] | .[] | .tick? // empty] | flatten)) | map(tonumber? // empty) | unique | map(tostring) | join(",")' "$PROJECT_ROOT/$script" 2>/dev/null || true)"
    [ -z "$ticks" ] && ticks="8,60,120,180,240,300"
    dir="$(mktemp -d)"
    info "Scanning $script at ticks $ticks"
    # Same grading as the CI step: a failed dump and an unusable-input analyzer exit
    # (rc 2) WARN rather than fail -- absence of data is not a defect -- and only a
    # genuine defect verdict (rc 1) fails, so local and CI verdicts stay in sync.
    if ! SPARTA_DEMO_STATE_FULL=1 \
         "$PROJECT_ROOT/tools/demo/dump-state.sh" "$script" "$ticks" "$dir" >/dev/null 2>&1; then
      warn "State dump failed for $script -- skipping its scan (CI warns the same way)."
      continue
    fi
    # Bash 3.2 (macOS's system bash, a supported target) errors expanding an empty
    # array under `set -u`, so branch on whether --expect applies instead of
    # expanding a maybe-empty argument array.
    rc=0
    if jq -e '.expect | type == "array" and length > 0' "$PROJECT_ROOT/$script" >/dev/null 2>&1; then
      "$GODOT_BIN" --headless --path "$PROJECT_ROOT" -s tools/demo/analyze_transcript.gd -- \
        "$dir" --expect "$PROJECT_ROOT/$script" || rc=$?
    else
      "$GODOT_BIN" --headless --path "$PROJECT_ROOT" -s tools/demo/analyze_transcript.gd -- \
        "$dir" || rc=$?
    fi
    if [ "$rc" -eq 1 ]; then
      err "Defect scan failed for $script"
      failed=1
    elif [ "$rc" -ne 0 ]; then
      warn "Defect scan input unusable for $script (rc=$rc); nothing gated."
    fi
  done <<< "$changed"
  if [ "$failed" -ne 0 ]; then
    set_result demo_defects fail
    return 1
  fi
  return 0
}

run_check() {
  local name="$1"
  section "$name"
  local fn="check_${name}"
  if ! declare -F "$fn" >/dev/null; then
    err "Unknown check: $name (try --list)"
    set_result "$name" fail
    return 1
  fi
  if "$fn"; then
    # A check may have set its own result (e.g. 'skip'); default to pass.
    if [ -z "$(get_result "$name")" ]; then
      set_result "$name" pass
    fi
  else
    set_result "$name" fail
  fi
}

main() {
  local checks=()
  for arg in "$@"; do
    case "$arg" in
      -h|--help) usage; exit 0 ;;
      -l|--list) list_checks; exit 0 ;;
      all)       checks+=("${ALL_CHECKS[@]}") ;;
      validate|test|chars|comments|units|coverage|patch_coverage|links|demo_defects) checks+=("$arg") ;;
      *) err "Unknown argument: $arg"; usage; exit 2 ;;
    esac
  done
  if [ ${#checks[@]} -eq 0 ]; then
    checks=("${DEFAULT_CHECKS[@]}")
  fi

  # De-duplicate (order-preserving) so e.g. `all validate` or repeated names run
  # each check once and print one summary line apiece.
  local deduped=() c seen name
  for c in "${checks[@]}"; do
    seen=""
    if [ ${#deduped[@]} -gt 0 ]; then
      for name in "${deduped[@]}"; do
        if [ "$name" = "$c" ]; then seen=1; break; fi
      done
    fi
    [ -z "$seen" ] && deduped+=("$c")
  done
  checks=("${deduped[@]}")

  # If both a plain `test` and a coverage-shaped check (`coverage`/`patch_coverage`)
  # were requested in this same invocation, run the coverage-shaped one FIRST --
  # check_test's own short-circuit (see its comment) only has something to reuse if
  # a coverage-shaped check already ran and recorded a result, and `test` sorts
  # before both in DEFAULT_CHECKS/ALL_CHECKS, so without this reorder it would
  # always run first and the short-circuit would never fire for `all` or any
  # explicit `test coverage`/`test patch_coverage` combination. Reinserts `test`
  # immediately after the first coverage-shaped check found, preserving every
  # other check's relative order.
  local has_test="" has_cov_shaped=""
  for c in "${checks[@]}"; do
    [ "$c" = "test" ] && has_test=1
    { [ "$c" = "coverage" ] || [ "$c" = "patch_coverage" ]; } && has_cov_shaped=1
  done
  if [ -n "$has_test" ] && [ -n "$has_cov_shaped" ]; then
    local reordered=() inserted=""
    for c in "${checks[@]}"; do
      [ "$c" = "test" ] && continue
      reordered+=("$c")
      if [ -z "$inserted" ] && { [ "$c" = "coverage" ] || [ "$c" = "patch_coverage" ]; }; then
        reordered+=("test")
        inserted=1
      fi
    done
    checks=("${reordered[@]}")
  fi

  preflight_godot_count

  for name in "${checks[@]}"; do
    run_check "$name" || true
  done

  # Summary.
  section "summary"
  local failed=0
  for name in "${checks[@]}"; do
    case "$(get_result "$name")" in
      pass) printf '  %sPASS%s  %s\n' "$C_GREEN" "$C_RESET" "$name" ;;
      skip) printf '  %sSKIP%s  %s\n' "$C_YELLOW" "$C_RESET" "$name" ;;
      *)    printf '  %sFAIL%s  %s\n' "$C_RED" "$C_RESET" "$name"; failed=1 ;;
    esac
  done
  if [ "$failed" -ne 0 ]; then
    printf '\n%sSome checks failed.%s\n' "$C_RED$C_BOLD" "$C_RESET"
    exit 1
  fi
  printf '\n%sAll checks passed.%s\n' "$C_GREEN$C_BOLD" "$C_RESET"
}

main "$@"
