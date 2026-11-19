# Repository layout

## Current layout

| At the root | Contents |
| --- | --- |
| `backend/`, `frontend/`, `admin/` | Python API, Flutter app, and admin app |
| `database/`, `deploy/ovh/` | Database schema and migrations, and OVH deployment assets |
| `docs/`, `tools/` | Project documentation and development utilities |
| `.codex/` and root project files | Workspace configuration, README, changelog, and guides |
| Local data | `audio sample(good)/`, `audio sample(bad)/`, `audio sample(noise)/`, `Generate Settings songs/`, `DATA GATHERING/`, `sample/`, `results/`, `dist/`, `output/`, and `tmp/` |

## Planned changes

| From | To | Reason |
| --- | --- | --- |
| `tools/noise_guard_eval.py` | `tools/noise_guard/noise_guard_eval.py` | Group Noise Guard evaluation tools. |
| `tools/noise_guard_compare.py` | `tools/noise_guard/noise_guard_compare.py` | Group Noise Guard evaluation tools. |
| `tools/noise_guard_oracle.py` | `tools/noise_guard/noise_guard_oracle.py` | Group Noise Guard evaluation tools. |
| `tools/noise_guard_subtraction_probe.py` | `tools/noise_guard/noise_guard_subtraction_probe.py` | Group Noise Guard evaluation tools. |
| `tools/analyze_bad_samples.py` | `tools/audio_samples/analyze_bad_samples.py` | Group audio-sample analysis tools. |
| `tools/check_uat_noise_bands.py` | `tools/audio_samples/check_uat_noise_bands.py` | Group audio-sample analysis tools. |
| `tools/plot_good_sample_boundaries.py` | `tools/audio_samples/plot_good_sample_boundaries.py` | Group audio-sample analysis tools. |
| `docs/empirical-scoring-report.md` | `docs/findings/empirical-scoring-report.md` | Group evidence and findings. |
| `docs/recommendation-quality-findings.md` | `docs/findings/recommendation-quality-findings.md` | Group evidence and findings. |
| `docs/report-reference-audit.md` | `docs/findings/report-reference-audit.md` | Group evidence and findings. |
| `docs/uat-feedback-verification.md` | `docs/findings/uat-feedback-verification.md` | Group evidence and findings. |
| `docs/uat-noise-samples.csv` | `docs/findings/uat-noise-samples.csv` | Group evidence and findings. |
| `docs/deferred-profile-signup.md` | `docs/design/deferred-profile-signup.md` | Group design and calibration guidance. |
| `docs/settings-profile-sources.md` | `docs/design/settings-profile-sources.md` | Group design and calibration guidance. |
| `docs/technician-genre-calibration.md` | `docs/design/technician-genre-calibration.md` | Group design and calibration guidance. |
| `docs/superpowers/specs/2026-11-18-noise-guard-design.md` | `docs/noise-guard/2026-11-18-noise-guard-design.md` | Keep the Noise Guard plan and specification together. |
| `docs/superpowers/plans/2026-11-18-noise-guard.md` | `docs/noise-guard/2026-11-18-noise-guard.md` | Keep the Noise Guard plan and specification together. |
| Root `.gitignore` | Same path | Group existing rules into five sections and add `/audio sample(noise)` and `/DATA GATHERING`. Keep one `/output/` rule. |
| `backend/karaok/modules/genre_settings/` | Remove local cache-only folder | Contains only `__pycache__` and Git search found no imports of the module. |
| `backend/karaok/modules/locations/` | Remove local cache-only folder | Contains only `__pycache__` and Git search found no imports of the module. |
| Ignored, untracked Python and Flutter caches | Remove verified generated directories | Clear project-source `__pycache__` directories, verified pytest caches, `backend/.tmp-tests/`, and Flutter build and Kotlin caches without traversing dependencies, protected data, or platform source trees. |
| Empty `docs/superpowers/` tree | Remove only empty directories after moves | Retire the old plan and specification folders. |
| `README.md`, `backend/README.md`, `database/README.md`, `tools/README.md` | Same paths | Update links and usage paths. Add a repository layout guide to the root README. |
| `backend/tests/test_modular_structure.py`, `backend/tests/test_noise_guard_acceptance.py` | Same paths | Update expected document and CLI paths. |
| Moved scripts and documents with path references | Their destinations above | Update script imports and root discovery, usage examples, document links, and the UAT CSV destination. Give the UAT script a non-writing dry run or help option. |

## Target layout

- `backend/`, `frontend/`, `admin/`, `database/`, and `deploy/ovh/` remain the application and infrastructure roots.
- `docs/` contains this guide, `design/`, `findings/`, `noise-guard/`, and `diagrams/`.
- `tools/` keeps build and development entry points at the root and adds `audio_samples/` and `noise_guard/`. Support folders stay in place.
- Local data and APKs keep their existing locations.

## Investigated, left as is

- The backend package layers, compatibility shims, platform sources, version numbers, deployment files, secrets, uploads, private storage, and local datasets retain their current paths.
- `admin/.gitignore` already ignores cache and log contents while retaining the tracked placeholders.
- The existing bare path in `CHANGELOG.md` is historical prose. Existing relative links within the same destination group keep working.

## Manual follow-up for Don

- In the deployment work, update the reference at `deploy.md:345` from `docs/settings-profile-sources.md` to `docs/design/settings-profile-sources.md` after the move.
