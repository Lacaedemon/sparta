class_name ReinforceLayout
## Pure slot bookkeeping for reinforcement insertion (Asclepiodotus, Tactics 10.17: doubling
## by NUMBER -- a reserve's men are interjected between a host's files or ranks). Maps ids
## only: no scene tree, no RNG, so live play and replay deal identically. Each result carries
## "file_ids" and "ranks" (index-aligned with the host's bodies FOLLOWED BY the reserve's, in
## their existing array orders) and "files", the new frontage. `reserve_local` is always the
## reserve's bodies expressed in the HOST's slot frame.

const UnitFormationRef = preload("res://scripts/UnitFormation.gd")

## Insert the reserve as whole files at the host's own density: `k = min(files, ceil(R *
## files / H))` of them (H = the host's headcount, so equal strength doubles exactly even
## over a partial rear rank), file j landing right of host file `floor((j + 0.5) * files /
## k)` -- evenly spread, and strictly alternating at `k == files` (host even, reserve odd).
## Host ranks hold; the reserve is dealt by lateral order and ranked by depth.
static func interleave_files(host_file_ids: PackedInt32Array, host_ranks: PackedInt32Array,
		files: int, reserve_local: PackedVector2Array, max_files: int = -1) -> Dictionary:
	var f: int = maxi(1, files)
	var r: int = reserve_local.size()
	var out := {"file_ids": PackedInt32Array(), "ranks": PackedInt32Array(), "files": f}
	if r <= 0 or host_file_ids.is_empty():
		return out
	var k: int = mini(f, int(ceil(float(r * f) / float(host_file_ids.size()))))
	k = mini(k, max_files - f) if max_files >= 0 else k
	if k <= 0:
		return out
	var hosts := PackedInt32Array()   # h_j: the host file each inserted file follows
	for j in range(k):
		hosts.push_back(int(floor((float(j) + 0.5) * float(f) / float(k))))
	var file_ids := PackedInt32Array()
	var ranks: PackedInt32Array = _ranks_or_index_order(host_file_ids, host_ranks)
	for fid in host_file_ids:
		var shift: int = 0
		for h in hosts:
			shift += 1 if h < fid else 0
		file_ids.push_back(fid + shift)
	var dealt: PackedInt32Array = UnitFormationRef.deal_file_ids_by_lateral_order(
			reserve_local, UnitFormationRef.file_capacities(r, k))
	ranks.append_array(UnitFormationRef.deal_ranks_by_depth(reserve_local, dealt))
	for j in dealt:
		file_ids.push_back(hosts[j] + 1 + j)
	out["file_ids"] = file_ids
	out["ranks"] = ranks
	out["files"] = f + k
	return out

## Insert the reserve as ranks: dealt across the host's `files` by lateral order, then in a
## file holding m inserted men over D_f host men, host rank r becomes `r + min(r, m)` and
## inserted man i `2i + 1` while `i < D_f`, else `D_f + i` (surplus at the rear). Frontage holds.
static func interleave_ranks(host_file_ids: PackedInt32Array, host_ranks: PackedInt32Array,
		files: int, reserve_local: PackedVector2Array) -> Dictionary:
	var f: int = maxi(1, files)
	var r: int = reserve_local.size()
	var out := {"file_ids": PackedInt32Array(), "ranks": PackedInt32Array(), "files": f}
	if r <= 0 or host_file_ids.is_empty():
		return out
	var caps: PackedInt32Array = UnitFormationRef.file_capacities(r, f)
	var dealt: PackedInt32Array = UnitFormationRef.deal_file_ids_by_lateral_order(reserve_local, caps)
	var dealt_ranks: PackedInt32Array = UnitFormationRef.deal_ranks_by_depth(reserve_local, dealt)
	var host_depth: PackedInt32Array = _file_counts(host_file_ids, f)
	var host_ranks_full: PackedInt32Array = _ranks_or_index_order(host_file_ids, host_ranks)
	var file_ids: PackedInt32Array = host_file_ids.duplicate()
	var ranks := PackedInt32Array()
	for i in range(host_file_ids.size()):
		ranks.push_back(host_ranks_full[i] + mini(host_ranks_full[i], caps[host_file_ids[i]]))
	for i in range(r):
		var d: int = host_depth[dealt[i]]
		file_ids.push_back(dealt[i])
		ranks.push_back(2 * dealt_ranks[i] + 1 if dealt_ranks[i] < d else d + dealt_ranks[i])
	out["file_ids"] = file_ids
	out["ranks"] = ranks
	return out

## How far the host's anchor must move REARWARD for the front rank to hold its ground when the
## block deepens: the slot grid is centred on position, so half the added depth lands in front.
static func rear_anchor_shift(old_ranks: int, new_ranks: int, rank_pitch: float) -> float:
	return float(new_ranks - old_ranks) * 0.5 * rank_pitch


static func _file_counts(file_ids: PackedInt32Array, files: int) -> PackedInt32Array:
	var counts := PackedInt32Array()
	counts.resize(files)
	for fid in file_ids:
		if fid >= 0 and fid < files:
			counts[fid] += 1
	return counts


## `ranks` when it lines up with `file_ids`; else index-order depth (what an empty array means).
static func _ranks_or_index_order(file_ids: PackedInt32Array, ranks: PackedInt32Array) -> PackedInt32Array:
	if ranks.size() == file_ids.size():
		return ranks.duplicate()
	var out := PackedInt32Array()
	var seen: Dictionary = {}
	for fid in file_ids:
		out.push_back(int(seen.get(fid, 0)))
		seen[fid] = out[-1] + 1
	return out
