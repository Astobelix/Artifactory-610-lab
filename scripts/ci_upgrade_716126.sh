#!/usr/bin/env bash
set -Eeuo pipefail

# Migration 6.x -> 7.x sur un CLONE du volume Derby, jamais sur la source.
TARGET="releases-docker.jfrog.io/jfrog/artifactory-oss:7.161.26"
HOME_LAB=/home/artifact/artifactory-lab
LOG=compose-lab-logs
UID_ARTIFACT="$(id -u artifact)"
mkdir -p "$LOG"
as_artifact() {
  (cd /home/artifact && sudo runuser -u artifact -- env -i \
    HOME=/home/artifact USER=artifact LOGNAME=artifact \
    PATH=/usr/local/bin:/usr/bin:/bin \
    XDG_CONFIG_HOME=/home/artifact/.config \
    XDG_DATA_HOME=/home/artifact/.local/share \
    XDG_RUNTIME_DIR="/run/user/$UID_ARTIFACT" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$UID_ARTIFACT/bus" "$@")
}

echo "Preflight image exacte : $TARGET"
df -h / | tee "$LOG/disk-before-7.txt"
free -h >"$LOG/memory-before-7.txt"
as_artifact podman pull "$TARGET" 2>&1 | tee "$LOG/pull-716126.log"
as_artifact podman image inspect "$TARGET" --format '{{.Id}}' >"$LOG/image-716126-id.txt"

echo 'Arret du service avant sauvegarde Derby 6.23.42'
as_artifact systemctl --user stop artifactory-lab.service
if as_artifact podman ps --format '{{.Names}}' | grep -q artifactory610; then
  echo 'Des conteneurs de la composition sont encore actifs' >&2
  exit 51
fi
sudo install -d -o artifact -g artifact -m 0700 "$HOME_LAB/backup"
ARCHIVE="$HOME_LAB/backup/source-62342-derby.tar"
as_artifact podman volume export artifactory62342_data --output "$ARCHIVE"
sudo test -s "$ARCHIVE"
sudo sha256sum "$ARCHIVE" | tee "$LOG/backup-62342.sha256"
sudo stat -c 'Taille sauvegarde 6.23.42 : %s octets' "$ARCHIVE"

echo 'Copie de la sauvegarde vers un nouveau volume 7.161.26'
as_artifact podman volume create artifactory716126_data
as_artifact podman volume import artifactory716126_data "$ARCHIVE"
as_artifact podman volume inspect artifactory62342_data >"$LOG/volume-62342-source.json"
as_artifact podman volume inspect artifactory716126_data >"$LOG/volume-716126-destination.json"

echo 'Adaptation de la composition et de Nginx dans le runner seulement'
sudo python3 - "$HOME_LAB/compose.yaml" "$HOME_LAB/nginx/default.conf" <<'PY'
from pathlib import Path
import sys
compose = Path(sys.argv[1])
nginx = Path(sys.argv[2])
c = compose.read_text(encoding='utf-8')
for old, new in (
    ('releases-docker.jfrog.io/jfrog/artifactory-oss:6.23.42',
     'releases-docker.jfrog.io/jfrog/artifactory-oss:7.161.26'),
    ('name: artifactory62342_data', 'name: artifactory716126_data'),
    ('EXTRA_JAVA_OPTIONS: "-Xms512m -Xmx2g"',
     'EXTRA_JAVA_OPTIONS: "-Xms512m -Xmx2g"\n      ENABLE_MIGRATION: "y"'),
):
    if c.count(old) != 1:
        raise SystemExit(f'Nombre inattendu de motifs dans compose : {old}')
    c = c.replace(old, new)
n = nginx.read_text(encoding='utf-8')
if n.count('proxy_pass http://artifactory:8081;') != 1:
    raise SystemExit('Port Nginx 6.x inattendu')
n = n.replace('proxy_pass http://artifactory:8081;',
              'proxy_pass http://artifactory:8082;')
n = n.replace('return 302 /artifactory/;', 'return 302 /ui/;')
# 7.x sert ses API sous /artifactory/ et son interface sous /ui/.
anchor = '    location /artifactory/ {'
if n.count(anchor) != 1:
    raise SystemExit('Localisation Artifactory absente')
n = n.replace(anchor, '''    location /ui/ {
        proxy_pass http://artifactory:8082;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

''' + anchor)
compose.write_text(c, encoding='utf-8')
nginx.write_text(n, encoding='utf-8')
PY

echo 'Premier demarrage court pour generer system.yaml, avant correction Derby'
as_artifact systemctl --user start artifactory-lab.service
sleep 15
as_artifact systemctl --user stop artifactory-lab.service
VOL="$(as_artifact podman volume inspect artifactory716126_data --format '{{.Mountpoint}}')"
CONFIG="$(sudo find "$VOL" -type f -path '*/etc/system.yaml' -print -quit)"
if [[ -z "$CONFIG" ]]; then
  echo 'system.yaml introuvable dans volume clone : diagnostic requis' >&2
  exit 52
fi
echo 'Configuration Derby historique: correction dans le volume clone'
sudo apt-get install -y -qq python3-yaml
sudo python3 scripts/patch_derby_716126.py "$CONFIG"
echo 'Demarrage avec migration explicite ENABLE_MIGRATION=y'
as_artifact systemctl --user start artifactory-lab.service
as_artifact systemctl --user is-active --quiet artifactory-lab.service
df -h / >"$LOG/disk-after-7.txt"
echo '7.161.26 lancee : attendre la migration des donnees et les services'
