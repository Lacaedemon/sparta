#!/usr/bin/env python3
"""Turn one arm's collected state dumps into the relief-balance study's numbers.

Reads <run-dir>/<seed>/state_*.json (as run-study.sh leaves them) and reports, per
seed and then aggregated:

  survivors     Soldiers still on the field at the final tick, per team. A unit
                destroyed outright is absent from the dump entirely, so this is a
                sum over whatever units remain rather than over a fixed roster.
  lost_units    Units of the starting roster missing at the final tick.
  relief        Rising edges of a RELIEF order across the dumped ticks, per team --
                an approximate episode count, since a dump every TICK_STEP cannot
                see an episode that begins and ends between two samples.
  margin        survivors[0] - survivors[1]. In the mirror arm its EXPECTED value is
                zero by construction, so a non-zero mean there measures the harness,
                not the mechanic. The same behavioural asymmetry (team 1 has a
                General, team 0's delegated group does not) sits under BOTH arms,
                so no single-arm margin is meaningful on its own in either arm.
                Read margins only as a pre-versus-post comparison, where the
                asymmetry sits on both sides and cancels.

Compare two runs (a pre-fix and a post-fix checkout) with --baseline.
"""

import argparse
import glob
import json
import math
import os
import statistics


def _tick(path):
    return int(os.path.basename(path).split("_")[1].split(".")[0])


def read_seed(seed_dir):
    """One battle's summary, or None when the run left no dumps."""
    files = sorted(glob.glob(os.path.join(seed_dir, "state_*.json")), key=_tick)
    if not files:
        return None
    frames = []
    for f in files:
        with open(f, encoding="utf-8") as fh:
            frames.append(json.load(fh))

    roster = {}
    for u in frames[0]["units"]:
        roster.setdefault(u["team"], set()).add(u["uid"])

    # Rising edges only: a RELIEF order spans many dumped ticks, and counting
    # every tick it is visible would report dump density rather than episodes.
    on_relief = {0: set(), 1: set()}
    relief = {0: 0, 1: 0}
    for fr in frames:
        now = {0: set(), 1: set()}
        for u in fr["units"]:
            if str(u.get("current_order", "")).upper() == "RELIEF":
                now[u["team"]].add(u["uid"])
        for team in (0, 1):
            relief[team] += len(now[team] - on_relief[team])
            on_relief[team] = now[team]

    final = frames[-1]
    survivors = {0: 0, 1: 0}
    alive = {0: set(), 1: set()}
    for u in final["units"]:
        survivors[u["team"]] += int(u["soldiers"])
        alive[u["team"]].add(u["uid"])

    return {
        "final_tick": final["tick"],
        "survivors": survivors,
        "lost_units": {t: len(roster.get(t, set()) - alive[t]) for t in (0, 1)},
        "relief": relief,
        "margin": survivors[0] - survivors[1],
    }


def read_run(run_dir):
    out = {}
    for entry in sorted(os.listdir(run_dir)):
        d = os.path.join(run_dir, entry)
        if not os.path.isdir(d):
            continue
        row = read_seed(d)
        if row is not None:
            out[entry] = row
    return out


def _stats(values):
    if not values:
        return "n=0"
    sd = statistics.stdev(values) if len(values) > 1 else 0.0
    return "n=%d mean=%.1f sd=%.1f median=%.1f" % (
        len(values), statistics.mean(values), sd, statistics.median(values))


def welch(a, b):
    """Welch's t and a two-sided p, for a difference of means at unequal variance.

    Reported so a difference is read against its own noise rather than by eye. A
    twenty-seed arm of a chaotic sim has a standard deviation comparable to most of
    the effects under study, which is exactly the situation where a mean difference
    reads as a result and is not one.

    The p is the normal approximation, adequate at these n and deliberately not a
    scipy dependency; treat it as an order of magnitude, not a decimal.
    """
    na, nb = len(a), len(b)
    if na < 2 or nb < 2:
        return None
    va, vb = statistics.variance(a), statistics.variance(b)
    se = math.sqrt(va / na + vb / nb)
    if se == 0.0:
        return None
    t = (statistics.mean(a) - statistics.mean(b)) / se
    p = math.erfc(abs(t) / math.sqrt(2.0))
    return t, p


def report(label, rows, expect_final_tick=None):
    print("== %s (%d seed(s))" % (label, len(rows)))
    if not rows:
        print("  no completed seeds")
        return {}
    # A short final_tick means the battle was cut off, and run-study.sh's snapshot count
    # is what normally catches that -- but a run collected some other way, or one whose
    # dumps were pruned afterwards, arrives here looking ordinary.
    #
    # The reference is the MAXIMUM final tick, not the modal one. A run cannot overshoot
    # the tick it was asked for, so the maximum is a bound; the mode is a vote, and it
    # elects the wrong answer as soon as most of the set is truncated -- which is the
    # case where being wrong matters most. Pass --expect-final-tick to bound it from
    # outside, which is the only way to catch a set where EVERY run was cut off at the
    # same tick, since nothing internal to the data distinguishes that from a short study.
    ticks = [r["final_tick"] for r in rows.values()]
    full = max(ticks) if expect_final_tick is None else int(expect_final_tick)
    print("  %-8s %-7s %-9s %-9s %-7s %-7s %-7s %-7s %s"
          % ("seed", "end", "surv t0", "surv t1", "lost0", "lost1", "rel0", "rel1",
             "margin"))
    for seed, r in rows.items():
        mark = "" if r["final_tick"] == full else "  <-- SHORT"
        print("  %-8s %-7d %-9d %-9d %-7d %-7d %-7d %-7d %+d%s"
              % (seed, r["final_tick"], r["survivors"][0], r["survivors"][1],
                 r["lost_units"][0], r["lost_units"][1], r["relief"][0], r["relief"][1],
                 r["margin"], mark))
    # Excluded from the aggregates, not merely flagged. A warning printed beside a
    # contaminated mean is worse than no warning: it reads as a caveat while the number
    # under it is still wrong, and nobody cross-references the marked rows by hand.
    short = [s for s, r in rows.items() if r["final_tick"] < full]
    kept = {s: r for s, r in rows.items() if r["final_tick"] >= full}
    if short:
        print("  WARNING: %d seed(s) ended before tick %d: %s."
              % (len(short), full, ", ".join(short)))
        print("           A truncated battle is not a decided one; they are EXCLUDED from"
              " the aggregates below.")
    if not kept:
        print("  no seed reached tick %d -- nothing to aggregate" % full)
        return {}
    print("  aggregates over %d of %d seed(s), all ending at tick %d"
          % (len(kept), len(rows), full))
    cols = {
        "survivors t0": [r["survivors"][0] for r in kept.values()],
        "survivors t1": [r["survivors"][1] for r in kept.values()],
        "survivors both": [r["survivors"][0] + r["survivors"][1] for r in kept.values()],
        "lost_units t0": [r["lost_units"][0] for r in kept.values()],
        "lost_units t1": [r["lost_units"][1] for r in kept.values()],
        "relief t0": [r["relief"][0] for r in kept.values()],
        "relief t1": [r["relief"][1] for r in kept.values()],
        "margin": [r["margin"] for r in kept.values()],
    }
    for name, vals in cols.items():
        print("  %-16s %s" % (name, _stats(vals)))
    return cols


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("run_dir", help="a run-study.sh output directory")
    p.add_argument("--baseline", help="a second run directory to compare against")
    p.add_argument("--label", default="run")
    p.add_argument("--baseline-label", default="baseline")
    p.add_argument("--expect-final-tick", type=int,
                   help="the tick a complete battle ends at. Without it the reference is "
                        "the maximum observed, which cannot detect a set where every run "
                        "was truncated at the same tick")
    a = p.parse_args()

    cols = report(a.label, read_run(a.run_dir), a.expect_final_tick)
    if not a.baseline:
        return
    print()
    base = report(a.baseline_label, read_run(a.baseline), a.expect_final_tick)
    if not cols or not base:
        return
    print()
    print("== %s minus %s (means)" % (a.label, a.baseline_label))
    # Seed sets can differ if a run dropped a sample; compare means, and say so.
    print("  %-16s %-9s %-8s %-8s %s" % ("", "diff", "t", "p", ""))
    for name in cols:
        if name not in base or not cols[name] or not base[name]:
            continue
        diff = statistics.mean(cols[name]) - statistics.mean(base[name])
        w = welch(cols[name], base[name])
        if w is None:
            print("  %-16s %+-9.1f %-8s %-8s" % (name, diff, "-", "-"))
            continue
        t, p = w
        print("  %-16s %+-9.1f %-8.2f %-8.3f %s"
              % (name, diff, t, p, "*" if p < 0.05 else ""))
    print("  (p is a normal approximation; * marks p < 0.05, uncorrected for the"
          " %d comparisons above)" % len(cols))


if __name__ == "__main__":
    main()
