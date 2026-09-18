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
#   7. A corrupt committed baseline (a non-positive, non-finite, or wrongly-typed
#      metric, which no real tick time ever is) is REPLACED rather than raising.
#      Raising would wedge the weekly cron: every later run would hit the same bad
#      file and nothing would replace it. NaN matters specifically: json.load accepts
#      a bare NaN and `nan <= 0` is False, so a non-positive test alone would let it
#      through and suppress every future refresh.
#   8. A NEW measurement that is not a finite positive number RAISES instead, since
#      writing it would poison the committed baseline for every later run. Checked
#      before the no-baseline shortcut, so the very first baseline is guarded too.
#   9. is_usable() is the single definition all three sites share: finite, positive,
#      and an actual number. bool matters most, since it subclasses int and a literal
#      `true` would otherwise read as a 1.0 ms measurement; a string or null would
#      raise a bare TypeError out of isfinite.
#  10. tolerance_from_env(): an unset/empty/blank env value falls back to the module's
#      own default, a supplied value wins, and a malformed one raises. This is what
#      lets the workflow file carry no band literal to drift from this module's.
#      'nan' and 'inf' are rejected explicitly: both parse as floats and slip past a
#      plain non-negative test, then silently suppress every refresh forever.
#  11. Bad input fails fast: a negative tolerance and a stats object missing a metric
#      both raise rather than silently deciding.
#
# The real refresh case this was built for is a +6.1%/+5.9%/+7.7% week, which
# case 1 reproduces exactly against a 20% band -- it is suppressed at the
# committed 30% default too, by a wider margin.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MODULE_DIR="$REPO_ROOT/tools/benchmark"

# Every assertion here needs python3, so without it this file would exit 0 having
# checked nothing -- and check.sh's driver reads only the exit code, so that is
# indistinguishable from a pass. In CI, where python3 is a given (the workflow under
# test runs on it), treat its absence as a failure rather than a silent skip. Locally
# it stays a skip, matching check.sh's own optional-python3 handling.
if ! command -v python3 >/dev/null 2>&1; then
  # GITHUB_ACTIONS, not CI: CI is a generic convention that npm, pytest, cargo and
  # assorted shell profiles also set, so keying off it would tell a local developer
  # they are in CI when they are not. GitHub sets GITHUB_ACTIONS and little else does.
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "error: python3 not on PATH in GitHub Actions; refresh_band.py went unexercised" >&2
    exit 1
  fi
  echo "skip: python3 not on PATH; refresh_band.py cannot be exercised" >&2
  exit 0
fi

python3 - "$MODULE_DIR" <<'PY'
import sys
import traceback

sys.path.insert(0, sys.argv[1])
from refresh_band import (
    DEFAULT_TOLERANCE_PCT,
    evaluate,
    format_delta_table,
    is_usable,
    tolerance_from_env,
)

failures = []


def check(label, condition):
    if condition:
        print("  ok   - %s" % label)
    else:
        print("  FAIL - %s" % label)
        failures.append(label)


def check_value(label, fn, expected):
    """Call fn() and compare, reporting a raise as a labelled failure.

    Bare calls inside check() abort the whole script when the production code
    regresses into raising, which skips every later case and prints a traceback
    instead of naming what broke.
    """
    try:
        actual = fn()
    except Exception as exc:
        check(label, False)
        print("       raised: %r" % (exc,))
        return
    check(label, actual == expected)


def stats(mean, p95, mx):
    return {"mean_ms": mean, "p95_ms": p95, "max_ms": mx}


def run_cases():
    """Every case, in one function so an unexpected raise is reported, not fatal.

    A bare top-level evaluate() call aborts the script when the production code
    regresses into raising, skipping every later case and printing a traceback
    instead of naming what broke. The caller below turns that into a labelled
    failure while preserving the non-zero exit.
    """
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

    # 7. A corrupt baseline is replaced, not raised on -- otherwise the weekly cron wedges.
    for bad in (0.0, -1.0, float("nan"), float("inf")):
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
              "is not a finite positive" in r["reason"])
        check("non-positive incumbent (%s) reports no deltas" % bad, r["deltas"] == {})

    # 8. A non-finite or non-positive NEW measurement is a broken benchmark rather
    #    than a stale baseline, so it raises rather than being written to the file.
    for bad_new in (float("nan"), float("inf"), 0.0, -5.0):
        try:
            evaluate(stats(45.0, 50.0, 58.0), stats(bad_new, 50.0, 58.0), 30.0)
            check("unusable new stat (%s) raises" % bad_new, False)
        except ValueError:
            check("unusable new stat (%s) raises" % bad_new, True)

    # The bootstrap path is validated too. It is the one that writes with no
    # comparison table to make a bad value visible, so checking the measurement
    # only after the no-baseline shortcut would leave the FIRST baseline the least
    # guarded value in the system.
    for bad_new in (float("nan"), 0.0, -3.0, "45", None):
        try:
            evaluate(None, stats(bad_new, 50.0, 58.0), 30.0)
            check("bootstrap rejects an unusable measurement (%r)" % bad_new, False)
        except ValueError:
            check("bootstrap rejects an unusable measurement (%r)" % bad_new, True)
    check_value("bootstrap still writes a good first baseline",
                lambda: evaluate(None, stats(45.0, 50.0, 58.0), 30.0)["write"], True)

    # 9. is_usable is the one definition all three sites share, so pin it directly.
    for ok_v in (0.001, 45.107, 1e9):
        check_value("is_usable(%s) is True" % ok_v, lambda v=ok_v: is_usable(v), True)
    for bad_v in (0.0, -1.0, float("nan"), float("inf"), float("-inf"), True, False,
                  "45.1", None, [], {}):
        check_value("is_usable(%s) is False" % bad_v, lambda v=bad_v: is_usable(v), False)

    # The default parameter itself: every other call passes a band explicitly, so
    # without this nothing would notice DEFAULT_TOLERANCE_PCT being wired up wrong.
    r = evaluate(stats(100.0, 100.0, 100.0), stats(125.0, 100.0, 100.0))
    check("evaluate default band suppresses a 25% change", r["write"] is False)
    check("evaluate default band reports 30.0", r["tolerance_pct"] == 30.0)
    r = evaluate(stats(100.0, 100.0, 100.0), stats(135.0, 100.0, 100.0))
    check("evaluate default band refreshes a 35% change", r["write"] is True)

    # 10. tolerance_from_env resolves the band, so the workflow needs no literal of
    #     its own. A scheduled run passes nothing; only a dispatch override does.
    check_value("unset env takes the module default",
                lambda: tolerance_from_env(None), DEFAULT_TOLERANCE_PCT)
    check_value("empty env takes the module default",
                lambda: tolerance_from_env(""), DEFAULT_TOLERANCE_PCT)
    check_value("blank env takes the module default",
                lambda: tolerance_from_env("   "), DEFAULT_TOLERANCE_PCT)
    check_value("a supplied override wins", lambda: tolerance_from_env("1.5"), 1.5)
    check_value("an integer-looking override parses", lambda: tolerance_from_env("40"), 40.0)
    for bad_raw in ("not-a-number", "nan", "inf", "-inf"):
        # nan and inf parse fine as floats and are NOT caught by a plain "< 0" test:
        # nan loses every comparison and inf wins every one, so either silently turns
        # the refresh off for good instead of failing.
        try:
            tolerance_from_env(bad_raw)
            check("override %r raises" % bad_raw, False)
        except ValueError:
            check("override %r raises" % bad_raw, True)

    for bad_tol in (float("nan"), float("inf")):
        try:
            evaluate(stats(100.0, 100.0, 100.0), stats(200.0, 100.0, 100.0), bad_tol)
            check("evaluate rejects a %s band" % bad_tol, False)
        except ValueError:
            check("evaluate rejects a %s band" % bad_tol, True)

    # 11. Bad input fails fast rather than deciding quietly.
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


try:
    run_cases()
except Exception:
    check("all cases run without an unexpected exception", False)
    traceback.print_exc()

if failures:
    print("\n%d assertion(s) failed" % len(failures))
    sys.exit(1)
print("\nall assertions passed")
PY
