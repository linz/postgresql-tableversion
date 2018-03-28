-- {
CREATE OR REPLACE FUNCTION ver_disable_versioning(
    p_table_oid       REGCLASS
) 
RETURNS BOOLEAN AS
$$
DECLARE
    v_schema NAME;
    v_table  NAME;
    v_owner  NAME;
BEGIN

    SELECT
      n.nspname, c.relname, r.rolname
    INTO
      v_schema, v_table, v_owner
    FROM
      pg_namespace n, pg_class c, pg_roles r
    WHERE
      c.oid = p_table_oid
    AND
      r.oid = c.relowner
    AND
      n.oid = c.relnamespace;

    -- Check that SESSION_USER is the owner of the table, or
    -- refuse to enable versioning on this table
    IF NOT pg_has_role(session_user, v_owner, 'usage') THEN
        RAISE EXCEPTION 'User % cannot disable versioning on table %'
            ' for lack of usage privileges on table owner role %',
            session_user, p_table_oid, v_owner;
    END IF;

    IF NOT (SELECT @extschema@.ver_is_table_versioned(v_schema, v_table)) THEN
        RAISE EXCEPTION 'Table %.% is not versioned', quote_ident(v_schema), quote_ident(v_table);
    END IF;
    
    UPDATE @extschema@.versioned_tables
    SET    versioned = FALSE
    WHERE  schema_name = v_schema
    AND    table_name = v_table;

    EXECUTE 'DROP TRIGGER IF EXISTS '  || @extschema@._ver_get_version_trigger(v_schema, v_table) || ' ON ' ||  
        quote_ident(v_schema) || '.' || quote_ident(v_table);
    EXECUTE 'DROP FUNCTION IF EXISTS ' || @extschema@.ver_get_version_table_full(v_schema, v_table) || '()';
    EXECUTE 'DROP FUNCTION IF EXISTS ' || @extschema@._ver_get_diff_function(v_schema, v_table);
    EXECUTE 'DROP FUNCTION IF EXISTS ' || @extschema@._ver_get_revision_function(v_schema, v_table);
    EXECUTE 'DROP TABLE IF EXISTS '    || @extschema@.ver_get_version_table_full(v_schema, v_table) || ' CASCADE';    

    EXECUTE 'WITH deleted AS ('
            ' DELETE FROM table_version.versioned_tables'
            ' WHERE schema_name=$1'
            ' AND table_name=$2 RETURNING id'
            ') DELETE FROM table_version.tables_changed'
            '  WHERE table_id in ( select * from deleted )'
    USING v_schema, v_table;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
--}

CREATE OR REPLACE FUNCTION ver_disable_versioning(p_schema NAME, p_table  NAME)
RETURNS BOOLEAN AS $$
  SELECT @extschema@.ver_disable_versioning(( p_schema || '.' || p_table)::regclass);
$$ LANGUAGE sql;
