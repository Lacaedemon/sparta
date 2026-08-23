# Relief-balance study

Measures whether AI line relief became too strong once a relieved regiment started
surviving its withdrawal. The question, and the reasons a single clip could not
answer it, are in the tracking issue; this directory is the instrument.

## What it runs

Both arms are AI against AI. Team 1 runs the General
(`Battle.ai_doctrine`); team 0 is handed to an AI subcommander group by a scripted
`Ctrl+Shift+1`, so both sides drive the same `Subcommander`/`UnitLeader` pipeline
and therefore the same ordinary inter-unit relief call -- which is the mechanic
under study.

Team 0 having no General was the first thing checked, since only the General holds
a reserve pool and it looked as though the ungeneraled side might be structurally
unable to rotate. It is not: a delegated rear-rank unit that is still `MOVING`
rather than `FIGHTING` satisfies `UnitLeader._relief_candidate` and answers a call.
Measured on a mirrored 6v6, team 0 issued its first `RELIEF` order at tick 340 and
team 1 at tick 640.

**`mirror`** puts both sides in the same shape: a tired front rank of four and a
fresh pair one `REAR_OFFSET` behind, inside `UnitLeader.RELIEF_CALL_RANGE`. Who
wins is a coin flip by construction, and that is the point -- the arm isolates what
relief *costs* rather than who it favours.

Both arms emit their own `map` block rather than running on the default battlefield,
because the default is not symmetric in the two ways that matter here. Its field is
`Rect2(0, 0, 1600, 1200)`, so mirroring about any line but `y = 600` hands one side
more ground; and both default `TERRAIN` patches sit at `y` 380-580 -- a forest that
halves speed and an impassable hill -- which is one team's half whatever midline is
chosen. The arms mirror about the field centre and run on empty terrain.

**`asym`** holds soldiers, unit count, per-unit size **and the morale mix** equal, and
varies only the deployment: team 0 puts all six units abreast while team 1 keeps its
pair back. Team 0's line is four tired and two fresh exactly as team 1's roster is,
with the fresh pair in the centre rather than on a flank. Starting all six of team 0
at the tired value would hand team 1 an undisclosed aggregate-morale edge, and it
would also gate relief directly, since `_relief_candidate` rejects a would-be reliever
below `RELIEF_MORALE_THRESHOLD`. The frontage difference is part of the tactical choice
being measured; a morale difference is not.

The arm was built to make team 0 unable to rotate at all, reasoning that a unit in
the front line is always `FIGHTING` and so fails `_relief_candidate`. **That is
wrong, and the arm's own relief column is what caught it**: over twenty seeds team
0 averaged 3.0 relief episodes against team 1's 3.0. A wide line does not engage
all at once, so whichever units are still closing are non-`FIGHTING` and answer
calls. Read this arm as wide-line-versus-reserved-rank, both rotating. Nothing
here is a rotate-versus-do-not-rotate comparison, and the reason -- an AI army
effectively cannot opt out of rotating -- is a finding rather than a defect in the
harness.

The general lesson is the one a sweep needs anyway: the relief column is this
study's negative control, and it is worth reading before any margin. A column that
was supposed to be zero and is not falsifies the arm, and no other number in the
output would have said so.

Run the arms under a doctrine whose `reserve_fraction` floors to zero on the roster
size in use, which `aggressive` does (`int(6 * 0.1) == 0`) and which is the default
for that reason. A doctrine that does hold reserves pins them at their own spawn
point via `General.reserve_directives`, far behind the line, which fights team 1
four-against-six for a long stretch and swamps the effect under study. Measured over
four seeds: `cautious` gave team 0 a mean margin of +80, `aggressive` -38.

## Running it

```sh
GODOT_BIN=".../Godot_v4.7-stable_win64_console.exe" \
  SPARTA_STUDY_SEEDS=101-120 SPARTA_STUDY_DOCTRINE=aggressive \
  tools/study/relief-balance/run-study.sh mirror /tmp/rb-mirror

python3 tools/study/relief-balance/summarize.py /tmp/rb-mirror --label mirror
```

Each seed is about half a minute, so a twenty-seed arm is roughly ten minutes.
Every parameter the arms turn on -- seeds, doctrine, soldiers per unit, rank morale,
run length, dump interval -- is an environment variable on `run-study.sh` or a flag on
`build-scenarios.py`; run either with no arguments for the list.

`run-study.sh` forwards each variable **only when it is set**, so the generator's own
defaults stay reachable. A shell-side default would shadow them, and that is not
hypothetical: this runner kept passing `--doctrine cautious` after the generator's
default had been changed to a zero-reserve doctrine, so the recommended configuration
was unreachable through the normal entry point and two studies ran on the arm this
README calls invalid. Both runs printed no doctrine at all, which is why the runner now
reads it back off a generated file and echoes it on the first and last line of every
run. If a study's validity turns on a value, that value belongs in its log.

## Comparing two versions of the code

The comparison the study exists for needs a **single-variable** counterfactual, and
two checkouts several commits apart do not give one. Build it by reverting the one
file on top of the current tree instead:

```sh
git worktree add <dir> --detach origin/main
cd <dir> && git checkout <fix-commit>^ -- scripts/UnitRelief.gd
cp -r <main-checkout>/tools/study/relief-balance tools/study/
```

The study tooling is copied in rather than checked out, because it postdates the
commit under test and reads state dumps rather than producing them -- copying it
changes no simulation behaviour. Then run the same arms in both trees and:

```sh
python3 tools/study/relief-balance/summarize.py /tmp/rb-post-mirror \
  --baseline /tmp/rb-pre-mirror --label post --baseline-label pre
```

## Reading the output

`survivors` sums soldiers still on the field at the final tick; a unit destroyed
outright is absent from the dump entirely, so it is a sum over what remains rather
than over a fixed roster. `lost_units` counts the roster entries that went missing.
`relief` counts rising edges of a `RELIEF` order, which approximates episodes --
a dump every `SPARTA_STUDY_TICK_STEP` ticks cannot see an episode that starts and
ends between two samples, so read it as a floor.

`margin` is `survivors[0] - survivors[1]`. Its expected value in the `mirror` arm is
zero, and the arm is mirrored in **setup** only: team 1 runs a General that issues an
army plan, while team 0's delegated group has no General and waits for contact (phase 4
deliberately stands none up for team 0), so the two sides' behaviour differs by
construction even on identical rosters and ground. Check the mirror arm's own margin
before reading anything into any other number, and treat a non-zero mean there as the
harness's floor of asymmetry rather than as a finding. A pre-versus-post comparison is
unaffected -- the same asymmetry sits on both sides and cancels -- but **no single-arm
margin from this harness means anything**, and neither does a single-arm survivor count.

A seed whose run crashes or times out is a **missing sample, not a zero**:
`run-study.sh` drops its directory and warns, and `summarize.py` reports the `n` it
actually had. Check that `n` against the seed range you asked for before quoting a
mean.

**The exit status does not decide that on its own.** `DemoInputRecorder`'s
`CAPTURE_TIMEOUT_SEC` net calls `push_warning` and then `get_tree().quit()`, which
exits **zero** -- so a battle cut short at sixty wall-clock seconds leaves a partial
dump and reports success.

**A short dump is not automatically a truncated one, and dropping every short seed
would bias the study.** A battle that ends decisively freezes `Battle`'s tick counter,
so dumping stops at the moment of victory and the seed arrives short -- mechanically
identical to a wall-clock truncation. Decisiveness correlates with the very quantities
under study, so excluding those seeds would select against the most informative
samples the harness produces. The last snapshot separates the two cases: a decided
battle has at most one team left on the field. Both the runner and `summarize.py`
classify a short seed that way -- DECIDED is kept as a complete sample, TRUNCATED is
dropped/excluded. `run-study.sh` counts the snapshots against the number of
ticks it asked for, which is what actually catches it, and drops the seed when they
disagree. `summarize.py` prints each seed's final tick, marks any that falls short, and
**excludes those rows from every aggregate** -- a warning printed beside a contaminated
mean is worse than no warning, since it reads as a caveat while the number under it is
still wrong.

Its reference is the **maximum** final tick observed, not the modal one: a run cannot
overshoot the tick it was asked for, so the maximum is a bound, whereas the mode is a
vote that elects the wrong answer as soon as most of the set is truncated. Pass
`--expect-final-tick` to bound it from outside, which is the only way to catch a set
where every run was cut off at the same tick -- nothing internal to the data
distinguishes that from a deliberately short study.

## Results

The run this was built for is written up on the tracking issue, not here -- a README that
carries its own findings goes stale the first time someone re-runs it. Two of its
conclusions are about the instrument rather than the mechanic, so they belong here:

- **Read the relief column before any margin.** It is the negative control. A column that
  was supposed to be zero and is not falsifies the arm, and no other number in the output
  would have said so.
- **A doctrine sweep is not currently meaningful**, because `General.reserve_directives`
  pins a held reserve at its spawn point and two of the three doctrines hold reserves. That
  is filed separately; until it lands, run the arms under a doctrine whose reserve fraction
  floors to zero.

## Generated files

`run-study.sh` writes the per-seed scripted-input files under `_generated/<arm>/`,
which is gitignored. They live inside the project rather than a temp directory
because `DemoInputRecorder` opens them through `res://` and cannot see anything
outside it.
