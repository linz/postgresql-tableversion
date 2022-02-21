#!/usr/bin/env bash

tgt_schema=table_version
tgt_db=
ext_mode=on
ext_name=table_version
ext_dir=@@LOCAL_SHAREDIR@@
tpl_file=
ver=

if test -n "$TABLE_VERSION_EXT_DIR"
then
  ext_dir="$TABLE_VERSION_EXT_DIR"
fi

while test -n "$1"
do
  if test "$1" = "--no-extension"
  then
    ext_mode=off
  elif test "$1" = "--version"
  then
    shift
    ver=$1
  elif test -z "${tgt_db}"
  then
    tgt_db=$1
  else
    echo "Unused argument $1" >&2
  fi
  shift
done

if test -z "${ver}"
then
# tpl_file is expected to have the following format:
#   table_version-1.4.0dev.sql.tpl
  ver="$(echo "${ext_dir}/${ext_name}"-*.sql.tpl | sed "s/^.*${ext_name}-//;s/\.sql\.tpl//" | sort --version-sort | tail --lines=1)"
  if test -z "${ver}"
  then
    echo "Cannot find template loader, maybe set TABLE_VERSION_EXT_DIR?" >&2
    exit 1
  fi
fi

if test -z "$tgt_db"
then
  echo "Usage: $0 [--no-extension] [--version <ver>] { <dbname> | - }" >&2
  exit 1
fi

dblbl=${tgt_db}
if [ "$dblbl" = "-" ]
then
    dblbl="(stdout)"
fi
echo "Loading ${ext_name} ${ver} in ${dblbl}.${tgt_schema} (ext_mode ${ext_mode})" >&2

{

if test "${ext_mode}" = 'on'
then cat<<EOF
  DO \$\$
    DECLARE
        OLDVER TEXT;
    BEGIN
      IF EXISTS (
        SELECT * FROM pg_catalog.pg_class c, pg_catalog.pg_namespace n
        WHERE c.relnamespace = n.oid AND n.nspname = 'table_version'
        AND c.relname = 'revision'
      )
      THEN
        SELECT extversion FROM pg_catalog.pg_extension
            WHERE extname = 'table_version'
            INTO OLDVER;
        IF OLDVER IS NOT NULL
        THEN
            IF OLDVER = '${ver}' THEN
                ALTER EXTENSION ${ext_name} UPDATE TO '${ver}next';
            END IF;
            ALTER EXTENSION ${ext_name} UPDATE TO '${ver}';
        ELSE
            CREATE EXTENSION ${ext_name} VERSION '${ver}';
        END IF;
      ELSE
        CREATE EXTENSION ${ext_name} VERSION '${ver}';
      END IF;
    END
  \$\$ LANGUAGE 'plpgsql';
EOF
else
  tpl_file=${ext_dir}/${ext_name}-${ver}.sql.tpl
  if test -r "$tpl_file"
  then
    echo "Using template file ${tpl_file}" >&2
    sed "s/@extschema@/${tgt_schema}/g" "$tpl_file"
  else
    echo "Template file ${tpl_file} is not readable or does not exist" >&2
    exit 1
  fi
fi

} | if [ "$tgt_db" = "-" ]
then
    cat
else
    psql -XtA --set ON_ERROR_STOP=1 "$tgt_db" -o /dev/null
fi
