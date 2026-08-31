#!/usr/bin/env bash
# Re-verify the agent-skill-spec-harness preview demo. Exits non-zero on any
# pass-criterion failure. Run this whenever the pinned versions in Dockerfile,
# docker-compose.yml, or app/requirements.txt get bumped.
set -uo pipefail
cd "$(dirname "$0")"
KEEP=0; [ "${1:-}" = "--keep" ] && KEEP=1
fail(){ echo "FAIL: $*" >&2; docker compose down -v >/dev/null 2>&1; exit 1; }

echo "==> config"
docker compose config --quiet || fail "compose config invalid"

echo "==> build"
docker compose build >/tmp/m1-agent-preview-build.log 2>&1 || { tail -20 /tmp/m1-agent-preview-build.log; fail "build"; }

echo "==> up"
docker compose up -d >/dev/null 2>&1 || fail "up"

echo "==> criterion: both services report healthy"
for i in $(seq 1 15); do
  APP_HEALTH=$(docker inspect --format '{{.State.Health.Status}}' m1-agent-preview-app-1 2>/dev/null)
  REDIS_HEALTH=$(docker inspect --format '{{.State.Health.Status}}' m1-agent-preview-redis-1 2>/dev/null)
  [ "$APP_HEALTH" = "healthy" ] && [ "$REDIS_HEALTH" = "healthy" ] && break
  sleep 2
done
[ "$APP_HEALTH" = "healthy" ] || fail "app never became healthy"
[ "$REDIS_HEALTH" = "healthy" ] || fail "redis never became healthy"
echo "    ok"

echo "==> criterion: app runs as a non-root user"
USER_IN_CONTAINER=$(docker inspect --format '{{.Config.User}}' m1-agent-preview-app-1)
[ "$USER_IN_CONTAINER" = "appuser" ] || fail "app container is not running as appuser (got: '$USER_IN_CONTAINER')"
echo "    ok"

echo "==> criterion: /health responds"
docker compose exec -T app python3 -c "
import urllib.request
r = urllib.request.urlopen('http://localhost:5000/health', timeout=5)
assert r.status == 200, r.status
" || fail "/health did not return 200"
echo "    ok"

echo "==> criterion: /stats increments against real redis"
docker compose exec -T app python3 -c "
import json, urllib.request
before = json.load(urllib.request.urlopen('http://localhost:5000/stats', timeout=5))['requests']
after = json.load(urllib.request.urlopen('http://localhost:5000/stats', timeout=5))['requests']
assert after == before + 1, (before, after)
" || fail "/stats did not increment"
echo "    ok"

if [ "$KEEP" = "1" ]; then
  echo "==> --keep: leaving the stack up. 'docker compose down -v' when done."
  exit 0
fi

echo "==> down"
docker compose down -v >/dev/null 2>&1 || fail "down"

echo
echo "DEMO PASSED — spec + skill produced a container that builds, runs, and passes real health checks"
