# HolyClaude on Railway

An always-on AI coding workstation: [HolyClaude](https://github.com/CoderLuii/HolyClaude) —
Claude Code with a browser UI, a headless Chromium, eight AI CLIs and ~50 dev tools — running on
Railway with its state on a volume and its web UI behind a generated password.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/holyclaude-workstation)

## Service

| Service | Base | Public | Role |
|---|---|---|---|
| `holyclaude` | `coderluii/holyclaude:1.6.1` | **yes** | The whole workstation. s6-overlay supervises CloudCLI, Xvfb and the session bridge. |

One service, no gateway: CloudCLI speaks plain HTTP and WebSocket on port 3001, which is what
Railway's edge expects. This repository is a thin wrapper around upstream's published multi-arch
image — it adapts three things to Railway and changes nothing else:

- **State goes on one volume** mounted at `/home/claude/.claude`, with `/workspace` symlinked into it.
- **The account is created before anyone can reach the URL**, from inside the container.
- **The server binds dual-stack** (`HOST=::`) so the private network works too.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `CLOUDCLI_PASSWORD` | generated, 24 chars | Password for the web UI. Generated per deployment; read it from the service variables. |
| `ANTHROPIC_API_KEY` | *(empty)* | Optional. Pay-as-you-go instead of signing in with a subscription. |
| `CLAUDE_CODE_OAUTH_TOKEN` | *(empty)* | Optional. From `claude setup-token` on your own machine, for Pro/Max plans. |
| `CLOUDCLI_USERNAME` | `admin` | Baked into the image. Add the variable to change it before the first boot. |
| `PORT` / `HOST` | `3001` / `::` | Baked. Upstream's service script runs `cloudcli --port 3001` literally. |
| `DATABASE_PATH` | `/home/claude/.claude/.cloudcli/auth.db` | Baked. Puts the account database on the volume. |

The deploy form asks for nothing. Other provider keys — `GEMINI_API_KEY`, `OPENAI_API_KEY`,
`CURSOR_API_KEY` — can be added as service variables, or entered in the web UI, which stores them in
the database on the volume.

**Do not set `API_KEY`.** CloudCLI applies it as `app.use('/api', validateApiKey)`, so every request
needs an `x-api-key` header — including the ones the browser makes. Setting it locks you out of the
web UI.

## First run

1. Open the service's **Variables** tab and copy `CLOUDCLI_PASSWORD`.
2. Open the public domain and sign in as **`admin`** with that password.
3. Sign in to Anthropic from the web UI (the same OAuth flow as desktop Claude Code), or set
   `ANTHROPIC_API_KEY`.

The account already exists when you arrive — the entrypoint registers it as soon as the server is
listening. That is deliberate: CloudCLI's own first-run flow is "open the page and create an
account", which is safe bound to `127.0.0.1` and unsafe on a public domain, where the first visitor
to reach the URL would own a machine holding your Anthropic session.

## Security

Read this before deploying. **Upstream's own advice is not to expose HolyClaude to the internet at
all** — its README says to put Tailscale or a Cloudflare Tunnel in front of it, because the web UI
"exposes a full shell through the web terminal plugin", can run arbitrary code, and holds your
Anthropic OAuth tokens and API keys. A Railway domain is public. This template makes that as sound
as it can be, and it is still further out than upstream intends.

What is actually true of the login, measured against a running deployment:

- Single user. Registration returns **403** once the account exists, so the URL cannot be claimed by
  a visitor.
- Passwords are bcrypt at cost 12. A wrong password returns **401**, unauthenticated API calls
  return **401**, and the JWT is signed with a per-installation secret kept in the database.
- **There is no login rate limiting.** The generated 24-character password is what carries the
  security — keep it. The entrypoint refuses to start with an empty or short one.
- There is no password-change endpoint. `CLOUDCLI_PASSWORD` is the *initial* password: changing the
  variable later does not change the account. To reset, delete `.cloudcli/auth.db` from the volume
  and redeploy, which also drops the stored provider credentials.

Claude Code runs in `acceptEdits` mode as shipped. Agents in this workspace run commands, so the
blast radius is a shell on this container and everything reachable from it.

## What persists

The volume at `/home/claude/.claude` holds Claude settings and memory, the saved Claude Code session
(so you do not sign in again after a redeploy), Codex/Gemini/Cursor config, Git and GitHub CLI
config, the CloudCLI account database with the JWT secret and any provider keys you entered in the
UI, and `workspace/` — your projects, reached at `/workspace`.

**Sessions do not persist.** A redeploy replaces the container, which ends running terminals and
agent runs. Files on the volume are untouched.

## Why it is shaped this way

- **The volume mounts at `~/.claude`, not at `/data`.** Upstream refuses to start when that
  directory is a symlink ("Claude durable state must be a real directory"), and mounting over
  `/home/claude` would hide the image-owned Claude Code binary at `~/.local/bin/claude`. So the
  durable root *is* the mount point, and everything else lives inside it.
- **`/workspace` is a symlink into the volume.** Upstream's s6 service sets `WORKSPACES_ROOT`
  to `/workspace` literally, so the path has to keep that name. CloudCLI resolves the root with
  `realpath` before comparing project paths against it, so the symlink is consistent.
- **The entrypoint steps out of `/workspace` first.** The image's `WORKDIR` is the directory being
  replaced; doing that while it is the working directory leaves every later process with an
  unreachable cwd, and the boot fails far from the cause.
- **`HOST=::`.** Node binds dual-stack, so the service answers both Railway's edge and the
  IPv6-only private network.
- **Chromium needs nothing special here.** The image already bakes
  `CHROMIUM_FLAGS=--no-sandbox --disable-gpu --disable-dev-shm-usage`, so the `SYS_ADMIN`,
  `seccomp=unconfined` and `shm_size: 2g` from upstream's Compose file are not required — verified
  by taking a Playwright screenshot in a container with none of them.

## Upgrading

Bump `HOLYCLAUDE_VERSION` in the `Dockerfile` and push. Upstream releases roughly weekly and pins
every input by checksum. For the smaller image, use a `-slim` tag: the tools Claude needs are then
installed on demand instead of being pre-baked.

## Licences

HolyClaude is [MIT](https://github.com/CoderLuii/HolyClaude/blob/master/LICENSE). Its web UI,
CloudCLI (`@cloudcli-ai/cloudcli`, upstream `siteboon/claudecodeui`), is **AGPL-3.0-or-later** and is
shipped unmodified from the published package. Claude Code is Anthropic's proprietary CLI and runs
on your own subscription or API key. The glue in this repository is MIT.
