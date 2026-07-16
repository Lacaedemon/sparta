class_name Armor
extends Resource
## A concrete armor TYPE: the fixed stats every soldier wearing this panoply
## shares. Shared and interned — LoadoutRegistry holds one instance per type,
## referenced by id from Unit.armor_type_id — so an armor object is never
## allocated per soldier and never mutated after the registry builds it, the
## same contract Weapon and Shield already keep.
## See docs/soldier-loadout-design.md.

@export var id: int
@export var display_name: String
# Protection in [0, 1]: the fraction of a landed blow's wound the panoply
# absorbs. This is the SAME scalar SoldierCombat.profile_for()'s rows carried
# as hard-coded "armour" literals before the registry existed —
# profile_for reads it through the unit's armor id, so combat outcomes are
# unchanged for the default roster.
@export var protection: float
# Panoply weight in kilograms. Provisional shape data, like Shield.arc_deg:
# nothing reads it for gameplay yet. The loadout table's gait speeds already
# encode panoply weight by hand (heavier kit costs proportionally more at a
# run than at a walk — see Battle._default_loadout's own comment); once a
# future pass derives those speeds instead of authoring them, this is the
# number it starts from.
@export var weight_kg: float


## Build one interned type instance. Registry construction only — everything
## else reads shared instances through LoadoutRegistry.armor(id).
static func make(p_id: int, p_name: String, p_protection: float, p_weight_kg: float) -> Armor:
	var a := Armor.new()
	a.id = p_id
	a.display_name = p_name
	a.protection = p_protection
	a.weight_kg = p_weight_kg
	return a
