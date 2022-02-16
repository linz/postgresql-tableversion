#!/usr/bin/env bash

set -o errexit -o noclobber -o nounset -o pipefail
shopt -s failglob inherit_errexit

project_root="$(dirname "$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")")"

#
# Versions/tags known to build
# NOTE: tag 1.0.1 does not build, so we skip that
#
versions=(
    '1.1.0'
    '1.1.1'
    '1.1.2'
    '1.1.3'
    '1.2.0'
    '1.3.0'
    '1.3.1'
    '1.4.0'
    '1.4.1'
    '1.4.2'
    '1.4.3'
    '1.5.0'
    '1.7.0'
)

trap 'rm -r "$work_directory"' EXIT
work_directory="$(mktemp --directory)"
tmp_install_dir_prefix="${work_directory}/table_version"
mkdir -p "$tmp_install_dir_prefix"

# Save current table_version
loader_bin="$(which table_version-loader)"
cp -a "$loader_bin" "$tmp_install_dir_prefix"

# Install all older versions
project_copy="${work_directory}/copy"
git clone "$project_root" "$project_copy"
cd "$project_copy"
for version in "${versions[@]}"
do
    echo "-------------------------------------"
    echo "Installing version ${version}"
    echo "-------------------------------------"
    git checkout . # revert local patches
    git checkout "$version"
    git clean -dxf
    # Workaround for Makefile bug which was fixed by
    # 2dee5082e0e89e4cf2430b566e8013ac1afd92be...
    sed -ie '/echo .*load this file/{s/echo /printf /;s|\\|\\\\|g}' Makefile
    # Since 1.4.0 we have a loader
    if test "$(echo "$version" | tr -d .)" -ge 140
    then
        tpl_install_dir="$(make install | grep tpl | tail -1 | sed "s/.* //;s/'$//;s/^'//")"
        test -n "$tpl_install_dir"
        mkdir -p "${tmp_install_dir_prefix}/${version}/share"
        cp -f "${tpl_install_dir}/"*.tpl "${tmp_install_dir_prefix}/${version}/share"
    else
        make install
    fi
done
cd -

# Restore current table_version after installing/overriding new one
# (effectively moving to wherever will be found first)
cp -a "${tmp_install_dir_prefix}/table_version-loader" "$(which table_version-loader)"

# Test upgrade from all older versions
for version in "${versions[@]}"
do
    echo "-------------------------------------"
    echo "Checking upgrade from version ${version}"
    echo "-------------------------------------"
    make installcheck-upgrade PREPAREDB_UPGRADE_FROM="$version"
    # Since 1.4.0 we have a loader
    if test "$(echo "$version" | tr -d .)" -ge 140
    then
        make installcheck-loader-upgrade \
            PREPAREDB_UPGRADE_FROM="$version" \
            PREPAREDB_UPGRADE_FROM_EXT_DIR="${tmp_install_dir_prefix}/${version}/share"
        make installcheck-loader-upgrade-noext \
            PREPAREDB_UPGRADE_FROM="$version" \
            PREPAREDB_UPGRADE_FROM_EXT_DIR="${tmp_install_dir_prefix}/${version}/share"
    fi
done
