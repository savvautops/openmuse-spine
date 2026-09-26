#!/usr/bin/env bash
# Health check for the OpenMuse Spine deployment.
set -uo pipefail
OPENMUSE_DIR="${OPENMUSE_DIR:-$HOME/openmuse}"
cd "$OPENMUSE_DIR" 2>/dev/null || { echo "no openmuse dir"; exit 1; }

for name in api web; do
  pidfile=".openmuse/${name}.pid"
  if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    echo "$name: running (pid $(cat "$pidfile"))"
  else
    echo "$name: NOT running"
  fi
done

curl -sf http://127.0.0.1:8787/api/health >/dev/null 2>&1 \
  && echo "api/health: OK" || echo "api/health: FAIL"
curl -sf http://127.0.0.1:8081/ >/dev/null 2>&1 \
  && echo "web ui: OK" || echo "web ui: FAIL"
docker compose -f infra/compose.yaml ps --format '{{.Name}} {{.Status}}' 2>/dev/null
tailscale serve status 2>/dev/null | head -8
