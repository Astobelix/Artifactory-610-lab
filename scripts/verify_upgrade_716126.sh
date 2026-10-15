#!/usr/bin/env bash
set -Eeuo pipefail
BASE=http://127.0.0.1:8080/artifactory
LOG=compose-lab-logs
mkdir -p "$LOG"
ready=false
for i in $(seq 1 120); do
  if curl -fsS --max-time 5 "$BASE/api/system/ping" >/dev/null 2>&1; then ready=true; break; fi
  sleep 10
done
[[ "$ready" == true ]] || { echo 'ERREUR : API 7 indisponible' >&2; exit 61; }
curl -fsS -u admin:password "$BASE/api/system/version" -o "$LOG/version-716126.json"
python3 - "$LOG/version-716126.json" <<'PY'
import json,sys
with open(sys.argv[1]) as f: v=json.load(f)['version']
print('Version apres migration majeure :',v)
assert v=='7.161.26'
PY
REPO="$(sed -n '1p' "$LOG/selected-repo.txt")"
KIND="$(sed -n '2p' "$LOG/selected-repo.txt")"
if [[ "$KIND" == maven ]]; then
  ARTIFACT_PATH=com/example/lab-persistence/1.0.0/lab-persistence-1.0.0.txt
else
  ARTIFACT_PATH=verification/artifact.txt
fi
curl -fsS -u admin:password "$BASE/api/repositories" -o "$LOG/repositories-716126.json"
python3 - "$LOG/repositories-716126.json" "$REPO" <<'PY'
import json,sys
with open(sys.argv[1]) as f: d=json.load(f)
assert any(x.get('key')==sys.argv[2] and x.get('type','').lower()=='local' for x in d)
print('Depot local preserve :',sys.argv[2])
PY
curl -fsS -u admin:password "$BASE/$REPO/$ARTIFACT_PATH" -o "$LOG/artifact-716126.txt"
cmp "$LOG/artifact-source.txt" "$LOG/artifact-716126.txt"
sha256sum "$LOG/artifact-source.txt" "$LOG/artifact-716126.txt" >"$LOG/checksums-716126.txt"
echo 'SUCCES : migration 6.23.42 -> 7.161.26 Derby, depot et artefact preserves'
