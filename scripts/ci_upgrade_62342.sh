#!/usr/bin/env bash
set -Eeuo pipefail
# Lab jetable uniquement : migrer une COPIE du volume Derby de 6.1.0.
uid="$(id -u artifact)"
TARGET=releases-docker.jfrog.io/jfrog/artifactory-oss:6.23.42
BASE=/home/artifact/artifactory-lab
LOG=compose-lab-logs
mkdir -p "$LOG"
as_artifact() {
  (cd /home/artifact && sudo runuser -u artifact -- env -i \
    HOME=/home/artifact USER=artifact LOGNAME=artifact \
    PATH=/usr/local/bin:/usr/bin:/bin \
    XDG_CONFIG_HOME=/home/artifact/.config \
    XDG_DATA_HOME=/home/artifact/.local/share \
    XDG_RUNTIME_DIR="/run/user/$uid" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" "$@")
}
echo "Preflight : image officielle $TARGET"
as_artifact podman pull "$TARGET" 2>&1 | tee "$LOG/pull-62342.log"
as_artifact podman image inspect "$TARGET" --format '{{.Id}}' >"$LOG/image-62342-id.txt"
df -h / >"$LOG/disk-before.txt"

echo 'Arreter proprement Derby 6.1.0 avant sauvegarde'
as_artifact systemctl --user stop artifactory-lab.service
if as_artifact podman ps --format '{{.Names}}' | grep -q artifactory610; then
  echo 'ERREUR : conteneurs toujours actifs, sauvegarde refusee' >&2
  exit 30
fi
sudo install -d -o artifact -g artifact -m 0700 "$BASE/backup"
ARCHIVE="$BASE/backup/source-610-derby.tar"
as_artifact podman volume export artifactory610_data --output "$ARCHIVE"
sudo test -s "$ARCHIVE"
sudo sha256sum "$ARCHIVE" | tee "$LOG/source-volume-backup.sha256"
sudo stat -c 'Backup: %s octets' "$ARCHIVE"

echo 'Restaurer le snapshot dans un second volume, sans toucher a la source'
as_artifact podman volume create artifactory62342_data
as_artifact podman volume import artifactory62342_data "$ARCHIVE"
as_artifact podman volume inspect artifactory610_data >"$LOG/source-volume.json"
as_artifact podman volume inspect artifactory62342_data >"$LOG/target-volume.json"

echo 'Modifier uniquement la copie locale de compose.yaml du runner'
sudo python3 - "$BASE/compose.yaml" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text(encoding='utf-8')
changes = {
    'releases-docker.jfrog.io/jfrog/artifactory-oss:6.1.0':
        'releases-docker.jfrog.io/jfrog/artifactory-oss:6.23.42',
    'name: artifactory610_data': 'name: artifactory62342_data',
}
for old, new in changes.items():
    if s.count(old) != 1:
        raise SystemExit(f'Attendu exactement une occurrence de {old!r}')
    s = s.replace(old, new)
p.write_text(s, encoding='utf-8')
PY
echo 'Demarrer la version 6.23.42 sur le volume copie'
as_artifact systemctl --user start artifactory-lab.service
as_artifact systemctl --user is-active --quiet artifactory-lab.service
df -h / >"$LOG/disk-after.txt"
echo 'Conteneurs lances : migration applicative et controle API a suivre'
