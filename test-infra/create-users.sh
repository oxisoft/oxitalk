#!/usr/bin/env bash
# Creates users on the running test homeserver; the password equals the user name.
# Usage: test-infra/create-users.sh alice bob ...   (COMPOSE defaults to "podman compose")
set -euo pipefail
cd "$(dirname "$0")"
for user in "$@"; do
  ${COMPOSE:-podman compose} exec -T synapse register_new_matrix_user \
    --config /conf/homeserver.yaml --user "$user" --password "$user" --no-admin \
    http://localhost:8008
done
