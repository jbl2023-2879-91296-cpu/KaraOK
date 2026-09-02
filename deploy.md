# KaraOK Live Deployment Runbook

This runbook deploys the KaraOK backend from `main` to the live Ubuntu server,
rebuilds the MySQL schema when explicitly required, and verifies the API. Run
commands in order and stop immediately if a verification step fails.

## Live environment

- Server: `ubuntu@139.99.89.112`
- Repository: `/opt/karaok/app`
- Backend: `/opt/karaok/app/backend`
- Service: `karaok-api`
- Internal API: `http://127.0.0.1:8000/api`
- Public API: `https://139.99.89.112/api`
- Data Administration API: `https://139.99.89.112/api/admin/data`
- Local Admin Console: `http://127.0.0.1:8080` on the development computer
- Database: `karaok_db`
- Application service account: `karaok`
- Persistent uploads and reports: `/var/lib/karaok/uploads`
- Backups: `/var/backups/karaok`

## 1. Connect from PowerShell

Open PowerShell on the development computer:

```powershell
ssh ubuntu@139.99.89.112
```

All commands in the following sections run inside the Ubuntu SSH session.

## 2. Confirm the current server state

```bash
cd /opt/karaok/app

git status --short
git branch --show-current
git log -1 --oneline

sudo systemctl status karaok-api --no-pager --full
```

The branch must be `main`. `git status --short` must be empty. Stop if it shows unexpected live-server changes; do not reset, delete, or overwrite them.

## 3. Back up MySQL and uploaded reports

Always make a new backup before changing the database or application.

```bash
BACKUP_DIR="/var/backups/karaok/manual-$(date -u +%Y%m%dT%H%M%SZ)"

sudo install -d -m 0700 "$BACKUP_DIR"

sudo mysqldump \
  --single-transaction \
  --routines \
  --triggers \
  karaok_db \
  | gzip -9 \
  | sudo tee "$BACKUP_DIR/karaok_db.sql.gz" >/dev/null

sudo tar \
  -C /var/lib/karaok \
  -czf "$BACKUP_DIR/uploads.tar.gz" \
  uploads

sudo sh -c "cd '$BACKUP_DIR' && sha256sum karaok_db.sql.gz uploads.tar.gz > SHA256SUMS"
```

Verify both archives and their checksums:

```bash
sudo gzip -t "$BACKUP_DIR/karaok_db.sql.gz"
sudo tar -tzf "$BACKUP_DIR/uploads.tar.gz" >/dev/null
sudo sh -c "cd '$BACKUP_DIR' && sha256sum -c SHA256SUMS"
sudo ls -lah "$BACKUP_DIR"
```

Do not continue unless both checksum lines say `OK` and the directory contains:

- `karaok_db.sql.gz`
- `uploads.tar.gz`
- `SHA256SUMS`

Keep the value printed by this command for recovery:

```bash
echo "$BACKUP_DIR"
```

## 4. Pull the current `main` branch

```bash
cd /opt/karaok/app

git fetch origin
git pull --ff-only origin main

git status --short
git log -1 --oneline
```

The pull must fast-forward successfully and the final status must be empty.

## 5. Prepare the backend environment

```bash
cd /opt/karaok/app

test -x backend/.venv/bin/python || python3 -m venv backend/.venv

backend/.venv/bin/python -m pip install --upgrade pip
backend/.venv/bin/python -m pip install -r backend/requirements.txt
KARAOK_COMPILE_CACHE="$(sudo -u karaok mktemp -d /tmp/karaok-compile.XXXXXX)"
sudo -u karaok env PYTHONPYCACHEPREFIX="$KARAOK_COMPILE_CACHE" \
  backend/.venv/bin/python -m compileall backend/karaok backend/scripts
```

Do not expose `.env` to the `ubuntu` account. The service user must be able to read it:

```bash
cd /opt/karaok/app/backend

sudo -u karaok test -r .env
sudo -u karaok test -r audio_thresholds/good_audio_thresholds.json
```

These commands are silent when successful.

## 6. Prepare the runtime caches

Direct audio tests must use the same writable Numba and Matplotlib cache
location as the production analyzer. The `karaok` service user normally has no writable home cache.

```bash
cd /opt/karaok/app/backend

CACHE_ROOT=/var/lib/karaok/uploads/_analysis/_runtime_cache

sudo install -d \
  -o karaok \
  -g karaok \
  -m 0750 \
  "$CACHE_ROOT/numba" \
  "$CACHE_ROOT/matplotlib" \
  "$CACHE_ROOT/xdg"

sudo -u karaok test -w "$CACHE_ROOT/numba"
sudo -u karaok test -w "$CACHE_ROOT/matplotlib"
sudo -u karaok test -w "$CACHE_ROOT/xdg"
```

Confirm that Librosa can initialize Numba with this cache:

```bash
sudo -u karaok env \
  NUMBA_CACHE_DIR="$CACHE_ROOT/numba" \
  MPLCONFIGDIR="$CACHE_ROOT/matplotlib" \
  ./.venv/bin/python -c "import librosa; from librosa.core import notation; print('Librosa and Numba cache: OK')"
```

Expected output:

```text
Librosa and Numba cache: OK
```

## 7. Run the correct live-server test suite

The live server intentionally does not contain the private
`results/results.csv` threshold-derivation dataset. Run the 58 deployment tests
below. The complete 66-test suite, including the eight dataset derivation
tests, is run on the development computer.

```bash
cd /opt/karaok/app/backend

CACHE_ROOT=/var/lib/karaok/uploads/_analysis/_runtime_cache

sudo -u karaok env \
  PYTHONDONTWRITEBYTECODE=1 \
  NUMBA_CACHE_DIR="$CACHE_ROOT/numba" \
  MPLCONFIGDIR="$CACHE_ROOT/matplotlib" \
  XDG_CACHE_HOME="$CACHE_ROOT/xdg" \
  ./.venv/bin/python -m unittest \
  tests.test_admin_data_api \
  tests.test_audio_analyzer_safety \
  tests.test_audio_pipeline \
  tests.test_audio_validation \
  tests.test_modular_structure \
  tests.test_security \
  -v
```

Expected final result:

```text
Ran 58 tests

OK
```

Do not rebuild the database or restart the API if any test fails.

## 8. Configure the Data Administration API

The administration system uses three independent credentials:

- Password A signs in to the local Admin Console.
- Password B belongs to the server-only MySQL identity `karaok_admin_api`.
- Raw API Key C stays in local `admin/.env`; only its SHA-256 hash belongs in
  live `backend/.env`.

Create `karaok_admin_api` for the actual loopback host used by MySQL. Grant
`SELECT` and `SHOW VIEW` on `karaok_db`, then grant only the table/column writes
implemented in `backend/karaok/modules/admin_data/policy.py`. Never grant
`CREATE`, `ALTER`, `DROP`, `FILE`, `GRANT OPTION`, or global privileges.

The protected live environment must contain:

```dotenv
ADMIN_DATA_API_ENABLED=true
ADMIN_DATA_API_KEY_HASH=<SHA256_HASH_OF_API_KEY_C>
ADMIN_DATA_API_QUERY_TIMEOUT_MS=5000
ADMIN_DB_HOST=localhost
ADMIN_DB_PORT=3306
ADMIN_DB_NAME=karaok_db
ADMIN_DB_USER=karaok_admin_api
ADMIN_DB_PASSWORD=<PASSWORD_B>
```

Verify the configuration without printing secrets:

```bash
cd /opt/karaok/app/backend

sudo -u karaok ./.venv/bin/python -c "from karaok.config import ADMIN_DATA_API_ENABLED, ADMIN_DATA_API_KEY_HASH, ADMIN_DB_CONFIG; assert ADMIN_DATA_API_ENABLED; assert len(ADMIN_DATA_API_KEY_HASH) == 64; assert ADMIN_DB_CONFIG['user'] == 'karaok_admin_api'; assert ADMIN_DB_CONFIG['password']; print('Administration configuration: OK')"

sudo -u karaok ./.venv/bin/python -c "from karaok.infrastructure.database import get_admin_db; c=get_admin_db(); q=c.cursor(); q.execute('SELECT CURRENT_USER(), DATABASE()'); print(q.fetchone()); q.close(); c.close()"
```

The administration feature requires no MySQL schema rebuild.

## Adjusted amplifier settings rollout gate

The settings-recommendation module must remain disabled in production until its
staging evidence and final review pass. Confirm the safe default in the service
environment without printing secrets:

```bash
sudo -u karaok grep '^SETTINGS_RECOMMENDATIONS_ENABLED=false$' \
  /opt/karaok/app/backend/.env
```

The standalone settings migration has been consolidated into
`database/schema.sql`. For a fresh or disposable staging deployment, complete
and verify the backup in section 3, then use the fresh-database rebuild in
section 9. Do not import `schema.sql` over a populated database because it is a
bootstrap, not an in-place migration; an existing production database requires
a separately reviewed in-place schema change before this feature is enabled.

```bash
sudo mysql -D karaok_db -e "
SHOW TABLES LIKE 'amplifier_profile';
SHOW TABLES LIKE 'settings_recommendation';
"
```

Verify the deployed genre-profile artifact. Loading it recalculates and checks
its canonical content checksum:

```bash
cd /opt/karaok/app/backend

sudo -u karaok ./.venv/bin/python -c \
  "from audio_thresholds import load_genre_profiles; p=load_genre_profiles(); assert p.artifact_checksum == '125800de3f963adf02e20a8edb2a4a492f750ae7814a1ac3272ecfdf222e6ec2'; print(p.artifact_checksum)"
```

Review `docs/settings-profile-sources.md` for source attribution, licenses,
selection exclusions, enabled genres, and profile version. KaraOK recommends
five physical knob positions but never controls the amplifier.

In staging only, set `SETTINGS_RECOMMENDATIONS_ENABLED=true`, restart the API,
and require both health endpoints to return
`{"db":"connected","status":"ok"}`. Confirm that a settings-purpose upload
persists a five-target recommendation and that history reload returns the same
recommendation ID. Inspect audit logs for:

- `amplifier_profile_created`, `amplifier_profile_updated`, and
  `amplifier_profile_deleted`
- `audio_upload_analyzed` with `purpose=settings_suggestion`
- `settings_recommendation_applied`

Collect at least five songs for each enabled genre, covering low, neutral, and
high starting positions. Use exactly these CSV columns:

```text
trial_id,genre,start_profile,before_score,after_score,clipping_violation
```

Run the deterministic release gate from the repository root:

```bash
./backend/.venv/bin/python backend/scripts/validate_settings_trials.py \
  results/settings-trials.csv \
  --output results/settings-trials-report.json

cat results/settings-trials-report.json
```

Do not enable production unless `passed` is `true`, clipping violations are
zero, every worsening or low-confidence trial has been reviewed, all automated
suites pass, and final code review approves the complete feature diff.

Rollback is configuration-only: set
`SETTINGS_RECOMMENDATIONS_ENABLED=false`, restart the API, and recheck both
health endpoints. This stops new generation and hides the settings endpoints;
it does not delete stored profiles, assessments, recommendations, or audits.
Never drop the additive tables as a routine rollback.

## 9. Rebuild the MySQL schema

> **Destructive operation:** This section permanently deletes all live users,
> sessions, assessments, settings, and database logs. Run it only when a full
> live schema replacement was explicitly approved and the backup above passed
> every verification.

Stop the API, remove the old database, and import the authoritative schema:

```bash
cd /opt/karaok/app

sudo systemctl stop karaok-api

sudo mysql -e "DROP DATABASE IF EXISTS karaok_db;"
sudo mysql < database/schema.sql
```

Verify the schema and seed data before restarting the API:

```bash
sudo mysql -D karaok_db -e "
SELECT COUNT(*) AS table_count
FROM information_schema.tables
WHERE table_schema = 'karaok_db';

SELECT COUNT(*) AS threshold_count
FROM audio_quality_threshold;

SELECT COUNT(*) AS preset_count
FROM genre_preset;
"
```

Expected values:

| Check                       | Expected |
| --------------------------- | -------: |
| `table_count`               |       12 |
| `threshold_count`           |        1 |
| `preset_count`              |        4 |

Confirm the non-secret database connection identity configured for the service:

```bash
cd /opt/karaok/app/backend

sudo -u karaok grep -E '^(DB_HOST|DB_PORT|DB_NAME|DB_USER)=' .env
```

Discover the actual MySQL host entry for that username instead of assuming it is registered under `127.0.0.1`:

```bash
sudo mysql -e "
SELECT User, Host, plugin
FROM mysql.user
WHERE User = 'karaok_app';
"
```

Use the exact `Host` returned by the query. For example, if it returns
`localhost`, inspect the grant with:

```bash
sudo mysql -e "SHOW GRANTS FOR 'karaok_app'@'localhost';"
```

If `.env` shows a different `DB_USER`, replace `karaok_app` with that username. If the discovery query returns no rows, stop and inspect the API's existing database configuration before creating or changing any MySQL account.

## 10. Restart and verify the API

```bash
sudo systemctl restart karaok-api

sudo systemctl status karaok-api --no-pager --full
```

The service must show `active (running)`. Check both internal and public health endpoints:

```bash
curl -fsS http://127.0.0.1:8000/api/health
echo

curl -fsS https://139.99.89.112/api/health
echo
```

Expected response from each endpoint:

```json
{ "db": "connected", "status": "ok" }
```

Confirm that the administration route exists and rejects unauthenticated
requests:

```bash
curl -sS -o /dev/null -w "HTTP %{http_code}\n" \
  https://139.99.89.112/api/admin/data/health
```

Expected output is `HTTP 401`. The authenticated check is performed from the
local Admin Console using raw API Key C.

Inspect recent service logs:

```bash
sudo journalctl -u karaok-api -n 100 --no-pager -o cat
```

Watch client requests and backend errors live:

```bash
sudo journalctl -u karaok-api -f -o cat
```

Press `Ctrl+C` to stop following the log.

## 11. Run the local Admin Console

No SSH tunnel is required. On the development computer, put the public API URL
and raw API Key C in ignored `admin/.env`, then run:

```powershell
cd "C:\Programming\Mobile Applications\Flutter\KaraOK\admin"
composer install
npm install
npm run css:build
composer test
composer serve
```

Open `http://127.0.0.1:8080/login`, sign in with local username `admin` and
Password A, then verify **API status**. Password B must never be stored locally.

## 12. Build the updated Android APK

Exit the SSH connection:

```bash
exit
```

Then run these commands in PowerShell on the development computer:

```powershell
cd "C:\Programming\Mobile Applications\Flutter\KaraOK\frontend"

flutter pub get
flutter analyze --no-pub
flutter test --no-pub

flutter build apk --release `
  --dart-define=API_BASE_URL=https://139.99.89.112/api

Get-FileHash `
  ".\build\app\outputs\flutter-apk\app-release.apk" `
  -Algorithm SHA256
```

The release APK is created at:

```text
frontend\build\app\outputs\flutter-apk\app-release.apk
```

Installing the backend does not update Android clients. Users must install the
new APK to receive the new mobile behavior.

## Troubleshooting

### `.env` permission denied

Cause: tests were run as `ubuntu`, but production secrets are intentionally
restricted to the `karaok` service account.

Resolution: run backend imports and tests through `sudo -u karaok`. Do not make
`.env` world-readable and do not copy its contents into the shell history.

### `results/results.csv` does not exist

Cause: the private threshold-derivation dataset is intentionally absent from
the live Git checkout.

Resolution: run the 58-test deployment suite in section 7. Do not upload the
private dataset merely to run production deployment tests.

### `cannot cache function ... no locator available`

Cause: Numba attempted to use an unavailable default cache for the service
account.

Resolution: create the service-owned runtime directories and pass
`NUMBA_CACHE_DIR` and `MPLCONFIGDIR` exactly as shown in sections 6 and 7. Do
not disable JIT, because production audio processing uses it.

### Health check fails after restart

```bash
sudo systemctl status karaok-api --no-pager --full
sudo journalctl -u karaok-api -n 200 --no-pager -o cat
sudo systemctl status mysql --no-pager --full
sudo nginx -t
sudo systemctl status nginx --no-pager --full
```

Do not repeatedly rebuild the database while diagnosing an API startup error.
The first verified backup remains the recovery point.

## Recovery note

The database backup created in section 3 is compressed SQL. Record its exact
directory before making destructive changes. Restoring a live database is also
destructive and should be performed only after stopping `karaok-api` and
confirming the exact backup path. Never restore from an unverified archive.
