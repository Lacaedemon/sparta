#!/usr/bin/env bash
# Self-contained unit test for tools/benchmark/refresh_band.py -- the decision the
# weekly baseline refresh makes about whether a measured change is big enough to
# open a PR for. Needs only python3; no Godot binary, no network, no real baseline.
#
# evaluate():
#   1. Change inside the band: suppressed, and the reason names the largest metric.
#   2. Change outside the band on ANY single metric: refreshed, even when the other
#      metrics are quiet -- the band is a max over metrics, not an average.
#   3. A large IMPROVEMENT refreshes too: the largest change is chosen by absolute
#      value, so suppressing only regressions cannot ratchet the baseline upward.
#   4. Exactly at the band: suppressed. The comparison is strictly-greater-than, so
#      the documented noise floor itself counts as noise.
#   5. No committed baseline: always writes, with no deltas to report.
#   6. A custom tolerance is honoured, so the band is caller-configurable rather
#      than baked in.
#   7. Bad input fails fast: a negative tolerance and a stats object missing a
#      metric both raise rather than silently deciding.
#   9. tolerance_from_env(): an unset/empty/blank env value falls back to the module's
#      own default, a supplied value wins, and a malformed one raises. This is what
#      lets the workflow file carry no band literal to drift from this module's.
#   8. A corrupt committed baseline (a non-positive metric, which no real tick time
#      ever is) is REPLACED rather than raising. Raising would wedge the weekly cron:
#      every later run would hit the same bad file and nothing would replace it.
#
# The real refresh case this was built for is a +6.1%/+5.9%/+7.7% week against a
# 20% band, which case 1 reproduces exactly.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MODULE_DIR="$REPO_ROOT/tools/benchmark"

if ! command -v python3 >/dev/null 2>&1; then
  echo "skip: python3 not on PATH; refresh_band.py cannot be exercised" >&2
  exit 0
fi

python3 - "$MODULE_DIR" <<'PY'
import sys

sys.path.insert(0, sys.argv[1])
from refresh_band import (
    DEFAULT_TOLERANCE_PCT,
    evaluate,
    format_delta_table,
    tolerance_from_env,
)

failures = []


def check(label, condition):
    if condition:
        print("  ok   - %s" % label)
    else:
        print("  FAIL - %s" % label)
        failures.append(label)


def stats(mean, p95, mx):
    return {"mean_ms": mean, "p95_ms": p95, "max_ms": mx}


# 1. The real week that motivated the band: +6.1% / +5.9% / +7.7% against 20%.
old = stats(45.107, 50.389, 58.287)
new = stats(47.868, 53.377, 62.770)
r = evaluate(old, new, 20.0)
check("inside band is suppressed", r["write"] is False)
check("inside band names the largest metric", r["largest_metric"] == "max_ms")
check("inside band reports ~+7.7%", abs(r["largest_pct"] - 7.7) < 0.1)
check("inside band reason mentions keeping", "keeping" in r["reason"])

# 2. One loud metric is enough, even when the others are quiet.
r = evaluate(stats(100.0, 100.0, 100.0), stats(100.0, 100.0, 130.0), 20.0)
check("one metric over the band refreshes", r["write"] is True)
check("the loud metric is the one reported", r["largest_metric"] == "max_ms")

# 3. A large improvement refreshes too (absolute value, not signed).
r = evaluate(stats(100.0, 100.0, 100.0), stats(70.0, 100.0, 100.0), 20.0)
check("large improvement refreshes", r["write"] is True)
check("improvement reports a negative change", r["largest_pct"] < 0)

# 4. Exactly at the band is still noise (strict >).
r = evaluate(stats(100.0, 100.0, 100.0), stats(120.0, 100.0, 100.0), 20.0)
check("exactly at the band is suppressed", r["write"] is False)
r = evaluate(stats(100.0, 100.0, 100.0), stats(120.01, 100.0, 100.0), 20.0)
check("just past the band refreshes", r["write"] is True)

# 5. No committed baseline: always write.
r = evaluate(None, stats(1.0, 2.0, 3.0), 20.0)
check("missing baseline writes", r["write"] is True)
check("missing baseline reports no deltas", r["deltas"] == {})
check("missing baseline has no largest metric", r["largest_metric"] is None)

# 6. The band is caller-configurable.
quiet = evaluate(stats(100.0, 100.0, 100.0), stats(105.0, 100.0, 100.0), 20.0)
loud = evaluate(stats(100.0, 100.0, 100.0), stats(105.0, 100.0, 100.0), 1.0)
check("same data suppressed at 20%", quiet["write"] is False)
check("same data refreshed at 1%", loud["write"] is True)
check("the applied tolerance is reported back", loud["tolerance_pct"] == 1.0)
check(
    "default tolerance is the upper bound of the documented 20-30% swing",
    DEFAULT_TOLERANCE_PCT == 30.0,
)

# 8. A corrupt baseline is replaced, not raised on -- otherwise the weekly cron wedges.
for bad in (0.0, -1.0):
    # Guarded: a regression here raises, and an unguarded raise would abort the whole
    # script, skipping every later case and reporting a traceback instead of a label.
    try:
        r = evaluate(stats(bad, 50.0, 60.0), stats(45.0, 50.0, 60.0), 20.0)
    except Exception as exc:
        check("non-positive incumbent (%s) does not raise" % bad, False)
        print("       raised: %r" % (exc,))
        continue
    check("non-positive incumbent (%s) writes rather than raising" % bad, r["write"] is True)
    check("non-positive incumbent (%s) says the baseline was unusable" % bad,
          "unusable" in r["reason"])
    check("non-positive incumbent (%s) reports no deltas" % bad, r["deltas"] == {})

# 9. tolerance_from_env resolves the band, so the workflow needs no literal of its own.
#    A scheduled run passes nothing; only a dispatch override passes a number.
check("unset env takes the module default", tolerance_from_env(None) == DEFAULT_TOLERANCE_PCT)
check("empty env takes the module default", tolerance_from_env("") == DEFAULT_TOLERANCE_PCT)
check("blank env takes the module default", tolerance_from_env("   ") == DEFAULT_TOLERANCE_PCT)
check("a supplied override wins", tolerance_from_env("1.5") == 1.5)
check("an integer-looking override parses", tolerance_from_env("40") == 40.0)
try:
    tolerance_from_env("not-a-number")
    check("a malformed override raises", False)
except ValueError:
    check("a malformed override raises", True)

# 7. Bad input fails fast rather than deciding quietly.
try:
    evaluate(stats(1.0, 1.0, 1.0), stats(1.0, 1.0, 1.0), -1.0)
    check("negative tolerance raises", False)
except ValueError:
    check("negative tolerance raises", True)

try:
    evaluate({"mean_ms": 1.0}, stats(1.0, 1.0, 1.0), 20.0)
    check("missing metric raises", False)
except KeyError:
    check("missing metric raises", True)

# format_delta_table renders every metric it is given.
table = format_delta_table({"mean_ms": 1.0, "p95_ms": -2.0, "max_ms": 3.5})
check(
    "table renders all three metric labels",
    all(lbl in table for lbl in ("mean tick time", "p95 tick time", "max tick time")),
)
check("table has a header and one row per metric", len(table.splitlines()) == 5)
check("table shows a signed positive", "+1.0%" in table)
check("table shows a signed negative", "-2.0%" in table)

if failures:
    print("\n%d assertion(s) failed" % len(failures))
    sys.exit(1)
print("\nall assertions passed")
PY
