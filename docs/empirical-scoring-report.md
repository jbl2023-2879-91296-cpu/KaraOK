# KaraOK: empirical scoring and user interpretation

Verified against repository sources on 2026-09-15.

[Download the PDF](../output/pdf/karaok-empirical-scoring-report.pdf).


## KaraOK empirical scoring

**Technical explanation and usability report**
Reference: 30 recordings | Quality profile 2026.09.1 | Algorithm 1.0.0
Prepared 15 September 2026

## What the score actually means

KaraOK compares five extracted measurements with a fixed empirical reference derived from 30 recordings labeled good. The result indicates agreement with that reference distribution. It is not a universally validated audio-quality rating, a singing-performance score, or a probability that audio is good.

The 30 recordings are incorporated through a saved threshold artifact. They are not replayed or matched song-by-song during each evaluation. The app does not identify lyrics, compare melodies, or require the uploaded file to be one of the reference songs.

## The evaluation path

| Step | Operation |
| --- | --- |
| 1. Capture | User records audio or selects a file in Flutter. |
| 2. Extract | The backend analyzer decodes audio and computes the five required measurements. |
| 3. Compare | The scorer loads the versioned threshold artifact and grades each measurement. |
| 4. Combine | Five feature scores are multiplied by their weights and summed. |
| 5. Present | Saved scores, measurements, and reference metadata appear in Results and history. |

## Decision relevant to usability

The interface should communicate reference agreement prominently. A different song, microphone, room, or playback setup can change the measurements even when a listener would still consider the audio good. The recommended wording is: "This score indicates how closely your recording matches the reference recordings used for this assessment."

Scope: this report documents existing behavior and proposes frontend wording. It does not modify the backend, thresholds, weights, or deployed scoring algorithm. [1-4]


## 1. Reference provenance

The artifact names results/results.csv as its source and records 30 selected recordings, 1.mp3 through 30.mp3. Its source SHA-256 matches a fresh hash of the current CSV. This verifies the checked-in reference provenance; it is not an independent inspection of the live server filesystem. [1]

**Source SHA-256**
bcc5d4c2710f1d49572a17db56c5cc23
ff5e8161f17adc9d2486b0edc8adfaa5

The numbered results folders contain older and newer analysis JSONs: 60 outputs represent repeated analysis runs of 30 recordings, not 60 independent audio examples. The reference CSV contains one row per recording. The earlier source audit identifies the matching JSONs and notes CSV rounding, especially for flatness. [5]

## How the distribution was derived

The derivation selects completed, in-cohort measurements, deduplicates by normalized recording path using the latest analysis timestamp and then analysis ID, and excludes missing or non-finite feature values. For this CSV, all 30 rows were selected. NumPy linear quantiles produce the percentile and median values. [1,6]

The artifact also records 10,000 bootstrap iterations, seed 20260719, and 95% confidence intervals. These express sampling uncertainty in reference statistics; they are not per-recording probabilities of good sound and are not the runtime score formula.

## Cohort limitations visible in the artifact

| Evidence | Implication |
| --- | --- |
| 30 good-labeled recordings only | There are no independently labeled improvement/bad examples to validate classification accuracy. |
| 4 complete decodes; 26 recovered partial | Reference quality depends on recovery behavior. Recovered-frame percentages span approximately 98.8633% to 100%. |
| 3 passed; 27 warning quality statuses | Analyzer diagnostic status is distinct from the source label "good". |
| Restricted recording/analyzer conditions | Generalization to other sources, devices and rooms has not been demonstrated. |

The artifact includes a stricter recovery sensitivity analysis. Its existence does not remove the limitations of the main 30-recording cohort. No classification accuracy percentage is established by these data.


## 2. The five evaluated factors

| Factor / weight | Extracted measurement and interpretation |
| --- | --- |
| Loudness / 30% | loudness.integrated_lufs: integrated mono loudness in LUFS. This measures the recording, not calibrated room sound pressure. |
| Bass / 25% | bass.energy_percentage: bass-band share of active-frame spectral energy, expressed as a percentage. This is not a bass-knob position. |
| Treble / 20% | treble.energy_percentage: treble-band share of active-frame spectral energy, expressed as a percentage. This is not a treble-knob position. |
| Sharpness / 15% | sharpness.normalized_score: approximate normalized high-frequency-weighted score. The algorithm uses the second normalized spectral moment; it is not certified sharpness in acum. |
| Flatness / 10% | flatness.mean: mean spectral flatness over active frames. It describes spectral energy distribution, not how flat the speaker frequency response is. |

## Raw measurements are not feature scores

A bass measurement of 51.50% and a bass score of 82.62/100 describe different things. The first is extracted energy share; the second comes from comparing that share with the reference distribution. Only the second enters the overall weighted calculation. [2-4]

## Why larger does not automatically mean better

All five score curves peak at the reference median. A measurement can lose points by moving either below or above that median. Maximizing bass, treble, loudness, sharpness, or flatness is therefore not the objective of the current scoring system.

## Weights are chosen, not learned

The 30/25/20/15/10 weights are transparent engineering defaults. They prioritize level and tonal balance while limiting repeated contribution from correlated treble, sharpness and flatness. They were not learned from listener ratings or established as perceptual importance by these 30 recordings. The weight values sum to 1.0. [1,3]

## What stays outside the overall score

Estimated noise level and distortion risk are advisory only. Noise is reported in dBFS and can be unreliable without a true quiet section. Distortion is a heuristic risk score, not THD or a percentage of distortion. Neither contributes to the five-factor weighted score. [4,5]


## 3. Thresholds and score mapping

For each feature, the artifact stores the observed minimum, P05, median, P95, and observed maximum. P05-P95 is the central reference interval, not a proven perceptual acceptance standard. The values below are rounded for readability; runtime scoring uses full precision. [1,2]

| Feature | Minimum | P05 | Median | P95 | Maximum |
| --- | --- | --- | --- | --- | --- |
| Loudness | -15.9364691 | -13.4383603 | -11.2008953 | -10.4977432 | -10.3436059 |
| Bass | 45.2451319 | 48.6009032 | 70.7071013 | 84.6019411 | 89.4261118 |
| Treble | 0.003258626 | 0.0238191611 | 0.132846439 | 0.883870783 | 2.82116425 |
| Sharpness | 0.000153528 | 0.0003089165 | 0.000749672 | 0.0028542138 | 0.014503939 |
| Flatness | 2.27e-06 | 5.702e-06 | 3.225e-05 | 0.00013378465 | 0.00048471 |

Units: loudness in LUFS; bass and treble in percent; sharpness as an approximate normalized score; flatness as a ratio.

| Feature classification | Rule |
| --- | --- |
| Good | P05 <= value <= P95 |
| Needs improvement | Inside the observed minimum/maximum envelope, but outside P05-P95 |
| Bad | Below the observed minimum or above the observed maximum |
| Not evaluated | Measurement is missing or non-finite |

## Numeric anchors and interpolation

Median = 100; P05 and P95 = 80; observed minimum and maximum = 50. Between anchors, the score follows a straight line. Beyond an extreme it falls below 50 and is clamped between 0 and 100. Percentile endpoints belong to Good; observed endpoints belong to the outer interval unless they coincide with percentile endpoints.

Between two anchors (x1, s1) and (x2, s2):
**score = s1 + (x - x1) / (x2 - x1) * (s2 - s1)**

Below minimum: subtract 50 times the distance below minimum divided by max(P05 - minimum, median - P05, 1e-12). Above maximum: subtract 50 times the distance above maximum divided by max(maximum - P95, P95 - median, 1e-12). Both tails start from 50 and are clamped. Coincident interpolation anchors use the smaller endpoint score; an exact median is scored 100. [2]


## 4. Overall result and worked example

**Overall = 0.30L + 0.25B + 0.20T + 0.15S + 0.10F**
L, B, T, S and F are feature scores out of 100, not extracted measurements.

| Overall grade | Weighted-score rule |
| --- | --- |
| Good | 80 or higher |
| Needs improvement | At least 50, but below 80 |
| Bad | Below 50 |
| Not evaluated | One or more required measurements missing or non-finite |

The scorer does not renormalize around missing factors. The application rejects an unavailable overall empirical score rather than silently supplying missing measurements. It also records worst-feature status separately; the weakest factor does not override the weighted overall grade. [2,4]

## Song 25: the phone-tested example

| Factor | Raw measurement | Feature score | Weight | Points* |
| --- | --- | --- | --- | --- |
| Loudness | -11.31 LUFS | 99.03 | 30% | 29.709 |
| Bass | 51.50% | 82.62 | 25% | 20.655 |
| Treble | 0.02% | 72.17 | 20% | 14.434 |
| Sharpness | 0.000495 | 88.44 | 15% | 13.266 |
| Flatness | 0.000005 | 77.76 | 10% | 7.776 |

*Points computed from displayed, rounded feature scores. They sum to 85.840. The earlier full-precision calculation was approximately 85.841165, displayed as **85.84/100**. The raw treble and flatness displays are also rounded, so reproducing the result requires full-precision values, not the displayed strings.

Loudness, bass and sharpness were Good; treble and flatness were Needs improvement. The weighted overall result was still Good. This is expected behavior, not a contradiction.

## What the phone test proves

Two evaluations of the same file displayed 85.84/100. Saved results survived restart and the guest sign-in/sign-out cycle; history remained separate. These checks establish consistency for that example, not accuracy across all songs or audio conditions. The 30 songs were not all uploaded individually during the phone tests.


## 5. Usability conclusions and evidence

## Interpretation the interface should support

Use "reference agreement" as the main explanation of the score. Explain that "Bad" is currently an operational flag for outside the observed reference envelope, not proof that a listener would judge the recording poor. A score of 100 means matching reference medians; it does not establish a perfect speaker or recording.

Recommended Results wording: "This score indicates how closely your recording matches the reference recordings used for this assessment." Show "30" only when that saved report contains the corresponding reference count. Historical records with missing metadata must not inherit an assumed count.

Recommended per-feature labels, if adopted in a future frontend change: "Within reference range", "Near reference limits", and "Outside observed reference range". Preserve the original saved statuses and numbers. These wording changes are recommendations, not changes made by this documentation task.

## Making comparisons useful

Use the same song segment, source, phone/microphone position and playback conditions; change one intended setting at a time. Compare raw measurements and feature scores separately. A B-minus-A difference is not automatically an improvement. Check reference-profile compatibility before treating scores from different profiles as directly comparable.

## Evidence sources and reproducibility

[1] backend/audio_thresholds/good_audio_thresholds.json - cohort, source hash, exact bounds, scoring anchors, weights and limitations.

[2] backend/audio_thresholds/scoring.py - classify_feature, score_feature, evaluate_features; runtime score rules and missing-value behavior.

[3] backend/audio_thresholds/metric_definitions.py - extracted field names, units, ranks and default weights.

[4] backend/karaok/application.py and backend/audio_engine/analyzer.py - extraction-to-scoring integration and measurement implementation.

[5] docs/report-reference-audit.md and results/results.csv - source audit, CSV rounding, measurement limitations and reference checksum.

[6] backend/audio_thresholds/derive_thresholds.py - cohort selection and threshold derivation.

[7] backend/tests/test_good_audio_thresholds.py - boundary, median, missing-value and scoring regression coverage.

Repository inspection and checksum verification were performed for this report. Prior phone and test results are reported from this work session; no new server test, deployment, threshold rebuild, or listener-validation study was performed. The latest startup animation still requires its phone check.
