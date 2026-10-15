#!/usr/bin/env bash
set -Eeuo pipefail
IMAGE=releases-docker.jfrog.io/jfrog/artifactory-oss:6.1.0
NAME=artifactory-610-podman
VOL=artifactory-610-podman-data
LOGS="${GITHUB_WORKSPACE:-$PWD}/podman-lab-logs"
mkdir -p "$LOGS"
finish() {
  code=$?
  podman logs "$NAME" >"$LOGS/container.log" 2>&1 || true
  podman rm -f "$NAME" >/dev/null 2>&1 || true
  podman volume rm "$VOL" >/dev/null 2>&1 || true
  exit "$code"
}
trap finish EXIT
podman --version | tee "$LOGS/podman-version.txt"
test "$(podman info --format '{{.Host.Security.Rootless}}')" = true
podman pull "$IMAGE" 2>&1 | tee "$LOGS/pull.log"
podman volume create "$VOL"
start() {
  podman run -d --name "$NAME" -p 127.0.0.1:8081:8081 \
    -v "$VOL:/var/opt/jfrog/artifactory" \
    -e EXTRA_JAVA_OPTIONS="-Xms512m -Xmx2g" "$IMAGE"
}
ready() {
  for attempt in $(seq 1 60); do
    if curl -fsS -m 5 http://127.0.0.1:8081/artifactory/api/system/ping; then return 0; fi
    test "$(podman inspect -f '{{.State.Running}}' "$NAME")" = true
    sleep 10
  done
  return 1
}
version() {
  curl -fsS -u admin:password http://127.0.0.1:8081/artifactory/api/system/version |
    tee "$LOGS/version-$1.json" |
    python3 -c 'import json,sys; v=json.load(sys.stdin)["version"]; print("Version:",v); assert v=="6.1.0"'
}
start
ready
version first
podman run --rm --network=none -v "$VOL:/data" docker.io/library/busybox:1.36 \
  sh -c 'echo persisted >/data/.lab-marker'
podman rm -f "$NAME"
start
ready
version second
podman run --rm --network=none -v "$VOL:/data" docker.io/library/busybox:1.36 \
  sh -c 'grep -qx persisted /data/.lab-marker'
echo "Artifactory 6.1.0 avec Podman rootless : tests reussis"
