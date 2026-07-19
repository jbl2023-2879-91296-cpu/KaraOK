#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "Run this script with sudo." >&2
    exit 1
fi

app_root=/opt/karaok/app
deploy_root="$app_root/deploy/ovh"

if [[ ! -f "$app_root/backend/app.py" || ! -d "$deploy_root" ]]; then
    echo "Expected the repository at $app_root." >&2
    exit 1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ffmpeg git libsndfile1 mysql-server nginx ufw snapd python3 python3-venv python3-pip

if ! id karaok >/dev/null 2>&1; then
    useradd --system --user-group --home-dir /opt/karaok --shell /usr/sbin/nologin karaok
fi

install -d -o karaok -g karaok -m 0750 /var/lib/karaok/uploads
install -d -o root -g root -m 0700 /var/backups/karaok
install -d -o www-data -g www-data -m 0755 /var/www/certbot/.well-known/acme-challenge

python3 -m venv "$app_root/backend/.venv"
"$app_root/backend/.venv/bin/python" -m pip install --upgrade pip
"$app_root/backend/.venv/bin/python" -m pip install -r "$app_root/backend/requirements.txt"
chown -R ubuntu:karaok "$app_root/backend/.venv"

install -o root -g root -m 0644 "$deploy_root/karaok-api.service" /etc/systemd/system/karaok-api.service
install -o root -g root -m 0644 "$deploy_root/karaok-backup.service" /etc/systemd/system/karaok-backup.service
install -o root -g root -m 0644 "$deploy_root/karaok-backup.timer" /etc/systemd/system/karaok-backup.timer
install -o root -g root -m 0750 "$deploy_root/backup.sh" /usr/local/sbin/karaok-backup
install -o root -g root -m 0644 "$deploy_root/nginx-http.conf" /etc/nginx/sites-available/karaok-api
rm -f /etc/nginx/sites-enabled/default
ln -sfn /etc/nginx/sites-available/karaok-api /etc/nginx/sites-enabled/karaok-api

ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

systemctl daemon-reload
systemctl enable mysql nginx karaok-backup.timer
nginx -t
systemctl restart nginx

echo
echo "Base server preparation completed."
echo "Next: configure MySQL and create $app_root/backend/.env before starting karaok-api and the backup timer."
