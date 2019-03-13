#!/bin/sh

TGT_SCHEMA=table_version
TGT_DB=
EXT_MODE=on
EXT_NAME=table_version
EXT_DIR=@@LOCAL_SHAREDIR@@
TPL_FILE=
VER=

if test -n "$TABLE_VERSION_EXT_DIR"; then
  EXT_DIR="$TABLE_VERSION_EXT_DIR"
fi

while test -n "$1"; do
  if test "$1" = "--no-extension"; then
    EXT_MODE=off
  elif test "$1" = "--version"; then
    shift; VER=$1
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

if test -z "$TGT_DB"; then
  echo "Usage: $0 [--no-extension] [--version <ver>] { <dbname> | - }" >&2
  exit 1
fi

DBLBL=${TGT_DB}
if [ "$DBLBL" = "-" ]; then
    DBLBL="(stdout)"
fi
echo "Loading ver ${VER} in ${DBLBL}.${TGT_SCHEMA} (EXT_MODE ${EXT_MODE})" >&2

{

if test "${EXT_MODE}" = 'on'; then cat<<EOF
  DO \$\$
    BEGIN
      IF EXISTS (
        SELECT * FROM pg_catalog.pg_class c, pg_catalog.pg_namespace n
        WHERE c.relnamespace = n.oid AND n.nspname = 'table_version'
        AND c.relname = 'revision'
      )
      THEN
        IF EXISTS (
            SELECT * FROM pg_catalog.pg_extension
            WHERE extname = 'table_version'
        )
        THEN
            ALTER EXTENSION ${EXT_NAME} UPDATE TO '${VER}';
        ELSE
            CREATE EXTENSION ${EXT_NAME} VERSION '${VER}'
            FROM unpackaged;
        END IF;
      ELSE
        CREATE EXTENSION ${EXT_NAME} VERSION '${VER}';
      END IF;
    END
  \$\$ LANGUAGE 'plpgsql';
EOF
else
  TPL_FILE=${EXT_DIR}/${EXT_NAME}-${VER}.sql.tpl
  if test -r ${TPL_FILE}; then
    echo "Using template file ${TPL_FILE}" >&2
    cat ${TPL_FILE} | sed "s/@extschema@/${TGT_SCHEMA}/g"
  else
    echo "Template file ${TPL_FILE} is not readable or does not exist" >&2
    exit 1
  fi
fi

} | if [ "$TGT_DB" = "-" ]; then
    cat
else
    psql -XtA --set ON_ERROR_STOP=1 $TGT_DB -o /dev/null
fi
