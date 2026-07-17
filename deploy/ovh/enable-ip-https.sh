#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "Run this script with sudo." >&2
    exit 1
fi

public_ip=139.99.89.112
app_root=/opt/karaok/app
webroot=/var/www/certbot

if ! command -v certbot >/dev/null 2>&1; then
    snap install core
    snap refresh core
    snap install --classic certbot
    ln -sfn /snap/bin/certbot /usr/local/bin/certbot
fi

echo "Installed $(certbot --version). Certbot 5.4 or newer is required for webroot IP certificates."

if [[ -z ${CERTBOT_EMAIL:-} ]]; then
    read -r -p "Let's Encrypt account email: " CERTBOT_EMAIL
fi
if [[ -z $CERTBOT_EMAIL ]]; then
    echo "A Let's Encrypt account email is required." >&2
    exit 1
fi

if [[ ${1:-} == "--staging" ]]; then
    staging=(--staging)
else
    staging=()
fi

certbot certonly \
    "${staging[@]}" \
    --non-interactive \
    --agree-tos \
    --email "$CERTBOT_EMAIL" \
    --preferred-profile shortlived \
    --webroot \
    --webroot-path "$webroot" \
    --ip-address "$public_ip"

if [[ ${1:-} == "--staging" ]]; then
    certbot delete --non-interactive --cert-name "$public_ip"
    echo "Staging certificate request succeeded and its test certificate was removed."
    echo "Run this script again without --staging."
    exit 0
fi

install -o root -g root -m 0644 "$app_root/deploy/ovh/nginx-https.conf" /etc/nginx/sites-available/karaok-api
install -d -m 0755 /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh <<'EOF'
#!/usr/bin/env bash
set -e
nginx -t
systemctl reload nginx
EOF
chmod 0755 /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh

nginx -t
systemctl reload nginx
systemctl enable --now snap.certbot.renew.timer

echo "HTTPS enabled at https://$public_ip/api"
