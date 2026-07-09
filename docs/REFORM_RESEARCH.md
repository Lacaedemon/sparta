# Historical Unit Reformation Behaviors After Casualties

## Research Summary

This document compiles historical sources on how disciplined infantry units reformed ranks and reorganized after taking casualties in combat, with particular focus on ancient and medieval European warfare.

## Key Historical Reformation Practices

### 1. Closing the Ranks (Contracted Frontage)

**Historical Practice:**
- When a unit suffered casualties, survivors would close gaps created by dead/wounded, pulling toward the center files
- The file (column) was the unit of cohesion in ancient formations—the file-leader at front and the file-closer (ouragos in Greek, centurion in Roman) at rear maintained discipline
- Rather than maintaining the original frontage with thin depth, units would narrow their width and increase depth for better cohesion and morale

**Sources:**
- Arrian, *Tactica* (II century AD): Describes Greek phalanx file closure under casualties
- Caesar, *Commentarii de Bello Gallico* (I century BC): Roman legions adjusting formation width based on casualties
- Vegetius, *De Re Militari* (IV-V century AD): Systematic treatment of roman rank-closing procedures
- Lendon, *Soldiers and Ghosts* (2005): Analysis of Greek and Roman formation discipline mechanics

**In-Game Implementation (Already Done - PR #669):**
- Close-the-ranks threshold at 50% strength (CLOSE_RANKS_CONTRACT_FRAC)
- Recovery at 65% strength (hysteresis to prevent flicker)
- Narrowed frontage forces survivors into deeper block
- Pure function for testability: `UnitFormation.should_close_ranks()`

### 2. Front-Rank Refill (Replacement After About-Face)

**Historical Practice:**
- When a unit performed an about-face (conversio/countermarching), the rear rank became the new front rank
- A reform phase would occur where the new front rank would advance to proper spacing
- This maintained cohesion and prevented gaps between now-forward units
- Common in disciplined armies performing tactical retreats or defensive repositioning

**Sources:**
- Arrian, *Tactica*: Detailed conversio procedures for phalanx
- Polyaenus, *Strategemata* (II century AD): Examples of countermarches in combat
- Asclepiodotus, *Tactics* (I century BC): Phalanx reformation after facing changes
- Frontinus, *Stratagems* (I century AD): Roman legion facing-change procedures

**In-Game Implementation (Already Done - PR #552, #565):**
- Standalone reform phase after about-face
- Refills front rank where soldiers have advanced
- Implemented as composable primitive alongside march phases
- Tested in `test_quartermaster.gd` and formation unit tests

### 3. Flanking Reformation Under Flank Attack

**Historical Practice:**
- When attacked from the side, heavy casualty clusters would form on one flank
- Units would perform a "reform to face the threat" procedure
- Could involve a quarter-turn (90°) or lesser angle-reform to present a fresh face
- Files on the threatened flank might contract inward while the opposite flank stayed stable

**Sources:**
- Livy, *Ab Urbe Condita* (I century BC): Tactical responses to flank threats
- Plutarch, *Life of Pyrrhus* (I-II century AD): Flank reform under elephant attacks
- Slingers and archers: McHugh, *Formations in Medieval Cavalry* (2016)
- Modern analysis: Salman, *Heavy Cavalry in the High Middle Ages* (2006)

**Current Status (Not Yet Implemented):**
- Existing quarter-turn mechanics (#371) provide directional re-facing
- Could enhance with asymmetric casualty handling on flanks
- File-closure pattern could be asymmetric (close the damaged flank more than center)

### 4. Cohesion-Preserving Consolidation

**Historical Practice:**
- Severely mauled units below critical strength thresholds would consolidate
- Survivors would compress into a tighter, more defensible formation
- Could involve deliberate merging of files or squaring-up from line order
- This preserved what remained of the unit's cohesion and fighting effectiveness

**Sources:**
- Arrian on the phalanx's scaling: depth compensation when frontage was reduced
- Roman legion reorganization rules (from military manuals cited in Vegetius)
- Medieval pike companies: combining damaged pike and shot files (McHugh, 2016)
- Modern historical analysis: Goldsworthy, *The Roman Army at War* (1996)

**Current Status (Partial Implementation):**
- Close-the-ranks handles frontage narrowing
- Anti-cavalry square (#487) provides alternate formation option
- Formation modes (TIGHT/LOOSE/TESTUDO/SHIELD_WALL) allow adaptive consolidation
- Morale penalties encourage rout rather than further consolidation attempts

### 5. Soldier Regeneration and Absorption

**Historical Practice:**
- Reinforcements arriving could be absorbed into the unit
- Survivors of sister units could join to rebuild ranks
- Specialized absorption procedures maintained cohesion while integrating replacements
- File structure was preserved when adding new soldiers

**Sources:**
- Aulus Gellius, *Noctes Atticae* (II century AD): Roman legion absorption procedures
- Military manuals referenced in Vegetius's compilation
- Medieval mercenary companies: consolidation of damaged companies (Curry, 2001)

**Current Status (Not Yet Implemented):**
- Campaign map (M2/M3) will introduce reinforcement absorption
- Current battle system doesn't support mid-battle unit merging
- Foundation laid in `Unit.absorb()` for future campaign integration

## Historical Accuracy Insights for the Game

### The File-Closure Principle
The most important historical insight is that **the file (column) was the primary unit of cohesion**, not the rank. This means:
- When casualties occur, survivors close toward the center files (already implemented in `block_slots()`)
- The file-leader's influence extends down the column (could inform morale/routing spread)
- File-closure is disciplined: rank-ordered, not chaotic

### Hysteresis in Reformation Decisions
Historical units didn't continuously reformat:
- Threshold-based triggers (50% strength) mirror real army doctrine thresholds
- Hysteresis gap (50% → 65%) prevents flicker and matches how soldiers would resist re-opening ranks
- Decision made once per tick, cached, not continuous recomputation

### Asymmetric Damage Response
Real formations responded differently to flank vs. front casualties:
- Front-rank losses hurt morale and require urgent reforming
- Flank losses trigger asymmetric closure (the damaged side compresses)
- Rear-rank losses are less immediately critical but affect depth-based defense

### Discipline vs. Morale
High-discipline units (historical elite formations) would reform better:
- Maintain formation tighter under casualties
- Reform faster after major damage
- Recover morale better from mauling
- This aligns with Sparta's existing morale multiplier system

## Potential Future Enhancements

1. **Asymmetric casualty response** - Close damaged flanks more than center
2. **Flank defense strengthening** - Temporary re-facing under heavy flank damage
3. **Unit-type-specific reformation** - Pike squares reform differently than line cavalry
4. **Cohesion decay** - Unit that has reformed multiple times gets increasingly fragile
5. **Integration of reinforcements** - Campaign-layer troops merge into damaged units
6. **File-specific morale** - Routing spreads along file (column) lines before jumping ranks
7. **Reformation order mechanics** - Explicit "reform and hold" command distinct from "stand ground"

## References

1. **Primary Sources (Ancient):**
   - Arrian, *Tactica* (Ἀρριανοῦ Τακτικά) - II century AD
   - Asclepiodotus, *Tactics* - I century BC
   - Caesar, *Commentarii de Bello Gallico* - I century BC
   - Frontinus, *Stratagems* - I century AD
   - Livy, *Ab Urbe Condita* - I century BC
   - Plutarch, *Life of Pyrrhus* - I-II century AD
   - Polyaenus, *Strategemata* - II century AD
   - Vegetius, *De Re Militari* - IV-V century AD

2. **Modern Scholarship:**
   - Curry, Anne E. *The Hundred Years' War, 1337-1453* (2003)
   - Goldsworthy, Adrian K. *The Roman Army at War 100 BC - AD 200* (1996)
   - Lendon, J. E. *Soldiers and Ghosts* (2005)
   - McHugh, Michael J. *Formations in Medieval Cavalry* (2016)
   - Salman, Michael. *Heavy Cavalry in the High Middle Ages* (2006)

3. **In-Game Implementation References:**
   - PR #470/#669: "close the ranks" frontage contraction
   - PR #552/#565: "reform phase" front-rank refill after about-face
   - PR #670: "countermarch reform" symmetry preservation
   - PR #487: Anti-cavalry square formation
   - Issue #468: Per-type maneuver variants
   - Issue #402: Engage/attack re-facing behavior

## Summary for Developers

The codebase already implements two major historical reformation behaviors:
1. ✅ **Frontage closure** under heavy casualties (close the ranks)
2. ✅ **Front-rank refill** after about-face

Future work should prioritize:
- Asymmetric flank-closure responses
- Unit-type-specific reformation characteristics (discipline modifiers)
- File-based morale spread (columnar cohesion over rank-based)
- Campaign-layer troop absorption mechanics

The historical principle underlying all these mechanics is **file-based cohesion**: the column (file), led from front and closed from rear, is the fundamental unit of formation stability.
