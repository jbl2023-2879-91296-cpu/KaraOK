# Noise Guard (Option A: basic noise filter) Design

Status: approach chosen by Don's team on 2026-11-18 (option A). Branch: `noise-guard`.

## Intent

KaraOK should give about the same assessment in a noisy outdoor place (jeeps,
motorcycles, chickens, people talking) as in a quiet room, for **any** karaoke
song. No song library, no song picker.

## What "the same" means (acceptance target)

The goal is that results stay within a stated tolerance, not that they are
bit-identical. A clean recording mixed with field noise is compared with the
same clean recording. The tolerances below define a pass in each must-pass cell:

| Measure | Tolerance |
|---|---|
| Overall score | within ±5 points, same pass/warning/fail status |
| Loudness (integrated LUFS) | within ±1.0 LU |
| Bass energy % | within ±3.0 percentage points |
| Treble energy %, sharpness | within ±1.0 dB as a ratio (about ±26 %), with a value floor of 1e-5 |
| Flatness | within ±1.0 dB as a ratio, with a value floor of 1e-5. Skipped when the noise check marks flatness unreliable. The report shows the value with a reliability note, and the score still includes it. |

Music-to-noise ratio (MNR) = song level over noise level, measured at the phone.

| Noise type | 20 dB MNR | 10 dB MNR | 5 dB MNR |
|---|---|---|---|
| Steady (engine, generator, jeep idling) | must pass | must flag | report only; low confidence shown |
| Transient (chickens, horns, motorcycle pass-by, shouts) | must pass | must flag | report only |
| Nearby talking (babble) | must pass | report only | report only |

At 20 dB, at least 90% of the cases in each required cell must meet every
tolerance above. At 10 dB, at least 90% of the steady and transient cases must
show low or medium confidence plus a noise warning, regardless of tolerance
outcome. No case in either required 10 dB cell may show high confidence.

When the target can't be met, the app has to **say so** (low confidence or
"too noisy, re-record") instead of quietly producing a wrong score.

## Measured facts that drive the design

- The app records the speaker at 44.1 kHz mono WAV (`record` 7.1.1). The backend
  averages bass/treble/flatness/sharpness over active STFT frames and computes
  BS.1770 loudness on the time signal (`backend/audio_engine/analyzer.py`).
- On the 30 "good" reference files, the median treble is 0.13 %, the median
  sharpness is 0.0007 and the median flatness is about 0. Even a small amount of
  hiss or a chicken at 2 to 4 kHz moves these by multiples, so they need the
  most protection.
- The current no-reference noise estimate is flagged unreliable on most files
  (`docs/findings/uat-noise-samples.csv`).
- Speech-tuned denoisers (RNNoise, phone OS noise suppression) reshape the
  music spectrum, which is exactly what we measure. They are not used, and the
  phone's own processing is turned off explicitly.

## Approaches considered

- **A. Basic filter (chosen):** a noise check before the song, removal of
  steady noise, and skipping of sudden noises. Works with any song. Voices are
  handled only partly.
- B. Reference-track library: most accurate, including voices, but needs an
  admin-managed song library and a picker. Not chosen.
- C. Both: not chosen. B can be added later on top of A without rework.

## Design

1. **Noise check (pre-roll).** When the user taps Record, the app records 3 s
   of room sound while showing "Stay quiet, checking background noise. Don't
   start the song yet". It shows a live level meter and warns when it's noisy.
   Then it says "Start the song now". It's one continuous WAV, and the app
   sends `noise_preroll_seconds=3`.
2. **Steady-noise subtraction.** The backend splits off the pre-roll, builds a
   per-frequency noise power profile, and applies power spectral subtraction
   (gain = sqrt(max(1 - P_noise/P, floor²))) to the rest. It then resynthesizes
   the audio, so every existing metric runs unchanged on cleaned audio.
3. **Sudden-noise skipping.** Frames whose band energies jump well above the
   local running median (±1.5 s) are dropped from the analysis mask. Loudness
   is computed on the kept segments only.
4. **Confidence and usable %.** A `noise_guard` block reports the pre-roll
   noise level, MNR, the percentage of frames kept and a high/medium/low
   confidence. If too little is usable, the result is a quality failure
   ("Too noisy, move closer or re-record").
5. **Better noise metric.** When a pre-roll exists, the report's noise level
   comes from it and is marked reliable. This replaces the old guess.
6. **Placement tip.** The checklist and the noise-check screen say to hold the
   phone about 30 cm (1 ft) from the speaker and point it at the speaker.
   Moving closer raises MNR more than any filter can.
7. **Uploaded files** have no pre-roll. Sudden-noise skipping still runs,
   subtraction does not (guessing a noise profile from music would remove
   music), confidence is capped at medium, and the report says no noise check
   was done.

## Non-goals

No song library or fingerprinting, no ML denoiser, no real-time on-device
cleaning (all cleaning runs server-side), and no change to the scoring
thresholds themselves.

## Left to the builder

Exact UI layout of the noise-check step and the report card, within the copy
given in the plan, plus internal helper structure.
