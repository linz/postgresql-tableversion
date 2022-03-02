#!/usr/bin/env bash

set -o errexit -o noclobber -o nounset -o pipefail -o xtrace
shopt -s failglob inherit_errexit

postgresql_version="$1"
# shellcheck disable=SC2034
readonly postgresql_version

script_dir="$(dirname "${BASH_SOURCE[0]}")"
readonly script_dir

# shellcheck source=test/ci/setup-postgresql.bash
. "${script_dir}/setup-postgresql.bash"

make
make check
make install
make installcheck
make installcheck-loader
make installcheck-loader-noext
make uninstall
