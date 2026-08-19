## A caching fallback outlives the window that produced it -- never commit a placeholder as an answer

A lazily-rebuilt per-soldier assignment (the `_ensure_*_assignment` family) guards its rebuild
on a committed key: `if _sim_soldier_square_slot.size() == count and _square_slot_files == files:
return`. If the rebuild has a fallback branch for "the inputs could not be read this tick," and
the function commits the key unconditionally afterwards, the fallback **satisfies the guard
forever after** -- the placeholder is never reconsidered, long after the condition that produced
it has passed. The bug is not the fallback; it is committing the key on the fallback path.

Shipped and caught in review on PR #1158: `_ensure_square_slot_assignment` fell back to
`identity_assignment` (the exact pre-fix layout the PR existed to remove) whenever
`_slot_frame_positions` returned empty, then set `_square_slot_files = files` regardless. A
settled square hit that window on its first melee strike and stayed on the index-order layout
for the rest of its life -- strictly worse than the bug being fixed, and in exactly the
anti-cavalry scenario the PR targeted.

**How to apply:** any lazy-rebuild function with both a real path and a degraded path must commit
its freshness key only on the real path (`_square_slot_files = files if not live.is_empty()
else -1`). Leaving the key invalid costs a recompute per tick until the inputs are readable
again, which is the correct trade: a cheap repeated attempt beats a permanent wrong answer.

## There are TWO casualty paths and they have opposite array-sync semantics

Easy to miss, and it makes a whole class of test structurally unable to reach a whole class of bug:

- **Per-soldier path** -- `SoldierMelee.reap()` splices every per-soldier array at the dead man's
  index, so `soldiers` and the arrays stay in sync, and per-soldier identity survives.
- **Regiment path** -- `UnitCombat.take_casualties` (`scripts/UnitCombat.gd`) does `u.soldiers -=
  total` and touches NO per-soldier array. It never says which man died. `SoldierBodies.step`
  then queries `soldier_world_slots(unit.soldiers)` BEFORE resizing `_sim_soldier_pos` to match
  later in the same call, so there is a guaranteed window where the body layer is LARGER than the
  live count.

The regiment path is not an edge case: the per-soldier path is gated on `is_engaged()`, a latch
that arms one tick after `FIGHTING` starts, so the **first strike of every fresh contact** goes
through the regiment path (as does every strike for a ranged unit in melee, plus `absorb()` and
`disengage_with_sacrifice()`).

**How to apply:** any new per-soldier state must be correct across BOTH paths, and a test that
only drives `SoldierMelee.reap()` proves nothing about the regiment path -- it is the one path
that keeps the arrays in sync, so it cannot reach a desync bug at all. Drive the regiment shape
explicitly (drop `soldiers` with the body arrays left untouched, then step) as its own test.
Note also that a body layer larger than `count` is real data, not a fault: `resize()` trims at
the tail, so the leading `count` entries are exactly the survivors, still index-aligned.
(PR #1158.)

## Never pin a benchmark number in PR prose -- the comment updates in place

The `sparta-benchmark` PR comment is rewritten in place on every push, so any figure copied out
of it into a PR description, a commit message, or a review reply goes stale silently and reads
as a live measurement. Worse, the run-to-run spread is large enough that the number was never
meaningful: across three pushes of essentially identical code on PR #1158 the same comment
reported **-7.0%, -0.2%, and -1.8%** against the same baseline -- the CI-runner variance
`tools/benchmark/baseline.json`'s own `_comment` already documents.

Quoting one of those produced a wrong claim in the PR description (caught by review), and then a
wrong correction of the correction. **Describe the result qualitatively ("neutral, inside the
threshold") and point at the live comment** rather than freezing a figure. Reserve actual numbers
for a same-machine local before/after comparison, which is the only form that controls for runner
noise.

## GitHub Actions does NOT follow a repo-transfer redirect for `uses:` -- and `gh api` DOES, which hides it

When the shared CI repo moved from `d-morrison/gha` to `Morrison-Lab/gha` (2026-07-28), every
sparta workflow calling a gha reusable workflow broke at once, repo-wide, on every push. The
failure signature is distinctive and easy to misread:

- The run **fails instantly at startup**: zero jobs scheduled, `created_at == updated_at`, and no
  check-run annotations to read (`gh run view --log-failed` reports "log not found").
- `gh run list` shows the run's name as the raw **`.github/workflows/x.yml` path** instead of the
  workflow's own `name:` field -- the tell that GitHub could not resolve the workflow at all.
- `gh run rerun` refuses outright: *"cannot be rerun; its workflow file may be broken."* A
  startup-failed run needs a **fresh trigger** (a push, or close/reopen); it can never be re-run
  in place.

**The trap that cost the most time:** `gh api repos/d-morrison/gha` transparently follows the
transfer redirect and returns `"full_name": "Morrison-Lab/gha"`, and every content path still
resolves under the old owner. So a check of "does the reference still work?" via `gh api` says
YES while Actions says no. Actions is the only authority here. On the first occurrence this was
misdiagnosed as a transient migration window and reported as self-healed; the very next push
failed identically, which is what forced the real diagnosis.

**How to spot it:** if several unrelated workflows fail at startup simultaneously, check what
they have in common -- here, every failing workflow was an external `uses: <owner>/<repo>/...`
caller and every passing one was self-contained. Confirm repo-wide (not PR-specific) by listing
one workflow's runs across all branches and finding the timestamp where success turns to failure.

**Fix:** retarget the references to the new owner, keeping the `@vN` pin, and verify every
distinct referenced path resolves at the new owner's tag before pushing. The consuming repo's own
CI is the real test -- if the previously-dead workflows schedule jobs and report their real names
again, the diagnosis and the fix are both confirmed. (sparta #1159/PR #1160: 11 call sites.)

**A still-open PR branch cut BEFORE the retarget carries the stale refs itself, and `gh run
rerun` reproduces the failure rather than recovering from it.** `main` being fixed does not help a
branch whose own `.github/workflows/` still says `d-morrison/gha`: every fresh trigger on it
startup-fails with zero jobs scheduled, no logs, and no annotations, and re-running that branch's
last SUCCESSFUL run on the same head startup-fails too -- which makes it look intermittently
broken rather than deterministically so. The fix is to merge `main` into the branch. Diagnose with
`git merge-base --is-ancestor <retarget-commit> <branch>` and confirm with
`git show <branch>:.github/workflows/<wf>.yml | grep uses:` (on Windows Git Bash that needs
`MSYS_NO_PATHCONV=1`, or the revision:path argument gets mangled into a Windows path).
(`Lacaedemon/sparta` PR #1135, 2026-07-29: stuck five review rounds, and the sixth could not
be triggered at all
until `main` was merged in -- after which the review ran normally and passed.)

**Related gotcha:** a PR that edits `claude-code-review.yml` makes the `@claude` review self-skip
by design (every step reports `skipped`; the action 401s validating a workflow file from a PR
ref). That is the benign skip, NOT a stub review -- read the run's step list to tell them apart.
Combined with Copilot being quota-exhausted, such a PR can have no automated verdict at all, in
which case the standing rule applies: do the review yourself and post it before merging.

**The account move was not limited to `gha` -- `ai-config` followed, and the thing that
actually breaks CI is the MARKETPLACE NAME, not the URL.** `d-morrison/ai-config` moved to
`Morrison-Lab/ai-config` the next day (2026-07-29) and, in the same move, its
`.claude-plugin/marketplace.json` renamed the marketplace itself from `d-morrison` to
`Morrison-Lab`. Those are two independent changes, and only the second one is fatal: git and
`gh` both follow GitHub's transfer redirect, so the marketplace CLONE still succeeds from the
old URL -- but a plugin ref is resolved by the marketplace's DECLARED name, which no longer
matches. `review / claude-review` then dies at plugin install, before reviewing anything:

```
Action failed with error: Failed to install plugin 'ai-config@d-morrison' (exit code: 1)
Claude review did not complete successfully and was not eligible for a stub-review retry
```

`review / require-review` fails with it, and it is required -- so the whole repo is
unmergeable. The signature differs from every other review failure documented above: the job
posts **no review comment at all**, so there is no stub body to read and no verdict to
mistake for one.

**The fix is NOT in this repo's `.claude/settings.json`.** That file's marketplace
registration governs LOCAL Claude Code sessions only; the review job never reads it. The
plugin ref the job installs is hardcoded as a built-in default in the reusable workflow
(`Morrison-Lab/gha`'s `claude-code-review.yml`, its `use-ai-config` input). A caller
overrides it with the trio `use-ai-config: false` plus `plugin-marketplaces` /`plugins`
naming the marketplace's current name -- and the workflow's own docs warn that the name
"must match the name that marketplace declares in its own .claude-plugin/marketplace.json --
it is not derived from the URL". Retargeting `settings.json` is still correct for local
sessions, it just fixes a different thing; the first attempt at this fixed only that and the
review failed again identically, with the error still naming the OLD `ai-config@d-morrison`
even though the PR's own settings.json said `Morrison-Lab` -- which is the tell that the ref
comes from upstream, not the checkout.

**Generalize rather than patching one repo at a time:** when ANY repo under a consumed
account moves, grep your own repo for **every** reference to that account -- `uses:` refs,
marketplace sources, submodule URLs, prose links -- and then check whether the moved repo
also renamed anything a consumer resolves BY NAME rather than by URL. Distinguish real repo
paths from lookalikes: a `reviewer: d-morrison` workflow comment is a GitHub **username**
(unaffected by a transfer), and `website/_extensions/d-morrison/equation-anchors/` is a
Quarto extension install path that only changes via a Quarto reinstall. Note also that a PR
editing `claude-code-review.yml` makes the review self-skip by design, so a fix applied there
cannot verify itself -- confirm it on the NEXT PR's review run instead.
(`Lacaedemon/sparta` #1171/PR #1172, 2026-07-29: caught when the first PR pushed after the
move failed review; the last green run was 30 minutes earlier.)


## A PR-description edit can duplicate the CI-managed demo block

`demo-video.yml` upserts its clip into the PR **description**, between `<!-- sparta-demo -->` and
`<!-- /sparta-demo -->`. A programmatic description edit that disturbs the whitespace around those
markers makes the next upsert fail to match, so it **appends a second block** instead of replacing
the first -- leaving a superseded commit's GIF live alongside the current one, rendering as two
"Gameplay demo" sections.

After any `gh api .../pulls/N -X PATCH` on a body, check `grep -c '<!-- sparta-demo -->'` is
exactly 1 and that no superseded SHA remains. When rebuilding a body programmatically, capture the
block with a regex and re-append it verbatim, newlines included.
(`Lacaedemon/sparta` PR #1135, 2026-07-29.)

**That check has to run again after the NEXT demo workflow completes --- immediately after your
own PATCH it passes even when the damage is already done.** The duplication is not something your
edit writes; it is something `demo-video.yml` writes later, when its next upsert fails to match
the markers you disturbed and appends a second block instead of replacing the first. So the
sequence is: you edit, you check, the count is 1 and the check looks satisfied, and the second
block appears minutes later on the next push or re-run.

Concretely, the count is a lagging indicator of an edit you already made, so treat a passing check
immediately after a PATCH as establishing nothing. Re-read the body once the demo job for the
following push has finished --- or simply before reporting the PR ready, which is the moment the
description gets read anyway:

```bash
gh pr view <N> --json body --jq .body | grep -c '<!-- sparta-demo -->'   # expect 1
```

Repairing it is a dedupe rather than a rewrite: strip every block with a regex, then re-append the
**last** one verbatim, since that is CI's most recent upsert and the earlier copies are stale.
Confirm afterwards that whatever else you had added to the body (an embedded image, a corrected
claim) survived the strip --- the naive `re.sub` that removes the blocks will happily remove
anything you nested between them.

(`Lacaedemon/sparta` PR #1196, 2026-08-07: a description edit adding a required UI screenshot and
correcting two stale claims was checked immediately afterwards and read exactly 1 block. The
round-5 review then found 2, from CI's own re-upsert in between. The rule above was followed to
the letter and still missed it, which is why the timing needs saying rather than the check.)

**The GitHub MCP tools STRIP HTML comments from a PR body, so round-tripping the body through
them destroys the markers outright.** The entry above is about an edit that merely disturbs the
whitespace *around* the markers. This is worse and quieter: `mcp__github__pull_request_read`
(method `get`) returns a body with `<!-- sparta-demo -->` / `<!-- /sparta-demo -->` already gone,
so the natural read-modify-write --- fetch with that tool, edit the prose, pass the result to
`mcp__github__update_pull_request` --- publishes a body with no markers at all. CI's next upsert
then has nothing to match and appends a whole second block, and unlike the whitespace case there
is no partial damage to notice: the markers were never in the string you edited.

The tell is a byte-count mismatch between the two surfaces. Measured on PR #1263, 2026-08-16: the
MCP `get` body carried `### 🎬 Gameplay demo` with **zero** markers, while the same body fetched
raw from `https://api.github.com/repos/<owner>/<repo>/pulls/<N>` had 1 open + 1 close at 6782
bytes. Nothing in the MCP response says a field was elided.

So edit a PR body through the **raw API**, never through the MCP round-trip: fetch the body with
`curl`/`urllib` against `api.github.com`, do a surgical `str.replace` on a paragraph well away
from the markers, and **assert before PATCHing** --- open count 1, close count 1, the demo asset
URL still present, and the body no shorter than it started.

**Don't gate a write on verifying the credential first --- and don't assume a `GET /user` probe
behaves the same way in every session, because it does not.** Measured 2026-08-16 in PR #1273's
own session, three calls to `https://api.github.com/user` --- no `Authorization` header at all,
`Bearer not-a-real-token`, and `Bearer $GH_TOKEN` --- each returned **200** with
`login: d-morrison`, so in that session the agent proxy authenticates the request and the header
is ignored. The automated reviewer on PR #1273 ran the first two of those probes from its own
environment and reported **401** for both. Both readings can hold at once: whether an outbound
call is proxy-authenticated is a property of the SESSION's egress configuration rather than of
the GitHub API, so neither result generalizes to the next session.

That environment-dependence IS the lesson, and it is `fail-fast`'s negative-control rule arriving
in a new place: a check whose pass path and failure path are indistinguishable is not a check. So
before trusting any auth probe, run it once with a deliberately bogus credential. A **401** means
the probe discriminates and you can rely on it; a **200** means it is measuring your egress path
rather than your token, and it will report success whatever the credential is.

`GH_TOKEN` and `GITHUB_TOKEN` were both set in that session, identical, and **14 characters**
(re-measured the same day), which is shorter than any real GitHub credential format --- classic
PATs are 40 hex, and `ghp_`/`github_pat_` run longer. In a proxy-authenticated session that is
consistent with a placeholder; in a session where the header IS honoured the same value would
simply be a broken token, so the length alone does not tell you which. The practical consequence
is the same either way: authenticated writes worked there from a session with no `gh` on `PATH`
and a token that looks wrong, so don't conclude a PATCH is impossible by inspecting the variable
--- make the call and read the status.

- **Do:** patch a PR body from the raw API, with marker-count assertions guarding the PATCH.
- **Do:** re-check the count again after CI's *next* demo run, per the timing rule above --- the
  two checks catch different halves, and this one does not replace it.
- **Don't:** pass an MCP-fetched body back to `update_pull_request`; the markers are already gone
  from the string, so the assertions have nothing left to protect.
- **Don't:** carry one session's proxy-authentication over to another --- run the
  bogus-credential control in the session you are in and let it decide.

## An umbrella issue at 5/5 children can still have unshipped scope its own phases named

An umbrella's `sub_issues_summary` reaching `percent_completed: 100` is a fact about how many
child issues got closed, not about what shipped. A phase issue can be closed as `completed` while
part of the scope written in its own body was quietly deferred elsewhere --- so before closing an
umbrella, grep `scripts/` for the concrete symbols its taxonomy and its phases name, and let the
code decide.

Worked instance (#516, closed 2026-08-16). All five phases (#522-#526) read closed/completed, and
the design landed as `docs/orders-queue-design.md`. But #516's own taxonomy and #524's scope both
name `SwitchWeaponOrder`, and `git grep -n "switch_weapon\|SwitchWeapon\|active_weapon" -- scripts/`
returns **nothing** on `main`: `Order.Type` carries twelve kinds (`MOVE`, `ATTACK`, `RELIEF`,
`SUPPORT`, `WHEEL`, `NUDGE`, `FORMATION`, `FRONTAGE`, `ABOUT_FACE`, `QUARTER_TURN`, `STANCE`,
`FORM_UP`) and no `SWITCH_WEAPON`.

The resolution turned on **which tree the deferred item belongs to**, which is worth checking
before either closing or holding an umbrella open. Here it was not unfinished #516 work at all:
weapon switching is phase 4 of the loadout series (#535), tracked as **#539**, which names #516 as
*its* dependency rather than the reverse. So #516 was genuinely complete and closable, and the
comment recording that is what stops the next reader re-deriving it. Had #539 been a child of
#516, the same evidence would have argued for leaving it open instead.

- **Do:** grep for the named symbols before closing an umbrella, and say in the closing comment
  where any deferred taxonomy item actually lives.
- **Don't:** read `percent_completed: 100` as "the stated scope shipped" --- it counts closed
  children, and a child can close with part of its own body deferred.

## An `.import` diff that reads as deletion is a headless-Godot rewrite, not a removal

`.jules/bolt.md`'s own 2024-11-20 entry already says to revert `.import` sidecars a headless run
regenerated. The tell is easy to misread: in `--stat` and in `gh pr view --json files` the churn
shows as `0+ 6-` per file -- pure removals, which reads as *deleted files*. They are not deleted.
They are modified, losing engine-version-specific keys (`compress/uastc_level`,
`process/channel_remap/*`). Confirm with `--diff-filter=D` (returns nothing) before describing
them as deletions, and restore with `git checkout origin/main -- <paths>`. (Misdescribed twice on
`Lacaedemon/sparta` PR #1165 before checking, 2026-07-29.)

## Grep `main` before stripping a "noise" pattern a PR appears to introduce

Before removing a stylistic pattern a PR adds -- a narration comment, a redundant annotation --
`git grep` it on `origin/main` first. On `Lacaedemon/sparta` PR #1165 three
`# OPTIMIZATION: ...` comments looked
like that PR's own noise; 17 identical ones were already on `main` from earlier merged work.
Stripping only the PR's three is inconsistent, and stripping all 20 drags eight unrelated files
into a PR whose whole purpose at that moment was being minimal -- the exact collateral-scope
problem being criticised on that same PR. Leave the pattern and note it, or raise it as its own
sweep. (2026-07-29.)

## A report-generating workflow's data-gathering step needs `continue-on-error` plus `if: always()` downstream -- and a salvaged partial report must say so

A scheduled workflow whose whole deliverable is "a durable signal posted every week" is
defeated by the default GitHub Actions behaviour that a job stops at its first failing
step. If the data-gathering step can fail on one bad input out of many, and the
report-posting steps have no `if: always()`, then a single flaky input costs the entire
run's report -- with no diagnostic beyond a red scheduled run nobody is watching.

This is easy to ship because the *consuming* script is often written to handle missing
data gracefully, which makes the pipeline feel robust when it is not. `website/tools/
dump-demo-states.sh` `exit`s at the first clip that fails, times out, or writes no
snapshots (only two genuinely-skippable cases `continue`), leaving every later clip
undumped. The sweep script consuming it buckets a missing transcript as a `no transcript`
finding rather than something fatal -- but that bucket was unreachable for exactly the
failure it was written to describe, because the job never reached the sweep step.

**The second-order trap, which the obvious fix alone does not cover:** because the dump
aborts at the FIRST bad input rather than skipping it, everything after that point is
missing too. A salvaged report therefore renders as a wall of "no data" rows that read
like a mass regression rather than absent data. Thread the gathering step's own
`steps.<id>.outcome` into the report and prepend a warning when it is not `success`, so a
partial run is legible as partial. Verify by simulating the report body for both outcomes,
including that the success path renders identically to before.

(`Lacaedemon/sparta` PR #1175, 2026-07-29: caught in review, not by the implementation.)

## Extract a workflow's `run:` blocks and `bash -n` them -- valid YAML does not imply valid shell

Parsing a workflow as YAML proves the file's structure, not that the shell inside each
`run:` block is syntactically valid. Extract every `run:` body, stub the GitHub
expressions (`re.sub(r'\$\{\{[^}]*\}\}', 'EXPR', run)` -- they are not bash and will
fail the check spuriously), write each to a file, and `bash -n` it. On Windows write those
files to a RELATIVE path in the worktree: a Python `tempfile` path hands bash a
backslashed Windows path it silently mangles into "No such file or directory", which reads
as a syntax failure.

The same pass also catches a distinct and nastier failure: a generated block whose
intended backslash-n ESCAPES became REAL newlines. If any resulting line then starts at
column 1 inside a `run: |` block the YAML itself breaks -- a line beginning `>` (e.g. a
`> [!WARNING]` GitHub callout) is read as a block-scalar indicator, not text. Confirm with
`sed -n 'A,Bp' file | cat -A` that every line of the block is indented.

**The mechanism, which bit twice while writing this entry.** A doubled backslash inside a
shell heredoc that feeds Python collapses to a SINGLE backslash before Python parses it,
so `\\n` arrives as `\n` and Python turns it into a real newline. The tell is a
`SyntaxWarning: invalid escape sequence` on a sibling sequence: `\\$` survives as `\$`
precisely because it is not a valid Python escape, while `\\n` silently does not. To emit a
literal backslash-n through that path, build it from `chr(92)` (or quadruple the backslash),
or reword to avoid the literal entirely -- do not trust a doubled backslash to survive.

(`Lacaedemon/sparta` PR #1175, 2026-07-29: a warning-callout `printf` broke the workflow
this way; the YAML parse caught the column-1 case and the extraction pass confirmed the
repair.)

## The no-issue-numbers-in-comments rule does not cover generated issue/PR body text

CLAUDE.md's "Comments: no issue-number references" rule is scoped to code comments -- its
own rationale is that "a reader shouldn't need to open a tracker to understand the code"
-- and it explicitly allows issue numbers in commit messages, PR descriptions, and
`TODO`/`FIXME` markers. A workflow step that BUILDS a tracking-issue body is producing
tracker-facing content, not a code comment, so a cross-reference there is appropriate and
has direct precedent: `godot-ci.yml`'s own failure-issue `printf` cites the issue that
motivated its check. A reviewer flagging such a line is worth rebutting rather than
complying with; this rebuttal was accepted on re-review after the reviewer independently
confirmed the precedent.

The rest of the rule still bites, and this file already records it recurring. When a review
flags it, **grep the whole diff** (`grep -n '#[0-9]\{3,4\}'` over every changed file)
rather than patching only the flagged lines -- that is how the code-comment instances and
the legitimate issue-body one get correctly separated in a single round instead of two.

(`Lacaedemon/sparta` PR #1175, 2026-07-29.)

## `tools/check.sh file_length` is scoped to `scripts/*.gd` -- new `.sh`/`.yml` files are not capped

`check_file_length`'s `SPARTA_CHECK_MAX_NEW_FILE_LINES` budget (default 100) applies only
to files ADDED under `scripts/` with a `.gd` extension -- deliberately not `test/`, and not
shell or workflow files. A CI/tooling PR adding a 115-line script and a 117-line workflow
passes it untouched, reporting "No new scripts/*.gd files in this diff". Worth knowing
before restructuring a new tool to fit a budget that does not apply to it.

## A stubbed fixture built from your own premise tests the code, not the premise

The two entries above cover verifying a bug's stated ROOT CAUSE, and verifying that a fix
engages the reported bug's real CODE PATH. This is the third member of that family, and it
bites when the thing under test is CI tooling rather than sim code: when you stand up a
stub or a fixture to exercise a script in isolation, the fixture encodes your model of the
system, so any assumption baked into it is exactly what the test cannot check. It returns
the answer it was built to return, and reads as a clean verification.

Two instances in one PR (#1180, closing #1179), both caught by review rather than by the
verification itself:

- **An unconstructible state.** The fix bounded the demo defect delta to ticks before two
  runs diverge, and a stub "proved" it worked by returning DIFFERENT failing metrics for the
  two sides inside that window. That state cannot exist: `div_tick` comes from
  `DemoStateHash.cheap_tick_hash`, which hashes each unit's `position` plus the whole
  `_sim_soldier_pos` byte array EVERY tick -- the same data the position metrics read -- so
  below it the two sides are bit-identical by construction. The bound did not narrow the
  comparison, it emptied it, and the one fixture row that fired was the one row reality
  forbids.
- **A filename format nobody writes.** The rework read a clip's last tick out of
  `state_<tick>.json` names, and the fixture created them as `state_8.json`. Both producers
  (`DemoInputRecorder.gd`, `DemoStateSink.gd`) write `state_%05d.json`, and bash reads a
  leading-zero numeral as OCTAL: `00900` raises "value too great for base" and, under
  `set -euo pipefail`, aborts the whole step, while an all-octal-valid `01260` silently
  evaluates to 688 and prints a plausible-looking wrong percentage.

**How to apply.** When a fixture stands in for real data, derive its shape from the PRODUCER,
not from memory or from the consumer's expectations -- open the code that writes the
filenames, emits the field, or defines the invariant, and generate the fixture the same way
(here, `printf %05d`). Then prove the fixture bites: run it against the unfixed code and
confirm it actually fails. A fixture that passes both before and after has told you nothing.
And when a stub asserts two things DIFFER, first check whether the system permits them to --
an impossible fixture is worse than no fixture, because it manufactures confidence.

## The regiment damage formula is load-bearing for the regiment ENGAGEMENT gate

Do not try to make the opening melee blow resolve per-soldier while the engagement
gate stays regiment-level. The two are entangled, and removing one without the other
replaces a violent bug with a silent one.

`UnitCombat.strike()` picks per-soldier resolution only when both sides pass
`is_engaged()`. Two independent ordering artifacts make the DEFENDER fail that test on
the exact tick contact is made, so the opening blow of every melee falls through to the
regiment damage formula -- where the damage number is used as an ABSOLUTE soldier count
(`take_casualties` does `u.soldiers -= total`):

1. **The latch arms a tick late.** `_physics_process` runs `_think()` -- where a unit
   enters FIGHTING and lands its first strike -- BEFORE `tick_engaged()` sets
   `_engaged_linger`. So an attacker is fighting but not "engaged" during its own first
   strike, even though `ENGAGED_LINGER`'s doc says a regiment is engaged "while FIGHTING
   and for ENGAGED_LINGER seconds after".
2. **`_in_enemy_contact` is stale for whoever has not run yet.** Each unit fills it in at
   the top of its OWN `_think()`. Units resolve one after another within a tick, so the
   unit that goes first strikes while its target still carries LAST tick's value. This
   ordering asymmetry is also why the loser takes 100% of the casualties: it is dead
   before it ever gets a tick of its own.

Fixing both does stop the wipe. But combat then never resolves at all: **400 ticks of
FIGHTING, zero casualties, both sides at full strength and morale 100**, with the pair
locked at a 28.30 wu centre gap. That is the load-bearing part: the regiment formula is
currently the only thing producing melee casualties on first contact, so removing it
without replacing it stops the fight rather than fixing it.

**The reason the per-soldier path then lands no wounds is NOT yet established -- do not
assume it is a reach shortfall.** Check the real numbers before theorising. Cavalry's
`attack_range` is **30.0 wu**, not the `@export` default of 26.0 that `Unit.gd` declares:
`Battle.gd` overwrites it per loadout (`u.attack_range = weapon_type.reach_m *
WORLD_UNITS_PER_METER`), and the Spatha's `reach_m` is 1.5 m at 20 wu/m.
`soldier_reach()` just returns `attack_range`, so per-soldier reach is 30.0 wu too, and
the regiment gate is `attack_range + RADIUS + enemy.RADIUS` = 30 + 18 + 18 = **66 wu**
(`RADIUS` is `0.9 * WU_PER_M` = 18). At a 28.30 wu separation the men are therefore
INSIDE reach, not outside it -- so "they cannot quite touch" does not explain the stall,
and whatever does is still open. (An earlier draft of this entry asserted exactly that
wrong explanation off the unused 26.0 default; caught by fact-checking the constants
rather than by any test.)

Either way the entanglement stands, and it is the deferred "retire the regiment circle"
work (#296), not an independent bug. Note #296 is **not** blocked on #783 any more --
that was the `SoldierBodies.couple()` averaging-dilution bug, fixed and closed by #784
on 2026-07-12. #296's own thread records the current blocker as a residual ~1-2 px
overshoot transient at first contact, which is still unfiled, and explicitly advises
against reusing #783's number for it.

- **Do:** sequence per-soldier casualties AFTER per-soldier engagement, and measure the
  post-fix battle far enough forward (hundreds of ticks) to prove casualties still accrue.
- **Don't:** remove or bypass the regiment casualty formula while the engagement gate is
  still regiment-level -- the fight silently stops instead of resolving.

**Instrument after the FIRST zero-effect result, not the third.** This file already says
a before/after showing no difference means the fix's path is not the one being exercised.
Two successive fixes here produced byte-identical output before the gate was instrumented;
a single `print()` of the gate's own operands then settled it in one run, showing
`u.eng=true e.eng=false e.inContact=false` -- the attacker half fixed, the defender half
not. A temporary print at the branch you believe you changed is cheaper than another
reasoning pass.

(`Lacaedemon/sparta` #1151, draft PR #1187, 2026-07-30. Reproduced with seed `40002`,
two 10-soldier Cavalry regiments: tick 94 gap 68.29 wu matching the issue's own figure,
one unit gone at tick 96 while the survivor kept full strength, full HP and morale 100.)


## `dump-state.sh` includes routers, and merges the script's own `state` ticks

Two things worth knowing before reading a state dump as evidence:

- **A unit missing from a snapshot really has left play.** `DemoState.build_snapshot`
  walks `COMBAT_GROUPS`, which covers `routers` as well as `units` -- a routing unit still
  appears, distinguished by `state: "ROUTING"`. So an absent uid means `_remove_from_play()`
  (death or merge), not a group change. Do not spend a round wondering whether the dump
  simply does not show routers.
- **The tick list is the UNION of the CLI argument and the input script's own `state`
  array.** Passing `96,100` to a script that declares `"state": [80, 88, 92, ...]` dumps
  all of them. Handy, but it means the dumped set can be wider than you asked for, and a
  run can hit its snapshot budget on ticks you did not request.

## Re-check a cited blocker's CURRENT state before writing it into durable prose

An issue number cited as "blocked on #N" is a claim with an expiry date, and nothing
warns you when it lapses. Copying such a citation from an existing doc inherits its
staleness silently, and the copy then reads as freshly verified.

A memory entry asserted `#296` was "blocked on #783". `#783` had been CLOSED/COMPLETED
for 18 days, fixed by `#784` -- and `#296`'s own thread recorded a different, still-
unfiled blocker (a residual ~1-2 px first-contact overshoot), explicitly advising against
reusing `#783`'s number for it. The phrasing came from
`docs/individual-collision-design.md`, which carried that stale phrasing in five of its
eight `#783` mentions (#1189).

The failure is worse than a dangling reference: a future reader who checks `#783` and
finds it closed has two plausible readings, and both are wrong -- "this is fixed now" or
"this whole entry is stale, ignore it". The genuinely useful state (still blocked, by
something narrower) survives only in a comment thread.

- **Do:** run `gh issue view <N> --json state,stateReason` on every issue cited as a
  blocker, and skim the blocked issue's own recent comments for what it currently says is
  blocking it, before the citation goes into a memory file, design doc, or code comment.
- **Do:** when a cited issue turns out closed, say so explicitly in the prose ("#783 was
  fixed by #784; the live blocker is X") rather than just swapping the number, so the next
  reader is not left re-deriving why a closed issue was mentioned.
- **Don't:** carry a "blocked on #N" phrase over from another file on the assumption that
  whoever wrote it checked -- inheriting it is exactly how it spreads.
- **Do:** when FIXING stale citations, classify every occurrence before changing any of
  them. Some are legitimate history ("#783 documented X", "#784 fixed it") and are exactly
  what tells a later reader why a closed issue is mentioned at all.
- **Don't:** blanket find-and-replace the stale issue number. That destroys the accurate
  mentions along with the wrong ones, and the accurate ones are the more useful half.

**Expect PARTIAL refresh, not uniform staleness.** When an issue closes, whoever updates
the doc tends to fix the section they were reading and miss the summary. The result is a
file that contradicts itself: `docs/individual-collision-design.md` simultaneously said
the work "stays blocked on #783" (the header summary, and the phase-5 "Enemy collision"
bullet) and that "#783 closed via #784 ... but still needs its own residual-transient fix"
(the level-of-detail section's authority-slices paragraph, the doc's only use of that
phrase).
It reads as authoritative in whichever section you happen to open, so grep the whole file
and reconcile the occurrences against each other -- do not assume the first one you find
represents the document's position.

(`Lacaedemon/sparta` PR #1188, 2026-07-30: caught by the automated reviewer, not by
drafting. Fixed one file over in #1191/#1189, where the count was ALSO wrong at first --
reported as five occurrences because a `grep | head -5` truncation was read as the total;
there were eight, of which five were stale and three were already accurate.)


## A script-inserted markdown block needs an EXPLICIT blank line, not just a newline

Inserting a block into a markdown file programmatically (a `python` splice, a `sed`
insertion, an anchor `replace`) terminates the last line but does not create a paragraph
break. Under CommonMark/GFM lazy continuation, a non-indented paragraph that directly
follows a list item's text with no blank line is folded INTO that list item rather than
rendered as its own top-level paragraph.

Building a bullet as `nl.join([...lines..., ''])` looks like it ends with a blank line; it
does not. `join` only puts the separator BETWEEN elements, so a trailing `''` merely ends
the final line. The result splices straight onto whatever followed the anchor.

Nothing in this repo's checks catches it: `tools/check.sh chars` scans characters, the
GDScript lint ignores markdown, and there is no conflict marker to point at -- the damage
is invisible in the raw text and shows up only in the rendered output. It was caught by
review reading the rendered semantics.

- **Do:** after any scripted insertion into markdown, print the seam (`sed -n 'A,Bp' file`)
  and confirm a blank line separates the block from what FOLLOWS it -- that is the half
  that fixes the swallowed paragraph.
- **Do:** add one BEFORE it too, unless the insertion is a new item continuing an existing
  TIGHT list. Per CommonMark, tightness is a property of the whole list: one blank line
  between any two items makes every sibling loose and `<p>`-wrapped, so a leading blank
  line silently reformats bullets the diff never touched.
- **Don't:** trust a trailing empty element in a `join` to produce a blank line.

(`Lacaedemon/sparta` PR #1188, 2026-07-30: the inserted bullet swallowed the closing
paragraph of the whole "no top-down X" list, which applies to the list rather than to any
one bullet.)

## Calibrate a threshold guard against a deliberately-regressed build, not just healthy seeds

A live-battle guard picks a threshold from measurements, and the measurements almost always
come from the healthy build alone -- "main sits at ~20 degrees, so gate at 28". That says
nothing about whether the metric MOVES when the fix is removed, and a metric that does not
move is a pass path indistinguishable from a failure path.

`test_residual_melee_swirl_battle.gd` measured each regiment's facing rotation at tick 700
of a matched 100v100 Infantry grind, gated at 28 degrees on one seed. Re-measuring across
six seeds showed clean main spanning 17.8-58.0 degrees (it exceeded its own gate at two of
them, and was outright red on Linux while green on Windows). The decisive measurement,
though, was a deliberately regressed build -- the canonical-slot mapping disabled in both
`SoldierBodies.step()` and `couple()`, behind a temporary `OS.has_environment` hook -- which
came out WORSE at three seeds and BETTER at three. The gated quantity carried no signal
about the fix at all, on any seed.

The same scenario measured in its OPENING window (300 ticks) separates cleanly: healthy
holds a 2.84-3.44 degree band across eight seeds while the regressed build ranges 1.94 to
14.45 (means 2.98 vs 6.52). Two regressed seeds still land under the healthy band, so the
gate has to be the SEED MEAN with a looser per-seed backstop, not a per-seed ceiling.

- **Do:** before trusting a threshold, break the fix behind a temporary env hook and re-run
  the same measurement. Ratio of regressed to healthy IS the guard's discriminating power;
  if it is near 1, the threshold is decoration whatever its value.
- **Do:** prefer the window where the two builds separate. Long chaotic battles diverge
  between platforms (this file already documents that for demo transcripts) and fan out
  seed to seed, so a late absolute bound is unportable on top of being uninformative.
- **Do:** assert the window is not vacuous -- here, that casualties actually occurred, since
  casualty-driven array compaction is what arms the defect.
- **Don't:** quietly widen a threshold to make a red guard green. Widening is only honest
  once you know the metric moves; otherwise it converts a wrong answer into no answer.

## `.gemini/` holds TWO configs for two different consumers -- and reviews are currently paused there

`.gemini/config.json` is the **Antigravity/Gemini CLI workspace** config (its `skills`/`memories`
path lists, written by ai-config's `bootstrap.sh`). `.gemini/config.yaml` is the **Gemini Code
Assist GitHub App** config -- a different schema read by a different consumer. Editing one does
nothing to the other, and the names are close enough to conflate at a glance.

As of PR #1214 (2026-08-06) the GitHub App's automated review is **off**: `code_review.disable:
true`, quota exhausted. A quota-exhausted reviewer posts nothing or a "could not review" stub,
which this file already documents as easy to misread as an approval (the Copilot quota case, the
review self-skip case) -- so the pause is deliberate and documented rather than a silent gap.
Claude's own `claude-code-review.yml` and Copilot review are untouched and still gate every PR.

Worth knowing before hunting for a lever that isn't there: sparta has **no** Actions-based
Antigravity reviewer (nothing under `.github/workflows/` references one) and no Gemini/Antigravity
bot has ever posted a review comment or check run on a recent PR. So `.gemini/config.yaml` is the
only in-repo switch; a reviewer driven from the Antigravity dashboard or IDE is toggled there, not
here. `GEMINI.md` carries the same note, since that is the file a Gemini/Antigravity session
actually reads.

## A "how to restore this" note must not pin a copy of an upstream product's defaults

When disabling a third-party feature by overriding its config, the natural way to document the
reversal is to write down what the defaults were, so a future reader can put them back. That is
exactly the wrong shape: the pinned copy is a second source of truth for a value you do not own,
it cannot be verified from inside the repo, and it rots silently when upstream changes it.

The failure is not hypothetical -- it happened in the same commit that introduced the note. The
reversal comment claimed `pull_request_opened` defaults of `help: false, summary: true,
code_review: true`; the real default for `summary` is `false`. Anyone following it to "restore the
defaults" would have left PR-open summaries on. Review caught it (`claude[bot]`, PR #1214), and the
web docs confirmed it independently.

Correcting the value would have left the mechanism intact. The fix that removes the failure mode is
to say **delete the overriding block** on re-enable, so whatever the product default is at that
time applies, with today's values quoted as context rather than as instructions.

- **Do:** phrase a reversal as "delete the override" whenever the pre-override behaviour is an
  upstream default rather than something this repo chose.
- **Do:** verify a documented third-party default against that product's own docs before writing
  it down at all -- and prefer not writing it down.
- **Don't:** treat a reviewer's `suggestion` block as the whole fix. Here the suggestion corrected
  the wrong value, which was right as far as it went; the better change was structural, and taking
  the suggestion verbatim would have re-armed the same trap for the next drift.
- **Don't:** forget the PR description carries the same claim. Fixing the files and leaving the
  description asserting the old values just moves the stale copy somewhere a reader still finds it.

