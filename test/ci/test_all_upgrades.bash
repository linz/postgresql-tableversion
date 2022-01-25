#!/usr/bin/env bash

cd "$(dirname "$0")/../../" || exit 1

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
)

tmp_install_dir_prefix=/tmp/table_version
mkdir -p "$tmp_install_dir_prefix" || exit 1

# Save current table_version
loader_bin="$(which table_version-loader)" || {
    echo "No table_version-loader found in PATH, did you run 'make install'?" >&2
    exit 1
}
cp -a "$loader_bin" "$tmp_install_dir_prefix" || exit 1

# Install all older versions
git clone . older-versions
cd older-versions || exit 1
for version in "${versions[@]}"
do
  echo "-------------------------------------"
  echo "Installing version ${version}"
  echo "-------------------------------------"
  git checkout . # revert local patches
  git checkout "$version" && git clean -dxf || exit 1
  # Workaround for Makefile bug which was fixed by
  # 2dee5082e0e89e4cf2430b566e8013ac1afd92be...
  sed -ie '/echo .*load this file/{s/echo /printf /;s|\\|\\\\|g}' Makefile
  # Since 1.4.0 we have a loader
  if test "$(echo "$version" | tr -d .)" -ge 140
  then
    tpl_install_dir="$(make install | grep tpl | tail -1 | sed "s/.* //;s/'$//;s/^'//")"
    test -n "$tpl_install_dir" || exit 1
    mkdir -p "${tmp_install_dir_prefix}/${version}/share" || exit 1
    cp -f "${tpl_install_dir}/"*.tpl "${tmp_install_dir_prefix}/${version}/share" || exit 1
  else
    make install || exit 1
  fi
done
cd ..
rm -rf older-versions

# Restore current table_version after installing/overriding new one
# (effectively moving to wherever will be found first)
cp -a "${tmp_install_dir_prefix}/table_version-loader" "$(which table_version-loader)" || exit 1

# Test upgrade from all older versions
for version in "${versions[@]}"
do
  echo "-------------------------------------"
  echo "Checking upgrade from version ${version}"
  echo "-------------------------------------"
  make installcheck-upgrade PREPAREDB_UPGRADE_FROM="$version" || exit 1
  # Since 1.4.0 we have a loader
  if test "$(echo "$version" | tr -d .)" -ge 140
  then
    make installcheck-loader-upgrade \
      PREPAREDB_UPGRADE_FROM="$version" \
      PREPAREDB_UPGRADE_FROM_EXT_DIR="${tmp_install_dir_prefix}/${version}/share" \
      || exit 1
    make installcheck-loader-upgrade-noext \
      PREPAREDB_UPGRADE_FROM="$version" \
      PREPAREDB_UPGRADE_FROM_EXT_DIR="${tmp_install_dir_prefix}/${version}/share" \
      || exit 1
  fi
done
