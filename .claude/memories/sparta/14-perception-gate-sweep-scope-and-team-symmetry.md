## When gating AI decisions on perception, sweep firing decisions as well as movement -- and name every found call site, gated or not

A perception/fog gate on AI decision-making is easy to sweep incompletely
by grouping "the unit decides where to go" and "the unit decides to shoot"
as one thing,
when they are separate call sites sharing the same unfogged candidate.

Battle-AI phase 5 (issue #588) swapped the omniscient placeholder
for a fogged view at the command level,
then gated `Unit._think()`'s auto-advance-on-detect fallback
and `Unit._support_tick`'s threat-chase branch -- both movement --
and reported that sweep complete.
Review of that round then found `_support_tick`'s and `_think()`'s
ranged-fire-at-standoff branches still ungated a few lines from the now-gated chase branch,
sharing the exact same unfogged `nearest_enemy_to(...)` candidate:
a unit could loose a visible volley at,
and enter `FIGHTING` against,
an enemy its own side had never sighted,
since missile range reaches well past fog-restricted sight.

A second, related gap survived three more review rounds before it was caught:
docs and code comments described the gate's exemption boundary
as "already in weapon reach (melee contact OR missile range),"
which self-contradicts the fix above --
missile fire at standoff,
within missile_range but not yet in melee contact,
is itself one of the gated branches,
not exempt from the gate.
Only true melee contact is unconditionally exempt;
stating the boundary as "weapon range" is wrong for any ranged unit,
and reads as correct until someone checks it against the actual gated branches.

The same sweep discipline also surfaces call sites that are deliberately left ungated,
and those need disclosure rather than silence.
Once a target has already been legitimately acquired through a perception-gated decision,
`Unit._think()`'s explicit-target chase branch keeps closing
on that target's current live position every tick
with no further perception re-check --
gating it naively would also cancel a player's own already-issued attack order
the instant perception lapses,
which is a design question
(does a commander recall an order already given, or trust the last position reported?)
rather than a bug to silently patch.
It was named in the docs and in a code comment,
and the actual fix (a last-known-contact memory model)
deferred to a follow-up issue rather than either patched blind or left unmentioned.

**Do:** enumerate every call site that acts on a perceived-enemy candidate
(every `UnitCombat.shoot` caller, every not-yet-`FIGHTING` targeting decision),
state the gate's exemption boundary precisely
(melee contact, not "weapon range" or a detection radius),
and report each site found in one table --
gated, already gated, or deliberately exempt with a stated reason --
rather than a narrative that only mentions the site being fixed this round.

**Don't:** treat "movement/chase is gated" as "perception is gated"
(a firing decision built on the same unfogged scan is a separate call site with its own gap,
not a consequence of the movement fix);
describe an exemption as "already in weapon reach" when only melee contact actually qualifies;
or leave a found-but-deliberately-ungated call site undisclosed.

(`Lacaedemon/sparta` issue #588:
the round that gated the two movement call sites reported the sweep complete;
the next review found the two firing call sites that sweep had missed
and required a full call-site table;
a later review found the "already in weapon reach" boundary claim
self-contradicted that fix
and required naming the melee-contact-only boundary precisely
and disclosing the explicit-target-chase exception,
deferred to `Lacaedemon/sparta#1626`.
2026-09-22/23.)

## A perception gate placed in per-unit code applies to the player's units too -- decide the team scope explicitly and state the player-visible effect

The same #588 work:
the fire and chase gates above live in `Unit`, which both teams share,
so with fog on the player's own idle ranged units and Support-stance units
also hold fire on an enemy their side has not sighted --
`Battle.ai_team_perceives(team, enemy)` is team-agnostic by construction,
not an AI-only check bolted on top.
The website's first description of the mechanic,
and the design docs' own prose,
framed all of it as enemy-AI-only,
which was wrong for three of the four gated branches --
only the auto-advance-on-detect fallback is genuinely AI-exclusive,
because it is gated on `auto_advance_on_detect`
(always false for a player-commanded unit,
which already held formation regardless of fog).

Confirming the existing (already-shipped) symmetric behavior
rather than narrowing it to AI-only
was itself a decision that needed making explicitly,
not merely inheriting the scope of the issue that motivated the gate.
Once made, the decision needed the same evidence a code change would:
GUT tests for the player's own side mirroring the enemy-side pairs already in place,
and a plain-language disclosure everywhere the mechanic was described --
the website (retitled to name the symmetry directly:
"Fog of war is symmetric -- it holds your own troops back too")
and both design docs,
not just the code comments only another engineer would read.

**Do:** when a gate lives in shared per-unit code,
decide its team scope explicitly (symmetric vs. one-team-only)
rather than inheriting the scope of the issue that motivated it;
add same-shape tests for the other team to prove the decided scope;
and state the player-visible consequence on the website and in the docs in plain terms
("your own units will not fire on an enemy you haven't sighted, even in range").

**Don't:** describe a per-unit gate as AI-only
just because the triggering issue was about the AI --
check who else shares the code path before writing the docs,
and don't let "the fix works" substitute for
"the scope decision was tested and disclosed for both sides."

(`Lacaedemon/sparta` issue #588:
the gate applied to both teams by construction from the round that added it
(`Battle.ai_team_perceives` takes any team int),
but review caught that the docs and website described it as AI-only,
and required deciding the team scope explicitly,
adding player-side tests proving it,
and disclosing the effect in plain language.
2026-09-23.)
