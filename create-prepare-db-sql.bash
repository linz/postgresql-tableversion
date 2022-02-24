#!/usr/bin/env bash

set -o errexit -o noclobber -o nounset -o pipefail -o xtrace
shopt -s failglob inherit_errexit

upgrade_from="$1"
preparedb_noextension="$2"
extversion="$3"

if [[ -n "$upgrade_from" ]]
then
    sed --expression='s/^--UPGRADE-- //' --expression="s/@@FROM_VERSION@@/version '${upgrade_from}'/"
elif [[ "$preparedb_noextension" -eq 1 ]]
then
    grep --invert-match table_version
else
    cat
fi | sed --expression="s/@@VERSION@@/${extversion}/" --expression='s/@@FROM_VERSION@@//'
