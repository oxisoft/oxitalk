#!/usr/bin/env bash
# A private homeserver with MatrixRTC (LiveKit SFU + lk-jwt-service) for the call tests, in one
# rootless podman pod. Test only, throwaway data; nothing listens beyond 127.0.0.1.
#
#   test-infra/rtc/up.sh synapse NAME HS_PORT     # e.g. up.sh synapse calls 8040
#   test-infra/rtc/up.sh tuwunel NAME HS_PORT     # e.g. up.sh tuwunel calls 8041
#   OXITALK_TEST_HOMESERVER=http://localhost:HS_PORT cargo test -p oxitalk_core \
#       --test homeserver -- --ignored calls::
#   test-infra/rtc/down.sh NAME                   # removes the pod, its containers and volumes
#
# In the pod (shared localhost):
#   - the homeserver on :8008 (host 127.0.0.1:HS_PORT), server name `localhost`, advertising the
#     LiveKit transport http://localhost:8091 (MSC4143 rtc/transports);
#   - LiveKit on :7890 (signal), :7891/tcp and :7892/udp (media), the same ports on the host;
#   - lk-jwt-service 0.9.0 on :8091: OpenID token -> LiveKit JWT (/sfu/get);
#   - a TLS proxy on :8448 for the homeserver's /_matrix/federation/v1/openid/userinfo, which
#     lk-jwt-service asks at https://localhost:8448 (see openid-tls-proxy.py).
# The LiveKit ports are fixed, so one such pod runs at a time.
set -euo pipefail

server=${1:?synapse or tuwunel}
name=${2:?pod name}
hs_port=${3:?homeserver port on the host}
here=$(cd "$(dirname "$0")" && pwd)
infra=$(dirname "$here")
work=${TMPDIR:-/tmp}/oxitalk-rtc-$name
mkdir -p "$work"

image_of() { grep -m1 "image: .*$1" "$infra/compose.yaml" | sed 's/.*image: //'; }
livekit_image=docker.io/livekit/livekit-server:v1.13.11@sha256:25cd902de7cacbd5f1f779f6a6ac1eae20ba8f56b0935934ce6b0ab80d1e3d20
jwt_image=ghcr.io/element-hq/lk-jwt-service:0.9.0@sha256:d210fd778ba38b7e42e6fc64e8a24a7d66ccc3b938fb20d73bd713224af2dfea
synapse_image=$(image_of synapse)
tuwunel_image=$(image_of tuwunel)
transport_url=http://localhost:8091

podman pod create --name "$name" \
  -p "127.0.0.1:$hs_port:8008" \
  -p 127.0.0.1:7890:7890 -p 127.0.0.1:7891:7891 -p 127.0.0.1:7892:7892/udp \
  -p 127.0.0.1:8091:8091 >/dev/null

case "$server" in
  synapse)
    # The test config, plus: its public URL, the OpenID userinfo endpoint (resource `openid`)
    # and the MSC4143 transports (Synapse serves only the unstable path).
    sed -e "s|^public_baseurl:.*|public_baseurl: http://localhost:$hs_port/|" \
        -e 's|names: \[client\]|names: [client, openid]|' \
        "$infra/homeserver.yaml" >"$work/homeserver.yaml"
    cat >>"$work/homeserver.yaml" <<EOF
experimental_features:
  msc4143_enabled: true
matrix_rtc:
  transports:
    - type: livekit
      livekit_service_url: $transport_url
EOF
    podman run -d --pod "$name" --name "$name-synapse" \
      -v "$name-synapse-data:/data" \
      -v "$work/homeserver.yaml:/conf/homeserver.yaml:ro,z" \
      -v "$infra/start.sh:/conf/start.sh:ro,z" \
      -e SYNAPSE_CONFIG_PATH=/conf/homeserver.yaml \
      --entrypoint /conf/start.sh "$synapse_image" >/dev/null
    proxy_image=$synapse_image
    ;;
  tuwunel)
    cp "$infra/tuwunel.toml" "$work/tuwunel.toml"
    cat >>"$work/tuwunel.toml" <<EOF

[global.well_known]
livekit_url = "$transport_url"
EOF
    podman run -d --pod "$name" --name "$name-tuwunel" \
      -v "$name-tuwunel-data:/var/lib/tuwunel" \
      -v "$work/tuwunel.toml:/conf/tuwunel.toml:ro,z" \
      -e TUWUNEL_CONFIG=/conf/tuwunel.toml "$tuwunel_image" >/dev/null
    # Any image with Python 3 and openssl; the Synapse one is there already.
    proxy_image=$synapse_image
    ;;
  *)
    echo "unknown server: $server" >&2
    exit 2
    ;;
esac

podman run -d --pod "$name" --name "$name-openid-tls" \
  -v "$here/openid-tls-proxy.py:/proxy.py:ro,z" \
  --entrypoint python3 "$proxy_image" /proxy.py >/dev/null

podman run -d --pod "$name" --name "$name-livekit" \
  -v "$here/livekit.yaml:/livekit.yaml:ro,z" \
  "$livekit_image" --config /livekit.yaml >/dev/null

podman run -d --pod "$name" --name "$name-lk-jwt" \
  -e LIVEKIT_URL=ws://localhost:7890 \
  -e LIVEKIT_KEY=oxitalk-test-key \
  -e LIVEKIT_SECRET=oxitalk-test-only-livekit-secret-0123456789 \
  -e LIVEKIT_FULL_ACCESS_HOMESERVERS=localhost \
  -e LIVEKIT_JWT_BIND=0.0.0.0:8091 \
  -e LIVEKIT_INSECURE_SKIP_VERIFY_TLS=YES_I_KNOW_WHAT_I_AM_DOING \
  "$jwt_image" >/dev/null

# Ready when the homeserver answers.
for _ in $(seq 120); do
  if curl -fsS "http://localhost:$hs_port/_matrix/client/versions" >/dev/null 2>&1; then
    echo "$server up on http://localhost:$hs_port, LiveKit ws://localhost:7890, lk-jwt $transport_url"
    exit 0
  fi
  sleep 1
done
echo "homeserver did not come up; podman logs $name-$server" >&2
exit 1
