# KaraOK diagram evidence and scope

Prepared 2026-09-11 from the working application at commit `b74ceb8`.
These diagrams use the **editorial-infographics** skill and the **pdf** skill.
The application code and database were not changed or executed for this task.

## Deliverables

- [Client-server architecture, SVG](client-server-architecture.svg)
- [Client-server architecture, PNG](client-server-architecture.png)
- [Level 1 DFD, SVG](dfd-level-1.svg)
- [Level 1 DFD, PNG](dfd-level-1.png)
- [Two-page A2 landscape PDF](../../output/pdf/karaok-application-diagrams.pdf)

The SVGs contain vector shapes and text. The PNGs are rendered from the actual
PDF pages. The architecture source canvas is 2200 x 1280; the DFD source canvas
is 2400 x 1800. PDF pages are A2 landscape, with each diagram fitted without
stretching. Exported page PNGs are 2779 x 1965 pixels.

## What "current ERD" means here

**Verified:** [database/schema.sql](../../database/schema.sql) defines exactly
11 application tables. [database/README.md](../../database/README.md), lines
3-5, calls it the authoritative fresh-install schema. No separate ERD image,
draw.io file, Mermaid ERD, or server-schema export was found in the current
project inventory. Every D-store ID in the DFD maps to exactly one table below.

**Known alternative:** the [server compatibility migration notes](../../database/migrations/20260908_01_server_compatibility.md),
lines 3-12, describe an older export with 12 tables and a compatibility outcome
of 14 tables. That migration preserves retired `genre_preset`,
`audio_quality_threshold`, and `user_genre_setting` structures. The current
diagram does not claim to match that older server ERD. The live server was not
queried, and the referenced server export is not present in the inspected
project. The user was offered the choice of schema basis during preparation;
the current checked-in 11-table application schema is the default basis.

| DFD ID | Exact ERD table | Schema declaration line | Owner / relation |
|---|---|---:|---|
| D1 | `user` | 19 | Account root |
| D2 | `assessment` | 60 | `user_id` -> `user` |
| D3 | `audio_upload` | 280 | Unique `assessment_id` -> `assessment` |
| D4 | `audio_analysis_result` | 94 | Unique `assessment_id` -> `assessment` |
| D5 | `amplifier_profile` | 146 | `user_id` -> `user` |
| D6 | `settings_recommendation` | 170 | User, assessment, amplifier profile; nullable parent recommendation |
| D7 | `registration_otp` | 324 | Unique `user_id` -> `user` |
| D8 | `refresh_token` | 229 | `user_id` -> `user` |
| D9 | `revoked_access_token` | 247 | `user_id` -> `user` |
| D10 | `audit_log` | 260 | Nullable `user_id` -> `user` |
| D11 | `api_request_log` | 302 | Nullable `user_id` -> `user` |

F1 (analysis files), F2 (checked-in reference/configuration JSON), and S1
(`information_schema`) are explicitly distinguished from the 11 application
tables. Client caches and the PHP console's private files are outside the
server-side DFD boundary and appear in the architecture diagram.

## Evidence pack

All source paths below are relative to the project root. Line numbers refer to
the inspected revision. "Verified" means found in the implementation; it does
not assert that a feature is enabled on a running deployment.

| Diagram claim | Status | Implementation evidence |
|---|---|---|
| Flutter exchanges JSON and multipart audio with the API; signed-in calls use bearer access tokens | Verified | `frontend/lib/core/network/api_service.dart:32,140,350,366,462` |
| Tokens use secure storage; signed-in history and image bytes have per-user caches | Verified | `frontend/lib/core/security/secure_token_store.dart:9`; `frontend/lib/core/storage/analysis_cache.dart:21` |
| Guest records/report images and optional amplifier profiles are device-local | Verified | `frontend/lib/core/storage/guest_assessment_store.dart:25`; `frontend/lib/features/sound_settings/data/guest_amplifier_store.dart:27` |
| Guest analysis returns `persisted: false`; it does not create assessment, result, upload, profile, or recommendation rows | Verified | `backend/karaok/application.py:2321,2439,2445`; `backend/karaok/modules/settings_recommendations/service.py:393` |
| Guest API requests can still generate request-log metadata | Verified | `backend/karaok/application.py:1274` |
| Admin browser uses a local PHP console with local account validation, PHP sessions and CSRF checks | Verified | `admin/app/Security/AuthService.php:19`; `admin/config/bootstrap.php:31`; `admin/public/index.php:19` |
| Console private files contain accounts, throttling and preferences in JSON; activity is JSONL | Verified | `admin/config/bootstrap.php:51,69`; `admin/app/Support/ActivityLogger.php:24` |
| PHP uses server-side cURL to the Flask admin API, with a separate bearer API key and actor header | Verified | `admin/app/Api/AdminApiClient.php:14,77`; `backend/karaok/security/admin_data_auth.py:14` |
| Flask feature modules are one application, with separate normal/admin MySQL connection identities | Verified | `backend/karaok/application.py:2888`; `backend/karaok/infrastructure/database.py:8,12` |
| Analyzer is a local Python subprocess, not a remote model service | Verified | `backend/karaok/application.py:341,353,388,404,518` |
| Temporary source audio is deleted; successful signed-in waveform/spectrogram PNGs are retained and referenced by relative DB paths | Verified | `backend/karaok/application.py:263,303,518,1038,2644` |
| Quality/genre/prior reference data comes from JSON files rather than lookup tables | Verified | `backend/audio_thresholds/good_audio_thresholds.json`; `genre_audio_profiles.json`; `amplifier_control_priors.json`; `backend/karaok/modules/settings_recommendations/service.py:539,844` |
| Analyzer settings also come from a checked-in JSON configuration file | Verified | `backend/audio_analyzer_settings.json`; `backend/audio_engine/analyzer.py:2165` |
| Registration and password recovery send email through SMTP with STARTTLS | Verified | `backend/karaok/application.py:1212,1239,1245,1264` |
| Nginx -> Gunicorn -> Flask is checked-in deployment wiring | Verified configuration | `deploy/ovh/nginx-https.conf:15`; `deploy/ovh/karaok-api.service:3` |
| Settings generation/profile endpoints are feature-gated and default off | Verified default | `backend/karaok/config.py:45`; `backend/karaok/modules/settings_recommendations/routes.py:16`; `backend/karaok/application.py:2345,2512` |
| Admin Data API is separately configuration/key-gated | Verified | `backend/karaok/security/admin_data_auth.py:14` |
| Current live deployment flags, SMTP availability and physical hosting locations | Unknown | No live-service or environment-secret inspection was performed |

## Level 1 decomposition and flow evidence

The DFD is an **interpretation of the verified code**, grouped into six logical
processes. These numbers are documentation labels, not invented services or
separate application modules. Each panel is a portion of the same DFD;
repeated entities and data-store IDs identify the same objects. Process
references repeated in 6.0 show the cross-cutting logging flows.

### 1.0 Manage accounts and sessions

Inputs: credentials, registration verification code, profile data, session
tokens and password-recovery/change requests. Outputs: profile/account state,
tokens and email messages for the SMTP service.

- D1: registration, verification state, login/security reads, password changes,
  and profile updates.
- D7: create/read pending hashed verification code, increment attempts and
  remove it on successful verification.
- D8: create/read/rotate/revoke refresh sessions.
- D9: record revoked JWT identifiers and check them on protected requests.

Evidence: `backend/karaok/application.py:1365,1404,1533,1685,1768,1821,1860,1898,1948,2020`.
Protected requests in other processes use this shared authentication logic;
the DFD does not repeat every middleware database read.

### 2.0 Evaluate playback; generate/verify recommendations

Audio uploads create D2 and D3 before analysis. Success creates D4 and updates
the assessment/upload status and score. Failure can leave D2/D3 without D4.
Conditional settings generation reads D5, creates D6 and may read/update a
parent D6 recommendation when processing a verification recording. P2 does
not update amplifier-profile last positions.

F1 contains the transient audio/analyzer output and retained report PNGs.
F2 supplies analyzer configuration, quality thresholds and genre references.
Control priors are exposed by the metadata workflow in P3, rather than used
by the recommendation calculation itself.

Evidence: `backend/karaok/application.py:894,960,982,1038,1081,1135,1160,1172,1187,2321,2489,2550,2563`;
`backend/karaok/modules/settings_recommendations/service.py:208,376,539`.

Guest processing returns scores, base64 report PNGs and optional recommendation
data to E1. Its business IDs are null. Guest verification uses a signed token,
not a database recommendation parent/child pair. Temporary guest files are
removed after constructing the response. Request/audit metadata is separate.

### 3.0 Manage amplifier profiles and applied state

D5 supports owner-scoped list/get/create/update/delete. Applying a generated
recommendation reads D5/D6 together, updates D5 `last_positions`, and updates D6
status/timestamp together. This is a user confirmation, not hardware telemetry
or a command sent to an amplifier. F2 also supplies public profile metadata.
The metadata endpoint is public when enabled; saved-profile operations require
authentication. Deleting D5 cascades its D6 rows, but preserves assessments.

Evidence: `backend/karaok/modules/settings_recommendations/routes.py:67,74,81,122,132,146`;
`backend/karaok/modules/settings_recommendations/service.py:832,844,915,950,1001,1026,1069`.

### 4.0 Manage records and reports

History, upload lists and reconstructed reports join D2-D6, scoped to the user.
Visualization requests use owned D2/D4 rows to locate F1 PNGs. Deleting an
assessment removes D2, cascades D3/D4/D6, then attempts F1 cleanup.

The implemented `POST /api/audio-tests` direct-save endpoint is included here:
it creates D2 and a partial D4 from client-supplied values, using F2 quality
provenance. It does not run the analyzer or create D3/D6/report images. The
client's `createAudioTest` method exists; the diagram does not imply a separate
visible manual-entry screen.

Evidence: `backend/karaok/application.py:2142,2179,2214,2262,2292,2719,2758`;
`frontend/lib/core/network/api_service.dart:366`.
History's legacy scoring fallback may read the current quality reference to
complete the response without rewriting stored records (`application.py:756`).

### 5.0 Inspect and administer data

The current policy permits record reads on D1-D6 and D10-D11; it blocks record
contents for D7-D9. Its allowed writes are D1 `is_active`, D2
`assessment_status`, and D2 deletion. No table currently has allowed create
fields, even though a generic POST route exists. Assessment deletion also
attempts F1 cleanup. S1 represents inspected MySQL table/column/index/FK
metadata; it is not a twelfth application table.

Evidence: `backend/karaok/modules/admin_data/policy.py:27`;
`backend/karaok/modules/admin_data/service.py:70,103,142,166,274,310,347`;
`backend/karaok/modules/admin_data/routes.py:13,95,106`;
`backend/karaok/modules/admin_data/reports.py:91`.

### 6.0 Record audit and API activity

Audit-instrumented actions write D10; the non-test API after-request hook
attempts to write D11 for API requests other than OPTIONS. D11 excludes request
bodies, credentials, tokens, OTPs and uploaded audio. P5 provides the operational
read side; legacy authenticated admin-only log endpoints also exist.

Evidence: `backend/karaok/application.py:1274,1284,1322,2858,2872`;
`backend/karaok/modules/admin_data/routes.py:13`;
`backend/karaok/modules/settings_recommendations/routes.py:55`.

## ERD consistency qualifications

- Unique assessment foreign keys mean **at most one** upload/result per
  assessment, not guaranteed existence. Direct saves may lack an upload;
  failed analysis may lack a result.
- A recommendation belongs to a user, an assessment and an amplifier profile.
  `parent_recommendation_id` links recommendations, not assessment rows.
  Its unique constraint allows at most one verification child for each parent.
- Deleting a parent recommendation sets a surviving child's parent ID to null.
- Account deletion cascades account-owned business/security records; audit and
  request-log user references become null. The diagram only draws deletion
  operations actually offered by the reviewed workflows, not every theoretical
  foreign-key cascade.
- Reference JSON, guest storage, profile-image bytes and temporary audio are
  not invented tables. Profile images are columns on `user`; audio bytes are
  not stored in `audio_upload`.

## Visual brief and production receipt

**Architecture takeaway:** clients request work from one backend, which owns
database and analysis storage access. Primary job: map. Layout family: layers;
the columns communicate real client/server/storage responsibility boundaries.

**DFD takeaway:** six server-side processes exchange named data with clients,
the email service and the exact 11-table model. Primary job: explain/map.
Topology: directed data-flow network, laid out in six readable flow panels;
containment separates logical areas and repeated IDs preserve shared stores.
It is not a process-execution sequence or an ERD relationship drawing.

Canvas: white, dark green text, one restrained green accent. Text and arrows
are generated deterministically. No AI-generated text, invented screenshots,
icons, provider brands, or external search claims are used.

Reproduction: run `render_diagrams.py` using Python with reportlab, pypdf,
pypdfium2 and Pillow. Final copy is also saved in each `.labels.txt` file.
`store-dictionary.json` gives exact D-store mappings. `receipt.json` contains
SHA-256 hashes and schema/page verification results.

QA: the renderer checks all 11 table names against CREATE TABLE declarations,
checks constrained text widths, reopens the two-page PDF, extracts its text,
and verifies that all table names appear. The final PDF is rasterized for visual
inspection. Technical diagrams require full-size viewing or zoom; they are not
social-media thumbnail graphics.

Self-assessed editorial quality after visual review: architecture **15/16**;
DFD **14/16**. Evidence and visual-job scores are 2/2 for each. The DFD needs
zoom for small edge labels; its large-format canvas is deliberate. Live-server
state and the unavailable separate ERD remain explicit limitations.
