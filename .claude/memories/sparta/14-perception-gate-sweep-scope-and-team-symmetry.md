## When gating AI decisions on perception, sweep firing decisions as well as movement/targeting

A perception/fog gate on AI decision-making is easy to sweep incompletely by
grouping "AI decides where to go" and "AI decides to shoot" as one thing when
they are separate call sites. Battle-AI phase 5 (issue #588) swapped the
omniscient placeholder for a fogged view command-level, then gated
`Unit._think()`'s auto-advance-on-detect fallback and `Unit._support_tick`'s
threat-chase branch -- both movement. Review of that round then found
`_support_tick`'s and `_think()`'s ranged-fire-at-standoff branches still
ungated three lines away from the now-gated chase branch, sharing the exact
same unfogged `nearest_enemy_to(...)` candidate: an AI unit could loose a
visible volley at, and enter `FIGHTING` against, an enemy its own side had
never sighted, since missile range reaches well past fog-restricted sight.

**Do:** enumerate every call site that acts on a perceived-enemy candidate
(every `UnitCombat.shoot` caller, every not-yet-`FIGHTING` targeting
decision), not only the ones already found -- grep the whole targeting
surface (`UnitTargeting.nearest_enemy_to` and its callers) rather than
stopping once movement is gated -- and add a fog-on/fog-off test pair for
each one gated.
**Don't:** treat "movement/chase is gated" as "perception is gated" -- a
firing decision built on the same unfogged scan is a separate call site with
its own gap, not a consequence of the movement fix.

(`Lacaedemon/sparta` issue #588, branch `worktree-agent-ac3cfa9c275f9d794`
commits `c36d459e` then `d4324879`, 2026-09-22/23.)

## A perception gate placed in per-unit code applies to the player's units too -- state the player-visible effect

The same #588 work: the fire and chase gates above live in `Unit`, which both
teams share, so with fog on the PLAYER's own idle ranged units and
Support-stance units also hold fire on an enemy their side hasn't sighted --
`Battle.ai_team_perceives(team, enemy)` is team-agnostic by construction, not
an AI-only check bolted on top. The website's first description of the
mechanic (and the design docs' own prose) framed all of it as enemy-AI-only,
which was wrong for three of the four gated branches -- only the
auto-advance-on-detect fallback is genuinely AI-exclusive, because it is
gated on `auto_advance_on_detect` (always false for a player-commanded unit,
which already held formation regardless of fog).

**Do:** when a gate lives in shared per-unit code, decide its team scope
explicitly (symmetric vs. one-team-only) rather than inheriting the scope of
the issue that motivated it, add same-shape tests for the OTHER team to prove
the decided scope, and state the player-visible consequence on the website
and in the PR/docs in plain terms ("your own units will not fire on an enemy
you haven't sighted, even in range").
**Don't:** describe a per-unit gate as AI-only just because the triggering
issue was about the AI -- check who else shares the code path before writing
the docs.

(`Lacaedemon/sparta` issue #588, branch `worktree-agent-ac3cfa9c275f9d794`
commit `e3116a44`, 2026-09-23.)
