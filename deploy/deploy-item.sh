#!/bin/sh
set -eu
cd /opt/erp
exec 9>.deploy.lock
flock -x 9
digest=${1:?Missing digest}
printf '%s\n' "$digest" | grep -Eq '^sha256:[0-9a-f]{64}$'
# Root-owned host configuration. The repository and registry are fixed on this host.
. ./registry.env
image="${ITEM_REPOSITORY:?}@$digest"
export DOCKER_CONFIG
DOCKER_CONFIG=$(mktemp -d)
trap 'rm -rf "$DOCKER_CONFIG"' EXIT
aws ecr get-login-password --region "${AWS_REGION:?}" > "$DOCKER_CONFIG/password"
docker login --username AWS --password-stdin "${ITEM_REPOSITORY%%/*}" < "$DOCKER_CONFIG/password"
rm "$DOCKER_CONFIG/password"
docker pull "$image"
compose() { docker compose -f compose.dev.yaml "$@"; }
export ITEM_IMAGE="$image"
old_id=$(compose ps -q erp-item)
old_image=''
if [ -n "$old_id" ]; then old_image=$(docker inspect -f '{{.Config.Image}}' "$old_id"); fi
if compose up -d --no-deps erp-item; then
    for attempt in $(seq 1 60); do
        if curl -fsS --max-time 2 http://127.0.0.1:8082/actuator/health | grep -Eq '"status"[[:space:]]*:[[:space:]]*"UP"'; then
            printf 'ITEM_IMAGE=%s\n' "$image" > deployed.env.tmp
            mv deployed.env.tmp deployed.env
            exit 0
        fi
        sleep 2
    done
fi
if [ -n "$old_image" ]; then
    ITEM_IMAGE="$old_image" compose up -d --no-deps erp-item
else
    compose stop erp-item
fi
exit 1
