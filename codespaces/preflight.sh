#!/usr/bin/env bash
set -Eeuo pipefail
echo '=== Verification Codespace (sans lancer Artifactory) ==='
if ! docker info >/dev/null 2>&1; then echo 'Docker indisponible dans le devcontainer'; exit 1; fi
docker version --format 'Docker Engine: {{.Server.Version}}'
df -h .
free -h
echo
echo 'IMPORTANT : ce Codespace consomme du calcul pendant son fonctionnement et du stockage meme arrete.'
echo 'Avant chaque demarrage, verifier Settings > Billing and licensing > Budgets and alerts et Codespaces.'
echo 'Port 8080 a laisser PRIVATE dans l onglet Ports.'
echo 'Pour lancer une instance : bash codespaces/lab.sh start 6.1.0'
echo 'Pour arreter et liberer CPU/RAM : bash codespaces/lab.sh stop'
