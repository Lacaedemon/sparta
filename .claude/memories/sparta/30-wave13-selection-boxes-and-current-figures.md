## A demo's selection box can catch a unit through its raised standard

`Unit.intersects_rect` selects a unit when the box touches its men (grown by a body radius), its regiment point, its block centre or its raised standard.
The standard is drawn above the block, over the ground of a unit standing behind it.
In #1840 (PR #1874) the `line_relief` box caught the tired unit's standard and the `passage_of_lines` box caught all three tired units' standards, so the right-click on a tired unit became a ground order for every selected unit and RELIEF never formed.
`passage_of_lines` still passed its 74 verdicts on main, because it had no order expects.
Tracked in #1875, which also asks for a selection field in the state dump.

- **Do:** check a new or moved selection box against every unit's men, regiment point, centre and standard, and pin the order it should produce with an expect.

- **Don't:** take a demo's passing verdicts as evidence its input does what its comment says, when no expect pins the order.

(`Lacaedemon/sparta` #1840, PR #1874, #1875, 2026-10-29.)

## Re-measure an issue's figures on current main before briefing an implementer

The #1837 brief quoted per-seed failures from the issue's comments, measured against older mains.
On main 46d11518, two of the three named cases (`battle_ai_leaders` uid2, `general_doctrine_reserves` uid1) passed on every seed, and one cited exemption (in `demos/camera-showcase.json`) did not exist: the only "1837" there was a zoom value.
The implementer caught this, but only after the brief had set its targets.

- **Do:** re-derive the figures and file references a brief asserts from current main (a dense dump, a `git grep` on `origin/main`) and paste the query beside them.

- **Don't:** copy an issue comment's figures into a brief as the current state.

(`Lacaedemon/sparta` #1837, PR #1879, 2026-10-29.)

## A merge grant relayed through the coordinator does not set mwc

Ezra's "mwc" reached the thread session through the coordinator's relay first.
`ai-session.sh enable-mwc` was refused twice by the auto-mode permission classifier as self-modification, because the relay is not the user's own message.
The same command ran once Ezra's own message arrived in the thread.

- **Do:** enable mwc only on the user's own message in the thread, and tell them plainly when a relayed grant could not be set.

- **Don't:** retry the grant in new command shapes after a refusal.

(`Lacaedemon/sparta` gii wave 13, 2026-10-29.)
