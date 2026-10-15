#!/usr/bin/env bash
set -Eeuo pipefail
BASE=http://127.0.0.1:8080/artifactory
REPO=lab-persistence-local
LOG=compose-lab-logs
mkdir -p "$LOG"
printf 'Donnees de recette Artifactory 6.1.0\n' >"$LOG/artifact-source.txt"
printf '{"key":"%s","rclass":"local","packageType":"generic"}\n' "$REPO" >"$LOG/repo.json"

echo 'Creation du depot local generique via Nginx'
curl -fsS -u admin:password -X PUT -H 'Content-Type: application/json' \
  --data-binary @"$LOG/repo.json" "$BASE/api/repositories/$REPO" -o "$LOG/repo-create.txt"

echo 'Depot et recuperation d un artefact via Nginx'
curl -fsS -u admin:password -X PUT --data-binary @"$LOG/artifact-source.txt" \
  "$BASE/$REPO/verification/artifact.txt" -o "$LOG/upload.json"
curl -fsS -u admin:password "$BASE/$REPO/verification/artifact.txt" -o "$LOG/before.txt"
cmp "$LOG/artifact-source.txt" "$LOG/before.txt"

echo 'Redemarrage de la composition via le test systemd existant'
bash scripts/test_lab_ubuntu.sh

echo 'Verification apres redemarrage du depot et du contenu'
curl -fsS -u admin:password "$BASE/api/repositories/$REPO" -o "$LOG/repo-after.json"
curl -fsS -u admin:password "$BASE/$REPO/verification/artifact.txt" -o "$LOG/after.txt"
cmp "$LOG/artifact-source.txt" "$LOG/after.txt"
python3 - "$LOG/repo-after.json" "$REPO" <<'PY'
import json,sys
with open(sys.argv[1],encoding='utf8') as f:
    d=json.load(f)
assert d.get('key')==sys.argv[2] and d.get('rclass')=='local'
print('Depot conserve:',d['key'])
PY
sha256sum "$LOG/artifact-source.txt" "$LOG/after.txt" >"$LOG/checksums.txt"
echo 'SUCCES : depot et artefact reels conserves apres restart systemd'
