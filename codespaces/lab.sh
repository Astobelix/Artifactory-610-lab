#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
op="${1:-status}"
version="${2:-}"
state="codespaces/.active-version"
mkdir -p codespaces
case "$op" in
  start)
    case "$version" in
      6.1.0|6.23.42)
        image="releases-docker.jfrog.io/jfrog/artifactory-oss:$version"
        nginx=6;;
      7.161.26)
        echo 'Le demarrage independant de 7.161.26 avec Derby n est pas encore qualifie.'
        echo 'La version 7 a ete validee apres migration depuis 6.23.42, pas en installation neuve.'
        exit 8;;
      *) echo 'Usage : bash codespaces/lab.sh start 6.1.0|6.23.42'; exit 2;;
    esac
    if ! docker info >/dev/null 2>&1; then echo 'Docker indisponible'; exit 3; fi
    if [ -f "$state" ]; then
      current="$(cat "$state")"
      if [ "$current" != "$version" ]; then
        echo "Une instance $current est active. L arreter d abord : bash codespaces/lab.sh stop"
        exit 4
      fi
    fi
    free_gb="$(df -BG . | awk 'NR==2 { gsub("G","",$4); print $4 }')"
    if [ "$free_gb" -lt 5 ]; then
      echo "Moins de 5 Go disponibles ($free_gb Go) : demarrage refuse."
      exit 5
    fi
    export ARTIFACTORY_IMAGE="$image" NGINX_GENERATION="$nginx"
    export COMPOSE_PROJECT_NAME="artifactory-${version//./}"
    docker compose -f codespaces/compose.yaml pull
    docker compose -f codespaces/compose.yaml up -d
    printf '%s\n' "$version" >"$state"
    echo "Artifactory $version : attendre 1 a 3 minutes puis ouvrir le port prive 8080 (onglet Ports)."
    echo 'Sur Android : ouvrir le Codespace GitHub, onglet Ports, puis ouvrir le lien HTTPS du port 8080.'
    ;;
  stop)
    if [ ! -f "$state" ]; then echo 'Aucune instance enregistree'; exit 0; fi
    version="$(cat "$state")"
    export COMPOSE_PROJECT_NAME="artifactory-${version//./}"
    export ARTIFACTORY_IMAGE="releases-docker.jfrog.io/jfrog/artifactory-oss:$version"
    export NGINX_GENERATION=6
    docker compose -f codespaces/compose.yaml down
    rm -f "$state"
    echo "Instance $version arretee ; volume de donnees conserve."
    ;;
  status)
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
    if [ -f "$state" ]; then echo "Version active : $(cat "$state")"; fi
    ;;
  logs)
    if [ ! -f "$state" ]; then echo 'Aucune instance active'; exit 0; fi
    version="$(cat "$state")"
    export COMPOSE_PROJECT_NAME="artifactory-${version//./}"
    export ARTIFACTORY_IMAGE="releases-docker.jfrog.io/jfrog/artifactory-oss:$version"
    export NGINX_GENERATION=6
    docker compose -f codespaces/compose.yaml logs --tail=100
    ;;
  *) echo 'Usage : bash codespaces/lab.sh start VERSION | stop | status | logs'; exit 2;;
esac
