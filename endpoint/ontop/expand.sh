#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$script_dir/namespaces.sh"
# Substitute only namespace variables; preserve SQL and other dollar expressions.
exec envsubst '${NS_GLOBAL_O} ${NS_GLOBAL_R} ${NS_TIVA_O} ${NS_TIVA_R}' "$@"
