# KaraOK UAT follow-up — 1.10.0+15

## Changes

- Uploads reject files above 25 MB before copying, and reject audio longer than
  five minutes with trimming instructions. Recording stops at 5:00 and explains
  why it stopped. Generated Android fixtures cover an hour-long WAV, an hour-long
  low-bitrate MP3 below 25 MB, a six-minute WAV and an accepted three-minute WAV.
- Results, guest results and detailed reports share plain grade descriptions,
  a “What this means” card with at most three items, and measurement definitions
  and status words visible in each row.
- Noise and distortion estimates show bands and open help sheets. A searchable
  glossary shares its definitions with report rows and help. Open it from Results,
  the measurement help panel or Account/Settings.
- Recommendations explain the amplifier profile and the reason for each change.
  Verification appears immediately after the recommendation note. Signed-in
  owners can save Better / Same / Worse feedback and reopen it later.
- The light theme and recommendation engine adjustment caps are preserved.

## Noise-band evidence (PR note)

Ran the current full analyzer, with its default configuration, on **every file**
in `audio sample(good)/` and `audio sample(bad)/`: 30 good MP3s and 45 altered WAVs.
All 75 completed without errors. No files were trimmed, normalized or modified.
Reproduce with the backend Python environment and
`python tools/check_uat_noise_bands.py` from the repository root. Per-file noise,
quiet-frame separation, distortion and reliability warnings are saved in
`artifacts/uat-noise-samples.csv`.

| Set | Files | Lowest noise estimate | Median | Highest | No clear quiet section |
| --- | ---: | ---: | ---: | ---: | ---: |
| Good | 30 | -26.92 dBFS | -15.22 dBFS | -11.94 dBFS | 28 |
| Altered | 45 | -41.12 dBFS | -13.63 dBFS | -2.44 dBFS | 41 |

The sets overlap substantially. Some bad low-volume examples have *lower*
estimates than any good sample. The analyzer uses the quietest 15% of frames;
music in those frames is included. Its existing reliability warning identifies
less than 6 dB separation in 69 of 75 files. These are music-quality examples,
not labeled recordings of background noise. They cannot justify cutoffs that
reliably distinguish quiet rooms from noisy rooms or good systems from bad ones.

Consequently, the requested -60 / -45 dBFS cutoffs remain **advisory**, rather than
being tuned to misclassify these examples as a room-noise calibration. All 75
samples land above -45. The visible caution says music can raise the estimate,
asks the owner to listen before changing the setup, and states explicitly that
background noise does not change the quality score. Actual room-noise calibration
would need separately recorded quiet sections. Distortion uses the existing
backend bands: below 20, 20 to below 50, and 50 or more.

## Deployment

Apply `database/migrations/20261025_01_recommendation_feedback.sql` before
deploying the updated backend. It adds one nullable feedback column, preserves
existing rows and answers, and is safe to repeat. Rollback instructions are in
the migration. No live database migration was performed by this change.

The feedback API is
`POST /api/settings-recommendations/<id>/feedback` with
`{"feedback":"better"}`, `"same"` or `"worse"` and the owner's access token.
Invalid values are rejected; other owners and missing recommendations return
not found. Feedback remains associated with the recommendation's profile and
genre.

## Verification

- `flutter analyze --no-pub`: clean.
- `flutter test --no-pub`: 289 passed, one existing skipped test.
- Backend `pytest`: 320 passed, one MySQL-dependent test skipped, and one
  environment-template test deselected. Used `PYTHON_DOTENV_DISABLED=1` and
  `-k 'not test_environment_examples_keep_feature_disabled_by_default'` to honor
  the instruction never to open environment files. No credential files were
  inspected or committed.
- Four real Android picker integration tests passed on device `R3CM908XHSK`.
  The oversized WAV test watches the picker cache to prove rejection before
  any copy. Test audio is generated and cleaned up; no large fixtures committed.
- `tools/test_build_theme_check.ps1`: 17 checks passed.
- Release built through `tools/build_karaok.ps1 -Mode release -NonInteractive
  -SkipPubGet`, which runs analysis and tests before building the signed APK.

For the next UAT round, install the **release 1.10.0+15 APK** from `dist/`, then:

1. Try the four upload lengths above and record until 5:00. Check both messages.
2. Open a saved result, a guest result and its detailed report. Check the plain
   summary, the three-item limit, row definitions, and both estimate help sheets.
3. Open the glossary from all three links, search for “bass”, and expand an entry.
4. Generate settings for a named amplifier. Check its name, the knob reasons and
   the visible verification action. Apply settings, record again, and compare.
5. Choose Better, Same or Worse, leave and reopen the recommendation. Confirm
   the saved choice. Check the same recommendation from another account is
   inaccessible.
