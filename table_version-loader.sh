#!/bin/sh

TGT_SCHEMA=table_version
TGT_DB=
EXT_MODE=on
EXT_NAME=table_version
EXT_DIR=`pg_config --sharedir`/extension/
TPL_FILE=
VER=

if test -n "$TABLE_VERSION_EXT_DIR"; then
  EXT_DIR="$TABLE_VERSION_EXT_DIR"
fi

while test -n "$1"; do
  if test "$1" = "--no-extension"; then
    EXT_MODE=off
  elif test "$1" = "--version"; then
    VER=$1; shift
  elif test -z "${TGT_DB}"; then
    TGT_DB=$1
  else
    echo "Unused argument $1" >&2
  fi
  shift
done

if test -z "${VER}"; then
# TPL_FILE is expected to have the following format:
#   table_version-1.4.0dev.sql.tpl
  VER=`ls ${EXT_DIR}/${EXT_NAME}-*.sql.tpl | sed "s/^.*${EXT_NAME}-//;s/\.sql\.tpl//" | tail -1`
  if test -z "${VER}"; then
    echo "Cannot find template loader, maybe set TABLE_VERSION_EXT_DIR?" >&2
    exit 1
  fi
fi

TPL_FILE=${EXT_DIR}/${EXT_NAME}-${VER}.sql.tpl


if test -z "$TGT_DB"; then
  echo "Usage: $0 [--no-extension] [--version <ver>] <dbname>" >&2
  exit 1
fi

export PGDATABASE=$TGT_DB

echo "Loading ver ${VER} in ${TGT_DB}.${TGT_SCHEMA} (EXT_MODE ${EXT_MODE})";

if test "${EXT_MODE}" = 'on'; then cat<<EOF | psql -tA --set ON_ERROR_STOP=1
  DO \$\$
    BEGIN
      IF EXISTS (
        SELECT * FROM pg_catalog.pg_class c, pg_catalog.pg_namespace n
        WHERE c.relnamespace = n.oid AND n.nspname = 'table_version'
        AND c.relname = 'revision'
      )
      THEN
        ALTER EXTENSION ${EXT_NAME} UPDATE TO '${VER}';
      ELSE
        CREATE EXTENSION ${EXT_NAME} VERSION '${VER}';
      END IF;
    END
  \$\$ LANGUAGE 'plpgsql';
EOF
else
  cat ${TPL_FILE} | sed "s/@extschema@/${TGT_SCHEMA}/g" |
  psql --set ON_ERROR_STOP=1 > /dev/null
fi
