# CLAUDE.md — AI working instructions for Sparta

Orientation and standing policies for any AI session working in this repo.
Sparta is a **Godot 4.7** (GDScript, Standard build — not .NET/C#) prototype
fusing dynastic grand strategy with real-time tactical battles. See
`README.md` for layout and `PLAN.md` for project vision, roadmap, architecture,
and verification steps — read `PLAN.md` first.

## Cross-repo AI configuration (`d-morrison/ai-config`)

This repo pulls in [`d-morrison/ai-config`](https://github.com/d-morrison/ai-config)
for portable skills and memories via the **Plugin Marketplace**.

`.claude/settings.json` registers the `d-morrison` marketplace and enables the
`ai-config` plugin, so Claude Code installs it at session start — skills are
available as `/ai-config:<name>` (e.g. `/ai-config:ardi`, `/ai-config:remember`).

**Local / after cloning:** the submodule is already registered in `.gitmodules`;
initialize it with:
```bash
git submodule update --init
```
Memories live in `.ai-config/memories/` (e.g. `@.ai-config/memories/preferences.md`).
Skills live in `.ai-config/skills/`.

## Project memories

Sparta-specific working notes and gotchas, imported so they load with this file:

@.claude/memories/sparta.md
@.claude/memories/sparta-demos.md

## Project at a glance
- Godot **4.7.x Standard** (GDScript, not C#/.NET). 2D top-down tactical battle.
- Main scene: `scenes/Battle.tscn`. Core scripts live in `scripts/`.
- Issues are tracked on this repo with `P0`–`P3` labels; `PLAN.md` mirrors the roadmap.

## Verify before you push
Run `tools/check.sh` to reproduce CI's gating checks locally (Godot import
validation + GUT unit suite + the docs char-check; `tools/check.sh all` adds the
lychee link-check). It vendors GUT on demand and needs only a Godot 4.7 binary on
`PATH` (or `GODOT_BIN`). See `tools/README.md`. Prefer it over invoking the
individual checks by hand so local and CI results stay in sync.

When the diff touches `scripts/`, also run `patch_coverage` before pushing —
a local approximation of the `codecov/patch` CI check, verified to match
Codecov's own numbers. Catching a shortfall locally saves a ~15–20 min CI
round trip; see "Checking patch coverage before you push" in
`tools/README.md`. **Add it to the same `tools/check.sh` invocation as the
other checks** (e.g. `tools/check.sh validate test chars comments units
patch_coverage`), not a separate command afterward — `patch_coverage`
already re-runs the full GUT suite via `coverage`, and `check.sh` dedupes
that against a same-invocation `test` automatically; a second, separate
`tools/check.sh patch_coverage` call pays for the whole suite again since
that dedup state doesn't survive across process invocations.

## Gameplay demos in PRs
When your change is **user-visible** — it affects how the game looks or plays
(`scenes/`, `scripts/`, `assets/`, `project.godot`) — help reviewers *see* it:
commit a **`demos/demo.json`** so CI records a short clip and inserts it into the
PR **description** (not a comment — the description stays visible at the top of
the PR page no matter how long the review thread grows).

- **Author demos as a scripted-input recording — not a hand-authored replay.** Write a
  deterministic input script (`demos/inputs/*.json`: a list of mouse clicks/drags and
  keystrokes stamped with the tick they fire on) and point `demos/demo.json` at it with
  the `input` field. The recorder drives a live battle through the *real* controls, so the
  clip exercises the actual code and the script stays editable as text. See the
  **Scripted-input demos** section of `demos/README.md`.
- The older `replay` field (play-and-save, or hand-authored scenario JSON) still works and
  is fine for a quick reuse of `demos/showcase.json`, but prefer `input` for anything that
  shows a specific interaction. Always write a `caption` describing what changed.
- See `demos/README.md` for the full contract and `demos/demo.example.json` for a
  template.
- If you skip this, CI still posts a *generic* build demo, but it won't show your
  specific change — so add a tailored manifest whenever the change is worth seeing.
- If your change genuinely **can't** be shown by a recorded battle (a paused-overlay
  interaction, an editor-only tool, a non-visual refactor), don't let CI post an
  unrelated generic clip: commit a `demos/demo.json` with `"skip": true` and a
  `"reason"`. CI then inserts a short note explaining the absence into the same
  description section instead (`demos/demo.skip.example.json` is a template).
- **Keep each demo simple and focused on one thing — use multiple demos when a PR
  touches multiple features, rather than one clip trying to show everything.** A
  clip that chains an unrelated setup phase (spawning, an AI unit's first move
  order, a formation change) onto the actual feature under review makes the
  reviewer wade through noise to find the point — or worse, mistakes an unrelated
  transient (e.g. the spawn-facing churn tracked in #631) for a bug in the change
  being reviewed. CI's demo-video workflow only auto-posts **one** clip per PR
  (`demos/demo.*.json` — if several exist, it warns and picks the first
  alphabetically), so when a PR genuinely has multiple features worth showing
  separately: pick the most complete/representative one as the primary
  `demos/demo.json`, and record any others as supplementary GIFs committed under
  `demos/shots/` and embedded directly in the PR description (same raw-URL/commit-SHA
  pattern as the static-image case below, but animated). (Learned on PR #615: the
  original single clip conflated a pre-existing spawn/facing-flip transient with
  the actual formation-change and charge-bracing mechanics being reviewed, reading
  as "physics is broken" until traced with a state dump.)
- **Check every new demo against the standard defect checklist before calling it
  verified.** Run the "Standard demo defect checklist" in
  `.claude/skills/verify-via-state-dump/SKILL.md` (blobbing, pulsing,
  flank-swapping, rank-swapping, facing whipsaw/rotation/reshape surge) against
  the demo's state dump — a rendered clip that looks fine can still hide one of
  these, so this is a standing check, not something to run only when a clip
  looks off.

### Static features: images in the PR description
For changes a still shows better than motion — new **interfaces/menus/HUD**, **new
or improved art**, layout/visual polish — also embed informative **image(s) in the
PR description itself** (in addition to the CI clip when motion matters). A labelled
screenshot in the body lets a reviewer judge the change at a glance without opening
media.

- Capture a PNG, commit it under `demos/shots/` on your PR branch, and embed it in
  the description by raw URL with a caption — referencing the **commit SHA** so the
  image keeps rendering after the branch is deleted on merge.
- See `demos/README.md` for how to produce the PNG (pull a frame from the demo
  recording, or screenshot a scene) and the full image contract.
- This is separate from the `demos/demo.json` video manifest: images go in the PR
  **body** (you post them by hand), while CI inserts the gameplay clip into the same
  body, in its own marked section (not a comment). For a static UI a recorded battle
  can't film, `skip` the clip (above) and rely on the
  image.

## Website updates in user-facing PRs

When a PR changes **how the game looks or plays** — mechanics, controls, UI,
balance, or any player-visible behaviour — include corresponding updates to the
`website/` docs site so the documentation stays in sync.

**When the rule applies:** any PR that touches `scenes/`, `scripts/`, `assets/`,
or `project.godot` in a way a player would notice. Pure refactors, internal
architecture, and CI changes are exempt.

**What to update:**

- `website/how-to-play.qmd` — step-by-step guide for new players. Add a step,
  update a control description, or note a new interaction.
- `website/tactics.qmd` — tactical guidance. Add a section when a new mechanic
  creates strategic decisions (terrain types, order delay, unit interactions, etc.).
- Other pages (`website/index.qmd`, `website/roadmap.qmd`) when the change is
  milestone-level.
- `website/tools/demo-catalog.sh` — the `DEMOS` list controls which website
  video clips get recorded at deploy time (via `record-demos.sh`) and which
  clips the per-PR state-transcript diff sweeps. When your PR adds a mechanic or
  visual that isn't visible in any existing scenario, append a row to `DEMOS`
  and a matching `<video>` embed on the page that covers that mechanic (follow
  the pattern in `website/how-to-play.qmd` or `website/index.qmd`).
  Each row has six pipe-separated fields: `"name|source|fps|max_frames|width|type"`.
  - **`type=replay`** (default): plays a hand-authored or recorded replay file
    (`demos/*.json`) via `DemoRunner.tscn`. Record a new replay by playing the
    battle and copying it from `user://replays/` into `demos/`.
  - **`type=input`**: drives the game from a scripted-input file
    (`demos/inputs/*.json`) via `DemoInputRecorder.tscn` — preferred for
    mechanics that need specific player gestures (a key toggle, a multi-unit
    drag). Reuse the file you wrote for `demos/demo.json`.
  See `website/README.md` for the full pipeline.

  **`demos/demo.json` conflict:** every PR updates this file to point to its
  own demo clip. When you merge `main` after another PR also changed it, you
  get a conflict. Keep YOUR version (it describes the change being merged).

**Figures and tables get labels + captions, via div syntax.** Every figure and
table on the site — images, markdown tables, and the raw-HTML `<video>` embeds —
gets a cross-referenceable label and a caption using Quarto
[div syntax](https://quarto.org/docs/authoring/figures.html#figure-divs): wrap it
in a fenced `::: {#fig-slug .demo}` / `::: {#tbl-slug}` div with the caption as
the last line before the closing `:::`. Keep a video's ` ```{=html} ` fence (just
the `<video>` element — no `<figure>`/`<figcaption>` HTML) inside the div; don't
use chunk-option syntax (`#| label:` / `#| fig-cap:`) for the cross-reference id.

**Where to look for site layout:** `website/README.md` describes the page
structure, build instructions, and how demo clips are recorded. Each `.qmd` page
links back to its source of truth in the repo root.

Keep website changes on the **same PR branch** as the code change — don't split
them into a follow-up PR, since reviewers need to see both together.

**Re-check website sync at each review round and at the end of every work
session — not just when first authoring the PR.** Before declaring a round done
or reporting a PR clean, audit the live `website/` content against the current
state of the game and confirm nothing has drifted, including:

- **Prose** — does any page describe behaviour the PR (or an earlier merged PR
  that never updated the site) has since changed?
- **Demo videos** — the `<video>` embeds (`website/media/*.mp4`) are recorded
  fresh at deploy time from the fixed replay scenarios in
  `website/tools/record-demos.sh`. That means they track *code* changes
  automatically (new art, HUD tweaks, balance), but only for features that
  appear in those scenarios **and** at the scenario's default camera position.
  Features that only appear at a non-default pan or zoom won't be captured even
  if a scenario covers them. A new mechanic that requires specific orders, a
  new scenario, or a camera move won't show up unless you added an entry to
  `DEMOS` (and a matching `<video>` embed) on this PR. If you didn't, and the
  feature is worth showing, file a follow-up issue.
- **Screenshots / images** — any committed image embedded in a page must still
  match what the game looks like now; a visual change can make an existing
  screenshot stale even when no prose changed. Recapture it on the PR branch.

This audit covers drift from **previously merged PRs** too, not only the one in
hand — if you spot a page that an earlier change left stale, fix it on the
current PR when it's in scope, or file a follow-up issue otherwise.

## Code conventions

### Parameters are caller-configurable; only real physical constants are fixed
Any parameter value a caller could reasonably want to vary — sizes, counts,
layouts, spawn geometry, timings, gameplay thresholds — enters through a
function parameter, a constructor/instance field, or a data file, with
today's value as the default. Never a bare literal buried in the
implementation: the battlefield size was hard-coded for months and changing
it forced a 19-clip demo sweep that per-battle map data would have avoided.
The exemptions are empirically known physical constants and unit conversions
(the units convention's territory), true mathematical constants, and solver
epsilons/convergence tolerances (see the units convention's "deliberately
NOT metric" list — those aren't gameplay parameters). A const remains the
right home for the DEFAULT value; the instance/parameter is what the battle
actually runs on (`Battle.field`/`terrain`/`spawn_line_ys` vs the `FIELD`/
`TERRAIN`/`SPAWN_LINE_YS` consts is the worked example). In review, a new
hard-coded tunable in a diff is a standard finding, the same weight as the
units-convention checks. The migration audit of pre-existing hard-coded
tunables is tracked in the issue tracker rather than done wholesale.

### Comments: no issue-number references
Don't cite issue numbers (`#123`) in code comments. The explanation itself
should stand on its own; a reader shouldn't need to open a tracker to understand
the code, and the reference rots as issues close and renumber. Issue numbers
belong in commit messages, PR descriptions, and `TODO`/`FIXME` comments (where a
`TODO(#123):` link to outstanding work is useful) — not in ordinary explanatory
comments or docstrings.

### Units: author in metres, store in world units, display in metric
See `docs/units-convention.md` for the full rules; `tools/check.sh units`
lints each diff's added lines. In short: a physically-derived length/speed
constant is written as `<metres> * WorldScaleRef.WU_PER_M` (parse-time-folded,
bit-exact-pinned by a test; `WorldScaleRef` is the script's own
`preload("res://scripts/WorldScale.gd")` alias — declare it with the other
preloads), runtime state stays world units end to end (no
conversions in hot loops), and any user-facing length/distance/speed renders
through `DistanceLegend`'s wu→metric helpers — a raw world-unit number is
never shown to the player. Deliberately unit-tuned knobs and solver epsilons
keep their wu literal, marked `# tuned in wu`. In review, treat as standard
findings: a new metric-looking bare literal, a runtime `WU_PER_M`
multiplication outside the boundary files, or a player-visible number not
routed through `DistanceLegend`.

### GDScript / Godot 4 quirks

- **`about_to_popup` fires before the layout pass.** `popup.size` is `(0, 0)` on
  the first call. Wrap any position assignment in `call_deferred()` so it runs
  after Godot has sized the popup.

- **`PopupMenu.set_item_metadata` takes an *index*, not an id.** Convert with
  `popup.get_item_index(id)`. Using the raw id silently sets the wrong item's
  metadata when ids and indexes differ.

- **`PopupMenu` auto-toggles a check-item's visual state BEFORE `id_pressed`
  fires.** If your handler early-returns without applying the change (e.g. the
  last enabled mode in a cycle can't be unchecked), the checkbox still shows
  the toggled-off visual. Call your sync-toggles helper (e.g.
  `_sync_setting_toggles()`) before the early-return to restore the correct
  visual state.

- **`set_deferred()` does not parse colon sub-paths the way `set_indexed()`
  does.** `set_deferred("position:y", ...)` is a silent no-op — `Object::set()`
  doesn't understand the colon syntax, only `set_indexed()` (NodePath-based)
  does. Defer the whole property instead:
  `set_deferred("position", Vector2(x, new_y))`.

- **Disconnect `Settings.changed` in `_exit_tree()`.** Connections made in
  `_ready()` persist after `reload_current_scene()` and create dangling callbacks.
  Use a named method (not a lambda) so `Signal.disconnect(callable)` can find it.

- **GDScript can't infer type from an untyped array access.** `var x := arr[i]`
  fails with a parse error when `arr` has no type annotation. Use an explicit type:
  `var x: MyType = arr[i]`.

- **A local `var name` shadows the inherited `Node.name` property.** Every
  `Node` already has `name` (`get_name()`/`set_name()`), so a local `var name`
  inside a `Node`-derived script trips a GDScript shadow warning. Qualify it —
  e.g. `mode_name`, `display_name`, `name_label` — so the local doesn't shadow
  the inherited property. The same applies to other inherited names
  (`position`, `owner`, `scale`).

- **Godot generates `.import` sidecar files — don't add new ones to git.**
  `.gitignore` already has `*.import`. Several legacy ones in `assets/sfx/` and
  `demos/shots/` are still committed and tracked; don't add new `.import` files
  without intent.

- **`.gd.uid` sidecars are tracked — commit one with every new script.** Unlike
  `.import`, `.gd.uid` files are checked in (see the `test/unit/*.gd.uid` next to
  each test). When you add a new `.gd`, `git add` its generated `.gd.uid` too;
  leaving it out makes the file show as perpetually-untracked (Godot regenerates
  it on every import) and churns the UID. Run `godot --headless --import` first
  to generate it.

- **A new `class_name` isn't visible to other scripts until the project
  re-imports.** Add a `class_name Foo` script and a test that references `Foo`
  fails to parse with `Identifier "Foo" not declared in the current scope` until
  you run `godot --headless --import` once (it registers the global class). Do
  the import before running the GUT suite on any change that adds a `class_name`.

- **The soldier body arrays (`_sim_soldier_pos`, etc.) are PARENT-LOCAL, not
  world-space.** They're built from `unit.position` (local) via
  `soldier_world_slots`, so any new consumer that compares a unit/regiment position
  against them must use `.position`, not `.global_position` — the two only coincide
  while the Battle scene sits at the world origin with an identity transform, so a
  `global_position` mix-up is a latent bug that stays dormant until that changes.
  `flank_multiplier` and all the `SoldierMelee` geometry use `.position`; match them.

- **GUT's `assert_almost_eq` does not support `Vector2` operands — it silently
  passes regardless of the actual difference.** The `diff > margin` check reduces
  to `Vector2 > float`, which GDScript always evaluates as `false`. For an *exact*
  Vector2 comparison use `assert_eq`; for approximate component checks, split into
  `assert_almost_eq(v.x, …)` and `assert_almost_eq(v.y, …)`.

- **When testing a normalized Vector2, always assert both `x` and `y`.** Checking
  only one component misses bugs where the vector is `(1.0, epsilon)` instead of
  `(1.0, 0.0)`. Always pair the two asserts.

- **Movie Maker mode: drop `--headless`, use `xvfb-run` alone.** Running
  `godot --headless --write-movie` crashes with a null-texture error (dummy
  renderer). Use `xvfb-run -a godot --rendering-driver opengl3 --write-movie`
  instead — Godot's default Vulkan renderer doesn't work under Xvfb's software
  framebuffer, so `--rendering-driver opengl3` is required.
  Pass the input script path via the `SPARTA_DEMO_INPUT` env var — CLI `--`
  args are not forwarded to `DemoInputRecorder`.

- **`push_error()` does not set a non-zero exit code.** A `--headless` Godot run
  (or a GUT run) that calls `push_error(...)` still exits `0`, so a CI step or
  script that only checks the exit code passes even when the work silently
  failed — e.g. a report file was never written. When a headless step is meant to
  produce an artifact, verify the artifact exists (and is non-empty) rather than
  trusting the exit code. The coverage job and `tools/check.sh coverage` guard
  `coverage/lcov.info` this way.

## Code review handling policy
When addressing review feedback (human or automated) on a PR, triage each finding:

1. **In scope + confident + small** → fix it on the PR branch, commit, push.
2. **Ambiguous or architecturally significant** → ask the user before acting.
3. **Out of scope for the current PR** (forward-looking polish, speculative
   future-proofing, preventative robustness with no current bug) → do **not**
   expand the PR to absorb it. Instead:
   - Create a GitHub issue to track it (or, if an existing issue already covers
     it, reuse that issue), and
   - Reply to the review with a link to the tracking issue so the reviewer
     knows where the work landed.
4. **Duplicate / no action needed** → skip silently.

A PR's scope is defined by its title/description. Keep the diff focused on that;
push genuinely separate concerns to their own tracked issues rather than letting
review rounds grow the change set unboundedly.

### Findings that live in an upstream/external repo
When a review raises an issue that actually lives in an **upstream/external
repository** — a reusable workflow, a dependency, an action we call, etc. —
rather than only working around it here:

1. **File a follow-up issue in the upstream repo** describing the problem (link
   back to this repo's PR/review for context).
2. **Reply to the review comment with a link to that upstream issue**, so the
   reviewer can see it's tracked at the source.

Still apply any reasonable local mitigation, but do not let the upstream root
cause go unrecorded.

## Git / branch conventions
- Develop on the designated feature branch; never push to a different branch
  without explicit permission.
- Commit messages: clear and descriptive, present tense.

### Handling missing `send_later` (PR check-in scheduling)

In some sessions (especially those where the `claude-code-remote` MCP server is
not configured), the `send_later` tool is **not available**, so you cannot
schedule a delayed self check-in to re-poll a PR's CI/merge state. This is a
session/MCP-config condition, not specific to any one client. When you hit it,
do not just report it as a dead end — use whichever of these is available:

1. **`subscribe_pr_activity`** (if available) — it wakes the session on PR
   comments, CI completions, and reviews (the exact set depends on the
   deployment), which covers most babysitting needs.
   Two things a PR-activity subscription won't reliably hand you, so check them
   actively rather than waiting on a webhook. First, a CI run that goes green
   *and* needs you to act on it (e.g. auto-merge). Second, a **merge conflict
   appearing** — poll the PR's `mergeable_state` (via the GitHub API) to catch
   it. (A push does emit a `synchronize` webhook, but the subscription may not
   surface it, so don't rely on it.)

2. **`/loop` skill** (if available) — runs a prompt or slash command on an
   interval (e.g. `/loop 1h check PR #N CI and mergeability`). This is the
   practical replacement for `send_later`'s self-scheduling: periodic re-checks
   without the MCP tool.

3. **On-demand** — while the session is alive, the user can ping at any time and
   you re-check the PR state.

4. **Enable the MCP server** — `send_later` lives in the `claude-code-remote` MCP
   server. If you truly need it, it must be configured for the environment; that's
   a settings/MCP-config change, not something to flip on mid-session.

When both are available, **#1 + #2 together** replicate what `send_later` was for.
Never use Bash `sleep` to wait for external events.
