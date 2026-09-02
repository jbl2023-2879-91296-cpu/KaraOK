# Instrumental Settings Calibration and Database Simplification Design

**Date:** 2026-09-03
**Status:** Approved in conversation; awaiting written-spec review

## Purpose

KaraOK evaluates instrumental karaoke-machine playback and recommends adjusted
positions for five physical controls: Volume, Bass, Treble, Sharpness, and
Flatness. The user records the sound emitted by the machine's speakers, enters
the current physical positions, selects a genre, and receives five bounded
recommendations. After applying them, the user may record again to verify
whether the measured quality improved.

The application analyzes the audio waveform produced by MIDI playback. It does
not parse `.mid` event files and does not evaluate a singer, microphone input,
vocal balance, feedback, or microphone effects.

## Decisions

1. Versioned JSON artifacts remain authoritative for empirical quality
   thresholds, genre targets, and researched control starting priors.
2. Python remains authoritative for calculation logic and safety rules.
3. MySQL stores transactional application state and the versions/checksums that
   explain each result; it does not duplicate mutable copies of reference
   targets.
4. `genre_preset`, `audio_quality_threshold`, and `user_genre_setting` are
   retired without replacement tables.
5. The five user-facing settings remain exactly Volume, Bass, Treble,
   Sharpness, and Flatness.
6. Current genre profiles are provisional because their existing FMA source
   manifest is not documented as instrumental-only. They remain available with
   appropriately conservative confidence until regenerated from a licensed,
   genre-representative instrumental or rendered-MIDI corpus.

## Sources of truth

### Empirical quality artifact

`backend/audio_thresholds/good_audio_thresholds.json` contains global empirical
quality ranges derived from the prior reference dataset. It governs whether the
recording is good, needs improvement, bad, or unavailable and contributes the
overall quality score.

The artifact and derivation code will expose and validate:

- schema version;
- quality-profile version;
- scoring algorithm version;
- source dataset identity and checksum;
- artifact checksum;
- sample counts and measurement units;
- per-feature empirical distributions and score anchors;
- overall feature weights and status boundaries.

### Genre profile artifact

`backend/audio_thresholds/genre_audio_profiles.json` contains per-genre lower,
preferred, and upper targets plus robust scales for loudness, bass, treble,
sharpness, and flatness. It determines the direction and normalized magnitude
of each control adjustment.

### Control-prior artifact

A small versioned artifact,
`backend/audio_thresholds/amplifier_control_priors.json`, will document the
neutral starting setup and its research basis. Its initial normalized 0-100
positions are:

| Control | Position | Basis |
| --- | ---: | --- |
| Volume | 40 | Conservative starting headroom; not a universal optimum |
| Bass | 50 | Neutral midpoint |
| Treble | 50 | Neutral midpoint |
| Sharpness | 50 | Neutral project assumption pending hardware response data |
| Flatness | 50 | Neutral project assumption pending hardware response data |

The artifact contains a schema version, prior version, positions, citations,
assumptions, and canonical checksum. It does not contain executable formulas.
The backend validates it and exposes the normalized defaults and version through
the existing settings-profile metadata endpoint.

The setup screen does not silently claim these defaults are the user's current
positions. It provides a clearly labelled **Use researched starting point**
action. When selected, the app converts the normalized values to the chosen
physical scale and tells the user to put all five real controls at those
positions before recording. A saved amplifier's last applied positions always
take precedence.

## Research basis and limitations

- ITU-R BS.1770-5 is the reference for objective programme loudness and
  true-peak concepts:
  <https://www.itu.int/rec/R-REC-BS.1770-5-202311-I/en>.
- Yamaha documents the midpoint of conventional bass and treble controls as a
  flat response:
  <https://manual.yamaha.com/av/22/rn1000a/en-US/8393117835.html>.
- Librosa defines spectral flatness as a measure of how noise-like rather than
  tone-like a spectrum is:
  <https://librosa.org/doc/main/generated/librosa.feature.spectral_flatness.html>.
- Standard acoustic sharpness is normally expressed in acum under methods such
  as DIN 45692. KaraOK's existing `normalized_score` remains explicitly an
  approximation and must not be labelled as standards-compliant acum:
  <https://www.mathworks.com/help/audio/ref/acousticsharpness.html>.

Online guidance can justify neutral starting behavior, measurement definitions,
and safety constraints. It cannot establish universally optimal physical dial
positions because control response depends on the hardware, loudspeakers,
playback level, room, and recording placement. Genre-specific targets therefore
come from extracted audio distributions, not from unsourced web EQ recipes.

The Lakh MIDI Dataset is a possible future multi-genre symbolic source, but its
own documentation warns about corrupt files, inconsistent attribution, and some
incorrect MIDI/audio matches. It must not be imported automatically without a
license and quality review: <https://colinraffel.com/projects/lmd/>. MAESTRO is
well documented but piano/classical-specific and cannot support all KaraOK
genres by itself: <https://magenta.withgoogle.com/datasets/maestro>.

## Recommendation algorithm

The physical-control-to-measurement contract is:

| Physical control | Primary recorded measurement |
| --- | --- |
| Volume | Integrated loudness |
| Bass | Bass-band energy percentage |
| Treble | Treble-band energy percentage |
| Sharpness | Approximate normalized sharpness score |
| Flatness | Mean spectral flatness ratio |

For each control:

1. Validate that the recording, current position, amplifier scale, and selected
   genre target are complete and finite.
2. Leave the control unchanged when its measurement is within the genre's
   accepted lower-to-upper interval.
3. Otherwise calculate signed distance to the nearest accepted boundary.
4. Divide by the target's robust scale and clamp the normalized error to
   `[-1, 1]`.
5. Apply the versioned recommendation sensitivity in the direction of the
   preferred interval.
6. Cap an initial change at 15 normalized points and a verification change at
   7.5 normalized points.
7. Convert back to the amplifier's physical range, round to its real increment,
   and clamp to its minimum and maximum.

The engine must continue blocking Volume increases when clipping or excessive
distortion is detected. Cross-coupled spectral controls receive reduced
confidence because one physical adjustment may change multiple measurements.
All five results are returned even when a control remains unchanged.

The assumed physical direction is monotonic: increasing a named control
increases its corresponding measured property. This is an explicit baseline
assumption until hardware-specific response curves are available. Verification
recordings are the mechanism for detecting and correcting poor assumptions.

## Confidence

Confidence must communicate evidence rather than merely successful execution.
It is reduced when:

- a genre has fewer than 20 reference recordings;
- a measurement is far outside its reference distribution;
- noise, distortion, clipping, or insufficient active audio is detected;
- spectral controls are likely to be cross-coupled;
- the profile corpus is not confirmed instrumental-only;
- a hardware-specific transfer curve is unavailable.

With the current five recordings per enabled genre, the feature remains a
conservative starting assistant and must not claim universal or professionally
validated optimality.

## Runtime data flow

1. The client loads enabled genres, artifact versions, and researched starting
   positions from `GET /api/settings-profile-metadata`.
2. The user selects an existing amplifier or creates one with a 0-10, 0-100,
   or custom scale.
3. The user enters all five actual positions or explicitly applies the
   researched starting point and physically matches the machine to it.
4. The user selects a genre and records the machine's instrumental playback
   under controlled placement.
5. The backend extracts the five audio features and empirical safety signals.
6. The quality scorer evaluates the recording against the global empirical
   artifact.
7. The recommendation engine compares the same measurements with the selected
   genre artifact and produces five bounded control positions.
8. Authenticated results are committed with the assessment; guest results stay
   device-local.
9. Applying a recommendation updates the saved amplifier's last positions.
10. An optional second recording verifies the result and permits only the
    smaller refinement cap.

## Database changes

The following business tables remain:

- `user`
- `assessment`
- `audio_analysis_result`
- `audio_upload`
- `amplifier_profile`
- `settings_recommendation`
- `refresh_token`
- `revoked_access_token`
- `registration_otp`
- `audit_log`
- `api_request_log`

The following legacy tables are removed:

- `genre_preset`
- `audio_quality_threshold`
- `user_genre_setting`

`audio_analysis_result.preset_id` and
`audio_analysis_result.threshold_id`, their indexes if present, and their
foreign keys are removed. The obsolete genre-preset lookup in analysis
persistence is removed. Admin Data API policies and tests stop advertising the
three retired tables.

`audio_analysis_result` records the quality-profile version and checksum in
addition to the scoring algorithm version. `settings_recommendation` records
the genre-profile version and checksum in addition to the recommendation
algorithm version. Published artifact versions are retained in source control
so historical results can be reproduced.

The development database contains only disposable test data, so it may be
rebuilt from the updated authoritative `database/schema.sql`. The implementation
must not drop or recreate an unspecified database. The integration runner keeps
using its isolated, explicitly named test database.

## Failure behavior

- Missing, malformed, incomplete, or checksum-invalid artifacts make settings
  generation unavailable; the backend never substitutes invented targets.
- A missing genre profile preserves the ordinary quality report and marks the
  recommendation unavailable.
- Silent, corrupt, too-short, or non-finite analysis produces no knob changes.
- A user who selects the researched starting point must acknowledge that the
  physical machine was set to match before recording.
- Unsupported `.mid` uploads receive a clear message that the app records or
  accepts rendered audio, not symbolic MIDI events.
- No endpoint, response, instruction, or confidence calculation introduces
  microphone or vocal processing.

## Verification

### Artifact tests

- Validate exact control keys, finite normalized defaults, versions, citations,
  canonical checksums, and schema rejection.
- Verify that regenerated empirical and genre artifacts are deterministic.
- Verify that source documentation identifies whether each recording is
  instrumental and records its license.

### Engine tests

- Cover in-range dead zones, signed changes, scale conversion, step rounding,
  clamping, initial and verification caps, and all five controls.
- Preserve the clipping/distortion Volume guard.
- Verify deterministic output for identical inputs and artifact versions.
- Verify conservative confidence for the current small or non-instrumental-only
  cohorts.

### API and database tests

- Verify metadata returns enabled genres and the versioned researched defaults.
- Verify saved results contain artifact versions/checksums.
- Verify the authoritative schema excludes the three retired tables and two
  retired result columns.
- Verify foreign-key cascades for assessments, uploads, recommendations, and
  amplifier profiles remain intact.
- Verify the Admin Data API catalog contains only supported tables.

### Flutter and end-to-end tests

- Verify the starting-point action converts 40/50 normalized positions onto
  0-10, 0-100, and custom scales without silently overwriting saved positions.
- Verify the user must acknowledge matching physical controls before recording.
- Verify the five labels and request keys remain Volume, Bass, Treble,
  Sharpness, and Flatness.
- Run the full authenticated Android flow through recording, analysis,
  persistence, recommendation display, apply, reload, and verification.

## Rollout and rollback

1. Add and validate the control-prior artifact and metadata contract.
2. Add provenance fields and update persistence.
3. Remove legacy code references, schema objects, admin policies, and tests.
4. Update the Flutter starting-position interaction.
5. Rebuild only the disposable development/integration databases from the
   authoritative schema.
6. Run affected suites, backend tests, Flutter tests, Admin tests, and Android
   integration.

Rollback is application-first: disable settings recommendations with the
existing feature flag. Database rollback must restore the matching prior schema
and application together; reference data remains recoverable from versioned
artifacts.

## Out of scope

- Microphone input, singers, vocals, vocal isolation, feedback, and mic effects.
- Remote or automatic movement of physical amplifier controls.
- Live administrator editing of reference profiles.
- Parsing or synthesizing `.mid` event files.
- Claiming universal optimality or hardware-specific calibration without
  measured response data.
