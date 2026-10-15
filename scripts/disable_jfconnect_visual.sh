#!/usr/bin/env bash
set -Eeuo pipefail
uid="$(id -u artifact)"
as_artifact() {
  (cd /home/artifact && sudo runuser -u artifact -- env -i HOME=/home/artifact USER=artifact LOGNAME=artifact PATH=/usr/local/bin:/usr/bin:/bin XDG_CONFIG_HOME=/home/artifact/.config XDG_DATA_HOME=/home/artifact/.local/share XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" "$@")
}
as_artifact systemctl --user stop artifactory-lab.service
mount="$(as_artifact podman volume inspect artifactory716126_data --format '{{.Mountpoint}}')"
config="$(sudo find "$mount" -type f -path '*/etc/system.yaml' -print -quit)"
[[ -n "$config" ]] || { echo 'system.yaml absent'; exit 81; }
sudo python3 scripts/patch_jfconnect_visual.py "$config"
as_artifact systemctl --user start artifactory-lab.service
as_artifact systemctl --user is-active --quiet artifactory-lab.service
for i in $(seq 1 100); do
  if curl -fsS --max-time 7 -u admin:password http://127.0.0.1:8080/artifactory/api/system/version -o compose-lab-logs/version-7-jfconnect.json 2>/dev/null; then
    python3 - <<'PY'
import json
assert json.load(open("compose-lab-logs/version-7-jfconnect.json"))["version"]=="7.161.26"
PY
    echo 'API de Artifactory 7 fonctionnelle'
    exit 0
  fi
  sleep 10
done
echo 'Echec API apres configuration JFConnect'
exit 82
