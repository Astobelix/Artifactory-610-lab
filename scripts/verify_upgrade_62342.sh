#!/usr/bin/env bash
set -Eeuo pipefail
BASE=http://127.0.0.1:8080/artifactory
LOG=compose-lab-logs
mkdir -p "$LOG"
echo 'Attendre Artifactory apres migration Derby'
ready=false
for attempt in $(seq 1 120); do
  if curl -fsS --max-time 5 "$BASE/api/system/ping" >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 10
done
[[ "$ready" == true ]] || { echo 'ERREUR : API indisponible apres migration 6.23.42' >&2; exit 41; }
curl -fsS --max-time 30 -u admin:password "$BASE/api/system/version" -o "$LOG/version-62342.json"
python3 - "$LOG/version-62342.json" <<'PY'
import json,sys
with open(sys.argv[1],encoding="utf-8") as f:
    v=json.load(f)["version"]
print("Version apres migration :",v)
assert v == "6.23.42", f"Version inattendue: {v}"
PY
REPO="$(sed -n '1p' "$LOG/selected-repo.txt")"
KIND="$(sed -n '2p' "$LOG/selected-repo.txt")"
if [[ "$KIND" == maven ]]; then
  PATH_ARTIFACT=com/example/lab-persistence/1.0.0/lab-persistence-1.0.0.txt
else
  PATH_ARTIFACT=verification/artifact.txt
fi
curl -fsS --max-time 30 -u admin:password "$BASE/api/repositories" -o "$LOG/repositories-62342.json"
python3 - "$LOG/repositories-62342.json" "$REPO" <<'PY'
import json,sys
with open(sys.argv[1],encoding="utf-8") as f:
    repos=json.load(f)
assert any(r.get("key")==sys.argv[2] and r.get("type","").lower()=="local" for r in repos)
print("Depot preserve :",sys.argv[2])
PY
curl -fsS --max-time 30 -u admin:password "$BASE/$REPO/$PATH_ARTIFACT" -o "$LOG/artifact-62342.txt"
cmp "$LOG/artifact-source.txt" "$LOG/artifact-62342.txt"
sha256sum "$LOG/artifact-source.txt" "$LOG/artifact-62342.txt" >"$LOG/integrite-upgrade.sha256"
echo 'Test du second demarrage 6.23.42 via systemd'
uid="$(id -u artifact)"
(cd /home/artifact && sudo runuser -u artifact -- env -i HOME=/home/artifact USER=artifact LOGNAME=artifact \
 PATH=/usr/local/bin:/usr/bin:/bin XDG_CONFIG_HOME=/home/artifact/.config \
 XDG_DATA_HOME=/home/artifact/.local/share XDG_RUNTIME_DIR="/run/user/$uid" \
 DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
 systemctl --user restart artifactory-lab.service)
ready=false
for attempt in $(seq 1 120); do
  if curl -fsS --max-time 5 "$BASE/api/system/ping" >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 10
done
[[ "$ready" == true ]] || { echo 'ERREUR : API indisponible apres second demarrage' >&2; exit 42; }
curl -fsS -u admin:password "$BASE/$REPO/$PATH_ARTIFACT" -o "$LOG/artifact-after-restart.txt"
cmp "$LOG/artifact-source.txt" "$LOG/artifact-after-restart.txt"
echo 'SUCCES : migration 6.1.0 -> 6.23.42 Derby, depot et artefact conserves'
