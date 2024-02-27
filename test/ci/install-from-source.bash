#!/usr/bin/env bash

set -o errexit -o noclobber -o nounset -o pipefail -o xtrace
shopt -s failglob inherit_errexit

make
make check
make install
make installcheck
make installcheck-loader
make installcheck-loader-noext
make uninstall
