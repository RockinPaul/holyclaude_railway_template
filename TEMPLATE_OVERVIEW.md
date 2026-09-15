# HolyClaude Workstation

An always-on AI coding workstation in your browser. [HolyClaude](https://github.com/CoderLuii/HolyClaude)
packages Claude Code with a web UI, a headless Chromium, eight AI CLIs — Codex, Gemini, Cursor,
Junie, OpenCode, Pi, TaskMaster — and around fifty development tools. This template runs it on
Railway with its state on a volume and its web UI behind a password generated for your deployment.

## What you get

One service, one volume, a public domain. The deploy form asks for nothing.

- **Claude Code 2.1.270**, the real CLI, on your own Anthropic subscription or API key.
- **A browser UI** with a web terminal, file tree, git integration and project management.
- **A headless browser** — Chromium 152 with Playwright, already configured.
- **A dev toolchain** — Node, Python, git, GitHub CLI, ripgrep, deployment and database clients.

## After deploying

1. Copy `CLOUDCLI_PASSWORD` from the service's **Variables** tab.
2. Open the public domain and sign in as **`admin`**.
3. Sign in to Anthropic from the web UI, or set `ANTHROPIC_API_KEY`.

The account is created inside the container before the URL is reachable, so nobody can claim your
deployment by getting to it first.

## What persists

The volume holds your projects (`/workspace`), Claude's settings and memory, the saved Claude Code
session — you do not sign in again after a redeploy — the CLI configuration for Codex, Gemini and
Cursor, your Git and GitHub CLI config, and the account database. Running terminals and agent
sessions end on redeploy; files do not.

## Before you deploy this

**Upstream advises against putting HolyClaude on the public internet.** Its web UI gives a full
shell, runs arbitrary code, and holds your Anthropic credentials; the project recommends a Tailscale
or Cloudflare tunnel instead of an open port. A Railway domain is public.

This template does what can be done about that: a single-user account created before first contact,
registration closed afterwards (403), bcrypt at cost 12, per-installation JWT secret, and a
24-character generated password that the container refuses to start without. **CloudCLI has no login
rate limiting**, so that password is the whole door — keep the generated one, and treat the URL like
an SSH session into your dev box.

There is no password-change endpoint: `CLOUDCLI_PASSWORD` is the initial password, and resetting it
means deleting the account database from the volume.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `CLOUDCLI_PASSWORD` | generated | Web UI password for `admin`. |
| `ANTHROPIC_API_KEY` | *(empty)* | Optional, instead of signing in. |
| `CLAUDE_CODE_OAUTH_TOKEN` | *(empty)* | Optional, from `claude setup-token`. |

`GEMINI_API_KEY`, `OPENAI_API_KEY` and `CURSOR_API_KEY` can be added as variables or entered in the
web UI. Do not set `API_KEY` — CloudCLI applies it to every `/api` request and that locks the browser
out.

## Notes

The image is large (~13 GB unpacked), so the first deploy takes a while and it will not fit the Free
or Trial plan's 4 GB image limit. Codex's bubblewrap sandbox needs user namespaces that Railway's
runtime does not grant; use Codex in its non-sandboxed modes, or Claude Code.

## Licences

HolyClaude is MIT. Its web UI, CloudCLI (`@cloudcli-ai/cloudcli`, upstream `siteboon/claudecodeui`),
is AGPL-3.0-or-later and ships unmodified. Claude Code is Anthropic's proprietary CLI, used with
your own account. The template's glue is MIT.
