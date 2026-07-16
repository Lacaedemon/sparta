extends GutTest
## WorldScale.gd is the single source of truth for the sim's world-units-per-metre
## scale; Battle.WORLD_UNITS_PER_METER re-exports it so existing consumers compile
## unmodified. These pins are exact (assert_eq, never assert_almost_eq): the whole
## metric-definition plan rests on conversions being bit-identical, so a drifted
## value must fail loudly, not round away.

const WorldScaleRef = preload("res://scripts/WorldScale.gd")
const BattleScript = preload("res://scripts/Battle.gd")


func test_world_scale_value_is_pinned_exactly() -> void:
	assert_eq(WorldScaleRef.WU_PER_M, 20.0,
		"the world scale is 20 wu/m; changing it rescales every physical constant and is a sim-wide balance change")


func test_battle_re_export_matches_world_scale_exactly() -> void:
	assert_eq(BattleScript.WORLD_UNITS_PER_METER, WorldScaleRef.WU_PER_M,
		"Battle's legacy name re-exports WorldScale's value; they must never diverge")


func test_inverse_round_trips_exactly() -> void:
	assert_eq(WorldScaleRef.WU_PER_M * WorldScaleRef.M_PER_WU, 1.0,
		"the product of 20.0 and fl(1/20.0) rounds back to exactly 1.0 in float64, so the round trip is exact -- pinned so a scale change that breaks this exactness fails loudly")
