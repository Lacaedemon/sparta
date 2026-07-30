# Computations per tick — the evidence a backend-only performance PR ships

A backend-only performance PR changes how much work the simulation does without changing what
a player sees. That combination is exactly the one a reviewer cannot check by reading the diff
or watching a clip, so this directory exists to make the claim checkable:

- **A before/after graph of computations per tick** — deterministic work counts, x = tick,
  y = operations, one line per build.
- **A demo video recorded after the improvement** — proof the optimization didn't quietly
  change the battle it was optimizing.

Both are required. See CLAUDE.md's "Backend-only performance PRs" section for the policy; this
file is how you produce the artifacts.

## Why counts and not milliseconds

`tools/benchmark/` already measures wall-clock tick time, and it stays the right tool for "does
this build hold the 60fps budget on the reference hardware". It is the wrong tool for "did this
PR remove work": `benchmarks/baseline.json`'s own header documents a run-to-run swing around
20–30% between functionally identical builds on a CI runner, which is wide enough to hide a
real win or manufacture a fake one. The repo has already spent PRs chasing benchmark
"regressions" that turned out to be a stale baseline or pure runner noise.

Counting is immune to that. `scripts/SimOps.gd` tallies the sim's dominant work units — grid
insertions, broadphase candidates, steering and contact pairs, body steps, melee reach checks,
regiment contact checks, unit think passes, and the square-root-class evaluations across those
passes.
The same scenario and seed produce byte-identical counts on any machine, so the two lines on
the graph differ only where the code actually changed.

Counting is off unless a run asks for it, and every call site sits at PASS granularity — once
per steering pass, per contact pass, per unit-step — passing a batch size the pass already
knows. An ordinary tick pays a few dozen early-returning static calls in total. That placement
is load-bearing, not stylistic: the same counts taken per-soldier cost a measurable ~2% of
every tick, which is why the per-soldier proximity queries are deliberately uninstrumented and
the broadphase's candidate totals are tallied by its callers instead of inside `query()`.

## Recording a before/after graph

One command, from the repo root, with a Godot 4.7 binary on `PATH` or in `GODOT_BIN`:

```sh
GODOT_BIN=/path/to/godot tools/perf/ops-before-after.sh
```

It runs the benchmark twice — once in a throwaway worktree at the merge-base with `origin/main`,
once in your tree — writes `demos/shots/ops-per-tick.png`, and prints a markdown table of the
per-bucket means and their change, ready to paste into the PR body. The two runs are sequential
on purpose: two Godot processes on one machine corrupt each other's `user://settings.cfg` and
import cache (see `.claude/memories/sparta.md`).

Useful knobs: `SPARTA_PERF_BUCKET` to graph one bucket instead of the total,
`SPARTA_PERF_SCENARIO` / `SPARTA_PERF_SCALE` to change the workload on both sides,
`SPARTA_BENCHMARK_TICKS` to shorten a run while iterating, and `SPARTA_PERF_KEEP=1` to keep the
recorded series so you can re-plot other buckets without re-recording.

To record a single side by hand — or to re-plot from series you already have:

```sh
SPARTA_BENCHMARK_SERIES=/tmp/after.json SPARTA_BENCHMARK_LABEL=after \
  tools/benchmark/run-benchmark.sh

tools/perf/plot-ops-per-tick.py --before /tmp/before.json --after /tmp/after.json \
  --bucket grid_candidate --out demos/shots/ops-per-tick.png
```

`plot-ops-per-tick.py` and its `tinyplot.py` renderer are pure Python standard library — no
matplotlib, no pip install — because the graph is required on every such PR and the tool has to
run wherever the author (or an automated agent) happens to be working.

`demos/shots/ops-per-tick-example.png` is what the output looks like — there, the two committed
echelon scenarios (reserves parked beyond the demote range vs. inside the hysteresis band), which
differ in how much the tier thresholds promote rather than in code, so the shape of a real
before/after is visible without waiting for one.

## Reading the result

- **Lines separate and the gap holds across ticks** — the optimization removed work. Say which
  bucket moved and by how much; the printed table gives you both.
- **Lines coincide exactly** — the change did not touch a counted path. That is a real finding,
  not a failed measurement: either the hot path you optimized is one no bucket covers, or the
  change is cheaper-per-operation rather than fewer-operations (a `distance_to` →
  `distance_squared_to` swap moves `sqrt_eval` only where the loop is instrumented). Say which,
  and pair the claim with timing evidence instead of implying the graph showed a win.
- **The `after` line is higher** — the change added work somewhere. Worth understanding before
  merging even when the wall clock happens to look fine.

## Keeping the counters honest

Two rules for anyone editing an instrumented pass:

1. **A counter counts what it says it counts.** If you add an early `continue` ahead of a
   tally, or move a call site inside a loop, you have changed the meaning of a number that
   older recorded series are compared against — update the bucket's doc comment in
   `scripts/SimOps.gd` and say so in the PR.
2. **Never call into `SimOps` from an inner loop or a per-soldier function.** Tally into a
   local integer — or derive the count arithmetically from the loop bounds, as
   `SoldierMelee.resolve` does — and report once per pass. The existing sites all follow this;
   copy the nearest one, and re-measure with `tools/benchmark/run-benchmark.sh` if you add a
   site to a path that runs more often than once a tick.

`test/unit/test_sim_ops.gd` guards the module and the broadphase wiring.
