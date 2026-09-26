#!/usr/bin/env bash
# Stop OpenMuse API + web UI (+ browser worker) on Spine.
set -uo pipefail
OPENMUSE_DIR="${OPENMUSE_DIR:-$HOME/openmuse}"
cd "$OPENMUSE_DIR" 2>/dev/null || exit 0

for name in api web; do
  pidfile=".openmuse/${name}.pid"
  if [ -f "$pidfile" ]; then
    pid="$(cat "$pidfile")"
    if kill -0 "$pid" 2>/dev/null; then kill "$pid" && echo "stopped $name ($pid)"; fi
    rm -f "$pidfile"
  fi
done

docker compose -f infra/compose.yaml down 2>/dev/null && echo "browser worker stopped"
echo "done"
