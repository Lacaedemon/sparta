class_name OfficerRank
## Cosmetic officer-rank labeling for a unit's commander, using real Roman military
## rank names as flavor text (see https://en.wikipedia.org/wiki/Centurion#Hierarchy).
## Purely informational: it reads a unit's type/size and returns a display string --
## nothing here writes back into the simulation or changes combat/movement behavior.
## Shown in the HUD's selected-unit info panel (see HUD.gd -> show_unit).
##
## Scope: every regiment in this game is already century-to-cohort sized (80-140
## soldiers), so rather than model the full legion chain of command (tribunes,
## legates, the legion-wide primus pilus) this picks ONE title per unit from the
## centurion tier -- the officer who would actually command a body of this size --
## varying it by troop type the way the historical centuriate did: foot centurions,
## a decurion for cavalry (a Roman cavalry troop/turma was led by a decurion, not a
## centurion). A larger, more prestigious foot unit gets the more senior centurion
## title (primus pilus tier) purely as size-based flavor -- no gameplay effect.


## Soldier-count threshold at/above which a foot (non-cavalry) unit's officer is
## styled as the senior "first cohort" grade (primus pilus / primi ordines) rather
## than an ordinary centurion. Chosen so only the largest lines earn the senior
## title -- the default loadout's 140-strong spearmen line qualifies, its
## 120-strong infantry does not.
const SENIOR_CENTURION_THRESHOLD := 130


## The officer-rank title for `u`'s commander -- pure function of the unit's type
## flags and max_soldiers (its intended full strength, not its current casualty-
## reduced soldiers, so the title doesn't change as the unit takes losses).
static func title_for(u: Unit) -> String:
	if u.is_cavalry:
		return "Decurion"
	if u.is_ranged:
		return "Centurion (Sagittariorum)"
	if u.max_soldiers >= SENIOR_CENTURION_THRESHOLD:
		return "Primus Pilus" if u.anti_cavalry else "Pilus Prior"
	return "Centurion"
