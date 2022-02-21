#!/usr/bin/env bash

set -o errexit -o noclobber -o nounset -o pipefail -o xtrace
shopt -s failglob inherit_errexit

printf '\echo Use "CREATE EXTENSION %s" to load this file. \quit\n' "$1"
shift

echo '---- TABLES -- '
grep '^CREATE TABLE' "$@" \
    | sed --expression='s/^CREATE /ALTER EXTENSION table_version ADD /' \
        --expression='s/ IF NOT EXISTS//' \
        --expression='s/(.*/;/'

echo '---- FUNCTIONS -- '
grep --after-context=10 '^CREATE OR REPLACE FUNCTION [^%]' "$@" \
    | tr '\n' '\r' \
    | sed \
        --expression='s/CREATE OR REPLACE/\nALTER EXTENSION table_version ADD/g' \
        --expression='s/ IF NOT EXISTS//g' \
        --expression='s/)[^\r]*\r/);\n/g' \
    | grep '^ALTER EXTENSION' \
    | sed \
        --expression='s/\r/ /g' \
        --expression='s/  */ /g' \
        --expression='s/ DEFAULT [^,)]*//g' \
        --expression='s/ = [^,)]*//g'
