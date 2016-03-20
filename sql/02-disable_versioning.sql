
CREATE OR REPLACE FUNCTION ver_disable_versioning(
    p_schema NAME, 
    p_table  NAME
) 
RETURNS BOOLEAN AS
$$
BEGIN
    IF NOT (SELECT @extschema@.ver_is_table_versioned(p_schema, p_table)) THEN
        RAISE EXCEPTION 'Table %.% is not versioned', quote_ident(p_schema), quote_ident(p_table);
    END IF;
    
    UPDATE @extschema@.versioned_tables
    SET    versioned = FALSE
    WHERE  schema_name = p_schema
    AND    table_name = p_table;

    EXECUTE 'DROP TRIGGER IF EXISTS '  || @extschema@._ver_get_version_trigger(p_schema, p_table) || ' ON ' ||  
        quote_ident(p_schema) || '.' || quote_ident(p_table);
    EXECUTE 'DROP FUNCTION IF EXISTS ' || @extschema@.ver_get_version_table_full(p_schema, p_table) || '()';
    EXECUTE 'DROP FUNCTION IF EXISTS ' || @extschema@._ver_get_diff_function(p_schema, p_table);
    EXECUTE 'DROP FUNCTION IF EXISTS ' || @extschema@._ver_get_revision_function(p_schema, p_table);
    EXECUTE 'DROP TABLE IF EXISTS '    || @extschema@.ver_get_version_table_full(p_schema, p_table) || ' CASCADE';    
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

