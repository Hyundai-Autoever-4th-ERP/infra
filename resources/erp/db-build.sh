#!/bin/sh
set -eu
case "$ERP_SERVICE" in
  erp-auth|erp-item|erp-sales|erp-inventory|erp-procurement) domain=${ERP_SERVICE#erp-} ;;
  erp-notification) domain=noti ;;
  *) echo "Unknown ERP service" >&2; exit 1 ;;
esac

tmp=$(mktemp -d)
network=erp-ci-${tmp##*.}
db=$network-db
builder=$network-build
cleanup() {
    docker rm -fv "$builder" "$db" >/dev/null 2>&1 || true
    docker network rm "$network" >/dev/null 2>&1 || true
    rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
docker network create "$network" >/dev/null
docker run -d --name "$db" --network "$network" --network-alias db \
    -e POSTGRES_PASSWORD="$(openssl rand -hex 24)" postgres:17 >/dev/null
ready=false
for attempt in $(seq 1 60); do
    if docker exec "$db" pg_isready -h 127.0.0.1 -U postgres >/dev/null; then ready=true; break; fi
    sleep 1
done
[ "$ready" = true ] || { echo 'PostgreSQL startup timed out' >&2; exit 1; }
user=${domain}_app
database=${domain}_db
password=$(openssl rand -hex 24)
docker exec -i "$db" psql -X -v ON_ERROR_STOP=1 -U postgres <<SQL
CREATE ROLE $user LOGIN PASSWORD '$password';
CREATE DATABASE $database OWNER $user;
REVOKE CONNECT ON DATABASE $database FROM PUBLIC;
SQL
docker run --rm --network "$network" -e PGPASSWORD="$password" postgres:17 \
    psql -X -v ON_ERROR_STOP=1 -h db -U "$user" -d "$database" \
    -c 'select current_database(), current_user'
if [ ! -f gradlew ]; then
    if [ -n "$(git ls-files | grep -Ev '^(Jenkinsfile|README\.md|\.gitignore|\.github/.*|\.githooks/.*|compose\.yaml|db/init\.sql)$' || true)" ]; then
        echo 'Gradle wrapper missing' >&2; exit 1
    fi
    echo 'PostgreSQL connection verified. No application source yet.'
    exit 0
fi
git archive HEAD > "$tmp/source.tar"
# Only the two long-lived branches retain Gradle downloads across builds.
set --
case "${BRANCH_NAME:-}" in
    main|develop)
        set -- --mount "type=volume,source=gradle-${ERP_SERVICE}-${BRANCH_NAME},target=/gradle-cache" \
            -e GRADLE_USER_HOME=/gradle-cache
        ;;
esac
docker create "$@" --name "$builder" --network "$network" -w /workspace \
    -e SPRING_DATASOURCE_URL="jdbc:postgresql://db:5432/$database" \
    -e SPRING_DATASOURCE_USERNAME="$user" -e SPRING_DATASOURCE_PASSWORD="$password" \
    eclipse-temurin:25-jdk ./gradlew --no-daemon --max-workers=1 clean build >/dev/null
docker cp - "$builder:/workspace" < "$tmp/source.tar"
docker start -a "$builder"
test "$(docker inspect -f '{{.State.ExitCode}}' "$builder")" = 0
