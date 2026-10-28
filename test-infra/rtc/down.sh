#!/usr/bin/env bash
# Removes a pod made by up.sh: its containers, its volumes and its generated configs.
set -uo pipefail
name=${1:?pod name}
podman pod rm -f "$name" >/dev/null 2>&1
podman volume rm -f "$name-synapse-data" "$name-tuwunel-data" >/dev/null 2>&1
rm -rf "${TMPDIR:-/tmp}/oxitalk-rtc-$name"
echo "removed $name"
