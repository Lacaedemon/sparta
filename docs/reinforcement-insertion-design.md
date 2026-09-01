# Design: reinforcement insertion (doubling by number)

Status: **design drafted** -- the maneuver is not implemented; this document is the implementation plan for it, phased so each slice ships as its own reviewable PR.
Builds on [#378](https://github.com/Lacaedemon/sparta/issues/378), [#362](https://github.com/Lacaedemon/sparta/issues/362), and [#369](https://github.com/Lacaedemon/sparta/issues/369), and connects to [#377](https://github.com/Lacaedemon/sparta/issues/377), [#373](https://github.com/Lacaedemon/sparta/issues/373), [#3](https://github.com/Lacaedemon/sparta/issues/3), [#1327](https://github.com/Lacaedemon/sparta/issues/1327), [`docs/historical-reshaping-maneuvers.md`](historical-reshaping-maneuvers.md), [`docs/unit-groups-grand-tactics-design.md`](unit-groups-grand-tactics-design.md), and [`docs/orders-queue-design.md`](orders-queue-design.md).

File, function, and field names below were read from `main` at commit `0bae0766` (2026-09-01); re-check them against the tree before wiring.

## The maneuver

Asclepiodotus separates two kinds of doubling.
Doubling *of place* keeps the headcount and spreads the same men over twice the ground, by opening the intervals or by a countermarch of the interjected men.
Doubling *of number* raises the headcount: "by length when we interject or insert between the original files other files of equal strength", and "by depth when we interject between the original ranks others of equal strength" (*Tactics* 10.17, Loeb translation; see Sources).
He also records the objection: "Some condemn such doublings, especially when the enemy is near" (10.20), and prefers to fake the widening by extending the light infantry and cavalry on the wings rather than disturb the phalanx.

Sparta already has doubling of place: the file-doubling drills (explicatio and duplicatio) and the density cycle reshape one regiment's own men.
This document designs doubling of number: a fresh reserve regiment marches up behind a line regiment, and its men are interjected into that regiment's files or ranks, so the line's headcount rises while the existing men keep their places relative to one another.

A note on the citation: the tracking issue names chapter 4, which in the Loeb numbering covers the intervals between soldiers; the doubling passage is chapter 10, the same chapter the file-doubling and countermarch work cites.

## What exists today, and the gap

Three neighbours already cover parts of this ground.

| Feature | Headcount | Bodies move | When |
| --- | --- | --- | --- |
| Merge (`M`; `Battle._apply_merge` -> `Unit.absorb`) | pooled into the primary | no: the absorbed regiment is removed, and the primary's body layer seeds the extra tail bodies directly on their slots at rest (`SoldierBodies.step`'s resize path) | instantly, at issue |
| Line relief and passage of lines (`UnitRelief`; `Order.friendly_target`) | unchanged | yes: whole regiments pass through each other | when the fresh unit reaches the tired one |
| File doubling (`Battle.enqueue_file_double` -> `Unit.set_frontage`) | unchanged | yes: one regiment's own men reflow, easing onto the new slots at velocity | instantly, at issue |

Reinforcement insertion is the missing cell: the headcount grows *and* the newcomers arrive physically, walking into interleaved slots while the host's men side-step (files) or step back (ranks) to make room.
A merge drops the extra men straight onto the tail of the host's grid; a reserve inserted this way is instead visible marching up, and the host's grid visibly doubles.

## Player-facing behaviour

**Gesture.**
Select the reserve regiment, press `Shift+M` to arm insertion by files (or `Ctrl+Shift+M` for insertion by ranks), then right-click the friendly regiment to reinforce.
The arm is one-shot, like the `G` support arm: it applies to the next right-click on a friendly outside the selection, and it clears on `Esc` or on issue.
Today a right-click on a friendly outside the selection only targets it when that friendly is fighting (relief) or support is armed; with insertion armed, the click targets any live friendly, idle or engaged.

**Two axes.**

- *By files* (the default).
  The host's frontage grows by the inserted files, up to double; the host's own files spread apart, and each inserted file steps into a gap.
  The front rank does not move forward.
  This is the axis for an engaged line that needs to overlap the enemy.
- *By ranks*.
  The host's depth grows, up to double; each inserted rank steps in between two existing ranks.
  The front rank holds its ground, and the block grows rearward.
  This is the axis for a column before contact, for the push.

**Guards.**
The order is refused -- nothing is armed, and a HUD flash says why -- when:

- the two regiments are on different teams, or either is routing or dead;
- the reserve is itself in enemy contact (`Unit._in_enemy_contact`), since a body in a fight cannot file off to the rear;
- the loadouts differ (`weapon_type_id` or `shield_type_id`), because `Unit.combat_profile()` and `shield_rest_angle()` read per unit, so a mixed regiment cannot yet be represented (see Risks);
- the host is squared (`in_square()`) or in the far simulation tier (`tier == FormationTier.FAR`), since neither has a file-major grid to interleave into;
- the host reflows row-major (`_effective_file_major_reform()` false: cavalry, and undisciplined foot), for the same reason.

**Costs.**
The result starts at a cohesion floor and recovers at `COHESION_RECOVER_PER_SEC`, the same strangers debuff a merge pays; Asclepiodotus' objection above is the historical warrant for a debuff at all.
The floor is a per-unit field, `reinforce_cohesion_floor`, defaulting to a new `Unit.REINFORCE_COHESION_FLOOR` that is initialised to `MERGE_COHESION_FLOOR` until balance data says otherwise.
A host reshaped while moving faster than a walk pays the existing `_apply_moving_reshape_penalty`.
The host also grows: `max_soldiers` pools as in a merge, and `separation_radius` widens by the rule `absorb` already uses.

## Mechanics

Three stages, all deterministic from serialized state with no RNG, so live play and replay take one path.

### Stage A -- issue (`Battle._apply_order_cmd`)

The command carries `target` = the host's uid (a friendly outside `units`, exactly as a relief does) plus a new `reinforce` field: `Battle.ReinforceAxis.FILES` or `RANKS`, and absent or `NONE` on every other order.
In the friendly-target branch of `_apply_order_cmd`, ahead of the relief branches, a non-`NONE` axis dispatches to `UnitReinforce.begin(reserve, host, order)`, which:

1. installs `Order.new_reinforce(host.uid, axis)` as the reserve's current order (`Order.Type.REINFORCE`, appended after `SWITCH_WEAPON` so recorded transcripts keep every other type value stable);
2. arms `order.friendly_target = host`, which grants the pair the separation exemption `Unit._separation_exempt` already grants a relief pair, read from either side;
3. sets the reserve's `move_target` to the rendezvous point behind the host (Stage B) with `has_move_target = true`, and `ordered_facing = host.facing`, so the last leg is walked with the heading held the way a relieved unit backs out;
4. leaves the host untouched: no retreat order, no change to its `target_enemy`; its fight goes on.

The guards run here, on both units' live state, and a refused command applies nothing, so the reserve keeps whatever it was doing.

### Stage B -- approach (`UnitReinforce.update`, per tick)

Called from `Unit._physics_process` beside `UnitRelief.update`.
For a current `REINFORCE` order:

- if the host is gone (freed, dead, or routing), clear the link and retire the order where the reserve stands -- the same `gone` test `Order.resolve_friendly_target` makes;
- otherwise re-aim `move_target` at the rendezvous each tick, since a fighting host drifts;
- once the reserve's front edge is within one rank pitch of the host's rear edge, measured along `host.facing`, and the two headings agree within a tolerance, run Stage C.

The rendezvous point is `host.position - host.facing * (host_half_depth + reserve_half_depth + host.rank_pitch_wu())`, with both half-depths taken from the block half-extents the relief corridor already sizes off.
No new length constant is needed: the approach gap and the commit tolerance are both one rank pitch of the host, which is already metric-authored.

### Stage C -- commit (`UnitReinforce.commit`)

Runs once, inside the physics tick, and does five things in order.

1. **Interleave assignment** (`ReinforceLayout`, pure).
   Read the host's `_sim_soldier_file` and `_sim_soldier_rank`, its file count `F = UnitFormation.frontage(host)`, and its depth `D` (the largest file capacity).
   Deal the reserve's `R` bodies into the inserted files or ranks with the same `UnitFormation.deal_file_ids_by_lateral_order` and `deal_ranks_by_depth` the reshape path uses, so the leftmost reserve man takes the leftmost inserted file.
   Then remap the ids:
   - *Files.*
     `k = min(F, ceil(R / D))` files are inserted.
     Inserted file `j` (for `0 <= j < k`) goes immediately to the right of host file `h_j = floor((j + 0.5) * F / k)`, which spreads a partial reserve evenly and, at `k = F`, alternates strictly.
     Host file `f` becomes `f + |{j : h_j < f}|`, and inserted file `j` becomes `h_j + 1 + j`.
     With `k = F`, the host's men land on the even ids and the reserve on the odd ones.
     Ranks are unchanged; the new frontage is `F + k`.
   - *Ranks.*
     The reserve is dealt across the host's `F` files with `file_capacities(R, F)`.
     In a file holding `m` inserted men and `D_f` host men, host rank `r` becomes `r + min(r, m)`, and inserted man `i` becomes `2i + 1` while `i < D_f`, else `D_f + i`; ranks alternate for as long as both files last, and any surplus continues at the rear.
     The frontage is unchanged.

   `ReinforceLayout` returns the concatenated `file_ids` and `ranks`, the new file count, and the order in which the reserve's bodies are appended.

2. **Body transfer.**
   Append the reserve's per-soldier arrays onto the host's in that order.
   Both regiments' bodies are stored in their shared parent's frame (`_sim_soldier_pos` is built from `unit.position`, and both units are children of the battle scene), so positions concatenate without a transform.
   The arrays to carry, all index-aligned with `_sim_soldier_pos`: `_sim_body_vel`, `_sim_steer`, `_sim_soldier_hp`, `_sim_prone`, `_sim_soldier_stamina`, `_sim_soldier_broken`, `_sim_soldier_weapon_id`, `_sim_soldier_shield_id`, `_sim_soldier_shield_hold_angle`, `_sim_soldier_facing`, and the two render-only progress arrays.
   `_sim_soldier_square_slot` and `_sim_soldier_row_slot` stay empty, since a file-major host never holds them.
   This mirrors `SoldierMelee.reap` in reverse: reap trims every array at one index, and commit appends every array at the tail.

3. **Install the assignment** through a new `Unit.install_file_assignment(file_ids, ranks, files)` setter that writes `_sim_soldier_file`, `_sim_soldier_rank`, `_file_assignment_files`, and `frontage_override` together.
   Writing `_file_assignment_files` is what stops `_ensure_file_assignment` from re-dealing the files by lateral order on the next slot query and undoing the interleave; a frontage change is exactly the event that triggers that re-deal today, so bypassing it needs an explicit setter rather than a call to `set_frontage`.
   `_last_reshape_tick` and `_last_reshape_widened` are stamped as `set_frontage` stamps them, so the host reports `FILE_DOUBLE_WIDEN` on the commit tick in the transcript.

4. **Pool strength.**
   Split `Unit.absorb` into `pool_strength(other)` -- the strength-weighted attack, defense, morale, and fatigue blend, the `soldiers` and `max_soldiers` sums, the cohesion floor, and the separation-radius widening -- and its spatial finish (`set_formation(formation_mode)` and `_merged_away`).
   Commit calls `pool_strength` with the reinforcement floor, then removes the reserve with `_merged_away()`, and does *not* call `set_formation`, which would reset every shield hold angle the transfer just carried.
   `absorb` keeps its behaviour by calling the two halves in turn.

5. **Anchor the front (ranks axis only).**
   The slot grid is centred on `position` -- `SoldierBodies.couple` relies on `mean(slots) ~ position` -- so deepening from `D` to `D'` ranks would push the front rank forward by `(D' - D) / 2` rank pitches, into the enemy on an engaged host.
   Commit instead moves `host.position` rearward along `host.facing` by that amount: a one-time relocation of the anchor rather than a standing offset, so the coupling premise holds again from the next tick and the growth lands entirely at the rear.
   The files axis widens laterally about the same centre and needs no shift; a flank-held widen can reuse `frontage_anchor_offset` and `UnitFormation.anchor_shift` exactly as the anchored explicatio does.

After commit, the host's bodies ease onto their new slots at velocity through the ordinary arrival dynamics; nobody teleports.
The host's men side-step half a file pitch per inserted neighbour (files) or step back one pitch per inserted rank ahead of them (ranks), and the inserted men walk forward from the rear into their gaps.

### Retirement

`Unit._update_current_order` gains a `REINFORCE` branch: retire when `friendly_target == null` and no move is in flight.
A committed reserve is freed, so its order dies with it; a reserve whose host vanished mid-approach halts where it stands.

## Replay and transcript compatibility

- `Battle.enqueue_order` gains a `reinforce` argument, carried on the pending command and recorded through a new `reinforce: int = 0` parameter of `Replay.record_order`, omitted when zero -- the same omit-when-default rule `anchor_offset` follows -- so every existing replay stays valid and byte-identical on re-save.
- `Order.to_dict` and `from_dict` round-trip a new `reinforce_axis` field; `friendly_target` stays deliberately uncaptured, as its doc comment already explains.
- `Order.TYPE_NAMES` gains `REINFORCE`.
  `Unit.Maneuver` gains `REINFORCING`, appended last, and `current_maneuver()` reports it for the whole approach, the way `COUNTERMARCH` is reported for its composite; `tools/demo/DemoState.gd`'s maneuver name table gains the matching entry.
- The per-soldier id is `uid * SOLDIER_ID_STRIDE + index`, so transferred men re-key under the host's uid on the commit tick.
  The hash stream and a full state dump show that discontinuity at exactly one tick; it is expected, and the demo's caption should name it.

## Code touch-points

| File | Change |
| --- | --- |
| `scripts/ReinforceLayout.gd` (new, pure, under the 100-line new-file cap) | `interleave_files(...)`, `interleave_ranks(...)`, `rear_anchor_shift(old_ranks, new_ranks, rank_pitch)`; no scene-tree access, unit-testable like `UnitManeuver` |
| `scripts/UnitReinforce.gd` (new, static, under the cap) | `begin(reserve, host, order)`, `update(u)`, `commit(reserve, host)`, `rendezvous_point(host, reserve)`, `refusal_reason(reserve, host) -> String` (empty when allowed, else the text for the HUD flash) |
| `scripts/Order.gd` | `Type.REINFORCE` (appended), `reinforce_axis` field, `new_reinforce(host_uid, axis)`, `TYPE_NAMES`, `to_dict` / `from_dict` |
| `scripts/Battle.gd` | `enum ReinforceAxis { NONE, FILES, RANKS }`; `enqueue_order(..., reinforce)`; the record-time drain passes it to `Replay.record_order`; the friendly-target branch of `_apply_order_cmd` dispatches to `UnitReinforce.begin` |
| `scripts/Replay.gd` | `record_order(..., reinforce: int = 0)`, omitted when zero |
| `scripts/SelectionManager.gd` | `_armed_reinforce` one-shot arm on `Shift+M` and `Ctrl+Shift+M`; `_issue_order` targets any live friendly outside the selection while armed and passes the axis; `Esc` clears it |
| `scripts/Unit.gd` | `Maneuver.REINFORCING`; `current_maneuver()`; `order_summary()` ("Reinforcing %s"); `install_file_assignment(...)`; `absorb` split into `pool_strength` plus its spatial finish; `REINFORCE_COHESION_FLOOR` const and `reinforce_cohesion_floor` field; `UnitReinforce.update(self)` beside `UnitRelief.update(self)`; the `REINFORCE` retire branch |
| `scripts/ShortcutsOverlay.gd`, `scripts/HUD.gd` | shortcut rows, and the refusal flash |
| `tools/demo/DemoState.gd` | the maneuver name entry |
| `test/unit/...` | see Tests |
| `demos/inputs/reinforcement-insertion.json`, `demos/demo.<pr>.json` | see Demo |
| `website/how-to-play.qmd`, `website/tactics.qmd`, `website/tools/demo-catalog.sh` | see Website |

Both new scripts need their `.gd.uid` sidecars committed, generated by a headless import.

## Tests

- `test/unit/test_reinforce_layout.gd` (pure, no scene tree): the files axis at `k = F` (host on even ids, reserve on odd, ranks untouched); a partial reserve (`R < D` inserts one centred file); a surplus reserve (`k` capped at `F`, the inserted files deeper than the host's); the ranks axis full and partial (`r + min(r, m)` and `2i + 1`), and its surplus tail; `rear_anchor_shift`; and lateral order (the leftmost reserve body takes the leftmost inserted file).
- `test/unit/test_reinforcement_battle.gd` (an in-tree `Battle` in `drill_mode`, modelled on `test_passage_of_lines.gd`): a reserve behind a host receives a `REINFORCE` order with the link and the exemption armed and the host's own order untouched; stepping until commit leaves `host.soldiers` at the sum, the reserve out of the `units` group, every per-soldier array at the new size, `UnitFormation.frontage(host)` at `F + k`, the interleave pattern in `_sim_soldier_file` surviving a `formation_slots` query, `host.position` unchanged on the files axis, and the front-rank slot unchanged on the ranks axis; and each guard refuses (different loadout, routing host, engaged reserve, squared host).
- `test/unit/test_replay.gd`: `reinforce` round-trips when set and is omitted when zero, beside the existing `anchor_offset` cases.
- `test/unit/test_order.gd` and `test/unit/test_demo_state.gd`: the new type and maneuver names are added to the name-table tests there.
- `test/unit/test_lockstep_ab_sim_hash.gd`: one A/B run whose script commits an insertion, so the commit tick is proven deterministic.

## Demo

A scripted-input recording, `demos/inputs/reinforcement-insertion.json`, with `drill: true` and its own scenario: a 40-man `Infantry` host at about (600, 520) facing down and a 40-man `Infantry` reserve at about (600, 340) behind it, camera framed on the pair.
Steps: click the reserve, `Shift+M`, right-click the host; then a second pair to the right, showing the ranks axis with `Ctrl+Shift+M`.
`state` dumps before the approach, mid-approach, and after commit, with `expect` entries: the reserve's `maneuver` reads `REINFORCING` mid-approach; after commit the host's `soldiers` is 80 and its `frontage` has doubled (files pair) or held (ranks pair), and the reserve rows are gone.
Run the standard defect checklist on the dump; the commit tick needs a `path_crossing` exemption on the host uids, with the reason stated (the inserted men cross the host's rear rank by design).
The manifest must not point at this recording until Stage C is implemented; a design-only or layout-only PR ships a skip-form manifest.

## Website

- `website/how-to-play.qmd`: a controls row "Reinforce a friendly (doubling numbers)" beside "Merge selected units".
- `website/tactics.qmd`: a section after "Passage of lines" contrasting the three ways to combine regiments (merge, relief, insertion), the two axes, when to use each, and the cohesion cost, with a `{#fig-reinforcement-insertion .demo}` video div.
- `website/tools/demo-catalog.sh`: a `reinforcement_insertion|demos/inputs/reinforcement-insertion.json|30|300|640|input` row.

## Phases

1. **Design** -- this document (a docs-only PR with a skip-form manifest).
2. **Layout helper** -- `ReinforceLayout.gd` and `test_reinforce_layout.gd`; no behaviour changes, so the manifest is skip-form with that reason.
3. **The maneuver, files axis** -- `UnitReinforce.gd`, the order type, the replay field, the gesture, `install_file_assignment`, the `absorb` split, the battle tests, the demo, and the website updates, in one PR.
4. **Ranks axis** -- the rank interleave and the rear anchor, their tests, and the demo's second pair.
5. **Follow-ups**, each its own issue: subcommander reserve dispatch choosing insertion over relief for a host under half strength; hosts with a declared file-group subunit (Spearmen), where an inserted file should be a whole subunit column; far-tier hosts (promote, then insert); and a milder cohesion floor for a same-loadout insertion once balance data exists.

## Risks and open questions

- **The coupling premise.**
  `SoldierBodies.couple` skips coupling while a `frontage_anchor_offset` is in effect, precisely because a standing centroid offset confuses it.
  The rear anchor above is a one-time position move rather than a standing offset, but it needs a test that the host does not creep after commit.
- **The re-deal trap.**
  `_ensure_file_assignment` re-deals file ids from live positions whenever the file count changes; the interleave survives only if `_file_assignment_files` is written with it.
- **File-group subunits.**
  For a `FILE_GROUP` host, `UnitFormation.frontage` derives the width from `subunit_size` unless overridden, and `_ensure_file_assignment` reforms through `subunit_reform_files`; phase 3 sets the override explicitly and leaves subunit-aware insertion to a follow-up.
- **Mixed loadouts.**
  The per-soldier `weapon_id` and `shield_id` arrays could carry a mixed regiment, but `combat_profile()`, `shield_rest_angle()`, and the type-level stats read per unit; the same-loadout guard stays until those read per soldier.
- **Mid-fight commit.**
  Asclepiodotus' objection is real in the sim too: the host's rear ranks reshuffle while its front rank fights.
  The cohesion floor is the cost, and the files axis keeps the front rank's men on their slots.
- **Transcript discontinuity.**
  Soldier ids re-key at commit (above); the demo-diff and hash tooling read that as a change at one tick, which is correct.
- **Gesture.**
  `Shift+M` and `Ctrl+Shift+M` are unbound today: `M` merges, and the `Shift` and `Ctrl` chords `SelectionManager`'s key handler binds sit on `I`, `V`, `T`, `O`, `B`, `X`, `Y`, `Down`, and the control-group digits.
  Confirm against `KeybindingsDialog` when wiring.

## Sources

- Asclepiodotus, *Tactics*, chapter 10 ("The Terms in common Use for military Evolutions"), sections 17-20, in the Loeb translation by the Illinois Greek Club (1928), online at [LacusCurtius](https://penelope.uchicago.edu/Thayer/E/Roman/Texts/Asclepiodotus/10*.html).
  Chapter 4 of the same edition is "The Intervals between the Soldiers".
- Aelian's *Tactica* covers the same doublings; the file-doubling issue cites its chapters 29-30, and [`docs/historical-reshaping-maneuvers.md`](historical-reshaping-maneuvers.md) carries the wider background.
- Polybius VI on the manipular reserve lines, via [`docs/acies-triplex-design.md`](acies-triplex-design.md).
