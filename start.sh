#!/usr/bin/env bash
# Start OpenMuse API + web UI on Spine. Run from anywhere: bash start.sh
set -euo pipefail
OPENMUSE_DIR="${OPENMUSE_DIR:-$HOME/openmuse}"
API_LOCAL_PORT=8787
WEB_LOCAL_PORT=8081
cd "$OPENMUSE_DIR"
mkdir -p logs .openmuse

[ -f dist/apps/server/src/index.js ] || { echo "API not built — run deploy.sh first"; exit 1; }
[ -d apps/mobile/dist/web ] || { echo "web UI not built — run deploy.sh first"; exit 1; }

if [ -f .openmuse/api.pid ] && kill -0 "$(cat .openmuse/api.pid)" 2>/dev/null; then
  echo "API already running (pid $(cat .openmuse/api.pid))"
else
  node --env-file=.env dist/apps/server/src/index.js >>logs/api.log 2>&1 &
  echo $! > .openmuse/api.pid
  echo "API started (pid $!)"
fi

if [ -f .openmuse/web.pid ] && kill -0 "$(cat .openmuse/web.pid)" 2>/dev/null; then
  echo "web UI already running (pid $(cat .openmuse/web.pid))"
else
  npx --yes serve apps/mobile/dist/web -l "$WEB_LOCAL_PORT" >>logs/web.log 2>&1 &
  echo $! > .openmuse/web.pid
  echo "web UI started (pid $!)"
fi

sleep 2
curl -sf "http://127.0.0.1:${API_LOCAL_PORT}/api/health" >/dev/null \
  && echo "API health: OK" || echo "API health: FAIL — see logs/api.log"
