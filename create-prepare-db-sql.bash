#!/usr/bin/env bash

set -o errexit -o noclobber -o nounset -o pipefail -o xtrace
shopt -s failglob inherit_errexit

upgrade="$1"
upgrade_from="$2"
preparedb_noextension="$3"
extversion="$4"

if [[ "$upgrade" -eq 1 ]]
then
    if [[ -n "$upgrade_from" ]]
    then
        upgrade_from="version '${upgrade_from}'"
    fi

    sed -e 's/^--UPGRADE-- //' -e "s/@@FROM_VERSION@@/${upgrade_from-}/"
elif [[ "$preparedb_noextension" -eq 1 ]]
then
    grep -v table_version
else
    cat
fi | sed -e "s/@@VERSION@@/${extversion}/" -e 's/@@FROM_VERSION@@//'
