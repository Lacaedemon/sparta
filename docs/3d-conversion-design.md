# 3D conversion — design & phased plan

Tracking issue: [#69](https://github.com/Lacaedemon/sparta/issues/69).
Status: **proposed design** — research done (three-agent survey of the codebase,
of MichelangeloConserva/TotalWarSimulator, and of sim/render-split precedents),
phases not yet started.

## Goal

Convert the battle presentation from 2D top-down to a **Total War-style 3D
battle view**: a terrain plane (eventually with real elevation), a free
**rotatable** orbit camera, and animated soldier crowds — while preserving,
bit-for-bit, the deterministic fixed-tick simulation, its replay system, and
the test/demo/CI infrastructure built around them.

Hard requirements, in priority order:

1. **The sim survives unchanged.** Same orders, same ticks, same RNG draws,
   same state-dump output. The conversion is a presentation-layer swap, not a
   rewrite. Existing replays keep replaying bit-identically.
2. **A rotatable map camera.** Full yaw orbit plus pitch within a clamped
   range, zoom to cursor, pan (keys + edges), a "reset to north" affordance.
   This rules out any 2.5D compromise built on the axis-aligned 2D renderer.
3. **The 60fps large-battle budget holds** (several hundred soldiers engaged,
   on the reference M2 MacBook Air and the dev PC — see `PLAN.md`).
4. **CI keeps working headlessly**: GUT suite, state-dump diffs, and Movie
   Maker demo recording under xvfb + the GL Compatibility renderer.

Out of scope: the campaign map (`scenes/Campaign.tscn` stays 2D; it is a
separate scene with its own presentation), and any gameplay changes to combat
or movement. Terrain *elevation affecting gameplay* is designed for but gated
behind its own phase and its own decision.

## Should we switch engines? (Godot vs Unity)

Considered and rejected — the conversion stays in Godot. The assessment:

**What Unity would offer.** A more mature 3D animation toolchain (Mecanim,
rigging), a built-in terrain system, a large asset store, and — the
heavyweight argument — DOTS/ECS with Burst, the industry answer for crowds an
order of magnitude beyond ours.

**Why it loses here:**

- **The expensive, load-bearing 60% of this codebase is engine-portable only
  in theory.** The deterministic sim, replay format, 138-file GUT suite,
  benchmark harness, scripted-input demo recorder, and CI pipeline would all
  need rewriting in C# and re-verifying from scratch. Inside Godot, the same
  work is a bounded render-layer swap (see *Architecture: planar authoritative
  sim + 3D projection shell*).
- **Our scale does not need DOTS.** The budget is hundreds of soldiers at
  60fps; MultiMesh + vertex-animation-texture crowds demonstrably render
  thousands of instances at hundreds of fps in Godot 4 (numbers under
  *Rendering stack*). Unity's ECS advantage starts mattering around 10k+
  animated agents — beyond the game we are building.
- **TotalWarSimulator is the cautionary tale for exactly this move.** Its
  author abandoned a working Python prototype for a Unity port, left that port
  with two coexisting half-migrated generations of unit code, then started a
  Unity-DOTS rewrite that never got past scaffolding, plus a `cpp` branch.
  The engine hop, not any technical wall, is where that project died. Our
  conversion must be an incremental port of a working game, never a restart.
- **Cheaper escape hatches exist inside Godot** if GDScript sim performance
  ever becomes the wall: packed arrays (already in use), GDExtension (C++),
  or Godot's .NET build — each preserves the codebase and the tooling.
- **Practical frictions:** Unity headless CI needs license activation where
  headless Godot is a download; Godot is MIT-licensed with no
  runtime-fee-style platform risk; and a solo developer already productive in
  Godot restarts the learning curve for no player-visible gain.

Revisit trigger: if requirements ever grow to tens of thousands of
simultaneously animated soldiers or AAA-grade animation blending, reassess —
and even then, Godot's .NET build or GDExtension comes first.

## Architecture: planar authoritative sim + 3D projection shell

Every credible precedent keeps the authoritative simulation on a plane (or a
ground-locked heightfield) with controlled arithmetic, and treats 3D as a
presentation shell that samples the sim:

- **0 A.D. (Pyrogenesis):** fixed-point sim (`CFixed_15_16`, float conversions
  deliberately private), 2D navcell pathfinding; the renderer "finds the
  height of a unit based on the position" at display time
  ([source](https://www.moddb.com/games/0-ad/news/the-pathfinding-saga-continues)).
- **Spring/Recoil (Beyond All Reason):** hard synced/unsynced split, and
  notably **two heightmaps** — a synced one the sim owns and an unsynced copy
  for rendering ([RecoilEngine #779](https://github.com/beyond-all-reason/RecoilEngine/issues/779)).
  30Hz sim under 60Hz rendering with draw-time interpolation.
- **OpenRA:** integer world coordinates (`WPos`, 1024 units/cell); "much of
  the logic treats the game as being 2D"
  ([wiki](https://github.com/OpenRA/OpenRA/wiki/World-Coordinate-System)).
- **Total War itself** (by public evidence): battle logic decoupled from
  rendering — "the logic generates the 'future' whilst the display renders the
  'now'" ([Game Developer interview](https://www.gamedeveloper.com/design/designing-i-total-war-warhammer-ii-i-to-handle-tons-of-units-and-massive-battles));
  heightfield battlefield, instanced soldier crowds, animation purely
  presentational ([GPUOpen engine series](https://gpuopen.com/learn/anatomy-total-war-engine-part/)).
- **TotalWarSimulator's Unity port:** the sim stays planar in XZ throughout;
  Y is stripped everywhere and exists only as presentation — proof the
  approach carries to a hobby-scale codebase, not just industrial engines.

Sparta already has this split as a one-way data contract: the sim writes
per-soldier `PackedVector2Array`s (`_sim_soldier_pos`, `_sim_soldier_facing`,
…) and the render layer only reads them (`scripts/Unit.gd`, flock-renderer
section, states the contract explicitly; snapshots exclude render caches).
**The conversion formalizes that contract and hangs a second, 3D consumer off
it.**

The mapping is:

```
sim (unchanged)                    render shell (new)
Vector2(x, y)  wu, planar   →      Vector3(x_m, h(x, y), y_m)  metres
facing angle   (radians)    →      yaw about +Y
tick t         (60 TPS)     →      draw-time interpolation between t-1 and t
```

- **Height enters the sim as data, never as physics or plugin calls.** When
  elevation lands (phase 3D-4), the sim owns a plain height array sampled by
  a Sparta-owned GDScript function with a pinned bilinear rule — mirroring
  Spring's synced heightmap — and the terrain renderer consumes the same
  source image. No `Terrain3D` call, no raycast, no GDExtension float path
  ever executes inside sim code. Until then the height function is
  constant zero and existing replays stay valid.
- **The render shell converts wu→metres at the boundary** (divide by
  `WorldScale.WU_PER_M`), because Godot 3D conventions (lighting, camera
  near/far, physics defaults) assume metres. This is a permitted boundary
  conversion under `docs/units-convention.md` — the sim keeps world units end
  to end, exactly as today.
- **Nothing flows back.** Animation state, LOD choices, camera position, and
  terrain rendering derive from sim state and never write into it — same as
  the current 2D renderer.

### Transitional scene strategy: the 2D sim tree keeps running

`Unit` extends `Node2D`, and the parent-local soldier arrays are seeded from
`unit.position` — a `Vector2`. Rather than migrating the sim off `Node2D` (a
risky, determinism-touching refactor with no player value), the transition
keeps the entire existing battle tree as the authoritative sim, with its
canvas hidden, and adds a 3D shell beside it:

```
Battle3D (Node3D)                      ← new scene, becomes the battle entry
├─ SimRoot (SubViewport or hidden CanvasLayer)
│  └─ Battle (Node2D) — today's tree, unmodified: sim + orders + replay
├─ GroundPlane / Terrain (MeshInstance3D; later Terrain3D)
├─ UnitViews (Node3D) — one view node per Unit: MultiMeshInstance3D consumers
│  of that unit's _sim_* arrays, banner/chrome quads
├─ OrbitCamera (Camera3D + controller)
└─ HUD (CanvasLayer) — carried over
```

A `Node2D` whose canvas item is hidden is just data + `_physics_process` —
the sim runs identically whether or not anything draws it. `Unit._draw` and
the 2D MultiMesh refresh are skipped when not visible, so the hidden 2D tree
costs sim time only. This gives a genuine A/B during the transition: the same
battle can be opened in the 2D scene or the 3D scene, and the state dumps must
match. Retiring the 2D renderer later (phase 3D-5) means deleting render
methods, not surgery on the sim.

**Input flows through the existing chokepoints.** All gestures already read
the cursor through `SelectionManager._cursor_world()`, and the scripted-demo
recorder already injects *world-coordinate* clicks via
`set_cursor_override()`. The 3D shell computes the ground point under the
mouse (analytic ray–plane while the world is flat; heightfield walk later)
and feeds it through the same override path — the drag-select, right-click
orders, formation-drag, and frontage-grip logic above it is planar `Vector2`
math and runs unchanged. Box-select switches from a world-space `Rect2` test
to the standard screen-space test (`camera.unproject_position(unit_pos)`
against the drag rect — the [KidsCanCode recipe](https://kidscancode.org/godot_recipes/4.x/input/multi_unit_select/index.html)),
which needs no colliders and reads positions straight from the sim.

## Rendering stack

| Layer | Technique | Assessment |
| --- | --- | --- |
| Mass soldiers | `MultiMeshInstance3D`, one instance per soldier, transforms pushed from `_sim_soldier_pos` each dirty frame (same pattern as today's `MultiMeshInstance2D`) | Engine-native; the current 2D flock renderer is architecturally identical, so this is a port, not a redesign |
| Soldier animation | Vertex-animation textures (VAT) in the MultiMesh shader — per-instance track (idle/march/attack/die) selected via `INSTANCE_CUSTOM` from sim state | Community-proven: the [antzGames VAT plugin](https://github.com/antzGames/Godot_Vertex_Animation_Textures_Plugin) reports 2,000 instances at 300–450fps **on the Compatibility renderer** (author's numbers — verify on reference hardware in the spike). No track blending on GL; acceptable for massed troops |
| Near/hero detail (optional, later) | A handful of real `Skeleton3D` units swapped in near the camera | Keep count in the tens: ~100 GL-rendered skeletons flatline even a 4090 ([godot#88954](https://github.com/godotengine/godot/issues/88954)) — per-soldier skeletons are the one hard "don't" |
| Interim soldier look (phase 3D-1) | Extruded versions of the existing procedural marks (dart/kite/disc/figure prisms), no animation | Zero art dependency; keeps the readable-token aesthetic while the VAT pipeline is built |
| Terrain | Flat `PlaneMesh` first; [Terrain3D](https://github.com/TokisanGames/Terrain3D) when elevation lands (production-grade, Compatibility-supported since 1.0/Godot 4.4; GDExtension — see CI notes). Fallback: [HTerrain](https://github.com/Zylann/godot_heightmap_plugin) (pure GDScript, maintenance mode) or a hand-rolled clipmap over the same height image | Decision deferred to phase 3D-4; the sim-owned height data makes the renderer swappable |
| Selection/state chrome | Terrain-conforming quads under units (rings, halos) via a small MultiMesh; `Decal` where the Forward+ renderer is active | Decals are reduced-featured on Compatibility, so quads are the baseline |
| Banners/flags | Quad meshes (optionally billboarded) replacing `UnitSprites.flag()` | Straightforward |
| Strength/morale bars | Screen-space: project unit position, draw in HUD layer | Keeps bars crisp and camera-angle-proof; already how HUD thinks |

Renderer target: the game itself can run Forward+ (better lighting, decals,
VAT blending) with **Compatibility as the supported floor**, because CI's
Movie Maker recording runs under xvfb + `--rendering-driver opengl3`. Every
technique above works on both; anything that doesn't (decals, VAT blending)
gets a Compatibility fallback or is cosmetic-only.

## Subsystem inventory: what converts, what ports, what's untouched

From the architecture survey (function-level pointers; see the files
themselves for detail):

**Rewritten for 3D (the bounded 2D surface):**

- `scripts/Unit.gd` render methods — `_setup_flock_renderer()`,
  `_refresh_flock_render()`, `_update_lod()`, `_draw()` → a `UnitView3D`
  consumer (MultiMesh3D + chrome). Zoom-hysteresis LOD becomes
  camera-distance LOD; the mesh-swap mirroring hack (2D MultiMesh cannot
  mirror an instance) dies — 3D transforms rotate properly.
- `scripts/UnitMeshes.gd` / `scripts/UnitSprites.gd` — 2D `ArrayMesh`
  builders → 3D mesh builders (extruded prisms first, VAT meshes later).
  Same pure-static, headless-testable style.
- `scripts/CameraController.gd` — full rewrite as an orbit RTS camera
  (pan/edge-pan, zoom-to-cursor, **yaw orbit**, pitch clamp, bounds,
  north-reset). Expect to roll our own (~150 lines is typical), cribbing from
  [godot-open-rts](https://github.com/lampe-games/godot-open-rts)'s camera
  (MIT, same engine). The replay presentation-track driver flag
  (`_presentation_driven`) carries over; the camera track format gains a
  version (see *Determinism, replay, and demo pipeline*).
- `Battle._draw()` ground rendering → ground plane / terrain node.

**Retargeted (logic survives, transform changes):**

- `SelectionManager._cursor_world()` → mouse-ray-to-ground; everything above
  it unchanged. Box-select world-`Rect2` → screen-space unproject test. The
  flag-standard pick fallback re-derives against the 3D banner quad's screen
  bounds.
- `HUD.gd` — screen-space UI survives; `DistanceLegend.metres_per_pixel()`
  assumes `Camera2D.zoom` and becomes a perspective-aware measurement
  (unproject two screen-centre points to the ground plane and divide); the
  pure wu→metric helpers are untouched.

**Untouched (the point of the whole design):** `SoldierBodies`,
`SoldierSteering`, `SoldierCollision`, `SoldierMelee`, `SoldierCombat`, the
spatial hashes, `UnitFormation`, `PathField` (grid A* is a floor-plane
algorithm no matter how the world renders), `UnitManeuver`, `UnitMorale`,
`Order`, `Replay`, snapshot/rewind, `WorldScale`, `DemoState` dumps, the
scripted-input demo format, and every pure-sim GUT test.

## What we take from TotalWarSimulator

License: the repo is **MIT** (LICENSE added on its default `unity` branch) —
rare in this genre, so both ideas and code are usable. Two caveats: its
vendored LAP solver (`Assets/lap/`, plus two other assignment
implementations) has no license headers and unclear upstream origin —
re-implement rather than copy; and its `Alglib` plugin is GPL/commercial
dual-licensed — don't touch. Full study in `docs/related-games.md`.

Ideas adopted into this plan:

1. **Keep the sim planar under a 3D view** — their Unity port's discipline
   (Y stripped everywhere) independently validates our architecture.
2. **Drag-out ghost formation preview**: ghost markers previewing slots live
   during the right-drag; drag length sets frontage, drag perpendicular sets
   facing. The direct 3D translation of our formation drag — same math on
   ray-projected ground points (phase 3D-2).

Ideas noted as **sim-side candidates, deliberately outside conversion
scope** (they are gameplay changes; file separately if wanted):

- Optimal soldier→slot assignment (Hungarian/Jonker-Volgenant) on formation
  change, **gated by turn angle** (their Python version re-assigns only when
  the path bends past ~50°; their Unity port dropped the gate and paid with
  per-frame O(n³)). Relevant to the slot-ownership work (#547 lineage).
- Arrival-time-normalized wheeling: per-soldier speed = `dist_i / t` with a
  shared `t`, so files stay dressed through a wheel with no explicit wheel
  math.
- Carrier-on-a-path unit movement with a lag throttle (the carrier waits when
  average soldier slot-error grows).
- Two-tier combat pressure: back-rank soldiers whose ray to their target hits
  an ally press up behind him — cheap rank-feeding behaviour.

Its pitfalls, adopted as **anti-requirements** for the conversion:

- No physics-engine-driven formation motion (their every incarnation fought
  the physics engine with force hacks; our kinematic slot-seeking stays).
- No per-frame global recomputation (assignment, nearest-enemy LINQ scans) —
  budget such work on staggered ticks and spatial hashes, as the sim already
  does.
- No frame-rate-coupled combat (their damage was `× Time.deltaTime` inside a
  render-driven loop; our fixed-tick resolution is non-negotiable).
- No engagement logic that mutates poses on collider contact (their units
  visibly snap on engagement).
- **No rewrite spiral.** Every phase of the roadmap lands on the existing
  scene tree with CI green and the 2D path still shippable, until the final
  retirement phase.

## Determinism, replay, and demo pipeline

- **Sim determinism is untouched by construction** — no new code runs inside
  the tick. The state-dump diff CI (`DemoState` + the website demo-state
  sweep) is the enforcement mechanism: phase 3D-1's exit criterion is
  bit-identical dumps for the standard scenarios driven through the 3D scene.
- **Replays:** order tracks replay unchanged. The *presentation* tracks
  (camera/pointer/keys) are camera-model-specific: the camera track gains a
  format version — v1 (pan/zoom) tracks keep replaying in the 2D scene or map
  approximately onto the orbit camera (top-down pitch, yaw 0); v2 records
  pos/yaw/pitch/distance. Decide the exact mapping in phase 3D-2.
- **Scripted-input demos** already inject world-space cursor overrides, so
  input scripts survive as-is while the world is planar.
- **Movie Maker recording** keeps working: `xvfb-run` + `opengl3` renders the
  3D viewport the same way it renders the 2D one today, provided every shader
  in the stack runs on Compatibility (a standing constraint above).
- **Cross-platform float caution** (from the precedent survey: streflop,
  fixed-point engines, [Gaffer on floating point determinism](https://gafferongames.com/post/floating_point_determinism/)):
  we already rely on same-engine-build float determinism for replays, and the
  conversion adds no sim math — but the future heightfield sampler must be
  our own pinned-arithmetic GDScript (no library calls, no transcendentals on
  height-derived values), verified by a Windows↔Linux bit-exactness test
  before any gameplay reads height.

## Performance budget

The budget stays `PLAN.md`'s: 60fps at several hundred engaged soldiers on
the M2 Air. Known numbers going in: VAT MultiMesh crowds report hundreds of
fps at 2k instances on all Godot renderers (author-reported; re-measure);
per-soldier `Skeleton3D` collapses around ~100 under GL and a few thousand
under Vulkan ([godot#99194](https://github.com/godotengine/godot/issues/99194),
[godot#88954](https://github.com/godotengine/godot/issues/88954)) — hence VAT
for the mass and skeletons only ever as a bounded hero-detail garnish. The
existing benchmark scenario gains a 3D-scene variant in phase 3D-1 so the
relative-regression CI check covers the shell; the absolute check stays a
by-hand run on reference hardware, as today.

## CI and tooling impact

- `tools/check.sh validate/test` — unaffected in principle (new scripts must
  parse and pass GUT headlessly; new `class_name`s need the one-time headless
  `--import`, per the GDScript quirks list in `CLAUDE.md`).
- **Terrain3D is a GDExtension**: CI needs its Linux binary present at import
  time, and headless `--import` behaviour must be verified before phase 3D-4
  commits to it — this is the plugin's main cost relative to a pure-GDScript
  fallback, and it is why terrain-plugin choice is deferred until then.
- Demo recording: unchanged mechanics; clips re-golden as the view changes
  (expected, per-phase). State-dump diffs are the invariant that must NOT
  change.
- Patch coverage: the render shell is view code, but its pure parts (mesh
  builders, LOD selection, ray/ground math, track-format mapping) follow the
  existing pure-static-function style precisely so they stay unit-testable
  headlessly — same discipline that keeps `UnitMeshes` and `DemoState`
  covered today.

## Phased roadmap

Each phase is independently shippable, lands with CI green, and leaves the 2D
battle scene as the default until the parity gate at the end. Phases map to
follow-up issues under #69.

- **3D-0 — Spikes (throwaway branches, findings recorded on #69):**
  (a) VAT pipeline: bake one CC0 low-poly soldier (idle/march/attack/die),
  render 1–2k instances on Forward+ and Compatibility, measure on reference
  hardware, record under xvfb. (b) Projection shell: hidden 2D battle driving
  a MultiMesh3D view with an orbit camera and ray-picking, state dumps
  verified identical. Exit: go/no-go numbers for the stack above.
- **3D-1 — Projection-shell MVP (the conversion's backbone):** `Battle3D`
  scene per the transitional strategy; flat ground plane; soldiers as
  extruded-mark prisms (no animation); orbit camera with full rotation;
  `_cursor_world` ray path; screen-space box-select; selection rings as
  ground quads; HUD carried over with the perspective-aware distance legend.
  Exit: every standard scenario playable in 3D; state dumps bit-identical to
  the 2D scene; benchmark variant added; all GUT green.
- **3D-2 — Interaction & presentation parity:** formation-drag ghost preview
  in 3D, frontage grips, banners, bars, camera presentation-track v2 (+v1
  mapping), demo catalog re-goldened, website pages updated with 3D clips.
  Exit: everything you can do in the 2D battle you can do in 3D, and the demo
  pipeline exercises it.
- **3D-3 — Animated crowds:** VAT bake pipeline committed (Blender + export
  scripts under `tools/`), CC0 soldier models (Quaternius / KayKit / Kenney
  candidates — CC0 keeps `PLAN.md`'s art policy intact), animation tracks
  driven from sim state, distance LOD (VAT mass ↔ hero skeletons optional).
  Exit: 60fps budget holds on reference hardware at the large-battle
  benchmark; Compatibility renderer still records demos.
- **3D-4 — Terrain elevation:** sim-owned heightfield asset + pinned bilinear
  sampler with Windows↔Linux bit-exactness tests; Terrain3D (or fallback)
  rendering from the same image; render-side projection of soldiers onto
  height. **Gameplay effects of height (slope speed, charge, missile range)
  are a separate, explicitly-gated decision** — they change balance and
  replays, and belong to their own design round.
- **3D-5 — Retire the 2D battle renderer:** once parity + perf are confirmed
  and the user signs off: delete `Unit`'s 2D render methods, `UnitMeshes`
  2D builders, the 2D camera path, and the scene switch; the sim tree stays
  (its nodes are the sim). Update all docs/website. The campaign map is
  unaffected.

## Open questions (decide before or during the flagged phase)

1. **Conversion vs permanent dual mode.** Issue #69 says "add 3d mode"; this
   plan recommends *conversion* — dual renderers are a standing tax on every
   future visual feature (every demo, every piece of chrome, twice). The
   transitional A/B period gives the mode experience temporarily; 3D-5 is
   where the 2D view actually dies. Needs an explicit user decision at the
   3D-5 gate.
2. **Terrain plugin choice** (Terrain3D vs HTerrain vs hand-rolled clipmap) —
   deferred to 3D-4; hinges on the GDExtension-in-CI verification.
3. **Default renderer** (Forward+ with Compatibility floor, or Compatibility
   everywhere) — decide after the 3D-0 measurements.
4. **Camera presentation-track v1 mapping** (replay old 2D camera moves in
   the 3D scene, or keep v1 replays 2D-scene-only until 3D-5) — decide in
   3D-2.

## References

Precedents: [RecoilEngine sim/render split](https://github.com/beyond-all-reason/RecoilEngine/blob/master/AGENTS.md) ·
[Recoil synced/unsynced heightmaps](https://github.com/beyond-all-reason/RecoilEngine/issues/779) ·
[0 A.D. fixed-point `CFixed`](https://github.com/0ad/0ad/blob/master/source/maths/Fixed.h) ·
[0 A.D. pathfinding architecture](https://www.moddb.com/games/0-ad/news/the-pathfinding-saga-continues) ·
[OpenRA coordinates](https://github.com/OpenRA/OpenRA/wiki/World-Coordinate-System) ·
[openage curves](https://blog.openage.dev/t1-curves-logic.html) ·
[TW:WH2 sim/render interview](https://www.gamedeveloper.com/design/designing-i-total-war-warhammer-ii-i-to-handle-tons-of-units-and-massive-battles) ·
[Total War engine anatomy, GPUOpen](https://gpuopen.com/learn/anatomy-total-war-engine-part/) ·
[TW group-formations modding docs](https://wiki.totalwar.com/w/Group_Formations_documentation.html) ·
[floating-point determinism](https://gafferongames.com/post/floating_point_determinism/) ·
[RTS float sync postmortem](https://www.gamedeveloper.com/programming/cross-platform-rts-synchronization-and-floating-point-indeterminism).
Godot techniques: [MultiMesh optimization](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html) ·
[antzGames VAT plugin](https://github.com/antzGames/Godot_Vertex_Animation_Textures_Plugin) ·
[VAT instancing shader](https://godotshaders.com/shader/vertex-animation-with-instancing/) ·
[Skeleton3D GL ceiling](https://github.com/godotengine/godot/issues/88954) ·
[Skeleton3D scaling](https://github.com/godotengine/godot/issues/99194) ·
[Terrain3D](https://github.com/TokisanGames/Terrain3D) ([height queries](https://terrain3d.readthedocs.io/en/latest/docs/collision.html)) ·
[HTerrain](https://github.com/Zylann/godot_heightmap_plugin) ·
[3D drag-select recipe](https://kidscancode.org/godot_recipes/4.x/input/multi_unit_select/index.html) ·
[godot-open-rts](https://github.com/lampe-games/godot-open-rts).
TotalWarSimulator: [upstream](https://github.com/MichelangeloConserva/TotalWarSimulator) ·
[fork](https://github.com/dem-extra1/TotalWarSimulator) — full study notes in
[`related-games.md`](related-games.md).
