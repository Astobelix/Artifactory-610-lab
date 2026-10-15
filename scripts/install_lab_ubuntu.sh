#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'Ce script doit etre execute avec sudo' >&2; exit 1; }
SRC="${LAB_SOURCE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends podman podman-compose uidmap slirp4netns fuse-overlayfs dbus-user-session curl
if ! id artifact >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash artifact
fi
grep -q '^artifact:' /etc/subuid || { echo 'subuid manquant' >&2; exit 2; }
grep -q '^artifact:' /etc/subgid || { echo 'subgid manquant' >&2; exit 2; }
install -d -o artifact -g artifact -m 0755 /home/artifact/artifactory-lab /home/artifact/artifactory-lab/nginx
install -d -o artifact -g artifact -m 0755 /home/artifact/.config/systemd/user
install -o artifact -g artifact -m 0644 "$SRC/compose/compose.yaml" /home/artifact/artifactory-lab/compose.yaml
install -o artifact -g artifact -m 0644 "$SRC/compose/nginx/default.conf" /home/artifact/artifactory-lab/nginx/default.conf
install -o artifact -g artifact -m 0644 "$SRC/systemd/artifactory-lab.service" /home/artifact/.config/systemd/user/artifactory-lab.service
loginctl enable-linger artifact
uid="$(id -u artifact)"
# GitHub Actions transmet parfois les variables du runner au gestionnaire systemd utilisateur.
# Imposer les chemins du compte artifact AVANT de lancer son user manager.
install -d -m 0755 "/etc/systemd/system/user@$uid.service.d"
cat >"/etc/systemd/system/user@$uid.service.d/10-artifact-environment.conf" <<EOF
[Service]
Environment=HOME=/home/artifact
Environment=XDG_CONFIG_HOME=/home/artifact/.config
Environment=XDG_DATA_HOME=/home/artifact/.local/share
Environment=XDG_RUNTIME_DIR=/run/user/$uid
EOF
systemctl daemon-reload
systemctl start "user@$uid.service"
for i in $(seq 1 30); do [[ -S "/run/user/$uid/bus" ]] && break; sleep 1; done
[[ -S "/run/user/$uid/bus" ]] || { echo 'Bus systemd utilisateur indisponible' >&2; exit 3; }
as_artifact() {
  (cd /home/artifact && runuser -u artifact -- env -i HOME=/home/artifact USER=artifact LOGNAME=artifact PATH=/usr/local/bin:/usr/bin:/bin XDG_CONFIG_HOME=/home/artifact/.config XDG_DATA_HOME=/home/artifact/.local/share XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" "$@")
}
[[ "$(as_artifact podman info --format '{{.Host.Security.Rootless}}')" == true ]] || exit 4
as_artifact systemctl --user daemon-reload
as_artifact systemctl --user enable artifactory-lab.service
as_artifact systemctl --user start artifactory-lab.service
as_artifact systemctl --user is-active --quiet artifactory-lab.service
echo 'Service rootless artifact actif et active pour le demarrage.'
