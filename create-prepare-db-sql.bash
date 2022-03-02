#!/usr/bin/env bash

set -o errexit -o noclobber -o nounset -o pipefail -o xtrace
shopt -s failglob inherit_errexit

upgrade="$1"
upgrade_from="$2"
preparedb_noextension="$3"
extversion="$4"
readonly upgrade upgrade_from preparedb_noextension extversion

if [[ "$upgrade" -eq 1 ]]
then
    if [[ -n "$upgrade_from" ]]
    then
        replacement_upgrade_from="version '${upgrade_from}'"
    fi

    sed --expression='s/^--UPGRADE-- //' --expression="s/@@FROM_VERSION@@/${replacement_upgrade_from-}/"
elif [[ "$preparedb_noextension" -eq 1 ]]
then
    grep --invert-match table_version
else
    cat
fi | sed --expression="s/@@VERSION@@/${extversion}/" --expression='s/@@FROM_VERSION@@//'
