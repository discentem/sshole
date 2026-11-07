#!/bin/sh
# Rebuild and run the PoC container from a clean slate, verifying it's
# actually this build before attacking it — guards against a stale/unrelated
# container or image silently squatting the name or port from a past run.
set -eu
NAME=sshole-poc
PORT=2222
EXPECT_PKG='openssh-server-10.3_p1-r1'
# override the Alpine base to test another musl-based image, e.g.:
#   BASE=alpine:3.21 ./repro.sh
BASE=${BASE:-alpine:latest}

# 1. kill anything already using this name OR this published port, by
#    container ID (not just name) so a renamed/retagged leftover can't hide.
#    podman has no "publish" ps filter (that's docker-only), so match the
#    port via inspect instead.
port_ids=$(podman ps -aq | while read -r id; do
  podman inspect "$id" --format '{{range $p,$v := .NetworkSettings.Ports}}{{range $v}}{{.HostPort}} {{end}}{{end}}' 2>/dev/null \
    | tr ' ' '\n' | grep -qx "$PORT" && echo "$id"
done)
for id in $(podman ps -aq --filter "name=^${NAME}$") $port_ids; do
  echo "killing stale container $id"
  podman rm -f "$id" >/dev/null
done

# 2. rebuild fresh (forces linux/amd64 since this Dockerfile has no platform
#    pin and defaults to the host arch, which fails on arm64 — see README).
podman build --platform=linux/amd64 --build-arg BASE="$BASE" -t "$NAME" .

# 3. run it
podman run -d --rm --platform=linux/amd64 --name "$NAME" \
  -p "127.0.0.1:${PORT}:22" "$NAME" \
  /usr/sbin/sshd -D -e -o PermitRootLogin=yes

# 4. assert it's actually the vulnerable build before trusting any attack
#    result against it — fail loudly instead of silently testing the wrong
#    container. `apk list --installed` is purely local (no network); unlike
#    `apk info -a`, which tries to refresh the APKINDEX and can hang for a
#    long time if gvproxy's DNS is flaky — timeout as a backstop regardless.
got_pkg=$(timeout 10 podman exec "$NAME" sh -c "apk list --installed 2>/dev/null | grep '^openssh-server-[0-9]'") || {
  echo "FATAL: version check timed out or failed" >&2
  podman rm -f "$NAME" >/dev/null
  exit 1
}
case "$got_pkg" in
  "$EXPECT_PKG "*) ;;
  *)
    echo "FATAL: running container is not the expected build (got: $got_pkg)" >&2
    podman rm -f "$NAME" >/dev/null
    exit 1
    ;;
esac
echo "verified: $NAME is running $EXPECT_PKG"
