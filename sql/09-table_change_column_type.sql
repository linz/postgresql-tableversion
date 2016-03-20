
CREATE OR REPLACE FUNCTION ver_versioned_table_change_column_type(p_schema_name name, p_table_name name, p_column_name name, p_column_datatype text)
  RETURNS boolean AS
$$
DECLARE
    v_key_col NAME;
    v_trigger_name TEXT;
    v_revision_table TEXT;
BEGIN
    IF NOT @extschema@.ver_is_table_versioned(p_schema_name, p_table_name) THEN
        RAISE EXCEPTION 'Table %.% is not versioned', quote_ident(p_schema_name), quote_ident(p_table_name);
    END IF;
    
    v_revision_table := @extschema@.ver_get_version_table_full(p_schema_name, p_table_name);
    v_trigger_name := @extschema@._ver_get_version_trigger(p_schema_name, p_table_name);
    
    EXECUTE 'ALTER TABLE ' || quote_ident(p_schema_name) || '.' ||
        quote_ident(p_table_name) || ' DISABLE TRIGGER ' || v_trigger_name;
    EXECUTE 'ALTER TABLE ' || quote_ident(p_schema_name) || '.' ||
        quote_ident(p_table_name) || ' ALTER COLUMN ' || quote_ident(p_column_name) ||
        ' TYPE ' || p_column_datatype;
    EXECUTE 'ALTER TABLE ' || v_revision_table      || ' ALTER COLUMN ' ||
        quote_ident(p_column_name) || ' TYPE ' || p_column_datatype;
    EXECUTE 'ALTER TABLE ' || quote_ident(p_schema_name) || '.' ||
        quote_ident(p_table_name) || ' ENABLE TRIGGER ' || v_trigger_name;
    
    SELECT
        key_column
    INTO
        v_key_col
    FROM 
        @extschema@.versioned_tables
    WHERE
        schema_name = p_schema_name AND
        table_name = p_table_name;
    
    PERFORM @extschema@.ver_create_table_functions(p_schema_name, p_table_name, v_key_col);
    PERFORM @extschema@.ver_create_version_trigger(p_schema_name, p_table_name, v_key_col);
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

