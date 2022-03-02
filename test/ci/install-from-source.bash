#!/usr/bin/env bash

set -o errexit -o noclobber -o nounset -o pipefail -o xtrace
shopt -s failglob inherit_errexit

script_dir="$(dirname "${BASH_SOURCE[0]}")"

# shellcheck source=test/ci/setup-postgresql.bash
. "${script_dir}/setup-postgresql.bash" "$1"

make
make check
make install
make installcheck
make installcheck-loader
make installcheck-loader-noext
make uninstall
