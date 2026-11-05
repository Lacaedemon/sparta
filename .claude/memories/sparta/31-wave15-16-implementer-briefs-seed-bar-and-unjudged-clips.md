## An implementer brief front-loads what review and CI block on

Three wave-15 PRs spent extra review or CI rounds on checks the brief could have required before the first push.
PR #1909 (#1904) had four not-clean review rounds before a clean one, on 2026-11-03 PT.
Round one found no `demos/demo.<N>.json` and stale `website/how-to-play.qmd` prose.
Round two rejected a skip manifest written because the case was hard to stage, which `demos/README.md` rules out ("don't use the self-check's difficulty as the excuse").
Round three found the prose still unchanged.
Round four found that the rewrite said "walk" where the code's rate is `jog_speed`.
CI's Coverage job then failed two PRs on patch coverage below the project-wide total:
PR #1912 at 94.74% (36/38) against 95.77%, and PR #1917 at 94.59% (35/37) against 95.76%.
`CLAUDE.md` already says to run `patch_coverage` before pushing a `scripts/` change, so this is the brief failing to carry a written rule, twice.

- **Do:** in every implementer brief, require before the first push:
  - a per-PR `demos/demo.<N>.json` pointing at a clip that shows the change, authoring a new `demos/inputs/*.json` whose expects fail on main if no clip does;
  - a grep of `website/*.qmd` for prose about the changed behaviour, with each claim checked against the constant behind it;
  - `patch_coverage` added to the brief's single `tools/check.sh` invocation (for example `tools/check.sh validate test chars comments units patch_coverage`), as `CLAUDE.md` describes.
- **Don't:** accept a skip manifest because staging is hard, or write a rate or speed word in prose without reading its constant.

(`Lacaedemon/sparta` #1904, PR #1909, PR #1912, PR #1917, 2026-11-03 to 2026-11-04.)

## The bar is no new unexempted failing verdict on seeds 0 to 4, and facing_flutter can count rounding

A PR passes the defect bar when no verdict newly fails on seeds 0 to 4, not only on the clip's own seed, unless the failure carries a fitting exemption.
PR #1912 hashed every `demos/inputs` script on seeds 0 to 4 against main, judged the one clip whose stream moved on dense dumps, and carried one perturbed-seed failure (`cycle_charge` uid 3 `facing_flutter` on seed 1) as an exemption citing #1841.
Part 27's "A new every-seed defect is a regression to fix, not to exempt" says which failures may be exempted at all.
One verdict can fail for a reason outside the sim:
demo dumps write facing to 2 decimals (`DemoState.POSITION_DECIMAL_PLACES`), while `FLUTTER_MIN_SWING_DEG` is 0.1 degrees, so a heading sitting on a rounding boundary reads as a swing.
#1920 records the case: `reform-before-move` uid 5 on seed 1 alternated between -61.89 and -62.67 degrees in the dump while its 4-decimal grid front moved only 0.1 to 0.18 degrees, and the verdict read 4 against a threshold of 3.

- **Do:** hash every `demos/inputs` script on seeds 0 to 4 against main, judge each clip whose stream moved, and exempt a perturbed-seed failure only with a citation to an open issue that fits it.
- **Do:** before fixing or exempting a `facing_flutter` failure, check the swings against a 4-decimal source such as the grid front.
- **Don't:** report a PR's verdicts from the clip's own seed alone.

(`Lacaedemon/sparta` PR #1912, #1841, #1920, 2026-11-04.)

## A clip outside the website catalog has no judge on main

On d0272c6d, 121 of the 238 scripts in `demos/inputs` were not in the website catalog, so no CI sweep judged them on main, and 13 of them failed their expects or verdicts there (#1914).
Part 8's "`check.sh demo_defects` is NOT a CI job" section names the jobs that judge clips: the PR's manifest clip is judged, the demo diff scans only changed catalog transcripts, and the weekly sweep covers only the catalog.
So a local `demo_defects` run on a touched non-catalog clip other than the manifest clip can fail where CI passes, and the failure may predate the PR.

- **Do:** when a local run fails on a non-catalog clip, run the same clip on main before attributing the failure to the PR, and check #1914's list.
- **Don't:** take a green CI run as evidence that a non-catalog clip the PR touched still passes.

(`Lacaedemon/sparta` #1914, 2026-11-04.)
