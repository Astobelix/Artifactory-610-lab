#!/usr/bin/env bash
set -Eeuo pipefail
BASE=http://127.0.0.1:8080/artifactory
LOG=compose-lab-logs
mkdir -p "$LOG"
printf 'Test de persistance applicative sous Artifactory OSS 6.1.0\n' >"$LOG/artifact-source.txt"

echo 'Lister les depots locaux disponibles dans Artifactory OSS'
curl -fsS -u admin:password "$BASE/api/repositories" -o "$LOG/repositories-before.json"
python3 - "$LOG/repositories-before.json" "$LOG/selected-repo.txt" <<'PY'
import json, sys
from pathlib import Path
repos = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if not isinstance(repos, list):
    raise SystemExit("Reponse de liste des depots inattendue")
local = [r for r in repos if str(r.get("type", r.get("rclass", ""))).lower() == "local"]
local.sort(key=lambda r: (str(r.get("packageType", "")).lower() != "generic", r.get("key", "")))
print("Depots locaux utilisables :", [(r.get("key"), r.get("packageType")) for r in local])
if not local:
    raise SystemExit("Aucun depot local existant dans la reponse de l API")
chosen = local[0]
key = chosen["key"]
kind = str(chosen.get("packageType") or "generic").lower()
if not key or not all(c.isalnum() or c in "-_" for c in key):
    raise SystemExit("Cle de depot non conforme")
Path(sys.argv[2]).write_text(key + "\n" + kind + "\n", encoding="utf-8")
print("Depot de validation selectionne :", key)
PY
REPO="$(sed -n '1p' "$LOG/selected-repo.txt")"
KIND="$(sed -n '2p' "$LOG/selected-repo.txt")"
if [[ "$KIND" == maven ]]; then
  ARTIFACT_PATH=com/example/lab-persistence/1.0.0/lab-persistence-1.0.0.txt
else
  ARTIFACT_PATH=verification/artifact.txt
fi

echo "Publier puis recuperer un artefact dans $REPO via Nginx"
curl --fail-with-body -sS -u admin:password -X PUT \
  --data-binary @"$LOG/artifact-source.txt" "$BASE/$REPO/$ARTIFACT_PATH" \
  -o "$LOG/upload-response.json" || { cat "$LOG/upload-response.json"; exit 21; }
curl -fsS -u admin:password "$BASE/$REPO/$ARTIFACT_PATH" -o "$LOG/before.txt"
cmp "$LOG/artifact-source.txt" "$LOG/before.txt"

echo 'Redemarrer la composition avec le test systemd existant'
bash scripts/test_lab_ubuntu.sh

echo 'Valider la persistance apres redemarrage'
curl -fsS -u admin:password "$BASE/api/repositories" -o "$LOG/repositories-after.json"
python3 - "$LOG/repositories-after.json" "$REPO" <<'PY'
import json, sys
from pathlib import Path
repos = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert any(r.get("key") == sys.argv[2] and str(r.get("type", r.get("rclass", ""))).lower() == "local" for r in repos)
print("Depot local conserve :", sys.argv[2])
PY
curl -fsS -u admin:password "$BASE/$REPO/$ARTIFACT_PATH" -o "$LOG/after.txt"
cmp "$LOG/artifact-source.txt" "$LOG/after.txt"
sha256sum "$LOG/artifact-source.txt" "$LOG/after.txt" >"$LOG/checksums.txt"
echo 'SUCCES : artefact reel conserve dans un depot OSS apres restart systemd'
