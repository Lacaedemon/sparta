## Both LOD layers carry the weapon silhouette -- rebuilding one is not rebuilding the block

`Unit` draws its soldiers through two independently-built mesh pairs, and BOTH derive their
shape from `_foot_kind()`, which is weapon-dependent as of the phase-4 switch work:

- `_build_figure_meshes` -- the detailed, zoomed-in silhouette (shaft glyph, rest-pose cant).
- `_build_mark_meshes` -- the flat, zoomed-out mark outline (dart/kite/pointer).

`_detailed_lod` defaults to **false**, so the mark layer is the DEFAULT render state rather than
an edge case. Both pairs are built once in `_setup_flock_renderer()`, so anything changing a
unit's weapon or type mid-battle has to rebuild both.

Rebuilding the mesh RESOURCES is still not enough. The MultiMeshes hold their own reference to
whichever pair they were last handed, and `_apply_lod_meshes()` -- the only code that re-hands
them -- is normally reached only when the LOD level or the facing side FLIPS. A weapon switch
does neither, so without an explicit re-application the block goes on drawing the weapon it just
put away until the camera happens to cross a zoom threshold; at mark LOD nothing re-hands it at
all.

**How this was missed, and it is the transferable half.** PR #1274 shipped the figure-mesh
rebuild plus the `_apply_lod_meshes()` re-application, having found the stale-handoff bug by
frame capture (the pre- and post-switch block regions were byte-identical). It fixed the
REPORTED INSTANCE and not the CLASS: `_build_mark_meshes` had exactly one call site against
`_build_figure_meshes`' two, and `_foot_kind()` drives both. Review caught the mark half.

The same round also hoisted `_apply_lod_meshes()` out of the `if _figure_body_mesh != null`
guard it had been nested inside. That reads like a second, load-bearing half of the fix and is
NOT one: `_setup_flock_renderer` calls `_build_mark_meshes` and `_build_figure_meshes`
unconditionally, back to back, and nothing anywhere nulls one mesh without the other -- so the
two guards are the SAME condition for any live unit, and both are false only for a bare
`Unit.new()` fixture that never ran setup. Adding the missing `_build_mark_meshes()` call alone
would still have reached `_apply_lod_meshes()` through the pre-existing figure guard. The hoist
is worth keeping for clarity (the guard now says "re-hand if there is a MultiMesh" rather than
being coincidentally nested), but claiming it was required overstates the finding. Caught in
review on PR #1278, which is itself the lesson: a plausible coupling between two adjacent null
guards is a claim about the code, and `grep -n "_build_.*_meshes\|_mark_body_mesh\s*=\|
_figure_body_mesh\s*=" scripts/Unit.gd` settles it in one command.

**How to apply:** when a fix rebuilds derived render state for one LOD layer, grep the OTHER
layer's builder for its call sites before calling the fix complete (`grep -n "_build_.*_meshes"
scripts/Unit.gd` settles it in seconds). More generally, after fixing a render-staleness bug
found by frame capture, ask which other consumers read the same `_foot_kind()`-style selector: a
frame capture only ever proves the ONE zoom it recorded, and demos record at zoom 3.5 (figure
LOD), so the DEFAULT render state is exactly the one no clip exercises.
(`Lacaedemon/sparta` PR #1274, 2026-08-16.)

## A session writes under TWO identities here, and which one decides both the reviewer request and whether the review runs at all

The client makes the identity, not the session. Measured 2026-08-16, same session, same branch,
minutes apart:

| write path | attributed author |
| --- | --- |
| GitHub MCP tools (`create_pull_request`, ...) | `dem-extra1` (User) (formerly `d-morrison` in earlier environments) |
| raw API with `GH_TOKEN` (`urllib`, `curl`) | `claude[bot]` (Bot) |
| the `gh` CLI (`gh pr create`, `gh api`) | `dem-extra1` (User) |

PR #1283 and #1308 were opened through MCP / CLI tools and are authored by `dem-extra1` (User); PR #1278 was opened through raw `urllib` with `GH_TOKEN` and is authored by `claude[bot]`.

**MCP and `gh` CLI paths behave sanely as User (`dem-extra1`).**
PRs opened via MCP tools (`create_pull_request`) or `gh pr create` are authored by `dem-extra1` (User). Two consequences follow:
1. The review workflow's `github.event.sender.type != 'Bot'` gate passes, so the PR gets its automatic review on the `opened` event without needing a follow-up push.
2. A `d-morrison` reviewer request does not name the PR's own author (`dem-extra1`), so `422 Unprocessable Entity` self-review errors do not arise on these PRs.

**Requesting `d-morrison` as a reviewer 422s on a `d-morrison`-authored PR.** GitHub rejects a
review request naming a PR's own author with `422 Unprocessable Entity`. That is not a
permissions or token problem and no retry fixes it, so don't spend a round diagnosing it and
don't report the PR as blocked on a reviewer request. It does NOT hold for a `claude[bot]`-authored
PR, where the request is merely useless rather than rejected -- combined with `Lacaedemon`'s zero
provisioned Copilot seats (documented above), `claude-code-review.yml` is the only automated
reviewer this repo has either way.

**`GET /user` is NOT a usable identity probe in this session -- it disagrees with the writes the
same token makes.** With the raw `GH_TOKEN` it returns `login: d-morrison`, while a PR created
with that identical token is authored by `claude[bot]`.

**The mechanism behind that split is unconfirmed, and the obvious explanation does not fit.**
"The agent proxy re-authenticates outbound calls" cannot be the whole story, because both calls
are raw `urllib` requests over the same token and the same egress path -- a uniform rewrite would
have made them agree. Something distinguishes the read from the write (a proxy that re-signs
POST/PATCH but passes GET through would do it), but that was not established, so don't repeat it
as fact. This matches the file's own convention elsewhere for an observed effect with an
unverified cause, and ai-config's "don't gate a write on verifying the credential first" rule
reaches the same practical conclusion from a different direction.

What IS measured is the disagreement itself, and it is enough: the only reliable reading is the
**attributed author of a write you actually made** (`pulls/<N>` -> `user.login`, or the workflow
run's `actor`). Don't reason about which identity you are from a probe.

(`Lacaedemon/sparta` PRs #1274 and #1278, 2026-08-16.)

## An empty `reviewRequests` DURING a claude-review run is the workflow stashing them, not a failed request

`Morrison-Lab/gha`'s reusable `claude-code-review.yml` --- the one sparta's own
`claude-code-review.yml` delegates to --- deliberately clears the pending-reviewer list while it
runs and restores it afterwards.
Two of its steps say so by name:

| step | name |
| --- | --- |
| 8 | Stash and clear reviewers; record starting head SHA |
| 24 | Re-assign reviewers after Claude finishes |

So a reviewer request that reads back as an empty `reviewRequests` moments later is behaving
exactly as designed, provided a review run was in flight at the time.
Re-POSTing changes nothing, and reading the empty list as a failure sends a session diagnosing a
request that never failed.

**This is the specific explanation ai-config's `pr-on-claim` family says it does not have.**
Its rationale sibling argues at length that a vanished pending request "has established nothing
either way", and warns against re-POSTing on the strength of it --- the right default for a repo
where no mechanism is known.

Cite `shared/workflow/pr-on-claim.rationale.md` for that quote, not `pr-on-claim.md`.
ai-config splits its heaviest fragments into `<name>.md` for the rule statement plus
`<name>.rationale.md` for the argument, so a phrase you remember sitting inline in the main file
may now live in the sibling.
An auto-loaded copy of the pre-split text sends you to the wrong file, and the main file returns
zero hits for the phrase, which reads as the quote being invented rather than merely relocated.
Grep both siblings, whitespace-normalized, before citing a phrase from that corpus.
Here there is one, and it is readable in a single call, so read the review job's own step list
before concluding anything about a disappeared reviewer:

```bash
gh api repos/Lacaedemon/sparta/actions/jobs/<job-id> \
  --jq '.steps[] | "\(.number) \(.name) => \(.status)/\(.conclusion)"'
```

Note what this does NOT establish: an empty list is still not evidence the request LANDED.
The zero-Copilot-seats case documented above produces the identical empty read for an entirely
different reason.
The stashing behaviour only rules out "the request failed" as the automatic reading, and whether
a `claude-review` run was in flight is what separates the two causes.

**The full cycle is measured, and the window is narrow enough to time your own POST against it.**
Two observations, on two PRs, from opposite sides of step 8:

| PR | POST relative to step 8 | read during the run | read after the run |
| --- | --- | --- | --- |
| #1281 | before the run started | `[]` | `["d-morrison"]` |
| #1293 | 5m18s after the clear, step 11 still running | `["d-morrison"]` | `["d-morrison"]` |

On #1293 step 8 completed at `17:25:49Z` and the PR's own `review_requested` timeline event is
stamped `17:31:07Z`, with step 24 still `pending`, so that request went in after the clear and
read back present rather than empty.

An empty read therefore dates your POST relative to step 8 rather than reporting a failure.
A request pending when the job reaches step 8 vanishes for the duration and returns at step 24;
one made after step 8 is added to an already-cleared list and looks normal throughout.
"Reviewer present while a review is running" consequently does not disprove the stashing either.
Both readings are the same mechanism seen from either side of one step, which is why the step list
settles it and a bare reviewer read never does.

Take the timeline event rather than trusting recollection of when you POSTed:

```bash
gh api repos/Lacaedemon/sparta/issues/<N>/timeline \
  --jq '.[] | select(.event=="review_requested") | "\(.created_at) \(.requested_reviewer.login)"'
```

**Step 24's restore ADDS rather than overwrites, so a mid-run request survives the run.**
This was the obvious way for the mechanism to bite and it does not.
The restore could plausibly have written back the stashed list wholesale --- empty on #1293 ---
silently dropping any reviewer added since.
It does not: step 24 completed `success` on that run and the list still read `["d-morrison"]`
afterwards, so the reviewer requested at `17:31:07Z` was still there when the job finished.
Nothing therefore needs re-requesting after a run, on either side of step 8.

Adjacent, and the reason the REST path is in use at all: `gh pr edit` fails in this environment
with the projectCards GraphQL deprecation error before applying the edit, so
`POST .../requested_reviewers` is the working path rather than a workaround.
Two flags are individually attested, from separate sessions on separate PRs ---
`gh pr edit <N> --add-reviewer d-morrison` and `gh pr edit <N> --body-file <path>` --- each exiting
1 with a `GraphQL: Projects (classic) is being deprecated` error naming
`(repository.pullRequest.projectCards)`.
So treat it as affecting `gh pr edit` generally rather than as a one-flag quirk.

- **Do:** read the review job's step list before treating a disappeared reviewer request as failed.
- **Do:** check whether a `claude-review` run was in flight at the moment the list read empty, and
  where in the step list it was.
- **Don't:** re-POST a reviewer request because `reviewRequests` came back empty.
- **Don't:** read the stashing as proof the request landed --- an empty list has more than one
  cause in this repo.
- **Don't:** read a reviewer that IS present mid-run as evidence against the stashing.
  A mid-run POST lands after the clear.
- **Don't:** re-request a reviewer once the run finishes.
  Step 24 adds rather than overwrites, so both sides of step 8 end up present.

(Measured 2026-08-16 across two PRs.
PR #1281, job 95198545509: steps 8 and 24 both `completed/success`, with the reviewer requested
before the run, `[]` mid-run, and restored afterwards.
PR #1293, run 31961543081 / job 95200181495: step 8 `completed/success` at `17:25:49Z`, a
`review_requested` timeline event at `17:31:07Z` while step 24 was still `pending` and reading
back present, then step 24 `completed/success` with the list still `["d-morrison"]`.)

## A PR opened via the raw API is opened by a Bot, and the review workflow's own gate silently skips it

`claude-code-review.yml` delegates to `Morrison-Lab/gha`'s reusable workflow, whose `gather-context`
job gate reads:

```yaml
if: >-
  github.event_name == 'workflow_dispatch' ||
  (
    github.event.pull_request.draft == false &&
    github.event.pull_request.head.repo.full_name == github.repository &&
    github.event.sender.type != 'Bot'
  )
```

That last clause is the trap. A PR opened through the raw API has `sender.type == 'Bot'` (see the
identity table above), so `gather-context`, `claude-review`, and `require-review` ALL skip -- with
no annotation, no output, and no summary. A skipped review is indistinguishable from one that has
not run yet, and `require-review` skipping means nothing turns red either. Measured on the same
branch: run 31936557788 (`5d974233`, actor `d-morrison`) succeeded and posted a verdict; run
31937729790 (`8163977d`, actor `claude[bot]`) skipped all three jobs.

Reading the CALLER settles nothing -- it carries no path filter and no job `if:` at all. The gate
is in the callee at its pinned ref, so clone `Morrison-Lab/gha` at `v2` and read it there.

**The skip is scoped to the `opened` event, and the NEXT PUSH heals it by itself.** A `git push`
goes out over the git proxy, which is the `d-morrison` identity, so the resulting `synchronize`
event has `sender.type == 'User'` and passes the gate untouched. Measured on this branch: run
31937946023, `pull_request` on `c8a19450`, actor `d-morrison`, `gather-context` success and
`claude-review` running -- against the `opened` run that skipped all three. So the ordinary
review-round rhythm repairs this on its own, and the ONLY genuinely stranded case is a PR whose
`opened` event skipped and which then needs a verdict with no further push to make.

**Reach for a `workflow_dispatch` only in that stranded case, and never while a `pull_request`
run is in flight.** Its branch of the `if:` is unconditional, so it does bypass the gate: pass
`ref` = the PR branch (a dispatch resolving against `main` reviews nothing and posts no comment)
and `pr_number` as the caller's input name; the dispatch guard blocks only fork and
`dependabot[bot]` PRs. But the `claude-review-<N>` concurrency group makes a redundant dispatch
actively HARMFUL. The section above on manual dispatches records the race in the direction where
an automated re-dispatch cancels a queued manual one; it runs the other way too, and that
direction costs a check: a dispatch QUEUED while a `pull_request` run is already in progress
cancels that in-flight run, and a cancelled `claude-review` fails `require-review` outright
(cancelled != skipped, unlike the by-design skip). Measured minutes apart on `c8a19450`: dispatch
31938015445 queued, run 31937946023 went `cancelled`, and its `require-review` reported `failure`.

Two corollaries. Cancelling the dispatch afterwards does not undo it, because the run it cancelled
stays cancelled -- so check for an already-running review BEFORE dispatching, not after. And a
`require-review` failure whose run conclusion is `cancelled` is self-inflicted bookkeeping rather
than a review finding: read the RUN's conclusion before treating it as one.

**Dispatching needs the MCP tool, not the raw API.** `POST .../workflows/<f>/dispatches` with the
raw `GH_TOKEN` returns `403 Forbidden` (no `actions: write`), while
`mcp__github__actions_run_trigger` with `method: run_workflow` returns `204` for the identical
call -- a second place the two identities differ in SCOPE and not just in name. A 403 here is
therefore a wrong-client error, not an absent capability: reach for the other client before
reporting the review unreachable or falling back to a self-review.

**How to apply:** after opening a PR, check the review workflow's newest run for
`conclusion: skipped` with `actor` a Bot. If the round has any push left in it, just push --
that heals the gate and costs nothing. Dispatch only when it does not, and only after confirming
no `pull_request` run is already in progress. (`Lacaedemon/sparta` PR #1278, 2026-08-16.)

## Never pipe `tools/check.sh` through `tail` -- the exit code becomes `tail`'s

The exit-code half is the load-bearing one, and it holds unconditionally: a piped invocation
reports the PIPELINE's status, so a `check.sh` that FAILED is reported by the harness as
`exit code 0`. Read the printed `== summary ==` block, never the task's exit status. Redirect to
a file rather than piping, so nothing is truncated either.

**A "Total Coverage" line with no "Patch coverage:" line after it means the run returned EARLY,
not that `tail` cut the breakdown.** The print order runs the other way from the intuitive
reading: `check_patch_coverage` calls `check_coverage` first (`tools/check.sh:633`), whose
instrumented ~2600-test suite log ends in the addon's own `...% Total Coverage: N/M lines`; the
per-file breakdown prints much LATER at `:707`, and `Patch coverage: X/Y = Z%` at `:735`, just
before the summary. So `tail -N` preserves the late patch answer and cuts the early total.

The failure path is what produces the confusing output. `:633` is `check_coverage || return 1`,
so when coverage itself fails -- e.g. on a version-mismatched binary or a test error -- `check_patch_coverage` returns there and `:707`/`:735` never run at all. The tail then
shows the end of the suite log ending in `93.4% Total Coverage: 8637/9244 lines`, a project-wide
number that reads convincingly as the patch figure, with no breakdown anywhere. Diagnose that as
"coverage failed and the patch step never ran", not as "the pipe ate the breakdown". (An earlier
revision of this entry made exactly that misreading, generalizing one failed run's output into a
claim about print order; corrected in review on PR #1278.)

Recovering without a re-run is cheap, because `coverage/lcov.info` is already written by then:
intersect its zero-hit `DA:` entries with the diff's added lines against the merge-base, per the
codecov-gap section above. On PR #1274 that reproduced Codecov's own figure EXACTLY -- local
65/66 = 98.48%, against codecov[bot]'s posted `98.48485%` naming the same single missing line in
`Battle.gd` -- so the lcov intersection is a genuine substitute for a CI round trip rather than an
approximation of one. That recovery is the right move for BOTH causes above: whether the patch
figure was truncated away or never computed, `lcov.info` is on disk either way.
(`Lacaedemon/sparta` PR #1274, corrected on PR #1278, 2026-08-16.)

## The manual 5-item demo checklist is NOT the 7-verdict automated scan -- run `demo_defects`

CLAUDE.md's standing demo requirement points at the "Standard demo defect checklist"
(blobbing, pulsing, flank-swapping, rank-swapping, facing whipsaw/rotation/reshape surge),
and it is easy to work that list by hand, find it clean, and call the demo verified. CI runs
a **different and wider** instrument: `tools/demo/analyze_transcript.gd` emits seven
deterministic verdicts, and two of them (`overlap`, `path_crossing`) have no counterpart in
the manual list at all.

**The two lists disagree in a way hand-verification structurally cannot close.** `blob` reads
`nnd_med` and `overlap` reads `nnd_min`, against the same `two_bodies` reference. A median
cannot see one interpenetrating pair, so a block can be a textbook lattice on every manual
metric while two men share ground. `overlap` also fires on **any single judged sample**
(`MIN_SUSTAIN` 1, unlike the sustain-gated `blob`), so a one-instant crossing is enough.

Worked instance: PR #1275's rally demo. The hand checklist reported nnd 9.00 throughout with a
7.33 dip, clean on all five, and that reading was correct --- it was measuring the wrong
quantity. CI reported `FAIL uid0 overlap worst=1.4599609375 threshold=2.25`.

**Run `tools/check.sh demo_defects` before pushing any new or edited `demos/inputs/*.json`.**
It scans exactly the input scripts your diff adds or edits, and it is minutes rather than the
suite's ~7. Skipping it costs a full review round, since CI reports the same verdict either
way.

**When a maneuver legitimately trips a metric, the sanctioned answer is a `defect_exemptions`
block in the input script, not a red check and not a reshaped scenario.** `demos/README.md`
carries the contract: `uids` and `reason` are both mandatory, the `uids` list keeps the claim
as narrow as the maneuver behind it, and exemptions never hide --- the verdict still prints, as
`EXEMPT` with the reason attached, and one whose metric has started passing prints as `STALE`
so it gets deleted rather than outliving its cause. A stale exemption is reported, not failed.

Word the reason for what it actually claims. "Expected under the current assignment, tracked
in #N" is honest where "correct by design" would not be, and the contract explicitly
anticipates a `see #N` pointer (its own example is the exelismos marching files through each
other).

- **Do:** run `tools/check.sh demo_defects` pre-push on every changed demo input.
- **Do:** exempt per-uid with a written reason when the trip is the maneuver doing its job.
- **Don't:** read a clean hand checklist as covering the automated scan --- it omits two
  metrics outright and reads a different statistic for a third.
- **Don't:** retick or restage a scenario to dodge a verdict; that is the one response the
  contract exists to prevent.

## Staging a demo that actually reaches a RALLY needs `starting_state`

No existing sparta scenario rallies. A rout that happens **in contact** gets pinned by enemy
soldier-body pressure and ground down rather than pulling clear, so it shatters ---
`rout-rally-recover.json` and `last-unit-rally.json` are both that case, and all three existing
rout demos end in annihilation. Three staging attempts failed this way before the mechanism was
clear: infantry-vs-infantry in contact (annihilated by tick 540), a slower Spearmen pursuer (the
router's `position` moved 753 -> 734 over 180 ticks, because the bodies are pinned and
`couple()` drags `position` back), and morale 0.5 with a distant enemy (never routed at all ---
morale climbed at +2/s, and `_rout()` is only reachable from `UnitCombat.register_casualties` or
`_apply_starting_state`).

**The tool is `Battle._apply_starting_state` via the `starting_state` scenario key**
(`Unit.State.ROUTING` is `3`), which is documented for demo tooling only. Spawn the unit already
routing at low morale with the enemy well outside the rally-contact radius, and its morale climbs
back toward the rout baseline and it re-forms where it stands --- deterministic at tick 334 for
`row-major-rally-reform.json`. Add a second, safe friendly unit outside the rout-shock radius, or
`_check_victory` ends the battle while the router is still routing.

**`_spawn_scenario` silently ignores keys it does not know.** A `"frontage": 8` override reads as
perfectly plausible and does nothing --- the supported keys are `count`, `morale`, `formation`,
`starting_state`, `disciplined`, `atomic_response_s`, `training`, `walk_advance`,
`reform_before_move`, `file_major_reform`, `team`, `x`, `y`, `facing`. Read the function before
inventing a key, and confirm the effect in a state dump rather than assuming it applied.

(`Lacaedemon/sparta` PR #1275, 2026-08-16.)

## `Battle._default_loadout()` is an ARMY ROSTER, and its two Cavalry entries are byte-identical

It returns five entries --- Spearmen, Infantry, Archers, Cavalry, Cavalry --- and `_spawn_line`
walks them with `loadout[i % loadout.size()]`.
That is what makes the default battle 5v5 with TWO cavalry regiments, rather than a four-type
registry spawned once each.

The duplicate is deliberate, and the docstring already says so: it opens
"The default battle loadout: spearmen, infantry, archers, cavalry, cavalry."
It has said that since PR #478, so do not read the repeat as a typo and do not delete it.

**The hazard is that a new per-type key must be set on BOTH Cavalry entries.**
Set it on one and it applies to only one of the two spawned regiments, so the default battle runs
with two supposedly-identical cavalry regiments that quietly behave differently.
The two entries are byte-identical today, and that is the property to preserve.

**`_loadout_for_type()` hides such an omission from any test that goes through it.**
It returns the FIRST entry whose `name` matches, so it answers with entry 4 and never reads entry
5 --- a test asserting "Cavalry's new key is X" passes whether or not entry 5 carries it.
A test routed through that lookup is therefore not evidence the roster is consistent, which is
the same first-match blindness this file already records for other selectors.

Derive the check instead of eyeballing the two lines:

```bash
awk '/^func _default_loadout/,/^\t\]/' scripts/Battle.gd \
  | grep '"name": "Cavalry"' > /tmp/cav.txt
echo "entries=$(wc -l < /tmp/cav.txt) unique=$(sort -u /tmp/cav.txt | wc -l)"
```

`entries=2 unique=1` is the healthy answer, and it proves both halves at once: two Cavalry
entries exist, and they are the same line.
`unique=2` means the two have diverged, whatever a `_loadout_for_type()`-based test reports.
The `awk` range is safe here because `^func _default_loadout` matches exactly once, per this
repo's own caution about a repeated start anchor silently widening a range.

- **Do:** set a new per-type key on both Cavalry entries in the same edit, then re-run the check
  above.
- **Do:** assert against the roster array itself when a test cares that both spawned regiments got
  the key.
- **Don't:** read `_loadout_for_type()`'s answer as evidence about the whole roster; it stops at
  the first match.
- **Don't:** "fix" the duplicate Cavalry entry --- the default 5v5 battle depends on it.

(Verified 2026-08-16 at `cee465f6`: five entries, `entries=2 unique=1` for Cavalry, and the
docstring's own first line naming cavalry twice.)

## A "disjoint, no merge-order constraint" claim must be DERIVED, and the candidate set is live

The rule already exists, and it is worth naming its home precisely: it lives in
`Morrison-Lab/ai-config`'s own `CLAUDE.md`, the corpus-wide file loaded into every session --- NOT
in this repo's `CLAUDE.md`, which says nothing about merge order at all.
Its "Surface merge-order constraints" section states it outright:

> But "disjoint" is a claim about their file *sets*, so derive both sets and check the intersection
> before asserting it --- `gh pr diff <N> --name-only` on each PR, and confirm no path appears in
> both --- rather than recalling what each PR is "about".

That rule was loaded and was not followed: the claim was made twice, from recollection, with no
derivation run either time.

Two failures stack here, and only the first is the one that rule covers.

**The process failure is that the sets were recalled rather than derived.**
One command per PR settles it, and it answers a question about PATHS where recollection answers
one about TOPICS.
Note that a correct conclusion is not evidence the derivation ran --- the two PRs really were
disjoint, and the claim was still unsupported at the moment it was made.

**The scope failure is that a two-PR intersection answers a question about two PRs.**
Any OTHER open PR touching the same file collides just as hard, so the set of candidates is not
the set you happen to have in mind.
This is the harder half, because running the derivation correctly does not fix it: the
derivation would have been scoped to a population that was already incomplete.

So derive the population as well as each member's files:

```bash
for n in $(gh pr list -R <owner>/<repo> --state open --json number --jq '.[].number'); do
  printf '%s: ' "$n"
  gh pr diff "$n" -R <owner>/<repo> --name-only | tr '\n' ' '
  echo
done
```

**And treat the answer as expiring.**
This file already records that `main` moves during a session, and that an append-collision on a
shared file recurs once per merge in a cascade rather than resolving permanently --- see
"Battle.gd merge: order-sentinel and same-name-local collisions" above, whose whole point is that
resolving once settles nothing while siblings keep landing.
A disjointness claim inherits that liveness.
It is a measurement of a live population, true when taken and capable of being false by merge
time, so re-derive it at merge time rather than citing the reading taken when the PRs were opened.

- **Do:** derive each candidate's file set with `gh pr diff <N> --name-only`, and intersect them.
- **Do:** derive the candidate set itself from `gh pr list --state open`, rather than from the
  PRs this session happens to know about.
- **Do:** re-derive at merge time, and say when the reading was taken.
- **Don't:** report "disjoint, merge in any order" from what each PR is for --- that is a claim
  about topic, and a conflict is a claim about paths.
- **Don't:** read a correct conclusion as evidence the derivation ran.

(`Lacaedemon/sparta`, 2026-08-16: PR #1283 touches `demos/demo.1201.json` and
`docs/related-games.md`, and PR #1292 touches `.claude/memories/sparta.md` and
`demos/demo.1292.json`.
The two were declared "disjoint, merge in any order" twice from recollection, and the intersection
is genuinely empty --- derived afterwards with the command above.
#1292 hit `Pull Request has merge conflicts` anyway, against #1293, a PR opened and merged by a
different session, which touches `.claude/memories/sparta.md` and nothing else.
#1293 merged at 18:36:59Z, ahead of #1283's own 18:38:43Z, and #1292 absorbed it with a `main`
merge at 18:41:43Z --- replaying that merge with `git merge-tree` reports exactly one conflicted
path, `.claude/memories/sparta.md`, so the collision is measured rather than inferred.
Four PRs landed on `main` inside four minutes --- #1293 at 18:36:59Z, #1281 at 18:37:50Z, #1283 at
18:38:43Z and #1282 at 18:40:31Z --- so the population any such comparison had to cover was moving
the whole time.)

## The sparta memory corpus contains literal conflict markers as documentation

The section on `record-demos.sh` DEMOS conflicts being ADDITIVE (in
`02-routing-units-early-return-in-physicsprocess.md`) quotes a real merge conflict
verbatim inside a fenced code block, so `<<<<<<< HEAD`, `=======` and `>>>>>>> origin/main` sit in
that part file as **content**.

**Those line numbers move faster than an append-only reader expects, because entries land mid-file as
well as at the end** --- and more so now that the corpus is split across
`.claude/memories/sparta/*.md` rather than one monolith.
So anchor on the section heading, never on a line number quoted anywhere --- including historical
ones in this paragraph.

Consequence: resolving a genuine conflict in any part file by stripping every conflict-marker line,
or by any editor "accept ours / accept theirs" pass that scans for markers globally, silently
deletes three lines out of that documentation block.
A `grep -n` for the markers during a resolution returns those three alongside the real ones and
cannot separate them --- same text, same column, and the grep output carries no surrounding
context to tell one from the other.

**Nothing downstream catches the loss.**
`tools/check.sh chars` and the `check-non-standard-chars` workflow both scan `*.qmd` and `*.R`
only, and this repo runs no Markdown linter at all, so a corrupted block reaches `main` with every
check green --- reading correctly everywhere except one code fence that has quietly become
nonsense.

So resolve by LINE NUMBER rather than by pattern.
Read the markers' line numbers, work out which fall inside the fenced example by anchoring on the
`record-demos.sh` heading rather than on stale numbers, and edit only the ranges outside it.
Then re-run the grep and count what survived:

```bash
grep -n '^<<<<<<<\|^=======\|^>>>>>>>' .claude/memories/sparta/*.md
```

Three hits, consecutive within five lines and under the `record-demos.sh` heading, is the healthy
answer.
Zero means the resolution ate the documented example.
More than three means a real conflict is still unresolved.

- **Do:** resolve a conflict in a part file by editing the real markers' line ranges, identified by
  number and confirmed against the `record-demos.sh` heading.
- **Do:** re-run the marker grep afterwards, and expect exactly three survivors.
- **Don't:** strip conflict markers from the corpus by pattern, and don't accept an editor's
  global ours/theirs pass over it.
- **Don't:** expect a check to catch the loss --- the chars scan does not read `.md`, and no
  Markdown linter runs in this repo.

(Historical note from the monolithic era at `4aee29b9`: exactly three documented markers inside
the fenced example under the `record-demos.sh` DEMOS-conflicts heading.
Exercised for real on the PR that records it: merging `origin/main` in raised a genuine
append-collision, so the grep returned SIX markers --- three documented, three real.
Deleting only the real triple by line number kept both sides' new sections and left the example
intact.)
## `pair_slots_by_lateral_file` is order-preserving, not identity-preserving -- so bound TRAVEL, never count movers

The slot-assignment family above ("Formation slot assignment is by ARRAY INDEX") explains why a
reshape relabels men onto distant cells. This is the measured consequence for anyone writing a
regression test against one of those paths, and it is the reason a mover COUNT is the wrong
metric there.

`UnitFormation.pair_slots_by_lateral_file` sorts each file's group by ascending y and assigns to
column cells in depth order. That preserves ORDER within a file; it does not preserve which man
holds which cell. On a partial-rank square the two come apart badly. Measured on a 60-man,
8-file square at 9.0 wu pitch, `moved` counting men displaced more than half a pitch:

| path | moved | farthest | mean |
| --- | ---: | ---: | ---: |
| in-sync reform | 4 | 63.0 | 4.20 |
| out-of-sync, composed twice (the bug) | 58 | 68.54 | 30.74 |
| out-of-sync, rebuild used as-is (the fix) | 51 | 28.46 | 13.44 |
| **out-of-sync, no reform at all** | **51** | 20.12 | 10.19 |

The last row is the one to keep. A bare rebuild with NO reform already churns 51 of 60 with
nothing else changing, so `moved` cannot discriminate the fix from the bug on that path at all --
the fixed and do-nothing readings are identical. Only `farthest` and `mean` separate (28.46/13.44
against 20.12/10.19), and `mean` separates most cleanly.

**How to apply:** when testing any out-of-sync or rebuild path in the slot-assignment family,
bound MEAN TRAVEL against a quantity derived from the block's own geometry (e.g.
`(ranks_for(n, files) - 1) * file_pitch_wu() / 3.0`), not a mover count and not a hand-picked
constant. A count-based assertion there is vacuous by construction, and a constant drifts as the
churn floor moves. The shipped guard in
`test_square_hold_ground_reform_holds_its_ground_from_an_out_of_sync_assignment` does exactly
this, and mutation-verifies at `[30.74] expected to be < than [21.0]` with the guard removed.

Related, and the reason the out-of-sync path exists at all: `_slot_frame_positions` reads
`_formation_mirror_x`, which `reform_ranks` arms BEFORE calling `_apply_square_slot_reflection`.
So when the assignment is stale and `_ensure_square_slot_assignment` rebuilds from live bodies,
that rebuild already lands men in the render frame -- the depth reflection is baked in, and
composing the pairing on top applies it twice. Snapshot the in-sync answer before the ensure call
can overwrite it. (`Lacaedemon/sparta` PR #1282, 2026-08-16.)


## A `/tmp` file written by MSYS bash is unreadable from native Windows Python

On Windows Git Bash the two tools resolve `/tmp` to different directories,
so a file handed from one to the other goes missing.
This sequence fails:

```bash
some_command > /tmp/added.txt
python -c "open('/tmp/added.txt')"     # FileNotFoundError
```

The redirection writes to **MSYS's own `/tmp`**, which on this machine is
`%LOCALAPPDATA%\Temp` (`pwd -W` inside `/tmp` reports
`C:/Users/dougm/AppData/Local/Temp`, the same mapping the `MSYS_NO_PATHCONV` entry
above already records).
The `python` on `PATH` is a **native Windows** interpreter (`C:\Python313\python.exe`),
which resolves the literal string `/tmp/added.txt` against the current drive as
`C:\tmp\added.txt`.

**The discriminator is whether MSYS can SEE the path, not which tool reads it.**
MSYS translates a `/`-rooted path that appears as a bare **argument**, so the same
interpreter reads the same file perfectly well when the path is passed rather than
embedded.
Measured, all in one Git Bash session:

| form | what Python receives | result |
| --- | --- | --- |
| `python /tmp/probe.py` | `C:/Users/dougm/AppData/Local/Temp/probe.py` | runs |
| `python -c "...open(sys.argv[1])" /tmp/probe.txt` | same, translated | reads |
| `python -c "...open('/tmp/probe.txt')"` | `/tmp/probe.txt` verbatim | `FileNotFoundError` |

The path embedded inside the `-c` program text is invisible to the translator, and only
that form breaks.
The same applies to any path MSYS cannot see as an argument, such as one written into a
config file or a JSON manifest that some later step reads.

**Neither tool reports the mismatch.**
Bash exits 0 and reads the file back fine itself, and Python raises a plain missing-file
error, so the pair reads as "the command produced nothing" rather than "these two tools
disagree about the root".
That is the expensive part, because the natural diagnosis is that the upstream command
failed, which sends you to debug a pipeline that was working.

**The sharper variant raises no error at all.**
`C:\tmp` is a real directory on this machine, already holding generic-named leftovers from
earlier sessions (`pr_body_payload.json`, `prbody2.md`, `doc_cmd.sh`).
A same-named file there is read INSTEAD of the one bash just wrote.
Measured: with `STALE-FROM-AN-EARLIER-SESSION` in `C:\tmp\probe.txt` and
`FRESH-FROM-THIS-COMMAND` written by bash to `/tmp/probe.txt`, `cat` printed the fresh line
while the embedded-path `open()` printed the stale one.
A missing file is at least loud; this is wrong data wearing a successful read.

**Fix: keep the handoff on a path both tools resolve identically.**
A relative path inside the repo working directory works for both, and deleting it
afterwards keeps the tree clean.
Better still, keep the whole operation inside one tool and skip the file entirely by
piping into `python -c` on stdin.
Both verified:

```bash
some_command > ./added.txt && python -c "print(open('added.txt').read())"; rm -f ./added.txt
some_command | python -c "import sys; print(sys.stdin.read())"
```

**Relationship to the `MSYS_NO_PATHCONV` entry above** (in the WSL cross-platform section):
same translation mechanism, opposite directions, so do not reach for that fix here.
There translation **happens and hurts**, because MSYS rewrites a `/`-rooted argument to
`wsl.exe`, which would have resolved the POSIX path correctly itself.
Here translation **does not happen, and its absence hurts**, because the path is hidden
inside a string where nothing can rewrite it.
So `MSYS_NO_PATHCONV=1` does nothing for this case, and would break the bare-argument form
in the table above that currently works.

- **Do:** hand a file between MSYS bash and a native Windows interpreter on a relative path
  inside the repo, or pipe it on stdin and skip the file.
- **Do:** pass a path as an argument rather than embedding it in `-c` program text when a
  temp file is unavoidable, so MSYS can translate it.
- **Do:** run `python -c "import os; print(os.path.abspath('/tmp/x'))"` when a just-written
  file reads as missing, since it names the wrong root immediately.
- **Don't:** diagnose a missing `/tmp` handoff as the upstream command having produced
  nothing; `cat` it from bash first, which reads the real file.
- **Don't:** trust a SUCCESSFUL read of a `/tmp` path from native Python either, since a
  same-named file in `C:\tmp` is returned silently in place of the fresh one.
- **Don't:** reach for `MSYS_NO_PATHCONV=1` here; it addresses the opposite failure.

(`Lacaedemon/sparta` PR #1292, 2026-08-16: reproduced deliberately in a Git Bash session on
this machine against `C:\Python313\python.exe`; every figure above is from that run.)

## `docs/related-games.md` is a living document with its own contribution contract

When reviewing an external project as a source of ideas for sparta, append to
`docs/related-games.md` rather than creating a new `docs/<project>-review.md`.
The doc calls itself a "running review" and a "living document", and its closing
**"Adding a game to this list"** section spells out the procedure: find the code licence
and the art/data licence **separately**, tag each with the legend symbols it shares with
`docs/asset-sources.md`, add a shortlist table row with links, then write the per-game
notes.
Its framing already covers closed-source subjects, via the rule that proprietary projects
and commercial-game mods give us design lessons only (no code, no art), so a
non-open-source subject is not a reason to start a separate file.

Three reviews have gone through it, so this is established practice rather than a
preference: PR #208 created it (closes #204), PR #1233 appended Renaissance Kingdom Wars,
and PR #1283 appends M2TWEOP for issue #1201 (open at the time of writing).
A parallel per-project file would fragment the licence legend and the **Bottom line**
summary, which are what make the doc worth consulting at all, since both rank every game
against each other and neither survives being split.

- **Do:** append a new per-game section plus a shortlist row, following the doc's own
  four-step "Adding a game to this list" procedure.
- **Don't:** create `docs/<project>-review.md` for a one-off review, since the comparison
  value lives in the single ranked list.

(`Lacaedemon/sparta` PR #1292, 2026-08-16, recorded from PR #1283's review of M2TWEOP.)

## Batch Work Summaries (GII / GIA / MWC / Wrap-Up): Explicitly state Stopping Point status

When completing a multi-issue backlog loop (`gii`, `gia`), PR stack sweep, or automated session wrap-up (`mwc`, `wrap-up`), always include an explicit **Stopping Point** declaration at the bottom of the summary table: e.g. `**Stopping Point**: All 5 issues completed / backlog clear. Clean stopping point reached.`
Do not leave the user guessing whether additional tasks remain queued or if a clean stopping point has been reached.

- **Do:** state explicitly `Stopping Point: Clean stopping point reached` (or name what remains) at the end of every batch/GII summary.
- **Don't:** print only a PR table without confirming whether the queue is complete and work is at a clean stopping point.

## AI Capability & Memory Changes (`cai` / `ca`): Always Push immediately via PR

Whenever a session creates or updates AI capabilities, memories, or skill definitions (`cai`, `ca`, `ums`), immediately branch off `main`, commit, push to origin, open a PR, request review, and drive to clean (or merge under `mwc`). Never leave capability or memory edits sitting uncommitted in the local working directory or wait for the user to prompt for a push.

- **Do:** branch, commit, push, open a PR, and ARDI to clean immediately upon applying memory or skill edits.
- **Don't:** leave `cai` or memory edits uncommitted in the local working tree without pushing them.

## `mergeable_state: clean` is NOT Fully Clean

GitHub API's `mergeable_state: clean` / `mergeStateStatus: CLEAN` indicates ONLY that git merge will succeed without merge conflicts. It does NOT mean CI has passed or that an AI/human review has approved the PR. NEVER merge a PR based on `mergeable_state: clean` without verifying both (1) all CI check runs are green, AND (2) an authentic clean review verdict evaluating the HEAD SHA has been received (triggering `@claude review` / `claude-code-review.yml` first in repos like `ai-config` where reviews do not auto-dispatch).

- **Do:** verify that all CI check runs are green AND latest review is clean before merging.
- **Don't:** treat `mergeable_state: clean` from GitHub API as a clean CI or review verdict.

## Always Keep a Scheduled Monitor Timer Running for In-Flight Work

Whenever ending a turn while background CI, `@claude review`, or async jobs are executing on active PRs under `mwc` / `ARDI`, ALWAYS launch a `schedule` timer (e.g. 120s) before ending the turn. Never finish a turn leaving in-flight PRs unmonitored without an active scheduled timer.

- **Do:** set a `schedule` timer (e.g. 120s) before ending any turn while background PR checks or reviews are in flight.
- **Don't:** end a turn leaving in-flight PRs unmonitored without a scheduled timer running.

## Always State Clean Stopping Point When Stopping Work

Whenever ending a session, completing a turn, or wrapping up work (whether finishing a single task, a multi-issue backlog loop like `gii`/`gia`, a PR stack sweep, or an automated session wrap-up like `mwc`/`wrap-up`), ALWAYS include an explicit `**Stopping Point**` declaration stating whether or not the session is at a clean stopping point (e.g. `**Stopping Point**: Clean stopping point reached` or `**Stopping Point**: Not a clean stopping point / work remains queued: ...`). Never leave the user guessing whether additional tasks remain queued or if a clean stopping point has been reached.

- **Do:** state explicitly whether or not the session is at a clean stopping point whenever stopping work.
- **Don't:** leave the user guessing about stopping point status when ending a turn or session.






## A GUT test asserting a tick-N outcome of a multi-hundred-tick battle is cross-platform-fragile

A test that runs a live Battle for a few hundred ticks and asserts an event happens
by a specific tick will diverge Windows-vs-Linux once enough soldier physics accumulates
(the same float-drift `.claude/skills/sparta-demos/SKILL.md` documents for precise-tick demo
captions -- it applies to GUT test tick windows too, not just captions/artifacts). A window
tuned to the local (Windows) fire tick can pass locally and fail on CI (Linux), where the
event lands later. `test_battle_ai_subcommanders.gd`'s SUPPORT-order window hit this: local
fire tick 301, CI Linux > 360 (#1095/PR #1351).

- **Do:** size a "does event X eventually happen" window to a battle length already proven to
  complete on CI (e.g. the sibling determinism test's own tick count), with wide margin over
  the observed fire tick, rather than a tight bound tuned to one platform's numbers.
- **Do:** verify a widened window against CI's own run (Linux), not just locally, when the
  event tick is platform-sensitive.
- **Don't:** hard-code a tick window from a single local `dump-state.sh` / probe reading for a
  battle that runs long enough to drift across platforms.

## Run ONE GUT test file: `-gselect`, not `-gtest`, because `.gutconfig.json` forces the dir

`.gutconfig.json` sets `dirs: ["res://test"]`, so a bare
`-s addons/gut/gut_cmdln.gd -gtest=res://test/unit/<file>.gd` still runs the WHOLE suite
(the config's dirs win) -- it times out looking like a hang. To run a single file:
`-gdir=res://test/unit -gselect=<basename.gd> -gexit`. It is `-gselect` (a substring filter
on script names) that limits which scripts actually RUN; `-gdir` just narrows the collection
directory so the scan is faster.

Don't pass `-ginclude_subdirs=false` expecting it to disable subdir scanning: GUT's optparse
(`addons/gut/cli/optparse.gd`) treats boolean flags as toggles -- presence sets the value to
`!default` and any `=false` suffix is ignored -- so the flag does the opposite of what
`=false` reads like. `-gselect` already scopes the run, so just omit it.

- **Do:** use `-gselect=<basename.gd>` (with `-gdir=res://test/unit`) to run one test file
  locally while iterating.
- **Don't:** assume `-gtest=<path>` limits the run -- the `.gutconfig.json` `dirs` override it.
- **Don't:** write `-ginclude_subdirs=false` -- a GUT boolean flag ignores its `=false` and
  toggles to `!default`.

## A battle-wide default change floods the website demo-diff -- classify structurally, don't re-verify 30 clips by hand

Changing a default that affects many scenarios (e.g. #1095's hold-formation default) makes
`website-demo-diff.yml` flag dozens of clips (33 on PR #1351), most diverging at tick 1.
Don't dump-state every one. The fast, rigorous classification:

- **Do:** first confirm the diff touches no physics/collision/formation code, checking only
  the diff's *added* lines and ignoring comment/prose matches -- this repo's own vocabulary
  ("hold formation", "press into") makes a naive whole-diff grep hit comment prose and
  unchanged `_move_to(...)` context lines, so it never reads empty even on a genuinely
  logic-free diff (this happened on the very PR this lesson is drawn from). Restrict to added
  code lines and read the hits:
  `git diff origin/main...HEAD -- scripts/ | grep -E '^\+' | grep -vE '^\+\+\+|^\+\s*#|^\+\s*$' | grep -iE 'press|collision|overlap|shape|formation|melee|_move|physics'`.
  Use `origin/main...HEAD` (merge-base, what `website-demo-diff.yml` itself uses), not two-dot
  `origin/main`, so a moved-forward `main` doesn't drag unrelated `scripts/` changes in. If the
  only hits are comment prose (`+ #`) or unchanged context, the logic is untouched: a
  "candidate regression" `overlap`/`shape_residual`/`blob` cannot be a NEW physics bug -- it is
  a re-arrangement (a unit now standing where it used to march, or an AI unit now marching
  further and tripping the known long-march deformation).
- **Do:** tally the WHOLE defect-delta table (cleared vs added), not just candidate-regression
  rows, and put the net in the PR description (PR #1351: ~13 cleared, 10 candidate, 10
  pre-existing).
- **Do:** treat `expect:position@N` / `expect:state@N` candidate regressions in OTHER demos as
  stale pins (they asserted the old behavior) -- they don't fail CI (`demo_defects` scans only
  CHANGED demos), so file a follow-up to re-pin them (PR #1351 -> #1354) rather than growing the
  PR.
- **Don't:** read a wide demo-diff as many regressions, or dump-state each clip's merge-base
  side unless its OUTCOME looks wrong (a wiped unit, a missing rally) per the sparta-demos
  wide-diff procedure.

## A GUT poll loop tests its bound BEFORE the await, so it samples one tick past it

The shape is everywhere in the live-battle tests:

```gdscript
while battle.current_tick() <= WINDOW and not saw_it:
    await get_tree().physics_frame
    ...check...
```

The condition is evaluated at tick `T`; if `T <= WINDOW` the body awaits, which advances to
`T + 1`, and only then samples. So the last tick actually inspected is **`WINDOW + 1`**, not
`WINDOW`. A test with `WINDOW = 600` passes on an event at tick 601.

The consequence is not the off-by-one itself, which is harmless, but the arithmetic done
**about** the loop afterwards. Counting how many sampled seeds a window would have failed,
comparing a measured fire tick against the bound, quoting a failure rate in a PR body or an
issue -- each is wrong by whatever lands on the boundary tick, and every one of those reads
as a careful, quantitative claim. It cost a published "6 of 30" that was really 4 of 30.

- **Do:** treat the effective bound as `WINDOW + 1` in any claim derived from such a loop.
- **Do:** re-derive a failure count against the effective bound before writing it down, not
  against the constant's value.
- **Don't:** compare a measured tick against `WINDOW` and call the difference the margin.

## Check a claimed-no-op refactor against `main`, never only against its own base

A stacked PR's demo-diff and its three-dot `git diff` are both computed against its **base
branch**. That is the right comparison for reviewing what the PR adds, and it is blind to the
thing most worth catching: content the branch has **deleted** that exists on `main`.

The tell is a wide demo-diff that the stated change cannot explain -- 33 of 83 clips changed,
most diverging at tick 1, on a PR converting two distance guards to squared space. A refactor
that touches maneuver classification cannot move the first tick of every scenario. Something
else did.

Derive it rather than reading the diff, since a deletion is invisible unless you go looking:

```sh
for ref in origin/main origin/<pr-head>; do
  git show $ref:scripts/Battle.gd | grep -c '<feature symbol>'
  git cat-file -e $ref:<file> && echo PRESENT || echo ABSENT
done
```

A symbol with N references on `main` and **0** on the head, or a file present on `main` and
absent on the head, is a revert of merged work that would land if the PR merged.

Rule out the innocent explanation before calling it a revert. "Present on `main`, absent on
the head" has two causes: `main` gained the content after the fork and the branch simply has
not merged it yet, or the content was in the branch's own ancestry and the branch deleted it.
Only the second is a revert, and what separates them is whether the **merge-base** carries it:

```sh
MB=$(git merge-base origin/main <head>)
git show $MB:<file> | grep -c '<symbol>'          # present in the branch's own ancestry?
git show <head>:<file> | grep -c '<symbol>'       # gone now?
```

Present at the merge-base and absent at the head is a deletion the branch made. On #1349 that
read 3 and 0.

**Do not substitute an ancestry check for this**, in any of its forms -- neither
`git merge-base --is-ancestor origin/main <head>` nor "the head has absorbed its base". Both
return a reassuring true for a branch that merged `main` and then reverted it, because the
merge genuinely is in the ancestry and the revert sits on top. `07-a-pr-can-revert-merged-main.md`
names that trap directly and gives the authoritative check, a real trial merge onto `main` in
a throwaway worktree read by its net diffstat; run that before merging, and treat the
merge-base symbol count above as the cheap triage that tells you to.

- **Do:** count a deleted feature's references on `main` and on the head, and check file
  presence, whenever a diff is wider than the stated change explains.
- **Do:** compare the head against the **merge-base**, not against the base branch's tip,
  before calling a removal a revert.
- **Do:** run `07-...md`'s trial merge for the authoritative answer.
- **Don't:** read a stacked PR's base-relative diff as evidence about what merging it does to
  `main`.
- **Don't:** rule out a revert with any ancestry check -- that is the one signal that is
  reliably true in exactly the case you are trying to detect.
- **Don't:** attribute a tick-1 divergence to a refactor of code that runs later than tick 1.

## A workflow claim checked against the caller is not checked

`.github/workflows/claude-code-review.yml` is a thin caller: `on:`, `permissions:`, `uses:`,
`with:`. Every gating condition lives in the reusable workflow it delegates to, in
`Morrison-Lab/gha`, at the pinned ref. So `grep -rn "draft ==" .github/workflows/` returns
nothing in this repo even though the review workflow does gate on `draft == false`. Grep the
bare word `draft` instead and you get exactly one hit -- a commented-out `eager-pr` line in
`claude.yml` -- which is a mention, not a gate.

Both directions of that gap have bitten in one session, and so has a third: the claim above
was first written citing the bare-word grep as returning nothing. It does not. The empty
result came from a run with `| grep -v "^.*#"` appended, which drops every line containing a
`#` anywhere and so removed exactly that comment hit -- and the unfiltered command was then
written down as if it had produced it. Cite the query you actually ran, and prefer one whose
emptiness is a property of the repo rather than of your filter.

- **Do:** follow the `uses:` to the callee at its pinned ref before asserting when a workflow
  runs or what gates it.
- **Do:** say where a gate lives when citing one, so an empty grep here is not read as a
  refutation.
- **Do:** paste the exact command whose output you are reporting, filters included.
- **Don't:** read a caller's `on:` types list as the trigger condition -- it is the wider of
  the two constraints.
- **Don't:** conclude from an empty `.github/workflows/` grep that nothing gates on the thing
  you searched for.

## A fixable red CI check means HOLD the PR, not ask what to do

When a PR fails a CI check and that failure has a known fix **that lands outside this PR** --
an issue is filed for it, or the fix is otherwise identified -- **hold the PR until that fix
lands.** Do not ask the owner to choose between merging past a red gate and waiting; the
answer is always wait. Mark the PR draft so the hold is visible at a glance and say on the
thread which issue it is waiting for.

The thing you wait on is usually a tracking issue, not a PR, because at the moment you file
the hold nobody has written the fix yet. So the trigger is "the fix lands" -- a fix PR merges,
or the tracking issue closes -- and watching for a specific PR number gives you nothing to
watch. Both of this section's worked examples went that way: #1348 held behind #1360 (the
tired unit's peel-back, which reddens its `demo` gate) and #1349 behind #1357 (the
nondeterministic subcommander test, which reddens its `Validate & test`). #1357 acquired a fix
PR, #1363, hours after the hold was filed; #1360 had none at all. Both are written up in full
at the end of this section.

**Draft stops the review round, not the CI spend.** Only the review workflow gates on draft
status, and that gate is not in this repo -- `grep -rn "draft ==" .github/workflows/` returns
nothing. (Search for the bare word `draft` instead and you get exactly one hit, an unrelated
`eager-pr` comment in `claude.yml`; it is a comment, not a gate.) `claude-code-review.yml` is a
thin caller that delegates via `uses:` to `Morrison-Lab/gha`, and the
`github.event.pull_request.draft == false` condition lives in the callee, at the pinned ref.
Don't read the empty grep as "nothing gates on draft". `godot-ci.yml`
triggers on a bare
`pull_request:` with no draft gate and no `paths:` filter, so `Validate & test` runs on every
push to a held draft. `demo-video.yml` fires on `synchronize`, also with no draft gate, but it
IS path-filtered (`scenes/`, `scripts/`, `assets/`, `project.godot`, `demos/*.json`,
`demos/scenarios/`, `demos/inputs/`), so `demo` re-runs only on a push that touches one of
those. Draft it for the signal and to stop burning review rounds -- not on the belief that it
makes the hold free.

**The failure has to belong to someone else.** This rule covers a pre-existing bug the PR
merely surfaces, or a flake tracked elsewhere -- cases where the fix is somebody's tracked
issue and waiting is the only way to get a true green. A defect the PR itself introduced is
not a hold: it is yours to fix on the branch now, per the standing no-technical-debt rule.
Deciding which one you have is the first step, not an afterthought.

This last paragraph is a deliberate narrowing, recorded here rather than left implicit. The
first draft of this entry -- and the tracking issue's restatement of it -- said the rule
"applies to the PR's own defects and to failures it merely surfaces", which was a paraphrase
rather than the directive. The directive itself is about a failure whose fix "comes through"
on another PR, and a defect the PR introduced has no such PR to wait for, so holding for it
would mean waiting on nothing. The narrowing is the reading that makes the rule executable.

**Never buy green instead of waiting.** Not by trimming the clip to end before the defect
appears, not by swapping to a scenario that avoids the code path. Both hide the signal the
check exists to give, and both falsify whatever the PR claims about the behaviour.

Two adjacent remedies are already sanctioned in this memory corpus and are **not** covered by
that ban, so read the distinction rather than the keyword:

- **`defect_exemptions`** is the sanctioned answer when a maneuver legitimately trips a
  metric -- see "When a maneuver legitimately trips a metric" above, which spells out the
  contract. Exempt when the trip is the maneuver doing its job, with the honest reason the
  contract requires. Hold when the trip is a genuine defect waiting on a fix; an exemption
  there is the buy-green move this section forbids.
- **Re-running a failed job** is the sanctioned answer for a failure confirmed transient or
  infra-side -- that contract lives in the sibling part-files `04-...md` and `07-...md`, not
  in this one, and both of its attested cases are narrow: a link-checker blip that a PASSED
  `main` run over the same corpus proves was reachable, and a `claude-review` that posted a
  full verdict and then failed on a step downstream of it. Note what does NOT qualify, from
  the same file: a `claude-review` dying at ~40s with `total_cost_usd: 0` is not transient,
  and `07-...md` says re-running that one waits forever. Read the failing step before
  classifying. What this
  section forbids is the different move of re-rolling a *nondeterministic gate whose defect
  is already tracked* until it happens to land green -- the flake is the known bug, so a
  green re-roll is an unearned pass rather than a recovered run.

**Resuming is part of the hold.** When the fix lands -- its PR merges, or the tracking issue
closes -- re-sync the held branch onto the new `main`, re-run CI, and mark it ready for review
again only once the check that caused the hold actually comes back clean.

(Owner directive, 2026-08-21, from the GIA sweep of #1345/#1348/#1349. Worked example: #1348's
`demo` gate failed on `uid0 overlap worst=0.117` -- the tired unit's peel-back, split out as
#1360 -- and #1349's `Validate & test` failed on the nondeterministic subcommander test tracked
in #1357. #1348's red gate was **first escalated to the owner** as a merge-policy question --
"I'd rather ask than quietly pick" -- and that escalation is what prompted this directive,
which then put both PRs on hold behind their unblocking issues and retracted the question.
The escalation is the retired behaviour this entry exists to replace, so it is recorded here
rather than smoothed over.)
