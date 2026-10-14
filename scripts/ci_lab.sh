#!/usr/bin/env bash
set -Eeuo pipefail

: "${ARTIFACTORY_IMAGE:=releases-docker.jfrog.io/jfrog/artifactory-oss:6.1.0}"
: "${ARTIFACTORY_EXPECTED_VERSION:=6.1.0}"
: "${ARTIFACTORY_STARTUP_TIMEOUT:=900}"
: "${LAB_LOG_DIR:=$PWD/lab-logs}"

CONTAINER=artifactory-610-lab
VOLUME=artifactory-610-lab-data
PING_URL=http://127.0.0.1:8081/artifactory/api/system/ping
VERSION_URL=http://127.0.0.1:8081/artifactory/api/system/version
mkdir -p "$LAB_LOG_DIR"

cleanup() {
  local code=$?
  trap - EXIT
  if docker container inspect "$CONTAINER" >/dev/null 2>&1; then
    docker logs --timestamps "$CONTAINER" >"$LAB_LOG_DIR/artifactory-container.log" 2>&1 || true
    docker inspect "$CONTAINER" >"$LAB_LOG_DIR/artifactory-container-inspect.json" 2>/dev/null || true
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  fi
  docker volume rm "$VOLUME" >/dev/null 2>&1 || true
  printf 'Code de sortie : %s\n' "$code" | tee -a "$LAB_LOG_DIR/resultat.txt"
  exit "$code"
}
trap cleanup EXIT

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$LAB_LOG_DIR/resultat.txt"; }

wait_for_ping() {
  local deadline=$((SECONDS + ARTIFACTORY_STARTUP_TIMEOUT))
  while (( SECONDS < deadline )); do
    if curl -fsS --max-time 5 "$PING_URL" >"$LAB_LOG_DIR/ping-response.txt" 2>/dev/null; then
      log 'Ping HTTP : OK'
      return 0
    fi
    if [[ "$(docker inspect --format '{{.State.Running}}' "$CONTAINER" 2>/dev/null || true)" != 'true' ]]; then
      log 'ECHEC : conteneur arrete'
      return 1
    fi
    sleep 15
  done
  log "ECHEC : timeout de ${ARTIFACTORY_STARTUP_TIMEOUT}s"
  return 1
}

log "Image exacte demandee : $ARTIFACTORY_IMAGE"
uname -a | tee "$LAB_LOG_DIR/runner.txt"
docker version --format '{{.Server.Version}}' | tee "$LAB_LOG_DIR/docker-version.txt"

if ! docker pull "$ARTIFACTORY_IMAGE" >"$LAB_LOG_DIR/docker-pull.log" 2>&1; then
  log 'ECHEC : telechargement impossible ; voir docker-pull.log'
  exit 10
fi
log 'Image telechargee'
docker image inspect "$ARTIFACTORY_IMAGE" --format 'Id={{.Id}}; RepoDigests={{json .RepoDigests}}' | tee "$LAB_LOG_DIR/image-digest.txt"

docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker volume rm "$VOLUME" >/dev/null 2>&1 || true
docker volume create "$VOLUME" >/dev/null

start_container() {
  docker run -d --name "$CONTAINER" \
    --publish '127.0.0.1:8081:8081' \
    --memory 6g \
    --volume "$VOLUME:/var/opt/jfrog/artifactory" \
    --env 'EXTRA_JAVA_OPTIONS=-Xms512m -Xmx2g' \
    "$ARTIFACTORY_IMAGE" >/dev/null
}

log 'Demarrage conteneur, port local uniquement'
start_container
wait_for_ping

log 'Verification de la version'
if ! curl -fsS --max-time 20 -u 'admin:password' "$VERSION_URL" >"$LAB_LOG_DIR/version.json"; then
  log 'ECHEC : API version non disponible avec les identifiants de test'
  exit 20
fi
python3 - "$LAB_LOG_DIR/version.json" "$ARTIFACTORY_EXPECTED_VERSION" <<'PY'
import json, pathlib, sys
payload=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
actual=payload.get('version')
expected=sys.argv[2]
print(f'Version annoncee : {actual}; attendue : {expected}')
if actual != expected:
    raise SystemExit(f'ECHEC : version inattendue {actual!r}')
PY
log 'Version exacte OK'

log 'Test de persistance du volume'
docker run --rm --volume "$VOLUME:/data" busybox:1.36 sh -c 'printf "persistance-ok\n" > /data/.lab-marker'
docker rm -f "$CONTAINER" >/dev/null
start_container
wait_for_ping
docker run --rm --volume "$VOLUME:/data" busybox:1.36 sh -c 'test "$(cat /data/.lab-marker)" = persistance-ok'
log 'Persistance marqueur volume OK'
log 'SUCCES : Artifactory 6.1.0 demarre, API et volume testes'
