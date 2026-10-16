#!/usr/bin/env python3
"""Measure how deep enemy men stand inside a block in melee, from FULL state dumps.

Reads one or more dump directories (state_<tick>.json written with SPARTA_DEMO_STATE_FULL=1,
see tools/demo/dump-state.sh) and, for every ordered pair of opposing units (A, B) at every
snapshot, measures B's men inside A's footprint:

  frame      A's front direction is the way its slot grid's front rank faces
             (motion_ref.slot_grid.front), which stays on the men after a folded turn.
             A dump from a tree without that field falls back to the normal of the
             grid's file axis (motion_ref.slot_grid.axis) signed to agree with A's facing,
             which reads a block folded half about as facing backwards.
  front line The median, along that front, of A's live front-rank men (those whose slot
             lies within half a rank pitch of the grid's front rank). The bodies, not the
             slots, since a front rank pushed back by contact is where the line really is.
  footprint  From half a rank pitch behind the rearmost slot up to the front line, and
             between the outermost slots padded by half a file pitch.
  depth      For each live B man inside the footprint, how far he stands behind the front
             line, in wu and in A's rank pitches.

A pair is "in contact" at a snapshot when both units read in_enemy_contact and the two are
fighting each other: one targets the other, or B has men inside A's footprint. It is
"frontal" when their fronts face each other (the dot of the two front directions is below
FRONTAL_DOT) and B's centre lies ahead of A's. The per-pair summary is taken over the
pair's contact snapshots.

Mechanism columns: `gap` is the distance between the two centres along A's front;
`slot_overlap` is (A's front slot depth + B's front slot depth - gap), how far the two slot
grids are ordered into each other, so a frontal pair whose lines meet has slot_overlap near
0; `inside_slots` counts B's slots (where B's men are ordered to stand) inside A's footprint,
beside `inside`, the men actually there.

Usage:
  melee_penetration.py <dump-dir>[=<label>] ... [--tsv out.tsv] [--series out.tsv]
                       [--markdown out.md] [--min-contact N]

Each dump dir is one run of one clip; its label (default: the directory's name) names the
clip in the output. Prints a per-pair summary to stdout as tab-separated rows prefixed
PEN, a per-clip roll-up of the frontal pairs prefixed PEN-CLIP, and, prefixed PEN-ALL, the
median over frontal pairs of each pair's mean depth in ranks with the shares of pairs past
one and two ranks: once over every pair and once over foot pairs (no cavalry or missile unit,
judged by the "<Type> <n>" unit name).
"""

import argparse
import glob
import json
import os
import statistics
import sys

# Two fronts face each other when the dot of their directions is below this (120 degrees
# or more apart).
FRONTAL_DOT = -0.5


def unit_frame(rec):
    """A's front direction, lateral axis, and pitches; None when the unit has no men."""
    full = rec.get("soldiers_full")
    ref = rec.get("motion_ref")
    if not full or not ref or not full.get("pos") or not ref.get("slot_grid"):
        return None
    ax, ay = ref["slot_grid"]["axis"]
    if "front" in ref["slot_grid"]:
        fx, fy = ref["slot_grid"]["front"]
    else:
        fx, fy = -ay, ax
        fac = rec.get("facing") or [0.0, 0.0]
        if fx * fac[0] + fy * fac[1] < 0.0:
            fx, fy = -fx, -fy
    return (fx, fy), (ax, ay), float(ref["rank_pitch"]), float(ref["file_pitch"])


def footprint(rec, frame):
    """A's footprint along its own front and file axes, relative to its position."""
    (fx, fy), (ax, ay), rp, fp = frame
    px, py = rec["position"]
    full = rec["soldiers_full"]
    slots = full.get("slots") or []
    pos = full["pos"]
    hp = full.get("hp") or [1.0] * len(pos)
    if not slots:
        return None
    sf = [(sx - px) * fx + (sy - py) * fy for sx, sy in slots]
    sl = [(sx - px) * ax + (sy - py) * ay for sx, sy in slots]
    front_slot = max(sf)
    front_men = []
    for i, (bx, by) in enumerate(pos):
        if i < len(sf) and i < len(hp) and hp[i] > 0.0 and sf[i] >= front_slot - rp * 0.5:
            front_men.append((bx - px) * fx + (by - py) * fy)
    front_line = statistics.median(front_men) if front_men else front_slot
    return {
        "front_slot": front_slot,
        "front_line": front_line,
        "rear": min(sf) - rp * 0.5,
        "lat_lo": min(sl) - fp * 0.5,
        "lat_hi": max(sl) + fp * 0.5,
        "rank_pitch": rp,
    }


def inside_depths(points, alive, origin, frame, fpa):
    """Depth behind A's front line of each live point inside A's footprint."""
    (fx, fy), (ax, ay), _rp, _fp = frame
    px, py = origin
    out = []
    for i, (qx, qy) in enumerate(points):
        if i < len(alive) and alive[i] <= 0.0:
            continue
        u = (qx - px) * fx + (qy - py) * fy
        lat = (qx - px) * ax + (qy - py) * ay
        if fpa["rear"] <= u < fpa["front_line"] and fpa["lat_lo"] <= lat <= fpa["lat_hi"]:
            out.append(fpa["front_line"] - u)
    return out


def load_snapshots(path):
    snaps = []
    for f in glob.glob(os.path.join(path, "state_*.json")):
        with open(f) as fh:
            snaps.append(json.load(fh))
    snaps.sort(key=lambda s: s["tick"])
    return snaps


def analyze_run(label, path, series_out):
    """Per-pair accumulators for one run."""
    pairs = {}
    for snap in load_snapshots(path):
        tick = snap["tick"]
        recs = [u for u in snap["units"] if u.get("state") != "DEAD"]
        frames = {}
        prints = {}
        for u in recs:
            fr = unit_frame(u)
            fpu = footprint(u, fr) if fr is not None else None
            if fpu is not None:
                frames[u["uid"]] = fr
                prints[u["uid"]] = fpu
        for a in recs:
            if a["uid"] not in frames:
                continue
            for b in recs:
                if b["team"] == a["team"] or b["uid"] not in frames:
                    continue
                sample(pairs, tick, label, a, b, frames, prints, series_out)
    return pairs


def sample(pairs, tick, label, a, b, frames, prints, series_out):
    fa, fpa = frames[a["uid"]], prints[a["uid"]]
    full = b["soldiers_full"]
    hp = full.get("hp") or [1.0] * len(full["pos"])
    depths = inside_depths(full["pos"], hp, a["position"], fa, fpa)
    slots_in = len(inside_depths(full.get("slots") or [], hp, a["position"], fa, fpa))
    fighting = a.get("target_enemy_uid") == b["uid"] or b.get("target_enemy_uid") == a["uid"]
    contact = bool(a.get("in_enemy_contact")) and bool(b.get("in_enemy_contact")) \
        and (fighting or bool(depths))
    if not depths and not contact:
        return
    (fx, fy) = fa[0]
    gap = (b["position"][0] - a["position"][0]) * fx + (b["position"][1] - a["position"][1]) * fy
    dot = fx * frames[b["uid"]][0][0] + fy * frames[b["uid"]][0][1]
    rp = fpa["rank_pitch"]
    frontal = dot < FRONTAL_DOT and gap > 0.0
    overlap = fpa["front_slot"] + prints[b["uid"]]["front_slot"] - gap
    max_d = max(depths) if depths else 0.0
    n_deep = sum(1 for d in depths if d > rp)
    acc = pairs.setdefault((a["uid"], b["uid"]), {
        "contact": [], "first_contact": None, "first_over_rank": None,
        "first": None, "a_state": set(), "b_state": set(),
        "names": "%s>%s" % (a.get("name"), b.get("name"))})
    if max_d > rp and acc["first_over_rank"] is None:
        acc["first_over_rank"] = tick
    if contact:
        # Each sample carries its own rank pitch, so a formation change mid-clip (Loose
        # doubles the pitch) converts each depth to ranks at the pitch it was taken at.
        row = (tick, max_d, len(depths), n_deep, frontal, gap, overlap, slots_in, rp)
        if acc["first_contact"] is None:
            acc["first_contact"] = tick
            acc["first"] = row
        acc["contact"].append(row)
        acc["a_state"].add(a.get("state"))
        acc["b_state"].add(b.get("state"))
    if series_out is not None:
        series_out.write("\t".join(str(x) for x in (
            label, tick, a["uid"], b["uid"], int(contact), int(frontal), len(depths),
            slots_in, n_deep, round(max_d, 1), round(gap, 1), round(overlap, 1),
            a.get("state"), b.get("state"))) + "\n")


PAIR_COLS = ("clip", "a", "b", "contact_snaps", "frontal_frac", "first_contact",
             "first_contact_depth_ranks", "first_contact_gap_wu",
             "first_contact_slot_overlap_wu", "first_over_1_rank", "max_depth_wu",
             "max_depth_ranks", "mean_depth_ranks", "max_inside", "mean_inside",
             "mean_inside_slots", "max_deep", "mean_slot_overlap_wu", "mean_gap_wu", "states",
             "names")


def summarize(label, pairs, min_contact):
    rows = []
    for (a, b), acc in sorted(pairs.items()):
        c = acc["contact"]
        if len(c) < min_contact or not c:
            continue
        depths = [x[1] for x in c]
        ranks = [x[1] / x[8] for x in c]
        inside = [x[2] for x in c]
        first = acc["first"]
        rows.append({
            "clip": label, "a": a, "b": b, "contact_snaps": len(c),
            "frontal_frac": round(sum(1 for x in c if x[4]) / len(c), 2),
            "first_contact": acc["first_contact"],
            "first_contact_depth_ranks": round(first[1] / first[8], 2),
            "first_contact_gap_wu": round(first[5], 1),
            "first_contact_slot_overlap_wu": round(first[6], 1),
            "first_over_1_rank": acc["first_over_rank"],
            "max_depth_wu": round(max(depths), 1),
            "max_depth_ranks": round(max(ranks), 2),
            "mean_depth_ranks": round(statistics.fmean(ranks), 2),
            "max_inside": max(inside),
            "mean_inside": round(statistics.fmean(inside), 1),
            "mean_inside_slots": round(statistics.fmean(x[7] for x in c), 1),
            "max_deep": max(x[3] for x in c),
            "mean_slot_overlap_wu": round(statistics.fmean(x[6] for x in c), 1),
            "mean_gap_wu": round(statistics.fmean(x[5] for x in c), 1),
            "states": "/".join(sorted(s for s in acc["a_state"] if s)) + ">"
                      + "/".join(sorted(s for s in acc["b_state"] if s)),
            "names": acc["names"],
        })
    return rows


def clip_rollup(label, rows):
    frontal = [r for r in rows if r["frontal_frac"] >= 0.5]
    if not frontal:
        return {"clip": label, "frontal_pairs": 0}
    return {
        "clip": label,
        "frontal_pairs": len(frontal),
        "pairs_over_1_rank": sum(1 for r in frontal if r["max_depth_ranks"] > 1.0),
        "worst_max_depth_ranks": max(r["max_depth_ranks"] for r in frontal),
        "worst_mean_depth_ranks": max(r["mean_depth_ranks"] for r in frontal),
        "worst_max_inside": max(r["max_inside"] for r in frontal),
        "worst_mean_inside": max(r["mean_inside"] for r in frontal),
    }


# Unit-name prefixes of the troop types MeleeFrontLine leaves on the centre-based ranges
# (scenario names are "<Type> <n>"), so the foot-only roll-up below compares like with like.
NON_FOOT_MELEE = ("Cavalry", "Archers", "Slingers", "Javelin")


def overall_rollup(rows, min_contact):
    """Over every frontal pair with at least min_contact contact snapshots: the median of the
    pairs' mean depth in ranks, and the share of pairs whose mean depth passes 1 and 2 ranks.
    Once over all such pairs and once over foot-only pairs (no NON_FOOT_MELEE unit)."""
    out = {}
    frontal = [r for r in rows if r["frontal_frac"] >= 0.5 and r["contact_snaps"] >= min_contact]
    foot = [r for r in frontal if not any(t in r["names"] for t in NON_FOOT_MELEE)]
    for name, group in (("all", frontal), ("foot", foot)):
        md = [r["mean_depth_ranks"] for r in group]
        out[name] = {
            "pairs": len(md),
            "median_mean_depth_ranks": round(statistics.median(md), 2) if md else None,
            "share_over_1_rank": round(sum(1 for x in md if x > 1.0) / len(md), 2) if md else None,
            "share_over_2_ranks": round(sum(1 for x in md if x > 2.0) / len(md), 2) if md else None,
        }
    return out


ROLLUP_COLS = ("clip", "frontal_pairs", "pairs_over_1_rank", "worst_max_depth_ranks",
               "worst_mean_depth_ranks", "worst_max_inside", "worst_mean_inside")


def write_markdown(path, rollups, overall):
    with open(path, "w") as fh:
        for name, o in overall.items():
            fh.write("- %s frontal pairs (%d): median mean depth %s ranks, %s over 1 rank, "
                     "%s over 2 ranks\n" % (name, o["pairs"], o["median_mean_depth_ranks"],
                                            o["share_over_1_rank"], o["share_over_2_ranks"]))
        fh.write("\n| " + " | ".join(ROLLUP_COLS) + " |\n")
        fh.write("|" + "---|" * len(ROLLUP_COLS) + "\n")
        for r in rollups:
            fh.write("| " + " | ".join(str(r.get(c, "")) for c in ROLLUP_COLS) + " |\n")


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("runs", nargs="+", help="dump dir[=label]")
    ap.add_argument("--tsv", help="write every pair row here")
    ap.add_argument("--series", help="write every per-snapshot pair sample here")
    ap.add_argument("--markdown", help="write a per-clip roll-up table here")
    ap.add_argument("--min-contact", type=int, default=1,
                    help="fewest contact snapshots for a pair to be reported (default 1)")
    ap.add_argument("--rollup-min-contact", type=int, default=5,
                    help="fewest contact snapshots for a pair to count in PEN-ALL (default 5)")
    args = ap.parse_args(argv)
    series_out = open(args.series, "w") if args.series else None
    if series_out is not None:
        series_out.write("clip\ttick\ta\tb\tcontact\tfrontal\tinside\tinside_slots\tdeep\t"
                         "max_depth_wu\tgap_wu\tslot_overlap_wu\ta_state\tb_state\n")
    all_rows = []
    rollups = []
    for spec in args.runs:
        path, _, label = spec.partition("=")
        label = label or os.path.basename(os.path.normpath(path))
        if not glob.glob(os.path.join(path, "state_*.json")):
            print("error: %s holds no state_*.json" % path, file=sys.stderr)
            return 2
        rows = summarize(label, analyze_run(label, path, series_out), args.min_contact)
        all_rows.extend(rows)
        rollups.append(clip_rollup(label, rows))
    if series_out is not None:
        series_out.close()
    lines = ["\t".join(PAIR_COLS)]
    for r in all_rows:
        lines.append("\t".join(str(r[c]) for c in PAIR_COLS))
    for line in lines:
        print("PEN\t" + line)
    for r in rollups:
        print("PEN-CLIP\t" + "\t".join("%s=%s" % kv for kv in r.items()))
    overall = overall_rollup(all_rows, args.rollup_min_contact)
    for name, o in overall.items():
        print("PEN-ALL\t%s\t" % name + "\t".join("%s=%s" % kv for kv in o.items()))
    if args.tsv:
        with open(args.tsv, "w") as fh:
            fh.write("\n".join(lines) + "\n")
    if args.markdown:
        write_markdown(args.markdown, rollups, overall)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
