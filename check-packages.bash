#!/usr/bin/env bash

set -o errexit -o noclobber -o nounset -o pipefail -o xtrace
shopt -s failglob inherit_errexit

cleanup() {
    rm --force --recursive "$working_dir"
}
trap cleanup EXIT
working_dir="$(mktemp --directory)"
readonly working_dir

contains_loader() {
    local package_contents
    package_contents="${working_dir}/package_contents.txt"
    set +o noclobber
    dpkg --contents "$1" > "$package_contents"
    set -o noclobber
    grep --quiet loader "$package_contents"
}

for postgres_specific_package in build-area/postgresql-*tableversion_*.deb
do
    if contains_loader "$postgres_specific_package"
    then
        echo "Package $postgres_specific_package contains loader" >&2
        exit 1
    fi
done

# Test postgresql-agnostic package DOES contain loader
for postgres_agnostic_package in build-area/tableversion_*.deb
do
    if ! contains_loader "$postgres_agnostic_package"
    then
        echo "Package $postgres_agnostic_package does NOT contain loader" >&2
        exit 1
    fi
done
