#!/usr/bin/env bash
# OpenMuse on Spine — one-shot install + build + start.
# Run on Spine:  bash deploy.sh
# Safe to re-run; it resumes where it left off.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENMUSE_DIR="${OPENMUSE_DIR:-$HOME/openmuse}"
OPENMUSE_PIN="${OPENMUSE_PIN:-205cc386b75aae1a862f3fdd43104b570c8d0911}"
# Override if your tailnet hostname differs: OPENMUSE_TAILNET_HOST=...
TAILNET_HOST="${OPENMUSE_TAILNET_HOST:-savv-spine.taila7272b.ts.net}"
# tailscale-serve HTTPS ports -> local services. Override with
# OPENMUSE_API_PORT / OPENMUSE_WEB_PORT if either is already taken.
# (8443 = code-server, 8444 = HAG on this tailnet — do NOT use those.)
API_PORT="${OPENMUSE_API_PORT:-8446}"
WEB_PORT="${OPENMUSE_WEB_PORT:-8445}"
API_LOCAL_PORT=8787
WEB_LOCAL_PORT=8081
API_URL="https://${TAILNET_HOST}:${API_PORT}"
WEB_URL="https://${TAILNET_HOST}:${WEB_PORT}"

log() { printf '\n==> %s\n' "$*"; }
die() { printf '\n!! %s\n' "$*" >&2; exit 1; }

# --- 0. prerequisites ----------------------------------------------------------
log "checking prerequisites"
command -v node >/dev/null || die "node not found — install Node 24 LTS first"
node -e "const v=process.versions.node.split('.').map(Number); if(v[0]<24){process.exit(1)}" \
  || die "node >= 24 required (found $(node --version))"
command -v pnpm >/dev/null || die "pnpm not found — run: npm i -g pnpm@11.19.0"
command -v docker >/dev/null || die "docker not found — needed for the browser worker"
command -v tailscale >/dev/null || die "tailscale not found"
command -v openssl >/dev/null || die "openssl not found"

# --- 0b. tailscale serve port conflicts -----------------------------------------
log "checking tailscale serve ports"
SERVE_STATUS="$(tailscale serve status 2>/dev/null || true)"
for p in "$API_PORT" "$WEB_PORT"; do
  if printf '%s' "$SERVE_STATUS" | grep -q ":${p}\b"; then
    die "tailscale serve already uses port $p.
    Pick a free port and re-run, e.g.:
      OPENMUSE_WEB_PORT=8447 OPENMUSE_API_PORT=8448 bash deploy.sh"
  fi
done
[ "$API_PORT" != "$WEB_PORT" ] || die "API and web ports must differ"

mkdir -p "$OPENMUSE_DIR/logs"

# --- 1. clone / update ---------------------------------------------------------
if [ -d "$OPENMUSE_DIR/.git" ]; then
  log "updating repo at $OPENMUSE_DIR"
  git -C "$OPENMUSE_DIR" fetch --depth 1 origin "$OPENMUSE_PIN" 2>/dev/null || \
    git -C "$OPENMUSE_DIR" fetch origin
  git -C "$OPENMUSE_DIR" checkout -q "$OPENMUSE_PIN"
else
  log "cloning OpenMuse @ $OPENMUSE_PIN"
  git clone --depth 1 https://github.com/CopilotKit/openmuse "$OPENMUSE_DIR"
  git -C "$OPENMUSE_DIR" fetch --depth 1 origin "$OPENMUSE_PIN"
  git -C "$OPENMUSE_DIR" checkout -q "$OPENMUSE_PIN"
fi
cd "$OPENMUSE_DIR"

# --- 2. install -----------------------------------------------------------------
log "installing dependencies (takes a few minutes)"
pnpm install --frozen-lockfile

# --- 3. env ---------------------------------------------------------------------
if [ ! -f .env ]; then
  log "writing .env from template"
  if [ -f "$SCRIPT_DIR/.env.spine.example" ]; then
    cp "$SCRIPT_DIR/.env.spine.example" .env
  else
    cp .env.example .env
  fi
  # bake in this machine's tailnet URLs
  sed -i "s|__OPENMUSE_API_URL__|$API_URL|g" .env
  sed -i "s|__OPENMUSE_WEB_URL__|$WEB_URL|g" .env
  # random worker token
  TOKEN="$(openssl rand -hex 24)"
  sed -i "s|WORKER_TOKEN=REPLACE_ME_GENERATED_BY_DEPLOY_SH|WORKER_TOKEN=$TOKEN|" .env
  grep -q "^WORKER_TOKEN=$TOKEN" .env || \
    sed -i "s|^# *WORKER_TOKEN=.*|WORKER_TOKEN=$TOKEN|" .env
fi

if grep -q "PASTE_YOUR_COPILOTKIT_INTELLIGENCE_KEY_HERE" .env; then
  cat <<'EOF'

!! Missing CPK_INTELLIGENCE_API_KEY — required even in sample mode.
   On Spine, run once:
     cd ~/openmuse
     npx copilotkit@latest login
     npx copilotkit@latest project select
   Then put the generated server-only key in ~/openmuse/.env as
   CPK_INTELLIGENCE_API_KEY and re-run:  bash deploy.sh
EOF
  exit 1
fi

# --- 4. build -------------------------------------------------------------------
log "building API server"
pnpm build:server

log "building web UI (bakes in API URL: $API_URL)"
EXPO_PUBLIC_API_URL="$API_URL" pnpm --dir apps/mobile build:web
[ -d apps/mobile/dist/web ] || die "web export missing at apps/mobile/dist/web"

# --- 5. browser worker ------------------------------------------------------------
log "starting browser worker (docker)"
docker compose --env-file .env -f infra/compose.yaml up --build -d

# --- 6. start API + web -------------------------------------------------------------
log "starting API + web UI"
bash "$SCRIPT_DIR/start.sh" 2>/dev/null || bash ./start.sh 2>/dev/null || true
# (start.sh lives next to deploy.sh; also copied below as fallback)
if ! curl -sf "http://127.0.0.1:${API_LOCAL_PORT}/api/health" >/dev/null; then
  # fallback: start directly
  node --env-file=.env dist/apps/server/src/index.js >>logs/api.log 2>&1 &
  echo $! > .openmuse/api.pid
  npx --yes serve apps/mobile/dist/web -l "$WEB_LOCAL_PORT" >>logs/web.log 2>&1 &
  echo $! > .openmuse/web.pid
  sleep 3
fi

# --- 7. tailscale serve ---------------------------------------------------------------
log "exposing on the tailnet"
sudo -n tailscale serve --https="$WEB_PORT" "http://127.0.0.1:${WEB_LOCAL_PORT}" 2>/dev/null \
  || tailscale serve --https="$WEB_PORT" "http://127.0.0.1:${WEB_LOCAL_PORT}"
sudo -n tailscale serve --https="$API_PORT" "http://127.0.0.1:${API_LOCAL_PORT}" 2>/dev/null \
  || tailscale serve --https="$API_PORT" "http://127.0.0.1:${API_LOCAL_PORT}"

# --- 8. verify --------------------------------------------------------------------------
log "verifying"
curl -sf "http://127.0.0.1:${API_LOCAL_PORT}/api/health" >/dev/null \
  && echo "API OK: http://127.0.0.1:${API_LOCAL_PORT}/api/health" \
  || die "API health check failed — see logs/api.log"
curl -sf "http://127.0.0.1:${WEB_LOCAL_PORT}/" >/dev/null \
  && echo "WEB OK: http://127.0.0.1:${WEB_LOCAL_PORT}/" \
  || die "web UI check failed — see logs/web.log"

cat <<EOF

Done. On your iPhone (Tailscale app active), open:

  $WEB_URL

Bookmark it / Add to Home Screen for fullscreen. Sample mode: fictional data,
no model key needed. API health: $API_URL/api/health
Logs: $OPENMUSE_DIR/logs/
EOF
