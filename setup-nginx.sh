#!/usr/bin/env bash
# Install nginx (from nginx.org) and certbot on Ubuntu, obtain a Let's Encrypt
# certificate for JENKINS_DOMAIN and configure nginx as an HTTPS reverse proxy
# for Jenkins on 127.0.0.1:8080.
#
# Usage: ./setup-nginx.sh            (reads .env next to this script)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
TEMPLATE="${SCRIPT_DIR}/nginx/jenkins.conf.template"
NGINX_CONF="/etc/nginx/conf.d/jenkins.conf"
WEBROOT="/var/www/certbot"
NGINX_KEY_FINGERPRINT="573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE. Create it with: cp .env.example .env" >&2
  exit 1
fi
set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

: "${JENKINS_DOMAIN:?set JENKINS_DOMAIN in .env}"
: "${LETSENCRYPT_EMAIL:?set LETSENCRYPT_EMAIL in .env}"

if [[ ! -f /etc/os-release ]] || ! grep -q '^ID=ubuntu' /etc/os-release; then
  echo "This script supports Ubuntu only." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Install nginx from the official nginx.org repository
# ---------------------------------------------------------------------------
echo "==> Installing prerequisites"
sudo apt-get update
sudo apt-get install -y curl gnupg2 ca-certificates lsb-release ubuntu-keyring gettext-base

echo "==> Importing nginx signing key"
curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor \
  | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null

if ! gpg --dry-run --quiet --no-keyring --import --import-options import-show \
    /usr/share/keyrings/nginx-archive-keyring.gpg | grep -q "$NGINX_KEY_FINGERPRINT"; then
  echo "nginx signing key fingerprint mismatch, aborting." >&2
  sudo rm -f /usr/share/keyrings/nginx-archive-keyring.gpg
  exit 1
fi

echo "==> Adding nginx stable repository"
echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/ubuntu $(lsb_release -cs) nginx" \
  | sudo tee /etc/apt/sources.list.d/nginx.list >/dev/null

printf "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" \
  | sudo tee /etc/apt/preferences.d/99nginx >/dev/null

echo "==> Installing nginx and certbot"
sudo apt-get update
sudo apt-get install -y nginx certbot

# The nginx.org package ships a default server on port 80; replace it with ours.
sudo rm -f /etc/nginx/conf.d/default.conf
sudo systemctl enable --now nginx

# ---------------------------------------------------------------------------
# Obtain the certificate (HTTP-only config first, so certbot can verify)
# ---------------------------------------------------------------------------
sudo mkdir -p "$WEBROOT"

if ! sudo test -f "/etc/letsencrypt/live/${JENKINS_DOMAIN}/fullchain.pem"; then
  echo "==> Requesting certificate for ${JENKINS_DOMAIN}"
  sudo tee "$NGINX_CONF" >/dev/null <<EOF
server {
  listen 80;
  server_name ${JENKINS_DOMAIN};

  location /.well-known/acme-challenge/ {
    root ${WEBROOT};
  }
}
EOF
  sudo nginx -t
  sudo systemctl reload nginx

  sudo certbot certonly --webroot -w "$WEBROOT" \
    -d "$JENKINS_DOMAIN" -m "$LETSENCRYPT_EMAIL" \
    --agree-tos --no-eff-email --non-interactive
else
  echo "==> Certificate for ${JENKINS_DOMAIN} already exists, skipping request"
fi

# Reload nginx whenever certbot's systemd timer renews the certificate.
sudo mkdir -p /etc/letsencrypt/renewal-hooks/deploy
sudo tee /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh >/dev/null <<'EOF'
#!/bin/sh
systemctl reload nginx
EOF
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh

# ---------------------------------------------------------------------------
# Install the full Jenkins reverse-proxy config
# ---------------------------------------------------------------------------
echo "==> Installing Jenkins nginx config"
# Only substitute JENKINS_DOMAIN so nginx variables like $host are kept.
# shellcheck disable=SC2016
envsubst '${JENKINS_DOMAIN}' < "$TEMPLATE" | sudo tee "$NGINX_CONF" >/dev/null
sudo nginx -t
sudo systemctl reload nginx

echo "==> Done. Jenkins is available at https://${JENKINS_DOMAIN}/"
echo "    Set Manage Jenkins -> System -> Jenkins URL to https://${JENKINS_DOMAIN}/"
