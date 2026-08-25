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
push to a held draft. `demo-video.yml` fires on `synchronize`, also with no draft gate, and it
IS path-filtered (`scenes/`, `scripts/`, `assets/`, `project.godot`, `demos/*.json`,
`demos/scenarios/`, `demos/inputs/`) -- but that filter buys a held draft almost nothing,
because on a `pull_request` event GitHub matches `paths:` against the **pull request's whole
changed-file set**, not against the individual push's own delta. Once a PR's diff has touched
a watched path at all, every later `synchronize` re-runs `demo`, including a push that touches
nothing relevant.

#1349 is the worked proof, and it is checkable: commit `f1beab07` changed exactly one file,
`.github/workflows/claude-code-review.yml`, which is not in that list -- and Demo video run
`32520548972` fired on it anyway, because the PR's cumulative diff carries
`scripts/UnitManeuver.gd`. So the only PR a path filter actually spares is one that has never
touched a watched path in its whole life; this entry's own PR, #1362, is that case -- it
touches `.claude/memories/` only and got no `demo` check on any of its heads. Never reason
about a path filter from what a single push changed. Draft it for the signal and to stop
burning review rounds -- not on the belief that it makes the hold free.

**The failure has to belong to someone else.** This rule covers a pre-existing bug the PR
merely surfaces, or a flake tracked elsewhere -- cases where the fix is somebody's tracked
issue and waiting is the only way to get a true green. A defect the PR itself introduced is
not a hold: it is yours to fix on the branch now. Deciding which one you have is the first
step, not an afterthought.

This last paragraph is a deliberate narrowing, recorded here rather than left implicit. The
first draft of this entry -- and the tracking issue's restatement of it -- said the rule
"Applies both to the PR's own defects **and** to pre-existing bugs the PR merely surfaces",
which was my paraphrase rather than the directive.

What separates the two cases is OWNERSHIP, not whether a fix PR exists. A pre-existing bug is
somebody else's tracked issue, so waiting is the only route to a true green; a defect you
introduced is already yours, so there is nobody to wait for. Don't reach for "there is no PR
to wait on" as the discriminator -- as the paragraph above establishes, a legitimate hold
usually has no fix PR either at the moment you file it, so that test would throw out this
section's own worked examples. The narrowing is the reading that makes the rule executable.

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
  full verdict and then failed on a step downstream of it. **Confirmed** is the load-bearing
  word, and `07-...md` is precisely about why a fingerprint cannot do the confirming: a
  `claude-review` dying at ~40s with `total_cost_usd: 0` covers quota exhaustion (which does
  clear on its own), expired credentials, AND a plugin-install failure -- identical cost,
  identical duration, and only the last one "will never clear on its own", so that "a
  retry-and-wait on this one waits forever". Its instruction is to read the job's own
  `##[error]` lines before classifying by the fingerprint. That is a DIFFERENT diagnostic
  from the STEP LIST reading the same file prescribes for its other case (verdict posted, a
  later step failed); two procedures for two failures, so don't merge them into one habit.
  What this section forbids is the different move of re-rolling a *nondeterministic gate
  whose defect is already tracked* until it happens to land green -- the flake is the known
  bug, so a green re-roll is an unearned pass rather than a recovered run.

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


## Batch a review round's fixes into one push; a superseded head's red check is not a defect

The review workflow runs with `cancel-in-progress`, so pushing while a round is in flight
kills it. Fixing findings one at a time as they arrive therefore costs a round per finding and
leaves a trail of red `require-review` checks on the intermediate heads -- one push per
finding produced three of them inside four minutes.

Those reds look exactly like defects and are not. **The check reports on the head it ran
against, not on the PR's current head**, so the discriminator is a SHA comparison:

```sh
gh pr view <N> --json headRefOid --jq .headRefOid     # or pull_request_read -> head.sha
# then compare against the failing check run's own head_sha
```

A failure whose `head_sha` is not the current head does not describe the current head. That is
all it establishes -- **it is not evidence the cause is gone.** Under the same
`cancel-in-progress` mechanism, a later push does not guarantee the new head got a completed
run of its own; that run can be cancelled or still queued. So confirm the current head has its
own COMPLETED run of that check before treating the older red as noise, and reproduce the
failure fresh if it does not.

The narrow case where a stale red really is a pure artifact is `require-review`, which mirrors
`claude-review`'s result and carries no independent information: cancel the review and it goes
red by construction. A stale `Validate & test` or `Coverage` deserves the confirmation above.

Wait for the round's verdict, collect every finding it posted, fix them together, push once.
The exception is a finding that makes the current head actively misleading to the reviewer
still reading it, which is rare.

- **Do:** wait for the verdict, then push one commit addressing the whole round.
- **Do:** compare a red check's `head_sha` against the PR's current head, then confirm the
  current head has its own completed run of that check.
- **Don't:** push per finding as findings arrive -- each push destroys the round evaluating
  the text you just corrected.
- **Don't:** read a stale `head_sha` as an all-clear; it says the result is about another
  commit, not that the failure is fixed.
- **Don't:** report a stale head's red check in a status summary without saying it is stale;
  it reads as an unresolved failure.

## `length_squared()` thresholds: the risk is not the comparison, it is the signature

Three concurrent PRs converted `length()` comparisons to `length_squared()` in this repo, so
the failure modes are worth stating precisely -- including the one that is NOT a failure mode,
because guessing wrong at it wastes a review round.

**A positive threshold is always safe.** Squaring is monotonic on non-negatives, so for any
`v >= 0` and `G > 0`, `v > G` and `v*v > G*G` are equivalent -- at every value of `G`, not
just at 1.0. A conversion that squares both sides of such a comparison cannot change
behaviour, and claiming it becomes a latent bug "if the threshold changes" is false.

**A negative threshold is the real sign trap.** `length() > x` is always true for `x < 0`
while `length_squared() > x*x` is not, so any threshold that can go negative -- a tunable, a
subtracted margin, a caller-supplied value -- breaks silently.

**The signature change is the one that hides**, and note that the equivalence above does NOT
cover it. That equivalence squares BOTH sides. When the conversion instead moves the squaring
to the CALLER, a caller left un-updated still passes plain `v` while the callee now compares
against `G*G`, so the live test is `v > G*G` -- one-sided, and monotonicity says nothing about
it. `v > G` and `v > G*G` agree for all `v` only when `G` is squaring's fixed point, `G = 1.0`.

`SoldierCollision.overcomes_static_friction` is the case to watch, because
`SoldierCombat.STATIC_FRICTION_VELOCITY_GATE` is exactly `1.0`. Under the conversion proposed
in the (unmerged, as of 2026-08-21) PR #1358 the parameter becomes `body_velocity_magnitude_sq`
and `SoldierMelee` is updated, while `test/unit/test_soldier_collision.gd`'s five call sites
still pass plain magnitudes. Those tests would still PASS -- not from monotonicity, but from
that fixed point -- while `body_vel_stationary = 0.5` silently stops meaning v = 0.5 and starts
meaning v ~ 0.707, so the suite quietly stops covering the boundary it was written for. Retune
the gate off 1.0, which this repo's own parameter-externalization convention invites, and the
same stale call sites flip outright and the suite fails.

- **Do:** grep for every caller and test of any function whose parameter the conversion
  re-scales, and update them in the same diff.
- **Do:** check whether a converted threshold can ever be negative.
- **Do:** check whether the squaring is two-sided (safe by monotonicity) or one-sided (safe
  only at `G = 1.0`) before reasoning about a conversion at all.
- **Don't:** claim a positive-threshold conversion is behaviour-changing -- verify the
  monotonicity argument before writing a finding about it.
- **Don't:** invoke monotonicity for a one-sided comparison; it does not apply, and citing it
  contradicts the two-sided rule above.
- **Don't:** treat a green suite as evidence the callers were updated; where the gate sits on
  squaring's fixed point it is evidence of nothing.

## Finish the reasoning before publishing it, especially in a review comment

A review finding posted to someone else's PR is the worst place to think out loud. One posted
here contained a false claim and a visible half-finished derivation (`"1.5 < 2, gated... wait"`)
that reached no conclusion, and needed a retraction comment minutes later.

The tell is writing a claim whose justification you are still deriving as you type it. The
fix is mechanical: derive it in a scratch buffer, state the conclusion, and paste the check
that settles it. If the check cannot be pasted, the finding is not ready to post.

- **Do:** settle the argument first, then write the comment as a conclusion plus its evidence.
- **Do:** retract plainly and immediately when a published claim turns out false, and say what
  survives.
- **Don't:** publish a sentence containing your own hedging mid-derivation.


## A bespoke probe is not verification; run the suite first

A `scripts/` diff that changed the formed-pivot pacing in `Unit.gd` was pushed with
"verification" consisting of `gdlint` plus a hand-written GUT probe. The probe measured
one number -- turn rate holding at 40.7 deg/s instead of collapsing to ~11 -- and the
number moved the right way, so the change looked measured rather than guessed.

`tools/check.sh validate test chars comments units patch_coverage`, run later, failed
**four** tests that pass on the same branch's base (2791/2791 -> 2787 passing, 4
failing). Three of them, in `test/unit/test_unit.gd`, assert the exact invariant the
change broke: that a formed pivot IS slower at speed than at a stand, and that the
body-acceleration cap governs at a sprint. The collapse to 11 deg/s that the probe was
built to eliminate **was the design**, already written down as an executable assertion.

The failure is not "forgot to run tests". It is building an instrument to measure a
quantity you have already decided is the problem, and never asking whether the repo
already encodes the opposite. A bespoke probe can only answer the question you thought
to ask; the suite answers the ones you didn't.

- **Do:** run `tools/check.sh ... patch_coverage` on a `scripts/` diff BEFORE writing any
  bespoke instrumentation. It is the cheapest way to discover that the behaviour you are
  "fixing" is a specified invariant, and it costs one run instead of a review round.
- **Do:** when a probe's number moves the way you hoped, go looking for the test that
  disagrees before writing it up. `grep` the suite for the function you touched.
- **Don't:** list `gdlint` + a scratch probe under a "Verification" heading. Lint proves
  the file parses. Name what you actually ran.

## Check a gate factor's value in the case the pacing exists for

The same change reused the turn-before-march gate factor as a pacing input:

```gdscript
var march_frac: float = clampf(facing.dot(steer_dir) * 2.0, 0.0, 1.0)
var marched_speed: float = _current_speed * march_frac
```

The reasoning was sound in the abstract -- the accelerator and the brake should read the
same variable. But `clampf(dot * 2.0, 0.0, 1.0)` is **exactly 0.0** for every bearing at
or past 90 degrees, so `marched_speed` is 0 there, and every bound computed from it
switches off: the taper returns full `TURN_RATE` (180 deg/s, identical to a standing
unit) and the `marched_speed > jog_speed` gate on the body-accel cap never fires (a
fixture the cap says should turn 2.1 deg/s turned 162.7 deg/s, 75.7x over).

A bearing at or past 90 degrees is the case the taper and the cap were written for. The
change removed the brake precisely where it was load-bearing, and looked correct
everywhere else -- which is why almost every demo scenario showed no difference at all
(see the sweep entry below for how nearly that "no difference" was itself over-claimed).

- **Do:** before multiplying a pacing/limit quantity by a gate factor, evaluate the
  factor at the extreme the limit exists to handle. If it is 0 or 1 there, the limit is
  gone or unbounded there.
- **Do:** treat "this makes two call sites read the same variable" as a hypothesis, not
  a proof. Symmetry is not correctness when one side is a throttle.

## Diff two transcripts by `uid`, not by list index

Comparing before/after `dump-state.sh` transcripts with `zip(before["units"],
after["units"])` is wrong the moment a unit is annihilated in one run and not the other:
every unit after it in the list is compared against its neighbour, which invents large
deltas out of nothing (a unit "moving" 190 wu because it is being compared to a
different regiment) and can equally hide a real one. The dumps carry a stable `uid`
field; key on it, and report a roster divergence (a uid alive in one run only) as its
own finding rather than letting it silently corrupt the position math.

The whole-corpus sweep this came from is worth reusing as a method: two `git worktree`s
at the two commits, `diff -rq` over `scripts/` to prove exactly one file differs, then
every `demos/inputs/*.json` through `dump-state.sh` on both sides. 146 scenarios take
about 40 minutes with the two runs in parallel, and an answer of the shape "almost all
show no difference, a handful change, and one of those reaches a different battle
outcome" is the kind of claim a spot check cannot make.

**But run it against CI's own website demo-diff before trusting it, because a hand-rolled
sweep is easy to under-scope, and both ways it fails are silent.** The first attempt
sampled every 60th tick up to 600 and enumerated `demos/inputs/` only. CI's diff, which
walks every tick and reads `website/tools/demo-catalog.sh`, found two things that sweep
could not: a scenario whose transcripts first diverge at tick 751 (reported "no
difference" because the sampling stopped at 600 -- and a coarse tick set always reports a
LATER onset than the real one), and two changed clips of `type=replay`, whose sources
(`demos/showcase.json`, `demos/charge_demo.json`) do not live under `demos/inputs/` at
all. CI also diffs `DemoDefects` verdicts per side and surfaced three new defects the
position-only comparison had no way to see -- including a `blob`, the exact failure the
changed code existed to prevent.

- **Do:** key transcript comparisons on `uid`; surface roster differences separately.
- **Do:** run each script to its own full length, cover the `replay`-type catalog entries,
  and diff defect verdicts -- not just positions.
- **Do:** sweep the whole corpus before claiming a sim change is invisible or
  "backend-only". A change can show no difference in nearly every scenario and still flip
  who wins in the one long AI-doctrine battle.
- **Don't:** trust a per-scenario spot check to bound a change in a chaotic simulation.
- **Don't:** report "identical" when you mean "no difference at the ticks I sampled". Say
  which ticks, and say what the sweep did not cover.

## `lychee` exits 2 on a TIMEOUT, and the auto-filed issue calls it a broken link

The Check Links workflow on `main` filed an issue titled "Broken links detected in main
branch", with a body saying the checker "found broken links" and a directive to fix
them. The run's own summary said:

```
| 🚫 Errors      | 0     |
| ⏳ Timeouts    | 1     |
```

Nothing was broken. One third-party host missed `lychee.toml`'s `timeout = 20` on one
run; a re-run of the same commit passed in 13 seconds with no file changed. `lychee`
exits `2` for timeouts as well as errors, and the reporting step does not distinguish
them -- so the issue's title, body and fix directive are all false for a
timeouts-only failure, and send the reader hunting a URL that does not exist.

- **Do:** open the `Check links` step and read the status table before touching any
  link. `Errors: 0` means there is nothing to fix.
- **Do:** treat a timeouts-only failure as the sanctioned transient case -- re-run once;
  a PASS over the same corpus at the same commit is the discriminator.
- **Do:** if the same host times out again after a re-run, add it to `lychee.toml`'s
  `exclude` with a dated reason. That file already carries a dozen such host entries,
  two of them explicitly for the timeout case (`divideetimperamod.com`,
  `freesound.org`); that is the in-convention fix, not a link edit. Count them yourself
  rather than trusting a number written here -- the list grows.
- **Don't:** conclude from a sandboxed `curl` that the host is down. This environment's
  egress proxy answers `CONNECT tunnel failed, response 403` for hosts it does not
  allow, which is a fact about the sandbox, not the site.

## `check.sh demo_defects` is NOT a CI job -- a `skip` manifest leaves a clip unjudged by anything

`tools/check.sh demo_defects` reads as a CI mirror (its own docstring says the grading
matches "the CI step"), and `CLAUDE.md` tells you to run `check.sh` to reproduce CI's
gating checks. Neither statement is false, and together they invite a wrong conclusion:
grep `.github/workflows/` for `demo_defects` and it appears in **comments only**. No
workflow invokes it.

What CI actually runs is narrower on every axis:

- **`demo-video.yml`'s "Demo defect scan"** judges exactly ONE clip -- whichever
  `demos/demo.*.json` the PR added -- at that script's own declared tick set. Gating.
- **`website-demo-diff.yml`** runs the analyzer only over clips whose transcript
  **changed** versus the merge-base. Informational.
- **`website-demo-defect-sweep.yml`** sweeps the whole catalog absolutely, but only
  weekly on `main` (or by `workflow_dispatch`), reporting to a tracking issue.

The consequence that bites: a PR whose manifest sets `"skip": true` gets **no CI-side
verdict on any clip at all**. If the PR also touches no sim code, the demo-diff finds
nothing changed and scans nothing either -- so a claim about a clip's defect verdicts
has no CI measurement behind it, and a local run is the only evidence, which the
divergence section below says not to trust for this kind of clip.

**How to apply:** when a PR's deliverable is a claim about how the scan judges a
particular clip -- removing a `defect_exemptions` block, changing `judged_mask()`,
re-staging a scenario -- point `demos/demo.<N>.json` at **that clip** rather than
skipping, and say in the caption that the footage itself is unchanged. That is what makes
CI judge it. Reserve `skip` for a PR that genuinely has nothing to show AND makes no claim
about any clip's verdicts.

- **Do:** point the manifest at the clip whose verdicts the PR is about.
- **Do:** grep `.github/workflows/` before asserting that a `check.sh` subcommand runs in
  CI -- several do not.
- **Don't:** read `check.sh <name>`'s "mirrors the CI step" docstring as evidence a
  workflow calls it.
- **Don't:** ship a `skip` manifest on a PR whose whole argument is about a scan verdict.

(PR #1374, 2026-08-22: a `skip` manifest was written first, on the correct reasoning that
the diff touched only `tools/demo/` and no render path. It was replaced by an `input`
manifest once the gap above was traced -- and CI's scan then returned `25/25 verdicts
passed`, which was the PR's entire deliverable and which the skip would have silently
withheld.)

## A local dump of a long relief clip can invert a defect verdict against CI -- do not gate an exemption on one

The demos skill already warns that a local run and CI's transcript diverge late in a
long, chaotic battle, and scopes that warning to precise-tick claims in captions and
comments. It goes further than a caption: **the divergence is large enough to flip a
gating verdict.**

Measured on `demos/inputs/relief-fighting-withdrawal.json`, same seed, same commit:

| | local (Windows, headless) | CI (Linux) |
|---|---|---|
| `uid0 overlap` worst | **1.611** (FAIL, threshold 2.25) | **2.432** (PASS) |
| `expect:facing@300-500` | **FAIL** | PASS |

The `expect` row is the tell, and it is worth reaching for deliberately: nothing in the
diff touched facing, and CI had passed that same assertion on the PR that introduced it,
so a local failure there is a **self-test proving the local run is the unreliable one**.
Look for an assertion your change cannot have affected before trusting any local verdict
on a clip like this.

- **Do:** find an untouched `expect` assertion in the same run and check it first; if it
  fails locally and passes on CI, discard the local numbers wholesale.
- **Do:** get CI to judge the clip (see the section above) when the decision turns on a
  verdict.
- **Don't:** restore or retain a `defect_exemptions` block on the strength of a local
  FAIL, or delete one on the strength of a local PASS.

This one is mechanized rather than left to prose, because prose is what failed: the
local-vs-CI rule was on the books, was loaded in the session, and was read as governing
captions while a verdict decision went out on a local number.
`remind-ci-crosscheck-sim-verdict.py` in `Morrison-Lab/ai-config` fires when a
verdict-shaped figure (`worst=`, `nnd_min`, `N/M verdicts`, `PASS uid3`) follows a local
`dump-state.sh` / `analyze_transcript.gd` / catalog-sweep run with no CI-side read in
between. It only ever adds context -- a local figure is fine to report, and only wrong to
gate a decision on, which no regex can tell apart.

## Changing the ANALYZER? Dump once, analyze twice -- never compare two recordings

A change to `tools/demo/DemoDefects.gd` changes how transcripts are *judged*, not what
the sim *does*. Comparing two recordings to measure it is therefore the wrong experiment
twice over: it costs a second full catalog dump, and it mixes the analyzer delta with
run-to-run sim divergence, which the section above shows can exceed the effect being
measured.

Dump the catalog **once**, then run the sweep against those same transcripts with each
version of the analyzer:

```sh
website/tools/dump-demo-states.sh <tx>                      # once, ~85 clips
tools/ci/website-demo-defect-sweep.sh <tx> before.md <tree> # analyzer A
tools/ci/website-demo-defect-sweep.sh <tx> after.md <tree>  # analyzer B
diff -u before.md after.md
```

`website-demo-defect-sweep.sh` takes the tree whose analyzer and catalog it uses as its
third argument, so "analyzer A/B" can be two checkouts -- or one checkout with the single
function swapped between runs, which is cheaper and is what PR #1374 did.

The `diff` is the whole report, and it comes with its own **negative control**: the rows
that did not change. "Five verdicts changed, 80 clip rows byte-identical" is a far
stronger claim than "the catalog got greener", because a sweep that silently examined
nothing produces the same improvement and a very different diff.

## A widened `judged_mask()` cannot redden a verdict -- and the reason is worth reusing

Before measuring, the direction is provable by reading `_sustained_verdict()`: an
unjudged sample sets `run = 0` and is skipped before `worst` is accumulated, and the
`path_crossing` loop resets `cross_run` the same way. So exempting MORE samples can only
shorten a failing run and only make `worst` less extreme. No verdict can flip
PASS -> FAIL from a wider mask; the blast radius is entirely FAIL -> PASS.

The reasoning generalizes to any mask change: ask whether the metric's accumulator
**resets** on an unjudged sample or merely **skips** it. A reset makes widening monotone.
A skip would let two failing samples become adjacent in the judged series and manufacture
a sustained run out of a transient -- the opposite conclusion from the same edit.

Note `path_crossing` consumes the mask too, gated on BOTH ends of a step being admitted,
even though the module docstring long described the mask as governing "blob, overlap,
shape, misslot". A catalog sweep flipped one of its verdicts, which is how the omission
surfaced.

## Re-staging an existing demo? Check it has not become a twin of another catalog clip

The demos skill says to author each NEW scenario fresh rather than copying one. The
mirror case has no rule and is easier to fall into: fixing an EXISTING clip's staging by
adopting whatever staging is known to work, which is usually the staging of the clip
sitting next to it in the catalog.

`demos/inputs/line-relief-queue.json` and `demos/inputs/relief-fighting-withdrawal.json`
demonstrate different things -- the orders queue, and the relieved block holding its
facing. A proposed fix to the first adopted the second's spawn coordinates, box, and
click tick exactly, making the two catalog clips the same recording with two names. The
tell was numeric and free: both dumps reported `nnd_min 1.611` for `uid0` at tick 460,
which is what identical scenarios on one seed produce.

- **Do:** diff a re-staged scenario's `scenario`/`steps` against its neighbours in
  `website/tools/demo-catalog.sh` before committing.
- **Do:** differentiate by CONTENT rather than by cosmetics -- give the clip a setup its
  own caption needs and the neighbour's does not (here: a genuinely under-strength front
  block, so the strength disparity relief answers is visible rather than asserted).
- **Don't:** read "this staging is known to arm the order" as sufficient; so is the
  neighbour's, which is why it was copied.

## `check-pr-fully-clean.py` needs `PYTHONUTF8=1` on Windows, and `PYTHONIOENCODING` is not enough

The ARDI gate crashes on this machine before it reaches a verdict: the reader thread decoding `gh`'s output dies with `UnicodeDecodeError: 'charmap' codec can't decode byte 0x8f`, `res.stdout` comes back `None`, and `run_cmd` raises `AttributeError: 'NoneType' object has no attribute 'strip'`.

**It exits 1 doing so, which is the code reserved for "not clean".**
So a crashed check and a real blocking verdict are the same exit status, and only the output separates them: a genuine not-clean prints `  - ` finding bullets, a crash prints a traceback.

The obvious workaround does not work.
`PYTHONIOENCODING=utf-8` reconfigures the parent's own stdio and leaves `subprocess.run(..., text=True)` decoding with the locale codec, which is where the failure is.
**`PYTHONUTF8=1` fixes it** -- UTF-8 mode applies to the whole interpreter, subprocess pipes included.

```sh
PYTHONUTF8=1 python3 <ai-config>/scripts/check-pr-fully-clean.py <N> -R <owner>/<repo>
```

Tracked upstream as Morrison-Lab/ai-config#1984, which also collects the *encode*-direction siblings (`check-links.py`, `check-hook-output-shape.py` dying on their own U+2713 success line, where `PYTHONIOENCODING=utf-8` IS sufficient because those only print).

- **Do:** prefix the fully-clean gate with `PYTHONUTF8=1` on Windows.
- **Do:** read a rc=1 with no `  - ` bullets as a crashed check rather than a verdict.
- **Don't:** reach for `PYTHONIOENCODING` for a decode-side failure; it governs the wrong stream.

## The gate's mirror false positive fires on a `### Findings` heading that says "None"

`check-pr-fully-clean.py` matched `#+\s*(Actionable\s+|Detailed\s+)?Findings` against a review whose Findings section read, in full, "None. No bugs, hallucinated APIs, or CLAUDE.md violations found." -- and reported the PR NOT clean while its own `verdict scan:` line on the same run said `latest = clean`.

`fully-clean.md` documents this direction, so the remedy is prescribed rather than improvised: read the verdict body when the script reports findings against a review whose prose merely discusses finding vocabulary.

What makes it worth a note here is the pairing. The script prints both signals, and they contradict each other in the same output:

```
verdict scan: examined 4 dated automated review item(s), 1 bore a verdict, latest = clean
NOT fully clean:
  - Review comment for SHA ... contains findings (matched pattern '#+\s*...Findings')
```

Reading only the bottom line reports a clean PR as blocked.

- **Do:** read the `verdict scan:` line and the finding bullets together, and open the review body when they disagree.
- **Don't:** treat a `contains findings (matched pattern ...)` bullet as a finding without reading what it matched.

## Merging a stack: verify each PR at its own head, immediately before its own merge

Four PRs merged in dependency order (#1374 -> #1377 -> #1378 -> #1348), the last carrying the first two as stacked merges.

Two things this made concrete:

**The stacked PR's checks were still running when its dependencies merged**, and it went green on its own without a re-push -- the two earlier merges did not invalidate it, because its branch already contained them. So a stack does not necessarily need a resync round between merges; check before assuming one.

**Re-verify per PR rather than once for the batch.**
A batch reading taken before the first merge describes a state that the first merge changes for every later member. The gate is cheap; run it immediately before each `gh pr merge`, and let its exit status decide rather than a table written earlier in the session.

- **Do:** run the fully-clean gate once per PR, immediately before that PR's own merge.
- **Do:** re-check a stacked PR's mergeability after its base lands, rather than assuming it needs a resync.
- **Don't:** carry one batch verification across several merges -- the first merge invalidates it.

## Creating a stacked PR requires `--base <parent-branch>` explicitly on `gh pr create`

Branching locally from another PR's branch (`git checkout -b <child-branch> <parent-branch>`) sets up the local commit history, but does NOT configure GitHub's PR base branch. `gh pr create` defaults to targeting `main` unless `--base <parent-branch>` is explicitly passed.

When a stacked PR is opened without `--base`:
1. The GitHub PR diff displays the cumulative diff of BOTH the parent PR and the child PR against `main`.
2. Merging the child PR merges all parent commits directly into `main`.
3. The parent PR's branch on GitHub then matches `main`, turning the parent PR into an empty diff.

**Rule:** Whenever opening a stacked PR, always pass `--base <parent-branch>` explicitly (`gh pr create --base <parent-branch> ...` or via API). When the parent PR merges to `main`, retarget the child PR back to `main` via `gh pr edit <child-N> --base main`.

- **Do:** pass `--base <parent-branch>` explicitly to `gh pr create` whenever creating a stacked PR.
- **Do:** retarget the child PR to `main` after the parent PR merges.
- **Don't:** assume `gh pr create` infers the base branch from the local tracking branch.

(`Lacaedemon/sparta` PR #1391 / #1390, 2026-08-24.)

## gha / ai-config workflow inventory (after #1396)

Sparta is a Godot + Quarto consumer of `Morrison-Lab/gha`, not an R package.
PR #1396 audited `examples/` against `.github/workflows/` and added the
applicable remaining callers.
Do not re-run that audit from scratch; this is the inventory.

**Already present before #1396:** `check-links`, `check-non-standard-chars`,
`claude.yml`, `claude-code-review.yml`, `summary.yml`, `quarto-publish.yml`
(via `publish-site.yml`), and a three-workflow preview family
(`website-preview.yml` / `-deploy` / `-cleanup`).
Godot CI, coverage, demos, and gdlint stay local.

**Added in #1396:** `check-junk-files`, `check-secrets`, `check-ai-tells`
(advisory; ignores `.claude/` `.gemini/` `.agents/`), `lint-workflows` /
`lint-yaml` / `lint-markdown` / `lint-qmd` (advisory `fail: false` on first
adoption), `check-new-line-breaks` (diff-scoped, blocking),
`website-preview-equations.yml` (gha `check-equation-renders` -- the preview
family is four workflows, not three), `report-failure` on `publish-site.yml`,
and on-request Jules (`jules-review.yml`, `@jules review`).
The repo has `JULES_API_KEY`.

**Do not add without a new secret or an explicit policy change:**
Gemini / Antigravity / Cursor Bugbot / OpenCode / `ai-code-review`.
`gh api repos/Lacaedemon/sparta/actions/secrets` (as of 2026-08-25) listed
only `CLAUDE_CODE_OAUTH_TOKEN`, `CODECOV_TOKEN`, and `JULES_API_KEY`.
`GEMINI.md` also pauses automatic Gemini/Antigravity review for quota.

**Skip as R-package-only or otherwise inapplicable:** `check-news`,
`lint-changed-lines`, gha `test-coverage` (covr), `spellcheck`,
`update-snapshots`, `bump-dev-version`, `version-check`,
`altdoc-multiversion-docs`, `check-bibliography-dois`, `check-phi`,
`request-dependabot-review` (no `dependabot.yml`), `bump-submodule` /
`sync-shared-fragments` / `sync-upstream`, `small-model-agent`.

**How to apply:** list repo secrets before copying a secret-gated gha example.
Start corpus-wide markdown/yaml/qmd/workflow linters at `fail: false`.
If the site has MathJax, install `check-equation-renders` as the fourth preview
stub and keep its `workflows:` name matched to `Website Preview Build`.

On this repo `gh pr edit` (body or `--add-label`) fails with the Projects
Classic GraphQL deprecation.
Patch the body with
`gh api -X PATCH repos/Lacaedemon/sparta/pulls/<N> -F body=@file.md`
and add labels with
`gh api -X POST repos/Lacaedemon/sparta/issues/<N>/labels -f "labels[]=<name>"`.

(`Lacaedemon/sparta` PR #1396 / issue #1395, 2026-08-25.)

