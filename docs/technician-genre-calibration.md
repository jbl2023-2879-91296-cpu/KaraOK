# Evaluation-guided Bass and Treble settings

The active genre artifact is `2026.10.1-technician`: 15 speaker recordings each
for Pop, R&B and Rock. It replaces the provisional FMA genre profiles. No raw
recordings are bundled with the app. The ordinary evaluation-only flow still
uses the existing global quality artifact when no supported genre is selected.

## User flow

Evaluate Audio Quality and Generate Audio Settings both open amplifier setup.
Select the genre, scale and actual current positions, then record playback.
The first upload opens the evaluation report. **Generate Audio Settings** opens
the recommendation calculated from that same evaluation, without uploading or
charging another guest evaluation. Apply the positions physically and confirm;
**Record Again to Verify** evaluates a new recording and compares actual scores.
Use the same passage, volume and recording placement for the comparison.

The existing `SETTINGS_RECOMMENDATIONS_ENABLED=true` deployment setting is still
required. **Evaluate only, without knob suggestions** remains available when
settings generation is disabled. Existing amplifier profiles and the five-field
API are retained; Volume, Sharpness and Flatness remain unchanged by technician
recommendations. Select **-10 to +10 (technician reference)** for the documented
tone-control scale. Existing 0–10, 0–100 and custom scales remain supported.

## Derivation

Run from the repository root:

```powershell
python backend/scripts/derive_technician_profiles.py
```

The script resolves song numbers from filenames, requires all 45 unique songs,
decodes through the production analyzer's recovery-aware loader, skips the first
10 seconds, and analyzes the remaining playback with the same feature extractor
used by the app. The skip is an approximation based on the user's description,
not automatic identification of the technician's final adjustment. Override it
with `--skip-seconds` when better timing information is available.

Each song contributes one measurement per feature, regardless of duration.
Linear p25 and p75 define the initial acceptable interval; the median is the
preferred value. The robust scale is max(IQR, 5% of absolute median, 1e-9).
The artifact includes every file's SHA-256, decoding/recovery information,
analyzed duration, extracted measurements and transcribed knob positions.
Recordings are user-supplied; instrumental status and redistribution rights
have not been independently established.

The existing piecewise scoring function scores the median at 100 and interval
boundaries at 80. An additional robust-scale width on either side scores 50;
values farther out approach zero. Existing feature weights are retained.
These are provisional assessment rules, not proof of universal audio quality.
Both recommendations and selected-genre evaluations use the same intervals.
Genre/profile checksum and algorithm version identify the score basis; obsolete
verification sessions are rejected instead of compared across versions.

## Technician positions and adjustment rules

`backend/audio_thresholds/technician_knob_observations.json` transcribes the
three photographs in song-number order. Four unclear entries remain null:
Rock 7 Treble, R&B 3 Treble, R&B 12 Treble and R&B 15 Bass. They are excluded only
from that control's position statistics. All 45 audio recordings contribute to
the audio thresholds. Confirm these entries before filling them and regenerating.

Current position medians (absolute positions, not deltas):

| Genre | Bass | Treble |
| --- | ---: | ---: |
| Pop | +2 | +4 |
| R&B | -4 | +2 |
| Rock | +6 | +4 |

Measured error determines adjustment direction. In-range controls stay unchanged.
On the documented -10 to +10 scale, an aligned technician median influences the
step magnitude with 25% weight; 75% comes from measured error. A conflicting
median never reverses the direction. The full allowed scale remains usable.
Absolute position priors are not transferred to other amplifier scales.

Initial changes are capped at 10% of the scale span (2 units on -10 to +10),
verification changes at 5% (1 unit), rounded within bounds to a supported step.
Clipping or excessive distortion blocks tone increases. These step sizes and
the prior weight are engineering starting assumptions, not measured transfer
curves. Hardware/room differences keep recommendations low-confidence.

## Validation limits

Automated tests cover direction, unchanged controls, step caps, clipping,
artifact provenance/counts, scoring consistency, persistence/API contracts and
evaluation-to-suggestions navigation. Actual score improvement still requires
controlled before/after trials on physical equipment. The app reports real
improvement or deterioration; it never raises a score for applying suggestions.
