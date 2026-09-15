# HolyClaude on Railway — https://github.com/CoderLuii/HolyClaude
#
# Upstream publishes multi-arch images and expects a Docker Compose host: bind
# mounts for state, a localhost-only port, and a human who creates the CloudCLI
# account in the browser. Railway gives a single volume, a public domain and an
# IPv6 private network, so this image is a thin wrapper that adapts those three
# things and changes nothing else.
ARG HOLYCLAUDE_VERSION=1.6.1
FROM coderluii/holyclaude:${HOLYCLAUDE_VERSION}

# The base image ends as root and drops to the `claude` user itself, through
# s6-overlay (`s6-setuidgid claude cloudcli`). Keep that: the entrypoint needs
# root to chown the volume, and dropping privileges here would break it.
USER root

# curl is already present (the upstream HEALTHCHECK uses it); it is what creates
# the CloudCLI account from inside the container.

# PORT is 3001 by default and is honoured for real: the service script below is
# upstream's with `--port "${PORT:-3001}"` in place of the literal. Railway's
# healthcheck probes whatever PORT names, so the two must not drift apart.
#
# CLOUDCLI_USERNAME is baked rather than declared as a template variable:
# template generation nulls literal defaults into required fields, which would
# make the deploy form ask someone to type "admin". Override it by adding the
# variable to the service if you want a different name.
#
# HOST=:: makes Node bind dual-stack, so the service answers on both Railway's
# public edge (IPv4) and the private network (IPv6).
#
# DATABASE_PATH moves CloudCLI's SQLite database onto the volume. Upstream's
# loader only fills this in when it is unset, so setting it here wins. That
# database holds the account, the provider credentials entered in the web UI,
# and the auto-generated JWT secret — which is why sessions survive a redeploy.
ENV PORT=3001 \
    HOST=:: \
    CLOUDCLI_USERNAME=admin \
    CLAUDE_STATE_DIR=/home/claude/.claude \
    DATABASE_PATH=/home/claude/.claude/.cloudcli/auth.db

COPY --chmod=755 entrypoint.sh /usr/local/bin/railway-entrypoint

# Upstream's service script runs `cloudcli --port 3001` literally. Railway's
# healthcheck probes the port named by the PORT variable, so the server has to
# follow it or every deploy fails its healthcheck while the app is listening
# perfectly well on 3001. This is upstream's script with that one change.
COPY --chmod=755 s6-overlay/s6-rc.d/cloudcli/run /etc/s6-overlay/s6-rc.d/cloudcli/run

EXPOSE 3001

# Hands off to upstream's own entrypoint, which ends with `exec /init` and makes
# s6-overlay PID 1.
ENTRYPOINT ["/usr/local/bin/railway-entrypoint"]
