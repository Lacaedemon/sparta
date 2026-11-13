class_name DemoRelations
extends RefCounted
## Who each man stands behind and beside, read off the block's grid: the relations a dump
## carries so an offline analyzer can judge the men against the men they follow, never
## against a point of the grid in the world. A man's place is his identity (his file and rank),
## so the plan names the man ahead of him in his file (`leaders`) and the man next to him in
## his rank (`dress`), each with the offset that places him there in his own frame as
## (to his own right, behind him) -- the shape SoldierFollow.place reads.
##
## Pure: plain values in, plain values out. The grid is the unit's own, laid out in its local
## frame (local x to the right, local y behind, before the lateral mirror is applied), so the
## plan is the same wherever the block stands or however its grid is folded.

## A man with no one ahead of him in his file, or no one beside him.
const NONE := -1
## A man's neighbour must lie within this fraction of a pitch of his own line or column.
const REACH_FRAC := 0.5


## The plan for the men at `local` (index-aligned): `leaders` and `dress` (index or NONE) and
## the matching `offsets` and `dress_offsets`, as (right, behind) in the man's own frame.
## `mirror` is -1.0 when the grid's local x runs to the man's left (a mirrored reform), else 1.0.
static func plan(local: PackedVector2Array, mirror: float, file_pitch: float,
		rank_pitch: float) -> Dictionary:
	var n: int = local.size()
	var leaders := PackedInt32Array()
	var dress := PackedInt32Array()
	var offsets := PackedVector2Array()
	var dress_offsets := PackedVector2Array()
	leaders.resize(n)
	dress.resize(n)
	offsets.resize(n)
	dress_offsets.resize(n)
	for i in range(n):
		leaders[i] = NONE
		dress[i] = NONE
		var best_ahead: float = INF
		var best_beside: float = INF
		for j in range(n):
			if j == i:
				continue
			var d: Vector2 = local[i] - local[j]
			var ahead: float = d.y
			if ahead > REACH_FRAC * rank_pitch and ahead < (1.0 + REACH_FRAC) * rank_pitch \
					and absf(d.x) <= REACH_FRAC * file_pitch + 0.01 and absf(d.x) < best_ahead:
				best_ahead = absf(d.x)
				leaders[i] = j
				offsets[i] = Vector2(d.x * mirror, d.y)
			var beside: float = -d.x
			if absf(d.y) <= REACH_FRAC * rank_pitch and beside > REACH_FRAC * file_pitch \
					and beside < (1.0 + REACH_FRAC) * file_pitch and beside < best_beside:
				best_beside = beside
				dress[i] = j
				dress_offsets[i] = Vector2(-d.x * mirror, -d.y)
	return {"leaders": leaders, "offsets": offsets, "dress": dress, "dress_offsets": dress_offsets}


## Each man's file: the root of his chain of leaders, so men sharing a root stand in one file.
## `leaders` is a plan's (or a dump's) index array.
static func files(leaders: Array) -> Array:
	var out: Array = []
	for i in range(leaders.size()):
		var root: int = i
		var hops: int = 0
		while int(leaders[root]) >= 0 and hops <= leaders.size():
			root = int(leaders[root])
			hops += 1
		out.append(root)
	return out
