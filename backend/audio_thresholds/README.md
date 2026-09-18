# Empirical good-audio thresholds

## Active assessment profile: median-centered (2026.09.2-median)

New backend assessments use `median_centered_thresholds.json` by default, based
on the approved **KaraOK Median.pdf**. This is a user-selected theoretical
profile, not a newly validated dataset. No server deployment is performed by
changing this checkout, and stored historical assessments keep their saved scores
and profile provenance.

The original `good_audio_thresholds.json` remains the unchanged empirical
reference. Schema 2 adds explicit `assessment_bounds` to each metric, preserving
the original percentiles, extrema, quartiles, bootstrap intervals, and medians
as statistics rather than relabeling theoretical boundaries as observations.
Both schemas retain checksum validation. New assessment details include the
new version, checksum, rules, and complete reference metrics with these bounds.

Each center is the prior Good-class median shown in the PDF (which equals the
cohort median for all five factors). Each full Good-band width is preserved:
2.94 LUFS for loudness and the original P95-P05 width for the other factors.
With center `m` and width `w`, Good is `[m-w/2, m+w/2]`; improvement extends
to `m-1.5w` and `m+1.5w`, inclusive; values outside those outer cutoffs are Bad.
The finite display ends in the PDF (`m +/- 2.5w`) are not cutoffs: Bad continues
past them. Centers do not move again after reclassification.

| Factor | Lower improvement | Lower Good | Center | Upper Good | Upper improvement |
| --- | ---: | ---: | ---: | ---: | ---: |
| Loudness (LUFS) | -15.610895335 | -12.670895335 | -11.200895335 | -9.730895335 | -6.790895335 |
| Bass (%) | 16.70554435725 | 52.70658229575 | 70.707101265 | 88.70762023425 | 124.70865817275 |
| Treble (%) | -1.1572309932 | -0.2971793714 | 0.1328464395 | 0.5628722504 | 1.4229238722 |
| Sharpness | -0.00306827395 | -0.00052297665 | 0.000749672 | 0.00202232065 | 0.00456761795 |
| Flatness | -0.000159873975 | -0.000031791325 | 0.00003225 | 0.000096291325 | 0.000224373975 |

The JSON retains full calculation precision; the PDF table is rounded. Scores
remain 100 at the center, 80 at each Good edge, and 50 at each improvement edge,
with linear interpolation and tails clamped to 0-100. Existing feature weights
and overall 80/50 grade cutoffs remain unchanged.

These mathematical bands are intentionally not clipped to physical domains:
some low bounds are negative, and the bass upper improvement bound exceeds
100%. Consequently, valid nonnegative treble, sharpness, and flatness cannot
enter the low-side improvement/Bad bands, and valid bass cannot enter high-side
Bad. This is a consequence of the requested symmetry and preserved widths.

Regenerate the active artifact from the original reference, from `backend/`:

```powershell
python -m audio_thresholds.derive_median_thresholds
```

Regenerating the original empirical reference alone does not replace the active
artifact. Explicitly pass its path to `load_thresholds` to evaluate the legacy
profile. Version the active profile again if its source or policy changes.

## Original empirical reference

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
