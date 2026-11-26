#!/usr/bin/env bash
# Manual (never in CI): a voice call between two app sessions over a REAL call deployment
# (apps/oxitalk/integration_test/call_prod_test.dart), e.g. chat.oxisoft.net + rtc.oxisoft.net.
#
#   scripts/call-prod.sh ALICE_ENV BOB_ENV
#
# Each env file holds the account as SERVER=, USER= (localpart), PASSWORD= lines (any prefix:
# the last `*SERVER=`, `*USER=`/`*USER_ID=` and `*PASSWORD=` lines count). Both accounts must be
# on the same homeserver; a new device is logged in for each and logged out at the end.
# The two sessions call each other in a DM: CALL_PROD_ROOM=<room id> to use one both are in,
# otherwise Alice creates a new DM with Bob (rings Bob's other devices too).
#   CALL_PROD_VERBOSE=1   livekit_client's log at ALL (signal, ICE, peer connections)
#   CALL_PROD_RACE=1      first a call that Alice ends while its media is still connecting
#
# Like call-e2e.sh: a fake microphone (440 Hz tone into a null sink, remapped as a source) and a
# silent output for the app only (PULSE_SOURCE/PULSE_SINK; the host's defaults stay), its own
# Xvfb and session bus. Logs: $CALL_PROD_OUT (default ${TMPDIR:-/tmp}/oxitalk-call-prod-<time>/).
set -euo pipefail

alice_env=${1:?alice env file}
bob_env=${2:?bob env file}
root=$(cd "$(dirname "$0")/.." && pwd)
out=${CALL_PROD_OUT:-${TMPDIR:-/tmp}/oxitalk-call-prod-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$out"
tag=oxi_prod_$$

# Reads a value from an env file without echoing it.
val() {
  sed -n "s/^[A-Z_]*$2=//p" "$1" | tail -1 | tr -d "\"'"
}
user() {
  local u
  u=$(val "$1" USER)
  [ -n "$u" ] || u=$(val "$1" USER_ID)
  u=${u#@}
  echo "${u%%:*}"
}
server=$(val "$alice_env" SERVER)
[ -n "$server" ] || server=${CALL_PROD_SERVER:?no SERVER= in $alice_env, set CALL_PROD_SERVER}

modules=()
ffmpeg_pid=
cleanup() {
  set +e
  [ -n "$ffmpeg_pid" ] && kill "$ffmpeg_pid" 2>/dev/null
  for ((i = ${#modules[@]} - 1; i >= 0; i--)); do pactl unload-module "${modules[i]}"; done
  echo "logs in $out"
}
trap cleanup EXIT

modules+=("$(pactl load-module module-null-sink sink_name="${tag}_tone" \
  sink_properties=device.description=oxitalk-prod-tone)")
modules+=("$(pactl load-module module-remap-source master="${tag}_tone.monitor" \
  source_name="${tag}_mic" source_properties=device.description=oxitalk-prod-mic)")
modules+=("$(pactl load-module module-null-sink sink_name="${tag}_out" \
  sink_properties=device.description=oxitalk-prod-out)")
ffmpeg -loglevel error -re -f lavfi -i sine=frequency=440:sample_rate=48000 \
  -f pulse -device "${tag}_tone" oxitalk-prod-tone >"$out/ffmpeg.log" 2>&1 &
ffmpeg_pid=$!

cd "$root/apps/oxitalk"
own_bus=()
command -v dbus-run-session >/dev/null && own_bus=(dbus-run-session --)
status=0
OXITALK_PROD_CALL=1 \
  OXITALK_PROD_SERVER=$server \
  OXITALK_PROD_ALICE_USER=$(user "$alice_env") \
  OXITALK_PROD_ALICE_PASSWORD=$(val "$alice_env" PASSWORD) \
  OXITALK_PROD_BOB_USER=$(user "$bob_env") \
  OXITALK_PROD_BOB_PASSWORD=$(val "$bob_env" PASSWORD) \
  OXITALK_PROD_ROOM=${CALL_PROD_ROOM:-} \
  OXITALK_PROD_VERBOSE=${CALL_PROD_VERBOSE:-0} \
  OXITALK_PROD_RACE=${CALL_PROD_RACE:-0} \
  OXITALK_PROD_DATA=$out/data \
  OXITALK_PROD_LOGS=$out/core \
  PULSE_SOURCE=${tag}_mic PULSE_SINK=${tag}_out \
  timeout 600 env -u WAYLAND_DISPLAY GDK_BACKEND=x11 \
  "${own_bus[@]}" xvfb-run -a flutter test integration_test/call_prod_test.dart -d linux 2>&1 |
  tee "$out/test.log" || status=$?
grep -q 'All tests passed!' "$out/test.log" || status=1
exit "$status"
