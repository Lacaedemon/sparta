## A tier-rule change must be benchmarked on cannae-scale, not only the default battle

The tier pass decides tier per formation, so any change to the distance it measures
changes how many soldiers are simulated per body, and the cost scales with the size of
the blocks the change promotes.

Measured 2026-10-02 (PR #1677): switching the pass from centre distance to the edge gap
between blocks was right for the default battle (a 960 wu deep cavalry squadron opened
far-tier when judged by its centre, 480 wu behind its front), and it left
`large-battle` and `echelon-battle-shallow` unchanged.
On `cannae-scale` it kept 43,656 of 43,720 soldiers close-tier instead of 1,656, about
30x the tick cost, because the 4,000-8,000-man reserve corps read the small enemy
cavalry's front within range.
Two cheaper fixes were measured and did not help: measuring the reach along the line of
centres (27,656 close) and capping the reach at 500 wu (27,656).
What worked was a headcount threshold on the block whose tier is decided
(`Battle.tier_edge_gap_max_soldiers`, 500): edge gap at or under it, centre distance above.
CI's website demo-diff surfaced it first, as a `cannae_scale` state dump timing out at 300 s.

- **Do:** benchmark `cannae-scale`, `echelon-battle`, `echelon-battle-shallow` and `large-battle` on `main` and the branch back to back, and compare the deterministic close-tier counts before pushing a tier change.

- **Do:** read a `demo-diff` dump timeout on a huge clip as a likely tier or cost regression, not a flaky runner.

- **Don't:** validate a tier change on the default 5v5 alone, since its 80-140-man blocks cannot show a per-formation cost blow-up.
