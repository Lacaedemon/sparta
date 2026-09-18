"""Decide whether a refreshed CI benchmark baseline is worth committing.

The weekly refresh measures the GitHub Actions runners' current speed, which
drifts for reasons unrelated to this repo's code. Two functionally identical
runs on a shared runner swing by 20-30% on their own (tools/perf/README.md),
so a refresh whose delta is smaller than that carries no information: it
cannot separate a real change from noise, and opening a PR for it asks a
reviewer a question the attached evidence cannot answer.

Note what this file is NOT. tools/benchmark/baseline.json is a SECONDARY,
informational comparison; benchmark.yml's pass/fail verdict comes from a
same-run PR-vs-base-tip measurement and never reads this baseline. So the
cost of a noise-dominated refresh is reviewer attention, not guard precision,
and a tolerance band is sized to remove that cost rather than to sharpen a
number nothing decides on.

Only the decision lives here, kept out of the workflow's inline script so it
can be unit-tested directly instead of exercised once a week by cron.
"""

import math

# Upper bound of the 20-30% run-to-run swing between functionally identical builds
# on a shared CI runner, documented in tools/perf/README.md. The UPPER bound, not
# the lower one: a band set at 20 would still pass through noise in the 20-30%
# part of that range, which is the exact case this exists to suppress.
# This module is the SINGLE source of the number: the workflow carries no band
# literal of its own, and passes one only when a workflow_dispatch run overrides it.
DEFAULT_TOLERANCE_PCT = 30.0

# Reporting order for the metrics carried in a baseline's "stats" object.
METRICS = ("mean_ms", "p95_ms", "max_ms")

METRIC_LABELS = {
    "mean_ms": "mean tick time",
    "p95_ms": "p95 tick time",
    "max_ms": "max tick time",
}


def tolerance_from_env(raw):
    """Resolve a band from an env value that may be unset or empty.

    A scheduled run passes nothing, so it takes DEFAULT_TOLERANCE_PCT. Only a
    workflow_dispatch override supplies a value, which keeps the default in one
    place rather than duplicated into the workflow file.
    """
    if raw is None or not raw.strip():
        return DEFAULT_TOLERANCE_PCT
    value = float(raw)
    # float() happily accepts "nan" and "inf", and neither is caught downstream:
    # nan fails every comparison, so abs(change) > nan is always False, and inf is
    # never exceeded. Either one silently suppresses every refresh forever, which is
    # the feature quietly doing nothing rather than failing. Reject them here.
    if not math.isfinite(value):
        raise ValueError("tolerance must be a finite number, got %r" % (raw,))
    return value


def is_usable(value):
    """True when a metric can be measured, compared against, and committed.

    One definition of corrupt, shared by the incumbent check, the new-measurement
    check, and any caller rendering a metric. A narrower re-derivation elsewhere
    (testing only <= 0) silently passes NaN, since every comparison against NaN is
    False.
    """
    return math.isfinite(value) and value > 0


def pct_change(old_value, new_value):
    """Signed percent change from old_value to new_value."""
    if old_value == 0:
        raise ValueError("old_value of 0 has no meaningful percent change")
    return (new_value - old_value) / old_value * 100.0


def evaluate(old_stats, new_stats, tolerance_pct=DEFAULT_TOLERANCE_PCT):
    """Decide whether new_stats should replace old_stats.

    old_stats is None when no baseline is committed yet; both are otherwise
    mappings carrying every key in METRICS.

    Returns a dict with:
      write          -- True when the baseline file should be rewritten.
      reason         -- one line explaining the decision, for a job summary.
      deltas         -- {metric: signed percent change}, empty when old_stats
                        is None.
      largest_metric -- the metric with the largest ABSOLUTE change, or None.
      largest_pct    -- that metric's signed change, or None.
      tolerance_pct  -- the band actually applied.

    The largest change is chosen by absolute value so a big improvement is as
    refresh-worthy as a big regression: the baseline tracks runner speed in
    both directions, and suppressing only one would ratchet it.
    """
    # isfinite first: nan fails every comparison, so a bare "< 0" test lets it through
    # and it then suppresses every refresh silently.
    if not math.isfinite(tolerance_pct) or tolerance_pct < 0:
        raise ValueError(
            "tolerance_pct must be a finite non-negative number, got %r"
            % (tolerance_pct,)
        )

    if old_stats is None:
        return {
            "write": True,
            "reason": "No baseline committed yet -- writing the first one.",
            "deltas": {},
            "largest_metric": None,
            "largest_pct": None,
            "tolerance_pct": tolerance_pct,
        }

    missing = [m for m in METRICS if m not in old_stats or m not in new_stats]
    if missing:
        raise KeyError("stats missing required metric(s): %s" % ", ".join(missing))

    # A new measurement that is not a finite POSITIVE number means the benchmark
    # itself went wrong: a tick time is never legitimately zero or negative, any more
    # than it is NaN. Writing one would poison the committed baseline for every later
    # run, so this raises rather than being absorbed like a corrupt incumbent below.
    # Deliberately the same bar as the incumbent check further down -- a value too
    # corrupt to compare against is also too corrupt to commit.
    unmeasurable = [
        m for m in METRICS
        if not is_usable(new_stats[m])
    ]
    if unmeasurable:
        raise ValueError(
            "new stats are not finite and positive for: %s"
            % ", ".join(unmeasurable)
        )

    # An incumbent metric that is non-finite or non-positive cannot anchor a percent
    # change, and a tick time is never legitimately either, so the committed file is
    # corrupt rather than merely stale. Treat it as no usable baseline and write a
    # fresh one. Raising instead would wedge an unattended weekly job: every future
    # run would hit the same bad file, and nothing would ever replace it.
    #
    # isfinite is tested FIRST and separately: json.load accepts a bare NaN, and
    # `nan <= 0` is False, so a non-positive test alone lets NaN through -- after
    # which every band comparison against it is False and the refresh is suppressed
    # forever, reported as a "+nan%" change.
    unusable = [
        m for m in METRICS
        if not is_usable(old_stats[m])
    ]
    if unusable:
        return {
            "write": True,
            "reason": (
                "Committed baseline is unusable (non-finite or non-positive %s)"
                " -- replacing it."
                % ", ".join(unusable)
            ),
            "deltas": {},
            "largest_metric": None,
            "largest_pct": None,
            "tolerance_pct": tolerance_pct,
        }

    deltas = {m: pct_change(old_stats[m], new_stats[m]) for m in METRICS}
    largest_metric = max(METRICS, key=lambda m: abs(deltas[m]))
    largest_pct = deltas[largest_metric]

    if abs(largest_pct) > tolerance_pct:
        reason = (
            "Largest change %s %+.1f%% exceeds the %.1f%% noise band -- refreshing."
            % (METRIC_LABELS[largest_metric], largest_pct, tolerance_pct)
        )
        write = True
    else:
        reason = (
            "Largest change %s %+.1f%% is within the %.1f%% noise band -- "
            "keeping the committed baseline."
            % (METRIC_LABELS[largest_metric], largest_pct, tolerance_pct)
        )
        write = False

    return {
        "write": write,
        "reason": reason,
        "deltas": deltas,
        "largest_metric": largest_metric,
        "largest_pct": largest_pct,
        "tolerance_pct": tolerance_pct,
    }


def format_delta_table(deltas):
    """Render deltas as a markdown table, for a job summary or a PR body."""
    rows = ["| metric | change vs committed baseline |", "| --- | --- |"]
    for metric in METRICS:
        if metric in deltas:
            rows.append("| %s | %+.1f%% |" % (METRIC_LABELS[metric], deltas[metric]))
    return "\n".join(rows)
