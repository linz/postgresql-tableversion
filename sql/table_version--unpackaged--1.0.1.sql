--------------------------------------------------------------------------------

-- postgresql-table_version - PostgreSQL database patch change management extension
--
-- Copyright 2016 Crown copyright (c)
-- Land Information New Zealand and the New Zealand Government.
-- All rights reserved
--
-- This software is released under the terms of the new BSD license. See the 
-- LICENSE file for more information.
--
--------------------------------------------------------------------------------

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION table_version FROM unpackaged" to load this file. \quit

ALTER EXTENSION table_version ADD TABLE @extschema@.revision;
ALTER EXTENSION table_version ADD TABLE @extschema@.tables_changed;
ALTER EXTENSION table_version ADD TABLE @extschema@.versioned_tables;

ALTER EXTENSION table_version ADD SEQUENCE @extschema@.revision_id_seq;
ALTER EXTENSION table_version ADD SEQUENCE @extschema@.versioned_tables_id_seq;

ALTER EXTENSION table_version ADD FUNCTION @extschema@.ver_complete_revision();
ALTER EXTENSION table_version ADD FUNCTION @extschema@.ver_create_revision(TEXT,TIMESTAMP,BOOLEAN);
ALTER EXTENSION table_version ADD FUNCTION @extschema@.ver_create_table_functions(NAME,NAME,NAME);
ALTER EXTENSION table_version ADD FUNCTION @extschema@.ver_create_version_trigger(NAME,NAME,NAME);
ALTER EXTENSION table_version ADD FUNCTION @extschema@.ver_delete_revision(INTEGER);
ALTER EXTENSION table_version ADD FUNCTION @extschema@.ver_disable_versioning(NAME,NAME);
ALTER EXTENSION table_version ADD FUNCTION @extschema@.ver_enable_versioning(NAME,NAME);
ALTER EXTENSION table_version ADD FUNCTION @extschema@.ver_expandtemplate(TEXT,TEXT[]);
ALTER EXTENSION table_version ADD FUNCTION @extschema@._ver_get_diff_function(NAME,NAME);
ALTER EXTENSION table_version ADD FUNCTION @extschema@.ver_get_last_revision();
ALTER EXTENSION table_version ADD FUNCTION @extschema@.ver_get_modified_tables(INTEGER);
ALTER EXTENSION table_version ADD FUNCTION @extschema@.ver_get_modified_tables(INTEGER,INTEGER);
ALTER EXTENSION table_version ADD FUNCTION @extschema@._ver_get_reversion_temp_table(NAME);
ALTER EXTENSION table_version ADD FUNCTION @extschema@._ver_get_revision_function(NAME,NAME);
ALTER EXTENSION table_version ADD FUNCTION @extschema@.ver_get_revision(INTEGER);
ALTER EXTENSION table_version ADD FUNCTION @extschema@.ver_get_revisions(INTEGER[]);
ALTER EXTENSION table_version ADD FUNCTION @extschema@.ver_get_revisions(TIMESTAMP,TIMESTAMP);
ALTER EXTENSION table_version ADD FUNCTION @extschema@.ver_get_revision(TIMESTAMP);
ALTER EXTENSION table_version ADD FUNCTION @extschema@.ver_get_table_base_revision(NAME,NAME);
ALTER EXTENSION table_version ADD FUNCTION @extschema@._ver_get_table_cols(NAME,NAME);
ALTER EXTENSION table_version ADD FUNCTION @extschema@.ver_get_table_last_revision(NAME,NAME);
ALTER EXTENSION table_version ADD FUNCTION @extschema@.ver_get_versioned_table_key(NAME,NAME);
ALTER EXTENSION table_version ADD FUNCTION @extschema@.ver_get_versioned_tables();
ALTER EXTENSION table_version ADD FUNCTION @extschema@.ver_get_version_table_full(NAME,NAME);
ALTER EXTENSION table_version ADD FUNCTION @extschema@.ver_get_version_table(NAME,NAME);
ALTER EXTENSION table_version ADD FUNCTION @extschema@._ver_get_version_trigger(NAME,NAME);
ALTER EXTENSION table_version ADD FUNCTION @extschema@.ver_is_table_versioned(NAME,NAME);
ALTER EXTENSION table_version ADD FUNCTION @extschema@.ver_versioned_table_add_column(NAME,NAME,NAME,TEXT);
ALTER EXTENSION table_version ADD FUNCTION @extschema@.ver_versioned_table_change_column_type(NAME,NAME,NAME,TEXT);

