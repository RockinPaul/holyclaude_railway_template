# Deploy and Host HolyClaude on Railway

[HolyClaude](https://github.com/CoderLuii/HolyClaude) is an AI coding workstation in a single
container: Claude Code with a browser UI, a headless Chromium, eight AI CLIs — Codex, Gemini,
Cursor, Junie, OpenCode, Pi, TaskMaster — and around fifty development tools, supervised by
s6-overlay.

This template runs it on Railway with its state on a volume and its web UI behind a password
generated for your deployment. One service, one volume, a public domain. The deploy form asks for
nothing.

## About Hosting HolyClaude

The container runs CloudCLI, the web UI, on port 3001 behind Railway's edge, with Claude Code and
the other CLIs installed alongside it and Chromium available for screenshots and browser testing.
Upstream is built for Docker Compose — bind mounts, a port published only on `127.0.0.1`, and a
person who creates the account in the browser — so this template adapts three things and changes
nothing else.

The volume mounts at `/home/claude/.claude`, the application's own state directory, because
upstream refuses to start when that path is a symlink and a mount over `/home/claude` would hide
the Claude Code binary the image installs. Your projects live at `/workspace`, which is symlinked
into that volume. The account database, and with it the signing secret for your session, sits on
the volume too — so a redeploy does not sign you out.

Registration is the part that needed the most care. CloudCLI is single-user: the first request to
create an account wins, and every later one is refused. That is safe on a laptop and unsafe on a
public URL, so the entrypoint creates the account itself — against a loopback-only instance of the
server, before the public one starts — and refuses to boot if that fails.

## Why Deploy HolyClaude on Railway?

- **It stays awake.** Long agent runs, builds and tests keep going when you close the laptop.
- **Nothing to install.** The image already has the CLIs, the browser, the language runtimes and
  the tools, pinned by checksum upstream.
- **Your own account.** Claude Code runs on your existing Claude subscription or API key; nothing
  is proxied through a third party.
- **It survives redeploys.** Projects, settings, memory, CLI credentials and your signed-in session
  are on the volume.
- **Reachable from anything.** It is a browser UI, so a phone or a borrowed machine works.

## Common Use Cases

- A always-on development box for agent work that outlasts a laptop session.
- Coding from a tablet or phone through the browser terminal and editor.
- Browser automation and screenshot testing with a Chromium that is already configured.
- Trying several AI CLIs against the same repository without installing any of them locally.

## Dependencies for HolyClaude Hosting

- An Anthropic account — a Claude Pro/Max subscription (sign in from the web UI) or an API key.
- Optional keys for the other CLIs: `GEMINI_API_KEY`, `OPENAI_API_KEY`, `CURSOR_API_KEY`. These can
  be added as service variables or entered in the web UI, which stores them on the volume.

### Deployment Dependencies

- Upstream project: [CoderLuii/HolyClaude](https://github.com/CoderLuii/HolyClaude) (MIT), image
  `coderluii/holyclaude:1.6.1`.
- Web UI: `@cloudcli-ai/cloudcli` (upstream `siteboon/claudecodeui`), **AGPL-3.0-or-later**,
  shipped unmodified.
- Claude Code is Anthropic's proprietary CLI, used with your own account:
  [docs.claude.com/en/docs/claude-code/overview](https://docs.claude.com/en/docs/claude-code/overview).
- Template source: [RockinPaul/holyclaude_railway_template](https://github.com/RockinPaul/holyclaude_railway_template) (MIT).

### Implementation Details

**After deploying:** copy `CLOUDCLI_PASSWORD` from the service's Variables tab, open the public
domain, and sign in as **`admin`**. Then sign in to Anthropic from the web UI, or set
`ANTHROPIC_API_KEY`.

**Read this before deploying.** Upstream advises against putting HolyClaude on the public internet
at all: the web UI gives a full shell, runs arbitrary code, and holds your Anthropic credentials,
and the project recommends a Tailscale or Cloudflare tunnel instead of an open port. A Railway
domain is public.

This template does what can be done about that: a single-user account claimed before the server is
ever exposed, registration closed afterwards (403 from the first request the public port answers),
bcrypt at cost 12, a per-installation JWT secret, and a 24-character generated password that the
container refuses to start without. **CloudCLI has no login rate limiting**, so that password is the
whole door — keep the generated one, and treat the URL like an SSH session into your dev box.

There is no password-change endpoint: `CLOUDCLI_PASSWORD` is the initial password, and resetting it
means deleting the account database from the volume. Do not set `API_KEY` — CloudCLI applies it to
every `/api` request, including the browser's, which locks you out of the UI.

`PORT` is set to 3001 and the web UI follows it; Railway's healthcheck probes that port and the
domain targets it, so leave it as it is.

**Notes.** The image is large (~13 GB unpacked), so the first deploy takes a while and it will not
fit the Free or Trial plan's 4 GB image limit. Codex's bubblewrap sandbox needs user namespaces that
Railway does not grant; use Codex in its non-sandboxed modes, or Claude Code. Running terminals and
agent sessions end on redeploy; files on the volume do not.
