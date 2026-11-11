#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# Respect an explicitly supplied external mapping file.
if [ "${ONTOP_MAPPING_FILE:-}" = "/tmp/provider-tiva.r2rml.ttl" ]; then
    rendered=$(mktemp /tmp/provider-tiva.XXXXXX)
    trap 'rm -f "$rendered"' EXIT HUP INT TERM
    sh "$script_dir/expand.sh" < "$script_dir/tiva.r2rml.ttl.in" > "$rendered"
    mv "$rendered" "$ONTOP_MAPPING_FILE"
    trap - EXIT HUP INT TERM
fi
exec /opt/ontop/entrypoint.sh "$@"
