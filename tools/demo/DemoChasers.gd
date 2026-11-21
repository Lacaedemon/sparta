class_name DemoChasers
extends RefCounted
## The men a formation's shape is judged on (DemoDefects.analyze): a rider riding a runner down
## (the dump's per-man `chasing`, SoldierPursuitStep.chasing) is off his place by design, so he is
## left out of the relational read, and the relations that run to him with him.


## `pos` and the relations `rel` (DemoState.relations) without the men flagged in `chasing`: the
## kept men renumbered in order, and a leader or dressing man who was dropped read as none (-1).
## Returns [pos, rel] unchanged when no man is flagged.
static func drop(pos: Array, rel: Dictionary, chasing: Array) -> Array:
	if not chasing.has(1):
		return [pos, rel]
	var renum := PackedInt32Array()
	renum.resize(pos.size())
	var kept: Array = []
	for i in range(pos.size()):
		var off: bool = i < chasing.size() and int(chasing[i]) == 1
		renum[i] = -1 if off else kept.size()
		if not off:
			kept.append(pos[i])
	var out: Dictionary = {}
	for key in ["leaders", "offsets", "dress", "dress_offsets"]:
		if rel.has(key):
			out[key] = []
	for i in range(pos.size()):
		if renum[i] < 0:
			continue
		for key in ["leaders", "dress"]:
			if rel.has(key) and i < rel[key].size():
				var j: int = int(rel[key][i])
				out[key].append(renum[j] if j >= 0 and j < renum.size() else -1)
		for key in ["offsets", "dress_offsets"]:
			if rel.has(key) and i < rel[key].size():
				out[key].append(rel[key][i])
	return [kept, out]
