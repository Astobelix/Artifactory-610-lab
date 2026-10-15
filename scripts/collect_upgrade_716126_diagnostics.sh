#!/usr/bin/env bash
set -Eeuo pipefail
# Diagnostic seulement : ne modifie aucun volume ni conteneur.
LOG=compose-lab-logs
mkdir -p "$LOG"
uid="$(id -u artifact)"
as_artifact() {
  (cd /home/artifact && sudo runuser -u artifact -- env -i \
    HOME=/home/artifact USER=artifact LOGNAME=artifact \
    PATH=/usr/local/bin:/usr/bin:/bin \
    XDG_CONFIG_HOME=/home/artifact/.config \
    XDG_DATA_HOME=/home/artifact/.local/share \
    XDG_RUNTIME_DIR="/run/user/$uid" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" "$@")
}
df -h / >"$LOG/disk-final.txt" 2>&1 || true
free -h >"$LOG/memory-final.txt" 2>&1 || true
as_artifact podman ps -a >"$LOG/podman-final.txt" 2>&1 || true
as_artifact podman stats -a --no-stream >"$LOG/podman-stats.txt" 2>&1 || true
as_artifact systemctl --user status artifactory-lab.service --no-pager >"$LOG/systemd-status.txt" 2>&1 || true
as_artifact journalctl --user -u artifactory-lab.service --no-pager -n 250 >"$LOG/systemd-artifactory-journal.txt" 2>&1 || true

while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  safe="$(printf '%s' "$name" | tr -cd '[:alnum:]_-')"
  as_artifact podman logs --timestamps --tail 350 "$name" >"$LOG/container-$safe.log" 2>&1 || true
  as_artifact podman inspect --format '{{.State.Status}} exit={{.State.ExitCode}} error={{.State.Error}}' "$name" \
    >"$LOG/container-$safe-state.txt" 2>&1 || true
done < <(as_artifact podman ps -a --format '{{.Names}}' 2>/dev/null || true)

VOL="$(as_artifact podman volume inspect artifactory716126_data --format '{{.Mountpoint}}' 2>/dev/null || true)"
if [[ -n "$VOL" && -d "$VOL" ]]; then
  sudo du -sh "$VOL" >"$LOG/volume-size.txt" 2>&1 || true
  sudo find "$VOL" -maxdepth 9 -type f \
    \( -name 'migration.log' -o -name 'console.log' -o -name 'artifactory.log' -o -name 'router-service.log' -o -name 'access-service.log' \) \
    -print >"$LOG/log-files-found.txt" 2>&1 || true
  count=0
  while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    count=$((count+1))
    [[ $count -le 8 ]] || break
    sudo tail -n 180 "$file" >"$LOG/volume-log-$count.txt" 2>&1 || true
    printf '%s = %s\n' "$count" "$file" >>"$LOG/log-file-index.txt"
  done <"$LOG/log-files-found.txt"
  sudo find "$VOL" -maxdepth 5 -type d -printf '%p\n' >"$LOG/volume-dirs.txt" 2>&1 || true
fi
echo 'Diagnostics Artifactory 7 collectes.'
