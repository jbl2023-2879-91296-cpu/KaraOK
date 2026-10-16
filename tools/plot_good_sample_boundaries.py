"""Plot observed Good boundaries from saved analyses; does not analyze audio."""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
from statistics import median

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import MaxNLocator


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "sample" / "good"
OUTPUT = ROOT / "output" / "good-boundary-reassessment"
METRICS = (
    ("loudness", "Loudness", "LUFS", "loudness", "integrated_lufs"),
    ("bass", "Bass energy", "%", "bass", "energy_percentage"),
    ("treble", "Treble energy", "%", "treble", "energy_percentage"),
    ("sharpness", "Sharpness", "normalized score", "sharpness", "normalized_score"),
    ("flatness", "Spectral flatness", "ratio", "flatness", "mean"),
)


def main() -> None:
    # Timestamped filenames sort chronologically within each recording folder.
    # Select the latest run per original recording, including any failed latest
    # run so failures cannot silently fall back to an older measurement.
    latest = {}
    for path in sorted(SOURCE.rglob("*_analysis.json")):
        record = json.loads(path.read_text(encoding="utf-8"))
        original = record["file_information"]["file_path"]
        if original not in latest or path.name > latest[original][0].name:
            latest[original] = (path, record)
    if not latest:
        raise ValueError(f"No saved analyses found in {SOURCE}")

    sources = []
    measurements = {key: [] for key, *_ in METRICS}
    recovered = 0
    for original, (path, record) in sorted(latest.items()):
        if "audio sample(good)" not in original.replace("\\", "/").split("/"):
            raise ValueError(f"Unexpected source origin: {original}")
        if record["analysis_information"]["analysis_status"] != "completed":
            raise ValueError(f"Latest analysis is incomplete: {path}")
        label = original.replace("\\", "/").rsplit("/", 1)[-1]
        recovered += record["file_information"].get("decode_status") == "recovered_partial"
        sources.append({
            "sample": label,
            "analysis": path.relative_to(ROOT).as_posix(),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        })
        for key, _, _, section, field in METRICS:
            value = record[section][field]
            if not isinstance(value, (int, float)) or not math.isfinite(value):
                raise ValueError(f"Invalid {key} measurement in {path}")
            measurements[key].append({"sample": label, "value": value})

    artifact = {
        "purpose": "Observed Good boundaries reassessed from saved good-sample analyses",
        "rule": "Good includes the observed minimum and maximum and all values between them.",
        "sample_count": len(sources),
        "partially_recovered_recordings": recovered,
        "needs_improvement_boundary": None,
        "bad_boundary": None,
        "note": "Outside Good is unclassified. Outer classes require a separate rule. Active app scoring is unchanged.",
        "sources": sources,
        "metrics": {},
    }
    plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 11})
    fig, axes = plt.subplots(5, 1, figsize=(14, 15))
    fig.patch.set_facecolor("#f7f8fa")
    fig.suptitle("Good audio: observed boundaries", x=0.08, y=0.975,
                 ha="left", fontsize=23, fontweight="bold", color="#18332b")
    fig.text(0.08, 0.935,
             f"{len(sources)} recordings | Good spans the lowest to highest observed value in each metric.\n"
             "Each dot is one recording. Vertical offsets separate overlapping dots; only horizontal position is measured.",
             fontsize=11, color="#475569", linespacing=1.6, va="top")

    for ax, (key, title, unit, _, _) in zip(axes, METRICS):
        points = sorted(measurements[key], key=lambda item: (item["value"], item["sample"]))
        values = [item["value"] for item in points]
        lower, upper = min(values), max(values)
        low_samples = [p["sample"] for p in points if p["value"] == lower]
        high_samples = [p["sample"] for p in points if p["value"] == upper]
        artifact["metrics"][key] = {
            "unit": unit, "good_lower": lower, "good_upper": upper,
            "inclusive": True, "median": median(values),
            "lower_boundary_samples": low_samples, "upper_boundary_samples": high_samples,
            "measurements": points,
        }
        assert all(lower <= value <= upper for value in values)
        span = upper - lower or max(abs(lower), 1) * 0.1
        ax.set_facecolor("#f7f8fa")
        ax.axvspan(lower, upper, color="#d9eee3", zorder=0)
        ax.axhline(0, color="#94bba5", linewidth=1, zorder=1)
        ax.axvline(lower, color="#16754b", linewidth=1.5)
        ax.axvline(upper, color="#16754b", linewidth=1.5)
        # Greedy stacking keeps near-identical measurements individually visible.
        levels = [0, 0.16, -0.16, 0.32, -0.32, 0.48, -0.48]
        occupied = [[] for _ in levels]
        heights = []
        for value in values:
            lane = next((i for i, taken in enumerate(occupied)
                         if not taken or value - taken[-1] >= span * 0.022), None)
            if lane is None:
                levels.append(0.16 * (len(levels) // 2 + 1))
                occupied.append([])
                lane = len(levels) - 1
            occupied[lane].append(value)
            heights.append(levels[lane])
        ax.scatter(values, heights, s=38, color="#176b48", edgecolors="white", linewidths=0.6, zorder=3)
        ax.scatter([lower, upper], [heights[0], heights[-1]], marker="D", s=65,
                   color="#103d2b", edgecolors="white", linewidths=0.8, zorder=4)
        fmt = lambda value: f"{value:.8g}"
        ax.set_title(f"{title} ({unit})", loc="left", fontweight="bold", pad=36)
        ax.text(lower, 1.03, f"MIN  {fmt(lower)}\n{', '.join(low_samples)}",
                transform=ax.get_xaxis_transform(), ha="left", va="bottom", fontsize=10, color="#145638")
        ax.text(upper, 1.03, f"MAX  {fmt(upper)}\n{', '.join(high_samples)}",
                transform=ax.get_xaxis_transform(), ha="right", va="bottom", fontsize=10, color="#145638")
        ax.set_xlim(lower - span * 0.08, upper + span * 0.08)
        ax.set_ylim(min(heights) - 0.25, max(heights) + 0.25)
        ax.set_yticks([])
        ax.xaxis.set_major_locator(MaxNLocator(7))
        ax.tick_params(axis="x", labelsize=10, colors="#475569")
        for side in ("top", "right", "left"):
            ax.spines[side].set_visible(False)
        ax.spines["bottom"].set_color("#cbd5e1")

    fig.text(0.08, 0.035,
             "Green band = Good (both endpoints included). Diamonds identify the extreme observations.\n"
             "Outside this band is unclassified in this reassessment; Needs Improvement and Bad cutoffs are not inferred.\n"
             f"Source: latest saved JSON per recording in sample/good/; {recovered} partially recovered recordings included.",
             fontsize=10, color="#475569", linespacing=1.6)
    fig.subplots_adjust(left=0.08, right=0.96, top=0.86, bottom=0.115, hspace=1.3)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for extension in ("png", "svg"):
        fig.savefig(OUTPUT / f"good-boundaries.{extension}", dpi=180, facecolor=fig.get_facecolor())
    plt.close(fig)
    (OUTPUT / "good-boundaries.json").write_text(json.dumps(artifact, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"sample_count": len(sources), "output": str(OUTPUT),
                      "bounds": {key: {name: metric[name] for name in
                                 ("good_lower", "good_upper", "lower_boundary_samples", "upper_boundary_samples")}
                                 for key, metric in artifact["metrics"].items()}}, indent=2))


if __name__ == "__main__":
    main()
