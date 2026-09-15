#!/bin/bash
set -eu

# The image's WORKDIR is /workspace, which this script is about to replace with
# a symlink. Doing that while it is the working directory leaves every later
# process with an unreachable cwd ("getcwd: cannot access parent directories"),
# and the boot dies well after the real cause. Step out of it first.
cd /

STATE_DIR="${CLAUDE_STATE_DIR:-/home/claude/.claude}"
WORKSPACE_LINK="/workspace"
WORKSPACE_TARGET="${STATE_DIR}/workspace"
CLOUDCLI_STATE="${STATE_DIR}/.cloudcli"
SERVER_PORT="${PORT:-3001}"

# ---------------------------------------------------------------------------
# Fail closed on a missing password
# ---------------------------------------------------------------------------
# CloudCLI's own first-run flow is "open the page and register an account".
# That is safe behind a Compose file bound to 127.0.0.1 and unsafe on a public
# Railway domain, where the first visitor to reach the URL would own a machine
# holding the deployer's Anthropic session. The account is therefore created
# from inside the container, before anyone can reach it.
if [ -z "${CLOUDCLI_PASSWORD:-}" ]; then
    echo "FATAL: CLOUDCLI_PASSWORD is empty." >&2
    echo "  Set it to a long random string; it is the password for the web UI," >&2
    echo "  which exposes a shell and this deployment's Claude Code session." >&2
    exit 1
fi
if [ "${#CLOUDCLI_PASSWORD}" -lt 12 ]; then
    echo "FATAL: CLOUDCLI_PASSWORD is shorter than 12 characters." >&2
    echo "  CloudCLI has no login rate limiting, so a short password is a real" >&2
    echo "  exposure on a public domain. Use the generated value." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Volume layout
# ---------------------------------------------------------------------------
# The volume is mounted at ~/.claude because upstream refuses to run when that
# directory is a symbolic link ("Claude durable state must be a real
# directory"), and mounting over /home or /home/claude would hide the
# image-owned Claude Code binary at ~/.local/bin/claude. Everything durable
# therefore lives under it: CLI state, the CloudCLI database and the workspace.
mkdir -p "${STATE_DIR}"
chown claude:claude "${STATE_DIR}"

for dir in "${WORKSPACE_TARGET}" "${CLOUDCLI_STATE}"; do
    if [ ! -d "${dir}" ]; then
        mkdir -p "${dir}"
        chown claude:claude "${dir}"
    fi
done

# /workspace is what upstream's s6 service sets as WORKSPACES_ROOT, so it has
# to keep that name. CloudCLI resolves the root with realpath before comparing
# project paths against it, so a symlink into the volume is consistent.
if [ ! -L "${WORKSPACE_LINK}" ]; then
    rmdir "${WORKSPACE_LINK}" 2>/dev/null || true
    if [ -e "${WORKSPACE_LINK}" ]; then
        echo "FATAL: ${WORKSPACE_LINK} exists and is not an empty directory." >&2
        echo "  It must become a symlink to ${WORKSPACE_TARGET} so projects land" >&2
        echo "  on the volume. Nothing was deleted; inspect it and retry." >&2
        exit 1
    fi
    ln -s "${WORKSPACE_TARGET}" "${WORKSPACE_LINK}"
fi

# ---------------------------------------------------------------------------
# Create the CloudCLI account once the server is listening
# ---------------------------------------------------------------------------
# Runs in the background because the server it talks to is started later in
# this same boot, by s6. CloudCLI is single-user: registration returns 403 once
# an account exists, so this is a no-op on every boot after the first.
create_account() {
    status=""
    for _ in $(seq 1 150); do
        status="$(curl -fsS --max-time 5 "http://127.0.0.1:${SERVER_PORT}/api/auth/status" 2>/dev/null || true)"
        case "${status}" in
            *needsSetup*) break ;;
        esac
        sleep 2
    done

    case "${status}" in
        *needsSetup*) ;;
        *)
            echo "[railway] WARNING: CloudCLI did not answer /api/auth/status in 5 minutes;"
            echo "[railway]          the account was not created. Check the service logs."
            return 0
            ;;
    esac

    case "${status}" in
        *'"needsSetup":false'*)
            echo "[railway] CloudCLI account already exists on the volume; leaving it alone."
            return 0
            ;;
    esac

    # The body is piped in rather than passed as an argument, so the password
    # never appears in the process table.
    if printf '{"username":"%s","password":"%s"}' \
            "${CLOUDCLI_USERNAME:-admin}" "${CLOUDCLI_PASSWORD}" \
       | curl -fsS --max-time 15 -o /dev/null \
              -X POST "http://127.0.0.1:${SERVER_PORT}/api/auth/register" \
              -H 'Content-Type: application/json' --data-binary @-; then
        echo "[railway] Created the CloudCLI account '${CLOUDCLI_USERNAME:-admin}'."
        echo "[railway] Its password is the CLOUDCLI_PASSWORD service variable."
    else
        echo "[railway] WARNING: could not create the CloudCLI account."
        echo "[railway]          Open the web UI and register manually, quickly."
    fi
}

create_account &

echo "[railway] state on the volume at ${STATE_DIR}; workspace -> ${WORKSPACE_TARGET}"

# Upstream's entrypoint does the UID/GID work, the persistence preflight, the
# first-boot bootstrap and finally `exec /init`.
exec /usr/local/bin/entrypoint.sh "$@"
