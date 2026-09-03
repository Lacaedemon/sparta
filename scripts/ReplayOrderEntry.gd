extends RefCounted
## Order entry factory: builds normalized replay order dictionaries.


static func build(tick: int, uids: Array, pos: Vector2, target_uid: int,
		order_mode: int = 0, formation: int = 0, frontage: int = 0, face: float = INF,
		group_attack: int = 0, anchor_offset: float = 0.0,
		form_up_group: int = -1, walk_advance_toggle: int = 0, reform_toggle: int = 0,
		file_major_reform_mode_toggle: int = -1,
		line_index: int = -1) -> Dictionary:
	var entry := {
		"tick": tick,
		"units": uids.duplicate(),
		"x": pos.x,
		"y": pos.y,
		"target": target_uid,
		"mode": order_mode,   # 0 = OrderMode.NORMAL
	}
	if formation != 0:
		entry["formation"] = formation
	if frontage != 0:
		entry["frontage"] = frontage
	# An asymmetric (anchored) explicatio/duplicatio's flank-fixing shift; 0.0 is the plain
	# centred resize every other frontage change already uses, so it's omitted for those
	# (old replays -- and every non-anchored resize in a new one -- stay exactly as compact).
	if anchor_offset != 0.0:
		entry["anchor_offset"] = anchor_offset
	# A drag-to-form-up order carries a deploy facing (radians); INF means "none"
	# (a plain move), so any real angle -- including 0 -- is recorded.
	if not is_inf(face):
		entry["face"] = face
	# 0 = GroupAttackMode.FOCUSED (the default); omit it so old replays stay valid.
	if group_attack != 0:
		entry["group_attack"] = group_attack
	# -1 = not part of a multi-unit form-up group (a single-unit form-up, or any other order kind);
	# omit it so old replays -- and every non-grouped order in a new one -- stay exactly as compact.
	if form_up_group >= 0:
		entry["form_up_group"] = form_up_group
	# 0 = Battle.UnitSettingToggle.LEAVE (the default -- no write); a Battle.
	# ORDER_UNIT_SETTINGS_ONLY order's walk_advance/reform_before_move toggle, omitted for
	# every other order kind so old replays stay valid.
	if walk_advance_toggle != 0:
		entry["walk_advance_toggle"] = walk_advance_toggle
	if reform_toggle != 0:
		entry["reform_toggle"] = reform_toggle
	# -1 = Battle.REFORM_MODE_TOGGLE_LEAVE (the default -- no write; can't reuse 0 the way the two toggles above do, since 0 is a legitimate Unit.ReformMode value -- FILE_MAJOR -- not a spare sentinel).
	# Omitted for every other order kind so old replays stay valid.
	if file_major_reform_mode_toggle != -1:
		entry["file_major_reform_mode_toggle"] = file_major_reform_mode_toggle
	# -1 = Battle.LINE_INDEX_UNCHANGED (the default -- leave each ordered unit's persistent Unit.line_index alone; can't reuse 0 the way the two toggles above do, since 0 is a legitimate line index -- the front line -- not a spare sentinel).
	# A checkerboard or tray-grid form-up assigns a real (>= 0) index, and a unit-settings order from a tray row
	# move carries it too, which has to ride the replay stream or a recorded acies triplex deploy
	# plays back with every unit's line membership dropped.
	# Omitted for a plain drag and every other order kind so old replays stay valid.
	if line_index != -1:
		entry["line"] = line_index
	return entry
