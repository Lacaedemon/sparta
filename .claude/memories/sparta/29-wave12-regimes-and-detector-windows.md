## Measure a mechanism in every regime the target clip runs it in

#1865 (PR #1871) now re-deals a block's ranks at the quarter when an order to a block standing when it comes squares a fold within 10 degrees of a quarter turn, if the block is no wider than 2.8 times its depth.
The first version applied to every order; the band (d25c4a4f) and the 2.8 width-to-depth cut (6cab4c33) were chosen from probes of 15 blocks squared holding ground.
The clip the issue was filed for, `sweep_routers` uid 4, squares its fold while marching, and there the re-deal was worse than main: worst shape residual 30.1 and 30.5 against 22.2 and 22.0 on seeds 0 and 3, judged without the transit window.
08e354f5 and 87c98c3a limited the re-deal to a block not marching when the order comes, after which every catalog clip's hash stream matched main's on the clip seed (and the melee clips on seeds 1 to 4), and #1865 stayed open for the marching case.

- **Do:** before choosing a threshold, measure the mechanism in each regime the target clip exercises (holding ground, marching, chasing), and scope it to the regimes it was measured in.

- **Don't:** carry a band chosen from probes in one regime to every caller.

(`Lacaedemon/sparta` #1865, PR #1871, d25c4a4f, 6cab4c33, 08e354f5, 87c98c3a, 2026-10-26.)

## A defect-scan window for a new event must not open on events main already judges

To let a re-dealt block re-form without scoring it as scrambled, #1865 added a `_last_redeal_tick` stamp that opens a transit window in the shape-residual scan.
The first version stamped every quarter re-deal, including the exact-quarter re-deals main already had, so the window hid failures main reports: battle_ai_leaders uid 1 (25.7 on seeds 0 to 4), quarter_turn_resquare uid 0 (21.5) and quarter_turn_residue uid 0 (13.56 against 13.5).
5ecb7c1a stamped only the re-deals the band adds, and 96229439 bounded the window by twice the time the farthest man needs to walk to his slot at jog speed, plus a second.
This is part 27's "judge an exemption with every exemption removed" applied to a detector's own suppression.

- **Do:** when a detector gets a new suppression window, re-judge every clip it touches with the window off, and confirm that clips identical to main still read as on main.

- **Don't:** key a suppression window to an event that also covers behaviour main already judges.

(`Lacaedemon/sparta` #1865, PR #1871, 5ecb7c1a, 96229439, 2026-10-26.)
