#!/bin/sh

cd `dirname $0`/../../

#
# Versions/tags known to build
# NOTE: tag 1.0.1 does not build, so we skip that
#
VER="1.1.0 1.1.1 1.1.2 1.1.3 1.2.0";

TMP_INSTALL_DIR_PREFIX=/tmp/table_version

# Install all older versions
git fetch --unshallow --tags # to get all commits/tags
git clone . older-versions
cd older-versions
for v in $VER; do
  echo "-------------------------------------"
  echo "Installing version $v"
  echo "-------------------------------------"
  git checkout $v && git clean -dxf && make install || exit 1
  mkdir -p ${TMP_INSTALL_DIR_PREFIX}/${v}/share
  cp -a /usr/local/share/table_version/* ${TMP_INSTALL_DIR_PREFIX}/${v}/share
done;
cd ..
rm -rf older-versions

# Test upgrade from all older versions
for v in $VER; do
  echo "-------------------------------------"
  echo "Checking upgrade from version $v"
  echo "-------------------------------------"
  make installcheck-upgrade PREPAREDB_UPGRADE_FROM=$v || exit 1
  # Since 1.4.0 we have a loader
  make installcheck-loader-upgrade \
    PREPAREDB_UPGRADE_FROM=$v \
    PREPAREDB_UPGRADE_FROM_EXT_DIR=${TMP_INSTALL_DIR_PREFIX}/${v}/share \
    || exit 1
  make installcheck-loader-upgrade-noext \
    PREPAREDB_UPGRADE_FROM=$v \
    PREPAREDB_UPGRADE_FROM_EXT_DIR=${TMP_INSTALL_DIR_PREFIX}/${v}/share \
    || exit 1
done

