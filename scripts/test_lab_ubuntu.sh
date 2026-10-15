#!/usr/bin/env bash
set -Eeuo pipefail
uid="$(id -u artifact)"
mkdir -p compose-lab-logs
as_artifact() {
  (cd /home/artifact && sudo runuser -u artifact -- env -i HOME=/home/artifact USER=artifact LOGNAME=artifact PATH=/usr/local/bin:/usr/bin:/bin XDG_CONFIG_HOME=/home/artifact/.config XDG_DATA_HOME=/home/artifact/.local/share XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" "$@")
}
check_api() {
  label="$1"
  deadline=$((SECONDS + 900))
  while ((SECONDS < deadline)); do
    if curl -fsS --max-time 5 http://127.0.0.1:8080/artifactory/api/system/ping >"compose-lab-logs/ping-$label.txt" 2>/dev/null; then
      break
    fi
    sleep 10
  done
  ((SECONDS < deadline)) || { echo 'Timeout API via Nginx' >&2; return 1; }
  curl -fsS --max-time 20 -u admin:password http://127.0.0.1:8080/artifactory/api/system/version >"compose-lab-logs/version-$label.json"
  python3 - "compose-lab-logs/version-$label.json" <<'PY'
import json,sys
with open(sys.argv[1],encoding='utf8') as f:
    version=json.load(f)['version']
print('Artifactory version:',version)
assert version=='6.1.0'
PY
}
[[ "$(loginctl show-user artifact -p Linger --value)" == yes ]]
as_artifact systemctl --user is-enabled artifactory-lab.service
as_artifact systemctl --user is-active artifactory-lab.service
check_api initial
as_artifact podman run --rm --network none -v artifactory610_data:/data docker.io/library/busybox:1.36 sh -c 'echo persisted >/data/.lab-marker'
as_artifact systemctl --user restart artifactory-lab.service
check_api restarted
as_artifact podman run --rm --network none -v artifactory610_data:/data docker.io/library/busybox:1.36 sh -c 'grep -qx persisted /data/.lab-marker'
as_artifact podman ps -a >compose-lab-logs/containers.txt
as_artifact podman volume inspect artifactory610_data >compose-lab-logs/volume.json
if curl --silent --max-time 2 http://127.0.0.1:8081/artifactory/api/system/ping >/dev/null; then
  echo 'Le port direct Artifactory 8081 ne devrait pas etre accessible.' >&2
  exit 5
fi
echo 'OK: compte artifact, nginx, artifactory 6.1.0, restart systemd, volume'
