## Read the tool's source before changing its config

Part 12 records the lychee fact: a 503 that GitHub returns is not retried, so raising `max_retries` does nothing.
The general habit behind it is the lesson.
The first fix for #1796 raised the retry count on the strength of the setting's name,
and only reading `retry.rs` at the pinned v0.24.2 showed that a 503 reaching `ErrorKind::should_retry` as a rejected status is retried only for 429.

- **Do:** read the retry, exclusion or threshold code at the pinned tool version before changing the tool's config, and name the function in the PR body.

- **Don't:** ship a config knob because its name sounds like the fix.

(`Lacaedemon/sparta` PR #1798, 2026-10-11.)

## Brief each reviewer with the in-flight sibling that reads the same state

Part 22 already says a conflict-free merge is no evidence that two sim changes compose.
The new part is how to catch it while both PRs are still open.
PRs #1802 (#1765) and #1803 (#1781) were in flight together.
#1802's first version (aaf4f68a) skipped its rally slot capture whenever `_slot_deal_pending` was true,
assuming a pending deal reads the bodies.
#1803 at 91c5b0b8, before `_slot_body_deal_pending` existed, made a row-major close-up leave `_slot_deal_pending` true without reading the bodies.
#1803 then added `_slot_body_deal_pending` and a merge-order note,
and #1802, landing second, deleted its own predicate and gated on that one.

- **Do:** when two in-flight PRs touch the same state, give each reviewer the sibling's head and ask what the PR that lands second must change.

- **Don't:** review sibling PRs each against main alone.

(`Lacaedemon/sparta` PRs #1802 and #1803, 2026-10-11.)

## A deferred state change needs an exit for every interruption

PR #1802 (#1765) deferred the rally re-square until the rally coast stopped, so the block would not slide sideways while it turned.
Review rounds 2 and 3 then found the exits the deferral lacked:

- An enemy that attacked during the pending window was turned away from: the unit ended 90 degrees off its attacker.
- Leaving IDLE finished the turn mid-engagement.
- Cancelling on an enemy's approach left an arbitrary fold, and the unit's next order dropped it, moving a slot 172.12 wu.
- Resuming once the enemy left needed hysteresis (1.25 times the radius, held for 30 ticks), or an enemy at the edge flips the cancel on and off.

- **Do:** before building a pending flag, list every way the world can end the window (attack, order, rout, state change, snapshot) and give each one a defined exit and a test.

- **Don't:** add a deferral with only the happy-path exit.

(`Lacaedemon/sparta` PR #1802, 2026-10-11.)

## Check every new const against "Parameters are caller-configurable"

PR #1802 added `RALLY_RESUME_RADIUS_FACTOR` and `RALLY_RESUME_CLEAR_TICKS` as bare consts.
Every local adversarial review round passed them.
The CI review flagged them under CLAUDE.md's rule, and the fix kept them as defaults behind instance fields, as `rout_time` does with `ROUT_TIME`.

- **Do:** put "for each new const: physical constant, solver epsilon, or tunable?" in every reviewer brief.

- **Don't:** accept a new const because consts sit next to it.

(`Lacaedemon/sparta` PR #1802, 2026-10-11.)

## An exemption must read EXEMPT on the clip's own ticks

`demo.1765`'s uid 0 `shape_residual` exemption covered a failure seen only on dense 2-tick samples (56.5 against 30, ticks 862 to 1080).
On the clip's declared state ticks the analyzer read it STALE, and `demos/README.md` treats a STALE exemption as one to remove.
The fix appended state ticks every 10 inside that window, so the regular scan reads it EXEMPT.
Part 20's rule against choosing sample ticks by the verdict they produce still holds:
these ticks were added so the scan sees a failure the clip already has, not so a verdict passes,
and no existing tick moved.

- **Do:** declare enough ticks inside the phase an exemption covers that the regular scan sees the failure, and scope the reason to that phase.

- **Don't:** leave an exemption that only the dense delta needs, where the next reader will delete it as stale.

(`Lacaedemon/sparta` PR #1802, 2026-10-11.)
