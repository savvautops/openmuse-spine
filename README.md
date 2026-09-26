# OpenMuse on Spine — real app, iPhone via Tailscale

Runs the **actual OpenMuse** (CopilotKit/openmuse, MIT) on Spine and exposes it
on the tailnet so it opens on iPhone Safari like a native app.

- **Phase 1 (this bundle): UI first, sample mode.** Real OpenMuse UI with
  fictional data. No model key, no Google account, no Docker computer needed.
  (Browser worker included — one compose command.)
- **Phase 2 (later): wire the backend.** Flip `AGENT_BACKEND=model`,
  add a provider key, done.

## What you get

| Piece | Local port | Tailscale URL (iPhone Safari) |
|---|---|---|
| Web UI (Expo web export) | 8081 | `https://savv-spine.taila7272b.ts.net:8445` |
| API server | 8787 | `https://savv-spine.taila7272b.ts.net:8446` |
| Browser worker (Docker) | 8790 | tailnet-internal only |

(Ports 8443/8444 are already taken on this tailnet by code-server and HAG —
deploy.sh refuses to reuse a served port and tells you how to pick another.
If you change ports later, also update `PUBLIC_API_URL`/`ALLOWED_ORIGINS`
in `~/openmuse/.env`.)

Bookmark the web UI URL on the iPhone home screen — it runs fullscreen.

## Run on Spine (one command)

```bash
bash deploy.sh
```

The script: checks node ≥ 24 / pnpm / docker / tailscale → clones
CopilotKit/openmuse at the pinned commit → `pnpm install` → writes `.env`
from the template (generates `WORKER_TOKEN`) → builds the API and the web UI
→ starts the browser worker → starts everything → enables
`tailscale serve` → prints the iPhone URL.

### The one manual step (only you can do it)

Every OpenMuse deployment needs a server-only **CopilotKit Intelligence
project key**, even in sample mode. On Spine, once:

```bash
cd ~/openmuse
npx copilotkit@latest login      # opens a browser OAuth flow — approve it
npx copilotkit@latest project select
```

Put the generated key in `~/openmuse/.env` as `CPK_INTELLIGENCE_API_KEY`,
then re-run `bash deploy.sh` (it resumes cleanly).

## Day-to-day

```bash
bash start.sh    # start API + web UI (+ worker)
bash stop.sh     # stop everything
bash status.sh   # health check
```

## Phase 2 — real backend (later)

In `~/openmuse/.env`:

```bash
AGENT_BACKEND=model
MODEL=anthropic/claude-sonnet-4-5-20250929   # or your pick
ANTHROPIC_API_KEY=sk-ant-...
```

Restart the API (`bash stop.sh && bash start.sh`). Provider keys stay on
Spine, never in the repo. Optional later: `WORKSPACE_MODE=live` + Google
OAuth for real Gmail/Calendar, `COMPUTER_ENABLED=true` for the Linux
terminal (needs `docker build -t openmuse-computer:local apps/computer`).

## Notes

- Built against upstream commit `205cc38`. The Expo web export was
  compile-tested on the pinned commit before this bundle shipped
  (pending final verification run — see status).
- `tailscale serve` provisions a real TLS cert for the tailnet hostname, so
  Safari on the iPhone trusts it with no warnings (Tailscale app must be
  active on the phone).
- API CORS is locked to the web UI origin via `ALLOWED_ORIGINS`.
- `.openmuse/` holds the app database — back it up, keep it private.
