## Read the tool's source before changing its config

The first fix for #1796 raised lychee's retry count so that GitHub's 503 answers would retry.
lychee v0.24.2 retries only timeouts and 429 (`retry.rs`, `ErrorKind::should_retry`), so the change would have done nothing.
The adversarial review caught it, and the merged fix checks this repo's own `blob/main` links against the tracked tree instead.

- **Do:** read the retry, exclusion or threshold code at the pinned tool version before changing the tool's config, and cite the line in the PR body.

- **Don't:** ship a config knob because its name sounds like the fix.

(`Lacaedemon/sparta` PR #1798, 2026-10-11.)

## A relayed cause is a hypothesis until it is measured

#1799 was filed with the cause an implementation run relayed: router men linger in the engaged tier.
A probe on main refuted it.
Giving engaged router men the flee feed-forward moved the end of contact by -2 and +1 ticks.
The real driver was body acceleration: 40 wu/s^2 takes about 330 ticks to reach flee pace, and a pursuer that can match it stays in contact.
The issue was retitled as a design question.

- **Do:** mark an unmeasured cause "inferred" in the issue body, and measure it with a toggle before calling it the cause.

- **Don't:** file a relayed cause as fact, even when the relaying run measured other things carefully.

(`Lacaedemon/sparta` #1799, 2026-10-11.)

## Sibling PRs that read the same state interact without conflicting

PRs #1802 (#1765) and #1803 (#1781) were in flight together and both read `_slot_deal_pending`.
#1803 changed what a pending deal means: a row-major close-up no longer reads the bodies.
#1802's rally re-square skipped its slot capture whenever a deal was pending, on the assumption that the deal read the bodies.
The two branches never conflicted in git.
The adversarial reviewer found the interaction only because its brief named the sibling branch.
The second PR to land deleted its own predicate and gated on #1803's `_slot_body_deal_pending`.

- **Do:** when two in-flight PRs touch the same state, brief each reviewer with the sibling's head, and ask what the PR that lands second must change.

- **Don't:** read "no merge conflict" as "no interaction".

(`Lacaedemon/sparta` PRs #1802 and #1803, 2026-10-11.)

## A deferred state change needs an exit for every interruption

PR #1802 (#1765) deferred the rally re-square until the rally coast stopped, so the block would not slide sideways while it turned.
The deferral took four review rounds, because each round found an exit it lacked:

- An enemy that attacked during the pending window got turned away from: the unit ended 90 degrees off its attacker.
- Leaving IDLE finished the turn mid-engagement.
- Cancelling on an enemy's approach left an arbitrary fold, and the unit's next order dropped it, moving a slot 172.12 wu.
- Resuming once the enemy left needed hysteresis (1.25 times the radius, held for 30 ticks), or an enemy at the edge flips the cancel on and off.

- **Do:** before building a pending flag, list every way the world can end the window (attack, order, rout, state change, snapshot) and give each one a defined exit and a test.

- **Don't:** add a deferral with only the happy-path exit.

(`Lacaedemon/sparta` PR #1802, 2026-10-11.)

## Check every new const against "Parameters are caller-configurable"

PR #1802 added `RALLY_RESUME_RADIUS_FACTOR` and `RALLY_RESUME_CLEAR_TICKS` as bare consts.
Six rounds of local adversarial review passed them.
The CI review flagged them under CLAUDE.md's rule, and the fix kept them as defaults behind instance fields, as `rout_time` does with `ROUT_TIME`.

- **Do:** put "for each new const: physical constant, solver epsilon, or tunable?" in every reviewer brief.

- **Don't:** accept a new const because consts sit next to it.

(`Lacaedemon/sparta` PR #1802, 2026-10-11.)

## An exemption must read EXEMPT on the clip's own ticks

`demo.1765`'s uid 0 `shape_residual` exemption covered a failure seen only on dense 2-tick samples (56.5 against 30, ticks 862 to 1080).
On the clip's declared state ticks the analyzer read it STALE, and the analyzer's own description of STALE is an exemption to remove.
The fix appended state ticks every 10 inside that window, so the regular scan reads it EXEMPT.
Appending ticks is not moving them.

- **Do:** declare enough ticks inside the phase an exemption covers that the regular scan sees the failure, and scope the reason to that phase.

- **Don't:** leave an exemption that only the dense delta needs, where the next reader will delete it as stale.

(`Lacaedemon/sparta` PR #1802, 2026-10-11.)
