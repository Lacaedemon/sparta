class_name SoldierFileNeighbours
extends RefCounted
## Who stands next to a man in his own file: the man in front of him and the man behind him,
## by identity (his file and rank), not by where anyone stands. The lane follower
## (SoldierBodies.step) keeps a man from running through the file-mate ahead of him, and a
## routed man takes his line from the file-mate running ahead of him (SoldierFlight).


## [front, rear]: for each of `unit`'s first `n` men, the body index of the man one rank in
## front of him and one rank behind him in his file, or -1. Read from the unit's explicit file
## (and rank) assignment when it has one for `n` men, else from index order (`files` men a
## rank). O(n).
static func compute(unit: Unit, n: int, files: int) -> Array[PackedInt32Array]:
	var front := PackedInt32Array()
	var rear := PackedInt32Array()
	front.resize(n)
	front.fill(-1)
	rear.resize(n)
	rear.fill(-1)
	if files <= 0:
		return [front, rear]
	if unit._sim_soldier_file.size() != n:
		for j in range(n):
			if j - files >= 0:
				front[j] = j - files
			if j + files < n:
				rear[j] = j + files
		return [front, rear]
	var max_r: int = ceili(float(n) / float(files)) + 2
	var grid := PackedInt32Array()
	grid.resize(files * max_r)
	grid.fill(-1)
	var explicit: bool = unit._sim_soldier_rank.size() == n
	var rank_counts := PackedInt32Array()
	if not explicit:
		rank_counts.resize(files)
	var soldier_ranks := PackedInt32Array()
	soldier_ranks.resize(n)
	for j in range(n):
		var f: int = clampi(unit._sim_soldier_file[j], 0, files - 1)
		var r: int = maxi(0, unit._sim_soldier_rank[j]) if explicit else rank_counts[f]
		if not explicit:
			rank_counts[f] += 1
		soldier_ranks[j] = r
		if r >= 0 and r < max_r:
			grid[f * max_r + r] = j
	for j in range(n):
		var f: int = clampi(unit._sim_soldier_file[j], 0, files - 1)
		var r: int = soldier_ranks[j]
		if r > 0 and r - 1 < max_r:
			front[j] = grid[f * max_r + r - 1]
		if r + 1 < max_r:
			rear[j] = grid[f * max_r + r + 1]
	return [front, rear]
