# Deploy KaraOK to OVHcloud

This guide targets the following deployment:

- OVHcloud VPS
- Ubuntu 26.04
- Public IPv4: `139.99.89.112`
- SSH account: `ubuntu`
- Repository: `git@github.com:jbl2023-2879-91296-cpu/KaraOK.git`
- Application directory: `/opt/karaok/app`
- MySQL on the same VPS
- Public API: `https://139.99.89.112/api`

The production path is Nginx on ports 80/443, Gunicorn on loopback port 8000,
and MySQL on loopback port 3306. Only SSH, HTTP, and HTTPS are opened in UFW.

## 1. Connect and prepare GitHub SSH access

From the local Windows machine:

```powershell
ssh ubuntu@139.99.89.112
```

On the VPS, create a GitHub SSH key if this server does not already have one:

```bash
ssh-keygen -t ed25519 -C "karaok-ovh-deploy" -f ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub
```

Add the printed public key to the GitHub account's SSH keys or as a read-only
deploy key for the KaraOK repository. Never copy or share the private key. Test:

```bash
ssh -T git@github.com
```

GitHub may report successful authentication while noting that shell access is not
provided. That is expected.

## 2. Clone the repository

```bash
sudo mkdir -p /opt/karaok
sudo chown ubuntu:ubuntu /opt/karaok
git clone git@github.com:jbl2023-2879-91296-cpu/KaraOK.git /opt/karaok/app
cd /opt/karaok/app
```

The deployment scripts intentionally do not run automatically after cloning.
Review them before using `sudo`:

```bash
less deploy/ovh/prepare-server.sh
less deploy/ovh/enable-ip-https.sh
```

## 3. Prepare Ubuntu

Run the repository's preparation script:

```bash
cd /opt/karaok/app
sudo bash deploy/ovh/prepare-server.sh
```

It updates Ubuntu, installs MySQL, Nginx, UFW, Snap, Python tooling, and Git;
creates the `karaok` service account and persistent directories; creates the
Python virtual environment; installs dependencies; installs systemd templates;
enables the backup timer; applies the HTTP Nginx configuration; and opens only
OpenSSH plus Nginx in UFW.

Keep the SSH session open until a second SSH connection succeeds. OVHcloud also
provides recovery/KVM options if a firewall mistake blocks remote access.

## 4. Configure MySQL

Confirm MySQL listens locally. Ubuntu's default may show loopback, but it must not
listen publicly on `0.0.0.0:3306`:

```bash
sudo ss -lntp | grep 3306
sudo mysql_secure_installation
```

Import the schema once:

```bash
sudo mysql < /opt/karaok/app/database/schema.sql
```

Generate a database password containing only hexadecimal characters so it is easy
to use safely in SQL and environment files:

```bash
openssl rand -hex 24
```

Copy that value, open MySQL, and replace `PASTE_GENERATED_PASSWORD`:

```bash
sudo mysql
```

```sql
CREATE USER IF NOT EXISTS 'karaok_app'@'localhost'
IDENTIFIED BY 'PASTE_GENERATED_PASSWORD';

ALTER USER 'karaok_app'@'localhost'
IDENTIFIED BY 'PASTE_GENERATED_PASSWORD';

GRANT SELECT, INSERT, UPDATE, DELETE
ON karaok_db.* TO 'karaok_app'@'localhost';

FLUSH PRIVILEGES;
EXIT;
```

Do not use MySQL `root` in the Flask environment.

## 5. Create the production environment

Generate a separate JWT secret:

```bash
python3 -c 'import secrets; print(secrets.token_urlsafe(48))'
```

Create the ignored production file from the committed template:

```bash
sudo cp deploy/ovh/backend.env.example backend/.env
sudo nano backend/.env
```

Replace every `replace-with-...` value. Use the database password and JWT secret
generated above. For `SMTP_*`, copy the same provider values currently used in
the local ignored `backend/.env`; do not commit or paste those credentials into
GitHub, documentation, issues, or chat.

Secure the file and ensure persistent upload storage belongs to the API account:

```bash
sudo chown karaok:karaok backend/.env
sudo chmod 600 backend/.env
sudo chown -R karaok:karaok /var/lib/karaok/uploads
```

## 6. Start the API and test locally

```bash
sudo systemctl enable --now karaok-api
sudo systemctl enable --now karaok-backup.timer
sudo systemctl status karaok-api --no-pager
curl http://127.0.0.1:8000/api/health
```

Expected response:

```json
{"status":"ok","db":"connected"}
```

If it fails, inspect logs without printing `backend/.env`:

```bash
sudo journalctl -u karaok-api -n 100 --no-pager
sudo nginx -t
sudo systemctl status mysql nginx --no-pager
```

At this stage, test HTTP externally from the local computer:

```powershell
Invoke-RestMethod http://139.99.89.112/api/health
```

Do not build or distribute the mobile application with this HTTP URL.

## 7. Request the IP certificate

Let's Encrypt IP certificates require Certbot 5.4 or newer and are valid for only
about six days, so automated renewal is mandatory. First run a staging request:

```bash
cd /opt/karaok/app
sudo bash deploy/ovh/enable-ip-https.sh --staging
```

Enter a real email address for expiry and account notices. After staging succeeds,
request the publicly trusted certificate:

```bash
sudo bash deploy/ovh/enable-ip-https.sh
```

The script installs the HTTPS Nginx configuration, adds an Nginx reload renewal
hook, and enables Certbot's renewal timer. Verify everything:

```bash
curl https://139.99.89.112/api/health
sudo certbot certificates
systemctl list-timers | grep certbot
sudo certbot renew --dry-run
```

The public health endpoint must return HTTP 200 before building the APK.

## 8. Verify security boundaries

```bash
sudo ufw status verbose
sudo ss -lntp
```

Expected public listeners are SSH 22, HTTP 80, and HTTPS 443. Gunicorn 8000 and
MySQL 3306 must listen only on `127.0.0.1` or the local socket. Do not expose either
port through the OVHcloud network firewall.

## 9. Build the Android client

On the local Windows development machine:

```powershell
cd frontend
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build apk --release --dart-define=API_BASE_URL=https://139.99.89.112/api
Get-Item build\app\outputs\flutter-apk\app-release.apk
```

The release Android configuration currently uses the debug signing key. Configure
a private Android release keystore before production distribution.

## 10. Updates and rollback preparation

Before updating, take an OVH snapshot and a KaraOK backup. A snapshot is not a
replacement for off-server backups.

```bash
sudo systemctl start karaok-backup.service
sudo systemctl status karaok-backup.service --no-pager
sudo ls -la /var/backups/karaok
```

Deploy a new committed revision:

```bash
cd /opt/karaok/app
git status --short
git pull --ff-only
backend/.venv/bin/python -m pip install -r backend/requirements.txt
backend/.venv/bin/python -m unittest discover -s backend/tests -v
sudo systemctl restart karaok-api
curl https://139.99.89.112/api/health
```

Copy database and upload backups to an encrypted off-server destination. Backups
stored only on the same VPS do not protect against VPS loss or account compromise.
