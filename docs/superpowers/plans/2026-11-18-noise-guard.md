# Noise Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep KaraOK's assessment of any karaoke song within a stated tolerance when it's recorded in a noisy outdoor place instead of a quiet room. The app should say so honestly when it can't.

**Architecture:** The app records a 3 s room-noise pre-roll before the song in the same WAV. The backend uses it for power spectral subtraction of steady noise, drops frames with sudden noise (transient gating against a running median), and reports usable % and confidence. All cleaning is server-side, in a new `audio_engine/noise_guard.py` that runs before the existing metrics, so the metrics code stays unchanged.

**Tech Stack:** Python 3 / numpy / librosa 0.11 / scipy (backend analyzer), Flask, MySQL, Flutter + `record` 7.1.1.

**Spec:** `docs/superpowers/specs/2026-11-18-noise-guard-design.md`

## Global Constraints

- Work on the existing branch `noise-guard`. Don's uncommitted changes (`CHANGELOG.md`, `README.md`, `deploy.md`, `frontend/pubspec.yaml`, `deploy/ovh/*recovery*`) are his. Never stage them unless he says so. Stage files by path, never `git add -A`.
- Pre-roll length is 3.0 s. The server accepts `noise_preroll_seconds` in [0, 5], default 0.
- The phone's own processing must be off: `RecordConfig(autoGain: false, echoCancel: false, noiseSuppress: false)`.
- Acceptance tolerances (from the spec): overall score ±5 points with the same status, loudness ±1.0 LU, bass ±3.0 pp, and treble/sharpness/flatness ±1.0 dB as a ratio with a 1e-5 floor.
- Test grid: MNR 20 / 10 / 5 dB x {steady, transient, babble}. Steady, transient, and babble at 20 dB must meet every tolerance in at least 90% of cases per cell. Steady and transient at 10 dB must show low or medium confidence plus a noise warning in at least 90% of cases per cell, with zero high-confidence cases. Remaining cells are report-only.
- Don't add ML denoisers or new Python dependencies. numpy, scipy and librosa are enough.
- Backend tests use `unittest`. Run them from `backend/` with `.\.venv\Scripts\python.exe -m unittest tests.<module> -v` (Windows) or `python -m unittest ...` on the server venv.
- Version: per `AGENTS.md`, take the highest version in `dist/` as the baseline. It's expected to be 1.11.0+17, which makes this release 1.12.0+18. Verify before bumping.
- Keep the noise-guard settings in `backend/audio_analyzer_settings.json` under a new `"noise_guard"` section. Its defaults are listed in Task 2.

## Review Focus

1. **A user starts the song during the 3 s noise check.** The pre-roll then contains music, and subtraction would remove music. Expected: the server detects that the pre-roll is music-like (pre-roll level within 6 dB of the song level), skips subtraction, adds the warning "The song started during the noise check, so background noise was not removed." and caps confidence at medium. The test is in Task 2.
2. **A pre-roll that is digital silence** (some Android devices emit zeros for the first ~300 ms). Expected: the profile ignores frames below -90 dBFS, and if fewer than 1.0 s of usable pre-roll remains, it behaves like "no pre-roll". The test is in Task 1.
3. **A recording where gating removes most frames** (constant shouting). Expected: below 30 % usable it's a quality failure with "Too noisy" copy. It must never crash on an empty mask (the analyzer currently raises when fewer than 10 active frames remain). The test is in Task 2.
4. **An uploaded file or an old app sending no field.** Expected: identical metrics to today except for transient gating, `noise_guard.preroll_seconds = 0`, and confidence no higher than medium. The test is in Task 4.
5. **Too little song after the pre-roll.** The rule is that the song part (whole file minus `noise_preroll_seconds`) must be **at least 10.0 s**, the same minimum the app already uses for a whole recording. The existing whole-file check (10 to 300 s via `audio_duration_seconds`) stays as it is and runs first. The song-length check runs in the analyzer on exact sample counts, and the boundary passes (10.0 s is OK, anything under 10.0 s is rejected). With a 3 s pre-roll, a **12.0 s file (9.0 s of song) returns 422** with "Record at least 10 seconds of song after the noise check." and a **13.0 s file (10.0 s of song) is analyzed normally**. The old 5 s rule could never trigger, because a file of at least 10 s with a pre-roll of at most 5 s always leaves at least 5 s of song. The tests are in Task 2 (analyzer) and Task 4 (API).

---

### Task 1: Noise-guard DSP module

**Files:**
- Create: `backend/audio_engine/noise_guard.py`
- Create: `backend/tests/noise_fixtures.py` (synthetic signals, shared by Tasks 1 to 3)
- Test: `backend/tests/test_noise_guard.py`

**Interfaces:**
- Produces:
  - `@dataclass(frozen=True) class NoiseGuardConfig` with fields and defaults: `enabled: bool = True`, `preroll_min_usable_seconds: float = 1.0`, `preroll_silence_dbfs: float = -90.0`, `subtraction_floor: float = 0.1`, `music_in_preroll_margin_db: float = 6.0`, `transient_window_seconds: float = 1.5`, `transient_band_db: float = 6.0`, `transient_band_fraction: float = 0.3`, `transient_pad_frames: int = 2`, `usable_warn_percentage: float = 60.0`, `usable_fail_percentage: float = 30.0`, `mnr_warn_db: float = 10.0`, `mnr_low_db: float = 5.0`.
  - `@dataclass class NoiseGuardResult: audio: np.ndarray; keep_frames: np.ndarray  # bool, one per analyzer frame (center=False framing); report: dict[str, Any]`
  - `def apply_noise_guard(audio: np.ndarray, sample_rate: int, preroll_seconds: float, config: NoiseGuardConfig, frame_length: int, hop_length: int) -> NoiseGuardResult`. The returned `audio` excludes the pre-roll.
  - `report` keys: `preroll_seconds: float`, `preroll_usable_seconds: float`, `preroll_noise_dbfs: float | None`, `music_to_noise_db: float | None`, `subtraction_applied: bool`, `transient_frames_removed_percentage: float`, `usable_percentage: float`, `confidence: "high"|"medium"|"low"`, `warnings: list[str]`.
  - `noise_fixtures.py`: `music_like(sr, seconds, seed) -> np.ndarray` (bass line 55 to 110 Hz, chords 200 to 2 kHz, hi-hat noise bursts 6 to 10 kHz, peak 0.5), `engine_noise(sr, seconds, seed)` (35 Hz harmonic series plus brown noise), `chicken_bursts(sr, seconds, seed)` (150 ms FM tones 1.5 to 4 kHz with harmonics, 0.4 to 2 per second), `babble(sr, seconds, seed)` (pink noise through 3 formant band-passes, 4 Hz syllabic AM, 4 overlapping talkers), and `mix_at_mnr(music, noise, mnr_db) -> np.ndarray` (scales the noise so 10·log10(P_music/P_noise) = mnr_db).

- [ ] **Step 1: Write the failing tests** in `test_noise_guard.py`:

```python
def test_split_removes_preroll_from_returned_audio(self):
    sr = 44100; noise = engine_noise(sr, 3, 1); song = music_like(sr, 12, 2)
    res = apply_noise_guard(np.concatenate([noise, song + engine_noise(sr, 12, 3)]), sr, 3.0, NoiseGuardConfig(), 2048, 512)
    self.assertAlmostEqual(res.audio.size / sr, 12.0, places=1)
    self.assertTrue(res.report["subtraction_applied"])

def test_subtraction_reduces_steady_noise_band_energy(self):
    # 0-250 Hz energy of (music+engine @10 dB) after the guard is within 1 dB of clean music
    ...
    self.assertLess(abs(db(bass_after) - db(bass_clean)), 1.0)
    self.assertGreater(abs(db(bass_before) - db(bass_clean)), 1.0)

def test_transient_frames_dropped(self):
    # music + chicken_bursts @10 dB: >=80 % of burst frames are False in keep_frames,
    # <=5 % of burst-free frames are False
    ...

def test_no_preroll_skips_subtraction_and_caps_confidence(self):
    res = apply_noise_guard(music_like(44100, 12, 2), 44100, 0.0, NoiseGuardConfig(), 2048, 512)
    self.assertFalse(res.report["subtraction_applied"])
    self.assertIn(res.report["confidence"], ("medium", "low"))

def test_silent_preroll_is_treated_as_missing(self):
    audio = np.concatenate([np.zeros(3 * 44100), music_like(44100, 12, 2)])
    res = apply_noise_guard(audio, 44100, 3.0, NoiseGuardConfig(), 2048, 512)
    self.assertFalse(res.report["subtraction_applied"])
    self.assertEqual(res.report["preroll_usable_seconds"], 0.0)

def test_clean_music_is_left_nearly_unchanged(self):
    # quiet pre-roll (white noise at -80 dBFS) + clean music: output RMS within 0.2 dB of input,
    # usable_percentage >= 95, confidence == "high"
```

- [ ] **Step 2: Run them to verify they fail.** Run `python -m unittest tests.test_noise_guard -v`. Expected: ImportError for `audio_engine.noise_guard`.

- [ ] **Step 3: Implement `noise_guard.py`.**
  - **Profile:** STFT with the analyzer's `frame_length`/`hop_length` and a Hann window. Use pre-roll frames whose RMS > `preroll_silence_dbfs`. If they total < `preroll_min_usable_seconds`, there's no profile. Otherwise the profile is the per-bin mean power.
  - **Subtraction:** `G = sqrt(max(1 - P_noise / max(P, eps), subtraction_floor**2))` per bin and frame, followed by `librosa.istft(..., length=len(song))`. Skip it if there's no profile, or if `10*log10(mean song power / mean pre-roll power) < music_in_preroll_margin_db` (Review Focus 1).
  - **MNR:** `10*log10(max(P_song - P_noise, eps) / P_noise)` from mean powers.
  - **Transient gating:** run it on the cleaned audio:

```python
# 24 log-spaced bands, 60 Hz to min(16 kHz, nyquist); E[b, t] in dB from the STFT power
med = scipy.ndimage.median_filter(E, size=(1, win_frames), mode="nearest")   # win = transient_window_seconds
excess = E - med
bad = (excess > transient_band_db).mean(axis=0) >= transient_band_fraction
bad = scipy.ndimage.binary_dilation(bad, iterations=transient_pad_frames)
keep = ~bad
```

  - **Frame alignment:** `keep_frames` must match the analyzer's `center=False` frame count `1 + (len(audio) - frame_length) // hop_length`. Compute the STFT for gating with `center=False` too.
  - **Confidence:** high if there's a profile and MNR ≥ `mnr_warn_db` and usable ≥ `usable_warn_percentage`. Low if MNR < `mnr_low_db` or usable < `usable_warn_percentage`. Medium otherwise, and always at most medium when there's no profile.
  - **Warning copy (exact):** `"No background-noise check was recorded, so steady noise was not removed."`, `"The song started during the noise check, so background noise was not removed."`, `"Background noise is loud compared with the song. Move the phone closer to the speaker."`, `"{p:.0f}% of the recording had sudden noises and was skipped."` (only when p ≥ 10).

- [ ] **Step 4: Run the tests to verify they pass.** Run `python -m unittest tests.test_noise_guard -v`. Expected: 6 tests OK.

- [ ] **Step 5: Commit.**

```bash
git add backend/audio_engine/noise_guard.py backend/tests/noise_fixtures.py backend/tests/test_noise_guard.py
git commit -m "feat(noise-guard): add pre-roll subtraction and transient gating"
```

### Task 2: Wire the guard into the analyzer

**Files:**
- Modify: `backend/audio_engine/analyzer.py` (`AudioAnalyzerSettings` ~L180, `load_settings` ~L341, `_analyze_with_context` ~L1588, `extract_loudness` ~L918, `estimate_noise` ~L970, `evaluate_quality` ~L1508, `_build_parser` ~L2033, `analyze_audio` ~L1662)
- Modify: `backend/audio_analyzer_settings.json` (add a `"noise_guard"` section with the Task 1 defaults; `enabled: true`)
- Test: `backend/tests/test_noise_guard_analyzer.py`

**Interfaces:**
- Consumes: `apply_noise_guard`, `NoiseGuardConfig` (Task 1).
- Produces:
  - `AudioAnalyzerSettings.noise_guard: NoiseGuardConfig`. `load_settings` validates the section, rejects unknown keys like the other sections, and requires `0 <= usable_fail_percentage < usable_warn_percentage <= 100`.
  - `analyze_audio(..., noise_preroll_seconds: float = 0.0)` and `_analyze_with_context(..., noise_preroll_seconds: float = 0.0, noise_guard: NoiseGuardConfig | None = None)`.
  - CLI flag `--noise-preroll-seconds FLOAT` (default 0.0).
  - `_analyze_with_context` raises `AudioAnalysisError("Record at least 10 seconds of song after the noise check.")` when `noise_preroll_seconds > 0` and the audio after the pre-roll split is shorter than 10.0 s (`song_samples < 10.0 * sample_rate`). With no pre-roll this check is skipped, because the existing 10 s whole-file check already covers it. Add two tests in Step 1: `test_short_song_after_preroll_raises` (3.0 s pre-roll + 9.0 s song = 12.0 s file raises with that exact message) and `test_ten_second_song_after_preroll_is_accepted` (3.0 s pre-roll + 10.0 s song = 13.0 s file analyzes and reports `noise_guard.preroll_seconds == 3.0`).
  - The results dict gains a top-level `"noise_guard"` (Task 1 `report`).
  - `AnalysisContext.active_frames` becomes `active & keep_frames`.
  - `extract_loudness` uses `context.loudness_audio`, a new context field holding the kept segments concatenated with 10 ms crossfades (equal to `audio` when nothing was dropped).
  - When a pre-roll profile exists, `results["noise"]` takes `noise_dbfs = preroll_noise_dbfs`, `reliable = True` and `source = "preroll"`. Otherwise it's unchanged, with `source = "quiet_frame_estimate"`.
  - `evaluate_quality`: usable < `usable_fail_percentage` is a failure with the reason `"Too noisy: less than {fail}% of the recording was usable. Move closer to the speaker or record somewhere quieter."`. Confidence "low" adds a warning.

- [ ] **Step 1: Write the failing tests.**
  - `test_settings_rejects_unknown_noise_guard_key`
  - `test_cli_preroll_flag_reaches_analysis` (run `main([...,"--noise-preroll-seconds","3"])` on a temp WAV with pre-roll; JSON output has `noise_guard.preroll_seconds == 3.0`)
  - `test_song_started_during_preroll_skips_subtraction` (pre-roll = music; asserts `subtraction_applied is False` and the exact warning text from Task 1)
  - `test_mostly_noise_recording_fails_quality_without_crashing` (music + continuous shouting-like bursts that leave usable < 30 %; asserts quality status `failed` and the reason starts with `"Too noisy"`)
  - `test_preroll_sets_reliable_noise_level` (`results["noise"]["reliable"] is True` and `["source"] == "preroll"`)
  - `test_zero_preroll_matches_previous_metrics` (clean `music_like`, preroll 0: bass/treble/flatness/sharpness/LUFS equal to a run with `noise_guard.enabled=False` within 1e-6, since no transients means nothing is dropped)

  - Every Task 2 fixture that has a pre-roll uses exactly 3.0 s of pre-roll and at least 12.0 s of song, so it never trips the 10 s song minimum by accident. The only exceptions are the two boundary tests above.

- [ ] **Step 2: Run them to verify they fail.** Run `python -m unittest tests.test_noise_guard_analyzer -v`. Expected: FAIL (no flag, no section).

- [ ] **Step 3: Implement the changes listed in Interfaces.** Make sure `_active_frame_mask`'s minimum-frames check runs after combining with `keep_frames`. Catch its error so the gating case becomes the "Too noisy" quality failure instead of an `AudioAnalysisError`.

- [ ] **Step 4: Run the new tests and the existing analyzer suites.** Run `python -m unittest tests.test_noise_guard_analyzer tests.test_audio_analyzer_safety tests.test_noise_reliability tests.test_audio_validation -v`. Expected: all OK.

- [ ] **Step 5: Commit.** `git add` the three files, then `git commit -m "feat(noise-guard): run guard inside analyzer and report confidence"`.

### Task 3: Acceptance harness (synthetic in CI, real files on demand)

**Files:**
- Create: `backend/audio_engine/noise_guard_eval.py` (comparison logic, importable)
- Create: `tools/noise_guard_eval.py` (CLI over real files)
- Test: `backend/tests/test_noise_guard_acceptance.py`

**Interfaces:**
- Consumes: `analyze_audio(..., noise_preroll_seconds=...)` (Task 2), and `_empirical_feature_values` and `summarize_audio_analysis` from `karaok/audio_pipeline/summary.py` for the overall score and status.
- Produces:
  - `TOLERANCES = {"score": 5.0, "loudness": 1.0, "bass": 3.0, "ratio_db": 1.0, "ratio_floor": 1e-5}`
  - `def compare(clean: dict, noisy: dict) -> dict[str, Any]`, which returns per-metric deltas, a per-metric `ok` flag, and an overall `passed: bool` (also requiring the same status).
  - `def run_case(clean_audio, noise_audio, sr, mnr_db, guard: bool) -> dict`. It builds `noise[:3 s] ++ (clean + scaled noise)`, writes a temp WAV, and analyzes with preroll 3.0 (guard on) or with `enabled=False` (baseline).
  - CLI: `python tools/noise_guard_eval.py --clean "audio sample(good)" --noise "audio sample(noise)" --mnr 20 10 5 --limit 10 --out results/noise_guard_eval/`. It writes `cases.csv` (one row per clean × noise × MNR × guard on/off) and `summary.md` (the pass-rate grid in the spec's layout, guard off versus on).
  - The CLI loads each noise file with the analyzer's `load_audio`, downmixes to mono, and resamples to the clean file's rate. It uses the noise file's first 3.0 s as the pre-roll and the next N s as the mix noise, where N = min(clean length, noise length - 3 s), looping the noise if needed. It trims the clean file to the same N. It accepts `.mp3`/`.wav` noise files, skips `.zip`, and maps the category from the file name through `--category jeep=steady chicken=transient motorcycle=transient "Human talk"=babble` (these are the defaults).

- [ ] **Step 1: Write the failing tests.**
  - One tolerance test per 20 dB must-pass cell using `music_like` (20 s, seed 7) and the matching fixture: `test_steady_20db_within_tolerance`, `test_transient_20db_within_tolerance`, and `test_babble_20db_within_tolerance`. Assert `compare(clean, noisy)["passed"]` and print the deltas on failure.
  - Add `test_steady_10db_is_flagged` and `test_transient_10db_is_flagged` with real noise-check profiles. Assert low or medium confidence and at least one noise warning. The 10 dB acceptance rule concerns flagging.
  - `test_guard_improves_on_baseline_steady_10db`: the guard-off case fails at least one tolerance and the guard-on case passes. This proves the harness can detect noise at all.
  - `test_low_mnr_is_flagged`: steady at 5 dB gives `noise_guard.confidence == "low"`.

- [ ] **Step 2: Run them to verify they fail.** Run `python -m unittest tests.test_noise_guard_acceptance -v`. Expected: ImportError.

- [ ] **Step 3: Implement `noise_guard_eval.py` and the CLI.** Tune only the `NoiseGuardConfig` defaults (and mirror them in the settings JSON) until the must-pass tests are green. Never loosen `TOLERANCES`. If a must-pass cell can't be met, stop and report the deltas instead of changing the target.

- [ ] **Step 4: Run them to verify they pass.** Same command. Expected: 7 tests OK. Runtime should be under 60 s. If it's slower, shorten the clips to 15 s.

- [ ] **Step 5: Commit.** `git add` the three files, then `git commit -m "test(noise-guard): add tolerance acceptance harness"`.

### Task 4: API, persistence and migration

**Files:**
- Modify: `backend/karaok/audio_pipeline/pipeline.py` (guest handler ~L83 to L140, user handler ~L257 to L300, response dicts ~L229 and ~L425)
- Modify: `backend/karaok/audio_pipeline/execution.py` (`_run_audio_analyzer` ~L89 and `run_audio_analyzer` ~L219: new kwarg `noise_preroll_seconds: float = 0.0`, appended as `--noise-preroll-seconds` when > 0)
- Modify: `backend/karaok/audio_pipeline/summary.py` (`summarize_audio_analysis`)
- Modify: `backend/karaok/results/records.py` (~L189 INSERT) and `backend/karaok/results/assessments.py` (~L58, ~L95 SELECTs)
- Modify: `database/schema.sql` (`audio_analysis_result`, after `noise_reliable`)
- Create: `database/migrations/20261118_01_noise_guard.sql` (same idempotent `information_schema` pattern and rollback note as `20261025_02_noise_reliable.sql`)
- Test: extend `backend/tests/test_audio_pipeline.py`, plus `backend/tests/test_health_schema.py` if it lists columns

**Interfaces:**
- Consumes: the `results["noise_guard"]` block (Task 2).
- Produces:
  - Form field `noise_preroll_seconds` (optional). It's a float in [0, 5], and anything else returns 400 `"noise_preroll_seconds must be between 0 and 5"`.
  - New columns `noise_guard_usable_pct FLOAT NULL`, `noise_guard_confidence VARCHAR(10) NULL` and `preroll_noise_dbfs FLOAT NULL`.
  - Summary and API response keys: `noise_guard_usable_percentage`, `noise_guard_confidence`, `preroll_noise_dbfs`, `noise_guard_warnings` (the last one is in the response only, not persisted).

- [ ] **Step 1: Write the failing tests.**
  - `test_guest_upload_passes_preroll_to_analyzer` (mock `run_audio_analyzer` and assert the kwarg is 3.0)
  - `test_preroll_out_of_range_rejected` (values "7" and "abc", both 400)
  - `test_missing_preroll_defaults_to_zero` (Review Focus 4)
  - `test_short_song_after_preroll_rejected`: a 12.0 s WAV with `noise_preroll_seconds=3` (9.0 s of song) passes the whole-file check and then returns 422 with `"Record at least 10 seconds of song after the noise check."`, raised by the analyzer (Task 2). Check how `pipeline.py` maps analyzer errors today and add a 422 mapping for this message if it doesn't already produce one.
  - `test_ten_second_song_after_preroll_accepted`: a 13.0 s WAV with `noise_preroll_seconds=3` (10.0 s of song) returns 201 like any normal upload (both handlers return 201 today, at `pipeline.py` ~L252 and ~L455).
  - `test_summary_exposes_noise_guard_fields`
  - `test_records_persist_noise_guard_columns`

- [ ] **Step 2: Run them to verify they fail.** Run `python -m unittest tests.test_audio_pipeline -v`. Expected: the new tests FAIL.

- [ ] **Step 3: Implement it.** Parse the field once in a helper `_parse_noise_preroll(form) -> float` in `pipeline.py` that both handlers use.

- [ ] **Step 4: Run the pipeline, schema and package-contract suites.** Run `python -m unittest tests.test_audio_pipeline tests.test_health_schema tests.test_package_contracts -v`. Expected: all OK.

- [ ] **Step 5: Commit.** `git add` the listed files only, then `git commit -m "feat(noise-guard): accept pre-roll and persist guard results"`.

### Task 5: App recording flow (noise check, phone processing off, placement tip)

**Files:**
- Modify: `frontend/lib/features/assessments/presentation/pages/audio_test_screen.dart` (`AudioInputState` ~L28, `_startRecording` ~L230 to L290, the stop/staging step ~L314, pause ~L293)
- Modify: `frontend/lib/features/assessments/data/audio_staging_service.dart` (`StagedAudio`: add `final double noisePrerollSeconds;` default `0`)
- Modify: `frontend/lib/core/network/api_service.dart` (`submitAudio` ~L485 and `createAudioUpload` ~L470: optional `double noisePrerollSeconds = 0`, sent as `request.fields['noise_preroll_seconds'] = noisePrerollSeconds.toStringAsFixed(1)` only when > 0)
- Modify: `frontend/lib/features/assessments/presentation/pages/recording_checklist.dart`
- Modify: callers that submit staged audio (`audio_test_screen.dart` and `audio_settings_suggestion_screen.dart`) so they pass `staged.noisePrerollSeconds`
- Test: `frontend/test/audio_recording_screen_test.dart`, `frontend/test/api_service_errors_test.dart` (or a new `frontend/test/noise_preroll_test.dart`)

**Interfaces:**
- Consumes: the form field from Task 4.
- Produces: `AudioInputState.noiseCheck`, `const kNoisePreroll = Duration(seconds: 3)`, `const kNoisyPrerollDbfs = -45.0`.

- [ ] **Step 1: Write the failing widget and unit tests.**
  - `recording starts with a 3-second noise check`: after tapping Record, the screen shows `Stay quiet, checking background noise. Don't start the song yet.`. After pumping 3 s it shows `Start the song now.` and the state is `recording`.
  - `noisy noise check shows the placement warning`: a fake amplitude stream at -30 dBFS shows `It's noisy here. Hold the phone about 30 cm (1 ft) from the speaker, pointed at it.`
  - `pause is disabled during the noise check`
  - `recorder config disables phone processing`: the fake recorder captures `RecordConfig` and asserts `autoGain`, `echoCancel` and `noiseSuppress` are all false.
  - `submitAudio sends noise_preroll_seconds only when > 0`: the field is `'3.0'` for a recording and absent for an uploaded file.
  - `checklist shows the placement tip`: the tile title is `Hold the phone close to the speaker` and the subtitle is `About 30 cm (1 ft) away, pointed at the speaker. Being closer cuts background noise more than any filter.`

- [ ] **Step 2: Run them to verify they fail.** Run `cd frontend; flutter test test/audio_recording_screen_test.dart test/noise_preroll_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement it.** Use `_recorder.onAmplitudeChanged(const Duration(milliseconds: 100))` during `noiseCheck`, average `current` dBFS, and cancel the subscription when the check ends. The recording itself is never paused or restarted, since the pre-roll is the first 3 s of the same file. Cancelling during the noise check behaves like cancelling a recording. The 5-minute limit includes the pre-roll, so the song itself can be up to 297 s. For a recording with a pre-roll, the app's minimum becomes 13 s (`AudioStagingService.minDuration` of 10 s + `kNoisePreroll` of 3 s), so the user can't stop before 10 s of song. Add a widget test, `stop is blocked until 13 s when a noise check was recorded`, that shows the existing too-short message at 12 s and allows stopping at 13 s. Picked files keep the 10 s minimum. Stage the recording with `noisePrerollSeconds: 3.0`. Picked files keep 0.

- [ ] **Step 4: Run the tests, then `flutter analyze`.** Expected: the new tests pass and analyze reports no new issues.

- [ ] **Step 5: Commit.** `git add` the listed Dart files and tests, then `git commit -m "feat(noise-guard): add noise check before recording"`.

### Task 6: Report card for noise guard

**Files:**
- Create: `frontend/lib/features/reports/presentation/widgets/noise_guard_card.dart`
- Modify: `frontend/lib/features/reports/presentation/pages/results_screen.dart` (`fromRecord` ~L50: read the new keys with the existing `reportNumber`/`reportBool`-style helpers; pass them into the detailed report next to `noiseReliable` ~L287 and ~L319)
- Modify: `frontend/lib/features/reports/presentation/pages/detailed_report_screen.dart` (render the card after the measurements)
- Modify: `frontend/lib/features/reports/domain/measurement_bands.dart` (`noiseImplication` copy: now "Background noise is measured before the song and removed where possible.")
- Test: `frontend/test/reports/noise_guard_card_test.dart`

**Interfaces:**
- Consumes: the response keys from Task 4.
- Produces: `NoiseGuardCard({super.key, required double? usablePercentage, required String? confidence, required double? prerollNoiseDbfs, List<String> warnings = const []})`. It renders nothing when all three values are null (old saved reports).

- [ ] **Step 1: Write the failing tests.**
  - `high confidence`: shows `Noise guard: High confidence` and `96% of the recording was used`.
  - `low confidence`: shows `Noise guard: Low confidence` and `Results may be affected by background noise. Try again closer to the speaker.`
  - `no pre-roll`: with `prerollNoiseDbfs: null` it shows `No background-noise check (uploaded file)`.
  - `old report`: with all null it finds no `NoiseGuardCard` content.
  - `warnings` are listed verbatim.

- [ ] **Step 2: Run them to verify they fail.** Run `flutter test test/reports/noise_guard_card_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement the card** using the existing report card styling (copy the structure of `what_this_means_card.dart`).

- [ ] **Step 4: Run all report tests.** Run `flutter test test/reports test/report_values_test.dart test/report_accuracy_test.dart`. Expected: pass.

- [ ] **Step 5: Commit.** `git add` the listed files, then `git commit -m "feat(noise-guard): show noise guard result on reports"`.

### Task 7: Real-world evaluation, docs and version

**Files:**
- Use the existing field noise in `audio sample(noise)/` (Don, 2026-11-18): `jeep.mp3` (60.6 s), `motorcycle.mp3` (65.5 s), `chicken.mp3` (60.5 s), `Human talk.mp3` (60.3 s). All are 48 kHz stereo MP3. `noise.zip` holds the same four files, so ignore it. Category mapping for the grid: jeep = steady, chicken and motorcycle = transient, Human talk = babble. The tool also builds a fifth `street_mix` by summing all four at equal RMS. This mix is report-only.
- Create: `docs/noise-guard-evaluation.md` (the pass-rate grid from `tools/noise_guard_eval.py` and the open-field UAT result)
- Modify: `CHANGELOG.md`, `backend/README.md` (new settings section and CLI flag), `deploy.md` (run `database/migrations/20261118_01_noise_guard.sql` before deploying), `frontend/pubspec.yaml` (version from the `dist/` baseline, expected `1.12.0+18`). Coordinate with Don's uncommitted edits to the same files: re-read each one and append without overwriting his lines.

- [ ] **Step 1: Run the real-file evaluation.** Run `python tools/noise_guard_eval.py --clean "audio sample(good)" --noise "audio sample(noise)" --mnr 20 10 5 --limit 10 --out results/noise_guard_eval/`. Expected: every must-pass cell has ≥ 90 % of cases passing with the guard on, and the guard-off pass rate is lower in the same cells.
- [ ] **Step 2: Do the open-field UAT** (manual, Don's team). Use the same karaoke machine, song section, phone and 30 cm distance. Record once in a quiet room and once in the open field with traffic and animals. Pass: overall score within ±5 points, the same status, and confidence not "low". Record both results in `docs/noise-guard-evaluation.md`.
- [ ] **Step 3: Run the full backend suite once, plus `flutter test` and `flutter analyze`.** Expected: all pass.
- [ ] **Step 4: Commit the docs and version** (stage by path), then `git commit -m "docs(noise-guard): evaluation, migration and release notes"`.
