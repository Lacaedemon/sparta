# Design note: chain-of-command battle AI

Status: **design — not yet implemented.** This note consolidates #498 (the
battle half of #387) into one spec, following the same design-doc-first
pattern as #516 (`docs/orders-queue-design.md`), #535
(`docs/soldier-loadout-design.md`), and #550
(`docs/large-scale-simulation-design.md`). It lays out the model and the
phased plan tracked by the phase issues linked below
([#584](https://github.com/Lacaedemon/sparta/issues/584)–[#588](https://github.com/Lacaedemon/sparta/issues/588),
sub-issues of #498).

The goal, per #498: a **chain of command** — a general who orchestrates army
movements through subcommander AIs assigned control of unit groups, with
possibly multiple hierarchical levels of subcommanders, down to single-unit
leaders who make small-scale tactical decisions. Suggestions and requests flow
**up** the chain; orders flow **down** it; no level controls a peer. Factions
at different time periods can have different command structures, and the
player can tap in by assigning their own unit groups to AI subcommanders with
period-flavored rank names (a Marian-era Roman army has centurions).

## Motivation

### Today's AI is a backdoor

The entire battle AI is one function: `Battle._run_enemy_ai()`, run every
`ai_period` ticks (default `AI_PERIOD` = 60 — once per second at
`Replay.PHYSICS_TPS` 60). Each idle enemy unit finds the nearest player unit
and takes it as a target by writing the unit's state directly:

```gdscript
# scripts/Battle.gd, _run_enemy_ai() — the line phase 1 replaces
u.target_enemy = nearest
```

That direct write bypasses the entire order pipeline. No `Order` is
constructed, nothing enters the unit's `orders` queue, `current_order` stays
empty, and the state transcript (#500/#501) records no decision — an
AI-driven unit's transcript shows *effects* (state flips to FIGHTING) with no
visible cause. The player has no equivalent gesture: a player attack order
goes through `Battle.enqueue_order` → `Battle._apply_order_cmd` and lands in
the queue; the AI's "order" is a private field write the queue never sees.

This violates the **compositionality pillar** (`PLAN.md`, pillar 3) directly:
the orders queue exists precisely so that every command — whoever issues it —
is one legible, composable `Order` on one apply path. An AI that mutates unit
state behind the queue's back is a second, hidden command channel. The first
job of this design is to close it.

What today's AI does right is worth naming, because the design keeps all of
it: it runs on a fixed tick cadence (`_tick % ai_period == 0`), it is a pure
function of sim state with no RNG and no wall-clock, and playback **re-runs
it** rather than recording it — per the comment at its call site: "Enemy AI is
part of the deterministic sim (not player input): re-run it on the same
cadence during playback so it reaches the same decisions." Those three
properties (tick cadence, purity, re-derivation on replay) are the
determinism contract below, inherited rather than invented.

### What the orders-queue migration enables

The orders-queue design (#516) is what makes an orders-only AI practical.
Phase 1 of that design is merged (PR #555): the `Order` value type
(`scripts/Order.gd`) exists with types `MOVE` / `ATTACK` / `RELIEF` /
`SUPPORT` / `WHEEL` / `NUDGE` / `FORMATION` / `FRONTAGE`, every unit carries
an `orders` queue with a transcript-visible `current_order`, and
`Battle._apply_order_cmd` is the single exactly-once apply site. Phases 2–3
(#523 / #524, in flight) migrate execution itself onto the queue.

Once that lands, "the AI issues real orders" stops being aspirational: an AI
attack decision becomes `Order.new_attack(uid)` on the same apply path as a
player click, and the transcript shows it as `current_order: ATTACK` exactly
as it would for the player. AI behavior becomes verifiable by the same state
dumps (`verify-via-state-dump`) used for everything else — a reviewer can read
*what the AI decided* per tick, not just infer it from motion.

### Why a hierarchy, not a smarter monolith

A single "army brain" that computes every unit's move each tick is the
top-down heuristic the **bottom-up emergence pillar** (`PLAN.md`, pillar 2)
tells us to avoid: it approximates coordinated behavior with an omniscient
script instead of letting coordination emerge from local rules. The chain of
command puts each decision at the organizational level where the information
naturally lives — a unit leader sees the cavalry bearing down on its own
flank; a subcommander sees its group's line bowing; a general sees the
reserve pool and the enemy's committed weight. Army-level behavior (a line
that advances together, a flank that gets refused, reserves that arrive where
they're needed) should **emerge** from those local decisions composing, the
same way formation shape now emerges from per-soldier physics.

## The model: a chain of command

Three roles form the baseline. The structure is recursive — a faction's
command profile can insert additional subcommander levels between the general
and the unit leaders (#498 explicitly wants multiple hierarchy levels), and a
small battle can run with a degenerate chain (a general directly commanding
unit leaders). Each role has one job at one scale:

### Unit leader (one per AI-controlled unit)

Executes the directive its superior gave it, and makes the small-scale
tactical calls that need no permission:

- **Face a flank threat** — an enemy closing on the unit's flank or rear gets
  a facing change (the professional maneuvers the game already has: wheel,
  quarter-turn, about-face) before it gets a charge into the unit's side.
- **Form anti-cavalry square** — cavalry closing on a spear unit triggers
  `Order.new_formation(Unit.FORMATION_SQUARE)` while there is still time to
  form it.
- **Call for relief when wavering** — a unit low on morale or stamina with a
  fresh ally behind it requests relief; the ally's leader (or the
  subcommander) answers with an `Order.Type.RELIEF` order.

This is where the core of #385 lands: *disciplined units use the implemented
professional battlefield maneuvers to execute orders*. The unit leader is the
decision-maker that picks the right maneuver for the situation and the unit's
discipline — a drilled unit wheels to face a threat in good order; a mob (per
#385's undisciplined-unit framing) just turns and walks. (#385's input-gesture
system — click count selecting pace — is player-facing UX, separate from this
design.)

### Subcommander (one per unit group)

Keeps its group fighting as a group:

- **Line integrity** — units in a advancing line hold alignment; no unit
  races ahead into an unsupported melee.
- **Mutual support** — an engaged unit's unengaged neighbor gets a directive
  to support (the queue already has `Order.Type.SUPPORT` for the actuation).
- **Flank coverage** — a group flank left open by casualties or maneuver gets
  refused or covered by a repositioned unit.

The subcommander interprets the general's plan for its group and translates
it into per-unit directives; it also aggregates its unit leaders' reports and
passes what matters upward (contact on the left, cavalry sighted, two units
wavering).

### General (one per AI army)

Owns the army-scale decisions, driven by a **doctrine profile** (data, below):

- **Army plan selection** — advance in line, refuse a flank, envelop, hold
  and skirmish; picked from the doctrine's plan set against what the
  general's perception shows.
- **Reserve commitment** — when and where the uncommitted units go.
- **Rout exploitation** — a breaking enemy unit draws pursuit or a
  follow-through into the gap, per doctrine (a cautious doctrine holds the
  line instead).

### Orders flow down; suggestions flow up

The contract between levels, in both directions:

- **Down: directives.** Each level issues directives to the level directly
  below — the general to subcommanders ("your group advances on the left"),
  subcommanders to unit leaders ("hold this line segment; support the unit on
  your right"). A directive states intent at the subordinate's scale and
  leaves execution to the subordinate. Only the **bottom** level actuates:
  unit leaders turn directives into real `Order`s on the unit's queue. Higher
  levels never write unit state and never place orders on a unit's queue
  directly — a directive to a subordinate AI is data between commanders, not
  actuation.
- **Up: suggestions and requests.** A unit leader reports state and asks for
  what it can't do alone ("wavering, request relief", "cavalry on my flank");
  a subcommander requests reserves or reports its group's situation.
  Suggestions are advisory data — the superior weighs them; nothing about a
  request compels the parent, and (per #498) no level controls a peer.
- **Local autonomy within intent.** A subordinate executes its directive by
  its own local decisions — which maneuver, which target, which formation.
  This is the bottom-up pillar applied to command: the general's plan
  constrains, the unit leader's tactics decide.

### Orders-only actuation — no AI backdoors

The hard rule, restated as the design's first invariant: **every command
level acts on the game exclusively through the same `Order` objects, the same
queue, and the same apply path the player uses.** Concretely:

- A unit leader's decision becomes an `Order` (via the same constructors —
  `Order.new_attack`, `Order.new_move`, `Order.new_formation`, ...) applied
  through the single apply site (`Battle._apply_order_cmd` today; whatever
  the queue migration's final entry point is).
- Anything the AI can do, the player could do by hand with the same orders;
  anything the player can do, the AI does the same way. No AI-only order
  types with private semantics, no direct writes to `target_enemy`,
  `move_target`, formation fields, or any other unit state.
- The transcript therefore records AI intent for free: an AI-commanded unit's
  `current_order` is as legible as a player-commanded unit's, which is how
  every phase below gets verified.

**Replay handling: re-derive, don't record.** Player orders are recorded into
the replay stream (`Replay.record_order`) because they are outside the sim.
AI orders stay *inside* the sim, as today: playback re-runs the AI on the
same cadence and — because the AI is deterministic (below) — it reaches the
same decisions and issues the same orders. This keeps replay files small,
keeps the existing replay format unchanged, and makes determinism a tested
property rather than a hope (a replay diverges loudly if the AI ever stops
being pure). The one cost: the AI must never consume anything that isn't
serialized sim state — which the perception interface enforces structurally.

## Perception: every decision reads a view, not the world

Every AI decision, at every level, reads a **perception view** — "what this
commander can currently see and know" — never raw game state. This interface
exists from phase 1, day one, as the only door between AI code and the
battle.

**Requirement (owner decision): the AI honors fog of war.** When fog of war
lands (#414), the perception interface returns the *fogged* view to AI
commanders exactly as it does to the player — same visibility rules, same
information, no omniscient fallback, no cheating. The first implementation of
the interface is omniscient because fog of war does not exist yet; that
omniscience is a **placeholder implementation detail, not a design
property**. AI code written against the interface cannot tell the difference,
which is the point: phase 5 swaps the implementation and every commander at
every level starts fighting on partial information without a line of AI logic
changing.

A sketch of the shape — **design, not implementation**; names and signatures
are illustrative and will be settled in phase 1:

```gdscript
# DESIGN SKETCH — not implementation. The contract is the important part:
# AI code takes one of these as its only window onto the battle.
class_name CommanderView

## Units of `team` this commander can currently perceive. Omniscient
## implementation: all living units. Fogged implementation (phase 5):
## only units inside some friendly unit's perception.
func visible_units(team: int) -> Array

## Last known contact for a unit that has been seen before but is not
## visible now: position/facing/strength as of the tick it was last seen,
## plus that tick. Empty if never seen. (Only meaningful once fog of war
## exists; the omniscient implementation never needs it.)
func last_known(uid: int) -> Dictionary

## The commander's own command: always fully known, fog or no fog
## (a commander knows where its own units are and what state they're in).
func own_units() -> Array

## Reports and requests received from direct subordinates this decision
## tick — the up-flowing half of the command contract.
func reports() -> Array
```

Two boundaries the sketch bakes in:

- **Own-command knowledge is exempt from fog.** A commander always knows its
  own units' positions and states — fog of war governs knowledge of the
  *enemy* (and, once #414 defines it, possibly distant friendlies outside
  the command). The exact friendly-knowledge rule is #414's call; the
  interface just has to route whatever #414 decides.
- **Suggestions ride the same interface.** What a subordinate reported is
  part of what a commander "knows", so it lives in the view too — which
  means a fogged general can know about a flanking force *because a unit
  leader saw it and the report propagated*, which is exactly the historical
  texture the chain of command is for.

## Determinism rules

The battle AI is part of the deterministic sim, holding the same two
invariants as the orders-queue design (`docs/orders-queue-design.md`, "Two
invariants"). Concretely, every level of the chain obeys:

- **Tick cadence.** Decisions run on a fixed physics-tick cadence keyed off
  the existing `ai_period` (default 60 ticks — once per second at
  `Replay.PHYSICS_TPS` 60), exactly like `_run_enemy_ai()` today. Different
  levels may use different (fixed, serialized) cadences or offsets — a
  general deciding less often than a unit leader is fine, and staggering
  levels across ticks spreads the cost — but never a frame-rate-, render-, or
  wall-clock-dependent one.
- **Seeded randomness only.** Any stochastic choice (doctrine-weighted plan
  selection, a tie-break) draws from the one seeded RNG the whole simulation
  uses — `Replay.rng`, whose seed is set once per battle and which must never
  be reseeded or bypassed elsewhere (per `scripts/Replay.gd`'s own contract).
  Same battle seed → same rolls → same decisions.
- **Pure functions of serialized state.** A decision is a pure function of
  (perception view, doctrine data, seeded RNG state). The perception view is
  itself a pure function of serialized sim state — including the fogged
  implementation, whose visibility computation must also be deterministic.
  No reading the camera, the UI, node iteration order, or anything else that
  can differ across runs or machines.
- **Replays re-derive AI decisions** (see "re-derive, don't record" above),
  so replay validity is a standing regression test of all of the above.

These rules are also what keep the **lockstep-multiplayer door open** (#290):
a deterministic, seed-driven AI runs identically on every peer, so AI-driven
units need no network traffic beyond what player orders already need.

## Doctrine profiles are data; LLMs stay offline

**Doctrine profiles** are the data that makes one army fight differently from
another — per faction, per period (ties into #427, factions grouped by time
period). A profile carries, roughly:

- the **command structure** itself — how many subcommander levels, group
  sizes, and the **rank names** per level (#502: a Marian-era Roman army has
  centurions; phase 4 surfaces these to the player);
- the general's **plan set and weights** — which army plans this doctrine
  knows and favors, aggression/caution parameters, reserve-commitment
  thresholds;
- subcommander and unit-leader **tuning** — how tightly lines are held, when
  a unit leader calls for relief, formation preferences against which
  threats.

The runtime that consumes these profiles is **deterministic classical AI** —
utility scoring and doctrine-table lookups, evaluated under the determinism
rules above. Nothing heavier is needed: the decisions are discrete, the
inputs are small, and legibility ("why did it do that" must be answerable
from the transcript plus the profile) is a feature.

**LLMs are offline authoring tools, never runtime dependencies.** This is the
design's answer to #387's "use modern AI models if feasible": feasible, but
at authoring time. An LLM can draft doctrine profiles (plausible plan weights
for a given historical army), command personalities, and period flavor (rank
names, report phrasings) — a human reviews the output and it is committed as
plain data files the deterministic runtime reads like any other data. At
runtime there are no model calls, no network, no nondeterminism, no latency —
a battle behaves identically with the network cable pulled.

## Phase plan

Design only, right now — no implementation dispatched by this doc. Each phase
below is filed as its own tracking issue, linked from #498 and from here.
Every phase holds the two standing invariants: orders-only actuation, and
determinism on replay.

### Phase 1 — unit leaders replace `_run_enemy_ai` — [#584](https://github.com/Lacaedemon/sparta/issues/584)

**Scope.** Give every AI-controlled unit a unit leader that decides through
the perception interface (omniscient implementation) and acts only by issuing
real orders through the queue. Delete `Battle._run_enemy_ai()` and its direct
`target_enemy` write. First tactical repertoire: advance/attack (subsuming
today's nearest-enemy behavior), face a flank threat, form anti-cavalry
square when cavalry closes, call inter-unit relief when wavering (the core of
#385).

**Dependencies.** Orders-queue phases 2–3 (#523 / #524, in flight) — unit
leaders need orders that actually execute from the queue, not the phase-1
mirror.

**Acceptance criteria.** `_run_enemy_ai()` is gone; every AI decision is
visible in the transcript as a queue order on an AI unit (`current_order`
reads ATTACK / MOVE / FORMATION / RELIEF with the right targets); a
fixed-seed battle replays to identical AI orders tick-for-tick; the existing
enemy behavior (idle enemies advance on the nearest player unit) is preserved
or deliberately improved, with the change described.

**Showcase demo (one clip).** Enemy infantry advances in line toward the
player; enemy spearmen form square as player cavalry closes on them; a unit
whose flank the player threatens turns to face the threat. Three legible
behaviors, none of which today's AI can do, all issued as visible orders.

### Phase 2 — subcommanders: groups, line integrity, mutual support — [#585](https://github.com/Lacaedemon/sparta/issues/585)

**Scope.** Subcommander entities commanding unit groups: line-integrity
(aligned advance), mutual support (unengaged neighbor supports an engaged
unit), flank coverage (refuse or cover an open group flank). Directives down
to unit leaders; reports and requests up. Builds on the multi-unit maneuver
foundations (#369 friendly-target hook, #377 passage-of-lines relief, #378
reinforcement insertion, #379 echelon/oblique order) — the subcommander is
the first *caller* with the standing job of coordinating those maneuvers.

**Dependencies.** Phase 1 (#584).

**Acceptance criteria.** A grouped enemy line advances as a line (no unit
races ahead unsupported); an engaged unit's neighbor moves to support it; a
group reacts to an exposed flank; all of it deterministic on replay and
legible in the transcript as unit-leader-issued orders.

### Phase 3 — the general: doctrine, plans, reserves — [#586](https://github.com/Lacaedemon/sparta/issues/586)

**Scope.** The general and the doctrine-profile data format: army plan
selection from the profile's plan set, group assignment to subcommanders,
reserve commitment, rout exploitation. First doctrine profiles authored for
the existing roster (period flavor per #427's faction/period direction).

**Dependencies.** Phase 2 (#585).

**Acceptance criteria.** Two doctrine profiles produce visibly different army
behavior from the same battle seed; reserve commitment fires on legible
serialized-state conditions; profiles are data files a non-programmer could
edit; the full chain replays deterministically.

### Phase 4 — player delegation — [#587](https://github.com/Lacaedemon/sparta/issues/587)

**Scope.** The player taps into the same system (#135): assign player unit
groups to AI subcommanders, give group-level directives as the general, take
manual control back at any time. Rank names and flavor surface from the
doctrine profile (#502 — Roman officer ranks for a Roman-period army). A
manual player order to a delegated unit always wins over the subcommander's
directive (the player outranks the AI).

**Dependencies.** Phase 3 (#586) for doctrine-profile rank data; phase 2
machinery pointed at team 0.

**Acceptance criteria.** Delegation and un-delegation work mid-battle; a
delegated group's orders are structurally indistinguishable from hand-issued
ones in the transcript; period rank names render from the profile; a
delegated group in a replay behaves identically on re-run.

### Phase 5 — perception honors fog of war — [#588](https://github.com/Lacaedemon/sparta/issues/588)

**Scope.** Swap the omniscient placeholder implementation of the perception
interface for the fogged view, when fog of war (#414, battle side) lands.
Every command level reads the same fogged information the player gets;
subordinate reports become the way information legitimately travels up the
chain (a general reacts to a flanking force *because a unit saw it*).

**Dependencies.** Phase 1 (#584) for the interface; #414 for fog of war
itself. (Phases 2–4 don't gate this — the swap covers whatever levels exist
when it lands.)

**Acceptance criteria.** An explicit "AI honors fog of war" test: an AI
general cannot react to an unseen flanking force until it enters some
friendly unit's perception, and reacts on the first decision tick after it
does; no AI code path reads unfogged state (enforced by the interface being
the only door); determinism on replay is preserved with fog active.

## Non-goals

- **Campaign AI.** #387's campaign half is a separate epic with its own
  future design; nothing here addresses strategic-map decisions.
- **Runtime LLM calls.** Ruled out above; LLMs are offline authoring tools
  only.
- **Fog of war itself.** #414 owns visibility rules, rendering, and player
  UX; this design only consumes the resulting view through the perception
  interface.
- **Per-soldier AI.** The chain of command ends at the unit leader. Behavior
  below the unit — individual soldier motion, slot ownership, per-soldier
  orders — is #547's territory and unchanged here.
- **New order types.** The AI speaks the existing (and in-flight #516) order
  vocabulary. If a phase discovers a genuinely missing verb, that is an
  orders-queue change first, an AI change second.

## Open questions

- **Command-entity representation.** Nodes in the scene tree vs plain
  `RefCounted` objects owned by `Battle` — settle in phase 1 (lean: plain
  objects; commanders need no transform, no rendering, no tree lifecycle).
- **Chain latency.** Should a directive crossing a command level incur a
  delay? Units already model `order_response_delay` per order; a per-level
  lag (messenger time) would add historical texture and make deep hierarchies
  meaningfully slower than flat ones — but also complicates tuning. Defer to
  phase 2, default to no extra latency beyond the existing per-unit delay.
- **Group assignment dynamics.** Are unit groups fixed at spawn from the
  doctrine profile, or can the general re-group mid-battle (e.g. fold a
  mauled group into a neighbor)? Phase 3 decides; start static.
- **Commander casualties.** Can a general or subcommander be killed, and
  what does that do to the chain (promotion from below, a morale shock, a
  command vacuum)? Rich flavor, not scoped in any phase here — file when a
  phase wants it.
- **Difficulty knobs.** Player-facing difficulty should come from doctrine
  quality and doctrine parameters (a "poor commander" profile), never from
  letting the AI cheat perception or determinism. Named here so the cheap
  alternative stays off the table.

## Relationship to existing issues

- **#498** — this doc is its design deliverable; phases
  [#584](https://github.com/Lacaedemon/sparta/issues/584)–[#588](https://github.com/Lacaedemon/sparta/issues/588)
  are its tracked sub-issues. The epic stays open through implementation.
- **#387** — the battle half of "build battle and campaign AI"; the "modern
  AI models" question is answered by the offline-LLM stance above. Campaign
  AI remains for a later epic.
- **#385** — its core ("disciplined units use the implemented professional
  battlefield maneuvers to execute orders") lands in phase 1's unit leaders;
  its click-count pace-gesture system is separate player-input UX.
- **#523 / #524** — orders-queue phases 2–3, the gate for phase 1.
- **#369 / #377 / #378 / #379** — the multi-unit maneuver foundations phase
  2's subcommanders coordinate.
- **#427** — factions by time period; doctrine profiles (phase 3) are the AI
  side of that data.
- **#135 / #502** — player delegation and period rank names, phase 4.
- **#414** — fog of war; phase 5 integrates it through the perception
  interface, with the AI honoring it by requirement.
- **#290** — lockstep multiplayer; the determinism rules keep that door open.
- **#516** (`docs/orders-queue-design.md`) — the actuation layer this whole
  design speaks through; its two invariants are inherited here.
- **#550** (`docs/large-scale-simulation-design.md`) — a far-tier formation
  still receives queue orders at unit granularity, so the chain of command
  works unchanged across simulation tiers.
