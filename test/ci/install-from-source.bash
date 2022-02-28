#!/usr/bin/env bash

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
