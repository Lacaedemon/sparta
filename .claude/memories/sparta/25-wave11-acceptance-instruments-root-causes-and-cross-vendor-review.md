## An acceptance instrument must report its power, and be validated on effects it was not tuned on

#1826 (PR #1830, merged) built the perturbed-seed melee comparison that part 24 called for.
Its first version looked validated: a null run flagged 0/138 rows and a known effect (flee speed x0.7) flagged 3 rows.
Review of that version found the validation circular.
The travel threshold had been lowered from 3 m to 1 m after the known-effect run, and the HIGH-power claim rested on K=8 seeds, where power at 2 SD was 28%.
It took five review rounds to get a defensible instrument:

- K=16 seeds by default, and a minimum detectable shift (MDS) reported per row;
- the MDS set at 80% power, since round 2 found the first one was 50% power;
- thresholds taken from the null spread (0.5x robust SD), not from a run that already showed the effect;
- Fisher's exact test for indicator rows, where the Hodges-Lehmann shift gate is blind, and a "not comparable" mark where the MDS is undefined.

The figures that survived review: null 0/200, flee x0.85 flagged 3 of 197 rows, wound x0.8 flagged 35 of 191, and the #1806 back-test flagged 0 of 42.
The instrument then paid for itself on #1792.
Its first fix (62c5fc40) flagged 41 of 180 rows.
The flags included a trapped_routing router regression, fewer breaks (charge uid7 never breaks) and lower losses on both sides.
Single-seed comparison is what part 24 and #1826 set out to replace, because per-clip outcomes there can be chance.

- **Do:** make an acceptance instrument print the smallest shift it can detect for each row, and validate it on known effects (and a null) that were not used to choose its thresholds.

- **Don't:** report "flagged nothing" without saying what the instrument could have seen, or tune a threshold on the run that is then cited as its validation.

(`Lacaedemon/sparta` #1826, PR #1830, #1792, 2026-10-12 to 2026-10-13.)

## When two fixes fail on the same upstream condition, fix the condition

#1792 (hold the slot grid on a small in-contact re-face) failed acceptance: trapped_routing routers regressed and the swing in `coast_to_stop` turned out to be accidental lethality.
Only front ranks strike, so a man inside the footprint was never struck (#1834).
The first #1834 fix, an all-ranks interior strike, failed too: 52 of 210 rows flagged and lethality up broadly (`fighting_withdrawal` t1 56 to 7.5).
The `coast_to_stop` result and #1834's over-lethality share one cause.
Blocks interpenetrate 3 to 4 ranks from first contact in about 25 clips, so every all-ranks rule fires constantly.
#1827 is that condition.
On 2026-10-14, on d129a960 (#1827's first version, before the review rounds changed it), the median penetration fell from 2.98 to 0.06 ranks.
With #1834 on top of d129a960 the over-lethality went away.
#1792's own regressions did not share that cause.
The trapped_routing router regression and the charge/showcase uid7 never-break persisted with #1834 combined, and again on #1827's branch, because those are cavalry and archer pairs that #1827 does not cover.
As of 2026-10-15, PR #1838 (#1827) is open, so #1792 and #1834 have not landed: their commits stay local.

- **Do:** when a second fix fails the same acceptance check as the first, ask what condition both depend on, and measure it directly (here, penetration in ranks) before adding a third fix.

- **Don't:** stack a compensation on a compensation, or tune a rule's gate until one clip passes while the upstream condition is untouched.

(`Lacaedemon/sparta` #1792, #1834, #1827, PR #1838, 2026-10-13 to 2026-10-15.)

## Cross-vendor review found complementary defects on one PR, and its findings needed verifying

This was observed on one PR (#1838, for #1827) over five rounds.
Each round, the same head was reviewed by agy (Gemini, `gemini-4-argon-high`, read-only plan mode) and by a Claude adversarial reviewer.
Their findings only partly overlapped each round:

| Round | agy | Claude | Shared |
|---|---|---|---|
| 1 | 12 | 8 | 4 |
| 2 | 7 | 12 | 2 |
| 3 | 6 | 8 | 3 |
| 4 | 8 | 8 | 6 |
| 5 | 4 | 4 | 3 |

The split was clearest in round 2.
There agy found more code-path defects, such as an acquisition cap in `nearest_enemy_to`.
Claude found more data and prose problems, such as stale docs and exemption reasons that contradicted the cited issue numbers.
Claude's round 1 and round 3 findings were mostly code findings: the offset ratchet, per-pair cost before the distance reject, and the eager fallback calls.
agy's round 1 list included several unextended contact sites.
One round 1 finding of agy's named two functions that do not exist.
The two reviewers also disagreed in round 1: Claude said no other contact site was missed while agy listed several.
The finisher grepped in response and reported after round 1 (head 7d9e0ac0, 2026-10-14):
"Engaged fraction, morale and rally were genuinely missed and are fixed.
The other two agy names don't exist.
`clear_dist` is a shove length."
So agy was partly right (3 real misses), and its list also held 2 functions that do not exist.

- **Do:** run a second-vendor reviewer on a large change, send both lists to the implementer, and check every finding against the code (grep the cited function) before acting on it.

- **Don't:** act on a finding because its citation looks specific, or treat the union of two reviewers as verified.

(`Lacaedemon/sparta` #1827, PR #1838, 2026-10-14.)

## A rebuttal is a claim to verify, like any finding

In round 3 the implementing agent rebutted a finding on `nearest_routing_enemy`, saying the sweep-routers stance was cavalry-only.
The rebuttal was relayed unchecked into the next round.
In round 4 both reviewers independently showed it false: sweep-routers is not cavalry-only.
The rebuttal was withdrawn and a fallback was added.

- **Do:** grep the code behind a rebuttal's premise before sending or accepting it, with the same care as a finding.

- **Don't:** relay an agent's "this is out of scope, it only affects X" without checking X.

(`Lacaedemon/sparta` PR #1838, 2026-10-14.)

## Issue text written from an agent's numbers inherits the agent's errors

Two issues filed from the #1827 finisher's handback needed correction comments.
#1839 (square contact) blamed squares.
The stall was caused by the #1827 branch itself, which excluded squares from the front-line extension.
#1840 (RELIEF order) quoted overlap figures of 0.19 to 1.27 wu that were measured on the branch, not on main (main passes at 5.22 wu on its own seed and dips to 0.11 wu on perturbed seed 3).

- **Do:** state on which commit each number was measured, and have a reviewer check an issue's claims against the code and a main baseline before filing.

- **Don't:** copy an agent's causes and figures into an issue body unchecked.

(`Lacaedemon/sparta` #1839, #1840, 2026-10-14.)

## Verify a "platform-only" claim before writing it into an exemption

#1840 first said the RELIEF failure was Windows only, because the Linux sweep showed the RELIEF forming.
A second correction showed the claim wrong.
The Linux sweep never ran that input, since its `line_relief` clip uses `line-relief-queue.json`.
The RELIEF in `relief-fighting-withdrawal.json` never forms on any platform: the tick-30 selection box takes in uid0's rear ranks as well as uid1, and selection is deterministic position arithmetic.

- **Do:** before calling a failure platform-specific, confirm the other platform ran the same input.

- **Don't:** write a platform scope into an exemption reason from a sweep that exercised a different clip.

(`Lacaedemon/sparta` #1840, 2026-10-15.)

## Balance run order and repeat batches in A/B performance comparisons

On #1827 the round-3 perf figure for large-battle (f370562d) was +3.9% against main, from a single run order.
Running both orders on 09ad356b gave about +10% on large-battle in each order.
The round-4 report compared 09ad356b and f370562d head to head on large-battle in both orders: +8% with f370562d first, and -1% in reverse (46.7 vs 47.2 ms).
Both trees had an identical close-tier trajectory (mean 1285.44).
So round 4's code changes did not move perf.
Round 3's +3.9% was a single-batch, single-order reading that later balanced batches did not reproduce.
Main vs 09ad356b read +9.2% with main first and +10.7% with head first, so order alone cannot explain the gap.
The handback also notes session noise: main itself ranged from 38 to 46 ms across batches, and between-session noise is the likely cause.
The order effect is real, as the head-to-head shows (+8% against -1% for the same two trees).
The branch also kept about 4.3% more close-tier soldiers alive, so the per-soldier cost is about +5%.
Cannae measured about 0 and was noisy.

- **Do:** run branch-first and main-first, repeat the batches, report all of them, and normalise by the work done (here, soldiers alive in the close tier).

- **Don't:** report a single-batch or single-order A/B figure as the cost of a change.

(`Lacaedemon/sparta` PR #1838, 2026-10-15.)
