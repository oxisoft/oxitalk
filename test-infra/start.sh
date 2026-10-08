#!/bin/sh
# The image's run mode expects a writable /data with the signing key already in it: create
# both as Synapse's user (991, as /start.py runs it), then start.
set -eu
chown -R 991:991 /data
gosu 991:991 python -m synapse.app.homeserver --config-path "$SYNAPSE_CONFIG_PATH" \
  --keys-directory /data --generate-keys
exec /start.py run
