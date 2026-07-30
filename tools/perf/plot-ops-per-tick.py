#!/usr/bin/env python3
"""Graph computations per tick (y) against tick (x), before vs after an optimization.

Input is one or two per-tick work series recorded by tools/benchmark/BenchmarkRunner.gd
(SPARTA_BENCHMARK_SERIES). Output is a PNG for the PR description plus a markdown summary
table on stdout.

    tools/perf/plot-ops-per-tick.py --before before.json --after after.json \
        --out demos/shots/ops-per-tick.png

Counts are deterministic for a given scenario and seed, so the two lines are directly
comparable -- unlike the wall-clock series recorded alongside them, which carries the CI
runner's own noise. See tools/perf/README.md.
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tinyplot import Canvas, text_width  # noqa: E402

WIDTH, HEIGHT = 1100, 560
MARGIN = {"left": 108, "right": 34, "top": 74, "bottom": 62}

INK = (34, 38, 46)
MUTED = (120, 128, 140)
GRID = (223, 227, 233)
BEFORE_COLOR = (198, 76, 58)    # warm: the cost you had
AFTER_COLOR = (36, 116, 182)    # cool: the cost you have now
BACKGROUND = (255, 255, 255)


def load_series(path):
    with open(path) as f:
        data = json.load(f)
    for key in ("ticks", "ops", "ops_total"):
        if key not in data:
            raise SystemExit("%s: not a per-tick work series (missing '%s')" % (path, key))
    return data


def column(series, bucket):
    """The per-tick counts for `bucket` ('total' is the summed row the recorder wrote)."""
    if bucket == "total":
        return list(series["ops_total"])
    if bucket not in series["ops"]:
        raise SystemExit("unknown bucket '%s' -- series has: total, %s"
                         % (bucket, ", ".join(series["ops"].keys())))
    return list(series["ops"][bucket])


def mean(values):
    return (sum(values) / len(values)) if values else 0.0


def si(value):
    """Short human-readable magnitude for an axis label or legend (1234567 -> '1.2M')."""
    for limit, suffix in ((1e9, "G"), (1e6, "M"), (1e3, "K")):
        if abs(value) >= limit:
            scaled = value / limit
            return ("%.0f%s" if scaled >= 10 else "%.1f%s") % (scaled, suffix)
    return "%d" % round(value)


def delta_pct(before, after):
    if before == 0:
        return 0.0
    return (after - before) / before * 100.0


def _nice_ceiling(value):
    """Round an axis maximum up to 1, 2 or 5 times a power of ten, so labels stay readable."""
    if value <= 0:
        return 1.0
    exp = 0
    scaled = float(value)
    while scaled >= 10.0:
        scaled /= 10.0
        exp += 1
    while scaled < 1.0:
        scaled *= 10.0
        exp -= 1
    for step in (1.0, 2.0, 5.0, 10.0):
        if scaled <= step:
            return step * (10.0 ** exp)
    return 10.0 ** (exp + 1)


def plot(datasets, bucket, out_path, title=None):
    """Render `datasets` (list of (label, ticks, counts, color)) to a PNG at `out_path`."""
    canvas = Canvas(WIDTH, HEIGHT, BACKGROUND)
    left, right = MARGIN["left"], WIDTH - MARGIN["right"]
    top, bottom = MARGIN["top"], HEIGHT - MARGIN["bottom"]

    all_ticks = [t for _, ticks, _, _ in datasets for t in ticks]
    all_counts = [c for _, _, counts, _ in datasets for c in counts]
    x_min, x_max = min(all_ticks), max(all_ticks)
    if x_max == x_min:
        x_max = x_min + 1
    y_max = _nice_ceiling(max(all_counts) if all_counts else 1)

    def sx(tick):
        return int(left + (tick - x_min) / (x_max - x_min) * (right - left))

    def sy(count):
        return int(bottom - (count / y_max) * (bottom - top))

    canvas.text(MARGIN["left"] - 18, 24,
                title or ("computations per tick - %s" % bucket), INK, scale=4)

    # Horizontal gridlines with y labels, then the axes on top of them.
    for i in range(6):
        value = y_max * i / 5.0
        y = sy(value)
        canvas.hline(left, right, y, GRID)
        label = si(value)
        canvas.text(left - 14 - text_width(label, 2), y - 5, label, MUTED, scale=2)
    for i in range(6):
        tick = x_min + (x_max - x_min) * i / 5.0
        x = sx(tick)
        canvas.vline(x, top, bottom, GRID)
        label = "%d" % round(tick)
        canvas.text(x - text_width(label, 2) // 2, bottom + 12, label, MUTED, scale=2)
    canvas.hline(left, right, bottom, INK)
    canvas.vline(left, top, bottom, INK)

    canvas.text_centered((left + right) // 2, bottom + 36, "tick", MUTED, scale=2)
    canvas.text(MARGIN["left"] - 100, top - 26, "ops/tick", MUTED, scale=2)

    for label, ticks, counts, color in datasets:
        previous = None
        for tick, count in zip(ticks, counts):
            point = (sx(tick), sy(count))
            if previous is not None:
                canvas.line(previous[0], previous[1], point[0], point[1], color, weight=2)
            previous = point

    # Legend, top-right inside the plot area: swatch, series label, and its mean.
    legend_y = top + 10
    for label, _, counts, color in datasets:
        entry = "%s  mean %s" % (label, si(mean(counts)))
        entry_w = text_width(entry, 2) + 30
        canvas.rect(right - entry_w, legend_y, right - entry_w + 18, legend_y + 10, color)
        canvas.text(right - entry_w + 26, legend_y, entry, INK, scale=2)
        legend_y += 22

    canvas.save(out_path)
    return out_path


def summary_table(before, after, buckets):
    """Markdown table of per-bucket mean counts and their change -- paste into the PR body."""
    rows = ["| work bucket | before (mean/tick) | after (mean/tick) | change |",
            "| --- | ---: | ---: | ---: |"]
    for bucket in buckets:
        b_mean = mean(column(before, bucket)) if before else 0.0
        a_mean = mean(column(after, bucket))
        if before:
            change = "%+.1f%%" % delta_pct(b_mean, a_mean) if b_mean else "n/a"
            rows.append("| `%s` | %s | %s | %s |"
                        % (bucket, si(b_mean), si(a_mean), change))
        else:
            rows.append("| `%s` | - | %s | - |" % (bucket, si(a_mean)))
    return "\n".join(rows)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--after", required=True,
                        help="series recorded on the optimized build")
    parser.add_argument("--before",
                        help="series recorded on the base build (omit to plot one line)")
    parser.add_argument("--out", required=True, help="PNG path to write")
    parser.add_argument("--bucket", default="total",
                        help="work bucket to graph: 'total' (default) or one SimOps bucket")
    parser.add_argument("--title", help="override the chart title")
    args = parser.parse_args(argv)

    after = load_series(args.after)
    before = load_series(args.before) if args.before else None

    datasets = []
    if before:
        datasets.append((before.get("label", "before"), before["ticks"],
                         column(before, args.bucket), BEFORE_COLOR))
    datasets.append((after.get("label", "after"), after["ticks"],
                     column(after, args.bucket), AFTER_COLOR))
    plot(datasets, args.bucket, args.out, args.title)

    buckets = ["total"] + list(after["ops"].keys())
    print("wrote %s" % args.out)
    print()
    print(summary_table(before, after, buckets))
    if before:
        change = delta_pct(mean(column(before, args.bucket)), mean(column(after, args.bucket)))
        print()
        print("%s: %+.1f%% mean computations per tick over %d sampled ticks."
              % (args.bucket, change, len(after["ticks"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
