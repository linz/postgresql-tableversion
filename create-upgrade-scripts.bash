#!/usr/bin/env bash

set -o errexit -o noclobber -o nounset -o pipefail -o xtrace
shopt -s failglob inherit_errexit

path="$1"
extension="$2"
version="$3"
readonly path extension version
shift 3

output_directory='upgrade-scripts'
readonly output_directory
mkdir -p "$output_directory"

for old_version
do
    cp "$path" "${output_directory}/${extension}--${old_version}--${version}.sql"
done

# allow upgrading to same version (for same-version-but-different-revision)
cp "$path" "${output_directory}/${extension}--${version}--${version}next.sql"
cp "$path" "${output_directory}/${extension}--${version}next--${version}.sql"
