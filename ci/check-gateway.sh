#!/bin/sh
set -eu

image=${1:?검증할 이미지 태그를 입력하세요}
container=$(docker run -d -p 127.0.0.1::8080 "$image")
trap 'docker rm -f "$container" >/dev/null' EXIT
address=$(docker port "$container" 8080/tcp)
for attempt in $(seq 1 45); do
    if curl -fsS --max-time 2 "http://$address/actuator/health" 2>/dev/null |
        grep -Eq '"status"[[:space:]]*:[[:space:]]*"UP"'; then
        echo "Gateway health UP"
        exit 0
    fi
    sleep 1
done

docker logs --tail 60 "$container" >&2
exit 1
