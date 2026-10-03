extends GutTest
## Every Unit member variable is either captured by to_snapshot_dict() or deliberately left
## out of it, with the reason written down here. A new piece of sim state that nobody adds
## to the snapshot is otherwise silent: a replay seek or a rearguard clone restores the unit
## without it, the run diverges, and no test fails. With this test a new member forces a
## decision when it is added -- capture it, or list it below with the reason it needs no
## capturing.
##
## A member counts as captured when the snapshot carries it under its own name, under its
## name without the leading underscore (`_rout_timer` is saved as `rout_timer`), or, for a
## Unit reference, as `<name>_uid` (resolved after every unit is respawned).

## Reasons a member needs no capturing, by category.
const RENDER := "render-only state, rebuilt on the next draw like a freshly spawned unit's"
const CACHE := "a cache keyed to the current physics frame or slot layout, rebuilt on the next tick"
const COUNTER := "an instrumentation counter read only by tests and benchmarks"
const DERIVED := "re-derived on restore from fields the snapshot does carry"
const LINK := "a scene or UI link, not simulation state"

## Members deliberately not captured, each with its reason.
const EXCLUDED := {
	"current_order": DERIVED + " (always orders[0]; the orders queue is captured)",
	"file_major_reform": DERIVED + " (a bool view of file_major_reform_mode, which is captured)",
	"_cached_combat_profile": DERIVED + " (rebuilt by update_combat_profile)",
	"max_stamina": DERIVED + " (update_combat_profile reads it off the combat profile)",
	"auto_advance_on_detect": DERIVED + " (Battle._spawn_from_snapshot recomputes it from the team)",
	"incoming_friendly_links": DERIVED + " (each restored order's friendly_target setter recounts it)",
	"selected": LINK,
	"_owning_battle": LINK,
	"_formation_slots_call_count": COUNTER,
	"_relief_reverse_scan_count": COUNTER,
	"_adjacent_engaged_cache": CACHE,
	"_adjacent_engaged_cache_frame": CACHE,
	"_engaged_indices_cache": CACHE,
	"_engaged_indices_cache_frame": CACHE,
	"_engaged_indices_cache_count": CACHE,
	"_engaged_indices_cache_engaged": CACHE,
	"_step_slots_for_couple": CACHE,
	"_step_slots_for_couple_valid": CACHE,
	"_flock_color": RENDER,
	"_block_extent": RENDER,
	"_render_dirty": RENDER,
	"_render_last_facing": RENDER,
	"_render_alpha": RENDER,
	"_render_last_alpha": RENDER,
	"_render_extent_n": RENDER,
	"_render_extent_frontage": RENDER,
	"_render_extent_mode": RENDER,
	"_render_last_anchor_offset": RENDER,
	"_render_prone_progress": RENDER,
	"_prone_easing_active": RENDER,
	"_render_strike_progress": RENDER,
	"_strike_easing_active": RENDER,
	"_mm_body": RENDER,
	"_mm_outline": RENDER,
	"_mmi_body": RENDER,
	"_mmi_outline": RENDER,
	"_mm_facing_pip": RENDER,
	"_mmi_facing_pip": RENDER,
	"_facing_pip_mesh": RENDER,
	"_shadow": RENDER,
	"_mark_body_mesh": RENDER,
	"_mark_outline_mesh": RENDER,
	"_figure_body_mesh": RENDER,
	"_figure_outline_mesh": RENDER,
	"_figure_body_mesh_flip": RENDER,
	"_figure_outline_mesh_flip": RENDER,
	"_detailed_lod": RENDER,
	"_figure_faces_left": RENDER,
}

# Members the snapshot carries under a different key, because their raw value means
# nothing to a restore into another battle: an absolute engine frame travels as an age
# in ticks, the way the standoff and anchor-hold timers travel as remaining ticks.
const RENAMED := {
	"_engaged_target_reassign_frame": "engaged_target_pairing_age_ticks",
}


## The Unit script's own member variables (not Node's built-ins).
func _members(u: Unit) -> Array[String]:
	var out: Array[String] = []
	for p in u.get_script().get_script_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.append(String(p["name"]))
	return out


## Whether the snapshot carries `member` under one of the names it may be saved as.
func _captured(snapshot: Dictionary, member: String) -> bool:
	var bare: String = member.trim_prefix("_")
	if RENAMED.has(member) and snapshot.has(RENAMED[member]):
		return true
	return snapshot.has(member) or snapshot.has(bare) \
			or snapshot.has(member + "_uid") or snapshot.has(bare + "_uid")


func _spawned_unit() -> Unit:
	var u := Unit.new()
	u.max_soldiers = 20
	add_child_autofree(u)
	return u


func test_every_member_is_captured_or_excluded_with_a_reason() -> void:
	var u: Unit = _spawned_unit()
	await get_tree().physics_frame
	var snapshot: Dictionary = u.to_snapshot_dict()
	var unaccounted: Array[String] = []
	for m in _members(u):
		if not _captured(snapshot, m) and not EXCLUDED.has(m):
			unaccounted.append(m)
	assert_eq(unaccounted, [] as Array[String],
			"capture these in to_snapshot_dict() or add them to EXCLUDED with a reason: %s"
			% ", ".join(PackedStringArray(unaccounted)))


func test_every_exclusion_names_a_real_uncaptured_member() -> void:
	# A renamed or deleted member, or one that has since been captured, must leave the list,
	# or the list drifts into documenting fields that no longer exist.
	var u: Unit = _spawned_unit()
	await get_tree().physics_frame
	var snapshot: Dictionary = u.to_snapshot_dict()
	var members: Array[String] = _members(u)
	for m in EXCLUDED.keys():
		assert_true(members.has(m), "%s is listed but is not a Unit member" % m)
		assert_false(_captured(snapshot, m), "%s is listed but the snapshot captures it" % m)
	for m in RENAMED.keys():
		assert_true(members.has(m), "%s is renamed but is not a Unit member" % m)
		assert_true(snapshot.has(RENAMED[m]), "%s's renamed key %s is in the snapshot" % [m, RENAMED[m]])
		# A renamed key must be the member's own, not another member's saved name, or an
		# uncaptured member could be waved through by pointing it at any existing key.
		for other in members:
			if other == m:
				continue
			var other_bare: String = other.trim_prefix("_")
			assert_false(RENAMED[m] in [other, other_bare, other + "_uid", other_bare + "_uid"],
					"%s's renamed key %s is %s's own saved name" % [m, RENAMED[m], other])


func test_captured_names_resolve_without_the_underscore_or_as_a_uid() -> void:
	assert_true(_captured({"rout_timer": 0.0}, "_rout_timer"), "a private member saved without its underscore")
	assert_true(_captured({"target_enemy_uid": 3}, "target_enemy"), "a Unit reference saved as a uid")
	assert_false(_captured({"rout_timer": 0.0}, "_attack_cd"), "an unrelated key does not count")


## Keys to_snapshot_dict() writes that apply_snapshot_dict() does not read, with the reason;
## every other key it writes must be read back there, or the field is captured in name only.
const NOT_READ_BY_APPLY := {
	"morale_ladder": "a readable label for transcripts; morale itself is restored",
	"combat_status": "a readable label for transcripts; derived from restored state",
	"target_enemy_uid": "resolved by Battle.restore_snapshot once every unit is respawned",
	"support_target_uid": "resolved by Battle.restore_snapshot once every unit is respawned",
	"engage_turn_enemy_uid": "resolved by Battle.restore_snapshot once every unit is respawned",
}


func test_every_written_key_is_read_back() -> void:
	# The write side alone is not enough: a field added to to_snapshot_dict() but forgotten
	# in apply_snapshot_dict() still reverts on restore. Checked against the apply function's
	# own source, since a value-level round trip would need a non-default value per field.
	var u: Unit = _spawned_unit()
	await get_tree().physics_frame
	var src: String = u.get_script().source_code
	var start: int = src.find("func apply_snapshot_dict(")
	var stop: int = src.find("\nfunc ", start + 1)
	if stop == -1:
		stop = src.length()   # apply_snapshot_dict is the script's last function
	assert_gt(start, -1, "found apply_snapshot_dict")
	var body: String = src.substr(start, stop - start)
	var unread: Array[String] = []
	for key in u.to_snapshot_dict().keys():
		var k := String(key)
		if NOT_READ_BY_APPLY.has(k):
			continue
		if body.find('d["%s"]' % k) == -1 and body.find('d.get("%s"' % k) == -1:
			unread.append(k)
	assert_eq(unread, [] as Array[String],
			"read these back in apply_snapshot_dict() or list them in NOT_READ_BY_APPLY: %s"
			% ", ".join(PackedStringArray(unread)))
	# And the reverse, so the list cannot drift: every listed key is still written, and
	# apply_snapshot_dict() still does not read it.
	var written: Array = u.to_snapshot_dict().keys()
	for k in NOT_READ_BY_APPLY:
		assert_true(written.has(k), "%s is listed but to_snapshot_dict() no longer writes it" % k)
		assert_true(body.find('d["%s"]' % k) == -1 and body.find('d.get("%s"' % k) == -1,
				"%s is listed but apply_snapshot_dict() reads it" % k)
