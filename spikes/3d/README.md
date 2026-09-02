# 3D-0 spikes -- projection shell and MultiMesh crowd

**Nothing in this directory is production code.**
It is throwaway spike work for phase 3D-0 of [`docs/3d-conversion-design.md`](../../docs/3d-conversion-design.md).
The scripts here are not covered by the GUT suite, not wired into any shipped scene, and not exempt from being deleted wholesale once the real `Battle3D` work starts.
They exist to answer go/no-go questions about the rendering stack, and nothing else.

## What is here

- [`ProjectionShell.tscn`](ProjectionShell.tscn) / [`ProjectionShell.gd`](ProjectionShell.gd) -- spike (b): the existing 2D battle tree running inside a hidden `SubViewport` while a `Node3D` shell reads its per-soldier arrays and draws one `MultiMeshInstance3D` per unit.

- [`OrbitCamera.gd`](OrbitCamera.gd) -- a minimal orbit camera (full yaw, clamped pitch, zoom, keyboard pan) plus the analytic ray-to-ground picking that stands in for `SelectionManager._cursor_world()`.

- [`CrowdBench.tscn`](CrowdBench.tscn) / [`CrowdBench.gd`](CrowdBench.gd) -- spike (a), partial: a `MultiMeshInstance3D` crowd whose every instance transform is rewritten each frame, reporting a frame-rate summary and quitting.

## How to run

```sh
# Projection shell, Compatibility (the CI floor). Left mouse prints the picked
# ground point; middle-drag orbits; WASD/arrows pan; wheel zooms.
godot --rendering-driver opengl3 --path . res://spikes/3d/ProjectionShell.tscn

# Crowd benchmark, Compatibility and Forward+.
SPARTA_SPIKE_INSTANCES=2000 godot --rendering-driver opengl3 --path . res://spikes/3d/CrowdBench.tscn
SPARTA_SPIKE_INSTANCES=2000 godot --rendering-method forward_plus --path . res://spikes/3d/CrowdBench.tscn
```

Do not pass `--headless`: it selects the dummy renderer, which makes any frame-rate number meaningless and (per `CLAUDE.md`) breaks Movie Maker recording outright.

## Measured numbers

Measured 2026-09-02, Godot 4.7.2 stable, Windows 11, **NVIDIA GeForce RTX 3050 Ti Laptop GPU**.
Vsync is disabled and `Engine.max_fps` is zeroed inside the benchmark, so these are throughput numbers rather than a monitor refresh rate.

| Scene | Renderer | Instances | Mean fps | Worst frame |
| --- | --- | --- | --- | --- |
| `CrowdBench` | Compatibility (OpenGL 3.3) | 2000 | 534 | 41.5 ms (24 fps) |
| `CrowdBench` | Forward+ (Vulkan 1.3) | 2000 | 630 | 16.9 ms (59 fps) |

Two caveats that make these a **floor rather than a headline**.

- The GPU is a 3050 Ti Laptop, **not** the RTX 3060 Ti the design document names as the reference machine, so the reference-hardware numbers the phase's exit criterion asks for are still outstanding.

- The machine was shared with other Godot processes during the run (`tools/check.sh` warned about 8 live Godot processes minutes earlier), so contention is baked into both figures, and the single bad worst-frame on Compatibility is more likely scheduling noise than a rendering cliff.

The projection shell was run for 900 idle frames on Compatibility and logged a live census each time the drawn population changed:

```
[shell] units=10 soldier-instances=1020
...
[shell] units=10 soldier-instances=833
```

The falling instance count is the point: the hidden 2D battle really ticked, soldiers really died, and the 3D view tracked it without anything writing back into the sim.

## What this proves

- **The projection-shell architecture works as written.** A `Node2D` battle tree with `visible = false` inside a `SubViewport` keeps running its `_physics_process`, and a sibling `Node3D` can read `_sim_soldier_pos` and draw it. No sim file was modified.

- **One `MultiMeshInstance3D` per unit is a viable shape** for the render consumer, and it maps one-to-one onto today's `MultiMeshInstance2D` flock renderer.

- **The wu-to-metre conversion belongs at the render boundary and costs nothing.** `WorldScale.M_PER_WU` is applied once per soldier per frame in the shell; the sim never sees metres.

- **Analytic ray-plane picking is enough while the world is flat.** `Camera3D.project_ray_origin` / `project_ray_normal` plus one division gives the ground point, with no colliders and no physics query.

- **A 2k static-mesh crowd is not close to the budget ceiling on either renderer**, on hardware weaker than the stated reference machine, with the worst possible update pattern (every transform rewritten every frame).

## What this does NOT prove

The following were in scope for 3D-0 and are **not** answered here.

- **Vertex-animation textures.** No CC0 soldier was baked, no VAT shader was written, and no animation track was driven from sim state. The crowd benchmark renders untextured, unanimated boxes, so it measures instancing and transform upload only -- it is not a VAT measurement, and the design document's 2,000-instances-at-300-450fps figure remains an unverified author-reported number.

- **State-dump parity.** The shell was never run against `DemoState` output, so the phase's bit-identical-dump criterion is untested. Nothing in the shell writes to the sim, which is an argument that parity should hold, not evidence that it does.

- **Reference-hardware numbers**, per the caveat above.

- **Recording under xvfb plus `opengl3`.** No clip was captured, on this machine or in CI.

- **Input routed back into the sim.** The shell prints the picked ground point and stops there; it never calls `set_cursor_override()`, so no selection, order, or formation drag was exercised through the 3D path.

- **Anything past a flat plane.** No terrain, no heightfield sampling, no LOD, no facing (instances are drawn with an identity basis), no selection chrome, no banners, no HUD.

- **A clean public accessor for the sim arrays.** The shell reaches into `_sim_soldier_pos` via `Object.get()`. A production shell needs `scripts/Unit.gd` to publish that contract properly.

## Suggested reading of the results

The Forward+ / Compatibility gap at 2k static instances is about 18 percent, which is small enough that it should not by itself decide open question 3 in the design document (default renderer).
That decision wants the VAT measurement, since VAT track blending is one of the features Compatibility does not have.
