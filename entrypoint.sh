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
SETUP_PORT="${CLOUDCLI_SETUP_PORT:-3999}"

# ---------------------------------------------------------------------------
# Fail closed on a missing password
# ---------------------------------------------------------------------------
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
# Claim the CloudCLI account before anything is reachable
# ---------------------------------------------------------------------------
# CloudCLI is single-user: the first POST /api/auth/register creates the
# account and every later one is refused with 403. Behind a Compose file bound
# to 127.0.0.1 that is a fine first run. On a public Railway domain it is a
# land grab — whoever reaches the URL first owns a machine holding the
# deployer's Anthropic session.
#
# Registering in the background while the real server starts is NOT enough:
# there is a window between the server listening (which is also when Railway's
# healthcheck passes and the edge starts routing) and the account existing, and
# that window is wide enough to lose. So the account is created here, against a
# throwaway instance bound to loopback only, before the public server is ever
# started. This phase has to succeed: an exposed CloudCLI with no account is
# exactly the state this template exists to prevent.
seed_account() {
    local pid status body

    # Loopback-only, on a port nothing else uses, as the runtime user so the
    # database file lands with the right ownership.
    runuser -u claude -- env \
        HOME=/home/claude \
        HOST=127.0.0.1 \
        DATABASE_PATH="${CLOUDCLI_STATE}/auth.db" \
        cloudcli --port "${SETUP_PORT}" >/tmp/cloudcli-setup.log 2>&1 &
    pid=$!

    status=""
    for _ in $(seq 1 90); do
        if ! kill -0 "${pid}" 2>/dev/null; then
            echo "FATAL: the setup instance of CloudCLI exited before it was ready." >&2
            tail -20 /tmp/cloudcli-setup.log >&2 || true
            exit 1
        fi
        status="$(curl -fsS --max-time 5 "http://127.0.0.1:${SETUP_PORT}/api/auth/status" 2>/dev/null || true)"
        case "${status}" in *needsSetup*) break ;; esac
        sleep 1
    done

    case "${status}" in
        *'"needsSetup":false'*)
            echo "[railway] CloudCLI account already exists on the volume; leaving it alone."
            ;;
        *needsSetup*)
            # The body is piped in rather than passed as an argument, so the
            # password never appears in the process table.
            if body="$(printf '{"username":"%s","password":"%s"}' \
                          "${CLOUDCLI_USERNAME:-admin}" "${CLOUDCLI_PASSWORD}" \
                       | curl -fsS --max-time 20 \
                              -X POST "http://127.0.0.1:${SETUP_PORT}/api/auth/register" \
                              -H 'Content-Type: application/json' --data-binary @-)"; then
                echo "[railway] Created the CloudCLI account '${CLOUDCLI_USERNAME:-admin}'."
                echo "[railway] Its password is the CLOUDCLI_PASSWORD service variable."
            else
                echo "FATAL: could not create the CloudCLI account." >&2
                echo "  Refusing to start the public server with an unclaimed account." >&2
                kill -TERM "${pid}" 2>/dev/null || true
                exit 1
            fi
            ;;
        *)
            echo "FATAL: the setup instance of CloudCLI never answered /api/auth/status." >&2
            tail -20 /tmp/cloudcli-setup.log >&2 || true
            kill -TERM "${pid}" 2>/dev/null || true
            exit 1
            ;;
    esac

    kill -TERM "${pid}" 2>/dev/null || true
    wait "${pid}" 2>/dev/null || true
    rm -f /tmp/cloudcli-setup.log
}

seed_account

echo "[railway] state on the volume at ${STATE_DIR}; workspace -> ${WORKSPACE_TARGET}"

# Upstream's entrypoint does the UID/GID work, the persistence preflight, the
# first-boot bootstrap and finally `exec /init`.
exec /usr/local/bin/entrypoint.sh "$@"
