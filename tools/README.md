# KaraOK tools

Run commands from the repository root in PowerShell.

| Command | Purpose |
| --- | --- |
| `./tools/run-dev.ps1` | Start the backend, local Admin Console, and Flutter; optionally pass `-DeviceId` |
| `./tools/build_karaok.ps1` | Build and package a signed Android APK or AAB; see [build guide](../build.md) |
| `./tools/run-affected-tests.ps1` | Select checks from tracked and untracked working-tree changes |
| `./tools/run-affected-tests.ps1 -All` | Run full backend and Flutter suites, Flutter analysis, and every `tools/tests/*.tests.ps1` suite |
| `./tools/run-affected-tests.ps1 -All -ListOnly` | Preview release test groups without running them |
| `./tools/run-settings-integration.ps1` | Run opt-in real-service settings integration using isolated database `karaok_settings_e2e` and port 5100 |
| `python tools/security/generate_secrets.py` | Print freshly generated database, JWT, and keystore secrets; store securely and do not capture in shared logs |

`lib/` contains shared PowerShell helpers for command resolution and build API
configuration. Dot-source these from commands and tests; they are not standalone
entry points. `tests/` contains self-contained PowerShell regression scripts.
Run an individual suite with `& ./tools/tests/build-karaok.tests.ps1`.

Install backend dependencies in `backend/.venv` and Flutter dependencies before
running checks. The full runner does not run the Admin Console suite; run
`composer test` from `admin/` separately. Real-service integration additionally
requires MySQL, a configured `karaok-e2e` login path, and a Flutter target; inspect
the integration script prerequisites before opting in with `-Integration`.

Backend-specific commands stay in `backend/scripts/`; audio artifact generators
stay in `backend/audio_thresholds/`. Ubuntu provisioning, HTTPS, and backup
utilities stay in `deploy/ovh/` beside their service configuration. See the
[deployment runbook](../deploy.md) before using server utilities.

Generated builds belong in ignored `dist/` and `frontend/build/`; local research
outputs belong in ignored `results/`, `docs/reports/`, or `tmp/`. Keep reusable
utilities here or with their owning component, rather than in temporary folders.
