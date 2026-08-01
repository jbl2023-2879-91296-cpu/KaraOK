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
backend/.venv/bin/python -m compileall backend/karaok
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
  "$CACHE_ROOT/matplotlib"

sudo -u karaok test -w "$CACHE_ROOT/numba"
sudo -u karaok test -w "$CACHE_ROOT/matplotlib"
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
`results/results.csv` threshold-derivation dataset. Run the 48 deployment tests
below. The complete 56-test suite, including the eight dataset derivation
tests, is run on the development computer.

```bash
cd /opt/karaok/app/backend

CACHE_ROOT=/var/lib/karaok/uploads/_analysis/_runtime_cache

sudo -u karaok env \
  NUMBA_CACHE_DIR="$CACHE_ROOT/numba" \
  MPLCONFIGDIR="$CACHE_ROOT/matplotlib" \
  ./.venv/bin/python -m unittest \
  tests.test_audio_analyzer_safety \
  tests.test_audio_pipeline \
  tests.test_audio_validation \
  tests.test_modular_structure \
  tests.test_security \
  -v
```

Expected final result:

```text
Ran 48 tests

OK
```

Do not rebuild the database or restart the API if any test fails.

## 8. Rebuild the MySQL schema

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

## 9. Restart and verify the API

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

Inspect recent service logs:

```bash
sudo journalctl -u karaok-api -n 100 --no-pager -o cat
```

Watch client requests and backend errors live:

```bash
sudo journalctl -u karaok-api -f -o cat
```

Press `Ctrl+C` to stop following the log.

## 10. Build the updated Android APK

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

Resolution: run the 49-test deployment suite in section 7. Do not upload the
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
