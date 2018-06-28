#!/bin/sh

cd `dirname $0`/../../

#
# Versions/tags known to build
# NOTE: tag 1.0.1 does not build, so we skip that
#
VER="1.1.0 1.1.1 1.1.2 1.1.3 1.2.0 1.3.0 1.3.1 1.4.0 1.4.1 1.4.2 1.4.3";

TMP_INSTALL_DIR_PREFIX=/tmp/table_version
mkdir -p ${TMP_INSTALL_DIR_PREFIX} || exit 1

# Save current table_version
cp -a `which table_version-loader` ${TMP_INSTALL_DIR_PREFIX} || exit 1

# Install all older versions
git fetch --unshallow --tags # to get all commits/tags
git clone . older-versions
cd older-versions
for v in $VER; do
  echo "-------------------------------------"
  echo "Installing version $v"
  echo "-------------------------------------"
  git checkout $v && git clean -dxf || exit 1
  # Since 1.4.0 we have a loader
  if test `echo $v | tr -d .` -ge 140; then
    TPL_INSTALL_DIR=`make install | grep tpl | tail -1 | sed "s/.* //;s/'$//;s/^'//"`
    test -n "$TPL_INSTALL_DIR" || exit 1
    mkdir -p ${TMP_INSTALL_DIR_PREFIX}/${v}/share || exit 1
    cp -f ${TPL_INSTALL_DIR}/*.tpl ${TMP_INSTALL_DIR_PREFIX}/${v}/share || exit 1
  else
    make install || exit 1
  fi
done;
cd ..
rm -rf older-versions

# Restore current table_version after installing/overriding new one
# (effectively moving to wherever will be found first)
cp -a ${TMP_INSTALL_DIR_PREFIX}/table_version-loader `which table_version-loader` || exit 1

# Test upgrade from all older versions
for v in $VER; do
  echo "-------------------------------------"
  echo "Checking upgrade from version $v"
  echo "-------------------------------------"
  make installcheck-upgrade PREPAREDB_UPGRADE_FROM=$v || exit 1
  # Since 1.4.0 we have a loader
  if test `echo $v | tr -d .` -ge 140; then
    make installcheck-loader-upgrade \
      PREPAREDB_UPGRADE_FROM=$v \
      PREPAREDB_UPGRADE_FROM_EXT_DIR=${TMP_INSTALL_DIR_PREFIX}/${v}/share \
      || exit 1
    make installcheck-loader-upgrade-noext \
      PREPAREDB_UPGRADE_FROM=$v \
      PREPAREDB_UPGRADE_FROM_EXT_DIR=${TMP_INSTALL_DIR_PREFIX}/${v}/share \
      || exit 1
  fi
done

