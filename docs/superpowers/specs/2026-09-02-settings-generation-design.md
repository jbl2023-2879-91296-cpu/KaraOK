# KaraOK Adjusted Settings Generation Design

Date: 2026-09-02  
Status: Approved for implementation planning

## Summary

KaraOK will turn a genre-labelled initial recording and the user's current
amplifier-knob positions into adjusted targets for all five supported physical
controls: volume, bass, treble, sharpness, and flatness. Recommendations will
be conservative, deterministic, explainable, and expressed on the amplifier's
actual scale. Users may optionally make a second recording to verify the
result and receive one smaller refinement.

The first release will use a bounded rule engine informed by reproducible
genre audio profiles. It will not claim to control the amplifier remotely or
use a machine-learning model trained without amplifier-position labels.

## Goals

- Generate adjusted targets for all five amplifier knobs.
- Require the initial positions so every target is relative to the user's
  actual starting configuration.
- Provide 0-10 and 0-100 scale presets plus a custom minimum, maximum, and
  increment, while calculating internally on a normalized 0-100 scale.
- Make recommendations genre-specific.
- Explain why every knob should increase, decrease, or remain unchanged.
- Preserve the existing quality-evaluation flow.
- Persist authenticated recommendations and keep guest recommendations local.
- Offer one optional before/after verification and refinement round.
- Make the research inputs, profile versions, and algorithm versions auditable.

## Non-goals

- Remote control of an amplifier.
- Generation of a processed or downloadable corrected audio file.
- Automatic genre detection in the first release.
- An unconstrained machine-learning model that directly predicts knob values.
- Unlimited iterative tuning sessions in the first release.
- A claim that one profile or knob position is universally correct for every
  room, speaker, microphone, or amplifier.

## Research basis and licensing

Genre targets will be derived offline from audio features rather than copied
from consumer equalizer charts.

Primary references:

- Free Music Archive (FMA): 106,574 tracks in a hierarchical genre taxonomy,
  with precomputed Librosa features. Its metadata is CC BY 4.0 and its code is
  MIT licensed. Individual audio retains the artist-selected license.
  <https://github.com/mdeff/fma>
- AcousticBrainz Genre Dataset: large-scale genre annotations joined to
  Essentia audio features, including loudness, band energy, and spectral
  descriptors. The genre data is CC BY-NC-SA 4.0, while AllMusic-derived data
  is limited to non-commercial scientific research. Restricted raw data must
  not be bundled into KaraOK without a separate distribution review.
  <https://mtg.github.io/acousticbrainz-genre-dataset/>
- Essentia MusicExtractor: defines low, middle-low, middle-high, and high
  spectral energy bands, EBU R128 loudness, and spectral descriptors used to
  interpret the dataset features.
  <https://essentia.upf.edu/streaming_extractor_music.html>
- EBU R128: reference method for program loudness and true-peak-aware
  normalization. It informs measurement and safety, not genre-specific knob
  numbers. <https://tech.ebu.ch/publications/r128>

The repository will contain only a generated profile artifact and its source
manifest. It will not contain restricted raw recordings or annotations. The
artifact must identify the source, source version, license, filters, sample
count, calculation method, output checksum, and generation date. Dataset
attribution must appear in project documentation and the app's About/legal
surface before public distribution.

## User flow

1. The user opens **Generate Audio Settings Suggestion**.
2. The user selects or creates an amplifier profile.
3. The user selects the amplifier's physical scale: 0-10, 0-100, or a custom
   validated minimum, maximum, and increment.
4. The user selects a supported genre.
5. The user enters the current positions of all five knobs.
6. KaraOK gives controlled-recording guidance: use the same song section,
   playback level, phone position, and room for any verification recording.
7. The user records or uploads the initial song.
8. The existing analyzer measures loudness, bass, treble, sharpness, flatness,
   noise, distortion, clipping, and the overall quality score.
9. The recommendation engine compares the five measurements with the selected
   genre profile and creates bounded adjusted targets.
10. The results screen displays the original score and five
    **Current -> Recommended** cards, each with a delta, reason, and confidence.
11. The user either finishes, confirms that the settings were applied, or
    optionally records again to verify.
12. A verification recording compares before and after results. KaraOK may
    issue one smaller refinement. If quality worsens, it recommends returning
    to the previous positions.

Confirming the settings updates the amplifier profile's last-known positions.
The UI must never imply that KaraOK changed a physical knob automatically.

## Architecture

The feature is divided into independently testable components:

1. **Genre profile derivation script**
   - Reads approved source feature data outside application runtime.
   - Maps source genres into KaraOK's supported genre taxonomy.
   - Re-extracts KaraOK's exact five measurements from source audio whose
     individual license permits this use. Incompatible precomputed features
     may be used only as a documented cross-check, not mixed directly into the
     target distributions.
   - Produces robust percentile ranges and a source manifest.
   - Writes a deterministic, versioned JSON artifact.

2. **Genre profile loader**
   - Loads and validates the artifact once per backend process.
   - Rejects missing metrics, invalid ranges, unknown schema versions,
     non-finite values, insufficient sample counts, and checksum mismatches.

3. **Recommendation engine**
   - Accepts measurements, genre, normalized current positions, analyzer
     safety signals, and optional prior verification context.
   - Returns five targets, deltas, reasons, confidence values, and versions.
   - Has no Flask, database, or filesystem dependencies after profile loading.

4. **Recommendation API and persistence service**
   - Validates user input and ownership.
   - Invokes the analyzer and recommendation engine.
   - Stores authenticated recommendations transactionally.
   - Returns transient recommendation data for guests.

5. **Flutter settings wizard**
   - Collects amplifier, genre, scale, and current positions.
   - Reuses the existing audio staging and upload behavior.
   - Renders generated targets and optional verification results.

## Genre profile artifact

The backend will add the version-controlled artifact
`backend/audio_thresholds/genre_audio_profiles.json`. Its root fields are:

- `schema_version`: integer artifact format, initially 1.
- `profile_version`: immutable semantic profile identifier.
- `generated_at`: UTC generation timestamp.
- `generator_version`: derivation-script version.
- `sources`: source name, release/checksum, license, citation URL, selection
  filters, and compatible-feature notes.
- `artifact_checksum`: checksum over the canonical profile content.
- `genres`: normalized genre keys mapped to sample count and metric profiles.

Every genre contains `loudness`, `bass`, `treble`, `sharpness`, and `flatness`.
Every metric contains finite numeric `lower`, `preferred`, `upper`, and
`robust_scale` values plus its unit. The invariant is
`lower < preferred < upper`, and `robust_scale` must be positive. No target
value will be hand-filled in this design; the approved derivation script must
produce all values from compatible source measurements before a genre can be
enabled.

Initial supported genres are Rock, Pop, Ballad, Hip-Hop, Classical, R&B, and
General/Other. A genre is enabled only when the derivation report shows enough
compatible source material. Labels must be normalized consistently, including
`HipHop` versus `Hip-Hop`, `Classic` versus `Classical`, and `Soul-RnB` versus
`R&B`.

## Recommendation algorithm

Every physical position is converted to normalized 0-100 form before the
engine runs. For each metric:

1. Read its lower, preferred, and upper genre bounds.
2. If the observed measurement is within the accepted interval, return a zero
   delta and explain that no adjustment is needed.
3. Otherwise, compute the signed distance to the nearest interval boundary.
4. Divide the distance by the profile's robust scale to produce normalized
   error. The robust scale is derived from the profile distribution and must be
   positive.
5. Multiply normalized error by that metric's conservative sensitivity.
6. Apply the known monotonic direction between the physical knob and measured
   feature.
7. Limit the first-pass delta to 15 percent of the full physical scale.
8. Clamp the result to 0-100 and convert it back to the user's selected scale.
9. Round to a supported physical increment.

Conceptually:

```text
error = signed_distance_to_genre_interval(observed)
normalized_error = clamp(error / robust_scale, -1, 1)
raw_delta = direction * sensitivity * normalized_error
bounded_delta = clamp(raw_delta, -15, 15)
target = clamp(current_position + bounded_delta, 0, 100)
```

The first release treats the five control-to-measurement relationships as
primarily monotonic:

- Volume -> integrated loudness
- Bass -> low-frequency energy share
- Treble -> high-frequency energy share
- Sharpness -> normalized sharpness measurement
- Flatness -> spectral-flatness measurement

The engine must acknowledge cross-coupling in its confidence calculation.
Bass, treble, sharpness, and flatness controls can affect more than one
measurement. The optional verification step is the mechanism for detecting
and conservatively correcting that mismatch for a specific amplifier.

### Safety gates

- Do not increase volume when clipping or excessive distortion is detected.
- Do not generate settings for silent, corrupt, too-short, or non-finite input.
- Do not generate settings when any required profile metric is unavailable.
- Low-confidence measurements may produce guidance but not a fabricated knob
  number.
- A recommendation must contain all five valid targets or be marked
  unavailable as a whole; partial hidden failure is not allowed.
- Verification refinements use a smaller maximum delta than the initial pass.
- If verification quality worsens, show the comparison and the prior settings
  as the recommended rollback point.

## Confidence and explanations

Each setting has `high`, `medium`, `low`, or `unavailable` confidence based on:

- Recording validity and duration.
- Distance from the target interval.
- Analyzer measurement quality.
- Clipping, noise, and distortion warnings.
- Whether the result relies on a cross-coupled control.
- Genre profile sample count and spread.
- Whether an amplifier-specific verification response is available.

Example explanation:

```text
Bass: 4.0 -> 5.5 (+1.5)
Low-frequency energy was below the accepted Rock range. Increase Bass
moderately, then use the optional verification recording to confirm the room
and amplifier response. Confidence: High.
```

Explanations are generated from structured reason codes, not stored arbitrary
text, so Flutter can render consistent and testable messages.

## Persistence model

Versioned database migrations will add two principal entities.

### amplifier_profile

- `amplifier_profile_id`
- `user_id`
- `name`
- `scale_min`
- `scale_max`
- `scale_step`
- Last-applied positions for volume, bass, treble, sharpness, and flatness
- `created_at`
- `updated_at`

Profiles are private to their owner. The first profile is named `My Amplifier`
by default, and the schema supports multiple profiles per user.

### settings_recommendation

- `recommendation_id`
- `user_id`
- `assessment_id`
- `amplifier_profile_id`
- `genre`
- `parent_recommendation_id` for optional verification
- Current positions JSON
- Recommended positions JSON
- Deltas JSON
- Structured reasons and confidence JSON
- Before and optional after quality scores
- Algorithm version
- Genre profile version
- Status: generated, applied, verified, reverted, or unavailable
- `created_at`
- `applied_at`

Foreign keys enforce ownership and lifecycle consistency. Assessment deletion
must remove or safely cascade its recommendation. A user cannot attach a
recommendation to another user's assessment or amplifier profile.

The existing `/genre-settings` client flow and public API will be retired.
`genre_preset` and `user_genre_setting` remain read-only during one migration
window solely to preserve historical rows and existing analysis foreign keys;
the new engine never reads or writes their values. The Admin Console policy
will mark both legacy tables read-only. A later, separately approved migration
may archive or remove them after backup and relationship verification. Only
the versioned genre artifact and recommendation engine are authoritative for
new suggestions.

Guests receive the same response shape but no server database row. Their
recommendation and plots are saved through the existing device-local guest
report lifecycle.

## API contract

The authenticated and guest multipart analysis requests add these logical
fields:

```json
{
  "analysis_purpose": "settings_suggestion",
  "genre": "rock",
  "amplifier_profile_id": 12,
  "amplifier_scale": {"minimum": 0, "maximum": 10, "step": 0.5},
  "current_settings": {
    "volume": 5.0,
    "bass": 4.0,
    "treble": 6.0,
    "sharpness": 5.0,
    "flatness": 5.0
  },
  "verification_of": null
}
```

`current_settings` and `amplifier_scale` are serialized JSON multipart fields.
Authenticated clients normally reference a stored amplifier profile; guest
clients send the complete scale. The server validates all values regardless of
client-side validation.

The successful response retains the normal analysis fields and adds:

```json
{
  "settings_recommendation": {
    "id": 41,
    "genre": "rock",
    "profile_version": "2026.09.1",
    "algorithm_version": "1.0.0",
    "overall_confidence": "medium",
    "original_score": 72.4,
    "current": {
      "volume": 5.0,
      "bass": 4.0,
      "treble": 6.0,
      "sharpness": 5.0,
      "flatness": 5.0
    },
    "recommended": {
      "volume": 5.5,
      "bass": 5.5,
      "treble": 5.5,
      "sharpness": 5.0,
      "flatness": 4.5
    },
    "adjustments": []
  }
}
```

The supporting routes are:

- `GET/POST /api/amplifier-profiles`
- `GET/PATCH/DELETE /api/amplifier-profiles/<id>`
- `GET /api/settings-recommendations/<id>`
- `POST /api/settings-recommendations/<id>/apply`

The existing authenticated and guest audio-analysis routes generate the
recommendation. Verification uses the same upload route with
`verification_of`. It must reference an owned, applied recommendation and is
limited to one refinement in v1.

## Flutter design

### Setup screen

- Amplifier profile selector.
- Scale selector with 0-10 and 0-100 presets plus a validated custom maximum.
- Genre selector for enabled profiles.
- Five labeled sliders and numeric inputs constrained to the selected scale.
- Recording-consistency guidance.
- Continue button disabled until every required input is valid.

### Audio screen

- Reuse `AudioTestScreen` recording, selection, preview, retry, and staging
  behavior.
- Display the chosen genre, amplifier, and current positions in a compact
  summary.
- Preserve staged audio on network failure.

### Generated settings screen

- Original quality score and status.
- Five current-to-recommended cards with delta, direction, reason, and
  confidence.
- Prominent clipping or reliability warnings.
- `I've Applied These Settings` action.
- Optional `Record Again to Verify` action.
- `Finish Without Verification` action.

### Verification result

- Before and after quality scores.
- Per-measurement improvements and regressions.
- One smaller refined target set when justified.
- Clear rollback recommendation when the score worsens.

The old unreachable genre and recommended-settings screens should be replaced
or integrated rather than left as a second disconnected flow.

## Error handling

- Invalid scale or knob values: inline field errors before upload and a
  structured 400 API response if bypassed.
- Missing genre profile: retain the quality report and mark recommendation
  unavailable.
- Unsafe recording: explain the exact blocker and allow a new recording.
- Network timeout: retain staged audio and all setup inputs for retry.
- Session expiry: preserve local setup, refresh authentication when possible,
  and ask the user to sign in when refresh fails.
- Persistence failure after successful analysis: roll back the authenticated
  recommendation transaction and return a retryable error without claiming it
  was saved.
- Guest local-storage failure: show the generated result for the active
  session, report that it could not be saved, and do not claim persistence.
- Unsupported profile or algorithm version: reject it explicitly rather than
  silently applying old semantics.

## Testing strategy

### Genre artifact tests

- Deterministic generation and checksum.
- Required source and license metadata.
- Supported genre mapping.
- Minimum sample counts.
- Finite, ordered, non-degenerate ranges.
- No placeholder values.

### Recommendation engine tests

- Increase, decrease, and no-change cases for every metric.
- Dead-zone behavior inside each accepted genre interval.
- Initial and verification delta caps.
- 0-10, 0-100, and custom scale conversion and rounding.
- Lower/upper clamping.
- Clipping prevents volume increase.
- Invalid input produces unavailable recommendations.
- Determinism for identical inputs.
- Structured reason and confidence generation.
- Cross-coupling lowers confidence where required.

### Backend tests

- Authenticated persistence and transaction rollback.
- Guest non-persistence.
- Ownership of amplifier profiles, assessments, recommendations, and
  verification parents.
- Multipart JSON validation.
- Recommendation retrieval and apply confirmation.
- One-verification limit.
- Assessment deletion lifecycle.
- Backward compatibility for normal quality evaluations.

### Flutter tests

- Setup validation for all five inputs and scales.
- Genre and amplifier selection.
- Audio submission includes recommendation context.
- Five generated-setting cards render correctly.
- Safety and unavailable states.
- Apply confirmation updates last-known settings.
- Optional verification and rollback UI.
- Guest and authenticated persistence behavior.

### End-to-end and field validation

An integration test will exercise Flutter inputs, upload, Flask analysis,
recommendation persistence, result rendering, apply confirmation, and optional
verification against a test database and fixed audio fixtures.

Physical validation will use at least five representative songs per supported
genre and low, neutral, and high starting configurations. The song segment,
phone position, room, and playback process must remain controlled between each
before/after pair. Release requires:

- Valid in-range output for all five knobs.
- No clipping-safety violation.
- Positive median overall-score change across the controlled trials.
- Strictly more than 50 percent of controlled trials improve and the number of
  improving trials exceeds the number of worsening trials.
- Explicit review of every worsening or low-confidence case.

## Rollout and observability

1. Add the offline derivation script, source manifest, and validated artifact.
2. Add the pure recommendation engine using test-driven development.
3. Add versioned database migrations and persistence services.
4. Extend API requests and responses behind a feature flag.
5. Replace the disconnected Flutter settings flow.
6. Run unit, widget, backend, integration, and controlled amplifier tests.
7. Enable the feature for internal testing before public release.

Backend logs and audit records will capture recommendation generation status,
genre, profile and algorithm versions, confidence, and failure reason without
logging audio contents or unnecessary personal data. Operational metrics
should distinguish analysis failures from recommendation failures.

## Approved decisions

- Generate all five amplifier settings.
- Require users to enter current positions.
- Support selectable physical scales and normalize internally to 0-100.
- Use explicit genre selection and research-informed profiles.
- Use a bounded deterministic first pass with optional adaptive verification.
- Make verification optional and limited to one refinement in v1.
- Persist authenticated recommendations and keep guest recommendations local.
- Show explanations, confidence, and safe rollback behavior.
