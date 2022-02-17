#!/usr/bin/env bash

set -o errexit -o noclobber -o nounset -o pipefail
shopt -s failglob inherit_errexit

printf '\echo Use "CREATE EXTENSION %s" to load this file. \quit\n' "$1"
shift

cat "$@"

echo "GRANT USAGE ON SCHEMA table_version TO public;"
