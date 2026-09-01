# Design note: Historical deployment distances, far-tier openings, and paced advances

Status: **design drafted** -- establishes architectural and historical grounding for deep battlefield deployments, seamless far-tier opening transitions, and multi-phase AI advance pacing.
Builds on [#957](https://github.com/Lacaedemon/sparta/issues/957) and extends [#945](https://github.com/Lacaedemon/sparta/issues/945) and [#550](https://github.com/Lacaedemon/sparta/issues/550).

## Historical background

Historical Mediterranean armies did not spawn within stone-throwing distance of one another:

- **Deployment Separation**:
  Ancient armies typically drew up their battle lines at distances of 200 to 800 metres (well out of missile range), allowing commanders to survey enemy disposition, dress their lines, and give final pre-battle harangues.
  Polybius documents Cannae and Zama opening with deliberate separations that took minutes to traverse.
- **Paced and Phased Advance**:
  Phalanxes and legions did not sprint across hundreds of metres.
  They maintained a steady, measured march to prevent disordered gaps from tearing open the line (Thucydides 5.70 at Mantinea).
  Only in the final 50 to 100 metres did the front ranks raise the war cry (*barritus* / *alalagmos*) and accelerate to charge velocity to maximize impact momentum while conserving vital breath for melee.
- **Skirmisher Screening**:
  The opening minutes were dominated by light troops (*velites*, *psiloi*, *peltasts*) contesting the space between armies before retreating through gaps as the main lines met.

## Core Architecture and Mechanics

### 1. Far-Tier Battle Openings

- When armies spawn at historical deployment distances (exceeding `FormationTier.DEMOTE_RANGE = 600`), units spawn directly in `FormationTier.FAR`.
- Aggregate bounding boxes and coarse position vectors represent formations during the initial approach, minimizing CPU simulation overhead during the non-combat march.
- As formations approach within `FormationTier.PROMOTE_RANGE = 400`, the promotion pipeline reconstructs individual soldier slots smoothly without visual pop-in or collision impulses.

### 2. Multi-Phase AI Advance Pacing

The battle AI (`scripts/BattleAI.gd`) coordinates the army advance through three distinct distance-based phases:

- **Approach Phase (Distance > 150m)**:
  Main battle line advances at steady march pace (`Unit.default_speed`), maintaining formation alignment with adjacent wings.
- **Skirmish & Missile Phase (Distance 50m - 150m)**:
  Skirmishers deploy ahead to trade missile volleys while heavy infantry dresses its ranks and readies weapons (e.g. javelin throw or spear bracing).
- **Charge & Shock Phase (Distance < 50m)**:
  Frontline regiments initiate charge sprint, expending stamina for physical collision momentum and impact penetration.

### 3. Pre-Battle Setup Options

- In `scripts/PrebattleScreen.gd`, players can select between:
  1. *Immediate Contact* (~30m gap, instant action).
  2. *Standard Deployment* (~60m gap, short approach).
  3. *Historical Distance* (~200m+ gap, full far-tier approach and skirmish phase).

## Implementation Roadmap

1. **Phase 1 (Design & Architecture)**:
   Document architectural requirements in `docs/deployment-distance-design.md` (this document).

2. **Phase 2 (Far-Tier Opening Initialization)**:
   Support spawning units directly into `FormationTier.FAR` when scenario deployment distance exceeds `DEMOTE_RANGE`.

3. **Phase 3 (BattleAI Advance Pacing)**:
   Implement phased march, skirmish screening, and terminal charge triggers in `scripts/BattleAI.gd`.

4. **Phase 4 (Prebattle UI Distance Selector)**:
   Add deployment distance presets to `scripts/PrebattleScreen.gd` and `scripts/CustomMatchup.gd`.
