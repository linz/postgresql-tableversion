#!/usr/bin/env bash

set -o errexit -o noclobber -o nounset -o pipefail
shopt -s failglob inherit_errexit

printf '\echo Use "CREATE EXTENSION %s" to load this file. \quit\n' "$1"
shift

echo '---- TABLES -- '
grep '^CREATE TABLE' "$@" \
    | sed -e 's/^CREATE /ALTER EXTENSION table_version ADD /' \
        -e 's/ IF NOT EXISTS//' \
        -e 's/(.*/;/'

echo '---- FUNCTIONS -- '
grep -A10 '^CREATE OR REPLACE FUNCTION [^%]' "$@" \
    | tr '\n' '\r' \
    | sed \
        -e 's/CREATE OR REPLACE/\nALTER EXTENSION table_version ADD/g' \
        -e 's/ IF NOT EXISTS//g' \
        -e 's/)[^\r]*\r/);\n/g' \
    | grep '^ALTER EXTENSION' \
    | sed \
        -e 's/\r/ /g' \
        -e 's/  */ /g' \
        -e 's/ DEFAULT [^,)]*//g' \
        -e 's/ = [^,)]*//g'
