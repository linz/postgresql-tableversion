#!/bin/sh

cd `dirname $0`/../../

#
# Versions/tags known to build
# NOTE: tag 1.0.1 does not build, so we skip that
#
VER="1.1.0 1.1.1 1.1.2 1.1.3 1.2.0";

# Install all older versions
git clone . older-versions
cd older-versions
for v in $VER; do
  echo "Installing version $v"
  git checkout $v && git clean -dxf && sudo make install
done;
cd ..
rm -rf older-versions;

# Test upgrade from all older versions
for v in $VER; do
  echo "Checking upgrade from version $v"
  make installcheck-upgrade PREPAREDB_UPGRADE_FROM=$v || { cat regression.diffs; exit 1; }
done

