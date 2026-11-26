#!/bin/sh
set -eu
cd /opt/erp
exec 9>.deploy.lock
flock -x 9
service=${1:?Missing service}
case "$service" in
    erp-auth) port=8081; image_key=AUTH_IMAGE ;;
    erp-item) port=8082; image_key=ITEM_IMAGE ;;
    erp-inventory) port=8083; image_key=INVENTORY_IMAGE ;;
    erp-procurement) port=8084; image_key=PROCUREMENT_IMAGE ;;
    erp-sales) port=8085; image_key=SALES_IMAGE ;;
    erp-notification) port=8086; image_key=NOTIFICATION_IMAGE ;;
    *) echo "Unknown service: $service" >&2; exit 1 ;;
esac
digest=${2:?Missing digest}
printf '%s\n' "$digest" | grep -Eq '^sha256:[0-9a-f]{64}$'
# Root-owned host configuration. The repository and registry are fixed on this host.
. ./registry.env
image="${DEV_ECR_REGISTRY:?}/$service@$digest"
export DOCKER_CONFIG
DOCKER_CONFIG=$(mktemp -d)
trap 'rm -rf "$DOCKER_CONFIG"' EXIT
aws ecr get-login-password --region "${AWS_REGION:?}" > "$DOCKER_CONFIG/password"
docker login --username AWS --password-stdin "$DEV_ECR_REGISTRY" < "$DOCKER_CONFIG/password"
rm "$DOCKER_CONFIG/password"
docker pull "$image"
touch deployed.env
compose() { docker compose --env-file .env --env-file deployed.env -f compose.dev.yaml "$@"; }
export "$image_key=$image"
old_id=$(compose ps -q "$service")
old_image=''
if [ -n "$old_id" ]; then old_image=$(docker inspect -f '{{.Config.Image}}' "$old_id"); fi
if compose up -d --no-deps "$service"; then
    for attempt in $(seq 1 60); do
        if curl -fsS --max-time 2 "http://127.0.0.1:$port/actuator/health" | grep -Eq '"status"[[:space:]]*:[[:space:]]*"UP"'; then
            awk -F= -v key="$image_key" '$1 != key' deployed.env > deployed.env.tmp
            printf '%s=%s\n' "$image_key" "$image" >> deployed.env.tmp
            mv deployed.env.tmp deployed.env
            exit 0
        fi
        sleep 2
    done
fi
if [ -n "$old_image" ]; then
    export "$image_key=$old_image"
    compose up -d --no-deps "$service"
else
    compose stop "$service"
fi
exit 1
