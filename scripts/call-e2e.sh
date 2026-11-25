#!/usr/bin/env bash
# The end-to-end voice call test (apps/oxitalk/integration_test/call_test.dart) on Linux:
# two app sessions call each other through a real LiveKit SFU, with frame encryption.
#
#   scripts/call-e2e.sh [synapse|tuwunel] [HS_PORT]      # default: synapse 8046
#   CALL_E2E_TONE=0 scripts/call-e2e.sh ...               # a silent microphone: the sound
#                                                         # checks must fail (negative check)
#
# Brings up the RTC test pod (test-infra/rtc/up.sh; LiveKit ports are fixed, so only one such
# pod at a time on a host), a fake microphone for this run only (a 440 Hz tone into a PulseAudio
# null sink, remapped as a source) and a silent output sink, so no real microphone is opened
# and nothing plays on the speakers; the app process gets them through PULSE_SOURCE/PULSE_SINK
# (the host's default devices are not changed). Runs the test under its own Xvfb, then saves
# the LiveKit and lk-jwt-service logs and tears everything down again.
#
# Needs: podman, pactl (PulseAudio or PipeWire-pulse), ffmpeg, xvfb-run, Flutter.
# Logs: $CALL_E2E_OUT (default ${TMPDIR:-/tmp}/oxitalk-call-e2e-<server>-<time>/).
set -euo pipefail

server=${1:-synapse}
hs_port=${2:-8046}
root=$(cd "$(dirname "$0")/.." && pwd)
pod=call-e2e-$server
out=${CALL_E2E_OUT:-${TMPDIR:-/tmp}/oxitalk-call-e2e-$server-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$out"
tag=oxi_e2e_$$

modules=()
ffmpeg_pid=
watcher_pid=
cleanup() {
  set +e
  [ -n "$watcher_pid" ] && kill "$watcher_pid" 2>/dev/null
  [ -n "$ffmpeg_pid" ] && kill "$ffmpeg_pid" 2>/dev/null
  for ((i = ${#modules[@]} - 1; i >= 0; i--)); do pactl unload-module "${modules[i]}"; done
  if podman pod exists "$pod" 2>/dev/null; then
    for c in livekit lk-jwt "$server"; do
      podman logs "$pod-$c" >"$out/$c.log" 2>&1
    done
    "$root/test-infra/rtc/down.sh" "$pod" >/dev/null 2>&1
  fi
  echo "logs in $out"
}
trap cleanup EXIT

"$root/test-infra/rtc/up.sh" "$server" "$pod" "$hs_port"

# The fake microphone and a silent speaker, for this run only.
modules+=("$(pactl load-module module-null-sink sink_name="${tag}_tone" \
  sink_properties=device.description=oxitalk-e2e-tone)")
modules+=("$(pactl load-module module-remap-source master="${tag}_tone.monitor" \
  source_name="${tag}_mic" source_properties=device.description=oxitalk-e2e-mic)")
modules+=("$(pactl load-module module-null-sink sink_name="${tag}_out" \
  sink_properties=device.description=oxitalk-e2e-out)")
if [ "${CALL_E2E_TONE:-1}" != 0 ]; then
  ffmpeg -loglevel error -re -f lavfi -i sine=frequency=440:sample_rate=48000 \
    -f pulse -device "${tag}_tone" oxitalk-e2e-tone >"$out/ffmpeg.log" 2>&1 &
  ffmpeg_pid=$!
fi
mic=$(pactl list short sources | awk -v n="${tag}_mic" '$2 == n { print $1 }')

# Which source the app records from, every second (checked below: only the fake one).
(
  while :; do
    pactl list source-outputs | awk '
      /^Source Output/ { so = $3 } /^\tSource:/ { src = $2 }
      /application.process.binary/ { print so, src, $3 }'
    sleep 1
  done
) >"$out/pulse.log" 2>&1 &
watcher_pid=$!

cd "$root/apps/oxitalk"
status=0
# The Linux app is a unique GApplication: on the user's session bus, an OxiTalk already
# running there takes the test app's launch and the test can't start ("Unable to start the
# app on the device"). A session bus of its own for the test, when there is dbus-run-session.
own_bus=()
command -v dbus-run-session >/dev/null && own_bus=(dbus-run-session --)
OXITALK_TEST_RTC=1 \
  OXITALK_TEST_HOMESERVER=http://localhost:$hs_port \
  OXITALK_CALL_E2E_LOGS=$out/core \
  PULSE_SOURCE=${tag}_mic PULSE_SINK=${tag}_out \
  timeout 900 env -u WAYLAND_DISPLAY GDK_BACKEND=x11 \
  "${own_bus[@]}" xvfb-run -a flutter test integration_test/call_test.dart -d linux 2>&1 |
  tee "$out/test.log" || status=$?
kill "$watcher_pid" 2>/dev/null || true
# tee hides flutter's status: read it from the result line.
grep -q 'All tests passed!' "$out/test.log" || status=1
# The app recorded, and only from the fake microphone (never a real one on the host).
# (4294967295: a stream not linked to a source yet or any more.)
recorded=$(awk '$3 == "\"oxitalk\"" && $2 != "4294967295" { print $2 }' "$out/pulse.log" | sort -u)
if [ -z "$recorded" ]; then
  echo "the app never recorded (see $out/pulse.log)" >&2
  status=1
elif [ "$recorded" != "$mic" ]; then
  echo "the app recorded from sources '$recorded', not only the fake microphone $mic" >&2
  status=1
else
  echo "the app recorded from the fake microphone only (source $mic)"
fi
exit "$status"
