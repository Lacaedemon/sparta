extends GutTest
## Battle AI phase 3 (docs/battle-ai-design.md): DoctrineRegistry.parse_doctrine() validation/
## conversion in isolation, plus a load of the two real profile files this phase ships
## (data/doctrines/aggressive.json, cautious.json). A malformed profile returns {} (empty) so
## the caller (General.decide_army) falls back to phase 2's own single-group behaviour.

const DoctrineRegistryScript = preload("res://scripts/DoctrineRegistry.gd")


func _valid_raw() -> Dictionary:
	return {
		"name": "Test Doctrine",
		"plans": ["advance_line", "envelop"],
		"envelop_ratio_threshold": 1.0,
		"reserve_fraction": 0.25,
		"reserve_commit_morale_threshold": 50.0,
		"pursue_routers": true,
	}


func test_parse_valid_doctrine() -> void:
	var d := DoctrineRegistryScript.parse_doctrine(_valid_raw())
	assert_false(d.is_empty(), "a well-formed doctrine parses")
	assert_eq(d["name"], "Test Doctrine")
	assert_eq(d["plans"], ["advance_line", "envelop"] as Array[String])
	assert_almost_eq(float(d["envelop_ratio_threshold"]), 1.0, 0.001)
	assert_almost_eq(float(d["reserve_fraction"]), 0.25, 0.001)
	assert_almost_eq(float(d["reserve_commit_morale_threshold"]), 50.0, 0.001)
	assert_true(d["pursue_routers"])


func test_reserve_fraction_is_clamped_to_0_1() -> void:
	var raw := _valid_raw()
	raw["reserve_fraction"] = 1.5
	var d := DoctrineRegistryScript.parse_doctrine(raw)
	assert_almost_eq(float(d["reserve_fraction"]), 1.0, 0.001, "clamped to the 0..1 range")

	raw["reserve_fraction"] = -0.5
	d = DoctrineRegistryScript.parse_doctrine(raw)
	assert_almost_eq(float(d["reserve_fraction"]), 0.0, 0.001)


func test_rejects_missing_required_key() -> void:
	for key in DoctrineRegistryScript.REQUIRED_KEYS:
		var raw := _valid_raw()
		raw.erase(key)
		assert_true(DoctrineRegistryScript.parse_doctrine(raw).is_empty(),
			"missing '%s' -> rejected" % key)


func test_rejects_empty_plans() -> void:
	var raw := _valid_raw()
	raw["plans"] = []
	assert_true(DoctrineRegistryScript.parse_doctrine(raw).is_empty(), "no plans -> rejected")


func test_rejects_non_array_plans() -> void:
	var raw := _valid_raw()
	raw["plans"] = "envelop"
	assert_true(DoctrineRegistryScript.parse_doctrine(raw).is_empty(),
		"'plans' must be an array, not a bare string")


func test_load_doctrine_missing_file_returns_empty() -> void:
	var d := DoctrineRegistryScript.load_doctrine("res://data/doctrines/does_not_exist.json")
	assert_true(d.is_empty())


# --- the two real shipped profiles ------------------------------------------------------

func test_aggressive_profile_loads_and_favors_committing_early() -> void:
	var d := DoctrineRegistryScript.doctrine("aggressive")
	assert_false(d.is_empty(), "data/doctrines/aggressive.json parses")
	assert_true(d["pursue_routers"], "aggressive doctrine chases down routers")


func test_cautious_profile_loads_and_favors_holding_reserves() -> void:
	var d := DoctrineRegistryScript.doctrine("cautious")
	assert_false(d.is_empty(), "data/doctrines/cautious.json parses")
	assert_false(d["pursue_routers"], "cautious doctrine holds the line instead of pursuing")


func test_the_two_shipped_profiles_have_genuinely_different_parameters() -> void:
	# The whole point of two profiles: they must differ on more than just their name, or
	# there is nothing for "two doctrines produce visibly different behavior" to demonstrate.
	var aggressive := DoctrineRegistryScript.doctrine("aggressive")
	var cautious := DoctrineRegistryScript.doctrine("cautious")
	assert_ne(aggressive["envelop_ratio_threshold"], cautious["envelop_ratio_threshold"])
	assert_ne(aggressive["reserve_fraction"], cautious["reserve_fraction"])
	assert_ne(aggressive["reserve_commit_morale_threshold"], cautious["reserve_commit_morale_threshold"])
	assert_ne(aggressive["pursue_routers"], cautious["pursue_routers"])


func test_doctrine_ids_lists_both_shipped_profiles() -> void:
	var ids := DoctrineRegistryScript.doctrine_ids()
	assert_true(ids.has("aggressive"))
	assert_true(ids.has("cautious"))
