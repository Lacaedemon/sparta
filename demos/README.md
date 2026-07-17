# Gameplay demos in PRs

When a PR makes a **user-visible change** (anything affecting how the game looks
or plays), a short clip is inserted so reviewers can *see* the change, not just read
the diff.
[`.github/workflows/demo-video.yml`](../.github/workflows/demo-video.yml) plays a
replay back headlessly (Godot Movie Maker → ffmpeg) and upserts it into the PR
**description** as an inline GIF that **plays once** (it freezes on the final frame
instead of looping) — plus a link to an **MP4 with sound** (the GIF is silent; see
[Sound](#sound) below). It lives in the description (not a comment) so it stays
visible at the top of the PR page no matter how long the review thread grows; a
compact **state transcript** (when one dumps) still posts as its own comment — see
[CI posts the transcript automatically](#ci-posts-the-transcript-automatically). An
inline GIF is used rather than a poster-linked MP4 because GitHub's blob-view video
player doesn't work on the mobile site or app, while a GIF renders inline everywhere.

CI can't infer what a diff changed, so to make the clip *demonstrate your change*
you **declare what to show**: commit a small **manifest** pointing at a **replay**
that exercises it. If you don't, CI still posts a demo — the default
`showcase.json` battle, labelled as a generic build demo — but a tailored one is
far more useful, so prefer to add a manifest.

## The contract

Add a manifest on your PR branch, named **`demos/demo.<slug>.json`** — `<slug>`
is your issue or PR number (e.g. `demos/demo.371.json`). Each PR's manifest gets
its own unique filename, so two PRs in flight never conflict editing the same
file (the older shared `demos/demo.json` pointer still works as a fallback, but
a uniquely-named manifest is preferred for exactly this reason — see
[Resolution order](#resolution-order)):

```json
{
  "replay": "demos/showcase.json",
  "caption": "What this PR changes and what to watch for in the clip.",
  "fixed_fps": 30,
  "max_frames": 300,
  "fps": 12,
  "width": 640
}
```

| Field | Required | Meaning |
| --- | --- | --- |
| `input` | preferred | Repo-relative path to a **scripted-input** demo (`demos/inputs/*.json`) — **no `res://` prefix**. Recorded live through the real controls. The standard way to author a demo; see [Scripted-input demos](#scripted-input-demos). Wins over `replay` when both are present. |
| `replay` | alt | Repo-relative path to a saved replay JSON to play back — **no `res://` prefix**. The older path; prefer `input`. See [Getting a replay](#getting-a-replay-that-shows-your-change). |
| `caption` | recommended | Explains the change; shown above the GIF. |
| `fixed_fps` | no (30) | Sim/record framerate Movie Maker runs at. |
| `max_frames` | no (300) | Recording length in frames (`300 / fixed_fps` ≈ seconds). |
| `fps` | no (12) | Output GIF framerate. |
| `width` | no (640) | Output GIF width in px (height auto). |
| `skip` | no (false) | Set `true` when the change **can't** be shown by a recorded battle (a paused-overlay interaction, an editor-only tool, a non-visual refactor). CI then records nothing and posts a short note instead of an unrelated clip. See [No clip applies](#no-clip-applies). |
| `reason` | no | Used only with `skip` — the explanation shown in the note (falls back to `caption`). |

`demo.example.json` is a copy-paste starting point — copy it to
`demos/demo.<slug>.json` rather than `demos/demo.json`. Any **other** keys are
ignored by the workflow (its `jq` only reads the fields above), so a leading
`"_comment"` note — as used in `demo.example.json` itself — is safe to include.

### Resolution order

CI's "Resolve demo source" step picks the most specific manifest available:

1. A **per-PR manifest** (`demos/demo.*.json`, e.g. `demos/demo.371.json`) that
   was **added** in your PR's diff against the base branch. Preferred — see above.
2. The legacy shared `demos/demo.json`, if present. Still works, but every PR
   that uses it is editing the same file, so two such PRs in flight will conflict
   on merge (`demos/demo.json` is a perennial source of merge conflicts for
   exactly this reason — prefer the per-PR filename to avoid it).
3. The default `showcase.json` battle (generic, honestly labelled).

If your PR adds more than one `demos/demo.*.json` file, CI warns and picks the
first alphabetically — stick to one manifest per PR.

## Scripted-input demos

**The standard way to author a demo.** Instead of a recorded or hand-authored
replay, write a deterministic **input script** — a list of mouse clicks/drags and
keystrokes stamped with the physics tick they fire on. The recorder
(`tools/demo/DemoInputRecorder.gd`) drives a live battle by injecting those as real
`InputEvent`s through the same `SelectionManager` code a player's mouse drives, while
Movie Maker records. So the clip is produced by the actual controls (a demo doubles
as an input smoke test), and the script is editable text you can tune without replaying
the game.

Point your `demos/demo.<slug>.json` at it with the `input` field, and put the
script under `demos/inputs/`:

```json
{
  "seed": "12345",
  "camera": [ { "tick": 0, "x": 510.0, "y": 380.0, "zoom": 1.9 } ],
  "steps": [
    { "tick": 8,  "click": [500, 300] },
    { "tick": 24, "rmb_drag": { "from": [620, 460], "to": [385, 460] } }
  ]
}
```

- `seed` — the battle seed (string). Use `"12345"` for the documented standard 5v5
  layout (the unit table below); spawn **positions** are seed-independent, so clicks
  land regardless — the seed only fixes combat RNG for reproducibility.
- `camera` (optional) — a list of keyframes `{tick,x,y,zoom}` (world coordinates), sorted
  by tick. The recorder interpolates position and zoom linearly between them, so the clip
  pans and zooms over time; outside the track's range it holds the first / last frame. A
  single keyframe just statically frames the whole clip. Omit for the default whole-field
  camera. (`demos/inputs/camera-zoom.json` shows a multi-keyframe pan-and-zoom.)
- `steps` — each stamped with a `tick` (physics ticks, 60/s). Coordinates are world-space:
  - `click [x,y]` / `shift_click [x,y]` / `rmb_click [x,y]` — a press+release at a point.
  - `box { "from": [x,y], "to": [x,y] }` — a left-drag box-select.
  - `rmb_drag { "from": [x,y], "to": [x,y], "shift": false }` — a right-drag (move / form-up;
    `shift` toggles the form-up ordering variant). Drags animate over a few ticks so the
    live preview renders.
  - `key "Y"` — a gameplay hotkey press (formation cycle, order stance, etc.). Add
    `"ctrl": true` to chord it with Ctrl (e.g. `{"key": "H", "ctrl": true}` writes the
    Hold stance on the selection in place — see the stance-order gesture in
    `how-to-play.qmd`) or `"shift": true` to chord it with Shift (e.g.
    `{"key": "O", "shift": true}` jumps straight to the schiltron stance, sharing
    orbis's O key — see "Square: orbis and schiltron" in `how-to-play.qmd`).
- `drill` (optional bool, **default it to `true` unless the demo needs an enemy**) — solo/
  no-opponent rehearsal: only the player army (team 0) deploys and the battle never auto-ends
  on "no enemies", so a unit can rehearse a maneuver with no combat. Set `"drill": true` for
  any demo that isn't specifically about combat/enemy interaction (a clash, a rout, an
  engagement mechanic, morale under fire) — maneuver, formation, order-queue, HUD, and UI
  demos have no reason to spawn an enemy at all, and a nearby enemy AI can introduce
  engagement/proximity noise that has nothing to do with what the demo is showing (a reviewer
  cross-checking a caption against the state transcript then has to account for combat state
  that's irrelevant to the actual change). Only omit `drill` (or set it `false`) when the demo
  genuinely needs a live opponent.
- `doctrine` (optional string) — override team 1's battle-AI doctrine profile (a
  `DoctrineRegistry` id, e.g. `"aggressive"` or `"cautious"` — see `data/doctrines/*.json`
  and `docs/battle-ai-design.md`'s phase-3 section). Set before the battle spawns, like
  `drill`/`scenario` above. Omit to use `Battle.ai_doctrine`'s own default.
- `all_teams_control` (optional bool, default `false`) — debug/testing mode: the player
  commands every team's units directly (`SelectionManager`'s team checks are relaxed) and
  team 1's AI never runs, so a script can select and order BOTH sides of a real clash by
  hand instead of only team 0 against the AI. Unlike `drill`, both armies still spawn — set
  before the battle spawns, like `drill`/`scenario`/`doctrine` above. See
  `scripts/AllTeamsControl.gd` and `demos/inputs/all-teams-control.json`.
- `show_soldier_ids` (optional bool, **default `true`**) — session-only: enables the
  per-soldier-ID HUD overlay for the recording without touching a developer's saved
  settings. On by default so scripted-input recordings show this debugging/verification
  signal for reviewers; set `"show_soldier_ids": false` to opt a script back out. Note
  this alone isn't enough to render the overlay — it also requires the unit to be
  `selected` and the camera at detailed LOD (`Unit._draw`'s
  `if selected and Settings.show_soldier_ids and _detailed_lod` gate), so a demo that
  doesn't already select a unit and zoom in past `LOD_ZOOM_IN` won't show IDs
  regardless of this default.
- `show_position_anchor` (optional bool, default `false`) — session-only: draws a small dot
  at each unit's `position` (the regiment's own kinematic anchor, `SoldierBodies.couple()`)
  for the recording, without touching a developer's saved settings. Off by default; set
  `"show_position_anchor": true` for a demo specifically about how `position` tracks (or
  doesn't track) the block.
- `scenario` (optional) — **stage a custom matchup** instead of the default 5v5 lines, so a
  demo can show a *specific* fight the default battle won't produce on its own (a weak unit
  that routs, an enemy placed off a unit's flank, cavalry vs a single target). A list of unit
  specs; when present it replaces the default spawn entirely. Each spec:
  - `team` — `0` (player, deploys facing down by default) or `1` (enemy, facing up).
  - `type` — one of `"Spearmen"`, `"Infantry"`, `"Archers"`, `"Cavalry"` (uses that type's
    full stat block from the default loadout).
  - `x`, `y` — world-space spawn position.
  - `facing` (optional `[x, y]`) — an explicit heading; defaults to facing the enemy half.
  - `count` (optional) — soldier-count override (a smaller unit routs sooner; a bigger one
    holds longer).
  - `morale` (optional) — starting morale (default 100; set low to stage a quick rout).
  - `formation` (optional) — starting stance (`0` Normal, `1` Tight, `2` Loose,
    `3` Square, `4` Shield Wall, `5` Testudo). Square is the anti-cavalry ring; the two
    shielded stances plant and barely move but blunt missile fire (testudo from all
    sides, shield wall from the front).
  - `atomic_response_s` (optional) — seconds the unit holds between a drill command
    (wheel, about-face, quarter-turn, countermarch) and the men starting the evolution
    (default 0.2, `Unit.atomic_response_delay`). Lower stages an elite regiment's
    snappier drill; higher a raw levy's sluggish one.
  - `starting_state` (optional) — force the unit's initial `Unit.State` on spawn, for
    staging a state a normal battle can't otherwise reach: `3` (`ROUTING`) starts the
    unit already fleeing/recovering — routing is normally only reachable as a side
    effect of real combat casualties — and `4` (`DEAD`) sets it dead in place. This is
    the one scenario field that is **not strict** about a bad value: an unrecognized
    `starting_state` warns (`push_warning`) and leaves the unit at the default `IDLE`,
    rather than failing the recording outright. Pair `starting_state: 3` with a low
    `morale` override — a unit that starts ROUTING at the default morale (100) is
    already above the rally threshold and rallies in a single tick, showing no
    recovery at all. See `demos/inputs/morale-recovery.json` (morale `1.0`, so the
    climb back to the ~35 rally threshold is gradual and visible).

  Example — stage a lone, low-morale infantry unit against a strong cavalry force so it routs
  (then rallies, if the build has that): `demos/inputs/rout-rally.json`.
- `frames` (optional) — a list of physics ticks to save a viewport PNG at, for visual
  verification (see [Verifying a demo visually](#verifying-a-demo-visually-frame-capture)). The
  `SPARTA_DEMO_FRAMES` env var adds to this list, so a reviewer can capture frames from any demo
  without editing its script. Ignored during a normal movie recording (capture only runs when a
  frame is armed).
- `state` (optional) — a list of physics ticks to dump a machine-readable JSON game-state snapshot
  at, for AI verification (see [Verifying a demo by state](#verifying-a-demo-by-state-ai-verification)).
  The `SPARTA_DEMO_STATE` env var adds to this list, so a reviewer can dump state from any demo
  without editing its script. Ignored during a normal movie recording.

A malformed `camera`, `frames`, or `state` field (a non-array value, e.g. `"state": "8,60"`)
**degrades instead of failing** in the recorder, which warns and ignores the field. CI's
transcript tick parser degrades the same way, but only reads `frames`/`state` — a malformed
`camera` field doesn't affect it. `steps` and `scenario` stay strict — a typo there would
change what the demo simulates, so the recording fails loudly instead.

The standard 5v5 (`seed "12345"`) unit positions are in [Hand-authoring a scenario](#hand-authoring-a-scenario)
below — clicks target those world coordinates.

## Verifying a demo visually (frame capture)

A demo that *runs* clean isn't proof it *shows the right thing* — the camera can frame the
wrong spot, the intended unit can sit off-screen, an effect can fail to appear. To catch
that, render the demo to **PNG frames at chosen ticks** and look at them.

The scripted-input recorder (`tools/demo/DemoInputRecorder.gd`) captures frames when the
`SPARTA_DEMO_FRAMES` env var is **set** (to a comma-separated tick list like `10,60,120`). At
each listed physics tick it saves the drawn viewport to `SPARTA_DEMO_FRAME_DIR/frame_<tick>.png`
(a temp dir by default), then quits once the last frame is saved. A demo's input script can also
carry a `"frames": [10, 60, 120]` array; when the env var is set, the two lists are merged (an
empty env value falls back to the script's list). Capture is **env-gated**: with the env var
unset — the CI movie-recording path — it never arms, so a demo's own `frames` array never
truncates the recording and normal recording is unchanged.

**A real renderer is required.** `--headless` uses the dummy renderer and produces null/blank
textures, so capture must run **without `--headless`** using `--rendering-driver opengl3` (a
window may open locally — that's fine). The viewport texture is only valid after the frame is
drawn, so the recorder waits for `RenderingServer.frame_post_draw` before `save_png` — the
saved PNGs are real 1280×720 frames, not black.

### The wrapper

`tools/demo/capture-frames.sh` wraps it:

```sh
tools/demo/capture-frames.sh <input-script> <ticks> [out-dir]
```

Concrete command that works on **Windows** (Git Bash), from the repo root:

```sh
GODOT_BIN="C:\Users\you\Documents\apps\Godot_v4.7-stable_win64_console.exe" \
  tools/demo/capture-frames.sh demos/inputs/rout-rally.json 10,20,40 /tmp/frames
```

On Linux/CI, drop `GODOT_BIN` if `godot` is on `PATH`; the render still runs windowed
(`--rendering-driver opengl3`), so wrap it in `xvfb-run -a` on a headless box.

Or invoke Godot directly (no wrapper):

```sh
SPARTA_DEMO_INPUT="res://demos/inputs/wheel.json" \
  SPARTA_DEMO_FRAMES="10,80,150" \
  SPARTA_DEMO_FRAME_DIR="/tmp/frames" \
  "$GODOT_BIN" --rendering-driver opengl3 --path . res://tools/demo/DemoInputRecorder.tscn
```

Then `Read` each `/tmp/frames/frame_<tick>.png` and confirm the intended units/behaviour are
on-screen. The filenames are zero-padded (`frame_00010.png`) so a directory listing sorts in
tick order.

**Pick ticks the demo actually reaches.** A battle freezes its physics tick the moment it ends
(a rout resolves, one side is wiped), so a frame armed past that tick never fires. For a
staged rout (`rout-rally.json`) capture *early* ticks (the clash, then the break); for a
no-opponent `drill` demo (`wheel.json`, `quarter-turn.json`) the sim never auto-ends, so any
tick up to the script's length works. The recorder also quits after a wall-clock timeout, so
an over-long tick can't hang the run — it just won't produce that frame.

### Required demo self-check (do this before opening a PR)

**Every demo PR must render a couple of frames at key ticks and confirm the change is visible
before the PR is opened.** "It runs clean" is not enough, and "can't verify visually" is no
longer a valid skip — with scenario staging (a custom matchup) and frame capture, a demo can
always be staged *and seen*. Concretely, for the demo your PR adds or changes:

1. Render 2–3 frames at the ticks where the behaviour should be on-screen (the command above).
2. Open each PNG and confirm the intended units/effect are framed and doing the intended thing.
3. If a frame shows the wrong thing (off-camera, wrong unit, no effect), fix the script
   (camera keyframes, tick timing, scenario placement) and re-render until it's right.

Only after the frames confirm the behaviour is on-screen is the demo ready. If a change
genuinely can't be shown in a battle frame at all (a paused-overlay interaction, an editor-only
tool), use the `skip` manifest ([No clip applies](#no-clip-applies)) with an honest reason —
don't use the self-check's difficulty as the excuse.

## Verifying a demo by state (AI verification)

A rendered frame (above) proves the behaviour is *on-screen*, but reading it back means
**interpreting pixels** — is that unit routing? what's its morale? A **machine-readable state
dump** answers those precisely: at the ticks a demo cares about, it writes the authoritative
game state to JSON, so a reviewing agent (or a test) reads **exact values** and asserts on them
— "at tick 280, 'Infantry 1' is at morale 19, down to 8 soldiers, engaged" — instead of eyeballing
a GIF. It's the machine-readable companion to the [frame capture](#verifying-a-demo-visually-frame-capture)
above: same recorder, same tick-list plumbing, but it emits readable state rather than pixels.

The recorder (`tools/demo/DemoInputRecorder.gd`) dumps state when the `SPARTA_DEMO_STATE` env var
is **set** (to a comma-separated tick list like `8,60,140`). At each listed physics tick it writes
`SPARTA_DEMO_STATE_DIR/state_<tick>.json` (a temp dir by default), then quits once the last snapshot
is written. A demo's input script can also carry a `"state": [8, 60, 140]` array; when the env var is
set, the two lists are merged (an empty env value falls back to the script's list — the same
merge rule as `frames`). Dumping is **env-gated**: with the env var unset — the CI movie-recording
path — it never arms, so normal recording and the frame-capture path are both unchanged.

**Replay playback dumps state the same way.** A `SPARTA_DEMO_REPLAY` run
(`tools/demo/DemoRunner.tscn`) honors the same `SPARTA_DEMO_STATE` /
`SPARTA_DEMO_STATE_DIR` / `SPARTA_DEMO_STATE_FULL` env vars via
`tools/demo/DemoStateSink.gd` — a root-level node that survives the runner's scene swap
and writes the identical snapshot shape (both paths share `DemoState.build_snapshot`).
The one difference: a replay file carries no `"state"` array, so the tick list comes from
the env var alone. This is what lets the website demo-diff workflow transcript-sweep the
catalog's `type=replay` rows, not just the scripted-input ones.

Unlike frame capture, the dump reads **sim state, not the drawn frame**, so it runs under
`--headless` (no real renderer needed) — faster, and no window opens.

Each `state_<tick>.json` holds the battle tick and a record per unit — **including routing
units**. The dumper walks the `"units"` and `"routers"` groups together (a ROUTING unit has
left `"units"` but is still on the field and may rally — the same union the victory check
scans), so a mid-rout unit stays transcript-visible: its `state` reads `ROUTING` and its
recovering `morale` and fleeing `position` can be followed tick by tick. Records are sorted
by `uid`, so a unit keeps its row across the rout/rally group changes:

| Field | Meaning |
| --- | --- |
| `uid`, `name`, `team` | Stable unit id, display name, side (0 player / 1 enemy). |
| `position`, `facing` | World-space `[x, y]` pairs (rounded). |
| `position_m` | `position` mirrored in metres (`WorldScale.WU_PER_M`), so a reviewer reads real distances without dividing by the world scale by hand. |
| `morale` | Current morale (100 = fresh; a rout triggers at 0). |
| `state` | Readable `State` name — `IDLE` / `MOVING` / `FIGHTING` / `ROUTING` / `DEAD`. |
| `formation` | Readable formation — `NORMAL` / `TIGHT` / `LOOSE` / `SQUARE` / `SHIELD_WALL` / `TESTUDO` / `SCHILTRON`. |
| `frontage` | Current file count — the durable width a `FRONTAGE` order last wrote, or the type-derived default when none has. |
| `soldiers` | Living soldier count (drops as the unit takes casualties). |
| `current_speed` | Current movement speed (world units/s). |
| `current_speed_mps` | The same speed in m/s (folding in `Battle.SPEED_SCALE`, so it reads back as the loadout's declared figure). |
| `order_mode` | Readable order stance (`Normal`, `Hold`, `Attack flank`, …). |
| `rank_relief` | Whether the intra-unit rank-relief mode is on (rear ranks rotate forward to relieve their own fighting line; written by a stance order). |
| `current_order` | The head of the unit's orders queue — readable `Order.Type` name (`MOVE`, `ATTACK`, `RELIEF`, `WHEEL`, …), or `null` when idle. |
| `order_phase` | The current order's active phase (`NONE`, or `TURN` / `REFORM` / `MARCH` / `RETURN_TURN` / `WHEEL`), or `null` when idle. `REFORM` covers BOTH a phased rear-move/lateral-pivot's interstitial hold and an ordinary move/form-up's reform-before-move pause (`Settings.reform_before_move`, default on) — both hold on a REFORM leaf order and read identically here. `RETURN_TURN` is a lateral pivot's closing quarter-turn back to its original facing; `WHEEL` is a wheel-turn composite's flank-pivot phase, between its opening about-face and its march. |
| `order_guard` | The current order's pending terminal condition — readable `Order.Guard` name (`ENEMY_IN_RANGE`, `CONTACT_MADE`, `MORALE_BELOW`, `ALLY_EXHAUSTED`, `TICKS_ELAPSED`, `FLANKED`), or `null` when the order carries no guard (or there is no current order). |
| `queue_tail` | The not-yet-current queued orders behind `current_order`, as an array of `Order.Type` names in queue order — `[]` (not `null`) when nothing is queued. |
| `target_enemy_uid` | The uid this unit is attacking, or `null`. |
| `engaged` | Whether the regiment is in the engaged tier (front ranks in/just-out of melee). |
| `maneuver` | A single readable label for the in-progress drill/maneuver — `IDLE` / `MARCHING` / `FIGHTING` / `CONVERSIO` / `QUARTER_TURN` / `WHEELING` / `FILE_DOUBLE_DEEPEN` / `FILE_DOUBLE_WIDEN` / `NUDGE_SIDESTEP` / `NUDGE_BACKSTEP` / `NUDGE_FORWARD_STEP` / `CYCLE_CHARGE` / `COUNTERMARCH`. Consolidates `current_order`/`order_phase`/`order_mode` into one field, so e.g. a conversio and a centre-pivot (both otherwise `MOVE`/`TURN` vs `QUARTER_TURN`) are distinguishable directly. `FILE_DOUBLE_DEEPEN`/`WIDEN` only show on the exact tick the reshape order applied — the order itself retires the same tick. See `Unit.current_maneuver()`. |
| `countermarch_variant` | Which exelismos variant a `maneuver: "COUNTERMARCH"` is running — `MACEDONIAN` / `LACONIAN` / `CHORAL`, or `null` when the unit isn't countermarching (`maneuver` alone can't distinguish the three). See `Unit.countermarch_variant()`. |
| `tier` | The formation's **simulation tier** — `CLOSE` (full per-soldier arrays) or `FAR` (aggregate record, no individual bodies). See `docs/large-scale-simulation-design.md`. |
| `soldier_summary` | Per-soldier `{count, centroid:[x,y], bbox:[w,h], prone_count}` — a compact digest, **not** the full per-soldier arrays. **Close-tier units only.** |
| `soldier_summary_m` | The summary's `{centroid_m, bbox_m}` mirrored in metres, derived from the same positions so the two can never disagree. Close-tier only, like its wu sibling. |

A `tier: "FAR"` record carries **no per-soldier payload at all** — no `soldier_summary`, no
`soldiers_full` — because a far-tier formation has no individual bodies to derive them from.
The explicit `tier` field is what tells that apart from "per-soldier detail not requested"
(a close-tier dump without the full flag, which still gets the summary).

Set `SPARTA_DEMO_STATE_FULL=1` to also dump `soldiers_full` — the raw per-soldier arrays
(`pos`, `facing`, `slots`, `hp`, `prone`, `stamina`) — for deep debugging. Off by default (the
summary is what a reviewer needs; the full arrays are ~20x larger). `slots` is the unit's
canonical slot grid (`Unit.soldier_world_slots`) at the same tick — the *ordered* shape the
bodies chase — and a `motion_ref` dict rides alongside with the per-unit constants an offline
analyzer derives thresholds from (`formation_spacing`, the three gait speeds, `pivot_radius`,
`turn_rate`), so analysis reads the sim's own tuning rather than hardcoding a copy.

### Declared expectations (`expect`)

An input script can declare its own intent as data — an optional `expect` list of
`{"tick": N, "uid": U, "field": F, "value": V}` entries (tick may be a `[lo, hi]` range for
drift-tolerant claims: the expectation passes when ANY snapshot inside the range matches).
Fields are the compact per-unit record fields every dump carries (`state`, `current_order`,
`order_mode`, `formation`, `engaged`, `target_enemy_uid`, ...). On a dump run the recorder
automatically arms a state snapshot at every expect tick, so declaring an expectation is
enough to make the data it checks exist; the analyzer evaluates them offline:

```sh
"$GODOT_BIN" --headless --path . -s tools/demo/analyze_transcript.gd -- <dump-dir> \
    --expect demos/inputs/<name>.json
```

An expectation that cannot be checked (no snapshot in range, no such unit, no such field)
FAILS rather than skips — an uncheckable claim is an authoring error. This is how a demo
that stops demonstrating its own caption (a rebound hotkey arming the wrong stance, a rally
where a flee was staged) turns into a red exit code instead of an eyeball catch.

### Algorithmic defect scan

`tools/demo/DemoDefects.gd` turns a FULL dump into deterministic defect verdicts — the
machine-checkable core of the demo-review checklist (blob/compression, soldier overlap,
shape scramble via an ordered-vs-actual best-fit decomposition, facing whipsaw, sustained
super-physical speed). Run it headless over a dump directory:

```sh
"$GODOT_BIN" --headless --path . -s tools/demo/analyze_transcript.gd -- <dump-dir> [--json]
```

Exit `0` = clean, `1` = at least one defect (the verdict lines name the unit, metric, worst
value, and threshold), `2` = unusable input (e.g. the dump wasn't taken with
`SPARTA_DEMO_STATE_FULL=1`). Post-contact samples are exempt from the spacing/shape checks —
melee press legitimately compresses a block.

### The wrapper

`tools/demo/dump-state.sh` wraps it, mirroring `capture-frames.sh`:

```sh
tools/demo/dump-state.sh <input-script> <ticks> [out-dir]
```

Concrete command that works on **Windows** (Git Bash), from the repo root:

```sh
GODOT_BIN="C:\Users\you\Documents\apps\Godot_v4.7-stable_win64_console.exe" \
  tools/demo/dump-state.sh demos/inputs/rout-rally.json 8,60,140 /tmp/state
```

On Linux/CI, drop `GODOT_BIN` if `godot` is on `PATH`. No `xvfb-run` needed — the dump is headless.

Or invoke Godot directly (no wrapper):

```sh
SPARTA_DEMO_INPUT="res://demos/inputs/rout-rally.json" \
  SPARTA_DEMO_STATE="8,60,140" \
  SPARTA_DEMO_STATE_DIR="/tmp/state" \
  "$GODOT_BIN" --headless --path . res://tools/demo/DemoInputRecorder.tscn
```

Then `Read` each `/tmp/state/state_<tick>.json` and assert on the values. As with frame capture,
**pick ticks the demo actually reaches** — a battle freezes its physics tick when it ends, so a
tick armed past that never fires (the run quits on a wall-clock timeout, warning which snapshots
it managed to write).

### Worked example — the staged rout

`demos/inputs/rout-rally.json` stages a lone, low-morale (25) player infantry unit of 60 against
two 80-man cavalry that hit it head-on. Dumping at `8,60,140` (and on to `280`) shows the collapse
in exact numbers, no frame-reading required:

- **tick 8** — `Infantry 1`: `state MOVING`, `morale 25.3`, `soldiers 60`, `engaged false`; the two
  cavalry (`morale 100`, `soldiers 80`) closing, `target_enemy_uid 0` (both targeting the infantry).
- **tick 140** — `state FIGHTING`, `morale 25.4`, `soldiers 38`, `engaged true`; the weak unit is
  locked in melee and already down a third of its men while the cavalry stay near full.
- **tick 280** — `morale 19.1`, `soldiers 8`; the unit is nearly annihilated (it's ground down
  before morale reaches the rout threshold of 0).

A reviewer asserts on those values directly — the low morale, the falling `soldiers`, the
`engaged`/`FIGHTING` transition — rather than judging a routed-looking sprite from a GIF.

### CI posts the transcript automatically

You don't have to run the dump by hand for a reviewer to see the state — `demo-video.yml`
does it for every PR whose demo is a **scripted-input** recording (a manifest with an `input`
field). Alongside the GIF/MP4, CI runs the same headless dump for the same input script, at the
ticks the script already cares about (its `state` list, else its `frames` list, else a default
`8,60,140`), then posts two things:

- **A compact per-tick table in a PR comment** — a `🔬 Per-tick state transcript` heading with
  one row per unit per dumped tick (State / formation / order mode / morale / soldier count /
  centroid), and a link to the full JSON. It's a **comment**, not part of the description, because
  it's large technical detail most reviewers don't need at a glance; the description (where the
  GIF lives) links to it. Both a human reviewer and the `@claude` review bot read PR comments
  directly — the bot reviews the PR thread and diff, not the media branch, so this is what makes
  the transcript actually reach it.
- **A link to the full JSON** — `Full machine-readable state transcript (JSON)`, the complete
  per-tick snapshots (every field, including `soldier_summary`) published next to the GIF/MP4 on
  the `demo-media` branch for detail.

The `claude-code-review.yml` reviewer is told to prefer this transcript over the video clip when
verifying behaviour.

It's **best-effort**, like the MP4 encode: a dump failure never blocks the GIF or fails the job —
the demo just posts without a transcript. It applies only to scripted-input demos; a **replay**
or the generic **showcase** fallback records via `DemoRunner`, which has no state-dump path, so
those post the clip alone. A `"skip": true` manifest posts neither clip nor transcript.

The summary block is built by [`../tools/ci/state-transcript-summary.sh`](../tools/ci/state-transcript-summary.sh),
which merges the per-tick `state_<tick>.json` files into one JSON and renders the markdown table.

## Getting a replay that shows your change

Replays are the project's deterministic seed-plus-orders logs (see
[`../REPLAY.md`](../REPLAY.md)). Two ways to produce one:

1. **Play it.** Run the game, play a battle that demonstrates your change, then
   grab the saved file from `user://replays/` (on Linux:
   `~/.local/share/godot/app_userdata/sparta/replays/`) and commit it under
   `demos/`. Point `replay` at it. This is how you show *specific tactics* (a
   flank charge, a rout, a new ability).
2. **Seed-only.** For changes visible in any battle (unit art, HUD, balance),
   `demos/showcase.json` is a ready-made deterministic auto-battle (seed `12345`,
   no orders). Copy it and change the seed if you want a different battle.

A replay only reproduces on the **same build**, which is exactly the point here —
CI replays it against *your PR's* build, so the clip reflects your change.

### Camera moves (presentation track)

A replay also records the **camera** — pan and zoom over time — as a presentation
track alongside the orders (see [`../REPLAY.md`](../REPLAY.md)). When CI records the
clip it drives the camera from that track, so a recorded session **pans and zooms
exactly as it was played**. This is how to show a change that only appears at a
non-default camera — e.g. the zoomed-in soldier figures: record a battle while you
zoom into the clash, and the clip zooms in too. `demos/camera-showcase.json` is a
ready-made example (an auto-battle that zooms into the melee and back out).

A demo can also **open already zoomed in or panned** — the clip starts on the
track's first keyframe (the recorder snaps to it before the first frame), so you
don't have to begin every demo on the wide default view.

The track is cosmetic and additive: a replay with no camera track (every older
recording, and hand-authored scenarios) plays with the default static camera, so
nothing here changes existing demos.

**Raise the framerate for a moving camera.** The defaults (`fixed_fps` 30, GIF
`fps` 12) are tuned for static-camera battle demos, where only the units move
slowly. A panning/zooming camera looks choppy at 12 fps, so for a camera-motion
demo bump the manifest — e.g. `"fixed_fps": 60, "max_frames": 600, "fps": 30` —
to record at the full physics-tick rate and output a smooth 30 fps GIF (at the
cost of a larger file). The manifest here uses those values.

### Order markers (what was commanded)

During a demo recording the clip also draws the **player's orders** over the
field, so a viewer sees *what was commanded*, not only the resulting moves: a
green dashed path with a destination ring (plus dots for shift-waypoints) for a
move, and a red line with a crosshair for an attack. It's driven from the orders
already in the replay, so any scenario with player orders shows them
automatically — no manifest field to set. The overlay is recording-only: in-app
**Watch Replay** keeps orders on the hold-Space survey, unchanged.

The clip also replays the player's **mouse**, captured into the replay's `pointer`
track (see `REPLAY.md`): the cursor reticle, yellow selection halos on the selected
regiments, the multi-select drag-box, a pulse ringing out where each order is issued,
and a label + tint on the cursor when a stance is armed. It's captured live while a
battle is recorded -- same as the orders and camera -- so playing and saving a replay
records your real mouse for free (`demos/scenarios/pointer-demo.json` is one such
recording). Replays without a pointer track simply show no cursor overlay.

The clip also flashes the **keyboard hotkeys** you pressed, captured into the replay's
`keys` track: each gameplay hotkey (stances, `T` formation, `[`/`]` line width, merge,
control groups) pops up as a labelled chip by the cursor and fades over ~0.7 s, so a
keyboard-driven change reads on screen rather than happening invisibly
(`demos/scenarios/resizable-widths.json` is one such recording). Like the pointer track
it's captured live and back-compatible -- replays without a keys track show no chips.

## Hand-authoring a scenario

You can also write a replay JSON by hand — a **scenario** — to stage a specific
clash deterministically, rather than recording one by playing. The files under
`demos/scenarios/` (and `charge_demo.json`, `support_demo.json`, `clash.json`)
are built this way. A scenario is an ordinary replay file (see
[`../REPLAY.md`](../REPLAY.md) for the schema): a `seed` plus a list of `orders`,
each stamped with the physics `tick` it fires on.

To get the timing right you need the default battle's layout. A standard 5v5
(seed `"12345"`, no campaign) spawns these units, by `uid`:

| Unit | Team 0 (player, top, `y=300`) | Team 1 (enemy, bottom, `y=700`) |
| --- | --- | --- |
| Spearmen | 0 | 5 |
| Infantry | 1 | 6 |
| Archers | 2 | 7 |
| Cavalry | 3 | 8 |
| Cavalry | 4 | 9 |

Both lines center on the `1600 × 1000` field, so they start **400 px** apart
vertically. The horizontal spacing is no longer a flat 150 px per unit (issue
#677: a flat spacing let a wide LOOSE-order Archers regiment overlap its
Infantry neighbour) — each adjacent pair's gap widens to fit their actual
formation widths, so the standard 5v5's `x` positions are:

| uid | Type | `x` |
| --- | --- | --- |
| 0 / 5 | Spearmen | 476.75 |
| 1 / 6 | Infantry | 626.75 |
| 2 / 7 | Archers | 806.75 |
| 3 / 8 | Cavalry | 973.25 |
| 4 / 9 | Cavalry | 1123.25 |

Each unit's sprint speed is stated
in the loadout in **metres/second** (`sprint_mps`); effective px/s is
`sprint_mps × WORLD_UNITS_PER_METER` (`20`) `× SPEED_SCALE` (`1.0`):

| Unit | sprint speed (m/s) | effective px/s |
| --- | --- | --- |
| Spearmen | 2.8 | 56 |
| Infantry | 4.0 | 80 |
| Archers | 4.5 | 90 |
| Cavalry | 8.5 | 170 |

**Only team 1 advances on its own.** The enemy AI (`Battle.gd` →
`_run_enemy_ai()`) walks each idle enemy toward the nearest player unit. Team 0
units stay put until you order them, so a scenario that needs the player line to
engage **must** issue a move (or attack) order early — for example the tick-12
order in `demos/scenarios/line-relief.json` and `charge_demo.json`. Forget it and
the clip records the player line standing still while only the enemy closes.

With both sides closing over the 400 px gap, a head-on meet takes roughly
`400 / (sum of the two effective speeds)` seconds: about 3.6 s for
spearmen-vs-spearmen (`56 + 56`), about 1.2 s for cavalry-vs-cavalry (`170 + 170`).
These are approximations — the enemy AI re-targets only every `AI_PERIOD` (1 s),
and cavalry carry a 0.3 s order-response delay — so work the timing out on paper
**before** spending a CI run on it; a mistimed scenario silently records the
wrong moment.

Note that `max_frames` counts **output video frames at `fixed_fps`**, not physics
ticks: at the default 30 fps, 480 frames ≈ 16 s and 600 ≈ 20 s.

**`camera`/`max_frames` and `state`/`frames` ticks live on two different tick bases —
author each against the right one.** The recorded clip (`--fixed-fps` from the
manifest, default 30) and a state/frame dump (`dump-state.sh`/`capture-frames.sh`,
which never pass `--fixed-fps` and so run at the project's default 60 physics
ticks/second) are two *separate* Godot runs of the same input script. Sim behavior
(morale recovery, rout timers, movement) is driven by real elapsed seconds via
`delta`, so it converges at the same wall-clock moment either way — but the tick
*count* that moment falls on differs by the ratio of the two rates (a `fixed_fps: 30`
recording needs half as many ticks to reach a given real-time point as a 60 Hz state
dump does). Concretely: author `camera` keyframes and reason about `max_frames`
against the manifest's own `fixed_fps`; author `state`/`frames` ticks (and any tick
numbers you verify with `dump-state.sh`/`capture-frames.sh`) against the default 60
Hz — don't reuse one script's `state` tick numbers as if they were also valid
`camera` tick numbers, or vice versa. A `scenario`-only demo with no `steps` (like
`demos/inputs/morale-recovery.json`) only has `camera` on the recording-basis side,
since there are no player-input ticks to fall out of sync between the two runs.

## When it runs

- On any same-repo PR that touches `scenes/`, `scripts/`, `assets/`, or
  `project.godot` (a "user-visible change"). Docs/CI/test-only PRs don't trigger it.
  Fork PRs are excluded because CI needs write access to push the clip to the
  `demo-media` branch.
- **A demo is always posted on those PRs.** With a manifest (`demos/demo.<slug>.json`
  or the legacy `demos/demo.json`), it records the replay you named (tailored to
  your change). Without one, it falls back to the default `demos/showcase.json`
  battle, posted with an honest "generic build demo" caption that nudges you to
  add a manifest. So the manifest is how you make the demo *demonstrate your
  change* — skipping it gives a generic clip, not nothing.
- **Unless you opt out.** A manifest with `"skip": true` posts a short note
  instead of a clip — see below.

## No clip applies

Some user-visible changes genuinely can't be shown by the recorded-battle pipeline:
a **paused-overlay** interaction (e.g. previewing a queued waypoint while the sim is
paused), an **editor-only** tool, or a change that's visible only through input the
replay format doesn't capture. In those cases a generic showcase clip is worse than
nothing — it shows an unrelated battle and implies it's a demo of your change (see
issue #75).

To say so, commit a `demos/demo.<slug>.json` that opts out:

```json
{
  "skip": true,
  "reason": "Previews a queued waypoint in the paused Space overlay — a paused-overlay interaction the recorded-battle pipeline can't capture."
}
```

CI records nothing and upserts the demo section of the PR **description** with an
honest note (`🚫 No gameplay clip for this PR — <reason>`) rather than a misleading
GIF. Only use this when the change really can't be filmed — for anything visible in
a normal battle, a tailored replay (or `showcase.json`) is far better.

## Still images for static features

A recorded battle is the right tool for *motion* — a charge, a rout, an ability
firing. For **static** changes a single labelled frame is clearer: a new
**interface/menu/HUD**, **new or improved art**, a layout or visual-polish change.
For those, post informative **image(s) in the PR description** (the body), in
addition to a clip when motion also matters — a reviewer then judges the change at a
glance without opening media.

### Producing the PNG

- **Battle-visible art** (units, HUD, effects): record as usual with the launcher
  command from [Trying the launcher locally](#trying-the-launcher-locally), then pull
  a single frame out of the AVI:

  ```sh
  ffmpeg -ss 5 -i /tmp/demo.avi -frames:v 1 demos/shots/your-change.png
  ```

  `-ss 5` grabs the frame ~5s in; pick a moment that shows your change.

- **A new menu/HUD/screen** the replay-driven battle doesn't reach: run that scene
  under Xvfb and save a viewport screenshot from a short throwaway script — after the
  frame draws, call

  ```gdscript
  get_viewport().get_texture().get_image().save_png("res://demos/shots/your-change.png")
  ```

  Crop or scale with ffmpeg or an image tool afterwards if needed.

### Posting it

Commit the PNG under `demos/shots/` on your PR branch (create the dir if needed),
then embed it in the **PR description** by raw URL with a caption:

```md
![What changed](https://github.com/lacaedemon/sparta/raw/COMMIT_SHA/demos/shots/YOUR_IMAGE.png)
```

Use the **commit SHA** (immutable) so the image keeps rendering after the branch is
deleted on merge — a branch-name URL works while the PR is open but breaks once the
branch is gone. The PNG is committed in-repo, so it's permanent in `main` after merge.

This is independent of the `demos/demo.json` manifest: the manifest drives the CI
gameplay **clip**, which CI itself inserts into the PR **description** (see
[Where the GIF lives](#where-the-gif-lives)), while these images live in the same
**description** but you add them yourself, by hand, outside CI's marked section. For
a static UI a battle can't film, combine them — opt the clip out with `"skip": true`
(see [No clip applies](#no-clip-applies)) and post a still in the description instead.

## Where the GIF lives

The GIF (and the MP4 — see [Sound](#sound)) is pushed to a long-lived
**`demo-media`** branch and embedded/linked by raw URL. This deliberately avoids
committing to your PR's own branch: it never disturbs the PR's required status
checks, and the clip keeps working after the PR branch is deleted on merge. CI
upserts it into the PR **description** between `<!-- sparta-demo -->` /
`<!-- /sparta-demo -->` markers, replacing only that section in place on each push
(no spam, and the rest of your description is left untouched) — see
[`tools/ci/upsert-pr-body-section.sh`](../tools/ci/upsert-pr-body-section.sh). The
filename carries the commit SHA so GitHub never shows a stale cached frame.

## Sound

The inline preview is a GIF (it plays once and freezes on the final frame), and
**GIF can't carry audio** — so the clip you see in the description is silent. The
workflow also encodes an **MP4 with sound** (Godot's Movie Maker captures the game's
audio into the recording; the GIF step just drops it) and links it under the GIF as
*"watch with sound"*. Click it to play the clip with audio, pause, and scrub. SFX
are off by default in-game, so whichever recorder runs turns them on for the recording
([`../tools/demo/DemoInputRecorder.gd`](../tools/demo/DemoInputRecorder.gd) for scripted
input, [`../tools/demo/DemoRunner.gd`](../tools/demo/DemoRunner.gd) for a replay) — that's
how the MP4 ends up with the battle's sound.

Why a GIF plus a link, and not an inline player: GitHub renders an inline, playable
`<video>` **only** for files uploaded through its browser-only attachment CDN
(`user-attachments` / `user-images.githubusercontent.com`), which needs a logged-in
session and is unreachable from CI. A `<video>` tag or bare link pointing at our
`demo-media` raw URL renders as a dead/greyed player or a download. Linking the
poster to the MP4's blob page (so a click opens GitHub's file-view player) works on
desktop but **not on mobile** — the blob-view video player doesn't play there — so
an inline GIF (which renders everywhere, including mobile) plus a click-to-play MP4
link is the honest best CI can post. The
recorder force-enables SFX, so the MP4 is silent only if no sound events happen to
fire during the recorded battle.

## Trying the launcher locally

```sh
godot --headless --import        # once, to import the project
SPARTA_DEMO_REPLAY="res://demos/showcase.json" \
  xvfb-run -a godot --rendering-driver opengl3 \
  --write-movie /tmp/demo.avi --fixed-fps 30 --quit-after 300 \
  res://tools/demo/DemoRunner.tscn
# Silent, play-once GIF (inline preview; -loop -1 = no infinite loop):
ffmpeg -i /tmp/demo.avi -vf "fps=12,scale=640:-1:flags=lanczos" -loop -1 /tmp/demo.gif
# MP4 with sound (the AVI already holds the audio track):
ffmpeg -i /tmp/demo.avi -vf "scale=640:-2:flags=lanczos" \
  -c:v libx264 -pix_fmt yuv420p -profile:v high -movflags +faststart -c:a aac -b:a 128k /tmp/demo.mp4
```

[`../tools/demo/DemoRunner.gd`](../tools/demo/DemoRunner.gd) is the headless entry
point: it arms replay playback from `SPARTA_DEMO_REPLAY`, then switches to the
battle scene while Movie Maker records. It's tooling only — it changes no
simulation code.
