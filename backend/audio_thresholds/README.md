# Empirical good-audio thresholds

This package derives a provisional five-feature reference from completed rows in
`results/results.csv` whose input path belongs to `audio sample(good)`. It is
separate from `audio_analyzer.py`: feature extraction continues unchanged, and
rerunning this tool only regenerates the threshold JSON.

## Regenerate the threshold artifact

From the repository root:

```powershell
backend\.venv\Scripts\python.exe backend\audio_thresholds\derive_thresholds.py
```

The command validates the CSV schema, retains the latest completed row for each
recording path, excludes missing or non-finite measurements, requires at least
20 valid recordings, and writes `good_audio_thresholds.json`. Calculations use
NumPy and include the median, P05, P95, observed envelope, MAD, IQR, bootstrap
confidence intervals, correlations, and a partial-decode sensitivity check. A
SHA-256 digest makes the source CSV version auditable.

## Feature statuses

- `good`: value is inside P05-P95, including both boundaries.
- `good_but_needs_improvement`: value is outside P05-P95 but inside the
  observed minimum-maximum envelope, including the envelope boundaries.
- `bad`: value is strictly outside the observed envelope.
- `not_evaluated`: value is missing or non-finite.

The generated 30-recording reference currently contains:

| Feature | Unit | Observed min | P05 | Median | P95 | Observed max |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Loudness | LUFS | -15.93646911 | -13.43836035 | -11.20089534 | -10.49774318 | -10.34360594 |
| Bass | percent | 45.24513191 | 48.60090316 | 70.70710127 | 84.60194110 | 89.42611184 |
| Treble | percent | 0.003258626 | 0.023819161 | 0.132846440 | 0.883870783 | 2.821164246 |
| Sharpness | normalized score | 0.000153528 | 0.000308917 | 0.000749672 | 0.002854214 | 0.014503939 |
| Flatness | ratio | 0.000002270 | 0.000005702 | 0.000032250 | 0.000133785 | 0.000484710 |

The JSON is authoritative and retains more precision than this readable table.

Each feature also receives a directional piecewise-linear score. The median is
100, P05/P95 are 80, and the observed minimum/maximum are 50. Values beyond the
envelope fall below 50 and are clamped at zero.

## Ranked overall score

| Rank | Feature | Default weight |
| ---: | --- | ---: |
| 1 | Loudness | 30% |
| 2 | Bass | 25% |
| 3 | Treble | 20% |
| 4 | Sharpness | 15% |
| 5 | Flatness | 10% |

The overall score is the weighted sum of all five feature scores. Scores of at
least 80 are `good`, scores from 50 through less than 80 are
`good_but_needs_improvement`, and scores below 50 are `bad`. All five values are
required. `worst_feature_status` and its responsible features are reported
separately so a weak feature stays visible without automatically replacing the
weighted overall result.

Use the scoring API from Python:

```python
from backend.audio_thresholds import evaluate_features

result = evaluate_features(
    {
        "loudness": -11.2,
        "bass": 70.7,
        "treble": 0.13,
        "sharpness": 0.00075,
        "flatness": 0.000032,
    }
)
```

The weights live in the generated JSON and may be adjusted after controlled
listening studies. They must remain positive and sum to 1.0.

## Interpretation limit

The source cohort contains 30 recordings labeled good, but no labeled bad or
needs-improvement recordings. Therefore, `bad` currently means outside the
observed good-cohort envelope; it is not yet a validated perceptual diagnosis.
The thresholds and weights should be recalibrated when more devices, recording
conditions, negative examples, and listener ratings are available.
