## Battle-spawning GUT tests seed via `Replay.forced_seed`, not `Replay.rng.seed`

`Replay.rng` is a global autoload RNG (`scripts/Replay.gd`), and pinning it looks like the
obvious way to make a test's combat rolls deterministic.
That pin is dead code for any test that instantiates `res://scenes/Battle.tscn`, because
`Battle._ready()` calls `Replay.start_recording()`, and `start_recording()` unconditionally
does:

```gdscript
if forced_seed >= 0:
    seed_value = forced_seed
    forced_seed = -1
else:
    var picker := RandomNumberGenerator.new()
    picker.randomize()
    seed_value = picker.seed
rng.seed = seed_value
```

`forced_seed` defaults to `-1`, so an untouched battle randomizes `rng.seed` at spawn time --
silently clobbering whatever `rng.seed` a `before_each()` set beforehand.
The result is not a suite-order-dependent failure;
it is flaky, because each battle rerolls its own seed regardless of draw order.

**The wrong belief, stated plainly so it is not repeated:** "pin `Replay.rng.seed` in
`before_each()` for deterministic battle rolls, the way `test_all_out_attack.gd` does."
That convention is real, but it only works there because `test_all_out_attack.gd` builds bare
`Unit.new()` nodes and never instantiates `Battle.tscn` -- nothing calls
`Replay.start_recording()` to reseed out from under it.
Confirmed at `test/unit/test_all_out_attack.gd:50`, `Replay.rng.seed = 12345` inside
`before_each()`, with no `Battle.tscn` load anywhere in the file.

**The corrected convention, for any test that spawns a `Battle`:** set `Replay.forced_seed`
in the spawn helper *before* `add_child`, and reset it in `after_each()`.
Confirmed at `test/unit/test_battle_ai_general.gd`:

```gdscript
func after_each() -> void:
    Replay.forced_seed = -1

func <spawn helper>() -> void:
    Replay.forced_seed = 12345
    ...
    add_child_autofree(battle)   # Battle._ready() consumes forced_seed here
```

- **Do:** set `Replay.forced_seed = <n>` before `add_child`-ing a `Battle.tscn` instance, and
  reset it to `-1` in `after_each()` so a later test's own `start_recording()` randomizes
  normally rather than inheriting a stale forced seed.

- **Do:** keep pinning `Replay.rng.seed` in `before_each()` for a test that only builds bare
  `Unit.new()` nodes and never spawns `Battle.tscn`.

- **Don't:** pin `Replay.rng.seed` in a test that spawns `Battle.tscn` and expect it to stick --
  `Battle._ready()`'s `Replay.start_recording()` call overwrites it the moment the node enters
  the tree.

- **Don't:** read a battle-spawning test that "usually passes" as evidence the pin worked;
  a clobbered seed still produces a plausible-looking battle, just a randomly different one
  each run.

(`Lacaedemon/sparta` PR #1401, 2026-08-26: caught by adversarial review before it shipped.)

## Run ONE GUT test function: add `-gunit_test_name` to the existing `-gdir`/`-gselect` invocation

The single-file selection flags (`-gdir=res://test/unit -gselect=<basename>.gd -gexit`, and
why `-gtest=res://...` is silently ignored) are already recorded above in this corpus (see
"Run ONE GUT test file: `-gselect`, not `-gtest`").
The one addition from this session: append `-gunit_test_name=<test_func>` to that same
invocation to narrow the run to a single test function inside the selected file, instead of
running every test in it.

## Demo defect scans sample DIFFERENT tick sets depending on which surface is asking

Three separate places sample a demo input script's ticks for a DemoDefects verdict pass, and
no two of them agree on the tick set.
A `defect_exemptions` block that clears one can look mismatched against another -- the
mismatch is a different sample set, not a contradiction.

**The local, diff-scoped scan** (`tools/check.sh demo_defects`, run before pushing) unions a
changed script's `state` array with every tick named in its `expect` blocks (ranges contribute
both ends), deduplicated, falling back to a fixed spread when the script declares neither.
Confirmed at `tools/check.sh`:

```bash
ticks="$(jq -r '((.state // []) + ([.expect // [] | .[] | .tick? // empty] | flatten))
  | map(tonumber? // empty) | unique | map(tostring) | join(",")' "$script")"
[ -z "$ticks" ] && ticks="8,60,120,180,240,300"
```

**`demo-video.yml`'s own "Demo defect scan" CI step** (the one that gates a PR's own
`demos/demo.*.json` clip) derives its `STATE_TICKS` independently, and does NOT fold in
`expect` ticks at all -- only `state`, falling back to `frames`, with its own, shorter default
spread.
Confirmed at `.github/workflows/demo-video.yml`:

```bash
((.state | ticks) // (.frames | ticks) // []) | map(tostring) | join(",")
...
STATE_TICKS="8,60,140"   # fallback when neither state nor frames is usable
```

So `check.sh demo_defects`'s own help text says it mirrors `demo-video.yml` -- and it does,
in *grading logic* (the same `DemoDefects`/`analyze_transcript.gd` verdicts) -- but the two do
NOT sample the same ticks.
`demos/inputs/arrow-nudge.json` is the concrete case: `state` is `[28,88,148,208,268,330]` and
`expect` fires at tick `8`, so `check.sh demo_defects` scans tick 8 and CI's `demo-video.yml`
step never does.

**The informational website-demo-diff delta** (`website-demo-diff.yml`, via
`website/tools/dump-demo-states.sh`) ignores a script's `state`/`expect`/`frames` fields
entirely and samples a fixed catalog-wide cadence: tick 8 (an early sanity sample past spawn),
then every `SPARTA_STATE_TICK_STEP` ticks (default 60) through the clip's covered range,
always including the final covered tick.
Confirmed at `website/tools/dump-demo-states.sh`'s `tick_list()`:

```bash
# ticks="8" then append every TICK_STEP through the covered range, plus the final tick
local ticks="8" t=$TICK_STEP
...
echo "$ticks,$covered"
```

None of the three sample sets is a subset of another in general, so a `defect_exemptions`
entry written against one surface's flagged ticks does not necessarily cover either of the
other two.
Measured on PR #1398's review round (cycle-charge-flee exemptions vs. delta flags) and PR
#1401's interval-labels fixes.

- **Do:** read which surface flagged a defect -- local `check.sh demo_defects`,
  `demo-video.yml`'s CI step, or the `website-demo-diff.yml` delta -- before writing or
  trusting a `defect_exemptions` entry against it; each samples different ticks.

- **Don't:** assume `check.sh demo_defects` and `demo-video.yml`'s CI step see the same ticks
  just because they share grading logic -- `expect` ticks are scanned by the former and not
  the latter.

- **Don't:** assume an exemption that silences one of the three surfaces silences either of
  the other two.

## `website-demo-diff.yml` diagnoses against the PR's MERGE REF -- check branch+current-main, not the branch alone

`website-demo-diff.yml`'s job checks out with a plain `actions/checkout@v4` (its first step,
carrying only `fetch-depth: 0`) and no explicit `ref:` override, under a `pull_request`
trigger.
GitHub Actions' documented default for that event is to check out the automatic merge commit
between the PR branch and the *current* tip of the base branch (`refs/pull/<N>/merge`), not
the branch's own head.
The later "Dump state transcripts (this PR)" step does not check anything out itself -- it
just runs `dump-demo-states.sh` against whatever `$GITHUB_WORKSPACE` already is, i.e. that
merge ref.
The separate "Check out the merge-base tree" step is the *other* side of the diff: it
computes its own `BASE_SHA` via `git merge-base` and adds a second worktree there purely as
the pre-PR baseline to compare against -- it does not change what the first checkout put in
`$GITHUB_WORKSPACE`.

The consequence: a PR branch that is one `main`-merge behind can hard-fail the dump on
content that exists only on `main` -- the error names a file whose branch copy looks
completely innocent, and a local `grep` of the branch finds nothing, because the offending
content was never on the branch at all.
It arrived through the automatic merge with `main`'s current tip.

Measured on `sparta#1401`: `demos/inputs/group-attack-distributed.json` declared a
`f8dd2ca1` spawn fingerprint in the failing dump, while the branch's own copy of that file
carried no fingerprint field at all -- a sibling PR had merged a `spawn_fingerprint` addition
to that same file into `main` mid-round.

- **Do:** diagnose a `website-demo-diff.yml` merge-ref failure against **branch plus
  current `main`** (e.g. `git show <branch>:<file>` and `git show origin/main:<file>`, or
  re-run the merge locally), not against the branch in isolation.

- **Don't:** conclude a CI failure is unreproducible or CI-only just because a plain `grep`
  or diff of the branch alone shows nothing -- the failing content may only exist on the
  current `main` side of the automatic merge.

(`Lacaedemon/sparta` PR #1401, 2026-08-27.)

## The git stash stack is shared across ALL of a repo's worktrees -- never bare `stash`/`pop` for a prove-the-test-bites revert

`git stash` and `git stash pop` operate on one shared stack in the repository's common `.git`
directory (already noted above, in the "edit the worktree path" entry, as a way to move
stray edits *between* the main checkout and a worktree).
The same sharing is a hazard rather than a feature when two agent sessions are working in
*different* worktrees of this repo at the same time: a `git stash pop` in one worktree can
pop whatever is currently on TOP of the shared stack, regardless of which worktree pushed it
there -- including a sibling session's own in-progress work.

This bit twice in one session doing the standard "revert production code, watch the guard
test fail, then restore it" verification step (see the "Guard tests must be proven to bite"
convention): one agent's `git stash push` followed by a sibling's unrelated `git stash pop`
popped the FIRST agent's entry instead of the second agent's own, so the first agent lost its
WIP and had to rebuild it;
a separate incident had one agent find a stray, unfamiliar stash entry on the shared stack
and quarantine it rather than popping blind.

- **Do:** use `git checkout <sha> -- <file>` (or `git show <sha>:<file> > <file>`) to
  temporarily revert a single file for a prove-the-test-bites check, then the same command
  with the working-tree `sha` to restore it -- no stash involved at all.

- **Do:** use a temporary WIP commit (`git commit -m wip`, then `git reset --soft HEAD~1` to
  restore) when reverting more than one file, so the revert lives in your own branch history
  rather than a shared stack.

- **Do:** if a stash genuinely cannot be avoided, tag it uniquely
  (`git stash push -u -m "<unique-tag-nobody-else-would-use>"`) and recover it with
  `git stash apply <sha-or-stash@{n}>` (never bare `pop`), then `git stash drop` explicitly
  once confirmed -- `apply` leaves the entry in place if you grabbed the wrong one.

- **Don't:** run a bare `git stash` / `git stash pop` in a worktree while another session may
  be working in a sibling worktree of the same repo -- the stack has no per-worktree
  namespacing, so "pop" always means "pop whatever is on top right now," not "pop what I just
  pushed."

(Two sessions, `Lacaedemon/sparta`, 2026-08-27.)

## Standing policy: every PR needs a fresh demo

Every PR requires a fresh demo authored specifically for the change under review.
Never rely on a generic fallback clip (`showcase.json`) or copy an existing demo's
`scenario`/`steps` block as a shortcut template.

- **Author from scratch**: Write each new scenario (`demos/inputs/*.json`) with its
  own unit types, coordinates, seed, and step sequence tailored to what the PR changes.
- **Commit a per-PR manifest**: Add `demos/demo.<slug>.json` (where `<slug>` is the
  PR or issue number) pointing at the new input script via the `input` field.
- **Legitimate skips**: Reserve `"skip": true` solely for changes that have no
  battlefield manifestation at all (such as pure documentation or CI-only tooling changes),
  with an honest `"reason"` specified in the manifest.
