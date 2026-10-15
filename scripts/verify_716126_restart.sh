#!/usr/bin/env bash
set -Eeuo pipefail

BASE=http://127.0.0.1:8080/artifactory
LOG=compose-lab-logs
uid="$(id -u artifact)"
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

wait_api() {
  local name="$1" ok=0
  for i in $(seq 1 90); do
    if curl --fail --silent --show-error --max-time 6 -u admin:password \
      "$BASE/api/system/version" -o "$LOG/version-$name.json" 2>/dev/null &&
       python3 - "$LOG/version-$name.json" <<'PY'
import json,sys
with open(sys.argv[1],encoding="utf-8") as f: ver=json.load(f)["version"]
print("Artifactory version:",ver)
assert ver=="7.161.26"
PY
    then
      ok=1
      break
    fi
    sleep 10
  done
  [[ "$ok" == 1 ]] || { echo "ECHEC: API 7.161.26 indisponible: $name" >&2; return 1; }
}

REPO="$(sed -n '1p' "$LOG/selected-repo.txt")"
KIND="$(sed -n '2p' "$LOG/selected-repo.txt")"
if [[ "$KIND" == maven ]]; then
  EXISTING=com/example/lab-persistence/1.0.0/lab-persistence-1.0.0.txt
  NEW=com/example/lab-persistence/2.0.0/lab-persistence-2.0.0.txt
else
  EXISTING=verification/artifact.txt
  NEW=verification/artifact-written-on-7.txt
fi
printf 'Artifactory 7.161.26 - ecriture nouvelle et persistance apres redemarrage\n' \
  >"$LOG/artifact-new-on-7-source.txt"

echo "Ecriture d un nouvel artefact sur Artifactory 7 : $REPO/$NEW"
curl --fail-with-body --silent --show-error --max-time 60 -u admin:password -X PUT \
  --data-binary @"$LOG/artifact-new-on-7-source.txt" "$BASE/$REPO/$NEW" \
  -o "$LOG/upload-new-on-7.json"
curl --fail --silent --show-error --max-time 30 -u admin:password \
  "$BASE/$REPO/$NEW" -o "$LOG/artifact-new-on-7-before.txt"
cmp "$LOG/artifact-new-on-7-source.txt" "$LOG/artifact-new-on-7-before.txt"

echo 'Redemarrer l ensemble Artifactory 7 + Nginx avec systemd utilisateur'
as_artifact systemctl --user restart artifactory-lab.service
as_artifact systemctl --user is-active --quiet artifactory-lab.service
wait_api after-restart-7

echo 'Verifier le depot et les deux artefacts apres redemarrage'
curl -fsS --max-time 30 -u admin:password "$BASE/api/repositories" \
  -o "$LOG/repositories-716126-after-restart.json"
python3 - "$LOG/repositories-716126-after-restart.json" "$REPO" <<'PY'
import json,sys
with open(sys.argv[1],encoding="utf-8") as f: repos=json.load(f)
assert any(r.get("key")==sys.argv[2] and r.get("type","").lower()=="local" for r in repos)
print("Depot conserve apres redemarrage :",sys.argv[2])
PY

curl -fsS --max-time 30 -u admin:password "$BASE/$REPO/$EXISTING" \
  -o "$LOG/artifact-old-on-7-after-restart.txt"
curl -fsS --max-time 30 -u admin:password "$BASE/$REPO/$NEW" \
  -o "$LOG/artifact-new-on-7-after-restart.txt"
cmp "$LOG/artifact-source.txt" "$LOG/artifact-old-on-7-after-restart.txt"
cmp "$LOG/artifact-new-on-7-source.txt" "$LOG/artifact-new-on-7-after-restart.txt"
sha256sum "$LOG/artifact-source.txt" "$LOG/artifact-old-on-7-after-restart.txt" \
  "$LOG/artifact-new-on-7-source.txt" "$LOG/artifact-new-on-7-after-restart.txt" \
  >"$LOG/checksums-after-restart-7.txt"

as_artifact podman volume inspect artifactory716126_data >"$LOG/volume-7-after-restart.json"
as_artifact podman ps -a >"$LOG/containers-7-after-restart.txt"
if curl --silent --max-time 3 http://127.0.0.1:8081/artifactory/api/system/ping >/dev/null; then
  echo 'ECHEC: exposition du port Artifactory 8081 non prevue' >&2
  exit 75
fi

echo 'SUCCES: 7.161.26 Derby, ecriture, lecture, redemarrage systemd, deux artefacts intacts.'
