# GEMINI.md — Google Antigravity / Gemini working instructions for Sparta

Orientation and standing policies for any Gemini or Google Antigravity (AGY) session working in this repo.
Sparta is a **Godot 4.7** (GDScript, Standard build — not .NET/C#) prototype fusing dynastic grand strategy with real-time tactical battles. See `README.md` for layout and `PLAN.md` for project vision, roadmap, architecture, and verification steps — read `PLAN.md` first.

## Cross-repo AI configuration (`d-morrison/ai-config`)

This repo pulls in [`d-morrison/ai-config`](https://github.com/d-morrison/ai-config) for portable skills and memories via the **Plugin Marketplace**.

**Local / after cloning:** the submodule is already registered in `.gitmodules`; initialize it with:
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
- Gemini skills live in `.gemini/skills/` (including `verify-via-state-dump`).

## Verify before you push
Run `tools/check.sh` to reproduce CI's gating checks locally (Godot import validation + GUT unit suite + the docs char-check; `tools/check.sh all` adds the lychee link-check). It vendors GUT on demand and needs only a Godot 4.7 binary on `PATH` (or `GODOT_BIN`). See `tools/README.md`. Prefer it over invoking individual checks by hand so local and CI results stay in sync.

When the diff touches `scripts/`, also run `patch_coverage` before pushing — a local approximation of the `codecov/patch` CI check, verified to match Codecov's own numbers. Add it to the same `tools/check.sh` invocation (e.g. `tools/check.sh validate test chars comments units patch_coverage`), not a separate command afterward.

## Gameplay demos in PRs
Every PR that changes the user experience (UI elements, HUD overlays, unit cards, battle maneuvers, visual presentation, controls, or settings affecting display) MUST include a recorded gameplay demo:
- Commit a **`demos/demo.json`** pointing to a scripted-input recording (`demos/inputs/*.json`) with the `input` field so CI records a clip and embeds it in the PR description.
- Never use `"skip": true` with excuses to avoid authoring demos for user-visible UX changes.
- Check every new demo against the standard defect checklist in `.gemini/skills/verify-via-state-dump/SKILL.md` (or `.claude/skills/verify-via-state-dump/SKILL.md`).

## Code conventions

### Parameters are caller-configurable; only real physical constants are fixed
Any parameter value a caller could reasonably want to vary — sizes, counts, layouts, spawn geometry, timings, gameplay thresholds — enters through a function parameter, a constructor/instance field, or a data file, with today's value as the default. Never a bare literal buried in the implementation.

### Comments: no issue-number references
Don't cite issue numbers (`#123`) in code comments. The explanation itself should stand on its own. Issue numbers belong in commit messages, PR descriptions, and `TODO`/`FIXME` comments.

### Units: author in metres, store in world units, display in metric
See `docs/units-convention.md` for full rules. Author length/speed constants as `<metres> * WorldScaleRef.WU_PER_M`, keep runtime state in world units, and render user-facing distances through `DistanceLegend`.

### GDScript / Godot 4 quirks
- `PopupMenu.set_item_metadata` takes an index, not an id. Convert with `popup.get_item_index(id)`.
- `set_deferred("position:y", ...)` is a silent no-op. Defer the full Vector2: `set_deferred("position", Vector2(x, new_y))`.
- Commit `.gd.uid` sidecars alongside every new `.gd` script.
- Run `godot --headless --import` after adding new `class_name` declarations so global classes register before running GUT unit tests.

## Code review handling policy
1. **In scope + confident + small** → fix on PR branch, commit, push.
2. **Ambiguous or architecturally significant** → ask user before acting.
3. **Out of scope** → create GitHub issue to track it and reply with a link to the issue.
