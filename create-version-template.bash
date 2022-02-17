#!/usr/bin/env bash

set -o errexit -o noclobber -o nounset -o pipefail -o xtrace
shopt -s failglob inherit_errexit

echo 'BEGIN;'
cat sql/noextension.sql.in
grep --fixed-strings --invert-match --regexp='CREATE EXTENSION' --regexp='pg_extension_config_dump'
echo 'COMMIT;'
