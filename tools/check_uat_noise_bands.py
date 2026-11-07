"""Run the shipped analyzer on both UAT sample sets without changing audio."""
import csv
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))
from audio_engine.analyzer import analyze_audio


def main():
    destination = ROOT / "docs" / "uat-noise-samples.csv"
    destination.parent.mkdir(exist_ok=True)
    with destination.open("w", newline="", encoding="utf-8") as output:
        fields = ["set", "file", "noise_dbfs", "separation_db", "reliable", "distortion", "warning", "error"]
        writer = csv.DictWriter(output, fieldnames=fields)
        writer.writeheader()
        for group in ("good", "bad"):
            for path in sorted((ROOT / f"audio sample({group})").glob("*")):
                if path.suffix.lower() not in (".mp3", ".wav"):
                    continue
                row = {"set": group, "file": path.name}
                try:
                    result = analyze_audio(path)
                    noise = result["noise"]
                    row.update(noise_dbfs=noise["noise_dbfs"],
                               separation_db=noise["signal_to_quiet_frame_separation_db"],
                               reliable=noise["reliable"],
                               distortion=result["distortion"]["estimated_score"],
                               warning=noise["reliability_warning"])
                except Exception as error:
                    row["error"] = str(error)
                writer.writerow(row)
                output.flush()
                print(group, path.name, row.get("noise_dbfs", row.get("error")), flush=True)


if __name__ == "__main__":
    main()
