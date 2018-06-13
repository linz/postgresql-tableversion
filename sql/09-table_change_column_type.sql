
-- {
CREATE OR REPLACE FUNCTION ver_versioned_table_change_column_type(
    p_table_oid   REGCLASS,
    p_column_name NAME,
    p_column_datatype TEXT
)
RETURNS boolean AS
$$
DECLARE
    v_key_col NAME;
    v_trigger_name TEXT;
    v_revision_table TEXT;
    v_schema          NAME;
    v_table           NAME;
    v_owner           NAME;
BEGIN

    SELECT nspname, relname, rolname
    INTO v_schema, v_table, v_owner
    FROM @extschema@._ver_get_table_info(p_table_oid);

    -- Check that SESSION_USER is the owner of the table, or
    -- refuse to add columns to it
    IF NOT pg_has_role(session_user, v_owner, 'usage') THEN
        RAISE EXCEPTION 'User % cannot change type of columns on table %'
            ' for lack of usage privileges on table owner role %',
            session_user, p_table_oid, v_owner;
    END IF;

    IF NOT @extschema@.ver_is_table_versioned(v_schema, v_table) THEN
        RAISE EXCEPTION 'Table %.% is not versioned', quote_ident(v_schema), quote_ident(v_table);
    END IF;
    
    v_revision_table := @extschema@.ver_get_version_table_full(v_schema, v_table);
    v_trigger_name := @extschema@._ver_get_version_trigger(v_schema, v_table);
    
    EXECUTE 'ALTER TABLE ' || quote_ident(v_schema) || '.' ||
        quote_ident(v_table) || ' DISABLE TRIGGER ' || v_trigger_name;
    EXECUTE 'ALTER TABLE ' || quote_ident(v_schema) || '.' ||
        quote_ident(v_table) || ' ALTER COLUMN ' || quote_ident(p_column_name) ||
        ' TYPE ' || p_column_datatype;
    EXECUTE 'ALTER TABLE ' || v_revision_table      || ' ALTER COLUMN ' ||
        quote_ident(p_column_name) || ' TYPE ' || p_column_datatype;
    EXECUTE 'ALTER TABLE ' || quote_ident(v_schema) || '.' ||
        quote_ident(v_table) || ' ENABLE TRIGGER ' || v_trigger_name;
    
    SELECT
        key_column
    INTO
        v_key_col
    FROM 
        @extschema@.versioned_tables
    WHERE
        schema_name = v_schema AND
        table_name = v_table;
    
    PERFORM @extschema@.ver_create_table_functions(v_schema, v_table, v_key_col);
    PERFORM @extschema@.ver_create_version_trigger(p_table_oid, v_key_col);
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
--}

CREATE OR REPLACE FUNCTION ver_versioned_table_change_column_type(
    p_schema_name NAME,
    p_table_name  NAME,
    p_column_name NAME,
    p_column_datatype TEXT
)
RETURNS boolean AS
$$
    SELECT @extschema@.ver_versioned_table_change_column_type(
        ( p_schema_name || '.' || p_table_name)::regclass,
        p_column_name,
        p_column_datatype
    );
$$ LANGUAGE sql;

