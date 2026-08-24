#!/usr/bin/env python3
"""Generate the scripted-input files for the relief-balance study, one per seed and arm.

The study asks whether AI line relief became too strong once a relieved regiment
started surviving its withdrawal. Both arms are AI-vs-AI: team 1 runs the General
(Battle.ai_doctrine), and team 0 is delegated to an AI subcommander group by a
scripted Ctrl+Shift+1 -- so both sides run the same Subcommander/UnitLeader
pipeline, and therefore the same ordinary inter-unit relief call, which is the
mechanic under study. Measured: team 0 does issue RELIEF orders under delegation,
so the ungeneraled side is not structurally barred from rotating.

Arms:

  mirror  Both sides identical: a tired front rank and a fresh rear pair inside
          UnitLeader.RELIEF_CALL_RANGE. Who wins is 50/50 by construction, which
          is the point -- it isolates what relief COSTS rather than who it favours.

  asym    Equal soldiers, equal unit count, equal per-unit size, deployed
          differently: team 0 puts every unit in one wide line while team 1 keeps
          a rear pair back. The frontage difference is intrinsic to the tactical
          choice being measured, not a confound to control away.

          This arm was DESIGNED to give team 0 no reliever at all, on the
          reasoning that a unit in the front line is always FIGHTING and so fails
          _relief_candidate. That reasoning is wrong, and the arm's own relief
          counts say so: over twenty seeds team 0 averaged 3.0 relief episodes
          against team 1's 3.0. A wide line does not engage all at once, so
          whichever units are still closing are non-FIGHTING and answer calls.
          Read the arm as wide-line-versus-reserved-rank, both rotating -- and
          treat "an AI army cannot opt out of rotating" as a finding rather than
          as a knob this study has.

The scripted box-select must complete before the delegation hotkey fires:
DemoInputRecorder expands a box into a press, DRAG_TICKS-1 motions and a release,
so a box at tick 8 is not resolved until tick 24.
"""

import argparse
import json
import os

# A box drag started at tick 8 releases at 8 + DemoInputRecorder.DRAG_TICKS.
BOX_TICK = 8
DELEGATE_TICK = 30

# The battle's own geometry. Front ranks face each other across the midline;
# each rear pair sits REAR_OFFSET behind its own front, which must stay inside
# UnitLeader.RELIEF_CALL_RANGE (220.0) for the rear units to answer a call.
# The default map is Rect2(0, 0, 1600, 1200), so its centre is y=600. Mirroring about any
# other line hands one side more ground than the other, and the arms emit an empty-terrain
# map block for the same reason: the default TERRAIN's two patches both sit at y 380-580,
# which is one team's half whatever midline is chosen.
FIELD_W = 1600.0
FIELD_H = 1200.0
MIDLINE_Y = FIELD_H / 2.0
FRONT_OFFSET = 140.0
REAR_OFFSET = 120.0
FRONT_XS = (500.0, 600.0, 700.0, 800.0)
REAR_XS = (590.0, 710.0)
# Centred on the same x=650 midpoint as FRONT_XS/REAR_XS: the asym arm's whole claim is
# that only the DEPLOYMENT differs, and a line whose mean sits 50 wu to one side hands
# team 0 an undisclosed flank overhang on a sim that has a flank-damage mechanic.
ALL_SIX_XS = (400.0, 500.0, 600.0, 700.0, 800.0, 900.0)


def _unit(team, x, y, count, morale=None):
    u = {"team": team, "type": "Infantry", "x": x, "y": y, "count": count}
    if morale is not None:
        u["morale"] = morale
    return u


def _side(team, arm, count, front_morale, rear_morale):
    """One army's spawns. Team 0 sits above the midline, team 1 below it."""
    sign = -1.0 if team == 0 else 1.0
    front_y = MIDLINE_Y + sign * FRONT_OFFSET
    # Further from the midline than the front, not between the two fronts.
    rear_y = MIDLINE_Y + sign * (FRONT_OFFSET + REAR_OFFSET)
    if arm == "asym" and team == 0:
        # Everything abreast. The morale mix stays four tired and two fresh, matching the
        # other side exactly: the arm varies DEPLOYMENT, and letting team 0's six all start
        # at the tired value would hand team 1 an undisclosed aggregate-morale edge that
        # also gates relief eligibility directly (_relief_candidate rejects a would-be
        # reliever below RELIEF_MORALE_THRESHOLD).
        # Fresh pair in the CENTRE, not on one flank: appending them would put the whole
        # right wing at full morale and leave the left tired, which is a flank bias rather
        # than the deployment difference the arm is for.
        morales = ([front_morale] * 2 + [rear_morale] * 2 + [front_morale] * 2)
        return [_unit(team, x, front_y, count, m)
                for x, m in zip(ALL_SIX_XS, morales)]
    return ([_unit(team, x, front_y, count, front_morale) for x in FRONT_XS]
            + [_unit(team, x, rear_y, count, rear_morale) for x in REAR_XS])


def scenario(arm, seed, doctrine, count, front_morale, rear_morale, last_tick, tick_step):
    """One input script: the arm's matchup at `seed`, dumping state to `last_tick`."""
    spawns = (_side(0, arm, count, front_morale, rear_morale)
              + _side(1, arm, count, front_morale, rear_morale))
    top = min(u["y"] for u in spawns if u["team"] == 0)
    bottom = max(u["y"] for u in spawns if u["team"] == 0)
    left = min(u["x"] for u in spawns if u["team"] == 0)
    right = max(u["x"] for u in spawns if u["team"] == 0)
    return {
        "_comment": ("tools/study/relief-balance: generated, do not hand-edit. "
                     "Arm %s, seed %s. See that directory's README." % (arm, seed)),
        "seed": str(seed),
        "doctrine": doctrine,
        "map": {"field": [FIELD_W, FIELD_H], "terrain": []},
        "scenario": spawns,
        "camera": [{"tick": 0, "x": 650.0, "y": MIDLINE_Y, "zoom": 0.42}],
        "steps": [
            # Bracket team 0 generously, then hand it to an AI subcommander group.
            {"tick": BOX_TICK, "box": {"from": [left - 80.0, top - 80.0],
                                       "to": [right + 80.0, bottom + 80.0]}},
            {"tick": DELEGATE_TICK, "key": "1", "ctrl": True, "shift": True},
        ],
        "state": list(range(tick_step, last_tick + 1, tick_step)),
    }


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("out_dir", help="directory to write the input scripts into")
    p.add_argument("--arm", default="mirror", choices=("mirror", "asym"))
    p.add_argument("--seeds", default="101-120",
                   help="inclusive range LO-HI, or a comma-separated list")
    p.add_argument("--doctrine", default="aggressive",
                   help="team 1's doctrine (a data/doctrines stem). Defaults to one whose "
                        "reserve_fraction floors to zero at this roster size; a doctrine "
                        "that does hold reserves pins them at spawn and invalidates the "
                        "measurement (see the README)")
    p.add_argument("--count", type=int, default=45, help="soldiers per unit")
    p.add_argument("--front-morale", type=float, default=34.0,
                   help="front-rank starting morale; below "
                        "UnitLeader.RELIEF_MORALE_THRESHOLD (35) so relief is "
                        "called early rather than only after a long grind")
    p.add_argument("--rear-morale", type=float, default=100.0,
                   help="rear-rank starting morale; the fresh half of the roster, and "
                        "applied to both sides in both arms so the aggregate is equal")
    p.add_argument("--last-tick", type=int, default=1440)
    p.add_argument("--tick-step", type=int, default=60)
    a = p.parse_args()

    if "-" in a.seeds and "," not in a.seeds:
        lo, hi = (int(v) for v in a.seeds.split("-", 1))
        seeds = list(range(lo, hi + 1))
    else:
        seeds = [int(v) for v in a.seeds.split(",")]

    os.makedirs(a.out_dir, exist_ok=True)
    for seed in seeds:
        d = scenario(a.arm, seed, a.doctrine, a.count, a.front_morale,
                     a.rear_morale, a.last_tick, a.tick_step)
        path = os.path.join(a.out_dir, "%s_%s.json" % (a.arm, seed))
        with open(path, "w", encoding="utf-8", newline="") as f:
            json.dump(d, f, indent=2)
        print(path)


if __name__ == "__main__":
    main()
