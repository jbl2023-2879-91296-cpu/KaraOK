# Report reference audit — 2026-09-14

## Source checked

The user identified `results/` as 30 feature-extracted recordings captured
directly from a karaoke machine. The directory contains 60 analysis JSONs:
older and newer analysis runs of those recordings, not 60 independent samples.

`results/results.csv` contains 30 rows for 30 distinct recording paths. Each
analysis ID has a matching JSON in the numbered directories. Its SHA-256 is
`bcc5d4c2710f1d49572a17db56c5cc23ff5e8161f17adc9d2486b0edc8adfaa5`, exactly
matching the source checksum in
`backend/audio_thresholds/good_audio_thresholds.json`.

The existing quality profile (`2026.09.1`, algorithm `1.0.0`) therefore already
uses these recordings. The report fixes preserve this artifact, its five
feature weights, and its P05–P95 and observed-envelope rules. No recordings,
extracted values, calibration thresholds, or weights were added or changed.

## Measurement findings

The following are observed ranges from the CSV, **not new pass/fail cutoffs**:

| Measurement | Minimum | Maximum | Unit |
| --- | ---: | ---: | --- |
| Integrated loudness | -15.93646911 | -10.34360594 | LUFS |
| Bass energy | 45.24513191 | 89.42611184 | % |
| Treble energy | 0.003258626 | 2.821164246 | % |
| Sharpness | 0.000153528 | 0.014503939 | approximate normalized score |
| Spectral flatness | 0.00000227 | 0.00048471 | ratio |
| Estimated noise | -26.92018717 | -11.93940516 | dBFS |
| Estimated SNR | 2.187103672 | 11.82450924 | dB |
| Estimated distortion risk | 5.137880785 | 13.98772993 | heuristic score, 0–100 |

Some CSV values, especially flatness, have less precision than the matching
JSON values. Flatness differences for all 30 samples are within the rounding
precision displayed in the CSV. Rebuilding the artifact from full-precision
JSON would be a separate calibration change requiring review; this update
does not silently replace the current source.

All 30 selected JSON files include a noise reliability warning: the recording
has little separation between typical and quiet frames and may lack a true
quiet section. Their no-reference SNR is advisory-only. The distortion score
is a heuristic risk estimate, not measured THD or a distortion percentage.
Neither estimate contributes to the existing five-feature weighted score.

## Report behavior

- Results and visual reports show the saved score and the same grade, keeping
  decimal precision instead of rounding to an integer before navigation.
- The visual report includes the saved five-feature measurements and grades.
- Reference sample count comes from assessment metadata. Missing metadata
  does not silently claim a 30-recording reference for every historical report.
- Missing or non-finite measurements are shown as unavailable, never as zero
  or demonstration values.
- Noise is labeled in dBFS and distortion as an estimated risk score. Both
  display explanatory limitations instead of fixed “low”/“acceptable” labels
  and decorative bars unrelated to measurements.

The good-only cohort supports comparison with observed recordings. It does
not establish validated perceptual boundaries for poor audio. Existing
reference limitations are documented in `backend/audio_thresholds/README.md`.

## Detailed interpretation report (2026-09-15)

See [empirical scoring and user interpretation](empirical-scoring-report.md)
for all five threshold anchors, the piecewise score formula, engineering-default
weights, song 25 worked example, and proposed user-facing explanations.
The [six-page PDF](../output/pdf/karaok-empirical-scoring-report.pdf) contains the
same explanation. The source CSV checksum was reverified for that report.
No scoring code, calibration values, or weights were changed.
