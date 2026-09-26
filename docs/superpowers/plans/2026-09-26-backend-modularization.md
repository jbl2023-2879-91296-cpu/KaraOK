# Backend modularization implementation plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task by task.

**Goal:** Extract the backend implementation while preserving existing behavior, routes, signatures, and legacy dependency patching.

**Architecture:** Shared core below accounts, results, and the audio pipeline. External processing callers use `audio_pipeline.pipeline`. Existing entry points remain compatibility interfaces; business modules never import the application composition module.

**Tech stack:** Python 3.13, Flask, MySQL connector, NumPy/librosa, unittest.

**Spec:** User-approved function inventory and dependency proposal in this conversation (2026-09-26).

## Constraints

- Keep all public function names/signatures, Blueprint names, HTTP behavior, subprocess execution, scoring formulas, transaction order, and cleanup semantics.
- Core imports no feature modules or application module. Importing core must not construct Flask.
- Results never import audio pipeline stages or orchestrator. Preserve legacy scoring through shared core scoring.
- Recommendation persistence keeps locked-row validation inside the transaction.
- Retain the numerical audio engine and immutable artifact locations.
- Use existing branch `refactor/backend-modularization`; no merge or push.
- User requires stopping on unexpected failures, rather than improvising fixes.

## Verification

Baseline: 251 tests passed using `backend/.venv.DESKTOP-RV5OA8H/Scripts/python.exe`.
The documented `.venv` points to a missing interpreter; do not modify it.
After EVERY extraction run, from backend:
`./.venv.DESKTOP-RV5OA8H/Scripts/python.exe -m unittest discover -s tests -p 'test_*.py'`

## Review focus

1. Cold imports of core and numerical compatibility packages must not bootstrap Flask or cycle.
2. Patching legacy application dependencies must reach extracted implementations and restore correctly.
3. Route method/path/endpoint identities and old callable signatures must remain identical.
4. Historical scoring and verification persistence must not call the pipeline backwards.
5. Artifact paths, rate-limit decorators, and request hook ordering must retain original behavior.

## Tasks

- [x] 1. Foundations: core config/database/validation/runtime, lazy package bootstrap, legacy compatibility adapter. Add cold-import, contract, and patch-restoration tests before extraction. Move config without changing backend/artifact paths. Full suite.
- [x] 2. Shared computations: core thresholds/quality/accounts/artifacts/audit and shared recommendation models. Preserve old import interfaces and JSON artifact locations. Full suite.
- [x] 3. Accounts: auth access/tokens/mail/accounts and user profiles; route ownership changes. Preserve signatures, decorators, and dependency patches. Full suite.
- [x] 4. Results: persistence, presentation, profile/recommendation records and binding checks. Separate summarization from database transaction without changing public persist signature. Full suite.
- [x] 5. Pipeline: execution, summary, upload workflow, generation, visualization encoding. Expose through pipeline only. Preserve subprocess and temporary-file behavior. Full suite.
- [x] 6. Admin and composition: admin modules, health, request logs, route registration. Remove feature implementation from application. Full suite, compile, contract/import checks, local review (independent review unavailable).

## Execution record

- Plan reflects the confirmed design; execution authorized by user's `confirm`. Implement inline, preserving the explicitly requested stop-on-unexpected-failure rule.
- User subsequently granted full autonomy to resolve routine issues, then required an explicit `go` before each subsequent task. Paused after accounts extraction; do not start results until `go`.
- Contract fixture records 69 function signatures, two exception constructor signatures, and all registered routes. Inherited exception signatures use `__init__` because inspect.signature on the ValueError subclass is unsupported.
- Foundations: 253 tests passed. An initial suite invocation from repository root failed import resolution; rerunning the documented command from backend passed.
- Shared extraction: scoring/profile artifact loaders, account helpers, paths/artifacts, audit writer, and password helpers relocated with original import aliases. 253 tests passed. Recommendation model extraction remains for the results/recommendation step.
- Accounts extraction: registration/login/password handling, tokens, access checks, email helpers, and profile update moved. Auth and profile-update routes call their owning modules. 255 tests passed (including new cold-import and legacy override restoration checks).
- No changes to scoring formulas, artifact JSON, schema, endpoints, or public signatures. Work remains uncommitted on refactor/backend-modularization.
- User authorized results with `go`. Results task completed; wait for another `go` before audio-pipeline extraction.
- Results: extracted history, saved visualization delivery, amplifier profile CRUD, recommendation read/apply, and upload/analysis record transactions. Shared recommendation models, verification contracts, and payload serializers moved below results/pipeline; original imports remain available.
- `persist_audio_analysis` retains its original signature and pre-summary validation in application until the pipeline task. It computes the summary then calls `results.records.save_audio_analysis`, which performs the original transaction without recomputation. Initial upload-record creation and rollback cleanup now live in `create_audio_upload_records`.
- Full suite after primary results extraction: 256 passed. After route ownership/upload-record extraction and direct prepared-summary persistence test: 257 passed. Compileall succeeded. AST comparison confirmed 15 extracted application definitions and 35 recommendation definitions unchanged; transaction and wrapper changes reviewed separately.
- Local extraction helpers are scratch tooling, not shipped code. Do NOT blindly rerun `extract_modules.py`: it regenerates from the original source and would overwrite the manually extracted persistence wrapper, upload-record delegation, records writer, and result imports. For the next task extract from CURRENT source or explicitly preserve these changes.
- User authorized audio pipeline with `go`. Extracted from CURRENT application and recommendation service, preserving the completed results task.
- Pipeline task: created `audio_pipeline/pipeline.py`, `execution.py`, `uploads.py`, `summary.py`, `recommendations.py`, and `visualizations.py`. The pipeline is the sole external import interface, including legacy helper re-exports. Upload routes now dispatch to this interface. The old recommendation service preserves its public imports without owning generation logic.
- Kept subprocess analyzer execution and the existing numerical audio/recommendation engines. No audio algorithms, thresholds, response bodies, or cleanup ordering changed. AST comparison verified all 21 moved function/class definitions match their pre-extraction bodies and signatures.
- Pipeline verification: 258 tests passed after extraction, then 259 passed after adding the import-boundary regression check and using canonical core imports. Compileall and diff whitespace checks passed. Cold-import test confirms the pipeline does not import application or the legacy recommendation service; results still import without pipeline.
- Paused before Task 6 (admin, system/request logs, composition, final review). Wait for user `go`. Changes remain uncommitted.
- User authorized Task 6 with `go` and reiterated `continue` during review. Extracted admin user/log reads, existing admin data operations/reports/policy, admin data authorization, health checks, and request logging. All feature routes now call their owners without importing application backwards.
- `application.py` now contains 73 lines of composition/error handling. `legacy_exports.py` retains the old import surface; it contains imports/constants only. Request hooks are explicitly registered in their original order. The singleton Flask/WSGI/factory identity is preserved.
- Full suite after admin extraction: 260 passed. Final full suite after documentation and dependency-boundary regression checks: 261 passed. Compileall passed for karaok, audio_thresholds, settings_recommendations, audio_engine, app.py, and run.py. git diff --check passed.
- Final AST comparison against HEAD: 69 of the original 71 application definitions have unchanged bodies/signatures (request-hook registration moved outside their bodies). The two intentional splits are persist_audio_analysis and create_audio_upload. Admin service, report, and policy definitions are unchanged.
- Independent read-only reviewer was dispatched per the review skill but failed before producing findings due to agent usage limits. Completed local source/import/lifecycle/deployment-entry-point review instead; do not represent it as independent review. Live MySQL, SMTP, and deployed client smoke checks were not run.
- No merge, push, or commit performed. All implementation and documentation changes remain available in the working tree on refactor/backend-modularization. No further extraction tasks remain.
