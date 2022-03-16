#!/usr/bin/env bash

set -o errexit -o noclobber -o nounset -o pipefail -o xtrace
shopt -s failglob inherit_errexit

postgresql_version="$1"
# shellcheck disable=SC2034
readonly postgresql_version

script_dir="$(dirname "${BASH_SOURCE[0]}")"
readonly script_dir

# shellcheck source=test/ci/install-latest.bash
. "${script_dir}/install-latest.bash"

dpkg --install "/packages/postgresql-${postgresql_version}-tableversion_"*.deb
# shellcheck disable=SC2154
make PREPAREDB_UPGRADE_FROM="$installed_package_version" installcheck-upgrade
